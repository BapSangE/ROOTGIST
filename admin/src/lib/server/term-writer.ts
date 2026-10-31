import "server-only";
import { createHash } from "node:crypto";
import type {
  Alias,
  ReviewMarks,
  Snapshot,
  TermCommandResult,
  TermTargetState,
} from "@/lib/domain/contracts";
import { parseTermCommand, termIdentity } from "@/lib/domain/term-commands";
import type { AdminIdentity } from "./auth-policy";
import { AdminError } from "./errors";
import { fixtureState } from "./fixtures";
import { createTermStorage } from "./term-storage";
import { termRpcClient } from "@/lib/supabase/term-rpc";

// 용어 검수 저장. 실제 연결은 DB의 원자적 command(admin_execute_term_command, 20261028125014)를 그대로 쓰고,
// 배치 보호는 DB 트리거(20261029150000)가 맡는다. 가상 데이터(로컬 개발)는 같은 규칙을 메모리에서 흉내 낸다.
export type TermWriter = {
  writable: boolean;
  read(kind: unknown, key: unknown): Promise<TermTargetState>;
  execute(input: unknown): Promise<TermCommandResult>;
  marks(): Promise<ReviewMarks>;
};

export async function termWriter(actor: AdminIdentity): Promise<TermWriter> {
  return actor.fixture ? fixtureWriter() : supabaseWriter(actor);
}

async function supabaseWriter(actor: AdminIdentity): Promise<TermWriter> {
  const rpc = termRpcClient(actor);
  // 관리자 UUID는 저장소에 적지 않는다: 서버 환경값으로 처음 한 번 등록(이미 다른 값이면 false → 저장 403)
  const claim = await rpc("admin_claim_term_writer", { actor: actor.user_id });
  const status = await rpc("admin_term_storage_status", {});
  if (claim.error || status.error)
    throw new AdminError(503, "DEPENDENCY_UNAVAILABLE", "용어 저장 연결 상태를 확인하지 못했습니다.");
  const s = status.data as { schema_version: number; worker_contract_version: number; writes_enabled: boolean };
  const readiness = {
    adminUserId: claim.data === true ? actor.user_id : "",
    schemaVersion: s.schema_version,
    workerContractVersion: s.worker_contract_version,
    writesEnabled: s.writes_enabled,
  };
  const writable = readiness.adminUserId !== "" && s.worker_contract_version === 1 && s.writes_enabled;
  const storage = writable ? createTermStorage(actor, readiness, rpc) : null;
  const locked = () => {
    throw new AdminError(423, "WRITES_NOT_READY", "용어 저장 연결 상태를 확인해 주세요.");
  };
  return {
    writable,
    read: async (kind, key) => (storage ? ((await storage.read(kind, key)) as TermTargetState) : locked()),
    execute: async (input) => (storage ? ((await storage.execute(input)) as TermCommandResult) : locked()),
    async marks() {
      const { data, error } = await rpc("admin_term_review_marks", {});
      if (error) return { writable, occurrences: [], controls: [] };
      return { writable, ...(data as Omit<ReviewMarks, "writable">) };
    },
  };
}

