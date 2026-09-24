# syntax=docker/dockerfile:1.7
ARG NIXOS_DOCKERS_VERSION=latest
ARG RUNTIME_PARENT_IMAGE=ghcr.io/shaogme/coding-images/qemu-rust-common:latest
ARG BUILDER_PARENT_IMAGE=local/coding-images/qemu-rust-common-builder:latest

FROM ${RUNTIME_PARENT_IMAGE} AS runtime-base

FROM ${BUILDER_PARENT_IMAGE} AS mise-builder
ARG TARGETARCH

WORKDIR /workspace

ENV RUSTUP_HOME=/usr/local/share/rustup \
    MISE_RUSTUP_HOME=/usr/local/share/rustup \
    CARGO_HOME=/usr/local/share/cargo \
    MISE_CARGO_HOME=/usr/local/share/cargo \
    PNPM_HOME=/usr/local/share/pnpm \
    PATH=/usr/local/share/cargo/bin:/usr/local/share/pnpm/bin:/usr/local/share/pnpm:$PATH

RUN mkdir -p /etc/mise/conf.d /usr/local/share/mise /data/cache/mise \
    /usr/local/share/rustup /usr/local/share/cargo /usr/local/share/pnpm

COPY .config/mise.toml /etc/mise/conf.d/30-cross.toml

RUN --mount=type=secret,id=GITHUB_TOKEN,required=false \
    if [ -f /run/secrets/GITHUB_TOKEN ]; then export GITHUB_TOKEN="$(cat /run/secrets/GITHUB_TOKEN)"; fi; \
    set -eu; \
    echo "Pre-installing Rust cross-compilation tools during docker build..."; \
    mise trust --all; \
    mise lock --global --platform linux-x64,linux-arm64; \
    mise install

FROM runtime-base AS runtime
ARG TARGETARCH

WORKDIR /workspace

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
