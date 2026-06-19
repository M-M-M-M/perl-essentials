#!/bin/sh

set -eu

: "${DOCKERHUB_USERNAME:?DOCKERHUB_USERNAME must be set}"
: "${PERL_VERSION:?PERL_VERSION must be set}"
: "${CPAN_CONFIGURE_TIMEOUT:=1200}"
: "${CPAN_TEST_TIMEOUT:=7200}"

command="${1:-}"
mode="${2:-}"
repository="${DOCKERHUB_USERNAME}/perl-essentials"

usage()
{
    printf 'Usage: %s build [perl|codex] PLATFORM DIGEST_FILE\n' "$0" >&2
    printf '       %s manifest [perl|codex] DIGEST_FILE...\n' "$0" >&2
    exit 2
}

select_target()
{
    case "${mode}" in
    perl)
        target="final"
        ;;
    codex)
        target="codex"
        ;;
    *)
        usage
        ;;
    esac
}

build_digest()
{
    platform="${3:-}"
    digest_file="${4:-}"
    test -n "${platform}" && test -n "${digest_file}" || usage

    select_target
    metadata_file="${digest_file}.metadata.json"
    mkdir -p "$(dirname "${digest_file}")"

    set -- docker buildx build \
        --progress plain \
        --platform "${platform}" \
        --target "${target}" \
        --build-arg PERL_VERSION="${PERL_VERSION}" \
        --build-arg CPAN_CONFIGURE_TIMEOUT="${CPAN_CONFIGURE_TIMEOUT}" \
        --build-arg CPAN_TEST_TIMEOUT="${CPAN_TEST_TIMEOUT}" \
        --tag "${repository}" \
        --output "type=image,name=${repository},push-by-digest=true,name-canonical=true,push=true" \
        --metadata-file "${metadata_file}"
    if [ "${mode}" = "codex" ]; then
        set -- "$@" --no-cache
    fi
    set -- "$@" .
    "$@"

    perl -MJSON::PP -0777 -e '
        my $metadata = decode_json(<STDIN>);
        my $digest = $metadata->{"containerimage.digest"};
        die "Build metadata does not contain containerimage.digest\n"
            if !defined $digest || $digest !~ /\Asha256:[0-9a-f]{64}\z/;
        print "$digest\n";
    ' < "${metadata_file}" > "${digest_file}"
    rm -f "${metadata_file}"
}

publish_manifest()
{
    shift 2
    test "$#" -eq 2 || usage

    : "${PUBLISH_TIMESTAMP:?PUBLISH_TIMESTAMP must be set}"
    : "${RELEASE_TAG:?RELEASE_TAG must be set}"

    select_target
    first_digest_file=$1
    second_digest_file=$2
    first_digest=$(tr -d '\r\n' < "${first_digest_file}")
    second_digest=$(tr -d '\r\n' < "${second_digest_file}")
    for digest in "${first_digest}" "${second_digest}"; do
        if ! printf '%s\n' "${digest}" \
            | grep -Eq '^sha256:[0-9a-f]{64}$'
        then
            printf 'Invalid architecture digest\n' >&2
            exit 1
        fi
    done

    if [ "${mode}" = "perl" ]; then
        series=$(printf '%s\n' "${PERL_VERSION}" | awk -F. \
            '{ print $1 "." $2 }')
        primary_tag="${repository}:${PERL_VERSION}"
        set -- \
            --tag "${repository}:${PERL_VERSION}-${PUBLISH_TIMESTAMP}" \
            --tag "${primary_tag}" \
            --tag "${repository}:${series}" \
            --tag "${repository}:${RELEASE_TAG}-${PERL_VERSION}"
        if awk -F'|' -v version="${PERL_VERSION}" \
            '$1 == version && $2 == "development" { found = 1 } END { exit !found }' \
            perl-versions.conf
        then
            set -- "$@" --tag "${repository}:latest"
        fi
    else
        primary_tag="${repository}:codex"
        set -- \
            --tag "${repository}:codex-${PUBLISH_TIMESTAMP}" \
            --tag "${primary_tag}" \
            --tag "${repository}:${RELEASE_TAG}-codex"
    fi

    docker buildx imagetools create "$@" \
        "${repository}@${first_digest}" \
        "${repository}@${second_digest}"
    docker buildx imagetools inspect "${primary_tag}"
}

case "${command}" in
build)
    build_digest "$@"
    ;;
manifest)
    publish_manifest "$@"
    ;;
*)
    usage
    ;;
esac
