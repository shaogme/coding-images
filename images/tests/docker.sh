#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <build-target> <required-command>" >&2
    exit 2
fi

target="$1"
required_command="$2"
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
repo_prefix="${REPO_PREFIX:-ghcr.io/shaogme/coding-images}"
image="${repo_prefix}/${target}:latest"
container="coding-images-test-${target//\//-}-$$"

cleanup() {
    local status=$?
    docker rm -f "$container" >/dev/null 2>&1 || true
    exit "$status"
}
trap cleanup EXIT

command -v docker >/dev/null
command -v bash >/dev/null

echo "==> building ${image} and its local ancestors"
REPO_PREFIX="$repo_prefix" "$repo_root/scripts/build_local.sh" "$target"

echo "==> checking Docker metadata"
entrypoint="$(docker image inspect --format '{{json .Config.Entrypoint}}' "$image")"
[[ "$entrypoint" == '["/usr/bin/container-init","run","--"]' ]] || {
    echo "unexpected entrypoint for ${image}: ${entrypoint}" >&2
    exit 1
}

docker run --rm --entrypoint /bin/sh "$image" -c '
    test ! -e /bin/entrypoint.sh
    test ! -e /usr/local/bin/mise-entrypoint.sh
    test -x /usr/bin/container-init
    test -x /usr/bin/dev-env
    test "$PWD" = /workspace
'

echo "==> checking the image tool through the default handoff"
tool_output="$(docker run --rm --env RUN_AS_ROOT=1 "$image" /bin/sh -c "command -v ${required_command} && ${required_command} --version" 2>&1)" || {
    echo "$tool_output" >&2
    exit 1
}
grep -F "$required_command" <<<"$tool_output"

echo "==> checking the resolved environment and bootstrap plan"
plan="$(docker run --rm --entrypoint /usr/bin/container-init "$image" plan --json)"
grep -Fq '"actions"' <<<"$plan"
grep -Fq '"handoff"' <<<"$plan"
environment="$(docker run --rm --entrypoint /usr/bin/dev-env "$image" print --format json)"
grep -Fq '"PATH"' <<<"$environment"
grep -Fq '"NIX_PATH"' <<<"$environment"

if [[ "$target" == rust-common ]]; then
    grep -Fq '"RUSTC_WRAPPER"' <<<"$environment"
    grep -Fq '"CARGO_INCREMENTAL"' <<<"$environment"
    grep -Fq '"CARGO_TARGET_DIR"' <<<"$environment"
    grep -Fq '"SCCACHE_DIR"' <<<"$environment"

    echo "==> checking Compose-compatible sccache disable inputs"
    disabled_environment="$(docker run --rm \
        --env SCCACHE_DISABLE=1 \
        --env ENABLE_SCCACHE=1 \
        --entrypoint /usr/bin/dev-env \
        "$image" print --format json)"
    if grep -Fq '"RUSTC_WRAPPER"' <<<"$disabled_environment"; then
        echo "RUSTC_WRAPPER must be unset when SCCACHE_DISABLE=1" >&2
        exit 1
    fi

    legacy_disabled_environment="$(docker run --rm \
        --env ENABLE_SCCACHE=0 \
        --entrypoint /usr/bin/dev-env \
        "$image" print --format json)"
    if grep -Fq '"RUSTC_WRAPPER"' <<<"$legacy_disabled_environment"; then
        echo "RUSTC_WRAPPER must be unset when ENABLE_SCCACHE=0" >&2
        exit 1
    fi

    overridden_environment="$(docker run --rm \
        --env CARGO_INCREMENTAL=1 \
        --env CARGO_TARGET_DIR=/tmp/rust-target \
        --env SCCACHE_DIR=/tmp/sccache \
        --entrypoint /usr/bin/dev-env \
        "$image" print --format json)"
    grep -Fq '"CARGO_INCREMENTAL":"1"' <<<"$overridden_environment"
    grep -Fq '"CARGO_TARGET_DIR":"/tmp/rust-target"' <<<"$overridden_environment"
    grep -Fq '"SCCACHE_DIR":"/tmp/sccache"' <<<"$overridden_environment"
fi

