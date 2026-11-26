# Triage rules

A candidate is a finding only when all three were read end to end: a source the attacker controls, a sink, and a path between them with no effective defense.

## Refutation checklist

Try to disprove the candidate before accepting it:

1. Is the source really attacker-controlled, and who can reach the entry point (anonymous, any user, admin only)
2. Is there validation, encoding, or parameterization between source and sink — including middleware, model binding, the ORM, and framework defaults
3. Is the code reachable: a registered route or handler, not dead code or a disabled feature
4. Does the claimed impact match what the sink actually does

Return: verdict, confidence 1-10, and when refuted the `path:line` of the defense.

## Confidence

- 9-10: complete exploit path identified
- 8: clear vulnerability pattern with a known exploitation method
- 7 or lower: do not report as a finding

## Severity

- **High**: directly exploitable — remote code execution, authentication bypass, data breach, account takeover
- **Medium**: significant impact but needs specific conditions; report only when concrete
- **Low**: defense in depth; goes under Hardening notes, never as a finding

## Not findings

Drop these, or move them to Hardening notes where marked:

- Denial of service, resource exhaustion, missing rate limiting (Hardening when it guards login, password reset, or one-time codes)
- A missing hardening measure with no concrete attack path (Hardening)
- Race conditions and timing attacks that are theoretical rather than demonstrated in the code
- Memory-safety issues in memory-safe languages
- Test-only code, fixtures, examples, and documentation — except a live secret committed in them
- Log spoofing, and logging data that is neither a secret nor personal data
- SSRF where the attacker controls only the path, not the host or protocol
- Regex injection and regex denial of service
- User content placed in an AI prompt, unless the model's output then reaches a privileged sink or tool
- Missing permission checks in client-side code; the server is responsible
- Open redirect, tabnabbing, XS-Leaks, and prototype pollution without a demonstrated impact chain
- XSS in auto-escaping templates (React, Angular, Vue, Razor, Jinja2 with autoescape, Blade `{{ }}`, ERB) unless a raw-output API is used
- Attacks that require controlling environment variables or command-line flags; those are trusted
- Guessing UUIDs
- Injection in shell scripts, CI workflows, or notebooks without a specific path for untrusted input to arrive

## In scope here, unlike a diff review

- **Pre-existing issues**: the whole project is under review, not just recent changes
- **Committed secrets**: a finding when the value looks live rather than a placeholder, example, or test key. Severity follows what the secret unlocks
- **Vulnerable dependencies**: reported in the Dependencies section from audit-tool output only, never from memory of advisories. Note whether the affected function is called when that is cheap to check
