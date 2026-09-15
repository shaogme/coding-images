ARG BASE_IMAGE=ghcr.io/shaogme/coding-images/rust-common:latest
FROM ${BASE_IMAGE}
ARG TARGETARCH

WORKDIR /workspace

# Install WebAssembly and headless browser testing packages via nix profile
RUN nix profile add \
        nixpkgs#fontconfig \
        nixpkgs#dejavu_fonts \
        nixpkgs#mesa \
        nixpkgs#firefox \
        nixpkgs#geckodriver

# Configure fontconfig and silent Firefox headless preferences via enterprise policies
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

COPY .config/mise.toml /etc/mise/conf.d/30-wasm.toml
COPY .config/dev-env.toml /etc/dev-env/profiles.d/40-coding-images-rust-wasm.toml

# Declaratively lock global toolchain versions and pre-install WebAssembly tools/targets
RUN --mount=type=secret,id=GITHUB_TOKEN,env=GITHUB_TOKEN,required=false \
    set -e; \
    echo "Locking global toolchain specifications and WebAssembly targets..."; \
    RUN_AS_ROOT=1 mise trust --all; \
    RUN_AS_ROOT=1 mise lock --global --platform linux-x64,linux-arm64; \
    RUN_AS_ROOT=1 mise install;

RUN printf 'coding-images-rust-wasm\n' > /etc/dev-env/default-profile
