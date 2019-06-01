#!/bin/bash

# Copyright (c) 2005-2019 Colin Pearse.
# All scripts are free in the binscripts repository but please refer to the
# LICENSE file at the top-level directory for the conditions of distribution.
#
# Name:        runall.sh
# Description: Script to run command on multiple systems (like dsh).


VERSION="1.6"

Myname=$(basename $0)
WS=$(printf " \t")
StderrNewline=""

ExitInterrupt=999
ExitTimeout=998
ExitKilled=997  # no exit file when process has finished; if I can write this value to the file then it probably means the process was killed (not filesystem full)

###############
###############
HostFile=""
Hosts=""
DefaultHostFile="/etc/hosts"
SshUser="${USER:-nouser}"
ConnectCmd="ssh -n -l$SshUser"       # put these in .ssh/config: -oLogLevel=ERROR -oBatchMode=yes -oConnectTimeout=5 -oPreferredAuthentications=publickey -oStrictHostKeyChecking=yes
Arg_c=0
#ConnectCmd="ssh -nB --allowed-authentications=publickey --tcp-connect-timeout=5"
HostTimeout=0
SshTimeout=5
RshArgs=""
ArgEgrHosts=""
ArgEgrOpt=""
ParseCmd="cat"
TmpDir="$HOME/tmp"
UniqStr=""
ShowLastRun=0
StatusSecs=0
ShowStdout=1
ShowStderr=1
OutputArg=0
ShowCols=1
MaxProcs=0
VerbosityLevel=1

#################
#################
usage()
{
	cat >&2 <<EOF

 usage: $Myname [-c cmd] [-f file]  [-e expr] [-D dir] [-OEN] [-S secs] <command>
        $Myname [-c cmd] [-H hosts] [-e expr] [-D dir] [-OEN] [-S secs] <command>
        $Myname -l       [-f file]  [-e expr] [-D dir] [-OEN] [-S secs]
        $Myname -l       [-H hosts] [-e expr] [-D dir] [-OEN] [-S secs]

  -f file   run <command> on the list of hosts in this file (default: $DefaultHostFile)
  -H hosts  run <command> on this (comma separated) list of hosts; this cannot be used with -f
  -e expr   case-insensitive expr to restrict the hosts list; !expr excludes, eg. "!host[01]$"
  -o cmd    command to parse output data (default: "$ParseCmd")
  -D dir    specify a different temporary directory (default: "$TmpDir")
  -u ustr   specify a unique string for temporary files: <tmpdir>/$Myname<.ustr>.<host>.out / err / exit (default: "$UniqStr")
  -l        show last runall.sh result
  -O        show stdout results (stderr turned off)
  -E        show stderr results (stdout turned off)
  -N        show no stdout/stderr results
  -S secs   show status of all hosts every <secs> seconds; number of out / err lines are shown (-1 indicates script has not started)
  -C cols   convert output to <cols> columns
  -c cmd    use <cmd> to connect (default: "$ConnectCmd")
            NOTE: "-n" (no stdin) is added to ssh/rsh to avoid SIGTTIN traps when running commands in the background
            NOTE: if rsh is used then "-l root" is used too
  -U user   ssh user (default: $SshUser)"
  -t secs   Timeout for ssh command used with -c (default: $SshTimeout)
  -T secs   Timeout for command(s) after connection is established; 0 = no timeout (default: $HostTimeout)
  -p qty    Run <qty> parallel cmds; if there are too many you could get the error "socket: All ports in use"
  -v level  Set verbosity level (default: $VerbosityLevel)

 This script will run <command> on the hosts in the file indicated by -f (all hosts must have passwordless logon)
 All calls will be done in parallel unless -p 1 is specified.

 If quotes are to be used then this generally works better when <command> is specified between single quotes
 and double quotes are used within. _QUOTE_ and _QUOTES_ can also be used and will be translated into ' and "
 respectively (see example below).

 The files $TmpDir/$Myname.<host>.out .err and .exit are created (and not removed) when using this script so
 that previous runs can be shown (with -l). Other users may overwrite these files (permissions permitting)
 so please use "-D dir" if you want these resultant files to be unique.

 egs. $Myname -e myms1 'egrep -i \$(uname -n) /etc/hosts'                          # look for entries in /etc/hosts
      $Myname -e myms1 'echo "sleep 3; ls -l / > /tmp/test 2>&1" |at now'         # run commands via cron
      $Myname -e myms1 "cat /etc/test"                                            # examine result of previous example
      $Myname -e myms1 -lO                                                        # list stdout of last run
      $Myname -e myms1 -lO -o "tail -1"                                           # as above and only print the last line of each host
      $Myname -H host1,host2 "ifconfig en2 |grep en2:"                            # ifconfig on host1 and host2
      $Myname -f newhostlist "ifconfig en2 |grep en2:"                            # ifconfig on all hosts in newhostlist
      $Myname -f newhostlist -lO                                                  # list stdout of last run using newhostlist

EOF
	exit 2
}

