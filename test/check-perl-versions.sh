#!/bin/sh

set -eu

script=scripts/check-perl-versions.pl
root=$(pwd)
profile=${1:-private}

if [ "$#" -gt 1 ] ||
    { [ "$profile" != private ] && [ "$profile" != public ]; }; then
    echo "Usage: $0 [public|private]" >&2
    exit 2
fi

perl "$script" --check \
    --drift-profile "$profile" \
    --tags-file test/perl-tags-current.txt

temp_dir=$(mktemp -d)
output="${temp_dir}/output"
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

if perl "$script" --check --no-drift \
    --tags-file test/perl-tags-update.txt > "$output"; then
    echo "ERROR: update fixture should require action." >&2
    exit 1
fi

grep -q 'UPDATE: 5.42.2 -> 5.42.3' "$output"
grep -q 'UPDATE: 5.43.9 -> 5.43.10' "$output"
grep -q 'ADD: 5.44.0' "$output"

cat > "${temp_dir}/drift.conf" <<'EOF'
9.99.1|development|Synthetic drift test
EOF
cat > "${temp_dir}/drift-tags.txt" <<'EOF'
9.99.1-threaded
EOF

if perl "$script" --check \
    --drift-profile "$profile" \
    --config "${temp_dir}/drift.conf" \
    --tags-file "${temp_dir}/drift-tags.txt" > "$output"; then
    echo "ERROR: repository drift should require action." >&2
    exit 1
fi

grep -q 'DRIFT: 9.99.1 is missing from README.md' "$output"
grep -q 'DRIFT: Dockerfile default is not 9.99.1' "$output"

if [ "${PERL_ESSENTIALS_NESTED_PUBLIC_TEST:-0}" != 1 ]; then
    public_dir="${temp_dir}/public"
    mkdir -p "${public_dir}/.github/workflows"
    cp "${root}/Dockerfile" "${public_dir}/Dockerfile"
    cp "${root}/README.md" "${public_dir}/README.md"
    cp "${root}/.github/workflows/ci.yml" \
        "${public_dir}/.github/workflows/ci.yml"
    mkdir -p "${public_dir}/scripts" "${public_dir}/test"
    cp "${root}/${script}" "${public_dir}/${script}"
    cp "${root}/perl-versions.conf" "${public_dir}/perl-versions.conf"
    cp "${root}/test/check-perl-versions.sh" \
        "${public_dir}/test/check-perl-versions.sh"
    cp "${root}/test/perl-tags-current.txt" \
        "${public_dir}/test/perl-tags-current.txt"
    cp "${root}/test/perl-tags-update.txt" \
        "${public_dir}/test/perl-tags-update.txt"

    (
        cd "$public_dir"
        PERL_ESSENTIALS_NESTED_PUBLIC_TEST=1 \
            test/check-perl-versions.sh public
    )

    if (
        cd "$public_dir"
        perl "${root}/${script}" --check \
            --drift-profile private \
            --config "${root}/perl-versions.conf" \
            --tags-file "${root}/test/perl-tags-current.txt" > "$output"
    ); then
        echo "ERROR: private drift profile should require Bitbucket config." >&2
        exit 1
    fi

    grep -q 'DRIFT: cannot read bitbucket-pipelines.yml' "$output"
fi

if perl "$script" --drift-profile unknown \
    --tags-file test/perl-tags-current.txt > "$output" 2>&1; then
    echo "ERROR: unknown drift profile should be rejected." >&2
    exit 1
fi

grep -q 'Unknown drift profile: unknown' "$output"

fake_http="${temp_dir}/lib/HTTP"
mkdir -p "$fake_http"
cat > "${fake_http}/Tiny.pm" <<'EOF'
package HTTP::Tiny;
use strict;
use warnings;
sub new { return bless {}, shift }
sub get {
    return {
        success => 0,
        status  => 599,
        reason  => 'Internal Exception',
        content => 'TLS support is unavailable',
    };
}
1;
EOF

if PERL5LIB="${temp_dir}/lib" perl "$script" --check \
    --no-drift > "$output" 2>&1; then
    echo "ERROR: simulated Docker Hub failure should be reported." >&2
    exit 1
fi

grep -q 'Docker Hub request failed (599 Internal Exception)' "$output"
grep -q 'TLS support is unavailable' "$output"

if test/check-perl-versions.sh unknown > "$output" 2>&1; then
    echo "ERROR: unknown wrapper profile should be rejected." >&2
    exit 1
fi

grep -q 'Usage: test/check-perl-versions.sh \[public|private\]' "$output"

echo "Perl version detector tests passed."
