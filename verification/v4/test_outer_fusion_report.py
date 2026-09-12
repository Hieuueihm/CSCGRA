"""Negative guards for fusion acceptance and raw trace verification."""
from copy import deepcopy
from pathlib import Path
import unittest
from unittest.mock import patch
from scripts.v4 import report_outer_fusion as subject
from verification.v4.test_resident_chain_comparison import case

class OuterFusionReportTests(unittest.TestCase):
    def test_raw_signed_results_and_actual_outer(self):
        record = dict(rows=1,columns=1,job_cycles=100,output_raw_x_sha256=subject.raw_digest([1]),
                      output_raw_r_sha256=subject.raw_digest([-1]))
        text = 'X 1 0 0000001\nV 1 0 7ffffff\nD 1 0 0 1 1 8 1 100\nM 1 1 1 1 0 1 1 0 0 3\n'
        self.assertEqual(subject.trace_outputs(text,record)['vectors'],{'X':[1],'V':[-1]})
        for changed in (text.replace('0000001','0000002'),text.replace('1 8 1 100','1 7 1 100'),
                        text.replace('X 1 0','X 1 1'),text+text):
            with self.assertRaises(ValueError): subject.trace_outputs(changed,record)

    def fixture(self):
        baseline = {}
        for algorithm in subject.evidence.ACTIVE:
            current = case(algorithm,32)
            current.update(_artifacts={'load':'a'*64},_raw={'result':'same'},
                           _services={'KERNEL:13':{'calls':1,'clocks':4,'accepted_frames':0},
                                      'KERNEL:19':{'calls':0,'clocks':0,'accepted_frames':0},
                                      'BUILD:0':{'calls':0,'clocks':0,'accepted_frames':0},
                                      'KERNEL:0':{'calls':16,'clocks':32,'accepted_frames':32}},
                           fixture_non_job_cycles=32,cycles=1032,raw_setup_markers=[],retired_instructions=20)
            current['cycle_profile'].update(program_done_clock=990,result_drain_clocks=10,accepted_frames=32)
            current['cycle_profile']['service_totals'] = deepcopy(current['_services'])
            baseline[algorithm] = current
        candidate = deepcopy(baseline)
        changed = candidate['HTP']
        changed['_artifacts']['load'] = 'b'*64
        changed['job_cycles'] = 990
        changed['retired_instructions'] = 12
        changed['_services']['KERNEL:0'] = dict(calls=0,clocks=0,accepted_frames=0)
        changed['_services']['KERNEL:23'] = dict(calls=8,clocks=24,accepted_frames=32)
        changed['cycle_profile']['service_totals'] = deepcopy(changed['_services'])
        return baseline,candidate

    def compare(self,baseline,candidate,old_config=None,new_config=None):
        values = [(Path('before'),{}, {'rtl':'same'},old_config or {'outer_fusion':False},baseline),
                  (Path('after'),{}, {'rtl':'same'},new_config or {'outer_fusion':True},candidate)]
        with patch.object(subject,'load',side_effect=values),patch.object(subject.evidence,'digest',return_value='a'*64):
            return subject.compare('before','after',32)

    def test_exact_off_on_pair_accepted(self):
        result = self.compare(*self.fixture())
        self.assertEqual(result['status'],'PASS')
        self.assertEqual(len(result['cases']),10)

    def test_changed_outputs_policy_or_unrelated_cycles_rejected(self):
        for algorithm,key,value in (('HTP','_raw',{'result':'wrong'}),('HTP','policy',{'changed':True}),
                                    ('GP','job_cycles',1001),('HTP','job_cycles',1000),
                                    ('HTP','retired_instructions',13)):
            baseline,candidate = self.fixture()
            candidate[algorithm][key] = value
            with self.assertRaises(ValueError): self.compare(baseline,candidate)

    def test_changed_configuration_and_work_counts_rejected(self):
        baseline,candidate = self.fixture()
        with self.assertRaises(ValueError):
            self.compare(baseline,candidate,{'outer_fusion':False,'scale':1},{'outer_fusion':True,'scale':2})
        candidate['HTP']['_services']['KERNEL:23']['calls'] = 7
        with self.assertRaises(ValueError): self.compare(baseline,candidate)

if __name__=='__main__':
    unittest.main()
