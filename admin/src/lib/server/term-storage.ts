import "server-only";
import {
  isUuid,
  parseTermCommand,
  parseTermDraft,
  termIdentity,
} from "@/lib/domain/term-commands";
import type { AdminIdentity } from "./auth-policy";
import { AdminError } from "./errors";

export type TermReadiness = {
  adminUserId: string;
  schemaVersion: number;
  workerContractVersion: number;
  writesEnabled: boolean;
};
export type TermRpc = (
  name: string,
  args: Record<string, unknown>,
) => Promise<{
  data: unknown;
  error: { code?: string; message?: string } | null;
}>;

/** M4 integration contract only. Existing routes/transports remain read-only.
 * M6 must obtain readiness from the database after M5 worker integration.
 * A browser flag or environment variable is never proof of worker readiness.
 */
export function createTermStorage(
  actor: AdminIdentity,
  readiness: TermReadiness,
  rpc: TermRpc,
) {
  if (
    actor.fixture ||
    !isUuid(actor.user_id) ||
    actor.user_id !== readiness.adminUserId
  )
    throw new AdminError(403, "ADMIN_ONLY", "관리자 계정으로 로그인해 주세요.");
  function writable() {
    if (
      readiness.schemaVersion !== 1 ||
      readiness.workerContractVersion !== 1 ||
      !readiness.writesEnabled
    )
      throw new AdminError(
        423,
        "WRITES_NOT_READY",
        "용어 수정본 보호와 저장 연결을 먼저 완료해야 합니다.",
      );
  }
  async function call(name: string, args: Record<string, unknown>) {
    let response: Awaited<ReturnType<TermRpc>>;
    try {
      response = await rpc(name, args);
    } catch {
      throw new AdminError(
        503,
        "DEPENDENCY_UNAVAILABLE",
        "저장 결과를 확인하지 못했습니다. 같은 작업 ID로 다시 시도해 주세요.",
      );
    }
    if (!response.error) return response.data;
    const status =
      (
        {
          PT403: 403,
          PT404: 404,
          PT409: 409,
          PT422: 422,
          PT423: 423,
        } as Record<string, number>
      )[response.error.code ?? ""] ?? 503;
    const codes = [
      "ADMIN_ONLY",
      "ENTITY_NOT_FOUND",
      "REVISION_CONFLICT",
      "DRAFT_CONFLICT",
      "OPERATION_ID_REUSED",
      "VALIDATION_FAILED",
      "WRITES_NOT_READY",
    ];
    const code = codes.includes(response.error.message ?? "")
      ? response.error.message!
      : status === 409
        ? "REVISION_CONFLICT"
        : status === 422
          ? "VALIDATION_FAILED"
          : status === 423
            ? "WRITES_NOT_READY"
            : "DEPENDENCY_UNAVAILABLE";
    throw new AdminError(
      status,
      code,
      status === 409
        ? "원본이나 초안이 변경됐습니다. 최신 내용을 비교해 주세요."
        : status === 422
          ? "허용 필드와 실제 번역문 적용 위치를 확인해 주세요."
          : "용어 저장 연결 상태를 확인해 주세요.",
    );
  }
  return {
    read: (kind: unknown, key: unknown) =>
      call("admin_read_term_target", termIdentity(kind, key)),
    async execute(input: unknown) {
      writable();
      const { operation_id, ...request } = parseTermCommand(input);
      return call("admin_execute_term_command", {
        actor: actor.user_id,
        operation_id,
        request,
      });
    },
    async saveDraft(input: unknown) {
      writable();
      return call("admin_save_term_draft", {
        actor: actor.user_id,
        ...parseTermDraft(input),
      });
    },
  };
}
