#!/bin/sh

set -eu

: "${PERL_VERSION:?PERL_VERSION must be set}"

image="perl-essentials:${PERL_VERSION}"
builder="perl-essentials-ci-$$"
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
docker buildx build --builder "${builder}" --check .
docker buildx build \
    --builder "${builder}" \
    --platform "${platform}" \
    --load \
    --build-arg PERL_VERSION="${PERL_VERSION}" \
    --tag "${image}" \
    .
docker run --rm "${image}" \
    /opt/perl-essentials/scripts/smoke-test.pl \
    /opt/perl-essentials/cpanfile \
    /opt/perl-essentials/cpanfile-notest
docker run --rm \
    --volume "${PWD}:/work:ro" \
    "${image}" \
    /work/test/check-perl-format.sh
docker run --rm "${image}" \
    /opt/perl-essentials/scripts/check-runtime-tools.sh
docker run --rm \
    --volume "${PWD}:/work:ro" \
    "${image}" sh -c \
    'set -eu
     perltidy -dpro | grep -q "Dump of file: '\''.perltidyrc'\''"
     cmp /work/AGENTS.md /opt/perl-essentials/AGENTS.md
     cmp /work/.perltidyrc /opt/perl-essentials/.perltidyrc'
docker run --rm "${image}" zsh -lic \
    'test "$PROMPT" = "[%n@%m][%h][%~] #" && test "$(alias ll)" = "ll='\''ls -Fl'\''"'
docker run --rm --user 12345:12345 "${image}" zsh -lic \
    'test "$PROMPT" = "[%n@%m][%h][%~] >"'
