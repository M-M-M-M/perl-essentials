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

The CI build mounts the checkout read-only at `/work` and runs the formatting
check with `--user "$(id -u):$(id -g)"`. This keeps the container process
aligned with the checkout owner, allowing `git ls-files` to run without adding
`/work` as a globally trusted `safe.directory`.

The bundled `/opt/perl-essentials/AGENTS.md` is not automatically active for a
project mounted at `/work`, because it is outside that project's directory
hierarchy. Copy it into the project only after reviewing its instructions:

```sh
cp -n /opt/perl-essentials/AGENTS.md /work/AGENTS.md
cp -n /opt/perl-essentials/.perltidyrc /work/.perltidyrc
```

The image also provides `rg` and GNU-prefixed aliases `gcat`, `gfind`, `ggrep`,
and `gsed`.

## Use the optional Codex target

The `codex` target derives from the complete `final` image. Normal image builds
stop at `final`; GitHub Actions and Bitbucket validate the Codex target
separately with Perl 5.43.9, while Docker Hub publication remains disabled.

The target runs the official standalone installer. Its package files remain
under `/opt/codex`, while runtime state uses `CODEX_HOME=/codex`. Keeping these
locations separate prevents the authentication mount from hiding the installed
CLI. A no-cache build deliberately resolves the latest available Codex version,
so this target is not reproducible at the Codex version level:

```sh
docker build --target codex --no-cache -t perl-essentials:codex .
mkdir -p codex-auth
```

The first login uses device authorization because a container cannot reliably
receive the browser callback:

```sh
docker run --rm -it \
  -v "$PWD":/work \
  -v "$PWD/codex-auth":/codex \
  perl-essentials:codex codex login --device-auth
```

Start Codex later with the same writable project and state mounts:

```sh
docker run --rm -it \
  --cap-add SYS_ADMIN \
  --security-opt seccomp=unconfined \
  --security-opt no-new-privileges=true \
  -v "$PWD":/work \
  -v "$PWD/codex-auth":/codex \
  perl-essentials:codex
```

Open an interactive Zsh shell when Perl commands or project checks should run
before Codex:

```sh
docker run --rm -it \
  --cap-add SYS_ADMIN \
  --security-opt seccomp=unconfined \
  --security-opt no-new-privileges=true \
  -v "$PWD":/work \
  -v "$PWD/codex-auth":/codex \
  perl-essentials:codex zsh -l
```

The shell starts in `/work`. Run commands such as `perl -v`, `prove -lr test`,
or project-specific scripts, then start Codex manually with `codex`. Keeping
the same `codex-auth/` mount makes the existing container-specific login
available to the manually started CLI.

The target installs Debian's `bubblewrap` package because Codex uses `bwrap`
for its Linux command sandbox. Docker applies its own seccomp syscall filter
outside that sandbox. The default Docker profile blocks the namespace-related
system calls that `bubblewrap` needs, so Codex cannot initialize its sandbox in
a normal container even when `bwrap` is installed.

`--security-opt seccomp=unconfined` disables Docker's outer syscall filter for
this container. It does not disable the sandbox that Codex creates with
`bubblewrap`, but it does expose more Linux kernel system calls to every process
in the container. Use this mode only with the trusted `perl-essentials:codex`
image and trusted projects. Do not combine it with `--privileged`, do not mount
`/var/run/docker.sock`, and do not weaken the host Docker daemon globally.

`--cap-add SYS_ADMIN` permits the mount namespace operations that Bubblewrap
uses. This is a broad Linux capability, although narrower than `--privileged`,
and must be granted only to the Codex container while it runs trusted projects.

`--security-opt no-new-privileges=true` remains compatible with the Codex
sandbox and prevents processes from gaining additional privileges through
set-user-ID binaries or file capabilities. It reduces risk but does not replace
Docker's disabled seccomp filter.

Do not mount the host's complete home directory or `~/.codex`. The repository
root's `codex-auth/` directory is ignored by Git and Docker, but it still
contains sensitive local state such as access tokens, configuration, sessions,
history, logs, and caches. To remove the container-specific login:

```sh
docker run --rm -it \
  -v "$PWD/codex-auth":/codex \
  perl-essentials:codex codex logout
rm -rf codex-auth
```

`codex logout` removes credentials stored in this Codex home. Deleting
`codex-auth/` removes only the local copy and must not be treated as
server-side token revocation.

Validate a fresh unauthenticated state without performing a real login:

```sh
tmp="$(mktemp -d)"
test -z "$(docker run --rm -v "$tmp":/codex \
  perl-essentials:codex find /codex -mindepth 1 -print -quit)"
docker run --rm -v "$tmp":/codex perl-essentials:codex codex --version
docker run --rm -v "$tmp":/codex perl-essentials:codex pwd
docker run --rm \
  --cap-add SYS_ADMIN \
  --security-opt seccomp=unconfined \
  --security-opt no-new-privileges=true \
  -v "$tmp":/codex \
  perl-essentials:codex codex sandbox -- sh -c 'printf sandbox-ok'
rm -rf "$tmp"
```

The standalone CLI may create runtime files under `/codex/tmp` even for
`codex --version`; the empty-state check must therefore run first.

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
