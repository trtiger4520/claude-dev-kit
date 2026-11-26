# OWASP Top 10:2025 coverage

Tag every finding with its category code. In standard and deep, mark each category before reporting: `checked`, `not applicable`, or `not checked` with the reason. A category with no check behind it is `not checked`, never clean.

| Code | Category | What this scan checks | Reported as |
| --- | --- | --- | --- |
| A01 | Broken Access Control | Authentication and authorization on every entry point, ownership and tenant scoping (IDOR), mass assignment, path traversal, SSRF | Finding |
| A02 | Security Misconfiguration | Debug mode, permissive CORS, default credentials, exposed admin or diagnostic endpoints, XML external entities, infrastructure and CI configuration | Finding when exploitable, otherwise hardening note |
| A03 | Software Supply Chain Failures | Audit-tool output, lockfiles, install scripts, unpinned CI actions, CI token permissions | Dependencies section |
| A04 | Cryptographic Failures | Weak algorithms and modes, committed keys and secrets, disabled TLS verification, non-cryptographic randomness for tokens | Finding |
| A05 | Injection | SQL, NoSQL, command, template, expression-language, and XSS sinks reached by attacker input | Finding |
| A06 | Insecure Design | Business-logic flows: state machines, check-then-act, missing limits on money or quantity, replay. Traced fully only in deep | Finding when a concrete path exists, otherwise hardening note |
| A07 | Authentication Failures | Password hashing, session handling, token validation, password-reset and one-time-code flows | Finding; missing brute-force protection is a hardening note |
| A08 | Software or Data Integrity Failures | Unsafe deserialization, unsigned or unverified updates and downloads, CI pipelines that run untrusted code | Finding |
| A09 | Security Logging and Alerting Failures | Secrets or personal data written to logs; whether authentication and authorization failures are logged at all | Finding for leaked secrets or personal data; absent logging is a hardening note |
| A10 | Mishandling of Exceptional Conditions | Fail-open paths: discarded errors or catch blocks that let an auth or validation check pass; stack traces and internal details returned to users | Finding when a check is bypassed or secrets leak, otherwise hardening note |
