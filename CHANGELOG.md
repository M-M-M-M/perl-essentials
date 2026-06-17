# Changelog

All notable public changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed

- GitHub CI now uses `docker/setup-qemu-action@v4` for ARM64 validation.
- GitHub CI now validates Perl and Codex images on both `linux/amd64` and
  `linux/arm64`, matching the Bitbucket platform coverage.
- Bitbucket validation now builds every Perl and Codex image on both
  `linux/amd64` and `linux/arm64` before Docker Hub publication, in bounded
  per-version batches with a custom single-image debug pipeline.
- CPAN test exceptions now include a bootstrap manifest for dependency failures
  that block a tested curated module before the main manifest can complete.

### Fixed

- Codex ARM64 validation now keeps Bubblewrap sandbox testing enabled under
  Bitbucket QEMU by installing `/usr/bin/bwrap` with its setuid fallback and by
  avoiding `no-new-privileges` in the sandbox validation container.
- Bitbucket ARM64 validation steps now extend their step runtime to avoid
  interrupting legitimate CPAN tests under QEMU before Docker Hub publication.
- Bitbucket `linux/arm64` validation for Perl 5.26.3 now preinstalls the
  failing `DateTime::Locale` dependency without upstream tests while keeping
  `DateTime` and the rest of the curated manifest tested.

## [0.4.1] - 2026-06-16

### Fixed

- Docker Hub publication now retries transient Buildx bootstrap failures,
  increases CPAN configure/test timeouts, and publishes Bitbucket images
  sequentially to avoid multi-architecture QEMU timeout failures.

## [0.4.0] - 2026-06-15

### Added

- Every image embeds a generated license inventory and available license texts
  for Debian, Perl, CPAN, and directly downloaded components; the Codex target
  adds Codex CLI and RTK to its own audit.
- Bitbucket release pipelines publish AMD64/ARM64 Perl and Codex manifests to
  Docker Hub with exact, release, rolling, and timestamped tags.
- Docker Hub credentials are maintained from 1Password in a committed
  SOPS/age-encrypted document and decrypted only inside publication jobs.
- The reusable SOPS/age scripts are vendored from `sops-age-op-framework`, so
  Docker Hub secret rotation does not require another repository checkout.

### Changed

- CI validates the embedded license audit and reports upstream components with
  missing machine-readable license metadata as `NOASSERTION`.
- The development Perl image owns `latest`; Codex uses separate `codex` tags
  and continues to resolve Codex CLI and RTK without cache.

## [0.3.0] - 2026-06-15

### Added

- The optional Codex target installs RTK and initializes its Codex integration
  automatically in the repository-local state directory.

### Changed

- Documentation records the observed Codex and RTK versions separately from
  the published Perl image matrix, while CI logs both floating versions.
- Local and CI Codex builds use the single `perl-essentials:codex` flavor,
  replacing the previous internal `codex-ci` tag.
- Perl and Codex CI builds now share `scripts/ci-build.sh`; the `codex` mode
  selects the Codex target and its dedicated validation suite.

### Fixed

- Bitbucket Codex validation now uses a dedicated 7168 MB Docker service and
  retries transient Buildx bootstrap failures before starting the build.
- Codex CI uses an ephemeral Docker volume for `/codex`, so validation works
  with both GitHub's host daemon and Bitbucket's separate Docker-in-Docker
  daemon.
- Default builds, Perl CI, and Docker publication select the Perl-only final
  image instead of accidentally building the optional Codex target.

## [0.2.5] - 2026-06-12

### Fixed

- The deterministic Perl version test now receives the public drift profile in
  GitHub while retaining private repository validation by default.
- The GitHub Perl version workflow installs the TLS modules required by
  `HTTP::Tiny`, and Docker Hub failures now include their underlying reason.

## [0.2.4] - 2026-06-12

### Fixed

- The public Perl version maintenance workflow ignores the intentionally
  private Bitbucket pipeline while private checks continue to require it.

### Documentation

- The Perl version detector, GitHub workflow, and Bitbucket custom pipeline now
  document their distinct maintenance roles and failure signals.

## [0.2.3] - 2026-06-12

### Changed

- GitHub workflows use Checkout v6 and its Node.js 24 runtime.

## [0.2.2] - 2026-06-12

### Fixed

- Codex sandbox validation also disables the outer Docker AppArmor profile that
  blocks Bubblewrap mount propagation on GitHub-hosted runners.

## [0.2.1] - 2026-06-11

### Fixed

- Codex sandbox validation grants Bubblewrap the mount capability required by
  GitHub-hosted Docker runners.

## [0.2.0] - 2026-06-11

### Added

- Optional local Codex CLI target with repository-local, ignored
  authentication and session state.

### Changed

- GitHub Actions and Bitbucket validate the optional Codex target without cache,
  including manual Zsh use and the Bubblewrap sandbox.
- The Codex documentation explains how to run Perl commands in Zsh before
  starting Codex manually.

### Fixed

- CI formatting checks run with the checkout owner's UID and GID so Git accepts
  the read-only repository mount without disabling ownership protection.
- The optional Codex target installs the distribution `bubblewrap` package and
  documents the Docker security options required by its Linux sandbox.
- Tag pipelines validate all supported Perl versions without attempting the
  deferred Docker Hub publication.
- Legacy Debian images derive GNU command aliases from the commands available
  on `PATH` and report precise runtime-tool or default-perltidy-profile
  failures.
- Runtime checks validate the system Perl::Tidy profile from a neutral
  directory, while project-local profiles retain precedence during normal use.

## [0.1.0] - 2026-06-11

### Added

- Multi-version Perl container images with curated tested and no-test CPAN
  manifests.
- CI validation across legacy, stable, and development Perl versions.
- Module inventory, manifest validation, smoke-test, integration-test, and
  Perl-version maintenance tooling.
- Shell configuration for interactive container use.
- MIT licensing and third-party notices.

[Unreleased]: https://github.com/M-M-M-M/perl-essentials/compare/v0.4.1...HEAD
[0.4.1]: https://github.com/M-M-M-M/perl-essentials/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/M-M-M-M/perl-essentials/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/M-M-M-M/perl-essentials/compare/v0.2.5...v0.3.0
[0.2.5]: https://github.com/M-M-M-M/perl-essentials/compare/v0.2.4...v0.2.5
[0.2.4]: https://github.com/M-M-M-M/perl-essentials/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/M-M-M-M/perl-essentials/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/M-M-M-M/perl-essentials/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/M-M-M-M/perl-essentials/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/M-M-M-M/perl-essentials/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/M-M-M-M/perl-essentials/releases/tag/v0.1.0
