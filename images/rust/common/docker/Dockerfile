ARG BASE_IMAGE=ghcr.io/shaogme/coding-images/common:latest
FROM ${BASE_IMAGE}
ARG TARGETARCH

WORKDIR /root/workspace

# Set PNPM and enhanced PATH environment variables
ENV PNPM_HOME=/root/.local/share/pnpm \
    PATH=/root/.local/share/pnpm/bin:/root/.local/share/pnpm:/root/.cargo/bin:/root/.nix-profile/bin:$PATH

# 1. Copy Rust & Node delta mise configuration into conf.d
COPY .config/mise.toml /root/.config/mise/conf.d/20-rust.toml

# Pre-install global Rust tools and toolchains with BuildKit cache mounts and lock toolchain
RUN --mount=type=secret,id=GITHUB_TOKEN,env=GITHUB_TOKEN,required=false \
    --mount=type=cache,id=mise-cache-${TARGETARCH},target=/root/.cache/mise,sharing=shared \
    --mount=type=cache,id=cargo-registry,target=/root/.cargo/registry,sharing=shared \
    --mount=type=cache,id=cargo-git,target=/root/.cargo/git,sharing=shared \
    --mount=type=cache,id=cargo-target-${TARGETARCH},target=/root/.cargo/target,sharing=shared \
    --mount=type=cache,id=tmp-build-${TARGETARCH},target=/tmp,sharing=shared \
    set -e; \
    echo "Pre-installing Rust toolchains and Node tools during docker build..."; \
    mise trust --all; \
    mise lock --global --platform linux-x64,linux-arm64; \
    mise install; \
    rustup toolchain install nightly --component rust-src;

# Default command passed to entrypoint (inherited from common base)
CMD []
