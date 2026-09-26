#!/bin/sh
set -eu

host="${CONTAINER_HOST:-${DOCKER_HOST:-unix:///run/podman/podman.sock}}"
case "$host" in
  unix://*) socket="${host#unix://}" ;;
  *) socket="" ;;
esac
if [ -n "$socket" ] && [ ! -S "$socket" ]; then
  echo "podman engine socket is not mounted: $socket" >&2
  echo "start the Compose podman service and mount podman-socket" >&2
  exit 125
fi
exec /nix/var/nix/profiles/default/bin/podman-compose "$@"
