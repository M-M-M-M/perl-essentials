# perl-essentials

`perl-essentials` is a Docker image with threaded Perl and a curated set of
CPAN modules for scripting, automation, data processing, databases, profiling,
testing, and web clients.

The image deliberately favors current modules over byte-for-byte reproducible
builds:

1. Modules already present in the official Perl image are updated with
   `cpan-outdated`.
2. Every required CPAN distribution installed from `cpanfile` runs its test
   suite. Already-current core modules are not downgraded.
3. Temporary, documented exceptions in `cpanfile-bootstrap-notest` and
   `cpanfile-notest` are installed without their upstream tests.
4. Every curated module, including core modules and exceptions, must pass the
   local load test.

See [DOCUMENTATION.md](DOCUMENTATION.md) for maintenance, exception, and
debugging procedures.

## Build

The default is Perl 5.44.0:

```sh
docker build -t perl-essentials:5.44.0 .
```

Select another official threaded Perl image:

```sh
docker build \
  --build-arg PERL_VERSION=5.43.9 \
  -t perl-essentials:5.43.9 \
  .
```

Supported CI matrix:

<!-- PERL_TARGETS_START -->
| Perl series | Image version | Role |
| --- | --- | --- |
| 5.26 | 5.26.3 | Legacy baseline |
| 5.32 | 5.32.1 | Broad legacy compatibility |
| 5.36 | 5.36.3 | Common LTS distributions |
| 5.38 | 5.38.5 | Established production series |
| 5.40 | 5.40.4 | Maintained stable series |
| 5.42 | 5.42.2 | Previous stable series |
| 5.43 | 5.43.9 | Development compatibility |
| 5.44 | 5.44.0 | Latest stable series |
<!-- PERL_TARGETS_END -->

Published GitHub Releases create multi-architecture images on Docker Hub:

```sh
docker pull perlessentials/perl-essentials:5.44.0
docker pull perlessentials/perl-essentials:5.44
docker pull perlessentials/perl-essentials:latest
docker pull perlessentials/perl-essentials:vX.Y.Z-5.44.0
docker pull perlessentials/perl-essentials:5.44.0-YYYY-MM-DD_HHmmss
```

Exact-version, series, release, and `latest` tags are mutable aliases.
Timestamped tags identify one publication run. `latest` follows the configured
default Perl release, currently 5.44.0.
Replace `vX.Y.Z` and `YYYY-MM-DD_HHmmss` with tags from the published GitHub
Release or Docker Hub tag list.

Release publication keeps the same CPAN test policy as validation. GitHub
Actions validates `linux/amd64` and `linux/arm64` images on native hosted
runners before a release is published.

Publishing a GitHub Release starts the Docker Hub workflow. GitHub builds each
architecture natively on explicit stable runners (`ubuntu-24.04` and
`ubuntu-24.04-arm`), pushes architecture digests, and then assembles the final
multi-architecture aliases. Publication does not use QEMU. The moving
`ubuntu-latest` label is avoided for releases, and Ubuntu 26.04 is not selected
while its GitHub runner image remains a preview.

The matrix intentionally includes older Perl releases. They are retained to
validate modules intended for distribution to legacy Debian, Ubuntu, RHEL, and
other machines that cannot immediately adopt the latest Perl. All versions,
including the development series, are blocking CI jobs and follow the same
installation and test policy.

The optional development target is validated separately:

<!-- CODEX_TARGET_START -->
| Target | Perl base | Codex CLI | RTK | Publication |
| --- | --- | --- | --- | --- |
| `codex` | 5.44.0 | Latest at no-cache build; 0.145.0 observed 2026-07-23 | Latest at no-cache build; 0.43.0 observed 2026-07-23 | `codex`, release, and timestamp tags |
<!-- CODEX_TARGET_END -->

These Codex and RTK versions are observations, not pins. CI prints both
versions on every build.

Published Perl and Codex images run by default as the non-root `perl` user
with UID/GID `1000:1000`. For writable host bind mounts, pass
`--user "$(id -u):$(id -g)"` to preserve host ownership. Use `--user root`
only for an explicit administrative operation. The `debug-base` and `debug`
targets remain root for package-installation diagnostics.

