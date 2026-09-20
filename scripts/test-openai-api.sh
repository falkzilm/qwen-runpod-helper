#!/usr/bin/env bash
set -euo pipefail

wait_only=false
case "${1:-}" in
  '') ;;
  --wait) wait_only=true ;;
  *)
    printf 'Aufruf: %s [--wait]\n' "$0" >&2
    exit 64
    ;;
esac

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${LOCAL_CONFIG_FILE:-${project_dir}/local/compose.env}"

if [[ ! -f "${config_file}" ]]; then
  printf 'Fehler: Lokale Konfiguration fehlt: %s. Erst make local-init ausfuehren.\n' "${config_file}" >&2
  exit 64
fi

set -a
# shellcheck disable=SC1090
source "${config_file}"
set +a

case "${INFERENCE_MODE:-serverless}" in
  local)
    : "${LOCAL_VLLM_API_KEY:?LOCAL_VLLM_API_KEY fehlt}"
    base_url="${LOCAL_VLLM_PUBLIC_BASE_URL:-http://localhost:8000/v1}"
    api_key="${LOCAL_VLLM_API_KEY}"
    ;;
  serverless)
    : "${RUNPOD_API_KEY:?RUNPOD_API_KEY fehlt}"
    if [[ -n "${RUNPOD_API_BASE_URL:-}" ]]; then
      base_url="${RUNPOD_API_BASE_URL%/}"
    else
      : "${RUNPOD_ENDPOINT_ID:?RUNPOD_ENDPOINT_ID fehlt}"
      case "${RUNPOD_ENDPOINT_ID}" in
        http://*|https://*) base_url="${RUNPOD_ENDPOINT_ID%/}" ;;
        *) base_url="https://${RUNPOD_ENDPOINT_ID}.api.runpod.ai" ;;
      esac
      [[ "${base_url}" == */v1 ]] || base_url="${base_url}/v1"
    fi
    api_key="${RUNPOD_API_KEY}"
    ;;
  *)
    printf 'Fehler: INFERENCE_MODE muss local oder serverless sein.\n' >&2
    exit 64
    ;;
esac

model="${SERVED_MODEL_NAME:-qwen3.8-27b-uncensored}"
curl_config="$(mktemp)"
chmod 600 "${curl_config}"
trap 'rm -f "${curl_config}"' EXIT
printf 'header = "Authorization: Bearer %s"\n' "${api_key}" > "${curl_config}"

if [[ "${INFERENCE_MODE:-serverless}" == "serverless" ]]; then
  readiness_timeout="${RUNPOD_COLD_START_TIMEOUT:-900}"
  readiness_interval="${RUNPOD_READINESS_INTERVAL:-10}"
else
  readiness_timeout="${LOCAL_START_TIMEOUT:-90}"
  readiness_interval="${LOCAL_READINESS_INTERVAL:-3}"
fi

if ! [[ "${readiness_timeout}" =~ ^[1-9][0-9]*$ ]] || ! [[ "${readiness_interval}" =~ ^[1-9][0-9]*$ ]]; then
  printf 'Fehler: Die Readiness-Zeitwerte muessen positive ganze Sekunden sein.\n' >&2
  exit 64
fi

printf 'Wecke %s-Worker und warte bis die OpenAI-API bereit ist (maximal %ss).\n' \
  "${INFERENCE_MODE:-serverless}" "${readiness_timeout}"
deadline=$((SECONDS + readiness_timeout))
while ! curl --config "${curl_config}" --fail --silent --connect-timeout 15 --max-time 30 \
  "${base_url}/models" >/dev/null; do
  if (( SECONDS >= deadline )); then
    printf 'Fehler: API nach %ss noch nicht bereit. Worker-Logs und Serverless-Queue pruefen.\n' \
      "${readiness_timeout}" >&2
    exit 1
  fi
  printf 'Worker startet noch; erneuter Bereitschaftstest in %ss ...\n' "${readiness_interval}"
  sleep "${readiness_interval}"
done
printf 'OpenAI-API ist bereit.\n'

if [[ "${wait_only}" == true ]]; then
  exit 0
fi

curl --config "${curl_config}" --fail --silent --show-error --connect-timeout 15 --max-time 360 \
  "${base_url}/chat/completions" \
  -H 'Content-Type: application/json' \
  --data "{\"model\":\"${model}\",\"messages\":[{\"role\":\"user\",\"content\":\"Antworte nur mit: bereit\"}],\"stream\":false,\"max_tokens\":32,\"chat_template_kwargs\":{\"enable_thinking\":false}}"
printf '\nOpenAI-kompatibler CLI-Test war erfolgreich (%s).\n' "${INFERENCE_MODE:-serverless}"