#################
#################
GetOptions()
{
	while getopts "f:H:e:o:D:u:lOENS:C:c:U:t:T:p:v:h?" name
	do
		case $name in
		f) HostFile="$OPTARG" ;;
		H) Hosts="$OPTARG" ;;
		e) ArgEgrHosts="$OPTARG" ;;
		o) ParseCmd="$OPTARG" ;;
		D) TmpDir="$OPTARG" ;;
		u) UniqStr="$OPTARG" ;;
		l) ShowLastRun=1 ;;
		O) let OutputArg+=1; ShowStdout=1; ShowStderr=0 ;;
		E) let OutputArg+=1; ShowStderr=1; ShowStdout=0 ;;
		N) let OutputArg+=1; ShowStderr=0; ShowStdout=0 ;;
		S) StatusSecs=$OPTARG ;;
		C) ShowCols=$OPTARG ;;
		c) Arg_c=1; ConnectCmd=$OPTARG ;;
		U) SshUser="$OPTARG" ;;
		t) SshTimeout=$OPTARG ;;
		T) HostTimeout=$OPTARG ;;
		p) MaxProcs=$OPTARG ;;
		v) VerbosityLevel=$OPTARG ;;
		*) usage ;;
		esac
	done
	shift $(($OPTIND - 1))
	(($ShowLastRun == 0)) && [[ "$1" == "" ]] && usage
	SetCmd "$@"
}

##############
##############
CheckOptions()
{
	[[ "$HostFile" != "" && "$Hosts" != "" ]] && errexit 2 "-f and -H are mutually exclusive"
	(($OutputArg > 1))                        && errexit 2 "-O, -E and -N are mutually exclusive"
	! IsNum "$StatusSecs"  && errexit 2 "-S must be numeric"
	! IsNum "$SshTimeout"  && errexit 2 "-t must be numeric"
	! IsNum "$HostTimeout" && errexit 2 "-T must be numeric"
	! IsNum "$ShowCols"    && errexit 2 "-C must be numeric"
	! IsNum "$MaxProcs"    && errexit 2 "-p must be numeric"

	echo "$ArgEgrHosts" |egrep -q "^!" && ArgEgrOpt="v"  # this will be next to -i
	ArgEgrHosts=$(echo "$ArgEgrHosts" |sed "s/^!//1")

	case $ConnectCmd in
	ssh*)
		ConnectCmd=$(SetOption "$ConnectCmd" "-n" "")
#		ConnectCmd=$(SetOption "$ConnectCmd" "--tcp-connect-timeout" "$SshTimeout")   # Tectia SSH2
		ConnectCmd=$(SetOption "$ConnectCmd" "-oConnectTimeout=" "$SshTimeout")
		((!$Arg_c)) && ConnectCmd=$(SetOption "$ConnectCmd" "-l" "$SshUser")   # don't change user if -c
		RshArgs=
		;;
	rsh*)
		RshArgs="-n -l root"
		;;
	esac
}

###########
###########
# If $Opt is not in $Cmd then add it
SetOption()
{
    typeset Cmd="$1"
    typeset Opt="$2"
    typeset Arg="$3"
    if echo "$Cmd" |egrep -q " $Opt" # if options is used
    then
		if [[ "$Arg" != "" ]]
		then
			case $Opt in
			--*) echo "$Cmd" |sed "s/\(.* $Opt\)=*[^ ]*\( *.*\)/\1${Arg:+=}$Arg\2/1" ;;
			-*)  echo "$Cmd" |sed "s/\(.* $Opt\)=*[^ ]*\( *.*\)/\1$Arg\2/1" ;;
			*)   echo "$Cmd" |sed "s/\(.* $Opt\) *[^ ]*\( *.*\)/\1${Arg:+ }$Arg\2/1" ;;
			esac
		else
			echo "$Cmd" # if option has no argument then keep the $Cmd as is
		fi
    else
        case $Opt in
        --*) echo "$Cmd $Opt${Arg:+=}$Arg" ;;
        -*)  echo "$Cmd $Opt$Arg" ;;
        *)   echo "$Cmd $Opt${Arg:+ }$Arg" ;;
        esac
    fi
}

