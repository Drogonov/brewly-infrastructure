#!/usr/bin/env bash

set -Eeuo pipefail

mode="${1:-snapshot}"
if [[ "$mode" != "snapshot" && "$mode" != "cutover" ]]; then
  echo "Usage: $0 [snapshot|cutover]" >&2
  exit 2
fi

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
backend_source="${BREWLY_BACKEND_SOURCE:-$repo_dir/../brewly-backend}"
old_host="${BREWLY_OLD_HOST:-81.177.139.160}"
new_host="${BREWLY_NEW_HOST:-176.12.68.205}"
old_key="${BREWLY_OLD_SSH_KEY:-$HOME/.ssh/brewly_server_ed25519}"
new_key="${BREWLY_NEW_SSH_KEY:-$HOME/.ssh/toolkit-ci}"
old_known_hosts="$repo_dir/ansible/known_hosts/jino"
new_known_hosts="$repo_dir/ansible/known_hosts/firstvds"
old_root="${BREWLY_OLD_ROOT:-/root/brewly-backend}"
new_root="${BREWLY_NEW_ROOT:-/opt/brewly}"
old_dump="$old_root/backups/brewly-migration.dump"
new_dump="$new_root/backups/initial.dump"
new_env="$new_root/backups/production.env"

if [[ ! -f "$backend_source/Dockerfile-prod" ]]; then
  echo "Brewly backend not found at $backend_source" >&2
  exit 1
fi

old_ssh=(
  ssh -i "$old_key" -o IdentitiesOnly=yes -o ForwardAgent=no
  -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$old_known_hosts"
  "root@$old_host"
)
new_ssh=(
  ssh -i "$new_key" -o IdentitiesOnly=yes -o ForwardAgent=no
  -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$new_known_hosts"
  "deploy@$new_host"
)

old_app_stopped=0
migration_succeeded=0

cleanup() {
  "${old_ssh[@]}" "rm -f '$old_dump'" >/dev/null 2>&1 || true
  if [[ "$mode" == "cutover" && "$old_app_stopped" == "1" && "$migration_succeeded" != "1" ]]; then
    echo "Migration failed; restarting the old application." >&2
    "${old_ssh[@]}" "docker start app" >/dev/null || true
  fi
}
trap cleanup EXIT

echo "Checking SSH access and source services..."
"${old_ssh[@]}" "test -r '$old_root/config/production.env' && docker inspect db-prod >/dev/null"
"${new_ssh[@]}" "test -d '$new_root/backups' && test -w '$new_root/backups'"

if [[ "$mode" == "cutover" ]]; then
  echo "Stopping the old application to freeze writes..."
  "${old_ssh[@]}" "docker stop app" >/dev/null
  old_app_stopped=1
fi

echo "Copying the production environment directly from Jino to FirstVDS..."
"${old_ssh[@]}" "cat '$old_root/config/production.env'" \
  | "${new_ssh[@]}" "umask 077; cat > '$new_env.tmp'; mv -f '$new_env.tmp' '$new_env'; chmod 0600 '$new_env'"

echo "Creating a consistent PostgreSQL dump on Jino..."
"${old_ssh[@]}" "mkdir -p '$old_root/backups'; umask 077; docker exec db-prod sh -lc 'exec pg_dump --format=custom --no-owner --no-privileges -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\"' > '$old_dump'; test -s '$old_dump'"
source_checksum="$("${old_ssh[@]}" "sha256sum '$old_dump' | cut -d ' ' -f 1")"

echo "Streaming the database dump directly to FirstVDS..."
"${old_ssh[@]}" "cat '$old_dump'" \
  | "${new_ssh[@]}" "umask 077; cat > '$new_dump.tmp'; mv -f '$new_dump.tmp' '$new_dump'; chmod 0600 '$new_dump'"
destination_checksum="$("${new_ssh[@]}" "sha256sum '$new_dump' | cut -d ' ' -f 1")"

if [[ "$source_checksum" != "$destination_checksum" ]]; then
  echo "Database dump checksum mismatch." >&2
  exit 1
fi
echo "Database dump verified: $source_checksum"

echo "Deploying Brewly and restoring the staged snapshot..."
mkdir -p /private/tmp/brewly-ansible-local
BREWLY_BACKEND_SOURCE="$backend_source" \
ANSIBLE_LOCAL_TEMP=/private/tmp/brewly-ansible-local \
  ansible-playbook \
  -i "$repo_dir/ansible/inventory/prod.yml" \
  "$repo_dir/ansible/playbooks/deploy.yml" \
  -e use_remote_production_env=true \
  -e use_remote_database_dump=true

migration_succeeded=1
if [[ "$mode" == "cutover" ]]; then
  echo "Cutover snapshot deployed. The old application remains stopped for DNS cutover."
else
  echo "Test snapshot deployed. The old application remained online."
fi
