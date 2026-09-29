---
name: html-to-wpf-dashboard
description: >
  Convert a static, AI-built HTML dashboard (business user hands you a single
  HTML file with data baked into embedded JS) into a WPF app that reads live
  from a real database (CKB, SQL Server, etc), using the WPF+WebView2
  fetch-bridge pattern proven in Hershey's H.-Reports (HersheyDashboard).
  Use this whenever the user has a static HTML report/dashboard (often
  produced by an LLM from a static data export) that now needs to point at
  a live database instead of embedded data, and the delivery target is a
  Windows desktop/Citrix exe rather than a web server.
---

<context>
Business users increasingly hand over dashboards they built themselves with AI:
a single HTML file, all data baked into embedded JS (`const DATA = {...}` or a
sibling `*_data.js` file), maybe some client-side file parsing to regenerate
that data. It looks and behaves like a real app, but it's a snapshot, not a
live view — and it needs to become one, usually as a Citrix-deployed desktop
exe rather than a hosted website (no IIS, no server team, no ops burden).

This skill is the playbook for that conversion, based on the actual pattern
found in `HersheyDashboard` (Hershey H.-Reports repo) — read
`HersheyDashboard/Views/MainWindow.xaml.cs` for the canonical implementation
before starting a new one.

**The trap to avoid:** the instinct is to stand up an ASP.NET Core Web API +
Kestrel and have the HTML `fetch()` it over HTTP. That works, but it's the
wrong default here — it needs a running server process, port management, and
(if genuinely shared across users) a real deployment story. Hershey's actual
production app has **no HTTP server at all**. Confirm this is genuinely a
per-user desktop app (Citrix, one process per session) before reaching for a
web API — if it truly is a shared multi-user backend, that's a different,
legitimate architecture and this skill doesn't apply.
</context>

<task>

## The pattern: WPF + WebView2 fetch-bridge, no HTTP server

1. **WPF hosts a WebView2 control.** The existing static HTML becomes the
   WebView2's content, unmodified at first — get it rendering inside WPF
   before changing anything else.

2. **Serve local files via a virtual host, not `file://`.**
   `webView.CoreWebView2.SetVirtualHostNameToFolderMapping("localreport.host", htmlDir, CoreWebView2HostResourceAccessKind.Allow)`
   then `Navigate("https://localreport.host/dashboard.html")`. This makes
   relative paths and `fetch()` URLs behave like a real site — `file://` breaks
   CORS and relative-path assumptions the HTML almost certainly makes.

3. **Intercept `fetch()` in-page instead of rewriting the dashboard's JS.**
   Inject a JS shim via `AddScriptToExecuteOnDocumentCreatedAsync` (must run
   *before* navigation) that overrides `window.fetch` to instead
   `chrome.webview.postMessage({id, url})` and return a `Promise` that
   resolves when a matching response arrives. The dashboard's own
   `fetch('/api/whatever')` calls then work completely unchanged — you are not
   rewriting the frontend's data-access code, only redirecting where it goes.
   This is the single highest-leverage move in this pattern: minimal HTML
   diff, maximum architectural change underneath it.

4. **First paint without a round trip.** Before `Navigate`, synchronously
   inject the dashboard's initial/summary data as a global
   (`window.__LIVE_SUMMARY__ = {json}`) so first render has data immediately.
   Everything else — drill-downs, filters, tab switches, pagination — goes
   through the bridge from step 3.

