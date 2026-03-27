---
name: mind-rules
description: |
  [Mind Manager] Manage project rules (.claude/rules/*.md). List, validate syntax, create new rules,
  migrate from paths: to globs: (fixing the known bug where paths: silently fails).
  Supports alwaysApply workaround (rule without globs: = always loaded). Offers
  InstructionsLoaded debug mode to verify which files load.

  Use when the user says "manage rules", "check rules", "mind rules", "create a rule",
  "fix my rules", "rules not working", "paths to globs", "rules syntax check",
  or "/mind-rules [list|check|create|migrate]".
argument-hint: "[list|check|create|migrate]"
context: inherit
allowed-tools: Read Glob Grep Edit Write Bash
---

# Rules Management

Manage, validate, create, and fix Claude Code rule files.

## Objective

Provide complete management of `.claude/rules/*.md` files including syntax validation, creation, and migration from the buggy `paths:` field to the working `globs:` field.

## Workflow

### Step 1: Parse Subcommand

From `$ARGUMENTS`:
- **list** — show all rules with frontmatter and line counts
- **check** — validate syntax, detect issues
- **create** — guided creation of a new rule
- **migrate** — auto-convert paths: to globs:
- No argument — default to `list`

Optional flag: `--debug` (only with `check`) — enable InstructionsLoaded hook

---

### Subcommand: list

1. Glob for `.claude/rules/*.md` and `~/.claude/rules/*.md`
2. Read each file's YAML frontmatter
3. Display table:

```
=== Rules Overview ===

| File | Scope | Glob Pattern | Lines | Status |
|------|-------|-------------|-------|--------|
| .claude/rules/typescript.md | Project | **/*.ts, **/*.tsx | 30 | OK (globs:) |
| .claude/rules/api.md | Project | src/api/**/* | 25 | OK (globs:) |
| .claude/rules/general.md | Project | (none — always loaded) | 15 | OK |
| ~/.claude/rules/style.md | User | — | 20 | WARNING (paths: — won't work) |

Total: 4 rules, 90 lines
```

---

### Subcommand: check

1. Read all rule files
2. Parse YAML frontmatter
3. Check for issues:

| Issue | Severity | Detection |
|-------|----------|-----------|
| Uses `paths:` instead of `globs:` | WARNING | Grep `^paths:` |
| User-level rule uses `paths:` | ERROR | paths: in ~/.claude/rules/ never works |
| YAML quoting issue | WARNING | `*` or `{` at line start without quotes |
| Empty frontmatter | INFO | No globs: = always loaded (may be intentional) |
| Rule >50 lines | INFO | Large rule may impact compliance |

Output:
```
=== Rules Syntax Check ===

.claude/rules/typescript.md — OK (globs: **/*.ts, **/*.tsx)
.claude/rules/testing.md   — WARNING: uses paths: instead of globs:
~/.claude/rules/global.md  — ERROR: paths: in user-level rules (never works)

Fixable: 2 issues (run /mind-rules migrate)
```

**With `--debug` flag:** Explain InstructionsLoaded hook:
```
To debug which files Claude loads and when, add this to .claude/settings.json:

"hooks": {
  "InstructionsLoaded": [{
    "hooks": [{ "type": "command",
      "command": "echo '[Debug] Files loaded:' && cat | jq -r '.files // empty'" }]
  }]
}

View output with Ctrl+O (verbose mode). Remove after debugging.
```

---

### Subcommand: create

Guided rule creation:

1. Ask: "What should this rule enforce?"
2. Ask: "Which files should it apply to? (glob pattern, e.g., **/*.ts)"
   - Option: "Always load (no file filter)" → creates rule without globs: frontmatter
3. Generate rule file:

```yaml
---
globs: src/api/**/*.ts
---
# API Development Rules

- All endpoints MUST validate input with Zod
- Error handling per src/lib/errors.ts
- NEVER use direct DB queries in route handlers — use repository pattern
```

4. Show preview, confirm file path (`.claude/rules/<name>.md`)
5. Write on confirmation

---

### Subcommand: migrate

Auto-convert `paths:` to `globs:` in all rule files:

1. Find all rule files with `paths:` frontmatter
2. For each file, show diff:

```
=== Migrating .claude/rules/testing.md ===

Before:
  paths:
    - "tests/**/*.test.ts"
    - "tests/**/*.spec.ts"

After:
  globs: tests/**/*.test.ts, tests/**/*.spec.ts

[Apply / Skip]
```

3. Apply changes with Edit on confirmation
4. Summary: "Migrated N files from paths: to globs:"

## Hard Constraints

- ALWAYS use `globs:` in generated rules, NEVER `paths:`
- ALWAYS show preview before writing new rule files
- ALWAYS warn about user-level rules with paths: (known to not work)
- NEVER modify rules without showing the diff first
- Rules without globs: are valid — they always load (document this, don't warn)
