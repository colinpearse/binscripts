#!/bin/bash


# Copyright (c) 2005-2019 Colin Pearse.
# All scripts are free in the binscripts repository but please refer to the
# LICENSE file at the top-level directory for the conditions of distribution.
#
# Name:         zonesnapshot.sh
# Description:  borrow disk from sparedg and make a snapshot of a zone; revert a snapshot and put back the disk


VERSION="0.1"

Myname=$(basename $0)

#########
DiskPrefix="emcpower"
AddSpareDisk=0
HasSnapVol=0

########
Exec=0
ExecStr="Preview"
Operation=""
Zone=""
ZoneDg=""
KeepDisk=0
SpareDg="sparedg"
Action=""


#######
usage()
{
    cat >&2 <<EOF

 usage: $Myname -o op -z zone snapshot
        $Myname -o op -z zone haltrevert

 -o op    "p"review or e"x"ecute
 -z zone  zone; data group of zone (where zonepath resides) must be the same name as the zone
 -k       keep spare disk on "haltrevert" action (default: return disk to spare data group)
 -d dg    data group where spare disks reside (default: $SpareDg)

 Actions:
 snapshot    Take a snapshot using a borrowed disk from the spare dg: $SpareDg
 haltrevert  Halt zone, revert to the snapshot and return the disk to the spare dg: $SpareDg
             NOTE: there is no point shutting down cleanly for revert since the snapshot will be that of a running zone

 NOTE: if a snapshot volume exists already then a refresh is done
 NOTE: this currently only works for zonepaths, ie. filesystems are not implemented yet 

 HARDCODED: DiskPrefix="$DiskPrefix"

 egs. $Myname -o p -z mysol-z1 snapshot    # preview commands to take a snapshot
      $Myname -o x -z mysol-z1 snapshot    # execute the above
      $Myname -o p -z mysol-z1 haltrevert  # preview commands to halt, revert and return disk
      $Myname -o x -z mysol-z1 haltrevert  # execute the above

EOF
    exit 2
}


#############
GetOptions()
{
	[[ "$1" == "" ]] && usage
	while getopts "o:z:kd:h?" name
	do
		case $name in
		o) Operation="$OPTARG" ;;
		z) Zone="$OPTARG"; ZoneDg="$Zone" ;;
		k) KeepDisk=1 ;;
		d) SpareDg="$OPTARG" ;;
		*) usage ;;
		esac
	done
	ShiftArgs=$(($OPTIND - 1))
}


##############
CheckOptions()
{
	shift $ShiftArgs
	Action="$1"
	case $Operation in
	p) Exec=0; ExecStr="Preview" ;;
	x) Exec=1; ExecStr="Execute" ;;
	*) errexit 2 "-o can only be \"p\" or \"x\"" ;;
	esac
}

