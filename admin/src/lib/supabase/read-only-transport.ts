import { AdminError } from "@/lib/server/errors";
export async function readOnlyFetch(
  input: RequestInfo | URL,
  init?: RequestInit,
): Promise<Response> {
  const method = (
    init?.method ?? (input instanceof Request ? input.method : "GET")
  ).toUpperCase();
  const url = new URL(input instanceof Request ? input.url : String(input));
  if (
    !["GET", "HEAD"].includes(method) ||
    !url.pathname.startsWith("/rest/v1/") ||
    url.pathname.includes("/rpc/")
  )
    throw new AdminError(
      423,
      "WRITES_NOT_READY",
      "현재 관리자 연결은 테이블 조회만 허용합니다.",
    );
  return fetch(input, { ...init, cache: "no-store" });
}
