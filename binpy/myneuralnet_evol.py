
"""
 Copyright (c) 2005-2019 Colin Pearse.
 All scripts are free in the binscripts repository but please refer to the
 LICENSE file at the top-level directory for the conditions of distribution.

 Name:        myneuralnet_evol.py
 Description: Create multiple neuralnets, take the top performers and swap parts of the weights analagous to alleles in genes.
"""

#import pandas as pd
#pd.options.display.width = 180
import numpy as np
import sys
import os
import time
import copy
import mkarrays
import click
import pickle
import random
import itertools
import multiprocessing as mp


@click.command()
@click.option('-st', '--sumtype',    default='',    help='Type of sum on which to train', type=click.Choice(['add', 'mod', 'factor', 'multiply']),)
@click.option('-tn', '--train',      is_flag=True,  help='Train from scratch',)
@click.option('-lt', '--loadtrain',  is_flag=True,  help='Train from last saved position',)
@click.option('-lr', '--lastrun',    is_flag=True,  help='View the last run for a particular sumtype',)
@click.option('-bj', '--bestjob',    is_flag=True,  help='View valid_x/y for the best job from the previous run',)
@click.option('-pd', '--predict',    is_flag=True,  help='Predict using last saved position',)
@click.option('-ck', '--checkjob',   default=-1,    show_default=True, help='Check valid_x/y using a particular job from the previous run',)
@click.option('-iq', '--inputqty',   default=10000, show_default=True, help='Number of sums generated as input',)
@click.option('-hf', '--hfactor',    default=2,     show_default=True, help='Hidden layer nodes is: binary-digits-of-input * hfactor',)
@click.option('-if', '--ifactor',    default=1,     show_default=True, help='Multiple factor for the input',)
@click.option('-bt', '--batch',      default=100,   show_default=True, help='Split inputs into batches of this size',)
@click.option('-dr', '--dropout',    default=0,     show_default=True, help='Percentage of random neurons to dropout when feeding-forward',)
@click.option('-ep', '--epochs',     default=2,     show_default=True, help='Training epochs for all input data',)
@click.option('-lo', '--loops',      default=10,    show_default=True, help='Training loops using the same batch of inputs',)
@click.option('-lr', '--learnrate',  default=0.1,   show_default=True, help='Learn rate on back progagation calculations',)
@click.option('-ld', '--learndecay', default=1.0,   show_default=True, help='Learn rate decay after each iteration',)
@click.option('-sn', '--seconds',    default=5,     show_default=True, help='Seconds between updates',)
@click.option('-pv', '--percvalid',  default=10,    show_default=True, help='Percentage of input which is validation',)
@click.option('-pa', '--parallel',   default=10,    show_default=True, help='Number of parallel neural nets created',)
@click.option('-ev', '--evols',      default=10,    show_default=True, help='Number of evolutions using mutations of the best 2 results',)
@click.option('-sw', '--swaps',      default=50,    show_default=True, help='Percentage of random alleles swapped in top performers',)
@click.option('-mu', '--mutations',  default=5,     show_default=True, help='Percentage of random alleles (cistrons) mutated in top performers',)
def main(sumtype, train, loadtrain, lastrun, bestjob, predict, checkjob, inputqty, hfactor, ifactor, batch, dropout, epochs, loops, learnrate, learndecay, seconds, percvalid, parallel, evols, swaps, mutations):
    """
    \b
    1. Make a neural network with fixed hidden layers.
    2. Run it n times using random starting weights.
    3. Take the top x performers and (a) swap weights (b) introduce random weight.
    4. Run it n times again with new starting weights.
    n. Repeat 3 and 4 until there are 0 errors.

    \b
    egs.
    ... --sumtype=add --train --seconds=2 --learnrate=0.1 --epochs=2 --loops=1000 --batch=0 --inputqty=100 --dropout=10 --parallel=100
    ... --sumtype=add --train --seconds=2 --learnrate=0.01 --epochs=2 --loops=100 --batch=0 --inputqty=1000 --dropout=1 --parallel=10 --evols=10
    ... --sumtype add --train --seconds=2 --learnrate=0.001 --epochs=2 --loops=100 --batch=0 --inputqty=1000 --dropout=20 --parallel=10
    ... --sumtype=add --loadtrain
    ... --sumtype=add --lastrun
    ... --sumtype=add --bestjob
    ... --sumtype=add --checkjob=92

    \b
    NOTE: these have worked well
    ... --sumtype=add -tn -st=add -sn=2 -lr=0.01 -ld=1.001 -dr=0 -iq=1000 -pv=1 -lo=1000 -bt=0 -pa=1 -ep=2 -ev=1
    ... --sumtype=add -tn -st=add -sn=2 -lr=0.1 -dr=0 -iq=20 -lo=100 -bt=0 -pa=1 -ep=1 -ev=1

    BEST SO FAR: verr/vL/vH(terr/tH/tL); 0.0062/0/0 (0.0021/9/5)  validation 196/200 correct)
    ... --sumtype=add -tn -st=add -sn=2 -lr=0.001 -ld=1.0001 -dr=0 -iq=20000 -pv=1 -lo=2000 -bt=0 -pa=1 -ep=20 -ev=1
    """
    init()
    argsd = locals()

    if train is True or loadtrain is True:
        evolution_training = Train(argsd)
        evolution_training.etraining()

    elif lastrun is True:
        terrs, verrs = get_lastrun(sumtype)
        print_lastrun(terrs, verrs)
        print_top_verrs(verrs, terrs, 2)

    elif bestjob is True:
        print_bestjob(sumtype)

    elif checkjob >= 0:
        print_job(sumtype, checkjob)

    elif predict is True:
        # TO DO
        click.echo("Function not implemented yet")

    else:
        click.echo("Please specify one of: --train, --loadtrain, --lastrun, --checkjob, --predict")
        sys.exit(2)

    sys.exit(0)


