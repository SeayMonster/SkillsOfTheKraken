# Kraken → Cursor translation conventions

All `kraken-cursor-*` skills follow these rules. Read this file before editing any skill in `kraken-cursor/`.

## Naming

| Item | Pattern |
|------|---------|
| Skill folder | `kraken-cursor/<source-skill-name>/` |
| Installed name | `kraken-cursor-<source-skill-name>` |
| YAML `name` | same as installed name |
| Invoke phrase | "Use kraken-cursor-foo" (not `/kraken:foo`) |

## Mechanical replacements

| Claude Code | Cursor |
|-------------|--------|
| `/kraken:foo` | Use kraken-cursor-foo |
| `kraken:foo` cross-skill | kraken-cursor-foo |
| `crisp-tc:qa-*` | kraken-cursor-qa-* |
| `Workflow({ scriptPath })` | Task subagents + Shell; see `references/workflow-phases.md` |
| `<context>` / `<task>` XML | Flat markdown (`## Pre-flight`, `## Steps`) |
| `~/.claude/.qa-bots-path` | `~/.cursor/.kraken-cursor/qa-bots-path` |
| Claude browser MCP | Cursor `cursor-ide-browser` (`browser_navigate`, `browser_snapshot`, etc.) |
| Claude Notion tools | Cursor `plugin-notion-workspace-notion` MCP |
| `CronCreate` / `CronList` | Omit |

## Paths — never hardcode user paths

- `{SKILL_DIR}` — directory containing this skill's SKILL.md
- `{repoRoot}` — client repo root (where `_package-request.json` or `.sln` lives)
- Deploy state: `{repoRoot}/.kraken-cursor/`

## SKILL.md frontmatter

```yaml
---
name: kraken-cursor-<skill-name>
description: >-
  Third-person WHAT + WHEN. Include trigger terms for discovery.
---
```

Keep SKILL.md under 500 lines; use `references/` for long content.

## QA Bots shared config

- Path file: `~/.cursor/.kraken-cursor/qa-bots-path` (one line, absolute path to QA Bots repo)
- `qa-init` writes QA Bots workspace under `clients/<name>/` (keep `.claude/` layout for Claude Code compatibility)
- Also write `.cursor/qa-config.json` in client workspace when scaffolding

## Cross-skill references

| Orchestrator | Invokes |
|--------------|---------|
| qa-run | kraken-cursor-qa-dapper, kraken-cursor-qa-web-smoke, kraken-cursor-qa-openaccess |
| qa-uat | kraken-cursor-qa-init (prerequisite message if missing) |
| client-onboarding | kraken-cursor-setup-copilot (mention only if skill exists; else inline steps) |

## Plan execution (Cursor)

When implementing multiple kraken-cursor skills, use **parallel Task subagents** for disjoint folders. See `~/.cursor/rules/multi-agent-plan-execution.mdc`.

## Forbidden in kraken-cursor skills

- `Workflow()` calls
- Hardcoded `C:\Users\...` paths
- Claude-only APIs (CronCreate, `/plugin`, `/mcp` slash commands)
- References to `~/.cursor/skills-cursor/` (Cursor internal)
