# kraken-cursor

Cursor Agent Skills adapted from [SkillsOfTheKraken](../README.md). These skills replace Claude Code's `Workflow()` API with explicit **Task subagent** orchestration that works in Cursor.

**Namespace:** every skill is installed as `kraken-cursor-<skill-name>` so you can distinguish them from Claude Code `kraken:*` skills.

## Install

```powershell
cd C:\path\to\SkillsOfTheKraken
.\kraken-cursor\install.ps1
```

Or from GitHub:

```powershell
irm https://raw.githubusercontent.com/SeayMonster/SkillsOfTheKraken/main/kraken-cursor/install.ps1 | iex
```

Restart Cursor (or start a new Agent chat) after installing.

## Keep Claude and Cursor in sync

After editing `skills/` (Claude source):

```
Use kraken-cursor-sync-skills to audit and sync Cursor skills.
```

The sync skill audits gaps, spawns **parallel Task agents** to translate/update, runs `install.ps1`, and reminds you to `/plugin update` in Claude Code.

Quick audit only:

```powershell
.\kraken-cursor\sync-skills\scripts\audit-sync.ps1
```

See [TRANSLATION.md](TRANSLATION.md) for manual porting rules.

## Skills (mirrors `skills/`)

| Installed name | Purpose |
|----------------|---------|
| `kraken-cursor-sync-skills` | Audit + agent-driven sync from `skills/` → `kraken-cursor/` |
| `kraken-cursor-create-saas-deployment-package` | SaaS CKB deployment package |
| `kraken-cursor-create-reporting-deploy-package` | ASP.NET Core IIS deploy ZIP |
| `kraken-cursor-client-onboarding` | BlueYonder client repo setup |
| `kraken-cursor-spec-review` | Interactive HTML spec review |
| `kraken-cursor-html-likeness` | Reference vs target HTML dashboards |
| `kraken-cursor-dev-notion-setup` | Notion UAT/Requirements setup |
| `kraken-cursor-setup-copilot` | Generate `.github/copilot-instructions.md` |
| `kraken-cursor-pin-project` | VS Code Project Manager registry |
| `kraken-cursor-desktop-vscode-bridge` | Cursor ↔ VS Code project sync |
| `kraken-cursor-by-oa-adhoc` | Playwright OA adhoc commands |
| `kraken-cursor-by-local-batch-test` | Local batch testing |
| `kraken-cursor-ba-workflow` | BA workflow overview |
| `kraken-cursor-ba-requirement` | Requirements / user stories |
| `kraken-cursor-ba-generate-uat` | Generate UAT test cases |
| `kraken-cursor-ba-uat-pull` | Export Notion UAT to Excel |
| `kraken-cursor-ba-uat-import` | Import UAT Excel to Notion |
| `kraken-cursor-ba-signoff` | BA sign-off workflow |
| `kraken-cursor-qa-init` | Scaffold QA Bots workspace |
| `kraken-cursor-qa-run` | Run QA checks + dashboard |
| `kraken-cursor-qa-uat` | UAT validation |
| `kraken-cursor-qa-openaccess` | Static OA ASCX analysis |
| `kraken-cursor-qa-openaccess-playwright` | OA browser QA |
| `kraken-cursor-qa-dapper` | Dapper/SQL analysis |
| `kraken-cursor-qa-web-smoke` | Web smoke tests |
| `kraken-cursor-qa-process-flow` | QA process flow guide |
| `kraken-cursor-plugin-digest` | Cursor plugin discovery digest |
| `kraken-cursor-register-skill-repo` | Register skill repos for Cursor |
| `kraken-cursor-add-marketplace` | Add Cursor plugin marketplace |

## Invoke in Cursor

```
Use kraken-cursor-sync-skills after I change skills in the Claude folder.
Use kraken-cursor-create-saas-deployment-package to build a --saas deployment package.
```

## vs Claude Code `kraken`

| | Claude Code | Cursor |
|--|-------------|--------|
| Source folder | `skills/` | `kraken-cursor/` |
| Install | `/plugin update kraken@SkillsOfTheKraken` | `install.ps1` |
| Sync | edit `skills/` + push | `kraken-cursor-sync-skills` |
| QA config | `~/.claude/.qa-bots-path` | `~/.cursor/.kraken-cursor/qa-bots-path` |

## Repo layout

```
kraken-cursor/
  README.md
  TRANSLATION.md
  install.ps1
  sync-skills/          # meta: keep trees aligned
  <skill-name>/SKILL.md # one folder per Claude skill
```
