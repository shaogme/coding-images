# syntax=docker/dockerfile:1.7
ARG NIXOS_DOCKERS_VERSION=latest
ARG RUNTIME_PARENT_IMAGE=ghcr.io/shaogme/coding-images/podman:latest
ARG BUILDER_PARENT_IMAGE=local/coding-images/common-builder:latest

FROM ${RUNTIME_PARENT_IMAGE} AS runtime-base

FROM ${BUILDER_PARENT_IMAGE} AS mise-builder
ARG TARGETARCH

WORKDIR /workspace

# Keep mise and Rust state in paths copied into the runtime image. The
# builder's default /root state must never be part of the runtime sync.
ENV MISE_DATA_DIR=/usr/local/share/mise \
    MISE_CONFIG_DIR=/etc/mise \
    MISE_CACHE_DIR=/data/cache/mise \
    MISE_YES=1 \
    RUSTUP_HOME=/usr/local/share/rustup \
    MISE_RUSTUP_HOME=/usr/local/share/rustup \
    CARGO_HOME=/usr/local/share/cargo \
    MISE_CARGO_HOME=/usr/local/share/cargo \
    PNPM_HOME=/usr/local/share/pnpm \
    PATH=/usr/local/share/cargo/bin:/usr/local/share/pnpm/bin:/usr/local/share/pnpm:$PATH

RUN mkdir -p /etc/mise/conf.d /usr/local/share/mise /data/cache/mise \
    /usr/local/share/rustup /usr/local/share/cargo /usr/local/share/pnpm

COPY .config/mise.toml /etc/mise/conf.d/20-rust.toml

RUN --mount=type=secret,id=GITHUB_TOKEN,required=false \
    if [ -f /run/secrets/GITHUB_TOKEN ]; then export GITHUB_TOKEN="$(cat /run/secrets/GITHUB_TOKEN)"; fi; \
    set -eu; \
    echo "Pre-installing Rust toolchains and Node tools during docker build..."; \
    mise trust --all; \
    mise lock --global --platform linux-x64,linux-arm64; \
    mise install rust@stable; \
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
    fi; \
    if ! rustup toolchain list | grep -q "^nightly"; then \
        echo "Error: No nightly Rust toolchain found after linking" >&2; \
        exit 1; \
    fi; \
    chmod -R 1777 /usr/local/share/rustup /usr/local/share/cargo /usr/local/share/pnpm 2>/dev/null || true

FROM runtime-base AS runtime
ARG TARGETARCH

WORKDIR /workspace

ENV RUSTUP_HOME=/usr/local/share/rustup \
    MISE_RUSTUP_HOME=/usr/local/share/rustup \
    CARGO_HOME=/usr/local/share/cargo \
    MISE_CARGO_HOME=/usr/local/share/cargo \
    PNPM_HOME=/usr/local/share/pnpm \
    PATH=/usr/local/share/cargo/bin:/usr/local/share/pnpm/bin:/usr/local/share/pnpm:$PATH

RUN --mount=type=bind,from=mise-builder,target=/mnt/mise-builder,ro \
    set -eu; \
    for path in \
        /etc/mise \
        /usr/local/share/mise \
        /data/cache/mise \
        /usr/local/share/rustup \
        /usr/local/share/cargo \
        /usr/local/share/pnpm; do \
        mkdir -p "$path"; \
        rsync -aH --checksum --omit-dir-times \
            "/mnt/mise-builder$path/" "$path/"; \
    done

COPY .config/dev-env.toml /etc/dev-env/profiles.d/30-coding-images-rust.toml

RUN set -eu; \
    for shared_dir in /usr/local/share/mise /usr/local/share/rustup /usr/local/share/cargo /usr/local/share/pnpm; do \
        if [ -d "$shared_dir" ]; then \
            chmod -R a+rwX "$shared_dir"; \
            find "$shared_dir" -type d -exec chmod 0777 {} +; \
        fi; \
    done

# Install rust debug tools.
RUN nix profile add \
    nixpkgs#valgrind \
    nixpkgs#gdb \
    nixpkgs#lldb \
    nixpkgs#llvmPackages.llvm \
    nixpkgs#perf \
    nixpkgs#elfutils

RUN rm -f /etc/dev-env/default-profile && printf 'coding-images-rust\n' > /etc/dev-env/default-profile
