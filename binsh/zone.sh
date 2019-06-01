#!/usr/bin/bash


# Copyright (c) 2005-2019 Colin Pearse.
# All scripts are free in the binscripts repository but please refer to the
# LICENSE file at the top-level directory for the conditions of distribution.
#
# Name:         zone.sh
# Description:  Create or remove a Solaris zone


[[ "$Debug" == "" ]] && Debug=0
(($Debug>=3)) && set -x

export PATH=/usr/xpg4/bin:$PATH

Myname=$(basename $0)
Zonedir="/zones"
Tempfile="/tmp/$Myname.tmp"

###################
###################
Usage()
{
	cat <<EOF >&2

 usage: $Myname <zonename> <root type> <nic> <zone hostname> <zone ip> <zone netmask>  <zone gateway>
 usage: $Myname -r <zonename>

        Create or remove a Solaris zone (or application container in Sun/Oracle speak).

    eg. $Myname zone1 whole e1000g0 myhost1 172.1.2.10 255.255.255.0 172.1.2.2
        $Myname zone2 sparce e1000g0 myhost2 172.1.2.11 255.255.255.0 172.1.2.2
        $Myname -r zone2

EOF
	exit 2
}

###################
###################
GetVars()
{
	(($Debug>=9)) && set -x
	:
	: GetVars
	:
	! test -d $Zonedir && echo "$Myname: Error: Zonedir $Zonedir does not exist" >&2 && exit 2 
	[[ "$(id -u)" != 0 ]] && echo "$Myname: Error: Must be root to run this" >&2 && exit 2 
	if [[ "$1" != "-r" ]]
	then
		CreateZone=1
		Zonename=$1
		RootType=$2
		ZoneNIC=$3
		ZoneHostname=$4
		ZoneIP=$5
		ZoneNetmask=$6
		ZoneGateway=$7
		[[ "$ZoneGateway" == "" ]] && Usage
	else
		CreateZone=0
		Zonename=$2
		[[ "$Zonename" == "" ]] && Usage
	fi
}

###################
###################
remove_zone()
{
	(($Debug>=5)) && set -x
	:
	: remove_zone $*
	:
	typeset Zonename=$1
	echo "Halting $Zonename"
	zoneadm -z $Zonename halt
	echo "Uninstalling $Zonename"
	zoneadm -z $Zonename uninstall -F
	echo "Deleting $Zonename"
	zonecfg -z $Zonename delete -F
}	
	
###################
###################
# Automatically set the zone up at boot time
# On boot - any errors are sent to the console and will stop configuration
create_zone_sysidcfg()
{
	(($Debug>=5)) && set -x
	:
	: create_zone_sysidcfg $*
	:
	typeset ZoneHostname=$1
	typeset ZoneIP=$2
	typeset ZoneNetmask=$3
	typeset ZoneGateway=$4
	# root password is abc123 - passwds encrypted with special characters will cause a 'syntax error' to occur on boot
	cat <<EOF
system_locale=C
timezone=Europe/London
timeserver=localhost
terminal=xterm
name_service=NONE
service_profile=OPEN
security_policy=NONE
nfs4_domain=dynamic
root_password=MNY4FaPMbBnRs
network_interface=PRIMARY {hostname=$ZoneHostname ip_address=$ZoneIP netmask=$ZoneNetmask protocol_ipv6=no default_route=$ZoneGateway}
EOF

}

###################
###################
# Whole root (create -b) will have its own copy of /usr /lib /platform and /sbin.
# Sparce root (no -b) will use the global zone's copy and mount them readonly.
create_zone_template()
{
	(($Debug>=5)) && set -x
	:
	: create_zone_template $*
	:
	typeset	RootType=$1
	typeset	Zonename=$2
	typeset	ZoneIP=$3
	typeset	ZoneNIC=$4
	CreateFlag=""; [[ "$RootType" == "whole" ]] && CreateFlag="-b"
	cat <<EOF
create $CreateFlag
set zonepath=$Zonedir/$Zonename
set autoboot=true
add net
set address=$ZoneIP
set physical=$ZoneNIC
end
commit
EOF
}

###################
###################
create_zone()
{
	(($Debug>=5)) && set -x
	:
	: create_zone $*
	:
	typeset Template=$1
	typeset Zonename=$2
	typeset ZoneRoot=$Zonedir/$Zonename/root

	echo; echo "Creating $Zonename"
	zonecfg -z $Zonename -f $Tempfile.zone
	echo; echo "Installing $Zonename"
	zoneadm -z $Zonename install
#	zoneadm -z $Zonename verify

#	change? $ZoneRoot/etc/svc/profile/generic.xml
#   echo "<network> <netmask>" >> /zones/zone2/root/etc/inet/netmasks
	cp /etc/resolv.conf $ZoneRoot/etc/
	cp /etc/default/login $ZoneRoot/etc/default/
	cp $ZoneRoot/etc/ssh/sshd_config $ZoneRoot/etc/ssh/sshd_config.save
	cat $ZoneRoot/etc/ssh/sshd_config.save |sed "s/^PermitRootLogin.*/PermitRootLogin yes/1" > $ZoneRoot/etc/ssh/sshd_config
}

###################
###################
# Main
GetVars "$@"
set -e
if (($CreateZone))
then
	echo "Creating the template: $Tempfile.zone"
	create_zone_template $RootType $Zonename $ZoneIP $ZoneNIC > $Tempfile.zone
	create_zone $Tempfile.zone $Zonename
	create_zone_sysidcfg $ZoneHostname $ZoneIP $ZoneNetmask $ZoneGateway > $Zonedir/$Zonename/root/etc/sysidcfg
	echo; echo "Readying $Zonename"
	zoneadm -z $Zonename ready
	echo; echo "Booting $Zonename - root password is abc123"
	zoneadm -z $Zonename boot
	# zlogin $Zonename "uname -a"  # test host has booted
	# zlogin $Zonename "svcadm enable svc:/network/ssh:default"
	# zlogin -C $Zonename  # system shouldn't need configuring if sysidcfg did its job
else
	remove_zone $Zonename
fi
exit 0

