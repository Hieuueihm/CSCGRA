from __future__ import annotations

import copy
import unittest

from compiler.v3 import architecture_configuration as architecture


class ArchitectureConfigurationTests(unittest.TestCase):
    def test_checked_configuration_builds_stable_collateral(self) -> None:
        configuration = architecture.load()
        numeric = configuration["numeric_profiles"]
        profiles = {profile["name"]: profile for profile in numeric["profiles"]}
        self.assertEqual(numeric["active"], "production")
        self.assertEqual(numeric["closure_candidate"], "quality_d22")
        self.assertEqual(
            (profiles["quality_d22"]["data_width"],
             profiles["quality_d22"]["data_fraction_bits"],
             profiles["quality_d22"]["solver_width"],
             profiles["quality_d22"]["solver_fraction_bits"],
             profiles["quality_d22"]["accumulator_width"],
             profiles["quality_d22"]["scalar_divide_latency"],
             profiles["quality_d22"]["strict_normal_residual_shift"]),
            (22, 18, 31, 23, 70, 17, 16),
        )
        self.assertEqual(configuration["context_format_revision"], 9)
        self.assertEqual(
            configuration["context_storage"]["array_context_programming_order"],
            [0, 1, 2, 3, 4, 5, 6, 7, 9, 8])
        self.assertEqual(configuration["memory"]["memory_configuration_read_ports"], 4)
        self.assertEqual(configuration["memory"]["memory_configuration_read_latency"], 1)
        self.assertEqual(configuration["memory"]["memory_configuration_ram_copies"], 2)
        self.assertEqual(configuration["memory"]["memory_configuration_bram36_count"], 4)
        self.assertEqual(len(architecture.configuration_hash(configuration)), 64)
        mrrg = architecture.mrrg_payload(configuration)
        self.assertEqual(len([node for node in mrrg["nodes"]
                              if node["kind"] == "paired_context_tile"]), 16)
        self.assertEqual(len([node for node in mrrg["nodes"]
                              if node["kind"] == "memory_bank"]), 8)
        self.assertEqual(mrrg["physical_pe_lanes"], 32)
        paired = next(node for node in mrrg["nodes"]
                      if node["kind"] == "paired_context_tile")
        self.assertEqual(len(paired["physical_lane_replicas"]), 2)
        self.assertIn("PHI_SIGN_SCALE", paired["operations"])
        self.assertIn("PHI_ACCUMULATE", paired["operations"])
        phi_mac_timing = paired["operation_timing"]["PHI_ACCUMULATE"]
        self.assertEqual(
            (phi_mac_timing["latency"], phi_mac_timing["initiation_interval"],
             phi_mac_timing["variable_latency"], phi_mac_timing["status"],
             phi_mac_timing["timing_status"]),
            (1, 1, False, "implemented", "measured"))
        self.assertEqual(paired["operation_timing"]["SATURATING_ADD"]["latency"], 1)
        connector_links = [
            link for link in mrrg["links"]
            if link["plane"] == "intercluster_column_connector"
        ]
        self.assertEqual(len(connector_links), 8)
        self.assertTrue(all(link["latency"] == 1 for link in connector_links))
        self.assertEqual(
            {link["physical_source"].split("_")[1] for link in connector_links},
            {"c0", "c1"})

    def test_unknown_field_and_forbidden_topology_are_rejected(self) -> None:
        configuration = architecture.load()
        unknown = copy.deepcopy(configuration)
        unknown["topology"]["hidden_router"] = True
        with self.assertRaises(ValueError):
            architecture.validate(unknown)
        independent_pc = copy.deepcopy(configuration)
        independent_pc["topology"]["shared_array_context_pc"] = False
        with self.assertRaises(ValueError):
            architecture.validate(independent_pc)
        express = copy.deepcopy(configuration)
        express["topology"]["express_links_enabled"] = True
        with self.assertRaises(ValueError):
            architecture.validate(express)
        wrong_connector_width = copy.deepcopy(configuration)
        wrong_connector_width["topology"]["intercluster_connector_lanes"] = 3
        with self.assertRaises(ValueError):
            architecture.validate(wrong_connector_width)

        duplicate_owner = copy.deepcopy(configuration)
        duplicate_owner["physical_resources"][4]["operations"].append(
            "SCALAR_DIVIDE")
        with self.assertRaises(ValueError):
            architecture.validate(duplicate_owner)

    def test_operation_table_and_context_launch_are_complete(self) -> None:
        configuration = architecture.load()
        missing_operation = copy.deepcopy(configuration)
        missing_operation["tile_operations"].pop()
        with self.assertRaises(ValueError):
            architecture.validate(missing_operation)
        algorithm_decode = copy.deepcopy(configuration)
        algorithm_decode["execution_context"]["hardware_algorithm_decode"] = True
        with self.assertRaises(ValueError):
            architecture.validate(algorithm_decode)

        timing = architecture.operation_timing(configuration)
        self.assertEqual(timing["SCALAR_DIVIDE"]["latency"], 15)
        self.assertEqual(timing["PHI_SIGN_WORD"]["initiation_interval"], 2)

    def test_reserved_scalar_operations_are_not_physical_resources(self) -> None:
        configuration = architecture.load()
        timing = architecture.operation_timing(configuration)
        for name in ("SCALAR_RECIPROCAL", "SCALAR_SQRT"):
            self.assertEqual(timing[name]["status"], "reserved")
            self.assertEqual(timing[name]["timing_status"], "unimplemented")
            self.assertEqual((timing[name]["latency"],
                              timing[name]["initiation_interval"]), (1, 1))
            self.assertFalse(
                architecture.resource_operation_is_schedulable(configuration, name))

        resources = architecture.physical_resource_map(configuration)
        self.assertEqual(resources["scalar_function_unit"]["operations"],
                         ["SCALAR_DIVIDE"])
        self.assertTrue(architecture.resource_operation_is_schedulable(
            configuration, "SCALAR_DIVIDE"))
        for name in ("TOPK_PUSH", "TOPK_COMMIT"):
            self.assertTrue(architecture.resource_operation_is_schedulable(
                configuration, name))
            self.assertEqual(timing[name]["rtl_owner"], "topk_selection_unit")
            self.assertEqual(timing[name]["timing_status"], "measured")
        for name in (
                "SUPPORT_CLEAR", "SUPPORT_APPEND", "SUPPORT_UNION",
                "SUPPORT_MEMBERSHIP", "SUPPORT_GATHER", "SUPPORT_SCATTER",
                "SUPPORT_COMMIT", "SUPPORT_ROLLBACK"):
            self.assertTrue(architecture.resource_operation_is_schedulable(
                configuration, name))
            self.assertEqual(timing[name]["rtl_owner"], "support_state_manager")
            self.assertEqual(timing[name]["timing_status"], "measured")
        self.assertTrue(architecture.resource_operation_is_schedulable(
            configuration, "REFINEMENT_CHECK"))
        self.assertEqual(timing["REFINEMENT_CHECK"]["rtl_owner"],
                         "normal_residual_checker")
        self.assertEqual(timing["REFINEMENT_CHECK"]["timing_status"],
                         "measured")

        execution = configuration["execution_context"]
        self.assertEqual(execution["selection"], "active_finalized_image")
        self.assertEqual(execution["phase_entry_pc"], 0)
        self.assertFalse(execution["hardware_algorithm_decode"])
        self.assertTrue(execution["software_defines_context"])

        illegal_owner = copy.deepcopy(configuration)
        scalar = next(item for item in illegal_owner["physical_resources"]
                      if item["id"] == "scalar_function_unit")
        scalar["operations"].append("SCALAR_RECIPROCAL")
        with self.assertRaises(ValueError):
            architecture.validate(illegal_owner)

        stale_fault_latency = copy.deepcopy(configuration)
        reciprocal = next(item for item in stale_fault_latency["resource_operations"]
                          if item["name"] == "SCALAR_RECIPROCAL")
        reciprocal["latency"] = 28
        with self.assertRaises(ValueError):
            architecture.validate(stale_fault_latency)


if __name__ == "__main__":
    unittest.main()
