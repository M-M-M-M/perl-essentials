#!/bin/sh

set -eu

# Install the same curated modules into the current Perl environment.
# The broad update skips tests; newly required curated distributions run tests.
cpanm -in App::cpanoutdated
cpan-outdated -p | cpanm -in
cpanm --installdeps --cpanfile cpanfile .

if scripts/list-cpanfile-modules.pl cpanfile-notest | grep -q .; then
    cpanm -in --installdeps --cpanfile cpanfile-notest .
fi

scripts/check-manifests.pl cpanfile cpanfile-notest
scripts/smoke-test.pl cpanfile cpanfile-notest
scripts/module-versions.pl cpanfile cpanfile-notest
