ARG NIXOS_DOCKERS_VERSION=latest
ARG BASE_IMAGE=ghcr.io/shaogme/coding-images/rust-common:latest
ARG BUILDER_IMAGE=ghcr.io/shaogme/nixos-dockers/mise-builder:${NIXOS_DOCKERS_VERSION}

FROM ${BASE_IMAGE} AS runtime-base
RUN mkdir -p /etc/mise /usr/local/share/mise /data/cache/mise \
    /usr/local/share/rustup /usr/local/share/cargo /usr/local/share/pnpm

FROM ${BUILDER_IMAGE} AS mise-tools
ARG TARGETARCH

WORKDIR /workspace

ENV RUSTUP_HOME=/usr/local/share/rustup \
    MISE_RUSTUP_HOME=/usr/local/share/rustup \
    CARGO_HOME=/usr/local/share/cargo \
    MISE_CARGO_HOME=/usr/local/share/cargo \
    PNPM_HOME=/usr/local/share/pnpm \
    PATH=/usr/local/share/cargo/bin:/usr/local/share/pnpm/bin:/usr/local/share/pnpm:$PATH

RUN mkdir -p /etc/mise /usr/local/share/mise /data/cache/mise \
    /usr/local/share/rustup /usr/local/share/cargo /usr/local/share/pnpm

COPY --from=runtime-base /etc/mise /etc/mise
COPY --from=runtime-base /usr/local/share/mise /usr/local/share/mise
COPY --from=runtime-base /data/cache/mise /data/cache/mise
COPY --from=runtime-base /usr/local/share/rustup /usr/local/share/rustup
COPY --from=runtime-base /usr/local/share/cargo /usr/local/share/cargo
COPY --from=runtime-base /usr/local/share/pnpm /usr/local/share/pnpm
COPY .config/mise.toml /etc/mise/conf.d/30-cross.toml

RUN --mount=type=secret,id=GITHUB_TOKEN,env=GITHUB_TOKEN,required=false \
    set -eu; \
    echo "Pre-installing Rust cross-compilation tools during docker build..."; \
    mise trust --all; \
    mise lock --global --platform linux-x64,linux-arm64; \
    mise install;

FROM runtime-base
ARG TARGETARCH

WORKDIR /workspace

COPY .config/mise.toml /etc/mise/conf.d/30-cross.toml
COPY --from=mise-tools /etc/mise /etc/mise
COPY --from=mise-tools /usr/local/share/mise /usr/local/share/mise
COPY --from=mise-tools /data/cache/mise /data/cache/mise
COPY --from=mise-tools /usr/local/share/rustup /usr/local/share/rustup
COPY --from=mise-tools /usr/local/share/cargo /usr/local/share/cargo
COPY --from=mise-tools /usr/local/share/pnpm /usr/local/share/pnpm
