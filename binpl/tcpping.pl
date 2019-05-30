#!/usr/bin/perl


# Copyright (c) 2005-2019 Colin Pearse.
# All scripts are free in the binscripts repository but please refer to the
# LICENSE file at the top-level directory for the conditions of distribution.
#
# File:        tcpping.pl
# Description: Ping one or more tcp ports


our $VERSION = "1.1";

our $Myname = $0; { $Myname =~ s,.*/,,; } # bug in grep means I can't strip dir this outside these brackets

use strict;
use warnings;
no warnings 'uninitialized';

use Getopt::Std;
use Time::Local;
use FileHandle;
use Fcntl;
use Socket;

#################
#################
our $Timeout = 3;
our $Count = 0;
our $WaitSecs = 1;
our $HostList = "";
our $HostnamesStr = "";
our @Hostnames = ();
our $PortRange = "";
our $DefaultProtocolName = "tcp";
our $ProtocolName = "";
our $OneSuccess = 0;

###########
###########
sub usage
{
	print STDERR qq{
 usage: $Myname [-t timeout] [-p ports] [-P protocol] [-c count] [-w secs] <host>
        $Myname [-t timeout]               [-c count] [-w secs] <host> <ports> [protocol]
        $Myname [-t timeout] [-f hostlist] [-c count] [-w secs]        <ports> [protocol]
        $Myname [-t timeout] [-H hosts]    [-c count] [-w secs]        <ports> [protocol]

    -t secs      timeout (default: $Timeout)
    -c count     count (default: indefinite)
    -w secs      wait between pings (default: $WaitSecs)
    -f hostlist  file containing a list of hosts to ping; cannot be used with -H
    -H hostlist  comma separated hosts to ping; cannot be used with -f
    -p ports     port range
    -P protocol  protocol (default: $DefaultProtocolName)
    -1           (minus one) exit success on the first successful ping of any port (see Exit code below)

 Ping (try to open a socket to) one or more tcp/udp ports on one or many hosts.

 Exit code: by default success is returned only if pings to all ports and hosts are successful
 to all hosts on the final iteration (if count > 1), unless -1 (minus one) is used which exits
 with success on the first successful ping of any port specified.

   egs. $Myname 192.168.1.2 22,23,100-120            # ping these tcp ports
        $Myname 192.168.1.2 11 udp                   # fairly meaningless since UDP is fire and forget
        $Myname -f lpars -c3600 513-514              # ping rlogin/rsh ports for one hour
        $Myname -f viostab -c3600 22                 # ping ssh port for one hour
        $Myname -H myhost1,myhost2 -c1 22            # ping ssh port once
        $Myname -H myhost1,myhost2 -c10 22,111,657   # exit success on first ping of any port on all hosts

};
	exit 2
}

##########
##########
sub error
{
	my ($ExitValue, $Format, @Args) = @_;
	our ($Myname);
	printf STDERR "$Myname: ERROR: $Format\n", @Args;
	exit $ExitValue;
}

###############
###############
sub GetOptions
{
	our($Count, $Timeout, $PortRange, $ProtocolName);
	my %options;
	usage if $ARGV[0] eq "";
	getopts("ht:c:w:f:H:p:P:1",\%options) or usage;
	usage if defined $options{h};
	$Timeout      = $options{t} if defined $options{t};
	$Count        = $options{c} if defined $options{c};
	$WaitSecs     = $options{w} if defined $options{w};
	$HostList     = $options{f} if defined $options{f};
	$HostnamesStr = $options{H} if defined $options{H};
	$PortRange    = $options{p} if defined $options{p};
	$ProtocolName = $options{P} if defined $options{P};
	$OneSuccess   = 1           if defined $options{1};

	my $ArgCount = 0;
	$HostnamesStr = $ARGV[$ArgCount++]   if ($HostList eq "" && $HostnamesStr eq "");
	$PortRange    = $ARGV[$ArgCount++]   if ($PortRange eq "");
	$ProtocolName = $ARGV[$ArgCount]     if ($ProtocolName eq "" && $ARGV[$ArgCount] ne "");
	$ProtocolName = $DefaultProtocolName if ($ProtocolName eq "");
	error 2, q#no host specified#,   $HostnamesStr if ($HostList eq "" && $HostnamesStr eq "");
	error 2, q#port range is blank#, $PortRange    if ($PortRange eq "");

	my $ArgPortRange = $PortRange;
	$PortRange =~ s/-/../g;  # convert to Perl style range n..n
	my @TestRange = eval $PortRange;
	error 2, q#Range of ports (%s) is invalid#, $ArgPortRange if ($PortRange ne "" && $TestRange[0] eq "");
	error 2, q#-t must be numeric#, $Timeout  if ($Timeout !~ /^\d+$/);
	error 2, q#-c must be numeric#, $Count    if ($Count !~ /^\d+$/);
	error 2, q#-w must be numeric#, $WaitSecs if ($WaitSecs !~ /^\d+$/);
	error 2, q#file "%s" does not exist or is not readable#, $HostList if ($HostList ne "" && (not -r $HostList));
}

