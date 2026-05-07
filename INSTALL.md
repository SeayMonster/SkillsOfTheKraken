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
2. Verify with `/skills` — you should see all `crisp-dev-*` skills listed.

### Skills that will be available

| Skill | Purpose |
|-------|---------|
| `/crisp-dev-csharp-style` | C# conventions for JDA/BlueYonder tooling |
| `/crisp-dev-jda-space-automation` | Write/convert JDA Space Automation scripts |
| `/crisp-dev-openaccess-controls` | Build OpenAccess custom controls |
| `/crisp-dev-datamanager-converter` | Convert Data Manager `.fsf` forms to OA |
| `/crisp-dev-generate-deployment` | Generate SQL deployment packages |
| `/crisp-dev-spec-reviewer` | Generate interactive HTML spec review pages |
| `/crisp-dev-switch-sql-mcp` | Repoint mssql MCP between local/client connections |
| `/crisp-dev-register-skill-repo` | Register any GitHub skill repo |