###############
###############
IsNum()       { echo "$1" |egrep -q "^[0-9][0-9]*$"; }
GetTmpFile()  { echo "$TmpDir/$Myname${UniqStr:+.}$UniqStr.$Host.$1"; }

########
########
# Put single quotes around every arg with a space in.
SetCmd()
{
	Cmd=""
	typeset Arg
	for Arg in "$@"
	do
		if echo "$Arg" |grep -q " "
		then
			Cmd="$Cmd${Cmd:+ }'$Arg'"
		else
			Cmd="$Cmd${Cmd:+ }$Arg"
		fi
	done
}

#########
#########
SetVars()
{
	typeset HostList
	if [[ "$Hosts" != "" ]]
	then
		HostList=$(echo $Hosts |tr ',' '\n')
	else
		[[ "$HostFile" == "" ]] && HostFile="$DefaultHostFile"
		! test -r $HostFile && errexit 1 "file \"$HostFile\" does not exist or is not readable"
		HostList=$(egrep "^[a-zA-Z0-9_]" $HostFile)
	fi

	Hosts=$(echo "$HostList" |egrep -i$ArgEgrOpt -- "$ArgEgrHosts" |awk '{print $1}' |xargs echo)
	HostCount=$(echo "$Hosts" |wc -w |awk '{print $1}')
	[[ "$MaxProcs" == "0" ]] && MaxProcs=$HostCount

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
verbose_func()
{
	typeset Newline="$1"; shift
	typeset Level="$1"; shift
	typeset Format="$1"; shift
	if (($VerbosityLevel >= $Level))
	then
		printf "$Format" "$@" >&2
		StderrNewline="$Newline"
	fi
}
verbose()
{
	typeset Level="$1"; shift
	typeset Format="$1"; shift
	verbose_func "" "$Level" "$StderrNewline$Format\n" "$@"
}
verbose_nonl()
{
	typeset Level="$1"; shift
	typeset Format="$1"; shift
	verbose_func "\n" "$Level" "$Format" "$@"
}
DisplayDot()       { (($VerbosityLevel <= 1)) && verbose_nonl 1 "."; }      # only do dots for lowest level verbosity
NewlineAfterDots() { (($VerbosityLevel <= 1)) && verbose_func "" 1 "\n"; }  # this displays a newline and sets StderrNewline=""

###############
###############
CheckNotDone()
{
	typeset BlankFilePaths=$(for Host in $Hosts
	do
		File=$(GetTmpFile "out")
		! test -s $File && echo $File
	done)
	typeset BlankFiles=$(echo "$BlankFilePaths" |sed "s,$TmpDir/$Myname.\(.*\).out,\1,1" |xargs echo)
	verbose 1 "The following hosts have not produced any output: $BlankFiles"

	typeset Proc=0
	while (($Proc < $MaxProcs))
	do
		typeset Pid=${JobsPid[$Proc]}
		typeset PidChild=${JobsPidChild[$Proc]}
		typeset Host=${JobsHost[$Proc]}
		typeset ExitFile=$(GetTmpFile "exit")

		if [[ "$Pid" != "" || "$PidChild" != "" ]]
		then
			kill -9 $PidChild $Pid >/dev/null 2>&1
			verbose 1 "Killing: $PidChild and $Pid"
			echo $ExitInterrupt > $ExitFile  # process ended due to interrupt
		fi
		let Proc+=1
	done

	PrintResults
	SetSuccessesAndFailures displaytotal
	(($Failures)) && exit 1
	exit 0
}

###################
###################
PrintWithHostname()
{
	verbose 1 "Results (std$1) -----------"
	typeset HostPad=30
	typeset Lines
	typeset Host
	for Host in $Hosts
	do
		typeset File=$(GetTmpFile "$1")
		if ! test -s $File
		then
			[[ "$1" == "out" ]] && printf "%-${HostPad}s %s\n" "$Host:" "---no output---"  # only for stdout
		elif test -r $File
		then
			typeset Err=""; echo "$File" |egrep -q "\.err$" && Err="(STDERR)"
#			cat $File |sh -c "$ParseCmd" |awk -v h=$Host -v e=$Err '{print h e": "$0}';
			cat $File |sh -c "$ParseCmd" |while read Line
			do
				printf "%-${HostPad}s %s\n" "$Host$Err:" "$Line"
			done
			Lines=$(cat $File |sh -c "$ParseCmd" |wc -l |awk '{print $1}')
			[[ "$Lines" -gt 1 ]] && printf "%-${HostPad}s %s\n" "$Host$Err:" "---end---"
		else
			echo "$Host: ERROR: $File not found"
		fi
	done
}
PrintResults()
{
	(($ShowStdout && $ShowCols == 1)) && PrintWithHostname out
	(($ShowStdout && $ShowCols  > 1)) && PrintWithHostname out |column.pl -S'   | ' -C$ShowCols
	(($ShowStderr && $ShowCols == 1)) && PrintWithHostname err
	(($ShowStderr && $ShowCols  > 1)) && PrintWithHostname err |column.pl -S'   | ' -C$ShowCols
#	(($ShowCols > 1)) && echo 'CP: ignoring -C <cols> at the moment - I need to update if I want to keep "nice" format changes'
#	(($ShowStdout)) && PrintWithHostname out |column.pl -s: -S: -F2
#	(($ShowStderr)) && PrintWithHostname err |column.pl -s: -S: -F2
}

#########################
#########################
# "echo" used so that the output can be piped to column.pl
PrintStatusWithHostname()
{
	typeset StartSecs=$(echo ${JobsStart[@]} |awk '{print $1}')  # use the first job to set count
	typeset CurrentCount=$(($SECONDS - ${StartSecs:-$SECONDS}))
	typeset HourMin=$(date '+%H:%M')
	verbose 1 "Status of jobs (time=$HourMin,c=${CurrentCount}s,timeout=${HostTimeout}s) -----------"
	typeset Host
	for Host in $Hosts
	do
		typeset OutFile=$(GetTmpFile "out")
		typeset ErrFile=$(GetTmpFile "err")
		typeset ExitFile=$(GetTmpFile "exit")
		typeset OutLines=$(wc -l $OutFile 2>/dev/null |awk '{print $1}')
		typeset ErrLines=$(wc -l $ErrFile 2>/dev/null |awk '{print $1}')
		typeset ExitValue=$(cat $ExitFile 2>/dev/null |awk '{print $1}')
		! test -r $OutFile && OutLines=-1
		! test -r $ErrFile && ErrLines=-1
		! test -r $ExitFile && ExitValue="running"
		echo "$Host: ---$ExitValue--- stdout($OutLines) stderr($ErrLines)"
	done
}

########################
########################
SetSuccessesAndFailures()
{
	Successes=0
	for Host in $Hosts
	do
		typeset ExitFile=$(GetTmpFile "exit")
		if test -r $ExitFile
		then
			typeset ExitValue=$(cat "$ExitFile" 2>/dev/null)
			if IsNum $ExitValue
			then
				case $ExitValue in
				0)         let Successes+=1 ;;
				$ExitInterrupt) echo "$Host: ERROR: local interrupt" ;;
				$ExitTimeout)   echo "$Host: ERROR: command timed out" ;;
				$ExitKilled)    echo "$Host: ERROR: command died without writing an exit file" ;;
				esac
			else
				echo "$Host: ERROR: exit value found in \"$ExitFile\" is not numeric \"$ExitValue\""
			fi
		else
			echo "$Host: ERROR: exit file \"$ExitFile\" not found"
		fi
	done
	Failures=$(($HostCount - $Successes))
	[[ "$1" == "displaytotal" ]] && echo "Successes=$Successes Failures=$Failures" >&2
}

