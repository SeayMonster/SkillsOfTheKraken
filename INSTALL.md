# SkillsOfTheKraken — Auto-Install Instructions for Claude

> **How to use:** Share this file with a teammate. They paste its contents into Claude Code chat (or drag the file in) and say "follow the instructions in this file."
>
> **Prereqs:** None — the installer uses only built-in PowerShell (Windows 10/11). No git, no npm, no Claude CLI required.

---

## Instructions for Claude

You are setting up the SkillsOfTheKraken skill plugin for this developer. Complete all steps below without asking unnecessary questions.

### Step 1 — Run the installer

Run this in PowerShell (no installs required — works on any Windows 10/11 machine):

```powershell
irm https://raw.githubusercontent.com/SeayMonster/SkillsOfTheKraken/main/addclaudeskills.ps1 | iex
```

This registers the marketplace, downloads all skills, and populates the plugin cache. No git, no npm, no Claude CLI needed.

### Step 2 — Tell the user what to do next

After the script completes:

1. Restart Claude Code (full window reload).
2. Verify with `/skills` — you should see all `kraken:*` skills listed.

### Skills that will be available

| Skill | Purpose |
|-------|---------|
| `/kraken:csharp-style` | C# conventions for JDA/BlueYonder tooling |
| `/kraken:jda-space-automation` | Write/convert JDA Space Automation scripts |
| `/kraken:openaccess-controls` | Build OpenAccess custom controls |
| `/kraken:datamanager-converter` | Convert Data Manager `.fsf` forms to OA |
| `/kraken:generate-deployment` | Generate SQL deployment packages |
| `/kraken:spec-reviewer` | Generate interactive HTML spec review pages |
| `/kraken:switch-sql-mcp` | Repoint mssql MCP between local/client connections |
| `/kraken:register-skill-repo` | Register any GitHub skill repo |
