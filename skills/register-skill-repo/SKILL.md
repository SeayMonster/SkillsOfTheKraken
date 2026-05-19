---
name: register-skill-repo
description: >
  Register a GitHub-hosted Claude Code skill plugin for this developer. Use when the
  user says "add this skill repo", "register this plugin", "install skills from <URL>",
  or pastes a GitHub URL and asks to use the skills in it. Also use when the user wants
  to share their own skill repo with a teammate and needs setup instructions generated.
---

# Register a Skill Repo

## Overview

Claude Code plugins are hosted on GitHub. Registering one requires two steps: add the marketplace entry to `settings.json`, then run `/plugin install <plugin>@<marketplace>` inside Claude Code.

## Workflow

### 1 — Get the repo details

Ask the user for:
- **GitHub repo** — accept any of: full URL (`https://github.com/owner/repo`), `owner/repo`, or just `repo` if owner is obvious from context
- **Plugin name** — the value of `name` in the repo's `.claude-plugin/plugin.json`. If the user doesn't know it, tell them to check that file in the repo. Most repos use a short slug matching the repo or org name.

Suggest a marketplace name derived from the repo name (last segment, PascalCase). Confirm with the user before using it.

### 2 — Register the marketplace

Run this PowerShell, substituting `<MarketplaceName>` and `<owner/repo>`:

```powershell
$settingsPath = "$env:USERPROFILE\.claude\settings.json"

if (Test-Path $settingsPath) {
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
} else {
    $settings = [PSCustomObject]@{}
}

if (-not $settings.PSObject.Properties["extraKnownMarketplaces"]) {
    $settings | Add-Member -MemberType NoteProperty -Name "extraKnownMarketplaces" -Value ([PSCustomObject]@{})
}

$marketplaceName = "<MarketplaceName>"
if (-not $settings.extraKnownMarketplaces.PSObject.Properties[$marketplaceName]) {
    $entry = [PSCustomObject]@{
        source = [PSCustomObject]@{
            source = "github"
            repo   = "<owner/repo>"
        }
    }
    $settings.extraKnownMarketplaces | Add-Member -MemberType NoteProperty -Name $marketplaceName -Value $entry
    $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding utf8
    Write-Host "Registered $marketplaceName marketplace." -ForegroundColor Green
} else {
    Write-Host "$marketplaceName already registered." -ForegroundColor Yellow
}
```

### 3 — Complete installation

Tell the user:

1. In Claude Code, run: `/plugin install <plugin-name>@<MarketplaceName>`
2. Restart Claude Code (full window reload — skills only load at startup).
3. Confirm with `/skills` — the new skills should appear.

If skills don't appear after restart: `/plugin update <plugin-name>@<MarketplaceName>`

### 4 — Generate a shareable INSTALL.md (optional)

If the user wants to share the repo with a teammate, offer to generate an `INSTALL.md` for their repo. Use the same structure as `SkillsOfTheKraken/INSTALL.md`: Claude instructions up top, then a skills table at the bottom. The teammate pastes it into Claude Code chat and Claude handles the registration automatically.

## Common Mistakes

- **Wrong plugin name** — the `name` field in `.claude-plugin/plugin.json`, not the repo name. They often match but not always.
- **Forgetting to restart** — `/plugin install` only takes effect after a full Claude Code window reload.
- **Already registered** — the script checks and skips safely; no double entries.
- **Private repo** — Claude Code's plugin system only works with public GitHub repos. Warn the user if the repo is private.
