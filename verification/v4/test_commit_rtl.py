"""Transactional stored-X result publication, compared with an independent list oracle."""
import hashlib
import json
import os
from pathlib import Path
import random
import shutil
import tempfile
import unittest
from scripts.v4.generate_commit_interface import ROOT,render
from scripts.v4.xsim import compile_rtl,run_rtl
IO=json.loads((ROOT/'verification/v4/commit/io.json').read_text())
RUNS=[]
def pack(values,width):return sum((int(v)&((1<<width)-1))<<(i*width) for i,v in enumerate(values))
def signed(v,width):return v-(1<<width) if v&(1<<(width-1)) else v

class Oracle:
    def __init__(self):
        self.candidate=None;self.committed=None;self.status=None;self.response=None
    def outputs(self,p):
        active=not(p['rst'] or p['cancel'])
        out=dict.fromkeys(IO['outputs'],0)
        out.update(begin_ready=int(active and self.candidate is None and self.status is None),
            decision_ready=int(active and self.candidate is not None and self.status is None and self.candidate['check']==96),
            fill_ready=int(active and self.candidate is not None and self.status is None and self.candidate['check']==96 and not p['decision_valid']),
            status_valid=int(active and self.status is not None),
            committed_valid=int(self.committed is not None),read_ready=int(active and self.response is None),
            rsp_valid=int(active and self.response is not None))
        if self.status:out.update(self.status)
        if self.response:out.update(self.response)
        if self.committed:out.update(committed_count=self.committed['count'],committed_rows=self.committed['rows'])
        return [out[k]&((1<<w)-1) for k,w in IO['outputs'].items()]
    def finish(self,metadata,fault):
        self.status=dict(status_fault=fault,status_committed=int(fault==0),
            status_job=metadata['job'],status_tag=metadata['tag'],status_fmt=metadata['fmt'])
        self.candidate=None
    def tick(self,p):
        if p['rst']:
            self.__init__();return
        if p['cancel']:
            if self.candidate is not None:self.finish(self.candidate,7)
            self.response=None;return
        before=dict(zip(IO['outputs'],self.outputs(p)))
        # Read observes the committed pointer at edge entry, including a concurrent publish.
        if p['read_valid'] and before['read_ready']:
            self.response=dict(rsp_x=0,rsp_index=0,rsp_exponent=0,rsp_job=0,rsp_tag=0,rsp_fmt=0,rsp_fault=8)
            if self.committed is not None and p['read_slot']<self.committed['count']:
                c=self.committed;slot=p['read_slot']
                self.response.update(rsp_x=c['x'][slot],rsp_index=c['support'][slot],rsp_exponent=c['exponent'],
                    rsp_job=c['job'],rsp_tag=c['tag'],rsp_fmt=c['fmt'],rsp_fault=0)
        elif self.response is not None and p['rsp_ready']:self.response=None
        if self.status is not None and p['status_ready']:self.status=None
        if self.candidate is not None and self.candidate['check']<96:
            c=self.candidate;slot=c['check'];index=c['support'][slot]
            if (slot<c['count'] and index in c['support'][:slot]) or (slot>=c['count'] and index!=0):self.finish(c,2)
            else:c['check']+=1
        if p['begin_valid'] and before['begin_ready']:
            support=[(p['begin_support']>>(10*i))&1023 for i in range(96)]
            c=dict(rows=p['begin_rows'],count=p['begin_count'],support=support,
                job=p['begin_job'],tag=p['begin_tag'],fmt=p['begin_fmt'],
                exponent=signed(p['begin_exponent']&127,7),x=[],block=0,check=0)
            if not(1<=c['rows']<=128 and c['count']<=96 and c['fmt']==1 and -31<=c['exponent']<=31):self.finish(c,1)
            else:self.candidate=c
        if p['decision_valid'] and before['decision_ready']:
            c=self.candidate
            if any(p['decision_'+k]!=c[k] for k in ('job','tag','fmt')):fault=3
            elif len(c['x'])!=c['count']:fault=4
            elif not p['decision_approve']:fault=6
            else:fault=0
            if not fault:self.committed=dict(c,x=list(c['x']))
            self.finish(c,fault)
        elif p['fill_valid'] and before['fill_ready']:
            c=self.candidate;remaining=c['count']-len(c['x']);lanes=min(32,remaining)
            values=[signed((p['fill_data']>>(i*27))&((1<<27)-1),27) for i in range(32)]
            if any(p['fill_'+k]!=c[k] for k in ('job','tag','fmt')):fault=3
            elif remaining==0 or p['fill_block']!=c['block'] or p['fill_mask']!=(1<<lanes)-1 or p['fill_last']!=int(remaining<=32) or any(values[lanes:]):fault=4
            elif any(v%4 or not -(1<<23)<=v//4<(1<<23) for v in values[:lanes]):fault=5
            else:fault=0
            if fault:self.finish(c,fault)
            else:c['x'].extend(v//4 for v in values[:lanes]);c['block']+=1

class Replay:
    def __init__(self):self.model=Oracle();self.rows=[];self.expected=[];self.step(rst=1)
    def step(self,**fields):
        p=dict.fromkeys(IO['inputs'],0);p.update(begin_fmt=1,fill_fmt=1,decision_fmt=1);p.update(fields)
        self.rows.append(' '.join(f'{p[k]&((1<<w)-1):x}' for k,w in IO['inputs'].items()))
        self.expected.append(None if len(self.rows)==1 else self.model.outputs(p))
        self.model.tick(p);self.expected.append(self.model.outputs(p))
    def begin(self,values,support=None,**extra):
        support=list(range(len(values))) if support is None else support
        self.step(begin_valid=1,begin_rows=128,begin_count=len(values),begin_support=pack(support,10),**extra)
        for _ in range(96):self.step()
    def fill(self,values,**extra):
        for block in range((len(values)+31)//32):
            chunk=values[block*32:(block+1)*32]
            fields=dict(fill_valid=1,fill_block=block,fill_data=pack(chunk,27),fill_mask=(1<<len(chunk))-1,fill_last=int((block+1)*32>=len(values)))
            fields.update(extra);self.step(**fields)
    def decision(self,**extra):
        fields=dict(decision_valid=1,decision_approve=1);fields.update(extra);self.step(**fields)
    def drain(self):self.step(status_ready=1,rsp_ready=1)
    def read(self,slot,stall=1):
        self.step(read_valid=1,read_slot=slot)
        for i in range(stall):self.step(read_valid=1,read_slot=127-i)
        self.step(rsp_ready=1,read_valid=1,read_slot=127)
    def run(self,test):
        (ROOT/'work').mkdir(exist_ok=True)
        folder=Path(tempfile.mkdtemp(prefix='commit_',dir=ROOT/'work'))
        try:
            vec=folder/'vectors.txt';trace=folder/'trace.txt';image=folder/'commit.xsim.json'
            vec.write_text('\n'.join(self.rows)+'\n')
            compiled=compile_rtl(image,'tb_commit_controller',[
                ROOT/'rtl/v4/dataflow/result_writeback.sv',ROOT/'rtl/v4/control/commit_controller.sv',
                ROOT/'verification/v4/commit/tb_commit_controller.sv'],root=ROOT)
            test.assertEqual(compiled.returncode,0,compiled.stdout+compiled.stderr)
            sim=run_rtl(image,['+src='+vec.as_posix(),'+dst='+trace.as_posix()],root=ROOT)
            test.assertEqual(sim.returncode,0,sim.stdout+sim.stderr);test.assertIn('PASS cycles=',sim.stdout)
            lines=trace.read_text().splitlines();test.assertEqual(len(lines),len(self.expected))
            for index,(line,expected) in enumerate(zip(lines,self.expected)):
                row=line.split();test.assertEqual([int(v) for v in row[:2]],[index//2,index%2])
                if expected is not None:test.assertEqual([int(v,16) for v in row[2:]],expected,f'cycle{index//2}phase{index%2}')
            RUNS.append(dict(test=test.id(),cycles=len(self.rows),comparisons=(len(self.expected)-1)*len(IO['outputs']),
                vector_sha256=hashlib.sha256(vec.read_bytes()).hexdigest(),trace_sha256=hashlib.sha256(trace.read_bytes()).hexdigest(),commands=compiled.commands+sim.commands))
        finally:
            if not os.environ.get('V4_COMMIT_KEEP'):shutil.rmtree(folder)

class CommitTests(unittest.TestCase):
    def test_generated_contract(self):self.assertEqual((ROOT/'rtl/v4/include/commit_interface.vh').read_text(),render())
    def test_transactions_faults_and_snapshot_reads(self):
        r=Replay();rng=random.Random(9781)
        r.read(0)
        for count in (0,1,31,32,33,64,65,95,96):
            values=[rng.randrange(-(1<<23),1<<23)*4 for _ in range(count)]
            support=rng.sample(range(1024),count)
            job=count+17;tag=count+300
            r.begin(values,support,begin_job=job,begin_tag=tag,begin_exponent=-31 if count&1 else 31)
            # Held begin cannot replace metadata; read while candidate is unfinished sees old commit.
            r.step(begin_valid=1,begin_rows=0,begin_job=65535)
            r.fill(values,fill_job=job,fill_tag=tag)
            r.step(read_valid=1,read_slot=0)
            r.decision(decision_job=job,decision_tag=tag)
            for _ in range(3):r.step(begin_valid=1,decision_valid=1,fill_valid=1)
            r.drain()
            for slot in range(count):r.read(slot,stall=rng.randrange(3))
            r.read(count)
        # Valid old result must survive every subsequent job failure.
        for bad in (dict(begin_rows=0),dict(begin_rows=129),dict(begin_count=97),dict(begin_fmt=2),
                    dict(begin_exponent=-32),dict(begin_exponent=32),dict(begin_support=pack([1,1],10)),
                    dict(begin_support=pack([1,2,3],10))):
            fields=dict(begin_valid=1,begin_rows=128,begin_count=2,begin_support=pack([1,2],10));fields.update(bad)
            r.step(**fields)
            for _ in range(96):r.step()
            r.drain();r.read(0)
        for bad in (dict(fill_block=1),dict(fill_mask=0),dict(fill_mask=3),dict(fill_last=0),
                    dict(fill_job=1),dict(fill_tag=1),dict(fill_fmt=2),dict(fill_data=1),
                    dict(fill_data=33554432),dict(fill_data=pack([-33554436],27)),dict(fill_data=pack([4,4],27)),
                    dict(fill_data=pack([1,4],27)),dict(fill_data=pack([-33554433],27))):
            r.begin([4]);fields=dict(fill_valid=1,fill_block=0,fill_mask=1,fill_last=1,fill_data=4);fields.update(bad)
            r.step(**fields)
            for _ in range(96):r.step()
            r.drain();r.read(0)
        for bad in (dict(decision_approve=0),dict(decision_job=1),dict(decision_tag=1),dict(decision_fmt=2)):
            r.begin([4]);r.fill([4]);r.decision(**bad);r.drain();r.read(0)
        r.begin([4]);r.decision();r.drain();r.read(0)
        r.begin([4]);r.fill([4]);r.fill([8]);r.drain();r.read(0)
        # Cancel on every side of the final fill and decision, with competing ready/valid.
        for delay in range(5):
            r.begin([4]*33)
            sequence=[dict(fill_valid=1,fill_block=0,fill_mask=(1<<32)-1,fill_data=pack([4]*32,27)),
                      dict(fill_valid=1,fill_block=1,fill_mask=1,fill_data=4,fill_last=1),
                      dict(decision_valid=1,decision_approve=1),{},{}]
            for i,pins in enumerate(sequence):r.step(**pins,cancel=int(i==delay),status_ready=int(i==delay))
            r.drain();r.read(0)
        for support in (list(range(95))+[0], list(range(95))+[94]):
            r.begin([4]*96,support);r.drain();r.read(0)
        for delay in (0,1,47,95):
            r.step(begin_valid=1,begin_rows=128,begin_count=1)
            for _ in range(delay):r.step(fill_valid=1,decision_valid=1)
            r.step(cancel=1,fill_valid=1,decision_valid=1)
            r.drain();r.read(0)
        # Boundary X values and read snapshot survive publish plus reuse of the old bank.
        r.begin([-33554432,33554428]);r.fill([-33554432,33554428]);r.decision();r.drain()
        r.step(read_valid=1,read_slot=0)
        for value in (16,20):
            r.begin([value]);r.fill([value]);r.decision();r.step(status_ready=1)
        r.step();r.step(rsp_ready=1);r.read(0)
        r.step(rst=1,begin_valid=1,read_valid=1);r.read(0)
        r.begin([]);r.decision();r.drain();r.read(0)
        for phase in range(4):
            r.begin([4]);r.fill([4]);r.decision();r.drain()
            r.begin([8])
            if phase>=1:r.fill([8])
            if phase>=2:r.decision()
            if phase>=3:r.step(read_valid=1,read_slot=0)
            r.step(rst=1,fill_valid=1,decision_valid=1,status_ready=1,rsp_ready=1)
            r.read(0);r.begin([]);r.decision();r.drain()
        r.run(self)
if __name__=='__main__':unittest.main()
