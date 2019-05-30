# -no shell because AIX/Sun/HP/Linux don't always have korn/bash in the same place


# Copyright (c) 2005-2019 Colin Pearse.
# All scripts are free in the binscripts repository but please refer to the
# LICENCE file at the top-level directory for the conditions of distribution.
#
# Name:         getsysinfo.sh
# Description:  Get system config for Sun, HP, AIX and Linux


# NOTE: Sun uses egrep only and not grep -E, so use egrep
#
# The idea is to make the list of commands in: getAIX_sysinfo, getHP_sysinfo, getSun_sysinfo and getLinux_sysinfo ;;
# as easily readable as possible. If a command/file/directory doesn't exist the command run by "run" or "run_loop"
# should simply fail.
#
# Verbosity level
# ---------------
# -v[v] is used to up the level of info. Ie. 0 'v's mean only the 'run 0 ...'  are executed. 2 'v's mean 'run [0,1,2] ...' are executed.
#
# run and run_loop commands
# -------------------------
# run_loop runs <command 1> and the output is taken and given to <command 2>, EG.
# run      <level> "ls -1"
# run_loop <level> "ls -1 2>/dev/null" "cat -v \$1"
# --where each listed file is also cat'ed.
# One should always do the following with run_loop:
# . redirect errout as per the example so that <command 2> doesn't run anything unknown
# . use 'run' to run <command 1> on it's own which can show errors and help debugging and understanding output file
#
# Headings:
#	Heading=GENERAL
#	Heading=NETWORK
#	Heading=STORAGE
#	Heading=DRIVER
#	Heading=LOG
#	Heading=STARTUP
#	Heading=SNAPSHOT
#	Heading=CLUSTER
#	Heading=SECURITY
#	Heading=PACKAGES
#	Heading=PATCHES
#
# CHANGES:
# - added Solaris 10 stuff
# - changed "find ... -exec file ... |cut -d: -f1"  to  "... |sed 's/:[$TAB ].*//1'"  because a lot of files have ':' in their name
#
##################
# Beginning is born shell stuff to ascertain a location for ksh or bash
# (Linux sometimes will not have ksh and bash shell is not always on AIX, Sun or HP)
#
VERSION="0.1"

PATH=/bin:/usr/bin:$PATH

#set -n   # don't exec commands - for testing syntax errors

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
myname=`basename $0`
HOSTNAME=`uname -n`
OSn=`uname -s`
ARCH=`uname -m`
TAB=`printf "\t"`
Username=`id |sed "s/).*//1" |sed "s/.*(//1"`

test "0$DEBUG_sh" -ge 1 && set -x

TMP_DIR="."                  # temporary directory
CMD_TIMEOUT=300              # cap run time to 5 mins per command
CMD_MAX_OUTPUT_SIZE=1048576  # cap output at 1MB per command

export PATH=/usr/xpg4/bin:/etc:/sbin:/bin:/usr/sbin:/usr/bin:/usr/platform/$ARCH/sbin:/usr/cluster/bin:/usr/es/sbin/cluster:/usr/es/sbin/cluster/utilities:/usr/local/bin:$PATH:/usr/ucb:/usr/ccs/bin
usage()
{
	exec >&2
	echo
	echo "usage: $myname <-p|-x> [-lv] [-t <secs>] [-s <bytes>] [-d <dir>]"
	echo
	echo "       -p          Preview (see what commands will be used)."
	echo "       -x          Execute."
	echo "       -t <secs>   Timeout for commands (default: $CMD_TIMEOUT seconds)."
	echo "       -s <bytes>  Max output size for commands (default: $CMD_MAX_OUTPUT_SIZE bytes)."
	echo "       -d <dir>    Specify temporary directory (default: $TMP_DIR)."
	echo "       -l          Include heading in the label."
	echo "       -ll         Include hostname and heading in the label."
	echo "       -v[v]       Get more info, (degrees of info: 0, 1 and 2 exist for now)."
	echo
	echo "       TIMEOUT:            Look for \"ret_value=256\""
	echo "       OUTPUT_TOO_BIG:     Look for \"ret_value=257\""
	echo "       Commands not found: Look for \"ret_value=127\""
	echo
	echo "       EG: $myname -plvv      will show the maximum commands run (ie. 2 'v's = 2'nd degree info)"
	echo "       EG: $myname -xlvv      will execute them"
	echo "       OR  echo \"./$myname -xlvv > sysinfo.$HOSTNAME.$Username.txt 2>&1\" |at now"
	echo "       OR  nohup ./$myname -xlvv > sysinfo.$HOSTNAME.$Username.txt 2>&1&"
	echo
	exit 2
}

x_OPT=0
p_OPT=0
v_OPT=0
l_OPT=0
#t_OPT=0
#s_OPT=0
#d_OPT=0
while getopts "xplvt:s:d:h?" name
do
	case $name in
	x)      x_OPT=1 ;;
	p)      p_OPT=1 ;;
	l)      l_OPT=$(($l_OPT + 1)) ;;
	v)      v_OPT=$(($v_OPT + 1)) ;;
	t)      if expr $OPTARG + 0 >/dev/null 2>&1
		then
			CMD_TIMEOUT=$OPTARG
		else
			echo "\n$myname: Timeout must be numeric." >&2
			usage 
		fi
		;;
	s)      if expr $OPTARG + 0 >/dev/null 2>&1
		then
			CMD_MAX_OUTPUT_SIZE=$OPTARG
		else
			echo "\n$myname: Max output size must be numeric." >&2
			usage 
		fi
		;;
	d)      if test -d $OPTARG >/dev/null 2>&1
		then
			TMP_DIR=$OPTARG
		else
			echo "\n$myname: $OPTARG is not a directory." >&2
			usage 
		fi
		;;
	h|?|*)	usage ;;
	esac
