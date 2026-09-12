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
require_var WEBUI_ADMIN_EMAIL
require_var WEBUI_ADMIN_PASSWORD

internal_vllm_api_key="${INTERNAL_VLLM_API_KEY:-${VLLM_INTERNAL_API_KEY:-}}"
if [[ -z "${internal_vllm_api_key}" ]]; then
  printf 'Fehler: Pflichtvariable INTERNAL_VLLM_API_KEY fehlt.\n' >&2
  exit 64
fi

export DATA_DIR="${DATA_DIR:-/workspace/open-webui}"
export HF_HOME="${MODEL_CACHE_DIR:-/root/.cache/huggingface}"
export OPENAI_API_BASE_URL="http://127.0.0.1:8000/v1"
export OPENAI_API_KEY="${internal_vllm_api_key}"
export VLLM_API_KEY="${internal_vllm_api_key}"
# Avoid vLLM's unknown-variable warning for the legacy name and keep the
# secret out of the command line and its startup argument log.
unset INTERNAL_VLLM_API_KEY VLLM_INTERNAL_API_KEY
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
export ENABLE_PLUGINS=false
export ENABLE_COMMUNITY_SHARING=false
export ENABLE_NOTES=true
export ENABLE_MEMORIES=true
export ENABLE_MEMORY_SYSTEM_CONTEXT=false
export ENABLE_MEMORY_BACKGROUND_REVIEW=false
export ENABLE_AUTOMATIONS=false
export ENABLE_SUBAGENTS=false
export AIOHTTP_CLIENT_ALLOW_REDIRECTS=false
export JWT_EXPIRES_IN="${JWT_EXPIRES_IN:-7d}"
export UVICORN_WORKERS=1
export USER_AGENT="${USER_AGENT:-qwen-runpod-helper/0.1.1 (+https://github.com/falkzilm/qwen-runpod-helper)}"

enable_searxng="${ENABLE_SEARXNG:-false}"
searxng_pid=""
searxng_secret=""
if [[ "${enable_searxng}" == "true" ]]; then
  require_var SEARXNG_SECRET
  searxng_secret="${SEARXNG_SECRET}"
  unset SEARXNG_SECRET
  export ENABLE_WEB_SEARCH=true
  export WEB_SEARCH_ENGINE=searxng
  export SEARXNG_QUERY_URL="http://127.0.0.1:8888/search?q=<query>"
  export SEARXNG_LANGUAGE="${SEARXNG_LANGUAGE:-all}"
  export WEB_SEARCH_RESULT_COUNT="${WEB_SEARCH_RESULT_COUNT:-5}"
fi

if [[ -n "${RUNPOD_POD_ID:-}" ]]; then
  pod_origin="https://${RUNPOD_POD_ID}-8080.proxy.runpod.net"
  export WEBUI_URL="${WEBUI_URL:-${pod_origin}}"
  export CORS_ALLOW_ORIGIN="${CORS_ALLOW_ORIGIN:-${pod_origin}}"
else
  export WEBUI_URL="${WEBUI_URL:-http://localhost:8080}"
  export CORS_ALLOW_ORIGIN="${CORS_ALLOW_ORIGIN:-http://localhost:8080}"
fi

data_parent="$(dirname "${DATA_DIR}")"
install -d -m 0700 "${data_parent}" "${HF_HOME}"

if [[ "${RECOVER_OPEN_WEBUI_0112:-false}" == "true" ]]; then
  recovery_marker="${data_parent}/.open-webui-0112-recovered"
  if [[ ! -e "${recovery_marker}" ]]; then
    if [[ -d "${DATA_DIR}" ]]; then
      recovery_dir="${DATA_DIR}.broken-0112-$(date -u +%Y%m%dT%H%M%SZ)"
      mv "${DATA_DIR}" "${recovery_dir}"
      printf 'Open-WebUI-0.11.2-Daten wurden zur Wiederherstellung archiviert: %s\n' \
        "${recovery_dir}" >&2
    fi
    install -d -m 0700 "${DATA_DIR}"
    : >"${recovery_marker}"
  else
    printf 'RECOVER_OPEN_WEBUI_0112 wurde bereits ausgefuehrt; ueberspringe erneuten Reset.\n' >&2
  fi
