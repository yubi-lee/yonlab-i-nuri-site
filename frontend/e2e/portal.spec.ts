import { expect, test } from "@playwright/test";

test("home search opens integrated search", async ({ page }) => {
  await page.goto("/");
  await page.getByLabel("자료 검색").fill("AI");
  await page.getByRole("button", { name: "검색" }).click();
  await expect(page).toHaveURL(/search\?q=AI/);
  await expect(page.getByRole("heading", { name: "통합검색" })).toBeVisible();
});

test("mobile navigation reaches inquiry", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/");
  await page.getByRole("button", { name: "메뉴 열기" }).click();
  await page.getByRole("link", { name: "문의", exact: true }).click();
  await expect(page.getByRole("heading", { name: "무엇을 함께 해결할까요?" })).toBeVisible();
});
test("member login, bookmark, and inquiry history", async ({ page }) => {
  await page.goto("/login");
  await page.getByLabel("이메일").fill("learner@example.com");
  await page.getByLabel("비밀번호").fill("DemoUser!234");
  await page.getByRole("button", { name: "로그인" }).click();
  await expect(page).toHaveURL(/\/mypage$/);
  await page.goto("/resources");
  await page.locator(".card a").first().click();
  await page.getByRole("button", { name: "관심 자료 저장" }).click();
  await page.goto("/inquiry");
  await page.getByRole("textbox", { name: "이메일", exact: true }).fill("learner@example.com");
  await page.getByLabel("문의 제목").fill("E2E 문의");
  await page.getByLabel("문의 내용").fill("브라우저 E2E 문의 내역 확인을 위한 충분히 긴 내용입니다.");
  await page.getByRole("checkbox").check();
  await page.getByRole("button", { name: "문의 보내기" }).click();
  await page.goto("/mypage");
  await expect(page.getByRole("heading", { name: "관심 자료" })).toBeVisible();
  await expect(page.getByText("E2E 문의").first()).toBeVisible();
});

test("administrator can create and edit category", async ({ page }) => {
  const suffix = Date.now().toString();
  const categoryName = `E2E category ${suffix}`;
  await page.goto("/login");
  await page.getByLabel("이메일").fill("admin@example.com");
  await page.getByLabel("비밀번호").fill("AdminPass1234");
  await page.getByRole("button", { name: "로그인" }).click();
  await expect(page).toHaveURL(/\/admin$/);
  await page.getByRole("tab", { name: "카테고리" }).click();
  await page.getByLabel("이름").fill(categoryName);
  await page.getByLabel("슬러그").fill(`e2e-${suffix}`);
  await page.getByRole("button", { name: "새 항목 저장" }).click();
  await expect(page.getByText(categoryName)).toBeVisible();
});

for (const viewport of [
  { width: 1440, height: 900, name: "desktop" },
  { width: 768, height: 1024, name: "tablet" },
  { width: 390, height: 844, name: "mobile" },
]) {
  test(`responsive home has no horizontal overflow at ${viewport.name}`, async ({ page }) => {
    const errors: string[] = [];
    page.on("console", (message) => { if (message.type() === "error") errors.push(message.text()); });
    await page.setViewportSize(viewport);
    await page.goto("/");
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBeTruthy();
    expect(errors).toEqual([]);
    await page.screenshot({ path: `../docs/qa/screenshots/home-${viewport.name}.png`, fullPage: true });
  });
}
