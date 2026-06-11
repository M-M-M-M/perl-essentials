#!/bin/sh

set -eu

script=scripts/check-perl-format.pl

perl "$script"

fixture=$(mktemp)
trap 'rm -f "$fixture"' EXIT HUP INT TERM

cat > "$fixture" <<'EOF'
use strict;
use warnings;
if (1) {
    print "not formatted\n";
}
EOF

if perl "$script" "$fixture" >/dev/null 2>&1; then
    echo "ERROR: unformatted fixture should fail." >&2
    exit 1
fi

echo "Perl formatting detector tests passed."
