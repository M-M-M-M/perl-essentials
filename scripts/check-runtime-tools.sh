#!/bin/sh

set -eu

for command in perltidy perlcritic rg gcat gfind ggrep gsed; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Required command not found: $command" >&2
        exit 1
    fi
done

if ! perltidy_output=$(cd / && perltidy -dpro 2>&1); then
    echo "Unable to inspect the default perltidy profile" >&2
    printf '%s\n' "$perltidy_output" >&2
    exit 1
fi

case "$perltidy_output" in
    *"/etc/perltidyrc"*)
        ;;
    *)
        echo "Expected perltidy profile /etc/perltidyrc" >&2
        printf '%s\n' "$perltidy_output" >&2
        exit 1
        ;;
esac

echo "Runtime tool checks passed."
