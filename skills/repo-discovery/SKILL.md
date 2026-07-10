---
name: repo-discovery
description: Systematic playbook for entering an unfamiliar repository. Use when starting work in a codebase not yet explored in this session, before planning any change.
---

# Repository discovery playbook

Follow this sequence before planning changes in an unfamiliar repo. Prefer delegating steps 2-4 to the explorer subagent to keep output out of the main context.

1. **Entry points**: README, CONTRIBUTING, Makefile, package.json / *.csproj / *.sln, build scripts, CI pipelines, service manifests (Dockerfile, k8s yaml)
2. **Architecture cues**: folder structure, module boundaries, DI registration, dependency graph hints
3. **Closest tests**: search for tests covering the feature area — treat them as executable documentation. Authority ranking when sources disagree: existing tests > public interfaces/types > docs/comments > implementation details
4. **Ownership conventions**: lint rules, formatter configs, analyzers (.editorconfig, eslint, StyleCop), codegen expectations
5. **Local verification loop**: identify the fastest command that gives signal (targeted test > full build)

Deliverable — write a short list to `tasks/notes.md` (create it if missing):

- authoritative files (paths)
- key commands (build, test, lint, run)
- discovered invariants (e.g. "IDs are ULIDs", "timestamps are UTC", "this endpoint is idempotent")

`tasks/notes.md` is the single shared location: the planner and every implementer read it, so invariants survive across subagent boundaries. Keep it curated — remove stale entries when they no longer hold.
