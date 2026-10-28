import "server-only";
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import type { AdminEnvironment } from "@/lib/server/environment";
export async function sessionClient(
  environment: Extract<AdminEnvironment, { mode: "supabase" }>,
) {
  const jar = await cookies();
  return createServerClient(environment.url, environment.publishableKey, {
    cookies: {
      getAll: () => jar.getAll(),
      setAll: (values) => {
        try {
          for (const { name, value, options } of values)
            jar.set(name, value, options);
        } catch {
          /* RSC cookies are refreshed by proxy; actions/handlers can write. */
        }
      },
    },
  });
}
