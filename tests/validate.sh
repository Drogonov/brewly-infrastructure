#!/usr/bin/env bash

set -Eeuo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
backend_source="${BREWLY_BACKEND_SOURCE:-$repo_dir/../brewly-backend}"
validation_env="${BREWLY_VALIDATION_ENV_FILE:-$repo_dir/production.env.example}"
ansible_temp="${BREWLY_ANSIBLE_LOCAL_TEMP:-${TMPDIR:-/tmp}/brewly-ansible-local}"

mkdir -p "$ansible_temp"
bash -n "$repo_dir/scripts/migrate.sh"

ANSIBLE_LOCAL_TEMP="$ansible_temp" ansible-playbook \
  -i "$repo_dir/ansible/inventory/prod.yml" \
  "$repo_dir/ansible/playbooks/provision.yml" --syntax-check
ANSIBLE_LOCAL_TEMP="$ansible_temp" ansible-playbook \
  -i "$repo_dir/ansible/inventory/prod.yml" \
  "$repo_dir/ansible/playbooks/deploy.yml" --syntax-check
ANSIBLE_LOCAL_TEMP="$ansible_temp" ansible-playbook \
  -i "$repo_dir/ansible/inventory/prod.yml" \
  "$repo_dir/ansible/playbooks/ssl.yml" --syntax-check

BREWLY_BACKEND_ROOT="$backend_source" \
BREWLY_ENV_FILE="$validation_env" \
  docker compose \
  --env-file "$validation_env" \
  -f "$repo_dir/compose/docker-compose-prod.yaml" config --quiet
