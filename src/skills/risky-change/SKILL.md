---
name: risky-change
description: MANDATORY protocol before implementing any change touching high-risk domains. Hard trigger on keywords (any language): auth, authentication, authorization, permission, role, Identity, OAuth, JWT, SSO, payment, billing, migration, schema, secret, credential, crypto, tenant, deploy, pipeline, 授權, 認證, 身分, 角色, 權限, 登入, 金流, 付款, 遷移, 密鑰, 憑證, 部署. If the task mentions these, invoke this skill first — do not weigh task size.
---

# High-risk change protocol

High-risk areas: auth/authz, payments/billing, data migrations and deletions, cryptography and secrets, multi-tenant data boundaries, rate limiting, infra/deployment pipelines.

Before implementing:

1. **Grade the risk**: low (internal refactor with tests) / medium (behavior change behind flag or with migration) / high (auth, payment, migration, infra). Medium and high require the steps below
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
