# Plugin Digest — Design Spec
**Date:** 2026-05-14  
**Status:** Approved for implementation

---

## Overview

A daily digest page that surfaces the top 10 Claude plugins from GitHub by star count, letting the user check off plugins they want installed with a single click. Runs automatically every morning at 9am and is also available on-demand via `/crisp-dev:plugin-digest`.

---

## Architecture

Three components, all living in `SkillsOfTheKraken/skills/plugin-digest/`:

| Component | Location | Purpose |
|---|---|---|
| Skill | `SKILL.md` | Slash command entry point — invokes script, opens HTML |
| Python script | `scripts/fetch_and_generate.py` | Queries GitHub, builds HTML, saves digest |
| Scheduled task | Registered on first run | Fires skill daily at 9am via `anthropic-skills:schedule` |

---

## Data Flow

1. Search GitHub broadly for Claude plugin/skill repos using topic tags (`claude-plugin`, `claude-skill`, `claude-code-plugin`) and keyword searches
2. Also include all repos from `~/.claude/settings.json` → `extraKnownMarketplaces` so no known plugins are missed
3. Deduplicate across both sources
4. Fetch GitHub star count for each discovered repo
5. Filter out already-installed plugins (check `~/.claude/plugins/installed_plugins.json`)
6. Sort remaining by stars descending, take top 10
7. Check installed plugins for available updates (compare installed version vs latest GitHub tag/release)
8. Generate HTML digest → save to `~/.claude/plugin-digest.html`
9. Open in browser

---

## Page Layout

### Section 1 — Top 10 Discoveries
- Only uninstalled plugins
- Ranked by GitHub stars
- Top 3 get gold border ring + gold rank number
- Each card: rank, plugin name (monospace), star count, marketplace source, description
- Checkboxes to multi-select
- "Install Selected (N)" button at top right
- Clicking a card toggles its checkbox

### Section 2 — Needs Update
- Installed plugins where a newer version is available on GitHub
- Each card shows: plugin name, installed version, latest version
- Individual "Update" button per card (no checkbox, one-click)
- Hidden entirely if no updates available

### Hidden
- Installed plugins that are already up to date do not appear anywhere on the page

### Footer
- Last updated timestamp
- Next refresh time
- `Run /crisp-dev:plugin-digest to refresh now`

---

## Install Mechanism

**If the plugin's repo has an `install.ps1`:**  
Run `irm <raw-github-url>/install.ps1 | iex` via PowerShell.

**If no `install.ps1` exists (generic fallback):**  
1. Register repo in `extraKnownMarketplaces` in `~/.claude/settings.json` and `~/.claude/plugins/known_marketplaces.json`
2. Download repo ZIP, extract to `~/.claude/plugins/marketplaces/<repo-name>/`
3. Copy skills to `~/.claude/plugins/cache/<repo-name>/<plugin-name>/<version>/skills/`
4. Write entry to `~/.claude/plugins/installed_plugins.json`
5. Add to `enabledPlugins` in `settings.json`

This ensures every plugin in the list is installable with one click — no manual steps.

## Update Mechanism

Re-runs the same install script (or generic fallback) for the plugin. Overwrites the existing cache with the latest version — identical to a fresh install.

---

## Schedule Setup

- On first run of `/crisp-dev:plugin-digest`, the skill checks if a schedule already exists
- If not, registers a daily 9am task via `anthropic-skills:schedule`
- Schedule invokes the Python script directly (not via Claude) for reliability
- Re-running the skill never duplicates the schedule

---

## Error Handling

- GitHub API rate limit: script uses unauthenticated requests (60/hr). If rate limited, show cached results with a "rate limited — showing last known results" banner
- No internet: show cached `plugin-digest.html` with stale warning
- Plugin install fails: show inline error on the card, leave checkbox unchecked

---

## File Structure

```
SkillsOfTheKraken/
└── skills/
    └── plugin-digest/
        ├── SKILL.md
        └── scripts/
            └── fetch_and_generate.py
```

Output file: `~/.claude/plugin-digest.html` (overwritten on each run)
