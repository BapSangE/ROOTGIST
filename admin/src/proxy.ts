import { NextRequest, NextResponse } from "next/server";
import { createServerClient } from "@supabase/ssr";
import { resolveEnvironment } from "@/lib/server/environment";
export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });
  try {
    const environment = resolveEnvironment(process.env);
    if (environment.mode === "supabase") {
      const client = createServerClient(
        environment.url,
        environment.publishableKey,
        {
          cookies: {
            getAll: () => request.cookies.getAll(),
            setAll: (values) => {
              for (const { name, value } of values)
                request.cookies.set(name, value);
              response = NextResponse.next({ request });
              for (const { name, value, options } of values)
                response.cookies.set(name, value, options);
            },
          },
        },
      );
      await client.auth.getUser();
    }
  } catch {
    /* Page and API guards fail closed with a safe error, not an auth bypass. */
  }
  response.headers.set("Cache-Control", "private, no-store, max-age=0");
  return response;
}
export const config = {
  matcher: ["/admin/:path*", "/api/admin/:path*", "/login"],
};
