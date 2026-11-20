#!/bin/sh
set -eu

if [ "$(id -u)" -eq 0 ]; then
  echo "PI_UID must identify a non-root user" >&2
  exit 1
fi

exec pi "$@"
