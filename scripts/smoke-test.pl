#!/usr/bin/env perl

use strict ;
use warnings ;

my @files   = @ARGV ? @ARGV : qw(cpanfile cpanfile-notest) ;
my @modules = read_modules(@files) ;
my @failed ;

for my $module (@modules) {
  my $status = system(
    $^X,
    "-M$module",
    '-e',
    'exit 0',
  ) ;

  if ( $status == 0 ) {
    print "ok - $module\n" ;
  }
  else {
    push @failed, $module ;
    print STDERR "not ok - $module\n" ;
  }
}

die "Smoke test failed: @failed\n" if @failed ;
print "All " . scalar(@modules) . " modules loaded successfully.\n" ;

sub read_modules {
  my @paths = @_ ;
  my %seen ;
  my @result ;

  for my $path (@paths) {
    open my $fh, '<', $path or die "Cannot open $path: $!\n" ;

    while ( my $line = <$fh> ) {
      next if $line =~ /^\s*#/ ;
      next unless $line =~ /^\s*requires\s+['"]([^'"]+)['"]/ ;
      push @result, $1 unless $seen{$1}++ ;
    }
  }

  return @result ;
}
