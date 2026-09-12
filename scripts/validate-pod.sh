#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "${project_dir}"/pod/*.sh "${project_dir}"/scripts/*.sh

if ! rg -q '^  bind_address: 127\.0\.0\.1$' "${project_dir}/pod/searxng-settings.yml" ||
  ! rg -q '^    - json$' "${project_dir}/pod/searxng-settings.yml" ||
  rg -q '(^|[[:space:]])--api-key([[:space:]]|$)' "${project_dir}/pod/start.sh"; then
  printf 'Fehler: SearXNG-Bindung/JSON oder vLLM-Key-Uebergabe ist unsicher.\n' >&2
  exit 1
fi

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

printf 'Pod-Dateien, Shell-Skripte und Sicherheitsinvarianten sind gueltig.\n'
