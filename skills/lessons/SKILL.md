---
name: lessons
description: Self-improvement loop. Use after a user correction or a discovered mistake to record the failure mode and a prevention rule, and at the start of major work to review past lessons.
---

# Lessons loop

Storage: `~/.claude/lessons.md` for cross-project lessons, `tasks/lessons.md` for project-specific ones. Create the file if missing.

## Recording (after a correction or mistake)

Append one entry:

```markdown
## YYYY-MM-DD <short title>
- Failure mode: what went wrong
- Class: requirements misunderstanding | wrong repo assumption | missing verification | unsafe scope | security oversight
- Detection signal: how it was noticed
- Prevention rule: one concrete, checkable rule
- Tripwire: a proactive check (grep query, test, invariant assertion) that catches recurrence
```

## Reviewing (before major work)

Read the lessons file and list entries relevant to the current task area. Apply their prevention rules and run their tripwires.

Rules:

- Keep entries curated — merge duplicates, delete obsolete ones
- A lesson without a checkable prevention rule is not done; rewrite vague rules ("be careful with X") into decidable ones ("grep for X before Y")