#########
SetVars()
{
	VxPrintZoneDgInfo=$(vxprint -g $ZoneDg)
	if echo "$VxPrintZoneDgInfo" |egrep "^v .*-snap" >/dev/null 2>&1
	then
		AddSpareDisk=0
		HasSnapVol=1
		SpareDisk=$(echo "$VxPrintZoneDgInfo" |egrep "^sd .*-snap" |head -1 |awk '{print $2}' |cut -d- -f1 |uniq |xargs echo)  # should be one disk, eg. emcpower558
		[[ "$SpareDisk" == "" ]] && errexit 1 "snap volume exists but cannot find a spare disk using vxprint -g $ZoneDg |egrep \"^sd .*-snap\""
	else
		AddSpareDisk=1
		HasSnapVol=0
		VxPrintSpareDgInfo=$(vxprint -g $SpareDg)
		SpareDisk=$(echo "$VxPrintSpareDgInfo" |egrep "^dm " |awk '{print $2}' |head -1 |xargs echo)
		[[ "$SpareDisk" == "" ]] && errexit 1 "no snap volume exists and cannot find a spare disk in $SpareDg"
	fi
	Vols=$(echo "$VxPrintZoneDgInfo" |egrep "^v " |egrep -v -- "-snap |-snap_dcl |_dcl " |awk '{print $2}' |uniq |xargs echo)  # should be original volumes
}
SetVolVars()
{
	typeset Vol="$1"
	DclVol="${Vol}_dcl"
	SnapVol="${Vol}-snap"
	SnapDclVol="${Vol}-snap_dcl"
	VolDev="/dev/vx/dsk/$ZoneDg/$SnapVol"

	Vols=$(echo "$VxPrintZoneDgInfo" |egrep "^v  *$Vol" |awk '{print $2}' |xargs echo)
	case $Vols in
	"$Vol")
		# vol size
		VolSize=$(echo "$VxPrintZoneDgInfo" |egrep "^v *$Vol " |awk '{print $5}' |xargs echo |head -1)  # in sectors of 512 bytes
		! IsNum $VolSize && errexit 1 "$ZoneDg: $Vol: volume size is not numeric \"$VolSize\""
		# disk used
		VxPrintVolInfo=$(vxprint -g $ZoneDg $Vol)
		VolDisk=$(echo "$VxPrintVolInfo" |egrep "^sd " |awk '{print $2}' |cut -d- -f1 |uniq |xargs echo)  # should be one disk, eg. emcpower4
		! IsOneDisk $VolDisk && errexit 1 "$ZoneDg: $Vol: none or more than one disk found: $VolDisk"
		echo "NOTICE: volume \"$Vol\" size is $VolSize sectors ($(($VolSize*512/1024/1024/1024)) MB)"
		echo "NOTICE: volume \"$Vol\" uses disk \"$VolDisk\""
		echo "NOTICE: spare disk to be used is \"$SpareDisk\" (from $SpareDg)"
		;;
	"$Vol $DclVol")
		errexit 1 "$ZoneDg: unexpected volume order, vols=\"$Vols\" - did procedure quit half-way through?"
		;;
	"$Vol $DclVol $SnapVol")
		errexit 1 "$ZoneDg: unexpected volume order, vols=\"$Vols\" - did procedure quit half-way through?"
		;;
	"$Vol $DclVol $SnapVol $SnapDclVol")
		! IsOneDisk $SpareDisk && errexit 1 "$ZoneDg: $SnapVol: none or more than one disk found: $SpareDisk"
		echo "NOTICE: $SnapVol uses spare disk \"$SpareDisk\""
		if [[ "$Action" == "haltrevert" ]]
		then
			(($KeepDisk)) && echo "NOTICE: spare disk \"$SpareDisk\" will be kept" || echo "NOTICE: spare disk \"$SpareDisk\" will be returned to $SpareDg"
		fi
		;;
	*)
		errexit 1 "$ZoneDg: unknown volume(s) or order, vols=\"$Vols\" (expected: \"$Vol\", with or without snapshot and dcl volumes)"
		;;
	esac
}

########
Heading() { typeset Lines=$(echo "$*" |sed "s/./-/g"); printf "%s\n%s\n%s\n" "$Lines" "$*" "$Lines"; }
errexit() { typeset RetCode=$1; shift; echo "$Myname: ERROR: $*" >&2; exit $RetCode; }

########
IsNum()      { echo "$1" |egrep "^[0-9][0-9]*$" >/dev/null; }
IsOneDisk()  { echo "$*" |egrep "^$DiskPrefix[0-9][0-9]*$" >/dev/null; }

################
# SetCmdAndArgs() - put single quotes around every arg with a space in.
# printcmd*()     - run $CmdAndArgs with quotes to preserve args
#                   NOTE: If stdout/stderr needs to be redirected then the special characters must be escaped.
#                         eg1. printcmd ls -l \>/tmp/output 2\>\&1
#                         eg2. printcmd ls -l '>' /tmp/output '2>&1'
SetCmdAndArgs()
{
	CmdAndArgs=""
	for Arg in "$@"
	do
		if echo "$Arg" |grep " " >/dev/null
		then
			CmdAndArgs="$CmdAndArgs${CmdAndArgs:+ }'$Arg'"
		else
			CmdAndArgs="$CmdAndArgs${CmdAndArgs:+ }$Arg"
		fi
	done
}
printcmd_noexit()
{
	SetCmdAndArgs "$@"
	printf "$ExecStr: %s\n" "$CmdAndArgs"  # use printf is case $CmdAndArgs includes '\n' characters
	RetCode=0
	if (($Exec))
	then
		sh -c "$CmdAndArgs"
		RetCode=$?
	fi
	return $RetCode
}
printcmd()
{
	! printcmd_noexit "$@" && errexit $RetCode "RetCode=$RetCode:$CmdAndArgs"
}


