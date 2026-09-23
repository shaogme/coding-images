ARG NIXOS_DOCKERS_VERSION=latest
ARG BASE_IMAGE=ghcr.io/shaogme/nixos-dockers/mise:${NIXOS_DOCKERS_VERSION}
ARG BUILDER_IMAGE=ghcr.io/shaogme/nixos-dockers/mise-builder:${NIXOS_DOCKERS_VERSION}

FROM ${BASE_IMAGE} AS runtime-base
RUN mkdir -p /etc/mise /usr/local/share/mise /data/cache/mise

FROM ${BUILDER_IMAGE} AS mise-tools
ARG TARGETARCH

WORKDIR /workspace

# These variables are needed while the image layer installs the global mise
# tools. Runtime environment construction is declared in dev-env.toml.
ENV MISE_DATA_DIR=/usr/local/share/mise \
    MISE_CONFIG_DIR=/etc/mise \
    MISE_YES=1 \
    MISE_CACHE_DIR=/data/cache/mise

# Reuse only the parent Mise state. The builder keeps its real Bash and never
# receives the runtime profile or entrypoint.
COPY --from=runtime-base /etc/mise /etc/mise
COPY --from=runtime-base /usr/local/share/mise /usr/local/share/mise
COPY --from=runtime-base /data/cache/mise /data/cache/mise
RUN mkdir -p /etc/mise/conf.d /usr/local/share/mise /data/cache/mise
COPY .config/mise.toml /etc/mise/conf.d/10-common.toml

RUN --mount=type=secret,id=GITHUB_TOKEN,env=GITHUB_TOKEN,required=false \
    set -eu; \
    mise trust --all; \
    mise lock --global --platform linux-x64,linux-arm64; \
    mise install; \
    chmod -R 1777 /etc/mise /usr/local/share/mise /data/cache/mise; \
    chmod -R a+rwX /etc/mise /data/cache/mise

FROM runtime-base
ARG TARGETARCH

WORKDIR /workspace

ENV MISE_DATA_DIR=/usr/local/share/mise \
    MISE_CONFIG_DIR=/etc/mise \
    MISE_YES=1 \
    MISE_CACHE_DIR=/data/cache/mise

RUN nix profile add nixpkgs#bubblewrap

# Runtime environment construction is declared in dev-env.toml.
COPY .config/dev-env.toml /etc/dev-env/profiles.d/20-coding-images.toml
COPY --from=mise-tools /etc/mise /etc/mise
COPY --from=mise-tools /usr/local/share/mise /usr/local/share/mise
COPY --from=mise-tools /data/cache/mise /data/cache/mise

# The derived profile adds the coding-images providers and bootstrap actions.
RUN rm -f /etc/dev-env/default-profile && printf 'coding-images\n' > /etc/dev-env/default-profile
