ARG BASE_IMAGE=ghcr.io/shaogme/coding-images/common:latest
FROM ${BASE_IMAGE}
ARG TARGETARCH

WORKDIR /workspace

# Set Rustup and PNPM environment variables for multi-user access
ENV RUSTUP_HOME=/usr/local/share/rustup \
    PNPM_HOME=/usr/local/share/pnpm \
    PATH=/usr/local/share/pnpm/bin:/usr/local/share/pnpm:$PATH

# 1. Copy Rust & Node delta mise configuration into conf.d
COPY .config/mise.toml /etc/mise/conf.d/20-rust.toml

# Pre-install global Rust tools and toolchains with BuildKit cache mounts and lock toolchain
RUN --mount=type=secret,id=GITHUB_TOKEN,env=GITHUB_TOKEN,required=false \
    --mount=type=cache,id=tmp-build-${TARGETARCH},target=/tmp,sharing=shared \
    set -e; \
    echo "Pre-installing Rust toolchains and Node tools during docker build..."; \
    mise trust --all; \
    mise lock --global --platform linux-x64,linux-arm64; \
    mise install; \
    rustup toolchain install nightly --component rust-src; \
    chmod -R 1777 /usr/local/share/mise /usr/local/share/rustup /usr/local/share/pnpm 2>/dev/null || true;

# Default command passed to entrypoint (inherited from common base)
CMD []
