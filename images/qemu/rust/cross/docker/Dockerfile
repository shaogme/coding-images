ARG BASE_IMAGE=ghcr.io/shaogme/coding-images/qemu-rust-common:latest
FROM ${BASE_IMAGE}
ARG TARGETARCH

WORKDIR /workspace

# Copy cross-compilation mise delta configuration into conf.d
COPY .config/mise.toml /etc/mise/conf.d/30-cross.toml

# Declaratively lock global toolchain versions and pre-install cross tools
RUN --mount=type=secret,id=GITHUB_TOKEN,env=GITHUB_TOKEN,required=false \
    --mount=type=cache,id=tmp-build-${TARGETARCH},target=/tmp,sharing=shared \
    set -e; \
    echo "Pre-installing Rust cross-compilation tools during docker build..."; \
    mise trust --all; \
    mise lock --global --platform linux-x64,linux-arm64; \
    mise install;

# Default command passed to entrypoint (inherited from qemu-rust-common base)
CMD []
