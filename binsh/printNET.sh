#!/bin/bash

# File:         printNET.sh
# Description:  Print network IP from <ip> and <mask|mask num>

VERSION="0.1"

Myname=$(basename $0)


########
Show="n"


#######
usage()
{
    cat >&2 <<EOF

 usage: $Myname [-n|-g] <ip> <mask|mask num>
        $Myname -m <mask num>

 -n     show network (default)
 -g     show gateway as <network> + 1
 -m     show mask in IP format

 Show network IP using <ip> and <mask|mask num>.

 egs. $Myname    10.154.207.105 27               # shows a network of 10.154.207.96
      $Myname -n 10.154.207.105 27               # shows a network of 10.154.207.96
      $Myname -m 27                              # shows a netmask of 255.255.255.224
      $Myname -g 10.154.207.105 27               # shows a gateway of 10.154.207.97
      $Myname -g 10.154.207.105 255.255.255.224  # shows a gateway of 10.154.207.97

EOF
    exit 2
}


#############
GetOptions()
{
	[[ "$1" == "" ]] && usage
	while getopts "ngm2:h?" name
	do
		case $name in
		n) Show="n" ;;
		g) Show="g" ;;
		m) Show="m" ;;
		2) Show="2$OPTARG" ;;
		*) usage ;;
		esac
	done
	ShiftArgs=$(($OPTIND - 1))
}


##############
CheckOptions()
{
	shift $ShiftArgs
	case $Show in
	n)  IP="$1";      MASK="$2"; BlankArg="$3" ;;
	g)  IP="$1";      MASK="$2"; BlankArg="$3" ;;
	m)  IP="0.0.0.0"; MASK="$1"; BlankArg="$2" ;;
	2*) IP="$1";      MASK="$1"; BlankArg="$2" ;;
	*) usage ;;
	esac
	[[ "$IP"       == "" ]] && usage
	[[ "$MASK"     == "" ]] && usage
	[[ "$BlankArg" != "" ]] && usage

	IsNum $MASK && MASK=$(Num2IP $(Masknum2Num $MASK))
	! IsIP $MASK && errexit 1 "MASK \"$MASK\" must be a number or in the format <num>.<num>.<num>.<num>"
	! IsIP $IP   && errexit 1 "IP \"$IP\" must be in the format <num>.<num>.<num>.<num>"
}


########
errexit() { typeset RetCode=$1; shift; echo "$Myname: ERROR: $*" >&2; exit $RetCode; }


##########
IsNum()   { echo "$1" |egrep -q "^[0-9][0-9]*$"; }
IsIP()    { echo "$1" |egrep -q "^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$"; }


############
# GetGW()       eg. "192.168.1.5" "255.255.255.0" yields "192.168.1.1"    network + 1
# GetNET()      eg. "192.168.1.5" "255.255.255.0" yields "192.168.1.0"
# IP2Num()      makes an equation, eg. "192.168.1.5" becomes "192<<24)+(168<<16)+(1<<8)+5" which becomes "3232235781"
# Num2IP()      is the reverse of IP2Num
# Masknum2Num() convert mask number (bit shift) to IP number, eg. Masknum = 15, output = 4294836224 (255.254.0.0)
#               NOTE: for let, use 16# not 0x in case ksh is used.
GetGW()
{
	typeset IP="$1"
	typeset MASK="$2"
	typeset Net
	let "Net=$(IP2Num $IP) & $(IP2Num $MASK)"
	Num2IP $(($Net + 1))
}
GetNET()
{
	typeset IP="$1"
	typeset MASK="$2"
	typeset Net
	let "Net=$(IP2Num $IP) & $(IP2Num $MASK)"
	Num2IP $Net
}
IP2Num()
{
	typeset IP="$1"
	typeset SumIP="("$(echo "$IP" |sed "s/\./<<24)+(/1" |sed "s/\./<<16)+(/1" |sed "s/\./<<8)+/1")
	typeset NumIP
	let "NumIP=$SumIP"
	echo "$NumIP"
}
Num2IP()
{
	typeset NumIP="$1"
	typeset c1
	typeset c2
	typeset c3
	typeset c4
    let "c1=(($NumIP & 16#ff000000)>>24)"
	let "c2=(($NumIP & 16#00ff0000)>>16)"
    let "c3=(($NumIP & 16#0000ff00)>>8)"
	let "c4=( $NumIP & 16#000000ff)"
    echo "$c1.$c2.$c3.$c4"
}
Masknum2Num()
{
	typeset Masknum="$1"
	typeset Num
	let "Num=(16#ffffffff<<(32-$Masknum)) & 16#ffffffff"
	echo $Num
}


######
Main()
{
	case $Show in
	n) GetNET $IP $MASK ;;
	g) GetGW  $IP $MASK ;;
	m) echo $MASK ;;
	2num) IP2Num $IP ;;
	esac
}


################
GetOptions "$@"
CheckOptions "$@"
Main
