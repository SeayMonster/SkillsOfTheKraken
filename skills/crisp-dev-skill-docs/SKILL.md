---
name: crisp-dev-skill-docs
description: Use when the user wants a reference document showing all available skills, what each one does, and when to use it. Triggered by phrases like "generate skill docs", "what skills do I have", "skill reference", or "skill list".
---

# Generate Skill Reference Docs

## Overview

Fetches all skills from the SkillsOfTheKraken repo, reads each SKILL.md, and generates a styled HTML reference page. Always reads from the repo so the output reflects the latest skills, including ones not yet cached.

## Steps

Run this PowerShell — no prompts needed:

```powershell
$repo    = "SeayMonster/SkillsOfTheKraken"
$outFile = "g:\My Drive\!ai\skill-reference.html"

# Fetch skill folder list
$skills = gh api repos/$repo/contents/skills --jq '.[].name' | Where-Object { $_ -ne "" }

$cards = foreach ($skill in $skills) {
    $encoded = gh api repos/$repo/contents/skills/$skill/SKILL.md --jq '.content'
    $raw = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(($encoded -join "")))

    $nameMatch = [regex]::Match($raw, '(?m)^name:\s*(.+)$')
    $descMatch = [regex]::Match($raw, '(?m)^description:\s*(.+)$')
    $name    = if ($nameMatch.Success) { $nameMatch.Groups[1].Value.Trim() } else { $skill }
    $descVal = if ($descMatch.Success) { $descMatch.Groups[1].Value.Trim() } else { "" }

    $desc = if ($descVal -eq '>') {
        $block = [regex]::Match($raw, '(?m)^description:\s*>\r?\n((?:[ \t]+.+\r?\n?)+)')
        if ($block.Success) {
            ($block.Groups[1].Value -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ' '
        } else { "No description." }
    } else { $descVal }
    $when = $desc -replace '^Use when\s*', ''

    "    <div class=`"card`"><div class=`"skill-name`">/$name</div><div class=`"when`"><span class=`"label`">Use when</span> $when</div></div>"
}

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Crisp Dev Skill Reference</title>
<style>
  body { font-family: Segoe UI, Arial, sans-serif; background: #f4f6f9; margin: 0; padding: 2rem; }
  h1   { color: #1a1a2e; font-size: 1.6rem; margin-bottom: 0.25rem; }
  .subtitle { color: #666; font-size: 0.9rem; margin-bottom: 2rem; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(380px, 1fr)); gap: 1rem; }
  .card { background: white; border-radius: 8px; padding: 1.2rem 1.4rem; box-shadow: 0 1px 4px rgba(0,0,0,.08); border-left: 4px solid #4f8ef7; }
  .skill-name { font-weight: 700; font-size: 1rem; color: #1a1a2e; margin-bottom: 0.4rem; font-family: Consolas, monospace; }
  .when  { font-size: 0.88rem; color: #444; line-height: 1.5; }
  .label { font-weight: 600; color: #4f8ef7; }
  @media print { body { background: white; } .card { box-shadow: none; border: 1px solid #ddd; } }
</style>
</head>
<body>
<h1>Crisp Dev Skill Reference</h1>
<div class="subtitle">Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') &nbsp;·&nbsp; $($skills.Count) skills &nbsp;·&nbsp; github.com/$repo</div>
<div class="grid">
$($cards -join "`n")
</div>
</body>
</html>
"@

[System.IO.File]::WriteAllText($outFile, $html, [System.Text.UTF8Encoding]::new($false))
Write-Host "Saved to $outFile"
Start-Process $outFile
```

After running, tell the user:
> "Skill reference saved to `g:\My Drive\!ai\skill-reference.html` and opened in your browser. Use Ctrl+P to save as PDF."
