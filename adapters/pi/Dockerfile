FROM node:22.19.0-alpine3.21@sha256:d4760191131171132bb788c4fd0014ef07a5e4e79e5155e26068f3cc9fdffea4

RUN apk add --no-cache jq git && \
    npm install --global --ignore-scripts --no-audit --no-fund @earendil-works/pi-coding-agent@0.84.4

RUN mkdir -p /home/agent /workspace && \
    chown -R 1000:1000 /home/agent /workspace

COPY --chmod=0755 entrypoint.sh /usr/local/bin/sympozium-pi-adapter
COPY --chmod=0755 session-server.mjs /usr/local/bin/sympozium-pi-session

USER 1000:1000
ENV HOME=/home/agent
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/sympozium-pi-adapter"]
