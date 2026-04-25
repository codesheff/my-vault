# devpod — UBI 9 Linux development environment
#
# Provides: latest Python, uv, VS Code remote server (code CLI), vault CLI
# Default user: z4701038-779 (uid 7401038)
#
# Build:
#   docker build -t devpod:latest k8s/devpod/
#
# To push to a registry:
#   docker tag devpod:latest <registry>/devpod:latest
#   docker push <registry>/devpod:latest

FROM registry.access.redhat.com/ubi9/ubi:latest

# ── System dependencies ──────────────────────────────────────────────────────
RUN dnf install -y \
      python3 \
      python3-pip \
      curl \
      git \
      unzip \
      tar \
      gzip \
      jq \
      which \
      shadow-utils \
    && dnf clean all

# ── uv (Python package/venv manager) ────────────────────────────────────────
# Install uv to /usr/local/bin so all users can access it.
RUN curl -LsSf https://astral.sh/uv/install.sh \
    | env INSTALLER_NO_MODIFY_PATH=1 sh \
    && mv /root/.local/bin/uv /usr/local/bin/uv \
    && mv /root/.local/bin/uvx /usr/local/bin/uvx \
    && chmod 755 /usr/local/bin/uv /usr/local/bin/uvx

# ── Vault CLI ────────────────────────────────────────────────────────────────
ARG VAULT_VERSION=1.18.2
RUN curl -fsSL \
      "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip" \
      -o /tmp/vault.zip \
    && unzip /tmp/vault.zip -d /usr/local/bin/ \
    && rm /tmp/vault.zip \
    && chmod 755 /usr/local/bin/vault

# ── VS Code CLI (code) ───────────────────────────────────────────────────────
# Downloads the official Microsoft VS Code CLI for Linux x64.
# The `code tunnel` command allows VS Code desktop to connect to this container.
RUN curl -fsSL \
      "https://code.visualstudio.com/sha/download?build=stable&os=cli-linux-x64" \
      -o /tmp/vscode-cli.tar.gz \
    && tar -xzf /tmp/vscode-cli.tar.gz -C /usr/local/bin/ \
    && rm /tmp/vscode-cli.tar.gz \
    && chmod 755 /usr/local/bin/code

# ── Non-root user ────────────────────────────────────────────────────────────
# Username: z4701038-779   UID: 7401038
RUN useradd \
      --uid 7401038 \
      --create-home \
      --shell /bin/bash \
      z4701038-779

USER z4701038-779
WORKDIR /home/z4701038-779

# Keep the container running so kubectl/VS Code can attach to it.
CMD ["sleep", "infinity"]
