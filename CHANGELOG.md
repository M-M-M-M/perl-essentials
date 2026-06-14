# Changelog

All notable public changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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

- Codex CI permits RTK initialization in its temporary `/codex` bind mount
  when the Docker daemon remaps container users, and creates that state with
  the runner UID so subsequent assertions can read it.
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

[Unreleased]: https://github.com/M-M-M-M/perl-essentials/compare/v0.2.5...HEAD
[0.2.5]: https://github.com/M-M-M-M/perl-essentials/compare/v0.2.4...v0.2.5
[0.2.4]: https://github.com/M-M-M-M/perl-essentials/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/M-M-M-M/perl-essentials/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/M-M-M-M/perl-essentials/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/M-M-M-M/perl-essentials/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/M-M-M-M/perl-essentials/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/M-M-M-M/perl-essentials/releases/tag/v0.1.0
