use strict ;
use warnings ;

use Test::More ;

my @workflows = qw(
  .github/workflows/ci.yml
  .github/workflows/perl-versions.yml
) ;

for my $path (@workflows) {
  my $workflow = _read_text($path) ;

  like $workflow, qr/actions\/checkout\@v6/,
    "$path uses Checkout v6" ;
  unlike $workflow, qr/actions\/checkout\@v4/,
    "$path does not use Checkout v4" ;
}

my $perl_versions = _read_text('.github/workflows/perl-versions.yml') ;
like $perl_versions, qr{run: test/check-perl-versions\.sh public},
  'Perl version workflow tests the public drift profile' ;
like $perl_versions,
  qr{name: Install Perl HTTPS support.*libio-socket-ssl-perl}s,
  'Perl version workflow installs HTTPS support for the system Perl' ;
like $perl_versions,
  qr{scripts/check-perl-versions\.pl --check --drift-profile public},
  'Perl version workflow uses the public drift profile' ;

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
