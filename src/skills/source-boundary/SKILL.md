---
name: source-boundary
description: Capture and verify tracked plus non-ignored untracked file hashes around an independent verifier so unexpected source writes invalidate its result without automatically reverting anything.
---

# Source boundary

Use this skill only around an independent verifier or another explicitly read-only agent that must run build or test commands.

## Workflow

1. Create a unique snapshot path in the operating-system temporary directory outside the repository
2. Capture the repository before dispatch:
   - PowerShell: `scripts/Test-SourceBoundary.ps1 -Mode Capture -SnapshotFile <path> -Repository <repo>`
   - Bash: `bash scripts/Test-SourceBoundary.sh --capture --snapshot-file <path> --repository <repo>`
3. Review and record any repository-relative generated-file patterns that may legitimately change
4. After the verifier returns, verify the same snapshot and pass each allowed pattern explicitly
5. Treat any other tracked or non-ignored untracked change as a boundary violation that invalidates PASS
6. Do not revert, delete, or repair unexpected changes; report them to the user
7. Remove only the unique temporary snapshot created for this workflow

The scripts intentionally ignore files already excluded by the repository's ignore rules.
