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

# RunPod load-balancing endpoints provide the public authentication layer with
# the RunPod API key. VLLM_API_KEY is deliberately opt-in so it can protect the
# local worker without rejecting RunPod-authenticated requests. vLLM reads this
# official environment variable itself, avoiding an API key in the process list.
port="${PORT:-8000}"
vllm_args=(
  serve "${MODEL_NAME}"
  --host 0.0.0.0
  --port "${port}"
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
printf 'Starte OpenAI-kompatiblen vLLM-Worker auf Port %s fuer Modell %s.\n' \
  "${port}" "${SERVED_MODEL_NAME:-qwen3.8-27b-uncensored}"
exec vllm "${vllm_args[@]}"
