#!/bin/bash


# Copyright (c) 2005-2019 Colin Pearse.
# All scripts are free in the binscripts repository but please refer to the
# LICENSE file at the top-level directory for the conditions of distribution.
#
# Author:      Colin Pearse
# Description: Part of bootablebackup.sh. This uses RIPLinux ISO to create a bootable ISO of your current system.


# NOTES:
# . The RIPLinux is mounted and rootfs.cgz extracted, modified and repacked.
# . The backup files from backuphost.sh are put in the root directory of the ISO image.
# . mkisofs lack of -o option will write to stdout but I use a pipe instead in bootablebackup.sh.

myname=$(basename $0)
HOSTNAME=$(uname -n)

BackupPrefix="backuphost.sh"
RestoreScript="restorehost.sh"    # This can take on a full path in get_args

# using -e to trap errors
TMPDIR="/tmp"
DebugFile="$TMPDIR/$myname.debug"


usage()
{
	cat >&2 <<EOF

usage: $myname [-n BackupName] [-o BootableISO] [-d] [-x ExtraCpioGz] -r RIPLinuxISO -b BackupDir

	-n   Name the bootable backup (default is "${HOSTNAME}").
	-o   Bootable ISO backup file (default is "<BackupDir>/<BackupName>_bootable_backup.iso").
	-r   RIP Linux ISO bootable image which is used to re-create the volume group.
	-b   Backup directory where the gz files are kept (result of backuphost.sh).
	-d   Delete the gz backup files after the iso backup has been successfully created.
	-x   Put extra gz cpio file on backup so that $RestoreScript restores it last of all.

   eg. $myname -o /sharedrive/\$(uname -n).iso -r RIPLinux-1.9.iso -b /backupdir
   eg. $myname -n newhost -o /sharedrive/newhost.iso -x newhost_network_settings.cgz -r RIPLinux-1.9.iso -b /backupdir

EOF
	exit 2
}
get_args()
{
	ALL_ARGS="$*"
	n_OPT=0 ; o_OPT=0 ; r_OPT=0 ; b_OPT=0 ; d_OPT=0 ; x_OPT=0
	while getopts "n:o:r:b:dx:h?" name
	do
		case $name in
		n)      n_OPT=1 ; BackupName="$OPTARG" ;;
		o)      o_OPT=1 ; BootableISO="$OPTARG" ;;
		r)      r_OPT=1 ; RIPLinuxISO="$OPTARG" ;;
		b)      b_OPT=1 ; BackupDir="$OPTARG" ;;
		d)      d_OPT=1 ;;
		x)      x_OPT=1 ; ExtraCpioGz="$OPTARG" ;;
		h|?|*)  usage ;;
		esac
	done
	shift $(($OPTIND - 1))
	(($r_OPT==0 || b_OPT==0)) && usage
	! test -r "$RIPLinuxISO" && printf "\nERROR: Cannot read RIPLinuxISO ($RIPLinuxISO)\n" && usage
	! test -d "$BackupDir"   && printf "\nERROR: BackupDir is not a directory ($BackupDir)\n" && usage

	(($x_OPT==1)) && ! test -r "$ExtraCpioGz" && printf "\nERROR: Cannot read ExtraCpioGz ($ExtraCpioGz)\n" && usage

	[[ "$BackupName"  == "" ]] && BackupName="$HOSTNAME"
	[[ "$BootableISO" == "" ]] && BootableISO="$BackupDir/${BackupName}_bootable_backup.iso"

	# Find restorehost.sh in dir where script is kept.
	mydir=$(dirname $0)
	[[ "$mydir" == "" ]] && mydir=$(which $0 2>/dev/null)
	[[ "$mydir" == "" ]] && mydir="."
	RestoreScript="$mydir/$RestoreScript"
	! test -r "$RestoreScript" && printf "\nERROR: Cannot read RestoreScript ($RestoreScript)\n\n" >&2 && exit 2

	# For now find pre/post stuff dir where script is kept too.
	PreScript="$mydir/prescript.sh"
	PostScript="$mydir/postscript.sh"
	! test -r "$PreScript" && PreScript=""
	! test -r "$PostScript" && PostScript=""
}

# This outputs to a saved stdout (whether file or tty)
show_error()
{
	set +x
	exec 1>&3

	echo
	echo "ERROR ======= last 10 lines of logfile: $DebugFile"
	tail -10 $DebugFile
	echo "ERROR ================================="
	exit 1
}

