#!/usr/bin/env bash
set -Eeuo pipefail

# Build the same runtime/builder topology used by CI. Builder archives stay
# local and are never tagged with the public runtime repository name.
REPO_PREFIX="${REPO_PREFIX:-ghcr.io/shaogme/coding-images}"
RUNTIME_PARENT_IMAGE_OVERRIDE="${RUNTIME_PARENT_IMAGE_OVERRIDE:-}"
BUILDER_PARENT_IMAGE_OVERRIDE="${BUILDER_PARENT_IMAGE_OVERRIDE:-}"
NIXOS_DOCKERS_VERSION="${NIXOS_DOCKERS_VERSION:-latest}"
TARGET="${1:-all}"
BUILD_ENGINE="${BUILD_ENGINE:-docker}"
BUILDER_ARCHIVE_DIR="${BUILDER_ARCHIVE_DIR:-${TMPDIR:-/tmp}/coding-images-artifacts}"

if ! command -v "$BUILD_ENGINE" >/dev/null 2>&1; then
    echo "Build engine not found: ${BUILD_ENGINE}" >&2
    exit 127
fi

case "$(uname -m)" in
    x86_64|amd64) ARCH=amd64; PLATFORM=linux/amd64 ;;
    aarch64|arm64) ARCH=arm64; PLATFORM=linux/arm64 ;;
    *) echo "Unsupported host architecture: $(uname -m)" >&2; exit 2 ;;
esac

BUILD_ENGINE_PATH="$(command -v "$BUILD_ENGINE")"
BUILD_ENGINE_REALPATH="$(readlink -f "$BUILD_ENGINE_PATH" 2>/dev/null || printf '%s' "$BUILD_ENGINE_PATH")"
BUILD_ENGINE_VERSION="$($BUILD_ENGINE --version 2>&1 || true)"
if [[ "$(basename "$BUILD_ENGINE_REALPATH")" == podman || "${BUILD_ENGINE_VERSION,,}" == *podman* ]]; then
    USE_PODMAN=1
else
    USE_PODMAN=0
fi

mkdir -p "$BUILDER_ARCHIVE_DIR"

declare -A BUILT_TARGETS=()
declare -A RUNTIME_TAGS=()
declare -A BUILDER_TAGS=()

echo "========================================================"
echo "  Building Coding Images Locally (Target: ${TARGET})"
echo "  Image Prefix: ${REPO_PREFIX}"
echo "  Architecture: ${ARCH} (${PLATFORM})"
echo "  NixOS Docker version: ${NIXOS_DOCKERS_VERSION}"
echo "========================================================"

ensure_upstream_tags() {
    if ! "$BUILD_ENGINE" image inspect local/coding-images/mise:${ARCH} >/dev/null 2>&1; then
        local runtime_parent="${RUNTIME_PARENT_IMAGE_OVERRIDE:-ghcr.io/shaogme/nixos-dockers/mise:${NIXOS_DOCKERS_VERSION}}"
        "$BUILD_ENGINE" pull --platform "$PLATFORM" "$runtime_parent"
        "$BUILD_ENGINE" tag "$runtime_parent" local/coding-images/mise:${ARCH}
    fi
    if ! "$BUILD_ENGINE" image inspect local/coding-images/mise-builder:${ARCH} >/dev/null 2>&1; then
        local builder_parent="${BUILDER_PARENT_IMAGE_OVERRIDE:-ghcr.io/shaogme/nixos-dockers/mise-builder:${NIXOS_DOCKERS_VERSION}}"
        "$BUILD_ENGINE" pull --platform "$PLATFORM" "$builder_parent"
        "$BUILD_ENGINE" tag "$builder_parent" local/coding-images/mise-builder:${ARCH}
    fi
}

build_command() {
    local target="$1" dockerfile="$2" context="$3" runtime_parent="$4" builder_parent="$5" build_target="$6" tag="$7"
    local cmd=("$BUILD_ENGINE" build --platform "$PLATFORM" --target "$build_target" -t "$tag" -f "$dockerfile")
    cmd+=(--build-arg "NIXOS_DOCKERS_VERSION=${NIXOS_DOCKERS_VERSION}")
    cmd+=(--build-arg "RUNTIME_PARENT_IMAGE=${runtime_parent}")
    cmd+=(--build-arg "BUILDER_PARENT_IMAGE=${builder_parent}")
    if (( USE_PODMAN )); then
        if [[ -n "${GITHUB_TOKEN:-}" ]]; then
            cmd+=(--secret "id=GITHUB_TOKEN,env=GITHUB_TOKEN")
        fi
    fi
    cmd+=("$context")
    echo "==> ${target}: ${build_target}"
    "${cmd[@]}"
}

