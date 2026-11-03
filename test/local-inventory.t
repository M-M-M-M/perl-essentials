use strict ;
use warnings ;
use Cwd        qw(abs_path getcwd) ;
use File::Temp qw(tempdir) ;
use File::Path qw(make_path) ;
use Test::More ;
my $script = abs_path('scripts/refresh-local-inventory.sh') ;
my $tmp    = tempdir( CLEANUP => 1 ) ;
make_path( "$tmp/scripts", "$tmp/bin" ) ;

sub write_file {
  my ( $path, $text ) = @_ ;
  open my $fh, '>', $path or die $! ;
  print {$fh} $text or die $! ;
  close $fh         or die $! ;
}

sub read_file {
  my ($path) = @_ ;
  open my $fh, '<', $path or die $! ;
  local $/ ;
  return <$fh> ;
}
write_file( "$tmp/perl-versions.conf", "5.44.0|stable|Stable\n5.45.4|development|Dev\n" ) ;
write_file( "$tmp/bin/docker",         <<'SH' ) ;
#!/bin/sh
printf '%s\n' "$*" >> "$TEST_LOG"
case "$*" in
  info*) echo aarch64 ;;
  run*)
    if [ "${BAD_VERSION:-0}" = 1 ]; then echo 5.45.4
    else case "$*" in *dev*) echo 5.45.4 ;; *) echo 5.44.0 ;; esac; fi ;;
esac
SH
write_file( "$tmp/bin/prettier", <<'SH' ) ;
#!/bin/sh
printf 'format\n' >> "$TEST_LOG"
SH
write_file( "$tmp/scripts/ci-build.sh", <<'SH' ) ;
#!/bin/sh
printf 'build %s %s %s\n' "$PERL_VERSION" "$CI_PLATFORM" "$CI_IMAGE" >> "$TEST_LOG"
if [ "${BUILD_FAIL:-0}" = 1 ]; then exit 19; fi
SH
write_file( "$tmp/scripts/update-readme-module-versions.sh", <<'SH' ) ;
#!/bin/sh
printf 'capture %s %s %s\n' "$IMAGE" "$CODEX_IMAGE" "$CODEX_DEV_IMAGE" >> "$TEST_LOG"
printf 'updated\n' > README.md
SH
for my $file (qw(bin/docker bin/prettier scripts/ci-build.sh scripts/update-readme-module-versions.sh)) {
  chmod 0755, "$tmp/$file" or die $! ;
}
my $cwd = getcwd() ;
chdir $tmp or die $! ;
local $ENV{PATH}     = "$tmp/bin:$ENV{PATH}" ;
local $ENV{TEST_LOG} = "$tmp/log" ;

sub run_capture {
  my (@args) = @_ ;
  write_file( "$tmp/log",  '' ) ;
  write_file( 'README.md', "original\n" ) ;
  my $pid = fork() ;
  die $! unless defined $pid ;
  if ( !$pid ) {
    open STDOUT, '>',  "$tmp/output" or die $! ;
    open STDERR, '>&', STDOUT        or die $! ;
    exec '/bin/sh', $script, @args or die $! ;
  }
  waitpid $pid, 0 ;
  return $? >> 8 ;
}
is run_capture(), 0, 'captures existing validated local images' ;
like read_file('README.md'),  qr/updated/,         'writes the captured inventory' ;
unlike read_file("$tmp/log"), qr/build |image rm/, 'reuse does not build or delete images' ;
{
  local $ENV{BAD_VERSION} = 1 ;
  isnt run_capture(),        0,            'rejects the wrong Perl base' ;
  is read_file('README.md'), "original\n", 'wrong base leaves documentation intact' ;
}
is run_capture('--build'), 0, 'builds and captures native Codex variants' ;
like read_file("$tmp/log"), qr/build 5\.44\.0 linux\/arm64 perl-essentials:inventory-stable-/,   'builds stable under a temporary tag' ;
like read_file("$tmp/log"), qr/build 5\.45\.4 linux\/arm64 perl-essentials:inventory-dev-/,      'builds development under a temporary tag' ;
like read_file("$tmp/log"), qr/capture .*\nformat\nimage rm perl-essentials:inventory-stable-/s, 'cleans temporary tags after capture and formatting' ;
{
  local $ENV{BUILD_FAIL} = 1 ;
  isnt run_capture('--build'), 0,            'failed build stops capture' ;
  is read_file('README.md'),   "original\n", 'failed build preserves documentation' ;
  like read_file("$tmp/log"), qr/image rm perl-essentials:inventory-stable-/, 'failed build cleans temporary tags' ;
}
chdir $cwd or die $! ;
done_testing ;
