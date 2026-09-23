ARG BASE_IMAGE=ghcr.io/shaogme/coding-images/podman:latest
FROM ${BASE_IMAGE}
ARG TARGETARCH

WORKDIR /workspace

# Install QEMU, OVMF firmware, swtpm, cloud-init utilities, ISO/disk tools, and virtual networking via nix profile
RUN nix profile add \
        nixpkgs#qemu \
        nixpkgs#OVMF.fd \
        nixpkgs#swtpm \
        nixpkgs#cloud-utils \
        nixpkgs#xorriso \
        nixpkgs#mtools \
        nixpkgs#dnsmasq \
        nixpkgs#bridge-utils \
        nixpkgs#socat \
        nixpkgs#openssh \
        nixpkgs#sshpass

COPY .config/dev-env.toml /etc/dev-env/profiles.d/30-coding-images-qemu.toml

# Configure standard UEFI firmware symlinks, kvm group, and persistent VM data directory.
# /dev/kvm is a host device; its mode is controlled by the container runtime and
# must not be changed from the image bootstrap process.
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

RUN rm -f /etc/dev-env/default-profile && printf 'coding-images-qemu\n' > /etc/dev-env/default-profile
