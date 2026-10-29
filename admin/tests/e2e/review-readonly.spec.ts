import { test, expect } from "@playwright/test";
test("term-only entry, actual span projection and disabled persistence", async ({
  page,
  request,
}) => {
  await page.goto("/admin");
  await expect(page).toHaveURL(/\/admin\/terms$/);
  await expect(
    page.getByRole("heading", { name: /frozen decoder/ }),
  ).toBeVisible();
  await expect(page.getByText("가상 데이터 · 로컬 검토본")).toBeVisible();
  await expect(
    page.getByRole("link", { name: "논문 검수", exact: true }),
  ).toHaveCount(0);
  const span = page.getByLabel("번역문에서 강조할 표기", { exact: true });
  await span.fill("동결된 디코더");
  await expect(page.getByTestId("app-preview").locator("mark")).toContainText(
    "동결된 디코더",
  );
  await expect(
    page.getByRole("button", { name: "적용 위치 저장", exact: true }),
  ).toBeDisabled();
  await expect(
    page.getByRole("button", { name: "임시 저장", exact: true }),
  ).toBeDisabled();
  expect(
    (
      await request.post("/api/admin/v1/commands", {
        data: { action: "approve" },
      })
    ).status(),
  ).toBe(423);
  await page.getByRole("button", { name: "다음 항목", exact: true }).click();
  await expect(
    page.getByRole("dialog", { name: "변경한 미리보기가 있어요" }),
  ).toBeVisible();
  await page
    .getByRole("button", { name: "미리보기 유지 후 이동", exact: true })
    .click();
  await expect(
    page.getByRole("heading", { name: /policy head/ }),
  ).toBeVisible();
  await page.getByRole("button", { name: /^frozen decoder/ }).click();
  await expect(span).toHaveValue("동결된 디코더");
  await page.getByRole("button", { name: "원래대로", exact: true }).click();
  await page.getByLabel("용어 검색", { exact: true }).fill("no-such-term");
  await expect(page.getByText("검색 결과가 없어요").first()).toBeVisible();
});
test("core tools fit 1280x720, with an accessible dictionary drawer in narrow windows", async ({
  page,
}) => {
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.goto("/admin/terms");
  await expect(page.getByLabel("번역문에서 강조할 표기")).toBeVisible();
  expect(
    await page.evaluate(
      () =>
        document.documentElement.scrollWidth <= innerWidth &&
        document.documentElement.scrollHeight <= innerHeight,
    ),
  ).toBe(true);
  for (const label of ["사전 의미", "앱 표시 예상"])
    await expect(
      page.getByRole("heading", { name: label, exact: true }),
    ).toBeVisible();
  await page.setViewportSize({ width: 752, height: 720 });
  await page.getByRole("button", { name: "사전 의미", exact: true }).click();
  const dialog = page.getByRole("dialog", { name: "사전 의미", exact: true });
  await expect(dialog).toBeVisible();
  await page.keyboard.press("j");
  await expect(dialog).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(
    page.getByRole("button", { name: "사전 의미", exact: true }),
  ).toBeFocused();
  await expect(
    page.getByRole("heading", { name: /frozen decoder/ }),
  ).toBeVisible();
});
test("an explicit item outside the current filter remains selected", async ({
  page,
}) => {
  const id = encodeURIComponent(
    JSON.stringify({ paper_id: "0000.00001", idx: 0 }),
  );
  await page.goto(`/admin/terms?type=occurrence&id=${id}&query=latent`);
  await expect(
    page.getByRole("heading", { name: /frozen decoder/ }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: /^latent space/ }),
  ).toBeVisible();
});
test("sentence navigation keeps the same local span and does not pretend to change the linked IDs", async ({
  page,
}) => {
  await page.goto("/admin/terms");
  const span = page.getByLabel("번역문에서 강조할 표기");
  await span.fill("동결");
  await page.getByLabel("적용 문장", { exact: true }).selectOption("A03");
  await expect(span).toHaveValue("동결");
  await expect(page.getByText("탐색 문장 · 적용 연결 안 됨")).toBeVisible();
});
test("old menu URLs reach terms without restoring unrelated navigation", async ({
  page,
}) => {
  for (const path of [
    "/admin/papers",
    "/admin/news",
    "/admin/notices",
    "/admin/operations",
  ]) {
    await page.goto(path);
    await expect(page).toHaveURL(/\/admin\/terms$/);
  }
  await expect(
    page.getByRole("heading", { name: /frozen decoder/ }),
  ).toBeVisible();
});

test("cancelling a pending search restores the displayed filter to the applied URL", async ({
  page,
}) => {
  await page.goto("/admin/terms");
  await page.getByLabel("번역문에서 강조할 표기").fill("동결");
  await page.getByLabel("용어 검색", { exact: true }).fill("latent");
  await page.getByRole("button", { name: "계속 검토", exact: true }).click();
  await expect(page.getByLabel("용어 검색", { exact: true })).toHaveValue("");
  await expect(page).not.toHaveURL(/query=latent/);
});
