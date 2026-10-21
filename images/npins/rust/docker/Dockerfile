ARG RUNTIME_PARENT_IMAGE=ghcr.io/shaogme/coding-images/rust-common:latest
FROM ${RUNTIME_PARENT_IMAGE} AS runtime
ARG TARGETARCH

WORKDIR /workspace

# Install npins dependency pin tool via nix profile on top of rust-common
RUN nix profile add \
        nixpkgs#npins && \
    npins_binary="$(readlink -f /root/.nix-profile/bin/npins)" && \
    mkdir -p /usr/local/share/npins/bin && \
    printf '#!/bin/sh\nunset LD_LIBRARY_PATH\nexec "%s" "$@"\n' \
        "$npins_binary" > /usr/local/share/npins/bin/npins && \
    chmod 0755 /usr/local/share/npins/bin/npins && \
    printf '%s\n' \
        '#!/bin/sh' \
        'printf "%s\n" "export PATH=\"/usr/local/share/npins/bin\""' \
        > /usr/local/share/npins/npins-path-env && \
    chmod 0755 /usr/local/share/npins/npins-path-env && \
    printf "%s\n" \
        "" \
        "[config.providers.npins-path]" \
        "executable = \"/usr/local/share/npins/npins-path-env\"" \
        "depends_on = [\"devbox-global\", \"devbox-init\"]" \
        "[config.providers.npins-path.shellenv]" \
        "argv = [\"shellenv\"]" \
        "format = \"shell\"" \
        "path_mode = \"merge\"" \
        "failure = \"error\"" \
        >> /etc/dev-env/profiles.d/20-coding-images.toml && \
    /usr/local/share/npins/bin/npins --version
