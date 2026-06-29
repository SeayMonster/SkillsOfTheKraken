---
name: kraken-cursor-by-oa-adhoc
description: >-
  Executes a BlueYonder Open Access operation on demand via Playwright. Use when
  the user gives a direct OA command — "lock DBKey X", "unlock DBKey 5 on Dev",
  "navigate to CKB Planograms", "delete DBKey 77450 on Test". Default environment
  is resolved from playwright-run.json, then OA_ENV env var, then local. Always
  read references/oa-patterns.md before writing any script.
---

# kraken-cursor: by-oa-adhoc

**Announce at start:** "I'm using kraken-cursor-by-oa-adhoc to run the Open Access operation."

Execute a single BlueYonder Open Access operation end-to-end using Playwright and Edge.

## Pre-flight — Read reference files

Read **both** files before writing any code:

1. `{SKILL_DIR}/references/oa-patterns.md` — frame paths, selectors, auth args, URL pattern, strict-mode rule
2. `{repoRoot}/playwright-scratch/oa-page-registry.md` (if it exists) — per-page toolbar, more-menu actions, and grid columns discovered by the scanner. Use this to know exactly what actions are available on each page before generating a script. If it doesn't exist, tell the user to run `npm run discover` from `{repoRoot}/UAT/runner/` to build the registry.

## Step 1 — Resolve environment

**Important:** You do NOT need the user to specify the env if the portal has already set it.
"lock planogram DBKey 45" with Dev written in `playwright-run.json` → uses Dev automatically.

Priority:

1. Explicit env in user command ("on Dev", "on Test", "on local") → use that
2. Read `{repoRoot}/playwright-run.json` → use `env` field
3. Default to `local` if neither exists

For SaaS envs: read `{repoRoot}/Environment Details/env-config.json[env]` for `OpenAccessUrl` and `RealmName`.

URL construction for any page (local or SaaS):

```js
// pageName = exact Name from ix_web_page (e.g. 'CKB Planograms', 'PogSplit')
// Local:  https://cx-lpt943/ikb/CKB%20Planograms
// SaaS:   parse OpenAccessUrl → origin+pathname + '/' + encodedName + search
const u    = new URL(openAccessUrl);
const url  = `${u.origin}${u.pathname}/${encodeURIComponent(pageName)}${u.search}`;
```

## Step 2 — Parse the command

Extract from the user's message:

- **operation** — lock, unlock, delete, edit, copy, navigate, or any action title from the more menu
- **dbkey** — planogram DBKey integer (e.g. 77450)
- **environment** — from Step 1 resolution

## Step 3 — Write and run a script

Write a one-off script in `{repoRoot}/playwright-scratch/adhoc-{operation}-{dbkey}.js`.

Use the auth args and frame locator from `{SKILL_DIR}/references/oa-patterns.md` for the target environment.

**Key rules (do not skip):**

1. Navigate to the OA page URL built from the page name (see Step 1)
2. Wait for OA grid ready (poll element count > 500, max 30s) before interacting
3. Use `frameLocator.locator(...).click()` for all actions — never `evaluate(__doPostBack)`
4. Screenshot before and after the operation
5. Verify by reading the row attribute after an 8s postback wait

**Script template:**

```js
const { chromium } = require('playwright');
const path = require('path');

(async () => {
  const DBKEY  = 12345;      // replace
  const ACTION = 'Lock';     // replace
  const PAGE   = 'CKB Planograms'; // replace with exact ix_web_page.Name

  const browser = await chromium.launchPersistentContext(
    path.join(__dirname, '.edge-profile-local'), // .edge-profile for SaaS
    {
      headless: false, channel: 'msedge', ignoreHTTPSErrors: true,
      viewport: { width: 1280, height: 800 },
      args: [
        '--auth-server-whitelist=cx-lpt943',
        '--auth-negotiate-delegate-whitelist=cx-lpt943',
      ],
      // SaaS args: ['--disable-features=SameSiteByDefaultCookies,CookiesWithoutSameSiteMustBeSecure']
    }
  );

  const page = await browser.newPage();
  const BASE  = 'https://cx-lpt943/ikb'; // SaaS: origin+pathname from OpenAccessUrl
  const QS    = '';                        // SaaS: u.search from OpenAccessUrl
  await page.goto(`${BASE}/${encodeURIComponent(PAGE)}${QS}`, { waitUntil: 'load', timeout: 30000 });

  // Wait for grid
  const frame = page.mainFrame().childFrames()[0]; // SaaS: .childFrames()[0]?.childFrames()[0]
  for (let i = 0; i < 30; i++) {
    const n = await frame?.evaluate(() => document.querySelectorAll('*').length).catch(() => 0);
    if (n > 500) break;
    await page.waitForTimeout(1000);
  }

  const oaLocator = page.frameLocator('#LegacyOA'); // SaaS: page.frameLocator('#mfe').frameLocator('#LegacyOA')

  await page.screenshot({ path: path.join(__dirname, 'before.png') });

  // Open more menu
  await oaLocator.locator(`tr[versionkey="${DBKEY}"] input.extendedbuttonimage`).click();
  await page.waitForTimeout(1000);

  // Click action
  await oaLocator.locator(`tr[versionkey="${DBKEY}"] span[title="${ACTION}"].commandButton`).click();
  await page.waitForTimeout(8000);

  const locked = await oaLocator.locator(`tr[versionkey="${DBKEY}"]`).getAttribute('locked');
  console.log(`locked="${locked}"`);

  await page.screenshot({ path: path.join(__dirname, 'after.png') });
  await browser.close();
})();
```

Run via Shell:

```powershell
node "{repoRoot}/playwright-scratch/adhoc-{operation}-{dbkey}.js"
```

For simple navigation-only commands (no row actions), prefer **plugin-playwright-playwright** MCP or **cursor-ide-browser** MCP instead of a custom script.

## Step 4 — Report result

- Show before/after screenshot paths
- Report the verified attribute value (`locked="true"`, etc.)
- **If DBKey not found:** report count of visible `tr[versionkey]` rows
- **If action not in menu:** click more, read `span.commandButton` titles, report what IS available
- **If SaaS auth prompt appears:** handle the realm → popup → Ping Identity flow from `{SKILL_DIR}/references/oa-patterns.md`
