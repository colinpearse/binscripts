
"""
 Copyright (c) 2005-2019 Colin Pearse.
 All scripts are free in the binscripts repository but please refer to the
 LICENSE file at the top-level directory for the conditions of distribution.

 File:        autologin.py
 Description: automatic login using password and then run a command
"""


from optparse import OptionParser
from os.path import basename
import sys
import pexpect
import getpass, os
import time
import re

myname = basename(sys.argv[0])


# NOTE: override OptionParser.format_epilog() to not strip out newlines so we can display examples
def get_options ():
    class MyOptionParser(OptionParser):
        def format_epilog(self, formatter):
            return self.epilog
    parser = MyOptionParser(usage="usage: %prog [options] filename", version="%prog 0.1",
        description=
"""Execute a command, then a password and lastly a command after the
   previous command was successful. A typical example is testing a
   login with password and then a follow-up command to proove a successful login
""",
        epilog=
"""Examples:
  %s -c "ssh -t -oBatchMode=no -oPreferredAuthentications=password -oStrictHostKeyChecking=no myuser@myhost.example.com" -w mypass12 -x id
  %s -c "su - myuser" -w mypass12 -x id
  %s -c "unset LD_LIBRARY_PATH; kinit pu1@MYDOM.COM" -w poctest123 -x klist -o ""    # LD_LIBRARY_PATH can give "kinit: relocation error"
"""%(myname,myname,myname))
    parser.add_option("-c", "--pw-command",     dest="pw_command",     metavar="CMD",   type="string", help="(mandatory) execute command that requires a password")
    parser.add_option("-o", "--logout-command", dest="logout_command", metavar="CMD",   type="string", help="logout command for the --pw-command (default: exit)", default="exit")
    parser.add_option("-w", "--password",       dest="password",       metavar="PW",    type="string", help="(mandatory) password")
    parser.add_option("-x", "--fup-command",    dest="fup_command",    metavar="CMD",   type="string", help="(mandatory) execute follow-up command to prove the previous command was successful")
    parser.add_option("-s", "--shell",          dest="shell",          metavar="CMD",   type="string", help="shell to run commands (default: /usr/bin/ksh)", default="/usr/bin/ksh")
    parser.add_option("-v", "--verbosity",      dest="verbosity",      metavar="LEVEL", type="int",    help="verbosity level")
    (options, args) = parser.parse_args()
    if len(args) > 0:
        parser.error("only options should be specified, no arguments")
    if options.pw_command == None or options.password == None or options.fup_command == None:
        parser.print_help()
        sys.exit(2)
    return options, args


def runexp (child, timeout, sendstr, recstr, verbosity=1):
    if verbosity > 1: print('')
    if verbosity > 1: print('sendline: %s' % (sendstr))
    child.sendline(sendstr)
    if verbosity > 1: print('expect: %s' % (recstr))
    i = child.expect ([recstr, pexpect.EOF, pexpect.TIMEOUT], timeout)
    if i == 0:
        if verbosity > 1: print('buffer(before)="%s"'%(child.before))
        if verbosity > 1: print('buffer(after)="%s"'%(child.after))
        return child.after
    elif i == 1:
        print('child exited (%s)' % (child.after), file=sys.stderr)
        sys.exit(1)
    elif i == 2:
        print('timeout: we did not get expected response "%s" (%s)' % (recstr, child.after), file=sys.stderr)
        sys.exit(1)


def login (shell, pw_command, password, fup_command, logout_command, verbosity=1):
    os.environ["HISTFILE"] = ".sh_history.%s" % (myname)
    if verbosity > 1: print('spawn: %s' % (shell))
    child = pexpect.spawn(shell)

    PrecomPrompt = '__PocTestPrompt:precommand__'
    PostcomPrompt = '__PocTestPrompt:postcommand__'
    PrecomPromptExpr  = '.*[^=]%s.*' % (PrecomPrompt)
    PostcomPromptExpr = '.*[^=]%s.*' % (PostcomPrompt)
    PrecomPromptCmd  = 'PS1=%s' % (PrecomPrompt)
    PostcomPromptCmd = 'PS1=%s' % (PostcomPrompt)

    ignore = runexp (child, 3, PrecomPromptCmd,  PrecomPromptExpr,  verbosity)
    ignore = runexp (child, 3, "id",             PrecomPromptExpr,  verbosity)
    ignore = runexp (child, 3, pw_command,       ".*[^=][Pp]assword.*", verbosity)
    ignore = runexp (child, 5, password,         "..*",             verbosity)
    ignore = runexp (child, 3, PostcomPromptCmd, PostcomPromptExpr, verbosity)
    fu_out = runexp (child, 3, fup_command,      PostcomPromptExpr, verbosity)
    if logout_command != "" and logout_command != "_NONE_":
        ignore = runexp (child, 3, logout_command, PrecomPromptExpr, verbosity)
    ignore = runexp (child, 3, "exit",           "..*",             verbosity)
    # NOTE: tried this expression to exclude the first and last lines, but felt split worked better
    # NOTE: modes: re.M=multiline (match ^..$ multiple times) re.S=DOTALL (. matches \n too)
    #       out = re.match(r'^.*%s(.*)%s.*$'%(fup_command,PostcomPromptExpr), fu_out, re.S)
    #       if out != None: print(out.group(1))
    # Exclude 1st and last lines (fup_command and PostcomPromptExpr respectively)
    fu_lines = re.split('\r\n', fu_out)
    for line in fu_lines[1:len(fu_lines)-1]:
        print(line)


def main ():
    (options, args) = get_options()
    login (options.shell, options.pw_command, options.password, options.fup_command, options.logout_command, options.verbosity)


if __name__ == '__main__':
    try:
        main()
    except Exception:
        traceback.print_exc()
        os._exit(1)

