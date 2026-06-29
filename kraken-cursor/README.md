# kraken-cursor

Cursor Agent Skills adapted from [SkillsOfTheKraken](../README.md). These skills replace Claude Code's `Workflow()` API with explicit **Task subagent** orchestration that works in Cursor.

**Namespace:** every skill is installed as `kraken-cursor-<skill-name>` so you can distinguish them from Claude Code `kraken:*` skills.

## Install

From PowerShell (uses your local clone or downloads from GitHub):

```powershell
# From a local clone
cd C:\path\to\SkillsOfTheKraken
.\kraken-cursor\install.ps1

# Or one-liner from GitHub
irm https://raw.githubusercontent.com/SeayMonster/SkillsOfTheKraken/main/kraken-cursor/install.ps1 | iex
```

Restart Cursor (or start a new Agent chat) after installing.

## Skills

| Installed name | Purpose |
|----------------|---------|
| `kraken-cursor-create-saas-deployment-package` | Multi-phase SaaS CKB deployment package (`--saas` or `--local`) |
| `kraken-cursor-create-reporting-deploy-package` | ASP.NET Core IIS deploy ZIP packager |
| `kraken-cursor-client-onboarding` | One-time BlueYonder client repo setup |
| `kraken-cursor-spec-review` | Interactive HTML spec review pages |
| `kraken-cursor-html-likeness` | Compare reference vs target HTML dashboards |
| `kraken-cursor-dev-notion-setup` | Notion UAT/Requirements database setup |
| `kraken-cursor-qa-init` | Scaffold QA Bots client workspace |
| `kraken-cursor-qa-run` | Run QA checks across solution projects |
| `kraken-cursor-qa-uat` | UAT validation (Playwright + sqlcmd) |
| `kraken-cursor-qa-openaccess` | Static OA ASCX analysis |
| `kraken-cursor-qa-dapper` | Dapper/SQL static analysis |
| `kraken-cursor-qa-web-smoke` | Web smoke tests via browser MCP |
| `kraken-cursor-qa-process-flow` | Open QA process flow guide |

## Invoke in Cursor

Ask the agent:

```
Use kraken-cursor-create-saas-deployment-package to build a --saas deployment package.
Use kraken-cursor-qa-init to set up QA for this client repo.
```

Or reference the skill when trigger files exist (`_package-request.json`, `.sln`, etc.).

## vs Claude Code `kraken` plugin

| | Claude Code `kraken` | Cursor `kraken-cursor` |
|--|----------------------|-------------------------|
| Install | `/plugin install kraken@SkillsOfTheKraken` | `install.ps1` → `~/.cursor/skills/` |
| Orchestration | `Workflow({ scriptPath: workflow.js })` | Task subagents per phase (see SKILL.md) |
| Skill prefix | `kraken:create-saas-deployment-package` | `kraken-cursor-create-saas-deployment-package` |
| QA config path | `~/.claude/.qa-bots-path` | `~/.cursor/.kraken-cursor/qa-bots-path` |

Both read the same client repo files and produce the same outputs where applicable.

## Translation conventions

See [TRANSLATION.md](TRANSLATION.md) for Claude → Cursor replacement rules when adding or updating skills.

## Repo layout

```
kraken-cursor/
  README.md
  TRANSLATION.md
  install.ps1
  create-saas-deployment-package/
  create-reporting-deploy-package/
  client-onboarding/
  spec-review/
  html-likeness/
  dev-notion-setup/
  qa-init/ ... qa-process-flow/
```
