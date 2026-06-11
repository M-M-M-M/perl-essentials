# Maintenance and debugging

## Module policy

`cpanfile` is the canonical list of curated modules. CPAN runs tests for every
distribution it installs to satisfy this file. A core or dual-life module that
is already current is not downgraded just to rerun its distribution tests.
Every listed module is always covered by the blocking local smoke test.

`cpanfile-notest` is a temporary workaround list. It disables only the upstream
CPAN test suite for the listed module. The module must still install and pass
the local smoke test.

The global update remains intentionally test-free:

```sh
cpanm -in App::cpanoutdated
cpan-outdated -p | cpanm -in
```

This updates installed distributions, including dual-life modules, but does
not replace the Perl interpreter. Some modules, such as `File::Copy`, are
published only as part of the complete Perl distribution. Forcing their
reinstallation could replace a newer development Perl with an older stable
release, so they are validated by the official base-image tests and this
repository's smoke test.

## Add a module

1. Add an alphabetical `requires 'Module::Name';` entry to `cpanfile`.
2. Build the default image with detailed output.
3. Run the smoke test and inspect the generated version inventory.
4. Build every Perl version in the CI matrix before release.

```sh
docker build --progress=plain --no-cache \
  --build-arg PERL_VERSION=5.43.9 \
  -t perl-essentials:debug .

docker run --rm perl-essentials:debug \
  cat /opt/perl-essentials/module-versions.txt
```

Regenerate the README module table after rebuilding the default image:

```sh
scripts/update-readme-module-versions.sh
git diff -- README.md
```

## Perl agent guidance and formatting

The repository vendors the exact `AGENTS.md` and `.perltidyrc` files from
`perl-agents-md` v1.0.0, commit
`8d8df7b718308ab6d7b8ced3486f1a779330a529`.

The Docker image stores both files under `/opt/perl-essentials` and installs
the profile as `/etc/perltidyrc`. Perl::Tidy checks the current directory
before the system profile, so a mounted project's `.perltidyrc` overrides the
image default.

Preview formatting without changing a source file:

```sh
perltidy -st -se path/to/script.pl
```

Format a file in place without a backup:

```sh
perltidy -b -bext='/' path/to/script.pl
```

Run the repository formatting test and static analysis:

```sh
test/check-perl-format.sh
perlcritic path/to/script.pl
```

The bundled `/opt/perl-essentials/AGENTS.md` is not automatically active for a
project mounted at `/work`, because it is outside that project's directory
hierarchy. Copy it into the project only after reviewing its instructions:

```sh
cp -n /opt/perl-essentials/AGENTS.md /work/AGENTS.md
cp -n /opt/perl-essentials/.perltidyrc /work/.perltidyrc
```

The image also provides `rg` and GNU-prefixed aliases `gcat`, `gfind`, `ggrep`,
and `gsed`.

## Create a temporary test exception

An exception is appropriate only when installation succeeds but an upstream
test is broken or depends on an unavailable external service. A compilation
failure, missing system library, or real compatibility defect is not a test
exception.

1. Reproduce the failure with tests and verbose output:

   ```sh
   cpanm --reinstall --verbose Module::Name
   ```

2. Preserve and inspect the latest CPAN work directory:

   ```sh
   cpanm --reinstall --verbose Module::Name
   ls -lt /root/.cpanm/work
   find /root/.cpanm/work -name build.log -print
   less /root/.cpanm/work/*/build.log
   ```

3. Enter the distribution directory and rerun its tests:

   ```sh
   cd /root/.cpanm/work/*/Module-Name-*
   prove -lv t
   # Or, according to the distribution:
   make test TEST_VERBOSE=1
   ./Build test --verbose
   ```

4. Confirm that installation without tests succeeds and the module loads:

   ```sh
   cpanm -in --reinstall Module::Name
   perl -MModule::Name -e 'print "$Module::Name::VERSION\n"'
   ```

5. Move the module from `cpanfile` to `cpanfile-notest`. On the same line,
   record the upstream issue URL, affected Perl/module versions, and a review
   date:

   ```perl
   requires 'Module::Name'; # https://issue.example/123; Perl 5.43.9; review 2026-09-01
   ```

6. Rebuild the affected version, then the complete matrix. The smoke test is
   still blocking.

Do not duplicate a module across both files. Do not add a permanent exception
without a review date.

