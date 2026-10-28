import { requireAdmin } from "@/lib/server/require-admin";
import { toAdminResponse } from "@/lib/server/http-response";
import { readSnapshot } from "@/lib/server/data-source";
import { readResource } from "@/lib/server/read-models";
import { AdminError } from "@/lib/server/errors";
export const dynamic = "force-dynamic";
export async function GET(
  request: Request,
  context: { params: Promise<{ segments: string[] }> },
) {
  return toAdminResponse(async () => {
    const actor = await requireAdmin();
    const { segments } = await context.params;
    return readResource(
      await readSnapshot(actor),
      segments,
      new URL(request.url).searchParams,
    );
  });
}
async function blockedWrite() {
  return toAdminResponse(async () => {
    await requireAdmin();
    throw new AdminError(
      423,
      "WRITES_NOT_READY",
      "조회 전용 검토본입니다. 수정본 보호와 저장 연결을 완료한 뒤 사용할 수 있습니다.",
    );
  });
}
export const POST = blockedWrite;
export const PUT = blockedWrite;
export const PATCH = blockedWrite;
export const DELETE = blockedWrite;
