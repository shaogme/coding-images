ARG BASE_IMAGE=ghcr.io/shaogme/coding-images/rust-common:latest
FROM ${BASE_IMAGE}
ARG TARGETARCH

WORKDIR /workspace

# Install Podman, crun runtime, and container virtualization packages via nix-env
RUN --mount=type=cache,id=tmp-build-${TARGETARCH},target=/tmp,sharing=shared \
    echo "sandbox = false" >> /etc/nix/nix.conf && \
    nix-env --option sandbox false -iA \
        nixpkgs.podman \
        nixpkgs.crun \
        nixpkgs.conmon

# Configure Podman engine defaults and container runtime for in-container execution
ENV CROSS_CONTAINER_ENGINE=podman

RUN set -e; \
    mkdir -p /etc/containers; \
    { \
        echo '[containers]'; \
        echo 'cgroup_manager = "cgroupfs"'; \
        echo 'events_logger = "file"'; \
        echo 'netavark_enabled = true'; \
        echo ''; \
        echo '[engine]'; \
        echo 'runtime = "crun"'; \
        echo 'runtimes.crun = ["/nix/var/nix/profiles/default/bin/crun", "/usr/bin/crun"]'; \
    } > /etc/containers/containers.conf; \
    # Create docker and docker-compose masquerade wrappers for podman
    printf '#!/usr/bin/env bash\nexec podman "$@"\n' > /usr/local/bin/docker; \
    chmod 755 /usr/local/bin/docker; \
    printf '#!/usr/bin/env bash\nexec podman compose "$@"\n' > /usr/local/bin/docker-compose; \
    chmod 755 /usr/local/bin/docker-compose; \
    mkdir -p /var/run /run/podman; \
    chmod 1777 /var/run /run/podman; \
    ln -sf /run/podman/podman.sock /var/run/docker.sock

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

# Default command passed to entrypoint (inherited from common base)
CMD []
