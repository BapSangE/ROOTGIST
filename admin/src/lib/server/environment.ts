import { AdminError } from "./errors";
export type AdminEnvironment =
  | { mode: "fixture" }
  | {
      mode: "supabase";
      url: string;
      publishableKey: string;
      adminUserId: string;
    };
export function resolveEnvironment(
  source: Record<string, string | undefined>,
): AdminEnvironment {
  if (source.ADMIN_DATA_MODE === "fixture") {
    if (
      !["development", "test"].includes(source.NODE_ENV ?? "") ||
      source.VERCEL ||
      source.VERCEL_ENV
    ) {
      throw new AdminError(
        503,
        "DEPENDENCY_UNAVAILABLE",
        "배포 환경에서는 가상 데이터 모드를 사용할 수 없습니다.",
      );
    }
    return { mode: "fixture" };
  }
  const url = source.SUPABASE_URL?.trim();
  const publishableKey = source.SUPABASE_PUBLISHABLE_KEY?.trim();
  const adminUserId = source.ADMIN_USER_ID?.trim();
  if (
    source.ADMIN_DATA_MODE !== "supabase" ||
    !url ||
    !publishableKey ||
    !adminUserId ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      adminUserId,
    )
  ) {
    throw new AdminError(
      503,
      "DEPENDENCY_UNAVAILABLE",
      "관리자 연결 설정이 필요합니다.",
    );
  }
  try {
    const u = new URL(url);
    if (
      u.username ||
      u.password ||
      u.search ||
      u.hash ||
      (u.pathname !== "/" && u.pathname !== "")
    )
      throw new Error();
    if (
      u.protocol !== "https:" &&
      !(
        u.protocol === "http:" &&
        ["localhost", "127.0.0.1"].includes(u.hostname)
      )
    )
      throw new Error();
  } catch {
    throw new AdminError(
      503,
      "DEPENDENCY_UNAVAILABLE",
      "관리자 연결 설정을 확인해 주세요.",
    );
  }
  return { mode: "supabase", url, publishableKey, adminUserId };
}
