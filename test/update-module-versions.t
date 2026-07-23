use strict ;
use warnings ;

use Cwd        qw(abs_path) ;
use File::Path qw(make_path) ;
use File::Spec ;
use File::Temp qw(tempdir) ;
use Test::More ;

my $root   = abs_path('.') ;
my $script = File::Spec->catfile(
  $root, 'scripts', 'update-readme-module-versions.sh'
) ;
my $tmp       = tempdir( CLEANUP => 1 ) ;
my $bin       = File::Spec->catdir( $tmp, 'bin' ) ;
my $readme    = File::Spec->catfile( $tmp, 'README.md' ) ;
my $dockerhub = File::Spec->catfile( $tmp, 'DOCKERHUB.md' ) ;
make_path($bin) ;

ok -x $script, 'module table update script is executable' ;

_write_text(
  File::Spec->catfile( $bin, 'docker' ),
  <<'SH',
#!/bin/sh
case "$*" in
*" codex --version")
  printf '%s\n' 'codex-cli 9.87.0'
  exit 0
  ;;
*" rtk --version")
  printf '%s\n' 'rtk 6.54.0'
  exit 0
  ;;
esac
printf '%s\n' '| Module | Version |'
printf '%s\n' '| --- | --- |'
printf '%s\n' '| `Example` | `4.20` |'
SH
) ;
chmod 0755, File::Spec->catfile( $bin, 'docker' )
  or die "Cannot make fake Docker executable: $!" ;

for my $path ( $readme, $dockerhub ) {
  _write_text(
    $path,
    <<'MARKDOWN',
Before
<!-- CODEX_TARGET_START -->
old codex
<!-- CODEX_TARGET_END -->
<!-- MODULE_VERSIONS_START -->
old
<!-- MODULE_VERSIONS_END -->
After
MARKDOWN
  ) ;
}

my ( $status, $output ) = _run_with_env(
  {
    DOCUMENT_FILES            => "$readme:$dockerhub",
    MODULE_VERSIONS_TIMESTAMP => '2026-06-19 12:34:56',
    PATH                      => "$bin:$ENV{PATH}",
  },
  '/bin/sh',
  $script,
) ;

is $status, 0, 'module table update succeeds for both documents'
  or diag $output ;
for my $path ( $readme, $dockerhub ) {
  my $content = _read_text($path) ;
  like $content,
    qr/Versions captured on 2026-06-19 12:34:56 \(UTC\)\./,
    "$path receives the module version capture date" ;
  like $content,
    qr{This inventory was captured from the default image.*Module versions may differ between publication runs.*`/opt/perl-essentials/module-versions\.txt`}s,
    "$path explains the inventory scope and exact-image source" ;
  like $content, qr/\| `Example` \| `4\.20` \|/,
    "$path receives the generated module table" ;
  like $content,
qr/\| `codex` \| 5\.44\.0 \| Latest at no-cache build; 9\.87\.0 observed 2026-06-19 12:34:56 \| Latest at no-cache build; 6\.54\.0 observed 2026-06-19 12:34:56 \| `codex`, release, and timestamp tags \|/,
    "$path receives the generated Codex target table" ;
}

done_testing ;

sub _run_with_env {
  my ( $env, @command ) = @_ ;
  my $pid = open my $fh, '-|' ;
  die "Cannot fork: $!" if !defined $pid ;

  if ( $pid == 0 ) {
    @ENV{ keys %{$env} } = values %{$env} ;
    open STDERR, '>&', STDOUT
      or die "Cannot redirect STDERR: $!" ;
    exec @command or die "Cannot execute '@command': $!" ;
  }

  local $/ ;
  my $output = <$fh> // q{} ;
  close $fh ;
  return ( $? >> 8, $output ) ;
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

sub _write_text {
  my ( $path, $content ) = @_ ;
  open my $fh, '>:encoding(UTF-8)', $path
    or die "Cannot write '$path': $!" ;
  print {$fh} $content or die "Cannot write '$path': $!" ;
  close $fh            or die "Cannot close '$path': $!" ;
  return ;
}
