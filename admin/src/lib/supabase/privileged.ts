import "server-only";
import { createClient } from "@supabase/supabase-js";
import { resolveEnvironment } from "@/lib/server/environment";
import type { AdminIdentity } from "@/lib/server/auth-policy";
import { AdminError } from "@/lib/server/errors";
import { readOnlyFetch } from "./read-only-transport";
export function privilegedReadClient(actor: AdminIdentity) {
  const environment = resolveEnvironment(process.env);
  const key = process.env.SUPABASE_SECRET_KEY?.trim();
  if (
    environment.mode !== "supabase" ||
    actor.fixture ||
    actor.user_id !== environment.adminUserId ||
    !key
  )
    throw new AdminError(
      503,
      "DEPENDENCY_UNAVAILABLE",
      "서버의 관리자 조회 연결 설정이 필요합니다.",
    );
  return createClient(environment.url, key, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
    global: { fetch: readOnlyFetch },
  });
}
