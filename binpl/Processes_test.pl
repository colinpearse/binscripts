#!/usr/bin/perl
#!/usr/bin/perl -d

# Copyright (c) 2005-2019 Colin Pearse.
# All scripts are free in the binscripts repository but please refer to the
# LICENSE file at the top-level directory for the conditions of distribution.
#
# File:         Processes_test.pl
# Description:  test Processes.pm


our $VERSION = "0.1";
our $Myname = $0; { $Myname =~ s,.*/,,; } # bug in grep means I can't strip dir this outside these brackets

use strict;
use warnings;
no warnings 'uninitialized';

use Processes;

use Data::Dumper;
use Time::Local;
use Time::HiRes qw(usleep);

#####################
#####################
sub KillAllProcesses
{
	my (%Processes) = @_;
	foreach my $Index (keys %Processes)
	{
		$Processes{$Index}->kill;
		delete $Processes{$Index};
	}
}
sub WaitProcesses
{
	my ($RetType, %Processes) = @_;
	my %AllHashes = ();  # so far only hashes
	while (keys %Processes)
	{
		foreach my $Index (keys %Processes)
		{
			if($Processes{$Index}->is_finished)
			{
				if ($RetType eq "hash")
				{
					my %Hash = $Processes{$Index}->attach;
					$AllHashes{$Index} = \%Hash;
#					AppendRecursiveHash(\%Hash, \%{$AllHashes{$Index}});
				}
				my $ExitValue = $Processes{$Index}->getexit;
				delete $Processes{$Index};
				if ($ExitValue > 0)
				{
					KillAllProcesses %Processes;
					printf STDERR "one of the processes exited with ERROR %s\n", $ExitValue;
					exit $ExitValue;
				}
			}
		}
		usleep rand(100000);  # don't want the wait to use up much cpu
	}
	if ($RetType eq "hash")
	{
		return %AllHashes;
	}
}

###############
###############
sub Test1
{
	my %Find = ();
	$Find{1}{2}{2} = "two";
	$Find{1}{2}{3} = "three";
	return %Find;
}
sub Test2
{
	my ($Cmd) = @_;
	my %Cmds = ();
	$Cmds{output} = `$Cmd`;
	return %Cmds;
}

###############
###############
sub RunProcesses
{
	my %Processes;
	my %Find;

    printf ("TEST 1: create hash in parallel\n");
	$Processes{1} = new Processes "hash", \&Test1;
	$Processes{2} = new Processes "hash", \&Test1;
	%Find = WaitProcesses "hash", %Processes;
	print Dumper \%Find;

    printf ("\nTEST 2: run commands in parallel\n");
	$Processes{1} = new Processes "hash", \&Test2, "sleep 2 && uname -a 2>&1";
	$Processes{2} = new Processes "hash", \&Test2, "sleep 2 && id 2>&1";
	$Processes{3} = new Processes "hash", \&Test2, "sleep 2 && ls -ld . 2>&1";
	$Processes{4} = new Processes "hash", \&Test2, "sleep 2 && ls -ld notexist 2>&1";
	%Find = WaitProcesses "hash", %Processes;
	print Dumper \%Find;
}

RunProcesses;


