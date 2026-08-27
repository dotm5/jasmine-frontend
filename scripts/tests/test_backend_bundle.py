"""Frontend accepts a published bundle without importing backend source code."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_backend_contract as bridge
from test_artifact_tools import elf_fixture


def contract_fixture():
    return {
        "protocol": "jasmine-json", "version": 1,
        "request": {"method": "string", "params": "string"},
        "response": {"error_message": "string", "response_data": "string"},
        "android": {"channel": "methods", "invoke_method": "invoke",
                    "jni_class": "opensource.jenny.Jni", "library": "rust"},
        "methods": ["init_dart", "daily", "reload_pro"],
        "retired_legacy_services": ["reload_pro"],
    }


class BackendBundleTest(unittest.TestCase):
    def test_frontend_checks_multiline_calls_against_external_contract(self):
        dart = '_invoke(\n"init_dart", ""); _invoke("daily", 42); _invoke("reload_pro", "");'
        result = bridge.check_frontend(dart, contract_fixture())
        self.assertEqual(result["dart_calls"], 3)
        self.assertEqual(result["missing"], [])
        self.assertEqual(result["retired_legacy_services"], ["reload_pro"])
        result = bridge.check_frontend(dart + '_invoke("new_method", "");', contract_fixture())
        self.assertEqual(result["missing"], ["new_method"])

    def test_protocol_and_jni_changes_are_rejected(self):
        for field, value in [("version", 2), ("request", {"params": "object"}),
                             ("android", {"jni_class": "another.Jni"})]:
            with self.subTest(field=field), self.assertRaises(ValueError):
                bridge.check_frontend('_invoke("daily", 42)', {**contract_fixture(), field: value})

    def test_bundle_verifies_library_without_a_native_checkout(self):
        with tempfile.TemporaryDirectory() as folder:
            bundle = Path(folder)
            library = bundle / "jniLibs/arm64-v8a/librust.so"
            library.parent.mkdir(parents=True)
            library.write_bytes(elf_fixture())
            lock = bundle / "sources.lock.json"
            lock.write_text('{"schema":1}', encoding="utf-8")
            manifest = {
                "schema_version": 1, "contract": contract_fixture(),
                "target": "aarch64-linux-android", "abi": "arm64-v8a",
                "library": "jniLibs/arm64-v8a/librust.so",
                "library_sha256": hashlib.sha256(library.read_bytes()).hexdigest(),
                "library_size": library.stat().st_size,
                "build": {"source_lock_sha256": hashlib.sha256(lock.read_bytes()).hexdigest()},
            }
            (bundle / "backend-manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
            self.assertEqual(bridge.inspect_bundle(bundle), manifest)
            library.write_bytes(b"wrong library")
            with self.assertRaisesRegex(ValueError, "digest mismatch"):
                bridge.inspect_bundle(bundle)


if __name__ == "__main__":
    unittest.main()
