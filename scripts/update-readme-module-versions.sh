#!/bin/sh

set -eu

config=${PERL_VERSIONS_CONFIG:-perl-versions.conf}
readme=${README_FILE:-README.md}
version=$(
    awk -F'|' '!/^#/ && NF { value=$1 } END { print value }' "$config"
)
image=${IMAGE:-perl-essentials:${version}}
start='<!-- MODULE_VERSIONS_START -->'
end='<!-- MODULE_VERSIONS_END -->'
table=$(mktemp)
output=$(mktemp)
trap 'rm -f "$table" "$output"' EXIT HUP INT TERM

docker run --rm "$image" \
    /opt/perl-essentials/scripts/module-versions.pl \
    --format markdown \
    /opt/perl-essentials/cpanfile \
    /opt/perl-essentials/cpanfile-notest > "$table"

awk -v start="$start" -v end="$end" -v table="$table" '
    $0 == start {
        print
        while ((getline line < table) > 0) print line
        close(table)
        replacing = 1
        next
    }
    $0 == end {
        replacing = 0
        print
        found = 1
        next
    }
    !replacing { print }
    END {
        if (!found) exit 2
    }
' "$readme" > "$output"

mv "$output" "$readme"
trap - EXIT HUP INT TERM
rm -f "$table"
printf 'Updated module table for Perl %s from %s\n' "$version" "$image"