Bind mounts preserve numeric host ownership. A macOS file owned by
UID/GID `502:80` can therefore appear as `502:dialout` inside the Linux
container while remaining owned by the correct host user and group. This is
expected and does not require `chown`. The global Zsh configuration applies to
root, `perl`, and host UID overrides; a minimal personal `.zshrc` prevents the
Zsh new-user assistant without replacing custom shell settings.

## Run scripts and data

Mount the current directory and run a script:

```sh
docker run --rm --user "$(id -u):$(id -g)" \
  -v "$PWD":/work \
  perl-essentials:5.44.0 \
  perl /work/script.pl
```

Mount separate script and data directories:

```sh
docker run --rm --user "$(id -u):$(id -g)" \
  -v "$PWD/scripts":/work/scripts:ro \
  -v "$PWD/data":/work/data \
  perl-essentials:5.44.0 \
  perl /work/scripts/report.pl /work/data/input.csv
```

Open an interactive shell:

```sh
docker run --rm -it --user "$(id -u):$(id -g)" \
  -v "$PWD":/work perl-essentials:5.44.0 zsh -l
```

Zsh and Oh My Zsh are installed in every target. The prompt displays the user,
host, history event, and current directory; aliases `ls`, `l`, `ll`, `d`, and
`c` are configured globally.

## Optional Codex target

Codex CLI and RTK are available in a separate development target. GitHub
Actions validates this target with Perl 5.44.0. GitHub Release
publication also publishes it separately as `codex`,
`vX.Y.Z-codex`, and `codex-YYYY-MM-DD_HHmmss`. Unqualified builds, Perl tags,
and `latest` select the Perl-only `final` stage; RTK is installed only by the
explicit `codex` target.
Build without the cache to retrieve the latest versions available from their
official installers:

```sh
PERL_VERSION=5.44.0 scripts/ci-build.sh codex
mkdir -p codex-auth
```

The script builds, tags, and validates the single local Codex flavor as
`perl-essentials:codex`. It replaces any older image under that tag, reports
each build phase, and retries transient Buildx bootstrap failures.

Pull the published Codex flavor with:

```sh
docker pull perlessentials/perl-essentials:codex
```

Codex publication always builds without cache. A timestamp identifies the
publication run, but Codex CLI and RTK still resolve to the latest versions
available from their official installers during that run.

CI validates state with an ephemeral Docker volume that never contains login
credentials. Interactive use persists credentials and configuration in the
repository-local `codex-auth/` directory.

Authenticate on the first run with device authorization:

```sh
docker run --rm -it --user "$(id -u):$(id -g)" \
  -v "$PWD":/work \
  -v "$PWD/codex-auth":/codex \
  perl-essentials:codex codex login --device-auth
```

On subsequent runs, reuse the same local state directory:

```sh
docker run --rm -it --user "$(id -u):$(id -g)" \
  -v "$PWD":/work \
  -v "$PWD/codex-auth":/codex \
  perl-essentials:codex
```

To run Perl commands before starting Codex, open Zsh with the same mounts:

```sh
docker run --rm -it --user "$(id -u):$(id -g)" \
  -v "$PWD":/work \
  -v "$PWD/codex-auth":/codex \
  perl-essentials:codex zsh -l
```

Then run commands such as `perl -v`, `prove -lr test`, and finally `codex`
inside the container. The shell starts in `/work`, so these commands operate on
the mounted project.

The container entrypoint runs `rtk init -g --codex` automatically and
idempotently before every command. It creates the RTK global `AGENTS.md` and
`RTK.md` integration files in `codex-auth/`; RTK telemetry is disabled by
default. The same directory therefore stores RTK configuration alongside the
Codex authentication and session state.

Codex uses the distribution `bubblewrap` package for its Linux command
sandbox. Normal use should keep Docker's default security profile. If Codex
reports a Bubblewrap namespace or mount error, consult the advanced
troubleshooting section in [DOCUMENTATION.md](DOCUMENTATION.md) before
weakening container isolation. Ubuntu 24.04 hosts may require the documented
Bubblewrap AppArmor profile for non-root sandboxing.

`codex-auth/` is isolated from the host's `~/.codex` and ignored by both Git
and the Docker build context. It can contain sensitive access tokens,
configuration, sessions, history, logs, and caches. Run `codex logout` with
the same mounts before deleting the directory when possible. Deleting the
directory removes only this local copy of the stored state.

