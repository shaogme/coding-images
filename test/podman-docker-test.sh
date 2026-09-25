#!/usr/bin/env bash
set -Eeuo pipefail

# Reproduce images/tests/docker.sh from a NixOS guest that uses the real
# Docker daemon. The default image is pulled from GHCR. Set
# PODMAN_IMAGE_SOURCE=local to build/import a local podman image instead.

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
image_nix="$script_dir/docker-image.nix"
image_source="${PODMAN_IMAGE_SOURCE:-registry}"
image="${PODMAN_IMAGE:-ghcr.io/shaogme/coding-images/podman:latest}"
local_image="${LOCAL_PODMAN_IMAGE:-local/coding-images/podman:latest}"
build_local="${BUILD_LOCAL_PODMAN:-1}"
ssh_port="${PODMAN_TEST_SSH_PORT:-22229}"
memory="${PODMAN_TEST_MEMORY:-4096}"
cores="${PODMAN_TEST_CORES:-4}"
work_dir="${PODMAN_TEST_WORK_DIR:-${TMPDIR:-/tmp}/coding-images-podman-qemu-test}"
qemu_log="$work_dir/qemu.log"
image_link="$work_dir/image"
image_path=""
vm_link="$work_dir/vm"
vm_disk="$work_dir/vm.qcow2"
vm_runner=""
qemu_pid=""
known_hosts="$work_dir/known_hosts"

case "$image_source" in
    registry|local) ;;
    *)
        echo "PODMAN_IMAGE_SOURCE must be registry or local (got: $image_source)" >&2
        exit 2
        ;;
esac

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "required command not found: $1" >&2
        exit 127
    }
}

for command in nix-build qemu-img ssh sshpass docker; do
    require_command "$command"
done

mkdir -p "$work_dir"

cleanup() {
    local status=$?
    if [[ -n "$qemu_pid" ]] && kill -0 "$qemu_pid" 2>/dev/null; then
        kill "$qemu_pid" 2>/dev/null || true
        wait "$qemu_pid" 2>/dev/null || true
    fi
    if [[ "$status" -ne 0 && -f "$qemu_log" ]]; then
        echo "==> QEMU log ($qemu_log)" >&2
        tail -n 160 "$qemu_log" >&2 || true
    fi
    exit "$status"
}
trap cleanup EXIT

echo "==> building the Docker NixOS qcow2 image"
nix-build --no-out-link "$image_nix" -o "$image_link"
image_path="$(readlink -f "$image_link")"
if [[ -d "$image_path" ]]; then
    image_path="$(find "$image_path" -maxdepth 1 -type f -name '*.qcow2' -print -quit)"
fi
[[ -n "$image_path" && -f "$image_path" ]] || {
    echo "could not find a qcow2 image in $image_link" >&2
    exit 1
}
echo "==> building the NixOS VM runner"
nix-build --no-out-link "$image_nix" --argstr output metadata -A vm -o "$vm_link"
rm -f "$vm_disk"
qemu-img create -f qcow2 -F qcow2 -b "$image_path" "$vm_disk" >/dev/null
vm_runner="$(readlink -f "$vm_link")/bin/run-nixos-vm"
[[ -x "$vm_runner" && -f "$vm_disk" ]] || {
    echo "VM runner setup is incomplete" >&2
    exit 1
}

if [[ "$image_source" == local ]]; then
    if [[ "$build_local" == 1 ]]; then
        echo "==> building local Podman image: $local_image"
        REPO_PREFIX="${local_image%/*}" "$repo_root/scripts/build_local.sh" podman
    fi
    image="$local_image"
    docker image inspect "$image" >/dev/null 2>&1 || {
        echo "local image is unavailable: $image" >&2
        echo "set BUILD_LOCAL_PODMAN=1 or build it with scripts/build_local.sh podman" >&2
        exit 1
    }
fi

echo "==> starting Docker NixOS VM (image: $image)"
(
    cd "$work_dir"
    QEMU_NET_OPTS="hostfwd=tcp:127.0.0.1:$ssh_port-:22" \
        NIX_DISK_IMAGE="$vm_disk" \
        QEMU_OPTS="-m $memory -smp $cores" \
        "$vm_runner"
) >"$qemu_log" 2>&1 &
qemu_pid=$!

ssh_guest() {
    SSHPASS="${PODMAN_TEST_SSH_PASSWORD:-root}" sshpass -e ssh \
        -q \
        -o ConnectTimeout=3 \
        -o PreferredAuthentications=password \
        -o PubkeyAuthentication=no \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile="$known_hosts" \
        -p "$ssh_port" \
        root@127.0.0.1 \
        "$@"
}

echo "==> waiting for SSH and Docker in the guest"
for attempt in {1..120}; do
    if ! kill -0 "$qemu_pid" 2>/dev/null; then
        echo "QEMU exited before the guest became ready" >&2
        exit 1
    fi
    if ssh_guest true 2>/dev/null; then
        if ssh_guest systemctl is-active --quiet docker && ssh_guest docker info >/dev/null 2>&1; then
            break
        fi
    fi
    if [[ "$attempt" -eq 120 ]]; then
        echo "timed out waiting for the guest Docker daemon" >&2
        exit 1
    fi
    sleep 2
done

if [[ "$image_source" == local ]]; then
    echo "==> loading local Podman image into the guest"
    docker save "$image" | SSHPASS="${PODMAN_TEST_SSH_PASSWORD:-root}" sshpass -e ssh \
        -q \
        -o ConnectTimeout=10 \
        -o PreferredAuthentications=password \
        -o PubkeyAuthentication=no \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile="$known_hosts" \
        -p "$ssh_port" \
        root@127.0.0.1 docker load
