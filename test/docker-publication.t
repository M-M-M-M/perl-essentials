use strict ;
use warnings ;

use File::Path qw(make_path) ;
use File::Spec ;
use File::Temp qw(tempdir) ;
use Test::More ;

my $publish = 'scripts/publish.sh' ;

ok -x $publish, 'Docker publication script is executable' ;

my $tmp = tempdir( CLEANUP => 1 ) ;
my $bin = File::Spec->catdir( $tmp, 'bin' ) ;
my $log = File::Spec->catfile( $tmp, 'docker.log' ) ;
make_path($bin) ;

my $docker = File::Spec->catfile( $bin, 'docker' ) ;
_write_text(
  $docker,
  <<'SH',
#!/bin/sh
set -eu

printf '%s\n' "$*" >> "$DOCKER_TEST_LOG"

metadata=
previous=
for argument in "$@"; do
    if [ "$previous" = "--metadata-file" ]; then
        metadata="$argument"
        break
    fi
    previous="$argument"
done

if [ -n "$metadata" ]; then
    printf '{"containerimage.digest":"sha256:%064d"}\n' 1 > "$metadata"
fi
SH
) ;
chmod 0755, $docker or die "Cannot make fake Docker executable: $!" ;

my %base_env = (
  DOCKERHUB_USERNAME => 'perlessentials',
  DOCKER_TEST_LOG    => $log,
  PATH               => "$bin:$ENV{PATH}",
  PERL_VERSION       => '5.42.2',
  PUBLISH_TIMESTAMP  => '2026-06-19_142233',
  RELEASE_TAG        => 'v0.5.1',
) ;

my $amd64_digest = File::Spec->catfile( $tmp, 'digests', 'amd64' ) ;
my ( $status, $output )
  = _run_with_env( \%base_env, $publish, 'build', 'perl',
  'linux/amd64', $amd64_digest ) ;
is $status, 0, 'AMD64 Perl digest build succeeds' or diag $output ;
is _read_text($amd64_digest), "sha256:" . ( "0" x 63 ) . "1\n",
  'digest build records the pushed canonical digest' ;

my $build_log = _read_text($log) ;
like $build_log, qr/buildx build/,
  'digest build uses Docker Buildx' ;
like $build_log, qr/--platform linux\/amd64/,
  'digest build targets one selected architecture' ;
unlike $build_log, qr/linux\/amd64,linux\/arm64/,
  'digest build does not emulate another architecture' ;
like $build_log, qr/--target final/,
  'Perl digest build selects the final target' ;
like $build_log, qr/push-by-digest=true/,
  'digest build pushes a canonical image without final aliases' ;
like $build_log, qr/--build-arg CPAN_CONFIGURE_TIMEOUT=1200/,
  'digest build keeps the extended configure timeout' ;
like $build_log, qr/--build-arg CPAN_TEST_TIMEOUT=7200/,
  'digest build keeps the extended test timeout' ;
unlike $build_log, qr/setup-qemu|binfmt|--privileged/,
  'digest build does not install QEMU or require privileged containers' ;
unlike $build_log, qr/--no-cache/,
  'Perl digest build remains cacheable' ;

unlink $log or die "Cannot reset fake Docker log: $!" ;
my $arm64_digest = File::Spec->catfile( $tmp, 'digests', 'arm64' ) ;
( $status, $output )
  = _run_with_env( \%base_env, $publish, 'build', 'codex',
  'linux/arm64', $arm64_digest ) ;
is $status, 0, 'ARM64 Codex digest build succeeds' or diag $output ;

my $codex_build_log = _read_text($log) ;
like $codex_build_log, qr/--platform linux\/arm64/,
  'Codex digest build targets native ARM64' ;
like $codex_build_log, qr/--target codex/,
  'Codex digest build selects the Codex target' ;
like $codex_build_log, qr/--no-cache/,
  'Codex digest build resolves current Codex and RTK versions' ;

unlink $log or die "Cannot reset fake Docker log: $!" ;
( $status, $output )
  = _run_with_env( \%base_env, $publish, 'manifest', 'perl',
  $amd64_digest, $arm64_digest ) ;
