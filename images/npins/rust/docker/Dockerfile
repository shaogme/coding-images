ARG BASE_IMAGE=ghcr.io/shaogme/coding-images/rust-common:latest
FROM ${BASE_IMAGE}
ARG TARGETARCH

WORKDIR /workspace

# Install npins dependency pin tool via nix-env on top of rust-common
RUN --mount=type=cache,id=tmp-build-${TARGETARCH},target=/tmp,sharing=shared \
    echo "sandbox = false" >> /etc/nix/nix.conf && \
    nix-env --option sandbox false -iA \
        nixpkgs.npins

# Default command passed to entrypoint (inherited from common base)
CMD []
