# -no shell because AIX/Sun/HP/Linux don't always have korn/bash in the same place


# Copyright (c) 2005-2019 Colin Pearse.
# All scripts are free in the binscripts repository but please refer to the
# LICENSE file at the top-level directory for the conditions of distribution.
#
# Author:      Colin Pearse
# Description: Part of bootablebackup.sh. Basic script to get 3 types of listings of the root disk or root volume group.


# For Sun, (HP - not yet), AIX and Linux.
#
# Basic script to get 3 types of listings of the root disk or root volume group:
# NOTE: any sorting to make comparisons easier can be done at the compare stage
# 1. find <dir>
# 2. find <dir> -ls
# 3. find <dir> -exec sum {} \;   # which does a 'sum' on the normal files
# (4. find for Linux devices) This is because Linux find does not show maj,min numbers. However,
#  since /dev is a special filesystem on Linux find / -xdev will not see any special devices
#  anyway. I will keep this fourth pass though in just in case /dev is specified explicitly.
# 
#
# ?. Do rpm -qal, lslpp -f, cat /var/sadm/install/contents ?
#
#set -n

if test "$1" = "found_MyShell"
then
	shift
else
	test -x /sbin/bash && MySHELL=/sbin/bash
	test -x /sbin/ksh  && MySHELL=/sbin/ksh
	test -x /usr/bin/bash && MySHELL=/usr/bin/bash
	test -x /usr/bin/ksh  && MySHELL=/usr/bin/ksh
	test -x /bin/bash && MySHELL=/bin/bash
	test -x /bin/ksh  && MySHELL=/bin/ksh
	test "$MySHELL" = "" && echo "Cannot find korn or bash shell - exiting..." && exit 3
	exec $MySHELL $0 "found_MyShell" "$@"
fi


##################
# the script should now be running with korn or bash
myname=$(basename $0)
HOSTNAME=$(uname -n)
OSn=$(uname -s)
ARCH=$(uname -m)
Username=$(id |sed "s/).*//1;s/.*(//1")

export PATH=.:/usr/xpg4/bin:/etc:/sbin:/bin:/usr/sbin:/usr/bin:/usr/platform/$ARCH/sbin:/usr/cluster/bin:/usr/es/sbin/cluster:/usr/es/sbin/cluster/utilities:/usr/local/bin:$PATH:/usr/ucb:/usr/ccs/bin

##################
[[ "$GETFILEINFO_EXCLUDE_FSS" == "" ]] && GETFILEINFO_EXCLUDE_FSS=""
[[ "$GETFILEINFO_TMPDIR" == "" ]]      && GETFILEINFO_TMPDIR="/tmp"
TmpDir="$GETFILEINFO_TMPDIR/$myname.$$"
TarGzFile="$myname.$HOSTNAME.tar.gz"
ExcludeDirs="$TmpDir"
ExcludeFss="$GETFILEINFO_EXCLUDE_FSS"
IncludeFss=""

myname_dir="$myname.dir"

cleanup()
{
	ret_value=$1 ; [[ "$1" == "" ]] && ret_value=1
	rm -rf $TmpDir
        exit $ret_value
}
trap cleanup 1 2 6 9 15        # don't do exit signal 0 as cleanup calls itself when it exits

usage()
{
	cat >&2 <<EOF

usage: $myname [-p|-x] [-f TarGzFile] [-e ExcludeDirs] [-E ExcludeFss] [-I IncludeFss]

       -p   Preview - display guess of filesystems on root disk/vg where fileinfo will be collected.
       -x   Execute - get and zip file information.
       -f   Create TarGzFile    (default is "$myname.$HOSTNAME.tar.gz")
       -e   Exclude directories (default is "")
       -E   Exclude filesystems (default is "$GETFILEINFO_EXCLUDE_FSS")
       -I   Include filesystems (default is guess)

	NOTE: The temp dir used by this script is always excluded.
	NOTE: For -e /dir1 will exclude /dir1 and /dir11. Use /dir1/ for a less generic match.

   eg. $myname -p
   eg. $myname -x -f /tmp/dir1.tar.gz -i . -e "./dir1/"
   eg. $myname -x -f /tmp/dir1.tar.gz -e "/bin/lib" -E "/tmp /home"
   eg. cd /mydir1; $myname -x -I . -f /tmp/mydir1.tar.gz
 cont. cd /mydir2; $myname -x -I . -f /tmp/mydir2.tar.gz

 To see the command line used in a TarGz file previously created by this script
 set gz (eg. gz=before.tgz) and then cut'n'paste the following command:
 d=$myname.dir; gunzip -c \$gz |tar xf - "\$d/cmdline" && cat \$d/cmdline && rm -f \$d/cmdline && rmdir \$d

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
	p_OPT=0 ; x_OPT=0 ; f_OPT=0 ; e_OPT=0 ; E_OPT=0 ; I_OPT=0
	while getopts "pxf:e:E:I:h?" name
	do
		case $name in
		p)      p_OPT=1 ;;
		x)      x_OPT=1 ;;
		f)      f_OPT=1 ; TarGzFile="$OPTARG" ;;
		e)      e_OPT=1 ; ExcludeDirs="$ExcludeDirs $OPTARG" ;;  # allow -e dir -e dir ...
		E)      E_OPT=1 ; ExcludeFss="$ExcludeFss $OPTARG" ;;  # allow -E fs -E fs ...
		I)      I_OPT=1 ; IncludeFss="$IncludeFss $OPTARG" ;;  # allow -I fs -I fs ...
		h|?|*)  usage ;;
		esac
	done
	shift $(($OPTIND - 1))
	#RestOfArgs="$1"
	(($p_OPT==$x_OPT)) && usage
	[[ "$1" != "" ]] && usage   # don't accept any other args after shift
}