###############
###############
# user "fuser -fuV" to check to tmp file being written (don't worry about reading, ie. fd=0)
# fuser -fu:  backup/runall.sh: 18678052(colin)
# fuser -fuV: backup/runall.sh: 
#             inode=147943 size=23080        fd=1      18678052(colin)
CheckTmpFiles()
{
	typeset RetValue=0
	typeset TmpFile
	typeset FuserOut
	typeset Pid
	typeset User
	typeset Affix
	typeset Host
	for Affix in out err exit
	do
		for Host in $Hosts
		do
			TmpFile=$(GetTmpFile "$Affix")
			if test -f $TmpFile
			then
				FuserOut=$(fuser -fuV "$TmpFile" 2>&1 |egrep "fd=" |head -1 |sed "s/.*fd=/fd=/1")  # eg. "fd=1  18678052(colin)"
				Fd=$(  echo "$FuserOut" |awk '{print $1}')
				Pid=$( echo "$FuserOut" |awk '{print $2}' |sed 's/[()]/ /g' |awk '{print $1}')
				User=$(echo "$FuserOut" |awk '{print $2}' |sed 's/[()]/ /g' |awk '{print $2}')
				if [[ "$Pid" != "" && "$Fd" == "fd=1" ]]
				then
					echo "ERROR: user \"$User\" is writing to \"$TmpFile\" (pid=$Pid) so will not remove" >&2
					RetValue=1
				fi
			fi
		done
		return $RetValue
	done
}

