import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "./tests/e2e",
  fullyParallel: false,
  workers: 1,
  retries: 0,
  use: {
    baseURL: "http://127.0.0.1:3100",
    viewport: { width: 1440, height: 900 },
    headless: true,
    trace: "retain-on-failure",
  },
  webServer: {
    command: "npm run dev:fixture -- --port 3100",
    url: "http://127.0.0.1:3100/admin",
    reuseExistingServer: !process.env.CI,
    timeout: 120000,
  },
});