# mount cdrom
mount_cdrom()
{
	set -x
	mount -r -o loop -t iso9660 "$1" "$2"
}

# copy and unmount cdrom
copy_cdrom()
{
	set -x
	pushd $1 ; find . -depth -print |cpio -pdum $2
	popd
	umount $1
}

set_restoreboot()
{
	set -x
	# Alter isolinux.cfg file to boot without prompts or choice
	# timeout isn't needed when prompt is 0
	cat >$1 <<EOF
kbdmap be.ktl
display restore.msg

default localboot
timeout 0
prompt 1

label localboot
        localboot 0x80

label 1
	kernel /boot/kernel
	append nokeymap initrd=/boot/rootfs.cgz root=/dev/ram0 rw vga=normal text RESTOREHOST_DISK=repartition

label 1n
	kernel /boot/kernel
	append nokeymap initrd=/boot/rootfs.cgz root=/dev/ram0 rw vga=normal text RESTOREHOST_DISK=repartition RESTOREHOST_REBOOT=no

label 1u
	kernel /boot/kernel
	append nokeymap initrd=/boot/rootfs.cgz root=/dev/ram0 rw vga=normal text RESTOREHOST_DISK=repartition RESTOREHOST_ACCESS=userroot

label 1nu
	kernel /boot/kernel
	append nokeymap initrd=/boot/rootfs.cgz root=/dev/ram0 rw vga=normal text RESTOREHOST_DISK=repartition RESTOREHOST_REBOOT=no RESTOREHOST_ACCESS=userroot

label 1un
	kernel /boot/kernel
	append nokeymap initrd=/boot/rootfs.cgz root=/dev/ram0 rw vga=normal text RESTOREHOST_DISK=repartition RESTOREHOST_REBOOT=no RESTOREHOST_ACCESS=userroot

label 2
	kernel /boot/kernel
	append nokeymap initrd=/boot/rootfs.cgz root=/dev/ram0 rw vga=normal text

label 2n
	kernel /boot/kernel
	append nokeymap initrd=/boot/rootfs.cgz root=/dev/ram0 rw vga=normal text RESTOREHOST_REBOOT=no

label 2u
	kernel /boot/kernel
	append nokeymap initrd=/boot/rootfs.cgz root=/dev/ram0 rw vga=normal text RESTOREHOST_ACCESS=userroot

label 2nu
	kernel /boot/kernel
	append nokeymap initrd=/boot/rootfs.cgz root=/dev/ram0 rw vga=normal text RESTOREHOST_REBOOT=no RESTOREHOST_ACCESS=userroot

label 2un
	kernel /boot/kernel
	append nokeymap initrd=/boot/rootfs.cgz root=/dev/ram0 rw vga=normal text RESTOREHOST_REBOOT=no RESTOREHOST_ACCESS=userroot

label rip
	kernel /boot/kernel
	append nokeymap initrd=/boot/rootfs.cgz root=/dev/ram0 rw vga=normal text RESTOREHOST_RIP=yes
EOF

	HardDisk=$(grep "^HardDisk:" $BackupDir/${BackupPrefix}.disk_and_vg.conf |sed "s,^HardDisk:,,1")
	# 21 lines is about the maximum you can use (with the ISOlinux message included)
	UnderlineBU=$(echo "$BackupName" |sed "s/./-/g")
	UnderlineHD=$(echo "$HardDisk" |sed "s/./-/g")
	cat >$2 <<EOF

  -----------$UnderlineBU    ---------$UnderlineHD
  BackupName=$BackupName    HardDisk=$HardDisk
  -----------$UnderlineBU    ---------$UnderlineHD

  <ret>   Boot from hard disk after restore.
  1       Restore (re-partition disk).
  2       Restore (disk is ok - use current partitions).
  rip     Go straight to RIPLinux login. For:
          - Manual recovery (do vgchange -a y <RootVg> before mounting).
          - Manual re-partitioning (/tmp/README will have instructions).
          - Restore to a HardDisk of a different name (see /tmp/README).

 options:  n   No reboot after restore (goes to RIPLinux login).
           u   Create tmpuser and reset root's passwd (passwd=username).

 Choose menu item (+ options)
  EG: 1nu
  EG: 2u
EOF
}

