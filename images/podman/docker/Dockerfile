ARG RUNTIME_PARENT_IMAGE=ghcr.io/shaogme/coding-images/common:latest
FROM ${RUNTIME_PARENT_IMAGE} AS runtime
ARG TARGETARCH

WORKDIR /workspace

# Build only Podman's remote CLI. The engine, OCI runtime, monitor, network
# stack, and storage live in nixos-dockers/podman.
COPY docker/podman-remote.nix /tmp/podman-remote.nix
RUN set -eu; \
    podman_path="$(nix build --impure --no-link --print-out-paths --file /tmp/podman-remote.nix)"; \
    nix profile add "$podman_path" 'nixpkgs#podman-compose^out'; \
    nix store gc

COPY .config/dev-env.toml /etc/dev-env/profiles.d/30-coding-images-podman.toml

# Keep the client from silently switching to a local storage backend when the
# engine service was not started or its socket volume was not mounted.
COPY docker/podman-remote.sh /usr/local/bin/podman
COPY docker/podman-compose-remote.sh /usr/local/bin/podman-compose
RUN chmod 0755 /usr/local/bin/podman /usr/local/bin/podman-compose

ENV CONTAINER_HOST=unix:///run/podman/podman.sock \
    DOCKER_HOST=unix:///run/podman/podman.sock

RUN rm -f /etc/dev-env/default-profile && printf 'coding-images-podman\n' > /etc/dev-env/default-profile
