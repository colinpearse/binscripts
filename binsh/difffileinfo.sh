#!/usr/bin/ksh


# Copyright (c) 2005-2019 Colin Pearse.
# All scripts are free in the binscripts repository but please refer to the
# LICENSE file at the top-level directory for the conditions of distribution.
#
# Author:      Colin Pearse
# Description: Part of bootablebackup.sh. This takes two tgz files (reports from getfileinfo.sh) and compares them.


# This takes two tgz files (reports from getfileinfo.sh) and compares them in 4 passes:
# 1. filenames only.
# 2. file attributes (mode/usr/group) against files existing in both reports.
# 3. file sums and sizes against files existing in both reports.
# 4. special pass for Linux because it doesn't display maj/min numbers in the find output.
#
#set -n
[[ "$Debug" == "" ]] && Debug=0
(($Debug>=9)) && set -x

myname=$(basename $0)

GetScriptName="getfileinfo.sh"
GetScriptNameDir="getfileinfo.sh.dir"   # for AIX since its tar doesn't allow metachars; see unzip_files()
HOSTNAME=$(uname -n)
OSn=$(uname -s)
ARCH=$(uname -m)
Username=$(id |sed "s/).*//1;s/.*(//1")

export PATH=.:/usr/xpg4/bin:/etc:/sbin:/bin:/usr/sbin:/usr/bin:/usr/platform/$ARCH/sbin:/usr/cluster/bin:/usr/es/sbin/cluster:/usr/es/sbin/cluster/utilities:/usr/local/bin:$PATH:/usr/ucb:/usr/ccs/bin

FilesCreatedByRestore="/etc/lvm /restorehost.sh.debug /restore_selinux.sh.log /boot/grub/device.map.save /etc/fstab.save /etc/inittab.save /etc/restore_selinux.sh"
FilesRemovedByRelabel="/var/lib/rpm/__db"
FilesThatChangeFrequently="/etc/adjtime /etc/aliases.db /etc/cups/certs/0"
BB_ExcludeFiles="$FilesRemovedByRelabel $FilesCreatedByRestore"
BB_ExcludeAttrs=""
BB_ExcludeSums="/var/log/ /var/run/ $FilesThatChangeFrequently"
BB_ExcludeLDevs=""
ExcludeFiles=""
ExcludeAttrs=""
ExcludeSums=""
ExcludeLDevs=""

TempFile=$myname.$$
myname_dir="$myname.dir"
Unzip_tmpdir="/tmp/$myname_dir.$$"

cleanup()
{
	ret_value=$1 ; [[ "$1" == "" ]] && ret_value=1
	rm -rf $Unzip_tmpdir
      exit $ret_value
}
trap cleanup 1 2 6 9 15        # don't do exit signal 0 as cleanup calls itself when it exits

usage()
{
	cat >&2 <<EOF

usage: $myname [-b] [-f ExclDirs] [-a ExclAttrs] [-s ExclSums] [-l ExclLDevs] <BeforeTarGz> <AfterTarGz>

       -f   Exclude dirs/files from passes 1-4.
       -a   Exclude dirs/files from pass   2.
       -s   Exclude dirs/files from pass   3.
       -l   Exclude dirs/files from pass   4.
       -b   Use sensible bootablebackup.sh excludes (after system has just been restored).
            IE. Use: -f "$BB_ExcludeFiles" -a "$BB_ExcludeAttrs" -s "$BB_ExcludeSums" -l "$BB_ExcludeLDevs"

BeforeTarGz and AfterTarGz are the resultant tar gz'ed files from running: $GetScriptName
There are 3 passes (4 for Linux):
   1. Filenames differences only.
   2. Attribute (mode/user/group/filename) differences.
   3. Sum/Size/filename differences.
   4. Linux Device/filename differences. Since /dev on Linux is a pseudo-filesystem and therefore not
      listed by "find / -xdev ..." this pass is only useful if adhoc devices exist on real filesystems.

   eg. $myname -b -f "/root/ /var/spool" before.tgz after.tgz
   eg. $myname -f "/root/ /etc/lvm" before.tgz after.tgz

EOF
	exit 2
}
get_args()
{
	(($Debug>=9)) && set -x

	ALL_ARGS="$*"
	f_OPT=0 ; a_OPT=0 ; s_OPT=0 ; l_OPT=0 ; b_OPT=0
	while getopts "bf:a:s:l:h?" name
	do
		case $name in
		f)      f_OPT=1 ; ExcludeFiles="$ExcludeFiles $OPTARG" ;;
		a)      a_OPT=1 ; ExcludeAttrs="$ExcludeAttrs $OPTARG" ;;
		s)      s_OPT=1 ; ExcludeSums="$ExcludeSums $OPTARG" ;;
		l)      l_OPT=1 ; ExcludeLDevs="$ExcludeLDevs $OPTARG" ;;
		b)      b_OPT=1
			ExcludeFiles="$ExcludeFiles $BB_ExcludeFiles"
			ExcludeAttrs="$ExcludeAttrs $BB_ExcludeAttrs"
			ExcludeSums="$ExcludeSums $BB_ExcludeSums"
			ExcludeLDevs="$ExcludeLDevs $BB_ExcludeLDevs"
			;;
		h|?|*)  usage ;;
		esac
	done
	shift $(($OPTIND - 1))
	[[ "$1" == "" || "$2" == "" ]] && usage
	TarGzFile1="$1"
	TarGzFile2="$2"

	# Strip spaces at the beginning and end of string. Also, extra spaces should be removed so EGR... doesn't end up having "..||..".
	ExcludeFiles=$(echo "$ExcludeFiles" |sed "s,^ *,,1;s, *$,,1")
	ExcludeAttrs=$(echo "$ExcludeAttrs" |sed "s,^ *,,1;s, *$,,1")
	ExcludeSums=$(echo  "$ExcludeSums"  |sed "s,^ *,,1;s, *$,,1")
	ExcludeLDevs=$(echo "$ExcludeLDevs" |sed "s,^ *,,1;s, *$,,1")
	EGRfiles=" "$(echo "$ExcludeFiles" |sed "s/ [ ]*/| /g") ; [[ "$ExcludeFiles"  == "" ]] && EGRfiles="do not match for grep -v"
	EGRattrs=" "$(echo "$ExcludeAttrs" |sed "s/ [ ]*/| /g") ; [[ "$ExcludeAttrs" == "" ]] && EGRattrs="do not match for grep -v"
	EGRsums=" "$(echo  "$ExcludeSums"  |sed "s/ [ ]*/| /g") ; [[ "$ExcludeSums"  == "" ]] && EGRsums="do not match for grep -v"
	EGRldevs=" "$(echo "$ExcludeLDevs" |sed "s/ [ ]*/| /g") ; [[ "$ExcludeLDevs" == "" ]] && EGRldevs="do not match for grep -v"
}