###################
getAIX_root_fss()
{
	
	# mount output for AIX leaves 1st column blank if not an nfs mount (1st col is node)
	mounted_fss=$(mount |awk '{print "x"$0}' |awk '{print $3}' |grep "^/" |sort 2>/dev/null)
	root_fss=$(lsvg -l rootvg |grep open |egrep "jfs2[^a-z]" |awk '{print $NF}')
	if [[ "$root_fss" == "" ]]
	then
		echo "Couldn't get root disk or VG name"
		root_fss="/ /usr /opt /var /tmp /home"
	fi
}
getLinux_root_fss()
{
	FSTAB=$(grep -v "^#" /etc/fstab)
	mounted_fss=$(mount |awk '{print $3}' |grep "^/" |sort 2>/dev/null)

	rootdisk=$(echo "$FSTAB" |grep swap |grep "c.t.d.s." |sed "s,.*/c,c,1;s,s.*,,1")
	[[ "$rootdisk" == "" ]] && rootdisk=$(echo "$FSTAB" |grep swap |cut -d'/' -f3)

	if [[ "$rootdisk" == "" ]]
	then
		echo "Couldn't get root disk or VG name"
		root_fss="/ /boot /usr /opt /var /tmp /home"
	else
		root_fss=$(echo "$FSTAB" |grep "/$rootdisk/" |awk '{print $2}' |grep "^/" |sort 2>/dev/null)
		root_fss="/boot $root_fss"   # /boot is usually separate from the root volume
	fi
}
getSun_root_fss()
{
	VFSTAB=$(grep -v "^#" /etc/vfstab)
	mounted_fss=$(mount |awk '{print $1}' |grep "^/" |sort 2>/dev/null)

	rootdisk=$(echo "$VFSTAB" |awk '{if($3~/^\/$/){print $0}}' |head -1 |grep "/vx/" |cut -d'/' -f5)
	[[ "$rootdisk" == "" ]] && rootdisk=$(echo "$VFSTAB" |awk '{if($3~/^\/$/){print $0}}' |head -1 |grep "/dsk/" |sed "s,.*/c,c,1;s,s.*,,1")

	if [[ "$rootdisk" == "" ]]
	then
		echo "Couldn't get root disk or VG name"
		root_fss="/ /usr /opt /var /tmp /home"
	else
		root_fss=$(echo "$VFSTAB" |grep "/$rootdisk" |awk '{print $3}' |grep "^/")
	fi
}

get_mounted_root_fss()
{
	mounted_root_fss=""

	for fs in $root_fss
	do
		echo "$mounted_fss" |grep "^$fs$" >/dev/null 2>&1
		mounted_root_fss="$mounted_root_fss $fs"
	done
	mounted_root_fss=$(echo "$mounted_root_fss" |tr ' ' '\n' |sort -u |egrep -v "^$")
}

exclude_fss()
{
	EGRfss="^"$(echo  "$*" |sed "s/ /$|^/g")"$"
	[[ "$ExcludeFss" == "" ]] && EGRfss="do not match for grep -v"
	# should have "^/name1|^/name2" and " /name1| /name2" -or- "do not match for grep -v"
	mounted_root_fss=$(echo "$mounted_root_fss" |tr ' ' '\n' |egrep -v "$EGRfss")
}

get_root_fss()
{
	case $OSn in
		AIX*)   getAIX_root_fss ;;
	#	HP*)    getHP_root_fss ;;
		Sun*)   getSun_root_fss ;;
		Linux*) getLinux_root_fss ;;
	#	*)      getGeneric_root_fss ;;
	esac
}

test_file()
{
	if test -s $1
	then
		printf "errors."
	else
		printf "ok."
	fi
}

