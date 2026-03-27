---
name: mind-backup
description: |
  [Mind Manager] Manually backup or restore context files (MEMORY.md, CLAUDE.md,
  active-context.md, rules, transcript). List existing backups with timestamps and
  sizes. Restore from a specific backup with confirmation. Backups stored in
  .claude-mind/backups/ with rotation (last 5 per type, last 3 transcripts).

  Use when the user says "backup my context", "save a backup", "mind backup",
  "backup before changes", "list backups", "restore backup", or "/mind-backup".
argument-hint: "[--list | --restore TIMESTAMP]"
context: inherit
allowed-tools: Read Glob Grep Bash Write
---

# Manual Context Backup

Create, list, or restore backups of all context files.

## Objective

On-demand backup of MEMORY.md, CLAUDE.md, active-context.md, rule files, and transcript.
Optionally list existing backups or restore from a specific timestamp.

## Workflow

### Step 1: Parse Arguments

Check `$ARGUMENTS`:
- `--list` — list existing backups without creating new ones
- `--restore TIMESTAMP` — restore from a specific backup (e.g., `--restore 20260327-160850`)
- No arguments — create a new backup

### Step 2: Determine Paths

Derive the project hash to locate MEMORY.md:
```
HASH = cwd with /\: and spaces replaced by hyphens, leading hyphens stripped
MEMORY_PATH = ~/.claude/projects/<HASH>/memory/MEMORY.md
```

Backup directory: `<cwd>/.claude-mind/backups/`

### Step 3A: List Mode (--list)

Read the `.claude-mind/backups/` directory. For each file, show:
- Type (MEMORY, CLAUDE, active-context, transcript, rules)
- Timestamp (from filename)
- File size

Group by timestamp, display as table:

```
=== Backups in .claude-mind/backups/ ===

| Timestamp           | MEMORY | CLAUDE | Context | Transcript | Rules |
|---------------------|--------|--------|---------|------------|-------|
| 2026-03-27 16:08:50 | 2.1 KB | 1.8 KB | 0.5 KB  | 4.2 MB     | —     |
| 2026-03-27 15:30:12 | 2.0 KB | 1.8 KB | 0.4 KB  | 3.1 MB     | —     |
| 2026-03-27 14:00:00 | 1.9 KB | 1.7 KB | 0.3 KB  | —          | —     |

Total: 3 backup sets, 12.9 MB disk usage
```

Exit after displaying.

### Step 3B: Restore Mode (--restore TIMESTAMP)

1. Find all backup files matching the timestamp pattern
2. Show what will be restored with current vs backup sizes:

```
=== Restore from 2026-03-27 16:08:50 ===

| File | Current | Backup | Action |
|------|---------|--------|--------|
| MEMORY.md | 45 lines | 42 lines | Overwrite |
| CLAUDE.md | 66 lines | 60 lines | Overwrite |
| active-context.md | 25 lines | 30 lines | Overwrite |
| Transcript | (current session) | 4.2 MB | Copy to .claude-mind/restored/ |

WARNING: This will overwrite current context files!
Proceed? [Yes / No]
```

3. On confirmation:
   - First create a backup of CURRENT files (safety net)
   - Copy backup MEMORY.md to `~/.claude/projects/<HASH>/memory/MEMORY.md`
   - Copy backup CLAUDE.md to `./CLAUDE.md`
   - Copy backup active-context.md to `.claude/rules/active-context.md`
   - Transcript: copy to `.claude-mind/restored/` (NOT to Claude's transcript path — read-only)

4. Report what was restored.

### Step 3C: Create Mode (default)

Back up these files if they exist. For each file that does NOT exist, include a note in the report (e.g., "MEMORY.md: not found — no backup"):

1. **MEMORY.md** from `~/.claude/projects/<HASH>/memory/MEMORY.md`
2. **CLAUDE.md** from `./CLAUDE.md` or `./.claude/CLAUDE.md`
3. **active-context.md** from `.claude/rules/active-context.md`
4. **All rule files** from `.claude/rules/*.md` (except active-context.md) — bundled as `rules-TIMESTAMP.tar` or concatenated as `rules-TIMESTAMP.md`
5. **Transcript** — find via: `ls -t ~/.claude/projects/<HASH>/*.jsonl 2>/dev/null | head -1` (most recent JSONL file for this project). If no JSONL found, try `ls -t ~/.claude/projects/<HASH>/transcript*.jsonl 2>/dev/null`. NOTE: Do NOT use `/tmp/claude-transcript-*` — that path does not exist on Windows.

Use timestamp format: `YYYYMMDD-HHMMSS`
Destination: `.claude-mind/backups/`

### Step 4: Rotate

Keep last `MIND_BACKUP_KEEP_COUNT` (default 5) backups per type.
Transcripts: keep last `MIND_TRANSCRIPT_KEEP_COUNT` (default 3).
Delete oldest beyond the limit.

### Step 5: Report

```
=== Backup Complete ===

Backed up 4 files to .claude-mind/backups/:
- MEMORY-20260327-160850.md (2.1 KB)
- CLAUDE-20260327-160850.md (1.8 KB)
- active-context-20260327-160850.md (0.5 KB)
- transcript-20260327-160850.jsonl (4.2 MB)

Rotation: 5/5 MEMORY, 4/5 CLAUDE, 5/5 context, 3/3 transcript
```

## Hard Constraints

- NEVER delete source files during backup
- NEVER restore without user confirmation
- ALWAYS create a safety backup of current files before restoring
- ALWAYS rotate after backup (prevent unbounded growth)
- Transcript files are NEVER automatically loaded into context — only shown in --list or copied on --restore
- ALWAYS show file sizes to help user understand disk usage
