// @ts-check
// Browser smoke for the giacenza miso wasm page (spec issue #1):
// INV-1-CONST  — paste+compute shows the American 2023-01-01,100 table
// INV-1-ERROR-DATE — a bad date shows a visible error, no numbers
// Screenshots land in $EVIDENCE_DIR (default: ./browser-evidence).
//
// Audit finding F-1 binding: APP_WASM_SHA256 must hold the sha256 of
// the freshly built public/app.wasm (exported by
// scripts/browser-smoke.sh). The "wasm artifact binding" test fetches
// /app.wasm through the served page and asserts the bytes hash to it,
// so a foreign or stale server cannot satisfy this suite.
import { test, expect } from "@playwright/test";
import { createHash } from "node:crypto";

const evidence = process.env.EVIDENCE_DIR ?? "browser-evidence";
const appWasmSha256 = process.env.APP_WASM_SHA256 ?? "";

test.describe("giacenza wasm page", () => {
  test("wasm artifact binding: served /app.wasm is the freshly built artifact", async ({
    page,
  }) => {
    expect(
      appWasmSha256,
      "browser smoke requires APP_WASM_SHA256 (exported by scripts/browser-smoke.sh)",
    ).toMatch(/^[0-9a-f]{64}$/);
    await page.goto("/");
    const servedSha = await page.evaluate(async () => {
      const buf = await (await fetch("/app.wasm")).arrayBuffer();
      const digest = await crypto.subtle.digest("SHA-256", buf);
      return Array.from(new Uint8Array(digest))
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
    });
    expect(servedSha).toBe(appWasmSha256);
    const magic = await page.evaluate(async () => {
      const buf = new Uint8Array(await (await fetch("/app.wasm")).arrayBuffer());
      return [buf[0], buf[1], buf[2], buf[3]].join(",");
    });
    expect(magic).toBe("0,97,115,109"); // \\0asm
  });

  test("INV-1-CONST: american CSV 2023-01-01,100 computes saldo 100.00 giacenza 100.00", async ({
    page,
  }) => {
    await page.goto("/");
    await expect(page.locator("textarea.paste")).toBeVisible({ timeout: 120_000 });
    await page.locator("textarea.paste").fill("date,amount\n2023-01-01,100");
    await expect(page.locator("label.column select")).toHaveCount(2);
    await page.locator("button.compute").click();
    const constTable = page.locator("table.results").first();
    await expect(constTable).toBeVisible();
    await expect(constTable.locator("td").nth(0)).toHaveText("2023");
    await expect(constTable.locator("td").nth(1)).toHaveText("100.00");
    await expect(constTable.locator("td").nth(2)).toHaveText("100.00");
    await expect(page.locator(".error")).toHaveCount(0);
    await page.screenshot({ path: `${evidence}/inv1-const.png`, fullPage: true });
  });

  test("INV-1-ERROR-DATE: bad date shows a visible error and no table", async ({
    page,
  }) => {
    await page.goto("/");
    await expect(page.locator("textarea.paste")).toBeVisible({ timeout: 120_000 });
    await page
      .locator("textarea.paste")
      .fill("date,amount\n2023-13-40,100");
    await page.locator("button.compute").click();
    await expect(page.locator(".error")).toBeVisible();
    await expect(page.locator(".error")).toContainText("Invalid date");
    await expect(page.locator(".error")).toContainText("2023-13-40");
    await expect(page.locator("table.results")).toHaveCount(0);
    await page.screenshot({ path: `${evidence}/inv1-error-date.png`, fullPage: true });
  });

  test("INV-1-ERROR-EMPTY: empty paste shows a visible error", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator("textarea.paste")).toBeVisible({ timeout: 120_000 });
    await page.locator("button.compute").click();
    await expect(page.locator(".error")).toBeVisible();
    await expect(page.locator(".error")).toContainText("Empty input");
    await page.screenshot({ path: `${evidence}/inv1-error-empty.png`, fullPage: true });
  });

  test("file upload: choosing a CSV creates a named statement", async ({
    page,
  }) => {
    await page.goto("/");
    await expect(page.locator("textarea.paste")).toBeVisible({
      timeout: 120_000,
    });
    await page.locator("input.csv-file").setInputFiles({
      name: "alpha.csv",
      mimeType: "text/csv",
      buffer: Buffer.from("date,amount\n2023-01-01,100"),
    });
    await expect(page.getByText("alpha.csv")).toBeVisible();
    await page.getByRole("button", { name: "Analyze" }).click();
    const uploadTable = page.locator("table.results").first();
    await expect(uploadTable).toBeVisible();
    await expect(uploadTable.locator("td").nth(0)).toHaveText("2023");
    await expect(uploadTable.locator("td").nth(1)).toHaveText("100.00");
    await expect(uploadTable.locator("td").nth(2)).toHaveText("100.00");
    await page.screenshot({
      path: `${evidence}/file-upload.png`,
      fullPage: true,
    });
  });
});
