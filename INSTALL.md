# SkillsOfTheKraken — Auto-Install Instructions for Claude

> **How to use:** Share this file with a teammate. They paste its contents into Claude Code chat (or drag the file in) and say "follow the instructions in this file."

---

## Instructions for Claude

You are setting up the SkillsOfTheKraken skill plugin for this developer. Complete all steps below without asking unnecessary questions.

### Step 1 — Register the marketplace

Edit `$env:USERPROFILE\.claude\settings.json` to add the SkillsOfTheKraken marketplace entry. Use this PowerShell:

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

if (-not $settings.extraKnownMarketplaces.PSObject.Properties["SkillsOfTheKraken"]) {
    $entry = [PSCustomObject]@{
        source = [PSCustomObject]@{
            source = "github"
            repo   = "SeayMonster/SkillsOfTheKraken"
        }
    }
    $settings.extraKnownMarketplaces | Add-Member -MemberType NoteProperty -Name "SkillsOfTheKraken" -Value $entry
    $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding utf8
    Write-Host "Marketplace registered." -ForegroundColor Green
} else {
    Write-Host "SkillsOfTheKraken already registered." -ForegroundColor Yellow
}
```

### Step 2 — Tell the user what to do next

After running the script, give the user these exact instructions:

1. In Claude Code, run: `/plugin install crisp-dev@SkillsOfTheKraken`
2. Restart Claude Code (full window reload).
3. Verify with `/skills` — you should see all `crisp-dev-*` skills listed.

If `/plugin install` fails or the skills don't appear after restart, run: `/plugin update crisp-dev@SkillsOfTheKraken`

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
