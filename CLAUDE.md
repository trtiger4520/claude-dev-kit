# Global engineering rules

Bias toward caution over speed. For trivial tasks, use judgment.

## Think before coding

- State assumptions explicitly. If multiple interpretations exist, present them — don't pick silently
- Ask only when the answer changes architecture (sync vs async, new table vs new column). Ask exactly one question with a recommended default and what changes based on the answer. Otherwise state the assumption and proceed
- Never invent file paths, APIs, or config keys — verify in-repo before asserting. Treat memory as untrusted

## Simplicity and scope

- Minimum code that solves the problem. No speculative features, no abstractions for single-use code, no unrequested configurability
- Touch only what you must. Match existing style. Don't refactor or "improve" adjacent code; log follow-ups as TODOs instead
- Remove imports/variables that YOUR changes made unused; leave pre-existing dead code alone
- The test: every changed line traces directly to the user's request

## Delegation (subagents)

- If native dynamic orchestration (e.g. Ultracode dynamic workflows) is active, let it decide how to split work; use the flow below only when explicitly requested or when strict role isolation / verification boundaries are needed
- Route by risk, not file count:
  - single-agent: low risk, familiar path, roughly 1-3 files — do it directly
  - plan-light: moderate size, still low risk — short plan, single implementer, narrow verification
  - full orchestration (planner → implementer(s) → verifier): high risk, cross-module impact, unfamiliar code, independent verification required, or the user explicitly asks
- Hard trigger (no discretion): tasks touching auth/authorization/roles/permissions/Identity, payments/billing, data migrations/schema, secrets/crypto, multi-tenant boundaries, or infra/deploy pipelines are high risk BY DEFINITION — invoke the risky-change skill before implementing and use full orchestration. Keyword match decides, not your judgment of the change's size
- Large-scale flat fan-out (many parallel subtasks, ultracode-style): only via the /ultra command, never self-triggered — gates and topology rules live in commands/ultra.md
- Read-only research fans out: run up to 3-6 explorers in parallel when questions are independent. Write subtasks stay low-concurrency: group by file conflicts, at most 2 parallel writers, single writer in high-risk areas
- Parallel implementers run only project-scoped builds/tests (single project, filtered tests) — the full solution build/test runs once, in the verify stage
- Shared project invariants live in `tasks/notes.md`; planner and implementers read it when present
- Code search or tracing across many files: use the explorer subagent, keep raw search output out of the main context
- Keep subagent reports under ~300 words; summarize before continuing. Every subagent report ends with a `Runtime:` line (model, and effort if known) for later analysis

## Verification

- "Done" requires evidence: the command was actually run in this session and its output observed. Never accept an implementer's self-report — the verifier must re-run checks itself
- Use the narrowest verification command during iteration (single test file > full suite); run the full relevant suite once at the end
- If verification cannot be run, say so explicitly and provide the exact command to run later
- Bug fixes: when possible write the failing test that reproduces the bug first, then make it pass

## Failure handling

- On unexpected failure: stop adding features, preserve the error output, return to diagnosis
- Every fix attempt must be hypothesis-driven. After 2 failed attempts on the same error, stop modifying and report current hypotheses plus eliminated causes
- On verifier FAIL: fix only the listed items, re-verify, at most 2 iterations, then escalate to the user

## Conventions

- 註解、提交訊息、PR 訊息結尾不使用句號 `。`
- 提交訊息不填寫 Co-Authored-By
- Multi-line commit messages: use multiple `-m` flags or `git commit -F -`; never embed literal `\n` in a single quoted string
