#!/usr/bin/env perl

use strict ;
use warnings ;

my @files = @ARGV ? @ARGV : tracked_perl_files() ;
my @failed ;

for my $file (@files) {
  open my $source, '<', $file
    or die "Cannot open $file: $!\n" ;
  local $/ ;
  my $original = <$source> ;
  close $source or die "Cannot close $file: $!\n" ;

  open my $perltidy, '-|',
    'perltidy',
    '-pro=.perltidyrc',
    '-st',
    '-se',
    $file
    or die "Cannot run perltidy for $file: $!\n" ;
  my $formatted = <$perltidy> ;
  my $status    = close $perltidy ;

  if ( !$status || $original ne $formatted ) {
    push @failed, $file ;
    print STDERR "Formatting differs: $file\n" ;
  }
}

die "Perl formatting check failed\n" if @failed ;
print "Perl formatting check passed for " . scalar(@files) . " files.\n" ;

sub tracked_perl_files {
  open my $git, '-|',
    'git', 'ls-files', '--cached', '--others', '--exclude-standard',
    '-z',  '--',       '*.pl',     '*.pm',     '*.t'
    or die "Cannot list tracked Perl files: $!\n" ;

  local $/ = "\0" ;
  my @files = grep {length} map { chomp ; $_ } <$git> ;
  close $git or die "Cannot list tracked Perl files\n" ;

  return @files ;
}
