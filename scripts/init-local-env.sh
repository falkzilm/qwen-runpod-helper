#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="${project_dir}/local/compose.env"

if [[ -e "${target}" ]]; then
  printf 'Abbruch: %s existiert bereits.\n' "${target}" >&2
  exit 1
fi
command -v openssl >/dev/null 2>&1 || {
  printf 'Fehler: openssl fehlt.\n' >&2
  exit 1
}

umask 077
sed \
  -e "s|^WEBUI_SECRET_KEY=.*|WEBUI_SECRET_KEY=$(openssl rand -hex 32)|" \
  -e "s|^SEARXNG_SECRET=.*|SEARXNG_SECRET=$(openssl rand -hex 32)|" \
  -e "s|^LOCAL_VLLM_API_KEY=.*|LOCAL_VLLM_API_KEY=$(openssl rand -hex 32)|" \
  "${project_dir}/local/compose.env.example" > "${target}"
chmod 600 "${target}"

printf 'Lokale Konfiguration geschrieben: %s\n' "${target}"
printf 'Setze fuer Serverless RUNPOD_ENDPOINT_ID und RUNPOD_API_KEY.\n'
printf 'Setze fuer lokalen Worker INFERENCE_MODE=local und HF_TOKEN.\n'
