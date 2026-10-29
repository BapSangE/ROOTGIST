import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { supabaseSnapshot } from "@/lib/server/supabase-snapshot";
import { GET } from "@/app/api/admin/v1/[...segments]/route";
import { fixtureSnapshot } from "@/lib/server/fixtures";
vi.mock("@/lib/supabase/server", () => ({
  sessionClient: async () => ({
    auth: {
      getUser: async () => ({
        data: { user: { id: "11111111-1111-4111-8111-111111111111" } },
        error: null,
      }),
    },
  }),
}));
import { readResource } from "@/lib/server/read-models";

const actor = {
  user_id: "11111111-1111-4111-8111-111111111111",
  fixture: false,
};
const demo = fixtureSnapshot();
const tables: Record<string, unknown[]> = {
  terms: [
    {
      term_id: demo.senses[0].term_id,
      canonical_en: demo.senses[0].canonical_en,
    },
  ],
  term_senses: [demo.senses[0]],
  term_aliases: [demo.aliases[0]],
  term_candidates: [demo.candidates[0]],
  paper_glossary: [
    { ...demo.papers[0].glossary[0], paper_id: "demo", sentence_ids: ["A01"] },
  ],
  paper_ai: [
    {
      paper_id: "demo",
      title_ko: "가상 논문",
      summary_ko: "가상 요약",
      status: "done",
    },
  ],
  paper_key_points: [
    {
      paper_id: "demo",
      idx: 0,
      claim_ko: "가상 근거",
      evidence_sentence_ids: ["A01"],
    },
  ],
  digest_papers: [
    { digest_date: "2026-01-01", paper_id: "demo", is_exposed: true },
  ],
  trending_models: [{ id: "demo/model", name: "model", card: null }],
  official_news: [{ id: "news-1", source: "demo", title_ko: "가상 소식" }],
  digests: [
    {
      digest_date: "2026-01-01",
      status: "done",
      paper_count: 1,
      last_success_at: null,
    },
  ],
  worker_state: [
    { key: "blocked_urls", value: { urls: ["https://example.com/blocked"] } },
  ],
  app_config: [{ key: "show_ai_reviewed_terms", value: "true" }],
  papers: [
    {
      paper_id: "demo",
      title_en: "Demo",
      abstract_en: "Hello.",
      published_at: "2026-01-01",
      withdrawn: false,
    },
  ],
  paper_sentences: [
    {
      paper_id: "demo",
      sentence_id: "A01",
      start_offset: 0,
      end_offset: 6,
      kind: "text",
    },
  ],
  paper_translations: [
    { paper_id: "demo", sentence_id: "A01", translation_ko: "안녕." },
  ],
};
let requested: string[];
beforeEach(() => {
  requested = [];
  for (const [key, value] of Object.entries({
    ADMIN_DATA_MODE: "supabase",
    SUPABASE_URL: "https://test.supabase.co",
    SUPABASE_PUBLISHABLE_KEY: "test-public",
    SUPABASE_SECRET_KEY: "test-secret",
    ADMIN_USER_ID: actor.user_id,
  }))
    vi.stubEnv(key, value);
  // Keep the real Supabase query builder and read-only transport. Only HTTP is fake.
  vi.stubGlobal(
    "fetch",
    async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = new URL(input instanceof Request ? input.url : String(input));
      expect(init?.method ?? "GET").toBe("GET");
      const table = url.pathname.split("/").at(-1)!;
      requested.push(table);
      const rows = tables[table] ?? [];
      return new Response(JSON.stringify(rows), {
        headers: {
          "content-type": "application/json",
          "content-range": rows.length
            ? `0-${rows.length - 1}/${rows.length}`
            : "*/0",
        },
      });
    },
  );
});
afterEach(() => {
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
});

it.each([
  {
    resource: "models",
    want: ["app_config", "trending_models"],
    id: "demo/model",
  },
  { resource: "news", want: ["app_config", "official_news"], id: "news-1" },
])(
  "$resource lists do not read unrelated paper/term tables",
  async ({ resource, want, id }) => {
    const http = await GET(
      new Request(`https://example.com/api/admin/v1/${resource}`),
      { params: Promise.resolve({ segments: [resource] }) },
    );
    expect(http.status).toBe(200);
    expect(http.headers.get("cache-control")).toContain("no-store");
    const response = (await http.json()) as {
      rows: { id: string }[];
      fixture: boolean;
    };
    expect(response.rows[0].id).toBe(id);
    expect(response.fixture).toBe(false);
    expect(requested.sort()).toEqual(want);
  },
);

it.each([
  { resource: "notices", want: ["app_config"] },
  { resource: "sources", want: ["worker_state"] },
  { resource: "operations", want: ["digests"] },
])("$resource avoids all content-table scans", async ({ resource, want }) => {
  const snapshot = await supabaseSnapshot(actor, resource);
  const response = readResource(
    snapshot,
    resource === "operations" ? [resource, "runs"] : [resource],
    new URLSearchParams(),
  );
  expect(response).toBeTruthy();
  expect(requested.sort()).toEqual(want);
  if (resource === "sources")
    expect(snapshot.blockedUrls).toEqual(["https://example.com/blocked"]);
  if (resource === "operations")
    expect(snapshot.digests[0].paper_count).toBe(1);
});

it.each(["papers", "terms", "dashboard"])(
  "%s retains sentence translation dependencies",
  async (resource) => {
    const snapshot = await supabaseSnapshot(actor, resource);
    expect(snapshot.papers[0].sentences[0]).toMatchObject({
      id: "A01",
      text: "Hello.",
      translation: "안녕.",
    });
    expect(snapshot.showAiReviewedTerms).toBe(true);
    expect(requested).not.toContain("trending_models");
    expect(requested).not.toContain("worker_state");
  },
);

it.each([
  "models",
  "news",
  "notices",
  "sources",
  "operations",
  "papers",
  "terms",
  "dashboard",
])(
  "%s returns the same read model as the complete snapshot",
  async (resource) => {
    const scoped = await supabaseSnapshot(actor, resource);
    const complete = await supabaseSnapshot(actor);
    const paths =
      resource === "operations" ? [[resource, "runs"]] : [[resource]];
    if (resource === "papers") paths.push([resource, "demo"]);
    if (resource === "models") paths.push([resource, "demo/model"]);
    if (resource === "terms")
      paths.push([resource, "sense", demo.senses[0].sense_id]);
    for (const path of paths) {
      const { refreshed_at: scopedTime, ...actual } = readResource(
        scoped,
        path,
        new URLSearchParams(),
      ) as Record<string, unknown>;
      const { refreshed_at: completeTime, ...expected } = readResource(
        complete,
        path,
        new URLSearchParams(),
      ) as Record<string, unknown>;
      expect(scopedTime).toBeTruthy();
      expect(completeTime).toBeTruthy();
      expect(actual).toEqual(expected);
    }
  },
);
