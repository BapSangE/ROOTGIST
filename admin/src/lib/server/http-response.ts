import { randomUUID } from "node:crypto";
import { AdminError } from "./errors";
export const privateHeaders = {
  "Cache-Control": "private, no-store, max-age=0",
  Vary: "Cookie",
  "X-Content-Type-Options": "nosniff",
};
export async function toAdminResponse<T>(
  run: () => Promise<T>,
): Promise<Response> {
  try {
    return Response.json(await run(), { headers: privateHeaders });
  } catch (error) {
    const known = error instanceof AdminError;
    return Response.json(
      {
        error: {
          code: known ? error.code : "DEPENDENCY_UNAVAILABLE",
          message: known ? error.message : "데이터를 불러오지 못했습니다.",
          request_id: randomUUID(),
          retryable: !known || error.status >= 500,
        },
      },
      { status: known ? error.status : 503, headers: privateHeaders },
    );
  }
}