"""
 Evolution Training class
"""
class Train():
    def __init__(self, argsd):
        self.set_argsd(argsd)
        self.neural_network = None
        self.returnd = None
        self.topnnd = None
        self.jobs = None
        if self.train is True:
            self.sums, self.sizein, self.sizeout, self.train_x, self.train_y, self.valid_x, self.valid_y = make_x_y(self.sumtype, self.inputqty, self.ifactor, self.percvalid)
            save_args(gen_fileargs(self.sumtype), argsd)
            save_sums(gen_filesums(self.sumtype), self.sums)
        else:
            argsd = load_fileargs(gen_fileargs(self.sumtype))
            self.set_argsd(argsd)
            self.train     = False
            self.loadtrain = True
            self.sums, self.sizein, self.sizeout, self.train_x, self.train_y, self.valid_x, self.valid_y = load_x_y(self.sumtype, self.ifactor, self.percvalid)

    def set_argsd(self, argsd):
        self.sumtype    = argsd['sumtype']
        self.train      = argsd['train']
        self.loadtrain  = argsd['loadtrain']
        self.lastrun    = argsd['lastrun']
        self.bestjob    = argsd['bestjob']
        self.predict    = argsd['predict']
        self.checkjob   = argsd['checkjob']
        self.inputqty   = argsd['inputqty']
        self.hfactor    = argsd['hfactor']
        self.ifactor    = argsd['ifactor']
        self.batch      = argsd['batch']
        self.dropout    = argsd['dropout']
        self.epochs     = argsd['epochs']
        self.loops      = argsd['loops']
        self.learnrate  = argsd['learnrate']
        self.learndecay = argsd['learndecay']
        self.seconds    = argsd['seconds']
        self.percvalid  = argsd['percvalid']
        self.parallel   = argsd['parallel']
        self.evols      = argsd['evols']
        self.swaps      = argsd['swaps']
        self.mutations  = argsd['mutations']
        self.topqty = int(self.parallel / 5)
        if self.topqty == 0:
            self.topqty = 1

    def etraining(self):
        self.returnd = jobs_mgr()
        for evol in range(self.evols):
            self.jobs    = jobs_run(self.parallel, self.training, evol)
            jobs_check(self.jobs, self.returnd)
            self.topnnd  = top_jobs(self.topnnd, self.topqty, self.returnd, self.parallel)
            print_top_nns(self.topnnd, self.topqty, self.train_x, self.train_y, self.valid_x, self.valid_y)
            self.returnd = mutate_top_jobs(self.topnnd, self.topqty, self.returnd, self.parallel, self.swaps, self.mutations)
            self.train     = False
            self.loadtrain = False
            print_bestjob(self.sumtype) # CHECK

    def training(self, evol, jobnum):
        if self.train is True:
            self.neural_network = NeuralNetwork(self.sizein*self.ifactor, self.sizein*self.hfactor, self.sizeout, rseed=random.randint(1,self.parallel*100))
        elif self.loadtrain is True:
            self.neural_network = load_nn(self.sumtype, jobnum)
        else:
            self.neural_network = self.returnd[jobnum]['neural_network']

        secs = time.time()
        trainqty = self.train_x.shape[0]
        batchinc = {True:trainqty, False:self.batch}[self.batch == 0]

        for epoch in range(self.epochs):
            for batchstart in range(0, trainqty, batchinc):
                batch_x = self.train_x[batchstart:batchstart+batchinc]  # :<to> field may often exceed the array
                batch_y = self.train_y[batchstart:batchstart+batchinc]  #   this is not a problem for Python
                err = self.neural_network.train(batch_x, batch_y, self.loops, dropout=self.dropout, learnrate=self.learnrate, learndecay=self.learndecay)
                secs = print_status(evol, jobnum, secs, self.seconds, self.neural_network, batchstart, self.batch, self.inputqty, epoch+1, self.epochs, self.loops, self.dropout, self.learnrate, self.learndecay, batch_x, batch_y, self.valid_x, self.valid_y)
                save_nn(gen_filenn(self.sumtype,jobnum), self.neural_network)

        self.returnd[jobnum] = { 'neural_network': self.neural_network,
                                 'verr': get_err(self.neural_network, self.valid_x, self.valid_y),
                                 'terr': get_err(self.neural_network, self.train_x, self.train_y),
                               }