# NOTE: Already tried: find dir >file ; cat file |xargs ...
#       xargs -i .. {} is too slow and without -i xargs will not treat filenames with spaces in them.
getinfo()
{
	EGRdirs=" "$(echo "$ExcludeDirs" |sed "s/ /| /g")
	[[ "$ExcludeDirs" == "" ]] && EGRdirs="do not match for grep -v"

	# The output files are parsed through sed so that the result is "single space" separated (for cut and sort later on).
	# Just in case xargs is used later watch out for spaces in filenames, use xargs -i .. {}
	for fs in $*
	do
		displayfs=$(echo "$fs" |sed "s,/,_slash_,g")
		FindFilels="$TmpDir/$myname_dir/findls.$displayfs"
		FindFilesum="$TmpDir/$myname_dir/findsum.$displayfs"
		FindLinuxDevs="$TmpDir/$myname_dir/findlinuxdevs.$displayfs"

		printf "$(date): Filesystem: %-20.20s" "$fs"

		## Get file attributes ##############
		# NOTE: find /dev -ls does not display maj/min nos for devices. If /dev is included explicitly then the 3rd pass below
		#       will retrieve maj/min numbers.
		printf " findls..."
		[[ "$OSn" == "Linux" ]] && find $fs -xdev \( ! -type c -a ! -type b \) -ls 2>$FindFilels.err |sed "s/  */ /g;s/^ //1" |egrep -v "$EGRdirs" >$FindFilels.out
		[[ "$OSn" != "Linux" ]] && find $fs -xdev -ls 2>$FindFilels.err |awk '{if($7~/,$/){$7=$7$8;$8=""};print $0}' |sed "s/  */ /g;s/^ //1" |egrep -v "$EGRdirs" >$FindFilels.out
		test_file $FindFilels.err

		## Get file sum ##############
		# NOTE: A single find ... |perl script would be ideal to keep things standard but the major() minor() functions
		#       are not with the standard perl install so the masks used would have to be hardcoded (not ideal) for $rdev.
		#cat $FindFile.out |getfileinfo.pl > $FindFilesum.out 2>$FindFilesum.err
		# NOTE: "make_sum_display_filename" is given as a second filename since sum will only display filenames when
		#       there are more than one specified.
		printf " findsum..."
		find $fs -xdev \( -type f -a ! -type l \) -exec sum {} "make_sum_display_filename" \; 2>$FindFilesum.err |sed "s/  */ /g;s/^ //1" |egrep -v "$EGRdirs" >$FindFilesum.out
		mv $FindFilesum.err $FindFilesum.err2
		grep -v "make_sum_display_filename" $FindFilesum.err2 >$FindFilesum.err ; rm -f $FindFilesum.err2
		test_file $FindFilesum.err

		## Get linux device attributes ##############
		# NOTE: find / -xdev ... will not get devices since /dev for Linux is a separate filesystem created at boot time
		#       (df -k /dev shows '-'). Below is only useful for adhoc devices in the filesystem or an explicit find /dev.
		if [[ "$OSn" == "Linux" ]]
		then
			printf " findlinuxdevs..."
			find $fs -xdev \( -type c -o -type b \) -exec ls -lis {} \; 2>$FindLinuxDevs.err |awk '{if($7~/,$/){$7=$7$8;$8=""};print $0}' |sed "s/  */ /g;s/^ //1" |egrep -v "$EGRdirs" >$FindLinuxDevs.out
			test_file $FindLinuxDevs.err
		fi

		printf "\n"
	done
}
create_TmpDir()
{
	set -e
	mkdir $TmpDir
	mkdir $TmpDir/$myname_dir
	echo "$CmdLine" > "$TmpDir/$myname_dir/cmdline"
	set +e
	return 0
}
zip_myname_dir()
{
	echo "$(date): Making gzipped tar file of results ($TarGzFile)."
	set -e
	#may use ksh so cannot use pushd
	export TmpDir myname_dir
	(cd $TmpDir && tar cf - $myname_dir |gzip -c) > $TarGzFile
	set +e
	return 0
}

##########
# Main
##########
get_args "$@"
if [[ "$IncludeFss" != "" ]]
then
	# if fss specified by user then avoid 'mounted' checks
	mounted_root_fss="$IncludeFss"
	exclude_fss $ExcludeFss
else
	get_root_fss
	get_mounted_root_fss
	exclude_fss $ExcludeFss
fi

(($p_OPT==1)) && echo $(echo $mounted_root_fss) && exit 0

# Execute mode
create_TmpDir
echo "$(date): Saving information for: "$mounted_root_fss
getinfo $mounted_root_fss
zip_myname_dir

echo "$(date): Done $myname"
cleanup 0   # removed TmpDir too

