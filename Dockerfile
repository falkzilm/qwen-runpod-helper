# syntax=docker/dockerfile:1.7
ARG VLLM_VERSION=0.28.0
FROM ghcr.io/astral-sh/uv:0.12.12 AS uv
FROM vllm/vllm-openai:v${VLLM_VERSION}

ARG OPEN_WEBUI_VERSION=0.11.2
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
      --exclude-newer 2026-09-11 \
      "open-webui==${OPEN_WEBUI_VERSION}" && \
    uv cache clean

COPY pod/start.sh /opt/qwen-pod/start.sh
COPY pod/healthcheck.sh /opt/qwen-pod/healthcheck.sh
COPY pod/nginx.conf /etc/nginx/nginx.conf
RUN chmod 0755 /opt/qwen-pod/start.sh /opt/qwen-pod/healthcheck.sh

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10m --retries=3 \
  CMD ["/opt/qwen-pod/healthcheck.sh"]

ENTRYPOINT ["/opt/qwen-pod/start.sh"]
