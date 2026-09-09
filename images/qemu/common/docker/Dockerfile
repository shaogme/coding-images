ARG BASE_IMAGE=ghcr.io/shaogme/coding-images/podman:latest
FROM ${BASE_IMAGE}
ARG TARGETARCH

WORKDIR /workspace

# Copy custom entrypoint for automatic KVM, TUN, and FUSE device permissions
COPY --chmod=755 docker/entrypoint.sh /usr/local/bin/qemu-entrypoint.sh

# Install QEMU, OVMF firmware, swtpm, cloud-init utilities, ISO/disk tools, and virtual networking via nix profile
RUN --mount=type=cache,id=tmp-build-${TARGETARCH},target=/tmp,sharing=shared \
    nix profile add \
        nixpkgs#qemu \
        nixpkgs#OVMF.fd \
        nixpkgs#swtpm \
        nixpkgs#cloud-utils \
        nixpkgs#xorriso \
        nixpkgs#mtools \
        nixpkgs#dnsmasq \
        nixpkgs#bridge-utils \
        nixpkgs#socat

# Configure standard UEFI firmware symlinks, kvm group, and persistent VM data directory
RUN set -e; \
    # Ensure /usr/share/OVMF and /usr/share/qemu links exist for standard tools and scripts
    mkdir -p /usr/share/OVMF /usr/share/qemu /data/qemu; \
    if [ -d /nix/var/nix/profiles/default/FV ]; then \
        ln -sf /nix/var/nix/profiles/default/FV/OVMF.fd /usr/share/OVMF/OVMF.fd 2>/dev/null || true; \
        ln -sf /nix/var/nix/profiles/default/FV/OVMF_CODE.fd /usr/share/OVMF/OVMF_CODE.fd 2>/dev/null || true; \
        ln -sf /nix/var/nix/profiles/default/FV/OVMF_VARS.fd /usr/share/OVMF/OVMF_VARS.fd 2>/dev/null || true; \
        ln -sf /nix/var/nix/profiles/default/FV /usr/share/qemu/firmware-fv 2>/dev/null || true; \
    fi; \
    # Create kvm group if not present and append dev user
    groupadd -g 108 kvm 2>/dev/null || true; \
    usermod -aG kvm dev 2>/dev/null || true; \
    # Shared permissions for VM storage
    chmod 1777 /data/qemu

# Set the QEMU-aware entrypoint wrapper
ENTRYPOINT ["/usr/local/bin/qemu-entrypoint.sh"]

# Default command passed to entrypoint (inherited from common base)
CMD []
