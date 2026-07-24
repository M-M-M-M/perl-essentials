#!/usr/bin/env perl

use strict ;
use warnings ;

use Getopt::Long qw(GetOptions) ;
use HTTP::Tiny ;
use JSON::PP qw(decode_json) ;

my $file       = 'DOCKERHUB.md' ;
my $namespace  = $ENV{DOCKERHUB_USERNAME} || 'perlessentials' ;
my $repository = 'perl-essentials' ;
my $dry_run ;

GetOptions(
  'file=s'       => \$file,
  'namespace=s'  => \$namespace,
  'repository=s' => \$repository,
  'dry-run'      => \$dry_run,
) or die usage() ;

_validate_path_segment( 'namespace',  $namespace ) ;
_validate_path_segment( 'repository', $repository ) ;

my $description = _read_text($file) ;
my $length      = length $description ;
die "Docker Hub full_description from $file is empty\n"
  if $length == 0 ;
die "$file exceeds Docker Hub full_description limit: $length > 25000\n"
  if $length > 25_000 ;

if ($dry_run) {
  print "DRY-RUN: would update Docker Hub repository "
    . "$namespace/$repository from $file ($length characters)\n" ;
  exit 0 ;
}

my $username = $ENV{DOCKERHUB_USERNAME} // q{} ;
my $secret   = $ENV{DOCKERHUB_TOKEN}    // q{} ;
die "DOCKERHUB_USERNAME must be set\n" if $username eq q{} ;
die "DOCKERHUB_TOKEN must be set\n"    if $secret eq q{} ;

my $http = HTTP::Tiny->new(
  agent   => 'perl-essentials-dockerhub-description/1.0',
  timeout => 30,
) ;
my $json = JSON::PP->new->utf8->canonical ;

my $access_token = _create_access_token( $http, $json, $username, $secret ) ;
my $repository_data
  = _get_repository( $http, $json, $access_token, $namespace, $repository ) ;
_patch_description(
  $http,        $json, $access_token, $namespace, $repository,
  $description, $repository_data->{description}
) ;

print "Updated Docker Hub description for $namespace/$repository from $file\n" ;
exit 0 ;

sub _create_access_token {
  my ( $http, $json, $identifier, $secret ) = @_ ;
  my $response = _request(
    $http,
    'POST',
    'https://hub.docker.com/v2/auth/token',
    {
      'Content-Type' => 'application/json',
      'Accept'       => 'application/json',
    },
    $json->encode( {
        identifier => $identifier,
        secret     => $secret,
    } ),
    'Docker Hub authentication',
  ) ;
  my $data  = _decode_json_response( $json, $response, 'Docker Hub authentication' ) ;
  my $token = $data->{access_token} // $data->{token} // q{} ;
  die "Docker Hub authentication response did not include an access token\n"
    if $token eq q{} ;
  return $token ;
}

sub _get_repository {
  my ( $http, $json, $access_token, $namespace, $repository ) = @_ ;
  my $response = _request(
    $http,
    'GET',
    "https://hub.docker.com/v2/namespaces/$namespace/repositories/$repository",
    _bearer_headers($access_token),
    undef,
    'Docker Hub repository lookup',
  ) ;
  return _decode_json_response( $json, $response, 'Docker Hub repository lookup' ) ;
}

sub _patch_description {
  my ( $http, $json, $access_token, $namespace, $repository, $full_description,
    $short_description )
    = @_ ;

  my %body = ( full_description => $full_description ) ;
  $body{description} = $short_description
    if defined $short_description && $short_description ne q{} ;

  _request(
    $http,
    'PATCH',
    "https://hub.docker.com/v2/repositories/$namespace/$repository/",
    {
      %{ _bearer_headers($access_token) },
      'Content-Type' => 'application/json',
    },
    $json->encode( \%body ),
    'Docker Hub description update',
  ) ;
  return ;
}

sub _request {
  my ( $http, $method, $url, $headers, $content, $context ) = @_ ;
  my %options = ( headers => $headers || {} ) ;
  $options{content} = $content if defined $content ;

  my $response = $http->request( $method, $url, \%options ) ;
  return $response if $response->{success} ;

  my $status  = $response->{status}  // 599 ;
  my $reason  = $response->{reason}  // 'Unknown error' ;
  my $details = $response->{content} // q{} ;
  my $message = "$context failed ($status $reason): $url" ;
  $message .= "\n$details" if $details ne q{} ;
  die "$message\n" ;
}

sub _decode_json_response {
  my ( $json, $response, $context ) = @_ ;
  my $content = $response->{content} // q{} ;
  my $data    = eval { $json->decode($content)  } ;
  die "$context returned invalid JSON\n" if $@ || ref $data ne 'HASH' ;
  return $data ;
}

sub _bearer_headers {
  my ($access_token) = @_ ;
  return {
    'Authorization' => "Bearer $access_token",
    'Accept'        => 'application/json',
  } ;
}

sub _read_text {
  my ($path) = @_ ;
  open my $fh, '<:encoding(UTF-8)', $path
    or die "Cannot read $path: $!\n" ;
  local $/ ;
  my $content = <$fh> ;
  close $fh or die "Cannot close $path: $!\n" ;
  return $content // q{} ;
}

sub _validate_path_segment {
  my ( $label, $value ) = @_ ;
  die "$label must not be empty\n" if !defined $value || $value eq q{} ;
  die "Invalid Docker Hub $label: $value\n"
    unless $value =~ /\A[A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)*\z/ ;
  return ;
}

sub usage {
  return "Usage: $0 [--file DOCKERHUB.md] [--namespace NAME]"
    . " [--repository NAME] [--dry-run]\n" ;
}
