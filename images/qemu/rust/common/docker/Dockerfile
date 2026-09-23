ARG NIXOS_DOCKERS_VERSION=latest
ARG BASE_IMAGE=ghcr.io/shaogme/coding-images/qemu-common:latest
ARG BUILDER_IMAGE=ghcr.io/shaogme/nixos-dockers/mise-builder:${NIXOS_DOCKERS_VERSION}

FROM ${BASE_IMAGE} AS runtime-base
RUN mkdir -p /etc/mise /usr/local/share/mise /data/cache/mise \
    /usr/local/share/rustup /usr/local/share/cargo /usr/local/share/pnpm

FROM ${BUILDER_IMAGE} AS mise-tools
ARG TARGETARCH

WORKDIR /workspace

# Set Rustup and PNPM environment variables for multi-user access
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
COPY .config/mise.toml /etc/mise/conf.d/20-rust.toml

RUN --mount=type=secret,id=GITHUB_TOKEN,env=GITHUB_TOKEN,required=false \
    set -eu; \
    echo "Pre-installing Rust toolchains and Node tools during docker build..."; \
    mise trust --all; \
    mise lock --global --platform linux-x64,linux-arm64; \
    mise install; \
    TRIPLE=$(rustc -vV 2>/dev/null | sed -n 's/host: //p' || echo "$(uname -m)-unknown-linux-gnu"); \
    cd "${RUSTUP_HOME}/toolchains"; \
    LATEST_NIGHTLY=$(ls -d nightly-[0-9]* 2>/dev/null | sort -V | tail -n 1); \
    if [ -n "$LATEST_NIGHTLY" ]; then \
        echo "Linking nightly toolchain aliases for ${LATEST_NIGHTLY}..."; \
        ln -sfn "$LATEST_NIGHTLY" "nightly-${TRIPLE}"; \
        ln -sfn "$LATEST_NIGHTLY" "nightly"; \
        if [ -d "${RUSTUP_HOME}/update-hashes" ] && [ -f "${RUSTUP_HOME}/update-hashes/${LATEST_NIGHTLY}" ]; then \
            ln -sfn "$LATEST_NIGHTLY" "${RUSTUP_HOME}/update-hashes/nightly-${TRIPLE}"; \
            ln -sfn "$LATEST_NIGHTLY" "${RUSTUP_HOME}/update-hashes/nightly"; \
        fi; \
    fi; \
    if ! rustup toolchain list | grep -q "^nightly"; then \
        echo "Error: No nightly Rust toolchain found after linking" >&2; \
        exit 1; \
    fi; \
    chmod -R 1777 /usr/local/share/rustup /usr/local/share/cargo /usr/local/share/pnpm 2>/dev/null || true;

FROM runtime-base
ARG TARGETARCH

WORKDIR /workspace

COPY .config/mise.toml /etc/mise/conf.d/20-rust.toml
COPY .config/dev-env.toml /etc/dev-env/profiles.d/40-coding-images-qemu-rust.toml
COPY --from=mise-tools /etc/mise /etc/mise
COPY --from=mise-tools /usr/local/share/mise /usr/local/share/mise
COPY --from=mise-tools /data/cache/mise /data/cache/mise
COPY --from=mise-tools /usr/local/share/rustup /usr/local/share/rustup
COPY --from=mise-tools /usr/local/share/cargo /usr/local/share/cargo
COPY --from=mise-tools /usr/local/share/pnpm /usr/local/share/pnpm

RUN set -e; \
    for shared_dir in /usr/local/share/mise /usr/local/share/rustup /usr/local/share/cargo /usr/local/share/pnpm; do \
        if [ -d "$shared_dir" ]; then \
            chmod -R a+rwX "$shared_dir"; \
            find "$shared_dir" -type d -exec chmod 0777 {} +; \
        fi; \
    done

# Install rust debug tools
RUN nix profile add \
    nixpkgs#valgrind \
    nixpkgs#gdb \
    nixpkgs#lldb \
    nixpkgs#llvmPackages.llvm \
    nixpkgs#perf \
    nixpkgs#elfutils

RUN rm -f /etc/dev-env/default-profile && printf 'coding-images-qemu-rust\n' > /etc/dev-env/default-profile
