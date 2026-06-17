use strict ;
use warnings ;

use Test::More ;

my $actionlint = _find_command('actionlint') ;

if ( !defined $actionlint ) {
  plan skip_all => 'actionlint not installed' ;
}

my $output = qx{"$actionlint" 2>&1} ;
my $status = $? >> 8 ;

is $status, 0, 'GitHub workflows pass actionlint'
  or diag $output ;

done_testing ;

sub _find_command {
  my ($command) = @_ ;

  for my $dir ( split /:/, $ENV{PATH} ) {
    next if $dir eq '' ;

    my $path = "$dir/$command" ;
    return $path if -x $path && !-d $path ;
  }

  return ;
}
