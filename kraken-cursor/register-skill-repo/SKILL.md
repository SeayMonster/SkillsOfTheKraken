---
name: kraken-cursor-register-skill-repo
description: >-
  Registers a GitHub-hosted skill repo for Cursor. Installs skills to ~/.cursor/skills/ and
  optionally sets up a Cursor plugin at ~/.cursor/plugins/local/. Use when the user says
  "add this skill repo", "register this plugin", "install skills from <URL>", or pastes a
  GitHub URL and asks to use the skills in Cursor. Also use when generating setup instructions
  for a teammate. Invoke with Use kraken-cursor-register-skill-repo.
---

# kraken-cursor: register-skill-repo

**Announce at start:** "I'm using kraken-cursor-register-skill-repo to install skills from that repo."

Registers a GitHub-hosted skill or plugin repo for Cursor. Primary path: symlink (or copy) skill folders into `~/.cursor/skills/`. Optional path: install as a full Cursor plugin under `~/.cursor/plugins/local/`.

## Overview

Cursor skills live in `~/.cursor/skills/<skill-name>/SKILL.md`. Cursor plugins (rules, skills, MCP, hooks bundled) live in `~/.cursor/plugins/local/<plugin-name>/` with a `.cursor-plugin/plugin.json` manifest.

Most GitHub skill repos need only the **skills install**. Use the **plugin install** when the repo has `.cursor-plugin/plugin.json` and the user wants the full plugin bundle (MCP servers, rules, etc.).

## Pre-flight

1. Confirm the repo is **public** on GitHub. Private repos cannot be fetched without credentials.
2. Resolve install mode from repo layout (inspect via GitHub API or raw URLs):
   - `kraken-cursor/install.ps1` or root `install.ps1` → prefer running the installer script
   - `*/SKILL.md` under `skills/`, `kraken-cursor/`, or repo root → skills install
   - `.cursor-plugin/plugin.json` → offer plugin install to `~/.cursor/plugins/local/`

## Steps

### Step 1 — Get repo details

Ask the user for:

- **GitHub repo** — full URL (`https://github.com/owner/repo`), `owner/repo`, or `repo` if owner is obvious
- **Install mode** — `skills` (default), `plugin`, or `both` when the repo supports both
- **Skill name prefix** (optional) — e.g. `kraken-cursor-` to avoid collisions; default to folder names from the repo

If the repo has `.cursor-plugin/plugin.json`, read the `name` field for the plugin folder name (not always the repo name).

### Step 2 — Run installer script (preferred)

If the repo ships `kraken-cursor/install.ps1` or root `install.ps1`, run:

```powershell
irm "https://raw.githubusercontent.com/<owner>/<repo>/main/kraken-cursor/install.ps1" | iex
```

Or for root `install.ps1`:

```powershell
irm "https://raw.githubusercontent.com/<owner>/<repo>/main/install.ps1" | iex
```

Use `main` or `master` depending on the repo's default branch. Skip to Step 4 if the script succeeds.

### Step 3 — Manual skills install

When no installer script exists, run PowerShell (substitute `<owner/repo>`, `<RepoLeaf>`):

