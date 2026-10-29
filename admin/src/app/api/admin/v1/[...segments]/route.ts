import { requireAdmin } from "@/lib/server/require-admin";
import { toAdminResponse } from "@/lib/server/http-response";
import { readSnapshot } from "@/lib/server/data-source";
import { readResource } from "@/lib/server/read-models";
import { AdminError } from "@/lib/server/errors";
import { termWriter } from "@/lib/server/term-writer";
export const dynamic = "force-dynamic";
export async function GET(
  request: Request,
  context: { params: Promise<{ segments: string[] }> },
) {
  return toAdminResponse(async () => {
    const actor = await requireAdmin();
    const { segments } = await context.params;
    // 저장 직전 비교용 원본 상태(DB revision·hash). /term-target/{sense|candidate|paper}/{key}
    if (segments[0] === "term-target") {
      if (segments.length !== 3) throw new AdminError(404, "ENTITY_NOT_FOUND", "항목이 없습니다.");
      return (await termWriter(actor)).read(segments[1], decodeURIComponent(segments[2]));
    }
    return readResource(
      await readSnapshot(actor, segments[0]),
      segments,
      new URL(request.url).searchParams,
    );
  });
}
// 용어 검수 저장: POST /term-commands 하나만 연다. 다른 쓰기는 계속 423.
// 쿠키 인증이라 다른 사이트에서 보낸 요청(CSRF)을 막는다: 같은 출처의 fetch만 받는다.
export async function POST(
  request: Request,
  context: { params: Promise<{ segments: string[] }> },
) {
  return toAdminResponse(async () => {
    const actor = await requireAdmin();
    const { segments } = await context.params;
    if (segments.length !== 1 || segments[0] !== "term-commands") return blocked();
    // 출처 비교는 Host 머리글로(개발 서버·Vercel 모두 request.url의 호스트가 실제 주소와 다를 수 있다)
    const origin = request.headers.get("origin");
    const host = request.headers.get("x-forwarded-host") ?? request.headers.get("host");
    let sameOrigin = origin === null;
    try {
      sameOrigin ||= new URL(origin!).host === host;
    } catch {}
    if (
      request.headers.get("sec-fetch-site") === "cross-site" ||
      !sameOrigin ||
      !request.headers.get("content-type")?.startsWith("application/json")
    )
      throw new AdminError(403, "ADMIN_ONLY", "같은 관리자 화면에서만 저장할 수 있어요.");
    let body: unknown;
    try {
      body = await request.json();
    } catch {
      throw new AdminError(422, "VALIDATION_FAILED", "저장 요청 형식을 확인해 주세요.");
    }
    return (await termWriter(actor)).execute(body);
  });
}
function blocked(): never {
  throw new AdminError(
    423,
    "WRITES_NOT_READY",
    "용어 검수 저장만 열려 있어요. 다른 변경은 지원하지 않습니다.",
  );
}
async function blockedWrite() {
  return toAdminResponse(async () => {
    await requireAdmin();
    return blocked();
  });
}
export const PUT = blockedWrite;
export const PATCH = blockedWrite;
export const DELETE = blockedWrite;
