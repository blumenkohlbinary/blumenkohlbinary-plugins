# Context File Guide — Complete Catalog

All context files Claude Code loads, organized by load timing and scope.

## Always Loaded at Session Start (Budget-Critical)

| File | Path Pattern | Scope | Limit | Notes |
|------|-------------|-------|-------|-------|
| Global CLAUDE.md | `~/.claude/CLAUDE.md` | All projects | <200 lines recommended | Lowest priority in hierarchy |
| Project CLAUDE.md | `./CLAUDE.md` or `./.claude/CLAUDE.md` | Team (Git) | <200 lines recommended | Overrides global |
| Local CLAUDE.md | `./CLAUDE.local.md` | Personal (gitignored) | — | **Deprecation indicated** — migrate to @imports |
| Enterprise CLAUDE.md | `/Library/Application Support/ClaudeCode/CLAUDE.md` (macOS), `%PROGRAMDATA%\ClaudeCode\CLAUDE.md` (Win) | Org-wide | — | Highest priority, read-only |
| MEMORY.md | `~/.claude/projects/<hash>/memory/MEMORY.md` | Per-project | **200 lines hard limit** | Truncated from bottom silently |
| Rules (matching) | `.claude/rules/*.md` | Team (Git) | — | Only when `globs:` matches current files |
| User Rules | `~/.claude/rules/*.md` | Personal | — | `paths:` field does NOT work here — use `globs:` |

## Loaded On-Demand (Lazy)

| File | Path Pattern | Trigger | Notes |
|------|-------------|---------|-------|
| Subdirectory CLAUDE.md | `./subdir/CLAUDE.md` | When Claude reads files in that directory | Powerful for monorepos |
| Topic Files (auto) | `~/.claude/projects/<hash>/memory/*.md` | When Claude needs them | No size limit, but <200 lines recommended |
| Topic Files (plugin) | `<cwd>/.claude-mind/*.md` | On-demand by Mind Manager skills | Plugin-managed, portable |
| Backups (plugin) | `<cwd>/.claude-mind/backups/` | Pre-compact hook | Rotated, last 5 kept |
| @Import targets | `@docs/file.md`, `@~/path` | Referenced from CLAUDE.md | Depth 5, relative resolution, codeblocks excluded |
| Skill bodies | `skills/*/SKILL.md` body | When skill is relevant | Frontmatter always loaded (~100 tokens) |

## Configuration Files (No Direct Token Cost)

| File | Path Pattern | Function |
|------|-------------|----------|
| Global settings | `~/.claude/settings.json` | Permissions, hooks, model, env, claudeMdExcludes |
| Team settings | `.claude/settings.json` | Team config (in Git) |
| Local settings | `.claude/settings.local.json` | Personal config (gitignored) |
| .claudeignore | `./.claudeignore` | Exclude files from Claude's view (saves up to 50% tokens) |
| MCP config (project) | `./.mcp.json` | Project MCP servers (~14K tokens per server for tool definitions) |
| MCP config (global) | `~/.claude/mcp_settings.json` | Global MCP servers |
| Plugin manifest | `.claude-plugin/plugin.json` | Plugin metadata and component paths |

## Extension Files

| Type | Project Path | User Path |
|------|-------------|-----------|
| Skills | `.claude/skills/*/SKILL.md` | `~/.claude/skills/*/SKILL.md` |
| Commands (legacy) | `.claude/commands/*.md` | `~/.claude/commands/*.md` |
| Agents | `.claude/agents/*.md` | `~/.claude/agents/*.md` |
| Plans | — | `~/.claude/plans/*.md` |

## Experimental / Unconfirmed

| File | Path Pattern | Status |
|------|-------------|--------|
| Agent Memory (project) | `.claude/agent-memory/<name>/` | Unconfirmed, may require feature flag |
| Agent Memory (local) | `~/.claude/agent-memory-local/<name>/` | Unconfirmed |
| Agent Memory (user) | `~/.claude/agent-memory/<name>/` | Unconfirmed |

## Project Hash Encoding

Project directories under `~/.claude/projects/` use path-to-hash encoding:

| Character | Replacement |
|-----------|-------------|
| `/` | `-` |
| `\` | `-` |
| `:` | `-` |
| Space | `-` |
| `(` `)` | `-` |

Example: `C:\Users\HackJ\My App` → `C--Users-HackJ-My-App`

Leading dashes from drive letter colon are collapsed.

**Caveat:** Ambiguity exists — `My-App` and `My App` produce the same hash. Best-effort decoding only.

## @Import Syntax Reference

```markdown
@docs/architecture.md          # Relative to importing file
@~/my-instructions.md          # Home directory
@~/.claude/shared-rules.md     # Global personal file
```

- Depth limit: 5 levels of nesting
- Imports inside markdown codeblocks: NOT evaluated
- External imports: show one-time approval dialog
- Non-existent targets: silently ignored (no error)
- Glob patterns (`@docs/*.md`): NOT supported — single files only
- **Pitfall:** Claude must be told WHEN and WHY to read the file — just referencing is not enough

## Additional Loading: --add-dir

```bash
CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1 claude --add-dir /other/project
```

Without this env var, CLAUDE.md from `--add-dir` directories are NOT loaded.
