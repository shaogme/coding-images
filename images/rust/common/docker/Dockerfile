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
    TRIPLE=$(rustc -vV 2>/dev/null | sed -n 's/host: //p' || echo "$(uname -m)-unknown-linux-gnu"); \
    cd "${RUSTUP_HOME}/toolchains"; \
    LATEST_NIGHTLY=$(ls -d nightly-[0-9]* 2>/dev/null | sort -V | tail -n 1); \
    if [ -n "$LATEST_NIGHTLY" ]; then \
        echo "Linking nightly toolchain aliases for ${LATEST_NIGHTLY}..."; \
        ln -sfn "$LATEST_NIGHTLY" "nightly-${TRIPLE}"; \
        ln -sfn "$LATEST_NIGHTLY" "nightly"; \
        if [ -d "${RUSTUP_HOME}/update-hashes" ] && [ -f "${RUSTUP_HOME}/update-hashes/${LATEST_NIGHTLY}" ]; then \
            ln -sfn "$LATEST_NIGHTLY" "${RUSTUP_HOME}/update-hashes/nightly-${TRIPLE}"; \
            ln -sfn "$LATEST_NIGHTLY" "${RUSTUP_HOME}/update-hashes/nightly"; \
        fi; \
    elif ! rustup toolchain list | grep -q "^nightly"; then \
        echo "Fallback: installing nightly toolchain directly via rustup..."; \
        rustup toolchain install nightly --component rust-src; \
    fi; \
    chmod -R 1777 /usr/local/share/rustup /usr/local/share/pnpm 2>/dev/null || true;

# Configure default sccache compiler cache wrapper, cache directory, and incremental setting
ENV RUSTC_WRAPPER=sccache \
    SCCACHE_DIR=/data/sccache \
    CARGO_INCREMENTAL=0

# Default command passed to entrypoint (inherited from common base)
CMD []
