#!/bin/sh

set -eu

: "${PERL_VERSION:?PERL_VERSION must be set}"

mode="${1:-perl}"
platform="${CI_PLATFORM:-linux/amd64}"
buildx_bootstrap_attempts=6
buildx_bootstrap_retry_delay=10
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
        if [ "${attempt}" -ge "${buildx_bootstrap_attempts}" ]; then
            printf 'Buildx bootstrap failed after %s attempts\n' \
                "${attempt}" >&2
            return 1
        fi

        printf 'Buildx bootstrap failed (attempt %s/%s), retrying\n' \
            "${attempt}" "${buildx_bootstrap_attempts}" >&2
        attempt=$((attempt + 1))
        sleep "${buildx_bootstrap_retry_delay}"
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

run_validation_step()
{
    label="$1"
    shift

    printf 'CI validation step: %s\n' "${label}"
    if "$@"; then
        printf 'CI validation step: %s ok\n' "${label}"
        return 0
    else
        status=$?
    fi

    printf 'CI validation step: %s failed with status %s\n' \
        "${label}" "${status}" >&2
    return "${status}"
}

docker_run()
{
    docker run --rm --platform "${platform}" "$@"
}

validate_perl()
{
    docker_run "${image}" sh -c \
        'test "$(id -u)" = 1000 \
         && test "$(id -un)" = perl \
         && test "$HOME" = /home/perl \
         && test -w /work'
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
        'test "$PROMPT" = "[%n@%m][%h][%~] >" && test "$(alias ll)" = "ll='\''ls -Fl'\''"'
    docker_run --user root "${image}" zsh -lic \
        'test "$PROMPT" = "[%n@%m][%h][%~] #"'
    docker_run --user 12345:12345 "${image}" zsh -lic \
        'test "$PROMPT" = "[%n@%m][%h][%~] >"'
    validate_license_audit 0
}

validate_codex()
{
    codex_state="perl-essentials-codex-state-$$"

    run_validation_step codex-empty-state validate_codex_empty_state
    run_validation_step codex-volume-create docker volume create "${codex_state}"
    run_validation_step codex-user validate_codex_user
    run_validation_step codex-agents-file validate_codex_file /codex/AGENTS.md
    run_validation_step codex-rtk-file validate_codex_file /codex/RTK.md
    run_validation_step codex-zshrc-file validate_codex_file /codex/.zshrc
    run_validation_step codex-zshrc-persist validate_codex_zshrc_persist
    run_validation_step codex-agents-include validate_codex_agents_include
    run_validation_step codex-version docker_run "${image}" codex --version
    run_validation_step rtk-version docker_run "${image}" rtk --version
    run_validation_step bwrap-version docker_run "${image}" bwrap --version
    run_validation_step bwrap-setuid validate_codex_bwrap_setuid
    run_validation_step codex-workdir docker_run "${image}" sh -c 'test "$PWD" = /work'
    run_validation_step codex-path validate_codex_path
    run_validation_step codex-license-audit validate_license_audit 1
    run_validation_step codex-sandbox validate_codex_sandbox
}

validate_codex_empty_state()
{
    test -z "$(docker_run --entrypoint find "${image}" \
        /codex -mindepth 1 -print -quit)"
}

validate_codex_user()
{
    docker_run \
        --volume "${codex_state}:/codex" \
        "${image}" sh -c \
        'test "$(id -u)" = 1000 \
         && test "$(id -un)" = perl \
         && test "$HOME" = /codex \
         && test -w /codex'
}

validate_codex_file()
{
    docker_run \
        --entrypoint test \
        --volume "${codex_state}:/codex" \
        "${image}" -f "$1"
}

