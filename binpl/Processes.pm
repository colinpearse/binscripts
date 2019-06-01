

# Copyright (c) 2005-2019 Colin Pearse.
# All scripts are free in the binscripts repository but please refer to the
# LICENSE file at the top-level directory for the conditions of distribution.
#
# File:        Processes.pm
# Description: Perl module to allow concurrent processes. Threads isn't useful because
#              (a) it uses too much memory and (b) you can't use alarm() which I may
#              need for command timeouts. Its limitation is dealing so far with functions
#              that return a single "hash" or no return type "void".


package Processes;

our $VERSION = "0.2";
our $PM_NAME = "Processes.pm";
our $PM_PREFIX = "Processes";
our $Myname = $0; { $Myname =~ s,.*/,,; } # bug in grep means I can't strip dir this outside these brackets

# Get $UserName to ensure different users can write to default log
our $UserName = getpwuid($>);  # $< = realuser, $> = effective user
$UserName = "nouser" if $UserName eq "";

$Processes::DefaultTmpDir  = "/tmp";
$Processes::DefaultLogFile = "/tmp/${PM_NAME}.$UserName.log";

use strict;
use warnings;
no warnings 'uninitialized';

use POSIX qw(:sys_wait_h);
use Data::Dumper;

# Defaults when instantiating class (with their defaults).
our %ClassVariables = ( "VerbosityLevel"  => 1);


#########
#########
sub verbose
{
	my $self = shift;
	my ($Level, $Format, @Args) = @_;
	my $Str = (@Args ? sprintf($Format, @Args) : $Format);
	printf STDERR "$PM_NAME: $Str\n" if ($Level <= $self->{VerbosityLevel});
}
sub error
{
	my $self = shift;
	my ($ExitValue, $Format, @Args) = @_;
	$self->verbose(1, "ERROR: $Format", @Args);
	exit $ExitValue;
}


#######################
#######################
# Options take the form (VerbosityLevel => 1, ...)
sub SetDefaults
{
	my $self = shift;
	foreach my $ClassVariable (sort keys %ClassVariables)
	{
		$self->{$ClassVariable} = $ClassVariables{$ClassVariable};
	}
}
sub SetVariables
{
	my $self = shift;
	my (%Options) = @_;
	foreach my $ClassVariable (sort keys %ClassVariables)
	{
		$self->{$ClassVariable} = $Options{$ClassVariable}         if defined $Options{$ClassVariable};
		$self->{$ClassVariable} = $ENV{"$PM_PREFIX$ClassVariable"} if defined $ENV{"$PM_PREFIX$ClassVariable"}; # override using environmental
	}
}

