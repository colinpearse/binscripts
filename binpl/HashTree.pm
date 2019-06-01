

# Copyright (c) 2005-2019 Colin Pearse.
# All scripts are free in the binscripts repository but please refer to the
# LICENSE file at the top-level directory for the conditions of distribution.
#
# Module:      HashTree.pm
# Description: Functions to display a recursive hash of hashes delimited by colons. Colons are replaced by <colon>
#              when displayed on screen, but converted back to ':' when read back into a hash.
#              There is a long version "k:key1:key2" "v:key1:key2:var1" and a short version "key1:key2" ":var1".
#              Functions: PrintRecursiveHashShort(Debug), FillRecursiveHashShort, PrintRecursiveHashLong(Debug), FillRecursiveHashLong


package HashTree;

our $VERSION = "0.1";
our $PM_NAME = "HashTree.pm";
our $Myname = $0; { $Myname =~ s,.*/,,; } # bug in grep means I can't strip dir this outside these brackets

use strict;
use warnings;
no warnings 'uninitialized';

###############
###############
# This routine should cope with any number of hash keys and values in any order.
# Also, it aims to write the absolute minimum in case the hash is huge. I previously
# has written hashes using PrintRecursiveHashLong() and if a hash was large enough to 
# create a 10MB file this would take up to 5 seconds to process. The method below
# is much quicker:
# 1) lines starting with a non-colon are all hash keys
# 2) lines starting with a colon are all key:value
# Therefore:
# line1=a:b:c
# line2=:d:xxx    is $hash{a}{b}{c}{d} = "xxx"
# line1=          (blank line)
# line2=:z:xxx    is $hash{z} = "xxx"
# NOTE: To ensure key:value lines aren't mixed with the wrong key lines two loops will
#       be used: the first to process non-hash values first, then hash values.
sub PrintRecursiveHashShort
{
	my ($fd, $t, %hash) = @_;
	my $Colon = ":";   $Colon        = "" if $t eq "";  # only on first call will $t eq ""
	our $PrevWholeKey; $PrevWholeKey = "" if $t eq "";  # only on first call will $t eq ""
	my $Text = "$t";
	my $DisplayKeysOnce = 1;
	while (my ($key, $value) = each(%hash))
	{
		$key   =~ s/:/<colon>/g; # if delimiter is : then put the word <colon> in all fields
		$value =~ s/:/<colon>/g; # if delimiter is : then put the word <colon> in all fields
		if (ref($value) ne "HASH")
		{
			if ($DisplayKeysOnce)
			{
				printf $fd "${Text}\n"; # hash key displayed (those hash keys that have non-hash values)
				$DisplayKeysOnce = 0;
				$PrevWholeKey = $Text;  # ensure same keys are not redisplayed by second loop
			}
			printf $fd ":%s:%s\n", $key, $value              if (ref($value) ne "ARRAY");
			printf $fd ":%s:%s\n", $key, join " ", @{$value} if (ref($value) eq "ARRAY");
		}
	}
	while (my ($key, $value) = each(%hash))
	{
		$key   =~ s/:/<colon>/g; # if delimiter is : then put the word <colon> in all fields
		$value =~ s/:/<colon>/g; # if delimiter is : then put the word <colon> in all fields
		if (ref($value) eq "HASH")
		{
			PrintRecursiveHashShort($fd, "$Text${Colon}$key", %{$value});
			# below is to display hash keys without values
			my $WholeKey = sprintf "%s%s", "$Text$Colon", $key;
			print $fd "$WholeKey\n" if $PrevWholeKey ne $WholeKey; # don't use /expr/ in case line has special chars
			$PrevWholeKey = $WholeKey;
		}
	}
}

###############
###############
# Designed to read a file created by PrintRecursiveHashShort() and recreate the original hash.
sub FillRecursiveHashShort
{
	my ($fd, $ShowCount, $HashTreeRoot) = @_;
	my $HashTreePtr;
	my $LineCount=1;
	while (<$fd>)
	{
		my $Line = $_; chomp $Line;
        if ($Line !~ /^:/) # short format: only values start with a colon, otherwise line shows keys only
		{
			$HashTreePtr = $HashTreeRoot;
			foreach my $key (split(':', $Line))
			{
				$key =~ s/<colon>/:/g;
				$HashTreePtr->{$key}{dummy} = "dummy entry";
				delete $HashTreePtr->{$key}{dummy};
				$HashTreePtr = \%{$HashTreePtr->{$key}};
			}
		}
		else
		{
			my ($blank, $key, $value) = split(':', $Line);
			$value =~ s/<colon>/:/g;
			$key   =~ s/<colon>/:/g;
			$HashTreePtr->{$key} = $value;
		}
		print STDERR "\r$LineCount" if ($ShowCount && -t STDERR);
		$LineCount++;
	}
	print STDERR "\r            \r" if ($ShowCount && -t STDERR);
}

