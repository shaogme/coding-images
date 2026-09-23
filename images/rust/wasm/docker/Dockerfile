ARG NIXOS_DOCKERS_VERSION=latest
ARG BASE_IMAGE=ghcr.io/shaogme/coding-images/rust-common:latest
ARG BUILDER_IMAGE=ghcr.io/shaogme/nixos-dockers/mise-builder:${NIXOS_DOCKERS_VERSION}

FROM ${BASE_IMAGE} AS runtime-base
RUN mkdir -p /etc/mise /usr/local/share/mise /data/cache/mise \
    /usr/local/share/rustup /usr/local/share/cargo /usr/local/share/pnpm

FROM ${BUILDER_IMAGE} AS mise-tools
ARG TARGETARCH

WORKDIR /workspace

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
COPY --from=runtime-base /usr/local/share/rustup /usr/local/share/rustup
COPY --from=runtime-base /usr/local/share/cargo /usr/local/share/cargo
COPY --from=runtime-base /usr/local/share/pnpm /usr/local/share/pnpm
COPY .config/mise.toml /etc/mise/conf.d/30-wasm.toml

RUN --mount=type=secret,id=GITHUB_TOKEN,env=GITHUB_TOKEN,required=false \
    set -eu; \
    echo "Locking global toolchain specifications and WebAssembly targets..."; \
    mise trust --all; \
    mise lock --global --platform linux-x64,linux-arm64; \
    mise install;

FROM runtime-base
ARG TARGETARCH

WORKDIR /workspace

# Install WebAssembly and headless browser testing packages via nix profile.
RUN nix profile add \
        nixpkgs#fontconfig \
        nixpkgs#dejavu_fonts \
        nixpkgs#mesa \
        nixpkgs#firefox \
        nixpkgs#geckodriver

# Configure fontconfig and silent Firefox headless preferences via enterprise policies.
RUN set -e; \
    mkdir -p /etc/fonts; \
    if [ -d /nix/var/nix/profiles/default/etc/fonts ]; then \
        cp -rL /nix/var/nix/profiles/default/etc/fonts/* /etc/fonts/ 2>/dev/null || true; \
    elif [ -d /root/.nix-profile/etc/fonts ]; then \
        cp -rL /root/.nix-profile/etc/fonts/* /etc/fonts/ 2>/dev/null || true; \
    fi; \
    fc-cache -fv || true; \
    mkdir -p /etc/firefox/policies; \
    { \
        echo '{'; \
        echo '  "policies": {'; \
        echo '    "DisableTelemetry": true,'; \
        echo '    "DisableFirefoxStudies": true,'; \
        echo '    "DisablePocket": true,'; \
        echo '    "DisableFeedbackCommands": true,'; \
        echo '    "Preferences": {'; \
        echo '      "app.normandy.enabled": false,'; \
        echo '      "app.normandy.api_url": "",'; \
        echo '      "app.shield.optoutstudies.enabled": false,'; \
        echo '      "datareporting.healthreport.uploadEnabled": false,'; \
        echo '      "datareporting.policy.dataSubmissionEnabled": false,'; \
        echo '      "toolkit.telemetry.enabled": false,'; \
        echo '      "toolkit.telemetry.unified": false,'; \
        echo '      "services.settings.server": "",'; \
        echo '      "browser.safebrowsing.blockedURIs.enabled": false,'; \
        echo '      "browser.safebrowsing.downloads.enabled": false,'; \
        echo '      "browser.safebrowsing.malware.enabled": false,'; \
        echo '      "browser.safebrowsing.phishing.enabled": false,'; \
        echo '      "browser.search.suggest.enabled": false,'; \
        echo '      "signon.rememberSignons": false'; \
        echo '    }'; \
        echo '  }'; \
        echo '}'; \
    } > /etc/firefox/policies/policies.json

COPY .config/dev-env.toml /etc/dev-env/profiles.d/40-coding-images-rust-wasm.toml
COPY --from=mise-tools /etc/mise /etc/mise
COPY --from=mise-tools /usr/local/share/mise /usr/local/share/mise
COPY --from=mise-tools /data/cache/mise /data/cache/mise
COPY --from=mise-tools /usr/local/share/rustup /usr/local/share/rustup
COPY --from=mise-tools /usr/local/share/cargo /usr/local/share/cargo
COPY --from=mise-tools /usr/local/share/pnpm /usr/local/share/pnpm

RUN rm -f /etc/dev-env/default-profile && printf 'coding-images-rust-wasm\n' > /etc/dev-env/default-profile
