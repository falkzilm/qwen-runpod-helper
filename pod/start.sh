#!/usr/bin/env bash
set -Eeuo pipefail

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    printf 'Fehler: Pflichtvariable %s fehlt.\n' "${name}" >&2
    exit 64
  fi
}

require_var MODEL_NAME
require_var HF_TOKEN
require_var WEBUI_SECRET_KEY
require_var VLLM_INTERNAL_API_KEY
require_var WEBUI_ADMIN_EMAIL
require_var WEBUI_ADMIN_PASSWORD

export DATA_DIR="${DATA_DIR:-/workspace/open-webui}"
export HF_HOME="${MODEL_CACHE_DIR:-/root/.cache/huggingface}"
export OPENAI_API_BASE_URL="http://127.0.0.1:8000/v1"
export OPENAI_API_KEY="${VLLM_INTERNAL_API_KEY}"
export WEBUI_AUTH=true
export ENABLE_SIGNUP=false
export ENABLE_LOGIN_FORM=true
export ENABLE_PASSWORD_VALIDATION=true
export ENABLE_API_KEYS=true
export ENABLE_API_KEYS_ENDPOINT_RESTRICTIONS=true
export API_KEYS_ALLOWED_ENDPOINTS="/api/models,/api/chat/completions"
export ENABLE_OLLAMA_API=false
export ENABLE_OPENAI_API=true
export SAFE_MODE=true
export ENABLE_COMMUNITY_SHARING=false
export AIOHTTP_CLIENT_ALLOW_REDIRECTS=false
export JWT_EXPIRES_IN="${JWT_EXPIRES_IN:-7d}"
export UVICORN_WORKERS=1

if [[ -n "${RUNPOD_POD_ID:-}" ]]; then
  pod_origin="https://${RUNPOD_POD_ID}-8080.proxy.runpod.net"
  export WEBUI_URL="${WEBUI_URL:-${pod_origin}}"
  export CORS_ALLOW_ORIGIN="${CORS_ALLOW_ORIGIN:-${pod_origin}}"
else
  export WEBUI_URL="${WEBUI_URL:-http://localhost:8080}"
  export CORS_ALLOW_ORIGIN="${CORS_ALLOW_ORIGIN:-http://localhost:8080}"
fi

install -d -m 0700 "${DATA_DIR}" "${HF_HOME}"

vllm_args=(
  serve "${MODEL_NAME}"
  --host 127.0.0.1
  --port 8000
  --api-key "${VLLM_INTERNAL_API_KEY}"
  --served-model-name "${SERVED_MODEL_NAME:-qwen3.8-27b-uncensored}"
  --tensor-parallel-size "${TENSOR_PARALLEL_SIZE:-1}"
  --max-model-len "${MAX_MODEL_LEN:-131072}"
  --max-num-seqs "${MAX_NUM_SEQS:-4}"
  --gpu-memory-utilization "${GPU_MEMORY_UTILIZATION:-0.90}"
  --kv-cache-dtype "${KV_CACHE_DTYPE:-fp8}"
  --reasoning-parser "${REASONING_PARSER:-qwen3}"
  --tool-call-parser "${TOOL_CALL_PARSER:-qwen3_coder}"
  --enable-auto-tool-choice
  --enable-prefix-caching
  --enable-chunked-prefill
  --language-model-only
)

if [[ "${TRUST_REMOTE_CODE:-true}" == "true" ]]; then
  vllm_args+=(--trust-remote-code)
fi
if [[ -n "${SPECULATIVE_CONFIG:-}" ]]; then
  vllm_args+=(--speculative-config "${SPECULATIVE_CONFIG}")
fi

vllm "${vllm_args[@]}" &
vllm_pid=$!

/opt/open-webui/bin/open-webui serve --host 127.0.0.1 --port 8081 &
webui_pid=$!

/usr/sbin/nginx -c /etc/nginx/nginx.conf -g 'daemon off;' &
nginx_pid=$!

shutdown() {
  trap - TERM INT
  kill -TERM "${vllm_pid}" "${webui_pid}" "${nginx_pid}" 2>/dev/null || true
  wait "${vllm_pid}" "${webui_pid}" "${nginx_pid}" 2>/dev/null || true
}
trap shutdown TERM INT

set +e
wait -n "${vllm_pid}" "${webui_pid}" "${nginx_pid}"
status=$?
set -e
printf 'Ein Dienst wurde mit Status %s beendet; stoppe den zweiten Dienst.\n' "${status}" >&2
shutdown
exit "${status}"
