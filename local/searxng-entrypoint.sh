#!/bin/sh
set -eu

template=/opt/local/searxng-settings.yml
runtime=/tmp/searxng-settings.yml
api_key="${BRAVE_SEARCH_API_KEY:-}"

if [ -n "${api_key}" ]; then
  # Brave keys use URL-safe characters. Escape the delimiter for a safe YAML
  # substitution without placing the key in the repository.
  escaped_key=$(printf '%s' "${api_key}" | sed 's/[|&\\]/\\&/g')
  sed \
    -e 's|__BRAVE_API_INACTIVE__|false|' \
    -e "s|__BRAVE_SEARCH_API_KEY__|${escaped_key}|" \
    "${template}" > "${runtime}"
else
  sed \
    -e 's|__BRAVE_API_INACTIVE__|true|' \
    -e 's|__BRAVE_SEARCH_API_KEY__||' \
    "${template}" > "${runtime}"
fi

export SEARXNG_SETTINGS_PATH="${runtime}"
exec /usr/local/searxng/entrypoint.sh