"""
 NeuralNetwork class
"""
class NeuralNetwork():
    def __init__(self, sizein, sizelayer, sizeout, rseed=None):
        if rseed is not None:
            np.random.seed(rseed)
        try:
            self.w1_to_2 = 2 * np.random.random((sizein,    sizelayer)) - 1  # weights matrix rows x cols (init values -1 to 1)
            self.w2_to_3 = 2 * np.random.random((sizelayer, sizelayer)) - 1  # weights matrix rows x cols (init values -1 to 1)
            self.w3_to_4 = 2 * np.random.random((sizelayer, sizeout))   - 1  # weights matrix rows x cols (init values -1 to 1)
            self.alleles1_to_2 = dict(enumerate(random_chunks(list(range(self.w1_to_2.flatten().shape[0])), 5, 30)))  # for swapping
            self.alleles2_to_3 = dict(enumerate(random_chunks(list(range(self.w2_to_3.flatten().shape[0])), 5, 30)))  # for swapping
            self.alleles3_to_4 = dict(enumerate(random_chunks(list(range(self.w3_to_4.flatten().shape[0])), 5, 30)))  # for swapping
        except MemoryError:
            print('Memory error - sizes too big: sizein/sizelayer/sizeout {:d}/{:d}/{:d}'.format(sizein,sizelayer,sizeout))
            sys.exit(1)

    def isize(self):
        return np.size(self.w1_to_2, 0)
    def hsize(self):
        return np.size(self.w2_to_3, 0)
    def osize(self):
        return np.size(self.w3_to_4, 1)

    def squash(self, x):                    # function to squash value between 0 and 1
        return .5 * (1 + np.tanh(.5 * x))      # sigmoid: return 1 / (1 + exp(-x)) gave me: exp() overflow error

    def squashgradient(self, x):            # function to express the slope (derivative returns scalar, gradient returns vector)
        return x * (1 - x)                  # sigmoid derivative

    def decay(self, x, d):
        return x / d

    # w1_to_2 = weights for n1 - n2 (n1 = input)
    # w2_to_3 = weights for n2 - n3 (n? = neurons)
    # w3_to_4 = weights for n3 - n4 (n4 = output)
    # d4 = difference between guess and training output
    # d3 = difference between last difference (d4) and w2_to_3
    def train(self, train_x, train_y, loops, dropout=0, learnrate=1.0, learndecay=1.0):
        sumerror_y = 0
        n1 = train_x
        for loop in range(loops):                                         # EG. sizein=8 sizelayer=16 sizeout=8 inputs/outputs=100
            n2, n3, n4 = self.tthink(n1, dropout=dropout)                 # 100x16, 8x100 = think(100x8)
            error_y = train_y - n4                                        # we want error_y close to 0
            sumerror_y += error_y
            d4 = error_y * self.squashgradient(n4)                        # 100x8  =    (100x8 - 100x8) * 100x8
            d3 = np.dot(d4, self.w3_to_4.T) * self.squashgradient(n3)     # 100x16 = dot(100x8    8x16) * 100x16
            d2 = np.dot(d3, self.w2_to_3.T) * self.squashgradient(n2)     # 100x16 = dot(100x8    8x16) * 100x16
            self.w1_to_2 += np.dot(n1.T, d2) * learnrate                  # 8x16  += dot(8x100  100x16)
            self.w2_to_3 += np.dot(n2.T, d3) * learnrate                  # 16x8  += dot(16x100 100x8)
            self.w3_to_4 += np.dot(n3.T, d4) * learnrate                  # 16x8  += dot(16x100 100x8)
            learnrate = self.decay(learnrate, learndecay)                 # TO DO: should I include loop?
        return np.mean(abs(sumerror_y)/loops)

    def drop(self, n, dropout):
        dist = (100 - dropout) / 100        # Eg. dropout=25 keeps 75% so dist=0.75 (0 <= dist <= 1.0)
        return n * np.random.binomial(1, dist, size=n.shape)

    def tthink(self, n1, dropout=0):
        n2 = self.squash(np.dot(n1,                     self.w1_to_2))   # 100x16 = dot(100x8  8x16)
        n3 = self.squash(np.dot(self.drop(n2, dropout), self.w2_to_3))   # 100x8  = dot(100x16 16x8)
        n4 = self.squash(np.dot(self.drop(n3, dropout), self.w3_to_4))   # 100x8  = dot(100x16 16x8)
        return n2, n3, n4

    def think(self, n1):
        n2 = self.squash(np.dot(n1,self.w1_to_2))   # 100x16 = dot(100x8  8x16)
        n3 = self.squash(np.dot(n2,self.w2_to_3))   # 100x8  = dot(100x16 16x8)
        n4 = self.squash(np.dot(n3,self.w3_to_4))   # 100x8  = dot(100x16 16x8)
        return n4

    def dthink(self, valid_x, valid_y):
        n1 = valid_x
        n2 = self.squash(np.dot(n1,self.w1_to_2))   # 100x16 = dot(100x8  8x16)
        n3 = self.squash(np.dot(n2,self.w2_to_3))   # 100x8  = dot(100x16 16x8)
        n4 = self.squash(np.dot(n3,self.w3_to_4))   # 100x8  = dot(100x16 16x8)
        error_y = valid_y - n4                           # we want error_y close to 0
        err = np.mean(abs(error_y))
        lowerr = np.count_nonzero(error_y<-0.999)
        higherr = np.count_nonzero(error_y>0.999)
        return n4, error_y, err, lowerr, higherr


