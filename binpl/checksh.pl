#!/usr/bin/perl


# Copyright (c) 2005-2019 Colin Pearse.
# All scripts are free in the binscripts repository but please refer to the
# LICENSE file at the top-level directory for the conditions of distribution.
#
# Name:        checksh.pl
# Description: Perform basic variable checks on shell script.


our $VERSION = "0.1";

use strict;
use Getopt::Std;

our %options = ();

#########
#########
sub usage
{
	$0 =~ s,.*/,,;
	print STDERR qq{
usage: $0 [-ect] <shell script> [shell script [...]]

 -e   don't include exceptions (\$0-\$9, \$NF, \$OPTIND, \$OPTARG, \$ARGV)
 -c   check comments too (normally they are excluded)
 -t   process files together as if they were one script (for include environment files)

 Checks that variables are set in korn/bash script. Good for checking typos.

 Note that it will (incorrectly) raise an exception with the following:
 - Variables set outside of the script.
 - Variables in embedded perl, ie. perl -le '... \$var ...'
 - Arrays that have not been set by set -A directive, ie. \${arr[\$i]}="val"
 
};
	exit 2;
}

##############
##############
sub isinarray
{
	my ($f, @a) = @_;
	foreach (@a)
	{
		if ($f eq $_)
		{
			return 1;
		}
	}
	return 0;
}

################
################
sub getContents
{
	my (@Files) = @_;
	my $Contents = "";
	foreach my $File (@Files)
	{
		$Contents .= `cat $File`;
	}
	return $Contents;
}

############
############
# Extract variables from the string passed
sub getvars
{
	my ($Contents) = @_;
	our %options;

	unless ($options{c})
	{
		$Contents = "\n$Contents\n";       # Ensure a \n at start and end
		$Contents =~ s/[^'\\A-Za-z0-9_]#[^\n]*//g;   # remove comments
	}

	# Contents=" $var1, $var2;string$var3, ${var4} other chars"
	# becomes: "var1,var2,var3,var4"

	$Contents =~ s/\$\(/ /g;                        # remove $(
	$Contents =~ s/\$\{/\$/g; $Contents =~ tr/\}/,/;  # convert ${var} to $var,
	$Contents =~ tr/\n/ /;                          # convert \ns to blanks
	$Contents =~ s/\$(\w+)/\n\1\n/g;              # convert $var to \n<bell>var\n
	$Contents = "\n$Contents\n";                    # Ensure a \n at start and end
	$Contents =~ s/\n[^]+\n/\n/g;                 # blank out ^<not bell>... lines
	$Contents =~ s/\n(\w+)/\1,/g;                 # isolate words between <bell> and <non alphanum>
	$Contents =~ s/[\r\n]//g;                       # strip out spurious \r or \ns

	my @Vars = split (',', $Contents);
	my @UniqVars;

	foreach(sort @Vars)
	{
		if ($_ !~ /^$/)
		{
			push @UniqVars, $_ unless isinarray $_, @UniqVars;
		}
	}

	return @UniqVars;
}

############
############
sub checksh
{
	my ($Label, $Contents, @Variables) = @_;
	our %options;

	foreach(@Variables)
	{
		if ($Contents !~ /\b$_=/)
		{
			# skip if variable set by set -A <var>
			# skip if variable set by getopts "..." <var>
			# skip if variable set by for <var> in
			# skip if variable set by read ... <var>
			# skip if exception option used + var is one of the exceptions
			next if ($Contents =~ /\bset[ \t]+-A[ \t]+$_\b/);
			next if ($Contents =~ /\bgetopts[ \t]+[^ ]+ $_\b/);
			next if ($Contents =~ /\bfor[ \t]+$_[ \t]+in\b/);
			next if ($Contents =~ /\bread[ \t]+[\w \t]*\b$_\b/);
			next if ($options{e} && ($_=~/^[0-9]$/ || $_ eq "NF" || $_ eq "OPTARG" || $_ eq "OPTIND" || $_ eq "ARGV") );
			printf "%s: %s\n", $Label, $_;
		}
	}
}

#################
#################
sub checkfuncs
{
	my (@Files) = @_;
	my $Label = (scalar @Files == 1 ? $Files[0] : "all scripts");
	my $Cmd = sprintf q#egrep '^[A-Za-z]*\(\)' %s |sed 's/().*//1' |sort |uniq -d#, join(' ',@Files);
	my @DupFunctions = `$Cmd`;
	foreach (@DupFunctions)
	{
		chomp $_;
		printf "%s: duplicate function: %s()\n", $Label, $_;
	}
}

########
########
sub Main
{
	my (@Files) = @_;
	our %options;

	if ($options{t})
	{
		my $Contents = getContents @Files;
		my @Variables = getvars $Contents;
		checksh "all scripts", $Contents, @Variables;
		checkfuncs @Files;
	}
	else
	{
		foreach my $File (@Files)
		{
			my $Contents = getContents $File;
			my @Variables = getvars $Contents;
			checksh $File, $Contents, @Variables;
			checkfuncs $File;
		}
	}
}

########
########
getopts("ecth:",\%options) or usage;   # ? cannot be specified
usage unless defined $ARGV[0];
Main @ARGV;
exit 0;