#################
MountUmountVols()
{
	typeset Cmd="$1"; shift
	typeset Vols="$*"
	typeset VolsFs
	typeset VolFs
	for Vol in $*
	do
		VolFs=$(egrep "^/dev/vx/dsk/$ZoneDg/$Vol " /etc/vfstab |awk '{print $3}')
		VolsFs="$VolsFs $VolFs"
	done
	typeset SortArg
	[[ "$Cmd" == "mount" ]] && SortArg="" || SortArg=" -r"
	VolsFs=$(echo $VolsFs |tr ' ' '\n' |sort$SortArg)
	for VolFs in $VolsFs
	do
		printcmd $Cmd $VolFs
	done
}
MountVols()  { MountUmountVols "mount"  "$@"; }
UmountVols() { MountUmountVols "umount" "$@"; }

######
Main()
{
	Heading "$ExecStr: $Action"
	SetVars

	case $Action in
	snapshot)
		if (($AddSpareDisk))
		then
			printcmd vxdg -g $SpareDg rmdisk $SpareDisk
			printcmd vxdg -g $ZoneDg adddisk $SpareDisk
		fi
		for Vol in $Vols
		do
			SetVolVars $Vol
			if ((! $HasSnapVol))
			then
				printcmd vxsnap -g $ZoneDg -b prepare $Vol                               # prep vol; vxprint shows new vol ${Vol}_dcl
				printcmd vxassist -g $ZoneDg make $SnapVol 33554432                      # make snapvol; vxprint shows new vol $SnapVol
				printcmd vxsnap -g $ZoneDg -b prepare $SnapVol                           # prep snapvol; vxprint shows new vol $SnapVol-dcl
				printcmd vxsnap -g $ZoneDg -o nofreeze make source=$Vol/snapvol=$SnapVol # link the two vols
			fi
			printcmd vxsnap -g $ZoneDg refresh $SnapVol source=$Vol
			echo "$ZoneDg: $Vol: snapshot created on \"$SnapVol\" (dev=\"$VolDev\")"
		done
		;;
	haltrevert)
		(($HasSnapVol)) && errexit 1 "$ZoneDg: $Vol: cannot revert because \"$SnapVol\" does not exist"

		printcmd zoneadm -z $ZoneDg halt
		printcmd sleep 120
		UmountVols $Vols
		printcmd sleep 60

		for Vol in $Vols
		do
			SetVolVars $Vol
			printcmd vxsnap -g $ZoneDg refresh $Vol source=$SnapVol
		done
		MountVols $Vols
		printcmd zoneadm -z $ZoneDg boot
		echo "$ZoneDg: $Vol: reverted to snapshot \"$SnapVol\" (dev=\"$VolDev\")"

		if ((! $KeepDisk))
		then
			for Vol in $Vols
			do
				SetVolVars $Vol
				printcmd vxsnap -g $ZoneDg dis $SnapVol          # disassociate snap
				printcmd vxedit -f -g $ZoneDg -r rm $SnapVol     # remove snap volume
				printcmd vxsnap -f -g $ZoneDg -b unprepare $Vol  # remove the DCL volume
			done
			printcmd vxdg -g $ZoneDg rmdisk $SpareDisk
			printcmd vxdg -g $SpareDg adddisk $SpareDisk
			echo "$ZoneDg: $Vol: snapshot \"$SnapVol\" removed and spare disk \"$SpareDisk\" returned to $SpareDg"
		fi
		;;
	*)
		errexit 2 "<action> can only be \"snapshot\" or \"haltrevert\""
		;;
	esac
}

################
GetOptions "$@"
CheckOptions "$@"
Main
