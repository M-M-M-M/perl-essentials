use strict ;
use warnings ;

use Test::More ;

my $readme        = _read_text('README.md') ;
my $documentation = _read_text('DOCUMENTATION.md') ;

for my $document (
  [ 'README.md',        $readme ],
  [ 'DOCUMENTATION.md', $documentation ],
  )
{
  my ( $name, $content ) = @{$document} ;
  unlike $content,
    qr/Bitbucket|Docker-in-Docker|validate-one-image|linux\.arm64|SOPS|1Password/,
    "$name contains no private CI provider details" ;
}

unlike $readme,
  qr/--cap-add SYS_ADMIN|apparmor=unconfined|seccomp=unconfined/,
  'README normal usage does not weaken Docker isolation' ;
like $documentation, qr/Advanced Bubblewrap troubleshooting/,
  'detailed documentation keeps an advanced sandbox troubleshooting section' ;
like $documentation, qr/--cap-add SYS_ADMIN.*apparmor=unconfined.*seccomp=unconfined/s,
  'advanced sandbox troubleshooting documents the optional Docker overrides' ;
like $readme, qr/cron `17 6 \* \* 1`.*Monday at 06:17 UTC/s,
  'README explains the weekly GitHub schedule precisely' ;
like $readme, qr/`Mojolicious::Lite` \| `9\.46`/,
  'README reports the installed Mojolicious distribution version' ;

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
