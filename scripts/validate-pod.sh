#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "${project_dir}"/pod/*.sh "${project_dir}"/scripts/*.sh

if [[ -f "${project_dir}/pod/template.env" ]]; then
  if [[ "$(stat -c '%a' "${project_dir}/pod/template.env")" != "600" ]]; then
    printf 'Fehler: pod/template.env muss Modus 600 haben.\n' >&2
    exit 1
  fi
  if rg -q 'replace-with|hf_replace_me' "${project_dir}/pod/template.env"; then
    printf 'Fehler: pod/template.env enthaelt Platzhalter.\n' >&2
    exit 1
  fi
fi

printf 'Pod-Dateien und Shell-Skripte sind syntaktisch gueltig.\n'
