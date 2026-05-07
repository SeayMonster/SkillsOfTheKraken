# SkillsOfTheKraken

Claude Code skills for Crisp / Blue Yonder development — JDA Space Automation, OpenAccess controls, C# coding conventions, deployment generation, and SQL MCP wrangling.

## Skills included

| Skill | What it does |
|-------|--------------|
| `crisp-dev-csharp-style` | C# coding conventions for JDA Space Automation Pro and CKB tooling |
| `crisp-dev-jda-space-automation` | Convert / write / explain JDA Space Automation scripts (legacy `.sas` and modern SA Pro C#) |
| `crisp-dev-openaccess-controls` | Build new OpenAccess (OA) custom controls for the Cantactix/BlueYonder platform |
| `crisp-dev-datamanager-converter` | Convert legacy Data Manager `.fsf` forms to OA controls |
| `crisp-dev-generate-deployment` | Generate SQL deployment packages (`--saas` handoff or `--direct` execution) |
| `crisp-dev-spec-reviewer` | Generate interactive HTML review pages for committed design specs |
| `crisp-dev-switch-sql-mcp` | Repoint the mssql MCP between local and client SQL Server connections |
| `crisp-dev-register-skill-repo` | Register any GitHub skill repo (or generate an INSTALL.md to share one) |

## Install (recommended)

In Claude Code, run:

```
/plugin marketplace add SeayMonster/SkillsOfTheKraken
/plugin install crisp-dev@SkillsOfTheKraken
```

Restart Claude Code (or run `/skills` to reload) and the skills are live.

## Install (Windows one-click)

If you'd rather skip the slash commands, run the included PowerShell installer to register the marketplace, then install the plugin:

```powershell
# from a PowerShell prompt anywhere on your machine
irm https://raw.githubusercontent.com/SeayMonster/SkillsOfTheKraken/main/addclaudeskills.ps1 | iex
```

Then in Claude Code:

```
/plugin install crisp-dev@SkillsOfTheKraken
```

The PowerShell script only adds the marketplace; you still need `/plugin install` to actually pull in the skills.

## Updating

Plugins refresh from GitHub automatically; if a skill seems stale, run:

```
/plugin update crisp-dev@SkillsOfTheKraken
```

## Repo layout

```
.claude-plugin/
  marketplace.json    # marketplace manifest
  plugin.json         # plugin manifest
skills/
  crisp-dev-<name>/
    SKILL.md          # one folder per skill
addclaudeskills.ps1   # optional Windows installer
```
