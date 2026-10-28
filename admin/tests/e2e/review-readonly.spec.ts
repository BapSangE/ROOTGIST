import { test, expect } from "@playwright/test";
test("six real routes, filters, span simulation, app preview and disabled writes", async ({
  page,
  request,
}) => {
  await page.goto("/admin/terms");
  await expect(
    page.getByRole("heading", { name: "용어 검수 워크벤치" }),
  ).toBeVisible();
  await expect(page.getByText("가상 데이터 · 로컬 검토본")).toBeVisible();
  await expect(
    page.getByRole("heading", { name: "frozen decoder", exact: true }),
  ).toBeVisible();
  const span = page.getByLabel("번역문에서 강조할 표기");
  await expect(span).toHaveValue("고정 디코더");
  await span.fill("동결된 디코더");
  await expect(page.getByTestId("app-preview").locator("mark")).toContainText(
    "동결된 디코더",
  );
  await expect(
    page.getByRole("button", { name: "적용 위치 저장", exact: true }),
  ).toBeDisabled();
  const response = await request.post("/api/admin/v1/commands", {
    data: { action: "approve" },
  });
  expect(response.status()).toBe(423);
  await page.getByLabel("용어 검색").fill("no-such-term");
  await expect(page.getByText("검색 결과가 없어요")).toBeVisible();
  await page.getByLabel("용어 검색").fill("");
  await expect(
    page.getByRole("heading", { name: "frozen decoder", exact: true }),
  ).toBeVisible();
  for (const [path, title] of [
    ["/admin", "대시보드"],
    ["/admin/papers", "논문 검수"],
    ["/admin/news", "공식 AI 소식 검수"],
    ["/admin/notices", "공지사항 관리"],
    ["/admin/operations", "출처 · 운영 상태"],
  ]) {
    await page.goto(path);
    await expect(
      page.getByRole("heading", { name: title, exact: true }),
    ).toBeVisible();
  }
  await expect(
    page.getByText("실행 이력 연동 필요", { exact: true }).first(),
  ).toBeVisible();
});
test("layouts stay within desktop viewport, with keyboard-visible search", async ({
  page,
}) => {
  for (const [width, height] of [
    [1280, 800],
    [1440, 900],
    [1600, 1000],
  ]) {
    await page.setViewportSize({ width, height });
    await page.goto("/admin/terms");
    await expect(page.getByLabel("번역문에서 강조할 표기")).toBeVisible();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
  }
  await page.getByLabel("용어 검색").focus();
  await expect(page.getByLabel("용어 검색")).toBeFocused();
});
test("an explicit item outside current filter stays selected instead of silently switching", async ({
  page,
}) => {
  const id = encodeURIComponent(
    JSON.stringify({ paper_id: "0000.00001", idx: 0 }),
  );
  await page.goto(`/admin/terms?type=occurrence&id=${id}&query=latent`);
  await expect(
    page.getByRole("heading", { name: "frozen decoder", exact: true }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", {
      name: "latent space 잠재 공간 의미 · 검토 대상",
      exact: true,
    }),
  ).toBeVisible();
});
test("generic paper list supports paging and keeps failed state distinct", async ({
  page,
}) => {
  await page.goto("/admin/papers?limit=1");
  await expect(
    page.getByRole("button", { name: "다음 페이지 →", exact: true }),
  ).toBeVisible();
  await page
    .getByRole("button", { name: "다음 페이지 →", exact: true })
    .click();
  await expect(
    page.getByRole("button", { name: "첫 페이지로", exact: true }),
  ).toBeVisible();
  await expect(
    page.getByRole("heading", {
      name: "검색된 정보를 모델의 입력에 더하는 가상 실험",
      exact: true,
    }),
  ).toBeVisible();
  await page.goto("/admin/papers");
  await expect(
    page.getByRole("button", {
      name: "해설 생성에 실패한 가상 논문 0000.00004 · AI 처리 실패",
      exact: true,
    }),
  ).toBeVisible();
});
test("one evidence click keeps the translation panel selected", async ({
  page,
}) => {
  await page.goto("/admin/papers");
  await page.getByRole("button", { name: "근거 A02 ↗", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "문장별 번역", exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByLabel("A02 번역", { exact: true })).toBeVisible();
});
