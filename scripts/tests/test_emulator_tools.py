"""Offline regression tests for local emulator setup and UI smoke helpers."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from xml.dom import minidom
from xml.etree import ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import android_emulator_smoke as smoke
import install_android_sdk as sdk
import prepare_android_emulator as prepare


class EmulatorToolsTest(unittest.TestCase):
    def test_system_image_url_uses_its_own_repository(self):
        doc = minidom.parseString('''<repository><remotePackage path="fixture">
          <revision><major>1</major></revision><display-name>Fixture</display-name>
          <archives><archive><complete><size>10</size><checksum type="sha1">0000000000000000000000000000000000000000</checksum>
          <url>x86_64-fixture.zip</url></complete></archive></archives></remotePackage></repository>''')
        info = sdk.package_info(doc, "fixture", prepare.SOURCES[1][1])
        self.assertEqual(info["url"], "https://dl.google.com/android/repository/sys-img/google_apis/x86_64-fixture.zip")
        with self.assertRaisesRegex(ValueError, "origin"):
            sdk.package_info(doc, "fixture", "https://fixture.invalid/repository.xml")

    def test_license_normalization_preserves_paragraphs(self):
        value = "  Heading\n\nAn indented\n    line.  \n\nLast paragraph.\n"
        normalized = "Heading\n\nAn indented line. \n\nLast paragraph."
        self.assertEqual(prepare.license_hash(value), hashlib.sha1(normalized.encode()).hexdigest())

    def test_installed_components_are_reused_only_when_complete(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            info = {"path": "emulator", "url": "https://dl.google.com/fixture.zip", "size": 10,
                    "algorithm": "sha1", "checksum": "0" * 40}
            target = root / "emulator"
            target.mkdir()
            (target / ".jasmine-toolchain-receipt.json").write_text(json.dumps({**info, "archive_sha256": "1" * 64}))
            for name in ("source.properties", "package.xml", "emulator.exe"):
                (target / name).write_text("fixture")
            self.assertTrue(prepare.installed(info, root, ("emulator.exe",)))
            self.assertFalse(prepare.installed(info, root, ("missing.exe",)))
            self.assertFalse(prepare.installed({**info, "size": 11}, root, ("emulator.exe",)))

    def test_ui_bounds_and_merged_flutter_semantics(self):
        tree = ET.fromstring('<hierarchy><node text="" content-desc="登录即为同意 &#10;使用协议"/><node text="取消"/></hierarchy>')
        self.assertEqual(smoke.labels(tree), ["登录即为同意 \n使用协议", "取消"])
        self.assertEqual(smoke.center("[0,736][720,838]"), (360, 787))
        for invalid in ("", "[0,0][0,10]", "[-1,0][20,20]"):
            with self.assertRaises(ValueError):
                smoke.center(invalid)

    def test_real_device_serials_are_rejected_before_any_command(self):
        with self.assertRaisesRegex(ValueError, "local emulator"):
            smoke.Smoke(Path("adb.exe"), 5038, "physical-device", Path("unused"))


if __name__ == "__main__":
    unittest.main()
