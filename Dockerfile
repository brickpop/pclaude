FROM docker.io/library/node:22-slim

ARG CLAUDE_CODE_VERSION=latest

# Everyday CLI tools. Deliberately no sudo / iptables / man-db / build-essential:
# add what you need in Dockerfile.dev instead of growing this one.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      openssh-client \
      less \
      jq \
      make \
      unzip \
      fzf \
      vim \
      procps \
  && rm -rf /var/lib/apt/lists/*

# Do NOT set CLAUDE_CONFIG_DIR here. Claude resolves .claude.json *inside* it, so
# pointing it at ~/.claude makes it read ~/.claude/.claude.json and ignore the
# mounted ~/.claude.json, losing your login. HOME=/home/node already gives the
# right default of /home/node/.claude.
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global \
    PATH=/usr/local/share/npm-global/bin:$PATH \
    DEVCONTAINER=true

RUN mkdir -p /usr/local/share/npm-global /workspace /home/node/.claude \
  && chown -R node:node /usr/local/share/npm-global /workspace /home/node/.claude

USER node

RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
  && npm cache clean --force

WORKDIR /workspace

# Drop the node image's docker-entrypoint.sh, which silently rewrites any
# argument starting with "-" into a `node` invocation. With no entrypoint, the
# command is exactly what you pass...
ENTRYPOINT []

# ...and defaults to Claude when you pass nothing:
#   podman run <image>              claude
#   podman run <image> bash         a shell, no --entrypoint needed
CMD ["claude"]
