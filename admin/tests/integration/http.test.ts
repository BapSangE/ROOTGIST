import { it, expect } from "vitest";
const origin = process.env.ADMIN_TEST_URL;
it.skipIf(!origin)(
  "HTTP route returns scoped fixture content and rejects every write verb",
  async () => {
    const response = await fetch(
      `${origin}/api/admin/v1/terms?type=occurrence`,
    );
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toContain("no-store");
    const data = await response.json();
    expect(data.fixture).toBe(true);
    // 같은 개발 서버에서 검수 저장 시험을 먼저 했으면 순서가 바뀐다: 이름으로 찾는다
    const first = data.rows.find((r: { term: string }) => r.term === "frozen decoder");
    expect(first).toBeTruthy();
    const detail = await fetch(
      `${origin}/api/admin/v1/terms/occurrence/${encodeURIComponent(first.id)}`,
    );
    expect((await detail.json()).value.papers[0].id).toBe("0000.00001");
    for (const method of ["POST", "PUT", "PATCH", "DELETE"]) {
      const result = await fetch(`${origin}/api/admin/v1/commands`, {
        method,
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ action: "approve" }),
      });
      expect(result.status).toBe(423);
    }
    expect((await fetch(`${origin}/api/admin/v1/not-a-resource`)).status).toBe(
      404,
    );
  },
);

it.skipIf(!origin)(
  "legacy admin entry pages converge on the focused terms workspace",
  async () => {
    for (const path of [
      "/admin",
      "/admin/papers",
      "/admin/news",
      "/admin/notices",
      "/admin/operations",
    ]) {
      const r = await fetch(`${origin}${path}`, { redirect: "manual" });
      expect(r.status, path).toBe(307);
      expect(r.headers.get("location")).toBe("/admin/terms");
    }
  },
);

it.skipIf(!origin)(
  "term review writes: same-origin JSON only, revision checked, idempotent, list status updated",
  async () => {
    const list = await (await fetch(`${origin}/api/admin/v1/terms?type=occurrence&filter=all`)).json();
    const row = list.rows.find((r: { term: string }) => r.term === "frozen decoder");
    const target = await (await fetch(`${origin}/api/admin/v1/term-target/paper/${row.paper_id}`)).json();
    expect(target.base_sha256).toMatch(/^[0-9a-f]{64}$/);
    const body = (operation_id: string, base = target) => ({
      operation_id,
      action: "apply_patch",
      reason: "",
      targets: [{ entity_type: "paper", entity_key: row.paper_id, expected_revision: base.revision, base_sha256: base.base_sha256,
        patch: { glossary: [{ idx: row.idx, expected_term: row.term, ko_span: "동결된 디코더" }] } }],
    });
    const post = (b: unknown, headers: Record<string, string> = {}) =>
      fetch(`${origin}/api/admin/v1/term-commands`, {
        method: "POST",
        headers: { "content-type": "application/json", origin: origin!, ...headers },
        body: JSON.stringify(b),
      });
    const id = crypto.randomUUID();
    expect((await post(body(id), { origin: "https://evil.example" })).status).toBe(403);
    const first = await post(body(id));
    expect(first.status).toBe(200);
    const saved = await first.json();
    expect(saved.targets[0].revision).toBe(target.revision + 1);
    expect(await (await post(body(id))).json()).toEqual(saved); // 같은 작업 ID는 한 번만
    expect((await post(body(crypto.randomUUID()))).status).toBe(409); // 옛 revision
    const done = await (await fetch(`${origin}/api/admin/v1/terms?type=occurrence&filter=approved`)).json();
    expect(done.rows.some((r: { id: string; status: string }) => r.id === row.id && r.status === "checked")).toBe(true);
    expect((await fetch(`${origin}/api/admin/v1/papers`, { method: "POST", headers: { "content-type": "application/json" }, body: "{}" })).status).toBe(423);
  },
);
