---
name: deep-review
description: |
  Comprehensive code review using 8 parallel specialist agents and an Opus Critic-Agent with
  confidence scoring. Detects security vulnerabilities (OWASP/CWE), performance anti-patterns,
  concurrency issues, resilience defects, API design problems, testing quality smells, code
  maintainability issues, and architecture problems. Covers 31 checks across 8 categories.
  Works with any programming language. Read-only — never modifies source files.

  Use when the user says:
  - "deep-review", "deep review my code"
  - "security review", "full code review", "comprehensive review"
  - "review my code", "code audit", "analyze this file"
  - "/deep-review [path]"
argument-hint: "[file path, directory, or glob pattern]"
context: inherit
allowed-tools:
  - Read
  - Glob
  - Grep
  - Agent
  - Write
  - Bash
---

# /deep-review — Comprehensive Code Review

You perform a deep, multi-dimensional code review using 8 parallel specialist agents and a synthesizing Critic-Agent. This is a **read-only** analysis — no source files are modified.

The pipeline runs at 3 tiers:
- **Tier 1** (deterministic): Pattern-based checks embedded in each agent prompt
- **Tier 2** (parallel): 8 specialized Sonnet agents running simultaneously
- **Tier 3** (synthesis): 1 Opus Critic-Agent filtering, deduplicating, and calibrating

---

## Step 1: Parse Input

Analyze `$ARGUMENTS`:
- **File path given** (e.g., `src/app.py`) — review that single file
- **Directory given** (e.g., `src/`) — review all source files in that directory
- **Glob pattern** (e.g., `**/*.py`) — review matching files
- **No arguments** — ask: "Which file(s) or directory should I review? Provide a path, glob pattern, or paste the code."

Edge cases:
- File < 30 lines: perform the review inline without agents (too lightweight for full pipeline)
- More than 50 files: warn "Large scope detected. This may take several minutes. Continue?" — proceed only on confirmation
- Binary files, node_modules, .git, vendor, dist, build, __pycache__: skip automatically

---

## Step 2: Target Discovery

Use Glob to:
1. Confirm the target files exist and are readable
2. Count total source files and test files
3. Identify the primary programming language(s) from file extensions

Announce:
```
Deep Review starting...
Target: [path]
Source files: [N] | Test files: [N]
Language(s): [detected]
Pipeline: 8 specialist agents (Sonnet) + 1 Critic (Opus)
```

---

## Step 3: Parallel Dispatch — Tier 2 (8 Specialist Agents)

Dispatch ALL 8 specialist agents simultaneously via the Agent tool. Do not wait for one to finish before starting another — dispatch all in a single message.

Use this prompt template for each agent:
```
Review the following target for [CATEGORY] issues.
Target: [TARGET_PATH_OR_DESCRIPTION]
Read all relevant source files using your available tools (Read, Glob, Grep).
Output ONLY a JSON array of findings following your agent protocol exactly.
If no findings, output [].
```

Dispatch all 8 agents in parallel:
1. Agent: security-reviewer — "Review [target] for security vulnerabilities (OWASP/CWE). Output ONLY JSON array."
2. Agent: performance-reviewer — "Review [target] for performance anti-patterns. Output ONLY JSON array."
3. Agent: concurrency-reviewer — "Review [target] for concurrency and thread-safety issues. Output ONLY JSON array."
4. Agent: resilience-reviewer — "Review [target] for error handling and resilience defects. Output ONLY JSON array."
5. Agent: api-reviewer — "Review [target] for API design issues. Output ONLY JSON array."
6. Agent: testing-reviewer — "Review [target] for test quality issues. Test files present: [yes/no]. Output ONLY JSON array."
7. Agent: quality-reviewer — "Review [target] for code quality and maintainability smells. Output ONLY JSON array."
8. Agent: architecture-reviewer — "Review [target] for architectural issues and dependency problems. Output ONLY JSON array."

Show progress while waiting:
```
=== Deep Review Pipeline — Tier 2 ===
[Running 8 agents in parallel...]
  security-reviewer    performance-reviewer   concurrency-reviewer  resilience-reviewer
  api-reviewer         testing-reviewer       quality-reviewer      architecture-reviewer
```

---

## Step 4: Collect Findings and Write to File

After all 8 agents complete:

1. Collect the JSON array output from each agent
2. For each output: parse the JSON (if an agent returned empty `[]` or errored, use `[]` for that agent)
3. Merge all findings into a single JSON array
4. Use Write tool to write the merged array to `.deep-review-findings.json` in the current working directory

Announce count:
```
=== Tier 2 complete ===
Raw findings: [N total from all agents]
Security: [N] | Performance: [N] | Concurrency: [N] | Resilience: [N]
API Design: [N] | Testing: [N] | Maintainability: [N] | Architecture: [N]

Dispatching Critic-Agent (Opus) for synthesis...
```

---

## Step 5: Critic-Agent Dispatch — Tier 3

Dispatch the critic-agent with this prompt:
```
Read .deep-review-findings.json from the current working directory.
Apply your full critic protocol: false positive filtering, deduplication, confidence calibration,
severity validation, and complete report generation.
The review target was: [TARGET_PATH_OR_DESCRIPTION]
Output the complete structured review report.
```

Show:
```
=== Deep Review Pipeline — Tier 3 ===
[Critic-Agent (Opus) running: filtering, deduplication, confidence calibration...]
```

---

## Step 6: Present Report and Clean Up

1. Display the complete structured report from the Critic-Agent in the conversation
2. Delete the temporary file using Bash: `rm -f .deep-review-findings.json`
3. Offer follow-up options:
   - "Focus on a specific category? (security, performance, concurrency, etc.)"
   - "Export this report to a markdown file?"
   - "Review a specific finding in detail?"

---

## Hard Constraints

- NEVER modify any source files under review
- NEVER skip the Critic-Agent step — raw findings are not the final output
- NEVER display raw agent JSON to the user — only the Critic's synthesized report
- ALWAYS dispatch all 8 agents in parallel in a single message (not one at a time)
- ALWAYS clean up .deep-review-findings.json after the review completes
- If an agent fails or returns invalid JSON: use [] for that agent and note it in the summary

---

## Quality Standards Applied

This review uses:
- **OWASP Top 10** (2021) for security classification
- **CWE** identifiers for all vulnerability types
- **NASA JPL Power of Ten** (R1 unbounded recursion, R5 assertions, R7 return values)
- **CERT Secure Coding** standards (ERR33-C, DCL30-C, MSC12-C)
- **MISRA** concepts for variable scope and dead code
- **Fowler/Beck** code smell catalog for maintainability
- **xUnit Test Patterns** for testing quality
- Confidence threshold: 70 (findings below 70 are filtered out; 70-79 marked [REVIEW])
