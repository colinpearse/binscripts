#!/bin/bash


# Copyright (c) 2005-2019 Colin Pearse.
# All scripts are free in the binscripts repository but please refer to the
# LICENSE file at the top-level directory for the conditions of distribution.
#
# Name:        restorehost.sh
# Description: Part of bootablebackup.sh. Restore Linux.


# This is normally placed in the root directory of an ISO image and run from RIPLinux
# image with specific options (see RESTOREHOST_* variables in makeiso.sh).
#
# . The disk is (re-partitioned depending on RESTOREHOST_DISK), prepared, vg, lvs and fs' are created and the
#   cpio.gz files restored from backup to re-created fs'.
# . The new LVM config (since it resides on the RIPLinux ramfs) is saved on the re-created fs'.
# . Ig selinux is installed then .autorelabel is set so the system relabels all files after reboot.
# . If a prescript.sh or postscript.sh exist in the ISO's root directory then the script is run at
#    the appropriate time.
# . The system reboots (unless RESTOREHOST_REBOOT=no)
#
# Things to note for prescript.sh and postscript.sh:
# - They are executed in the same shell so stdout and stderr go to the DebugFile. Fd=3 goes to the screen.
# - -E is set so show_error is called when a command's return is non-0.
# - Root for restore is $NewRootDir (so do: chmod 755 $NewRootDir/etc -or- chroot $NewRootDir chmod 755 /etc)

myname=$(basename $0)
mydir=$(dirname $0)

TMPDIR=/tmp
NewRootDir=/newroot
DebugFile="$TMPDIR/$myname.debug"
BackupPrefix="backuphost.sh"
TmpDiskInfoFile="$TMPDIR/$BackupPrefix.disk_and_vg.conf"
BootFs="/boot"

usage()
{
	cat >&2 <<EOF

usage: $myname [-f] <cdrom> [disk_and_vg.conf file]

       -f   Force sfdisk to accept partitions.

   eg: $myname /mnt/cdrom
   eg: $myname -f /mnt/cdrom $TMPDIR/$BackupPrefix.disk_and_vg.conf

EOF
	exit 2
}
get_args()
{
	[[ "$1" == "" ]] && usage

	if [[ "$1" == "-f" ]]
	then
		shift
		ForceSfdisk="-f"
	else
		ForceSfdisk=""
	fi
	
	CDsource="$1"
	DiskInfoFile="$CDsource/$BackupPrefix.disk_and_vg.conf"

	[[ "$2" != "" ]] && DiskInfoFile="$2"
	! test -r "$DiskInfoFile" && printf "\nERROR: Cannot read $DiskInfoFile\n\n" >&2

	[[ "$3" != "" ]] && usage
}

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

createfs()
{
	vg=$1
	lv=$2
	fs=$3
	fstype=$4
	set -x
	if [[ "$fs" == "swap" ]]
	then
		mkswap /dev/$vg/$lv
	else
		mkfs.$fstype /dev/$vg/$lv
		# e2label $BootDisk $BootFsLabel
		mkdir -p $fs
		mount /dev/$vg/$lv $fs
	fi
}

