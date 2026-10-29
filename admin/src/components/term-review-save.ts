"use client";
import { useRef, useState } from "react";
import type { TermCommandResult, TermTargetState } from "@/lib/domain/contracts";

export type ReviewAction = "apply_patch" | "approve" | "reject" | "needs_changes";
export type SaveTarget = {
  entity_type: "sense" | "candidate" | "paper";
  entity_key: string;
  patch: Record<string, unknown>;
};
export type SaveState =
  | { kind: "idle" }
  | { kind: "saving"; action: ReviewAction }
  | { kind: "saved"; action: ReviewAction; at: string; syncPending: boolean; label: string }
  | { kind: "error"; message: string; conflict: boolean; retryable: boolean };

/** 검수 저장 한 번: DB command 하나(원자적). 같은 내용을 다시 보내면 같은 작업 ID를 써서
 * 응답을 못 받은 저장을 다시 눌러도 두 번 저장되지 않는다(서버 operation_id 멱등성). */
export function useReviewSave() {
  const [state, setState] = useState<SaveState>({ kind: "idle" });
  const pending = useRef<{ body: string; id: string } | null>(null);
  async function save(
    action: ReviewAction,
    target: SaveTarget,
    base: TermTargetState,
    reason: string,
    label: string,
  ): Promise<TermCommandResult | null> {
    const request = {
      action,
      reason,
      targets: [{ ...target, expected_revision: base.revision, base_sha256: base.base_sha256 }],
    };
    const body = JSON.stringify(request);
    if (pending.current?.body !== body) pending.current = { body, id: crypto.randomUUID() };
    setState({ kind: "saving", action });
    try {
      const response = await fetch("/api/admin/v1/term-commands", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ operation_id: pending.current.id, ...request }),
      });
      const json = await response.json().catch(() => ({}));
      if (!response.ok) {
        const conflict = response.status === 409;
        if (conflict) pending.current = null; // 최신 원본으로 다시 만들어야 하니 새 작업 ID로
        setState({
          kind: "error",
          conflict,
          retryable: response.status >= 500,
          message: conflict
            ? "다른 곳에서 먼저 바뀌었어요. 최신 내용을 다시 불러왔으니 확인하고 다시 저장해 주세요."
            : (json.error?.message ?? "저장하지 못했어요."),
        });
        return null;
      }
      pending.current = null;
      const result = json as TermCommandResult;
      setState({ kind: "saved", action, at: result.committed_at, syncPending: result.dictionary_sync_pending, label });
      return result;
    } catch {
      setState({
        kind: "error",
        conflict: false,
        retryable: true,
        message: "저장 결과를 확인하지 못했어요. 다시 누르면 같은 작업으로 한 번만 저장돼요.",
      });
      return null;
    }
  }
  return { state, save, reset: () => setState({ kind: "idle" }) };
}
