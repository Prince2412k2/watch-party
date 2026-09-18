#!/bin/sh
set -eu

if [ "$(id -u)" = "0" ]; then
  target_uid="${PUID:-1000}"
  target_gid="${PGID:-1000}"
  groupmod -o -g "$target_gid" media
  usermod -o -u "$target_uid" -g "$target_gid" media
  mkdir -p "${DATA_DIR:-/data}"
  chown media:media "${DATA_DIR:-/data}"
  exec su-exec media "$@"
fi

exec "$@"
