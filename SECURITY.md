# Security

## Docker Scout audit

Last local audit: 2026-07-23.

Docker Scout CLI: `v1.22.0 (go1.26.3 - darwin/arm64)`. Docker Scout reported
that `v1.23.1` was available during the scan.

The audit covered the canonical published Docker Hub tags for both supported
platforms:

- Tags: `5.26.3`, `5.32.1`, `5.36.3`, `5.38.5`, `5.40.4`, `5.42.2`,
  `5.43.9`, `5.44.0`, and `codex`
- Platforms: `linux/amd64` and `linux/arm64`
- Repository: `perlessentials/perl-essentials`

Aliases such as `5.44`, `latest`, timestamp tags, and release tags were not
scanned separately because they point to the same published manifests.

The scan used:

```sh
docker scout quickview --platform PLATFORM registry://perlessentials/perl-essentials:TAG
docker scout cves --platform PLATFORM --format sarif registry://perlessentials/perl-essentials:TAG
docker scout cves --platform PLATFORM --only-base --format sarif registry://perlessentials/perl-essentials:TAG
docker scout cves --platform PLATFORM --ignore-base --format sarif registry://perlessentials/perl-essentials:TAG
```

When Docker Hub rate limiting interrupted Scout registry pulls, the remaining
scans were resumed by pulling the platform explicitly with Docker and scanning
`local://perlessentials/perl-essentials:TAG`. The locally pulled canonical tags
were removed after scanning. Three unrelated historical local tags remained:
`v0.7.1-5.44.0`, `codex-2026-06-19_172956`, and
`smoke-2026-06-15_170711`.

### Summary

Counts are Docker Scout SARIF rule counts. `Base` is `--only-base`; `Final` is
`--ignore-base`.

| Tag | Platform | All | Base | Final | Final packages |
| --- | --- | ---: | ---: | ---: | --- |
| `5.26.3` | `linux/amd64` | 18 | 18 | 0 | none |
| `5.26.3` | `linux/arm64` | 18 | 18 | 0 | none |
| `5.32.1` | `linux/amd64` | 1001 | 830 | 171 | `vim` |
| `5.32.1` | `linux/arm64` | 1001 | 830 | 171 | `vim` |
| `5.36.3` | `linux/amd64` | 650 | 590 | 60 | `vim` |
| `5.36.3` | `linux/arm64` | 650 | 590 | 60 | `vim` |
| `5.38.5` | `linux/amd64` | 303 | 270 | 33 | `vim` |
| `5.38.5` | `linux/arm64` | 303 | 270 | 33 | `vim` |
| `5.40.4` | `linux/amd64` | 303 | 270 | 33 | `vim` |
| `5.40.4` | `linux/arm64` | 303 | 270 | 33 | `vim` |
| `5.42.2` | `linux/amd64` | 303 | 270 | 33 | `vim` |
| `5.42.2` | `linux/arm64` | 303 | 270 | 33 | `vim` |
| `5.43.9` | `linux/amd64` | 303 | 270 | 33 | `vim` |
| `5.43.9` | `linux/arm64` | 303 | 270 | 33 | `vim` |
| `5.44.0` | `linux/amd64` | 303 | 270 | 33 | `vim` |
| `5.44.0` | `linux/arm64` | 303 | 270 | 33 | `vim` |
| `codex` | `linux/amd64` | 307 | 270 | 37 | `vim`, `gawk` |
| `codex` | `linux/arm64` | 307 | 270 | 37 | `vim`, `gawk` |

The architectures produced identical counts for each tag. No final-layer CVE
reported a fixed package version in Docker Scout.

### Notable findings

- Base-image CVEs dominate the report. For current Perl images, Scout reported
  270 CVEs in the official `perl` base image and 33 CVEs outside the base.
- Image format libraries are inherited from the official base image. For
  `5.44.0/linux/amd64`, Scout reported base CVEs for `imagemagick` (9),
  `openexr` (14), `libheif` (17), and `libde265` (10), all with no fixed
  package version reported by Scout.
- Scout reported 11 CVEs against the base `perl` package for `5.44.0`, including
  one critical entry, all with no fixed package version reported. The final
  images locally load `Socket` version `2.041` for both `perl-essentials:5.44.0`
  and `perl-essentials:codex`, so base-package findings for Perl modules should
  be checked against the runtime module actually loaded by Perl before creating
  an exception.
- The final image adds `vim` findings. Current tags report 33 `vim` CVEs:
  4 high, 12 medium, 6 low, and 11 unspecified. Older `5.32.1` and `5.36.3`
  tags report more `vim` CVEs because they carry older image contents.
- The `codex` target adds 4 `gawk` CVEs, all unspecified severity, in addition
  to the same `vim` findings.

### Risk decision

The current decision is to accept the risk and keep the developer-oriented tools
and image format support.

Removing packages inherited from the official Perl base image is not the right
default response. Packages such as ImageMagick, OpenEXR, HEIF, and de265 support
image manipulation workflows that are useful in a local development container,
and the reported CVEs do not by themselves show a reachable exploit path in the
project's expected usage.

Removing `vim` is also not recommended at this time. The image is intended to be
usable as an interactive development environment, not only as a minimal runtime
artifact. Scout reports no fixed Debian package version for the `vim` findings,
so removing the editor would trade away a useful local workflow for a risk
reduction that is not clearly proportional.

The preferred mitigation is:

- rebuild and republish regularly from the current official Perl base images;
- keep CPAN updates in the final image;
- review Docker Scout after each publication;
- investigate critical or high findings that are reachable from normal use;
- use targeted exceptions only after documenting why a CVE is accepted or not
  affected.

### Docker Scout exceptions

Docker Scout exceptions are appropriate for targeted, documented cases. They
should not be used as a blanket suppression for all base-image CVEs.

Acceptable exception candidates:

- `vim` CVEs in final layers when no fixed package is available and the accepted
  risk is the presence of an interactive editor in a development image;
- `gawk` CVEs in the `codex` target when no fixed package is available and the
  finding remains low practical risk for the container's intended use;
- Perl module CVEs reported against the base Debian `perl` package when the
  final runtime demonstrably loads a corrected CPAN-installed module instead.

Each exception should include the CVE, package, affected image or tag family,
reason, review date, and whether the status is accepted risk or not affected.
Prefer narrow Docker Scout exceptions or VEX statements over organization-wide
suppression.
