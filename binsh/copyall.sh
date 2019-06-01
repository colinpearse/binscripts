#!/bin/bash

# Name:        copyall.sh
# Description: Copy multiple files to multiple servers using rcp, sftp or sshtar method

VERSION="1.3"

Myname=$(basename $0)
Tempfile="/tmp/$Myname.$$"

##############
##############
EgrHosts=""
EgrOpt=""
RemoteUser=""
SourceDir=""
CurrentDir=""
DestDir="/tmp"
CopyPort=""
CopyCmd="scp"
HostFile=""
Hosts=""
HostCount=0
Files=""
FileCount=0

cleanexit() { test -e $Tempfile.log* && rm -f $Tempfile.log*; exit ${1:-1}; }
trap cleanexit 1 2 6 9 15


#######
usage()
{
	cat >&2 <<EOF

 usage: $Myname [-e expr] -f hostfile <file> [file [...]]
        $Myname [-e expr] -H hosts    <file> [file [...]]

 -f hostfile get host list using this file (eg. /etc/hosts)
 -H hosts    specify (comma separated) list of hosts; this cannot be used with -f
 -e expr     case-insensitive expr to restrict the LPAR list; !expr excludes, eg. "!myhost[12]"
 -U user     use this user on the remote host (default: ${RemoteUser:-<current user>})
 -s dir      use this as the source directory (default is current dir)
 -d dir      use this as the destination directory (default is: $DestDir)
 -p port     use this as the port (default: copy command's default)
 -c cmd      copy command; "rcp", "sftp", "sshtar" available (default: $CopyCmd)

 Copies files specified from the local dir (or that of -s) to $DestDir (or that of -d)
 of all hosts specified. The current user (of that of -U) is used to connect to the remote host.

 The copy command used can either be:
 rcp     which will use rcp to copy files to the hosts specified
 sftp    which will create an sftp command file and use sftp to copy files to the hosts specified
 sshtar  which will use ssh and tar to copy files to the hosts specified

 NOTE: this script does not handle filenames containing spaces

 egs. $Myname -H myhost1,myhost2 file1 file2                                       # rcp file1,file2 from local dir to /tmp in myhost1 and myhost2
      $Myname -f /tmp/hosts file1 file2                                            # as above but to <hosts> specified in hosts file
      $Myname -f /tmp/hosts -c sftp -p4 -Uroot -d /tmp -s /home/colin file1 file2  # sftp (port 4) file1,file2 from /home/colin to /tmp dir on <hosts> in /etc/hosts
      $Myname -H host1 -c sshtar -d /tmp -s /home/colin file1 file2                # sh -c "cd /home/colin; tar chf - file1 file2" |ssh host1 "cd /tmp; tar xvf -"

EOF
	exit 2
}


############
GetOptions()
{
	while getopts "f:H:e:U:s:d:p:c:h?" name
	do
		case $name in
		f) HostFile="$OPTARG" ;;
		H) Hosts=$(echo "$OPTARG" |tr ',' ' ' |xargs echo) ;;
		e) EgrHosts="$OPTARG" ;;
		U) RemoteUser="$OPTARG" ;;
		s) SourceDir="$OPTARG" ;;
		d) DestDir="$OPTARG" ;;
		p) CopyPort="$OPTARG" ;;
		c) CopyCmd="$OPTARG" ;;
		*) usage ;;
		esac
	done
	shift $(($OPTIND - 1))
	[[ "$1" == "" ]] && usage

	echo "$EgrHosts" |egrep -q "^!" && EgrOpt="v"  # this will be next to -i
	EgrHosts=$(echo "$EgrHosts" |sed "s/^!//1")

	[[ "$HostFile"  == "" && "$Hosts" == "" ]]          && errexit 2 "\"$Myname <file> [file [...]] <hostfile>\" is deprecated - please specify hosts with -f or -H"
	[[ "$HostFile"  != "" && "$Hosts" != "" ]]          && errexit 2 "-f and -H are mutually exclusive"
	[[ "$EgrHosts" != "" && "$Hosts" != "" ]]          && errexit 2 "-e cannot be used with -H"
	[[ "$SourceDir" != "" ]] && ! test -d "$SourceDir" && errexit 1 "dir \"$SourceDir\" does not exist or is not a directory"
	[[ "$CopyPort"  != "" ]] && ! IsNum $CopyPort      && errexit 1 "port \"$CopyPort\" must be numeric"

	FileCount=$#
	ChangeDir $SourceDir
	typeset NotExist
	typeset File
	for File in "$@"
	do
		test -r "$File" && Files="$Files${Files:+ }$File" || NotExist="$NotExist${NotExist:+ }$File"
	done
	ChangeDir $CurrentDir

	[[ "$NotExist" != "" ]] && errexit 1 "the following file(s) do not exist or are not readable${SourceDir:+ from directory }$SourceDir: $NotExist"
	[[ "$Files"    == "" ]] && errexit 1 "no readable files were found on the command line"

	if [[ "$HostFile" != "" ]]
	then
		! test -r "$HostFile" && errexit 1 "hosts file \"$HostFile\" does not exist or is not readable"
		Hosts=$(egrep "^[a-zA-Z_]" $HostFile |awk '{print $1}' |egrep -i$EgrOpt -- "$EgrHosts")
	fi
	HostCount=$(echo $Hosts |wc -w |awk '{print $1}')
	(($HostCount == 0)) && errexit 1 "0 valid hosts identified - please check options, hostnames or hostfile"
}


