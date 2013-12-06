#!/usr/bin/perl -w
# Standard preamble
use strict;

BEGIN { unshift @INC, split( /:/, $ENV{FOSWIKI_LIBS} ); }

use Foswiki::Contrib::Build;

my $build = new Foswiki::Contrib::Build('SignHerePlugin');
$build->build( $build->{target} );

