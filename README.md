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
3. Temporary, documented exceptions in `cpanfile-notest` are installed without
   their upstream tests.
4. Every curated module, including core modules and exceptions, must pass the
   local load test.

See [DOCUMENTATION.md](DOCUMENTATION.md) for maintenance, exception, and
debugging procedures.

## Build

The default is Perl 5.43.9:

```sh
docker build -t perl-essentials:5.43.9 .
```

Select another official threaded Perl image:

```sh
docker build \
  --build-arg PERL_VERSION=5.42.2 \
  -t perl-essentials:5.42.2 \
  .
```

Supported CI matrix:

| Perl series | Image version | Role |
| --- | --- | --- |
| 5.26 | 5.26.3 | Legacy baseline |
| 5.32 | 5.32.1 | Broad legacy compatibility |
| 5.36 | 5.36.3 | Common LTS distributions |
| 5.38 | 5.38.5 | Established production series |
| 5.40 | 5.40.4 | Maintained stable series |
| 5.42 | 5.42.2 | Latest stable series |
| 5.43 | 5.43.9 | Development compatibility |

The matrix intentionally includes older Perl releases. They are retained to
validate modules intended for distribution to legacy Debian, Ubuntu, RHEL, and
other machines that cannot immediately adopt the latest Perl. All versions,
including the development series, are blocking CI jobs and follow the same
installation and test policy.

## Run scripts and data

Mount the current directory and run a script:

```sh
docker run --rm \
  -v "$PWD":/work \
  perl-essentials:5.43.9 \
  perl /work/script.pl
```

Mount separate script and data directories:

```sh
docker run --rm \
  -v "$PWD/scripts":/work/scripts:ro \
  -v "$PWD/data":/work/data \
  perl-essentials:5.43.9 \
  perl /work/scripts/report.pl /work/data/input.csv
```

Open an interactive shell:

```sh
docker run --rm -it -v "$PWD":/work perl-essentials:5.43.9 zsh -l
```

Zsh and Oh My Zsh are installed in every target. The prompt displays the user,
host, history event, and current directory; aliases `ls`, `l`, `ll`, `d`, and
`c` are configured globally.

## Optional Codex target

Codex CLI is available in a separate development target. GitHub Actions and
Bitbucket build and validate this target with the default Perl version, but it
is not part of the default image or Docker Hub publication. Build without the
cache to retrieve the latest Codex version available from the official
installer:

```sh
docker build --target codex --no-cache -t perl-essentials:codex .
mkdir -p codex-auth
```

Authenticate on the first run with device authorization:

```sh
docker run --rm -it \
  -v "$PWD":/work \
  -v "$PWD/codex-auth":/codex \
  perl-essentials:codex codex login --device-auth
```

On subsequent runs, reuse the same local state directory:

```sh
docker run --rm -it \
  --cap-add SYS_ADMIN \
  --security-opt apparmor=unconfined \
  --security-opt seccomp=unconfined \
  --security-opt no-new-privileges=true \
  -v "$PWD":/work \
  -v "$PWD/codex-auth":/codex \
  perl-essentials:codex
```

To run Perl commands before starting Codex, open Zsh with the same mounts and
security options:

```sh
docker run --rm -it \
  --cap-add SYS_ADMIN \
  --security-opt apparmor=unconfined \
  --security-opt seccomp=unconfined \
  --security-opt no-new-privileges=true \
  -v "$PWD":/work \
  -v "$PWD/codex-auth":/codex \
  perl-essentials:codex zsh -l
```

Then run commands such as `perl -v`, `prove -lr test`, and finally `codex`
inside the container. The shell starts in `/work`, so these commands operate on
the mounted project.

Codex uses the distribution `bubblewrap` package to sandbox commands on Linux.
Docker's default seccomp profile blocks the namespace-related system calls that
`bubblewrap` needs inside a container, and Bubblewrap also needs the `SYS_ADMIN`
capability to create its mount namespace. These options increase the
container's access to Linux kernel system calls and mount operations. Use this
target only with trusted images and projects, do not add `--privileged`, and do
not mount the Docker socket. `apparmor=unconfined` is also required on hosts
whose Docker AppArmor profile blocks mount propagation. The
`no-new-privileges=true` option remains enabled to prevent processes from
gaining additional privileges.

