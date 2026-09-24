# Global engineering rules

Bias toward caution over speed. For trivial tasks, use judgment.
Traditional Chinese (Taiwan, zh-TW) as the primary language.

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

- Classify the lane before delegating, but report it only when a subagent is dispatched or the complete orchestration workflow is used
- Route by actual change risk, not file count, step count, cross-module scope, cross-platform scope, or unfamiliar paths:
  - `single-agent`: known paths, local edits, routine low-risk work, or work covered by deterministic checks — the main agent completes it directly
  - `plan-light`: non-high-risk work that benefits from a short plan — default to zero subagents and select at most one of explorer, implementer, or verifier
  - `orchestrate-heavy`: use only when the user explicitly requests the complete workflow, or the requested change modifies security-sensitive behavior or controls, persisted data or schema, production state, core architecture, or a breaking public contract
- Keep read-only security, migration, deployment, and architecture analysis in `single-agent` or `plan-light`; independent verification alone is verifier-only `plan-light`
- A keyword match marks a potential high-risk domain but never decides the lane by itself. Invoke the risky-change skill and use `orchestrate-heavy` only when the requested write actually changes high-risk behavior
- Default to no delegation and perform limited local exploration first. Delegate only when at least two signals are present:
  - the work can complete independently without frequent context exchange
  - it produces substantial search results, logs, or intermediate evidence
  - it has explicit inputs, a stop condition, and a concise output format
  - the main agent has other independent work to perform concurrently
  - delegation isolates substantial context noise
  - the result has observable or deterministic verification
- Do not delegate known small edits, work whose context the main agent already holds, work requiring continuous design decisions, work the main agent must fully repeat, or merely running build, lint, or existing test commands
- Escalate limited exploration to one explorer only when the code path does not converge quickly
- Give an implementer one bounded cohesive delivery unit with stable ownership and observable acceptance criteria; keep product code, tests, and required documentation together
- Use the minimum number of writers: one by default, at most two for independent units with disjoint files, and one for high-risk work
- Every `orchestrate-heavy` workflow uses one planner, explicit user approval before any writer, and one independent verifier. One explorer is optional only for an unanswered code-path question after approval
- Use a verifier only when the user explicitly requests independent verification, the change is high risk, or deterministic checks cannot cover material semantic risk
- Native dynamic workflows take ownership only when explicitly invoked or when the job genuinely outgrows a handful of subagents; availability alone does not bypass this gate
- Ask subagents to report only what the parent needs to act on, citing path:line instead of pasting code; summarize a long report before continuing

## Verification

- "Done" requires evidence: the relevant command was actually run in this session and its output observed
- Prefer deterministic verification in this order: compiler, formatter or linter, targeted tests, full relevant tests, then independent semantic review when materially valuable
- Do not accept an implementer's self-report as independent verification evidence; when a verifier is required it must re-run approved checks itself
- Use the narrowest verification command during iteration (single test file > full suite); run the full relevant suite once at the end
- If verification cannot be run, say so explicitly and provide the exact command to run later
- Bug fixes: when possible write the failing test that reproduces the bug first, then make it pass

## Failure handling

- On unexpected failure: stop adding features, preserve the error output, return to diagnosis
- Every fix attempt must be hypothesis-driven. After 2 failed attempts on the same error, stop modifying and report current hypotheses plus eliminated causes
- On verifier FAIL: return only blocking items to the original implementer when available, reuse the verifier context, re-run the narrowest failed checks, and stop after 2 failed repair cycles

## Conventions

- All replies will be conducted in Traditional Chinese (zh-TW) as the primary language
- Do not end comments, commit messages, or pull request messages with the Chinese full stop `。`
- Do not add `Co-Authored-By` trailers to commits
- Multi-line commit messages: use multiple `-m` flags or `git commit -F -`; never embed literal `\n` in a single quoted string

## Code comments

- Default to no comments. If a line needs explaining, rename it instead
- Write a comment only for: why this approach over the obvious one; a non-obvious constraint or workaround with its source (issue number, spec link); the origin of an algorithm or formula; preconditions or side effects the caller must know
- Never: restate the next line, section markers (`// init`), change narration ("changed X to Y" belongs in the commit), commented-out code
- Match the comment density of the file being edited; do not add comments to untouched lines
- Chinese comments: Taiwan usage, no `。` at end

<!-- CODEGRAPH_START -->

## CodeGraph

In repositories indexed by CodeGraph (a `.codegraph/` directory exists at the repo root), reach for it BEFORE grep/find or reading files when you need to understand or locate code:

- **MCP tool** (when available): `codegraph_explore` answers most code questions in one call — the relevant symbols' verbatim source plus the call paths between them, including dynamic-dispatch hops grep can't follow. Name a file or symbol in the query to read its current line-numbered source. If it's listed but deferred, load it by name via tool search.
- **Shell** (always works): `codegraph explore "<symbol names or question>"` prints the same output.

If there is no `.codegraph/` directory, skip CodeGraph entirely — indexing is the user's decision.

<!-- CODEGRAPH_END -->
