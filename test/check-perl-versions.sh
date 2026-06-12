#!/bin/sh

set -eu

script=scripts/check-perl-versions.pl
root=$(pwd)

perl "$script" --check \
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
    --config "${temp_dir}/drift.conf" \
    --tags-file "${temp_dir}/drift-tags.txt" > "$output"; then
    echo "ERROR: repository drift should require action." >&2
    exit 1
fi

grep -q 'DRIFT: 9.99.1 is missing from README.md' "$output"
grep -q 'DRIFT: Dockerfile default is not 9.99.1' "$output"

public_dir="${temp_dir}/public"
mkdir -p "${public_dir}/.github/workflows"
cp "${root}/Dockerfile" "${public_dir}/Dockerfile"
cp "${root}/README.md" "${public_dir}/README.md"
cp "${root}/.github/workflows/ci.yml" \
    "${public_dir}/.github/workflows/ci.yml"

(
    cd "$public_dir"
    perl "${root}/${script}" --check \
        --drift-profile public \
        --config "${root}/perl-versions.conf" \
        --tags-file "${root}/test/perl-tags-current.txt"
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

if perl "$script" --drift-profile unknown \
    --tags-file test/perl-tags-current.txt > "$output" 2>&1; then
    echo "ERROR: unknown drift profile should be rejected." >&2
    exit 1
fi

grep -q 'Unknown drift profile: unknown' "$output"

echo "Perl version detector tests passed."