################
################
RemoveTmpFiles()
{
	typeset Affix
	typeset Host
	typeset TmpFile=$(GetTmpFile "$Affix")
	for Affix in out err exit
	do
		for Host in $Hosts
		do
			TmpFile=$(GetTmpFile "$Affix")
			test -f "$TmpFile" && rm -f "$TmpFile"
		done
	done
}

###########
###########
# GetRunningJobs:    will display a list of PIDs, eg: "56165842 6227474 11470402 57082218"
# eg. "jobs -l"
#[52] + 56165842  running                 <command unknown>
#[39] - 6227474   running                 <command unknown>
#[27]   11470402  running                 <command unknown>
#[1]   57082218   running                 <command unknown>
#[2]   57082221   done(2)                 <command unknown>
#[3]   57082226   done                    <command unknown>
GetJobsRunning() { jobs -l |tr '[A-Z]' '[a-z]' |egrep -i "running" |sed "s/.*[$WS][$WS]*\([0-9][0-9]*\)[$WS][$WS]*running.*/\1/g" |xargs echo; }

###########
###########
SetupJobs()
{
	typeset Cmd="$1"; shift
	JobCount=0
	for Host in "$@"
	do
		AllJobsHost[$JobCount]="$Host"
		AllJobsCmd[$JobCount]="$Cmd"
		let JobCount+=1
	done
	JobsTotal=$JobCount
	JobCount=0
	HostsTimedOut=""
}

########
########
# Two background processes will be run (1) $Cmd and (2) wait for $Cmd. When I kill (1) then (2) will die.
# This is preferable to "$Cmd && echo $?" where $! is the shell executing $Cmd, and not $Cmd itself.
RunJob()
{
	typeset Proc="$1"
	typeset Host="${AllJobsHost[$JobCount]}"
	typeset Cmd=$(eval echo "${AllJobsCmd[$JobCount]}" |sed "s/_QUOTE_/'/g;s/_QUOTES_/\"/g")
	typeset StartSecs="$SECONDS"
	typeset TempOut=$(GetTmpFile "out")
	typeset TempErr=$(GetTmpFile "err")
	typeset TempExit=$(GetTmpFile "exit")

	# NOTE: because "... && echo 0 ... || echo $? ..." is used two processes (parent and child) are run
	#       (1) parent: ksh which echoes the return code and
	#       (2) child:  the real process ("$ConnectCmd $Host ...")
	#        $! will refer to (1) so I have to use it to obtain (2)
	$ConnectCmd $Host $RshArgs${RshArgs:+ }"$Cmd" >$TempOut 2>$TempErr && echo 0 > $TempExit || echo $? > $TempExit &
	typeset Pid=$!
	typeset PidChild=$(ps -eo ppid,pid |sed "s/  */ /g;s/^ //1" |egrep "^$Pid " |awk '{print $2}' |xargs echo)
	if echo "$PidChild" |egrep -q " "
	then
		errexit 3 "more than one child process ($PidChild) created when runnning on host $Host"
	fi

	DisplayDot
	JobsHost[$Proc]="$Host"
	JobsCmd[$Proc]="$Cmd"
	JobsPidChild[$Proc]=$PidChild   # this is the one that needs to be killed
	JobsPid[$Proc]=$Pid
	JobsStart[$Proc]=$StartSecs
	verbose 2 "RunJob: %s: job=%s: proc=%s: start=%s: %s: %s" "$Pid" "$JobCount" "$Proc" "$StartSecs" "$Host" "$Cmd"
	let JobCount+=1
}