```powershell
$repo = "<owner/repo>"
$repoLeaf = "<RepoLeaf>"
$zip = "$env:TEMP\$repoLeaf.zip"
$extract = "$env:TEMP\$repoLeaf-extract"
$skillsRoot = Join-Path $env:USERPROFILE ".cursor\skills"

Invoke-WebRequest "https://github.com/$repo/archive/refs/heads/main.zip" -OutFile $zip
Expand-Archive $zip $extract -Force
$src = Join-Path $extract "$repoLeaf-main"

if (-not (Test-Path $skillsRoot)) {
    New-Item -ItemType Directory -Path $skillsRoot -Force | Out-Null
}

# Install kraken-cursor/* skills
$krakenCursor = Join-Path $src "kraken-cursor"
if (Test-Path $krakenCursor) {
    Get-ChildItem $krakenCursor -Directory | Where-Object {
        Test-Path (Join-Path $_.FullName "SKILL.md")
    } | ForEach-Object {
        $targetName = "kraken-cursor-$($_.Name)"
        $target = Join-Path $skillsRoot $targetName
        if (Test-Path $target) { Remove-Item $target -Recurse -Force }
        try {
            New-Item -ItemType SymbolicLink -Path $target -Target $_.FullName -Force | Out-Null
        } catch {
            Copy-Item $_.FullName $target -Recurse -Force
        }
        Write-Host "Installed $targetName" -ForegroundColor Green
    }
}

# Install skills/* (Claude-style layout)
$skillsDir = Join-Path $src "skills"
if (Test-Path $skillsDir) {
    Get-ChildItem $skillsDir -Directory | Where-Object {
        Test-Path (Join-Path $_.FullName "SKILL.md")
    } | ForEach-Object {
        $target = Join-Path $skillsRoot $_.Name
        if (Test-Path $target) { Remove-Item $target -Recurse -Force }
        try {
            New-Item -ItemType SymbolicLink -Path $target -Target $_.FullName -Force | Out-Null
        } catch {
            Copy-Item $_.FullName $target -Recurse -Force
        }
        Write-Host "Installed $($_.Name)" -ForegroundColor Green
    }
}
```

### Step 3b — Optional plugin install

When the user wants a full Cursor plugin (or repo has `.cursor-plugin/plugin.json` and no separate skills tree):

```powershell
$repo = "<owner/repo>"
$repoLeaf = "<RepoLeaf>"
$pluginName = "<plugin-name-from-manifest>"
$zip = "$env:TEMP\$repoLeaf-plugin.zip"
$extract = "$env:TEMP\$repoLeaf-plugin-extract"
$localRoot = Join-Path $env:USERPROFILE ".cursor\plugins\local"

Invoke-WebRequest "https://github.com/$repo/archive/refs/heads/main.zip" -OutFile $zip
Expand-Archive $zip $extract -Force
$src = Join-Path $extract "$repoLeaf-main"
$dest = Join-Path $localRoot $pluginName

if (-not (Test-Path $localRoot)) {
    New-Item -ItemType Directory -Path $localRoot -Force | Out-Null
}
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
Copy-Item $src $dest -Recurse -Force
Write-Host "Plugin installed to $dest" -ForegroundColor Green
```

For marketplace-distributed plugins (multi-plugin repos), use **kraken-cursor-add-marketplace** instead of copying manually.

### Step 4 — Tell the user

After install:

1. **Restart Cursor** (or start a new Agent chat) so skills reload.
2. Confirm skills appear — ask the agent to list available skills or invoke one by name.
3. For plugin installs, open **Cursor Settings → Plugins** and confirm the plugin is enabled.

If skills don't appear: re-run install, check folder names under `~/.cursor/skills/`, and verify each folder contains `SKILL.md` with valid YAML frontmatter.

### Step 5 — Generate shareable INSTALL.md (optional)

If the user wants to share the repo with a teammate, offer to generate an `INSTALL.md` for their repo. Structure:

1. Cursor instructions up top (run installer or paste into Agent chat)
2. Skills table at the bottom

Teammate workflow: clone or paste INSTALL.md into Cursor Agent chat; agent runs **kraken-cursor-register-skill-repo** steps.

## Common mistakes

- **Wrong plugin name** — use `name` from `.cursor-plugin/plugin.json`, not the repo name.
- **Forgetting to restart** — Cursor loads skills at chat startup; a new Agent chat is required.
- **Symlink vs copy** — symlinks need Developer Mode on Windows; script falls back to copy.
- **Private repo** — warn the user; public GitHub raw URLs and ZIP downloads will fail.
- **Skills vs plugin** — skills-only repos do not need `~/.cursor/plugins/local/` unless they ship MCP/rules.
