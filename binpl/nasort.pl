#!/usr/bin/perl
#!/usr/bin/perl -d


# Copyright (c) 2005-2019 Colin Pearse.
# All scripts are free in the binscripts repository but please refer to the
# LICENSE file at the top-level directory for the conditions of distribution.
#
# Name:         nasort.pl
# Description:  A Numerical-alpha sort where "str9" comes before "str10"
#               (as opposed to alphanumerically where numbers are treated like letters)


our $VERSION = "1.1";

our $Myname = $0; { $Myname =~ s,.*/,,; } # bug in grep means I can't strip dir this outside these brackets

use strict;
use warnings;
no warnings 'uninitialized';

use Getopt::Std;
use POSIX qw(:sys_wait_h);   # for signal defs

###############
###############
sub usage
{
	our $Myname;
	print STDERR qq{
 usage: $Myname [-k keys] [-u] [-i] [-r] [-s sep]

 -k    Keys to sort by separated by a comma; maximum 5 keys allows
 -u    Show unique lines only
 -i    Case insensitive sort
 -r    Reverse order
 -s    Separator to be processed as follows: split(/<sep>/, <line>)
       default is white space, ie: -s'[ \\t]+'

 Numerical-alpha sort.

 This is a specialised alphanumerical sort script where emphasis is placed on
 numerical values within the string. For example "str9" is sorted before "str10"
 which does not happen with a standard alphanumeric sort.

 Please note that as this conflicts with the standard alphanumerical sort trying to sort
 hexadecimal (for example) with this script will not yield useful results.

 cat file.csv |$Myname -s, -k2

};
	exit 2;
}

###############
###############
sub error
{
	my ($ExitValue, $Format, @Args) = @_;
	our ($Myname);
	printf STDERR "$Myname: ERROR: $Format", @Args;
	exit $ExitValue;
}

################
################
sub GetOptions
{
	my %options = ();
	getopts("k:uirs:t:",\%options) or usage;   # -? cannot be specified as an option (as in a shell)
	usage if defined $options{h};
	my $CaseInsensitive = 0;
	my $ReverseOrder    = 0;
	my $ShowUnique      = 0;
	my $Keys            = "";
	my $Separator       = '[ \t]+';   # white space
	$CaseInsensitive = 1           if defined $options{i};
	$ReverseOrder    = 1           if defined $options{r};
	$ShowUnique      = 1           if defined $options{u};
	$Keys            = $options{k} if defined $options{k};
	$Separator       = $options{s} if defined $options{s};
	usage if $Keys !~ /^[\d\,]*$/;
	error 2, "Maxmum 5 keys allowed with -k" if $Keys =~ /,.*,.*,.*,.*,/;
	return ($CaseInsensitive, $ReverseOrder, $ShowUnique, $Keys, $Separator);
}

#############
#############
# standard case-sensititve function for: sort { &NumInAlphaCompare } @arr
sub NumInAlphaCompare
{
	my ($s1, $s2) = ($a, $b);
	my ($f1, $f2) = ($a, $b);
	$f1 =~ s/(\d+)/%010d/g;
	$f2 =~ s/(\d+)/%010d/g;
	my (@a1, @a2);
	while ($s1 =~ /(\d+)/gs) { push @a1, $1; }
	while ($s2 =~ /(\d+)/gs) { push @a2, $1; }
	$s1 = sprintf $f1, @a1;
	$s2 = sprintf $f2, @a2;
	$s1 cmp $s2;
}

#############
#############
# This sorts alphanumerically but ensures that numbers within the string
# are sorted numerically, eg. aa9 comes before aa10
sub NumInAlphaCompareKey
{
	my ($CaseInsensitive, $Key, %Rows) = @_;
	my ($s1, $s2) = ($Rows{$Key}{$a}, $Rows{$Key}{$b});
	my ($f1, $f2) = ($Rows{$Key}{$a}, $Rows{$Key}{$b});
	my $max_numlen = 10; # max number of digits found in both strings
	while ($s1 =~ /(\d+)/gs) { $max_numlen = length($1) if length($1) > $max_numlen; }
	while ($s2 =~ /(\d+)/gs) { $max_numlen = length($1) if length($1) > $max_numlen; }
	$max_numlen++;
	$f1 =~ s/(\d+)/%0${max_numlen}s/g;  # NOTE: printf "%020d", <num> gives -1 for large numbers
	$f2 =~ s/(\d+)/%0${max_numlen}s/g;  #       printf "%020s", <num> works ok
	my (@a1, @a2);
	while ($s1 =~ /(\d+)/gs) { push @a1, $1; }
	while ($s2 =~ /(\d+)/gs) { push @a2, $1; }
	$s1 = sprintf $f1, @a1;
	$s2 = sprintf $f2, @a2;
	if ($CaseInsensitive)
	{
		lc $s1 cmp lc $s2;
	}
	else
	{
	   $s1 cmp $s2;
	}
}

###############
###############
sub inarray
{
	my ($f, @a) = @_;
	foreach my $af (@a)
	{
		if ($f eq $af)
		{
			return 1;
		}
	}
	return 0;
}

###############
###############
sub ReadInput
{
	my ($Rows, $Separator) = @_;
	my $Line;
	for(my $row=1; $Line=<STDIN> ; $row++)
	{
		chomp $Line;
		$Line =~ s/[\n\r]//;
		my @Cols = split(/$Separator/, $Line);
		$Rows->{Data}{$row} = $Line;
		for(my $col=1; $col<=@Cols ; $col++)
		{
			$Rows->{$col}{$row} = $Cols[$col-1];
		}
	}
}

###############
###############
sub Sort
{
	my ($CaseInsensitive, $ReverseOrder, $ShowUnique, $Keys, $Separator, %Rows) = @_;
	my @rows;
	my ($Key1, $Key2, $Key3, $Key4, $Key5) = split(',', $Keys);
	@rows = sort { &NumInAlphaCompareKey($CaseInsensitive, $Key1,  %Rows) 
				|| &NumInAlphaCompareKey($CaseInsensitive, $Key2,  %Rows)
				|| &NumInAlphaCompareKey($CaseInsensitive, $Key3,  %Rows)
				|| &NumInAlphaCompareKey($CaseInsensitive, $Key4,  %Rows)
				|| &NumInAlphaCompareKey($CaseInsensitive, $Key5,  %Rows) } keys %{$Rows{Data}} if $Keys ne "";

	@rows = sort { &NumInAlphaCompareKey($CaseInsensitive, "Data", %Rows) } keys %{$Rows{Data}} if $Keys eq "";

	@rows = reverse @rows if $ReverseOrder;

	foreach my $row (@rows)
	{
		next if $row eq "Data";

		# $Rows{Data}{$row} is blanked out so it can be used to test for duplicate lines
		my $Line = $Rows{Data}{$row};
		$Rows{Data}{$row} = "";
		printf "%s\n", $Line if ((not $ShowUnique) || not inarray $Line, values %{$Rows{Data}});
	}
}

###############
###############
my ($CaseInsensitive, $ReverseOrder, $ShowUnique, $Keys, $Separator) = GetOptions;
my %Rows;
ReadInput \%Rows, $Separator;
Sort $CaseInsensitive, $ReverseOrder, $ShowUnique, $Keys, $Separator, %Rows;
exit 0;

