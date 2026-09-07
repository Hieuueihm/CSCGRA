import unittest

from compiler.v3.numeric_packing import (
    ACC70, D22, S31, normalize_dma_beat, pack_acc70_threshold_beat,
    pack_candidate_threshold_words, pack_scratch_word,
    unpack_acc70_threshold_beat, unpack_candidate_threshold_words,
    unpack_scratch_word,
)


class NumericPackingTest(unittest.TestCase):
    def test_profile_layouts(self):
        self.assertEqual((D22.padding_width, D22.elements_per_word), (6, 3))
        self.assertEqual((S31.padding_width, S31.elements_per_word), (10, 2))
        self.assertEqual((ACC70.padding_width, ACC70.elements_per_word), (2, 1))

    def test_signed_scratch_round_trip_boundaries(self):
        for profile, values in (
            (D22, (-(1 << 21), -1, 0)),
            (D22, ((1 << 21) - 1, 1, 0)),
            (S31, (-(1 << 30), -1)),
            (S31, ((1 << 30) - 1, 1)),
            (ACC70, (-(1 << 69),)),
            (ACC70, ((1 << 69) - 1,)),
        ):
            word = pack_scratch_word(profile, values)
            self.assertEqual(unpack_scratch_word(profile, word), values)
            self.assertEqual(word >> (profile.width * profile.elements_per_word), 0)

    def test_scratch_range_and_padding_reject(self):
        with self.assertRaises(ValueError):
            pack_scratch_word(D22, (1 << 21,))
        with self.assertRaises(ValueError):
            pack_scratch_word(S31, (-(1 << 30) - 1,))
        with self.assertRaises(ValueError):
            unpack_scratch_word(D22, pack_scratch_word(D22, (1,)) | (1 << 70))

    def test_dma_narrowing_and_tail(self):
        self.assertEqual(normalize_dma_beat(D22, (-1, 0, 1), 3), (-1, 0, 1))
        self.assertEqual(normalize_dma_beat(S31, ((1 << 30) - 1,), 1), ((1 << 30) - 1,))
        with self.assertRaises(ValueError):
            normalize_dma_beat(D22, ((1 << 21),), 1)
        with self.assertRaises(ValueError):
            normalize_dma_beat(S31, (-(1 << 30) - 1,), 1)
        with self.assertRaises(ValueError):
            normalize_dma_beat(ACC70, (0,), 1)

    def test_acc70_threshold_beat_and_draft_words(self):
        threshold = (1 << 69) + 0x123456789
        beat = pack_acc70_threshold_beat(threshold)
        self.assertEqual(unpack_acc70_threshold_beat(beat), threshold)
        self.assertEqual(unpack_candidate_threshold_words(
            pack_candidate_threshold_words(threshold)), threshold)
        with self.assertRaises(ValueError):
            unpack_acc70_threshold_beat(beat | (1 << 70))
        with self.assertRaises(ValueError):
            unpack_candidate_threshold_words((0x40, 0, 0))


if __name__ == "__main__":
    unittest.main()
