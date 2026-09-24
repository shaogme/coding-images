# syntax=docker/dockerfile:1.7
ARG NIXOS_DOCKERS_VERSION=latest
ARG RUNTIME_PARENT_IMAGE=ghcr.io/shaogme/nixos-dockers/mise:${NIXOS_DOCKERS_VERSION}
ARG BUILDER_PARENT_IMAGE=ghcr.io/shaogme/nixos-dockers/mise-builder:${NIXOS_DOCKERS_VERSION}

FROM ${RUNTIME_PARENT_IMAGE} AS runtime-base

FROM ${BUILDER_PARENT_IMAGE} AS mise-builder
ARG TARGETARCH

WORKDIR /workspace

# Keep all generated state in directories explicitly synchronized into runtime.
ENV MISE_DATA_DIR=/usr/local/share/mise \
    MISE_CONFIG_DIR=/etc/mise \
    MISE_YES=1 \
    MISE_CACHE_DIR=/data/cache/mise

RUN mkdir -p /etc/mise/conf.d /usr/local/share/mise /data/cache/mise
COPY .config/mise.toml /etc/mise/conf.d/10-common.toml

RUN --mount=type=secret,id=GITHUB_TOKEN,required=false \
    if [ -f /run/secrets/GITHUB_TOKEN ]; then export GITHUB_TOKEN="$(cat /run/secrets/GITHUB_TOKEN)"; fi; \
    set -eu; \
    mise trust --all; \
    mise lock --global --platform linux-x64,linux-arm64; \
    mise install; \
    chmod -R 1777 /etc/mise /usr/local/share/mise /data/cache/mise; \
    chmod -R a+rwX /etc/mise /data/cache/mise

FROM runtime-base AS runtime
ARG TARGETARCH

WORKDIR /workspace

ENV MISE_DATA_DIR=/usr/local/share/mise \
    MISE_CONFIG_DIR=/etc/mise \
    MISE_YES=1 \
    MISE_CACHE_DIR=/data/cache/mise

# rsync is a small build helper inherited by all descendants. It compares
# content against the runtime parent and writes only changed files to this
# image's layer.
RUN nix profile add \
        nixpkgs#bubblewrap \
        nixpkgs#rsync

RUN --mount=type=bind,from=mise-builder,target=/mnt/mise-builder,ro \
    set -eu; \
    for path in \
        /etc/mise \
        /usr/local/share/mise \
        /data/cache/mise; do \
        mkdir -p "$path"; \
        rsync -aH --checksum --omit-dir-times \
            "/mnt/mise-builder$path/" "$path/"; \
    done

# Runtime environment construction is declared in dev-env.toml.
COPY .config/dev-env.toml /etc/dev-env/profiles.d/20-coding-images.toml
RUN rm -f /etc/dev-env/default-profile && printf 'coding-images\n' > /etc/dev-env/default-profile
