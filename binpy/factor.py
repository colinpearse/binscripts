#!/usr/bin/python

"""
 Author:       Colin Pearse
 Name:         factor.py
 Description:  Factor a number using different methods
"""

import sys
import math
import subprocess
from functools import reduce


# The problem with relying on any floating point computation (math.sqrt(x), or x**0.5)
# is that you can't really be sure it's exact (for sufficiently large integers x, it
# won't be, and might even overflow).
# This is based on the "Babylonian algorithm" for square root, see wikipedia. It does
# work for any positive number for which you have enough memory as is reasonably fast
def HasSquare(apositiveint):
    x = apositiveint // 2
    seen = set([x])
    while x * x != apositiveint:
        x = (x + (apositiveint // x)) // 2
        if x in seen: return False
        seen.add(x)
    return True


# Fermat's factorisation which works with semi-primes that are close together.
# A semi-prime (N) is a number with only two prime factors, and for large numbers
# it's always odd.
def FermatFactor(N):
    a = math.ceil(math.sqrt(N))
    b2 = a*a - N
    while not HasSquare(b2):
        a += 1       # equivalently: b2 = b2 + 2*a + 1
        b2 = a*a - N
    return int(a - math.sqrt(b2)) # or a + sqrt(b2)


def doFermatMethod(num,sqroot):
    print ("fermat's factorisation (for semi-primes)")
    print ("----------------------------------------")
    p = FermatFactor(num)
    q = num / p
    numlen = len(str(num))
    print ("FP:  %*d" % (numlen, p))
    print ("FQ:  %*d" % (numlen, q))

def doBruteForceMethod1(num,sqroot):
    print ("brute force factorisation method 1 (for numbers with multiple factors)")
    print ("----------------------------------------------------------------------")
    try:
        factors = set(reduce(list.__add__,([i, num//i] for i in range(2, sqroot+1) if num % i == 0)))
        print ("Found %d factor(s) of %d (excluding 1 and %d): %s" % (len(factors), num, num, sorted(factors)))
    except:
        print ("Found 0 factor(s) of %d (excluding 1 and %d): %s" % (num, num, []))

def doBruteForceMethod2(num,sqroot,debug=0):
    print ("brute force factorisation method 2 (for numbers with multiple factors)")
    print ("----------------------------------------------------------------------")
    factors = []
    sqroot += 2
    numlen = len(str(num))
    print ("NUM: %*d" % (numlen, num))
    for p in range(2,sqroot+1):
        if num % p == 0:
            q = num / p
            print ("P:   %*d" % (numlen, p))
            print ("Q:   %*d" % (numlen, q))
            factors.append(p)
            factors.append(q)

        if debug > 0 and (p % (sqroot/debug)) == 0:
            print ("fraction done: %d of %d" % (p,sqroot))
    factors = set(factors)
    factorslen = len(factors)
    factorsordered = list(map(int, sorted(factors)))
    print ("Found %d factor(s) of %d (excluding 1 and %d): %s" % (factorslen, num, num, factorsordered))
    if factorslen >= 3:
        flen = int(factorslen/2)
        print ("Factors (len/2)-1,len/2,(len/2)+1 after sorting: %d,%d,%d" % (factorsordered[flen-1], factorsordered[flen],factorsordered[flen+1]))
            

if len(sys.argv) == 2:
    num = int(sys.argv[1])
elif len(sys.argv) == 3:
    p = int(sys.argv[1])
    q = int(sys.argv[2])
    num = int(p*q)
else:
    print ("")
    print (" usage: factor p")
    print (" usage: factor p q [debug]")
    print ("")
    print (" Either factor p or create semiprime with p and q and try factoring algorithms")
    print ("")
    sys.exit(2)


sqroot = int(math.sqrt(num))  # OR: sqroot = pow(num, 0.5)
debug = 0
if len(sys.argv) == 4:
    debug = int(sys.argv[3])
numlen = len(str(num))
print ("")
print ("number and square")
print ("-----------------")
print ("NUM: %*d" % (numlen, num))
print ("SQR: %*d" % (numlen, sqroot))
print ("")
#doFermatMethod(num,sqroot)
if debug > 0:
    print ("")
    print ("skipping brute force method 1 (which is the same as method 2 on a single line) for debug mode")
else:
    print ("")
    doBruteForceMethod1(num,sqroot)
print ("")
#doBruteForceMethod2(num,sqroot,debug=debug)
doFermatMethod(num,sqroot)


