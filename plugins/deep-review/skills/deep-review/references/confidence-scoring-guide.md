# Confidence Scoring Guide

Rubric, thresholds, calibration rules, and examples for the Deep Review Critic-Agent.
Used by `critic-agent.md` to calibrate all findings from the 8 specialist agents.

---

## 1. Detection Method — Base Confidence

| Detection Method | Base Confidence Range | Examples |
|---|---|---|
| **Mechanical / Metric-based** | 85–95 | Empty catch body (AST count), LOC > threshold (line count), missing assert in test (AST), unreachable code after return |
| **AST Pattern Match** | 70–85 | String concat in SQL (pattern), hard-coded credential (regex + context), event listener without cleanup |
| **Cross-file / Taint trace** | 60–75 | SQL injection (source to sink across files), SSRF (user input to HTTP call across layers), circular dependency (import graph) |
| **Semantic / Heuristic** | 50–70 | God class responsibility analysis, deadlock from lock ordering inference, API contract change inference |

Start with the base confidence for the detection method, then apply adjustments below.

---

## 2. Confidence Adjustment Rules

| Condition | Adjustment |
|---|---|
| 2+ agents independently detected the same finding | +10 (cross-validation bonus) |
| Evidence snippet is ambiguous (could be safe or unsafe) | -15 |
| Reasoning chain has a logical gap or unsupported assumption | -20 |
| Finding relies on heuristic/semantic detection (not verifiable from code alone) | -10 |
| Referenced function/variable is private/internal (full call graph visible) | +5 |
| Referenced function is public API (external callers unknown) | -10 |
| Finding is in test, mock, or fixture file and pattern may be intentional | -25 |
| Framework or library known to mitigate this pattern (e.g., Django ORM handles SQLi) | -15 |
| Finding was confirmed by reading full function context (not just grep match) | +5 |

**Hard cap:** Maximum confidence = 95. Never assign 100 — static analysis always has uncertainty.

---

## 3. Threshold Rules

| Final Confidence | Action | Label in Report |
|---|---|---|
| 90–95 | Report | [CERTAIN] |
| 80–89 | Report | (no label) |
| 70–79 | Report | [REVIEW] — real but requires manual verification |
| 50–69 | Remove | Filtered out (too uncertain to report) |
| < 50 | Remove | Never reported |

**Filtering counts toward report statistics:**
```
Filtered out: 12 (false positives: 4, low confidence: 7, duplicates: 1)
```

---

## 4. Severity Calibration Matrix

Starting severity is set by the specialist agent. Adjust based on context:

| Context Modifier | Adjustment |
|---|---|
| Code is in test/ or dev/ directory only | -1 level (CRITICAL→HIGH, HIGH→MEDIUM, MEDIUM→LOW) |
| Code is guarded by feature flag (disabled in prod) | -1 level |
| Mitigating control exists elsewhere (WAF, input sanitizer, auth middleware) | -1 level, document in Critic Notes |
| Framework-level protection already active (Django CSRF middleware, SQLAlchemy parameterization) | Consider as false positive or -1 level |
| Issue is in a public-facing endpoint vs. internal-only service | +0 (public already HIGH or CRITICAL by default) |
| Issue is on a hot path (authenticated users can trigger easily) | No change — keep as-is |

**Severity scale:**
- CRITICAL: Directly exploitable, high impact, low difficulty (e.g., unauthenticated SQLi in login endpoint)
- HIGH: Exploitable with some conditions, significant impact
- MEDIUM: Exploitable with specific conditions, moderate impact or limited scope
- LOW: Defense-in-depth improvement, low direct impact

---

## 5. False Positive Rejection Catalog

The following patterns look like vulnerabilities but are SAFE — reject these findings:

### Security False Positives
1. **Parameterized SQL** — `cursor.execute("SELECT * WHERE id=%s", (user_id,))` — NOT SQLi
2. **ORM keyword args** — `User.objects.filter(name=username)` — NOT SQLi
3. **Placeholder credentials** — `password = "changeme"`, `API_KEY = "<YOUR_KEY>"`, `token = "example"` — NOT real credential
4. **Test file credentials** — any credential-like string in `/tests/`, `/test_`, `_test.py`, `_spec.js` — expected test fixtures
5. **Environment variable** — `os.environ["DB_PASSWORD"]` — NOT hard-coded
6. **textContent vs innerHTML** — `element.textContent = userInput` — NOT XSS (auto-encoded)
7. **safe_load** — `yaml.safe_load(data)` — NOT insecure deserialization
8. **subprocess with list** — `subprocess.run(["ls", path])` — NOT command injection

### Performance False Positives
9. **Pre-loaded queryset** — `users = User.objects.select_related('dept').all()` then loop — NOT N+1
10. **Fixed small collection** — nested loop over 2 lists with max 5 elements each — NOT O(n^2) concern
11. **join() for string building** — `", ".join(items)` in loop is O(n) — NOT string concat issue
12. **StringBuilder/join** — already using efficient builder pattern — NOT string concat issue

