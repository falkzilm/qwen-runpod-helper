# syntax=docker/dockerfile:1.7
ARG VLLM_VERSION=0.28.0
FROM ghcr.io/astral-sh/uv:0.12.12 AS uv
FROM vllm/vllm-openai:v${VLLM_VERSION}

ARG OPEN_WEBUI_VERSION=0.11.3
ARG SEARXNG_REVISION=61d660276f1288e7d512e8d8da46cb8442728454
COPY --from=uv /uv /uvx /bin/

LABEL org.opencontainers.image.title="Qwen RunPod Helper" \
      org.opencontainers.image.description="Secure single-Pod vLLM and Open WebUI runtime for RunPod" \
      org.opencontainers.image.licenses="MIT"

USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl nginx && \
    rm -rf /var/lib/apt/lists/*

# Open WebUI lives in a separate Python 3.11 environment, so its dependencies
# cannot alter the pinned vLLM/PyTorch/CUDA stack.
ENV UV_PYTHON_INSTALL_DIR=/opt/uv-python \
    UV_PYTHON_PREFERENCE=only-managed \
    UV_LINK_MODE=copy
RUN uv python install 3.11 && \
    uv venv --python 3.11 /opt/open-webui && \
    uv pip install --python /opt/open-webui/bin/python \
      --exclude-newer 2026-09-12 \
      "open-webui==${OPEN_WEBUI_VERSION}" && \
    mkdir -p /opt/searxng-src && \
    curl --fail --silent --show-error --location \
      "https://github.com/searxng/searxng/archive/${SEARXNG_REVISION}.tar.gz" \
      | tar --extract --gzip --strip-components=1 --directory /opt/searxng-src
COPY pod/searxng-version_frozen.py /opt/searxng-src/searx/version_frozen.py
RUN uv venv --python 3.11 /opt/searxng && \
    uv pip install --python /opt/searxng/bin/python \
      --exclude-newer 2026-09-12 \
      pyyaml msgspec typing-extensions pybind11 setuptools wheel granian && \
    uv pip install --python /opt/searxng/bin/python \
      --exclude-newer 2026-09-12 --no-build-isolation /opt/searxng-src && \
    uv cache clean

RUN useradd --system --home-dir /nonexistent --shell /usr/sbin/nologin searxng

COPY pod/start.sh /opt/qwen-pod/start.sh
COPY pod/healthcheck.sh /opt/qwen-pod/healthcheck.sh
COPY pod/hf_preflight.py /opt/qwen-pod/hf_preflight.py
COPY pod/searxng-settings.yml /etc/searxng/settings.yml
COPY pod/nginx.conf /etc/nginx/nginx.conf
RUN chmod 0755 /opt/qwen-pod/start.sh /opt/qwen-pod/healthcheck.sh \
    /opt/qwen-pod/hf_preflight.py

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10m --retries=3 \
  CMD ["/opt/qwen-pod/healthcheck.sh"]

ENTRYPOINT ["/opt/qwen-pod/start.sh"]
