import { beforeEach, afterEach, expect, it, vi } from "vitest";
const auth = vi.hoisted(() => ({
  signInWithPassword: vi.fn(),
  getUser: vi.fn(),
  signOut: vi.fn(),
}));
vi.mock("@/lib/supabase/server", () => ({
  sessionClient: async () => ({ auth }),
}));
vi.mock("next/navigation", () => ({
  redirect: (url: string) => {
    throw new Error(`redirect:${url}`);
  },
}));
import { login } from "@/lib/server/login-actions";
const admin = "11111111-1111-4111-8111-111111111111";
beforeEach(() => {
  vi.resetAllMocks();
  for (const [key, value] of Object.entries({
    ADMIN_DATA_MODE: "supabase",
    SUPABASE_URL: "https://test.supabase.co",
    SUPABASE_PUBLISHABLE_KEY: "test-public",
    ADMIN_USER_ID: admin,
  }))
    vi.stubEnv(key, value);
});
afterEach(() => vi.unstubAllEnvs());
const credentials = () => {
  const form = new FormData();
  form.set("email", "admin@example.com");
  form.set("password", "fixture-password");
  return form;
};
it("uses the server-authenticated sign-in result without a second user lookup", async () => {
  auth.signInWithPassword.mockResolvedValue({
    data: { user: { id: admin } },
    error: null,
  });
  auth.getUser.mockRejectedValue(
    new Error("unnecessary extra network request"),
  );
  await expect(login(credentials())).rejects.toThrow("redirect:/admin");
  expect(auth.getUser).not.toHaveBeenCalled();
});
it("signs out a successful sign-in by a non-admin", async () => {
  auth.signInWithPassword.mockResolvedValue({
    data: { user: { id: "other" } },
    error: null,
  });
  auth.getUser.mockResolvedValue({ data: { user: { id: "other" } } });
  await expect(login(credentials())).rejects.toThrow(
    "redirect:/login?error=admin",
  );
  expect(auth.signOut).toHaveBeenCalledOnce();
});
it("does not accept an unsuccessful password sign-in", async () => {
  auth.signInWithPassword.mockResolvedValue({
    data: { user: null },
    error: { message: "invalid credentials" },
  });
  await expect(login(credentials())).rejects.toThrow(
    "redirect:/login?error=credentials",
  );
});
