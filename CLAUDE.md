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

- Task touches 3+ files or has 3+ distinct steps: planner subagent → implementer subagent(s) → verifier subagent
- Run implementers in parallel only when subtasks share no files and no dependency. Parallel implementers run only project-scoped builds/tests (single project, filtered tests) — the full solution build/test runs once, in the verify stage
- Shared project invariants live in `tasks/notes.md`; planner and implementers read it when present
- Code search or tracing across many files: use the explorer subagent, keep raw search output out of the main context
- Keep subagent reports under ~300 words; summarize before continuing

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