#########
errexit()
{
	RetCode=$1; shift
	echo "$Myname: ERROR: $@" >&2
	cleanexit $RetCode
}


###############
IsNum() { echo "$1" |egrep -q "^[0-9][0-9]*$"; }

###########
###########
ChangeDir()
{
	typeset Dir="$1"
	if [[ "$Dir" != "" ]]
	then
		CurrentDir=$(pwd)
#		echo "Local directory is now: $Dir"
		cd $Dir
	fi
}


######
Rcp()
{
	typeset FileCount="$1"
	typeset Files="$2"
	typeset HostCount="$3"
	typeset Hosts="$4"
	typeset Host
	ChangeDir $SourceDir
	printf "Copying $FileCount file(s) to $HostCount host(s) using \"$CopyCmd\""
	for Host in $Hosts
	do
		$CopyCmd -p $Files $RemoteUser${RemoteUser:+@}$Host:$DestDir && printf "." &
	done
	wait
	echo
	ChangeDir $CurrentDir
}

######
Scp()
{
	typeset FileCount="$1"
	typeset Files="$2"
	typeset HostCount="$3"
	typeset Hosts="$4"
	typeset Host
	ChangeDir $SourceDir
	printf "Copying $FileCount file(s) to $HostCount host(s) using \"$CopyCmd\""
	for Host in $Hosts
	do
		$CopyCmd -p $Files $RemoteUser${RemoteUser:+@}$Host:$DestDir && printf "." &
	done
	wait
	echo
	ChangeDir $CurrentDir
}

######
Sftp()
{
	typeset FileCount="$1"
	typeset Files="$2"
	typeset File
	typeset HostCount="$3"
	typeset Hosts="$4"
	typeset Host
	typeset LocalCd="${SourceDir:+lcd }$SourceDir\n"
	typeset RemoteCd="cd $DestDir\n"

	typeset SftpCmd="$LocalCd$RemoteCd"
	for File in $Files
	do
		SftpCmd="${SftpCmd}put $File\n"
	done

	printf "Copying $FileCount file(s) to $HostCount host(s) using \"$CopyCmd\""
	for Host in $Hosts
	do
#		printf "$SftpCmd" |$CopyCmd${CopyPort:+ -P}$CopyPort $RemoteUser${RemoteUser:+@}$Host > $Tempfile.log.$Host.out 2> $Tempfile.log.$Host.err && printf "." &
		printf "$SftpCmd" |$CopyCmd${CopyPort:+ -oPort=}$CopyPort $RemoteUser${RemoteUser:+@}$Host > $Tempfile.log.$Host.out 2> $Tempfile.log.$Host.err && printf "." &
	done
	wait
	echo
	egrep -i error $Tempfile.log*
	rm -f $Tempfile.log*
}


########
SshTar()
{
	typeset FileCount="$1"
	typeset Files="$2"
	typeset HostCount="$3"
	typeset Hosts="$4"
	typeset Host
	typeset LocalCmd="cd ${SourceDir:-.}; tar chf - $Files"
	typeset RemoteCmd="cd $DestDir; tar xvf -"

	printf "Copying $FileCount file(s) to $HostCount host(s) using \"$CopyCmd\""
	for Host in $Hosts
	do
		sh -c "$LocalCmd" |ssh ${CopyPort:+ -p}$CopyPort $RemoteUser${RemoteUser:+@}$Host "$RemoteCmd" > $Tempfile.log.$Host.out 2> $Tempfile.log.$Host.err && printf "." &
	done
	wait
	echo
	egrep -i error $Tempfile.log*
	rm -f $Tempfile.log*
}


#######
Main()
{
	case "$CopyCmd" in
	scp|/scp)
		Scp    "$FileCount" "$Files" "$HostCount" "$Hosts"
		;;
	rcp|/rcp)
		Rcp    "$FileCount" "$Files" "$HostCount" "$Hosts"
		;;
	sftp|/sftp)
		Sftp   "$FileCount" "$Files" "$HostCount" "$Hosts"
		;;
	sshtar)
		SshTar "$FileCount" "$Files" "$HostCount" "$Hosts"
		;;
	*)
		errexit 2 "unknown copy command \"$CopyCmd\""
		;;
	esac
}


########
GetOptions "$@"
Main
cleanexit 0