## Remove an exception

At or before the review date:

1. Run `cpanm --reinstall --verbose Module::Name`.
2. If the tests pass, move the entry back to `cpanfile`.
3. Rebuild the complete matrix.
4. Remove obsolete workaround comments and close the corresponding TODO.

## Debug an image build

Validate Dockerfile syntax without building:

```sh
docker build --check .
```

Show full logs and disable the build cache:

```sh
docker build --progress=plain --no-cache \
  --build-arg PERL_VERSION=5.43.9 \
  -t perl-essentials:5.43.9 .
```

Build and enter the pre-CPAN debug target:

```sh
docker build --target debug-base \
  --build-arg PERL_VERSION=5.43.9 \
  -t perl-essentials:debug-base .
docker run --rm -it -v "$PWD":/work perl-essentials:debug-base
```

This target contains the official Perl interpreter, system packages, Zsh,
Oh My Zsh, manifests, and repository scripts. It stops before
`App::cpanoutdated`, the broad module upgrade, and curated module installation.
Use it to execute each `cpanm` command manually and inspect `/root/.cpanm`.

Build and enter the complete debug target:

```sh
docker build --target debug \
  --build-arg PERL_VERSION=5.43.9 \
  -t perl-essentials:debug .
docker run --rm -it -v "$PWD":/work perl-essentials:debug
```

Inside the container, useful diagnostics include:

```sh
perl -V
cpanm --version
cpan-outdated --verbose
perl -MModule::Name -e 'print "$Module::Name::VERSION\n"'
perl -MModule::Metadata -E 'say Module::Metadata->new_from_module("Module::Name")->filename'
perldoc Module::Name
ldd "$(perl -MModule::Metadata -E 'say Module::Metadata->new_from_module("Module::Name")->filename')"
```

Run repository checks without rebuilding:

```sh
scripts/list-cpanfile-modules.pl cpanfile cpanfile-notest
scripts/check-manifests.pl cpanfile cpanfile-notest
scripts/smoke-test.pl cpanfile cpanfile-notest
scripts/module-versions.pl cpanfile cpanfile-notest
perl -c test/integration-postgres.pl
test/check-perl-versions.sh
```

## CI and releases

CI validates all configured Perl versions. The matrix deliberately keeps legacy
versions in addition to the newest stable and development versions so software
can be tested before distribution to older systems.

`perl-versions.conf` records the exact versions and their roles. Check Docker
Hub for newer official threaded tags:

```sh
perl scripts/check-perl-versions.pl
perl scripts/check-perl-versions.pl --check
```

The script proposes newer patch releases for configured series and only the
immediately following series, such as 5.44 after 5.43. It also reports drift
between the configuration, Dockerfile, CI files, and README. It never edits
files. The scheduled workflow runs it every Monday. Keeping this maintenance
check separate from normal branch builds means a newly published upstream
image creates a maintenance action without blocking unrelated changes.

Release publication is intentionally separate from validation workflows.
Public release notes are recorded in `CHANGELOG.md`.

## Prepare a release

Releases follow semantic versioning:

- Increase the patch version for backward-compatible fixes, for example
  `v0.1.1`.
- Increase the minor version for backward-compatible functionality, for
  example `v0.2.0`.
- Increase the major version for incompatible changes, for example `v1.0.0`.

Before creating a release, update `CHANGELOG.md`:

1. Replace the current `Unreleased` changes with a version heading containing
   the release date, such as `## [0.1.1] - 2026-06-11`.
2. Add a new empty `## [Unreleased]` section above the released version.
3. Change the `Unreleased` comparison link to start at the new tag.
4. Add a comparison link from the previous tag to the new tag.

For example, a patch release after `v0.1.0` uses:

```markdown
[Unreleased]: https://github.com/M-M-M-M/perl-essentials/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/M-M-M-M/perl-essentials/compare/v0.1.0...v0.1.1
```

Run the complete test suite and confirm that every configured Perl version
passes CI before publishing the release. Create an annotated `vX.Y.Z` tag;
do not reuse or move a tag that has already been pushed. If a released change
needs correction, prepare a new patch release.

The Perl 5.26.3 base image uses end-of-life Debian Buster repositories. The
Dockerfile switches only that image to `archive.debian.org` and disables the
expired repository timestamp check.
