#!/bin/sh

set -eu

mkdir -p "${CODEX_HOME}"
rtk init -g --codex </dev/null >/dev/null

exec "$@"