// ---- 가상 데이터: 개발 서버 한 프로세스 안에서만 바뀐다(fixture는 production에서 켜지지 않는다) ----
const fixture = {
  revisions: new Map<string, number>(),
  occurrences: [] as ReviewMarks["occurrences"],
  controls: new Map<string, ReviewMarks["controls"][number]>(),
  operations: new Map<string, TermCommandResult>(),
};
const sha = (v: unknown) => createHash("sha256").update(JSON.stringify(v)).digest("hex");
function fixtureSource(s: Snapshot, kind: string, key: string): unknown {
  if (kind === "sense") {
    const sense = s.senses.find((x) => x.sense_id === key);
    return sense && { sense, aliases: s.aliases.filter((a) => a.sense_id === key) };
  }
  if (kind === "candidate") return s.candidates.find((c) => c.normalized_form === key);
  const paper = s.papers.find((p) => p.id === key);
  return paper && { glossary: paper.glossary, sentences: paper.sentences };
}
function fixtureWriter(): TermWriter {
  const fail = (status: number, code: string, message: string): never => {
    throw new AdminError(status, code, message);
  };
  function read(kind: unknown, key: unknown): TermTargetState {
    const id = termIdentity(kind, key);
    const value = fixtureSource(fixtureState(), id.entity_type, id.entity_key);
    if (!value) fail(404, "ENTITY_NOT_FOUND", "항목이 없거나 목록이 변경되었습니다.");
    return { value, revision: fixture.revisions.get(`${id.entity_type}:${id.entity_key}`) ?? 0, base_sha256: sha(value) };
  }
  return {
    writable: true,
    read: async (kind, key) => read(kind, key),
    async execute(input) {
      const command = parseTermCommand(input);
      const done = fixture.operations.get(command.operation_id);
      if (done) return done;
      const s = fixtureState();
      for (const t of command.targets) {
        const state = read(t.entity_type, t.entity_key);
        if (state.revision !== t.expected_revision || state.base_sha256 !== t.base_sha256)
          fail(409, "REVISION_CONFLICT", "원본이나 초안이 변경됐습니다. 최신 내용을 비교해 주세요.");
      }
      const results: TermCommandResult["targets"] = [];
      let pending = false;
      for (const t of command.targets) {
        const patch = t.patch as Record<string, unknown>;
        const status = (current: string) =>
          command.action === "approve" ? "approved" : command.action === "reject" ? "rejected"
            : command.action === "needs_changes" ? "needs_changes" : Object.keys(patch).length ? "pending" : current;
        if (t.entity_type === "sense") {
          const sense = s.senses.find((x) => x.sense_id === t.entity_key)!;
          Object.assign(sense, Object.fromEntries(Object.entries(patch).filter(([k]) => k !== "aliases")));
          // DB apply_patch와 같이: 보낸 별칭 목록이 이 의미의 별칭 전체가 된다
          if (Array.isArray(patch.aliases))
            s.aliases = [
              ...s.aliases.filter((a) => a.sense_id !== sense.sense_id),
              ...(patch.aliases as Omit<Alias, "sense_id">[]).map((a) => ({ ...a, sense_id: sense.sense_id })),
            ];
          const next = status(sense.review_status);
          if (command.action === "approve" && (!sense.canonical_ko || !sense.definition_ko))
            fail(422, "VALIDATION_FAILED", "한국어 표기와 일반 정의를 먼저 채워 주세요.");
          sense.review_status = next === "needs_changes" ? "deferred" : next;
        } else if (t.entity_type === "candidate") {
          const c = s.candidates.find((x) => x.normalized_form === t.entity_key)!;
          Object.assign(c, patch);
          if (command.action === "approve" && !c.canonical_ko)
            fail(422, "VALIDATION_FAILED", "한국어 표기를 먼저 채워 주세요.");
          const next = status(c.review_status);
          c.review_status = next === "needs_changes" ? "pending" : next;
          pending ||= next === "approved";
        } else {
          const paper = s.papers.find((p) => p.id === t.entity_key)!;
          for (const item of (patch.glossary as Record<string, unknown>[]) ?? []) {
            const g = paper.glossary.find((x) => x.idx === item.idx);
            if (!g || g.term !== item.expected_term) fail(409, "REVISION_CONFLICT", "용어 목록이 바뀌었습니다. 다시 불러와 주세요.");
            const span = "ko_span" in item ? (item.ko_span as string | null) : g!.ko_span;
            const texts = paper.sentences.filter((x) => g!.sentence_ids.includes(x.id)).map((x) => x.translation ?? "");
            if (span && !texts.some((x) => x.includes(span)))
              fail(422, "VALIDATION_FAILED", "번역문에 있는 글자만 강조할 수 있어요.");
            if ("ko_span" in item) g!.ko_span = span;
            fixture.occurrences = [
              ...fixture.occurrences.filter((o) => !(o.paper_id === paper.id && o.idx === g!.idx)),
              { paper_id: paper.id, idx: g!.idx, term: g!.term, reviewed_at: new Date().toISOString() },
            ];
          }
        }
        const id = `${t.entity_type}:${t.entity_key}`;
        const revision = (fixture.revisions.get(id) ?? 0) + 1;
        fixture.revisions.set(id, revision);
        fixture.controls.set(id, {
          entity_type: t.entity_type, entity_key: t.entity_key, revision,
          review_state: command.action === "apply_patch" ? "pending" : command.action === "needs_changes" ? "needs_changes" : command.action === "approve" ? "approved" : "rejected",
          note: command.reason || null, updated_at: new Date().toISOString(),
        });
        results.push({ entity_type: t.entity_type, entity_key: t.entity_key, revision, base_sha256: read(t.entity_type, t.entity_key).base_sha256 });
      }
      const result = { operation_id: command.operation_id, committed_at: new Date().toISOString(), targets: results, dictionary_sync_pending: pending };
      fixture.operations.set(command.operation_id, result);
      return result;
    },
    marks: async () => ({ writable: true, occurrences: fixture.occurrences, controls: [...fixture.controls.values()] }),
  };
}

