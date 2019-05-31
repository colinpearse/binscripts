
"""
 Author:      Colin Pearse
 Name:        mkarrays.py
 Description: Make different types of numpy array in decimal, convert to binary and back again
"""

from numpy import arange, around, round, newaxis, squeeze, array, append, exp, binary_repr, vstack, hstack, amin, amax, set_printoptions, random, zeros_like
import os
import sys
import primes


def blen(num):
    return len(bin(abs(int(num)))[2:])

# Convert int to binary, eg. int2bin(5, 4)  returns [0 1 0 1]
def int2bin(i, digits):
    return array(list(binary_repr(i, digits)), dtype=int)

def bin2int(binarray):
    return int("".join(str(bindigit) for bindigit in binarray), 2)

# returns maximum binary digits needed for any number in array
def maxbinarydigits(sums):
    return len("{0:b}".format(int(amax(sums))))



"""
 get number functions
"""

# eg1. getnNumbers(1, 10, randomskip=1)    will produce [1 .. 10]
# eg2. getnNumbers(1, 10, randomskip=10)   will produce [1 .. <plus 9 random numbers>]
def getnNumbers(start, n, randomskip=1):
    nums = [start]
    while n > 1:
        start = start + 1 + int(randomskip * random.random())
        nums.append(start) 
        n = n - 1
    return nums


"""
 Initialise array with values
 """

# Make array like numpy.random.random((3,2)) but following rules of valuefunc(col,cols).
def mkarray_valuefunc(col,cols):
    return [0.4, 0.5, -0.4, -0.5][col%4]
def mkarray(rows, cols, valuefunc=mkarray_valuefunc):
    return array([[valuefunc(col,cols) for col in range(cols)] for row in range(rows)])


""" Subtraction """
# Make n x 3 array of sums (num1, num1, answer) in decimal
def mkuniquesubtractionarray(start1, start2, n, randomskip1=1, randomskip2=1):
    num1s = array((getnNumbers(start1, n, randomskip=randomskip1)))
    num2s = array((getnNumbers(start2, n, randomskip=randomskip2)))
    return vstack((num1s, num2s, (num1s - num2s))).T

""" Multiplication """
# Make n x 3 array of sums (num1, num1, answer) in decimal
def mkuniquemultiplicationarray(start1, start2, n, randomskip1=1, randomskip2=1):
    num1s = array((getnNumbers(start1, n, randomskip=randomskip1)))
    num2s = array((getnNumbers(start2, n, randomskip=randomskip2)))
    return vstack((num1s, num2s, (num1s * num2s))).T

