#!/usr/bin/perl
#!/usr/bin/perl -d

# Copyright (c) 2005-2019 Colin Pearse.
# All scripts are free in the binscripts repository but please refer to the
# LICENSE file at the top-level directory for the conditions of distribution.
#
# Name:         Verbose_test.pl
# Description:  test Verbose.pm


our $VERSION = "0.1";
our $Myname = $0; { $Myname =~ s,.*/,,; } # bug in grep means I can't strip dir this outside these brackets

use strict;
use warnings;
no warnings 'uninitialized';

use Verbose;


###############
###############
# Functions: setVerbosity, verbose_nonl, verbose_nl, verbose, verbose_head, verbose_arr
sub RunTests
{
    print STDERR "Test 1\n";
    Verbose::setVerbosity "2,sys,debug";
    Verbose::verbose 2,       "message%d", 1;
    Verbose::verbose 3,       "message%d", 2;
    Verbose::verbose "3,sys", "message%d", 3;
    Verbose::verbose "sys",   "message%d", 4;
    Verbose::verbose 0, "only messages 1, 3, 4";

    print STDERR "\nTest 2\n";
    Verbose::setVerbosity "0,onlythis";
    Verbose::verbose 2,       "message%d", 1;
    Verbose::verbose 3,       "message%d", 2;
    Verbose::verbose "3,sys", "message%d", 3;
    Verbose::verbose "sys",   "message%d", 4;
    Verbose::verbose "debug", "message%d", 5;
    Verbose::verbose 0, "only message 5";

    my @myarr = ("one", "two", "three");
    print STDERR "\nTest 3\n";
    Verbose::setVerbosity "1";
    Verbose::verbose_arr 1, "myarr", @myarr;
}

RunTests;


