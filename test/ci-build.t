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
    case "$*" in
    *' --timeout '*)
        printf '%s\n' 'unknown flag: --timeout' >&2
        exit 125
        ;;
    esac

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

if [ "$1" = "info" ]; then
    case "$*" in
    *'{{.Architecture}}'*)
        printf '%s\n' "${DOCKER_ARCHITECTURE}"
        exit 0
        ;;
    esac
fi

case "$*" in
*'codex sandbox -- sh -c printf sandbox-ok'*)
    case "${SANDBOX_MODE}" in
    success)
        printf '%s' sandbox-ok
        ;;
    rtm-newaddr)
        if printf '%s\n' "$*" | grep -q -- '--user root'; then
            printf '%s' sandbox-ok
        else
            printf '%s\n' \
                'bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted' >&2
            exit 77
        fi
        ;;
    other-error)
        printf '%s\n' 'bwrap: Creating new namespace failed' >&2
        exit 78
        ;;
    seccomp-einval)
        printf '%s\n' \
            'error applying Linux sandbox restrictions: Sandbox(SeccompInstall(Seccomp(Os { code: 22, kind: InvalidInput, message: "Invalid argument" })))' >&2
        exit 101
        ;;
    fallback-error)
        if printf '%s\n' "$*" | grep -q -- '--user root'; then
            printf '%s\n' 'bwrap: root fallback failed' >&2
            exit 79
        fi
        printf '%s\n' \
            'bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted' >&2
        exit 77
        ;;
    esac
    ;;
esac

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

local $ENV{PATH}                = "$bin:$ENV{PATH}" ;
local $ENV{BUILD_STATUS}        = 42 ;
local $ENV{DOCKER_LOG}          = $log ;
local $ENV{INSPECT_COUNT}       = $count ;
local $ENV{INSPECT_SUCCEED_AT}  = 3 ;
local $ENV{PERL_VERSION}        = '5.45.1' ;
local $ENV{SANDBOX_MODE}        = 'success' ;
local $ENV{DOCKER_ARCHITECTURE} = 'x86_64' ;

my $output = qx{/bin/sh "$script" codex 2>&1} ;
my $status = $? >> 8 ;

is $status,            42,    'CI continues after a transient Buildx bootstrap failure' ;
is _read_text($count), "3\n", 'CI retries Buildx bootstrap until it succeeds' ;
like $output, qr/Buildx bootstrap failed \(attempt 1\/6\), retrying/,
  'CI reports a transient Buildx bootstrap failure' ;
like $output, qr/Buildx builder is ready/,
  'CI reports that Buildx bootstrap eventually succeeded' ;
{
  my $docker_log = _read_text($log) ;
  like $docker_log, qr/^buildx inspect --bootstrap perl-essentials-codex-\d+$/m,
    'CI bootstraps Buildx with runner-compatible inspect arguments' ;
  unlike $docker_log, qr/--timeout/,
    'CI does not pass the unsupported Buildx inspect timeout flag' ;
}

unlink $count or die "Cannot reset '$count': $!" ;
$ENV{INSPECT_SUCCEED_AT} = 99 ;

$output = qx{/bin/sh "$script" codex 2>&1} ;
$status = $? >> 8 ;

is $status,            1,     'CI rejects a permanently unavailable Buildx builder' ;
is _read_text($count), "6\n", 'CI limits Buildx bootstrap to six attempts' ;
like $output, qr/Buildx bootstrap failed after 6 attempts/,
  'CI reports a permanent Buildx bootstrap failure' ;

unlink $count or die "Cannot reset '$count': $!" ;
unlink $log   or die "Cannot reset '$log': $!" ;
$ENV{INSPECT_SUCCEED_AT} = 1 ;
$ENV{BUILD_STATUS}       = 0 ;
$ENV{INSPECT_SUCCEED_AT} = 1 ;

$output = qx{/bin/sh "$script" codex 2>&1} ;
$status = $? >> 8 ;
my $docker_log = _read_text($log) ;

is $status, 0, 'Codex validation succeeds with a Docker-managed fixture' ;
like $output, qr/CI validation step: codex-empty-state\nCI validation step: codex-empty-state ok/,
  'Codex validation reports successful validation steps' ;
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
{
  local $ENV{CI_IMAGE} = 'perl-essentials:local-validate-codex' ;

  $output     = qx{/bin/sh "$script" codex 2>&1} ;
  $status     = $? >> 8 ;
  $docker_log = _read_text($log) ;

  is $status, 0, 'Codex validation succeeds with an overridden image tag' ;
  like $docker_log, qr/buildx build .* --tag perl-essentials:local-validate-codex/s,
    'CI_IMAGE overrides the Codex build tag' ;
}