# EG. pvdisplay -c  (pvnum is obsolete)
# pv : vg : sizeKB : pvnum : status : (not)allocatable : lvs : peKB : totpe : freepe : allocpe
# /dev/cciss/c0d0p2:rootvg:141885440:-1:8:8:-1:32768:2165:1541:624:8CUpBR-FqMk-eBJ2-Mt1Q-Lg10-Ypob-03Kuig
#
# EG. vgdisplay -c
# vg : access : status : vgnum : maxlvs : lvs : openlvs : maxlvsize : maxpvs : pvs : actualpvs : sizeKB : peKB : totpe : allocpe : freepe : uuid
# rootvg:r/w:772:-1:0:7:7:-1:0:1:1:70942720:32768:2165:624:1541:wdNGKW-6q5u-phjH-ySAe-ir6a-bL5C-yiHQQ6
#
# EG. lvdisplay -ca
# lv : vg : access : status : lvnum : openlvs : sizeKB : lvle : allocle : allocpolicy : readahead : major : minor
# /dev/rootvg/rootlv:rootvg:3:1:-1:1:1048576:16:-1:0:0:253:0
setdiskvars()
{
	DiskVgConf=$(cat $1)
	FstabInfo=$(echo "$DiskVgConf" |egrep "^cat /etc/fstab:" |sed "s,^cat /etc/fstab:,,1")
	MountInfo=$(echo "$DiskVgConf" |egrep "^mount:" |sed "s/^mount://1")

	# GRUB or LILO
	GrubConf=$(echo "$DiskVgConf" |egrep "^GrubConf:" |sed "s,^GrubConf:,,1")
	LiloConf=$(echo "$DiskVgConf" |egrep "^LiloConf:" |sed "s,^LiloConf:,,1")

	# For getting hard disk which normally has boot and root vg partition
	HardDisk=$(echo      "$DiskVgConf" |grep "^HardDisk:" |sed "s,^HardDisk:,,1")
	FdiskInfo=$(echo     "$DiskVgConf" |grep "^fdisk -l $HardDisk:" |sed "s,^fdisk -l $HardDisk:,,1")
	SfdiskPartitionInfo=$(echo "$DiskVgConf" |grep "^sfdisk -d $HardDisk:" |sed "s,^sfdisk -d $HardDisk:,,1")
	SavedSectorsPerTrack=$(echo "$FdiskInfo" |grep -i cylinder |grep -i sector |grep -i head |sed "s,sector.*,,1" |awk '{print $NF}')
	SavedHeads=$(echo           "$FdiskInfo" |grep -i cylinder |grep -i sector |grep -i head |sed "s,head.*,,1"   |awk '{print $NF}')
	FdiskPartitionInfo=$(echo   "$FdiskInfo" |grep "^$HardDisk" |sed "s,^$HardDisk.*\*,on,1;s,^$HardDisk..,off,1;")

	# Get sectors of possibly new (unformatted) disk. Maybe use this for checking sizes?
	#Sectors=$(sfdisk -g $HardDisk |sed "s,.*$HardDisk: ,,1;s/cylinders,//1;s/heads,/*/1;s,sectors.*,* p,1" |dc)
	#[[ "$Sectors" == "" ]] && Sectors=$(fdisk -lu $HardDisk |egrep -i "total.*sectors" |sed "s/sectors$//1" |awk '{print $NF}')

	# Create similar partitions for sfdisk but with no end size to cater for different size disk.
	NewSfdiskPartitionInfo=$(echo "$SfdiskPartitionInfo" |grep "^$HardDisk" |sed "s,^/dev.*start,start,1" |tr -d ' ' |sed "s,start=,,1;s,size=,,1;s,Id=,,1;s,bootable,*,1")
	LastPartition=$(echo "$NewSfdiskPartitionInfo" |grep -v "0,0," |tail -1)
	NewLastPartition=$(echo "$LastPartition" |awk -F',' '{$2="";print $0}' |tr ' ' ',')
	NewSfdiskPartitionInfo=$(echo "$NewSfdiskPartitionInfo" |sed "s/$LastPartition/$NewLastPartition/1")

	# Get the boot partition and root vg.
	BootDisk=$(echo       "$MountInfo" |awk -v fs=$BootFs '{if($3==fs){print $1}}')
	BootDiskfstype=$(echo "$MountInfo" |awk -v fs=$BootFs '{if($3==fs){print $5}}')
	RootVg=$(echo         "$MountInfo" |awk -v fs=/       '{if($3==fs){print $1}}' |awk -F'/' '{print $NF}' |sed "s/-.*//1")
	BootFsLabel=$(echo    "$FstabInfo" |awk -v fs=$BootFs '{if($2==fs){print $1}}' |sed "s,^LABEL=,,1")
	[[ "$BootFsLabel" == "$BootDisk" ]] && BootFsLabel=""

	# Get all pvs that are in the root vg into RootVgDisks
	RootVgDisks=$(echo "$DiskVgConf" |egrep "^pvdisplay -c:" |sed "s/^pvdisplay -c: *//1" |grep ":$RootVg:" |cut -d':' -f1 |xargs echo)
	RootVgopts=$(echo  "$DiskVgConf" |egrep "^vgdisplay -c:" |sed "s/^vgdisplay -c: *//1" |grep "^$RootVg:")

	# vg : access : status : vgnum : maxlvs : lvs : openlvs : maxlvsize : maxpvs : pvs : actualpvs : sizeKB : peKB : totpe : allocpe : freepe : uuid
	#maxlvsize=$(echo "$RootVgopts" |cut -d':' -f8)
	maxlvs=$(echo "$RootVgopts" |cut -d':' -f5)
	maxpvs=$(echo "$RootVgopts" |cut -d':' -f9)
	peKB=$(($(echo "$RootVgopts" |cut -d':' -f13) / 1024))

	Fss=""
	# NOTE: The tmpbackuplv will not be created here if ssh .. back to pvmgt1 will be used.
	#LvInfo=$(echo "$DiskVgConf" |egrep "^lvdisplay -ca:" |sed "s/^lvdisplay -ca: *//1")
	LvInfo=$(echo "$DiskVgConf" |egrep "^lvdisplay -ca:" |sed "s/^lvdisplay -ca: *//1" |grep -v "/dev/$RootVg/tmpbackuplv")
	FsInfo=$(echo "$FstabInfo" |grep "^/dev/$RootVg/")
	for fs in $(echo "$FsInfo" |awk '{print $2}')
	do
		lv=$(echo     "$FsInfo" |awk -v fs=$fs '{if($2==fs){print $1}}' |sed "s,^/dev/$RootVg/,,1")
		fstype=$(echo "$FsInfo" |awk -v fs=$fs '{if($2==fs){print $3}}')

		lvopts=$(echo "$LvInfo" |grep "^/dev/$RootVg/$lv:")
		# WARNING: man page says lv size (on lvdisplay -c) is KB but its blocks of 512
		# NOTE: allocpolicy is -C not --alloc and with "lvdisplay -c" 2=y 0=n
		# lv : RootVg : access : status : lvnum : openlvs : sizeblocks512 : lvle : allocle : allocpolicy : readahead : major : minor
		allocpolicy=$(echo "$lvopts" |cut -d':' -f10)
		[[ "$allocpolicy" == "2" ]] && allocpolicy="y"
		[[ "$allocpolicy" == "0" ]] && allocpolicy="n"
		readahead=$(echo   "$lvopts" |cut -d':' -f11)
		sizeMB=$(($(echo   "$lvopts" |cut -d':' -f7) / 2 / 1024))

		Fss="${Fss}$fs:$fstype:lvcreate -C $allocpolicy -r $readahead -L ${sizeMB}M -n $lv $RootVg\n"
	done

	# Create in the same order as originals.
	Fss=$(for lv in $(echo "$LvInfo" |grep ":$RootVg:" |cut -d':' -f1 |cut -d'/' -f4) ; do printf "$Fss" |grep " $lv $RootVg";done)

	# For logfile.
	echo "HardDisk:$HardDisk:"
	echo "SavedSectorsPerTrack:$SavedSectorsPerTrack:"
	#echo "FdiskPartitionInfo:$FdiskPartitionInfo:"
	echo "SfdiskPartitionInfo:$SfdiskPartitionInfo:"
	echo "NewSfdiskPartitionInfo:$NewSfdiskPartitionInfo:"
	echo "BootDisk:$BootDisk:"
	echo "RootVgDisks:$RootVgDisks:"
	echo "Fss:$Fss:"
}

