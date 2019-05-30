#!/usr/bin/perl


# Copyright (c) 2005-2019 Colin Pearse.
# All scripts are free in the binscripts repository but please refer to the
# LICENSE file at the top-level directory for the conditions of distribution.
#
# File:         egreptab.pl
# Description:  Display each row found by <expr> over multiple lines with the field
#               name (taken from the header line) on the left hand side. Each row
#               will be separated by two newlines.


our $VERSION = "0.1";

our $Myname = $0; { $Myname =~ s,.*/,,; } # bug in grep means I can't strip dir this outside these brackets

use strict;
use warnings;
no warnings 'uninitialized';

use POSIX;
use Getopt::Std;

########
########
our $InSep="\t";
our $DispSep=":";

########
########
sub usage
{
	our $Myname;
	print STDERR qq{
 usage: $Myname [-iv] [-s sep] [-S sep] <expr> [file [...]]

   -i      Case insensitive <expr>
   -v      Does not match <expr>
   -s sep  Input separator (default: "$InSep")
   -S sep  Separator between field name and value (default: "$DispSep")

 Read input and display each row found by egrep args. Display over multiple lines
 with the field name (taken from the header line, ie. first line of input) on the
 left hand side. Each row will be separated by an empty line.

 egs. readexcel data/aperture_lpars.12-11-29.xls |$Myname -i dcgcgracad25u
      readexcel data/aperture_lpars.12-11-29.xls |$Myname "CTO Unix"
      readexcel data/aperture_lpars.12-11-29.xls |$Myname ".*"

};
	exit 2;
}

###############
###############
sub error
{
	my ($ExitValue, $Format, @Args) = @_;
	our $Myname;
	printf STDERR "$Myname: ERROR: $Format", @Args;
}

###############
###############
sub GetOptions
{
	our ($InSep, $DispSep);
	our %options;
	getopts("ivs:S:h",\%options) or usage;   # -? cannot be specified as an option (as in a shell)
	usage if defined $options{h};
	usage if @ARGV < 1;
	my $CaseInsensitive="";
	my $EqNotEq="=";
	my $Expr="";
	$CaseInsensitive = "i"    if defined $options{i};
	$EqNotEq         = "!"    if defined $options{v};
	$InSep      = $options{s} if defined $options{s};
	$DispSep    = $options{S} if defined $options{S};
	$Expr       = $ARGV[0];
	shift @ARGV;
	return ($CaseInsensitive, $EqNotEq, $Expr, @ARGV);
}

########
########
sub MySplit
{
	my ($Sep, $Str) = @_;
	my @Fields = ($Sep =~ /[\|\[\]\(\)\$\*\.\-]/ ? split(/\Q$Sep\E/, $Str) : split(/$Sep/, $Str));
	chomp @Fields;
	return @Fields;
}

########
########
sub Lines
{
	$_[0] =~ s/./-/g;
	return $_[0];
}

########
########
sub GetMaxWidth
{
	my (@Headers) = @_;
	my $MaxWidth=10;
	foreach my $Header (@Headers)
	{
		$MaxWidth = length $Header if (length $Header > $MaxWidth);
	}
	return $MaxWidth;
}

########
########
sub Main
{
	my ($CaseInsensitive, $EqNotEq, $Expr, @Files) = @_;
	my $Cmd = "cat";
	$Cmd = "cat '".join("' '",@Files)."'" if @Files;
	my @Rows = `$Cmd`;
	my $CmdExit = WEXITSTATUS($?);
	my @Headers = MySplit $InSep, $Rows[0];
	my $MaxWidth = GetMaxWidth @Headers;
	shift @Rows;
	foreach my $Row (@Rows)
	{
		my $Eval = sprintf q#($Row %s~ /$Expr/%s)#, $EqNotEq, $CaseInsensitive;
		if (eval $Eval)
		{
			my @Fields = MySplit($InSep, $Row);
			for (my $i=0 ; $i<@Headers ; $i++)
			{
				printf "%-*.*s%s%s\n", $MaxWidth, $MaxWidth, $Headers[$i], $DispSep, $Fields[$i] if not ($Headers[$i] eq "" && $Fields[$i] eq "");
			}
			printf "\n";
		}
	}
	return $CmdExit;
}

########
########
my ($CaseInsensitive, $EqNotEq, $Expr, @Files) = GetOptions;
exit Main $CaseInsensitive, $EqNotEq, $Expr, @Files;

