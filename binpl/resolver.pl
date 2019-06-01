#!/usr/bin/perl -w

# Author:      Colin Pearse
# Name:        resolver.pl
# Description: Testing resolv.conf and resolver libraries

use strict;
use Socket;

our $myname = $0; $myname =~ s,.*/,,;

##########
##########
sub usage
{

	print STDERR qq{
 usage: $myname <Hostname|IP> [Timeout]

};
	exit 2;
}

##########
##########
sub _resolver
{
	my ($NameOrIP) = @_;

	if ($NameOrIP =~ /^[0-9]/)
	{
		my $Hostname = gethostbyaddr(inet_aton($NameOrIP), AF_INET) or die "Can't resolve $NameOrIP\n";
		print "$Hostname\n";
	}
	else
	{
		my @IPs = gethostbyname($NameOrIP) or die "Can't resolve $NameOrIP\n";
		@IPs = map { inet_ntoa($_) } @IPs[4 .. $#IPs];     # format into array of IPs
		my $IP = inet_ntoa(inet_aton($NameOrIP));          # get first IP address
		print "@IPs\n";
	}
}

##########
##########
usage unless ($#ARGV==0 || $#ARGV==1);

my $NameOrIP = $ARGV[0];
my $Timeout  = $ARGV[1];

if (defined $Timeout)
{
	local $SIG{ALRM} = sub { die "Can't resolve $NameOrIP after $Timeout second(s)\n" };
	alarm $Timeout;
	_resolver $NameOrIP;
	alarm 0;
}
else
{
	_resolver $NameOrIP;
}

exit 0;

