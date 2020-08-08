'''
 Copyright (c) 2005-2019 Colin Pearse.
 All scripts are free in the binscripts repository but please refer to the
 LICENSE file at the top-level directory for the conditions of distribution.

 Name:        sphere.py
 Description: Draw a sphere given a radius using matrix coordinates
'''

import os
import sys
import math
import re
 
def usage(name):
    print ("")
    print (" usage: %s <radius> solid"%(name))
    print (" usage: %s <radius> hollow"%(name))
    print (" usage: %s <radius> mcsolid"%(name))
    print (" usage: %s <radius> mchollow"%(name))
    print ("")
    print (" Draw a solid sphere, then hollow it out if needed.")
    print (" The map coordinates, z slices, and ascii circles are displayed by slice z.")
    print ("")
    print (" The \"mcsolid\" and \"mchollow\" is used by \"mcwrite.sh\" to draw a")
    print (" sphere in Minecraft (Bedrock).")
    print ("")
    sys.exit(2)
 
'''
 VLM - class to allow matrices to grow as large as their largest index (x,y)
 usage.
   m = VLM(defval=' ')

   m[(1,1)] = '#'
   m[(-2,-2)] = '#'

   coords_map = {(0,0):0, (1,1):1, (-2,-2):1}
   m.msetd(coords_map, mapval={0:'O',1:'#'})

   coords_list = [(0,0), (1,1), (-2,-2)]
   m.mset(coords_list, 'X')

   m.printm('join', revy=True)
'''
class VLM:
    def __init__(self, minx=0, miny=0, maxx=0, maxy=0, defval=0):
        self.__m = {}
        self.__defval = defval
        self.__minx = minx
        self.__miny = miny
        self.__maxx = maxx
        self.__maxy = maxy
    def __setminmax(self, pos):
        x,y = pos
        if x < self.__minx: self.__minx = x
        if y < self.__miny: self.__miny = y
        if x > self.__maxx: self.__maxx = x
        if y > self.__maxy: self.__maxy = y
    def __setitem__(self, pos, val):
        self.__setminmax(pos)
        if val == self.__defval:
            if pos in self.__m:
                del self.__m[pos]
        else:
            self.__m[pos] = val
    def __getitem__(self, pos):
        self.__setminmax(pos)
        return self.__m[pos] if pos in self.__m else self.__defval
    def mset(self, a, val):
        for pos in a:
            self.__setitem__(pos, val)
    def msetd(self, d, mapval={}):
        for pos,val in d.items():
            if len(mapval) > 0:
                self.__setitem__(pos, mapval[val])
            else:
                self.__setitem__(pos, val)
    def printm(self, j="", revy=False, revx=False):
        minx = self.__minx
        miny = self.__miny
        maxx = self.__maxx+1
        maxy = self.__maxy+1
        incy = 1
        incx = 1
        if revy == True:
            miny = self.__maxy
            maxy = self.__miny-1
            incy = -1
        if revx == True:
            minx = self.__maxx
            maxx = self.__minx-1
            incx = -1
        for y in range(miny, maxy, incy):
            line = []
            for x in range(minx, maxx, incx):
                line.append(self.__getitem__((x,y)))
            if j == "join":
                print (''.join(list(map(str, line))))
            else:
                print (line)

def print_cmap(cmap):
    m = VLM(defval=' ')
    m.msetd(cmap, mapval={0:' ',1:'#'})
    m.printm('join', revy=True)
def print_coords(c):
    m = VLM(defval=' ')
    m.mset(c, '#')
    m.printm('join', revy=True)

def title(s):
    ul = '-'*len(s)
    print (ul); print (s); print (ul)

'''
 The general equation for a sphere is:
 r^2 = x^2 + y^2 + z^2   x,y,z are points on the surface of the sphere with centre (0,0,0)
 The code below fills in the coordinates of a solid sphere.
 It can be hollowed out later by removing those pixels who are surrounded by 6 neighbouring pixels.
'''
def get_sphere(r):
    cmap = {(0,0,0):0}
    for x in range(int(math.floor(-r)),int(math.ceil(r)+1)):
        x += 0.5
        for y in range(int(math.floor(-r)),int(math.ceil(r)+1)):
            y += 0.5
            for z in range(int(math.floor(-r)),int(math.ceil(r)+1)):
                z += 0.5
                if x*x + y*y + z*z <= r*r:
                    cmap[int(x),int(y),int(z)] = 1
    return cmap

def hollow_sphere(cmap):
    for x,y,z in cmap:
        if (x-1,y,z) in cmap and (x+1,y,z) in cmap and (x,y-1,z) in cmap and (x,y+1,z) in cmap and (x,y,z-1) in cmap and (x,y,z+1) in cmap:
            cmap[x,y,z] = 0
    return dict([(k,v) for k,v in cmap.items() if v==1]) 

# 1. print sphere map
# 2. print slices and coordinates
# 3. print slices as ascii circles
def print_slices(cmap):
    title ("coords {(x,y,z):1, ...}")
    print (cmap)
    slices = {}
    for x,y,z in cmap:
        if z not in slices:
            slices[z] = []
        slices[z] += [(x,y)]
    title ("coords: z slice and [(x,y), ...]")
    for z in sorted(list(slices.keys())):
        print (z, slices[z])
    title ("circle slices by z")
    for z in sorted(list(slices.keys())):
        print("SLICE:",z)
        print_coords(slices[z])

# print x,y,z for Minecraft script mcwrite.sh
def mcprint_slices(cmap):
    for x,y,z in cmap:
        print (x,y,z)

'''
 main
'''
if __name__ == '__main__':
    __myhome__ = os.getenv('HOME')
    __myname__ = os.path.basename(sys.argv[0])
    arg2 = ""
    if len(sys.argv) == 3: arg2 = sys.argv[2]
    if len(sys.argv) >= 2:
        radius = int(sys.argv[1])
        cmap = get_sphere(radius)
        if re.match(r'hollow$',arg2):
            cmap = hollow_sphere(cmap)
        if re.match(r'^mc',arg2):
            mcprint_slices(cmap)
        else:
            print_slices(cmap)
    else:
        usage(__myname__)


