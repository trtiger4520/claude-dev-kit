---
name: risky-change
description: Mandatory protocol before implementing an actual change to security-sensitive behavior or controls, payments, persisted data or schema, secrets or cryptography, tenant boundaries, or production deployment state. Keyword mentions and read-only analysis do not trigger this protocol by themselves.
---

# High-risk change protocol

High-risk areas: auth/authz, payments/billing, data migrations and deletions, cryptography and secrets, multi-tenant data boundaries, rate limiting, infra/deployment pipelines.

Use this protocol only when the requested write actually changes behavior or state in one of these areas. Keep read-only analysis, documentation-only changes, and incidental keyword matches in the normal lane unless the user explicitly requests complete orchestration or independent verification.

Before implementing:

1. **Grade the risk**: low (internal refactor with tests) / medium (behavior change behind flag or with migration) / high (security control, payment, persisted-data migration, production state). Medium and high require the steps below
2. **Rollback strategy first**: exact steps and commands documented before the change lands — feature flag, config gating, or isolated revertible commits. Irreversible migrations must be avoided or paired with a compensating strategy
3. **Prefer additive changes**: new code path behind a disabled-by-default flag before removing the old one

Schema and data migration sequencing:

expand schema → dual write → backfill → switch reads → remove legacy (only when safe, in a later deploy)

Safety checks for migrations: dry-run mode, expected vs observed row counts, sampling verification

Expanded verification (medium/high):

- unit + integration + targeted manual check
- baseline comparison: capture before/after outputs for critical paths (API responses, payload shapes, query counts)
- data safety: no unintended deletes, correct tenant scoping
- security: inputs validated at boundaries, no secrets in code or logs, least privilege

Deliverable: implementation plan must include a "Risk & Rollback" block — risk level, affected components, rollback steps, monitoring signals