#############################
# EG output of ..findls..: 232 4 drwxr-xr-x 3 root root 4096 Jun 30 19:04 /opt/file -> ./link
# these functions use the varibale: fs
diff_fnames()
{
	(($Debug>=9)) && set -x

	# field 11 onwards just in case filename has a space in it (NOTE: Linux find -ls does '\ ' for spaces)
	Func=$1 ; f="$2" ; d1="$3" ; d2="$4"
	EGRstr=$(echo "$EGRfiles" |tr ' ' '^') # result of simple find (names only) will be at the beginning of the line
	cut -d' ' -f11- "$d1/$f" |egrep -v "$EGRstr" |sort > $d1/$TempFile.$Func
	cut -d' ' -f11- "$d2/$f" |egrep -v "$EGRstr" |sort > $d2/$TempFile.$Func
	DIFF=$(diff $d1/$TempFile.$Func $d2/$TempFile.$Func |egrep "^<|^>")
	[[ "$DIFF" != "" ]] && echo "$DIFF"

	# EGRknown is for excluding filenames in diff_fattributes and diff_fsums since the diff in
	# those functions need not repeat showing missing or extra files.
	EGRknown=$(echo "$DIFF" |egrep "^<|^>" |sed "s/^<//1;s/^>//1" |awk '{print " "$1"$|"}' |tr -d '\n')"do not match grep -v"
	echo "$fs:$EGRknown:" >> $EGRfile
}
# mode/user/group/filename
diff_fattributes()
{
	(($Debug>=9)) && set -x

	Func=$1 ; f="$2" ; d1="$3" ; d2="$4"
	EGRknown=$(egrep "^$fs:" $EGRfile |tail -1 |cut -d':' -f2)
	cut -d' ' -f3,5,6,11- "$d1/$f" |egrep -v "$EGRattrs|$EGRknown|$EGRfiles" |sort -k4 > $d1/$TempFile.$Func
	cut -d' ' -f3,5,6,11- "$d2/$f" |egrep -v "$EGRattrs|$EGRknown|$EGRfiles" |sort -k4 > $d2/$TempFile.$Func
	diff $d1/$TempFile.$Func $d2/$TempFile.$Func |egrep "^<|^>"
}
# sum/size/filename
diff_fsums()
{
	(($Debug>=9)) && set -x

	Func=$1 ; f="$2" ; d1="$3" ; d2="$4"
	EGRknown=$(egrep "^$fs:" $EGRfile |tail -1 |cut -d':' -f2)
	cat "$d1/$f" |egrep -v "$EGRsums|$EGRknown|$EGRfiles" |sort -k3 > $d1/$TempFile.$Func
	cat "$d2/$f" |egrep -v "$EGRsums|$EGRknown|$EGRfiles" |sort -k3 > $d2/$TempFile.$Func
	diff $d1/$TempFile.$Func $d2/$TempFile.$Func |egrep "^<|^>"
}
# 624733 4 crw-rw---- 1 root root 180,33 Jul 4 2006 ./dev/usb/ez1
# mode/user/group/maj-min,filename
diff_flinuxdevs()
{
	(($Debug>=9)) && set -x

	Func=$1 ; f="$2" ; d1="$3" ; d2="$4"
	EGRknown=$(egrep "^$fs:" $EGRfile |tail -1 |cut -d':' -f2)
	cut -d' ' -f3,5,6,7,11- "$d1/$f" |egrep -v "$EGRldevs|$EGRknown|$EGRfiles" |sort -k4 > $d1/$TempFile.$Func
	cut -d' ' -f3,5,6,7,11- "$d2/$f" |egrep -v "$EGRldevs|$EGRknown|$EGRfiles" |sort -k4 > $d2/$TempFile.$Func
	diff $d1/$TempFile.$Func $d2/$TempFile.$Func |egrep "^<|^>"
}

