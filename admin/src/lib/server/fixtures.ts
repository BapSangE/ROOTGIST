import data from "./fixture-data.json";
import type { Snapshot } from "@/lib/domain/contracts";
export function fixtureSnapshot(): Snapshot {
  return structuredClone(data) as Snapshot;
}