See [DOCUMENTATION.md](DOCUMENTATION.md) for validation and cleanup details.

## Perl development tools

The image includes `perltidy`, `perlcritic`, `prove`, `cpanm`, `rg`,
`parallel`, `hyperfine`, and the GNU-prefixed commands `gcat`, `gfind`,
`ggrep`, and `gsed`.

The reference formatting profile is installed as `/etc/perltidyrc`, so it is
used automatically when a mounted project does not provide `.perltidyrc`.
A project-local profile takes precedence. Pass
`-pro=/work/custom.perltidyrc` to select another profile explicitly, or
`-npro` to ignore all profiles.

Preview formatting without modifying the mounted file:

```sh
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD":/work \
  perlessentials/perl-essentials:5.42 \
  perltidy -st -se /work/path/to/script.pl
```

Format in place without creating a backup, using the host user to preserve
file ownership:

```sh
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD":/work \
  perlessentials/perl-essentials:5.42 \
  perltidy -b -bext='/' /work/path/to/script.pl
```

The exact `perl-agents-md` v1.0.0 `AGENTS.md` and `.perltidyrc` snapshots are
also available under `/opt/perl-essentials`. `AGENTS.md` is a reference there;
Codex only treats it as project guidance after it is placed in the mounted
project hierarchy.

Copy the references into a project without replacing existing files:

```sh
docker run --rm --user "$(id -u):$(id -g)" \
  -v "$PWD":/work perl-essentials:5.44.0 sh -c \
  'cp -n /opt/perl-essentials/AGENTS.md /work/AGENTS.md
   cp -n /opt/perl-essentials/.perltidyrc /work/.perltidyrc'
```

## Tests and module versions

Run the quick backward-compatible validation:

```sh
docker run --rm --user "$(id -u):$(id -g)" \
  -v "$PWD":/work \
  perl-essentials:5.44.0 \
  perl /work/test.pl
```

Run the smoke test in a built image:

```sh
docker run --rm perl-essentials:5.44.0 \
  /opt/perl-essentials/scripts/smoke-test.pl \
  /opt/perl-essentials/cpanfile \
  /opt/perl-essentials/cpanfile-bootstrap-notest \
  /opt/perl-essentials/cpanfile-notest
```

Display the versions captured during the build:

```sh
docker run --rm perl-essentials:5.44.0 \
  cat /opt/perl-essentials/module-versions.txt
```

Regenerate the following table from the default image:

```sh
scripts/update-readme-module-versions.sh
```

Check repository Perl formatting without modifying files:

```sh
test/check-perl-format.sh
```

CI runs this check in the image with the checkout owner's UID and GID so Git
can inspect the read-only `/work` mount without weakening its ownership checks.
GitHub workflows use `actions/checkout@v6`, which runs on Node.js 24.

The separate `Check Perl versions` workflow uses cron `17 6 * * 1`, which
requests a run every Monday at 06:17 UTC from the default branch. GitHub may
delay scheduled jobs during periods of high load. The workflow can also be
started manually. It reports newer official threaded Perl images and drift in
the public version matrix without rebuilding Docker images. Its deterministic
test runs as `test/check-perl-versions.sh public`; before the live Docker Hub
query, GitHub installs the TLS modules required by Ubuntu's system Perl.

<!-- MODULE_VERSIONS_START -->
Versions captured on 2026-07-23 06:33:22 (UTC).

This inventory was captured from the default image at the
timestamp above. Module versions may differ between publication runs. For an
exact image, see `/opt/perl-essentials/module-versions.txt`.

