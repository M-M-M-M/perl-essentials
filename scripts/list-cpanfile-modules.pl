#!/usr/bin/env perl

use strict ;
use warnings ;

@ARGV or die "Usage: $0 CPANFILE [CPANFILE ...]\n" ;

for my $file (@ARGV) {
  open my $fh, '<', $file or die "Cannot open $file: $!\n" ;

  while ( my $line = <$fh> ) {
    next         if $line =~ /^\s*#/ ;
    print "$1\n" if $line =~ /^\s*requires\s+['"]([^'"]+)['"]/ ;
  }
}