# d1/<files>  are passed in the args
# Sets: fs
# NOTE for Linux: ls -1d sorts _slash_dev.out before _slash_.out because '.' is ignored
diff_files()
{
	(($Debug>=9)) && set -x

	Func=$1 ; metaf="$2" ; d1="$3" ; d2="$4"
	for pname in $(ls -1rtd "$d1"/$metaf)
	do
		f=$(basename $pname)
		fs=$(echo "$f" |sed "s/[^\.]*\.//1;s/\.out//1" |sed "s,_slash_,/,g")
		
		# check same filename exists in d2
		if test -f $d2/$f
		then
			echo "Calling $Func for $fs:"
			$Func $Func "$f" "$d1" "$d2"
		else
			echo "$myname: ERROR: Cannot find file: $d2/$f"
			echo "$myname: ERROR: Directory/filesystems in tar.gzs could be different. Compare directories..."
			find "$d1"
			find "$d2"
		fi
	done
}
# This checks that tar zip files extract to a relative not absolute dir
# Sets: d1 and d2
unzip_files()
{
	(($Debug>=9)) && set -x

	test -d $Unzip_tmpdir && echo "$myname: Please remove directory: $Unzip_tmpdir" && exit 1
	set -e
	mkdir -p $Unzip_tmpdir

	# Change from "${GetScriptName}*" to "$GetScriptNameDir" because ... |tar xf - "str*"  is not implemented on AIX
	export Unzip_tmpdir GetScriptName
	gunzip -c $1 |(cd $Unzip_tmpdir && tar xf - "$GetScriptNameDir")
	d=$(ls -1d $Unzip_tmpdir/* |grep "$GetScriptNameDir" |head -1)
	mv "$d" "$d.1"
	d1="$d.1"

	gunzip -c $2 |(cd $Unzip_tmpdir && tar xf - "$GetScriptNameDir")
	d=$(ls -1d $Unzip_tmpdir/* |grep "$GetScriptNameDir" |head -1)
	mv "$d" "$d.2"
	d2="$d.2"

	EGRfile="$Unzip_tmpdir/$TempFile.egreps"
	> $EGRfile
	test -r $EGRfile
	test -d "$d1"
	test -d "$d2"
	set +e

	HasLs=0 ; find "$d1" |grep -q "/findls\." && HasLs=1
	HasSum=0 ; find "$d1" |grep -q "/findsum\." && HasSum=1
	HasLDevs=0 ; find "$d1" |grep -q "/findlinuxdevs\." && HasLDevs=1
}



##########
# Main
##########
get_args "$@"
unzip_files "$TarGzFile1" "$TarGzFile2"

echo
echo "Original CmdLine 1: "$(cat "$d1"/cmdline)
echo "Original CmdLine 2: "$(cat "$d2"/cmdline)
echo
echo "Exclude list for -f is \"$ExcludeFiles\""
echo "Exclude list for -a is \"$ExcludeAttrs\""
echo "Exclude list for -s is \"$ExcludeSums\""
echo "Exclude list for -l is \"$ExcludeLDevs\""
(($HasLs)) && echo
(($HasLs)) && echo "Comparing filenames..."
(($HasLs)) && diff_files diff_fnames      "findls.*.out" "$d1" "$d2"

(($HasLs)) && echo
(($HasLs)) && echo "Comparing mode/user/group of filenames that exist in both reports..."
(($HasLs)) && diff_files diff_fattributes "findls.*.out" "$d1" "$d2"

(($HasSum)) && echo
(($HasSum)) && echo "Comparing sum/size on filenames that exist in both reports..."
(($HasSum)) && diff_files diff_fsums       "findsum.*.out" "$d1" "$d2"

(($HasLDevs)) && echo
(($HasLDevs)) && echo "Comparing linux devs that exist in both reports..."
(($HasLDevs)) && diff_files diff_flinuxdevs  "findlinuxdevs.*.out" "$d1" "$d2"

cleanup 0  # and exit


