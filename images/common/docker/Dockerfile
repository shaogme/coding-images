ARG BASE_IMAGE=ghcr.io/shaogme/nixos-dockers/mise:latest
FROM ${BASE_IMAGE}
ARG TARGETARCH

WORKDIR /workspace

# Copy custom entrypoint for automatic mise environment loading
COPY --chmod=755 docker/entrypoint.sh /usr/local/bin/mise-entrypoint.sh

# Configure global mise, nix, binstall, cargo, and direnv environment variables
ENV MISE_DATA_DIR=/usr/local/share/mise \
    MISE_CONFIG_DIR=/etc/mise \
    DIRENV_CONFIG=/etc/direnv \
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

# Configure direnv global defaults, workspace whitelist, and system bash hooks
RUN mkdir -p /etc/direnv && \
    { \
        echo '[whitelist]'; \
        echo 'prefix = [ "/workspace" ]'; \
    } > /etc/direnv/direnv.toml && \
    { \
        echo 'type -P mise &>/dev/null && eval "$(mise direnv activate 2>/dev/null || true)"'; \
        echo ''; \
        echo '# Load user-configuration if present (~/.direnvrc or ~/.config/direnv/direnvrc)'; \
        echo 'direnv_config_dir_home="${DIRENV_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/direnv}"'; \
        echo 'if [[ -f "$direnv_config_dir_home/direnvrc" ]]; then'; \
        echo '  source "$direnv_config_dir_home/direnvrc" >&2'; \
        echo 'elif [[ -f "$HOME/.direnvrc" ]]; then'; \
        echo '  source "$HOME/.direnvrc" >&2'; \
        echo 'fi'; \
        echo 'unset direnv_config_dir_home'; \
    } > /etc/direnv/direnvrc && \
    chmod -R 1777 /etc/direnv && \
    chmod 666 /etc/direnv/* && \
    { \
        echo '# Global interactive shell hooks for mise and direnv'; \
        echo 'if [[ $- == *i* ]]; then'; \
        echo '  type -P mise &>/dev/null && eval "$(mise activate bash 2>/dev/null || true)"'; \
        echo '  type -P direnv &>/dev/null && eval "$(direnv hook bash 2>/dev/null || true)"'; \
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
    chmod -R 1777 /usr/local/share/mise;

# Create unified persistent storage directories with shared permissions for AI config and direnv data
RUN mkdir -p /data/coding-config /data/direnv && chmod 1777 /data/coding-config /data/direnv

# Set the custom entrypoint
ENTRYPOINT ["/usr/local/bin/mise-entrypoint.sh"]

# Default command passed to entrypoint (empty to trigger default behavior: sshd or bash)
CMD []
