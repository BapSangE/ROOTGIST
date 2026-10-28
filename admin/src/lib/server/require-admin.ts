import "server-only";
import { resolveEnvironment } from "./environment";
import { executeAuthorizedRead } from "./auth-policy";
import { sessionClient } from "@/lib/supabase/server";
export async function requireAdmin() {
  const environment = resolveEnvironment(process.env);
  return executeAuthorizedRead(
    environment,
    async () => {
      if (environment.mode !== "supabase") return null;
      const client = await sessionClient(environment);
      const { data, error } = await client.auth.getUser();
      if (error && (!error.status || error.status >= 500)) throw error;
      return data.user ? { id: data.user.id } : null;
    },
    async (actor) => actor,
  );
}
