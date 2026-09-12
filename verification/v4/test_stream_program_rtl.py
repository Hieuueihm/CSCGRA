"""Stream package/compiler and control-leaf tests; RTL uses actual Vivado xsim."""
import hashlib
import json
from pathlib import Path
import random
import re
import tempfile
import unittest

from compiler.v4 import stream_program as compiler
from scripts.v4.generate_stream_interface import ROOT, render
from scripts.v4.xsim import compile_rtl, run_rtl

RUNS = []
IMAGES = []
SOURCES = ['rtl/v4/control/stream_program_control.sv',
           'verification/v4/stream/tb_stream_program_control.sv']


def package(template_count=3, calls=6):
    templates = []
    for tid in range(template_count):
        output = tid % 3
        contexts = [compiler.encode_context(op=('MOV','ADD','SUB','MUL')[lane%4] if output==0 else 'MAC',
                    mode=lane%2, src_a=lane%4, src_b=(lane+1)%4,
                    immediate=-(1<<26) if lane==0 else (1<<26)-1 if lane==31 else lane-15)
                    for lane in range(32)]
        templates.append({'descriptor': compiler.encode_descriptor(inc_a=1,inc_b=tid%2,inc_dst=1,
                            output_kind=output,shift=22 if output==1 else 0), 'contexts':contexts})
    rng = random.Random(923)
    program = [compiler.encode_program(kind='CALL',template=i%template_count,src_a=rng.randrange(100),
                 src_b=rng.randrange(100,200),dst=rng.randrange(200,300),frame_count=1+i%32,
                 tail_mask=(1<<(1+i%32))-1) for i in range(calls)]
    program.append(compiler.encode_program(kind='HALT'))
    return compiler.build_package(program,templates)


class StreamCompilerTests(unittest.TestCase):
    def test_generated_header_matches_authority(self):
        self.assertEqual((ROOT/'rtl/v4/include/stream_interface.vh').read_text(),render())

    def test_roundtrip_export_and_signed_contexts(self):
        data=package(16,255)
        for word in data['program']:
            self.assertEqual(compiler.encode_program(**compiler.decode_program(word)),word)
        for template in data['templates']:
            for word in template['contexts']:
                self.assertEqual(compiler.encode_context(**compiler.decode_context(word)),word)
        with tempfile.TemporaryDirectory(dir=ROOT/'work',prefix='stream_export_') as directory:
            metadata=compiler.export_package(data,directory)
            path=Path(directory)
            self.assertEqual([int(w,16) for w in (path/'program.hex').read_text().split()],data['program'])
            self.assertEqual(len((path/'templates.hex').read_text().split()),16*33)
            self.assertIn('PE31:',(path/'program.txt').read_text())
            self.assertEqual(metadata['program_count'],256)
            self.assertEqual(metadata['template_count'],16)
            self.assertEqual(len(metadata['image_sha256']),64)
            self.assertEqual(json.loads((path/'package.json').read_text())['source_hashes'],metadata['source_hashes'])

    def test_reject_invalid_modes_references_ranges(self):
        for fields in [dict(kind='HALT',dst=1),dict(kind='CALL',frame_count=33,tail_mask=1),
                       dict(kind='CALL',frame_count=1,tail_mask=0),dict(kind=3)]:
            with self.assertRaises(ValueError):compiler.encode_program(**fields)
        for output in ['EACH','SUM_ACC']:
            with self.assertRaises(ValueError):compiler.encode_descriptor(output_kind=output,shift=1)
        with self.assertRaises(ValueError):compiler.encode_context(op='MOV',immediate=1<<26)
        data=package();data['program'][0]=compiler.encode_program(kind='CALL',template=15,frame_count=1,tail_mask=1)
        with self.assertRaises(ValueError):compiler.validate_package(data)
        data=package();data['program'][0]=compiler.encode_program(kind='CALL',src_a=479,frame_count=2,tail_mask=1)
        with self.assertRaises(ValueError):compiler.validate_package(data)
        data=package();data['templates'][0]['contexts'][31]=compiler.encode_context(op='MAC')
        with self.assertRaises(ValueError):compiler.validate_package(data)
        data=package();data['templates'][1]['contexts'].pop()
        with self.assertRaises(ValueError):compiler.validate_package(data)


class StreamProgramRtlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary=tempfile.TemporaryDirectory(dir=ROOT/'work',prefix='stream_control_')
        cls.path=Path(cls.temporary.name)
        cls.binary=cls.path/'control.xsim.json'
        cls.compiled=compile_rtl(cls.binary,'tb_stream_program_control',[ROOT/s for s in SOURCES],root=ROOT)
        if cls.compiled.returncode:raise AssertionError(cls.compiled.stdout+cls.compiled.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def case(self,mode=0,expected=0,data=None):
        data=package() if data is None else data
        path=self.path/f'case{len(RUNS)}';path.mkdir()
        program=data['program'];templates=[w for t in data['templates'] for w in [t['descriptor'],*t['contexts']]]
        (path/'program.hex').write_text(''.join(f'{w:032x}\n' for w in program))
        (path/'templates.hex').write_text(''.join(f'{w:016x}\n' for w in templates))
        args=[f'program={(path/"program.hex").as_posix()}',f'templates={(path/"templates.hex").as_posix()}',
              f'pcount={len(program)}',f'tcount={len(data["templates"])}',f'mode={mode}',f'expected={expected}']
        result=run_rtl(self.binary,args,root=ROOT)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        match=re.search(r'PASS checks=(\d+) cycles=(\d+) commands=(\d+)',result.stdout)
        self.assertIsNotNone(match,result.stdout)
        checks,cycles,commands=map(int,match.groups());self.assertGreater(checks,0)
        identity={str(p.relative_to(ROOT)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in [*[ROOT/s for s in SOURCES],ROOT/'rtl/v4/include/stream_interface.vh',
                            ROOT/'config/v4_stream_interface.json',Path(compiler.__file__)]}
        RUNS.append(dict(test=self.id(),status='PASS',stdout=result.stdout,stderr=result.stderr,
                         compile_stdout=self.compiled.stdout,compile_stderr=self.compiled.stderr,
                         mode=mode,expected_fault=expected,checks=checks,cycles=cycles,call_commands=commands,
                         comparison_kind='control protocol and decoded fields',source_hashes=identity,
                         commands=[*self.compiled.commands,*result.commands]))
        IMAGES.append(dict(program_count=len(program),template_count=len(data['templates']),
                           program_sha256=hashlib.sha256((path/'program.hex').read_bytes()).hexdigest(),
                           template_sha256=hashlib.sha256((path/'templates.hex').read_bytes()).hexdigest()))

    def test_distinct_contexts_and_maximum_package(self):
        self.case();self.case(data=package(16,255));self.case(data=package(1,0))

    def test_loader_order_revision_verified_and_last(self):
        for mode in [1,2,3,4,5,6,18]:
            with self.subTest(mode=mode):self.case(mode,1)

    def test_invalid_context_descriptor_and_template_reference(self):
        data=package();data['templates'][0]['contexts'][31]|=1<<63;self.case(15,1,data)
        data=package();data['templates'][0]['contexts'][31]=compiler.encode_context(op='MAC');self.case(15,1,data)
        data=package();data['templates'][0]['descriptor']|=1<<31;self.case(16,1,data)
        data=package();data['program'][0]=compiler.encode_program(kind='CALL',template=15,frame_count=1,tail_mask=1);self.case(17,1,data)

    def test_cancel_load_command_done_and_reset(self):
        for mode in [7,8,9]:
            with self.subTest(mode=mode):self.case(mode)

    def test_runtime_fault_identity_and_format(self):
        self.case(10,6);self.case(11,5);self.case(14,7)
        data=package();data['program'][0]=compiler.encode_program(kind='CALL',src_a=479,frame_count=2,tail_mask=1)
        self.case(12,4,data)
        data=package(1,1);data['program'].pop();self.case(13,3,data)


if __name__=='__main__':
    unittest.main()
