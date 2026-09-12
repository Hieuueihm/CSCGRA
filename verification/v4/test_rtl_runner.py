"""Fail-closed discovery and metadata checks for the unified correctness runner."""
import json
import hashlib
from collections import Counter
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from scripts.v4 import run_rtl, xsim


class RtlRunnerTests(unittest.TestCase):
    @staticmethod
    def worker_outcomes(plans):
        return [dict(worker=plan['worker'], command={'returncode': 0}, result=dict(
            worker=plan['worker'], tests=len(plan['test_ids']), failures=0, errors=0,
            skips=0, successful=True, assigned_test_ids=plan['test_ids'],
            actual_test_ids=list(plan['test_ids']), test_output='',
            replays={}, compiler_images={}, rtl_commands={}, rtl_compile_output={})) for plan in plans]

    def test_module_partition_preserves_exact_coverage_and_serial_order(self):
        modules = {'test_context_rtl': ['context.a', 'context.b'],
                   'test_tile_rtl': ['tile.a'], 'test_pe_rtl': ['pe.a'],
                   'test_control_rtl': ['control.a'], 'test_models': ['model.a', 'model.b']}
        expected = [name for names in modules.values() for name in names]
        serial = run_rtl.partition_modules(modules, 1)
        parallel = run_rtl.partition_modules(modules, 3)
        self.assertEqual(serial[0]['test_ids'], expected)
        self.assertEqual(Counter(name for plan in parallel for name in plan['test_ids']), Counter(expected))
        owners = {name: plan['worker'] for plan in parallel for name in plan['modules']}
        self.assertEqual(len({owners[name] for name in ('test_context_rtl', 'test_tile_rtl', 'test_pe_rtl')}), 3)
        for plans in (serial, parallel):
            result = run_rtl.aggregate_workers(expected, plans, self.worker_outcomes(plans))
            self.assertTrue(result['successful'], result['coverage_errors'])
            self.assertEqual(result['tests'], len(expected))
            self.assertEqual(Counter(result['actual_test_ids']), Counter(expected))

    def test_worker_aggregation_rejects_failures_skips_timeouts_and_bad_coverage(self):
        plans = run_rtl.partition_modules({'one': ['one.a'], 'two': ['two.a']}, 2)
        expected = ['one.a', 'two.a']
        variants = []
        timed_out = self.worker_outcomes(plans); timed_out[0]['command']['returncode'] = 124
        variants.append(timed_out)
        for key in ('failures', 'errors', 'skips'):
            failed = self.worker_outcomes(plans); failed[0]['result'][key] = 1
            variants.append(failed)
        missing = self.worker_outcomes(plans); missing[0]['result'] = None
        variants.append(missing)
        missing_id = self.worker_outcomes(plans); missing_id[0]['result']['actual_test_ids'] = []
        variants.append(missing_id)
        duplicate_id = self.worker_outcomes(plans)
        duplicate_id[1]['result']['actual_test_ids'] = duplicate_id[0]['result']['actual_test_ids']
        variants.append(duplicate_id)
        duplicate_worker = self.worker_outcomes(plans); duplicate_worker[1] = duplicate_worker[0]
        variants.append(duplicate_worker)
        variants.append(self.worker_outcomes(plans)[:1])
        for outcomes in variants:
            with self.subTest(outcomes=outcomes):
                result = run_rtl.aggregate_workers(expected, plans, outcomes)
                self.assertFalse(result['successful'])
                self.assertTrue(result['coverage_errors'])

    def test_worker_aggregation_retains_all_replay_and_command_provenance(self):
        plans = run_rtl.partition_modules({'one': ['one.a'], 'two': ['two.a']}, 2)
        outcomes = self.worker_outcomes(plans)
        for index, outcome in enumerate(outcomes):
            outcome['result']['replays'] = {'shared-helper': [{'worker': index, 'cycles': 3}]}
            outcome['result']['rtl_commands'] = {'commands': [{'invocation_id': str(index)}]}
        result = run_rtl.aggregate_workers(['one.a', 'two.a'], plans, outcomes)
        self.assertTrue(result['successful'])
        self.assertEqual(len(result['replays']['shared-helper']), 2)
        self.assertEqual(len(result['rtl_commands']['commands']), 2)

    def test_discovers_only_listed_module_declarations(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            rtl = root / 'rtl/v4'
            rtl.mkdir(parents=True)
            (rtl / 'files.f').write_text('+incdir+rtl/v4/include\n-f rtl/v4/children.f\n')
            (rtl / 'children.f').write_text('rtl/v4/current.sv\n')
            (rtl / 'current.sv').write_text(
                '// module future_fake;\n/* module other_fake; */\n'
                'module pe_tile; initial $display("module fake;"); endmodule\n'
                'module pe_array; endmodule\nmodule leaf; endmodule\n')
            (rtl / 'unlisted.sv').write_text('module planned; endmodule\n')
            modules = run_rtl.implemented_modules(root)
            self.assertEqual(set(modules), {'pe_tile', 'pe_array', 'leaf'})
            (rtl / 'files.f').write_text('-unknown\n')
            with self.assertRaises(ValueError):
                run_rtl.implemented_modules(root)

    def test_aliases_merge_replays_images_and_phi_signal_counts(self):
        filename = str(run_rtl.ROOT / 'verification/v4/test_synthetic_rtl.py')
        row = dict(test='phi', cycles=12, signal_checks=84)
        first = SimpleNamespace(__file__=filename, RUNS=[row], IMAGES=[dict(name='bounded')])
        alias = SimpleNamespace(__file__=filename, RUNS=[dict(row)], IMAGES=[dict(name='bounded')],
                                FABRIC_RUNS=[dict(test='fabric', cycles=3, comparisons=21)],
                                PRIMITIVE_RUNS=[dict(test='primitive', cycles=1, checks=7)])
        metadata = run_rtl.collect_test_metadata([first, first, alias])
        self.assertEqual(len(metadata['replays']), 3)
        rows = [row for values in metadata['replays'].values() for row in values]
        self.assertEqual(run_rtl.totals(rows), dict(replays=3, cycles=16, comparisons=112))
        self.assertEqual(sum(len(rows) for rows in metadata['compiler_images'].values()), 1)

    def test_baseline_ignores_config_and_files_list_but_detects_old_rtl_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / 'reports/v4/rtl_baseline_audit_20260909'
            archive.mkdir(parents=True)
            archive.joinpath('evidence.json').write_text(json.dumps(dict(status='PASS', tests=7,
                source_sha256={'rtl/v4/old.sv': 'a', 'rtl/v4/include/old.vh': 'b',
                               'verification/v4/tb_old.sv': 'c', 'rtl/v4/files.f': 'd',
                               'config/v4_modules.json': 'e'})))
            current = {'rtl/v4/old.sv': 'a', 'rtl/v4/include/old.vh': 'b',
                       'verification/v4/tb_old.sv': 'c', 'rtl/v4/files.f': 'changed',
                       'rtl/v4/new.sv': 'new'}
            with patch.object(run_rtl, 'ROOT', root):
                self.assertTrue(run_rtl.baseline_audit(current)['unchanged'])
                current['rtl/v4/old.sv'] = 'changed'
                del current['verification/v4/tb_old.sv']
                audit = run_rtl.baseline_audit(current)
            self.assertFalse(audit['unchanged'])
            self.assertEqual(set(audit['changed']), {'rtl/v4/old.sv'})
            self.assertEqual(audit['missing'], ['verification/v4/tb_old.sv'])

    def test_vivado_metadata_requires_real_stage_records_not_pass_text(self):
        self.assertEqual(run_rtl.vivado_stages({'stdout': 'PASS xvlog xelab xsim'}), {})
        records = [{'argv': ['C:/Xilinx/Vivado/2018.1/bin/xsim.bat'], 'returncode': 0,
                    'invocation_id': 'sim-1', 'execution': 'executed'},
                   {'argv': ['C:/Xilinx/Vivado/2018.1/bin/xelab.bat'], 'returncode': 1,
                    'invocation_id': 'elab-1', 'execution': 'executed'}]
        self.assertEqual(run_rtl.vivado_stages(records), {'xsim': 1})

    def test_stage_counts_deduplicate_aliases_but_keep_distinct_invocations(self):
        command = dict(argv=['C:/Xilinx/Vivado/2018.1/bin/xsim.bat', 'same_snapshot'],
                       cwd='same_directory', returncode=0, invocation_id='first', execution='executed')
        repeated = dict(command, invocation_id='second')
        cached = dict(argv=['C:/Xilinx/Vivado/2018.1/bin/xelab.bat'], returncode=0,
                      invocation_id='old-compile', execution='reused')
        nested = dict(argv=['C:/Xilinx/Vivado/2018.1/bin/xvlog.bat'], returncode=0,
                      invocation_id='not-an-execution', execution='executed')
        command['source_identity'] = {'diagnostic': nested}
        metadata = dict(RUNS=[dict(commands=[command, repeated, cached])],
                        COMMANDS=json.loads(json.dumps([command, repeated, cached])),
                        source_identity={'diagnostic': nested})
        self.assertEqual(run_rtl.vivado_stages(metadata), {'xsim': 2})
        # Reuse encountered first must not suppress the original executed record.
        self.assertEqual(run_rtl.vivado_stages([dict(command, execution='reused'), command]), {'xsim': 1})
        self.assertEqual(run_rtl.vivado_stages([dict(command, invocation_id=None)]), {})

    def test_compile_provenance_survives_temp_files_and_marks_cache_reuse(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            rtl = root/'rtl/v4'
            include = rtl/'include'
            include.mkdir(parents=True)
            source = rtl/'leaf.sv'
            source.write_text('module leaf; endmodule\n')
            header = include/'profile.vh'
            header.write_text('`define WIDTH 8\n')
            (rtl/'files.f').write_text('rtl/v4/leaf.sv\n')
            bench = root/'generated_tb.sv'
            bench.write_text('module tb; leaf core(); endmodule\n')
            output = root/'sim.xsim.json'
            calls = []
            def invoke(tool, arguments, cwd, timeout):
                calls.append(str(tool))
                if tool.stem == 'xelab':
                    (Path(cwd)/'xsim.dir'/arguments[arguments.index('-s')+1]).mkdir(parents=True)
                return dict(argv=[str(tool), *map(str, arguments)], cwd=str(cwd),
                            returncode=0, stdout='', stderr='', execution='executed',
                            invocation_id=f'compile-{len(calls)}')
            executables = {name: root/(name+'.bat') for name in ('xvlog','xelab','xsim')}
            with patch.object(xsim, 'tools', return_value=executables), patch.object(xsim, '_invoke', side_effect=invoke):
                compiled = xsim.compile_rtl(output,'tb',[source,bench],root=root)
                original = json.loads(json.dumps(compiled.commands))
                expected = {str(path.resolve()):hashlib.sha256(path.read_bytes()).hexdigest()
                            for path in (source,bench,header)}
                self.assertEqual(original[0]['source_identity']['hashes'], expected)
                self.assertEqual(original[1]['source_identity']['hashes'], expected)
                reused = xsim.compile_rtl(output,'tb',[source,bench],root=root)
                self.assertEqual(len(calls),2)
                self.assertTrue(all(row['execution']=='reused' for row in reused.commands))
                self.assertTrue(all(row['execution']=='executed' for row in compiled.commands))
                self.assertEqual([row['invocation_id'] for row in reused.commands],
                                 [row['invocation_id'] for row in original])
                self.assertEqual(run_rtl.vivado_stages(reused.commands), {})
                bench.write_text('module tb; leaf changed(); endmodule\n')
                changed = xsim.compile_rtl(output,'tb',[source,bench],root=root)
                self.assertEqual(len(calls),4)
                self.assertNotEqual(changed.commands[0]['compile_signature'],original[0]['compile_signature'])
        # The report record, not the removed elaboration descriptor, owns source hashes.
        self.assertFalse(bench.exists())
        self.assertEqual(original[0]['source_identity']['hashes'], expected)

    def test_actual_invocation_records_have_distinct_ids_for_identical_commands(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(xsim, 'execute_process', return_value=subprocess.CompletedProcess('tool',0,'','')):
                first=xsim._invoke(Path('C:/Xilinx/Vivado/2018.1/bin/xsim.bat'), ['snapshot'],directory,10)
                second=xsim._invoke(Path('C:/Xilinx/Vivado/2018.1/bin/xsim.bat'), ['snapshot'],directory,10)
        self.assertNotEqual(first['invocation_id'],second['invocation_id'])
        self.assertEqual(first['execution'],'executed')
        self.assertIn('started_utc',first)
        self.assertEqual(run_rtl.vivado_stages([first,second,first]), {'xsim':2})

    def test_timeout_and_missing_tool_are_explicit_failed_commands(self):
        with patch.object(run_rtl, 'execute_process', side_effect=subprocess.TimeoutExpired(['tool'], 2, output=b'partial')):
            result = run_rtl.run(['tool'], timeout=2)
        self.assertEqual((result['returncode'], result['stdout']), (124, 'partial'))
        with patch.object(run_rtl, 'execute_process', side_effect=FileNotFoundError('missing')):
            self.assertEqual(run_rtl.run(['tool'])['returncode'], 127)


if __name__ == '__main__':
    unittest.main()
