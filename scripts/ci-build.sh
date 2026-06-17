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

validate_license_audit()
{
    expect_codex="${1}"

    docker_run "${image}" \
        test -s /opt/perl-essentials/licenses/SUMMARY.md
    docker_run "${image}" perl -MJSON::PP -e '
        use strict;
        use warnings;

        my ($expect_codex) = @ARGV;
        my $root = "/opt/perl-essentials/licenses";
        open my $fh, "<:raw", "$root/inventory.json"
            or die "Cannot read license inventory: $!\n";
        local $/;
        my $inventory = decode_json(<$fh>);
        close $fh or die "Cannot close license inventory: $!\n";

        die "License inventory has no components\n"
            if !$inventory->{component_count}
            || $inventory->{component_count} != @{$inventory->{components}};

        my %component = map {
            ("$_->{ecosystem}:$_->{name}" => $_)
        } @{$inventory->{components}};
        for my $component (@{$inventory->{components}}) {
            for my $file (@{$component->{license_files}}) {
                die "Missing audited license file: $file\n"
                    if !-f "$root/$file";
            }
        }

        my $unknown = grep {
            grep { $_ eq "NOASSERTION" } @{$_->{licenses}}
        } @{$inventory->{components}};
        print "license-audit NOASSERTION count: $unknown\n";

        for my $name (qw(direct:codex-cli direct:rtk)) {
            die "Unexpected Codex-only license component: $name\n"
                if !$expect_codex && $component{$name};
            die "Missing Codex license component: $name\n"
                if $expect_codex && !$component{$name};
        }
    ' "${expect_codex}"
}

docker_run()
{
    docker run --rm --platform "${platform}" "$@"
}

validate_perl()
{
    docker_run "${image}" \
        /opt/perl-essentials/scripts/smoke-test.pl \
        /opt/perl-essentials/cpanfile \
        /opt/perl-essentials/cpanfile-bootstrap-notest \
        /opt/perl-essentials/cpanfile-notest
    docker_run \
        --user "$(id -u):$(id -g)" \
        --volume "${PWD}:/work:ro" \
        "${image}" \
        /work/test/check-perl-format.sh
    docker_run "${image}" \
        /opt/perl-essentials/scripts/check-runtime-tools.sh
    docker_run \
        --volume "${PWD}:/work:ro" \
        "${image}" sh -c \
        'set -eu
         perltidy -dpro | grep -q "Dump of file: '\''.perltidyrc'\''"
         cmp /work/AGENTS.md /opt/perl-essentials/AGENTS.md
         cmp /work/.perltidyrc /opt/perl-essentials/.perltidyrc'
    docker_run "${image}" zsh -lic \
        'test "$PROMPT" = "[%n@%m][%h][%~] #" && test "$(alias ll)" = "ll='\''ls -Fl'\''"'
    docker_run --user 12345:12345 "${image}" zsh -lic \
        'test "$PROMPT" = "[%n@%m][%h][%~] >"'
    validate_license_audit 0
}

validate_codex()
{
    codex_state="perl-essentials-codex-state-$$"

    test -z "$(docker_run --entrypoint find "${image}" \
        /codex -mindepth 1 -print -quit)"
    docker volume create "${codex_state}" >/dev/null
    docker_run \
        --volume "${codex_state}:/codex" \
        "${image}" true
    docker_run \
        --entrypoint test \
        --volume "${codex_state}:/codex" \
        "${image}" -f /codex/AGENTS.md
    docker_run \
        --entrypoint test \
        --volume "${codex_state}:/codex" \
        "${image}" -f /codex/RTK.md
    docker_run \
        --volume "${codex_state}:/codex" \
        "${image}" true
    test "$(docker_run \
        --entrypoint grep \
        --volume "${codex_state}:/codex" \
        "${image}" -c '^@/codex/RTK\.md$' /codex/AGENTS.md)" -eq 1
    docker_run "${image}" codex --version
    docker_run "${image}" rtk --version
    docker_run "${image}" bwrap --version
    test "$(docker_run \
        --entrypoint stat \
        "${image}" -c '%a:%U:%G' /usr/bin/bwrap)" = "4755:root:root"
    docker_run "${image}" sh -c 'test "$PWD" = /work'
    docker_run "${image}" zsh -lic \
        'command -v perl >/dev/null \
         && command -v codex >/dev/null \
         && command -v rtk >/dev/null'
    validate_license_audit 1
    validate_codex_sandbox
}

validate_codex_sandbox()
{
    if [ "${CI_SKIP_CODEX_SANDBOX:-}" = "1" ]; then
        printf 'Skipping Codex sandbox validation because CI_SKIP_CODEX_SANDBOX=1\n'
        return 0
    fi

    docker_run \
        --cap-add SYS_ADMIN \
        --security-opt apparmor=unconfined \
        --security-opt seccomp=unconfined \
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
