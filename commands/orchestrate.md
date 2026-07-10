---
description: Plan → parallel subtasks → independent verification workflow for a feature or fix
---

Run the following workflow for this task: $ARGUMENTS

1. **Plan**: Use the planner subagent to decompose the task into subtasks with acceptance criteria and a dependency order. Show me the plan before continuing. Stop to ask only for ambiguity that changes the architecture — one question with a recommended default; for everything else state the assumption and proceed.
2. **Research (if needed)**: For subtasks that require understanding unfamiliar code, use the explorer subagent to research first. Run independent research in parallel. Record any invariants the explorer flags into `tasks/notes.md`.
3. **Implement**: For each subtask, use the implementer subagent. Launch subtasks with no dependency between them and no shared files in parallel; run dependent subtasks in sequence, passing forward only the relevant results. Parallel implementers run only project-scoped builds/tests — never the full solution build.
4. **Verify**: After all subtasks complete, use the verifier subagent to independently check the full change set against the plan's acceptance criteria. This is where the full solution build and full relevant test suite run, exactly once.
5. **Iterate**: If the verifier reports FAIL, send only the failing items back to the implementer subagent, then re-verify. Repeat at most twice; if still failing, stop and report the remaining issues to me.
6. **Summarize**: Report changed files, verification evidence, and any follow-ups.

Do not skip step 4 even if the implementation looks trivially correct.
