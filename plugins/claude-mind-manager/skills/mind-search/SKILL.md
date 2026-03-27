---
name: mind-search
description: |
  [Mind Manager] Natural language search across all context files, session learnings, and session
  summaries. Searches CLAUDE.md (all scopes), MEMORY.md, .claude/rules/, .claude-mind/
  topic files, learnings, and session summaries. Results sorted by relevance with
  progressive disclosure.

  Use when the user says "search context", "find in memory", "mind search",
  "search for", "what do I know about", "do I have a rule for", "look up",
  "where did I save", "find in claude.md", "search rules", "grep context",
  "what did I remember about", or "/mind-search".
argument-hint: "<query> [--deep]"
context: inherit
allowed-tools: Read Glob Grep
---

# Context Search

Natural language search across all Mind Manager context files.

## Objective

Find relevant information across all context layers by searching file contents, then present results sorted by relevance with progressive disclosure.

## Workflow

### Step 1: Parse Arguments

Extract from `$ARGUMENTS`:
- **query**: everything before `--deep` (trim whitespace)
- **deep mode**: true if `--deep` flag is present

If query is empty, respond: "Usage: /mind-search <query> [--deep]" and stop.

### Step 2: Define Search Locations

Search these locations in order of priority:

| Priority | Location | Description |
|----------|----------|-------------|
| 1 | `./CLAUDE.md`, `./.claude/CLAUDE.md` | Project CLAUDE.md |
| 2 | `~/.claude/CLAUDE.md` | User-level CLAUDE.md |
| 3 | Auto-memory MEMORY.md | `~/.claude/projects/<hash>/memory/MEMORY.md` |
| 4 | `.claude/rules/*.md` | Project rules |
| 5 | `~/.claude/rules/*.md` | User-level rules |
| 6 | `.claude-mind/*.md` | Topic files |
| 7 | `.claude-mind/learnings/*.md` | Session learnings |
| 8 | `.claude-mind/sessions/*.md` | Session summaries |

For MEMORY.md, derive the project hash the same way hooks do:
- Take cwd, replace `/\: ` with `-`, strip leading dashes
- Path: `~/.claude/projects/<hash>/memory/MEMORY.md`

### Step 3: Search Each Location

For each location that exists on disk:

1. Use **Grep** with the query pattern (case-insensitive) to find matches
2. Record: file path, line number, matching line, surrounding context
3. If a location directory doesn't exist, skip silently

### Step 4: Classify and Sort Results

Sort matches into three tiers:

1. **Exact match** — query appears as a whole word/phrase in line content
2. **Partial match** — query terms appear but not as exact phrase
3. **Filename match** — query matches part of the filename but not content

Within each tier, preserve the priority order from Step 2.

### Step 5: Present Results

#### Default Mode (no --deep)

For each match, show:
```
**[file:line]** matching line
  +3 lines surrounding context (1 before, 2 after)
```

Group by file. Show max 20 matches total across all files.

#### Deep Mode (--deep)

For each match, show the full surrounding section:
- Find the nearest `#` heading above the match
- Show everything from that heading to the next heading of same or higher level
- Max 50 lines per section

#### Summary Footer

Always end with:
```
--- Mind Search: X matches in Y files (query: "...") ---
```

If zero matches: "No matches found. Try broader terms or check /mind-status for indexed files."

## Hard Constraints

- NEVER modify any files -- this skill is strictly read-only
- NEVER create new files
- ALWAYS search case-insensitively
- ALWAYS show file paths relative to project root where possible
- ALWAYS include the summary footer with match/file counts
