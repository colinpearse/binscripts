#!/usr/bin/perl

# File:        colcat.pl
# Description: Concatenate two files or more sideways sideways, in multiple columns.

our $VERSION = "0.1";

our $Myname = $0; { $Myname =~ s,.*/,,; } # bug in grep means I can't strip dir this outside these brackets

use strict;
use warnings;
use Getopt::Std;

my %options=();
my $Separator = "\t";
my $LimitWidth = 0;

my @Rows;
my @Cols;
my @MaxLengths;
my $MaxCol;

###########
###########
sub usage
{
	our $Myname;

	print STDERR qq{
 usage: $Myname [-s <sep>] [-w] <file1> <file2> [file3 [...]]

 -s sep  Output separator (default is "$Separator")
 -w      Limit display to screen width (each file gets half/third/quarter the screen depending on number of files)

 Concatenate two files or more sideways sideways, in multiple columns.

};
	exit 2
}
sub error
{
	my ($ExitValue, $Format, @Args) = @_;
	printf STDERR "$Format\n", @Args;
	exit $ExitValue;
}
###########
###########
getopts("s:w",\%options) or usage;  # -? cannot be specified as an option (as in a shell)
$LimitWidth = 1           if defined $options{w};
$Separator  = $options{s} if defined $options{s};
$Separator  = `printf "$Separator"`;  # got to be a better way to do this, but sprintf didn't work
my $MaxArgs = @ARGV;

###########
###########
# TTY
my $TtyCols = 0;
my $ColSize = 0;
if ($LimitWidth)
{
	$TtyCols=`stty -a |grep columns`;
	chomp $TtyCols;
	$TtyCols =~ s/.* (\d+) columns.*/$1/;
	$ColSize = ($TtyCols / $MaxArgs) - 1;
}

###########
###########
# Read files
usage if (!defined $ARGV[0] || !defined $ARGV[1]); # at least two files
my @Lines;
my $MaxLine = 0;
for(my $f=0 ; $f < $MaxArgs ; $f++)
{
	error 1, "%s does not exist or is not readable", $ARGV[$f] if not -r $ARGV[$f];
	@{$Lines[$f]} = `cat $ARGV[$f]`;
	$MaxLine = @{$Lines[$f]} if @{$Lines[$f]} > $MaxLine;
	chomp @{$Lines[$f]};
}

###########
###########
# Output
error 1, "Bad column size %d =  %d columns / %d arguments\n", $ColSize, $TtyCols, $MaxArgs if $ColSize < 0;
for (my $i=0 ; $i<$MaxLine ; $i++)
{
	for(my $f=0 ; $f < $MaxArgs ; $f++)
	{
		next if not defined ${$Lines[$f]}[$i];
		chomp ${$Lines[$f]}[$i];
		${$Lines[$f]}[$i] =~ s/[\n\r]//;
		if ($ColSize)
		{
			printf "%-*.*s%s", $ColSize, $ColSize, ${$Lines[$f]}[$i], $Separator;
		}
		else
		{
			printf "%s%s", ${$Lines[$f]}[$i], $Separator;
		}
	}
	printf "\n";
}
exit 0;