is $status, 0, 'Perl manifest publication succeeds' or diag $output ;

my $perl_log = _read_text($log) ;
like $perl_log, qr/buildx imagetools create/,
  'manifest publication uses Docker Buildx imagetools' ;
like $perl_log, qr/--tag perlessentials\/perl-essentials:5\.42\.2-2026-06-19_142233/,
  'Perl manifest creates an immutable timestamp tag' ;
like $perl_log, qr/--tag perlessentials\/perl-essentials:5\.42\.2(?:\s|$)/,
  'Perl manifest creates an exact version alias' ;
like $perl_log, qr/--tag perlessentials\/perl-essentials:5\.42(?:\s|$)/,
  'Perl manifest creates a series alias' ;
like $perl_log, qr/--tag perlessentials\/perl-essentials:v0\.5\.1-5\.42\.2/,
  'Perl manifest creates a release-specific alias' ;
unlike $perl_log, qr/perl-essentials:latest/,
  'stable Perl does not update latest' ;
like $perl_log, qr/perl-essentials\@sha256:/,
  'manifest publication combines canonical architecture digests' ;
like $perl_log, qr/buildx imagetools inspect.*5\.42\.2/,
  'manifest publication verifies the exact-version alias' ;

unlink $log or die "Cannot reset fake Docker log: $!" ;
my %development_env = ( %base_env, PERL_VERSION => '5.43.9' ) ;
( $status, $output )
  = _run_with_env( \%development_env, $publish, 'manifest', 'perl',
  $amd64_digest, $arm64_digest ) ;
is $status, 0, 'development Perl manifest publication succeeds'
  or diag $output ;
like _read_text($log), qr/--tag perlessentials\/perl-essentials:latest/,
  'development Perl updates latest' ;

unlink $log or die "Cannot reset fake Docker log: $!" ;
( $status, $output )
  = _run_with_env( \%development_env, $publish, 'manifest', 'codex',
  $amd64_digest, $arm64_digest ) ;
is $status, 0, 'Codex manifest publication succeeds' or diag $output ;

my $codex_log = _read_text($log) ;
like $codex_log, qr/--tag perlessentials\/perl-essentials:codex-2026-06-19_142233/,
  'Codex manifest creates an immutable timestamp tag' ;
like $codex_log, qr/--tag perlessentials\/perl-essentials:codex(?:\s|$)/,
  'Codex manifest updates the Codex alias' ;
like $codex_log, qr/--tag perlessentials\/perl-essentials:v0\.5\.1-codex/,
  'Codex manifest creates a release-specific alias' ;
unlike $codex_log, qr/perl-essentials:latest/,
  'Codex manifest does not replace latest' ;

( $status, $output )
  = _run_with_env( \%base_env, $publish, 'build', 'unknown',
  'linux/amd64', $amd64_digest ) ;
isnt $status, 0, 'unknown image mode is rejected' ;
like $output, qr/Usage:/,
  'unknown image mode reports the supported interface' ;

my $publish_script = _read_text($publish) ;
unlike $publish_script, qr/setup-qemu|tonistiigi\/binfmt/,
  'publication script contains no QEMU setup path' ;

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

sub _run_with_env {
  my ( $env, @command ) = @_ ;
  my $pid = open my $fh, '-|' ;
  die "Cannot fork: $!" if !defined $pid ;
  if ( $pid == 0 ) {
    %ENV = ( %ENV, %{$env} ) ;
    open STDERR, '>&', STDOUT or die "Cannot redirect STDERR: $!" ;
    exec @command or die "Cannot execute '$command[0]': $!" ;
  }
  local $/ ;
  my $output = <$fh> // q{} ;
  close $fh ;
  return ( $? >> 8, $output ) ;
}

sub _write_text {
  my ( $path, $content ) = @_ ;
  open my $fh, '>:encoding(UTF-8)', $path
    or die "Cannot write '$path': $!" ;
  print {$fh} $content or die "Cannot write '$path': $!" ;
  close $fh            or die "Cannot close '$path': $!" ;
  return ;
}
