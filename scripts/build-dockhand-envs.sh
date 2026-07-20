#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_ENV="${REPO_ROOT}/.env"

if [[ ! -f "${ROOT_ENV}" ]]; then
    echo "Root environment file missing: ${ROOT_ENV}" >&2
    exit 1
fi

find "${REPO_ROOT}" \
    -mindepth 2 \
    -maxdepth 2 \
    -name docker-compose.yml \
    -print0 |
while IFS= read -r -d '' compose_file; do
    stack_dir="$(dirname "${compose_file}")"
    stack_name="$(basename "${stack_dir}")"
    local_env="${stack_dir}/.env"
    output_env="${stack_dir}/.env.dockhand"

    {
        echo "# Generated for Dockhand. Do not edit directly."
        echo "# Source: ${ROOT_ENV}"
        echo
        cat "${ROOT_ENV}"

        if [[ -f "${local_env}" ]]; then
            echo
            echo "# Stack-specific values: ${local_env}"
            echo
            cat "${local_env}"
        fi
    } > "${output_env}"

    chmod 600 "${output_env}"
    echo "Generated ${stack_name}/.env.dockhand"
done
