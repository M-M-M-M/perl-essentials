use strict ;
use warnings ;

use Test::More ;

my $dockerfile    = _read_text('Dockerfile') ;
my $ci            = _read_text('scripts/ci-build.sh') ;
my $readme        = _read_text('README.md') ;
my $documentation = _read_text('DOCUMENTATION.md') ;
my $dockerhub     = _read_text('DOCKERHUB.md') ;

my ($final) = $dockerfile =~ /(FROM modules AS final.*?)FROM final AS codex/s ;
ok defined $final, 'final Perl target is present' ;
like $final, qr/groupadd --gid 1000 perl/,
  'final target creates the perl group with GID 1000' ;
like $final, qr/useradd --uid 1000 --gid 1000.*\bperl\b/s,
  'final target creates the perl user with UID 1000' ;
like $final, qr/ENV HOME=\/home\/perl/,
  'final target uses the perl home directory' ;
like $final, qr/chown perl:perl \/work/,
  'final target makes the working directory writable by perl' ;
like $final, qr/touch \/home\/perl\/\.zshrc/,
  'final target suppresses the Zsh new-user assistant' ;
like $final, qr/chmod 0755 \/home\/perl/,
  'final target exposes the startup marker to host UID overrides' ;
like $final, qr/USER perl:perl/,
  'final target runs as perl by default' ;

my ($debug_base) = $dockerfile =~ /(FROM system AS debug-base.*?)FROM debug-base AS modules/s ;
my ($debug)      = $dockerfile =~ /(FROM modules AS debug.*?)FROM modules AS final/s ;
unlike $debug_base // q{}, qr/\bUSER perl/,
  'pre-CPAN debug target remains root' ;
unlike $debug // q{}, qr/\bUSER perl/,
  'complete debug target remains root' ;

my ($codex) = $dockerfile =~ /(FROM final AS codex.*?)FROM final AS default/s ;
like $codex // q{}, qr/USER root.*apt-get install/s,
  'Codex target regains root only for installation' ;
like $codex // q{}, qr/mkdir -p "\$\{CODEX_HOME\}".*chown perl:perl "\$\{CODEX_HOME\}"/s,
  'Codex state directory belongs to perl' ;
like $codex // q{}, qr/USER perl:perl.*ENTRYPOINT/s,
  'Codex runtime returns to the perl user' ;

my $entrypoint = _read_text('scripts/codex-entrypoint.sh') ;
like $entrypoint, qr/\[ -e "\$\{HOME\}\/\.zshrc" \] \|\| : > "\$\{HOME\}\/\.zshrc"/,
  'Codex entrypoint initializes only a missing Zsh startup file' ;

like $ci, qr/test "\$\(id -u\)" = 1000.*test "\$\(id -un\)" = perl/s,
  'CI validates the default Perl user identity' ;
like $ci, qr/--user root.*PROMPT.*#/s,
  'CI validates the explicit root override' ;
like $ci, qr/--volume "\$\{codex_state\}:\/codex".*\/codex\/\.zshrc/s,
  'CI validates Zsh initialization in persistent Codex state' ;
like $ci, qr/# custom Zsh configuration.*grep.*-qxF/s,
  'CI validates preservation of a custom Zsh startup file' ;

for my $document (
  [ 'README.md',        $readme ],
  [ 'DOCUMENTATION.md', $documentation ],
  [ 'DOCKERHUB.md',     $dockerhub ],
  )
{
  my ( $name, $content ) = @{$document} ;
  like $content, qr/default.*`perl`.*1000:1000/is,
    "$name documents the default non-root identity" ;
  like $content, qr/--user "\$\(id -u\):\$\(id -g\)"/,
    "$name documents host UID/GID for writable bind mounts" ;
}

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
