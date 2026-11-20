FROM debian:bookworm-slim AS gateway
ARG GATEWAY_UID=1000
ARG GATEWAY_GID=1000
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl openssh-client privoxy \
    && rm -rf /var/lib/apt/lists/* \
    && test "$GATEWAY_UID" -gt 0 && test "$GATEWAY_GID" -gt 0 \
    && groupadd --non-unique --gid "$GATEWAY_GID" tunnel \
    && useradd --uid "$GATEWAY_UID" --gid tunnel --no-create-home --home-dir /tmp tunnel
COPY config/gateway.sh config/privoxy.conf /opt/gateway/
USER tunnel
ENTRYPOINT ["/bin/bash", "/opt/gateway/gateway.sh"]

FROM node:24-bookworm-slim AS agent-base
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git openssh-client ripgrep \
    && rm -rf /var/lib/apt/lists/*

FROM agent-base AS pi
ARG PI_VERSION=latest
RUN npm install -g --ignore-scripts "@earendil-works/pi-coding-agent@${PI_VERSION}"
COPY config/pi.sh /usr/local/bin/pi-entrypoint
ENTRYPOINT ["/bin/sh", "/usr/local/bin/pi-entrypoint"]

FROM agent-base AS codex
RUN npm install -g --ignore-scripts @openai/codex && codex --version
USER node
ENTRYPOINT ["codex"]

FROM agent-base AS antigravity
RUN curl -fsSL https://antigravity.google/cli/install.sh -o /tmp/install-agy.sh \
    && bash /tmp/install-agy.sh --dir /usr/local/bin \
    && rm /tmp/install-agy.sh \
    && agy --version
USER node
ENTRYPOINT ["agy"]
