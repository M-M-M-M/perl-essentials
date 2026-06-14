#!/bin/sh

set -eu

: "${PERL_VERSION:?PERL_VERSION must be set}"

mode="${1:-perl}"
platform="${CI_PLATFORM:-linux/amd64}"
state=""

cleanup()
{
    if [ -n "${state}" ]; then
        rm -rf "${state}"
    fi
    docker buildx rm --force "${builder}" >/dev/null 2>&1 || true
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
    state="$(mktemp -d)"
    runner_user="$(id -u):$(id -g)"

    # Docker user-namespace remapping can prevent container root from writing
    # to the runner-owned 0700 directory. This state is temporary and has no tokens.
    chmod 0777 "${state}"

    test -z "$(docker run --rm --entrypoint find "${image}" \
        /codex -mindepth 1 -print -quit)"
    docker run --rm \
        --user "${runner_user}" \
        -v "${state}:/codex" \
        "${image}" true
    test -f "${state}/AGENTS.md"
    test -f "${state}/RTK.md"
    docker run --rm \
        --user "${runner_user}" \
        -v "${state}:/codex" \
        "${image}" true
    test "$(grep -c '^@/codex/RTK\.md$' "${state}/AGENTS.md")" -eq 1
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
docker buildx inspect --bootstrap "${builder}"
docker buildx build --builder "${builder}" --target "${target}" --check .

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

"${validate}"
