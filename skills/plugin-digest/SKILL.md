---
name: plugin-digest
description: >
  Generates a daily HTML digest of the top 10 uninstalled Claude plugins ranked by GitHub stars,
  with one-click install and update support. Use this skill whenever the user wants to discover
  new Claude plugins, browse what's trending, check for plugin updates, or says anything like
  "show me popular Claude skills", "what plugins should I install", or "plugin digest".
  Also runs automatically every morning at 9am after first use.
---

# Plugin Digest

Fetch the top 10 uninstalled Claude plugins from GitHub by star count, generate an interactive
HTML digest, and open it in the browser.

## How to Run

The skill runs a bundled Python script. Find the absolute path to this skill's directory, then run:

```
python "<skill-dir>/scripts/fetch_and_generate.py"
```

To find `<skill-dir>`: it's the directory containing this SKILL.md file.

## Flags

- No flags: fetch fresh from GitHub + open browser
- `--cached`: skip GitHub fetch, use last cached results (faster, for offline use)

## What the Page Shows

- **Top 10 Discoveries** — uninstalled plugins, ranked by stars. Top 3 get gold border.
  Click a card to check it, then click "Install Selected" to install automatically.
- **Needs Update** — installed plugins where a newer version is available. One-click Update button.
  Hidden entirely if no updates are available.

## Schedule

On first run, registers a Windows Task Scheduler job (`ClaudePluginDigest`) to run daily at 9am.
The schedule only registers once — re-running the skill won't duplicate it.

## Error Handling

- **GitHub rate limit**: shows last cached results with a warning
- **No internet**: uses cached results if available
- **Install fails**: shows inline error message on the card
