#!/usr/bin/perl
#!/usr/bin/perl -d


# Copyright (c) 2005-2019 Colin Pearse.
# All scripts are free in the binscripts repository but please refer to the
# LICENSE file at the top-level directory for the conditions of distribution.
#
# Name:         ldapsearch.pl
# Description:  Test LDAP search (uses Net/LDAP.pm version 0.56) by mimiking /usr/bin/ldapsearch


# NOTE: compare with the output of this command:
#       /usr/bin/ldapsearch -o ldif-wrap=no -Z -H ldaps://host1.thepearses.com:636 -D "cn=Directory Manager" -w $(cat /root/.oud.pw) -b "dc=thepearses,dc=com" -s sub '*'

our $VERSION = "0.1";

our $Myname = $0; { $Myname =~ s,.*/,,; } # bug in grep means I can't strip dir this outside these brackets

use strict;
use warnings;
no warnings 'uninitialized';

use Getopt::Std;
use Data::Dumper;
use Net::LDAP;
use HashTree;


############
our $LdapPasswd = `cat $ENV{HOME}/.oud.pw`; chomp $LdapPasswd;
our $StartTimeout = 30;


############
our $VerbosityLevel = 1;
#our $ServerCert = "/etc/openldap/cacerts/oud.pem";
our $LdapUris = "ldap://host1.thepearses.com:389";
our $LdapScheme = "ldap";
our $LdapPort = "389";
our $BindDn = "cn=Directory Manager";
our $Base = "dc=thepearses,dc=com";
our $Scope = "sub";
our $Filter = "";
our $Attr = "";
our $ArgExitOnError = "on";


############
sub version
{
	print STDERR "$Myname v$VERSION\n";
	exit 0;
}


##########
sub usage
{
	our ($Myname, $LdapUris, $LdapPort, $BindDn, $Base, $Attr, $ArgExitOnError);
	print STDERR qq{
 usage: $Myname <filter> <attribute>

 -V          show version
 -v level    verbosity level (default: $VerbosityLevel)
 -H URIs     LDAP URIs (comma separated) (default: $LdapUris)
 -p port     LDAP port (default: $LdapPort)
 -D bind     LDAP bind (default: $BindDn)
 -b base     LDAP search (default: $Base)
 -s scope    LDAP scope (default: $Scope)
 -E on|off   exit on error (default: $ArgExitOnError)

 Contact LDAP host(s) and query <user> to get user's <email>.

 egs. $Myname 'cn=*'
      $Myname 'uid=*' uid

};
	exit 2;
}



############
# NOTE: for Dumper() ref($Object) can't be used because it will return "" for variables that refer to hashes within objects
sub _verbose
{
	our ($VerbosityLevel);
	my ($Mode, $Level, $Format, @Args) = @_;
	if ($VerbosityLevel >= $Level)
	{
		if ($Mode eq "standard" || $Mode eq "heading")
		{
			my $Str = sprintf "$Format", @Args;
			$Str = $Format if scalar @Args eq 0;  # deal with '%' eg. verbose 1, "this is 90%";
			my $Line = $Str; $Line =~ s/./-/g;
			print STDERR "$Str\n"               if $Mode eq "standard";
			print STDERR "$Line\n$Str\n$Line\n" if $Mode eq "heading";
		}
		elsif ($Mode eq "dumper")
		{
			my ($Str, $Object) = ($Format, $Args[0]);
			print STDERR "$Str ----- START of Dumper() -----\n";
			print STDERR Dumper $Object;
			print STDERR "$Str ----- END of Dumper() -----\n";
		}
		elsif ($Mode eq "hash")
		{
			my ($Str, $Object) = ($Format, $Args[0]);
			HashTree::PrintRecursiveHashLongDebug %{$Object};
		}
		elsif ($Mode eq "array")
		{
			my ($Str, $Object) = ($Format, $Args[0]);
			foreach my $Line (@{$Object})
			{
				print STDERR "$Str: %s", $Line;
			}
		}
	}
}
sub verbose        { _verbose "standard", @_; }
sub verboseDumper  { _verbose "dumper",   @_; }
sub verboseArray   { _verbose "array",    @_; }
sub verboseHash    { _verbose "hash",     @_; }
sub verboseHeading { _verbose "heading",  @_; }


#########
sub error
{
	our ($Myname, $ArgExitOnError);
	my ($ExitValue, $Format, @Args) = @_;
	verbose(1, "$Myname: ERROR: $Format", @Args);
	exit $ExitValue if ($ArgExitOnError eq "on");
}


