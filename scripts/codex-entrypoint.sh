#!/bin/sh

set -eu

mkdir -p "${CODEX_HOME}"
[ -e "${HOME}/.zshrc" ] || : > "${HOME}/.zshrc"
rtk init -g --codex </dev/null >/dev/null

exec "$@"