archive_builder() {
    local image_name="$1" tag="$2"
    local archive="${BUILDER_ARCHIVE_DIR}/builder-${image_name}-${ARCH}.tar.gz"
    "$BUILD_ENGINE" save "$tag" | gzip -1 > "$archive"
    (cd "$(dirname "$archive")" && sha256sum "$(basename "$archive")") > "${archive%.tar.gz}.sha256"
    # Exercise the same load protocol used by CI and leave the deterministic
    # local tag available for descendants.
    gzip -dc "$archive" | "$BUILD_ENGINE" load >/dev/null
    BUILDER_TAGS["$image_name"]="$tag"
}

build_image() {
    local image_name="$1" dockerfile="$2" context="$3" runtime_parent="$4" builder_parent="$5" mode="$6"
    local runtime_tag="${REPO_PREFIX}/${image_name}:latest"
    if [[ "$mode" == mise ]]; then
        local builder_tag="local/coding-images/${image_name}-builder:${ARCH}"
        build_command "$image_name" "$dockerfile" "$context" "$runtime_parent" "$builder_parent" mise-builder "$builder_tag"
        archive_builder "$image_name" "$builder_tag"
    else
        # Passthrough nodes reuse their nearest real builder tag without
        # creating an archive or a second builder image.
        BUILDER_TAGS["$image_name"]="$builder_parent"
    fi
    build_command "$image_name" "$dockerfile" "$context" "$runtime_parent" "${BUILDER_TAGS[$image_name]:-$builder_parent}" runtime "$runtime_tag"
    RUNTIME_TAGS["$image_name"]="$runtime_tag"
}

build_target() {
    local target="$1"
    [[ "${BUILT_TARGETS[$target]:-}" == 1 ]] && return
    ensure_upstream_tags

    case "$target" in
        common)
            build_image common images/common/docker/Dockerfile images/common \
                local/coding-images/mise:${ARCH} local/coding-images/mise-builder:${ARCH} mise
            ;;
        podman)
            build_target common
            build_image podman images/podman/docker/Dockerfile images/podman \
                "${RUNTIME_TAGS[common]}" "${BUILDER_TAGS[common]}" passthrough
            ;;
        npins-common)
            build_target common
            build_image npins-common images/npins/common/docker/Dockerfile images/npins/common \
                "${RUNTIME_TAGS[common]}" "${BUILDER_TAGS[common]}" passthrough
            ;;
        rust-common)
            build_target podman
            build_image rust-common images/rust/common/docker/Dockerfile images/rust/common \
                "${RUNTIME_TAGS[podman]}" "${BUILDER_TAGS[common]}" mise
            ;;
        qemu-common)
            build_target podman
            build_image qemu-common images/qemu/common/docker/Dockerfile images/qemu/common \
                "${RUNTIME_TAGS[podman]}" "${BUILDER_TAGS[common]}" passthrough
            BUILDER_TAGS[qemu-common]="local/coding-images/qemu-common-builder:${ARCH}"
            "$BUILD_ENGINE" tag "${BUILDER_TAGS[common]}" "${BUILDER_TAGS[qemu-common]}"
            ;;
        npins-rust)
            build_target rust-common
            build_image npins-rust images/npins/rust/docker/Dockerfile images/npins/rust \
                "${RUNTIME_TAGS[rust-common]}" "${BUILDER_TAGS[rust-common]}" passthrough
            ;;
        rust-wasm)
            build_target rust-common
            build_image rust-wasm images/rust/wasm/docker/Dockerfile images/rust/wasm \
                "${RUNTIME_TAGS[rust-common]}" "${BUILDER_TAGS[rust-common]}" mise
            ;;
        rust-cross)
            build_target rust-common
            build_image rust-cross images/rust/cross/docker/Dockerfile images/rust/cross \
                "${RUNTIME_TAGS[rust-common]}" "${BUILDER_TAGS[rust-common]}" mise
            ;;
        qemu-rust-common)
            build_target qemu-common
            # qemu-common is passthrough, so its logical builder tag aliases
            # the common builder artifact without creating another archive.
            build_image qemu-rust-common images/qemu/rust/common/docker/Dockerfile images/qemu/rust/common \
                "${RUNTIME_TAGS[qemu-common]}" "${BUILDER_TAGS[qemu-common]}" mise
            ;;
        qemu-rust-cross)
            build_target qemu-rust-common
            build_image qemu-rust-cross images/qemu/rust/cross/docker/Dockerfile images/qemu/rust/cross \
                "${RUNTIME_TAGS[qemu-rust-common]}" "${BUILDER_TAGS[qemu-rust-common]}" mise
            ;;
        all)
            for image in common podman npins-common rust-common qemu-common npins-rust rust-wasm rust-cross qemu-rust-common qemu-rust-cross; do
                build_target "$image"
            done
            ;;
        *)
            echo "Unknown target: $target" >&2
            return 2
            ;;
    esac
    BUILT_TARGETS["$target"]=1
}

build_target "$TARGET"

echo ""
echo "========================================================"
echo "  Build finished successfully for: ${TARGET}"
echo "  Builder artifacts: ${BUILDER_ARCHIVE_DIR}"
echo "========================================================"
