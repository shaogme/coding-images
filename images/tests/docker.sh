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
engine_container="coding-images-engine-${target//\//-}-$$"
engine_image="ghcr.io/shaogme/nixos-dockers/podman:${NIXOS_DOCKERS_VERSION:-latest}"
socket_volume="coding-images-test-socket-${target//\//-}-$$"
data_volume="coding-images-test-data-${target//\//-}-$$"
compose_file="$repo_root/images/podman/docker-compose.yml"
compose_project="coding-images-podman-compose-$$"
compose_command=()

compose() {
    "${compose_command[@]}" \
        --project-name "$compose_project" \
        --file "$compose_file" \
        "$@"
}

cleanup() {
    local status=$?
    docker rm -f "$container" >/dev/null 2>&1 || true
    docker rm -f "$engine_container" >/dev/null 2>&1 || true
    docker volume rm -f "$socket_volume" "$data_volume" >/dev/null 2>&1 || true
    exit "$status"
}
trap cleanup EXIT

command -v docker >/dev/null
command -v bash >/dev/null

docker_run() {
    local args=()
    docker run "${args[@]}" "$@"
}

wait_for_backend() {
    local attempt state status
    for attempt in {1..60}; do
        state="$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null || true)"
        if [[ "$state" != running ]]; then
            echo "container $container exited before the dev-env backend became ready" >&2
            docker logs "$container" >&2 || true
            return 1
        fi
        if status="$(docker exec "$container" /usr/bin/dev-env backend status --json 2>/dev/null)"; then
            # `backend run` publishes its socket before the initial handoff
            # has finished. Do not let a transient socket response race the
            # first real client request on a busy CI runner.
            if grep -Fq '"state": "ready"' <<<"$status" ||
                grep -Fq '"state":"ready"' <<<"$status"; then
                return 0
            fi
        fi
        sleep 1
    done
    echo "timed out waiting for the dev-env backend in $container" >&2
    docker logs "$container" >&2 || true
    return 1
}

docker_exec_retry() {
    local attempt output state
    for attempt in {1..10}; do
        if output="$(docker exec "$container" "$@" 2>&1)"; then
            printf '%s\n' "$output"
            return 0
        fi
        state="$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null || true)"
        if [[ "$state" != running ]]; then
            break
        fi
        sleep 1
    done
    echo "docker exec failed in $container: $*" >&2
    printf '%s\n' "${output:-}" >&2
    docker logs "$container" >&2 || true
    return 1
}

echo "==> building ${image} and its local ancestors"
(
    cd "$repo_root"
    REPO_PREFIX="$repo_prefix" "$repo_root/scripts/build_local.sh" "$target"
)

echo "==> checking Docker metadata"
entrypoint="$(docker image inspect --format '{{json .Config.Entrypoint}}' "$image")"
[[ "$entrypoint" == '["/usr/bin/container-init","run","--"]' ]] || {
    echo "unexpected entrypoint for ${image}: ${entrypoint}" >&2
    exit 1
}

docker_run --rm --entrypoint /bin/sh "$image" -c '
    test ! -e /bin/entrypoint.sh
    test ! -e /usr/local/bin/mise-entrypoint.sh
    test -x /usr/bin/container-init
    test -x /usr/bin/dev-env
    test "$PWD" = /workspace
'

echo "==> checking the image tool through the default handoff"
tool_output="$(docker_run --rm \
        --env RUN_AS_ROOT=1 \
        "$image" /bin/sh -c "command -v ${required_command} && ${required_command} --version" 2>&1)" || {
    echo "$tool_output" >&2
    exit 1
}
grep -F "$required_command" <<<"$tool_output"

echo "==> checking the resolved environment and bootstrap plan"
plan="$(docker_run --rm --entrypoint /usr/bin/container-init "$image" plan --json)"
grep -Fq '"actions"' <<<"$plan"
grep -Fq '"handoff"' <<<"$plan"
environment="$(docker_run --rm --entrypoint /usr/bin/container-init "$image" run -- /usr/bin/dev-env print --format json)"
grep -Fq '"PATH"' <<<"$environment"
grep -Fq '"NIX_PATH"' <<<"$environment"