done
(($x_OPT == $p_OPT)) && usage

TEMPFILE1=$TMP_DIR/$myname.tmp1.$$
TEMPFILE2=$TMP_DIR/$myname.tmp2.$$
TEMPFILE3=$TMP_DIR/$myname.tmp3.$$
TEMPFILE4=$TMP_DIR/$myname.tmp4.$$
cleanup()
{
	rm -f $TEMPFILE1 $TEMPFILE2 $TEMPFILE3 $TEMPFILE4
        exit 0
}
trap cleanup 0 1 2 6 9 15        # 0: exit signal


#############
# Functions
#############

# uses: l_OPT, CMD, Heading, HOSTNAME
# sets:
cat_with_CMD()
{
	test "0$DEBUG_sh" -ge 9 && set -x

	if (($l_OPT > 1))
	then
		cat $1 |awk -v cmd="$CMD" -v head="$Heading" -v host="$HOSTNAME" '{print host ":" head ":" cmd ":" $0}'
	elif (($l_OPT > 0))
	then
		cat $1 |awk -v cmd="$CMD" -v head="$Heading" '{print head ":" cmd ":" $0}'
	else
		cat $1 |awk -v cmd="$CMD" '{print cmd ":" $0}'
	fi
}

# uses: 
# sets:
# args: list of process ids
# Typically one arg (one process id) is passed initially. The script kills the children, then calls
# itself to kill their children, etc, etc
kill_descendants()
{
	test "0$DEBUG_sh" -ge 1 && set -x

	for _ppid in $*
	do
		kids_display=`ps -ef |cut -c1-80 |awk -v ppid=$_ppid '{if($3==ppid){print $0}}'`
		kids=`echo "$kids_display" |awk '{print $2}' |tr '\n' ' '`

		if test "$kids_display" != ""
		then
			echo "Found children:"
			echo "$kids_display"
			kill_descendants $kids
		fi
	done
	echo "kill -9 $*"
	kill -9 $*        # kill from bottom up
}

# uses: CMD_TIMEOUT
# sets:
# args: arg1=job id, arg2=filename that will contain commands exit code, arg3=output filename
# NOTE: I found that job control (-m) with Linux doesn't work very well so I
#       use ps -e instead.
run_wait()
{
	test "0$DEBUG_sh" -ge 9 && set -x

	_pid=$1
	_ret_value_file=$2
	_output_filename=$3
	i=0

################
# NOTE: bug in Linux ps:
# when: CMD="..cmd.. |grep ..." the command (referenced with $!) does not appear in ps -e !!
# Therefore run_wait cannot check for it's termination.
# Therefore the command below will not work correctly.
#	while ps -e |awk -v pid=$_pid -v r=1 '{if($1==pid){r=0}} END{exit r}'
#
# ps -p <pid>  works ok on all Unix types and is much easier.
################

	while ps -p $_pid >/dev/null 2>&1
	do
		sleep 1
		i=$(($i+1))

		OUTPUT_SIZE=$(ls -l $_output_filename |awk '{print $5}')

		if (($i >= $CMD_TIMEOUT))
		then
			echo "$myname: Timeout ($CMD_TIMEOUT secs) reached for ($CMD), calling kill_descendants()" >&2
			ps -ef |cut -c1-80 |awk -v pid=$_pid '{if($2==pid){print $0;exit 0}}'
			kill_descendants $_pid        # kill children recursively first
			echo 256 > $_ret_value_file   # set timeout failure (>255 should be used to test)

		elif (($OUTPUT_SIZE > $CMD_MAX_OUTPUT_SIZE))
		then
			echo "$myname: Max size ($CMD_MAX_OUTPUT_SIZE bytes) exceeded for ($CMD), calling kill_descendants()" >&2
			ps -ef |cut -c1-80 |awk -v pid=$_pid '{if($2==pid){print $0;exit 0}}'
			kill_descendants $_pid        # kill children recursively first
			echo 257 > $_ret_value_file   # set output too big failure (>255 should be used to test)
		fi
	done
}

