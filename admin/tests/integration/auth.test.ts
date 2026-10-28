import { describe, it, expect, vi } from "vitest";
import { resolveEnvironment } from "@/lib/server/environment";
import { executeAuthorizedRead } from "@/lib/server/auth-policy";
import { toAdminResponse } from "@/lib/server/http-response";

const base = {
  NODE_ENV: "test",
  ADMIN_DATA_MODE: "supabase",
  SUPABASE_URL: "https://test.supabase.co",
  SUPABASE_PUBLISHABLE_KEY: "test-public",
  ADMIN_USER_ID: "11111111-1111-4111-8111-111111111111",
};

describe("server authorization boundary", () => {
  it.each([
    ["missing session", null, 401],
    [
      "ordinary authenticated user",
      { id: "22222222-2222-4222-8222-222222222222" },
      403,
    ],
  ])("%s cannot read privileged content", async (_, user, status) => {
    const load = vi.fn(async () => ({ internal: "must never be sent" }));
    const response = await toAdminResponse(() =>
      executeAuthorizedRead(resolveEnvironment(base), async () => user, load),
    );
    expect(response.status).toBe(status);
    expect(load).not.toHaveBeenCalled();
    expect(await response.text()).not.toContain("must never");
    expect(response.headers.get("Cache-Control")).toContain("no-store");
  });
  it("a verified admin reaches the read model, with no reusable public cache", async () => {
    const response = await toAdminResponse(() =>
      executeAuthorizedRead(
        resolveEnvironment(base),
        async () => ({ id: base.ADMIN_USER_ID }),
        async (actor) => ({ actor: actor.user_id, rows: [1] }),
      ),
    );
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      actor: base.ADMIN_USER_ID,
      rows: [1],
    });
    expect(response.headers.get("Cache-Control")).toContain("private");
  });
  it("auth provider failure is sanitized and never starts a data read", async () => {
    const load = vi.fn();
    const response = await toAdminResponse(() =>
      executeAuthorizedRead(
        resolveEnvironment(base),
        async () => {
          throw new Error("secret URL and token");
        },
        load,
      ),
    );
    expect(response.status).toBe(503);
    expect(await response.text()).not.toContain("secret");
    expect(load).not.toHaveBeenCalled();
  });
  it.each([
    { NODE_ENV: "production", ADMIN_DATA_MODE: "fixture" },
    { NODE_ENV: "development", ADMIN_DATA_MODE: "fixture", VERCEL: "1" },
    {
      NODE_ENV: "development",
      ADMIN_DATA_MODE: "fixture",
      VERCEL_ENV: "preview",
    },
    { NODE_ENV: "production" },
    { ...base, ADMIN_USER_ID: "" },
  ])(
    "deployment or incomplete config cannot enter fixture mode: %j",
    (source) => {
      expect(() => resolveEnvironment(source)).toThrow();
    },
  );
  it("an explicitly local fixture never consults Supabase", async () => {
    const verify = vi.fn();
    const result = await executeAuthorizedRead(
      resolveEnvironment({ NODE_ENV: "test", ADMIN_DATA_MODE: "fixture" }),
      verify,
      async (actor) => actor.fixture,
    );
    expect(result).toBe(true);
    expect(verify).not.toHaveBeenCalled();
  });
});

it("rejects a malformed UUID and a credential-bearing Supabase URL", () => {
  expect(() =>
    resolveEnvironment({
      ...base,
      ADMIN_USER_ID: "11111111----------------------------",
    }),
  ).toThrow();
  expect(() =>
    resolveEnvironment({
      ...base,
      SUPABASE_URL: "https://name:password@test.supabase.co",
    }),
  ).toThrow();
});
