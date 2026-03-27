---
name: mind-generate
description: |
  [Mind Manager] Generate or rewrite a project-level CLAUDE.md from scratch. Scans the repo for tech stack,
  project type, build commands, and directory structure using the project-scanner agent.
  Selects a matching template, applies best-practices rules, and produces a concise,
  high-compliance CLAUDE.md (target: 40-80 lines).

  Use when the user says "generate claude.md", "create claude.md", "mind generate",
  "init context", "bootstrap claude.md", "scaffold context", "write a claude.md",
  "set up context", "make me a claude.md", or "/mind-generate".
argument-hint: "[--rewrite]"
context: inherit
allowed-tools: Read Glob Grep Write Bash Agent
---

# CLAUDE.md Generation

Generate a project-tailored CLAUDE.md by scanning the repo and applying template-based generation.

## Objective

Produce a concise, high-quality CLAUDE.md that follows all best practices from the reference guide. The generated file MUST pass the generation checklist before being written to disk.

## Workflow

### Step 1: Parse Arguments

Check `$ARGUMENTS` for flags:
- `--rewrite` -- allow overwriting an existing CLAUDE.md
- No flags -- default mode (fail if CLAUDE.md already exists)

### Step 2: Check for Existing CLAUDE.md

Glob for `./CLAUDE.md` and `./.claude/CLAUDE.md` in the project root.

- **If found AND `--rewrite` NOT specified**: Stop immediately. Print:
  ```
  CLAUDE.md already exists at <path> (<N> lines).
  Use --rewrite to overwrite: /mind-generate --rewrite
  ```
- **If found AND `--rewrite` specified**: Continue. The existing file will be replaced.
- **If not found**: Continue with fresh generation.

### Step 3: Load Best Practices

Read the best-practices reference:
- [references/claudemd-best-practices.md](references/claudemd-best-practices.md)

Keep the required sections list, anti-patterns, size guidelines, and formatting rules in context for all subsequent steps.

### Step 4: Dispatch Project Scanner

Launch the **project-scanner** agent:

> "Scan this repository and produce a structured report of the tech stack, project type, build/test/lint commands, key directories, and detected frameworks. Include CI configuration details if present."

Wait for the agent to return its structured report before proceeding.

### Step 5: Load Templates

Read the templates reference:
- [references/templates.md](references/templates.md)

### Step 6: Select Template

Based on the project-scanner report, select the best matching template:

| Scanner Signal | Template |
|---------------|----------|
| React/Vue/Angular + Express/Fastify/Django | `web_app` |
| Express/Fastify/Django/Flask + no frontend | `api` |
| `bin` field in package.json, CLI framework detected | `cli` |
| `main`/`exports` in package.json, `lib/` structure | `library` |
| Monorepo with `packages/` or `apps/` dirs | `fullstack` |
| React Native / Flutter / Expo detected | `mobile` |
| None of the above | `default` |

### Step 7: Generate CLAUDE.md Content

Using the selected template as skeleton, fill in each section from the scanner report:

1. **Project Overview** -- 1-2 sentences: name, tech stack, purpose (from README + package.json)
2. **Commands** -- Exact CLI commands for build, test, lint, dev server (from scanner report)
3. **Architecture** -- 3-7 key directories with one-line purpose each (from scanner report)
4. **Conventions** -- Only non-linter-enforceable rules (infer from tsconfig, eslintrc, editorconfig)
5. **Gotchas** -- Project-specific pitfalls (from scanner report: env files, Docker quirks, CI issues)

Rules for generation:
- Target 40-80 lines, NEVER exceed 100 lines
- Use `##` for sections, `###` for subsections
- Bullet points only, NEVER paragraphs
- `MUST` / `NEVER` for hard constraints
- Every `NEVER` rule MUST include an alternative
- Backticks for all commands, paths, and code references
- No generic advice, no linter tasks, no secrets
- Every command MUST be a copy-pasteable CLI invocation

### Step 8: Run Generation Checklist

Before presenting to the user, verify every item from the best-practices generation checklist:

1. Total length under 80 lines (100 max for complex projects)
2. Every command is a copy-pasteable CLI invocation
3. No generic advice that applies to any project
4. No linter-enforceable rules
5. Every NEVER has a corresponding alternative
6. Architecture lists only non-obvious directories
7. No secrets, credentials, or sensitive data
8. Pointers to detail docs instead of inline copies
9. MUST/NEVER used for all hard constraints
10. Each line passes: "Would removing this line cause Claude to make a mistake?"

If any check fails, revise the content before presenting.

### Step 9: Present Preview

Show the generated CLAUDE.md to the user in a fenced code block:

```
=== Claude Mind Manager -- Generated CLAUDE.md ===

Template: <selected_template>
Lines: <N>
Estimated compliance: ~<X>% (based on line count)

--- Preview ---
<full generated content>
--- End Preview ---

Write to ./CLAUDE.md? (confirm to proceed)
```

### Step 10: Write File

After user confirmation:
1. Write the file to `./CLAUDE.md`
2. Confirm with: `CLAUDE.md written to ./CLAUDE.md (<N> lines, ~<T> tokens)`

## Hard Constraints

- NEVER overwrite an existing CLAUDE.md without `--rewrite` flag
- ALWAYS confirm with the user before writing any file
- ALWAYS run the full generation checklist before presenting the preview
- NEVER include secrets, credentials, or API keys in generated content
- NEVER exceed 100 lines in the generated file
- ALWAYS dispatch the project-scanner agent -- never skip the scan step
