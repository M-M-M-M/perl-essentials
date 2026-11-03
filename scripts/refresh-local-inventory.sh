#!/bin/sh
set -eu
build=0
case "${1:-}" in
    --build) build=1 ;;
    "") ;;
    *) printf 'Usage: %s [--build]\n' "$0" >&2; exit 2 ;;
esac
stable=$(awk -F'|' '$2 == "stable" { v=$1 } END { print v }' perl-versions.conf)
dev=$(awk -F'|' '$2 == "development" { v=$1 } END { print v }' perl-versions.conf)
IMAGE=${IMAGE:-perl-essentials:codex}
CODEX_IMAGE=${CODEX_IMAGE:-$IMAGE}
CODEX_DEV_IMAGE=${CODEX_DEV_IMAGE:-perl-essentials:codex-dev}
cleanup()
{
    if [ "$build" = 1 ]; then
        docker image rm "$CODEX_IMAGE" "$CODEX_DEV_IMAGE" >/dev/null 2>&1 || true
    fi
}
if [ "$build" = 1 ]; then
    CODEX_IMAGE="perl-essentials:inventory-stable-$$"
    IMAGE=$CODEX_IMAGE
    CODEX_DEV_IMAGE="perl-essentials:inventory-dev-$$"
    trap cleanup EXIT HUP INT TERM
    arch=$(docker info --format '{{.Architecture}}')
    case "$arch" in aarch64|arm64) arch=arm64 ;; x86_64|amd64) arch=amd64 ;; *) exit 1 ;; esac
    PERL_VERSION="$stable" CI_PLATFORM="linux/$arch" CI_IMAGE="$CODEX_IMAGE" scripts/ci-build.sh codex
    PERL_VERSION="$dev" CI_PLATFORM="linux/$arch" CI_IMAGE="$CODEX_DEV_IMAGE" scripts/ci-build.sh codex
fi
check_version()
{
    actual=$(docker run --rm --entrypoint perl "$1" -MConfig -e 'print $Config{version}')
    if [ "$actual" != "$2" ]; then
        printf 'Unexpected Perl in %s: expected %s, got %s\n' "$1" "$2" "$actual" >&2
        exit 1
    fi
}
check_version "$IMAGE" "$stable"
check_version "$CODEX_IMAGE" "$stable"
check_version "$CODEX_DEV_IMAGE" "$dev"
export IMAGE CODEX_IMAGE CODEX_DEV_IMAGE
scripts/update-readme-module-versions.sh
prettier --write README.md DOCKERHUB.md
