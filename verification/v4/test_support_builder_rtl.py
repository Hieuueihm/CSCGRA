"""Live LFSR/Phi-cache -> support builder -> one-copy B RTL integration."""
import hashlib
import json
from pathlib import Path
import random
import re
import sys
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from scripts.v4.xsim import compile_rtl, run_rtl, filelist_sources
from models.v4.lfsr_operator import indexed_sign
RUNS=[]
class SupportBuilderTests(unittest.TestCase):
    def test_live_cache_build_coordinate_replay(self):
        commands=[]
        reads=0
        def phi(m,n,seed): commands.append(f'0 {m} {n} {seed:x}')
        def build(m,n,support,scale=32768,key=123,gen=12,inject=0,fault=0,abort=0,count=None):
            packed=sum(col<<(10*i) for i,col in enumerate(support))
            commands.append(f'1 {m} {n} {len(support) if count is None else count} {packed:x} {scale:x} {key:x} {gen:x} {inject} {fault} {abort}')
        def check(m,support,scale,seed,transpose=False):
            nonlocal reads
            coords=((r,s) for s in range(len(support)) for r in range(m)) if transpose else ((r,s) for r in range(m) for s in range(len(support)))
            for r,s in coords:
                value=indexed_sign(seed,m,r,support[s])*scale
                commands.append(f'2 {r} {s} {value}'); reads+=1
        rng=random.Random(8821)
        for m,n,k,scale,seed in ((1,1,1,1,0),(7,19,7,131071,0xabcdef01),(33,101,33,32768,0x12345678),(65,129,17,65536,42),(128,1024,96,65535,13)):
            support=rng.sample(range(n),k)
            phi(m,n,seed); build(m,n,support,scale); check(m,support,scale,seed); check(m,support,scale,seed,True)
            # Rebuild in reversed support order to prove slots, key reuse and replacement.
            support.reverse(); build(m,n,support,scale); check(m,support,scale,seed,True)
        phi(33,17,9)
        for opts in (dict(scale=0),dict(scale=1<<17),dict(count=0),dict(count=97)):
            build(33,17,[0],fault=1,**opts)
        build(0,17,[0],fault=1); build(129,17,[0],fault=1); build(33,0,[0],fault=1); build(33,1025,[0],fault=1)
        build(33,17,[1,1],fault=2); build(33,17,[17],fault=2)
        for opts in (dict(key=124),dict(gen=13)):
            build(33,17,[1],fault=3,**opts)
        build(32,17,[1],fault=3); build(33,16,[1],fault=3)
        for inject in (1,2,4,8,64):
            build(33,17,[1],inject=inject,fault=4)
            build(33,17,[2]); check(33,[2],32768,9)
        build(33,17,[1],inject=16,fault=5)
        build(33,17,[1,2],inject=32,fault=5)
        build(33,17,[1,2],inject=128); check(33,[1,2],32768,9)
        build(33,17,[2]); check(33,[2],32768,9)
        for delay in (1,6,12,24,1000):
            for reset in (False,True):
                phi(65,17,9); build(65,17,[1,2,3,4],abort=-delay if reset else delay)
                phi(7,17,9); build(7,17,[3]); check(7,[3],32768,9)
        phi(33,17,9); commands.append('3')
        phi(1,1,9); build(1,1,[0]); check(1,[0],32768,9)
        with tempfile.TemporaryDirectory(prefix='builder_',dir=ROOT/'work') as folder:
            p=Path(folder); vec=p/'commands.txt'; sim=p/'builder.xsim.json'
            vec.write_text('\n'.join(commands)+'\n')
            logs=[]
            compiled=compile_rtl(sim,'tb_support_builder',filelist_sources(ROOT)+[ROOT/'verification/v4/memory/tb_support_builder.sv'],root=ROOT)
            logs.extend(compiled.commands)
            self.assertEqual(compiled.returncode,0,compiled.stdout+compiled.stderr)
            simulation=run_rtl(sim,['+src='+vec.as_posix()],root=ROOT)
            logs.extend(simulation.commands)
            self.assertEqual(simulation.returncode,0,simulation.stdout+simulation.stderr)
            output=simulation.stdout
            cycle_matches=re.findall(r'^PASS cycles=(\d+)$',output,re.M)
            self.assertEqual(len(cycle_matches),1,'missing or duplicate final cycle record')
            faults=[int(code) for code in re.findall(r'^BUILD fault=(\d+) ',output,re.M)]
            fault_totals={str(code):faults.count(code) for code in sorted(set(faults))}
            RUNS.append(dict(cycles=int(cycle_matches[0]),comparisons=reads,comparison_kind='coordinate checks',
                coordinate_reads=reads,completed_builds=len(faults),successful_builds=faults.count(0),
                faulted_builds=sum(code!=0 for code in faults),completion_fault_totals=fault_totals,
                reset_cancel_checks=len(re.findall(r'^ABORT ',output,re.M)),
                pending_identity_loss_checks=commands.count('3'),commands=len(commands),
                vector_sha256=hashlib.sha256(vec.read_bytes()).hexdigest(),runs=logs))
if __name__=='__main__': unittest.main()
