# BY OA Playwright Patterns

Reference for BlueYonder Open Access Playwright automation. Read this before writing any script.

---

## Frame Paths by Environment

Both environments host OA Web Forms in a `#LegacyOA` iframe inside a React (catman) wrapper.

| Environment | Playwright frame path |
|---|---|
| Local (`cx-lpt943`) | `page.frameLocator('#LegacyOA')` |
| SaaS (any BY portal) | `page.frameLocator('#mfe').frameLocator('#LegacyOA')` |

Local has no BY portal shell — the React wrapper is the root page.
SaaS adds one layer: the BY portal at `azureedge.net` wraps everything in `#mfe`.

---

## Page Navigation

All OA pages (legacy Web Forms and new React pages) share the same URL pattern:

```
baseUrl + '/' + encodeURIComponent(pageName)
```

`pageName` is the exact `Name` value from `ix_web_page` in the CKB database.
Page names are identical between local and SaaS — only the base URL prefix changes.

Examples:
- Local:  `https://cx-lpt943/ikb/CKB%20Planograms`
- SaaS:   `https://bylumuiportalplpvalna.azureedge.net/cm-oa/ikb/CKB%20Planograms?domain_hint=academy-cval-dev&group=dev03`

For SaaS, insert the encoded page name into the path BEFORE the `?domain_hint=...` query string.

---

## Waiting for Grid Ready

The `#LegacyOA` frame starts near-empty and fills as the React app fetches data.
Wait until element count exceeds 500 before interacting (about 25s cold, faster warm).

```js
async function waitForOaReady(page, isLocal) {
  const frame = isLocal
    ? page.mainFrame().childFrames()[0]
    : page.mainFrame().childFrames()[0]?.childFrames()[0];
  for (let i = 0; i < 30; i++) {
    const count = await frame?.evaluate(() =>
      document.querySelectorAll('*').length
    ).catch(() => 0);
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
```

---

## Row Actions — More Menu Pattern

OA stores row actions as base64 in a hidden div. The "more" button decodes and reveals them.

```js
// Step 1: open the menu
await oaLocator.locator(`tr[versionkey="${dbkey}"] input.extendedbuttonimage`).click();
await page.waitForTimeout(1000);

// Step 2: click the action by its title attribute
await oaLocator.locator(`tr[versionkey="${dbkey}"] span[title="${action}"].commandButton`).click();

// Known action titles: Lock, Unlock, Delete, Edit, Copy
// Actual available actions depend on status and permissions — read from DOM
```

---

## CRITICAL: No `frame.evaluate()` for Actions

OA's ASP.NET `__doPostBack` internally reads `arguments.callee.caller`.
Playwright's `evaluate()` runs in strict mode — this throws:

> `TypeError: 'caller', 'callee', and 'arguments' properties may not be accessed on strict mode functions`

**Rule: always use `frameLocator.locator(...).click()` to trigger OA actions.**
Never call `__doPostBack(...)` directly from `evaluate()`.

---

## Auth — Local (Windows Integrated)

```js
chromium.launchPersistentContext('.edge-profile-local', {
  headless: false, channel: 'msedge', ignoreHTTPSErrors: true,
  viewport: { width: 1280, height: 800 },
  args: ['--auth-server-whitelist=cx-lpt943', '--auth-negotiate-delegate-whitelist=cx-lpt943'],
});
```

---

## Auth — SaaS (B2C → Ping Identity → Academy SSO)

```js
chromium.launchPersistentContext('.edge-profile', {
  headless: false, channel: 'msedge', ignoreHTTPSErrors: true,
  viewport: { width: 1280, height: 800 },
  args: ['--disable-features=SameSiteByDefaultCookies,CookiesWithoutSameSiteMustBeSecure'],
});
```

Cold-session auth chain (cached in `.edge-profile` after first login):
1. Navigate to OA page → `#realm` field appears
2. Fill realm from `env-config.json[env].RealmName` (e.g. `academy-cval-dev`)
3. `await Promise.all([page.waitForEvent('popup', { timeout: 15000 }), page.keyboard.press('Enter')])`
4. Popup: B2C → `sso.connect.pingidentity.com` → `ssodev.academy.com` → SAML callback
5. Click `popup.$('button:has-text("Academy"), a:has-text("Academy")')`
6. `await popup.waitForEvent('close')`

---
