ARG BASE_IMAGE=ghcr.io/shaogme/coding-images/common:latest
FROM ${BASE_IMAGE}

WORKDIR /root/workspace

# Set PNPM and enhanced PATH environment variables
ENV PNPM_HOME=/root/.local/share/pnpm \
    PATH=/root/.local/share/pnpm/bin:/root/.local/share/pnpm:/root/.cargo/bin:/root/.nix-profile/bin:$PATH

# 1. Copy Rust & Node delta mise configuration into conf.d
COPY .config/mise.toml /root/.config/mise/conf.d/20-rust.toml

# Pre-install global Rust tools and toolchains with BuildKit cache mounts and lock toolchain
RUN --mount=type=cache,target=/root/.cache/mise \
    --mount=type=cache,target=/root/.cargo/registry \
    --mount=type=cache,target=/root/.cargo/git \
    set -e; \
    echo "Pre-installing Rust toolchains and Node tools during docker build..."; \
    mise trust --all; \
    mise lock --global --platform linux-x64,linux-arm64; \
    mise install;

# Default command passed to entrypoint (inherited from common base)
CMD []
