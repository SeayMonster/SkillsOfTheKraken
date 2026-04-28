# SkillsOfTheKraken

A Claude Code skills plugin repository containing reusable skills and plugins for project work.

## What is this?

This repository is a **Claude Code skills plugin marketplace**. It follows the Claude plugin marketplace format and can be added to Claude Code to make its skills available as slash commands (e.g. `/skill-name`).

## Repository Structure

```
SkillsOfTheKraken/
├── .claude-plugin/
│   └── marketplace.json   # Marketplace metadata
├── skills/
│   └── (skill folders go here)
└── README.md
```

## Installation

To install this plugin marketplace in Claude Code, add it to your `~/.claude/settings.json` under `extraKnownMarketplaces`:

```json
{
  "extraKnownMarketplaces": [
    {
      "name": "SkillsOfTheKraken",
      "url": "https://github.com/SeayMonster/SkillsOfTheKraken"
    }
  ]
}
```

After saving the file, restart Claude Code (or reload the window) for the new marketplace to be detected.

## Using Skills

Once the marketplace is installed, skills are invoked using slash commands in Claude Code:

```
/skill-name
```

For example, if a skill named `summarize` exists in this repository, you would invoke it with:

```
/summarize
```

## Adding Skills

To add a new skill, create a folder under `skills/` with the skill's name and include the required plugin definition files. Then add the skill entry to `.claude-plugin/marketplace.json` under the `"plugins"` array.