validate_codex_zshrc_persist()
{
    docker_run \
        --entrypoint sh \
        --volume "${codex_state}:/codex" \
        "${image}" -c \
        'printf "%s\n" "# custom Zsh configuration" > /codex/.zshrc'
    docker_run \
        --volume "${codex_state}:/codex" \
        "${image}" true
    docker_run \
        --entrypoint grep \
        --volume "${codex_state}:/codex" \
        "${image}" -qxF '# custom Zsh configuration' /codex/.zshrc
}

validate_codex_agents_include()
{
    test "$(docker_run \
        --entrypoint grep \
        --volume "${codex_state}:/codex" \
        "${image}" -c '^@/codex/RTK\.md$' /codex/AGENTS.md)" -eq 1
}

validate_codex_bwrap_setuid()
{
    test "$(docker_run \
        --entrypoint stat \
        "${image}" -c '%a:%U:%G' /usr/bin/bwrap)" = "4755:root:root"
}

validate_codex_path()
{
    docker_run "${image}" zsh -lic \
        'command -v perl >/dev/null \
         && command -v codex >/dev/null \
         && command -v rtk >/dev/null'
}

validate_codex_sandbox()
{
    sandbox_output=""
    sandbox_status=0

    if [ "${CI_SKIP_CODEX_SANDBOX:-}" = "1" ]; then
        printf 'Skipping Codex sandbox validation because CI_SKIP_CODEX_SANDBOX=1\n'
        return 0
    fi

    if sandbox_output="$(run_codex_sandbox 2>&1)"; then
        printf '%s\n' "${sandbox_output}"
        return 0
    else
        sandbox_status=$?
    fi

    printf '%s\n' "${sandbox_output}" >&2
    case "${sandbox_output}" in
    *'bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted'*)
        printf '%s\n' \
            'Retrying Codex sandbox validation as root because the host blocked non-root RTM_NEWADDR' >&2
        run_codex_sandbox --user root
        ;;
    *'Sandbox(SeccompInstall'*'Invalid argument'*)
        if codex_sandbox_seccomp_einval_is_expected; then
            printf '%s\n' \
                'Skipping Codex sandbox validation because linux/amd64 is running on an arm64 Docker host and Codex seccomp sandbox is not supported there'
            return 0
        fi
        return "${sandbox_status}"
        ;;
    *)
        return "${sandbox_status}"
        ;;
    esac
}

codex_sandbox_seccomp_einval_is_expected()
{
    host_architecture=""

    if [ "${platform}" != "linux/amd64" ]; then
        return 1
    fi

    host_architecture="$(docker info --format '{{.Architecture}}' 2>/dev/null || true)"
    case "${host_architecture}" in
    aarch64|arm64)
        return 0
        ;;
    *)
        return 1
        ;;
    esac
}

run_codex_sandbox()
{
    docker_run \
        "$@" \
        --cap-add SYS_ADMIN \
        --security-opt apparmor=unconfined \
        --security-opt seccomp=unconfined \
        "${image}" codex sandbox -- sh -c 'printf sandbox-ok'
}

case "${mode}" in
perl)
    target="final"
    image="${CI_IMAGE:-perl-essentials:${PERL_VERSION}}"
    no_cache=""
    validate="validate_perl"
    ;;
codex)
    target="codex"
    image="${CI_IMAGE:-perl-essentials:codex}"
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
if [ -n "${no_cache}" ]; then
    docker buildx build \
        --builder "${builder}" \
        --platform "${platform}" \
        --target "${target}" \
        --load \
        --build-arg PERL_VERSION="${PERL_VERSION}" \
        --tag "${image}" \
        "${no_cache}" \
        .
else
    docker buildx build \
        --builder "${builder}" \
        --platform "${platform}" \
        --target "${target}" \
        --load \
        --build-arg PERL_VERSION="${PERL_VERSION}" \
        --tag "${image}" \
        .
fi

printf 'Docker image %s loaded successfully\n' "${image}"
printf 'Validating %s image\n' "${mode}"
if "${validate}"; then
    exit 0
else
    status=$?
fi
exit "${status}"
