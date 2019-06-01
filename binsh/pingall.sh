#!/bin/bash

# Copyright (c) 2005-2019 Colin Pearse.
# All scripts are free in the binscripts repository but please refer to the
# LICENSE file at the top-level directory for the conditions of distribution.
#
# Name:         pingall.sh
# Description:  Ping multiple hosts simultaneously

VERSION="0.2"

Myname=$(basename $0)

###########
###########
HostFile=""
Hosts=""
EgrHosts=""
EgrOpt=""
PingCmd="ping -c2 -w2"

#######
#######
usage()
{
	cat >&2 <<EOF

 usage: $Myname [-e expr] -f file
        $Myname [-e expr] -H hosts

 -f file    run <command> on the list of hosts in this file; this cannot be used with -H
 -H hosts   run <command> on this (comma separated) list of hosts; this cannot be used with -f
 -e expr    case-insensitive expr to restrict the hosts list; !expr excludes, eg. "!^host[01]$"
 -c cmd     ping command (default: \"$PingCmd\")

 This script will ping in parallel the hosts in the file indicated by -f or -H and show the result
 "ok" or "failed". NOTE: "failed" can also mean that the hostname does not have an IP.

 egs. $Myname -e rdc-780-c3 -f /etc/hosts                  # ping hosts that match expression
      $Myname -H myhost1,myhost2,myhost3                   # ping these hosts
      $Myname -c "-nc2 -t2" -f myips                       # ping IPs using MacOS ping args

EOF
	exit 2
}

############
############
GetOptions()
{
	[[ "$1" == "" ]] && usage
	while getopts "f:H:e:c:h?" name
	do
		case $name in
		f) HostFile="$OPTARG" ;;
		H) Hosts="$OPTARG" ;;
		e) EgrHosts="$OPTARG" ;;
		c) PingCmd="$OPTARG" ;;
		*) usage ;;
		esac
	done
	shift $(($OPTIND - 1))
	[[ "$1" != "" ]] && usage
}

##############
##############
CheckOptions()
{
	echo "$EgrHosts" |egrep -q "^!" && EgrOpt="v"  # this will be next to -i
	EgrHosts=$(echo "$EgrHosts" |sed "s/^!//1")

	typeset HostList
	if [[ "$Hosts" != "" ]]
	then
		HostList=$(echo $Hosts |tr ',' '\n')

	elif [[ "$HostFile" != "" ]]
	then
		! test -r $HostFile && errexit 1 "file \"$HostFile\" does not exist or is not readable"
		HostList=$(egrep "^[a-zA-Z0-9_]" $HostFile)
	else
		errexit 2 "you must specify either -f or -H"
	fi

	Hosts=$(echo "$HostList" |egrep -i$EgrOpt -- "$EgrHosts" |awk '{print $1}' |nasort.pl -u |xargs echo)
	HostCount=$(echo "$Hosts" |wc -w |awk '{print $1}')
	(($HostCount == 0)) && errexit 1 "0 valid hosts identified - please check options, hostnames or hostfile"
}

########
########
errexit()
{
	typeset ExitValue=$1; shift
	echo "$Myname: ERROR: $@" >&2
	exit $ExitValue
}

#############
#############
DisplayCmds()
{
	for Host in "$@"
	do
		echo "$PingCmd $Host >/dev/null 2>&1 && printf '\n$Host: ok\n' || printf '\n$Host: failed\n'&"
	done
	echo "wait"
}

#######
#######
Main()
{
	typeset ExecCmds=$(DisplayCmds $Hosts)
	echo "Running \"$PingCmd\" on $HostCount host(s):" >&2

	typeset Output=$(sh -c "$ExecCmds" |egrep -v "^$" |nasort.pl)
	echo "$Output"

	typeset Oks=$(     echo "$Output" |egrep -i ": ok$"     |wc -l |awk '{print $1}')
	typeset Failures=$(echo "$Output" |egrep -i ": failed$" |wc -l |awk '{print $1}')
	typeset CheckTotal=$(($Oks + $Failures))
	echo "Ok=$Oks Failures=$Failures" >&2

	(($CheckTotal != $HostCount)) && errexit 1 "ok+failed != hostcount ($Oks+$Failures != $HostCount) - please check"
	(($Failures   != 0))          && errexit 1 "$Failures ping failure(s)"
}

#########
#########
GetOptions "$@"
CheckOptions
Main
exit 0

# reduce possibility of overlapping text by using newlines above. Then make it readable by removing them below

