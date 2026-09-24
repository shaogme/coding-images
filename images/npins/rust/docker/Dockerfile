ARG RUNTIME_PARENT_IMAGE=ghcr.io/shaogme/coding-images/rust-common:latest
FROM ${RUNTIME_PARENT_IMAGE} AS runtime
ARG TARGETARCH

WORKDIR /workspace

# Install npins dependency pin tool via nix profile on top of rust-common
RUN nix profile add \
        nixpkgs#npins
