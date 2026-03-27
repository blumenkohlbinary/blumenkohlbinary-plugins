# Quality Criteria — Optimization Patterns

## Optimization Categories

### 1. Shortening (Lossless Compression)
Verbose lines that convey the same meaning in fewer words.

**Before:** "When you are writing TypeScript code, you should always make sure to use the strict mode setting"
**After:** "TypeScript: MUST use strict mode"

**Savings:** ~60% token reduction per line (SFEIR: 22.5 → 9 tokens/line after optimization)

### 2. Modularization (CLAUDE.md → Rules)
Extract file-scoped sections into `.claude/rules/` files with `globs:` frontmatter.

**Before (in CLAUDE.md):**
```markdown
## TypeScript Conventions
- Use strict mode
- No any types
- Prefer interfaces over type aliases
- Use barrel exports in libs/
```

**After (.claude/rules/typescript.md):**
```yaml
---
globs: src/**/*.ts, src/**/*.tsx
---
# TypeScript Conventions
- MUST use strict mode — no `any` types, use `unknown` instead
- Prefer interfaces over type aliases
- Barrel exports (`index.ts`) in every `libs/` directory
```

**Savings:** Lines removed from always-loaded CLAUDE.md, rule only loads when *.ts files accessed. SFEIR data: 96% compliance with 5 rule files vs 92% with single file.

### 3. Progressive Disclosure (Content → @Import)
Move detailed documentation to separate files referenced via @import.

**Before (in CLAUDE.md):**
```markdown
## Database
- PostgreSQL 16 with Prisma ORM
- Migrations: npx prisma migrate dev --name description
- Seeds: npx prisma db seed
- Schema: prisma/schema.prisma
- Connection: DATABASE_URL in .env
- Pool size: 10 (configurable via connection_limit)
[15 more lines of database details]
```

**After (in CLAUDE.md):**
```markdown
## Database
PostgreSQL 16, Prisma ORM. Details: @docs/database.md
```

**Savings:** ~18 lines removed from always-loaded CLAUDE.md. Detail file loads only when Claude needs it.

### 4. Deduplication (Cross-File)
Same information repeated in multiple files.

**Common duplicates:**
- Tech stack listed in both CLAUDE.md and MEMORY.md
- Build commands in CLAUDE.md and also in MEMORY.md (auto-learned)
- Architecture notes duplicated between global and project CLAUDE.md

**Rule:** Information belongs in ONE place:
- Project conventions → CLAUDE.md
- Learned patterns → MEMORY.md
- File-scoped rules → .claude/rules/
- Personal preferences → ~/.claude/CLAUDE.md

### 5. Topic File Offloading (MEMORY.md → Topic Files)
Move detailed memory entries to topic files when MEMORY.md approaches 200 lines.

**Candidates for offloading:**
- Debugging histories (→ `memory/debugging.md`)
- API conventions (→ `memory/api-conventions.md`)
- Architecture notes (→ `memory/architecture.md`)

**MEMORY.md becomes an index** pointing to topic files. Topic files load on-demand only.

### 6. CLAUDE.local.md Migration
Migrate deprecated CLAUDE.local.md content to @import pattern.

**Before:**
```
./CLAUDE.local.md (loaded always, deprecated)
```

**After:**
```
~/.claude/my-project-instructions.md (loaded via @import)
```

Add to project CLAUDE.md: `Personal settings: @~/.claude/my-project-instructions.md`

## Anti-Patterns to Detect

| Anti-Pattern | Detection | Fix |
|-------------|-----------|-----|
| Linter tasks in CLAUDE.md | "format", "indent", "eslint" rules | Move to hooks or remove |
| Generic advice | "Write clean code", "Use meaningful names" | Remove entirely |
| Execution plans | "TODO", "Step 1: ...", outdated plans | Remove or move to plans/ |
| Secrets | API keys, tokens, passwords | Remove immediately, warn user |
| One-off fixes | "Fixed bug in commit abc123" | Remove |
| Verbose explanations | Multi-sentence descriptions | Compress to one-liners |

## Korrektur-Flywheel Pattern

When using `--error` mode in `/mind:remember`:

**Input:** "Claude used console.log instead of logger"
**Output rule:** `- NEVER use console.log — use libs/core/logger instead`

**Input:** "Claude created a new utility file instead of using the existing one"
**Output rule:** `- MUST check for existing implementations before creating new files`

Format: `NEVER <bad pattern> — <alternative>` or `MUST <required pattern>`