5. **`WebMessageReceived` dispatches by URL path.** One handler
   (`OnWebMessageReceived` → `ServeApi(url)` in Hershey's code) pattern-matches
   the intercepted URL/query string and routes to a data-access layer
   (Hershey calls it `CommandFactory` — Dapper over the target DB, one method
   per report/table). Return small payloads via `ExecuteScriptAsync`
   (resolves the JS promise directly); for large ones use
   `PostWebMessageAsJson` instead — **`ExecuteScriptAsync` chokes on big
   payloads.** Hershey's own comment: unfiltered bulk table dumps hit
   12–67MB and broke the bridge. Any table that can grow unbounded (planogram
   lists, product lists, store lists) must be server-side paged
   (`offset`/`limit`/`sort`/`filters` query params) from the start — don't
   ship the naive "return everything" version even temporarily.

6. **Forward console/errors out of the page.** Inject a shim that overrides
   `console.error`/`console.warn` and listens for `window.onerror`/
   `unhandledrejection`, posting them back over the same bridge to your
   logger. Once the HTML is inside WebView2 instead of a browser tab, this is
   your only visibility into page-side JS failures — there's no F12 for the
   end user to open.

7. **File uploads/ingestion, if the HTML has any client-side file
   parsing:** don't try to shuttle file bytes through the JSON bridge
   (same payload-size ceiling as step 5). Instead, have the "select file(s)"
   button send a bridge message that triggers WPF's native
   `OpenFileDialog`/`FolderBrowserDialog`; WPF reads the files directly off
   disk and does whatever parsing/staging/DB-write the original client-side
   JS was doing, in C#.

8. **Connection config**: gitignored `connectionStrings.local.config` (or
   `.json`) with a `.template` committed alongside it, Windows Integrated auth
   where the target DB supports it. Never ship the real per-machine config —
   packaging/deploy scripts must exclude it (see `package-hershey-dashboard`
   skill for the validate-then-zip pattern once this is ready to ship).

## Conversion checklist (in order)

1. Read the existing static HTML: find the embedded data variable(s), any
   client-side file-parsing/upload flow, and every place the UI reads from
   that embedded data (usually one `STATE`/`DATA` object plus render
   functions keyed off it).
2. Identify what real DB tables/columns the embedded data actually
   corresponds to. **Verify column names against the live schema**
   (`INFORMATION_SCHEMA.COLUMNS` or equivalent) — don't guess from memory,
   and don't assume a vendor's generic schema names your custom fields the
   way you'd expect (see: JDA/CKB's `DescN`/`ValueN` override columns, which
   need a data-dictionary lookup, not a naive column read).
3. Scaffold the WPF project + bare WebView2 (`MainWindow` renders the
   unmodified HTML via virtual host mapping — steps 1–2 above). Confirm it
   renders identically to the original before touching data flow.
4. Add the fetch bridge + message dispatcher skeleton (steps 3, 5, 6) with
   no real queries yet — confirm a trivial round trip works
   (e.g. `/api/ping` → `{"ok":true}`).
5. Port the embedded-data structure into real DB queries, one
   table/tab/report at a time, each returning through the bridge at the
   same URL path the HTML already calls. Paginate anything that can be
   large from the first version.
6. If there's an ingestion/upload flow, port it last (step 7) — it's usually
   the most bespoke part and benefits from the read-side plumbing already
   being proven.
7. Confirm every original tab/view still renders and behaves the same,
   now backed by live data — the acceptance bar is "the business user
   can't tell the data source changed," not just "it compiles."

## Reference implementations

- **Canonical:** `Hershey/New Reports/H.-Reports/HersheyDashboard` — read
  `Views/MainWindow.xaml.cs` for the actual bridge/dispatcher code,
  `HelperClasses/CommandFactory.cs` for the Dapper query layer pattern.
- Their `ReportingDashboard` project (`Sdk.Web`/Kestrel) in the same repo is
  **not** production — it's a browser-preview dev harness with seeded mock
  data, useful only for previewing the HTML outside WPF during development.
  Don't mistake it for the real data path.
</task>

<constraints>
| Scenario | Action |
|---|---|
| User's target is genuinely a shared multi-user web app, not per-session desktop | Stop — this skill's no-HTTP-server pattern doesn't apply; that's a real web API project |
| Embedded data variable structure is unclear or undocumented | Read the HTML's render functions to reverse-engineer the shape before touching the DB side |
| Vendor DB uses generic/override column names (DescN, custom fields, etc) | Look up the data dictionary / schema override table for that vendor — don't guess field meaning from column name alone |
| A table/report has no natural page size limit | Paginate it from the first version — don't defer "we'll add paging later" |
| Any file-upload/ingestion flow in the original HTML | Port to native WPF file dialogs + on-disk read, not bytes-over-bridge |
| Tempted to stand up ASP.NET Core + Kestrel as the data layer | Default to the fetch-bridge pattern instead unless multi-user shared hosting is the actual, confirmed requirement |
</constraints>
