"""Held-out identities must be deterministic and separate from development."""

from __future__ import annotations

import unittest

from scripts.numeric import v3_freeze_heldout_manifest as heldout


class HeldoutManifestTest(unittest.TestCase):
    def test_seed_derivation_is_stable_and_domain_separated(self) -> None:
        digest = "12" * 32
        seeds = [heldout.derive_phi_seed(digest, ordinal) for ordinal in range(3)]
        self.assertEqual(seeds, [
            10633911675017763943,
            197098501558471273,
            8909691259604214510,
        ])
        self.assertEqual(len(set(seeds)), len(seeds))
        self.assertNotIn(heldout.DEVELOPMENT_PHI_SEED, seeds)

    def test_block_name_roundtrip(self) -> None:
        self.assertEqual(heldout.parse_block_name("slice112_r64_c184"), (112, 64, 184))
        with self.assertRaisesRegex(ValueError, "unsupported block name"):
            heldout.parse_block_name("r64_c184")

    def test_canonical_bytes_are_sorted_and_newline_terminated(self) -> None:
        self.assertEqual(heldout.canonical_bytes({"b": 1, "a": 2}), b'{\n  "a": 2,\n  "b": 1\n}\n')


if __name__ == "__main__":
    unittest.main()
