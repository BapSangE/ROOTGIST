import "server-only";
import { createClient } from "@supabase/supabase-js";
import { resolveEnvironment } from "@/lib/server/environment";
import type { AdminIdentity } from "@/lib/server/auth-policy";
import { AdminError } from "@/lib/server/errors";
import type { TermRpc } from "@/lib/server/term-storage";

// 용어 검수 저장 전용 연결. 이름을 정한 서버 전용 RPC만 부른다(테이블 쓰기·다른 RPC는 거부).
// 조회 화면은 계속 read-only-transport를 쓴다. 관리자 확인(requireAdmin) 뒤에만 만든다.
const allowed = new Set([
  "admin_read_term_target",
  "admin_execute_term_command",
  "admin_term_storage_status",
  "admin_claim_term_writer",
  "admin_term_review_marks",
  "admin_term_history",
]);
export function termRpcClient(actor: AdminIdentity): TermRpc {
  const environment = resolveEnvironment(process.env);
  const key = process.env.SUPABASE_SECRET_KEY?.trim();
  if (
    environment.mode !== "supabase" ||
    actor.fixture ||
    actor.user_id !== environment.adminUserId ||
    !key
  )
    throw new AdminError(503, "DEPENDENCY_UNAVAILABLE", "서버의 관리자 저장 연결 설정이 필요합니다.");
  const client = createClient(environment.url, key, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { fetch: (input, init) => fetch(input, { ...init, cache: "no-store" }) },
  });
  return async (name, args) => {
    if (!allowed.has(name))
      throw new AdminError(423, "WRITES_NOT_READY", "허용하지 않은 저장 경로입니다.");
    const { data, error } = await client.rpc(name, args);
    return { data, error: error ? { code: error.code, message: error.message } : null };
  };
}
