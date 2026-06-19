#!/bin/sh

set -eu

config=${PERL_VERSIONS_CONFIG:-perl-versions.conf}
if [ -n "${DOCUMENT_FILES:-}" ]; then
    documents=${DOCUMENT_FILES}
elif [ -n "${README_FILE:-}" ]; then
    documents=${README_FILE}
else
    documents=README.md:DOCKERHUB.md
fi
version=$(
    awk -F'|' '!/^#/ && NF { value=$1 } END { print value }' "$config"
)
image=${IMAGE:-perl-essentials:${version}}
capture_timestamp=${MODULE_VERSIONS_TIMESTAMP:-$(date -u '+%F %T')}
start='<!-- MODULE_VERSIONS_START -->'
end='<!-- MODULE_VERSIONS_END -->'
table=$(mktemp)
trap 'rm -f "$table"' EXIT HUP INT TERM

printf 'Versions captured on %s (UTC).\n\n' "$capture_timestamp" > "$table"
docker run --rm "$image" \
    /opt/perl-essentials/scripts/module-versions.pl \
    --format markdown \
    /opt/perl-essentials/cpanfile \
    /opt/perl-essentials/cpanfile-bootstrap-notest \
    /opt/perl-essentials/cpanfile-notest >> "$table"

old_ifs=${IFS}
IFS=:
for document in ${documents}; do
    output=$(mktemp)
    if ! awk -v start="$start" -v end="$end" -v table="$table" '
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
    ' "$document" > "$output"
    then
        rm -f "$output"
        exit 2
    fi
    mv "$output" "$document"
    printf 'Updated module table in %s\n' "$document"
done
IFS=${old_ifs}

trap - EXIT HUP INT TERM
rm -f "$table"
printf 'Updated module table for Perl %s from %s\n' "$version" "$image"
