#!/usr/bin/env perl

use strict ;
use warnings ;

my ( $tested_file, $notest_file ) = @ARGV ;
die "Usage: $0 CPANFILE CPANFILE_NOTEST\n"
  unless defined $tested_file && defined $notest_file ;

my @tested = read_modules($tested_file) ;
my @notest = read_modules($notest_file) ;
my %tested = map { $_ => 1 } @tested ;
my @errors ;

push @errors, "$tested_file is not alphabetically sorted"
  unless join( "\0", @tested ) eq join( "\0", sort @tested ) ;
push @errors, "$notest_file is not alphabetically sorted"
  unless join( "\0", @notest ) eq join( "\0", sort @notest ) ;

my %seen ;
for my $module ( @tested, @notest ) {
  push @errors, "$module is declared more than once" if $seen{$module}++ ;
}

for my $module (@notest) {
  push @errors, "$module is present in both manifests" if $tested{$module} ;
}

if (@errors) {
  die join( "\n", map {"ERROR: $_"} @errors ) . "\n" ;
}

print "Manifest check passed: "
  . scalar(@tested)
  . " tested modules, "
  . scalar(@notest)
  . " test exceptions.\n" ;

sub read_modules {
  my ($path) = @_ ;
  my @modules ;

  open my $fh, '<', $path or die "Cannot open $path: $!\n" ;
  while ( my $line = <$fh> ) {
    next if $line =~ /^\s*#/ ;
    push @modules, $1 if $line =~ /^\s*requires\s+['"]([^'"]+)['"]/ ;
  }

  return @modules ;
}
