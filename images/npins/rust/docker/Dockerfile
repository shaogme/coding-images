ARG BASE_IMAGE=ghcr.io/shaogme/nixos-dockers/mise:latest
FROM ${BASE_IMAGE}

WORKDIR /root/workspace

# Copy custom entrypoint for automatic mise environment loading
COPY --chmod=755 docker/entrypoint.sh /usr/local/bin/mise-entrypoint.sh

# Enable non-interactive auto-confirm for mise
ENV MISE_YES=1

# Install system-level binaries via nix-env with BuildKit cache mount & binary mirror
RUN --mount=type=cache,target=/root/.cache/nix \
    --mount=type=cache,target=/tmp \
    echo "sandbox = false" >> /etc/nix/nix.conf && \
    nix-env --option sandbox false -iA \
        nixpkgs.bubblewrap \
        nixpkgs.npins

# Set the PNPM, PATH and Headless / Fontconfig environment variables
ENV PNPM_HOME=/root/.local/share/pnpm \
    PATH=/root/.local/share/pnpm/bin:/root/.local/share/pnpm:/root/.cargo/bin:/root/.nix-profile/bin:$PATH

# 1. Copy global mise configuration to ~/.config/mise/config.toml
COPY .config/mise.toml /root/.config/mise/config.toml

# Pre-install global mise tools and Rust targets with BuildKit cache mounts
RUN --mount=type=cache,target=/root/.cache/mise \
    --mount=type=cache,target=/root/.cargo/registry \
    --mount=type=cache,target=/root/.cargo/git \
    set -e; \
    echo "Pre-installing mise tools and Rust targets during docker build..."; \
    mise trust --all; \
    mise install;

# 2. Copy the rest of the workspace source code
COPY . /root/workspace/

# Set the custom entrypoint
ENTRYPOINT ["/usr/local/bin/mise-entrypoint.sh"]

# Default command passed to entrypoint (empty to trigger default behavior: sshd or bash)
CMD []

