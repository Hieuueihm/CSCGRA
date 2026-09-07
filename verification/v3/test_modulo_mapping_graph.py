from __future__ import annotations

import copy
import json
from pathlib import Path
import unittest

from compiler.v3 import architecture_configuration as architecture
from compiler.v3 import modulo_mapping_graph as mmg
from compiler.v3 import reconstruction_graphs as graphs


class ModuloMappingGraphTests(unittest.TestCase):
    ROOT = Path(__file__).resolve().parents[2]
    @classmethod
    def setUpClass(cls) -> None:
        cls.configuration = architecture.load()
        _, cls.ddgs = graphs.validate_all()

    def test_locked_kernel_library_maps_at_smallest_feasible_ii(self) -> None:
        expected = {
            "correlation": 2,
            "residual_update": 2,
            "phi_support_forward": 2,
            "phi_support_transpose": 2,
        }
        for name, expected_ii in expected.items():
            result = mmg.map_kernel(self.ddgs[name], self.configuration)
            self.assertEqual(result["mmg"]["mii"]["minimum_ii"], expected_ii)
            self.assertEqual(result["mapping"]["candidate_ii"], expected_ii)
            mmg.validate_mapping(self.ddgs[name], result["mmg"], result["mapping"])

    def test_phi_latency_and_occupancy_are_distinct(self) -> None:
        ddg = self.ddgs["correlation"]
        phi = next(node for node in ddg.operations if node.name == "phi")
        self.assertEqual((phi.latency, phi.initiation_interval, phi.occupancy),
                         (21, 2, 2))
        self.assertEqual(mmg.mii(ddg, self.configuration)["minimum_ii"], 2)

    def test_corresponding_cluster_tiles_are_one_mapping_bundle(self) -> None:
        result = mmg.map_kernel(self.ddgs["correlation"], self.configuration)
        phi_mac = result["mapping"]["placements"]["phi_accumulate"]
        self.assertEqual(len(phi_mac["resources"]), 16)
        self.assertTrue(all(name.startswith("paired_tile_")
                            for name in phi_mac["resources"]))
        reservations = [
            (item["link"], item["modulo_slot"])
            for route in result["mapping"]["routes"]
            for item in route["reservations"]
        ]
        self.assertEqual(len(reservations), len(set(reservations)))
        self.assertGreater(len(reservations), 0)
        replicas = phi_mac["physical_lane_replicas"]
        self.assertEqual(set(replicas), set(phi_mac["resources"]))
        self.assertTrue(all(len(items) == 2 for items in replicas.values()))

    def _connector_ddg(self, target_instance: int) -> graphs.ArrayRoutineDDG:
        timing = architecture.operation_timing(self.configuration)["PASS"]
        return graphs.ArrayRoutineDDG(
            "connector_probe", "probe", "physical_replica", (
                graphs.OperationNode(
                    "source", "PASS", "paired_context_tile",
                    timing["latency"], timing["initiation_interval"], 1,
                    timing["variable_latency"], preferred_instance=12),
                graphs.OperationNode(
                    "sink", "PASS", "paired_context_tile",
                    timing["latency"], timing["initiation_interval"], 1,
                    timing["variable_latency"], preferred_instance=target_instance),
            ), (
                graphs.DependencyEdge(
                    "source", "sink", "connector_value", 0,
                    "intercluster_column_connector"),
            ), "modulo_array")

    def test_intercluster_connector_binds_physical_replicas(self) -> None:
        ddg = self._connector_ddg(0)
        graphs.validate_array_routine_ddg(ddg)
        result = mmg.map_kernel(ddg, self.configuration)
        route = result["mapping"]["routes"][0]
        self.assertEqual(route["reservations"][0]["link"],
                         "intercluster_c0_upper_to_lower")
        self.assertEqual(route["physical_source"], "pe_c0_r3_c0")
        self.assertEqual(route["physical_sink"], "pe_c1_r0_c0")
        self.assertEqual(result["mapping"]["placements"]["source"]
                         ["physical_replica"], "pe_c0_r3_c0")
        self.assertEqual(result["mapping"]["placements"]["sink"]
                         ["physical_replica"], "pe_c1_r0_c0")

    def test_intercluster_connector_rejects_cross_column_wraparound(self) -> None:
        ddg = self._connector_ddg(1)
        graphs.validate_array_routine_ddg(ddg)
        with self.assertRaises(ValueError):
            mmg.map_kernel(ddg, self.configuration, maximum_extra_ii=2)

    def test_candidate_below_mii_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            mmg.build_mmg(self.ddgs["residual_update"], self.configuration, 1)

    def test_variable_latency_operation_cannot_enter_modulo_kernel(self) -> None:
        source = self.ddgs["support_union"]
        invalid = graphs.ArrayRoutineDDG(
            source.name, source.loop_axis, source.partition_mode,
            source.operations, source.dependencies, "modulo_array")
        with self.assertRaises(ValueError):
            graphs.validate_array_routine_ddg(invalid)

    def test_mapping_validator_rejects_resource_collision(self) -> None:
        result = mmg.map_kernel(self.ddgs["residual_update"], self.configuration)
        corrupt = copy.deepcopy(result["mapping"])
        corrupt["placements"]["subtract"]["schedule_time"] = (
            corrupt["placements"]["phi_accumulate"]["schedule_time"])
        corrupt["placements"]["subtract"]["modulo_slot"] = (
            corrupt["placements"]["phi_accumulate"]["modulo_slot"])
        corrupt["placements"]["subtract"]["occupancy_slots"] = (
            corrupt["placements"]["phi_accumulate"]["occupancy_slots"])
        with self.assertRaises(ValueError):
            mmg.validate_mapping(self.ddgs["residual_update"], result["mmg"], corrupt)

        stale = copy.deepcopy(result["mapping"])
        stale["architecture_hash"] = "0" * 64
        with self.assertRaises(ValueError):
            mmg.validate_mapping(self.ddgs["residual_update"], result["mmg"], stale)

    def test_time_expanded_mrrg_preserves_shared_context_replication(self) -> None:
        expanded = mmg.time_expanded_mrrg(self.configuration, 3)
        paired = [node for node in expanded["nodes"]
                  if node["kind"] == "paired_context_tile"]
        self.assertEqual(len(paired), 16 * 3)
        self.assertTrue(all(len(node["physical_lane_replicas"]) == 2
                            for node in paired))

    def test_generated_graph_collateral_matches_live_authority(self) -> None:
        reports = self.ROOT / "reports" / "v3"
        generated_mmg = json.loads(
            (reports / "modulo_mapping_graphs.json").read_text(encoding="utf-8"))
        generated_mrrg = json.loads(
            (reports / "mrrg_base.json").read_text(encoding="utf-8"))
        generated_graphs = json.loads(
            (reports / "reconstruction_graphs.json").read_text(encoding="utf-8"))
        self.assertEqual(generated_mmg, mmg.payload())
        self.assertEqual(generated_mrrg,
                         architecture.mrrg_payload(self.configuration))
        live_graphs = json.loads(json.dumps(graphs.payload(), sort_keys=True))
        self.assertEqual(generated_graphs, live_graphs)


if __name__ == "__main__":
    unittest.main()
