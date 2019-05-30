
"""
 Copyright (c) 2005-2019 Colin Pearse.
 All scripts are free in the binscripts repository but please refer to the
 LICENSE file at the top-level directory for the conditions of distribution.

 Name:        primes.py
 Description: get primes using gmpy2 module
"""

import os
import sys
import click
import itertools
import random
import gmpy2
import numpy as np


@click.command()
@click.option('-v',   '--verbose',     is_flag=True,  help='Display with more information',)
@click.option('-rsd', '--randskipdig', default=0,     show_default=True, help='use this to force non-sequencial primes',)
@click.option('-bs',  '--base',        default=10,    show_default=True, help='base for calculating digits',)
@click.argument('nprimes', nargs=1, type=int)
@click.argument('digits', nargs=1, type=int)
def main(verbose, randskipdig, base, nprimes, digits):
    """
    \b
    Display NPRIMES prime numbers, the length of which should be at least DIGITS digits long.
    \b
    eg1.  primes.py -v -rsd=99 10 100   # 10 primes 100 digits long (non-sequential), nice output
    eg2.  primes.py 1000000 1           # 1 million primes (20 secs), in a list

    """
    #primes = get_primes_erat(10**digits,nprimes)
    #primes = getPrimes(10**digits,nprimes)
    #primes = getnPrimes(10**digits, nprimes, randomskip=arg3)
    #primes = getfPrimes(10**digits, nprimes, randomskip=arg3)
    primes = get_n_primes_d_digits(nprimes, digits, randskipdig=randskipdig, base=base)
    if verbose is True:
        show_int_ilens(primes, label="next_prime")
    else:
        print (primes)




# Easily the best method - GMP (GNU Multiple Precision) C coded library
# n - how many primes
# d - quantity of digits of primes (until you run out, then it continues with d+1 digit primes)
# randskipdig - ensures non-sequential primes
# NOTE: if randskipdig >= d then d will be pushed up too (ie. primes with digits > d)
def get_n_primes_d_digits(n, d, randskipdig=0, base=10):
    randskip = 0
    prime = base**(d-1)  # starts out life as a minimum
    primes = []
    for i in range(n):
        if randskipdig > 0:
            randskip = random.randint(base**(randskipdig-1), base**randskipdig)
        prime = int(gmpy2.next_prime(prime+randskip))   # next_prime returns type class mpz
        primes.append(prime)
    return primes

def ilen(n):
    return gmpy2.mpz(n).num_digits()
    #return len(str(abs(n)))

def show_int_ilens(numarr, label="number"):
    for num in numarr:
        print ("{:s}:{:d} len:{:d} type:{:s}".format(label, num, ilen(num), str(type(num))))


#############################
# ADHOC test using gmpy2.is_prime(possprime) and gmpy2.mpz(<str>)  (mpz are functions for signed integers)
#############################
# adhoc functions to get primes by using existing primes (2 * p1 * p2 ... pn) + 1
# NOTE: in tests I had to cycle between 100-400 possprimes for every 10 primes
def adhoc_get_possible_prime(primesarr, n):
    primes = np.random.choice(primesarr, n)
    primes = np.insert(primes, 0, 2)
    pprod = str(primes.prod())
    pmaybe = gmpy2.mpz(pprod) + 1
    return pmaybe
def adhoc_get_n_primes(n, primesarr, paqty):
    primes = []
    while n > 0:
        possprime = adhoc_get_possible_prime(primesarr, paqty)
        if gmpy2.is_prime(possprime) is True:
            primes.append(possprime)
            n = n - 1
    return primes
#primes_low  = np.array([3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97, 101, 103, 107, 109, 113, 127, 131, 137, 139, 149, 151, 157, 163, 167, 173], dtype=np.ulonglong)
#primes_9dig = np.array([982450801, 982450829, 982450849, 982450871, 982450913, 982450921, 982450943, 982450967, 982450981, 982450999, 982451023, 982451081, 982451087, 982451111, 982451123, 982451159, 982451161, 982451179, 982451191, 982451219, 982451227, 982451231, 982451243, 982451321, 982451333, 982451359, 982451383, 982451419, 982451429, 982451443, 982451467, 982451479, 982451497, 982451501, 982451549, 982451567, 982451579, 982451581, 982451609, 982451629], dtype=np.ulonglong)
#primes = adhoc_get_n_primes(10, primes_9dig, 10)
#show_int_ilens(primes, label="is_prime")
#############################


def erat2():
    D = {  }
    yield 2
    for q in itertools.islice(itertools.count(3), 0, None, 2):
        p = D.pop(q, None)
        if p is None:
            D[q*q] = q
            yield q
        else:
            x = p + q
            while x in D or not (x&1):
                x += p
            D[x] = p

def get_primes_erat(n):
  return list(itertools.takewhile(lambda p: p<n, erat2()))

# NOTE: for/else used here - when it doesn't break there is no factor - so prime
def getPrimes(startnum, maxnum):
    primes = []
    for num in range(startnum, maxnum+1):
        for i in range(2,num):
            if (num % i) == 0:
                break
        else:
            primes.append(num)
    return primes

def getnPrimes(startnum, nprimes, randomskip=1):
    primes = []
    num = startnum
    while nprimes > 0:
        for i in range(2,num):
           if (num % i) == 0:
                break
        else:
            primes.append(num)
            nprimes = nprimes - 1
        num = num + 1 + int(randomskip * random.random())
    return primes

def getfPrimes(start, n, randomskip=1):
    home = os.getenv('HOME')
    primes = []
    line = 0
    nextline = 0
    with open(home+"/bin/primes.txt") as fd:
        for prime in fd:
            line = line + 1
            if line >= start:
                if line >= nextline or nextline is 0:
                    if n > 0:
                        primes.append(int(prime))
                        n = n - 1
                        nextline = line + int(randomskip * random.random())
                    else:
                        return(primes)





if __name__ == '__main__':
    __myhome__ = os.getenv('HOME')
    __myname__ = os.path.splitext(os.path.basename(sys.argv[0]))[0]
    try:
        main()
    except KeyboardInterrupt:
        print('Aborted!')
    sys.exit(0)