###########
###########
# If job is still running check whether it has run too long
# Otherwise it has finished so blank the PID in JobsPid[$Proc]
CheckSetJobs()
{
	typeset PidsRunning="$1"
	verbose 2 "CheckSetJobs: still running: %s" "$PidsRunning"
	typeset Proc=0
	while (($Proc < $MaxProcs))
	do
		typeset Pid=${JobsPid[$Proc]}
		typeset PidChild=${JobsPidChild[$Proc]}
		typeset Host=${JobsHost[$Proc]}
		typeset Cmd=${JobsCmd[$Proc]}
		typeset StartSecs=${JobsStart[$Proc]}
		typeset CurrentSecs="$SECONDS"
		typeset ExitFile=$(GetTmpFile "exit")
		if [[ "$Pid" == "" ]]
		then
			:
			: process has finished already
			:
		elif ! echo " $PidsRunning " |egrep -q " $Pid "
		then
			:
			: process has just finished
			:
			typeset ExitValue=$(cat $ExitFile 2>/dev/null)
			[[ "$ExitValue" == "" ]] && verbose 1 "%s: WARNING: no exit value found for \"%s\" on host \"%s\" (pids=%s and %s)" "$Myname" "$Cmd" "$Host" "$Pid" "$PidChild"
			JobsPid[$Proc]=""
			JobsPidChild[$Proc]=""
			echo ${ExitValue:-$ExitKilled} > $ExitFile  # process was probably killed by someone if writing to $ExitFile works this time
		else
			:
			: process still going - check timeout
			:
			if (($HostTimeout && $CurrentSecs > ($StartSecs + $HostTimeout) ))  # 0 timeout = no timeout
			then
				verbose 1 "%s: WARNING: host \"%s\" timed out: \"%s\" is still running after %s seconds - killing %s and %s" "$Myname" "$Host" "$Cmd" "$HostTimeout" "$PidChild" "$Pid"
				kill -9 $PidChild $Pid >/dev/null 2>&1
				JobsPid[$Proc]=""
				JobsPidChild[$Proc]=""
				HostsTimedOut="$HostsTimedOut${HostsTimedOut:+ }$Host"
				echo ${ExitValue:-$ExitTimeout} > $ExitFile  # process timed out if $ExitValue is blank here
			fi
		fi
		let Proc+=1
	done
}

#################
#################
# 0 - there are still jobs running
# 1 - all jobs have finished
JobStillRunning()
{
	typeset Proc=0
	while (($Proc < $MaxProcs))
	do
		if [[ "${JobsPid[$Proc]}" != "" ]]
		then
			verbose 3 "JobStillRunning: job(%s) pids(%s and %s) host(%s) cmd(%s)" "$Proc" "${JobsPid[$Proc]}" "${JobsPidChild[$Proc]}" "${JobsHost[$Proc]}" "${JobsCmd[$Proc]}"
			return 0
		fi
		let Proc+=1
	done
	return 1
}

##########
##########
# This will run up to $MaxProcs at a time until all jobs
# have completed or timed-out
# NOTE: SetupJobs() must have been called before this
RunJobs()
{
	typeset StatusReset=$SECONDS
	typeset Proc=0
	while :
	do
		if [[ "${JobsPid[$Proc]}" == "" ]] && (($JobCount < $JobsTotal))
		then
			RunJob "$Proc"
		fi
		let Proc+=1

		if (($Proc >= $MaxProcs || $JobCount >= $JobsTotal))
		then
			sleep 1
			CheckSetJobs "$(GetJobsRunning)"
			Proc=0
		fi

		if ! JobStillRunning && (($JobCount >= $JobsTotal))
		then
			return 0
		fi

		if (($StatusSecs && $SECONDS >= ($StatusReset + $StatusSecs) ))
		then
			(($ShowCols == 1)) && PrintStatusWithHostname
			(($ShowCols  > 1)) && PrintStatusWithHostname |column.pl -S'   | ' -C$ShowCols
			StatusReset=$SECONDS
		fi
	done
	verbose 1 "\n"
}

#######
#######
Main()
{
	if (($ShowLastRun == 0))
	then
		mkdir -p $TmpDir
		! test -d $TmpDir && errexit 1 "Could not create temporary directory ($TmpDir)"

		! CheckTmpFiles && errexit 1 "$Myname sees a file conflict with another $Myname process (see above errors) - you can (a) wait for previous run to complete or (b) use -D to use another temporary directory"

		RemoveTmpFiles

		verbose_nonl 1 "Running command on all hosts in $HostFile (all must have no password login)"
		trap CheckNotDone 1 2 6 9 15

		SetupJobs "$Cmd" $Hosts
		RunJobs
	fi

	PrintResults
	SetSuccessesAndFailures displaytotal
	(($Failures)) && return 1 || return 0
}

#########
#########
GetOptions "$@"
CheckOptions
SetVars
Main "$Cmd"
exit $?

