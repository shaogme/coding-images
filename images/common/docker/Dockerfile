ARG BASE_IMAGE=ghcr.io/shaogme/nixos-dockers/mise:latest
FROM ${BASE_IMAGE}
ARG TARGETARCH

WORKDIR /workspace

# Copy custom entrypoint for automatic mise environment loading
COPY --chmod=755 docker/entrypoint.sh /usr/local/bin/mise-entrypoint.sh

# Configure global mise, nix, binstall, cargo, and devbox environment variables
ENV MISE_DATA_DIR=/usr/local/share/mise \
    MISE_CONFIG_DIR=/etc/mise \
    XDG_DATA_HOME=/data \
    NIX_PROFILE=/nix/var/nix/profiles/default \
    BINSTALL_NO_CONFIRM=true \
    BINSTALL_DISABLE_TELEMETRY=true \
    CARGO_NET_GIT_FETCH_WITH_CLI=true \
    PATH=/usr/local/share/mise/shims:$PATH

# Install system-level binaries via nix-env into system default profile
RUN echo "sandbox = false" >> /etc/nix/nix.conf && \
    nix-env --option sandbox false -iA \
        nixpkgs.bubblewrap

# Configure global interactive shell hooks for mise and devbox
RUN { \
        echo '# Global interactive shell hooks for mise and devbox'; \
        echo 'if [[ $- == *i* ]]; then'; \
        echo '  type -P mise &>/dev/null && eval "$(mise activate bash 2>/dev/null || true)"'; \
        echo '  if type -P devbox &>/dev/null; then'; \
        echo '    eval "$(devbox global shellenv --init-hook 2>/dev/null || true)"'; \
        echo '    __devbox_hook() {'; \
        echo '      local dir="$PWD"'; \
        echo '      if [ "$dir" != "${__devbox_last_dir:-}" ]; then'; \
        echo '        __devbox_last_dir="$dir"'; \
        echo '        if [ -f "$dir/devbox.json" ] && [ "${DEVBOX_PROJECT_ROOT:-}" != "$dir" ]; then'; \
        echo '          eval "$(devbox shellenv --init-hook 2>/dev/null || true)"'; \
        echo '        fi'; \
        echo '      fi'; \
        echo '    }'; \
        echo '    if [[ ";$PROMPT_COMMAND;" != *";__devbox_hook;"* ]]; then'; \
        echo '      PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}__devbox_hook"'; \
        echo '    fi'; \
        echo '  fi'; \
        echo 'fi'; \
    } >> /etc/bash.bashrc

# Copy global mise base configuration into conf.d
RUN mkdir -p /etc/mise/conf.d /usr/local/share/mise
COPY .config/mise.toml /etc/mise/conf.d/10-common.toml

# Pre-install global common mise tools and lock global tool versions
RUN --mount=type=secret,id=GITHUB_TOKEN,env=GITHUB_TOKEN,required=false \
    set -e; \
    echo "Pre-installing common mise tools during docker build..."; \
    mise trust --all; \
    mise lock --global --platform linux-x64,linux-arm64; \
    mise install; \
    chmod -R 1777 /etc/mise /usr/local/share/mise && \
    chmod -R a+rwX /etc/mise;

# Create unified persistent storage directories with shared permissions for AI config, devbox data, sccache, and cargo target
RUN mkdir -p /data/coding-config /data/devbox /data/.cargo/target /data/sccache && \
    chmod 1777 /data/coding-config /data/devbox /data/sccache && \
    chmod -R 1777 /data/.cargo

# Set the custom entrypoint
ENTRYPOINT ["/usr/local/bin/mise-entrypoint.sh"]

# Default command passed to entrypoint (empty to trigger default behavior: sshd or bash)
CMD []
