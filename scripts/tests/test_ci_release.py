from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from prepare_ci_release import check_packaged_manifest, check_signer, validate_revision


class CiReleaseTests(unittest.TestCase):
    def test_release_builds_keep_the_complete_material_icon_font(self):
        root = Path(__file__).resolve().parents[2]
        for relative in [".github/workflows/Release.yml", "scripts/build-android.ps1"]:
            command_file = (root / relative).read_text(encoding="utf-8")
            self.assertIn("flutter build apk", command_file)
            self.assertIn("--no-tree-shake-icons", command_file)

    def test_full_revision_only(self):
        self.assertEqual(validate_revision("a" * 40), "a" * 40)
        for value in ["master", "a" * 12, "a" * 40 + "\n", "../native"]:
            with self.assertRaises(ValueError):
                validate_revision(value)

    def test_signer_must_match_update_identity(self):
        check_signer("Signer #1 certificate SHA-256 digest: " + "a" * 64, "a" * 64)
        for text in ["", "Signer #1 certificate SHA-256 digest: " + "b" * 64]:
            with self.assertRaises(ValueError):
                check_signer(text, "a" * 64)

    def test_adaptive_flags_must_be_enabled_in_apk(self):
        text = ('package="opensource.jasmine.local"\n'
                'android:enableOnBackInvokedCallback(0x1)=(type 0x12)0xffffffff\n'
                'android:resizeableActivity(0x2)=(type 0x12)0xffffffff\n'
                'android:windowSoftInputMode(0x3)=(type 0x11)0x10\n')
        check_packaged_manifest(text)
        for changed in [text.replace("0xffffffff", "0x0"), text.replace("0x10\n", "0x20\n"),
                        text.replace("opensource.jasmine.local", "another.app")]:
            with self.assertRaises(ValueError):
                check_packaged_manifest(changed)


if __name__ == "__main__":
    unittest.main()