"""
 Parallel job functions
"""
def jobs_mgr():
    manager = mp.Manager()
    returnd = manager.dict()
    return returnd

def jobs_run(parallel, runfunc, evol):
    jobs = []
    try:
        for jobnum in range(parallel):
            job = mp.Process(target=runfunc, args=(evol, jobnum))
            jobs.append(job)
            job.start()
        for job in jobs:
            job.join()
    except KeyboardInterrupt:
        print('Aborted!')
        for job in jobs:
            job.terminate()
    return jobs

def jobs_check(jobs, returnd):
    err = False
    if len(returnd) > 0:
        for job in jobs:
            if len(returnd[job]) == 0:
                print ("job {:d} did not complete".format(job))
                err = True
    else:
       print ("all jobs failed")
       err = True
    if err is True:
        sys.exit(1)

# allnnds = { {0: neural_network: <...>, 'verr': 0.123, 'terr': 0.0101 },
#             {1: neural_network: <...>, 'verr': 0.234, 'terr': 0.0001 },
#             ... topnnd and returnd sorted and renumbered according to verr ...
def top_jobs(topnnd, topqty, returnd, parallel):
    allnnds = returnd
    if topnnd is not None:
        for i in range(topqty):
            allnnds[parallel+i] = topnnd[i]
    sortd = sorted(allnnds.items(), key=lambda x: x[1]['verr'])
    topnnd = {}
    for i in range(topqty):
        topnnd[i] = sortd[i][1]
    return topnnd

