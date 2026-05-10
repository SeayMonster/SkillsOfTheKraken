# BY OA Playwright Patterns

Reference for BlueYonder Open Access Playwright automation.
Both `by-oa-adhoc` and `by-oa-helpers` read this file.

---

## Frame Paths by Environment

Both environments host OA Web Forms in a `#LegacyOA` iframe inside a React (catman) wrapper.
The difference is the number of portal shells above it.

| Environment | Playwright frame path |
|---|---|
| Local (`cx-lpt943`) | `page.frameLocator('#LegacyOA')` |
| SaaS (any BY portal) | `page.frameLocator('#mfe').frameLocator('#LegacyOA')` |

Local has no BY portal shell — the React wrapper is the root page.
SaaS adds one layer: the BY portal at `azureedge.net` wraps everything in `#mfe`.

---

## Waiting for Grid Ready

The `#LegacyOA` frame starts near-empty and fills as the React app fetches data.
Wait until element count exceeds 500 before interacting.

```js
// Get the OA frame object (not a locator) for element-count polling
function getOaFrameObject(page) {
  if (process.env.OA_ENV === 'saas') {
    return page.mainFrame().childFrames()[0]?.childFrames()[0];
  }
  return page.mainFrame().childFrames()[0];
}

async function waitForOaReady(page) {
  const frame = getOaFrameObject(page);
  for (let i = 0; i < 30; i++) {
    const count = await frame?.evaluate(() => document.querySelectorAll('*').length).catch(() => 0);
    if (count > 500) return;
    await page.waitForTimeout(1000);
  }
  throw new Error('OA grid did not render within 30s');
}
```

---

## Row Selectors

```js
// Planogram row by DBKey
`tr[versionkey="${dbkey}"]`

// Row attributes set by OA:
// locked="true|false"    — whether current user has the lock
// versionkey="${dbkey}"  — the planogram DBKey
// compositekey="${dbkey}"
```

---

## Row Actions — More Menu Pattern

OA stores row actions as base64 in a hidden div. The "more" button decodes and reveals them.

```js
const oaLocator = /* see Frame Paths above */;

// Step 1: open the menu
await oaLocator.locator(`tr[versionkey="${dbkey}"] input.extendedbuttonimage`).click();
await page.waitForTimeout(1000);

// Step 2: click the action by its title attribute
await oaLocator.locator(`tr[versionkey="${dbkey}"] span[title="${action}"].commandButton`).click();

// Known action titles: Lock, Unlock, Delete, Edit, Copy
// Actual available actions depend on planogram status and user permissions — read from DOM
```

---

## CRITICAL: No `frame.evaluate()` for Actions

OA's ASP.NET `__doPostBack` internally reads `arguments.callee.caller`.
Playwright's `evaluate()` runs in strict mode — accessing `arguments` on a strict-mode function throws:

> `TypeError: 'caller', 'callee', and 'arguments' properties may not be accessed on strict mode functions`

**Rule: always use `frameLocator.locator(...).click()` to trigger OA actions.**
Never call `__doPostBack(...)` directly from `evaluate()`.

Real browser clicks (via `frameLocator`) bypass the strict mode wrapper entirely.

---

## Auth — Local (Windows Integrated)

```js
chromium.launchPersistentContext('.edge-profile-local', {
  headless: false,
  channel: 'msedge',
  ignoreHTTPSErrors: true,
  viewport: { width: 1280, height: 800 },
  args: [
    '--auth-server-whitelist=cx-lpt943',
    '--auth-negotiate-delegate-whitelist=cx-lpt943',
  ],
});
// No login UI — Windows Integrated Auth handles it automatically
```

---

## Auth — SaaS (B2C → Ping Identity → Academy SSO)

```js
chromium.launchPersistentContext('.edge-profile', {
  headless: false,
  channel: 'msedge',
  ignoreHTTPSErrors: true,
  viewport: { width: 1280, height: 800 },
  args: ['--disable-features=SameSiteByDefaultCookies,CookiesWithoutSameSiteMustBeSecure'],
});
```

Auth chain (only needed when session is cold):
1. Navigate to OA page → `#realm` field appears
2. Fill realm from `env-config.json["Dev"].RealmName` (e.g. `academy-cval-dev`)
3. `await Promise.all([page.waitForEvent('popup', { timeout: 15000 }), page.keyboard.press('Enter')])`
4. Popup navigates: B2C → `sso.connect.pingidentity.com` → `ssodev.academy.com` → SAML callback
5. Find and click the IDP button: `popup.$('button:has-text("Academy"), a:has-text("Academy")')`
6. Wait for `popup.isClosed()` — user completes Academy sign-in (cached after first time)

The `.edge-profile` folder caches the session. Subsequent runs are silent (no popup).

---

## Environment Resolution

Read `Environment Details/env-config.json` when the user specifies a SaaS environment.

| User says | Environment | Config source |
|---|---|---|
| (nothing / "local") | Local — `cx-lpt943/ikb` | Hardcoded default |
| "on Dev" | SaaS Dev | `env-config.json["Dev"].OpenAccessUrl` + `RealmName` |
| "on Test" | SaaS Test | `env-config.json["Test"].OpenAccessUrl` + `RealmName` |
