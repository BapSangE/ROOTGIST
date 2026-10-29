import "server-only";
import type { AdminIdentity } from "./auth-policy";
import { fixtureSnapshot } from "./fixtures";
import { supabaseSnapshot } from "./supabase-snapshot";
export async function readSnapshot(actor: AdminIdentity, resource = "all") {
  return actor.fixture ? fixtureSnapshot() : supabaseSnapshot(actor, resource);
}
