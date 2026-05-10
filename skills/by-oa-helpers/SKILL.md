---
name: by-oa-helpers
description: Scaffold oa-helpers.js and auth.js for a BlueYonder OA UAT Playwright framework. Invoke when building a UAT test framework for a BY OA client, when an Excel UAT sheet is in context, or when the user asks to implement oa-helpers or auth.js. Generates correct frame paths, selectors, and environment wiring without needing to rediscover the OA DOM. Always read references/oa-patterns.md before writing any code.
---

# BY OA Helpers Scaffolding

Generate the Playwright helper files for a BlueYonder OA UAT framework.

## Step 1 — Read the patterns reference

Read `references/oa-patterns.md` before writing any code.

## Files to Generate

Generate these files in the UAT framework directory (e.g. `POGSplit/UAT/runner/`):

### auth.js

```js
import { chromium } from 'playwright';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export async function launchBrowser() {
  const env = process.env.OA_ENV || 'local';
  if (env === 'saas') {
    return chromium.launchPersistentContext(
      path.resolve(__dirname, '../../../playwright-scratch/.edge-profile'),
      {
        headless: false, channel: 'msedge', ignoreHTTPSErrors: true,
        viewport: { width: 1280, height: 800 },
        args: ['--disable-features=SameSiteByDefaultCookies,CookiesWithoutSameSiteMustBeSecure'],
      }
    );
  }
  return chromium.launchPersistentContext(
    path.resolve(__dirname, '../../../playwright-scratch/.edge-profile-local'),
    {
      headless: false, channel: 'msedge', ignoreHTTPSErrors: true,
      viewport: { width: 1280, height: 800 },
      args: [
        '--auth-server-whitelist=cx-lpt943',
        '--auth-negotiate-delegate-whitelist=cx-lpt943',
      ],
    }
  );
}

export function getOaLocator(page) {
  if ((process.env.OA_ENV || 'local') === 'saas') {
    return page.frameLocator('#mfe').frameLocator('#LegacyOA');
  }
  return page.frameLocator('#LegacyOA');
}

export async function waitForOaReady(page) {
  const env = process.env.OA_ENV || 'local';
  const frame = env === 'saas'
    ? page.mainFrame().childFrames()[0]?.childFrames()[0]
    : page.mainFrame().childFrames()[0];
  for (let i = 0; i < 30; i++) {
    const count = await frame?.evaluate(() => document.querySelectorAll('*').length).catch(() => 0);
    if (count > 500) return;
    await page.waitForTimeout(1000);
  }
  throw new Error('OA grid did not render within 30s');
}
```

### oa-helpers.js — 8 UAT verbs

Each function takes `(page, oaLocator, ...args)`. Use `await test.step(...)` at the call site in generated specs so step titles appear in Playwright JSON output for the results dashboard.

```js
import { expect } from '@playwright/test';

export async function navigate(page, oaLocator, pageName) {
  const baseUrl = process.env.OA_BASE_URL || 'https://cx-lpt943/ikb';
  await page.goto(`${baseUrl}/${encodeURIComponent(pageName)}`, { waitUntil: 'load', timeout: 30000 });
}

export async function click(page, oaLocator, label) {
  await oaLocator.locator(`text="${label}"`).click();
}

export async function fill(page, oaLocator, field, value) {
  await oaLocator.locator(
    `[aria-label="${field}"], label:has-text("${field}") + input, label:has-text("${field}") + textarea`
  ).fill(value);
}

export async function selectPlanogram(page, oaLocator, dbkey) {
  await oaLocator.locator(`tr[versionkey="${dbkey}"] input.rowCheckBox`).click();
}

export async function selectRow(page, oaLocator, identifier) {
  // NOTE: selector needs live DOM inspection with stores loaded
  // Best guess based on OA patterns — adjust on first run
  await oaLocator.locator(`tr[storekey="${identifier}"] input.rowCheckBox, tr[dbkey="${identifier}"] input.rowCheckBox`).click();
}

export async function moveStores(page, oaLocator) {
  // NOTE: toolbar action selector needs live DOM inspection with stores loaded
  await oaLocator.locator('[title="Move Stores"], button:has-text("Move"), span[title="Move"]').first().click();
}

export async function promote(page, oaLocator) {
  // NOTE: toolbar action selector needs live DOM inspection
  await oaLocator.locator('[title="Promote"], button:has-text("Promote"), span[title="Promote"]').first().click();
}

export async function check(page, oaLocator, target, expectedValue) {
  if (expectedValue) {
    await expect(oaLocator.locator(`text="${expectedValue}"`).first()).toBeVisible({ timeout: 10000 });
  } else {
    await expect(oaLocator.locator(`[aria-label="${target}"], :has-text("${target}")`).first()).toBeVisible({ timeout: 10000 });
  }
}
```

### playwright.config.js

Place in the UAT root (e.g. `POGSplit/UAT/playwright.config.js`):

```js
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './generated',
  timeout: 120_000,
  use: {
    ignoreHTTPSErrors: true,
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  reporter: [
    ['html'],
    ['json', { outputFile: 'playwright-report/results.json' }],
  ],
});
```

## Generated Spec Pattern

Each generated spec wraps each UAT step in `test.step()` so step titles appear in Playwright JSON output (used by the results dashboard):

```js
import { test } from '@playwright/test';
import { getOaLocator, waitForOaReady, launchBrowser } from '../runner/auth.js';
import * as oa from '../runner/oa-helpers.js';

test('Happy path: select planogram, move stores, submit', async ({ page }) => {
  await waitForOaReady(page);
  const oaLocator = getOaLocator(page);

  await test.step('navigate: CKB Planograms', () => oa.navigate(page, oaLocator, 'CKB Planograms'));
  await test.step('select_planogram: 77450', () => oa.selectPlanogram(page, oaLocator, '77450'));
  // ... more steps
});
```

Step title format: `"{verb}: {target}"` or `"{verb}: {target} = {value}"` — the results dashboard parses these.

## Note on Unverified Selectors

`selectRow`, `moveStores`, and `promote` need live DOM inspection with stores loaded.
They are scaffolded with best-guess selectors and a NOTE comment.
Adjust these during the first POGSplit UAT run against a planogram that has stores.
