import importlib.util
from pathlib import Path
import unittest

MODULE = Path(__file__).resolve().parents[1] / "check_api_contract_surface.py"
SPEC = importlib.util.spec_from_file_location("api_contract_surface", MODULE)
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


class RuntimeCoverageTests(unittest.TestCase):
    def test_property_alternatives_are_not_dispatcher_methods(self):
        native = '''async fn match_method() {
            match method {
              "active" => { let cleanup = matches!(key, "auto_clean" | "cache_max_bytes"); }
              "retired" | "alias" => {}
            }
        }
async fn init_dart() {}'''
        frontend = '_invoke("active"); _invoke("retired"); _channel.invokeMethod("iosGetDocumentDir");'
        result = audit.inspect_surface(frontend, native, '', 'case "iosGetDocumentDir":',
            {"methods": ["active", "retired", "alias"], "retired_legacy_services": ["retired"]})
        self.assertEqual(result['registered_handler_count'], 3)

    def setUp(self):
        self.contract = {"methods": ["active", "retired"],
                         "retired_legacy_services": ["retired"]}
        self.report = {"scope": "synthetic",
                       "outcomes": {"active": ["success"], "retired": ["error"]}}

    def test_success_and_retired_error_are_distinct(self):
        result = audit.inspect_runtime(self.report, self.contract, {"active", "retired"})
        self.assertEqual(result["active_success_envelopes"], 1)
        self.assertEqual(result["retired_error_envelopes"], 1)

    def test_registration_and_errors_do_not_count_as_active_success(self):
        self.report["outcomes"]["active"] = ["error"]
        with self.assertRaisesRegex(ValueError, "No successful"):
            audit.inspect_runtime(self.report, self.contract, {"active", "retired"})

    def test_a_new_frontend_call_requires_a_case(self):
        with self.assertRaisesRegex(ValueError, "No runtime case"):
            audit.inspect_runtime(self.report, self.contract, {"active", "retired", "new"})

    def test_retired_noop_is_not_accepted(self):
        self.report["outcomes"]["retired"] = ["success"]
        with self.assertRaisesRegex(ValueError, "must reject"):
            audit.inspect_runtime(self.report, self.contract, {"active", "retired"})


if __name__ == "__main__":
    unittest.main()
