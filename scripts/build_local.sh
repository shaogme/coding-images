#!/usr/bin/env bash
set -e

# ==============================================================================
# Script: scripts/build_local.sh
# Description: Builds coding-images Docker images locally in dependency order.
# ==============================================================================

REPO_PREFIX="${REPO_PREFIX:-ghcr.io/shaogme/coding-images}"
TARGET="${1:-all}"

echo "========================================================"
echo "  Building Coding Images Locally (Target: ${TARGET})"
echo "  Image Prefix: ${REPO_PREFIX}"
echo "========================================================"

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

case "$TARGET" in
    common)
        build_image "common" "images/common/docker/Dockerfile" "images/common" ""
        ;;
    rust-common)
        build_image "rust-common" "images/rust/common/docker/Dockerfile" "images/rust/common" "${REPO_PREFIX}/common:latest"
        ;;
    npins-common)
        build_image "npins-common" "images/npins/common/docker/Dockerfile" "images/npins/common" "${REPO_PREFIX}/common:latest"
        ;;
    rust-wasm)
        build_image "rust-wasm" "images/rust/wasm/docker/Dockerfile" "images/rust/wasm" "${REPO_PREFIX}/rust-common:latest"
        ;;
    rust-cross)
        build_image "rust-cross" "images/rust/cross/docker/Dockerfile" "images/rust/cross" "${REPO_PREFIX}/rust-common:latest"
        ;;
    npins-rust)
        build_image "npins-rust" "images/npins/rust/docker/Dockerfile" "images/npins/rust" "${REPO_PREFIX}/rust-common:latest"
        ;;
    all|*)
        echo "==> Stage 0: Building common base image..."
        build_image "common" "images/common/docker/Dockerfile" "images/common" ""

        echo "==> Stage 1: Building rust-common & npins-common..."
        build_image "rust-common" "images/rust/common/docker/Dockerfile" "images/rust/common" "${REPO_PREFIX}/common:latest"
        build_image "npins-common" "images/npins/common/docker/Dockerfile" "images/npins/common" "${REPO_PREFIX}/common:latest"

        echo "==> Stage 2: Building rust-wasm, rust-cross & npins-rust..."
        build_image "rust-wasm" "images/rust/wasm/docker/Dockerfile" "images/rust/wasm" "${REPO_PREFIX}/rust-common:latest"
        build_image "rust-cross" "images/rust/cross/docker/Dockerfile" "images/rust/cross" "${REPO_PREFIX}/rust-common:latest"
        build_image "npins-rust" "images/npins/rust/docker/Dockerfile" "images/npins/rust" "${REPO_PREFIX}/rust-common:latest"
        ;;
esac

echo ""
echo "========================================================"
echo "  Build finished successfully for: ${TARGET}"
echo "========================================================"
