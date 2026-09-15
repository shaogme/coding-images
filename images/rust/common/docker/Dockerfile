ARG BASE_IMAGE=ghcr.io/shaogme/coding-images/podman:latest
FROM ${BASE_IMAGE}
ARG TARGETARCH

WORKDIR /workspace

# Build-time locations for mise-installed Rust and Node tools. The same values
# are exported at runtime by .config/dev-env.toml.
ENV RUSTUP_HOME=/usr/local/share/rustup \
    PNPM_HOME=/usr/local/share/pnpm \
    PATH=/usr/local/share/pnpm/bin:/usr/local/share/pnpm:$PATH

COPY .config/mise.toml /etc/mise/conf.d/20-rust.toml
COPY .config/dev-env.toml /etc/dev-env/profiles.d/30-coding-images-rust.toml

# Pre-install global Rust tools and toolchains with BuildKit cache mounts and lock toolchain
RUN set -e; \
    if [ -r /run/secrets/GITHUB_TOKEN ]; then export GITHUB_TOKEN="$(cat /run/secrets/GITHUB_TOKEN)"; fi; \
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
    elif ! rustup toolchain list | grep -q "^nightly"; then \
        echo "Fallback: installing nightly toolchain directly via rustup..."; \
        rustup toolchain install nightly --component rust-src; \
    fi; \
    chmod -R 1777 /usr/local/share/rustup /usr/local/share/pnpm 2>/dev/null || true;

RUN set -e; \
    for shared_dir in /usr/local/share/mise /usr/local/share/rustup /usr/local/share/pnpm; do \
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

RUN printf 'coding-images-rust\n' > /etc/dev-env/default-profile
