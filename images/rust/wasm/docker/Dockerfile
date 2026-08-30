ARG BASE_IMAGE=ghcr.io/shaogme/coding-images/rust-common:latest
FROM ${BASE_IMAGE}
ARG TARGETARCH

WORKDIR /root/workspace

# Install WebAssembly and headless browser testing packages via nix-env
RUN --mount=type=cache,id=nix-cache,target=/root/.cache/nix,sharing=shared \
    --mount=type=cache,id=tmp-build-${TARGETARCH},target=/tmp,sharing=shared \
    echo "sandbox = false" >> /etc/nix/nix.conf && \
    nix-env --option sandbox false -iA \
        nixpkgs.fontconfig \
        nixpkgs.dejavu_fonts \
        nixpkgs.mesa \
        nixpkgs.firefox \
        nixpkgs.geckodriver

# Set headless browser and fontconfig environment variables
ENV FONTCONFIG_PATH=/root/.nix-profile/etc/fonts \
    FONTCONFIG_FILE=/root/.nix-profile/etc/fonts/fonts.conf \
    MOZ_HEADLESS=1 \
    LIBGL_ALWAYS_SOFTWARE=1

# Configure fontconfig and silent Firefox headless preferences via enterprise policies
RUN set -e; \
    mkdir -p /etc/fonts; \
    if [ -f /root/.nix-profile/etc/fonts/fonts.conf ]; then \
        ln -sf /root/.nix-profile/etc/fonts/fonts.conf /etc/fonts/fonts.conf; \
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

COPY .config/mise.toml /root/.config/mise/conf.d/30-wasm.toml

# Declaratively lock global toolchain versions and pre-install WebAssembly tools/targets
RUN --mount=type=secret,id=GITHUB_TOKEN,env=GITHUB_TOKEN,required=false \
    --mount=type=cache,id=mise-cache-${TARGETARCH},target=/root/.cache/mise,sharing=shared \
    --mount=type=cache,id=cargo-registry,target=/root/.cargo/registry,sharing=shared \
    --mount=type=cache,id=cargo-git,target=/root/.cargo/git,sharing=shared \
    --mount=type=cache,id=cargo-target-${TARGETARCH},target=/root/.cargo/target,sharing=shared \
    --mount=type=cache,id=tmp-build-${TARGETARCH},target=/tmp,sharing=shared \
    set -e; \
    echo "Locking global toolchain specifications and WebAssembly targets..."; \
    mise trust --all; \
    mise lock --global --platform linux-x64,linux-arm64; \
    mise install;

# Default command passed to entrypoint (inherited from common base)
CMD []
