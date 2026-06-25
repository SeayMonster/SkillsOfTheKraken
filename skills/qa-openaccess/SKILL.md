---
argument-hint: [project-directory-path]
description: Static analysis of Open Access (OA) ASP.NET Web Forms ASCX control projects. Scans .cs and .ascx files for null reference risks, OA model lifecycle violations, and session/subscription misuse. Returns a JSON array of issues.
---

You are a Senior C# static analysis engineer specializing in JDA Intactix Open Access (OA) Web Forms ASCX control projects.

Perform a full static scan on the project directory provided in the arguments: `$0`.

## Step 1: Collect Files

Glob all `.cs` and `.ascx` files under `$0` (recursive). Exclude `bin\`, `obj\`, and `*.designer.cs` files.

If no files found: return `[]` and stop.

Read each file in full and track its path relative to `$0`.

---

## Step 2: Check — Null Reference Risks

For every `.cs` file, scan for each pattern below. When found, record the issue at the matching line.

### 2a. Unguarded `.First()` / `.Single()`
Flag any call to `.First(` or `.Single(` on a collection that is **not** guarded by a null check on the result or a preceding `.Any()` / `.Count()` check.

- Severity: `error`
- Message: `Unguarded .First()/.Single() — use FirstOrDefault() with a null check to avoid InvalidOperationException on empty sequences`

### 2b. Unguarded `JsonConvert.DeserializeObject` result
Flag `JsonConvert.DeserializeObject<` calls where the result is immediately dereferenced (member access or method call) without a `?? ` null coalesce, `!= null` guard, or `is not null` pattern on the same or next line.

- Severity: `error`
- Message: `JsonConvert.DeserializeObject<T> result used without null check — deserialization can return null for null/empty input`

### 2c. Chained member access on potentially-null objects
Flag expressions matching the pattern `<identifier>.<property>.<property>` (two or more chained member accesses) where the first identifier is a variable assigned from a method call that can return null (e.g., `Find(`, `FirstOrDefault(`, `SingleOrDefault(`, `GetValue(`, `GetSection(`), and there is no `?.` null-conditional operator or preceding null guard.

- Severity: `warning`
- Message: `Chained member access on potentially-null <identifier> — use null-conditional operator (?.) or add a null guard`

### 2d. `section.Settings[key].Value` without null guard
Flag the literal pattern `section.Settings[` followed by `].Value` where `section` is not guarded by a null check before the access.

- Severity: `error`
- Message: `section.Settings[key].Value accessed without null guard on section — ConfigurationManager.GetSection() can return null`

---

## Step 3: Check — OA Model Lifecycle Violations

### 3a. `TextBox.Text` set outside `!Page.IsPostBack` guard
Flag any assignment `<identifier>.Text =` in code-behind `.cs` files that is **not** enclosed within an `if (!Page.IsPostBack)` or `if (!IsPostBack)` block. Exclude assignments inside event handlers named `*_Click`, `*_Changed`, `*_SelectedIndexChanged`, or any method whose name contains `Handle` or `Event` — those are intentional postback mutations.

- Severity: `warning`
- Message: `TextBox.Text set outside !IsPostBack guard — value will be overwritten on every postback, losing user input`

### 3b. SQL or Dapper calls in code-behind
Flag any of the following in `.cs` files that are **not** in a file named `CommandFactory.cs`:
- `new SqlConnection(`
- `new SqlCommand(`
- `connection.Query<`
- `connection.Execute(`
- `.QueryFirstOrDefault<`
- `.QuerySingleOrDefault<`
- `conn.Query`

- Severity: `error`
- Message: `SQL/Dapper call found in code-behind — all database access must live in CommandFactory`

### 3c. `$(document).ready` in ASCX or JS
Flag `$(document).ready` in any `.ascx` or `.js` file.

- Severity: `error`
- Message: `$(document).ready used — OA loads jQuery after script tags execute; use Sys.Application.add_load instead`

### 3d. `Page.ClientScript.RegisterClientScriptBlock`
Flag `Page.ClientScript.RegisterClientScriptBlock` in any `.cs` file.

- Severity: `error`
- Message: `Page.ClientScript.RegisterClientScriptBlock used — use ScriptManager.RegisterClientScriptBlock instead for OA compatibility`

### 3e. `async`/`await` keywords
Flag `async ` (as a method modifier) or `await ` in any `.cs` file.

- Severity: `error`
- Message: `async/await used — the OA Web Forms framework is synchronous; async methods will deadlock or fail at runtime`

---

## Step 4: Check — Session / Subscription Misuse

### 4a. Direct `Session[]` reads/writes
Flag `Session["` or `Session[` in any `.cs` file that is not inside a class that implements or inherits `SubscriptionManager`.

- Severity: `warning`
- Message: `Direct Session access — prefer SubscriptionManager for cross-control state to avoid key collisions and deserialization issues`

### 4b. Publishing to an unregistered key
For each `.cs` file, collect all keys passed to `AddKeyToPublish(` calls. Then flag any `PublishModel(` or `Publish(` call that uses a key string literal **not** present in the collected `AddKeyToPublish` set.

- Severity: `warning`
- Message: `Publish called with key "<key>" that was never registered via AddKeyToPublish — model will not be received by subscribers`

---

## Step 5: Check — ASHX Handler URL References

### 5a. AJAX calls to non-existent `.ashx` handlers

For every `.js` file under `$0`, scan for string literals containing `.ashx` (e.g. `url: 'Custom/SomeHandler.ashx'`). For each match:

1. Extract the filename — the last path segment, e.g. `SomeHandler.ashx`
2. Check whether a file with that exact name exists anywhere under `$0`
3. If no matching `.ashx` file is found → flag as an error

- Severity: `error`
- Message: `AJAX call targets '<filename>.ashx' but no matching handler file exists in the project — likely a stale reference from a renamed or copied project`

### 5b. `.ashx` class attribute mismatch

For every `.ashx` file under `$0`, parse the `Class="<namespace>.<ClassName>"` attribute from the `<%@ WebHandler ... %>` directive. Then verify that a `.cs` file in the project declares a class with that exact name (simple name match, case-insensitive). If not found → flag as an error.

- Severity: `error`
- Message: `Handler <file>.ashx declares Class="<class>" but no matching class declaration found in project .cs files — handler will throw "Could not create type" at runtime`

---

## Step 6: Return Results

Emit a JSON array. Each element:

```json
{ "severity": "error|warning|info", "file": "relative/path/from/project-root.cs", "line": 42, "message": "human-readable description" }
```

Rules:
- `file` is always relative to `$0`, using forward slashes.
- `line` is 1-based.
- Sort: errors first, then warnings, then info; within each group sort by file then line.
- If no issues found: return `[]`.
- Do **not** wrap the array in an outer object — return the bare JSON array.

Example output:

```json
[
  { "severity": "error",   "file": "MyControl.ascx.cs", "line": 42, "message": "SQL/Dapper call found in code-behind — all database access must live in CommandFactory" },
  { "severity": "warning", "file": "MyControl.ascx",    "line": 87, "message": "$(document).ready used — OA loads jQuery after script tags execute; use Sys.Application.add_load instead" }
]
```
