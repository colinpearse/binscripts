
"""
 Author:      Colin Pearse
 Name:        readutmp.py
 Description: read utmp, utmpx, wtmp and wtmpx files
"""

import signal
import sys
import re
import struct
import os.path
import subprocess

myname = os.path.basename(sys.argv[0])


############
def handleInterrupt(SigNum, Frame):
    sys.stdout.flush()
    sys.stderr.write('Interrupt signal (%d) caught\n' % (SigNum))
    sys.exit(99)


############
def usage():
    sys.stderr.write('\n')
    sys.stderr.write(' usage: %s <utmp/utmpx/wtmp/wtmpx file>\n' % myname)
    sys.stderr.write('\n')
    sys.stderr.write(' NOTE: if .gz found then gunzip -c will be used\n')
    sys.stderr.write('\n')
    sys.exit(2)


############
def error(ExitValue, Msg):
    sys.stderr.write('ERROR: %s\n' % Msg)
    sys.exit(ExitValue)

############
def warning(Msg):
    sys.stderr.write("WARNING: %s\n" % Msg)


#####################
def getOptions(argv):
    if len(argv) < 2:
        usage()
    fname = argv[1]
    if not os.path.exists(fname):
        error(1, 'file "%s" does not exist' % (fname))
    return fname


######################
# -------
# Solaris (/usr/include/utmpx.h)
# -------
# xtmpStruct = '32s4s32sihhhiii5ih257sx'
# xtmpStructSize should be 372
# NOTE: exit_status as per utmp.h
# Key:
# h = short
# i = int
# 32s = char[32]
# 20x = char[20] = padded
#
#struct utmpx {
#        char    ut_user[32];            /* user login name */
#        char    ut_id[4];               /* inittab id */
#        char    ut_line[32];            /* device name (console, lnxx) */
#        pid_t   ut_pid;                 /* process id */
#        short   ut_type;                /* type of entry */
##if !defined(_XPG4_2) || defined(__EXTENSIONS__)
#        struct exit_status ut_exit;     /* process termination/exit status */
##else
#        struct ut_exit_status ut_exit;  /* process termination/exit status */
##endif
#        struct timeval ut_tv;           /* time entry was made */
#        int     ut_session;             /* session ID, used for windowing */
##if !defined(_XPG4_2) || defined(__EXTENSIONS__)
#        int     pad[5];                 /* reserved for future use */
##else
#        int     __pad[5];               /* reserved for future use */
##endif
#        short   ut_syslen;              /* significant length of ut_host */
#                                        /*   including terminating null */
#        char    ut_host[257];           /* remote host name */
#};

# ------------------
# OSs except Solaris (/usr/include/utmpx.h)
# ------------------
#xtmpStruct = 'hi32s4s32s256shhiii4i20x'
# xtmpStructSize should be 384
# Key:
# h = short
# i = int
# 32s = char[32]
# 20x = char[20] = padded
#
# #define UT_LINESIZE      32
# #define UT_NAMESIZE      32
# #define UT_HOSTSIZE     256
#
# struct exit_status {              /* Type for ut_exit, below */
#    short int e_termination;      /* Process termination status */
#    short int e_exit;             /* Process exit status */
# };
#
# struct utmp {
#    short   ut_type;              /* Type of record */
#    pid_t   ut_pid;               /* PID of login process */
#    char    ut_line[UT_LINESIZE]; /* Device name of tty - "/dev/" */
#    char    ut_id[4];             /* Terminal name suffix,
#                                     or inittab(5) ID */
#    char    ut_user[UT_NAMESIZE]; /* Username */
#    char    ut_host[UT_HOSTSIZE]; /* Hostname for remote login, or
#                                     kernel version for run-level
#                                     messages */
#    struct  exit_status ut_exit;  /* Exit status of a process
#                                     marked as DEAD_PROCESS; not
#                                     used by Linux init(8) */
#    /* The ut_session and ut_tv fields must be the same size when
#       compiled 32- and 64-bit.  This allows data files and shared
#       memory to be shared between 32- and 64-bit applications. */
# #if __WORDSIZE == 64 && defined __WORDSIZE_COMPAT32
#    int32_t ut_session;           /* Session ID (getsid(2)),
#                                     used for windowing */
#    struct {
#        int32_t tv_sec;           /* Seconds */
#        int32_t tv_usec;          /* Microseconds */
#    } ut_tv;                      /* Time entry was made */
# #else
#     long   ut_session;           /* Session ID */
#     struct timeval ut_tv;        /* Time entry was made */
# #endif
#
#    int32_t ut_addr_v6[4];        /* Internet address of remote
#                                     host; IPv4 address uses
#                                     just ut_addr_v6[0] */
#    char __unused[20];            /* Reserved for future use */
# };
def read_xtmp(fname,xtmpStruct,xtmpStructSize):
    result = []

    cmd = "gunzip -c %s" % (fname)
    if re.match(r'.*gz$', fname):
        fp = os.popen(cmd,'rb')
    else:
        fp = open(fname, 'rb')

    while True:
        bytes = fp.read(xtmpStructSize)
        if not bytes:
            break

        if (len(bytes) == xtmpStructSize):
            data = struct.unpack(xtmpStruct, bytes)
            data = [(lambda s: str(s).split("\0", 1)[0])(i) for i in data]
            if data[0] != '0':
                result.append(data)
        else:
            warning('block read (%d bytes) was not the right size (%d bytes)' % (len(bytes), xtmpStructSize))

    fp.close()
    result.reverse()

    return result



################
def main(fname):
    signal.signal(signal.SIGINT, handleInterrupt)
    if re.match(r'.*[uw]tmpx.*', fname):
	    print ('Found utmpx/wtmpx in filename so assuming utmpx/wtmpx structure')
	    xtmpStruct = '32s4s32sihhhiii5ih257sx'
	    xtmpStructSize = struct.calcsize(xtmpStruct)
    else:
	    print ('Assuming utmp/wtmp structure')
	    xtmpStruct = 'hi32s4s32s256shhiii4i20x'
	    xtmpStructSize = struct.calcsize(xtmpStruct)

    data = read_xtmp(fname, xtmpStruct, xtmpStructSize)
    for block in data:
        print (block)


#########################
if __name__ == "__main__":
    fname = getOptions(sys.argv)
    main(fname)

sys.exit(0)