else
    echo "==> pulling Podman image in the guest: $image"
    ssh_guest docker pull "$image"
fi

echo "==> running the Podman image checks from .github/workflows/docker-test.yml"
SSHPASS="${PODMAN_TEST_SSH_PASSWORD:-root}" sshpass -e ssh \
    -q \
    -o ConnectTimeout=10 \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile="$known_hosts" \
    -p "$ssh_port" \
    root@127.0.0.1 bash -s -- "$image" <<'GUEST_TEST'
set -Eeuo pipefail

image="$1"
container="coding-images-test-podman-$$"

cleanup() {
    local status=$?
    docker rm -f "$container" >/dev/null 2>&1 || true
    docker volume rm -f "test-podman-vol-$$" >/dev/null 2>&1 || true
    exit "$status"
}
trap cleanup EXIT

docker_run() {
    docker run \
        --cap-add=SYS_ADMIN \
        --cap-add=NET_ADMIN \
        --cgroupns=private \
        --security-opt apparmor=unconfined \
        --security-opt seccomp=unconfined \
        --security-opt systempaths=unconfined \
        --device /dev/fuse \
        --device /dev/net/tun \
        "$@"
}

command -v docker >/dev/null
docker info >/dev/null

echo "==> checking Docker metadata"
entrypoint="$(docker image inspect --format '{{json .Config.Entrypoint}}' "$image")"
[[ "$entrypoint" == '["/usr/bin/container-init","run","--"]' ]] || {
    echo "unexpected entrypoint for $image: $entrypoint" >&2
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
tool_output="$(docker_run --rm --env RUN_AS_ROOT=1 "$image" /bin/sh -c \
    'command -v podman && podman --version' 2>&1)" || {
    echo "$tool_output" >&2
    exit 1
}
grep -F podman <<<"$tool_output"

echo "==> checking the resolved environment and bootstrap plan"
plan="$(docker_run --rm --entrypoint /usr/bin/container-init "$image" plan --json)"
grep -Fq '"actions"' <<<"$plan"
grep -Fq '"handoff"' <<<"$plan"
environment="$(docker_run --rm --entrypoint /usr/bin/dev-env "$image" print --format json)"
grep -Fq '"PATH"' <<<"$environment"
grep -Fq '"NIX_PATH"' <<<"$environment"

echo "==> checking podman and docker execution with bridge and host networks (root user)"
# Docker gives the outer container a private cgroup namespace.  Its cpuset
# controller cannot be delegated again, so keep the inner root container at
# the namespace root while leaving cgroups enabled.
root_output="$(docker_run --rm --env RUN_AS_ROOT=1 "$image" /bin/bash -c '
    set -e
    podman run --rm docker.io/library/alpine:latest echo "root-podman-bridge-ok"
    podman run --rm --network host docker.io/library/alpine:latest echo "root-podman-host-ok"
    docker run --rm docker.io/library/alpine:latest echo "root-docker-bridge-ok"
    docker run --rm --network host docker.io/library/alpine:latest echo "root-docker-host-ok"
')"
grep -Fq root-podman-bridge-ok <<<"$root_output"
grep -Fq root-podman-host-ok <<<"$root_output"
grep -Fq root-docker-bridge-ok <<<"$root_output"
grep -Fq root-docker-host-ok <<<"$root_output"

echo "==> checking podman and docker execution with bridge and host networks (dev user)"
dev_output="$(docker_run --rm "$image" /bin/bash -c '
    set -e
    podman run --rm docker.io/library/alpine:latest echo "dev-podman-bridge-ok"
    podman run --rm --network host docker.io/library/alpine:latest echo "dev-podman-host-ok"
    docker run --rm docker.io/library/alpine:latest echo "dev-docker-bridge-ok"
    docker run --rm --network host docker.io/library/alpine:latest echo "dev-docker-host-ok"
')"
grep -Fq dev-podman-bridge-ok <<<"$dev_output"
grep -Fq dev-podman-host-ok <<<"$dev_output"
grep -Fq dev-docker-bridge-ok <<<"$dev_output"
grep -Fq dev-docker-host-ok <<<"$dev_output"

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

echo "==> checking compose tooling under root"
root_compose_output="$(docker_run --rm --env RUN_AS_ROOT=1 "$image" /bin/bash -c '
    set -e
    workdir="$(mktemp -d)"
    cd "$workdir"
    cat > docker-compose.yml <<"COMPOSE"
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
')"
grep -Fq compose-root-ok <<<"$root_compose_output"

echo "==> checking compose tooling under dev"
dev_compose_output="$(docker_run --rm "$image" /bin/bash -c '
    set -e
    workdir="$(mktemp -d -p /tmp)"
    cd "$workdir"
    cat > docker-compose.yml <<"COMPOSE"
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
')"
grep -Fq compose-dev-ok <<<"$dev_compose_output"

echo "==> checking single volume persistence for root and dev"
volume="test-podman-vol-$$"
docker volume create "$volume" >/dev/null
docker_run --rm --env RUN_AS_ROOT=1 -v "$volume:/var/lib/containers" "$image" \
    podman run --rm docker.io/library/alpine:latest echo vol-root-ok | grep -Fq vol-root-ok
docker_run --rm -v "$volume:/var/lib/containers" "$image" \
    podman run --rm docker.io/library/alpine:latest echo vol-dev-ok | grep -Fq vol-dev-ok

echo "==> checking deployment and docker exec"
docker_run --detach --name "$container" --env RUN_AS_ROOT=1 "$image" /bin/sh -c 'sleep 30' >/dev/null
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
docker exec "$container" /bin/sh -c 'test "$(id -u)" = 0'

echo "Docker test passed: $image"
GUEST_TEST

echo "==> Podman image test completed successfully"
