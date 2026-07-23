# Maintenance and debugging

## Module policy

`cpanfile` is the canonical list of curated modules. CPAN runs tests for every
distribution it installs to satisfy this file. A core or dual-life module that
is already current is not downgraded just to rerun its distribution tests.
Every listed module is always covered by the blocking local smoke test.

`cpanfile-bootstrap-notest` and `cpanfile-notest` are temporary workaround
lists. They disable only the upstream CPAN test suite for listed modules. The
module must still install and pass the local smoke test.

Use `cpanfile-bootstrap-notest` only for dependencies whose failing upstream
tests block a curated module before `cpanfile` can finish installing. Use
`cpanfile-notest` for direct curated modules whose own tests fail after the
tested manifest has installed.

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
  --build-arg PERL_VERSION=5.44.0 \
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
image default. Pass `-pro=/work/custom.perltidyrc` to use a specific profile,
or `-npro` to ignore all profile files.

Preview formatting in the container without changing a mounted source file:

```sh
docker run --rm -v "$PWD":/work \
  perlessentials/perl-essentials:5.42 \
  perltidy -st -se /work/path/to/script.pl
```

Format a mounted file in place without a backup, preserving host ownership:

```sh
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD":/work \
  perlessentials/perl-essentials:5.42 \
  perltidy -b -bext='/' /work/path/to/script.pl
```

Run the repository formatting test and static analysis:

```sh
test/check-perl-format.sh
perlcritic path/to/script.pl
actionlint
```

`actionlint` is optional for the Perl image but recommended for repository
maintenance. The test suite runs it when it is installed and skips that check
otherwise.

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
use a final `default` alias of the Perl-only `final` stage. Perl publication
selects `final` explicitly. GitHub Actions validates the Codex target
separately with Perl 5.44.0, and release publication publishes it under
Codex-specific tags. RTK is therefore present only in the explicit `codex`
target.

Published Perl and Codex images run by default as the non-root `perl` user
with UID/GID `1000:1000`. For writable host bind mounts, pass
`--user "$(id -u):$(id -g)"` so generated files retain host ownership.
Use `--user root` only for an explicit administrative operation. The
`debug-base` and `debug` targets intentionally remain root for package and
CPAN diagnostics.

Docker bind mounts retain numeric ownership from the host. Names are resolved
against the container's `/etc/passwd` and `/etc/group`, so a macOS file owned
by UID/GID `502:80` can appear as `502:dialout` inside the container while
still being correctly owned by the host account. Do not run `chown` merely to
change this container-side display. The global configuration in
`/etc/zsh/zshrc` applies to root, `perl`, and host UID overrides. A minimal
personal `.zshrc` suppresses `zsh-newuser-install`; Codex creates it only when
the mounted `/codex` state does not already contain one.

The target runs the official Codex and RTK installers. Codex package files
remain under `/opt/codex`, while both tools use `/codex` for runtime state.
Keeping these locations separate prevents the authentication mount from hiding
the installed CLIs. A no-cache build deliberately resolves their latest
available versions, so this target is not reproducible at the Codex or RTK
version level:

| Target | Perl base | Codex CLI | RTK | Publication |
| --- | --- | --- | --- | --- |
| `codex` | 5.44.0 | Latest; 0.139.0 observed 2026-06-12 | Latest; 0.42.4 observed 2026-06-12 | Docker Hub Codex tags |

The observed versions document a successful build rather than pinning future
builds. CI runs `codex --version` and `rtk --version` so each validation log
records the resolved versions.

```sh
PERL_VERSION=5.44.0 scripts/ci-build.sh codex
mkdir -p codex-auth
```

This command builds, tags, and validates the only Codex flavor,
`perl-essentials:codex`, replacing any older local image with that tag. Set
`CI_PLATFORM=linux/arm64` on an ARM64 Docker host when a native build is
preferred. The script reports build and validation phases and retries a
transient Buildx bootstrap failure up to three times.
Set `CI_SKIP_CODEX_SANDBOX=1` only when validating in an emulated or restricted
environment where Bubblewrap namespace creation is known to be blocked.
Native GitHub AMD64 and ARM64 validations run the live smoke test first as the
default non-root `perl` user. If the host returns exactly
`bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted`, CI reports the
host restriction and retries that smoke test once as root. Other failures
remain fatal without a retry.

CI state validation uses a uniquely named, ephemeral Docker volume mounted on
`/codex`. Keeping fixture creation, inspection, and deletion inside Docker
avoids runner-specific bind-mount assumptions. This fixture has no credentials,
keeps its ownership entirely inside the Docker daemon, and is removed when the
script exits. It is distinct from the repository-local `codex-auth/` directory
used to persist interactive logins.