def print_top_nns(topnnd, topqty, train_x, train_y, valid_x, valid_y):
    output = "top %d jobs verr/vL/vH(terr/tH/tL)" % (topqty)
    for i in range(topqty):
        pred_y, err_y, terr, tLerr, tHerr = topnnd[i]['neural_network'].dthink(train_x, train_y)
        pred_y, err_y, verr, vLerr, vHerr = topnnd[i]['neural_network'].dthink(valid_x, valid_y)
        output = output + "; %1.4f/%d/%d (%1.4f/%d/%d)" % (verr, vLerr, vHerr, terr, tLerr, tHerr)
    print (output)

# topjobnum, jobnums resolves as follows in the first for loop when parallel=17, topqty=3:
#   NOTE on chunks(): there must be no more than topqty (3) arrays so any remainder is appended to the last array
# 0 [0,  1,  2,  3,  4]             eg. topnnd[0] copied to returnd[0..4]   alleles (cistrons) mutated in [1..4]
# 1 [5,  6,  7,  8,  9]             eg. topnnd[1] copied to returnd[5..9]   swaps alleles with topnnd[0] in [6..9]
# 2 [10, 11, 12, 13, 14, 15, 16]    eg. topnnd[2] copied to returnd[10..16] swaps alleles with topnnd[0] in [11..16]
def mutate_top_jobs(topnnd, topqty, returnd, parallel, swaps, mutations):
    arr = chunks(list(range(parallel)), topqty)
    for topjobnum,jobnums in enumerate(chunks(list(range(parallel)), topqty)):
        returnd[jobnums.pop(0)] = copy.deepcopy(topnnd[topjobnum])
        if topjobnum > 0:
            for jobnum in jobnums:
                returnd[jobnum]['neural_network'] = random_swaps(copy.deepcopy(topnnd[topjobnum]['neural_network']), copy.deepcopy(topnnd[0]['neural_network']), swaps)
            for jobnum in jobnums:
                returnd[jobnum]['neural_network'] = random_mutate(copy.deepcopy(topnnd[topjobnum]['neural_network']), mutations)
    return returnd

def random_swaps(nnet1, nnet2, swaps):
    nnet1.w1_to_2 = swap_weights(nnet1.w1_to_2.shape, nnet2.w1_to_2.shape, nnet1.w1_to_2.flatten(), nnet2.w1_to_2.flatten(), nnet1.alleles1_to_2, nnet2.alleles1_to_2, swaps)
    nnet1.w2_to_3 = swap_weights(nnet1.w2_to_3.shape, nnet2.w1_to_2.shape, nnet1.w2_to_3.flatten(), nnet2.w1_to_2.flatten(), nnet1.alleles2_to_3, nnet2.alleles1_to_2, swaps)
    nnet1.w3_to_4 = swap_weights(nnet1.w3_to_4.shape, nnet2.w1_to_2.shape, nnet1.w3_to_4.flatten(), nnet2.w1_to_2.flatten(), nnet1.alleles3_to_4, nnet2.alleles1_to_2, swaps)
    return nnet1

