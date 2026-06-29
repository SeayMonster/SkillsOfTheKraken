# kraken-cursor

Cursor Agent Skills adapted from [SkillsOfTheKraken](../README.md). These skills replace Claude Code's `Workflow()` API with explicit **Task subagent** orchestration that works in Cursor.

**Namespace:** every skill is installed as `kraken-cursor-<skill-name>` so you can distinguish them from Claude Code `kraken:*` skills.

## Install

From PowerShell (uses your local clone or downloads from GitHub):

```powershell
# From a local clone
cd C:\Users\bseay\source\repos\SkillsOfTheKraken
.\kraken-cursor\install.ps1

# Or one-liner from GitHub
irm https://raw.githubusercontent.com/SeayMonster/SkillsOfTheKraken/main/kraken-cursor/install.ps1 | iex
```

Restart Cursor (or start a new Agent chat) after installing.

## Skills

| Installed name | Purpose |
|----------------|---------|
| `kraken-cursor-create-saas-deployment-package` | Multi-phase SaaS deployment package builder (`--saas` or `--local`) |

## Invoke in Cursor

Ask the agent:

```
Use kraken-cursor-create-saas-deployment-package to build a --saas deployment package.
```

Or reference the skill when `_package-request.json` exists in the repo root.

## vs Claude Code `kraken` plugin

| | Claude Code `kraken` | Cursor `kraken-cursor` |
|--|----------------------|-------------------------|
| Install | `/plugin install kraken@SkillsOfTheKraken` | `install.ps1` → `~/.cursor/skills/` |
| Orchestration | `Workflow({ scriptPath: workflow.js })` | Task subagents per phase (see SKILL.md) |
| Skill prefix | `kraken:create-saas-deployment-package` | `kraken-cursor-create-saas-deployment-package` |

Both read the same `_package-request.json` and produce the same `Deployments/YYYY-MM-DD/` output.

## Repo layout

```
kraken-cursor/
  README.md
  install.ps1
  create-saas-deployment-package/
    SKILL.md
    references/workflow-phases.md
    templates/deployment-guide-template.md
```
