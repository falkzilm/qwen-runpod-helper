#!/usr/bin/env bash
set -euo pipefail

curl --fail --silent --show-error --max-time 4 http://127.0.0.1:8080/health >/dev/null
curl --fail --silent --show-error --max-time 4 http://127.0.0.1:8081/health >/dev/null
internal_vllm_api_key="${VLLM_API_KEY:-${INTERNAL_VLLM_API_KEY:-${VLLM_INTERNAL_API_KEY:-}}}"
curl --fail --silent --show-error --max-time 4 \
  -H "Authorization: Bearer ${internal_vllm_api_key:?}" \
  http://127.0.0.1:8000/health >/dev/null

if [[ "${ENABLE_SEARXNG:-false}" == "true" ]]; then
  curl --fail --silent --show-error --max-time 4 \
    http://127.0.0.1:8888/ >/dev/null
fi
