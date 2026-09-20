#!/bin/sh
set -eu

case "${INFERENCE_MODE:-serverless}" in
  local)
    : "${LOCAL_VLLM_API_KEY:?LOCAL_VLLM_API_KEY muss fuer den lokalen Worker gesetzt sein}"
    export OPENAI_API_BASE_URL="${LOCAL_VLLM_BASE_URL:-http://worker:8000/v1}"
    export OPENAI_API_KEY="${LOCAL_VLLM_API_KEY}"
    ;;
  serverless)
    : "${RUNPOD_API_KEY:?RUNPOD_API_KEY muss fuer den Serverless-Endpoint gesetzt sein}"
    if [ -n "${RUNPOD_API_BASE_URL:-}" ]; then
      export OPENAI_API_BASE_URL="${RUNPOD_API_BASE_URL%/}/v1"
    else
      : "${RUNPOD_ENDPOINT_ID:?RUNPOD_ENDPOINT_ID muss fuer den Serverless-Endpoint gesetzt sein}"
      export OPENAI_API_BASE_URL="https://${RUNPOD_ENDPOINT_ID}.api.runpod.ai/v1"
    fi
    export OPENAI_API_KEY="${RUNPOD_API_KEY}"
    ;;
  *)
    printf 'Fehler: INFERENCE_MODE muss local oder serverless sein.\n' >&2
    exit 64
    ;;
esac

exec /app/backend/start.sh