# copy cpio.gz files to the iso image
# NOTE: cp -p is superfluous on ISO it seems since rwxr--r-- became r-xr-xr-x
move_backup_to_cdrom()
{
	set -x
	mv $BackupDir/${BackupPrefix}* $CDsource
	cp -p $RestoreScript $CDsource
	[[ "$PreScript" != "" ]] && cp -p $PreScript $CDsource
	[[ "$PostScript" != "" ]] && cp -p $PostScript $CDsource
	return 0   # ensure previous test doesn't make function return non-zero thus triggering ERR
}
move_back_backup()
{
	set -x
	mv $CDsource/${BackupPrefix}* $BackupDir
}
# Cp changes modification time which is what we want since it must be later than the other gz'ed files.
# (Because RestoreScript finds gz files using ls -rt)
copy_extra_file_to_cdrom()
{
	set -x
	cp $ExtraCpioGz $CDsource/${BackupPrefix}._slash_.extra.cpio.gz
}

# mkisofs outputs % done on stderr, ISO is outputted on stdout when -o is not specified.
# arg1 CD source dir
# arg2 ISO file. mkisofs can output to stdout but found it easier to use pipe from bootablebackup.sh.
make_iso()
{
	set -x
	pushd $1
	mkisofs -r -no-emul-boot -boot-load-size 4 -boot-info-table -b boot/isolinux/isolinux.bin -c boot/boot.cat -V "$BackupName" -A "$BackupName" -o "$2" $1 2>&3
	popd
}

# unpack change and repack temp root
# restore script will do the reboot
change_rootfs()
{
	set -x
	RootFS="$1"
	mkdir -p $RootFS
	pushd $RootFS
	gunzip -c $RootFS.cgz |cpio -idumc

	RestoreScriptName=$(basename $RestoreScript)
	cat > $RootFS/etc/restore_iso.sh <<EOF
#!/bin/bash
echo
sleep 20   # /dev/sr0 unavailable error if mount done straight away
echo "Mounting CD/DVD."
mount -r -t iso9660 /dev/sr0 /mnt/cdrom
echo "Calling /mnt/cdrom/$RestoreScriptName /mnt/cdrom"
/mnt/cdrom/$RestoreScriptName /mnt/cdrom   # normally reboots if successful
echo
echo "Press return for RIPLinux login."
read ans
EOF
	chmod 700 $RootFS/etc/restore_iso.sh
	echo "/etc/restore_iso.sh" >> $RootFS/etc/rc.d/rc.M

	# NOTE: use the same cpio given with rootfs.cgz otherwise there'll be RAMFS errors
	find . -xdev -print |bin/cpio -oc |gzip -c >$RootFS.cgz
	popd
	rm -rf $RootFS
}


###########
# Main
###########

get_args "$@"
CDorig="$BackupDir/CDorig"
CDsource="$BackupDir/CDsource"

# Save stdout (file or tty) in case this exits with an error and
# ensure all detailed output goes to the logfile.
exec 3>&1
exec >$DebugFile 2>&1
trap show_error ERR
set -E
echo >&3
echo "DebugFile is: $DebugFile" >&3

####
set -x
which mkisofs >/dev/null
mkdir -p $CDorig $CDsource
set +x
echo "Mounting $RIPLinuxISO on $CDorig" >&3
mount_cdrom "$RIPLinuxISO" $CDorig

####
echo "Copying to $CDsource" >&3
copy_cdrom $CDorig $CDsource
rmdir $CDorig
set_restoreboot "$CDsource/boot/isolinux/isolinux.cfg" "$CDsource/boot/isolinux/restore.msg"

####
echo "Moving backup files onto $CDsource" >&3
move_backup_to_cdrom
(($x_OPT==1)) && echo "Copying extra file onto $CDsource" >&3
(($x_OPT==1)) && copy_extra_file_to_cdrom

####
echo "Changing the temporary rootfs." >&3
change_rootfs "$CDsource/boot/rootfs"

####
echo "Getting size (in KB) of directory from which ISO will be created." >&3
du -sk $CDsource >&3

####
echo "Making ISO image: $BootableISO" >&3
make_iso $CDsource "$BootableISO"

####
(($d_OPT==0)) && echo "Moving backup files back to $BackupDir" >&3
(($d_OPT==0)) && move_back_backup
echo "Removing $CDsource" >&3
rm -rf $CDsource

echo "Done $myname." >&3
echo >&3
exit 0

