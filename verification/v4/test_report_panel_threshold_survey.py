import copy
import hashlib
import json
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from scripts.v4 import report_panel_threshold_survey as survey

class SurveyTests(unittest.TestCase):
    def real_archive(self):
        path=Path('D:/vivado_pj/reports/v4/context_stream_quick_m32_20260910/summary.json')
        if not path.is_file(): self.skipTest('real source-clean archive unavailable')
        return path

    def make_qr_fixture(self, root, name, threshold):
        """Copy real bytes, then make a self-consistent synthetic QR archive."""
        source_summary=self.real_archive()
        archive=Path(root)/name
        shutil.copytree(source_summary.parent,archive)
        summary_path=archive/'summary.json'
        summary=json.loads(summary_path.read_text(encoding='utf-8'))
        config=summary['config']
        config['report_name']=f'synthetic_threshold_{name}'
        config['qr_profile']='view'
        config['qr_panel_min_columns']=threshold
        config['algorithms']=list(survey.QR)
        summary['cases']=[case for case in summary['cases'] if case['algorithm'] in survey.QR]
        frozen=archive/'source_snapshot'/'benchmark_config.json'
        frozen.write_text(json.dumps(config,indent=2)+'\n',encoding='utf-8')
        summary['source_sha256']['benchmark_config.json']=hashlib.sha256(frozen.read_bytes()).hexdigest()
        summary_path.write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
        return summary_path

    def test_real_artifact_qr_subset_loader_and_negative_cases(self):
        source_path=self.real_archive()
        # The active-10 default remains strict on the untouched archive.
        active_summary=survey.base.read_summary(source_path)[1]
        active_cases,_,_=survey.base.load_cases(active_summary,source_path,32,'real active default')
        self.assertEqual(set(active_cases),set(survey.base.ACTIVE))
        with tempfile.TemporaryDirectory() as temporary:
            before_path=self.make_qr_fixture(temporary,'before',1)
            after_path=self.make_qr_fixture(temporary,'after',8)
            before=survey.base.read_summary(before_path)[1]
            cases,config,sources=survey.base.load_cases(before,before_path,32,'synthetic QR subset',survey.QR)
            self.assertEqual(set(cases),set(survey.QR));self.assertTrue(sources);self.assertEqual(config['algorithms'],list(survey.QR))
            # This successful path uses both real loaders and copied/rehashed
            # source, fixture, trace, package, and load artifacts.  Its inputs
            # are synthetic and are never a measured survey result.
            result=survey.survey_pair(before_path.parent,after_path.parent,32)
            self.assertEqual((result['threshold_before'],result['threshold_after']),(1,8))
            duplicate=copy.deepcopy(before);duplicate['cases'].append(copy.deepcopy(duplicate['cases'][0]))
            missing=copy.deepcopy(before);missing['cases'].pop()
            raw=copy.deepcopy(before);raw['cases'][0]['raw_phi_sha256']='0'*64
            outer=copy.deepcopy(before);outer['cases'][0]['outer_iterations']=7
            policy_missing=copy.deepcopy(before);policy_missing['cases'][0].pop('policy')
            policy_empty=copy.deepcopy(before);policy_empty['cases'][0]['policy']={}
            for bad in (duplicate,missing,raw,outer,policy_missing,policy_empty):
                with self.assertRaises(survey.base.ValidationError):
                    survey.base.load_cases(bad,before_path,32,'bad QR subset',survey.QR)
            source_bad=copy.deepcopy(before)
            source_name=next(iter(source_bad['source_sha256']))
            source_bad['source_sha256'][source_name]='0'*64
            with self.assertRaises(survey.base.ValidationError):
                survey.base.load_cases(source_bad,before_path,32,'source-byte mismatch',survey.QR)
            summary_only=copy.deepcopy(before)
            summary_only['config']['qr_panel_min_columns']=4
            with self.assertRaisesRegex(survey.base.ValidationError,'summary config differs'):
                survey.base.load_cases(summary_only,before_path,32,'summary-only config',survey.QR)
            changed=copy.deepcopy(cases['OMP']);changed['policy']={'changed':True}
            with self.assertRaises(survey.base.ValidationError):
                survey.base.compare_case(cases['OMP'],changed,32,'OMP',frozenset(survey.QR))
    def test_source_difference_rejected(self):
        with self.assertRaisesRegex(survey.ValidationError,'source snapshot'):
            survey._sources_equal({'a':'1'*64},{'a':'2'*64},'x')

    def test_requires_view_and_threshold_difference(self):
        summary=dict(status='PASS')
        cases={a:dict(algorithm=a) for a in survey.QR}
        cfg=dict(qr_profile='streamed',qr_panel_min_columns=8)
        with patch.object(survey.base,'read_summary',side_effect=[('a',summary),('b',summary)]),\
             patch.object(survey.base,'load_cases',side_effect=[(cases,cfg,{'s':'x'}),(cases,cfg,{'s':'x'})]),\
             patch.object(survey.base,'compare_config'):
            with self.assertRaisesRegex(survey.ValidationError,'qr_profile=view'):
                survey.survey_pair('a','b',32)
        cfg=dict(qr_profile='view',qr_panel_min_columns=8)
        with patch.object(survey.base,'read_summary',side_effect=[('a',summary),('b',summary)]),\
             patch.object(survey.base,'load_cases',side_effect=[(cases,cfg,{'s':'x'}),(cases,cfg,{'s':'x'})]),\
             patch.object(survey.base,'compare_config'):
            with self.assertRaisesRegex(survey.ValidationError,'thresholds must differ'):
                survey.survey_pair('a','b',32)
        for invalid in (0,97,True,'8'):
            before=dict(qr_profile='view',qr_panel_min_columns=invalid)
            after=dict(qr_profile='view',qr_panel_min_columns=2)
            with patch.object(survey.base,'read_summary',side_effect=[('a',summary),('b',summary)]),\
                 patch.object(survey.base,'load_cases',side_effect=[(cases,before,{'s':'x'}),(cases,after,{'s':'x'})]),\
                 patch.object(survey.base,'compare_config'):
                with self.assertRaisesRegex(survey.ValidationError,'integer in1..96'):
                    survey.survey_pair('a','b',32)

if __name__=='__main__':unittest.main()
