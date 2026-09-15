#!/usr/bin/env bash
set -e

# ==============================================================================
# Script: scripts/build_local.sh
# Description: Builds coding-images Docker images locally in dependency order.
# ==============================================================================

REPO_PREFIX="${REPO_PREFIX:-ghcr.io/shaogme/coding-images}"
BASE_IMAGE_OVERRIDE="${BASE_IMAGE_OVERRIDE:-}"
TARGET="${1:-all}"

echo "========================================================"
echo "  Building Coding Images Locally (Target: ${TARGET})"
echo "  Image Prefix: ${REPO_PREFIX}"
echo "========================================================"

declare -A BUILT_TARGETS=()

build_image() {
    local img_name="$1"
    local dockerfile="$2"
    local context="$3"
    local base_arg="$4"

    echo ""
    echo "--------------------------------------------------------"
    echo "==> Building image: ${REPO_PREFIX}/${img_name}:latest"
    echo "    Dockerfile: ${dockerfile}"
    echo "    Context:    ${context}"
    if [ -n "$base_arg" ]; then
        echo "    Base Image: ${base_arg}"
    fi
    echo "--------------------------------------------------------"

    local cmd=(docker build -t "${REPO_PREFIX}/${img_name}:latest" -f "${dockerfile}")
    if [ -n "$base_arg" ]; then
        cmd+=(--build-arg "BASE_IMAGE=${base_arg}")
    fi
    cmd+=("${context}")

    "${cmd[@]}"
}

build_target() {
    local target="$1"
    if [[ "${BUILT_TARGETS[$target]:-}" == 1 ]]; then
        return
    fi

    case "$target" in
        common)
            build_image "common" "images/common/docker/Dockerfile" "images/common" "${BASE_IMAGE_OVERRIDE}"
            ;;
        podman)
            build_target common
            build_image "podman" "images/podman/docker/Dockerfile" "images/podman" "${REPO_PREFIX}/common:latest"
            ;;
        npins-common)
            build_target common
            build_image "npins-common" "images/npins/common/docker/Dockerfile" "images/npins/common" "${REPO_PREFIX}/common:latest"
            ;;
        rust-common)
            build_target podman
            build_image "rust-common" "images/rust/common/docker/Dockerfile" "images/rust/common" "${REPO_PREFIX}/podman:latest"
            ;;
        qemu-common)
            build_target podman
            build_image "qemu-common" "images/qemu/common/docker/Dockerfile" "images/qemu/common" "${REPO_PREFIX}/podman:latest"
            ;;
        rust-wasm)
            build_target rust-common
            build_image "rust-wasm" "images/rust/wasm/docker/Dockerfile" "images/rust/wasm" "${REPO_PREFIX}/rust-common:latest"
            ;;
        rust-cross)
            build_target rust-common
            build_image "rust-cross" "images/rust/cross/docker/Dockerfile" "images/rust/cross" "${REPO_PREFIX}/rust-common:latest"
            ;;
        npins-rust)
            build_target rust-common
            build_image "npins-rust" "images/npins/rust/docker/Dockerfile" "images/npins/rust" "${REPO_PREFIX}/rust-common:latest"
            ;;
        qemu-rust-common)
            build_target qemu-common
            build_image "qemu-rust-common" "images/qemu/rust/common/docker/Dockerfile" "images/qemu/rust/common" "${REPO_PREFIX}/qemu-common:latest"
            ;;
        qemu-rust-cross)
            build_target qemu-rust-common
            build_image "qemu-rust-cross" "images/qemu/rust/cross/docker/Dockerfile" "images/qemu/rust/cross" "${REPO_PREFIX}/qemu-rust-common:latest"
            ;;
        all)
            for target in common podman npins-common rust-common qemu-common rust-wasm rust-cross npins-rust qemu-rust-common qemu-rust-cross; do
                build_target "$target"
            done
            ;;
        *)
            echo "Unknown target: $target" >&2
            return 2
            ;;
    esac
    BUILT_TARGETS[$target]=1
}

build_target "$TARGET"

echo ""
echo "========================================================"
echo "  Build finished successfully for: ${TARGET}"
echo "========================================================"
