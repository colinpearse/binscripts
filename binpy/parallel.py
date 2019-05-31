

"""
 Author:      Colin Pearse
 Name:        parallel.py
 Description: Examples of multiprocessing
"""


# NOTE: threading, implemented in CPython, is not true parallelism

import multiprocessing as mp
import random
import time



"""
 example 1
"""

print ('\nEG 1')
def func1():
    print ('func1: starting')
    for i in range(10000000): pass
    print ('func1: finishing')

def func2():
    print ('func2: starting')
    for i in range(10000000): pass
    print ('func2: finishing')

if __name__ == '__main__':
    p1 = mp.Process(target=func1)
    p2 = mp.Process(target=func2)
    p1.start()
    p2.start()
    p1.join()
    p2.join()


"""
 example 2
"""

print ('\nEG 2')
def runInParallel(*fns):
    jobs = []
    for fn in fns:
        job = mp.Process(target=fn)
        job.start()
        jobs.append(job)
    for job in jobs:
        job.join()
runInParallel(func1, func2)



"""
 example 3
"""

print ('\nEG 3')
def myfunc(jobnum, returnd):
    rand1 = random.randint(1,1000)
    rand2 = random.randint(1,1000)
    print ('process {:d}: rand1={:d} rand2={:d}'.format(jobnum, rand1, rand2))
    returnd[jobnum] = { 'rand1': rand1,
                        'rand2': rand2,
                      }

if __name__ == '__main__':
    manager = mp.Manager()
    returnd = manager.dict()
    jobs = []
    try:
        for jobnum in range(5):
            job = mp.Process(target=myfunc, args=(jobnum, returnd))
            jobs.append(job)
            job.start()
        #time.sleep(3)  # test ctrl-c does give error for each process
        for job in jobs:
            job.join()
    except KeyboardInterrupt:
        print('Aborted!')
        for job in jobs:
            job.terminate()
    print (returnd)

