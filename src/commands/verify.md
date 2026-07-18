---
description: Run independent acceptance verification on the current uncommitted changes
---

Use the verifier subagent to review the current uncommitted changes ($ARGUMENTS if specified, otherwise everything in git status).

Before dispatching, invoke the source-boundary skill to capture tracked and non-ignored untracked file hashes in an operating-system temporary file outside the repository. Review allowed build and test artifact patterns.

The verifier must inspect the actual diff, run the approved project build and test commands itself, and report PASS or actionable FAIL with evidence. It must not modify or repair source files.

After it returns, invoke the source-boundary skill to verify the snapshot. Any unexpected source change invalidates PASS. Do not revert, delete, or repair verifier changes; report them and wait for my decision. Remove only the temporary snapshot created for this verification.
