
"""
 Author:      Colin Pearse
 Name:        linked_list.py
 Description: Find m-th to last element
"""


"""
 Rules:
 - Script must use a linked list
 - Test cases consist of two inputs
 - Input 1 must be: 0 < M < 2^32 - 1,
 - Input 2 must be a list separated by a single space  NOTE: this implies a double space should yield an empty element, ie. "  " -> ['x','','x']
 - Input 2: each element of the list satisfies 0 <= L[i] <= 2^32 - 1
 - Input 2: number of elements in the list satisfies 0 < |L| < 1024
 - Invalid index shows "NIL"
 - UNSPECIFIED: expecting 0 exit value otherwise it thinks it's a runtime error
 - UNSPECIFIED: it must take O(n) (linear) time to make list, otherwise 2**32 numbers will take too long

 egs.
 inputs: "4"  "10 200 3 40000 5"   output: "200"
 inputs: "2"  "42"                 output: "NIL"
"""

import sys


def main():
    try:
        m = intscalar(input())
        #arr = intarray(input().strip().split())     # strip and split using white space, not single space
        arr = intarray(list(map(int, input().strip().split())))
        print (int(m_in_arr(m, arr)))
    except:
        print ("NIL")

# takes O(1) time (constant time) - meaning larger m -> same time
def OLD_m_in_arr(m, arr):
    return arr[-m]

# takes O(n) time (linear time) - meaning larger m -> longer time
def m_in_arr(m, arr):
    myll = LL()
    for elem in arr:
        myll.add(elem)
    return myll.showrev(n=int(m))


"""
 Check functions
"""

def intscalar(m):
    return validnum(m, msg="for m", nmin=1, nmax=(2**32)-2)

def intarray(arr):
    arrlen = len(arr)
    for num in arr:
        validnum(num, msg="for array element", nmin=0, nmax=(2**32)-1)
    return arr

def validnum(num, msg="", nmin=0, nmax=10):
    try:
        num = int(num)
        if nmin <= num and num <= nmax:
            return num
    except:
        raise
    raise



"""
 Classes to make the linked list
"""

class Element:
    def __init__(self, edata, enext=None, eprev=None, enum=0):
        self.edata = edata
        self.enext = enext
        self.eprev = eprev
        self.enum  = enum

class LL:
    def __init__(self):
        self.curr  = None
        self.start = None
        self.end   = None

    def add(self, data):
        if self.start is None:
            self.curr  = Element(data, eprev=self.start, enum=1)
            self.start = self.curr
            self.end   = self.curr
        else:
            prev       = self.curr
            self.curr  = Element(data, eprev=prev, enum=self.curr.enum+1)
            prev.enext = self.curr
            self.end   = self.curr

    def iterate(self, e, n=None, reverse=False):
        o = []
        if self.validnum(n) is False:
            raise

        if (n is not None) and reverse is True:
            n = e.enum - (n-1)

        while e is not None:
            if n is None:
                o.append(e.edata)
            elif n == e.enum:
                return e.edata

            if reverse is False:
                e = e.enext
            else:
                e = e.eprev
        return o

    def show(self, n=None):
        return self.iterate(self.start, n=n, reverse=False)

    def showrev(self, n=None):
        return self.iterate(self.end, n=n, reverse=True)

    def validnum(self, n):
        if n is not None:
            if n < 1 or n > self.end.enum:
                return False
        return True


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print('Aborted!')



