#!/usr/bin/env perl

use strict ;
use warnings ;

use DBI ;

my $dsn = $ENV{TEST_PG_DSN} ;

if ( !defined $dsn || $dsn eq '' ) {
  print "SKIP: set TEST_PG_DSN to run the PostgreSQL integration test.\n" ;
  exit 0 ;
}

my $dbh = DBI->connect(
  $dsn,
  $ENV{TEST_PG_USER}     // '',
  $ENV{TEST_PG_PASSWORD} // '',
  {
    RaiseError         => 1,
    PrintError         => 0,
    ShowErrorStatement => 1,
  },
) ;

my ($result) = $dbh->selectrow_array('SELECT 1') ;
die "Unexpected PostgreSQL result\n" unless defined $result && $result == 1 ;

$dbh->disconnect ;
print "PostgreSQL integration test passed.\n" ;