#########
#########
# When instantiated child will run function and the return value (referencing a hash tree)
# will be written to $self->{Tempfile} to be picked up by the parent on attach().
# Child will always exit with 0 after running the function since it is the
# return from that function that is significant which will be picked up
# when attach() is called.
sub new
{
	my ($class, $ReturnType, $Function, @Args) = @_;
	my $TmpDir = $Processes::DefaultTmpDir;
	my $self = {};
	our ($PM_NAME, $UserName);
	bless ($self, $class);
	$self->SetDefaults;
	$self->SetVariables;
	$self->{ReturnType}     = $ReturnType;
	$self->{Function}       = $Function;
	@{$self->{Args}}        = @Args;
	my $pid = fork();
	if (not defined $pid)
	{
		$self->error(3, "could not fork - no resources");
	}
	elsif (!$pid)
	{
		# child
		$SIG{INT} = 'DEFAULT';  # inherits trap from parent which I don't want

		$self->{Tempfile} = "$TmpDir/$PM_NAME.$UserName.$$";
		if ($self->{ReturnType} eq "hash")
		{
			my %hash = &{$self->{Function}} (@Args);
			$SIG{INT} = $self->MyEnd;
			open (my $fd, ">", $self->{Tempfile}) or $self->error(1, q#could not create tmp file "%s"#, $self->{Tempfile});
			print $fd Dumper \%hash               or $self->error(1, q#could not write hash to tmp file "%s"#, $self->{Tempfile});
			close ($fd);
		}
		elsif ($self->{ReturnType} eq "void")
		{
			&{$self->{Function}} (@Args);
		}
		else
		{
			$self->error(2, q#invalid return type "%s" (accepted: "hash", "void")#, $self->{ReturnType});
		}
		exit 0;
	}
	else
	{
		# parent
		$self->{Tempfile}  = "$TmpDir/$PM_NAME.$UserName.$pid";
		$self->{ChildPID}  = $pid;
		$self->{ExitValue} = -1;
		$self->{Status}    = "detached";
		return $self;
	}
}

###############
###############
# waitpid return codes: ret<0 dead process; ret==0 process still running; ret==PID process finished and $? set
sub attach
{
	my $self = shift;
	return () if $self->is_attached();            # already run this function

	my $PID = waitpid ($self->{ChildPID}, 0);  # waitpid will set $? if process is dead (and caught by waitpid in is_finished())
	$self->{ExitValue} = WEXITSTATUS($?) if ($PID==$self->{ChildPID});  # if $PID<0 then {ExitValue} must have been set by is_finished()
	# don't worry if $PID is -1 - still need to collect data from dead child process
	if ($self->{ReturnType} eq "hash")
	{
		if (-e $self->{Tempfile})  # if $self->{Function} did not return anything then there will not be a temp file
		{
			# $self->{ReturnType} is "hash" or "void" for now
			my $VAR1;
			eval `cat $self->{Tempfile}`;
			unlink ($self->{Tempfile});
			$SIG{INT} = 'DEFAULT';
			$self->{Status} = "attached";
			if (ref($VAR1) eq "HASH")
			{
				return %{$VAR1};
			}
			else
			{
				$self->error(1, q#return type is "hash" but variable read does not point to a hash (ref=%s)#, ref($VAR1));
			}
		}
		else
		{
#			$self->error(1, q#return type is "hash" but tmp file containing hash does not exist (%s)#, $self->{Tempfile});
			$self->verbose(10, q#return type is "hash" but tmp file containing hash does not exist (%s) - function probably terminated prematurely#, $self->{Tempfile});
		}
	}
	else
	{
		$self->{Status} = "attached";
	}
	return ();
}

###############
###############
sub is_attached
{
	my $self = shift;
	$self->verbose(10, "%s: child:%s status:%s", (caller(0))[3], $self->{ChildPID}, $self->{Status});
	return ($self->{Status} eq "attached" ? 1 : 0);
}

###############
###############
sub is_finished
{
	my $self = shift;
	my $PID = waitpid ($self->{ChildPID}, WNOHANG);  # can use non hanging wait: WNOHANG when you include: use POSIX ":sys_wait_h";
	$self->{ExitValue} = WEXITSTATUS($?) if ($PID == $self->{ChildPID});
	$self->verbose(10, "%s: child:%s exit:%s (wait:%s)", (caller(0))[3], $self->{ChildPID}, $self->{ExitValue}, $?);
	return ($PID == $self->{ChildPID} ? 1 : 0);
}

###############
###############
# $PidStr will be parent:child:child:child:child:etc..
sub GetPidStr
{
	my ($PidStr, @PsOutput) = @_;
	foreach (@PsOutput)
	{
		chomp $_;
		if ($_ =~ /^\s*[^\s]+\s*(\d+)\s*(\d+).*/)  # $1 $2 didn't work in the normal way here !?!
		{
			$_ =~ s/^\s*[^\s]+\s*(\d+)\s*(\d+).*/$1:$2/;
			my ($PID, $PPID) = split (':', $_);
			$PidStr .= ":$PID" if (":$PidStr:" =~ /:$PPID:/ && ":$PidStr:" !~ /:$PID:/);
		}
	}
	return $PidStr;
}

###############
###############
# TO DO: bit scappy this - invoking GetPidStr three times to make sure
#        no child of child of child etc is missed.
sub killtree
{
	my $self = shift;
	my @PsOutput = `ps -ef`;
	chomp @PsOutput;
	my $PidStr = GetPidStr( $self->{ChildPID}, @PsOutput );
	$PidStr    = GetPidStr( $PidStr, @PsOutput );
	$PidStr    = GetPidStr( $PidStr, @PsOutput );
	$PidStr =~ s/^\d+://;
	foreach my $PID (split /:/, $PidStr)
	{
		$self->verbose(20, "%s: child:%s killed %s", (caller(0))[3], $self->{ChildPID}, $PID);
		kill 9, $PID;
	}
}

#########
#########
sub kill
{
	my $self = shift;
	$self->killtree;
	$self->verbose(20, "%s: child:%s killed", (caller(0))[3], $self->{ChildPID});
	kill 9, $self->{ChildPID};
}

############
############
sub getexit
{
	my $self = shift;
	$self->verbose(10, "%s: child:%s exit:%s", (caller(0))[3], $self->{ChildPID}, $self->{ExitValue});
	return $self->{ExitValue};
}

#########
#########
sub pid
{
	my $self = shift;
	return $self->{ChildPID};
}

#########
#########
# don't do $self->killtree - don't need this
sub MyEnd
{
	my $self = shift;
	if (-e $self->{Tempfile})
	{
		$self->verbose(10, "%s: child:%s removing:%s", (caller(0))[3], $self->{ChildPID}, $self->{Tempfile});
		unlink ($self->{Tempfile});
	}
}

########################################################
########################################################

1; # Ensure Perl compiles the code

# Lines starting with an equal sign indicate embedded POD
# documentation.  POD sections end with an =cut directive, and can
# be intermixed almost freely with normal code.

__END__

=head1 NAME

Processes - Process functions

=head1 SYNOPSIS

	use Processes;

=head1 DESCRIPTION

Threads isn't useful because (a) it uses too much memory and (b) you can't use
alarm() which I need this for command timeouts. Processes.pm is leaner and
allows signal communication.

=head1 Caveats

=cut

