---
name: plugin-digest
description: >
  Generates a daily HTML digest of the top 10 uninstalled Claude plugins ranked by GitHub stars,
  with one-click install and update support. Use this skill whenever the user wants to discover
  new Claude plugins, browse what's trending, check for plugin updates, or says anything like
  "show me popular Claude skills", "what plugins should I install", or "plugin digest".
  Also runs automatically every morning at 9am after first use.
---

<context>
# Plugin Digest

Fetch the top 10 uninstalled Claude plugins from GitHub by star count, generate an interactive
HTML digest, and open it in the browser.

## What the Page Shows

- **Top 10 Discoveries** — uninstalled plugins, ranked by stars. Top 3 get gold border.
  Click a card to check it, then click "Install Selected" to install automatically.
- **Needs Update** — installed plugins where a newer version is available. One-click Update button.
  Hidden entirely if no updates are available.
</context>

<task>
## Step 1 — Run the script

Find the absolute path to this SKILL.md file's directory (`<skill-dir>`), then run:

```
python "<skill-dir>/scripts/fetch_and_generate.py"
```

Flags:
- No flags: fetch fresh from GitHub + open browser
- `--cached`: skip GitHub fetch, use cached results (offline/fast)

## Step 2 — Register the daily routine (first run only)

After running the script, check if a daily digest routine is already registered:

```
CronList
```

If no job with the prompt containing `plugin-digest` exists, register one:

```
CronCreate
  cron: "3 9 * * *"        ← 9:03am daily (off the :00 mark)
  prompt: "Run /kraken:plugin-digest"
  durable: true             ← persists across Claude restarts
  recurring: true
```

Only register once — if it's already in CronList, skip this step.

**Note:** Claude routines auto-expire after 7 days. The routine will re-register itself
on the next manual `/kraken:plugin-digest` run after expiry.
</task>

<constraints>
## Error Handling

- **GitHub rate limit**: shows last cached results with a warning
- **No internet**: uses cached results if available
- **Install fails**: shows inline error message on the card
</constraints>
