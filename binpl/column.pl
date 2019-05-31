#!/usr/bin/perl


# Copyright (c) 2005-2019 Colin Pearse.
# All scripts are free in the binscripts repository but please refer to the
# LICENSE file at the top-level directory for the conditions of distribution.
#
# File:        column.pl
# Description: Mimic column command on Linux


our $VERSION = "1.0";

our $Myname = $0; { $Myname =~ s,.*/,,; } # bug in grep means I can't strip dir this outside these brackets

use strict;
use warnings;
no warnings 'uninitialized';

use Getopt::Std;

###############
###############
sub usage
{
	our $Myname;
	print STDERR qq{
 usage: $Myname [-s sep] [-S sep] [-C cols] [-F cols]

 -s sep   Input separator (default is white space)
 -S sep   Output separator (default is a space)
 -C cols  Convert input and display in <cols> columns
 -F cols  Format only first <cols> columns

 egs. cat file.csv |$Myname -s,
      cat list.txt |$Myname -C3 -S' | '

};
	exit 2;
}

###############
###############
sub GetOptions
{
	our %options;
	getopts("s:S:C:F:h",\%options) or usage;   # -? cannot be specified as an option (as in a shell)
	usage if defined $options{h};
	my $InputSeparator = '\s+';   # white space
	my $OutputSeparator = ' ';
	my $MakeCols = 0;
	my $FirstCols = 0;
	my $InputType;
	$InputSeparator  = $options{s} if defined $options{s};
	$OutputSeparator = $options{S} if defined $options{S};
	$MakeCols        = $options{C} if defined $options{C};
	$FirstCols       = $options{F} if defined $options{F};
	return ($InputSeparator, $OutputSeparator, $MakeCols, $FirstCols, $InputType);
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

#################
#################
sub GetMaxLengths
{
	my ($InputSeparator, $FirstCols, @Rows) = @_;
	my @MaxLengths;
	foreach(@Rows)
	{
		my @Cols = MySplit $InputSeparator, $_;
		my $MaxCol = @Cols;
		for (my $i=0 ; $i<$MaxCol ; $i++)
		{
			my $MaxLength = $MaxLengths[$i];
			my $Length = length($Cols[$i]);
			$MaxLengths[$i] = $Length unless (defined $MaxLength && $MaxLength >= $Length);
			$MaxLengths[$i] = 1 if ($FirstCols && $i >= $FirstCols);
		}
	}
	return @MaxLengths;
}

###############
###############
sub DisplayRows
{
	my ($InputSeparator, $OutputSeparator, $MaxLengths, @Rows) = @_;
	foreach(@Rows)
	{
		my @Cols = MySplit $InputSeparator, $_;
		my $MaxCol = @Cols;
		for (my $i=0 ; $i<$MaxCol ; $i++)
		{
			printf "%-*s%s", @{$MaxLengths}[$i], $Cols[$i], (($i+1 < $MaxCol) ? $OutputSeparator : ""); # don't separator after final column
		}
		print "\n";
	}
}

###############
###############
sub ReadInput
{
	my ($InputSeparator, $InputType) = @_;
	my @Rows;
	while(<STDIN>)
	{
		chomp $_;
		$_ =~ s/[\n\r]//;
		push @Rows, $_;
	}
	return @Rows;
}

###############
###############
sub GetMaxDisplayCols
{
	my $MaxDisplayCols=`stty -a 2>/dev/null |grep column |head -1`;
	$MaxDisplayCols =~ s/.*[^\d]+(\d+) column.*/$1/;
	return $MaxDisplayCols =~ /^\d+$/ ? $MaxDisplayCols : 0;
}

###############
###############
sub MakeColumns
{
	my ($MakeCols, $FirstCols, $OutputSeparator) = @_;
	my @Rows = ReadInput "", "";
	my $NewRowsQty = @Rows / $MakeCols;
	my @NewRows = ();
	my $InputSeparator = "<separator>";
	my $i=0;
	for(my $x=0 ; $x<$MakeCols ; $x++)
	{
		for(my $y=0 ; $y<$NewRowsQty ; $y++)
		{
			$NewRows[$y] .= $Rows[$i++];
			$NewRows[$y] .= $InputSeparator;
		}
	}
	my @MaxLengths = GetMaxLengths $InputSeparator, $FirstCols, @NewRows;
	DisplayRows $InputSeparator, $OutputSeparator, \@MaxLengths, @NewRows;
}

###############
###############
sub Column
{
	my ($InputSeparator, $OutputSeparator, $FirstCols, $InputType) = @_;
	my @Rows = ReadInput $InputSeparator, $InputType;
	my @MaxLengths = GetMaxLengths $InputSeparator, $FirstCols, @Rows;
	DisplayRows $InputSeparator, $OutputSeparator, \@MaxLengths, @Rows;
}

###############
###############
sub Main
{
	my ($InputSeparator, $OutputSeparator, $MakeCols, $FirstCols, $InputType) = @_;
	if ($MakeCols) # turn list into columns
	{
		MakeColumns $MakeCols, $FirstCols, $OutputSeparator;
	}
	else # turn csv into equally spaces columns
	{
		Column $InputSeparator, $OutputSeparator, $FirstCols, $InputType;
	}
}

###############
###############
my ($InputSeparator, $OutputSeparator, $MakeCols, $FirstCols, $InputType) = GetOptions;
Main $InputSeparator, $OutputSeparator, $MakeCols, $FirstCols, $InputType;