else
  install -d -m 0700 "${DATA_DIR}"
fi

/opt/open-webui/bin/python /opt/qwen-pod/hf_preflight.py

if [[ "${enable_searxng}" == "true" ]]; then
  (
    cd /opt/searxng-src
    exec runuser --user searxng -- env -i \
      PATH=/opt/searxng/bin:/usr/bin:/bin \
      LANG=C.UTF-8 \
      SEARXNG_SETTINGS_PATH=/etc/searxng/settings.yml \
      SEARXNG_SECRET="${searxng_secret}" \
      GRANIAN_INTERFACE=wsgi \
      GRANIAN_HOST=127.0.0.1 \
      GRANIAN_PORT=8888 \
      GRANIAN_WEBSOCKETS=false \
      GRANIAN_WORKERS=1 \
      GRANIAN_BLOCKING_THREADS=4 \
      /opt/searxng/bin/granian searx.webapp:app
  ) &
  searxng_pid=$!

  searxng_ready=false
  for _ in $(seq 1 30); do
    if ! kill -0 "${searxng_pid}" 2>/dev/null; then
      wait "${searxng_pid}" || true
      printf 'Fehler: SearXNG wurde vor Erreichen der Bereitschaft beendet.\n' >&2
      exit 70
    fi
    if curl --fail --silent --max-time 2 http://127.0.0.1:8888/ >/dev/null; then
      searxng_ready=true
      break
    fi
    sleep 1
  done
  if [[ "${searxng_ready}" != "true" ]]; then
    printf 'Fehler: SearXNG war nach 30 Sekunden nicht bereit.\n' >&2
    kill -TERM "${searxng_pid}" 2>/dev/null || true
    wait "${searxng_pid}" 2>/dev/null || true
    exit 70
  fi
fi

vllm_args=(
  serve "${MODEL_NAME}"
  --host 127.0.0.1
  --port 8000
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

/opt/open-webui/bin/open-webui serve --host 127.0.0.1 --port 8081 &
webui_pid=$!

webui_ready=false
for _ in $(seq 1 60); do
  if ! kill -0 "${webui_pid}" 2>/dev/null; then
    wait "${webui_pid}" || true
    printf 'Fehler: Open WebUI wurde vor Erreichen der Bereitschaft beendet.\n' >&2
    exit 70
  fi
  if curl --fail --silent --max-time 2 http://127.0.0.1:8081/health >/dev/null; then
    webui_ready=true
    break
  fi
  sleep 2
done
if [[ "${webui_ready}" != "true" ]]; then
  printf 'Fehler: Open WebUI war nach 120 Sekunden nicht bereit.\n' >&2
  kill -TERM "${webui_pid}" 2>/dev/null || true
  wait "${webui_pid}" 2>/dev/null || true
  exit 70
fi

vllm "${vllm_args[@]}" &
vllm_pid=$!

/usr/sbin/nginx -c /etc/nginx/nginx.conf -g 'daemon off;' &
nginx_pid=$!

service_pids=("${vllm_pid}" "${webui_pid}" "${nginx_pid}")
if [[ -n "${searxng_pid}" ]]; then
  service_pids+=("${searxng_pid}")
fi

shutdown() {
  trap - TERM INT
  kill -TERM "${service_pids[@]}" 2>/dev/null || true
  wait "${service_pids[@]}" 2>/dev/null || true
}
trap shutdown TERM INT

set +e
wait -n "${service_pids[@]}"
status=$?
set -e
printf 'Ein Dienst wurde mit Status %s beendet; stoppe die anderen Dienste.\n' "${status}" >&2
shutdown
exit "${status}"
