"""Check a frontend against a published backend contract/bundle, not Rust source.

This is registration/packaging coverage, not proof of live endpoint behavior.
"""
import argparse
import hashlib
from pathlib import Path
import json
import re

from verify_local_apk import inspect_elf, require

ROOT = Path(__file__).resolve().parents[1]


def check_frontend(dart, contract):
    require(contract.get("protocol") == "jasmine-json" and contract.get("version") == 1,
            "Unsupported backend protocol/version")
    require(contract.get("request") == {"method": "string", "params": "string"} and
            contract.get("response") == {"error_message": "string", "response_data": "string"},
            "Incompatible bridge envelope")
    require(contract.get("android") == {"channel": "methods", "invoke_method": "invoke",
                                        "jni_class": "opensource.jenny.Jni", "library": "rust"},
            "Incompatible Android bridge")
    calls = set(re.findall(r'_invoke\(\s*"([^"]+)"', dart))
    require(calls, "No Dart backend calls found")
    registered = set(contract["methods"])
    retired = set(contract["retired_legacy_services"])
    return {"protocol": contract["protocol"], "version": contract["version"],
            "dart_calls": len(calls), "registered": len(calls & registered),
            "missing": sorted(calls - registered), "retired_legacy_services": sorted(calls & retired)}


def inspect_bundle(bundle):
    manifest = json.loads((bundle / "backend-manifest.json").read_text("utf-8-sig"))
    require(manifest.get("schema_version") == 1, "Unsupported backend bundle schema")
    require(manifest.get("target") == "aarch64-linux-android" and manifest.get("abi") == "arm64-v8a",
            "Expected an ARM64 Android backend bundle")
    require(manifest.get("library") == "jniLibs/arm64-v8a/librust.so", "Unexpected backend library path")
    library = (bundle / manifest["library"]).resolve()
    require(library.is_relative_to(bundle.resolve()), "Backend library points outside its bundle")
    data = library.read_bytes()
    require(hashlib.sha256(data).hexdigest() == manifest["library_sha256"], "Backend library digest mismatch")
    require(len(data) == manifest["library_size"], "Backend library size mismatch")
    require(hashlib.sha256((bundle / "sources.lock.json").read_bytes()).hexdigest() ==
            manifest["build"]["source_lock_sha256"], "Backend source lock digest mismatch")
    _, exports = inspect_elf(data)
    require({"Java_opensource_jenny_Jni_init", "Java_opensource_jenny_Jni_invoke"} <= exports,
            "Missing JNI exports in backend bundle")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--bundle", type=Path, help="Published backend bundle; no native checkout needed")
    source.add_argument("--contract", type=Path, default=ROOT / "native/bridge-contract.json")
    parser.add_argument("--dart", type=Path, default=ROOT / "lib/basic/methods.dart")
    args = parser.parse_args()
    contract = (inspect_bundle(args.bundle)["contract"] if args.bundle else
                json.loads(args.contract.read_text("utf-8")))
    result = check_frontend(args.dart.read_text("utf-8"), contract)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(bool(result["missing"]))


if __name__ == "__main__":
    main()
