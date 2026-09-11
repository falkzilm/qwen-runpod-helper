#!/usr/bin/env bash
set -euo pipefail

curl --fail --silent --show-error --max-time 4 http://127.0.0.1:8080/health >/dev/null
curl --fail --silent --show-error --max-time 4 http://127.0.0.1:8081/health >/dev/null
curl --fail --silent --show-error --max-time 4 \
  -H "Authorization: Bearer ${VLLM_INTERNAL_API_KEY:?}" \
  http://127.0.0.1:8000/health >/dev/null