The first login uses device authorization because a container cannot reliably
receive the browser callback:

```sh
docker run --rm -it --user "$(id -u):$(id -g)" \
  -v "$PWD":/work \
  -v "$PWD/codex-auth":/codex \
  perl-essentials:codex codex login --device-auth
```

Start Codex later with the same writable project and state mounts:

```sh
docker run --rm -it --user "$(id -u):$(id -g)" \
  -v "$PWD":/work \
  -v "$PWD/codex-auth":/codex \
  perl-essentials:codex
```

Open an interactive Zsh shell when Perl commands or project checks should run
before Codex:

```sh
docker run --rm -it --user "$(id -u):$(id -g)" \
  -v "$PWD":/work \
  -v "$PWD/codex-auth":/codex \
  perl-essentials:codex zsh -l
```

The shell starts in `/work`. Run commands such as `perl -v`, `prove -lr test`,
or project-specific scripts, then start Codex manually with `codex`. Keeping
the same `codex-auth/` mount makes the existing container-specific login
available to the manually started CLI.

Before every command, the container entrypoint runs `rtk init -g --codex`.
The operation is idempotent and creates the RTK global `AGENTS.md` and `RTK.md`
integration files under `/codex`; no manual initialization is required. RTK
telemetry is disabled by default. Because `/codex` is mounted from
`codex-auth/`, the integration and RTK configuration persist with the Codex
authentication, sessions, and history.

The target installs Debian's `bubblewrap` package because Codex uses `bwrap`
for its Linux command sandbox. The image keeps `/usr/bin/bwrap` owned by
`root:root` with mode `4755` so Bubblewrap can fall back to its setuid mode
when user namespaces are unavailable.

CI runs the Codex sandbox smoke test on native GitHub `linux/amd64` and
`linux/arm64` runners. Restricted or emulated environments can opt out with
`CI_SKIP_CODEX_SANDBOX=1`; those jobs still validate the installed tools,
`/usr/bin/bwrap` ownership and mode, entrypoint state initialization, and
license audit.

The targeted root fallback is limited to CI validation. It does not change the
image's default user or runtime behavior. On a host that blocks non-root
Bubblewrap namespaces, an interactive Codex session can still report the same
RTM_NEWADDR error until the host policy is configured.

### Advanced Bubblewrap troubleshooting

Start with the normal Docker commands above. Do not add capabilities or disable
security profiles preemptively. Some Linux hosts apply outer seccomp or
AppArmor rules that prevent Bubblewrap from creating its mount namespace. If
Codex specifically reports a namespace, mount propagation, or Bubblewrap
initialization error, reproduce it with:

```sh
docker run --rm --user "$(id -u):$(id -g)" \
  --cap-add SYS_ADMIN \
  --security-opt apparmor=unconfined \
  --security-opt seccomp=unconfined \
  -v "$PWD":/work \
  -v "$PWD/codex-auth":/codex \
  perl-essentials:codex codex sandbox -- sh -c 'printf sandbox-ok'
```

`--security-opt seccomp=unconfined` disables Docker's outer syscall filter for
this container. It does not disable the sandbox that Codex creates with
`bubblewrap`, but it does expose more Linux kernel system calls to every process
in the container. Use this mode only with the trusted `perl-essentials:codex`
image and trusted projects. Do not combine it with `--privileged`, do not mount
`/var/run/docker.sock`, and do not weaken the host Docker daemon globally.

`--cap-add SYS_ADMIN` permits the mount namespace operations that Bubblewrap
uses. This is a broad Linux capability, although narrower than `--privileged`,
and must be granted only to the Codex container while it runs trusted projects.

`--security-opt apparmor=unconfined` prevents the host's Docker AppArmor profile
from rejecting Bubblewrap's mount propagation setup. It weakens the outer
container confinement and therefore has the same trusted-image and
trusted-project restrictions.

