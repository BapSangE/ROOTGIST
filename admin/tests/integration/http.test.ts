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
    expect(data.rows[0].term).toBe("frozen decoder");
    const detail = await fetch(
      `${origin}/api/admin/v1/terms/occurrence/${encodeURIComponent(data.rows[0].id)}`,
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
