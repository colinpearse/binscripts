#!/bin/bash


# Copyright (c) 2005-2019 Colin Pearse.
# All scripts are free in the binscripts repository but please refer to the
# LICENSE file at the top-level directory for the conditions of distribution.
#
# Author:      Colin Pearse
# Description: Part of bootablebackup.sh. Linux backup. The LVM and disk commands are specifically Linux but not the backup itself.


myname=$(basename $0)
TMPDIR="/tmp"
DebugFile="$TMPDIR/$myname.debug"

DEF_ExcludeDirs=""
ExcludeDirs="$DEF_ExcludeDirs"

usage()
{
	cat >&2 <<EOF

usage: $myname <-p|-x> [-v VgName] [-e ExcludeDirs] [-s MBforbu] -b BackupDir [Filesystem[...]]

	-p  Preview (for checking space available).
	-x  Execute.
	-v  Create backup filesystem on this volume group.
	-s  Specify size in MB of backup directory (don't guess).
	-b  Backup directory (this should not exist).
	-e  Exclude directories (default is "$DEF_ExcludeDirs").
	    NOTE: The BackupDir is always excluded regardless.

	NOTE: getfileinfo.sh -p will guess filesystems on root disk

   eg. $myname -x -v rootvg -b /backupdir / /boot /usr /opt /var
   eg. $myname -x -e "/lib /bin" -b /var/backup / /boot

EOF
	exit 2
}
get_args()
{
	ALL_ARGS="$*"
	p_OPT=0 ; x_OPT=0 ; v_OPT=0 ; s_OPT=0 ; b_OPT=0 ; e_OPT=0
	MBforbu=""
	while getopts "pxv:s:b:e:h?" name
	do
		case $name in
		p)      p_OPT=1 ;;
		x)      x_OPT=1 ;;
		s)      s_OPT=1 ; MBforbu="$OPTARG" ;;
		v)      v_OPT=1 ; VgName="$OPTARG" ;;
		b)      b_OPT=1 ; BackupDir="$OPTARG" ;;
		e)      e_OPT=1 ; ExcludeDirs="$OPTARG" ;;
		h|?|*)  usage ;;
		esac
	done
	shift $(($OPTIND - 1))
	BackupFss="$*"
	(($p_OPT==$x_OPT)) && usage
	[[ "$BackupFss" == "" || "$BackupDir" == "" ]] && usage
	test -d "$BackupDir" && printf "\nERROR: BackupDir $BackupDir should not exist.\n\n" >&2 && exit 2

	(($s_OPT==1)) && ! expr $MBforbu + 0 >/dev/null 2>&1 && printf "\nERROR: MBs for backup is not numeric ($MBforbu).\n\n" >&2 && exit 2
}
check_space()
{
	MBused=$(echo "0 "$(df -k $BackupFss |tail +2 |awk '{print $2}' |egrep "^[0-9]" |awk '{print $1" + "}')" 1024 / p" |dc)
	echo "Used space: $MBused MB"

	if (($v_OPT==1))  # is volume group specified
	then
		VGout=$(vgdisplay -c 2>/dev/null |grep "$VgName:")
		PEsizeKB=$(echo "$VGout" |cut -d':' -f13)
		PEfree=$(echo   "$VGout" |cut -d':' -f16)
		MBfree=$(echo "$PEsizeKB $PEfree * 1024 / p" |dc)
		echo "Free space: $MBfree MB"
		echo "Filesystem to be created: $BackupDir on $VgName."
	else
		DFline=$(df -k $(dirname $BackupDir) |tail -1)
		MBfree=$(echo "0 "$(echo "$DFline" |awk '{print $3}' |egrep "^[0-9]")" 1024 / p" |dc)
		FSname=$(echo "$DFline" |awk '{print $NF}')
		echo "Free space: $MBfree MB"
		echo "Directory to be created: $BackupDir on the $FSname filesystem."
	fi

	if [[ "$MBforbu" == "" ]]
	then
		MBforbu=$(($MBused / 2))
		echo "For backup I will use: $MBforbu MB (Used space / 2)"
	else
		echo "For backup I will use: $MBforbu MB (User specified)"
	fi
	# Space required for gz files (not necessarily ISO image too since that can be specfied elsewhere)
	(($MBfree < $MBforbu)) && printf "\nERROR: Not enough space for backup. I need $MBforbu MB.\n\n" && exit 1
}

show_error()
{
	set +xe
	exec 1>&3
	echo
	echo "ERROR ======= last 10 lines of logfile: $DebugFile"
	tail -10 $DebugFile
	echo "ERROR ================================="

	# cleanup (get_args tests whether dir existed so we can be sure we created it)
	echo "Cleaning up." >&3
	mount |grep -q " $BackupDir " && umount $BackupDir
	test -b /dev/$vg/tmpbackuplv && lvremove -f /dev/$vg/tmpbackuplv
	test -d $BackupDir && rm -rf $BackupDir
	exit 1
}


createfs()
{
	vg=$1
	lv=$2
	fs=$3
	size=$4
	fstype=$5
	set -x
	lvcreate -L $size -n $lv $vg
	mkfs.$fstype /dev/$vg/$lv
	mkdir -p $fs
	mount /dev/$vg/$lv $fs
	set +x
}

# Awk is better for display than xargs here (keeps the original spacing)
runcmd()
{
	#$* 2>&1 |xargs -i echo "$*:"{}
	$* 2>&1 |awk -v cmd="$*" '{print cmd":"$0}'
}

