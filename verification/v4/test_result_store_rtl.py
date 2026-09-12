"""Transactional result RAM: embeddings, inactive-bank ownership and abort in Vivado."""
import json
from pathlib import Path
import re
import tempfile
import unittest
from scripts.v4.xsim import compile_rtl,run_rtl

ROOT=Path(__file__).resolve().parents[2]
RUNS=[]


class ResultStoreRtlTests(unittest.TestCase):
    def test_serialized_double_bank_publication_and_faults(self):
        path=Path(tempfile.mkdtemp(prefix='result_store_',dir=ROOT/'work'))
        binary=path/'result.xsim.json'
        compiled=compile_rtl(binary,'tb_result_store',[ROOT/'rtl/v4/memory/result_store.sv',ROOT/'verification/v4/stream/tb_result_store.sv'],root=ROOT,timeout=300)
        self.assertEqual(compiled.returncode,0,compiled.stdout+compiled.stderr)
        result=run_rtl(binary,[],root=ROOT,timeout=300)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        match=re.search(r'PASS cycles=(\d+) checks=(\d+)',result.stdout)
        self.assertIsNotNone(match,result.stdout)
        cycles,checks=map(int,match.groups())
        RUNS.append(dict(cycles=cycles,comparisons=checks,comparison_kind='real_1024_word_banked_result_RAM_exact_values_metadata_and_transaction_assertions',
            simulator='Vivado xsim',commands=compiled.commands+result.commands,returncode=result.returncode,stdout=result.stdout))
        (path/'evidence.json').write_text(json.dumps(RUNS,indent=2))


if __name__=='__main__':unittest.main()