def random_mutate(nnet, mutations):
    nnet.w1_to_2 = mutute_weights(nnet.w1_to_2.shape, nnet.w1_to_2.flatten(), nnet.alleles1_to_2, mutations)
    nnet.w2_to_3 = mutute_weights(nnet.w2_to_3.shape, nnet.w2_to_3.flatten(), nnet.alleles2_to_3, mutations)
    nnet.w3_to_4 = mutute_weights(nnet.w3_to_4.shape, nnet.w3_to_4.flatten(), nnet.alleles3_to_4, mutations)
    return nnet

def swap_weights(w1_shape, w2_shape, w1_1D, w2_1D, w1_alleles, w2_alleles, swaps):
    w_len   = get_smaller_weight(w1_1D.shape[0], w2_1D.shape[0])
    w_alen  = get_smaller_weight(len(w1_alleles), len(w2_alleles))
    n_swaps = swaps * int(w_len / 100)   # since swaps is a percentage (w_len will be the lowest length of the 1D arrays)
    for n in range(n_swaps):
        ri = random.randint(0, w_alen-1)
        # NOTE: cannot check values len(w1_alleles[ri])... because the larger 1D array may ligitmately have a shorter allele
        w_alleles = get_smaller_weight(w1_1D.shape[0], w2_1D.shape[0], r1=w1_alleles, r2=w2_alleles)
        for i in w_alleles[ri]:
            if i < w_len:
                w1_1D[i] = w2_1D[i]
            else:
                print ("WARNING: out of bounds",i,"from",w_alleles[ri])
                break
    return w1_1D.reshape(w1_shape)

def get_smaller_weight(v1, v2, r1=None, r2=None):
    if r1 is None:
        r1 = v1
    if r2 is None:
        r2 = v2
    return {True:r1, False:r2}[v2 > v1]

def mutute_weights(w_shape, w_1D, w_alleles, mutations):
    n_mutations = mutations * int(w_1D.shape[0] / 100)   # since mutations is a percentage
    for n in range(n_mutations):
        ri = random.randint(0, len(w_alleles)-1)
        randnums = [round(random.uniform(-1,1),4) for i in range(0, len(w_alleles[ri]))]
        for i,ai in enumerate(w_alleles[ri]):
            w_1D[ai] = randnums[i]
    return w_1D.reshape(w_shape)

# equal_chunks: returns divnum arrays of length chsize (ignoring the remainder)
# chunks: get equal_chunks, then append remaining elements onto the final array (crude)
def equal_chunks(arr, divnum):
    chsize = int(len(arr) / divnum)
    return [arr[0+chsize*i : chsize*(i+1)] for i in range(divnum)]

def chunks(arr, divnum):
    arrs = equal_chunks(arr, divnum)
    chmod = int(len(arr) % divnum)
    if chmod > 0:
        [arrs[-1].append(rem) for rem in arr[-chmod:]]
    return arrs

# Get random chunks between chmin, chmax
# NOTE: if the last chunk < chmin then it's appended to the 2nd last chunk
#       (which may make it > chmax) and the last chunk is removed
def random_chunks(arr, chmin, chmax):
    it = iter(arr)
    arrlen = len(arr)
    arrs = []
    for i in range(arrlen):
        arrs.append(list(itertools.islice(it, random.randint(chmin,chmax))))
        if arrs[-1][-1] == arrlen-1:
            if len(arrs[-1]) < chmin:
                [arrs[-2].append(rem) for rem in arrs[-1]]
                arrs.pop()
            break
    return arrs


"""
 Job printing functions using files
"""
def get_lastrun(sumtype):
    argsd = load_fileargs(gen_fileargs(sumtype))
    sums, sizein, sizeout, train_x, train_y, valid_x, valid_y = load_x_y(sumtype, argsd['ifactor'], argsd['percvalid'])
    terrs = {}
    verrs = {}
    for jobnum in range(argsd['parallel']):
        nnet = load_nn(sumtype, jobnum)
        pred_y, err_y, terr, tLerr, tHerr = nnet.dthink(train_x, train_y)
        pred_y, err_y, verr, vLerr, vHerr = nnet.dthink(valid_x, valid_y)
        terrs[jobnum] = terr
        verrs[jobnum] = verr
    return terrs, verrs