| Module | Version |
| --- | --- |
| `Archive::Zip` | `1.68` |
| `Archive::Zip::MemberRead` | `1.68` |
| `Array::Compare` | `3.0.8` |
| `Cpanel::JSON::XS` | `4.43` |
| `Cwd` | `3.95` |
| `DBD::Pg` | `3.20.2` |
| `DBD::SQLite` | `1.78` |
| `DBI` | `1.651` |
| `Data::Dumper` | `2.192` |
| `Data::Peek` | `0.54` |
| `Date::Calc` | `6.4` |
| `DateTime` | `1.66` |
| `DateTime::Format::Excel` | `0.31` |
| `DateTime::Format::ISO8601` | `0.19` |
| `Devel::NYTProf` | `6.15` |
| `Digest::SHA` | `6.04` |
| `Encode` | `3.24` |
| `Excel::Writer::XLSX` | `1.15` |
| `Excel::Writer::XLSX::Utility` | `1.15` |
| `File::Copy` | `2.43` |
| `File::Path` | `2.18` |
| `File::Spec` | `3.95` |
| `File::Temp` | `0.2312` |
| `File::Which` | `1.27` |
| `Getopt::Long` | `2.58` |
| `HTTP::Cookies` | `6.11` |
| `HTTP::Request::Common` | `7.02` |
| `I18N::Langinfo` | `0.24` |
| `IO::Pty` | `1.31` |
| `Imager` | `1.033` |
| `JSON` | `4.11` |
| `JSON::Lines` | `1.11` |
| `JSON::MaybeXS` | `1.004008` |
| `JSON::PP` | `4.18` |
| `JSON::XS` | `4.04` |
| `LWP::UserAgent` | `6.83` |
| `List::MoreUtils` | `0.430` |
| `List::Util` | `1.70` |
| `MIME::Base64` | `3.16_01` |
| `MIME::Lite` | `3.038` |
| `MIME::Parser` | `5.517` |
| `Math::Units` | `1.3` |
| `Mojolicious::Lite` | `9.48` |
| `Net::LDAP` | `0.68` |
| `Net::SFTP::Foreign` | `1.93` |
| `Perl::Critic` | `1.156` |
| `Perl::Tidy` | `20260705` |
| `Scalar::Util` | `1.70` |
| `Schedule::RateLimiter` | `0.01` |
| `Sort::Key` | `1.33` |
| `Spreadsheet::XLSX` | `0.18` |
| `Test::MockModule` | `0.185.3` |
| `Test::More` | `1.302222` |
| `Text::CSV` | `2.06` |
| `Text::Iconv` | `1.7` |
| `Thread::Queue` | `3.14` |
| `Time::Duration` | `1.21` |
| `Time::HiRes` | `1.9780` |
| `Time::Limit` | `0.003` |
| `URI::Escape` | `5.35` |
| `XML::Hash` | `0.95` |
| `XML::LibXML` | `2.0213` |
| `XML::LibXML::XPathContext` | `2.0213` |
| `threads` | `2.45` |
| `threads::shared` | `1.73` |
| `utf8` | `1.29` |
| `utf8::all` | `0.026` |
| `DateTime::Locale` | `1.45` |
| `REST::Client` | `281` |
| `XML::XML2JSON` | `0.06` |
<!-- MODULE_VERSIONS_END -->

The PostgreSQL integration test is optional:

```sh
docker run --rm \
  -e TEST_PG_DSN='dbi:Pg:dbname=postgres;host=host.docker.internal;port=5432' \
  -e TEST_PG_USER='postgres' \
  -e TEST_PG_PASSWORD='secret' \
  -v "$PWD":/work:ro \
  perl-essentials:5.44.0 \
  perl /work/test/integration-postgres.pl
```

Public release notes are maintained in [CHANGELOG.md](CHANGELOG.md).
Public Git tags identify the filtered snapshot commits corresponding to private
annotated SemVer release tags; their Git object IDs differ because private files
and private history are not exported.

## License

This project is distributed under the [MIT License](LICENSE).
Bundled agent guidance attribution is recorded in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

Each built image also contains a generated license audit under
`/opt/perl-essentials/licenses`. `inventory.json` is the machine-readable
component inventory, `SUMMARY.md` is the readable index, and `texts/` contains
the license or copyright files available during the build. The inventory
covers installed Debian packages, Perl, CPAN distributions captured during
installation, and directly downloaded components. The optional Codex image
adds Codex CLI and RTK to its own inventory; they are absent from Perl-only
images.

`NOASSERTION` means an upstream package did not provide usable
machine-readable license metadata. CI reports the count without failing the
build, while still requiring every referenced license file to exist. The OCI
`org.opencontainers.image.licenses=MIT` label describes this repository's own
code, not every bundled component.
