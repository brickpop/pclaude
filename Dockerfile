FROM docker.io/library/node:22-slim

ARG CLAUDE_CODE_VERSION=latest

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

ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global \
    PATH=/usr/local/share/npm-global/bin:$PATH \
    DEVCONTAINER=true

RUN mkdir -p /usr/local/share/npm-global /home/node/.claude \
  && chown -R node:node /usr/local/share/npm-global /home/node/.claude

USER node

RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
  && npm cache clean --force

# The command is exactly what you pass, and defaults to Claude.
# pclaude bind-mounts each project at its host path and passes a matching --workdir.
ENTRYPOINT []
CMD ["claude"]
