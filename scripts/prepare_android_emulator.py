"""Prepare only the missing project-local emulator packages; never install drivers.

Reuses the existing verified/resumable downloader, SDK installer, JDK and adb.
The separate lock prevents this optional runtime from changing the build SDK lock.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import urllib.request
from xml.dom import minidom

from download_verified import digest
import install_android_sdk as sdk_tools


SOURCES = (
    ("emulator", sdk_tools.REPOSITORY, "android-repository2-3.xml", ("emulator.exe",)),
    ("system-images;android-30;google_apis;x86_64",
     "https://dl.google.com/android/repository/sys-img/google_apis/sys-img2-3.xml",
     "google-apis-system-images.xml", ("system.img", "ramdisk.img", "kernel-ranchu")),
)


def license_hash(value):
    # Match the installed SDK repository-core's TrimStringAdapter, preserving
    # paragraph breaks instead of collapsing all whitespace (License.getValue).
    value = re.sub(r"(?<=\s)[ \t]*", "", value)
    value = re.sub(r"(?<!\n)\n(?!\n)", " ", value)
    value = re.sub(r" +", " ", value).strip()
    return hashlib.sha1(value.encode("utf-8")).hexdigest()


def check_license(document, package, sdk):
    remote = sdk_tools.remote_package(document, package)
    license_id = sdk_tools.child(remote, "uses-license").getAttribute("ref")
    node = next(n for n in document.getElementsByTagName("license") if n.getAttribute("id") == license_id)
    expected = license_hash(sdk_tools.text(node))
    accepted_file = sdk / "licenses" / license_id
    accepted = accepted_file.read_text(encoding="utf-8").split() if accepted_file.is_file() else []
    if expected not in accepted:
        raise ValueError(f"Review/accept the SDK license before installation: {license_id} ({expected})")
    return {"id": license_id, "sha1": expected, "reused_existing_acceptance": True}


def installed(info, sdk, sentinels):
    target = sdk_tools.inside(sdk.joinpath(*info["path"].split(";")), sdk)
    receipt_file = target / ".jasmine-toolchain-receipt.json"
    if not receipt_file.is_file():
        return False
    receipt = json.loads(receipt_file.read_text(encoding="utf-8"))
    return (all(receipt.get(k) == info[k] for k in ("path", "url", "size", "algorithm", "checksum"))
            and bool(receipt.get("archive_sha256"))
            and all((target / file).is_file() for file in ("package.xml", "source.properties", *sentinels)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check local metadata/licenses/cache without installing.")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    sdk = sdk_tools.inside(root / ".toolchains" / "android-sdk", root)
    downloads = sdk_tools.inside(root / ".toolchains" / "downloads", root)
    if not (sdk / "platform-tools" / "adb.exe").is_file():
        raise ValueError("Bind/reuse the existing local SDK before preparing an emulator")
    items = []
    for package, repository, filename, sentinels in SOURCES:
        metadata = downloads / filename
        if not metadata.is_file():
            if args.check:
                raise ValueError(f"Metadata not cached yet: {metadata}")
            with urllib.request.urlopen(repository, timeout=45) as response:
                data = response.read(16 * 1024 * 1024)
            document = minidom.parseString(data)
            sdk_tools.package_info(document, package, repository)
            metadata.write_bytes(data)
        document = minidom.parse(str(metadata))
        info = sdk_tools.package_info(document, package, repository)
        license_info = check_license(document, package, sdk)
        items.append((info, document, sentinels, {
            **info, "repository": repository, "metadata_sha256": digest(metadata),
            "license": license_info,
        }))
    lock = {"schema": 1, "purpose": "Optional local Android smoke test runtime",
            "packages": [item[3] for item in items]}
    lock_file = downloads / "android-emulator-packages.lock.json"
    if lock_file.is_file() and json.loads(lock_file.read_text(encoding="utf-8")) != lock:
        raise ValueError("Emulator metadata differs from the existing lock; review before updating")
    if not args.check and not lock_file.exists():
        lock_file.write_text(json.dumps(lock, indent=2) + "\n", encoding="utf-8")
    for info, document, sentinels, _ in items:
        if installed(info, sdk, sentinels):
            print(f"Reusing installed package (no download/install): {info['path']}", flush=True)
        elif args.check:
            print(f"Missing: {info['path']} ({info['size']} bytes, license already accepted)", flush=True)
        else:
            sdk_tools.install(info, document, sdk, downloads)
            if not installed(info, sdk, sentinels):
                raise ValueError(f"Installed package is incomplete: {info['path']}")


if __name__ == "__main__":
    main()
