import unittest
import hashlib
import json
from pathlib import Path
from collections import Counter
from copy import deepcopy
from unittest.mock import patch
import numpy as np
from compiler.v4.recovery_emit import MAPPING_CALIBRATION, Program
from models.v4.recovery import Policy
from compiler.v4.live_mapping import coefficient_address, frame_plan, frame_schedule, layout_descriptor
from compiler.v4.recovery_emit import mapping_selection, measured_mapping, validate_mapping_calibration

class LiveMappingTests(unittest.TestCase):
    def test_phi_addresses_and_tail(self):
        self.assertEqual(coefficient_address(128, 1024, 0, 0), dict(bank=0,address=0,bit=0,memory=0,port=0,physical_address=0))
        self.assertEqual(coefficient_address(128, 1024, 32, 8), dict(bank=0,address=5,bit=0,memory=0,port=0,physical_address=5))
        plan=frame_plan(33, 35,r4=True,transpose=True,output_base=0,reduction_base=0,step=0)
        self.assertTrue(plan['lane_mask'])
        self.assertTrue(any(lane['lane']==0 for lane in plan['lanes']))
        self.assertLess(len(list(frame_schedule(33,35,r4=True,transpose=True))), 1000)
    def test_dense_physical_pair_mapping(self):
        self.assertEqual(coefficient_address(64,24,1,0,True)['bank'],1)
        self.assertEqual(coefficient_address(64,24,1,0,True)['port'],0)
        self.assertEqual(coefficient_address(64,24,17,0,True)['port'],1)
        self.assertEqual(layout_descriptor(64,None,True)['width_source'],'runtime_support')
        self.assertEqual(coefficient_address(64,24,0,0,True)['physical_address'],0)
        self.assertEqual(coefficient_address(64,24,32,0,True)['physical_address'],32)
        self.assertEqual(coefficient_address(64,24,0,16,True)['bank'],16)
        self.assertEqual(coefficient_address(64,24,0,16,True)['port'],1)

    def test_phi_all_orientations_and_broadcasts(self):
        for transpose in (False, True):
            for r4 in (False, True):
                plan = frame_plan(64,256,r4=r4,transpose=transpose)
                self.assertEqual(plan['lane_mask'] != 0, True)
                self.assertEqual(sum(len(item['lanes']) for item in plan['requests']), len(plan['lanes']))
                self.assertGreaterEqual(plan['active_passes'], 1)
        plan = frame_plan(64,256,r4=False,transpose=False)
        self.assertTrue(any(len(item['lanes']) > 1 for item in plan['requests']))

    def test_dense_tails_and_runtime_width(self):
        for width in (1,2,7,8,16,24,31):
            plan = frame_plan(64,width,r4=True,dense=True,output_base=0,reduction_base=0,step=0)
            self.assertGreater(plan['lane_mask'], 0)
            self.assertLessEqual(len(plan['lanes']), 32)
        self.assertEqual(len(list(frame_schedule(64,24,r4=True,dense=True))), 64)

    def test_calibration_selection_and_stale_guard(self):
        validate_mapping_calibration()
        self.assertEqual(measured_mapping(32,64,False,False), {'R1':96,'R4':298})
        self.assertEqual(mapping_selection(32,64)['r4'], False)
        self.assertEqual(mapping_selection(32,64,True)['r4'], True)
        self.assertEqual(mapping_selection(32,64,r4=True)['selection'], 'explicit_ablation_override')
        self.assertEqual(mapping_selection(32,64,dense=True)['selection'], 'legacy_estimate_unqualified_fallback')
        self.assertEqual(mapping_selection(32,64,dense=True,support_columns=8)['r4'], False)
        with self.assertRaises(ValueError): mapping_selection(32,64,dense=True,support_columns=0)

    def test_calibration_matches_archived_xsim_evidence(self):
        root = Path(__file__).resolve().parents[2]
        payload = (root / MAPPING_CALIBRATION['measurement_source']).read_bytes()
        self.assertEqual(hashlib.sha256(payload).hexdigest(),MAPPING_CALIBRATION['measurement_sha256'])
        evidence = json.loads(payload)
        self.assertEqual(evidence['status'],'PASS')
        self.assertEqual(sum(record['commands_executed'] for record in evidence['records']),40)
        measured = {}
        for record in evidence['records']:
            self.assertEqual(record['status'],'PASS')
            if not record['test'].endswith('test_exact_live_phi_and_restricted_dense_measurements'):
                continue
            for command in record['per_command']:
                key = json.dumps(command['shape'],sort_keys=True)
                measured.setdefault(key,{})[command['mapping']] = command['cycles']
        self.assertEqual(len(MAPPING_CALIBRATION['entries']),16)
        for entry in MAPPING_CALIBRATION['entries']:
            self.assertEqual(entry['cycles'],measured[json.dumps(entry['shape'],sort_keys=True)])
    def test_modes_and_conflicts_reject(self):
        self.assertEqual(frame_plan(64,256,r4=False,transpose=False)['active_passes'],1)
        with self.assertRaises(ValueError): frame_plan(64,256,r4=True,transpose=True,output_base=1)
        with self.assertRaises(ValueError): frame_plan(64,256,r4=True,transpose=False,reduction_base=1)
        with self.assertRaises(ValueError): coefficient_address(64,24,64,0,True)

    def test_complete_coefficient_coverage(self):
        for dense in (False, True):
            for rows, columns in ((1,1), (3,5), (33,35), (64,24), (128,96)):
                expected = Counter((row,column) for row in range(rows) for column in range(columns))
                for r4 in (False, True):
                    for transpose in (False, True):
                        with self.subTest(dense=dense, rows=rows, columns=columns, r4=r4, transpose=transpose):
                            actual = Counter()
                            for frame in frame_schedule(rows,columns,r4=r4,transpose=transpose,dense=dense):
                                actual.update((lane['row'],lane['column']) for lane in frame['lanes'])
                                self.assertEqual(frame['lane_mask'],sum(1 << lane['lane'] for lane in frame['lanes']))
                            self.assertEqual(actual, expected)

    def test_physical_storage_is_injective_at_maximum_shape(self):
        for dense, columns in ((False,1024), (True,96)):
            locations = set()
            for row in range(128):
                for column in range(columns):
                    address = coefficient_address(128,columns,row,column,dense)
                    locations.add((address['memory'],address['physical_address'],address['bit']))
                    self.assertLess(address['address'],512)
                    self.assertLess(address['physical_address'],1024 if dense else 512)
            self.assertEqual(len(locations),128*columns)

    def test_invalid_shapes_types_and_empty_tail_step(self):
        for rows, columns, dense in ((True,8,False),(0,8,False),(129,8,False),(32,1025,False),
                                     (32,97,True),(32,None,False),(32,8,1)):
            with self.subTest(rows=rows, columns=columns, dense=dense):
                with self.assertRaises(ValueError): layout_descriptor(rows,columns,dense)
        with self.assertRaises(ValueError): layout_descriptor(32,None,1)
        with self.assertRaises(ValueError): frame_plan(32,64,r4=1)
        with self.assertRaises(ValueError): frame_plan(32,64,r4=True,transpose=1)
        with self.assertRaises(ValueError): frame_plan(32,64,r4=False,step=1)
        self.assertEqual(frame_plan(32,1,r4=True,step=7)['lane_mask'],0)
        self.assertGreater(frame_plan(32,64,r4=False,reduction_base=1)['lane_mask'],0)

    def test_conflicting_requests_are_rejected(self):
        def conflict(rows, columns, row, column, dense):
            return dict(bank=0,address=row,bit=0,memory=0,port=0,physical_address=row)
        with patch('compiler.v4.live_mapping.coefficient_address',side_effect=conflict):
            with self.assertRaisesRegex(ValueError,'same bank'):
                frame_plan(32,64,r4=False)

    def test_stale_profile_rejected_but_explicit_override_available(self):
        stale = deepcopy(MAPPING_CALIBRATION)
        name = next(iter(stale['source_sha256']))
        stale['source_sha256'][name] = '0'*64
        with patch('compiler.v4.recovery_emit.MAPPING_CALIBRATION',stale):
            with self.assertRaisesRegex(ValueError,'stale GEMV'):
                mapping_selection(32,64)
            self.assertTrue(mapping_selection(32,64,r4=True)['r4'])
        invalid = deepcopy(MAPPING_CALIBRATION)
        invalid['entries'].append(invalid['entries'][0])
        with self.assertRaisesRegex(ValueError,'duplicate shape'):
            validate_mapping_calibration(invalid)
        with patch('compiler.v4.recovery_emit.measured_mapping',return_value={'R1':10,'R4':10}):
            self.assertFalse(mapping_selection(32,64)['r4'])

    def test_program_metadata_preserves_runtime_support_width(self):
        program = Program('IHT',np.full((32,64),1/1024),Policy(8,max_iterations=8),None)
        program.call('GEMV','X','X',dense=1,support_length_s=28,template='gemv')
        decision = program.mappings[-1]
        self.assertIsNone(decision['bank_layout']['columns'])
        self.assertEqual(decision['bank_layout']['support_length_register'],28)
        self.assertEqual(decision['calibration']['reason'],'runtime_dynamic_restricted_dense_width')
        program.mv('X','X',True)
        self.assertEqual(program.mappings[-1]['bank_layout']['rows'],32)
        self.assertEqual(program.mappings[-1]['bank_layout']['columns'],64)
        self.assertFalse(program.mappings[-1]['bank_layout']['transpose_repacking'])

if __name__=='__main__': unittest.main()
