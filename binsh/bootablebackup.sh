#!/bin/bash

# Copyright (c) 2005-2019 Colin Pearse.
# All scripts are free in the binscripts repository but please refer to the
# LICENSE file at the top-level directory for the conditions of distribution.
#
# Name:       bootablebackup.sh
# Desription: Bootable backup because mindi could not make an ISO that worked with vmedia. See below for scripts/files needed.


# Scripts/files that make up suite:
# --------------------------------
#  RIPLinux.iso bootablebackup.sh makeiso.sh getfileinfo.sh difffileinfo.sh backuphost.sh restorehost.sh
#  chmod 755 bootablebackup.sh makeiso.sh getfileinfo.sh difffileinfo.sh backuphost.sh restorehost.sh
#
# This was written because mindi could not make an ISO (more importantly the ext2 boot image) that worked with vmedia
# (even with the recommended changes the various HW I used).
# The virtual BIOS didn't have netboot (CD, USB, floppy or harddisk only) and I wanted a simple 1 step recover.
# ie. restore in one go from the ISO. A 2 step process would be; load ISO, that kernel would find files on remote server
# (like kickstart). It could be automatic too but I didn't want an ISO plus other files residing on another server.
#
# If large non-critical filesystems and directories are typically excluded (eg. /home /var/cache/) because they are
# backed up by another method and this will obviously be another step to full recovery.
#
# Runs:
# 1. getsysinfo.sh
# 2. backuphost.sh
# 3. makeiso.sh
# 4. removes backup dir/fs used
#
# A recovery option (RIPLinux login) is always available, to enable network do:
#  ifconfig eth0 $IP netmask $netmask
#  route add default gw $gw
#  sh /etc/rc.d/rc.sshd start
# Now you should be able to connect.
#
# TO DO:  This assumes LVM for the root disk(s). This should work with a normal partitioned root disk(s).
# TO DO:  Create status for cpio restore (save filelist and compare when restoring with -v (there are too many files for cpio -V))
# TO DO:  If BackupDir (dir/fs) is left behind due to error then have option to delete and recreate it on re-run.
# TO DO:  Make sure makeiso.sh does not leave behind unpacked stuff.
# TO DO:  Only Boot partition label is taken care of. No check for labels on other filesystems.
# TO DO:  (do I need to do a fsck -fpv on all filesystems before the reboot?)
# TO DO:  LILO is not catered for yet (although backuphost.sh does report whether the /etc/lilo.conf exists).
# TO DO:  /boot is hardcoded and used to set HardDisk. Maybe grub/lilo should be used to set this.
# TO DO:  Another script to create any other application lvs on other vgs to aid entire restore?
# TO DO:  prescript.sh / postscript.sh are picked up if in the same dir as makeiso.sh, restorehost.sh can use them
#         if they exist. They are copied to /tmp and run using . so if pre/post is used the scripter has to be aware that -E will be
#         in effect, stdout/err goes to a debug file in /tmp, fd=3 goes to the screen and $NewRootDir is where the restored fs' are
#         mounted. If pre/post stuff proves useful a tidier solution should be written.
#
# DONE: Now you can output an ISO image. Found it easier to use a pipe file than use the stdout from mkisofs.
# DONE: Re-partitioning a different size root disk could is automatic.
# DONE: Cleanup and remove the BackupDir on error.
#

myname=$(basename $0)
HOSTNAME=$(uname -n)

BackupName="$HOSTNAME"
BBpipe="/tmp/bbpipe"

