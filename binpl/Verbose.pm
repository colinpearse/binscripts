#!/usr/bin/perl
#!/usr/bin/perl -d

# Copyright (c) 2005-2019 Colin Pearse.
# All scripts are free in the binscripts repository but please refer to the
# LICENSE file at the top-level directory for the conditions of distribution.
#
# File:         Verbose.pm
# Description:  verbosity functions


our $VERSION = "0.1";

package Verbose;

our $VERSION = "0.1";
our $PM_NAME = "Verbose.pm";
our $PM_PREFIX = "Verbose";
our $Myname = $0; { $Myname =~ s,.*/,,; } # bug in grep means I can't strip dir this outside these brackets

use strict;
use warnings;
no warnings 'uninitialized';

our $VerbosityLevel = 1;
our $VerbosityString = "$VerbosityLevel";
our $ExitOnError = "on";

# CP: use minimum Perl modules
#use Dumper;


############
sub Mytime
{
    my ($ss,$mm,$hh,$rest) = localtime(time);
	return sprintf("%02d:%02d:%02d",$hh,$mm,$ss);
}

################
# Verbosity functions which allow more targeted messaging.
# -v 11,f  shows messages from verbose("f", ...) and verbose(20, ...)
# GetOptions() will contain:
#   $VerbosityString = $options{v} if defined $options{v};
#   Verbosity::setVerbosity $VerbosityString;
sub setVerbosity
{
	our ($VerbosityLevel, $VerbosityString);
	my ($str) = @_;
	my $lev;
	if ($str =~ /(\d*),*(.*)/)
	{
		($lev, $str) = ($1, $2);
	}
	$lev = $VerbosityLevel if $lev eq "";
	($VerbosityLevel, $VerbosityString) = ($lev, $str);
}


##############
sub beVerbose
{
	our ($VerbosityLevel, $VerbosityString);
	my ($str) = @_;
	my $lev;
	if ($str =~ /(\d*),*(.*)/)
	{
		($lev, $str) = ($1, $2);
	}
	if ($lev ne "" && $VerbosityLevel >= $lev)
	{
		return 1;
	}
	else
	{
		foreach (split(',', $str))
		{
			return 1 if ",$VerbosityString," =~ /,$_,/;
		}
	}
	return 0;
}


##############
sub _verbose
{
	our ($VerbosityLevel, $VerbosityString);
	my ($Mode, $ArgString, $Format, @Args) = @_;
    my $HHMMSS = Mytime;
	if (beVerbose $ArgString)
	{
		if ($Mode =~ /(nonl|nl|standard|heading)/)
		{
			my $Str = sprintf "$HHMMSS: $Format", @Args;
			$Str = "$HHMMSS: $Format" if scalar @Args eq 0;  # deal with '%' eg. verbose 1, "this is 90%";
			my $Line = $Str; $Line =~ s/./-/g;
			printf STDERR "$Str"                 if $Mode eq "nonl";
			printf STDERR "\n"                   if $Mode eq "nl";
			printf STDERR "$Str\n"               if $Mode eq "standard";
			printf STDERR "$Line\n$Str\n$Line\n" if $Mode eq "heading";
		}
		elsif ($Mode eq "array")
		{
			foreach my $Line (@Args)
			{
				printf STDERR "$HHMMSS: $Format: $Line\n";
			}
		}
#		elsif ($Mode eq "dumper")
#		{
#			my ($Str, $Object) = ($Format, $Args[0]);
#			print STDERR "$Str ----- START of Dumper() -----\n";
#			print STDERR Dumper $Object;
#			print STDERR "$Str ----- END of Dumper() -----\n";
#		}
	}
}

#   verbose_nonl <num or string>, <format>, <printf args>;
#   verbose_nl   <num or string>;
#   verbose      <num or string>, <format>, <printf args>;
#   verbose_arr  <num or string>, <prefix>, <array>;
#   verbose_head <num or string>, <prefix>, <printf args>;
#   verbose_dump <num or string>, <varname>, <object>;
sub verbose_nonl  { _verbose "nonl",     @_; }
sub verbose_nl    { _verbose "nl",       @_; }
sub verbose       { _verbose "standard", @_; }
sub verbose_head  { _verbose "heading",  @_; }
sub verbose_arr   { _verbose "array",    @_; }
#sub verbose_dump  { _verbose "dumper",   @_; }


#########
sub setExitOnError
{
	our ($ExitOnError);
	$ExitOnError = @_;
}
sub error
{
	our ($Myname, $ExitOnError);
	my ($ExitValue, $Format, @Args) = @_;
	verbose 1, "$Myname: ERROR: $Format", @Args;
	exit $ExitValue if ($ExitOnError eq "on");
}



########################################################
########################################################

1; # Ensure Perl compiles the code

# Lines starting with an equal sign indicate embedded POD
# documentation.  POD sections end with an =cut directive, and can
# be intermixed almost freely with normal code.

__END__

=head1 NAME

Verbose - Verbosity functions

=head1 SYNOPSIS

	use Processes;

=head1 DESCRIPTION

Verbosity functions.
verbose 1, "Msg = %s", $Msg;

=head1 Caveats

=cut

