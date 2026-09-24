ARG RUNTIME_PARENT_IMAGE=ghcr.io/shaogme/coding-images/common:latest
FROM ${RUNTIME_PARENT_IMAGE} AS runtime
ARG TARGETARCH

WORKDIR /workspace

# Install Podman, crun runtime, conmon, and podman-compose via nix profile
RUN nix profile add \
        nixpkgs#podman \
        nixpkgs#crun \
        nixpkgs#conmon \
        nixpkgs#podman-compose

COPY .config/dev-env.toml /etc/dev-env/profiles.d/30-coding-images-podman.toml

# Configure Podman engine defaults
RUN { \
        echo '[containers]'; \
        echo 'cgroups = "enabled"'; \
        echo 'cgroupns = "private"'; \
        echo 'events_logger = "file"'; \
        echo 'netavark_enabled = true'; \
        echo ''; \
        echo '[engine]'; \
        echo 'cgroup_manager = "cgroupfs"'; \
        echo 'runtime = "crun"'; \
        echo 'runtimes.crun = ["/nix/var/nix/profiles/default/bin/crun", "/usr/bin/crun"]'; \
        echo 'compose_providers = ["/nix/var/nix/profiles/default/bin/podman-compose", "podman-compose"]'; \
    } > /etc/containers/containers.conf

RUN rm -f /etc/dev-env/default-profile && printf 'coding-images-podman\n' > /etc/dev-env/default-profile
