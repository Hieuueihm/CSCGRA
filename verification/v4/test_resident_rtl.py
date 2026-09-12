"""Real PC-driven GEMV: verified images, resident RTL memories, 32 PEs and sink retirement."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from compiler.v4.context_image import write_image
from compiler.v4.resident_program import descriptor, gemv
from models.v4.lfsr_operator import indexed_sign
from scripts.v4.export_control_stream import export_stream
from scripts.v4.generate_operator_defs import render
from scripts.v4.xsim import compile_rtl, run_rtl, filelist_sources

ROOT = Path(__file__).resolve().parents[2]
RUNS = []
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def signed(value, width): return value-(1 << width) if value >> (width-1) else value
def round_state(value): return (1 if value>=0 else -1)*((abs(value)+(1 << 15)) >> 16)

class ResidentRtlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='v4_resident_', dir=ROOT/'work')
        cls.path = Path(cls.temp.name)
        cls.binary = cls.path/'resident.xsim.json'
        run = compile_rtl(cls.binary, 'tb_resident_engine',
            filelist_sources(ROOT)+[ROOT/'verification/v4/control/tb_resident_engine.sv'], root=ROOT, timeout=300)
        cls.compile_result = run
        if run.returncode: raise AssertionError(run.stdout+run.stderr)

    @classmethod
    def tearDownClass(cls): cls.temp.cleanup()

    def case(self, rows=33, cols=35, mode=0, trans=0, base=7, bad=None, stride=1, address_mode='MATRIX', index=0, abort=0, corrupt=0):
        path = self.path/f'case_{len(RUNS)}'; path.mkdir()
        seed = 0x12345678
        values = dict(mode=mode, trans=trans, rows=rows, cols=cols, vec_base=base, vec_plane=0,
                      scale=32768, key=91, mat_generation=1, vec_generation=2, job=7, fmt=3)
        values.update(bad or {})
        (path/'desc.hex').write_text(f'{descriptor(**values):x}\n')
        program = gemv(rows, cols, mode, trans, index, stride, address_mode)
        manifest = write_image(program, path/'image')
        header = export_stream(path/'image', path/'stream', generation=123)
        plusargs = ['+stream='+(path/'stream/loader.txt').as_posix(),
            '+desc='+(path/'desc.hex').as_posix(), '+trace='+(path/'trace.txt').as_posix()]
        plusargs += [f'+{key}={value}' for key,value in dict(rows=rows,cols=cols,mode=mode,trans=trans,seed=seed,base=base,abort=abort,corrupt=corrupt).items()]
        run = run_rtl(self.binary, plusargs, root=ROOT, timeout=300)
        self.assertEqual(run.returncode, 0, run.stdout+run.stderr)
        self.assertIn('PASS accepted=',run.stdout)
        results = [{}, {}]; done = []
        for line in (path/'trace.txt').read_text().splitlines():
            parts=line.split()
            if parts[0]=='D': done.append(tuple(map(int,parts[1:])))
            else:
                _,run_id,tag,mask,indices,data=parts
                run_id=int(run_id); mask=int(mask,16); indices=int(indices,16); data=int(data,16)
                for lane in range(32):
                    if mask >> lane & 1:
                        output=indices >> (lane*11) & 2047
                        self.assertNotIn(output,results[run_id],f'duplicate candidate write output {output}')
                        results[run_id][output]=signed(data >> (lane*27) & ((1 << 27)-1),27)
        self.assertEqual(len(done),2)
        fault_expected = bool(bad) or bool(corrupt) or stride!=1 or address_mode!='MATRIX' or index!=0
        if fault_expected:
            self.assertTrue(all(row[1] != 0 for row in done),done)
            self.assertEqual(results,[{},{}])
            self.assertTrue(all(row[2]==2 and row[7]==0 for row in done),done)
        else:
            outputs,reductions=(cols,rows) if trans else (rows,cols)
            golden={}
            for output in range(outputs):
                acc=0
                for red in range(reductions):
                    row,col=(red,output) if trans else (output,red)
                    coefficient = row*101-col*53 if mode>=2 else indexed_sign(seed,rows,row,col)*32768
                    acc += coefficient*(10000-3*(base+red))
                golden[output]=round_state(acc)
            self.assertEqual(results,[golden,golden])
            self.assertTrue(all(row[1]==0 for row in done),done)
            expected_frames=((outputs+(7 if mode&1 else 31))//(8 if mode&1 else 32))*(((reductions+31)//32)*8 if mode&1 else reductions)
            self.assertTrue(all(row[7]==expected_frames for row in done),done)
        RUNS.append(dict(shape=[rows,cols],mode=mode,trans=trans,bad=bad,stride=stride,address_mode=address_mode,
            index=index,abort=abort,corrupt=corrupt,commands=self.compile_result.commands+run.commands,
            simulator="Vivado xsim",stdout=run.stdout,
            image_files=manifest['files'],verified_header=header,trace_sha256=digest(path/'trace.txt'),
            cycles=sum(row[3] for row in done), comparisons=sum(len(item) for item in results)+4,
            results_checked=sum(len(item) for item in results), comparison_kind='independent_coordinate_integer_GEMV_candidate_outputs_and_done_faults',
            source_request_stalls=sum(row[4] for row in done),result_stalls=sum(row[5] for row in done),
            completion_stalls=sum(row[6] for row in done), frame_issues=sum(row[7] for row in done), duplicate_candidate_writes=0,
            candidate_words=program.metadata['executable_words'], image_metadata=program.metadata, returncode=run.returncode, stderr=run.stderr,
            results_per_run=[len(item) for item in results],done=done))

    def test_generated_layout(self):
        self.assertEqual((ROOT/'rtl/v4/include/operator_defs.vh').read_text(),render())

    def test_live_phi_b_all_directions_tails_restart_and_stalls(self):
        for mode,trans in ((0,0),(1,1),(2,0),(2,1),(3,0),(3,1)):
            with self.subTest(mode=mode,trans=trans): self.case(mode=mode,trans=trans)

    def test_tiny_all_tail_r4_and_maximum_dimensions_compact_images(self):
        for mode,trans in ((0,0),(1,1),(2,0),(3,1)):
            with self.subTest(tiny=mode): self.case(rows=1,cols=1,mode=mode,trans=trans)
        self.case(rows=128,cols=1024,mode=1,trans=1)
        self.case(rows=128,cols=96,mode=3,trans=0)

    def test_descriptor_and_live_source_faults_do_not_store(self):
        for mode,trans in ((0,0),(2,0)):
            for bad in ({'key':92},{'mat_generation':9},{'vec_generation':9},{'job':8},{'fmt':4},{'vec_base':4095},{'vec_plane':3},{'rows':0},{'rows':32},{'cols':34}):
                with self.subTest(mode=mode,bad=bad): self.case(mode=mode,trans=trans,bad=bad)
        for stride in (0,-1,2,32767): self.case(stride=stride)
        self.case(address_mode='VECTOR')
        self.case(index=16)
        self.case(corrupt=1)
        self.case(mode=2,trans=0,corrupt=2)

    def test_cancel_and_reset_during_unjoined_reads_require_reload(self):
        self.case(abort=1)
        self.case(mode=3,trans=1,abort=2)

if __name__=='__main__': unittest.main()