`codex-auth/` is isolated from the host's `~/.codex` and ignored by both Git
and the Docker build context. It can contain sensitive access tokens,
configuration, sessions, history, logs, and caches. Run `codex logout` with
the same mounts before deleting the directory when possible. Deleting the
directory removes only this local copy of the stored state.

See [DOCUMENTATION.md](DOCUMENTATION.md) for validation and cleanup details.

## Perl development tools

The image includes `perltidy`, `perlcritic`, `prove`, `cpanm`, `rg`, and the
GNU-prefixed commands `gcat`, `gfind`, `ggrep`, and `gsed`.

The reference formatting profile is installed as `/etc/perltidyrc`, so it is
used automatically when a mounted project does not provide `.perltidyrc`.
A project-local profile takes precedence.

The exact `perl-agents-md` v1.0.0 `AGENTS.md` and `.perltidyrc` snapshots are
also available under `/opt/perl-essentials`. `AGENTS.md` is a reference there;
Codex only treats it as project guidance after it is placed in the mounted
project hierarchy.

Copy the references into a project without replacing existing files:

```sh
docker run --rm -v "$PWD":/work perl-essentials:5.43.9 sh -c \
  'cp -n /opt/perl-essentials/AGENTS.md /work/AGENTS.md
   cp -n /opt/perl-essentials/.perltidyrc /work/.perltidyrc'
```

## Tests and module versions

Run the quick backward-compatible validation:

```sh
docker run --rm \
  -v "$PWD":/work \
  perl-essentials:5.43.9 \
  perl /work/test.pl
```

Run the smoke test in a built image:

```sh
docker run --rm perl-essentials:5.43.9 \
  /opt/perl-essentials/scripts/smoke-test.pl \
  /opt/perl-essentials/cpanfile \
  /opt/perl-essentials/cpanfile-notest
```

Display the versions captured during the build:

```sh
docker run --rm perl-essentials:5.43.9 \
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

The separate `Check Perl versions` workflow runs every Monday and can also be
started manually. It reports newer official threaded Perl images and drift in
the public version matrix without rebuilding the Docker images. Its
deterministic test runs as `test/check-perl-versions.sh public`; local and
Bitbucket checks omit the argument and validate the complete private repository.
Before the live Docker Hub query, GitHub installs the TLS modules required by
Ubuntu's system Perl.

<!-- MODULE_VERSIONS_START -->
| Module | Version |
| --- | --- |
| `Archive::Zip` | `1.68` |
| `Archive::Zip::MemberRead` | `1.68` |
| `Array::Compare` | `3.0.8` |
| `Cpanel::JSON::XS` | `4.42` |
| `Cwd` | `3.95` |
| `DBD::Pg` | `3.20.2` |
| `DBD::SQLite` | `1.78` |
| `DBI` | `1.648` |
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
| `Imager` | `1.031` |
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
| `Mojolicious::Lite` | `unknown` |
| `Net::LDAP` | `0.68` |
| `Net::SFTP::Foreign` | `1.93` |
| `Perl::Critic` | `1.156` |
| `Perl::Tidy` | `20260204` |
| `Scalar::Util` | `1.70` |
| `Schedule::RateLimiter` | `0.01` |
| `Sort::Key` | `1.33` |
| `Spreadsheet::XLSX` | `0.18` |
| `Test::MockModule` | `0.185.2` |
| `Test::More` | `1.302220` |
| `Text::CSV` | `2.06` |
| `Text::Iconv` | `1.7` |
| `Thread::Queue` | `3.14` |
| `Time::Duration` | `1.21` |
| `Time::HiRes` | `1.9780` |
| `Time::Limit` | `0.003` |
| `URI::Escape` | `5.34` |
| `XML::Hash` | `0.95` |
| `XML::LibXML` | `2.0213` |
| `XML::LibXML::XPathContext` | `2.0213` |
| `threads` | `2.45` |
| `threads::shared` | `1.73` |
| `utf8` | `1.29` |
| `utf8::all` | `0.026` |
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
  perl-essentials:5.43.9 \
  perl /work/test/integration-postgres.pl
```

Public release notes are maintained in [CHANGELOG.md](CHANGELOG.md).

## License

This project is distributed under the [MIT License](LICENSE).
Bundled agent guidance attribution is recorded in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
