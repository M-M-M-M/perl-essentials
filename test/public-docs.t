use strict ;
use warnings ;

use Test::More ;

my $readme        = _read_text('README.md') ;
my $documentation = _read_text('DOCUMENTATION.md') ;
my $dockerhub     = _read_text('DOCKERHUB.md') ;
my $changelog     = _read_text('CHANGELOG.md') ;

for my $document (
  [ 'README.md',        $readme ],
  [ 'DOCUMENTATION.md', $documentation ],
  [ 'DOCKERHUB.md',     $dockerhub ],
  )
{
  my ( $name, $content ) = @{$document} ;
  unlike $content,
    qr/Bitbucket|Docker-in-Docker|validate-one-image|linux\.arm64|SOPS|1Password/,
    "$name contains no private CI provider details" ;
}

unlike $readme,
  qr/--cap-add SYS_ADMIN|apparmor=unconfined|seccomp=unconfined/,
  'README normal usage does not weaken Docker isolation' ;
like $documentation, qr/Advanced Bubblewrap troubleshooting/,
  'detailed documentation keeps an advanced sandbox troubleshooting section' ;
like $documentation, qr/--cap-add SYS_ADMIN.*apparmor=unconfined.*seccomp=unconfined/s,
  'advanced sandbox troubleshooting documents the optional Docker overrides' ;
like $documentation,
  qr/Ubuntu 24\.04.*bwrap-userns-restrict.*apparmor_parser/s,
  'detailed documentation covers the Ubuntu 24.04 AppArmor profile' ;
like $documentation,
  qr/root fallback.*CI.*does not change.*runtime/is,
  'detailed documentation distinguishes the CI fallback from runtime behavior' ;
like $readme, qr/cron `17 6 \* \* 1`.*Monday at 06:17 UTC/s,
  'README explains the weekly GitHub schedule precisely' ;
like $readme, qr{\[SECURITY\.md\]\(SECURITY\.md\)},
  'README links to the Docker Scout security audit' ;
like $readme, qr/`Mojolicious::Lite` \| `9\.48`/,
  'README reports the installed Mojolicious distribution version' ;
like $dockerhub,
  qr{/etc/perltidyrc.*project-local `.perltidyrc`.*-pro=/work/custom\.perltidyrc.*-npro}s,
  'Docker Hub overview explains Perl::Tidy profile precedence and overrides' ;
like $dockerhub,
  qr{--user "\$\(id -u\):\$\(id -g\)".*perltidy -b -bext='/'}s,
  'Docker Hub in-place formatting example preserves host ownership' ;
like $dockerhub, qr/based on the Perl 5\.45\.1 image/,
  'Docker Hub identifies the exact Codex Perl image' ;
unlike $dockerhub, qr/based on the latest development Perl target/,
  'Docker Hub does not describe the Codex base as an unstable latest target' ;
unlike $dockerhub, qr/based on the Perl 5\.43 development target/,
  'Docker Hub does not identify only the Codex Perl development series' ;

my $latest_perl_version  = _latest_perl_version() ;
my $latest_release_date  = _latest_release_date($changelog) ;
my $documented_codex_row = qr/\| `codex` \| \Q$latest_perl_version\E \|/ ;

for my $document ( [ 'README.md', $readme ], [ 'DOCKERHUB.md', $dockerhub ], )
{
  my ( $name, $content ) = @{$document} ;
  like $content, $documented_codex_row,
    "$name documents Codex on the latest Perl target" ;
  cmp_ok _module_capture_date($content), 'ge', $latest_release_date,
    "$name module inventory was captured for the current release" ;
}

like _read_text('.public-files'), qr/^DOCKERHUB\.md$/m,
  'public snapshot includes the Docker Hub overview source' ;
is _section( $dockerhub, 'PERL_TARGETS' ),
  _section( $readme, 'PERL_TARGETS' ),
  'Docker Hub and README Perl target tables match' ;
is _section( $dockerhub, 'CODEX_TARGET' ),
  _section( $readme, 'CODEX_TARGET' ),
  'Docker Hub and README Codex target tables match' ;
is _section( $dockerhub, 'MODULE_VERSIONS' ),
  _section( $readme, 'MODULE_VERSIONS' ),
  'Docker Hub and README module version tables match' ;

done_testing ;

sub _section {
  my ( $content, $name ) = @_ ;
  my ($section)
    = $content
    =~ /<!-- \Q${name}\E_START -->\n(.*?)<!-- \Q${name}\E_END -->/s ;
  return defined $section ? $section : q{} ;
}

sub _latest_perl_version {
  my $content = _read_text('perl-versions.conf') ;
  my @versions ;
  for my $line ( split /\n/, $content )
  {
    next if $line =~ /\A\s*(?:#|\z)/ ;
    my ($version) = split /\|/, $line ;
    push @versions, $version ;
  }

  return $versions[-1] ;
}

sub _latest_release_date {
  my ($content) = @_ ;
  my ($date)    = $content =~ /^## \[\d+\.\d+\.\d+\] - (\d{4}-\d{2}-\d{2})/m ;
  return $date ;
}

sub _module_capture_date {
  my ($content) = @_ ;
  my ($date)    = $content =~ /Versions captured on (\d{4}-\d{2}-\d{2}) / ;
  return $date ;
}

sub _read_text {
  my ($path) = @_ ;
  open my $fh, '<:encoding(UTF-8)', $path
    or die "Cannot read '$path': $!" ;
  local $/ ;
  my $content = <$fh> ;
  close $fh or die "Cannot close '$path': $!" ;
  return $content ;
}
