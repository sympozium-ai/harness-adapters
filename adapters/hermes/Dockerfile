FROM ghcr.io/astral-sh/uv:0.11.6-python3.13-trixie@sha256:b3c543b6c4f23a5f2df22866bd7857e5d304b67a564f4feab6ac22044dde719b

ARG HERMES_REVISION=fc0a10a924ce31a7badd0d7a202dcc0779ef7942

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_NO_DEV=1 \
    PATH=/opt/hermes/.venv/bin:$PATH

RUN apt-get update && \
    apt-get install -y --no-install-recommends jq git && \
    rm -rf /var/lib/apt/lists/* && \
    git clone --filter=blob:none https://github.com/NousResearch/hermes-agent.git /opt/hermes && \
    git -C /opt/hermes checkout --detach "$HERMES_REVISION" && \
    test "$(git -C /opt/hermes rev-parse HEAD)" = "$HERMES_REVISION" && \
    rm -rf /opt/hermes/.git && \
    # Keep the venv interpreter inside the image's world-readable Python
    # installation.  uv's managed interpreter cache is under /root and an
    # otherwise executable console script then fails under Sympozium's UID
    # 1000 security context.
    cd /opt/hermes && uv sync --frozen --no-dev --python /usr/local/bin/python3.13 && \
    groupadd --gid 1000 agent && \
    useradd --uid 1000 --gid 1000 --create-home --home-dir /home/agent agent

COPY --chmod=0755 entrypoint.sh /usr/local/bin/sympozium-hermes-adapter

USER 1000:1000
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/sympozium-hermes-adapter"]
