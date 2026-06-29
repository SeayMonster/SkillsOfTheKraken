---
name: kraken-cursor-add-marketplace
description: >-
  Registers a GitHub-hosted repo as a Cursor plugin marketplace so the user can browse and
  install plugins from it. Use when the user says "add marketplace", "register this plugin
  marketplace", "add plugins from <GitHub org/repo>", or wants to install a multi-plugin
  Cursor repo like anthropics/skills. Invoke with Use kraken-cursor-add-marketplace.
---

# kraken-cursor: add-marketplace

**Announce at start:** "I'm using kraken-cursor-add-marketplace to register that GitHub repo as a Cursor plugin marketplace."

Registers a GitHub-hosted repository as a **Cursor plugin marketplace** so plugins defined in `.cursor-plugin/marketplace.json` (or the repo root plugin) appear in Cursor's plugin UI.

For single-skill repos without a marketplace manifest, use **kraken-cursor-register-skill-repo** instead.

## Overview

Cursor plugin marketplaces are GitHub repos that expose one or more plugins via `.cursor-plugin/marketplace.json` and per-plugin manifests. After registration, the user installs individual plugins from **Cursor Settings → Plugins**.

Registered marketplaces are cached under `~/.cursor/plugins/marketplaces/github.com/<owner>/<repo>/`.

## Pre-flight

1. Confirm the repo is **public** on GitHub.
2. Verify the repo has `.cursor-plugin/marketplace.json` or `.cursor-plugin/plugin.json` (fetch via GitHub API or raw URL). If neither exists, stop and suggest **kraken-cursor-register-skill-repo** for skills-only install.

## Steps

### Step 1 — Get repo details

Ask the user for:

- **GitHub repo** — full URL, `owner/repo`, or repo name if owner is obvious
- **Marketplace display name** (optional) — suggest PascalCase from the repo name (last segment); confirm before proceeding
- **Plugin to install** (optional) — the `name` field from `.cursor-plugin/marketplace.json` → `plugins[].name`, or from root `plugin.json` for single-plugin repos

If the user doesn't know the plugin name, fetch `.cursor-plugin/marketplace.json` from the repo and list available plugins.

### Step 2 — Register the marketplace in Cursor

**Preferred — Cursor UI (user action):**

Tell the user:

1. Open **Cursor Settings → Plugins** (or **Extensions → Plugins**).
2. Click **Add marketplace** / **Install from GitHub**.
3. Enter `<owner/repo>` (e.g. `anthropics/skills`, `SeayMonster/SkillsOfTheKraken`).
4. Wait for Cursor to clone/cache the marketplace under `~/.cursor/plugins/marketplaces/`.

**Verify registration** — check that this path exists (substitute owner/repo):

```
~/.cursor/plugins/marketplaces/github.com/<owner>/<repo>/
```

If the folder is missing after UI registration, ask the user to retry or restart Cursor.

Do **not** use Claude Code `/plugin marketplace add` — that is Claude-only.

### Step 3 — Install a plugin from the marketplace

After the marketplace is registered, tell the user:

1. In **Cursor Settings → Plugins**, find the newly added marketplace.
2. Select the plugin (e.g. `notion-workspace`, `create-plugin`) and click **Install** / **Enable**.
3. Restart Cursor or start a new Agent chat if skills/MCP do not appear immediately.
4. For MCP-enabled plugins, complete OAuth or config prompts when first using MCP tools.

If the repo is a **single-plugin repo** (only `.cursor-plugin/plugin.json`, no marketplace.json), the user can install directly by entering `<owner/repo>` in **Install from GitHub** without a separate marketplace step.

### Step 4 — Confirm installation

Verify one of:

- Plugin listed under **Cursor Settings → Plugins** as installed/enabled
- Skills from the plugin appear in Agent (invoke by name from frontmatter)
- MCP tools from the plugin appear in the MCP tool list (if applicable)

If installation fails: confirm repo is public, manifest paths are valid, and Cursor is up to date.

### Step 5 — Generate shareable INSTALL.md (optional)

If the user wants teammates to add the same marketplace, generate an `INSTALL.md` with:

1. **Cursor section** — Settings → Plugins → Add marketplace → `<owner/repo>` → install `<plugin-name>`
2. **Skills table** — plugin name, purpose, invoke phrase (`Use <skill-name>`)

Teammate pastes INSTALL.md into Cursor Agent chat; agent runs **kraken-cursor-add-marketplace**.

## Common mistakes

- **Marketplace vs skills repo** — repos with only `skills/*/SKILL.md` and no `.cursor-plugin/` manifest need **kraken-cursor-register-skill-repo**, not this skill.
- **Wrong plugin name** — use `plugins[].name` from `marketplace.json`, not the repo or folder name.
- **Claude commands** — never instruct `/plugin marketplace add` or `/plugin install`; those are Claude Code only.
- **Private repo** — Cursor marketplace install requires a public GitHub repo (or authenticated access the user must configure in Cursor).
- **Already registered** — re-adding is safe; Cursor updates the cached clone.

## Related skills

| Skill | When to use |
|-------|-------------|
| **kraken-cursor-register-skill-repo** | Skills-only repos, `kraken-cursor/install.ps1`, symlink to `~/.cursor/skills/` |
| **kraken-cursor-plugin-digest** | Discover trending uninstalled Cursor plugins on GitHub |