""" Division """
# Make n x 3 array of sums (num1, num1, answer) in decimal
def mkuniquedivisionarray(start1, start2, n, randomskip1=1, randomskip2=1):
    num1s = array((getnNumbers(start1, n, randomskip=randomskip1)))
    num2s = array((getnNumbers(start2, n, randomskip=randomskip2)))
    return vstack((num1s, num2s, (num1s // num2s))).T


"""
 Addition list functions: num1 + num2 = answer
"""

# Make array of sums in decimal
# eg. mkaddarray(0,100) will make 10,000 sums [[0,0,0]...[99,99,198]]
# eg. mkaddarray(1,100) will make 10,000 sums [[1,1,2]...[100,100,200]]
def mkaddarray(start, size, randomskip=1):
    return array([[x,y,x+y] for x in range(start,size+start) for y in range(start,size+start)])

# Make n x 3 array of sums (num1, num1, answer) in decimal
def mkuniqueaddarray(start1, start2, n, randomskip1=1, randomskip2=1):
    num1s = array((getnNumbers(start1, n, randomskip=randomskip1)))
    num2s = array((getnNumbers(start2, n, randomskip=randomskip2)))
    return vstack((num1s, num2s, (num1s + num2s))).T

# returns <minimum bytes required to hold sum> <min digits required to hold answer>
def sumsbinarydigits(sums):
    num1, num2, answer = amax(sums, axis=0)
    return 2*len("{0:b}".format(max(num1, num2))), len("{0:b}".format(answer))

# Convert list of sums (each sum 3 numbers) to binary inputs (num1+num2) and outputs (answer)
# eg. sums([[4 5 9]], 10, 8)  makes input:     [0 0 1 0 0 0 0 1 0 1] (half num1/half num2) and output [0 0 0 0 1 0 0 1]
# eg. sums(..., multiplier=2) makes input x 2: [0 0 1 0 0 0 0 1 0 1 0 0 1 0 0 0 0 1 0 1] (half1/half2/half1/half2) and output [0 0 0 0 1 0 0 0]
def sums2binary(sums, digin, digout, multiplier=1):
    half = int(digin/2)
    # NOTE: without int(num1) I got error: numpy.float64 object cannot be interpreted as an integer
    inputs  = (array([list(binary_repr((int(num1)<<half)|int(num2), digin)) for num1,num2,answer in sums], dtype=int))
    outputs = (array([list(binary_repr(answer, digout))                     for num1,num2,answer in sums], dtype=int))
    originalinputs = inputs       # NOTE: don't need deepcopy here
    for i in range(1, multiplier):
        inputs = hstack((inputs, originalinputs))
    return inputs, outputs

# Check all sums are correct
def checksums(sums, sumtype="add"):
    try:
        if sumtype == "add":
            error = array([[((num1+num2)-answer) for num1,num2,answer in sums]], dtype=int)
        elif sumtype == "multiply":
            error = array([[((num1*num2)-answer) for num1,num2,answer in sums]], dtype=int)
        elif sumtype == "mod":
            error = array([[(num2-(num1%answer)) for num1,num2,answer in sums]], dtype=int)
        else:
            error = array([[-99999 for num1,num2,answer in sums]], dtype=int)
    except:
        error = array([[-99999 for num1,num2,answer in sums]], dtype=int)
    return hstack((sums, error.T))

# Take binary arrays and convert back to decimal sums
# NOTE: inputdigits=? must be specified if sums2binary(..., multiplier=?) was used to double, triple, etc the input
def binary2sums(inputs, outputs, inputdigits=0, check=False, sumtype="add"):
    if inputdigits > 0:
        digin = inputdigits
    else:
        digin = inputs.shape[-1]
    digout = outputs.shape[-1]
    half  = int(digin/2)
    num1s = inputs[0:,    0:half].dot(1 << arange(half-1,-1,-1))
    num2s = inputs[0:,half:digin].dot(1 << arange(half-1,-1,-1))
    answers = outputs.dot(1 << arange(digout-1, -1, -1))
    sums = vstack((num1s, num2s, answers)).T   # stack vertically then transpose so one sum per line
    if check is True:
        return checksums(sums, sumtype=sumtype)
    else:
        return sums


"""
 Semi-prime list functions: = semi-prime = prime x prime
"""

# Make array of n x n semi-primes in decimal
# eg. mksemiprimearray(0,100) will make 625 sums [[4,2]...[9409,97]]
def mksemiprimearray(start, n, randomskip=1):
    nprimes = primes.getfPrimes(start, n, randomskip=randomskip)
    return array([[p*q,p] for p in nprimes for q in nprimes])

# Make array of n semi-primes in decimal using only unique primes
def mkuniquesemiprimearray(pstart, qstart, n, randomskip=1):
    pprimes = array((primes.getfPrimes(pstart, n, randomskip=randomskip)))
    qprimes = array((primes.getfPrimes(qstart, n, randomskip=randomskip)))
    return array([[p*q,p] for p,q in vstack((pprimes, qprimes)).T])

# returns <minimum bytes required to hold sum> <min digits required to hold answer>
def OLDsemiprimesbinarydigits(semiprimes):
    semiprime, prime = amax(semiprimes, axis=0)
    return 2*len("{0:b}".format(semiprime)), len("{0:b}".format(prime))

# Convert list of semi-primes and primes to binary inputs and outputs
# eg. semiprimes([[4 2]], 8, 8) makes input:     [0 0 0 0 0 1 0 0] (semiprime) and output [0 0 0 0 0 0 1 0]
# eg. sums(..., multiplier=2)   makes input x 2: [0 0 0 0 0 1 0 0 0 0 0 0 0 1 0 0] (semip/semip) and output [0 0 0 0 1 0 0 0]
def OLDsemiprimes2binary(semiprimes, digin, digout, multiplier=1):
    inputs  = (array([list(binary_repr(semiprime, digin)) for semiprime,prime in semiprimes], dtype=int))
    outputs = (array([list(binary_repr(prime,    digout)) for semiprime,prime in semiprimes], dtype=int))
    originalinputs = inputs       # NOTE: don't need deepcopy here
    for i in range(1, multiplier):
        inputs = hstack((inputs, originalinputs))
    return inputs, outputs

# returns <minimum bytes required to hold sum> <min digits required to hold answer>
def semiprimesbinarydigits(semiprimes):
    semiprime, ignorezeros, prime = amax(semiprimes, axis=0)
    sqroot = semiprime ** 0.5
    return blen(semiprime), {True:blen(sqroot), False:blen(prime)} [sqroot > prime]

# Convert list of semi-primes and primes to binary inputs and outputs
# eg. semiprimes([[4 2]], 8, 8) makes input:     [0 0 0 0 0 1 0 0] (semiprime) and output [0 0 0 0 0 0 1 0]
# eg. sums(..., multiplier=2)   makes input x 2: [0 0 0 0 0 1 0 0 0 0 0 0 0 1 0 0] (semip/semip) and output [0 0 0 0 1 0 0 0]
def semiprimes2binary(semiprimes, digin, digout, multiplier=1):
    inputs  = (array([list(binary_repr(semiprime, digin)) for semiprime,ignorezeros,prime in semiprimes], dtype=int))
    outputs = (array([list(binary_repr(prime,    digout)) for semiprime,ignorezeros,prime in semiprimes], dtype=int))
    originalinputs = inputs       # NOTE: don't need deepcopy here
    for i in range(1, multiplier):
        inputs = hstack((inputs, originalinputs))
    return inputs, outputs

# Take binary arrays and convert back to decimal sums
# NOTE: returned is a numpy array not a normal array (so use sums.shape instead of len(sums))
def binary2semiprimes(inputs, outputs, inputdigits=0):
    if inputdigits > 0:
        digin = inputdigits
    else:
        digin = inputs.shape[-1]
    digout = outputs.shape[-1]
    semiprimes =  inputs[0:,0:digin].dot(1 << arange(digin-1,  -1, -1))
    primes     = outputs.dot(1 << arange(digout-1, -1, -1))
    #    digout = outputs.shape[-1]
    #    semiprimes =  inputs.dot(1 << arange(digin-1,  -1, -1))
    #    primes     = outputs.dot(1 << arange(digout-1, -1, -1))
    return vstack((semiprimes, primes, semiprimes/primes)).T   # stack vertically then transpose so one sum per line


"""
 Semi-prime remainder functions: = semi-prime, remainder = divisor (which gives the remainder)
"""

# Make array of n x 3 semi-prime sums: semi-prime, remainder, divisor
# NOTE: rnums are n random ints (prime guesses) between 2 and the square root of semiprime
# eg. mkspmodarray(11 * 17, 100) will make 100 sums [187,7,18]...[187,2,5]]
def mkspmodarray(semiprime, n):
    sqroot = (semiprime ** 0.5)
    rnums = array(sqroot * random.random((1, n)) + 2, dtype=int)
    mods = semiprime % rnums
    sp = zeros_like(mods) + semiprime
    sums = vstack((sp, mods, rnums)).T
    return sums

# As above but the array will consist of many semiprimes, not just one
def mkspsmodarray(pstartdig, qstartdig, n, spmods=1, randskipdig=0):
    pprimes = array((primes.get_n_primes_d_digits(n//spmods, pstartdig, randskipdig=randskipdig)))
    qprimes = array((primes.get_n_primes_d_digits(n//spmods, qstartdig, randskipdig=randskipdig)))
    sums = array(([0, 0, 0]))
    for i in range(len(pprimes)):
        sums = vstack((sums, mkspmodarray(pprimes[i] * qprimes[i], spmods - 1)))
        sums = vstack((sums, [pprimes[i] * qprimes[i], 0, pprimes[i]]))  # spmods is 1 fewer so space for this
    return sums[1:,:]


"""
 Read file and create array blocks for file compression tests using neural networks
    getblocks      will read in a text or binary file and return file blocks
    blocks2binary  will convert the file blocks to binary - this will be the output binary blocks for the neural net
    count2binary   will be the input binary blocks for the neural net
""" 

# return array of blocks of bytes
# TO DO: deal with files that are less than bsize
# TO DO: deal with end of file block which is less than bsize
def getblocks(path, bsize=10, bmax=10):
    bblocks = []
    bcount = 1
    with open(path, "rb") as fd:
        while bcount <= bmax:
            bblock = fd.read(bsize)
            bcount = bcount + 1
            if bblock:
                bblocks.append(bblock)
    return bblocks

# Convert list of byte blocks to binary
# eg. [b'<mediawiki', ... ]  makes: [[0 0 1 1 1 1 0 0 0 1 1 0 1 1 0 1 0 1 ...] [...]]
# eg. 10 blocks of the example above will yield a shape of (10, 80)  (80 cols as each of the 10 bytes is 8 binary digits)
def bytes2binary(bblocks):
    bsize = len(bblocks[0])
    bcount = len(bblocks)
    bablocks = array([array([list(binary_repr(byte,8)) for byte in list(block)], dtype=int).reshape(1,bsize*8) for block in bblocks]).reshape(bcount, bsize*8)
    return bablocks

# Convert list of binary blocks to byte blocks
# Binary blocks are chopped up into bytes of 8 binary digits long and put into an array.
# eg. [[0 0 1 1 1 1 0 0 0 1 1 0 1 1 0 1 0 1 ...] [...]]  makes [b'<mediawiki', ... ]
def binary2bytes(bablocks):
    nbytes = int(bablocks.shape[1] / 8)
    bablocks = array(around(bablocks), dtype=int)
    bblocks = []
    for bablock in bablocks:
        abinbytes = bablock.reshape(nbytes,8)             # array of bytes in binary form
        abytes = abinbytes.dot(1 << arange(8-1, -1, -1))  # array of bytes in integer form
        bstr = "".join(chr(x) for x in abytes)            # make string section
        bblocks.append(bytes(bstr, "utf-8"))              # TO DO: do I want byte literal, ie. b""??
    return bblocks

# Generate blocks in binary from first to last block
# eg. 1 -> 100 will give [[0 0 0 0 0 1] ... [1 1 0 0 1 0 0]]
def count2binary(fblock, lblock):
    bmax = len(binary_repr(lblock+1))
    countblocks = array([list(binary_repr(count,bmax)) for count in range(fblock,lblock+1)], dtype=int)
    return countblocks

# Generate random blocks in binary from first to last block.
# With seed so the same random numbers can be generated if need be.
def rand2binary(qty, mult, seed=1):
    random.seed(seed)
    bmax = len(binary_repr(mult+1))
    randblocks = array([list(binary_repr(int(random.random()*mult),bmax)) for rand in range(0,qty)], dtype=int)
    return randblocks


"""
 Tests
"""

if __name__ == "__main__":
    set_printoptions(linewidth=200)
    set_printoptions(edgeitems=10)
    set_printoptions(precision=3)
    set_printoptions(suppress=True)
    #set_printoptions(formatter={'float_kind':'{:f}'.format})

    randblocks = rand2binary(20,10000,1)
    print (randblocks)
    print (randblocks.shape)
    sys.exit(0)

    home = os.getenv('HOME')
    bblocks = getblocks(home+"/bin/neuralnet_lstm_enwik8.txt", bsize=10, bmax=10)
    countblocks = count2binary(1,20)
    bablocks = bytes2binary(bblocks)
    new_bblocks = binary2bytes(bablocks)
    print (countblocks)
    print (countblocks.shape)
    print (bablocks)
    print (bablocks.shape)
    print (bblocks)
    print (new_bblocks)
    sys.exit(0)

    #print (mkarray(2,4))
    #print (mkarray(4,2))
    #sys.exit(0)
    #print (int2bin(235,20))
    #print (bin2int(int2bin(235,20)))

    #sums = mkspsmodarray(3, 4, 1000, spmods=10, randskipdig=3)
    #sums = mkspmodarray(982451653 * 179424673, 1000)
    #sums = mkspmodarray(7123321 * 123799, 1000)
    #sums = mkspmodarray(11 * 17, 100)
    #print (sums)
    #print (sums[:,1:3])
    #print (maxbinarydigits(sums[:,1:3]))
    #sys.exit(0)

    sums = mkspsmodarray(3, 3, 10000, spmods=1, randskildig=2)
    sums = squeeze(sums[random.shuffle(sums[:])])   # shuffle on column 0
    sizein, sizeout = semiprimesbinarydigits(sums)
    print (sums)
    print (sizein, sizeout)
    tinputs, toutputs = semiprimes2binary(sums, sizein, sizeout, multiplier=1)
    print (tinputs)
    #print (toutputs)
    sys.exit(0)

    #sums = mkaddarray(1, 20, randomskip=100)
    sums = mkuniqueaddarray(100, 1000, 20, randomskip1=100)
    sizein, sizeout = sumsbinarydigits(sums)
    print (sums)
    print ("you need binary digits:", sizein, sizeout)
    i, o = sums2binary(sums, sizein, sizeout, multiplier=4)
    print (i)
    print (o)
    print ("shape of input:", i.shape)
    print ("shape of output:", o.shape)
    sums2 = binary2sums(i, o, inputdigits=sizein, check=False)
    print (sums2)
    print (sums2.shape)
    sys.exit(0)

    #semiprimes = mksemiprimearray(1000, 10, randomskip=100)
    semiprimes = mkuniquesemiprimearray(1000, 10000, 10, randomskip=100)
    sizein, sizeout = semiprimesbinarydigits(semiprimes)
    print (semiprimes)
    print ("you need binary digits:", sizein, sizeout)
    i, o = semiprimes2binary(semiprimes, sizein, sizeout, multiplier=4)
    print (i)
    print (o)
    print ("shape of input:", i.shape)
    print ("shape of output:", o.shape)
    semiprimes2 = binary2semiprimes(i, o, inputdigits=sizein)
    print (semiprimes2)
    print (semiprimes2.shape)
    sys.exit(0)


