use strict ;
use warnings ;

use Test::More ;

my $dockerfile     = _read_text('Dockerfile') ;
my ($perl_targets) = $dockerfile =~ /\A(.*)FROM final AS codex/s ;
my ($codex_target) = $dockerfile =~ /(FROM final AS codex.*)\z/s ;

ok defined $codex_target, 'Codex target derives from the final image' ;
unlike $perl_targets, qr{\brtk\b|RTK_},
  'Perl image targets do not install or configure RTK' ;

SKIP: {
  skip 'Codex target is not available yet', 15 if !defined $codex_target ;

  like $codex_target, qr/apt-get install.*\bbubblewrap\b/s,
    'Codex target installs the distribution bubblewrap package' ;
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
like $entrypoint, qr/exec "\$\@"/,
  'Codex entrypoint preserves the requested command' ;

my $public_files = _read_text('.public-files') ;
like $public_files, qr{^scripts/codex-entrypoint\.sh$}m,
  'Public export includes the Codex entrypoint' ;

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

my $codex_ci = _read_text('scripts/ci-build-codex.sh') ;
ok -x 'scripts/ci-build-codex.sh',
  'Codex CI script is executable' ;
like $codex_ci, qr/docker buildx build.*--target codex.*--no-cache/s,
  'Codex CI builds the target without cache' ;
like $codex_ci, qr/codex --version/,
  'Codex CI checks the CLI version' ;
like $codex_ci, qr/rtk --version/,
  'Codex CI checks the RTK version' ;
like $codex_ci, qr/bwrap --version/,
  'Codex CI checks the bubblewrap version' ;
like $codex_ci, qr/--entrypoint find.*\/codex -mindepth 1/s,
  'Codex CI checks state before the entrypoint initializes RTK' ;
like $codex_ci, qr/chmod 0777 "\$\{state\}"/,
  'Codex CI makes its temporary bind mount writable through user remapping' ;
like $codex_ci, qr/RTK\.md/,
  'Codex CI checks automatic RTK initialization' ;
like $codex_ci, qr/codex sandbox/,
  'Codex CI exercises the command sandbox' ;
like $codex_ci, qr/seccomp=unconfined/,
  'Codex CI enables the syscalls required by bubblewrap' ;
like $codex_ci, qr/--cap-add SYS_ADMIN/,
  'Codex CI grants the mount capability required by bubblewrap' ;
like $codex_ci, qr/apparmor=unconfined/,
  'Codex CI allows bubblewrap mount operations through AppArmor' ;
like $codex_ci, qr/no-new-privileges=true/,
  'Codex CI prevents privilege escalation' ;
like $codex_ci, qr/zsh -lic/,
  'Codex CI checks manual use from an interactive Zsh shell' ;

my $github = _read_text('.github/workflows/ci.yml') ;
like $github, qr/PERL_VERSION:\s*5\.43\.9.*scripts\/ci-build-codex\.sh/s,
  'GitHub CI validates Codex with the default Perl version' ;

my $bitbucket = _read_text('bitbucket-pipelines.yml') ;
like $bitbucket, qr/PERL_VERSION=5\.43\.9 scripts\/ci-build-codex\.sh/,
  'Bitbucket CI validates Codex with the default Perl version' ;

my $publication = _read_text('scripts/publish.sh') ;
unlike $publication, qr/--target[=\s]+codex/,
  'Codex target is absent from Docker publication' ;

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
