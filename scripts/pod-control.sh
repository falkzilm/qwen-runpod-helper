#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
control_file="${project_dir}/.env.control"
action="${1:-status}"

[[ -f "${control_file}" ]] || {
  printf 'Fehler: .env.control fehlt; Vorlage .env.control.example kopieren.\n' >&2
  exit 1
}
if [[ "$(stat -c '%a' "${control_file}")" != "600" ]]; then
  printf 'Fehler: .env.control muss Modus 600 haben.\n' >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${control_file}"
set +a
: "${RUNPOD_POD_ID:?}"
: "${RUNPOD_MANAGEMENT_API_KEY:?}"

base_url="https://rest.runpod.io/v1/pods/${RUNPOD_POD_ID}"
auth_header="Authorization: Bearer ${RUNPOD_MANAGEMENT_API_KEY}"

case "${action}" in
  start|stop)
    curl --fail --silent --show-error \
      --request POST "${base_url}/${action}" \
      --header "${auth_header}"
    printf '\n%s angefordert fuer Pod %s.\n' "${action}" "${RUNPOD_POD_ID}"
    ;;
  status)
    curl --fail --silent --show-error \
      --request GET "${base_url}" \
      --header "${auth_header}"
    printf '\n'
    ;;
  *)
    printf 'Aufruf: %s [start|stop|status]\n' "$0" >&2
    exit 2
    ;;
esac
