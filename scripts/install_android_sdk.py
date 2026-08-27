"""Install selected official Android packages from verified, resumable archives.

Uses Google's repository metadata and preserves existing incomplete directories.
SDK license acceptance remains with sdkmanager/bootstrap-android.ps1.
"""
import argparse
import json
from pathlib import Path, PurePosixPath
import stat
import time
import urllib.parse
import urllib.request
from uuid import uuid4
from xml.dom import minidom
import zipfile

from download_verified import digest, download

REPOSITORY = "https://dl.google.com/android/repository/repository2-3.xml"
PACKAGES = ("platform-tools", "platforms;android-35", "build-tools;35.0.0", "ndk;26.3.11579264")


def child(element, name):
    return next((n for n in element.childNodes if n.nodeType == n.ELEMENT_NODE and n.localName == name), None)


def text(element):
    return "".join(n.data for n in element.childNodes if n.nodeType in (n.TEXT_NODE, n.CDATA_SECTION_NODE)).strip()


def remote_package(document, path):
    matches = [n for n in document.getElementsByTagName("remotePackage") if n.getAttribute("path") == path]
    stable = [n for n in matches if (child(n, "channelRef") is None or child(n, "channelRef").getAttribute("ref") == "channel-0")
              and child(child(n, "revision"), "preview") is None]
    def revision(node):
        value = child(node, "revision")
        return tuple(int(text(child(value, part))) if child(value, part) is not None else 0 for part in ("major", "minor", "micro"))
    if not stable:
        raise ValueError(f"No stable official package found: {path}")
    return max(stable, key=revision)


def package_info(document, path, repository=REPOSITORY):
    remote = remote_package(document, path)
    archives = child(remote, "archives")
    archive = next(a for a in archives.childNodes if a.nodeType == a.ELEMENT_NODE and
                   (child(a, "host-os") is None or text(child(a, "host-os")) == "windows"))
    complete = child(archive, "complete")
    checksum = child(complete, "checksum")
    algorithm = checksum.getAttribute("type") or "sha1"
    if algorithm not in ("sha1", "sha256"):
        raise ValueError(f"Unsupported official checksum: {algorithm}")
    url = urllib.parse.urljoin(repository, text(child(complete, "url")))
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or parsed.hostname != "dl.google.com":
        raise ValueError("Unexpected repository archive origin")
    return {"path": path, "url": url, "size": int(text(child(complete, "size"))),
            "algorithm": algorithm, "checksum": text(checksum), "display_name": text(child(remote, "display-name"))}


def local_package_xml(document, path):
    # Preserve ALL namespace declarations, including prefixes used in xsi:type
    # attribute values, which ElementTree does not retain automatically.
    remote = remote_package(document, path)
    local = minidom.Document()
    root = local.createElement("localrepo:repository")
    root.setAttribute("xmlns:localrepo", "http://schemas.android.com/repository/android/common/02")
    for name, value in document.documentElement.attributes.items():
        if name == "xmlns" or name.startswith("xmlns:"):
            root.setAttribute(name, value)
    local.appendChild(root)
    uses_license = child(remote, "uses-license")
    if uses_license is not None:
        license_id = uses_license.getAttribute("ref")
        license_node = next(n for n in document.getElementsByTagName("license") if n.getAttribute("id") == license_id)
        root.appendChild(local.importNode(license_node, True))
    package = local.createElement("localPackage")
    package.setAttribute("path", path)
    package.setAttribute("obsolete", "false")
    for name in ("type-details", "revision", "display-name", "uses-license", "dependencies"):
        node = child(remote, name)
        if node is not None:
            package.appendChild(local.importNode(node, True))
    root.appendChild(package)
    return local.toxml(encoding="utf-8")


def inside(path, root):
    resolved = path.resolve()
    if resolved == root or not resolved.is_relative_to(root):
        raise ValueError(f"Path outside installation root: {path}")
    return resolved


