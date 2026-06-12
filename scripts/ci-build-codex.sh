#!/bin/sh

set -eu

: "${PERL_VERSION:?PERL_VERSION must be set}"

image="perl-essentials:codex-ci"
builder="perl-essentials-codex-ci-$$"
platform="${CI_PLATFORM:-linux/amd64}"

cleanup()
{
    docker buildx rm --force "${builder}" >/dev/null 2>&1 || true
}

trap cleanup EXIT HUP INT TERM

docker buildx create \
    --driver docker-container \
    --name "${builder}" \
    --use
docker buildx inspect --bootstrap "${builder}"
docker buildx build \
    --builder "${builder}" \
    --platform "${platform}" \
    --target codex \
    --no-cache \
    --load \
    --build-arg PERL_VERSION="${PERL_VERSION}" \
    --tag "${image}" \
    .

test -z "$(docker run --rm "${image}" \
    find /codex -mindepth 1 -print -quit)"
docker run --rm "${image}" codex --version
docker run --rm "${image}" bwrap --version
docker run --rm "${image}" sh -c 'test "$PWD" = /work'
docker run --rm "${image}" zsh -lic \
    'command -v perl >/dev/null && command -v codex >/dev/null'
docker run --rm \
    --cap-add SYS_ADMIN \
    --security-opt apparmor=unconfined \
    --security-opt seccomp=unconfined \
    --security-opt no-new-privileges=true \
    "${image}" codex sandbox -- sh -c 'printf sandbox-ok'
