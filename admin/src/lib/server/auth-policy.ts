import type { AdminEnvironment } from "./environment";
import { AdminError } from "./errors";
export type AdminIdentity = { user_id: string; fixture: boolean };
export type VerifiedUser = { id: string } | null;
export async function executeAuthorizedRead<T>(
  environment: AdminEnvironment,
  verifyUser: () => Promise<VerifiedUser>,
  load: (actor: AdminIdentity) => Promise<T>,
): Promise<T> {
  if (environment.mode === "fixture")
    return load({ user_id: "local-fixture", fixture: true });
  let user: VerifiedUser;
  try {
    user = await verifyUser();
  } catch {
    throw new AdminError(
      503,
      "DEPENDENCY_UNAVAILABLE",
      "로그인 확인에 실패했습니다. 잠시 후 다시 시도해 주세요.",
    );
  }
  if (!user) throw new AdminError(401, "AUTH_REQUIRED", "로그인이 필요합니다.");
  if (user.id !== environment.adminUserId)
    throw new AdminError(403, "ADMIN_ONLY", "관리자 계정으로 로그인해 주세요.");
  return load({ user_id: user.id, fixture: false });
}
