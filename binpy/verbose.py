
"""
 Copyright (c) 2005-2019 Colin Pearse.
 All scripts are free in the binscripts repository but please refer to the
 LICENSE file at the top-level directory for the conditions of distribution.

 Name:        verbose.py
 Description: Implement verbosity. Full description and test at the bottom.
"""

from __future__ import print_function 
import sys
import os
import time
import datetime

__author__  = "Colin Pearse <colin@thepearses.com>"
__status__  = "beta"
__version__ = "0.0.1"
__date__    = "20 February 2018"

vlevels = [1]
vpathname = None
vfh = sys.stderr


def splitLevelsList(levels):
    strlevels = [l for l in levels if type(l) is str]
    numlevels = [l for l in levels if type(l) is int]
    if numlevels == []:
        numlevel = None
    else:
        numlevel = max(numlevels)
    return numlevel,strlevels

def splitLevelsStr(levels,separator=','):
    strlevels = levels.split(separator)
    numlevels = [n for n in strlevels if n.isdigit() is True]
    strlevels = [n for n in strlevels if n.isdigit() is False]
    if numlevels == []:
        numlevel = None
    else:
        numlevels = map(int,numlevels)
        numlevel = max(numlevels)
    return numlevel,strlevels

def splitLevelsInt(level):
    return level,[]

# levels can be a list [2,"blah","pod"] or str "2,blah,pod" or int 2
def splitLevels(levels,separator=','):
    ''' split verbosity levels into int and strs

    >>> splitLevels([1,"blah","pod"])
    (1, ['blah', 'pod'])

    >>> splitLevels("1,blah,pod")
    (1, ['blah', 'pod'])

    >>> splitLevels("1:blah:pod",separator=':')
    (1, ['blah', 'pod'])

    >>> splitLevels(99)
    (99, [])

    >>> splitLevels("blah,pod,6,9,pie")
    (9, ['blah', 'pod', 'pie'])

    >>> splitLevels("info")
    (None, ['info'])
    '''
    if type(levels) is list:
        return splitLevelsList(levels)
    elif type(levels) is str:
        return splitLevelsStr(levels,separator)
    elif type(levels) is int:
        return splitLevelsInt(levels)
    else:
        return 1,[]

# levels can be a list or str - see splitLevels
def setLevels(levels,separator=','):
    global vlevels
    ivlevels,svlevels = splitLevels(levels)
    vlevels = [ivlevels] + svlevels

# if I've already opened a file, close it before setting a new fh
def setStream(fh):
    global vpathname
    global vfh
    if vpathname is not None:
        closeFile()
    vfh = fh

# if I've already opened a file, close it before opening the new one
def openFile(filename,mode="a"):
    global vpathname
    global vfh
    if vpathname is not None:
        closeFile()
    vpathname = os.path.abspath(filename)
    vfh = open(vpathname,mode)

# don't close if vpathname is None, implying vfh was not opened by me
def closeFile():
    global vpathname
    global vfh
    if vpathname is not None:
        try:
            vfh.close()
            vpathname = None
        except:
            sys.exit("cannot close %s" % (vpathname))

def showLabel(labels,dt,mod,func):
    label = ""
    if "dt" in labels:
        label = label + "%s: "%(dt)
    if "mod" in labels:
        label = label + "%s: "%(mod)
    if "func" in labels:
        label = label + "%s: "%(func)
    return label

def isLevel(levels):
    ilevel,slevels = splitLevels(levels)
    ivlevel,svlevels = splitLevels(vlevels)
    if (ivlevel is not None and ilevel is not None and ivlevel >= ilevel) or set(slevels) & set(svlevels):
        return True
    else:
        return False

# NOTE: don't think this label is very useful, but just in case...
#       ilevel,slevels = splitLevels(levels)
#       showlevels = "%s" % (','.join([str(ilevel)] + slevels))
def verbose(levels,message,tee=None,labels=["dt","mod","func"],teelabels=["dt","mod","func"]):
    ts = time.time()
    dt = datetime.datetime.fromtimestamp(ts).strftime('%Y-%m-%d %H:%M:%S')
    mod = os.path.basename(sys._getframe(1).f_code.co_filename)
    func = sys._getframe(1).f_code.co_name
    if isLevel(levels):
        print ("%s%s" % (showLabel(labels,dt,mod,func),message), file=vfh)
        if tee is not None:
            print ("%s%s" % (showLabel(teelabels,dt,mod,func),message), file=tee)


"""
Description:
Allows granular verbose messaging. verbose.verbose() commands can be used everywhere
in the code, but only activated with a specific level or multiple strings.
For example: myprog.py -v 5,read,boot ...  would display all messages level 5 and under
plus those labelled "read" and "boot" which might be a very specified area of the code
you wish to debug.

Code:
import verbose
verbose.setLevels(vlist)                            # vlist can be a str: "2,readcmds,blah" or list [2,"readcmds","blah"]
verbose.openFile("log/verbose_test.log","w")        # output to a file (open with truncate); default: sys.stderr output
verbose.verbose([2,"loop"],"message")               # output if verbose level >= 2 or one verbose string is "loop"
verbose.verbose(["info"],"message")                 # output if one verbose string is "info"
verbose.verbose(["info"],"message",tee=sys.stderr)  # as above, but write to stderr too
verbose.verbose([99],"message")                     # output if verbose level >= 99
verbose.verbose("99","message")                     # output if verbose level >= 99
verbose.verbose(99,"message")                       # output if verbose level >= 99
verbose.isLevel("99,blah")                          # True if verbose level >= 99 or verbose str is "blah"
verbose.setStream(sys.stderr)                       # will call closeFile() if necessary before redirecting
verbose.closeFile()

Testing (doctest):
python -m doctest verbose.py -v

Testing (manual):
python bin/verbose.py 1               # 2 tests below should be displayed
python bin/verbose.py 2               # 3 tests below should be displayed
python bin/verbose.py 3               # 4 tests below should be displayed
python bin/verbose.py 3 show          # 5 tests below should be displayed
python bin/verbose.py nothing         # no tests below should be displayed

Eg output for "3 show":
2018-02-28 19:33:06: myTestFunc: True for test: [1, 'show']
2018-02-28 19:33:06: myTestFunc: True for test: [2, 'func']
2018-02-28 19:33:06: myTestFunc: True for test: [3, 'func']
2018-02-28 19:33:06: myTestFunc: True for test: [1]
2018-02-28 19:33:06: myTestFunc: True for test: ['show']

"""

if __name__ == "__main__":
    def myTestFunc():
        tests = [[1,"show"],
                 [2,"func"],
                 [3,"func"],
                 1,
                 "show"]
        for test in tests:
            print ("test:",test)
        for test in tests:
            verbose(test,"%s for test: %s" % (isLevel(test),test))
            #verbose(test,"%s for test: %s" % (isLevel(test),test), tee=sys.stderr)

    if len(sys.argv) >= 2:
        setLevels(sys.argv[1])
    #openFile("log/verbose_test.log","w")
    #setStream(sys.stdout)
    #setStream(sys.stderr)
    print ("vlevels:",vlevels)
    print ("vpathname:",vpathname)
    myTestFunc()
    #closeFile()

