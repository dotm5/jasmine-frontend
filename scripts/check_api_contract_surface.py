"""Audit declared calls and real runtime coverage; registration alone is not success."""
import argparse
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def inspect_surface(frontend, native, android, ios, contract):
    calls = set(re.findall(r'_invoke\(\s*"([^"]+)"', frontend))
    platform_calls = set(re.findall(
        r'_channel\s*\.\s*invokeMethod(?:<[^>]+>)?\(\s*"([^"]+)"', frontend))
    dispatcher = native.split("async fn match_method(", 1)[1].split(
        "\nasync fn init_dart(", 1)[0]
    handlers = set(re.findall(r'"(\w+)"\s*(?=\||=>)', dispatcher))
    published = set(contract["methods"])
    android_handlers = set(re.findall(r'"(\w+)"\s*->', android))
    ios_handlers = set(re.findall(r'case\s+"(\w+)"\s*:', ios))
    require(calls, "No frontend bridge calls found")
    require(handlers == published,
            f"Dispatcher/catalog drift: missing={sorted(published - handlers)}, "
            f"unpublished={sorted(handlers - published)}")
    require(not calls - handlers, f"Dangling bridge calls: {sorted(calls - handlers)}")
    require(platform_calls - android_handlers == {"iosGetDocumentDir"},
            f"Unexpected missing Android handlers: {sorted(platform_calls - android_handlers)}")
    require("iosGetDocumentDir" in ios_handlers, "iOS document-directory handler is missing")
    return {
        "frontend_bridge_count": len(calls),
        "registered_handler_count": len(handlers),
        "frontend_platform_count": len(platform_calls),
        "android_platform_handlers": sorted(platform_calls & android_handlers),
        "ios_only_platform_handlers": ["iosGetDocumentDir"],
        "retired_methods": sorted(set(contract["retired_legacy_services"]) & calls),
        "known_noops": ["config_links", "test"],
        "dangling_bridge_calls": [],
    }


def inspect_runtime(report, contract, frontend_calls):
    outcomes = report["outcomes"]
    retired = set(contract["retired_legacy_services"])
    active = frontend_calls - retired
    missing = frontend_calls - outcomes.keys()
    unsuccessful = {name for name in active if "success" not in outcomes.get(name, [])}
    retired_without_error = {name for name in retired
                             if "error" not in outcomes.get(name, [])}
    require(not missing, f"No runtime case: {sorted(missing)}")
    require(not unsuccessful, f"No successful active-method case: {sorted(unsuccessful)}")
    require(not retired_without_error,
            f"Retired methods must reject explicitly: {sorted(retired_without_error)}")
    return {
        "frontend_invoked": len(frontend_calls),
        "active_success_envelopes": len(active),
        "retired_error_envelopes": len(retired),
        "registered_invoked": len(set(contract["methods"]) & outcomes.keys()),
        "scope": report["scope"],
        "live_service_validation": False,
        "platform_device_validation": False,
        "note": "Run only after the typed integration suite passes; envelopes alone do not verify DTOs.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-report", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    frontend = (ROOT / "lib/basic/methods.dart").read_text("utf-8")
    contract = json.loads((ROOT / "native/bridge-contract.json").read_text("utf-8"))
    report = inspect_surface(
        frontend,
        (ROOT / "native/jmbackend/src/lib.rs").read_text("utf-8"),
        (ROOT / "android/app/src/main/kotlin/opensource/jmtt2mic/MainActivity.kt").read_text("utf-8"),
        (ROOT / "ios/Runner/AppDelegate.swift").read_text("utf-8"),
        contract,
    )
    if args.runtime_report:
        runtime = json.loads(args.runtime_report.read_text("utf-8"))
        calls = set(re.findall(r'_invoke\(\s*"([^"]+)"', frontend))
        report["runtime"] = inspect_runtime(runtime, contract, calls)
    text = json.dumps(report, ensure_ascii=False, indent=2)
    if args.out:
        require(args.out.resolve().is_relative_to((ROOT / ".tmp").resolve()),
                "Audit output must remain in workspace .tmp")
        args.out.write_text(text + "\n", encoding="utf-8")
    print(text)


if __name__ == "__main__":
    main()