if [[ "$target" == rust-common ]]; then
    grep -Fq '"RUSTC_WRAPPER"' <<<"$environment"
    if grep -Fq '"CARGO_INCREMENTAL"' <<<"$environment"; then
        echo "CARGO_INCREMENTAL must be unset while sccache is enabled" >&2
        exit 1
    fi
    grep -Fq '"CARGO_TARGET_DIR"' <<<"$environment"
    grep -Fq '"SCCACHE_DIR"' <<<"$environment"

    echo "==> checking Compose-compatible sccache disable inputs"
    disabled_environment="$(docker_run --rm \
        --env SCCACHE_DISABLE=1 \
        --env ENABLE_SCCACHE=1 \
        --entrypoint /usr/bin/container-init \
        "$image" run -- /usr/bin/dev-env print --format json)"
    if grep -Fq '"RUSTC_WRAPPER"' <<<"$disabled_environment"; then
        echo "RUSTC_WRAPPER must be unset when SCCACHE_DISABLE=1" >&2
        exit 1
    fi

    legacy_disabled_environment="$(docker_run --rm \
        --env ENABLE_SCCACHE=0 \
        --entrypoint /usr/bin/container-init \
        "$image" run -- /usr/bin/dev-env print --format json)"
    if grep -Fq '"RUSTC_WRAPPER"' <<<"$legacy_disabled_environment"; then
        echo "RUSTC_WRAPPER must be unset when ENABLE_SCCACHE=0" >&2
        exit 1
    fi

    overridden_environment="$(docker_run --rm \
        --env CARGO_INCREMENTAL=1 \
        --env CARGO_TARGET_DIR=/tmp/rust-target \
        --env SCCACHE_DIR=/tmp/sccache \
        --env SCCACHE_DISABLE=1 \
        --entrypoint /usr/bin/container-init \
        "$image" run -- /usr/bin/dev-env print --format json)"
    grep -Fq '"CARGO_INCREMENTAL":"1"' <<<"$overridden_environment"
    grep -Fq '"CARGO_TARGET_DIR":"/tmp/rust-target"' <<<"$overridden_environment"
    grep -Fq '"SCCACHE_DIR":"/tmp/sccache"' <<<"$overridden_environment"
fi

echo "==> checking non-root identity handoff"
docker_run --rm "$image" /bin/sh -c '
    test "$HOME" = /home/dev
    test "$USER" = dev
    test "$LOGNAME" = dev
    test "$(id -u)" = 1000
    test "$(id -g)" = 1000
    test "$(stat -c %u:%g /home/dev)" = "1000:1000"
    test "$(stat -c %U /home/dev)" = dev
    for directory in .config .local .cache .cargo; do
        test "$(stat -c %a "/home/dev/$directory")" = 700
        test "$(stat -c %u:%g "/home/dev/$directory")" = "1000:1000"
    done
    test "$(readlink /home/dev/.codex)" = /data/coding-config/codex
    test "$(readlink /home/dev/.config/opencode)" = /data/coding-config/opencode
    test "$(readlink /home/dev/.cargo/registry)" = /data/cargo/registry
    test "$(readlink /home/dev/.cargo/git)" = /data/cargo/git
'

echo "==> checking root identity handoff"
docker_run --rm --env RUN_AS_ROOT=1 "$image" /bin/sh -c '
    test "$HOME" = /root
    test "$USER" = root
    test "$(id -u)" = 0
    test "$(id -g)" = 0
    test "$(stat -c %u:%g /root)" = "0:0"
    test "$(stat -c %U /root)" = root
    test "$(stat -c %a /root)" = 700
    for directory in .config .local .cache .cargo; do
        test "$(stat -c %a "/root/$directory")" = 700
        test "$(stat -c %u:%g "/root/$directory")" = "0:0"
    done
    test "$(readlink /root/.codex)" = /data/coding-config/codex
    test "$(readlink /root/.config/opencode)" = /data/coding-config/opencode
    test "$(readlink /root/.cargo/registry)" = /data/cargo/registry
    test "$(readlink /root/.cargo/git)" = /data/cargo/git
'

echo "==> checking deployment and docker exec"
docker_run --detach --name "$container" --env RUN_AS_ROOT=1 "$image" /bin/sh -c 'sleep 300' >/dev/null
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
wait_for_backend

doctor_output="$(docker_exec_retry /usr/bin/dev-env doctor --json)"
grep -Fq '"ok": true' <<<"$doctor_output"
docker_exec_retry /bin/bash -lc 'test -n "$PATH" && test -n "$NIX_PATH"' >/dev/null
docker_exec_retry /bin/sh -c 'test "$(stat -c %u:%g /root)" = "0:0" && test "$(stat -c %U /root)" = root' >/dev/null

echo "Docker test passed: ${image}"
