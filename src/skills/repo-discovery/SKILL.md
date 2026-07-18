---
name: repo-discovery
description: Systematic playbook for a large unfamiliar repository when limited parent exploration has not converged and further discovery is needed before planning.
---

# Repository discovery playbook

Follow this sequence after limited parent exploration has not converged. Use one explorer only when the delegation gate is satisfied and the remaining search would create substantial context noise.

1. **Entry points**: README, CONTRIBUTING, Makefile, package.json / *.csproj / *.sln, build scripts, CI pipelines, service manifests (Dockerfile, k8s yaml)
2. **Architecture cues**: folder structure, module boundaries, DI registration, dependency graph hints
3. **Closest tests**: search for tests covering the feature area — treat them as executable documentation. Authority ranking when sources disagree: existing tests > public interfaces/types > docs/comments > implementation details
4. **Ownership conventions**: lint rules, formatter configs, analyzers (.editorconfig, eslint, StyleCop), codegen expectations
5. **Local verification loop**: identify the fastest command that gives signal (targeted test > full build)

Return a concise report to the parent containing:

- authoritative files (paths)
- key commands (build, test, lint, run)
- discovered invariants (e.g. "IDs are ULIDs", "timestamps are UTC", "this endpoint is idempotent")

The parent passes only relevant invariants and commands to later contexts. Do not create repository note files automatically.