def install(info, document, sdk, downloads):
    archive = downloads / Path(urllib.parse.urlparse(info["url"]).path).name
    download(info["url"], archive, info["size"], info["checksum"], algorithm=info["algorithm"])
    target = inside(sdk.joinpath(*info["path"].split(";")), sdk)
    receipt = target / ".jasmine-toolchain-receipt.json"
    archive_hash = digest(archive)
    if receipt.is_file():
        previous = json.loads(receipt.read_text(encoding="utf-8"))
        if previous.get("archive_sha256") == archive_hash and (target / "source.properties").is_file():
            print(f"Installed cache: {info['path']}", flush=True)
            return
    stage = inside(sdk / ".verified-staging" / uuid4().hex, sdk)
    stage.mkdir(parents=True)
    print(f"Extracting verified {archive.name}", flush=True)
    with zipfile.ZipFile(archive) as zipped:
        for entry in zipped.infolist():
            member = PurePosixPath(entry.filename)
            if member.is_absolute() or ".." in member.parts or "\\" in entry.filename or ":" in entry.filename:
                raise ValueError(f"Unsafe archive member: {entry.filename}")
            if stat.S_ISLNK(entry.external_attr >> 16):
                raise ValueError("Unexpected symlink in Windows SDK archive")
            inside(stage.joinpath(*member.parts), stage)
        zipped.extractall(stage)
    children = list(stage.iterdir())
    source = children[0] if len(children) == 1 and children[0].is_dir() else stage
    if not (source / "source.properties").is_file():
        raise ValueError("Archive layout has no source.properties; original installation preserved")
    (source / "package.xml").write_bytes(local_package_xml(document, info["path"]))
    (source / ".jasmine-toolchain-receipt.json").write_text(json.dumps({**info, "archive_sha256": archive_hash}, indent=2), encoding="utf-8")
    if target.exists():
        backup = inside(sdk / ".previous-incomplete" / (target.name + "-" + uuid4().hex), sdk)
        backup.parent.mkdir(parents=True, exist_ok=True)
        # Atomic directory rename with resolved source/destination containment;
        # no recursive deletion and no cross-shell path interpretation.
        inside(target, sdk).rename(backup)
        print(f"Previous directory preserved: {backup}", flush=True)
    target.parent.mkdir(parents=True, exist_ok=True)
    inside(source, sdk).rename(target)
    print(f"Installed: {info['path']}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk", type=Path, required=True)
    parser.add_argument("--downloads", type=Path, required=True)
    parser.add_argument("--package", action="append", choices=PACKAGES,
                        help="Prepare only these missing components; repeat for multiple packages.")
    args = parser.parse_args()
    sdk, downloads = args.sdk.resolve(), args.downloads.resolve()
    sdk.mkdir(parents=True, exist_ok=True)
    downloads.mkdir(parents=True, exist_ok=True)
    metadata = downloads / "android-repository2-3.xml"
    if not metadata.is_file():
        for attempt in range(3):
            try:
                with urllib.request.urlopen(REPOSITORY, timeout=45) as response:
                    data = response.read(16 * 1024 * 1024)
                document = minidom.parseString(data)
                for package in PACKAGES:
                    package_info(document, package)
                metadata.write_bytes(data)
                break
            except Exception:
                if attempt == 2:
                    raise
                time.sleep(2)
    document = minidom.parse(str(metadata))
    packages = [package_info(document, path) for path in PACKAGES]
    lock = {"repository": REPOSITORY, "metadata_sha256": digest(metadata), "packages": packages}
    lock_path = downloads / "android-packages.lock.json"
    if lock_path.is_file() and json.loads(lock_path.read_text(encoding="utf-8")) != lock:
        raise ValueError("Repository metadata differs from local package lock; preserved for review")
    lock_path.write_text(json.dumps(lock, indent=2), encoding="utf-8")
    for info in packages:
        if args.package is None or info["path"] in args.package:
            install(info, document, sdk, downloads)


if __name__ == "__main__":
    main()
