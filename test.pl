#!/usr/bin/env perl

use strict ;
use warnings ;

# Backward-compatible entry point for the image smoke test.
exec $^X, 'scripts/smoke-test.pl', 'cpanfile', 'cpanfile-notest'
  or die "Cannot run smoke test: $!\n" ;