# Only one primary disk saved for now. Other disks that belong to RootVg will be seen and
# included via pvdisplay -c but they won't be re-partitioned.
# fdisk -l saved since the geometry (heads, sectors/track, cylinders) is more accurate than sfdisk -g.
savediskinfo()
{
	# Establish whether GRUB or LILO
	if test -r /etc/grub.conf ; then echo "GrubConf:yes"; else echo "GrubConf:no"; fi
	if test -r /etc/lilo.conf ; then echo "LiloConf:yes"; else echo "LiloConf:no"; fi

	# TO DO: /boot is hardcoded - maybe ls -ld /*/grub/device.map should be used to set HardDisk
	#        and then name "/boot" can be obtained from that.
	# For getting actual disk of root vg partition, first line for /dev/sda, second for type /dev/cciss/c0d0
	DiskBoot=$(mount |awk '{if($3~/^\/boot$/){print $1}}')
	echo "$DiskBoot" |grep -q "1$"       && HardDisk=$(echo "$DiskBoot" |sed "s/1$//1")
	echo "$DiskBoot" |egrep -q "/c.*p1$" && HardDisk=$(echo "$DiskBoot" |sed "s/p1$//1")

	echo "HardDisk:$HardDisk"
	runcmd sfdisk -d $HardDisk
	runcmd fdisk -l $HardDisk
	runcmd pvdisplay -c
	runcmd vgdisplay -c
	runcmd lvdisplay -ca
	runcmd cat /etc/fstab
	runcmd mount

	# get labels (currently for information purposes only - currently restorehost.sh obtains the boot
	# disk label from the .etc.fstab file).
	runcmd e2label $DiskBoot
	SwapLvs=$(egrep -v "^#" /etc/fstab |awk '{if($3~/^swap$/){print $1"|"}}' |tr -d '\n')"dont_match"
	lvdisplay -ca |cut -d':' -f1 |egrep -v "$SwapLvs" |while read lv
	do
		# If a non-fs exists (like swap) that is not in fstab then don't exit the shell with an error.
		set +e
		runcmd e2label $lv
		set -e
	done
}
savediskinfo_readable()
{
	runcmd df -k
	runcmd sfdisk -d
	runcmd fdisk -l
	runcmd pvdisplay -v
	runcmd vgdisplay -v
	for lv in $(vgdisplay -v 2>/dev/null |grep 'LV Name' |awk '{print $3}')
	do
		runcmd lvdisplay $lv
	done
	runcmd pvs
	runcmd vgs
	runcmd lvs
}

backupfss()
{
	set -x
	BackupFiles=""
	for fs in $*
	do
		displayfs=$(echo "$fs" |sed "s,/,_slash_,g")
		CpioGz=$BackupDir/$myname.$displayfs.cpio.gz

		# Since the exclude dirs are absolute pathnames and find displays relative pathnames EGRforfs
		# is changed so that only those directories in the relevant filesystem are matched.
		#  eg. when exclude dirs is " /backup /var/backup /var/log /usr/lib" 
		#  ... and fs=/    egrep string will be "^./backup|^./var/backup|^./var/log|^./usr/lib"
		#  ... and fs=/var egrep string will be "^/backup|^./backup|^./log|^/usr/lib"
		EGRforfs=$(echo " $BackupDir $ExcludeDirs" |sed "s, $fs, ./,g;s,//,/,g;s, ,|^,g;s,^|,,1;s,|^$,,1;s,^^$,,1")

		printf "$(date): Backing up: %-10.10s to $CpioGz\n" "$fs" >&3
		pushd $fs
		find . -xdev -print |egrep -v "$EGRforfs" |cpio -oc |gzip -c >$CpioGz
		popd
		BackupFiles="$BackupFiles $CpioGz"
	done
	ls -ld $BackupFiles >&3
}


##########
# Main
##########

get_args "$@"
(($p_OPT==1)) && DiskVgConf="$myname.disk_and_vg.conf.preview" && DiskVgReadable="$myname.disk_and_vg.readable.preview"
(($x_OPT==1)) && DiskVgConf="$myname.disk_and_vg.conf"         && DiskVgReadable="$myname.disk_and_vg.readable"

check_space
echo "$(date): Saving disk and vg information to $TMPDIR/$DiskVgConf (and $TMPDIR/$DiskVgReadable)"
savediskinfo >$TMPDIR/$DiskVgConf
savediskinfo_readable >$TMPDIR/$DiskVgReadable

(($p_OPT==1)) && echo "$(date): Preview mode finished." && exit 0

###
# Save stdout (file or tty) in case this exits with an error and
# ensure all detailed output goes to the logfile.
exec 3>&1
exec >$DebugFile 2>&1
trap show_error ERR
set -E
echo >&3
echo "$(date): DebugFile is: $DebugFile" >&3

###
if (($v_OPT==0))
then
	echo "$(date): Creating backup directory: $BackupDir" >&3
	mkdir -p $BackupDir
else
	echo "$(date): Creating backup filesystem: $BackupDir (size ${MBforbu} MB)" >&3
	createfs rootvg tmpbackuplv $BackupDir ${MBforbu}M ext3
fi

###
echo "$(date): Copying vg information to $BackupDir" >&3
cp -p $TMPDIR/$myname.disk_and_vg.conf $BackupDir
cp -p $TMPDIR/$myname.disk_and_vg.readable $BackupDir

###
echo "$(date): Backing up: $BackupFss"
backupfss $BackupFss

echo "$(date): Done $myname" >&3
echo >&3

exit 0

