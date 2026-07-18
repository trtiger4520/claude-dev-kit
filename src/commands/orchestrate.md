---
description: Heavyweight full-orchestration workflow for explicit requests or actual high-risk changes. High token cost.
---

Run the following workflow for this task: $ARGUMENTS

1. **Plan**: Use one planner subagent to inspect the real project and group the request into the smallest dependency-ordered cohesive delivery units with exact files and observable acceptance criteria. Keep product code, tests, and required documentation together. Do not dispatch writers yet.
2. **Approve**: Present the plan, assumptions, risk, writer count, and verification commands. Stop until I explicitly approve it. Architecture-changing ambiguity gets one question with a recommended default; otherwise state assumptions and proceed.
3. **Research only unanswered questions**: After approval, use at most one explorer only when a code-path question remains unanswered. Pass its concise findings through the parent context; do not create repository note files.
4. **Implement**: Assign each approved cohesive unit to an implementer. Use one writer by default, two only for independent units with disjoint files, and one for high-risk work. Serialize dependencies and file conflicts. Parallel implementers run only project-scoped checks.
5. **Capture the boundary**: Invoke the source-boundary skill to create a tracked and non-ignored untracked file snapshot in an operating-system temporary file outside the repository. Review any allowed generated-file patterns before verification.
6. **Verify**: Send the approved plan and complete change set to one verifier. The verifier must inspect the actual diff and run the approved full relevant build and test commands itself without editing source files.
7. **Check the boundary**: Invoke the source-boundary skill again. Any changed source outside reviewed allowed patterns invalidates the verifier result. Do not revert or delete unexpected changes; report them.
8. **Iterate**: On FAIL, send only blocking findings to the original implementer context when available, then re-use the same verifier context. Run the narrowest failed checks after each repair. Stop after two failed repair cycles; after blockers clear, run the complete relevant suite once.
9. **Summarize**: Report changed files, verification evidence, acceptance criteria, agent roles and counts, repair cycles, and follow-ups. Remove only the temporary boundary snapshot created by this workflow.
