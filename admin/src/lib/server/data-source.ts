import "server-only";
import type { AdminIdentity } from "./auth-policy";
import { fixtureSnapshot } from "./fixtures";
import { supabaseSnapshot } from "./supabase-snapshot";
import { termWriter } from "./term-writer";
export async function readSnapshot(actor: AdminIdentity, resource = "all") {
  const snapshot = actor.fixture ? fixtureSnapshot() : await supabaseSnapshot(actor, resource);
  // 용어 화면만 검수 기록을 붙인다. 기록을 못 읽어도 조회는 계속한다(검수 상태만 「미확인」으로 보인다)
  if (resource === "terms")
    snapshot.review = await termWriter(actor)
      .then((w) => w.marks())
      .catch(() => undefined);
  return snapshot;
}
