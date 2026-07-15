---
description: Ultracode-style large-scale flat fan-out (many parallel subagents). Very high token cost — run only when explicitly invoked and every gate below passes
---

Run a large-scale fan-out for this task: $ARGUMENTS

## Gates — check all before spawning anything

If any gate fails, say which one and fall back to /orchestrate (or handle directly):

1. **Explicit invocation only.** This command was typed by the user. Never trigger large fan-out on your own judgment, and never treat one invocation as standing permission for later turns.
2. **The task decomposes into at least 4 independent subtasks** — no shared files, no dependency order between them. Fewer independent units → /orchestrate is cheaper and sufficient.
3. **Hard-trigger areas** (auth/authorization/Identity, payments/billing, migrations/schema, secrets/crypto, multi-tenant, infra/deploy — per CLAUDE.md): the risky-change skill must run first, and files in those areas are excluded from parallel writing — they get a single implementer in a sequential tail stage after the fan-out.
4. **State the expected cost** (rough agent count and that this is a high-token run) in the plan you show before spawning implementers.

## Topology — one layer only, the orchestrator owns every spawn

Subagents cannot spawn subagents (implementer explicitly disallows the Agent tool). Never instruct an implementer to "have a verifier check this" or "send an explorer first" — it can't. Keep the tree flat: the main conversation (or a workflow script) spawns every agent, and per-subtask sequencing (research → implement → verify) is expressed as pipeline stages the orchestrator drives, not as nesting.

## Execution

Prefer the checked-in workflow when the harness provides the Workflow tool: run the saved `ultra-fanout` workflow (`workflows/ultra-fanout.js`, installed to `~/.claude/workflows/`) with the planner's subtask list as `args` — do not author a new orchestration script when the saved one fits. It pipelines research → implement → per-item verify per subtask with worktree isolation on every implementer; merge, global verify, and the repair loop stay in this conversation. If the saved workflow is missing, author an equivalent script inline. If the harness has no Workflow tool at all, fan out with the Agent tool directly: batch parallel calls in a single message, cap concurrent writers at ~8, and group subtasks so no two concurrent implementers share files.

Stages:

1. **Plan once**: planner subagent produces the subtask list, acceptance criteria, and file ownership per subtask. Show me the list and the planned fan-out width before spawning implementers.
2. **Research fan-out** (inside the workflow): explorers, read-only, as wide as the independent questions require. Record invariants into `tasks/notes.md`.
3. **Implement fan-out** (inside the workflow): one implementer per subtask in an isolated worktree, project-scoped builds/tests only, report must state its worktree path.
4. **Per-item verify** (inside the workflow): one verifier per completed subtask, running the checks inside that subtask's worktree against its own acceptance criteria.
5. **Merge**: after the workflow returns, fold each passing worktree's changes back in order; if a merge conflicts, discard that item's result and re-run it sequentially on the merged state.
6. **Global verify barrier**: a single verifier runs the FULL solution build and full relevant test suite on the merged tree, exactly once.
7. **Repair loop**: send only FAIL items to a fresh implementer, re-verify; at most 2 rounds, then stop and report remaining issues to me.

## Report

Changed files, verification evidence, follow-ups. Then append one line to `tasks/metrics.log` (create it if missing):
`<ISO date> | cmd=ultra | subtasks=<n> | explorers=<n> | implementers=<n> | verifiers=<n> | models=<from Runtime lines> | verifier=<PASS|FAIL> | repair_iterations=<n>`

Do not skip stage 6 even if every per-item verify passed.
