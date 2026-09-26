# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest (`main`) | ✅ |
| Previous minor | ⚠️ Critical fixes only |
| Older | ❌ |

## Reporting a Vulnerability

**Please do not open a public GitHub issue for security vulnerabilities.**

To report a security issue, open a [GitHub Security Advisory](https://github.com/awesome-lang-auth/awesome-dart-auth/security/advisories/new) (private disclosure). You can also use the **"Report a vulnerability"** button on the [Security tab](https://github.com/awesome-lang-auth/awesome-dart-auth/security).

Please include:

- A description of the vulnerability and its potential impact
- Steps to reproduce or a proof-of-concept
- Affected versions
- Any suggested fix, if you have one

## Response timeline

- **Acknowledgement** within 48 hours
- **Assessment and triage** within 5 business days
- **Fix and advisory** published after a patch is ready (coordinated disclosure)

## Scope

This policy covers the packages in this repository. It does **not** cover third-party dependencies — please report those directly to their respective maintainers.

## Security best practices for users

- Never commit token secrets or other credentials to source control.
- Rotate secrets if you suspect they have been exposed.
- Keep packages updated to receive security patches.
- Use HTTPS in production.
