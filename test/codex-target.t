use strict ;
use warnings ;

use Test::More ;

my $dockerfile = _read_text('Dockerfile') ;
my ($codex_target) = $dockerfile =~ /(FROM final AS codex.*)\z/s ;

ok defined $codex_target, 'Codex target derives from the final image' ;

SKIP: {
  skip 'Codex target is not available yet', 9 if !defined $codex_target ;

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
  like $codex_target, qr/ENV CODEX_HOME=\/codex/,
    'Codex runtime state is stored under /codex' ;
  like $codex_target, qr/WORKDIR \/work/,
    'Codex starts in the mounted project directory' ;
  like $codex_target, qr/CMD \["codex"\]/,
    'Codex is the default command' ;
  unlike $codex_target, qr/\bCOPY\b.*(?:auth\.json|\.codex|codex-auth)/i,
    'Codex target does not copy credentials or local state' ;
}

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
like $codex_ci, qr/bwrap --version/,
  'Codex CI checks the bubblewrap version' ;
like $codex_ci, qr/find \/codex -mindepth 1/,
  'Codex CI checks the initial state directory' ;
like $codex_ci, qr/codex sandbox/,
  'Codex CI exercises the command sandbox' ;
like $codex_ci, qr/seccomp=unconfined/,
  'Codex CI enables the syscalls required by bubblewrap' ;
like $codex_ci, qr/--cap-add SYS_ADMIN/,
  'Codex CI grants the mount capability required by bubblewrap' ;
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
