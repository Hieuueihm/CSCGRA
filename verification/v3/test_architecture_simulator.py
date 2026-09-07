from __future__ import annotations
from copy import deepcopy
from dataclasses import replace
import unittest

from compiler.v3 import architecture_configuration

from models.v3 import architecture_simulator as sim
from models.v3 import hardware
from scripts.golden.generate_v3_phase_golden import suite


class ResourceSchedulerTests(unittest.TestCase):
    def test_independent_resources_overlap_and_shared_resources_serialize(self) -> None:
        scheduler = sim.ResourceScheduler()
        common = dict(phase_seq=0, iteration=0, phase_name="TEST",
                      category="test", macroblock="reconstruction_control")
        first = scheduler.schedule(sim.TransactionSpec(
            name="a", duration=5, resources=("a",), **common))
        second = scheduler.schedule(sim.TransactionSpec(
            name="b", duration=3, resources=("b",), **common))
        third = scheduler.schedule(sim.TransactionSpec(
            name="ab", duration=2, resources=("a", "b"), **common))
        self.assertEqual((scheduler.scheduled[first].start_cycle,
                          scheduler.scheduled[second].start_cycle), (0, 0))
        self.assertEqual(scheduler.scheduled[third].start_cycle, 5)


class ArchitectureSimulatorTests(unittest.TestCase):
    @staticmethod
    def run_omp(profile: str = "strict_paper") -> sim.SimulationResult:
        case = suite("smoke")[1]
        trace = hardware.run(
            "OMP", case["phi"], case["y"], case["policy"],
            hardware.NumericProfile(), hardware.RefinementPolicy(profile=profile))
        return sim.simulate(
            trace, case_name=case["name"], measurement_count=case["m"],
            signal_length=case["n"], sparsity=case["k"], profile=profile)

    def test_default_timing_contract_uses_measured_architecture_authority(self) -> None:
        timing = sim.timing_contract_from_architecture_configuration()
        self.assertEqual(timing.reduction_latency_cycles, 5)
        self.assertEqual(timing.scalar_divide_cycles, 15)
        self.assertEqual((timing.shared_vector_dot_latency_cycles,
                          timing.shared_vector_dot_initiation_interval), (6, 2))
        self.assertEqual((timing.shared_vector_scale_latency_cycles,
                          timing.shared_vector_scale_initiation_interval), (4, 2))
        self.assertEqual((timing.shared_vector_copy_latency_cycles,
                          timing.shared_vector_copy_initiation_interval), (2, 1))
        self.assertEqual((timing.threefry_first_word_latency_cycles,
                          timing.threefry_request_initiation_interval), (21, 2))
        self.assertEqual((timing.phi_normalize_latency_cycles,
                          timing.phi_normalize_initiation_interval), (4, 1))

    def test_required_measured_timing_is_fail_closed(self) -> None:
        configuration = architecture_configuration.load()
        missing = deepcopy(configuration)
        missing["resource_operations"] = [
            record for record in missing["resource_operations"]
            if record["name"] != "SCALAR_DIVIDE"
        ]
        with self.assertRaisesRegex(ValueError, "missing SCALAR_DIVIDE"):
            sim.timing_contract_from_architecture_configuration(missing)

        modeled = deepcopy(configuration)
        divide = next(record for record in modeled["resource_operations"]
                      if record["name"] == "SCALAR_DIVIDE")
        divide["timing_status"] = "modeled"
        divide["timing_evidence"] = None
        with self.assertRaisesRegex(ValueError, "must be implemented with measured timing"):
            sim.timing_contract_from_architecture_configuration(modeled)

    def test_total_partition_and_phase_invocations_are_conserved(self) -> None:
        result = self.run_omp()
        self.assertEqual(result.total_cycles,
                         result.ingress_cycles + result.compute_cycles
                         + result.egress_cycles)
        trace_phase_count = sum(result.phase_invocations.values())
        dispatch_count = sum(
            item.spec.name == "phase_dispatch" for item in result.transactions)
        self.assertEqual(trace_phase_count, dispatch_count)
        self.assertGreater(result.category_cycles["correlation"], 0)
        self.assertGreater(result.category_cycles["refinement"], 0)
        self.assertGreater(result.category_cycles["certificate"], 0)

    def test_all_six_macroblocks_are_exercised_by_strict_omp(self) -> None:
        result = self.run_omp()
        self.assertEqual(set(result.macroblock_busy_cycles), set(sim.MACROBLOCKS))

    def test_resource_reservations_never_overlap(self) -> None:
        result = self.run_omp()
        for resource in result.resource_busy_cycles:
            reservations = sorted(
                (item.start_cycle, item.end_cycle) for item in result.transactions
                if resource in item.spec.resources)
            for left, right in zip(reservations, reservations[1:]):
                self.assertLessEqual(left[1], right[0], resource)

    def test_fast_profile_reduces_omp_cycle_estimate(self) -> None:
        strict = self.run_omp("strict_paper")
        fast = self.run_omp("fast_variant")
        self.assertLess(fast.total_cycles, strict.total_cycles)

    def test_cycle_model_is_deterministic(self) -> None:
        first = self.run_omp()
        second = self.run_omp()
        self.assertEqual(first.payload(), second.payload())

    def test_candidate_capture_eliminates_exact_phi_fill_word_count(self) -> None:
        case = suite("smoke")[1]
        trace = hardware.run(
            "OMP", case["phi"], case["y"], case["policy"],
            hardware.NumericProfile(), hardware.RefinementPolicy())
        enabled = sim.simulate(
            trace, case_name=case["name"], measurement_count=case["m"],
            signal_length=case["n"], sparsity=case["k"],
            profile="strict_paper")
        disabled = sim.simulate(
            trace, case_name=case["name"], measurement_count=case["m"],
            signal_length=case["n"], sparsity=case["k"],
            profile="strict_paper",
            timing=replace(
                sim.timing_contract_from_architecture_configuration(),
                candidate_symbol_capture=False))
        promotions = [
            item for item in enabled.transactions
            if item.spec.name == "active_support_phi_cache_promote"
        ]
        eliminated_words = sum(
            int(item.spec.detail["eliminated_generator_words"])
            for item in promotions)
        self.assertGreater(eliminated_words, 0)
        self.assertEqual(disabled.total_cycles - enabled.total_cycles,
                         eliminated_words)
        self.assertFalse(any(
            item.spec.name == "active_support_phi_cache_fill"
            for item in enabled.transactions))
        enabled_correlation = [
            item.duration for item in enabled.transactions
            if item.spec.name == "full_correlation_and_candidate_capture"
        ]
        disabled_correlation = [
            item.duration for item in disabled.transactions
            if item.spec.name == "full_correlation_and_candidate_capture"
        ]
        self.assertEqual(enabled_correlation, disabled_correlation)

    def test_recurrence_is_per_step_and_full_certificate_is_cadenced(self) -> None:
        case = suite("smoke")[1]
        trace = hardware.run(
            "CoSaMP", case["phi"], case["y"], case["policy"],
            hardware.NumericProfile(), hardware.RefinementPolicy())
        result = sim.simulate(
            trace, case_name=case["name"], measurement_count=case["m"],
            signal_length=case["n"], sparsity=case["k"],
            profile="strict_paper")
        step_count = result.phase_invocations["REFINEMENT_STEP"]
        certificate_count = result.phase_invocations["REFINEMENT_CERTIFICATE"]
        recurrence_count = sum(
            item.spec.name == "recurrence_solver_transpose"
            for item in result.transactions)
        true_residual_count = sum(
            item.spec.name == "certificate_true_residual"
            for item in result.transactions)
        self.assertEqual(recurrence_count, step_count)
        self.assertEqual(true_residual_count, certificate_count)
        self.assertLess(certificate_count, step_count)


if __name__ == "__main__":
    unittest.main()
