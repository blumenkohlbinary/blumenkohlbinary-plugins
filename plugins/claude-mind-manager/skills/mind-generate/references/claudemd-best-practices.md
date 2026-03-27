# CLAUDE.md Best Practices Reference

Reference guide for the `/mind:generate` skill. Use this to produce high-quality CLAUDE.md files.

---

## File Hierarchy (4 Levels)

| Priority | Level | Path | Scope |
|----------|-------|------|-------|
| 1 (lowest) | Enterprise | `/Library/Application Support/ClaudeCode/CLAUDE.md` | Org-wide rules |
| 2 | User | `~/.claude/CLAUDE.md` | Personal prefs, all projects |
| 3 | Project | `./CLAUDE.md` or `./.claude/CLAUDE.md` | Team standards (committed to Git) |
| 4 (highest) | Local | `./CLAUDE.local.md` | Personal project overrides (gitignored) |

- Subdirectory CLAUDE.md files load on-demand when Claude reads files in that directory
- Project rules override global rules on conflict
- `.claude/rules/*.md` files load with CLAUDE.md priority; support path-scoped rules via YAML frontmatter

---

## Required Sections

Every generated CLAUDE.md MUST contain these sections:

### 1. Project Overview (H2)
- 1-2 sentences: project name, tech stack, purpose
- Example: `Next.js 14 e-commerce app with App Router, Stripe payments, Prisma ORM.`

### 2. Commands (H2)
- Exact CLI commands, not descriptions
- MUST include: build, test (single + suite), lint, dev server
- Format: `- Build: \`pnpm run build\``
- NEVER write "run the tests" -- write `npm test -- --grep "auth"`

### 3. Architecture (H2)
- 3-7 key directories with one-line purpose each
- Entry point file path
- Core design patterns (MVC, Repository, etc.)
- Data flow and external integrations (APIs, DBs)
- Format: `- \`src/api/\` -- Route handlers (Express)`

### 4. Conventions (H2)
- Only rules a linter cannot enforce
- Use MUST/NEVER for hard constraints
- MUST provide an alternative for every NEVER rule
- Examples: module system, type strictness, naming patterns, import rules

### 5. Gotchas (H2)
- Non-obvious traps and project-specific pitfalls
- Debugging tips, known quirks, timeout values
- Environment-specific issues (Docker, CI, local dev)

### 6. Workflow (H2, optional but recommended)
- Branch naming, commit conventions, PR process
- Pre-commit checks to run
- Pointers to detailed docs via `@docs/filename.md`

---

## Anti-Patterns -- What NOT to Include

NEVER include any of the following:

- **Generic advice**: "Write clean code", "Test your changes", "Keep files organized"
- **Linter tasks**: Indentation, formatting, semicolons -- put these in linter/formatter config
- **Execution plans**: Plans go stale fast -- use MEMORY.md or task files instead
- **Secrets**: API keys, credentials, tokens -- NEVER in a file loaded as context
- **Verbose explanations**: No paragraphs. Use bullet points with MUST/NEVER
- **Redundant info**: Nothing Claude can infer from `package.json`, `tsconfig.json`, or README
- **Full directory listings**: Only list non-obvious directories
- **Preventive rules**: Add rules reactively when Claude makes mistakes, not speculatively

---

## Size Guidelines

Compliance data from SFEIR Institute study:

| Lines | Compliance Rate | Verdict |
|-------|----------------|---------|
| 5 files x 30 lines | 96% | Optimal (modular) |
| <150 lines | 92% | Good |
| 150-200 | Acceptable | Anthropic's recommended ceiling |
| >200 | Degrading | Split into `.claude/rules/` files |
| >400 | ~71% | Critical -- must refactor |

- Target: 40-80 lines for root CLAUDE.md
- Claude's system prompt already contains ~50 instructions; every CLAUDE.md line competes
- Modularize: 5 files at 30 lines each beats 1 file at 150 lines
- Use `@docs/detail.md` references for complex topics

---

## Formatting Rules

- Use `##` (H2) for top-level sections, `###` (H3) for subsections
- Bullet points, NEVER paragraphs
- `MUST` / `NEVER` / `IMPORTANT` for hard constraints -- not "prefer" or "try to"
- Backticks for all commands, paths, config keys, and code references
- Every NEVER rule MUST include an alternative: "NEVER use `any` -- use `unknown` instead"
- One blank line between sections
- No emojis in production CLAUDE.md files (use sparingly if at all)

---

## Generation Checklist

Before outputting a CLAUDE.md, verify:

1. [ ] Total length under 80 lines (100 max for complex projects)
2. [ ] Every command is a copy-pasteable CLI invocation
3. [ ] No generic advice that applies to any project
4. [ ] No linter-enforceable rules
5. [ ] Every NEVER has a corresponding alternative
6. [ ] Architecture lists only non-obvious directories
7. [ ] No secrets, credentials, or sensitive data
8. [ ] Pointers to detail docs instead of inline copies
9. [ ] MUST/NEVER used for all hard constraints
10. [ ] Tested by asking: "Would removing this line cause Claude to make a mistake?"
