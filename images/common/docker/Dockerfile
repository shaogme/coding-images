ARG BASE_IMAGE=ghcr.io/shaogme/nixos-dockers/mise:latest
FROM ${BASE_IMAGE}
ARG TARGETARCH

WORKDIR /root/workspace

# Copy custom entrypoint for automatic mise environment loading
COPY --chmod=755 docker/entrypoint.sh /usr/local/bin/mise-entrypoint.sh

# Set base PATH
ENV PATH=/root/.cargo/bin:/root/.nix-profile/bin:$PATH

# Install system-level binaries via nix-env with BuildKit cache mount & binary mirror
RUN --mount=type=cache,id=nix-cache,target=/root/.cache/nix,sharing=shared \
    --mount=type=cache,id=tmp-build-${TARGETARCH},target=/tmp,sharing=shared \
    echo "sandbox = false" >> /etc/nix/nix.conf && \
    nix-env --option sandbox false -iA \
        nixpkgs.bubblewrap

# Configure direnv global defaults and workspace whitelist
RUN mkdir -p /root/.config/direnv /root/.local/share/direnv && \
    printf '[whitelist]\nprefix = [ "/root/workspace" ]\n' > /root/.config/direnv/direnv.toml && \
    printf 'type -P mise &>/dev/null && eval "$(mise direnv activate 2>/dev/null || true)"\n' > /root/.config/direnv/direnvrc

# Configure declarative cargo and binstall defaults
RUN mkdir -p /root/.cargo
COPY .config/cargo.toml /root/.cargo/config.toml
COPY .config/binstall.toml /root/.cargo/binstall.toml

# 1. Copy global mise base configuration into conf.d
RUN mkdir -p /root/.config/mise/conf.d
COPY .config/mise.toml /root/.config/mise/conf.d/10-common.toml

# Pre-install global common mise tools and lock global tool versions
RUN --mount=type=secret,id=GITHUB_TOKEN,env=GITHUB_TOKEN,required=false \
    --mount=type=cache,id=mise-cache-${TARGETARCH},target=/root/.cache/mise,sharing=shared \
    --mount=type=cache,id=cargo-registry,target=/root/.cargo/registry,sharing=shared \
    --mount=type=cache,id=cargo-git,target=/root/.cargo/git,sharing=shared \
    --mount=type=cache,id=cargo-target-${TARGETARCH},target=/root/.cargo/target,sharing=shared \
    --mount=type=cache,id=tmp-build-${TARGETARCH},target=/tmp,sharing=shared \
    set -e; \
    echo "Pre-installing common mise tools during docker build..."; \
    mise trust --all; \
    mise lock --global --platform linux-x64,linux-arm64; \
    mise install;

# Set the custom entrypoint
ENTRYPOINT ["/usr/local/bin/mise-entrypoint.sh"]

# Default command passed to entrypoint (empty to trigger default behavior: sshd or bash)
CMD []
