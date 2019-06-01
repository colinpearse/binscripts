#!/usr/bin/perl
#!/usr/bin/perl -d

# Copyright (c) 2005-2019 Colin Pearse.
# All scripts are free in the binscripts repository but please refer to the
# LICENSE file at the top-level directory for the conditions of distribution.
#
# Name:         HashTree_test.pl
# Description:  test HashTree.pm


our $VERSION = "0.1";
our $Myname = $0; { $Myname =~ s,.*/,,; } # bug in grep means I can't strip dir this outside these brackets

use strict;
use warnings;
no warnings 'uninitialized';

use HashTree;


###############
###############
# PrintRecursiveHashShort(Debug), FillRecursiveHashShort, PrintRecursiveHashLong(Debug), FillRecursiveHashLong
sub RunTests
{
	my %Find = ();
	$Find{1}{2}{2} = "two";
	$Find{1}{2}{3} = "three";
	$Find{1}{2}{4} = "four";
	$Find{2}{1}{1} = "etc";
	$Find{2}{1}{2} = "etc";

    printf("Test1 HashTree::PrintRecursiveHashLongDebug\n");
	HashTree::PrintRecursiveHashLongDebug(%Find);

    printf("\nTest2 HashTree::PrintRecursiveHashShortDebug\n");
	HashTree::PrintRecursiveHashShortDebug(%Find);
}

RunTests;


