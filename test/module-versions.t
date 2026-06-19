use strict ;
use warnings ;

use Config ;
use Cwd        qw(abs_path) ;
use File::Path qw(make_path) ;
use File::Spec ;
use File::Temp qw(tempdir) ;
use Test::More ;

my $root   = abs_path('.') ;
my $script = File::Spec->catfile( $root, 'scripts', 'module-versions.pl' ) ;
my $tmp    = tempdir( CLEANUP => 1 ) ;
my $lib    = File::Spec->catdir( $tmp, 'lib' ) ;
my $cpan   = File::Spec->catfile( $tmp, 'cpanfile' ) ;

ok -x $script, 'module version script is executable' ;

make_path( File::Spec->catdir( $lib, 'Mojolicious' ) ) ;
_write_text(
  File::Spec->catfile( $lib, 'Mojolicious', 'Lite.pm' ),
  "package Mojolicious::Lite;\n1;\n",
) ;
_write_text(
  File::Spec->catfile( $lib, 'Mojolicious.pm' ),
  "package Mojolicious;\nour \$VERSION = '7.31';\n1;\n",
) ;
_write_text( $cpan, "requires 'Mojolicious::Lite';\n" ) ;

local $ENV{PERL5LIB} = join $Config{path_sep}, $lib,
  grep {length} ( $ENV{PERL5LIB} // q{} ) ;
my $output = qx{$^X "$script" --format markdown "$cpan"} ;
my $status = $? >> 8 ;

is $status, 0, 'module version report succeeds' ;
like $output, qr/^\| `Mojolicious::Lite` \| `7\.31` \|$/m,
  'Mojolicious::Lite reports the canonical distribution version' ;

done_testing ;

sub _write_text {
  my ( $path, $content ) = @_ ;
  open my $fh, '>:encoding(UTF-8)', $path
    or die "Cannot write '$path': $!" ;
  print {$fh} $content or die "Cannot write '$path': $!" ;
  close $fh            or die "Cannot close '$path': $!" ;
  return ;
}
