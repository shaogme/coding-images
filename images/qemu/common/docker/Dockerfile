ARG RUNTIME_PARENT_IMAGE=ghcr.io/shaogme/coding-images/podman:latest
FROM ${RUNTIME_PARENT_IMAGE} AS runtime
ARG TARGETARCH

WORKDIR /workspace

# Build a QEMU variant without graphical, remote-display, audio, or 3D backends.
COPY docker/qemu-headless.nix /tmp/qemu-headless.nix
RUN set -eu; \
    qemu_path="$(nix build --impure --no-link --print-out-paths --file /tmp/qemu-headless.nix)"; \
    rm -rf /homeless-shelter /homeless-shelter-qemu-headless; \
    nix profile add "$qemu_path" \
        'nixpkgs#OVMF.fd^out' \
        'nixpkgs#swtpm^out' \
        'nixpkgs#cloud-utils^out' \
        'nixpkgs#xorriso^out' \
        'nixpkgs#mtools^out' \
        'nixpkgs#dnsmasq^out' \
        'nixpkgs#bridge-utils^out' \
        'nixpkgs#socat^out' \
        'nixpkgs#openssh^out' \
        'nixpkgs#sshpass^out'; \
    rm -rf /homeless-shelter /homeless-shelter-qemu-headless; \
    rm -f /tmp/qemu-headless.nix; \
    nix store gc

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
