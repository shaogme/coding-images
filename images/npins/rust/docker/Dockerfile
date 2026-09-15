ARG BASE_IMAGE=ghcr.io/shaogme/coding-images/rust-common:latest
FROM ${BASE_IMAGE}
ARG TARGETARCH

WORKDIR /workspace

# Install npins dependency pin tool via nix profile on top of rust-common
RUN nix profile add \
        nixpkgs#npins