# uses: v_OPT, TEMPFILE1, TEMPFILE2
# sets:
# args: arg1=detail level, arg2=command
run()
{
	test "0$DEBUG_sh" -ge 5 && set -x

	(($# != 2)) && echo 'ERROR: run_loop must take 2 arguments. $#=('"$#"') $*=('"$*"'). PLEASE CORRECT !!'

	v_LEVEL=$1
	if (($v_LEVEL <= $v_OPT))
	then
		CMD="$2"

		if (($x_OPT==1))
		then
			echo 0 > $TEMPFILE2        # default is success
			sh -c "$CMD" > $TEMPFILE1 2>&1 || sh -c "echo $? > $TEMPFILE2" &
			run_wait $! $TEMPFILE2 $TEMPFILE1 > $TEMPFILE4 2>&1
			cat $TEMPFILE4 >> $TEMPFILE1
			echo "ret_value="`cat $TEMPFILE2` >> $TEMPFILE1
			cat_with_CMD $TEMPFILE1
		else
			#This displays the contents.
			# Don't do: echo "$Heading::$CMD" use awk to display command instead (exactly like cat_with_CMD) so that
			#  the strings are identical (AIX/Linux's awk remove the backslash \ but echo doesn't)
			echo "$Heading:" |awk -v cmd="$CMD" '{print $0":"cmd}'
		fi
	fi
}

# uses: v_OPT, p_OPT, TEMPFILE1, TEMPFILE2
# sets:
# args: arg1=detail level, arg2=command whose output is used in loop, arg3=command
# use input from rl_CMD1 as args for rl_CMD2. Use \$1 \$2 ... when passing rl_CMD2
#
# NOTE: a recursive run_loop was tried but the example in getSun_sysinfo (getting network interface info)
#       shows why it wasn't useful unless variables from different iterations are kept:
#   I wanted to use it for this line:
#       run_loop 0 "find /devices -xdev -name 'network*' |cut -d: -f2 |grep -v network |sort" "ndd -get /dev/\$1 \'?\' \|awk \'{print \\\$1}\' \|xargs -I {} ndd -get /dev/\$1 {}"
#   However,
#     cmd 1. gets the names (eg. bge1),
#     cmd 2. would show the parameters (ndd -get /dev/\$1 '?')  --but--
#     cmd 3. would have to use output from cmd1 and cmd2 which recursive run_loop wouldn't do.
#            (In "ndd -get <var from cmd1> <var from cmd2>" how would run_loop know which output \$1 refers to?).
#
run_loop()
{
	test "0$DEBUG_sh" -ge 5 && set -x

	(($# != 3)) && echo 'ERROR: run_loop must take 3 arguments. $#=('"$#"') $*=('"$*"'). PLEASE CORRECT !!'

	v_LEVEL=$1
	if (($v_LEVEL <= $v_OPT))
	then
		rl_CMD1="$2"
		rl_CMD2="$3"

		if (($p_OPT==1))
		then
			echo "$Heading: ($rl_CMD1) used to generate further ($rl_CMD2) commands:"
		fi

		echo 0 > $TEMPFILE2        # default is success
		sh -c "$rl_CMD1" > $TEMPFILE3 2>&1 || sh -c "echo $? > $TEMPFILE2" &
		run_wait $! $TEMPFILE2 $TEMPFILE3

		# Some progs return error even when displaying something useful so don't check return code.
		#if cat $TEMPFILE2 |grep -q "^0$"
		if test -s $TEMPFILE3
		then
			while read ARGS
			do
				set $ARGS #plug in output from TEMPFILE3 into \$1, \$2, etc or \$*
				rl_CMD2_withargs=$(eval echo "$rl_CMD2")

				run $v_LEVEL "$rl_CMD2_withargs"
			done < $TEMPFILE3
		fi
	fi
}

#########################
# Getinfo system stuff
#
# NOTE: -follow option not recognised on AIX
#########################
common_sysinfo()
{
	test "0$DEBUG_sh" -ge 1 && set -x

	Heading=GENERAL
	run      0 "date"
	run      0 "uname -a"
	run      0 "locale"
	run      0 "ls -ld /*"
	run      0 "ls -ld /etc/*"
	run      0 "ls -ld /usr/*"
	run      0 "ls -ld /opt/*"
	run      0 "cat /etc/passwd"
	run      0 "cat /etc/group"

	run      0 "ls -ld /var/spool/cron/crontabs/*"
	run_loop 1 "file /var/spool/cron/crontabs/* 2>&1 |grep -v data |grep text |sed 's/:[$TAB ].*//1'" "cat -v \$1"
	run      0 "cat /var/adm/cron.allow"
	run      0 "cat /var/adm/cron.deny"
	run      0 "find /etc -xdev -name '*tab' -ls"
	run_loop 1 "find /etc -xdev -name '*tab' -exec file {} \; 2>/dev/null |grep -v data |egrep -i 'text|script' |sed 's/:[$TAB ].*//1'" "cat -v \$1"
	run      0 "find /etc -xdev -name '*.conf' -ls"
	run_loop 1 "find /etc -xdev -name '*.conf' -exec file {} \; 2>/dev/null |grep -v data |egrep -i 'text|script' |sed 's/:[$TAB ].*//1'" "cat -v \$1"
}

common_network_info()
{
	test "0$DEBUG_sh" -ge 1 && set -x

	Heading=NETWORK
	run 0 "ifconfig -a"               # getHP_sysinfo will redo this with args
	run 0 "netstat -in"               # useful for AIX - gets MAC address
	run 0 "netstat -rn"
#	run 1 "cat /etc/resolv.conf"      # find in GENERAL will gets this .conf files
#	run 1 "cat /etc/nsswitch.conf"    # find in GENERAL will gets this .conf files
#	run 1 "cat /etc/netsvc.conf"      # find in GENERAL will gets this .conf files
	run 1 "cat /etc/hosts"
	run 1 "cat /etc/netmasks"
	run 1 "cat /etc/services"
	run 1 "arp -an"
	run 0 "rpcinfo -p"
	run 0 "rpcinfo -s"                # won't work on Linux
	run 0 "rpcinfo -m"                # won't work on Linux
	run 0 "ypwhich"
	run 0 "domainname"
	run 0 "exportfs"
	run 0 "cat /etc/exports"
}

common_startup_info()
{
	test "0$DEBUG_sh" -ge 1 && set -x

	Heading=STARTUP
#	run 1 "cat /etc/inittab"          # find in GENERAL will gets this tab files

	# NOTE on find ... -exec file ...:
	# 1. Don't use cut -d: -f1 just in case filenames have : in them.
	# 2. Also file can return "/bin/sh script" (as with Sun) so use just "text|script" (not "text|shell script")

	# Previously did "find /etc/rc*" - but this was too unwieldy since it displayed duplicates due to soft/hard links.
	run      0 "find /etc/*/init.d /etc/init.d /etc/*/rc* /etc/rc* -ls"
	run_loop 1 "find /etc/*/init.d /etc/init.d -xdev -exec file {} \; 2>/dev/null |grep -v data |egrep -i 'text|script' |sed 's/:[$TAB ].*//1'" "cat -v \$1"
	# "file /etc/rc*" put in OS specific functions because Linux does not have -h (don't follow symlinks) option for file
}

common_snapshot_info()
{
	test "0$DEBUG_sh" -ge 1 && set -x

	Heading=SNAPSHOT
	run 0 "uptime"
	run 0 "ipcs -a"
	run 0 "at -l"
	run 0 "netstat -v"
	run 0 "getconf -a"		# all systems now have getconf (HP may not have -a though) - useful for telling 32/64 bit kernel
}

common_driver_info()
{
	test "0$DEBUG_sh" -ge 1 && set -x

	Heading=DRIVER
	run 0 "find /dev -xdev -ls"
}

common_printer_info()
{
	test "0$DEBUG_sh" -ge 1 && set -x

	Heading=PRINTER
	run 0 "lpstat -t"
}

get_common_info()
{
	common_sysinfo
	common_network_info
	common_startup_info
	common_snapshot_info
	common_driver_info
	common_printer_info
}

getSun_sysinfo()
{
	test "0$DEBUG_sh" -ge 1 && set -x

	OSvnum=0
	OSv=$(uname -r)                       # EG. OSv=5.10
	OSvnum=$(echo "$OSv" |cut -d'.' -f2)  # EG. OSvnum=10

	get_common_info

	Heading=GENERAL
	run 0 "eeprom"
	run 0 "isainfo -b"
	run 0 "uname -iX"
	run 0 "cat /etc/user_attr"
	run 0 "cat /etc/project"

	Heading=NETWORK
	run      0 "find /etc/hostname.* -xdev -ls"
	run_loop 0 "find /etc/hostname.* -xdev" "cat -v \$1"
	run 0 "cat /etc/defaultroute"
	run      0 "ndd -get /dev/ip \?"
	run_loop 0 "ndd -get /dev/ip \?  2>/dev/null |egrep '^[A-z]' |sed 's/(.*//g'" "ndd -get /dev/ip \$1"
	run      0 "ndd -get /dev/tcp \?"
	run_loop 0 "ndd -get /dev/tcp \? 2>/dev/null |egrep '^[A-z]' |sed 's/(.*//g'" "ndd -get /dev/tcp \$1"

	# For NIC settings:
	# OLD METHOD: only shows one instance: ndd -get /dev/qfe instance - so not ideal
	#run      0 "ndd -get /dev/qfe \?"
	#run_loop 0 "ndd -get /dev/qfe \? 2>/dev/null |egrep '^[A-z]' |sed 's/(read.*//g'" "ndd -get /dev/qfe \$1"
	#run      0 "ndd -get /dev/hme \?"
	#run_loop 0 "ndd -get /dev/hme \? 2>/dev/null |egrep '^[A-z]' |sed 's/(read.*//g'" "ndd -get /dev/hme \$1"
	#run      0 "ndd -get /dev/bge \?"
	#run_loop 0 "ndd -get /dev/bge \? 2>/dev/null |egrep '^[A-z]' |sed 's/(read.*//g'" "ndd -get /dev/bge \$1"

	# To access new network card types and info on Solaris 10 the following is required (and root access too).
	#  Output from the 1st and 2nd command to be passed to the 3rd command, EG.
	#  1. Get NIC types:         "find /devices -xdev -name "network*" |cut -d: -f2 |grep -v network |sort"
	#  2. List options of NICs:  "ndd -get /dev/\$1 \? 2>/dev/null |egrep '^[A-z]' |sed 's/(read.*//g'"
	#  3. Show those options:    "ndd -get /dev/bge \$1"
	# NEW METHOD: Not ideal, but here's a crude method:
	#  Since ndd -get /dev/\$1 \? includes '?' itself it the output xargs will pick it up and the option defs will
	#  be displayed as well as the settings themselves.
	run      0 "find /devices -xdev -name 'network*' |cut -d: -f2 |grep -v network |sort"
	run_loop 0 "find /devices -xdev -name 'network*' |cut -d: -f2 |grep -v network |sort" "ndd -get /dev/\$1 \'?\' \|awk \'{print \\\$1}\' \|xargs -I {} ndd -get /dev/\$1 {}"

	Heading=STORAGE
	#run 0 "cat /etc/vfstab" # this will be caught by find /etc -xdev -name "*tab"
	run 0 "swap -l"
	run 0 "df -k"
	run 0 "iostat -En"
	run 0 "vxdisk list"
	run 0 "vxprint"
	run      0 "find /etc/vx -name '*info' -ls"
	run_loop 0 "find /etc/vx -name '*info' 2>/dev/null" "cat -v \$1"
	run 0 "ls -ld /dev/rdsk/c*s0"
	run_loop 0 "file /dev/rdsk/c*s0 2>/dev/null |grep 'character spec' |sed 's/:[$TAB ].*//1'" "prtvtoc \$1"
	run      0 "find /etc/auto* -xdev -ls"
	run_loop 1 "find /etc/auto* -xdev -exec file {} \; 2>/dev/null |egrep -i 'text|script' |sed 's/:[$TAB ].*//1'" "cat -v \$1"

	Heading=DRIVER
	run 0 "sysdef"
	run 0 "prtconf -vD"
	(($OSvnum<=6)) && run 0 "modinfo -D"
	(($OSvnum>=7)) && run 0 "modinfo"
	run 0 "powermt display"
	run 0 "find /devices -xdev -ls"
	run 0 "cat /etc/path_to_inst"
	run 0 "cat /etc/name_to_major"
	run 0 "cat /etc/name_to_sysnum"
	run      0 "find /kernel/drv -xdev -ls"
	run_loop 1 "find /kernel/drv -xdev -exec file {} \; 2>/dev/null |grep -v data |egrep -i 'text|script' |sed 's/:[$TAB ].*//1'" "cat -v \$1"

	Heading=LOG
	test -r /var/adm/wtmpx && run 0 "who -a /var/adm/wtmpx |tail -500"
	test -r /var/adm/wtmp  && run 0 "who -a /var/adm/wtmp  |tail -500"
	(($OSvnum>=10)) && run      1 "svcs -l '*' |grep -i logfile"
	(($OSvnum>=10)) && run_loop 1 "svcs -l '*' |grep -i logfile" "cat -v \$2 \|tail -10"
	run 0 "dmesg"

	Heading=STARTUP
	run 0 "prtdiag -v"
	run      0 "find /etc/inet -xdev -ls"
	run_loop 1 "find /etc/inet -xdev -exec file {} \; 2>/dev/null |grep -v data |egrep -i 'text|script' |sed 's/:[$TAB ].*//1'" "cat -v \$1"
	run      0 "find /etc/default -xdev -ls"
	run_loop 1 "find /etc/default -xdev -exec file {} \; 2>/dev/null |grep -v data |egrep -i 'text|script' |sed 's/:[$TAB ].*//1'" "cat -v \$1"
	run      0 "ls -ld /etc/rc*"
	run_loop 0 "file -h /etc/rc* |grep -v data |egrep 'text|script' |sed 's/:[ 	].*//1'" "cat -v \$1"
	(($OSvnum>=10)) && run      0 "find /var/svc/manifest -xdev -name '*.xml' -ls"
	(($OSvnum>=10)) && run_loop 1 "find /var/svc/manifest -xdev -name '*.xml' 2>/dev/null" "cat -v \$1"

	Heading=SNAPSHOT
	#run 2 "find /tmp -xdev -ls"   # bit overkill
	run 0 "ps -ef"
	run 1 "ps -elf"
	(($OSvnum>=10)) && run 0 "svcs -a"
	(($OSvnum>=10)) && run 0 "svcs -l '*'"
	# This is overkill too - svcs done under LOGS now
	#(($OSvnum>=10)) && run      0 "find /etc/svc/volatile -xdev -ls"
	#(($OSvnum>=10)) && run_loop 1 "find /etc/svc/volatile -xdev -exec file {} \; 2>/dev/null |grep -v data |egrep -i 'text|script' |sed 's/:[$TAB ].*//1'" "cat -v \$1"

	Heading=CLUSTER
	run 0 "scstat"   # keep this, not sure if older versions of Sun Cluster do -vv
	run 0 "scstat -pvv"
	run 0 "scconf -pvv"
	run 0 "scrgadm -pvv"

	Heading=VM
	(($OSvnum>=10)) && run      0 "zoneadm list -v"
	(($OSvnum>=10)) && run      0 "ls -l /etc/zones/index"
	(($OSvnum>=10)) && run      0 "cat /etc/zones/index"
	(($OSvnum>=10)) && run      0 "find /etc/zones -xdev -name '*.xml' -ls"
	(($OSvnum>=10)) && run_loop 1 "find /etc/zones -xdev -name '*.xml' 2>/dev/null" "cat -v \$1"

	Heading=SECURITY

	Heading=PACKAGES
	run 0 "pkginfo -x"

	Heading=PATCHES
	run 0 "showrev -a"
	#run 2 "cat /var/sadm/install/contents"  # too much info
}

getAIX_sysinfo()
{
	test "0$DEBUG_sh" -ge 1 && set -x

	OSvnum=0
	OSv=$(uname -v).$(uname -r)     # EG. OSv=5.3
	OSvnum=$(uname -v)              # EG. OSvnum=5

	get_common_info

	Heading=GENERAL
	run 0 "oslevel -s"
	run 0 "hostid"
	run 0 "bootinfo -b"
	run 0 "bootinfo -y"
	run 0 "bootinfo -K"
	run 0 "bootlist -m normal -o"
	run 0 "sysdumpdev -L"
	run 0 "lsattr -El sys0"
	run 0 "lssrc -a"

	Heading=NETWORK
	run 0 "no -a"
	run 0 "lsattr -El inet0"

	Heading=STORAGE
	run 0 "lsps -s"
	run 0 "lsps -a"
	run 0 "df -kI"
	run 0 "lspv"
	run 0 "lsvg"
	run_loop 0 "lsvg 2>/dev/null" "lsvg \$1"
	run_loop 0 "lsvg 2>/dev/null" "lsvg -l \$1"
	run 0 "lsfs -q"
	run 0 "cat /etc/filesystems"
	run      0 "find /etc/auto* -xdev -ls"
	run_loop 1 "find /etc/auto* -xdev -exec file {} \; 2>/dev/null |egrep -i 'text|script' |sed 's/:[$TAB ].*//1'" "cat -v \$1"

	Heading=DRIVER
	run 0 "lsmcode -c"
	run 0 "lsmcode -Ac"
	run 0 "invscout -r"
	run 0 "bindprocessor -q"
	run 0 "lspath"
	run 0 "lscfg -vp"
	run 0 "lsdev -C"
	run_loop 0 "lsdev -C |grep fcs" "fcstat \$1"
	run 0 "ls -Rl /dev"
	run 2 "odmget CuDv"
	run 2 "odmget CuDvDr"
	run 2 "odmget CuAt"

	Heading=LOG
	test -r /var/adm/wtmp && run 0 "who /var/adm/wtmp |tail -500"
	run 0 "audit query"
	run 1 "tail -500 /var/adm/ras/conslog"
	run 1 "tail -200 /smit.log"

	Heading=STARTUP
	run      0 "cat /etc/environment"
	run      0 "ls -ld /etc/rc*"
	run_loop 0 "file -h /etc/rc* |grep -v data |egrep 'text|script' |sed 's/:[ 	].*//1'" "cat -v \$1"

	Heading=SNAPSHOT
	run 0 "ps -ef"
	run 0 "errpt"
	run 1 "errpt -a |head -500"
	run 0 "vmstat -sv"
	(($OSvnum==4)) && run 0 "/usr/samples/kernel/vmtune"
	(($OSvnum==4)) && run 0 "/usr/samples/kernel/vmtune -a"
	(($OSvnum==4)) && run 0 "/usr/samples/kernel/schedtune"
	(($OSvnum>=5)) && run 0 "vmo -a"
	(($OSvnum>=5)) && run 0 "vmo -r -a"
	(($OSvnum>=5)) && run 0 "vmo -p -a"
	(($OSvnum>=5)) && run 0 "ioo -a"
	(($OSvnum>=5)) && run 0 "ioo -r -a"
	(($OSvnum>=5)) && run 0 "ioo -p -a"
	run      0 "find /etc/tunables -xdev -ls"
	run_loop 1 "find /etc/tunables -xdev -exec file {} \; 2>/dev/null |grep -v data |grep text |sed 's/:[$TAB ].*//1'" "cat -v \$1"
	run 0 "genkex"

	Heading=CLUSTER
	(($OSvnum==4)) && run 0 "clstat"
	(($OSvnum>=5)) && run 0 "clstat -o"
	run 0 "clRGinfo"
	run 0 "cltopinfo"
	run 0 "cllscf"
	run 0 "clshowres"
	run 0 "cllsserv"
	run 0 "tail -500 /tmp/hacmp.out"

	Heading=SECURITY
	run      0 "find /etc/security -xdev -ls"
	run_loop 2 "ls -1d /etc/security/* 2>/dev/null |xargs file |grep -v data |grep text |sed 's/:[$TAB ].*//1'" "cat -v \$1"
	run_loop 3 "find /etc/security/*/* -xdev -exec file {} \; 2>/dev/null |grep -v data |grep text |sed 's/:[$TAB ].*//1'" "cat -v \$1"

	Heading=PACKAGES
	run 0 "lslpp -Lqc"

	Heading=PATCHES
	run 2 "instfix -ic"
}

# Other get..._sysinfo() functions for AIX, Linux, Sun have evolved because I could test them.
# The below was left in working order so reluctant to modify it until I can test the changes on HP.
getHP_sysinfo()
{
	test "0$DEBUG_sh" -ge 1 && set -x

	OSv="`uname -r`"                     # EG. OSv=11.00   #change to $() when it's possible to test on HP
	OSvnum=`echo "$OSv" |cut -d'.' -f1`  # EG. OSvnum=11

	get_common_info

	Heading=GENERAL
	run 0 "/opt/ignite/bin/print_manifest"
	run 0 "cat /etc/TIMEZONE"
	run 0 "getconf KERNEL_BITS"           # common_snapshot_info does getconf -a but not sure HP has -a
	run 0 "getconf HW_32_64_CAPABLE"
	run 0 "getconf HW_CPU_SUPP_BITS"
	run 0 "chatr /stand/vmunix"
	run 0 "echo 'cpu_version/X' | adb -k /stand/vmunix /dev/kmem"
	run 0 "echo 'cpu_revision_number/X' | adb -k /stand/vmunix /dev/kmem"
	run 0 "crashconf"
	run 0 "sysdef"
	run 0 "kmtune"
	run 0 "kmsystem"

	Heading=NETWORK
	run 0 "netstat -in"
	run_loop 0 "netstat -in |tail +2" "ifconfig \$1"
	run 0 "lanscan"
	run 0 "lanshow"
	run 0 "cat /var/adm/inetd.sec"
	run 0 "echo '\$Z' |sendmail -bt -d"
	run 0 "praliases"

	Heading=STORAGE
	run 0 "bdf"
	run 0 "swapinfo -tam"
	run 0 "strings /etc/lvmtab |grep dev"
	run 0 "grep -v -e ^# -e ^$ /etc/lvmrc" "Auto-activate /etc/lvmrc"
	run 0 "ls -ld /dev/*/group"
	run 0 "vgdisplay -v"
	run_loop 0 "vgdisplay -v 2>/dev/null |grep 'LV Name'" "lvdisplay \$3"
	#run 0 "/usr/contrib/bin/xpinfo -i|grep -v Scanning"
	#run_loop 0 "/opt/hparray/bin/arraydsp -i |tail -1" "/opt/hparray/bin/arraydsp -a \$2"
	#run 0 "/opt/hparray/bin/amdsp -i"
	run      0 "find /etc/auto* -xdev -ls"
	run_loop 1 "find /etc/auto* -xdev -exec file {} \; 2>/dev/null |egrep -i 'text|script' |sed 's/:[$TAB ].*//1'" "cat -v \$1"

	Heading=DRIVER
	run 0 "ioscan -kfn"
	run_loop 0 "ls /dev/td* /dev/fcms* 2>/dev/null" "fcmsutil \$1"

	Heading=LOG
	run 0 "ls -l /var/adm/shutdownlog"
	run 0 "ls -l /var/adm/syslog/syslog.log"
	run 1 "tail -20 /var/adm/shutdownlog"
	run 1 "tail -500 /var/adm/syslog/syslog.log"

	Heading=STARTUP
	run 0 "setboot"
	run_loop 0 "lvlnboot -v vg00 |grep ^Boot: |sed 's,.*/dsk/,,1'" "diskinfo /dev/rdsk/\$1"
	run_loop 0 "lvlnboot -v vg00 |grep ^Boot: |sed 's,.*/dsk/,,1'" "lifls -l /dev/rdsk/\$1"
	run_loop 0 "lvlnboot -v vg00 |grep ^Boot: |sed 's,.*/dsk/,,1'" "lifcp /dev/rdsk/\$1:AUTO -"
	run 0 "ls -ld /stand/*"
	run 0 "cat /stand/bootconf"
	run 0 "cat /stand/system"
	run      0 "ls -ld /etc/rc*"
	run_loop 0 "file -h /etc/rc* |grep -v data |egrep 'text|script' |sed 's/:[ 	].*//1'" "cat -v \$1"
	#run      0 "ls -ld /etc/rc.config.d/*" # common_startup_info should get this from: find /etc/rc* ...
	#run_loop 1 "file /etc/rc.config.d/* |grep -v data |grep text |sed 's/:[$TAB ].*//1'" "cat -v \$1"

	Heading=SNAPSHOT
	run 0 "export UNIX95=yes;ps -efH"

	Heading=CLUSTER
	run 0 "cmviewcl -v"
	run 0 "find /etc/cmcluster -ls"
	run_loop 1 "find /etc/cmcluster -name '*.cntl'   -xdev -exec file {} \; |grep -v data |egrep -i 'text|script' |sed 's/:[$TAB ].*//1'" "cat -v \$1"
	run_loop 1 "find /etc/cmcluster -name '*.config' -xdev -exec file {} \; |grep -v data |egrep -i 'text|script' |sed 's/:[$TAB ].*//1'" "cat -v \$1"
	run_loop 1 "find /etc/cmcluster -name '*.sh'     -xdev -exec file {} \; |grep -v data |egrep -i 'text|script' |sed 's/:[$TAB ].*//1'" "cat -v \$1"

	Heading=SECURITY
	run 0 "find /etc/tcb -ls"
	run 0 "sysaud query"

	Heading=PACKAGES
	run 0 "cat /var/adm/sw/.codewords"
	run 2 "swlist -l product"
	run 0 "swlist -l depot"
	run 0 "/opt/ifor/ls/bin/i4target -v"
	run 0 "/opt/ifor/ls/bin/i4lbfind -q"

	Heading=PATCHES
	run 0 "swlist"
	run 2 "swlist -l patch"
	run 0 "show_patches -a"
	run 1 "show_patches -s"
}
getLinux_sysinfo()
{
	test "0$DEBUG_sh" -ge 1 && set -x

	OSv=$(uname -r)                       # EG. OSv=1.5.19(0.150/4/2)
	OSvnum=$(echo "$OSv" |cut -d'.' -f1)  # EG. OSvnum=1

	get_common_info

	Heading=GENERAL
	run      0 "ls -ld /etc/cron*"
	run_loop 1 "file /etc/cron* |grep -v data |grep text |sed 's/:[$TAB ].*//1'" "cat -v \$1"
	run 0 "cat /etc/redhat-release"
	run 0 "cat /etc/issue"
	run 0 "cat /proc/version"
	run 0 "cat /etc/shells"
	run 0 "cat /etc/filesystems"

	Heading=NETWORK
	run      0 "ls -ld /etc/sysconfig/network-scripts/ifcfg*"
	run_loop 0 "file /etc/sysconfig/network-scripts/ifcfg* |grep -v data |grep text |sed 's/:[$TAB ].*//1'" "cat -v \$1"
	run      0 "find /etc/sysconfig/networking -xdev -ls"
	run_loop 0 "find /etc/sysconfig/networking -xdev -exec file {} \; |grep -v data |grep text |sed 's/:[$TAB ].*//1'" "cat -v \$1"
	run      0 "find /etc/sysconfig/rhn -xdev -ls"
	run_loop 0 "find /etc/sysconfig/rhn -xdev -exec file {} \; |grep -v data |grep text |sed 's/:[      ].*//1'" "cat -v \$1"
	run      0 "ls -ld /etc/xinetd.d/*"
	run_loop 1 "find /etc/xinetd.d -xdev -type f" "cat -v \$1"
	run      0 "find /proc/sys/net/ipv* -xdev -ls"
	run_loop 1 "find /proc/sys/net/ipv* -xdev -exec file {} \; |grep -v data |grep text |sed 's/:[$TAB ].*//1'" "cat -v \$1"

	Heading=STORAGE
	run 0 "df -k"
	run 0 "fdisk -l"
	run 0 "sfdisk -d"
	run 0 "cat /proc/partitions"
	run 0 "cat /proc/swaps"
	run 0      "find /proc/driver/cciss -ls"   # HW RAID disk(s)
	run_loop 1 "find /proc/driver/cciss -type f 2>/dev/null" "cat -v \$1"
	run 0      "find /proc/ide -ls"
	run_loop 1 "find /proc/ide -type f 2>/dev/null" "cat -v \$1"
	run 0      "find /proc/scsi -ls"
	run_loop 1 "find /proc/scsi -type f 2>/dev/null" "cat -v \$1"
	run 0      "vgdisplay -v"		# LVM used on many Linux servers
	run_loop 0 "vgdisplay -v 2>/dev/null |grep 'LV Name'" "lvdisplay \$3"
	run 0      "pvdisplay -v"
	run 0      "find /proc/lvm -ls"         # LVM info that a normal user can get
	run_loop 1 "find /proc/lvm -type f 2>/dev/null" "cat -v \$1"
	run      0 "find /etc/auto* -xdev -ls"
	run_loop 1 "find /etc/auto* -xdev -exec file {} \; 2>/dev/null |egrep -i 'text|script' |sed 's/:[$TAB ].*//1'" "cat -v \$1"

	Heading=DRIVER
	run 0 "lshw"
	run 0 "cat /proc/driver/rtc"
	run 0 "cat /proc/cpuinfo"
	run 0 "cat /proc/meminfo"
	run 0 "lspci -v"
	run 0 "cat /proc/pci"
	run 0 "cat /proc/ioports"
	run 0 "cat /proc/dma"
	run 0 "cat /proc/tty/driver/serial"

	Heading=LOG
	run 0 "who -w /var/log/wtmp  |tail -500"
	run 0 "cat /var/log/messages |tail -500"

	Heading=STARTUP
	run 0 "cat /proc/cmdline"
	run      0 "ls -ld /boot/grub/*"
	run_loop 0 "file /boot/grub/* |grep -v data |grep text |sed 's/:[$TAB ].*//1'" "cat -v \$1"
	run      0 "ls -ld /etc/sysconfig/*"
	run_loop 0 "file /etc/sysconfig/* |grep -v data |grep text |sed 's/:[$TAB ].*//1'" "cat -v \$1"
	run      0 "find /etc/default -xdev -ls"
	run_loop 1 "find /etc/default -xdev -exec file {} \; 2>/dev/null |grep -v data |egrep -i 'text|script' |sed 's/:[$TAB ].*//1'" "cat -v \$1"
	run      0 "ls -ld /etc/rc*"
	run_loop 0 "file /etc/rc* |grep -v data |egrep 'text|script' |sed 's/:[ 	].*//1'" "cat -v \$1"

	Heading=SNAPSHOT
	run 0 "ps -ef"
	run 0 "free"
	run 2 "ldconfig -vN"
	run 0 "lilo -q"
	run 0 "lsmod"
	run 0 "cat /proc/interrupts"

	Heading=CLUSTER

	Heading=SECURITY
	run      0 "cat /etc/login.defs"
	run      0 "find /etc/pam.d -xdev -ls"
	run_loop 0 "find /etc/pam.d -xdev -exec file {} \; |grep -v data |grep text |sed 's/:[$TAB ].*//1'" "cat -v \$1"
	run      0 "find /etc/security -xdev -ls"
	run_loop 0 "find /etc/security -xdev -exec file {} \; |grep -v data |grep text |sed 's/:[$TAB ].*//1'" "cat -v \$1"

	Heading=PACKAGES
	run 0 "dpkg -l"     # Debian

	Heading=PATCHES
	run 0 "rpm -qa"
	run 1 "rpm -qia"
}
getGeneric_sysinfo()
{
	test "0$DEBUG_sh" -ge 1 && set -x

	get_common_info
}

getSystemInfo()
{
	# -m : don't use job control
	# +u : don't exit if error
	set +u
	#run 0 "/tmp/zztest"
	#rm -f $TEMPFILE1 $TEMPFILE2 $TEMPFILE3 $TEMPFILE4
	#exit 0

	case $OSn in 
		AIX*)	getAIX_sysinfo ;;
		HP*)	getHP_sysinfo ;;
		Sun*)	getSun_sysinfo ;;
		Linux*)	getLinux_sysinfo ;;
		*)	getGeneric_sysinfo ;;
	esac
	#esac |awk -v host="$HOSTNAME" '{print host ":" $0}'    # maybe label with hostname as an option

	#######################
	# Write your own commands here using run and run_loop functions and OSv OSvnum environmentals
	Heading=EXTRA
	# Solaris returns ok even when the file is not found AND puts the error in stdout
	# so the test has to be done the following way.
	mydir=$(dirname $0)
	[[ "$mydir" == "" ]] && mydir=$(which $0 2>/dev/null |grep ^/)
	[[ "$mydir" == "" ]] && mydir="."

	test -r $mydir/$myname.env && . $mydir/$myname.env
	#######################

	rm -f $TEMPFILE1 $TEMPFILE2 $TEMPFILE3 $TEMPFILE4
}

if (($x_OPT==1))
then
	echo "#####################################################################"
	echo "## CONTENTS - The following commands have been executed on $HOSTNAME"
	echo "#####################################################################"
	x_OPT=0 ; getSystemInfo   # list commands - can act like a contents page
	echo
	echo "#####################################################################"
	echo "## DATA - The stdout/stderr of the above commands"
	echo "#####################################################################"
	x_OPT=1 ; getSystemInfo   # do commands
else
	echo "#####################################################################"
	echo "## CONTENTS - The following commands would be executed on $HOSTNAME"
	echo "#####################################################################"
	getSystemInfo # just list commands
fi

exit 0

