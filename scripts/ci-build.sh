#!/bin/sh

set -eu

: "${PERL_VERSION:?PERL_VERSION must be set}"

mode="${1:-perl}"
platform="${CI_PLATFORM:-linux/amd64}"
codex_state=""

cleanup()
{
    if [ -n "${codex_state}" ]; then
        docker volume rm --force "${codex_state}" >/dev/null 2>&1 || true
    fi
    docker buildx rm --force "${builder}" >/dev/null 2>&1 || true
}

bootstrap_builder()
{
    attempt=1

    while ! docker buildx inspect --bootstrap "${builder}"; do
        if [ "${attempt}" -ge 3 ]; then
            printf 'Buildx bootstrap failed after %s attempts\n' \
                "${attempt}" >&2
            return 1
        fi

        printf 'Buildx bootstrap failed (attempt %s/3), retrying\n' \
            "${attempt}" >&2
        attempt=$((attempt + 1))
        sleep 5
    done

    printf 'Buildx builder is ready\n'
}

validate_perl()
{
    docker run --rm "${image}" \
        /opt/perl-essentials/scripts/smoke-test.pl \
        /opt/perl-essentials/cpanfile \
        /opt/perl-essentials/cpanfile-notest
    docker run --rm \
        --user "$(id -u):$(id -g)" \
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
}

validate_codex()
{
    codex_state="perl-essentials-codex-state-$$"

    test -z "$(docker run --rm --entrypoint find "${image}" \
        /codex -mindepth 1 -print -quit)"
    docker volume create "${codex_state}" >/dev/null
    docker run --rm \
        --volume "${codex_state}:/codex" \
        "${image}" true
    docker run --rm \
        --entrypoint test \
        --volume "${codex_state}:/codex" \
        "${image}" -f /codex/AGENTS.md
    docker run --rm \
        --entrypoint test \
        --volume "${codex_state}:/codex" \
        "${image}" -f /codex/RTK.md
    docker run --rm \
        --volume "${codex_state}:/codex" \
        "${image}" true
    test "$(docker run --rm \
        --entrypoint grep \
        --volume "${codex_state}:/codex" \
        "${image}" -c '^@/codex/RTK\.md$' /codex/AGENTS.md)" -eq 1
    docker run --rm "${image}" codex --version
    docker run --rm "${image}" rtk --version
    docker run --rm "${image}" bwrap --version
    docker run --rm "${image}" sh -c 'test "$PWD" = /work'
    docker run --rm "${image}" zsh -lic \
        'command -v perl >/dev/null \
         && command -v codex >/dev/null \
         && command -v rtk >/dev/null'
    docker run --rm \
        --cap-add SYS_ADMIN \
        --security-opt apparmor=unconfined \
        --security-opt seccomp=unconfined \
        --security-opt no-new-privileges=true \
        "${image}" codex sandbox -- sh -c 'printf sandbox-ok'
}

case "${mode}" in
perl)
    target="final"
    image="perl-essentials:${PERL_VERSION}"
    no_cache=""
    validate="validate_perl"
    ;;
codex)
    target="codex"
    image="perl-essentials:codex"
    no_cache="--no-cache"
    validate="validate_codex"
    ;;
*)
    printf 'Unknown build mode: %s\nUsage: %s [perl|codex]\n' \
        "${mode}" "$0" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
    printf 'Usage: %s [perl|codex]\n' "$0" >&2
    exit 2
fi

builder="perl-essentials-${mode}-$$"

trap cleanup EXIT HUP INT TERM

docker buildx create \
    --driver docker-container \
    --name "${builder}" \
    --use
bootstrap_builder
docker buildx build --builder "${builder}" --target "${target}" --check .

printf 'Building target %s for %s as %s\n' \
    "${target}" "${platform}" "${image}"
set -- docker buildx build \
    --builder "${builder}" \
    --platform "${platform}" \
    --target "${target}" \
    --load \
    --build-arg PERL_VERSION="${PERL_VERSION}" \
    --tag "${image}"
if [ -n "${no_cache}" ]; then
    set -- "$@" "${no_cache}"
fi
set -- "$@" .
"$@"

printf 'Docker image %s loaded successfully\n' "${image}"
printf 'Validating %s image\n' "${mode}"
"${validate}"
