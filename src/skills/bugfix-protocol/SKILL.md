---
name: bugfix-protocol
description: Structured bug-fixing loop — reproduce, failing test first, isolate root cause, fix, regression guard. Use when handling a bug report, a failing test, or unexpected runtime behavior.
---

# Bug-fixing protocol

Work through these stages in order. Do not skip to "fix".

1. **Reproduce** reliably — produce a single command or script that reproduces (preferred over multi-step manual sequences)
2. **Classify** the bug: data-dependent / environment-dependent / concurrency-timing / integration boundary. Ask "why now?" — what changed recently (dependency, config, flag, data shape)
3. **Localize** the failing layer (UI, API, DB, network, build tooling), then **reduce** to a minimal failing case
4. **Regression test first**: when possible write the failing test that demonstrates the bug before applying the fix
5. **Fix the root cause**, not the symptom. No broad refactors as "fixes"
6. **Guard and verify**: regression test passes, then verify end-to-end against the original report

Rules:

- Each attempt must be hypothesis-driven; never try random fixes
- Preserve the minimal artifact: failing test name, command, input payload, stack trace snippet
- After 2 failed attempts on the same error: stop, list hypotheses and eliminated causes, report back
- Timing-dependent bugs need at least one race-focused or stress test

Report format: Repro steps / Expected vs actual / Root cause / Fix / Regression coverage / Verification performed
