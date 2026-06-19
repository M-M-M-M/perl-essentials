use strict ;
use warnings ;

use Test::More ;

my $dockerfile     = _read_text('Dockerfile') ;
my ($perl_targets) = $dockerfile =~ /\A(.*)FROM final AS codex/s ;
my ($codex_target) = $dockerfile =~ /(FROM final AS codex.*?)FROM final AS default/s ;

ok defined $codex_target, 'Codex target derives from the final image' ;
unlike $perl_targets, qr{\brtk\b|RTK_},
  'Perl image targets do not install or configure RTK' ;
like $dockerfile, qr/FROM final AS default\s*\z/,
  'Default image inherits the final Perl image without Codex or RTK' ;

SKIP: {
  skip 'Codex target is not available yet', 18 if !defined $codex_target ;

  like $codex_target, qr/apt-get install.*\bbubblewrap\b/s,
    'Codex target installs the distribution bubblewrap package' ;
  like $codex_target, qr/chown root:root \/usr\/bin\/bwrap/,
    'Codex target keeps bubblewrap owned by root' ;
  like $codex_target, qr/chmod 4755 \/usr\/bin\/bwrap/,
    'Codex target enables the bubblewrap setuid fallback' ;
  like $codex_target,
    qr/stat -c '%a:%U:%G' \/usr\/bin\/bwrap.*4755:root:root/s,
    'Codex target verifies the bubblewrap setuid mode while building' ;
  like $codex_target, qr{https://chatgpt\.com/codex/install\.sh},
    'Codex target uses the official standalone installer' ;
  like $codex_target, qr/CODEX_NON_INTERACTIVE=1/,
    'Codex installer runs non-interactively' ;
  like $codex_target, qr/CODEX_INSTALL_DIR=\/usr\/local\/bin/,
    'Codex command is installed under /usr/local/bin' ;
  like $codex_target, qr/CODEX_HOME=\/opt\/codex/,
    'Codex standalone package is installed outside mounted state' ;
  like $codex_target,
    qr{https://raw\.githubusercontent\.com/rtk-ai/rtk/refs/heads/master/install\.sh},
    'Codex target uses the official RTK installer' ;
  like $codex_target, qr/RTK_INSTALL_DIR=\/usr\/local\/bin/,
    'RTK is installed under /usr/local/bin' ;
  like $codex_target, qr/ENV CODEX_HOME=\/codex/,
    'Codex runtime state is stored under /codex' ;
  like $codex_target, qr/^\s+HOME=\/codex \\/m,
    'RTK runtime state is stored with Codex state' ;
  like $codex_target, qr/RTK_TELEMETRY_DISABLED=1/,
    'RTK telemetry is disabled by default' ;
  like $codex_target, qr/ENTRYPOINT \["\/opt\/perl-essentials\/scripts\/codex-entrypoint\.sh"\]/,
    'Codex target initializes RTK through its entrypoint' ;
  like $codex_target, qr/WORKDIR \/work/,
    'Codex starts in the mounted project directory' ;
  like $codex_target, qr/CMD \["codex"\]/,
    'Codex is the default command' ;
  unlike $codex_target, qr/\bCOPY\b.*(?:auth\.json|\.codex|codex-auth)/i,
    'Codex target does not copy credentials or local state' ;
  unlike $codex_target, qr/\brtk init\b/,
    'Codex target does not initialize RTK while building the image' ;
}

my $entrypoint = _read_text('scripts/codex-entrypoint.sh') ;
ok -x 'scripts/codex-entrypoint.sh',
  'Codex entrypoint is executable' ;
like $entrypoint, qr/rtk init -g --codex/,
  'Codex entrypoint initializes the RTK Codex integration' ;
like $entrypoint, qr/\[ -e "\$\{HOME\}\/\.zshrc" \] \|\| : > "\$\{HOME\}\/\.zshrc"/,
  'Codex entrypoint creates only a missing Zsh startup file' ;
like $entrypoint, qr/exec "\$\@"/,
  'Codex entrypoint preserves the requested command' ;

my $public_files = _read_text('.public-files') ;
like $public_files, qr{^scripts/codex-entrypoint\.sh$}m,
  'Public export includes the Codex entrypoint' ;
like $public_files, qr{^scripts/publish\.sh$}m,
  'Public export includes Docker publication logic' ;
like $public_files, qr{^test/docker-publication\.t$}m,
  'Public export includes Docker publication tests' ;
like $public_files, qr{^\.github/workflows/docker-publish\.yml$}m,
  'Public export includes the Docker publication workflow' ;

my $notices = _read_text('THIRD-PARTY-NOTICES.md') ;
like $notices, qr{\brtk-ai/rtk\b},
  'Third-party notices identify RTK' ;
like $notices, qr{github\.com/rtk-ai/rtk/blob/master/LICENSE},
  'Third-party notices link to the RTK license' ;

for my $ignore_file (qw(.gitignore .dockerignore)) {
  my $ignore = _read_text($ignore_file) ;
  like $ignore, qr{^codex-auth/$}m,
    "$ignore_file excludes local Codex state" ;
}

my $ci = _read_text('scripts/ci-build.sh') ;
ok -x 'scripts/ci-build.sh',
  'Unified CI script is executable' ;
ok !-e 'scripts/ci-build-codex.sh',
  'Separate Codex CI script is removed' ;
like $ci, qr/^codex\)$/m,
  'Unified CI script provides a Codex mode' ;
like $ci, qr/image="perl-essentials:codex"/,
  'Codex build uses the single local Codex image tag' ;
unlike $ci, qr/codex-ci/,
  'Codex build does not create a separate CI flavor' ;
like $ci, qr/target="codex".*no_cache="--no-cache"/s,
  'Codex CI builds the target without cache' ;
like $ci, qr/codex --version/,
  'Codex CI checks the CLI version' ;
like $ci, qr/rtk --version/,
  'Codex CI checks the RTK version' ;
like $ci, qr/bwrap --version/,
  'Codex CI checks the bubblewrap version' ;
like $ci, qr/stat.*\/usr\/bin\/bwrap.*4755:root:root/s,
  'Codex CI checks the bubblewrap setuid mode' ;
like $ci, qr/docker run --rm --platform "\$\{platform\}"/,
  'Codex CI runs validation containers for the selected platform' ;
like $ci, qr/--entrypoint find.*\/codex -mindepth 1/s,
  'Codex CI checks state before the entrypoint initializes RTK' ;
like $ci, qr/docker volume create "\$\{codex_state\}"/,
  'Codex CI creates a Docker-managed state fixture' ;
like $ci, qr/--volume "\$\{codex_state\}:\/codex"/,
  'Codex CI mounts its Docker-managed state fixture' ;
like $ci, qr/docker volume rm --force "\$\{codex_state\}"/,
  'Codex CI removes its Docker-managed state fixture' ;
unlike $ci, qr/mktemp|chmod 0777|\$\{state\}:\/codex/,
  'Codex CI does not depend on a runner bind mount' ;
unlike $ci, qr/runner_user|chown .*\/codex/,
  'Codex CI keeps fixture ownership inside the Docker daemon' ;
like $ci, qr/RTK\.md/,
  'Codex CI checks automatic RTK initialization' ;
like $ci, qr/\/codex\/\.zshrc/,
  'Codex CI checks automatic Zsh initialization' ;
like $ci, qr/# custom Zsh configuration.*grep.*-qxF/s,
  'Codex CI checks that Zsh initialization preserves custom state' ;
like $ci, qr/codex sandbox/,
  'Codex CI exercises the command sandbox where supported' ;
like $ci, qr/CI_SKIP_CODEX_SANDBOX/,
  'Codex CI can explicitly skip host-dependent sandbox validation' ;
like $ci,
  qr/Failed RTM_NEWADDR: Operation not permitted.*run_codex_sandbox --user root/s,
  'Codex CI retries as root only for the known host network restriction' ;
unlike $ci, qr/use_legacy_landlock/,
  'Codex CI does not depend on the deprecated Landlock backend' ;
like $ci, qr/seccomp=unconfined/,
  'Codex CI enables the syscalls required by bubblewrap' ;
like $ci, qr/--cap-add SYS_ADMIN/,
  'Codex CI grants the mount capability required by bubblewrap' ;
like $ci, qr/apparmor=unconfined/,
  'Codex CI allows bubblewrap mount operations through AppArmor' ;
unlike $ci, qr/no-new-privileges=true/,
  'Codex CI allows the bubblewrap setuid fallback when user namespaces are unavailable' ;
like $ci, qr/zsh -lic/,
  'Codex CI checks manual use from an interactive Zsh shell' ;
like $ci, qr/Unknown build mode/,
  'Unified CI script rejects unknown modes' ;
like $ci, qr/Building target .* for .* as /,
  'Unified CI script logs the selected build before it starts' ;
like $ci, qr/Docker image .* loaded successfully/,
  'Unified CI script logs successful image loading' ;
like $ci, qr/Validating .* image/,
  'Unified CI script logs the validation phase' ;

my $github = _read_text('.github/workflows/ci.yml') ;
like $github,
  qr/PERL_VERSION:\s*5\.43\.9.*CI_PLATFORM:\s*\$\{\{\s*matrix\.platform\s*\}\}.*scripts\/ci-build\.sh codex/s,
  'GitHub CI validates Codex with the default Perl version on each platform' ;
like $github, qr/platform:.*linux\/amd64.*linux\/arm64/s,
  'GitHub CI validates Codex on both Docker platforms' ;
like $github, qr/platform:\s+linux\/arm64\s+runner:\s+ubuntu-24\.04-arm/s,
  'GitHub CI uses a native ARM64 runner for ARM64 validation' ;
unlike $github, qr/docker\/setup-qemu-action/,
  'GitHub CI does not install QEMU for native ARM64 validation' ;
unlike $github, qr/ci-build-codex/,
  'GitHub CI uses only the unified build script' ;

my $bitbucket = _read_text('bitbucket-pipelines.yml') ;
like $bitbucket,
  qr/PERL_VERSION=5\.43\.9 CI_PLATFORM=linux\/amd64 scripts\/ci-build\.sh codex/,
  'Bitbucket CI validates Codex for linux/amd64 with the default Perl version' ;
like $bitbucket,
  qr/PERL_VERSION=5\.43\.9 CI_PLATFORM=linux\/arm64 scripts\/ci-build\.sh codex/,
  'Bitbucket CI validates Codex for linux/arm64 with the default Perl version' ;
unlike $bitbucket, qr/ci-build-codex/,
  'Bitbucket CI uses only the unified build script' ;

my $publication = _read_text('scripts/publish.sh') ;
like $publication, qr/target="final"/,
  'Docker publication explicitly selects the final Perl image' ;
like $publication, qr/target="codex".*set -- "\$\@" --no-cache/s,
  'Docker publication includes a no-cache Codex flavor' ;

like $ci, qr/target="final"/,
  'Perl CI explicitly selects the final image' ;

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
