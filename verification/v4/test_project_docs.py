"""Guards the current active10 language in generated architecture documents."""
import unittest

from scripts.v4 import project


class ProjectDocumentTests(unittest.TestCase):
    def test_module_catalog_uses_active10_and_existing_pe_scope(self):
        generated = project.generated_files()
        text = generated[project.ROOT / 'docs/v4/architecture/MODULES.md']
        self.assertIn('ten active loaded programs', text)
        self.assertIn('ADMM remains a historical reference', text)
        self.assertIn('exactly two 4x4 streaming PE arrays (32 PEs total)', text)
        self.assertIn('bounded command state', text)
        self.assertNotIn('eleven small programs', text)
        self.assertNotIn('Current streaming arrays use independent lanes.', text)


if __name__ == '__main__':
    unittest.main()