Ubuntu 24.04 can separately restrict unprivileged user namespaces through
AppArmor. OpenAI's
[Codex sandbox documentation](https://developers.openai.com/codex/concepts/sandboxing)
recommends loading the distribution Bubblewrap profile rather than disabling
that restriction globally:

```sh
sudo apt update
sudo apt install apparmor-profiles apparmor-utils
sudo install -m 0644 \
  /usr/share/apparmor/extra-profiles/bwrap-userns-restrict \
  /etc/apparmor.d/bwrap-userns-restrict
sudo apparmor_parser -r /etc/apparmor.d/bwrap-userns-restrict
```

This host-level profile cannot be installed from the image or a normal
container process. The deprecated Codex `use_legacy_landlock` feature is not
enabled by the image or CI.

Do not add `--security-opt no-new-privileges=true` to the Codex container. It
prevents the setuid fallback that Bubblewrap needs on hosts where unprivileged
user namespaces are unavailable.

Do not mount the host's complete home directory or `~/.codex`. The repository
root's `codex-auth/` directory is ignored by Git and Docker, but it still
contains sensitive local state such as access tokens, configuration, sessions,
history, logs, and caches. To remove the container-specific login:

```sh
docker run --rm -it --user "$(id -u):$(id -g)" \
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
test -z "$(docker run --rm --entrypoint find \
  perl-essentials:codex /codex -mindepth 1 -print -quit)"
docker run --rm --user "$(id -u):$(id -g)" \
  -v "$tmp":/codex perl-essentials:codex true
test -f "$tmp/AGENTS.md"
test -f "$tmp/RTK.md"
docker run --rm --user "$(id -u):$(id -g)" \
  -v "$tmp":/codex perl-essentials:codex codex --version
docker run --rm --user "$(id -u):$(id -g)" \
  -v "$tmp":/codex perl-essentials:codex rtk --version
docker run --rm --user "$(id -u):$(id -g)" \
  -v "$tmp":/codex perl-essentials:codex pwd
rm -rf "$tmp"
```

The raw image contains an empty `/codex`; the empty-state check bypasses the
entrypoint so it must run first. Normal commands initialize the RTK integration
and Codex may also create runtime files under `/codex/tmp`.

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

5. Move the module from `cpanfile` to `cpanfile-notest`. If the failing module
   is only a dependency that blocks a tested curated module before `cpanfile`
   can finish, add it to `cpanfile-bootstrap-notest` instead. On the same line,
   record the upstream issue URL, affected Perl/module versions, platform when
   relevant, and a review date:

   ```perl
   requires 'Module::Name'; # https://issue.example/123; Perl 5.43.9; review 2026-09-01
   ```

6. Rebuild the affected version, then the complete matrix. The smoke test is
   still blocking.

Do not duplicate a module across manifests. Do not add a permanent exception
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
  --build-arg PERL_VERSION=5.44.0 \
  -t perl-essentials:5.44.0 .
```

Build and enter the pre-CPAN debug target:

```sh
docker build --target debug-base \
  --build-arg PERL_VERSION=5.44.0 \
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
  --build-arg PERL_VERSION=5.44.0 \
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
scripts/list-cpanfile-modules.pl cpanfile cpanfile-bootstrap-notest cpanfile-notest
scripts/check-manifests.pl cpanfile cpanfile-bootstrap-notest cpanfile-notest
scripts/smoke-test.pl cpanfile cpanfile-bootstrap-notest cpanfile-notest
scripts/module-versions.pl cpanfile cpanfile-bootstrap-notest cpanfile-notest
perl -c test/integration-postgres.pl
test/check-perl-versions.sh public
```

## CI and releases

CI validates all configured Perl versions. The matrix deliberately keeps legacy
versions in addition to the newest stable and development versions so software
can be tested before distribution to older systems.

GitHub workflows use `actions/checkout@v6`, which runs on Node.js 24 and avoids
the deprecated Node.js 20 action runtime. The main GitHub CI matrix validates
both `linux/amd64` and `linux/arm64`; ARM64 jobs run on the native
`ubuntu-24.04-arm` hosted runner and pass the selected platform through
`CI_PLATFORM`.

`perl-versions.conf` records the exact versions and their roles. Check Docker
Hub for newer official threaded tags:

```sh
perl scripts/check-perl-versions.pl
perl scripts/check-perl-versions.pl --check
perl scripts/check-perl-versions.pl --check --drift-profile public
```

The script proposes newer patch releases for configured series and only the
immediately following series, such as 5.45 after 5.44. It also reports drift
between the configuration, Dockerfile, CI files, and README. It never edits
files.

The public workflow selects the `public` drift profile, which checks only files
exported to GitHub.

`test/check-perl-versions.sh` is deterministic: it uses repository fixtures to
test current versions, available updates, a new Perl series, repository drift,
and both drift profiles without accessing the network. GitHub passes `public`
to validate the public snapshot. After that test passes, the workflow runs
`scripts/check-perl-versions.pl --check` against Docker Hub's live official
`perl` tags.

GitHub's `Check Perl versions` workflow declares cron `17 6 * * 1`, requesting
a run every Monday at 06:17 UTC from the default branch. GitHub may delay
scheduled runs during periods of high load. The workflow can also be started
manually.

Ubuntu's system Perl does not include the HTTPS modules used by `HTTP::Tiny`.
The GitHub workflow therefore installs `libio-socket-ssl-perl`, which also
provides the required `Net::SSLeay` dependency, before contacting Docker Hub.
A failure reporting `UPDATE` or `ADD` is an expected maintenance signal: review
the proposed Perl versions, update the configuration and matrices deliberately,
then run the full image validation. A `DRIFT` failure means repository files
disagree and should be corrected. Network or Docker Hub failures should be
retried before changing repository data. Keeping this maintenance check
separate from normal branch builds means a newly published upstream image does
not block unrelated changes.

Release publication is intentionally separate from validation workflows.
Public release notes are recorded in `CHANGELOG.md`.
The private publication tool recreates annotated SemVer release tags on the
corresponding filtered public snapshot. Public and private object IDs differ
because the public repository excludes private files and history.

### Docker Hub image tags

Publishing a GitHub Release starts `.github/workflows/docker-publish.yml`.

The GitHub workflow builds each architecture separately and natively:

- AMD64 uses the explicit stable `ubuntu-24.04` runner;
- ARM64 uses the explicit stable `ubuntu-24.04-arm` runner.

The workflow deliberately avoids `ubuntu-latest`, whose backing image can
change without a repository modification. It also avoids Ubuntu 26.04 while
that runner image is a public preview. Moving to 26.04 should be a deliberate
change after GitHub marks both architectures stable and the complete matrix has
passed.

Each build pushes a canonical architecture digest. A later job downloads the
AMD64 and ARM64 digest artifacts and creates the final multi-architecture
manifest aliases. Publication uses native runners rather than QEMU and receives
only the Docker Hub username and token configured in the protected GitHub
environment. One UTC timestamp in `YYYY-MM-DD_HHmmss` format is shared by all
images in the release.

The publication builds keep CPAN upstream tests enabled and pass explicit
`cpanm` configure and test timeouts (`CPAN_CONFIGURE_TIMEOUT=1200`,
`CPAN_TEST_TIMEOUT=7200` by default). Docker Hub authentication uses the
protected GitHub environment `dockerhub-production`, with
`DOCKERHUB_USERNAME` as an environment variable and `DOCKERHUB_TOKEN` as an
environment secret.

For a release such as `vX.Y.Z`, Perl 5.44.0 receives:

- `5.44.0-YYYY-MM-DD_HHmmss`, identifying the publication run;
- `5.44.0`, the exact-version alias;
- `5.44`, the series alias;
- `vX.Y.Z-5.44.0`, the release-specific alias.

The configured default Perl version also updates `latest`. Codex, built on
Perl 5.44.0 without cache, receives `codex-YYYY-MM-DD_HHmmss`, `codex`, and
`vX.Y.Z-codex`. It never updates `latest`. Rerunning failed jobs for the same
release keeps its shared timestamp when GitHub reuses the workflow run.

Inspect either manifest before use:

```sh
docker buildx imagetools inspect perlessentials/perl-essentials:5.44.0
docker buildx imagetools inspect perlessentials/perl-essentials:codex
```

## Image license audit

Every `final` image generates `/opt/perl-essentials/licenses/inventory.json`,
`SUMMARY.md`, and a `texts/` tree during the same layer that installs CPAN
dependencies. The audit reads the installed Debian package database and its
`/usr/share/doc/*/copyright` files, retains the Perl Artistic and GPL license
documents, and analyzes the CPAN archives saved by `cpanm --save-dists` before
the build cache is removed. Oh My Zsh is recorded with the exact cloned commit
and its bundled MIT license.

The `codex` target extends that existing inventory after installation. It
records the observed Codex CLI and RTK versions and downloads their official
Apache-2.0 license texts. These two entries and texts therefore exist only in
the Codex image.

CPAN metadata is normalized to SPDX identifiers where a direct mapping is
known. Missing or ambiguous declarations are recorded as `NOASSERTION`.
The build and CI print these entries as review warnings but do not reject the
image. CI does reject malformed inventories, missing component entries for the
Codex target, and references to absent license files.

The OCI image label remains `org.opencontainers.image.licenses=MIT` because it
describes the repository-authored image definition and scripts. The generated
audit describes the separately licensed software bundled in each concrete
image.

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