###############
sub GetOptions
{
	our %options;
	our ($ArgExitOnError);
	getopts("hVv:H:p:D:s:E:",\%options) or usage;
	usage   if defined $options{h};
	version if defined $options{V};
	$VerbosityLevel    = $options{v}  if defined $options{v};
	$LdapUris          = $options{H}  if defined $options{H};
	$LdapPort          = $options{p}  if defined $options{p};
	$BindDn            = $options{D}  if defined $options{D};
	$Scope             = $options{s}  if defined $options{s};
	$Base              = $options{b}  if defined $options{b};
	$ArgExitOnError    = $options{E}  if defined $options{E};
	usage unless ($ArgExitOnError =~ /^on$|^off$/);
	usage if $ARGV[0] eq "";
#	usage if $ARGV[1] eq "";
	usage if $ARGV[2] ne "";
	$Filter = $ARGV[0];
	$Attr = defined $ARGV[1] ? $ARGV[1] : '*';
}


##############
sub LdapLookup
{
	our ($ServerCert, $LdapUris, $LdapScheme, $LdapPort, $BindDn, $Base, $Scope);
	my ($Filter, $Attr) = @_;
	my $LdapObj = 0;
	my $LdapUriOk = "<all failed>";
	foreach my $LdapUri (split(/,/, $LdapUris))
	{
		my $UriScheme = $LdapUri; $UriScheme =~ s,://.*,,; $UriScheme = $LdapScheme if $UriScheme eq "";
		my $UriPort   = $LdapUri; $UriPort   =~ s,.*:,,;   $UriPort   = $LdapPort   if $UriPort eq "";
		my $LdapHost  = $LdapUri; $LdapHost  =~ s,$UriScheme://(.*):$UriPort,$1,;
		verbose 2, q#%s: LDAP call "%s://%s:%s" (timeout=%d)#, $LdapUri, $UriScheme, $LdapHost, $UriPort, $StartTimeout;
		if($LdapObj = Net::LDAP->new("$LdapHost", scheme => $UriScheme, port => "$UriPort", version => 3, timeout => $StartTimeout, async => 1))
		{
			$LdapUriOk = $LdapUri;
			last;
		}
		else
		{
			verbose 1, q#LDAP call "%s://%s:%s" FAILED: %s#, $LdapScheme, $LdapUri, $LdapPort, $@;
		}
	}
	error 1, q#LDAP call(s) to "%s" failed (%s)#, $LdapUris, $@ if not $LdapObj; 

#	Need a few Perl modules: search under LDAPS, SSL
#	verbose 2, q#%s: LDAP start_tls "%s"#, $LdapUriOk, $BindDn;
#	my $TlsResult = $LdapObj->start_tls( cafile => $ServerCert );
#	error 1, "%s: LDAP start_tls failed: %s", $LdapUriOk, $TlsResult->error if ($TlsResult->{Error} ne "");
#	verboseDumper 9, qq#$LdapUriOk: variable \$TlsResult#, $TlsResult;

	verbose 2, q#%s: LDAP bind "%s"#, $LdapUriOk, $BindDn;
	my $BindResult = $LdapObj->bind($BindDn, password => $LdapPasswd);
	error 1, "%s: LDAP bind failed: %s", $LdapUriOk, $BindResult->error if ($BindResult->{Error} ne "");
	verboseDumper 9, qq#$LdapUriOk: variable \$BindResult#, $BindResult;

# NOTE: on $SearchResult
#       $SearchResult->{Entries}
#       $SearchResult->{Entries}{attrs}  <-- this is a blessed object so cannot display it like a hash
#
	my $SearchValue = "";
	verbose 2, q#%s: LDAP search base=>"%s", filter=>"%s", attrs=>[%s]#, $LdapUriOk, $Base, $Filter, $Attr;
	my $SearchResult = $LdapObj->search(base => $Base, scope => $Scope, filter => $Filter, attrs => [$Attr]);
	verboseDumper 19, qq#$LdapUriOk: variable \$SearchResult#, $SearchResult;
	foreach my $HashEntry ($SearchResult->entries())
	{
		verboseHash 1, qq#$LdapUriOk: \$HashEntry: #, $HashEntry;
		verbose 1, "";
	}

	verbose 1, qq#$LdapUriOk: Bind Error="%s"#, $BindResult->{Error}     if ($BindResult->{Error} ne "");
	verbose 1, qq#$LdapUriOk: Search Error="%s"#, $SearchResult->{Error} if ($SearchResult->{Error} ne "");

	verbose 2, qq#$LdapUriOk: LDAP unbind#;
	$LdapObj->unbind;
}


########
sub Main
{
	LdapLookup $Filter, $Attr;
}


############
GetOptions;
Main;
exit 0;

