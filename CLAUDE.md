# Brewly infrastructure

This repository owns Brewly host provisioning, Docker Compose orchestration, monitoring,
database migration, nginx, and TLS. The application image contract remains in the sibling
`brewly-backend` repository.

## Safety invariants

- Keep PostgreSQL, Loki, and application ports private; nginx is the public ingress.
- Never commit plaintext secrets, dumps, or private keys.
- `snapshot` migrations must leave the old production application online.
- `cutover` migrations must restart the old application automatically when deployment fails.
- Database replacement is allowed only when a non-empty staged dump has been verified.
- Preserve VK Workspace MX/SPF/DKIM/DMARC records during DNS changes.
- Do not stage, commit, push, or create a remote repository without explicit human approval.
