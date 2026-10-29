import data from "./fixture-data.json";
import type { Snapshot } from "@/lib/domain/contracts";
// 로컬 가상 데이터. 개발 서버에서 검수 저장을 시험할 수 있게 한 프로세스 안에서만 바뀐다(term-writer.ts).
let state: Snapshot | null = null;
export function fixtureState(): Snapshot {
  return (state ??= structuredClone(data) as Snapshot);
}
export function fixtureSnapshot(): Snapshot {
  return structuredClone(fixtureState());
}
export function resetFixtureState() {
  state = null;
}