def print_lastrun(terrs, verrs):
    tsorted = sorted(terrs, key=terrs.get, reverse=True)
    vsorted = sorted(verrs, key=verrs.get, reverse=True)
    for key in tsorted:
        print (key, verrs[key], "training was", terrs[key])
 
def print_top_verrs(verrs, terrs, topqty):
    tsorted = sorted(terrs, key=terrs.get)
    vsorted = sorted(verrs, key=verrs.get)
    output = "top %d jobs" % (topqty)
    for i in range(topqty):
	    output = output + "; %d=%1.4f(%1.4f)" % (vsorted[i], verrs[vsorted[i]], terrs[vsorted[i]])
    print (output)

def print_job(sumtype, checkjob):
    argsd = load_fileargs(gen_fileargs(sumtype))
    sums, sizein, sizeout, train_x, train_y, valid_x, valid_y = load_x_y(sumtype, argsd['ifactor'], argsd['percvalid'])
    nnet = load_nn(sumtype, checkjob)
    print_predsums(nnet, train_x, train_y, sumtype, sizein)
    print_predsums(nnet, valid_x, valid_y, sumtype, sizein)

def print_bestjob(sumtype):
    terrs, verrs = get_lastrun(sumtype)
    vsorted = sorted(verrs, key=verrs.get)
    print_job(sumtype, vsorted[0])


"""
 General Functions
"""

# Normally exec
# eg. obj = {'var1':1, {'var2': 'blah'}
# eg. tmplocal after exec: {'tmpd': {'var1':1, {'var2': 'blah'}}
def exec_getlocal(obj):
    tmplocal = {}
    exec('tmplocal = '+obj, None, tmplocal)
    return tmplocal['tmplocal']

def exec_cmd(cmd=None):
    if cmd != None:
        exec(msg)

def gen_pathroot(sumtype):
    return __myhome__+"/log/"+__myname__+"_"+sumtype

def gen_fileargs(sumtype):
    return gen_pathroot(sumtype)+".args"

def gen_filesums(sumtype):
    return gen_pathroot(sumtype)+".sums"

def gen_filenn(sumtype, jobnum):
    return gen_pathroot(sumtype)+".nn"+str(jobnum)

def load_fileargs(fileargs):
    text_file = open(fileargs, "r")
    setargs = text_file.read()
    text_file.close()
    return exec_getlocal(setargs)

def load_nn(sumtype, jobnum):
    return pickle.load(open(gen_filenn(sumtype, jobnum), "rb"))

def save_args(fileargs, argsd):
    fd = open(fileargs, "w")
    fd.write("%s\n" % (argsd))
    fd.close()

def save_sums(filesums, sums):
    fd = open(filesums, "wb")
    pickle.dump(sums, fd)
    fd.close()

def save_nn(filenn, nnet):
    fd = open(filenn, "wb")
    pickle.dump(nnet, fd)
    fd.close()

def split_x_y(x, y, percvalid):
    qty = x.shape[0]
    validqty = int(qty * (percvalid/100))
    trainqty = int(qty - validqty)
    return x[:trainqty], y[:trainqty], x[trainqty:], y[trainqty:]

