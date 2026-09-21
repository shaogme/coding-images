ARG BASE_IMAGE=ghcr.io/shaogme/nixos-dockers/mise:latest
FROM ${BASE_IMAGE}
ARG TARGETARCH

WORKDIR /workspace

# These variables are needed while the image layer installs the global mise
# tools. Runtime environment construction is declared in dev-env.toml.
ENV MISE_DATA_DIR=/usr/local/share/mise \
    MISE_CONFIG_DIR=/etc/mise \
    MISE_YES=1 \
    MISE_CACHE_DIR=/data/cache/mise

RUN nix profile add nixpkgs#bubblewrap

RUN mkdir -p /etc/mise/conf.d /usr/local/share/mise /data/cache/mise
COPY .config/mise.toml /etc/mise/conf.d/10-common.toml
COPY .config/dev-env.toml /etc/dev-env/profiles.d/20-coding-images.toml

# mise invokes helper scripts through bash. The image's bash shim bootstraps
# root callers, so keep these build-time operations explicitly root while
# leaving the runtime RUN_AS_ROOT default unset.
RUN --mount=type=secret,id=GITHUB_TOKEN,env=GITHUB_TOKEN,required=false \
    set -e; \
    mise trust --all; \
    mise lock --global --platform linux-x64,linux-arm64; \
    mise install; \
    chmod -R 1777 /etc/mise /usr/local/share/mise /data/cache/mise; \
    chmod -R a+rwX /etc/mise /data/cache/mise

# The derived profile adds the coding-images providers and bootstrap actions.
RUN printf 'coding-images\n' > /etc/dev-env/default-profile