#  (Simulated an overwritten MBR using dd if=/dev/zero on the first 512 bytes made sfdisk
#   display "No partitions found" but it didn't return non-zero.
prepare_disk()
{
	set -x

	if [[ "$RESTOREHOST_DISK" == "repartition" ]]
	then
		# Tried with fdisk (partition using cylinder sizes) but settled for sfdisk instead.
		# eg. contents of FdiskPartitionInfo
		#on           1          19      152586   83  Linux
		#off         20        8854    70967137+  8e  Linux LVM
#		echo "Making empty DOS partitions." >&3
#		CylLast=$(echo "$FdiskPartitionInfo" |tail -1 |awk '{print $3}' |sed "s,[+-],,g")
#		echo -e "o\nw" |fdisk -S $SavedSectorsPerTrack $HardDisk
#		Pnum=1
#		while read Boot CylStart CylEnd blocks Id descrition
#		do
#			CylStart=$(echo $CylStart |sed "s,[+-],,g")  # shouldn't have + or - but just in case
#			CylEnd=$(echo $CylEnd |sed "s,[+-],,g")
#			(($CylEnd==$CylLast)) && CylEnd=""         # use default for end in case disk is bigger (or smaller)
#
#			AddPartition="n\np\n$Pnum\n$CylStart\n$CylEnd\n"
#			ChangeId="t\n$Pnum\n$Id\n"
#			(($Pnum==1)) && ChangeId="t\n$Id\n"    # 1st partition means fdisk won't ask for a partition number
#
#			echo "Creating partition $Pnum (boot=$Boot)." >&3
#			echo -e "$AddPartition${ChangeId}w" |fdisk -S $SavedSectorsPerTrack $HardDisk
#			parted $HardDisk set $Pnum boot $Boot
#			Pnum=$(($Pnum+1))
#		done <<EOF
#$FdiskPartitionInfo
#EOF

		# USE SAVED GEOMETRY - cylinders,heads,sectors/track (c/h/s)
		# It's fake geometry anyway but it may be desirable to keep the original layout and using the saved geometry
		# allows me to use the same sizes from the saved sfdisk -d command. Cylinders is allowed to change since there
		# may be a new root disk of a different size.
		#
		# NOTE on problems possibly due to replicating sectors/track=63:
		#   Using 63 for sectors/track (kickstart formats with this) I couldn't get sfdisk to boot without an extra grub fix (see below).
		#   sfdisk -S63 -H255 .. below needed the -C too, ie. it couldn't calculate the cylinders correctly on its own.
		#
		# NOTE on disk geometry:
		# - the partition start and sizes used with sfdisk (eg. 305172) must be multiples of sectors/track size (eg. 63).
		# - also the geometry (sectors/track etc) that should be adhered to is the one as seen by fdisk -l not sfdisk -g.
		# EG. If the first partition is 63-305172 then the sectors/track size must be 63. If it's 32 then the partition's
		#     start will not be found and fdisk -l will complain that the partition does not start on a cylinder boundary.
		#
		# NOTE: Linux doesn't need to have a "bootable" partition as shown by sfdisk/fdisk since grub takes care of that
		#       however it will still be replicated since I want to replicate the disk partitions as faithfully as possible.
		#
		# The following will use saved head and sectors/track to recalculate the cylinders in the disk:
		# - Re-partition with sfdisk using saved sectors/track.
		# - fdisk now shows correct cylinders (recalculated from the saved sectors/track value).
		# - sfdisk used again with correct geometry.
		# NOTE: sfdisk -g shows kernel interpretation of the geometry which may not be the same.
		echo "Re-partitioning using saved settings: sectors/track=$SavedSectorsPerTrack and heads=$SavedHeads" >&3
		echo -e ";\n;\n;\n;" |sfdisk -f -H $SavedHeads -S $SavedSectorsPerTrack $HardDisk   # now fdisk will show c/h/s
		Cylinders=$(fdisk -l $HardDisk |grep -i cylinder |grep -i sector |grep -i head |sed "s,cylinder.*,,1" |awk '{print $NF}')
		# If partitions are on cylinder boundaries (which they will be since I'm using the saved sizes + geometry)
		# then sfdisk shouldn't need -f (force).
		echo "$NewSfdiskPartitionInfo" |sfdisk $ForceSfdisk -u S -C $Cylinders -H $SavedHeads -S $SavedSectorsPerTrack $HardDisk
	else
		echo "Using existing partitions." >&3
	fi

	# NOTE: There are problems on boot if the label isn't on the disk and it's in /etc/fstab.
	echo "Creating $BootDiskfstype filesystem on $BootDisk" >&3
	mkfs.$BootDiskfstype ${BootFsLabel:+-L} $BootFsLabel $BootDisk

	if [[ "$GrubConf" == "yes" ]]
	then
		# Dirty workaround for a corrupted MBR. The grub-install script uses grub shell's "setup" to copy the MBR.
		# NOTE: Not having root mounted is ok since $root_device in the grub-install script is blank
		#       causing grub's root command to display "fd0: filesystem type unknown ...".
		# NOTE: Saved grub.conf is not needed since it has no effect on what is written to the MBR (unlike LILO).
		echo "Writing GRUB's MBR to $HardDisk" >&3
		mount $BootDisk $BootFs
		# grub-install is used to copy the relevant grub files to $BootFs/grub.
		# grub used to rewrite the boot stuff because grub-install rendered unbootable disks that had sectors/track=63.
		grub-install $HardDisk
		GrubDisk=$(egrep "^\(hd[0-9]+\)" $BootFs/grub/device.map |head -1)
		GrubBootDisk=$(echo "$GrubDisk" |sed "s/)/,0)/1")
		grub --batch --device-map=$BootFs/grub/device.map <<EOF
root $GrubBootDisk
setup --stage2=$BootFs/grub/stage2 --prefix=/grub $GrubDisk
quit
EOF
		DiskName=$(basename $HardDisk)
		cp -p $BootFs/grub/device.map /tmp
		rm -rf $BootFs/grub/*                 # This will be restored from ISO so don't need it (just using grub-install for it's call to grub)
		cp -p /tmp/device.map $BootFs/grub/device.map.$DiskName
		umount $BootFs
	fi
	# For LILO implementation:
	# 1) Check LiloConf, restore /etc/lilo.conf, then run lilo (uses lilo.conf file to create and write MBR)

	echo "Preparing RootVgDisks: $RootVgDisks" >&3
	pvcreate -ffy $RootVgDisks
}

createvg()
{
	# Only options available for vgcreate are these
	vgcreate -s $peKB -p $maxpvs -l $maxlvs $RootVg $RootVgDisks
}

# Will eventually use restored /etc/fstab so no need to change this file on ram OS.
createlvs()
{
	set -x
	while read line
	do
		fs=$(echo       "$line" |cut -d':' -f1)
		fstype=$(echo   "$line" |cut -d':' -f2)
		createlv=$(echo "$line" |cut -d':' -f3-)

		RootVg=$(echo   "$createlv" |awk '{print $NF}')
		lv=$(echo   "$createlv" |awk '{print $(NF-1)}')
		[[ "$fs" != "swap" ]] && fs="${NewRootDir}$fs"

		echo "Creating $fstype filesystem on $fs" >&3
		$createlv
		createfs $RootVg $lv $fs $fstype
	done <<EOF
$Fss
EOF
}

mountbootfs()
{
	set -x
	mkdir -p $NewRootDir$BootFs
	mount $BootDisk $NewRootDir$BootFs
}

# NOTE: ls -rt makes sure _slash_.out goes before _slash_boot.out since the former will have been created first.
restorefiles()
{
	set -x
	BackupFiles=$(ls -rt1d $CDsource/${BackupPrefix}*gz)
	for CpioGz in $BackupFiles
	do
		fs=$(echo "$CpioGz" |cut -d'.' -f3 |sed "s,_slash_,/,g")
		echo "Restoring $CpioGz" >&3
		cd $NewRootDir$fs
		gunzip -c $CpioGz |cpio -idumc
	done
}

# If a different root disk was used then the device map will be different.
update_devicemap()
{
	cp -p $NewRootDir$BootFs/grub/device.map $NewRootDir$BootFs/grub/device.map.save
	mv $NewRootDir$BootFs/grub/device.map.$DiskName $NewRootDir$BootFs/grub/device.map

	set +E
	if ! diff $NewRootDir$BootFs/grub/device.map $NewRootDir$BootFs/grub/device.map.save
	then
		echo "WARNING: $NewRootDir$BootFs/grub/device.map and $NewRootDir$BootFs/grub/device.map.save differ." >&3
		echo "WARNING: Please check whether this was a normal change of root disk or a real problem." >&3
	fi
	set -E
	return 0
}

# I only want to mount the filesystems I have recreated otherwise there'll be an fsck error on boot.
# NOTE: -E is still in effect. The grep -v .. may return an error (if no other non-root lvs are present) but this will never
#       be seen by this script since it is piped into an awk that should always return 0 (unless there's a real problem).
update_fstab()
{
	set -x
	FstabFile="/etc/fstab"
	cp -p $NewRootDir$FstabFile $NewRootDir$FstabFile.save

	EGRRootLvs=$(echo "$FsInfo" |awk '{print "^"$1"|"}' |tr -d '\n')"^do_not_match "
	echo "$FstabInfo" |egrep    "^#|^none|${BootFsLabel:+"LABEL="}$BootFsLabel|^$BootDisk|$EGRRootLvs" > $NewRootDir$FstabFile
	echo "$FstabInfo" |egrep -v "^#|^none|${BootFsLabel:+"LABEL="}$BootFsLabel|^$BootDisk|$EGRRootLvs" |awk '{print "#"$0}' >> $NewRootDir$FstabFile
}

# Make sure the current lvm files are valid after reboot. The valid vg info is on ram OS so replace the old one just restored.
update_lvm()
{
	set -x
	vgcfgbackup
	cd /
	find . -xdev |egrep "^./etc/lvm" |cpio -pdum $NewRootDir
}

# If SElinux is installed then we want to set permissive and relabel the files to be compliant
# for when it is reenabled.
# NOTE: no check yet for "enforcing=1" in /etc/grub/grub.conf
# NOTE: chroot $NewRootDir fixfiles -F relabel - does not work since selinux is not used in the boot CD
update_selinux()
{
	set -x
	SElinux=/etc/sysconfig/selinux
	SElinux=$(ls -l $NewRootDir/$SElinux |awk '{print $NF}')  # set to actual file if symlink
	if test -f $NewRootDir/$SElinux
	then
		if egrep -q "^SELINUX=enforcing" $NewRootDir/$SElinux
		then
			cp -p $NewRootDir/$SElinux $NewRootDir/$SElinux.save
			cat $NewRootDir/$SElinux.save |sed "s/^SELINUX=enforcing/SELINUX=permissive/1" > $NewRootDir/$SElinux
			echo "SElinux: Re-labelling required. Setting permissive mode and will re-enable after reboot." >&3

			# put script in /tmp?
			InittabLine="rest:12345:wait:/etc/restore_selinux.sh > /restore_selinux.sh.log 2>&1"
			cat > $NewRootDir/etc/restore_selinux.sh <<EOF
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/etc:\$PATH
set -x
cp -p /etc/inittab /etc/inittab.save
grep -v "^$InittabLine$" /etc/inittab.save > /etc/inittab
mv $SElinux.save $SElinux
echo 1 >/selinux/enforce
EOF
			chmod 700 $NewRootDir/etc/restore_selinux.sh
			echo "$InittabLine" >> $NewRootDir/etc/inittab
		else
			echo "SElinux: Re-labelling required. However, enforced mode is not set." >&3
		fi
		touch $NewRootDir/.autorelabel
	fi
}

# passwd --stdin ...  gave "no passwd module" error when I tried this
userroot()
{
	set -x
	chroot $NewRootDir useradd tmpuser
	echo "tmpuser:tmpuser" |chroot $NewRootDir chpasswd
	echo "root:root"       |chroot $NewRootDir chpasswd
}


# Was in function rip but it's useful on failure too.
create_README()
{
	set +ex
	cat > $TMPDIR/README <<EOF

-----------
Description:
-----------
Running the restore as per the second example below will partition your disk
using the data in the configuration file and then create the volume group as
per the rest of the configuration file. If the name of HardDisk has changed
then all references in the configuration file must also be changed.

NOTE: You cannot change the names of the filesystems since these names
      are also encoded in the name of each cpio gz file.

NOTE: Kickstart builds often format a disk with geometry of 63 sectors/track
      which is different to what the kernel thinks it is (sfdisk -g gives 32).
      I had problems making a disk using this geometry bootable without an
      extra grub command after grub-install (see restore script).

For formatting yourself the rip contains: fdisk, sfdisk and parted. The
restore script expects at least two partitions (boot and lvm). This script
will then write an ext3 filesystem on the boot partition and make the disk
bootable using grub. NOTE: That for booting Linux sfdisk/fdisk need not show
the boot partition to be bootable since it's grub that writes the MBR (master
boot record) and makes the disk bootable.

----------------------
Restoring on new disks:
----------------------
Partition the disk yourself and then run:
# $0 $mydir

 -or-

Update $TmpDiskInfoFile with new hard disk and new partition info and then run:
  (use -f to force sfdisk to accept the partition sizes)
# export RESTOREHOST_DISK=repartition
# $0 $mydir $TmpDiskInfoFile

--------------------------------
Variables that affect the script:
--------------------------------
RESTOREHOST_REBOOT=no         Does not reboot after restore.
RESTOREHOST_ACCESS=userroot   Create tmpuser and reset root's passwd (passwd=username).

EOF
}

# RIP - recovery is possible
# This is only called from a first boot since RESTOREHOST_RIP != "rip" on manual invokation.
rip()
{
	set +ex
	cat <<EOF

No restore. Going straight to the RIPLinux login.

If you want to use another hard disk as the root disk
before restoring please read: $TMPDIR/README

EOF
	exit 0   # Calling script (created by makeiso.sh) has a wait for return in it.
}

# If it's the first run after boot then TmpDiskInfoFile will not exist.
# If it's not the first run no copy and no test of RESTOREHOST_RIP==yes will take place.
#  (on tests after logging in this environmental (set at boot time) is not present)
do_once_after_boot()
{
	echo
	echo "Copying $DiskInfoFile to $TMPDIR"
	cp -p "$DiskInfoFile" $TMPDIR

	echo "Copying prescript.sh and postscript.sh to $TMPDIR (if they exist)"
	test -r $CDsource/prescript.sh && cp -p "$CDsource/prescript.sh" $TMPDIR
	test -r $CDsource/postscript.sh && cp -p "$CDsource/postscript.sh" $TMPDIR

	[[ "$RESTOREHOST_RIP" == "yes" ]] && rip
}

########
# Main
########

create_README

get_args "$@"
! test -r "$TmpDiskInfoFile" && do_once_after_boot

###

# Save stdout (file or tty) in case this exits with an error and
# ensure all detailed output goes to the logfile.
exec 3>&1
exec >$DebugFile 2>&1
trap show_error ERR
set -E
echo >&3
echo "DebugFile is: $DebugFile" >&3

###
# Useful for log
echo "Environment variables start -----------"
set
echo "Environment variables finish ----------"
echo "/proc/cmdline is: "$(cat /proc/cmdline)

###
# Get disk file and fill vars
setdiskvars "$DiskInfoFile"

###
test -r $TMPDIR/prescript.sh && echo "Running pre script." >&3
test -r $TMPDIR/prescript.sh && . $TMPDIR/prescript.sh

###
# Create the vg and lvs
mkdir -p $NewRootDir
echo "Preparing HardDisk: $HardDisk" >&3
prepare_disk
echo "Creating RootVg: $RootVg" >&3
createvg
echo "Creating lvs:" >&3
createlvs
echo "Mounting: $BootDisk $NewRootDir$BootFs" >&3
mountbootfs

###
# restore and do some post install tasks that ensure consistency (ie: grub, fstab, lvm, selinux).
echo "Restoring fss:" >&3
restorefiles
[[ "$GrubConf" == "yes" ]] && echo "Update $BootFs/grub/device.map." >&3
[[ "$GrubConf" == "yes" ]] && update_devicemap
echo "Update $NewRootDir/etc/fstab." >&3
update_fstab
echo "Copying new vg config info to $NewRootDir" >&3
update_lvm
echo "Checking if relabelling is required." >&3
update_selinux

###
[[ "$RESTOREHOST_ACCESS" == "userroot" ]] && echo "Creating tmpuser and resetting root." >&3
[[ "$RESTOREHOST_ACCESS" == "userroot" ]] && userroot

###
test -r $TMPDIR/postscript.sh && echo "Running post script." >&3
test -r $TMPDIR/postscript.sh && . $TMPDIR/postscript.sh

###
# All done without error
echo "Finished. Will now sync and reboot."   # for logfile
echo "Copying logfile to $NewRootDir." >&3
cp -p $DebugFile $NewRootDir

if [[ "$RESTOREHOST_REBOOT" == "no" ]]
then
	echo >&3
	echo "Finished. Now please remove the virtual DVD/CD. No reboot was specified." >&3
	echo >&3
else
	echo >&3
	echo "Finished. Now please remove the virtual DVD/CD. This host will now reboot." >&3
	echo >&3
	sync; sync
	sleep 10
	reboot -fd    # useful: -f do halt, -d don't write to wtmp
fi
exit 0

