---
description: Run independent acceptance verification on the current uncommitted changes
---

Use the verifier subagent to review the current uncommitted changes ($ARGUMENTS if specified, otherwise everything in git status).

The verifier must run the project's build and test commands itself and report PASS or FAIL with evidence. If FAIL, list the fixes needed but do not apply them — wait for my decision.
