---
name: kraken-cursor-qa-dapper
description: >-
  Scans Dapper data access blocks in a target C# file, maps raw SQL variables,
  verifies entity tracking and nullability, checks SQL injection patterns, and
  runs verification builds. Use when the user asks for Dapper QA, kraken-cursor-qa-dapper,
  or SQL/data-access validation on a repository file.
argument-hint: [target-repository-file]
---

# kraken-cursor: qa-dapper

**Announce at start:** "I'm using kraken-cursor-qa-dapper to validate Dapper data access."

Performs deep structural code validation on the target file provided in the arguments: `$0`.

## Assessment Checkpoints

1. **Query & Mapping Parity:** Cross-reference inline SQL strings or Stored Procedure parameters with target C# mapping model properties to ensure binding parity.
2. **Nullability Safety:** Confirm that database column values capable of containing null tables evaluate safely into nullable C# configurations (`int?`, `string`) to prevent runtime NullReferenceExceptions.
3. **SQL Injection Check:** Ensure no query blocks append raw variable string concatenations. Everything must use Dapper anonymous objects for parameters (e.g., `new { Id }`).
4. **Connection Integrity:** Verify that `SqlConnection` streams are bound inside robust execution patterns to prevent memory or connection leaks.

## Remediation and Validation

If anomalies are discovered, modify the source code to resolve them. Then execute the validation cycle:

- Run `msbuild YourSolution.sln /t:Build` to ensure compilation integrity.
- Execute `vstest.console.exe` to confirm no regression occurred.

Resolve `YourSolution.sln` from `{repoRoot}` or the client workspace `.cursor/qa-config.json` / `.claude/qa-config.json` `solution_path` when available.
