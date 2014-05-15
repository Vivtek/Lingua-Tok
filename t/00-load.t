#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'Lingua::Tok' ) || print "Bail out!\n";
}

diag( "Testing Lingua::Tok $Lingua::Tok::VERSION, Perl $], $^X" );
