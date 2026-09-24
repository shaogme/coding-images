ARG RUNTIME_PARENT_IMAGE=ghcr.io/shaogme/coding-images/common:latest
FROM ${RUNTIME_PARENT_IMAGE} AS runtime
ARG TARGETARCH

WORKDIR /workspace

# Install npins dependency pin tool via nix profile on top of common
RUN nix profile add \
        nixpkgs#npins
