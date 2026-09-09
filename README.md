# Brewly infrastructure

Standalone infrastructure repository for Brewly, following the same ownership boundary as
Omnichat: the backend repository builds application code, while this repository owns deployment,
host configuration, Compose topology, monitoring, data migration, nginx, and TLS.

## Layout

```text
ansible/group_vars/        shared host and service settings
ansible/inventory/         bootstrap and steady-state inventories
ansible/playbooks/         provision, deploy, and TLS entry points
ansible/templates/         nginx HTTP/HTTPS virtual hosts
compose/                   production stack topology and resource limits
monitoring/                Loki and Promtail configuration
scripts/migrate.sh         repeatable Jino -> FirstVDS snapshot/cutover
```

The local sibling backend defaults to `../brewly-backend`. Override it with
`BREWLY_BACKEND_SOURCE` when the checkout lives elsewhere.

## Test migration

```bash
./scripts/migrate.sh snapshot
```

This streams the production environment and a consistent PostgreSQL dump directly from Jino to
FirstVDS over pinned-host-key SSH, deploys the stack, and leaves Jino online.

## Final cutover

```bash
./scripts/migrate.sh cutover
```

This stops the old application before taking the final dump. A failed deployment automatically
starts the old application again. A successful deployment leaves it stopped so A records can be
changed without accepting writes on two databases.

After `@`, `www`, `grafana`, and `pgadmin` resolve to `176.12.68.205`, enable HTTPS:

```bash
ANSIBLE_LOCAL_TEMP=/private/tmp/brewly-ansible-local \
  ansible-playbook -i ansible/inventory/prod.yml ansible/playbooks/ssl.yml
```

Do not change VK Workspace MX, SPF, DKIM, or DMARC records.

## Secrets

Plaintext credentials and database dumps never touch the operator machine during migration.
They are staged on FirstVDS under `/opt/brewly/backups` and installed under
`/opt/brewly/secrets` with mode `0600`. Both paths are outside the synchronized source tree.
