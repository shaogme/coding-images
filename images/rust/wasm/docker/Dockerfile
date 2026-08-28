ARG BASE_IMAGE=ghcr.io/shaogme/nixos-dockers/mise:latest
FROM ${BASE_IMAGE}

WORKDIR /root/workspace

# Copy custom entrypoint for automatic mise environment loading
COPY --chmod=755 docker/entrypoint.sh /usr/local/bin/mise-entrypoint.sh

# Enable non-interactive auto-confirm for mise
ENV MISE_YES=1

# Install system-level binaries via nix-env with BuildKit cache mount & binary mirror
RUN --mount=type=cache,target=/root/.cache/nix \
    --mount=type=cache,target=/tmp \
    echo "sandbox = false" >> /etc/nix/nix.conf && \
    nix-env --option sandbox false -iA \
        nixpkgs.bubblewrap \
        nixpkgs.fontconfig \
        nixpkgs.dejavu_fonts \
        nixpkgs.mesa \
        nixpkgs.firefox \
        nixpkgs.geckodriver \
        nixpkgs.zola

# Set the PNPM, PATH and Headless / Fontconfig environment variables
ENV PNPM_HOME=/root/.local/share/pnpm \
    PATH=/root/.local/share/pnpm/bin:/root/.local/share/pnpm:/root/.cargo/bin:/root/.nix-profile/bin:$PATH \
    FONTCONFIG_PATH=/root/.nix-profile/etc/fonts \
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

# 1. Copy global mise configuration to ~/.config/mise/config.toml
COPY .config/mise.toml /root/.config/mise/config.toml

# Pre-install global mise tools and Rust targets with BuildKit cache mounts
RUN --mount=type=cache,target=/root/.cache/mise \
    --mount=type=cache,target=/root/.cargo/registry \
    --mount=type=cache,target=/root/.cargo/git \
    set -e; \
    echo "Pre-installing mise tools and Rust targets during docker build..."; \
    mise trust --all; \
    mise install;

# 2. Copy the rest of the workspace source code
COPY . /root/workspace/

# Set the custom entrypoint
ENTRYPOINT ["/usr/local/bin/mise-entrypoint.sh"]

# Default command passed to entrypoint (empty to trigger default behavior: sshd or bash)
CMD []

