#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="${project_dir}/pod/template.env"

if [[ -e "${target}" ]]; then
  printf 'Abbruch: %s existiert bereits.\n' "${target}" >&2
  exit 1
fi
command -v openssl >/dev/null 2>&1 || {
  printf 'Fehler: openssl fehlt.\n' >&2
  exit 1
}

read -r -s -p 'Hugging-Face Read-Token: ' hf_token
printf '\n'
read -r -p 'Admin-E-Mail [admin@example.invalid]: ' admin_email
admin_email="${admin_email:-admin@example.invalid}"

if [[ ! "${hf_token}" =~ ^hf_[A-Za-z0-9]+$ ]]; then
  printf 'Fehler: Der Hugging-Face-Token hat ein unerwartetes Format.\n' >&2
  exit 1
fi
if [[ ! "${admin_email}" =~ ^[A-Za-z0-9._+@-]+$ ]]; then
  printf 'Fehler: Die Admin-E-Mail enthaelt unzulaessige Zeichen.\n' >&2
  exit 1
fi

admin_password="$(openssl rand -base64 36 | tr -d '\n')"
webui_secret="$(openssl rand -hex 32)"
vllm_key="$(openssl rand -hex 32)"
searxng_secret="$(openssl rand -hex 32)"

umask 077
sed \
  -e "s|^HF_TOKEN=.*|HF_TOKEN=${hf_token}|" \
  -e "s|^WEBUI_SECRET_KEY=.*|WEBUI_SECRET_KEY=${webui_secret}|" \
  -e "s|^INTERNAL_VLLM_API_KEY=.*|INTERNAL_VLLM_API_KEY=${vllm_key}|" \
  -e "s|^SEARXNG_SECRET=.*|SEARXNG_SECRET=${searxng_secret}|" \
  -e "s|^WEBUI_ADMIN_EMAIL=.*|WEBUI_ADMIN_EMAIL=${admin_email}|" \
  -e "s|^WEBUI_ADMIN_PASSWORD=.*|WEBUI_ADMIN_PASSWORD=${admin_password}|" \
  "${project_dir}/pod/template.env.example" > "${target}"
chmod 600 "${target}"

printf 'Pod-Variablen geschrieben: %s\n' "${target}"
printf 'Einmaliges Admin-Passwort: %s\n' "${admin_password}"
printf 'Diese Werte jetzt in das private RunPod-Template uebertragen.\n'
