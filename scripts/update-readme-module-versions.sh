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
codex_image=${CODEX_IMAGE:-perl-essentials:codex}
codex_timestamp=${CODEX_VERSIONS_TIMESTAMP:-$capture_timestamp}
module_start='<!-- MODULE_VERSIONS_START -->'
module_end='<!-- MODULE_VERSIONS_END -->'
codex_start='<!-- CODEX_TARGET_START -->'
codex_end='<!-- CODEX_TARGET_END -->'
module_table=$(mktemp)
codex_table=$(mktemp)
trap 'rm -f "$module_table" "$codex_table"' EXIT HUP INT TERM

printf 'Versions captured on %s (UTC).\n\n' "$capture_timestamp" > "$module_table"
cat >> "$module_table" <<'MARKDOWN'
This inventory was captured from the default image at the
timestamp above. Module versions may differ between publication runs. For an
exact image, see `/opt/perl-essentials/module-versions.txt`.

MARKDOWN
docker run --rm "$image" \
    /opt/perl-essentials/scripts/module-versions.pl \
    --format markdown \
    /opt/perl-essentials/cpanfile \
    /opt/perl-essentials/cpanfile-bootstrap-notest \
    /opt/perl-essentials/cpanfile-notest >> "$module_table"

codex_version=$(
    docker run --rm "$codex_image" codex --version | awk '{ print $2 }'
)
rtk_version=$(
    docker run --rm "$codex_image" rtk --version | awk '{ print $2 }'
)

cat > "$codex_table" <<MARKDOWN
| Target | Perl base | Codex CLI | RTK | Publication |
| --- | --- | --- | --- | --- |
| \`codex\` | $version | Latest at no-cache build; $codex_version observed $codex_timestamp | Latest at no-cache build; $rtk_version observed $codex_timestamp | \`codex\`, release, and timestamp tags |
MARKDOWN

replace_section()
{
    document=$1
    start=$2
    end=$3
    table=$4
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
}

old_ifs=${IFS}
IFS=:
for document in ${documents}; do
    replace_section "$document" "$module_start" "$module_end" "$module_table"
    replace_section "$document" "$codex_start" "$codex_end" "$codex_table"
    printf 'Updated module and Codex tables in %s\n' "$document"
done
IFS=${old_ifs}

trap - EXIT HUP INT TERM
rm -f "$module_table" "$codex_table"
printf 'Updated module table for Perl %s from %s\n' "$version" "$image"
printf 'Updated Codex table from %s\n' "$codex_image"
