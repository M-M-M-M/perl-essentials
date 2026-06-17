#!/usr/bin/env perl

use strict ;
use warnings ;

use Getopt::Long qw(GetOptions) ;
use Module::Metadata ;

my $format = 'text' ;
GetOptions( 'format=s' => \$format )
  or die "Usage: $0 [--format text|markdown] [CPANFILE ...]\n" ;
die "Unknown format: $format\n"
  unless $format eq 'text' || $format eq 'markdown' ;

my @files =
  @ARGV ? @ARGV : qw(cpanfile cpanfile-bootstrap-notest cpanfile-notest) ;
my %seen ;

if ( $format eq 'markdown' ) {
  print "| Module | Version |\n" ;
  print "| --- | --- |\n" ;
}
else {
  printf "%-36s %s\n", 'Module', 'Version' ;
  printf "%-36s %s\n", '-' x 36, '-' x 16 ;
}

for my $file (@files) {
  open my $fh, '<', $file or die "Cannot open $file: $!\n" ;

  while ( my $line = <$fh> ) {
    next if $line     =~ /^\s*#/ ;
    next unless $line =~ /^\s*requires\s+['"]([^'"]+)['"]/ ;

    my $module = $1 ;
    next if $seen{$module}++ ;

    my $metadata = Module::Metadata->new_from_module($module) ;
    my $version  = $metadata ? $metadata->version : undef ;
    $version = 'unknown' unless defined $version && length $version ;
    if ( $format eq 'markdown' ) {
      print "| `$module` | `$version` |\n" ;
    }
    else {
      printf "%-36s %s\n", $module, $version ;
    }
  }
}
