---
name: by-oa-adhoc
description: Execute a BlueYonder Open Access operation on demand. Invoke when the user gives a direct OA command without an Excel or UAT context — "lock DBKey X", "delete DBKey 5 on Dev", "unlock DBKey 77450 on Test", "navigate to CKB Planograms". Default environment is local (cx-lpt943). Specify "on Dev" or "on Test" for SaaS. Triggers on any OA row-level or navigation command. Always read references/oa-patterns.md before proceeding.
---

# BY OA Ad-Hoc Operation

Execute a single BlueYonder Open Access operation end-to-end using Playwright and Edge.

## Step 1 — Read the patterns reference

Read `references/oa-patterns.md` before writing any code. It has frame paths, selectors,
auth args, and the critical strict-mode rule you must not skip.

## Step 2 — Parse the command

Extract from the user's message:
- **operation** — lock, unlock, delete, edit, copy, navigate, or other action title
- **dbkey** — planogram DBKey (integer, e.g. 77450)
- **environment** — default `local` unless user says "on Dev" or "on Test"

## Step 3 — Resolve environment config

For local: base URL is `https://cx-lpt943/ikb`, no realm needed.

For SaaS: read `Environment Details/env-config.json` from the project root:
```js
const config = JSON.parse(fs.readFileSync('Environment Details/env-config.json', 'utf8'));
const env = config['Dev']; // or 'Test'
const baseUrl = env.OpenAccessUrl;
const realm = env.RealmName;
```

## Step 4 — Write and run a script

Write a one-off script in `playwright-scratch/adhoc-{operation}-{dbkey}.js`.

Use the launch args and frame locator from `references/oa-patterns.md` for the target environment.

**Key implementation rules:**
1. Wait 25s after navigation before interacting (React app needs time to load the grid)
2. Use `frameLocator.locator(...).click()` for all actions — never `evaluate(__doPostBack)`
3. Screenshot before and after the operation
4. Verify the result by reading the row's attribute after the postback (wait 8s)

**Template for a row action:**
```js
const { chromium } = require('playwright');
const path = require('path');

(async () => {
  const browser = await chromium.launchPersistentContext(
    path.join(__dirname, '.edge-profile-local'), // or .edge-profile for SaaS
    {
      headless: false, channel: 'msedge', ignoreHTTPSErrors: true,
      viewport: { width: 1280, height: 800 },
      args: [ /* see oa-patterns.md for correct args */ ],
    }
  );
  const page = await browser.newPage();
  await page.goto(BASE_URL, { waitUntil: 'load', timeout: 30000 });
  await page.waitForTimeout(25000); // wait for OA grid to render

  const oaLocator = /* frameLocator chain from oa-patterns.md */;

  // Verify row exists
  const row = await oaLocator.locator(`tr[versionkey="${DBKEY}"]`);

  // Open more menu
  await oaLocator.locator(`tr[versionkey="${DBKEY}"] input.extendedbuttonimage`).click();
  await page.waitForTimeout(1000);

  // Click action
  await oaLocator.locator(`tr[versionkey="${DBKEY}"] span[title="${ACTION}"].commandButton`).click();
  await page.waitForTimeout(8000); // wait for postback

  // Verify
  const locked = await oaLocator.locator(`tr[versionkey="${DBKEY}"]`).getAttribute('locked');
  console.log(`locked="${locked}"`);

  await page.screenshot({ path: path.join(__dirname, `adhoc-after.png`) });
  await browser.close();
})();
```

Run with: `node playwright-scratch/adhoc-{operation}-{dbkey}.js`

## Step 5 — Report result

After the script runs:
- Show the before/after screenshot paths
- Report the verified attribute value or visible text
- If it failed: report what was found (available actions, row state, error message)

## Error Handling

- **DBKey not found**: read `document.querySelectorAll('tr[versionkey]').length` to report visible count
- **Action not in menu**: click more, read `span.commandButton` titles, report what's available
- **Auth required (SaaS)**: handle the realm popup flow per `references/oa-patterns.md` auth section