###############
###############
sub PrintRecursiveHashLong
{
	my ($fd, $t, %hash) = @_;
	my $Colon = ":"; $Colon = "" if ($t eq "");
	my $Text = "$t";
	while (my ($key, $value) = each(%hash))
	{
		$key   =~ s/:/<colon>/g; # if delimiter is : then put the word <colon> in all fields
		$value =~ s/:/<colon>/g; # if delimiter is : then put the word <colon> in all fields
		if (ref($value) eq "HASH")
		{
			printf $fd "k:%s%s\n", "$Text$Colon", $key;
			PrintRecursiveHashLong($fd, "$Text${Colon}$key", %{$value});
		}
		else
		{
			printf $fd "v:%s%s:%s\n", "$Text$Colon", $key, $value              if (ref($value) ne "ARRAY");
			printf $fd "v:%s%s:%s\n", "$Text$Colon", $key, join " ", @{$value} if (ref($value) eq "ARRAY");
		}
	}
}

########################
########################
# Lines with keys begin with k: values begin with v:
# NOTE: Colons will be put back: <colon> returned to ':'
sub FillRecursiveHashLong
{
	my ($fd, $ShowCount, $HashTreeRoot) = @_;
	my $Line;
	my $LineCount=1;
	while ($Line = <$fd>)
	{
		chomp $Line;
        if ($Line =~ /^k:/) # long format: k: is keys only, otherwise v: denoting a keys+value
		{
			$Line =~ s/^..//;
			SetHashKeys(\%{$HashTreeRoot}, split(':', $Line));
		}
		else
		{
			$Line =~ s/^..//;
			SetHashValue(\%{$HashTreeRoot}, $Line);
		}
		print STDERR "\r$LineCount" if ($ShowCount && -t STDERR);
		$LineCount++;
	}
	print STDERR "\r                             \r" if ($ShowCount && -t STDERR);
}
# set only keys
sub SetHashKeys
{
	my ($hash, @Fields) = @_;
	foreach my $key (@Fields)
	{
		$key =~ s/<colon>/:/g;
		$hash->{$key}{dummy} = "dummy entry";
		delete $hash->{$key}{dummy};
		$hash = \%{$hash->{$key}};
	}
	return \%{$hash};
}
# set keys and key:value
sub SetHashValue
{
	my ($hash, $Line) = @_;
	return if $Line =~ /::/; # this anywhere is invalid since it implies a blank key - so ignore
	my @Fields = split(':', $Line);
	my $value = "";
	my $LineLength = length($Line);
	$value  = pop @Fields if $Line !~ /:$/; # if final field (value) is blank then don't pop since key will be final field
	my $key = pop @Fields;
	$value =~ s/<colon>/:/g;
	$key   =~ s/<colon>/:/g;
	$hash = SetHashKeys(\%{$hash}, @Fields);
	$hash->{$key} = $value;
}

############################
############################
sub PrintRecursiveHashShortDebug
{
	my (%hash) = @_;
	my $stderr_fd = *STDERR;
	PrintRecursiveHashShort($stderr_fd, "", %hash);
}
sub PrintRecursiveHashLongDebug
{
	my (%hash) = @_;
	my $stderr_fd = *STDERR;
	PrintRecursiveHashLong($stderr_fd, "", %hash);
}
sub PrintRecursiveHashDebug
{
	PrintRecursiveHashLongDebug @_;
}

########################################################
########################################################

1; # Ensure Perl compiles the code

# Lines starting with an equal sign indicate embedded POD
# documentation.  POD sections end with an =cut directive, and can
# be intermixed almost freely with normal code.

__END__

=head1 NAME

HashTree - Save / display recursively a hash of hashes

=head1 SYNOPSIS

	use HashTree;

=head1 DESCRIPTION

Functions to display a recursive hash of hashes delimited by colons. Colons are replaced by <colon>
when displayed on screen, but converted back to ':' when read back into a hash.

=head1 Caveats

=cut