def make_x_y(sumtype, inputqty, ifactor, percvalid):
    if sumtype == "factor":
        sums = mkarrays.mkspsmodarray(3, 3, inputqty, spmods=1, randomskip=10)
        sums = np.squeeze(sums[np.random.shuffle(sums[:])])   # shuffle on column 0
        sizein, sizeout = mkarrays.semiprimesbinarydigits(sums)
        x, y = mkarrays.semiprimes2binary(sums, sizein, sizeout, multiplier=ifactor)
    else:
        if sumtype == "add":
            sums = mkarrays.mkuniqueaddarray(10, 15, inputqty, randomskip1=10, randomskip2=10)
        elif sumtype == "mod":
            sums = mkarrays.mkspsmodarray(3, 3, inputqty, spmods=10, randskipdig=2)
        elif sumtype == "multiply":
            sums = mkarrays.mkuniquemultiplicationarray(10, 10, inputqty, randomskip1=10, randomskip2=10)
        sums = np.squeeze(sums[np.random.shuffle(sums[:])])   # shuffle on column 0
        sizein, sizeout = mkarrays.sumsbinarydigits(sums)
        x, y = mkarrays.sums2binary(sums, sizein, sizeout, multiplier=ifactor)
    train_x, train_y, valid_x, valid_y = split_x_y(x, y, percvalid)
    return sums, sizein, sizeout, train_x, train_y, valid_x, valid_y

def load_x_y(sumtype, ifactor, percvalid):
    sums = pickle.load(open(gen_filesums(sumtype), "rb"))
    if sumtype == "factor":
        sizein, sizeout = mkarrays.semiprimesbinarydigits(sums)
        x, y = mkarrays.semiprimes2binary(sums, sizein, sizeout, multiplier=ifactor)
    else:
        sizein, sizeout = mkarrays.sumsbinarydigits(sums)
        x, y = mkarrays.sums2binary(sums, sizein, sizeout, multiplier=ifactor)
    train_x, train_y, valid_x, valid_y = split_x_y(x, y, percvalid)
    return sums, sizein, sizeout, train_x, train_y, valid_x, valid_y

def print_status(evol, jobnum, secs, seconds, nnet, batchstart, batch, inputqty, epoch, epochs, loops, dropout, learnrate, learndecay, batch_x, batch_y, valid_x, valid_y):
    if time.time() > secs+seconds:
        secs = time.time()
        HHMM = time.strftime("%H:%M")   #("%Y,%m,%d,%H,%M,%S")
        pred_y, err_y, terr, tLerr, tHerr = nnet.dthink(batch_x, batch_y)
        pred_y, err_y, verr, vLerr, vHerr = nnet.dthink(valid_x, valid_y)
        print ("%s: %d-%d) %d:%d of %d; loop/epochs/epoch=%d/%d/%d; nn=%d/%d/%d; terr/tL/tH=%1.4f/%d/%d; verr/vL/vH=%1.4f/%d/%d; dropout=%d%s; learnrate=%1.6f/%1.6f" % (HHMM, evol, jobnum, batchstart, batch, inputqty, loops, epochs, epoch, nnet.isize(), nnet.hsize(), nnet.osize(), terr, tLerr, tHerr, verr, vLerr, vHerr, dropout, "%", learnrate, learndecay))
        sys.stdout.flush()
    return secs
    
# print_predsums(nnet, valid_x, valid_y, sumtype, sizein)
# print_predsums(nnet, train_x, train_y, sumtype, sizein)
def print_predsums(nnet, x, y, sumtype, sizein):
    pred_y, err_y, err, Lerr, Herr = nnet.dthink(x, y)
    print ("err / L / H = %1.4f / %d / %d" % (err, Lerr, Herr))
    if sumtype == "factor":
        predsums = mkarrays.binary2semiprimes(x, np.round(pred_y,0))
    else:
        predsums = mkarrays.binary2sums(x, np.round(pred_y,0), inputdigits=sizein, check=True, sumtype=sumtype)
    print (predsums)

def get_err(nnet, x, y):
    pred_y, err_y, err, Lerr, Herr = nnet.dthink(x, y)
    return err


def init():
    np.set_printoptions(linewidth=250)
    np.set_printoptions(edgeitems=10)
    np.set_printoptions(precision=3)
    np.set_printoptions(suppress=True)
    #np.set_printoptions(formatter={'float_kind':'{:f}'.format})   # for semiprime to avoid <num>+e format


if __name__ == '__main__':
    __myhome__ = os.getenv('HOME')
    __myname__ = os.path.splitext(os.path.basename(sys.argv[0]))[0]
    try:
        main()
    except KeyboardInterrupt:
        print('Aborted!')


