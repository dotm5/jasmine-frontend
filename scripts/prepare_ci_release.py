"""Verify and export a binary-only CI release; never publish native source/logs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

from check_backend_contract import inspect_bundle, check_frontend
from verify_local_apk import require, verify

ROOT = Path(__file__).resolve().parents[1]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_revision(value):
    require(re.fullmatch(r"[0-9a-f]{40}", value) is not None, "Expected full Git revision")
    return value


def check_packaged_manifest(text):
    require('package="opensource.jasmine.local"' in text, "Unexpected Android package")
    for flag in ("enableOnBackInvokedCallback", "resizeableActivity"):
        require(re.search(rf"android:{flag}\([^\n]+0xffffffff", text), f"Missing Android flag: {flag}")
    require(re.search(r"android:windowSoftInputMode\([^\n]+0x10\b", text), "adjustResize is missing")


def check_signer(text, expected):
    match = re.search(r"Signer #1 certificate SHA-256 digest: ([0-9a-f]{64})", text)
    require(match is not None and match[1] == expected, "APK signer differs from the pinned update key")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--backend-sha", required=True)
    args = parser.parse_args()
    backend_sha = validate_revision(args.backend_sha)
    source_sha = validate_revision(os.environ["GITHUB_SHA"])
    actual_backend = subprocess.check_output(["git", "-C", str(ROOT / "native"), "rev-parse", "HEAD"], text=True).strip()
    require(actual_backend == backend_sha, "Backend checkout does not match the gitlink")
    bundle = args.bundle.resolve()
    backend = inspect_bundle(bundle)
    contract = check_frontend((ROOT / "lib/basic/methods.dart").read_text("utf-8"), backend["contract"])
    require(not contract["missing"], "Missing backend methods")
    apk = ROOT / "build/app/outputs/flutter-apk/app-release.apk"
    binary_report = verify(apk, bundle / backend["library"])
    build_tools = Path(os.environ["ANDROID_HOME"]) / "build-tools/35.0.0"
    suffix = ".bat" if os.name == "nt" else ""
    signer = subprocess.check_output([str(build_tools / ("apksigner" + suffix)), "verify", "--print-certs", str(apk)], text=True)
    certificate = (ROOT / "ci/android-signing.sha256").read_text("utf-8").strip()
    check_signer(signer, certificate)
    subprocess.run([str(build_tools / ("zipalign.exe" if os.name == "nt" else "zipalign")), "-c", "-P", "16", "4", str(apk)], check=True)
    manifest_xml = subprocess.check_output([str(build_tools / ("aapt.exe" if os.name == "nt" else "aapt")), "dump", "xmltree", str(apk), "AndroidManifest.xml"], text=True)
    check_packaged_manifest(manifest_xml)
    output = ROOT / "dist"
    output.mkdir(exist_ok=True)
    name = f"jasmine-local-{source_sha[:12]}-arm64.apk"
    require(not (output / name).exists(), "Release APK already exists")
    shutil.copyfile(apk, output / name)
    notices = ("UPSTREAM-NOTICES.md", "upstream/jenny/README.md", "upstream/jmcomic-downloader/LICENSE")
    with zipfile.ZipFile(output / "licenses.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        for relative in notices:
            archive.write(bundle / relative, relative)
    coverage = json.loads((ROOT / ".tmp/api-coverage.json").read_text("utf-8"))
    require(coverage["runtime"]["active_success_envelopes"] > 0 and not coverage["dangling_bridge_calls"],
            "Typed runtime coverage is required before publishing")
    manifest = {
        "schema": 1, "artifact": name, "sha256": sha256(output / name),
        "size": (output / name).stat().st_size, "sourceRevision": source_sha,
        "backendRevision": backend_sha, "backendLibrarySha256": backend["library_sha256"],
        "packageId": "opensource.jasmine.local", "abi": "arm64-v8a",
        "signingCertificateSha256": certificate, "flutter": "3.29.3",
        "ndk": backend["build"]["ndk"], "rust": backend["build"]["rust"],
        "workflowRun": f"https://github.com/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}",
        "checks": {"flutterTests": "passed", "backendTests": "passed", "typedApiCoverage": coverage,
                   "signature": "passed", "zipAlignment16KiB": "passed", "adaptiveManifest": "passed"},
        "binaryVerification": binary_report,
        "deviceValidation": "pending", "liveApiValidation": "not run in CI",
    }
    (output / "build-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    files = (name, "build-manifest.json", "licenses.zip")
    (output / "SHA256SUMS.txt").write_text("".join(f"{sha256(output / item)}  {item}\n" for item in files), encoding="utf-8")
    (output / "release-notes.md").write_text(
        "## Jasmine Android ARM64\n\n"
        "- Material 3 Expressive 风格、响应式导航与宽屏布局。\n"
        "- 收藏、历史、阅读、下载与分组设置。\n"
        "- 自动执行前后端测试、合成 API 集成测试、签名及包体检查后发布。\n\n"
        "同包名、同签名，可覆盖安装；请保留应用数据。CI 使用本地合成数据，不代表真实服务或实机已通过。\n\n"
        f"前端：`{source_sha}`\n\n后端：`{backend_sha}`\n\n"
        "附 APK、SHA256SUMS.txt、构建清单与来源许可。\n", encoding="utf-8")
    print(json.dumps({"artifact": name, "sha256": manifest["sha256"]}))


if __name__ == "__main__":
    main()