############
############
sub SetVars
{
	our($HostList);
	if ($HostList ne "")
	{
		@Hostnames = grep /^[A-Za-z0-9_]/, `cat $HostList`;
		chomp @Hostnames;
	}
	elsif ($HostnamesStr ne "")
	{
		@Hostnames = grep /^[A-Za-z0-9_]/, split(',', $HostnamesStr);
	}
	error 1, q#no valid hosts identified - please check the hostnames# if @Hostnames == 0;
}

###############
###############
sub GetDateTime
{
	my ($ss, $mm, $hh, $d, $m, $y, $w, $yd, $dst) = localtime(time);
	my $DateTime = sprintf "%02d-%02d-%02d %02d:%02d:%02d",$d,++$m,$y+1900,$hh,$mm,$ss;
	chomp $DateTime;
	return $DateTime;
}

###########
###########
# socket(SOCKET, DOMAIN, TYPE, PROTOCOL) 
# DOMAIN should be AF_INET (or AF_INET6) - see Socket.pm for more possibilities
# TYPE can be SOCK_DGRAM, SOCK_RAW, SOCK_RDM, SOCK_SEQPACKET or SOCK_STREAM
sub PingPort
{
	my ($Timeout, $Hostname, $Port, $ProtocolName) = @_;
	my $PingOk = 0;

	my $Protocol = getprotobyname($ProtocolName);
	my $SockType = $ProtocolName =~ /udp/i ? SOCK_DGRAM : SOCK_STREAM;
	my $SocketAddrFormat = "S n a4 x8";

	my $DateTime = GetDateTime;
	my $InAddr = (gethostbyname($Hostname))[4];
	if ($InAddr ne "")
	{
		my $HostAddr = pack($SocketAddrFormat, AF_INET, $Port, $InAddr);
		if (socket(my $Socket, AF_INET, $SockType, $Protocol))
		{
			$Socket->autoflush(1);  # sockets must be unbuffered
			my $CurrentFcntl = fcntl($Socket, F_GETFL, 0);
			fcntl($Socket, F_SETFL, $CurrentFcntl | O_NONBLOCK);
			connect($Socket, $HostAddr);

			my $Vector = "";
			vec($Vector, fileno($Socket), 1) = 1;     # vec() turns $Vector into a bit vector with offset fileno, bits 1
			select(undef, $Vector, undef, $Timeout);  # select() the filehandle via $Vector
			if (vec($Vector, fileno($Socket), 1))
			{
				$! = unpack("L", getsockopt($Socket, SOL_SOCKET, SO_ERROR));  # now check if error
				if ($! eq "")
				{
					$PingOk = 1;
					printf "%s: %s:%s:%s: ok\n", $DateTime, $Hostname, $ProtocolName, $Port;
				}
				else
				{
					printf STDERR "%s: %s:%s:%s: ERROR on call to connect(): %s\n", $DateTime, $Hostname, $ProtocolName, $Port, $!;
				}
			}
			else
			{
				printf STDERR "%s: %s:%s:%s: timeout waiting for connect()\n", $DateTime, $Hostname, $ProtocolName, $Port;
			}
			shutdown($Socket, 2); # don't try to send outstanding data
			close($Socket);
		}
		else
		{
			printf STDERR "%s: %s:%s:%s: ERROR on call to socket(): %s\n", $DateTime, $Hostname, $ProtocolName, $Port, $!;
		}
	}
	else
	{
		printf STDERR "%s: %s:%s:%s: ERROR on call to gethostbyname()\n", $DateTime, $Hostname, $ProtocolName, $Port;
	}

	return $PingOk;
}

##############
##############
# if $OneSuccess is set then success if at least port succeeds
# otherwise success if all ports ping
sub PingPorts
{
	our($OneSuccess);
	my ($Timeout, $Hostname, $PortRange, $ProtocolName) = @_;
	my $PingOks   = 0;
	my $PingsDone = 0;
	foreach my $Port (eval $PortRange)
	{
		$PingsDone++;
		$PingOks++ if PingPort $Timeout, $Hostname, $Port, $ProtocolName;
	}
	return ($PingOks) if $OneSuccess;
	return ($PingOks == $PingsDone);
}

##############
##############
# success if all hosts ping
sub PingHosts
{
	my ($Timeout, $PortRange, $ProtocolName, @Hostnames) = @_;
	my $PingOks = 0;
	foreach my $Hostname (@Hostnames)
	{
		$PingOks++ if PingPorts $Timeout, $Hostname, $PortRange, $ProtocolName;
	}
	return ($PingOks == scalar @Hostnames);
}

#########
#########
sub Main
{
	our($Count, $Timeout, $WaitSecs, @Hostnames, $PortRange, $ProtocolName, $OneSuccess);
	my $Success = 0;
	GetOptions;
	SetVars;
	for (my $i=0; $i < $Count || $Count == 0 ; $i++)
	{
		sleep $WaitSecs if $i > 0;

		$Success = 1 if PingHosts $Timeout, $PortRange, $ProtocolName, @Hostnames;

		last if ($Success && $OneSuccess);
	}
	return $Success;
}

#######
#######
STDOUT->autoflush(1);  # noticed stdout messages displayed after stderr when I redirect output
STDERR->autoflush(1); 
exit (Main() ? 0 : 1);

