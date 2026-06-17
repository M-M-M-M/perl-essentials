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
my $log    = File::Spec->catfile( $tmp, 'docker.log' ) ;
make_path($bin) ;

_write_command(
  File::Spec->catfile( $bin, 'docker' ),
  <<'SH',
#!/bin/sh
set -eu

printf '%s\n' "$*" >>"${DOCKER_LOG}"

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
    exit "${BUILD_STATUS}"
fi

case "$*" in
*'--entrypoint grep '*)
    printf '%s\n' 1
    ;;
*'--entrypoint stat '*)
    printf '%s\n' '4755:root:root'
    ;;
esac

if [ "$1 $2" = "volume create" ]; then
    printf '%s\n' "$3"
fi

exit 0
SH
) ;
_write_command(
  File::Spec->catfile( $bin, 'sleep' ),
  "#!/bin/sh\nexit 0\n",
) ;

local $ENV{PATH}               = "$bin:$ENV{PATH}" ;
local $ENV{BUILD_STATUS}       = 42 ;
local $ENV{DOCKER_LOG}         = $log ;
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

unlink $count or die "Cannot reset '$count': $!" ;
unlink $log   or die "Cannot reset '$log': $!" ;
$ENV{BUILD_STATUS}       = 0 ;
$ENV{INSPECT_SUCCEED_AT} = 1 ;

$output = qx{/bin/sh "$script" codex 2>&1} ;
$status = $? >> 8 ;
my $docker_log = _read_text($log) ;

is $status, 0, 'Codex validation succeeds with a Docker-managed fixture' ;
like $docker_log, qr/^volume create perl-essentials-codex-state-/m,
  'Codex validation creates a named Docker volume' ;
like $docker_log, qr/--volume perl-essentials-codex-state-\d+:\/codex/,
  'Codex validation reuses the named Docker volume' ;
like $docker_log, qr/^run --rm --platform linux\/amd64 /m,
  'Codex validation runs containers for the selected platform' ;
like $docker_log, qr/--entrypoint stat .* \/usr\/bin\/bwrap/,
  'Codex validation checks the bubblewrap setuid mode' ;
like $docker_log, qr/codex sandbox -- sh -c printf sandbox-ok/,
  'Codex validation runs the sandbox smoke test on AMD64' ;
like $docker_log, qr/^volume rm --force perl-essentials-codex-state-/m,
  'Codex validation removes the named Docker volume' ;
unlike $docker_log, qr{--volume /[^ ]+:/codex},
  'Codex validation does not bind mount a runner path' ;

unlink $log or die "Cannot reset '$log': $!" ;
local $ENV{CI_PLATFORM} = 'linux/arm64' ;

$output     = qx{/bin/sh "$script" codex 2>&1} ;
$status     = $? >> 8 ;
$docker_log = _read_text($log) ;

is $status, 0, 'ARM64 Codex validation succeeds with the sandbox smoke test' ;
like $docker_log, qr/codex sandbox -- sh -c printf sandbox-ok/,
  'ARM64 Codex validation runs the sandbox smoke test by default' ;
like $docker_log, qr/^run --rm --platform linux\/arm64 /m,
  'ARM64 Codex validation still runs containers for the selected platform' ;

unlink $log or die "Cannot reset '$log': $!" ;
local $ENV{CI_SKIP_CODEX_SANDBOX} = '1' ;

$output     = qx{/bin/sh "$script" codex 2>&1} ;
$status     = $? >> 8 ;
$docker_log = _read_text($log) ;

is $status, 0, 'Codex validation can explicitly skip the sandbox smoke test' ;
like $output,
  qr/Skipping Codex sandbox validation because CI_SKIP_CODEX_SANDBOX=1/,
  'explicit sandbox skip reports why it skipped' ;
unlike $docker_log, qr/codex sandbox -- sh -c printf sandbox-ok/,
  'explicit sandbox skip does not run the sandbox smoke test' ;

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