usage()
{
	cat >&2 <<EOF

usage: $myname [-n BackupName] [-v VgName] [-e ExcludeDirs] [-E ExcludeFss] [-I IncludeFss] -f FileInfo [-k] [-s MBforbu] -b BackupDir -o BootableISO

	-n  Backup name (default is "$HOSTNAME").
	-v  Create backup filesystem on this volume group.
	-x  Extra gz cpio file to restore last of all after cd /.
	-e  Exclude directories (default is "").
	    NOTE: The BackupDir is always excluded regardless.
	-E  Exclude filesystems.
	-I  Include filesystems. If not specified getfileinfo.sh -p is used to guess root filesystems.
	-s  Specify size in MB of backup directory (don't guess).
	-b  Backup directory (this should not exist).
	-k  Keep backup filesystem/directory after ISO has been created.
	-o  Filename for bootable ISO (or use - for stdout).
	-f  Zipped tarfile containing file information collected by getfileinfo.sh.
	    NOTE: This has to be on a filesystem that will be backed up otherwise the restore cannot be checked.
	          To check after a restore: run getfileinfo.sh (same includes/excludes) and then difffileinfo.sh.

	NOTE: The RIPLinuxISO used for booting and re-creating the volume groups
              is the latest RIPLinux found in the directory of this executable.

   eg. $myname -f /root/before.tgz -v rootvg -b /backupdir -E "/tmp /home" -o "/var/pxlamgt1_bootablebackup.iso"
   eg. $myname -f /root/before.tgz -n pxlamgt1 -v rootvg -b /backupdir -e "/etc/sysconfig/network-scripts/" -E "/tmp /home" -x /root/pxlamgt1_network_settings.cpio.gz -o "/unix infrastructure/pxlamgt1_bootablebackup (pymgt1 files).iso"
   eg. $myname -f /root/before.tgz -n test -b /var/backupdir -o "/unix infrastructure/test.iso" -I /boot    # test

 TO COMPARE AFTER RESTORE use the same includes/excludes as backuphost.sh used (shown in output log):
      getfileinfo.sh -x -f /root/after.tgz -e "\$ExcludeDirs" -E "\$ExcludeFss" -I "\$IncludeFss"
      difffileinfo.sh -b /root/before.tgz /root/after.tgz
      NOTE: /var/lib/rpm/__db* files are removed when a selinux relabel is done on rpm's restored db files.

EOF
	exit 2
}
get_args()
{
	CmdLine="$0"
	for Arg in "$@"
	do
		if echo "$Arg" |grep -q " "
		then CmdLine="$CmdLine '$Arg'"
		else CmdLine="$CmdLine $Arg"
		fi
	done

	ALL_ARGS="$*"
	n_OPT=0 ; v_OPT=0 ; k_OPT=0 ; f_OPT=0 ; A_OPT=0 ; s_OPT=0 ; b_OPT=0 ; x_OPT=0 ; o_OPT=0 ; e_OPT=0 ; E_OPT=0 ; I_OPT=0
	MBforbu=""
	while getopts "n:v:f:e:x:E:I:s:b:ko:h?" name
	do
		case $name in
		n)      n_OPT=1 ; BackupName="$OPTARG" ;;
		v)      v_OPT=1 ; VgName="$OPTARG" ;;
		f)      f_OPT=1 ; FileInfo="$OPTARG" ;;
		x)      x_OPT=1 ; ExtraCpioGz="$OPTARG" ;;
		e)      e_OPT=1 ; ExcludeDirs="$OPTARG" ;;
		E)      E_OPT=1 ; ExcludeFss="$OPTARG" ;;
		I)      I_OPT=1 ; IncludeFss="$OPTARG" ;;
		s)      s_OPT=1 ; MBforbu="$OPTARG" ;;
		b)      b_OPT=1 ; BackupDir="$OPTARG" ;;
		k)      k_OPT=1 ;;
		o)      o_OPT=1 ; BootableISO="$OPTARG" ;;
		h|?|*)  usage ;;
		esac
	done
	shift $(($OPTIND - 1))

	[[ "$FileInfo" == "" || "$BackupDir" == "" || "$BootableISO" == ""  ]] && usage
	[[ "$BootableISO" == "-"  ]] && BootableISO="$BBpipe"

	test -d "$BackupDir" && printf "\nERROR: BackupDir $BackupDir should not exist.\n\n" >&2 && exit 2

	(($s_OPT==1)) && ! expr $MBforbu + 0 >/dev/null 2>&1 && printf "\nERROR: MBs for backup is not numeric ($MBforbu).\n\n" >&2 && exit 2

	mydir=$(dirname $0)
	[[ "$mydir" == "" ]] && mydir=$(which $0 2>/dev/null)
	[[ "$mydir" == "" ]] && mydir="."
	RIPLinuxISO=$(ls -1rtd "$mydir"/RIPLinux*iso |tail -1)
	! test -r "$RIPLinuxISO" && printf "\nERROR: Cannot read RIPLinuxISO ($RIPLinuxISO).\n\n" >&2 && exit 2

	[[ "$BackupName" == "" ]] && BackupName="$HOSTNAME"
	if [[ "$ExcludeDirs" == "" ]]
	then
		ExcludeDirs="$BackupDir"
	else
		ExcludeDirs="$ExcludeDirs $BackupDir"
	fi
}

###########
# Main
###########
get_args "$@"
echo "CmdLine=\"$CmdLine\"" >&2

PATH=.:$PATH
[[ "$IncludeFss" == "" ]] && IncludeFss=$(getfileinfo.sh -p -E "$ExcludeFss")

if [[ "$BootableISO" == "$BBpipe" ]]
then
	echo "ISO image going to stdout." >&2
	mknod $BBpipe p
	cat < $BBpipe &
fi
exec >&2   # Do like mkisofs and use stderr to display all messages keeping stdout clear for output of ISO if required.

set -ex
# Preview
backuphost.sh -p -e "$ExcludeDirs" ${VgName:+-v} $VgName ${MBforbu:+-s} $MBforbu -b $BackupDir $IncludeFss

# There should be enough space so start
getfileinfo.sh -x -f $FileInfo -e "$ExcludeDirs" -E "$ExcludeFss" -I "$IncludeFss"
backuphost.sh -x -e "$ExcludeDirs" ${VgName:+-v} $VgName ${MBforbu:+-s} $MBforbu -b $BackupDir $IncludeFss

# Don't exit if makeiso.sh has an error wince we have to remove tmpbackuplv (backuphost.sh cleans this up on error since it's the script that creates it).
set +e
makeiso.sh -d -n $BackupName -o "$BootableISO" ${ExtraCpioGz:+-x} $ExtraCpioGz -r $RIPLinuxISO -b $BackupDir
ret_value=$?
set +x

###
if (($k_OPT==0))
then
	echo "Removing $BackupDir"
	if (($v_OPT==1))
	then
		umount $BackupDir
		lvremove -f /dev/$VgName/tmpbackuplv
	fi
	rm -rf $BackupDir
fi

###
if [[ "$BootableISO" == "$BBpipe" ]]
then
	# "cat < $BBpipe &" should have terminated at this point when makeiso.sh ended.
	rm -f $BBpipe
	NewISOFile="ISO image was written to stdout."
else
	NewISOFile=$(ls -l "$BootableISO" 2>/dev/null)
fi
(($ret_value==0)) && printf "\n$NewISOFile\n"
echo
echo "Done $myname (ret_value=$ret_value)"
echo
exit $ret_value

