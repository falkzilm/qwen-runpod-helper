#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "${project_dir}"/pod/*.sh "${project_dir}"/scripts/*.sh
bash -n "${project_dir}"/serverless/*.sh "${project_dir}"/local/*.sh

if ! grep -Eq '^  bind_address: 127\.0\.0\.1$' "${project_dir}/pod/searxng-settings.yml" ||
  ! grep -Eq '^    - json$' "${project_dir}/pod/searxng-settings.yml" ||
  ! grep -Fq 'https://download.pytorch.org/whl/cpu' "${project_dir}/Dockerfile" ||
  ! grep -Fq 'OPEN_WEBUI_TORCH_VERSION=2.8.0+cpu' "${project_dir}/Dockerfile" ||
  grep -Eq '(^|[[:space:]])--api-key([[:space:]]|$)' "${project_dir}/pod/start.sh"; then
  printf 'Fehler: SearXNG-, Open-WebUI-Torch- oder vLLM-Key-Invariante verletzt.\n' >&2
  exit 1
fi

if [[ -f "${project_dir}/pod/template.env" ]]; then
  if [[ "$(stat -c '%a' "${project_dir}/pod/template.env")" != "600" ]]; then
    printf 'Fehler: pod/template.env muss Modus 600 haben.\n' >&2
    exit 1
  fi
  if grep -Eq 'replace-with|hf_replace_me' "${project_dir}/pod/template.env"; then
    printf 'Fehler: pod/template.env enthaelt Platzhalter.\n' >&2
    exit 1
  fi
fi

if ! grep -Fq 'FROM vllm/vllm-openai:v${VLLM_VERSION}' "${project_dir}/Dockerfile.serverless" ||
  ! grep -Fq 'exec vllm' "${project_dir}/serverless/start.sh" ||
  ! grep -Fq 'HEALTH_CHECK_PATH=/health' "${project_dir}/serverless/template.env.example" ||
  ! grep -Fq 'INFERENCE_MODE' "${project_dir}/compose.yaml"; then
  printf 'Fehler: Serverless- oder lokale Compose-Invariante verletzt.\n' >&2
  exit 1
fi

printf 'Pod-Dateien, Shell-Skripte und Sicherheitsinvarianten sind gueltig.\n'
