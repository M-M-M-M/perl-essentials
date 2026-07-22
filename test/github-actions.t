use strict ;
use warnings ;

use Test::More ;

my @workflows = qw(
  .github/workflows/ci.yml
  .github/workflows/docker-publish.yml
  .github/workflows/perl-versions.yml
) ;

for my $path (@workflows) {
  my $workflow = _read_text($path) ;

  like $workflow, qr/actions\/checkout\@v6/,
    "$path uses Checkout v6" ;
  unlike $workflow, qr/actions\/checkout\@v4/,
    "$path does not use Checkout v4" ;
}

my $perl_versions = _read_text('.github/workflows/perl-versions.yml') ;
my $ci            = _read_text('.github/workflows/ci.yml') ;
my $publication   = _read_text('.github/workflows/docker-publish.yml') ;

like $ci, qr/timeout-minutes:\s+360/,
  'GitHub image validation has an explicit timeout' ;
like $ci, qr/perl-version:.*5\.26\.3.*5\.44\.0/s,
  'GitHub image validation covers all configured Perl versions' ;
like $ci, qr/platform:.*linux\/amd64.*linux\/arm64/s,
  'GitHub image validation covers both Docker platforms' ;
like $ci, qr/platform:\s+linux\/amd64\s+runner:\s+ubuntu-latest/s,
  'GitHub image validation runs AMD64 jobs on the standard Ubuntu runner' ;
like $ci, qr/platform:\s+linux\/arm64\s+runner:\s+ubuntu-24\.04-arm/s,
  'GitHub image validation runs ARM64 jobs on a native ARM64 runner' ;
like $ci, qr/runs-on:\s*\$\{\{\s*matrix\.runner\s*\}\}/,
  'GitHub image validation selects the runner from the matrix' ;
like $ci, qr/CI_PLATFORM:\s*\$\{\{\s*matrix\.platform\s*\}\}/,
  'GitHub image validation passes the selected Docker platform' ;
unlike $ci, qr/docker\/setup-qemu-action/,
  'GitHub image validation does not install QEMU on native ARM64 runners' ;
like $ci, qr/PERL_VERSION:\s*5\.44\.0.*CI_PLATFORM:\s*\$\{\{\s*matrix\.platform\s*\}\}.*scripts\/ci-build\.sh codex/s,
  'GitHub Codex validation covers both Docker platforms' ;
unlike $ci, qr/ci-build-codex/,
  'GitHub image validation uses only the unified build script' ;

like $perl_versions, qr{run: test/check-perl-versions\.sh public},
  'Perl version workflow tests the public drift profile' ;
like $perl_versions,
  qr{name: Install Perl HTTPS support.*libio-socket-ssl-perl}s,
  'Perl version workflow installs HTTPS support for the system Perl' ;
like $perl_versions,
  qr{scripts/check-perl-versions\.pl --check --drift-profile public},
  'Perl version workflow uses the public drift profile' ;

like $publication, qr/release:\s+types:\s+\[published\]/,
  'Docker publication starts only from a published GitHub release' ;
unlike $publication, qr/^\s+(?:workflow_dispatch|push):/m,
  'Docker publication has no arbitrary manual or tag-push trigger' ;
like $publication, qr/environment:\s+dockerhub-production/,
  'Docker publication uses the protected production environment' ;
like $publication, qr/cancel-in-progress:\s+false/,
  'Docker publication never cancels an in-progress release' ;
like $publication, qr/permissions:\s+contents:\s+read/s,
  'Docker publication uses read-only repository permissions' ;
like $publication, qr/runner:\s+ubuntu-24\.04\b/,
  'Docker publication uses explicit stable AMD64 runners' ;
like $publication, qr/runner:\s+ubuntu-24\.04-arm\b/,
  'Docker publication uses explicit stable ARM64 runners' ;
unlike $publication, qr/ubuntu-latest|ubuntu-26\.04/,
  'Docker publication avoids moving or preview runner labels' ;
like $publication, qr/docker\/login-action\@v4/,
  'Docker publication uses Docker Login v4' ;
like $publication, qr/docker\/setup-buildx-action\@v4/,
  'Docker publication uses Docker Buildx v4' ;
like $publication, qr/actions\/upload-artifact\@v7/,
  'Docker publication uploads architecture digests with Node 24 support' ;
like $publication, qr/actions\/download-artifact\@v8/,
  'Docker publication downloads architecture digests with Node 24 support' ;
like $publication, qr/vars\.DOCKERHUB_USERNAME/,
  'Docker publication reads the Docker Hub username from an environment variable' ;
like $publication, qr/secrets\.DOCKERHUB_TOKEN/,
  'Docker publication reads the Docker Hub PAT from an environment secret' ;
unlike $publication, qr/SOPS|AGE|1Password|setup-qemu/,
  'Docker publication does not expose private secret tooling or QEMU' ;
like $publication, qr/scripts\/publish\.sh build/,
  'Docker publication builds architecture-specific digests through the public script' ;
like $publication, qr/scripts\/publish\.sh manifest/,
  'Docker publication assembles final manifests through the public script' ;

done_testing ;

sub _read_text {
  my ($path) = @_ ;
  open my $fh, '<:encoding(UTF-8)', $path
    or die "Cannot read '$path': $!" ;
  local $/ ;
  my $content = <$fh> ;
  close $fh or die "Cannot close '$path': $!" ;
  return $content ;
}
