#!/usr/bin/env bash
set -e

# ==========================================
# QEMU & Virtualization Device Node Setup
# ==========================================
# Ensure /dev/kvm, /dev/net/tun, and /dev/fuse are accessible to non-root users
for dev_node in /dev/kvm /dev/net/tun /dev/fuse; do
    if [ -e "$dev_node" ]; then
        chmod 666 "$dev_node" 2>/dev/null || true
    fi
done

# Ensure /data/qemu exists and has shared permissions
mkdir -p /data/qemu 2>/dev/null || true
chmod 1777 /data/qemu 2>/dev/null || true

# Hand over to the standard mise entrypoint
exec /usr/local/bin/mise-entrypoint.sh "$@"
