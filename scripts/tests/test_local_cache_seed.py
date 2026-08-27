"""Local cache isolation/idempotency tests; no network or tool installations."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from seed_local_caches import Seeder, index_name


class CacheSeedTest(unittest.TestCase):
    def test_copy_is_verified_reused_and_does_not_change_shared_source(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / 'project'
            root.mkdir()
            source = Path(folder) / 'shared-source'
            source.write_bytes(b'existing cached package')
            destination = root / '.toolchains/cache/package'
            seed = Seeder(root)
            seed.copy(source, destination)
            seed.copy(source, destination)
            self.assertEqual(destination.read_bytes(), source.read_bytes())
            self.assertEqual(source.read_bytes(), b'existing cached package')
            self.assertEqual((seed.copied, seed.reused), (1, 1))
            source.write_bytes(b'new shared data')
            seed.copy(source, destination)
            self.assertEqual(destination.read_bytes(), b'existing cached package')

    def test_destination_outside_project_toolchains_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / 'project'
            root.mkdir()
            source = Path(folder) / 'source'
            source.write_bytes(b'package')
            outside = Path(folder) / 'outside'
            with self.assertRaisesRegex(ValueError, 'escapes workspace'):
                Seeder(root).copy(source, outside)
            self.assertFalse(outside.exists())

    def test_reparse_source_is_rejected_without_following_it(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = Mock()
            source.is_symlink.return_value = True
            with self.assertRaisesRegex(ValueError, 'Reparse point'):
                Seeder(root).copy(source, root / '.toolchains/cache/item')

    def test_crates_io_sparse_index_layout(self):
        self.assertEqual(index_name('a'), '1/a')
        self.assertEqual(index_name('ab'), '2/ab')
        self.assertEqual(index_name('abc'), '3/a/abc')
        self.assertEqual(index_name('serde'), 'se/rd/serde')


if __name__ == '__main__':
    unittest.main()
