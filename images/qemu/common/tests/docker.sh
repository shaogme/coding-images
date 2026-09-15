#!/usr/bin/env bash
set -Eeuo pipefail
exec "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)/tests/docker.sh" qemu-common qemu-system-x86_64
