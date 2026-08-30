ARG BASE_IMAGE=ghcr.io/shaogme/nixos-dockers/mise:latest
FROM ${BASE_IMAGE}

WORKDIR /root/workspace

# Copy custom entrypoint for automatic mise environment loading
COPY --chmod=755 docker/entrypoint.sh /usr/local/bin/mise-entrypoint.sh

# Enable non-interactive auto-confirm for mise and set base PATH
ENV MISE_YES=1 \
    PATH=/root/.cargo/bin:/root/.nix-profile/bin:$PATH

# Install system-level binaries via nix-env with BuildKit cache mount & binary mirror
RUN --mount=type=cache,target=/root/.cache/nix \
    --mount=type=cache,target=/tmp \
    echo "sandbox = false" >> /etc/nix/nix.conf && \
    nix-env --option sandbox false -iA \
        nixpkgs.bubblewrap

# Configure direnv global defaults and workspace whitelist
RUN mkdir -p /root/.config/direnv /root/.local/share/direnv && \
    printf '[whitelist]\nprefix = [ "/root/workspace" ]\n' > /root/.config/direnv/direnv.toml && \
    printf 'type -P mise &>/dev/null && eval "$(mise direnv activate 2>/dev/null || true)"\n' > /root/.config/direnv/direnvrc

# 1. Copy global mise base configuration into conf.d
RUN mkdir -p /root/.config/mise/conf.d
COPY .config/mise.toml /root/.config/mise/conf.d/10-common.toml

# Pre-install global common mise tools and lock global tool versions
RUN --mount=type=cache,target=/root/.cache/mise \
    set -e; \
    echo "Pre-installing common mise tools during docker build..."; \
    mise trust --all; \
    mise lock --global --platform linux-x64,linux-arm64; \
    mise install;

# Set the custom entrypoint
ENTRYPOINT ["/usr/local/bin/mise-entrypoint.sh"]

# Default command passed to entrypoint (empty to trigger default behavior: sshd or bash)
CMD []
