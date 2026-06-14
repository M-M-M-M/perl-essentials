use strict ;
use warnings ;

use Cwd        qw(abs_path) ;
use File::Path qw(make_path) ;
use File::Spec ;
use File::Temp qw(tempdir) ;
use Test::More ;

my $root   = abs_path('.') ;
my $script = File::Spec->catfile( $root, 'scripts', 'ci-build.sh' ) ;
my $tmp    = tempdir( CLEANUP => 1 ) ;
my $bin    = File::Spec->catdir( $tmp, 'bin' ) ;
my $count  = File::Spec->catfile( $tmp, 'inspect-count' ) ;
make_path($bin) ;

_write_command(
  File::Spec->catfile( $bin, 'docker' ),
  <<'SH',
#!/bin/sh
set -eu

if [ "$1 $2" = "buildx inspect" ]; then
    count=0
    if [ -f "${INSPECT_COUNT}" ]; then
        count="$(cat "${INSPECT_COUNT}")"
    fi
    count=$((count + 1))
    printf '%s\n' "${count}" >"${INSPECT_COUNT}"
    if [ "${count}" -lt "${INSPECT_SUCCEED_AT}" ]; then
        printf '%s\n' 'context deadline exceeded' >&2
        exit 1
    fi
    exit 0
fi

if [ "$1 $2" = "buildx build" ]; then
    exit 42
fi

exit 0
SH
) ;
_write_command(
  File::Spec->catfile( $bin, 'sleep' ),
  "#!/bin/sh\nexit 0\n",
) ;

local $ENV{PATH}               = "$bin:$ENV{PATH}" ;
local $ENV{INSPECT_COUNT}      = $count ;
local $ENV{INSPECT_SUCCEED_AT} = 3 ;
local $ENV{PERL_VERSION}       = '5.43.9' ;

my $output = qx{/bin/sh "$script" codex 2>&1} ;
my $status = $? >> 8 ;

is $status,            42,    'CI continues after a transient Buildx bootstrap failure' ;
is _read_text($count), "3\n", 'CI retries Buildx bootstrap until it succeeds' ;
like $output, qr/Buildx bootstrap failed \(attempt 1\/3\), retrying/,
  'CI reports a transient Buildx bootstrap failure' ;
like $output, qr/Buildx builder is ready/,
  'CI reports that Buildx bootstrap eventually succeeded' ;

unlink $count or die "Cannot reset '$count': $!" ;
$ENV{INSPECT_SUCCEED_AT} = 99 ;

$output = qx{/bin/sh "$script" codex 2>&1} ;
$status = $? >> 8 ;

is $status,            1,     'CI rejects a permanently unavailable Buildx builder' ;
is _read_text($count), "3\n", 'CI limits Buildx bootstrap to three attempts' ;
like $output, qr/Buildx bootstrap failed after 3 attempts/,
  'CI reports a permanent Buildx bootstrap failure' ;

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

sub _write_command {
  my ( $path, $content ) = @_ ;
  open my $fh, '>:encoding(UTF-8)', $path
    or die "Cannot write '$path': $!" ;
  print {$fh} $content
    or die "Cannot write '$path': $!" ;
  close $fh or die "Cannot close '$path': $!" ;
  chmod 0755, $path or die "Cannot make '$path' executable: $!" ;
  return ;
}
