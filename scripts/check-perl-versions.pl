#!/usr/bin/env perl

use strict ;
use warnings ;

use Getopt::Long qw(GetOptions) ;
use HTTP::Tiny ;
use JSON::PP qw(decode_json) ;

my $check ;
my $tags_file ;
my $config      = 'perl-versions.conf' ;
my $check_drift = 1 ;

GetOptions(
  'check'       => \$check,
  'tags-file=s' => \$tags_file,
  'config=s'    => \$config,
  'no-drift'    => sub { $check_drift = 0  },
) or die usage() ;

my @configured = read_config($config) ;
my @tags       = defined $tags_file
  ? read_tags_file($tags_file)
  : fetch_tags( map { $_->{series} } @configured ) ;

my %available ;
for my $tag (@tags) {
  next unless $tag =~ /\A(\d+\.\d+)\.(\d+)-threaded\z/ ;
  my ( $series, $patch ) = ( $1, $2 ) ;
  my $version = "$series.$patch" ;
  $available{$series} = $version
    if !defined $available{$series}
    || version_cmp( $version, $available{$series} ) > 0 ;
}

my @proposals ;
for my $entry (@configured) {
  my $latest = $available{ $entry->{series} } ;
  if ( !defined $latest ) {
    push @proposals, "WARNING: no official threaded tag found for $entry->{series}" ;
    next ;
  }

  if ( version_cmp( $latest, $entry->{version} ) > 0 ) {
    push @proposals, "UPDATE: $entry->{version} -> $latest ($entry->{role})" ;
  }
  else {
    print "CURRENT: $entry->{version} ($entry->{role})\n" ;
  }
}

my ( $major, $minor ) = split /\./, $configured[-1]{series} ;
my $next_series = $major . '.' . ( $minor + 1 ) ;
if ( my $next = $available{$next_series} ) {
  push @proposals, "ADD: $next ($next_series is the next Perl series)" ;
}

if ($check_drift) {
  my @drift = check_repository_drift(@configured) ;
  push @proposals, map {"DRIFT: $_"} @drift ;
}

print "$_\n" for @proposals ;
exit 1 if $check && @proposals ;
exit 0 ;

sub read_config {
  my ($path) = @_ ;
  my @entries ;

  open my $fh, '<', $path or die "Cannot open $path: $!\n" ;
  while ( my $line = <$fh> ) {
    chomp $line ;
    next if $line =~ /\A\s*(?:#|\z)/ ;
    my ( $version, $role, $purpose ) = split /\|/, $line, 3 ;
    die "Invalid version entry: $line\n"
      unless defined $purpose
      && $version =~ /\A\d+\.\d+\.\d+\z/
      && $role    =~ /\A(?:legacy|stable|development)\z/ ;
    my ($series) = $version =~ /\A(\d+\.\d+)\./ ;
    push @entries, {
      version => $version,
      series  => $series,
      role    => $role,
      purpose => $purpose,
    } ;
  }

  die "$path contains no versions\n" unless @entries ;
  return @entries ;
}

sub read_tags_file {
  my ($path) = @_ ;
  open my $fh, '<', $path or die "Cannot open $path: $!\n" ;
  return map { chomp ; $_ } grep {/\S/} <$fh> ;
}

sub fetch_tags {
  my (@series) = @_ ;
  my ( $major, $minor ) = split /\./, $series[-1] ;
  push @series, $major . '.' . ( $minor + 1 ) ;

  my $http = HTTP::Tiny->new(
    agent   => 'perl-essentials-version-check/1.0',
    timeout => 30,
  ) ;
  my @tags ;

  for my $series (@series) {
    my $url = 'https://hub.docker.com/v2/repositories/library/perl/tags'
      . "?page_size=100&name=$series." ;

    while ( defined $url && length $url ) {
      my $response = $http->get($url) ;
      die "Docker Hub request failed ($response->{status}): $url\n"
        unless $response->{success} ;
      my $data = decode_json( $response->{content} ) ;
      push @tags, map { $_->{name} } @{ $data->{results} || [] } ;
      $url = $data->{next} ;
    }
  }

  return @tags ;
}

sub check_repository_drift {
  my (@entries) = @_ ;
  my @files = (
    'README.md',
    'bitbucket-pipelines.yml',
    '.github/workflows/ci.yml',
  ) ;
  my @errors ;

  for my $entry (@entries) {
    for my $file (@files) {
      open my $fh, '<', $file or do {
        push @errors, "cannot read $file" ;
        next ;
      } ;
      local $/ ;
      my $content = <$fh> ;
      push @errors, "$entry->{version} is missing from $file"
        unless index( $content, $entry->{version} ) >= 0 ;
    }
  }

  my $default = $entries[-1]{version} ;
  open my $dockerfile, '<', 'Dockerfile'
    or return ( @errors, 'cannot read Dockerfile default' ) ;
  my $first = <$dockerfile> // '' ;
  push @errors, "Dockerfile default is not $default"
    unless $first =~ /\AARG PERL_VERSION=\Q$default\E\s*\z/ ;

  return @errors ;
}

sub version_cmp {
  my ( $left, $right ) = @_ ;
  my @left  = split /\./, $left ;
  my @right = split /\./, $right ;
  for my $index ( 0 .. 2 ) {
    my $cmp = $left[$index] <=> $right[$index] ;
    return $cmp if $cmp ;
  }
  return 0 ;
}

sub usage {
  return "Usage: $0 [--check] [--no-drift] [--tags-file FILE] [--config FILE]\n" ;
}
