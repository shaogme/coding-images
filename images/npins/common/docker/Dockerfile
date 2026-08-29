ARG BASE_IMAGE=ghcr.io/shaogme/coding-images/common:latest
FROM ${BASE_IMAGE}

WORKDIR /root/workspace

# Install npins dependency pin tool via nix-env on top of common
RUN --mount=type=cache,target=/root/.cache/nix \
    --mount=type=cache,target=/tmp \
    echo "sandbox = false" >> /etc/nix/nix.conf && \
    nix-env --option sandbox false -iA \
        nixpkgs.npins

# Copy workspace source code
COPY . /root/workspace/

# Default command passed to entrypoint (inherited from common base)
CMD []