if [[ "$target" == podman ]]; then
    echo "==> checking podman and docker execution with bridge and host networks (root user)"
    root_output="$(docker run --rm --privileged \
        --cgroupns=host \
        --device /dev/fuse --device /dev/net/tun \
        --env RUN_AS_ROOT=1 \
        "$image" /bin/bash -c '
            set -e
            podman run --rm docker.io/library/alpine:latest echo "root-podman-bridge-ok"
            podman run --rm --network host docker.io/library/alpine:latest echo "root-podman-host-ok"
            docker run --rm docker.io/library/alpine:latest echo "root-docker-bridge-ok"
            docker run --rm --network host docker.io/library/alpine:latest echo "root-docker-host-ok"
        ')"
    grep -Fq "root-podman-bridge-ok" <<<"$root_output"
    grep -Fq "root-podman-host-ok" <<<"$root_output"
    grep -Fq "root-docker-bridge-ok" <<<"$root_output"
    grep -Fq "root-docker-host-ok" <<<"$root_output"

    echo "==> checking podman and docker execution with bridge and host networks (dev user)"
    dev_output="$(docker run --rm --privileged \
        --cgroupns=host \
        --device /dev/fuse --device /dev/net/tun \
        --env HOST_UID=1000:1000 \
        "$image" /bin/bash -c '
            set -e
            podman run --rm docker.io/library/alpine:latest echo "dev-podman-bridge-ok"
            podman run --rm --network host docker.io/library/alpine:latest echo "dev-podman-host-ok"
            docker run --rm docker.io/library/alpine:latest echo "dev-docker-bridge-ok"
            docker run --rm --network host docker.io/library/alpine:latest echo "dev-docker-host-ok"
        ')"
    grep -Fq "dev-podman-bridge-ok" <<<"$dev_output"
    grep -Fq "dev-podman-host-ok" <<<"$dev_output"
    grep -Fq "dev-docker-bridge-ok" <<<"$dev_output"
    grep -Fq "dev-docker-host-ok" <<<"$dev_output"

    echo "==> checking compose tooling (docker compose, docker-compose, podman compose, podman-compose) under root"
    root_compose_output="$(docker run --rm --privileged \
        --cgroupns=host \
        --device /dev/fuse --device /dev/net/tun \
        --env RUN_AS_ROOT=1 \
        "$image" /bin/bash -c '
            set -e
            workdir="$(mktemp -d)"
            cd "$workdir"
            cat << "COMPOSE" > docker-compose.yml
services:
  test:
    image: docker.io/library/alpine:latest
    command: ["echo", "compose-root-ok"]
COMPOSE
            docker compose up
            docker compose down
            docker-compose up
            docker-compose down
            podman compose up
            podman compose down
            podman-compose up
            podman-compose down
            rm -rf "$workdir"
        ')"
    grep -Fq "compose-root-ok" <<<"$root_compose_output"

    echo "==> checking compose tooling (docker compose, docker-compose, podman compose, podman-compose) under dev"
    dev_compose_output="$(docker run --rm --privileged \
        --cgroupns=host \
        --device /dev/fuse --device /dev/net/tun \
        --env HOST_UID=1000:1000 \
        "$image" /bin/bash -c '
            set -e
            workdir="$(mktemp -d -p /tmp)"
            cd "$workdir"
            cat << "COMPOSE" > docker-compose.yml
services:
  test:
    image: docker.io/library/alpine:latest
    command: ["echo", "compose-dev-ok"]
COMPOSE
            docker compose up
            docker compose down
            docker-compose up
            docker-compose down
            podman compose up
            podman compose down
            podman-compose up
            podman-compose down
            rm -rf "$workdir"
        ')"
    grep -Fq "compose-dev-ok" <<<"$dev_compose_output"

    echo "==> checking single volume persistence for root and dev"
    vol_name="test-podman-vol-${RANDOM}"
    docker volume create "$vol_name" >/dev/null
    docker run --rm --privileged \
        --cgroupns=host \
        --device /dev/fuse --device /dev/net/tun \
        --env RUN_AS_ROOT=1 \
        -v "$vol_name:/var/lib/containers" \
        "$image" podman run --rm docker.io/library/alpine:latest echo "vol-root-ok" | grep -Fq "vol-root-ok"
    docker run --rm --privileged \
        --cgroupns=host \
        --device /dev/fuse --device /dev/net/tun \
        --env HOST_UID=1000:1000 \
        -v "$vol_name:/var/lib/containers" \
        "$image" podman run --rm docker.io/library/alpine:latest echo "vol-dev-ok" | grep -Fq "vol-dev-ok"
    docker volume rm -f "$vol_name" >/dev/null
fi

echo "==> checking non-root identity handoff"
docker run --rm --env HOST_UID=1000:1000 "$image" /bin/sh -c '
    test "$HOME" = /home/dev
    test "$USER" = dev
    test "$LOGNAME" = dev
    test "$(id -u)" = 1000
    test "$(id -g)" = 1000
'

echo "==> checking deployment and docker exec"
docker run --detach --name "$container" --env RUN_AS_ROOT=1 "$image" /bin/sh -c 'sleep 30' >/dev/null
for _ in {1..30}; do
    state="$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null || true)"
    case "$state" in
        running) break ;;
        exited|dead)
            docker logs "$container" >&2 || true
            exit 1
            ;;
    esac
    sleep 1
done
[[ "$(docker inspect --format '{{.State.Running}}' "$container")" == true ]]

docker exec "$container" /usr/bin/dev-env doctor --json | grep -Fq '"ok": true'
docker exec "$container" /bin/bash -lc 'test -n "$PATH" && test -n "$NIX_PATH"'

echo "Docker test passed: ${image}"