unlink $log or die "Cannot reset '$log': $!" ;
{
  local $ENV{CI_IMAGE} = 'perl-essentials:local-validate-perl' ;

  $output     = qx{/bin/sh "$script" perl 2>&1} ;
  $status     = $? >> 8 ;
  $docker_log = _read_text($log) ;

  is $status, 0, 'Perl validation succeeds with an overridden image tag' ;
  like $docker_log, qr/buildx build .* --tag perl-essentials:local-validate-perl \./s,
    'CI_IMAGE overrides the Perl build tag without corrupting the build command' ;
}

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
$ENV{SANDBOX_MODE} = 'rtm-newaddr' ;

$output     = qx{/bin/sh "$script" codex 2>&1} ;
$status     = $? >> 8 ;
$docker_log = _read_text($log) ;

is $status, 0, 'Codex validation falls back for the known RTM_NEWADDR restriction' ;
like $output, qr/Retrying Codex sandbox validation as root.*RTM_NEWADDR/s,
  'known host restriction reports the targeted root fallback' ;
like $docker_log,
  qr/codex sandbox -- sh -c printf sandbox-ok.*--user root .*codex sandbox -- sh -c printf sandbox-ok/s,
  'known host restriction tries non-root before root' ;

unlink $log or die "Cannot reset '$log': $!" ;
$ENV{SANDBOX_MODE} = 'other-error' ;

$output     = qx{/bin/sh "$script" codex 2>&1} ;
$status     = $? >> 8 ;
$docker_log = _read_text($log) ;

is $status, 78, 'unrecognized sandbox failures remain fatal' ;
like $output, qr/bwrap: Creating new namespace failed/,
  'unrecognized sandbox failure is preserved in CI output' ;
like $output, qr/CI validation step: codex-sandbox failed with status 78/,
  'Codex validation reports the failing sandbox validation step' ;
unlike $docker_log, qr/--user root .*codex sandbox/,
  'unrecognized sandbox failure does not use the root fallback' ;

unlink $log or die "Cannot reset '$log': $!" ;
$ENV{SANDBOX_MODE}        = 'seccomp-einval' ;
$ENV{DOCKER_ARCHITECTURE} = 'aarch64' ;
$ENV{CI_PLATFORM}         = 'linux/amd64' ;

$output     = qx{/bin/sh "$script" codex 2>&1} ;
$status     = $? >> 8 ;
$docker_log = _read_text($log) ;

is $status, 0, 'Codex validation skips seccomp EINVAL under AMD64 emulation on ARM64 Docker' ;
like $output,
  qr/Skipping Codex sandbox validation because linux\/amd64 is running on an arm64 Docker host/,
  'emulated AMD64 seccomp skip reports why it skipped' ;
unlike $docker_log, qr/--user root .*codex sandbox/,
  'emulated AMD64 seccomp skip does not use the root fallback' ;

unlink $log or die "Cannot reset '$log': $!" ;
$ENV{DOCKER_ARCHITECTURE} = 'x86_64' ;

$output     = qx{/bin/sh "$script" codex 2>&1} ;
$status     = $? >> 8 ;
$docker_log = _read_text($log) ;

is $status, 101, 'Codex validation keeps seccomp EINVAL fatal on native AMD64 Docker' ;
like $output, qr/SeccompInstall/,
  'native AMD64 seccomp failure is preserved in CI output' ;
unlike $docker_log, qr/--user root .*codex sandbox/,
  'native AMD64 seccomp failure does not use the root fallback' ;

unlink $log or die "Cannot reset '$log': $!" ;
$ENV{DOCKER_ARCHITECTURE} = 'x86_64' ;
$ENV{SANDBOX_MODE}        = 'fallback-error' ;

$output     = qx{/bin/sh "$script" codex 2>&1} ;
$status     = $? >> 8 ;
$docker_log = _read_text($log) ;

is $status, 79, 'a failed root fallback remains fatal' ;
like $output, qr/bwrap: root fallback failed/,
  'root fallback failure is preserved in CI output' ;
like $docker_log, qr/--user root .*codex sandbox/,
  'known host restriction attempts the root fallback once' ;

unlink $log or die "Cannot reset '$log': $!" ;
local $ENV{CI_SKIP_CODEX_SANDBOX} = '1' ;
$ENV{SANDBOX_MODE} = 'success' ;

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