### Concurrency False Positives
13. **Type-only import** — TypeScript `import type { X }` — NOT runtime circular dependency
14. **Immutable global** — `MAX_RETRIES = 3` at module level — NOT shared mutable state (it's a constant)
15. **Thread-local storage** — variable in `threading.local()` — NOT shared state
16. **Atomic read of primitive** — reading a bool flag set once at startup in Python (GIL-protected) — LOW risk

### Resilience False Positives
17. **Top-level error boundary** — Express `app.use((err, req, res, next) => ...)` — correct catch-all location
18. **Flask global error handler** — `@app.errorhandler(Exception)` at application level — correct
19. **Main entry point** — `if __name__ == '__main__': try: main() except Exception: sys.exit(1)` — correct catch-all
20. **Optional operation** — `except Exception: pass` with clear comment: "Optional telemetry — safe to skip" — acceptable

### Testing False Positives
21. **assertDoesNotThrow** — test verifies no exception is thrown — this IS an assertion
22. **Mock.assert_called** or `verify()` on mock — counts as assertion
23. **Integration test accessing DB** — file in `integration/` or `e2e/` directory — expected external access
24. **pytest.raises** — tests that an exception IS raised — valid assertion

### Architecture False Positives
25. **Barrel file re-export** — `index.ts` that re-exports from multiple modules — NOT circular dependency
26. **Type import only** — TypeScript `import type { Foo }` from a module — no runtime cycle
27. **Configuration import** — `import constants from '../config'` is not a layer violation
28. **Same-layer import** — two services importing from each other's interface (not implementation) — acceptable coupling

---

## 6. Deduplication Rules

Merge findings when these conditions are met:

| Condition | Action |
|---|---|
| Same file:line AND same CWE | Merge — keep higher confidence, add `also_detected_by` |
| Same file AND same root cause AND adjacent lines (within 5 lines) | Merge — keep more specific finding |
| One finding is a symptom of another (e.g., resource leak AND missing finally) | Keep root cause finding, note symptom in remediation |
| Same pattern detected in 3+ locations in same file | Group into single finding with all locations listed |

**Merge format:**
```json
{
  "confidence": 92,
  "also_detected_by": ["performance-reviewer", "quality-reviewer"]
}
```

---

## 7. Calibration Examples

### Example 1 — Confidence Elevated by Cross-Validation
- security-reviewer finds SQL injection at `db.py:42`, confidence 82
- performance-reviewer also notes the raw query as evidence of N+1, confidence 75
- Cross-validation: same location, overlapping root cause
- Critic applies +10 cross-validation bonus to SQL injection finding
- Final confidence: 92 → CERTAIN, reported as CRITICAL

### Example 2 — Finding Filtered by Reasoning Gap
- concurrency-reviewer flags `counter += 1` in `app/config.py:15` as non-atomic increment, confidence 70
- Critic reads the code: `config.py` is loaded once at startup, `counter` is only written during initialization, never in request handling
- Applies -20 for reasoning gap (assumption of multi-thread access not supported)
- Also applies -10 for heuristic detection
- Final confidence: 40 → Below threshold, removed from report

### Example 3 — False Positive Rejected
- security-reviewer flags `db_password = os.environ['DB_PASSWORD']` at `settings.py:8` as hard-coded credential, confidence 75
- Critic identifies this is in the False Positive Rejection Catalog (item 5: environment variable reference)
- Finding rejected — not a real hard-coded credential
- Added to filtered count: false_positives + 1

### Example 4 — Severity Downgraded
- quality-reviewer finds God Class in `tests/helpers/test_utils.py` (test helper, 600 lines), confidence 88
- Critic checks: file is in tests/ directory
- Applies -1 severity level: HIGH → MEDIUM
- Notes in Critic Notes: "God class finding downgraded to MEDIUM — test helper file, not production code"

### Example 5 — REVIEW Label Applied
- resilience-reviewer finds swallowed exception in `background_tasks.py:88`, confidence 74
- Reasoning: exception is caught and logged, but task queue continues (may be intentional)
- Confidence 74 is in 70-79 range → report as [REVIEW]
- Labeled: `MEDIUM | Confidence: 74 [REVIEW]`
- Note: "Manual review recommended — exception handling in background task may be intentional"

### Example 6 — Cross-Agent Deduplication
- security-reviewer finds empty catch in `api/client.py:55` (CWE-1069), confidence 85
- resilience-reviewer finds same empty catch at `api/client.py:55` (CWE-1069), confidence 81
- Critic deduplicates: keep confidence 85 (higher), add `also_detected_by: ["resilience-reviewer"]`
- Apply cross-validation +10: final confidence 95 (capped)
- Report once with note: "Independently detected by 2 agents — high certainty"

---

## 8. Quality Gate Thresholds

| Gate | Conditions | Display |
|---|---|---|
| PASS | 0 CRITICAL findings | `[PASS] No critical findings. Ready for review.` |
| WARN — HIGH | 0 CRITICAL, 3+ HIGH findings | `[WARN — HIGH] N high severity findings. Review recommended before merge.` |
| FAIL — CRITICAL | 1+ CRITICAL findings | `[FAIL — CRITICAL] N critical finding(s) require remediation before merge.` |

The quality gate is informational, not blocking — it guides the developer's prioritization.
Final merge decision always rests with the human reviewer.
