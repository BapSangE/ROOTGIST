import { it, expect } from "vitest";
import { fixtureSnapshot } from "@/lib/server/fixtures";
import {
  listTerms,
  termDetail,
  dashboard,
  paginate,
} from "@/lib/server/read-models";
import { readOnlyFetch } from "@/lib/supabase/read-only-transport";

it("puts actual span risks first and keeps observations distinct from unique paper count", () => {
  const snapshot = fixtureSnapshot();
  const page = listTerms(snapshot, new URLSearchParams("type=occurrence"));
  expect(page.rows[0].term).toBe("frozen decoder");
  expect(page.rows[0].risk_labels).toContain("번역문 표기 불일치");
  const candidates = listTerms(snapshot, new URLSearchParams("type=candidate"));
  const row = candidates.rows.find((r) => r.term === "action chunk")!;
  expect(row.seen_count).toBe(8);
  expect(row.paper_count).toBe(1);
});
it("term detail keeps raw span but exposes the actual paper context, no fabricated review revision", () => {
  const snapshot = fixtureSnapshot();
  const row = listTerms(snapshot, new URLSearchParams("type=occurrence"))
    .rows[0];
  const detail = termDetail(snapshot, row.type, row.id);
  expect(detail.revision).toBe(0);
  expect(detail.value.papers[0].sentences[1].id).toBe("A02");
  expect(detail.value.papers[0].glossary[0].ko_span).toBe("고정 디코더");
  expect(Object.values(detail.capabilities).every((c) => !c.enabled)).toBe(
    true,
  );
});
it("zero search results differ from a missing item; invalid cursors are rejected", () => {
  const snapshot = fixtureSnapshot();
  expect(
    listTerms(snapshot, new URLSearchParams("query=does-not-exist")).rows,
  ).toEqual([]);
  expect(() => termDetail(snapshot, "sense", "no-such-id")).toThrow();
  expect(() =>
    paginate([{ id: "a" }], new URLSearchParams("cursor=not-valid")),
  ).toThrow();
});
it("cursor traversal has no duplicates and a filter change cannot reuse another cursor", () => {
  const values = Array.from({ length: 53 }, (_, i) => ({ id: `id-${i}` }));
  const first = paginate(values, new URLSearchParams("query=x"));
  expect(first.rows).toHaveLength(50);
  const second = paginate(
    values,
    new URLSearchParams({ query: "x", cursor: first.next_cursor! }),
  );
  expect(second.rows.map((x) => x.id)).toEqual(["id-50", "id-51", "id-52"]);
  expect(() =>
    paginate(
      values,
      new URLSearchParams({ query: "y", cursor: first.next_cursor! }),
    ),
  ).toThrow();
});
it("dashboard never represents missing run instrumentation as a successful batch", () => {
  const result = dashboard(fixtureSnapshot());
  expect(result.operations.state).toBe("unconnected");
  expect(result.operations.label).toBe("실행 이력 연동 필요");
  expect(result.counts.risks).toBeGreaterThan(0);
});
it("R0 transport rejects writes before they reach any network", async () => {
  await expect(
    readOnlyFetch("https://test.supabase.co/rest/v1/papers", {
      method: "POST",
      body: "{}",
    }),
  ).rejects.toThrow();
  await expect(
    readOnlyFetch("https://test.supabase.co/auth/v1/admin/users", {
      method: "DELETE",
    }),
  ).rejects.toThrow();
});

it("news source facets remain complete even after filtering one source", async () => {
  const { readResource } = await import("@/lib/server/read-models");
  const result = readResource(
    fixtureSnapshot(),
    ["news"],
    new URLSearchParams("source=demo_sdk"),
  ) as {
    rows: { source: string }[];
    source_options: { id: string; label: string }[];
  };
  expect(result.rows.every((r) => r.source === "demo_sdk")).toBe(true);
  expect(result.source_options.map((s) => s.id)).toEqual([
    "demo_lab",
    "demo_sdk",
  ]);
});

it("supports a smaller validated page size without dropping the next cursor", () => {
  const rows = [{ id: "a" }, { id: "b" }, { id: "c" }];
  const page = paginate(rows, new URLSearchParams("limit=1"));
  expect(page.rows.map((r) => r.id)).toEqual(["a"]);
  expect(page.next_cursor).not.toBeNull();
  expect(() => paginate(rows, new URLSearchParams("limit=0"))).toThrow();
});
