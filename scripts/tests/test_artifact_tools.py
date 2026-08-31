"""Synthetic/negative tests for build helpers; no network or real APK execution."""
import hashlib
import io
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile
from xml.dom import minidom

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import download_verified
import verify_local_apk
import install_android_sdk


def elf_fixture(alignment=16384, exports=True):
    data = bytearray(0x4010)
    data[:6] = b"\x7fELF\x02\x01"
    struct.pack_into("<HH", data, 16, 3, 183)
    struct.pack_into("<QQ", data, 32, 64, 0x100)
    struct.pack_into("<HHHHH", data, 54, 56, 1, 64, 3, 2)
    struct.pack_into("<IIQQQQQQ", data, 64, 1, 5, 0x4000, 0x4000, 0, 16, 16, alignment)
    names = b"\0Java_opensource_jenny_Jni_init\0Java_opensource_jenny_Jni_invoke\0"
    data[0x400:0x400 + len(names)] = names
    struct.pack_into("<IIQQQQIIQQ", data, 0x140, 0, 11, 0, 0, 0x300, 72, 2, 0, 8, 24)
    struct.pack_into("<IIQQQQIIQQ", data, 0x180, 0, 3, 0, 0, 0x400, len(names), 0, 0, 1, 0)
    if exports:
        for index, name in enumerate([1, names.index(b"Java_", 2)], 1):
            struct.pack_into("<IBBHQQ", data, 0x300 + 24 * index, name, 0x12, 0, 1, 0x4000, 4)
    return bytes(data)


class ArtifactToolsTest(unittest.TestCase):
    def test_exhausted_range_stops_queued_network_requests(self):
        with tempfile.TemporaryDirectory() as folder, \
                patch.object(download_verified.urllib.request, "urlopen", side_effect=OSError("synthetic network failure")) as request, \
                patch.object(download_verified.time, "sleep"):
            output = Path(folder) / "archive.zip"
            with self.assertRaisesRegex(RuntimeError, "Range .* failed"):
                download_verified.download("https://fixture.invalid/archive", output, 32 * 4 * 1024 * 1024, "0" * 64, workers=1)
            self.assertEqual(request.call_count, 4)
            self.assertFalse(output.exists())
            self.assertTrue(output.with_name("archive.zip.chunks").is_dir())

    def test_official_sdk_metadata_keeps_namespace_and_stable_revision(self):
        xml = '''<sdk:repository xmlns:sdk="http://schemas.android.com/sdk/android/repo/repository2/03"
          xmlns:generic="http://schemas.android.com/repository/android/generic/02"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <license id="android-sdk-license" type="text">Synthetic license text</license>
          <remotePackage path="platform-tools"><type-details xsi:type="generic:genericDetailsType"/>
            <revision><major>37</major><minor>0</minor><micro>1</micro></revision>
            <display-name>Tools</display-name><uses-license ref="android-sdk-license"/>
            <archives><archive><host-os>windows</host-os><complete><size>5</size>
              <checksum type="sha1">0123456789012345678901234567890123456789</checksum>
              <url>fixture.zip</url></complete></archive></archives><channelRef ref="channel-0"/>
          </remotePackage>
          <remotePackage path="platform-tools"><revision><major>38</major><preview>1</preview></revision>
            <channelRef ref="channel-1"/></remotePackage>
        </sdk:repository>'''
        document = minidom.parseString(xml)
        info = install_android_sdk.package_info(document, "platform-tools")
        self.assertEqual(info["size"], 5)
        self.assertEqual(info["algorithm"], "sha1")
        installed = minidom.parseString(install_android_sdk.local_package_xml(document, "platform-tools"))
        self.assertEqual(installed.documentElement.getAttribute("xmlns:generic"), "http://schemas.android.com/repository/android/generic/02")
        self.assertEqual(installed.getElementsByTagName("localPackage")[0].getAttribute("path"), "platform-tools")
        self.assertEqual(installed.getElementsByTagName("major")[0].firstChild.data, "37")

    def test_elf_alignment_and_jni_exports(self):
        report, exports = verify_local_apk.inspect_elf(elf_fixture())
        self.assertEqual(report["load_segment_alignments"], [16384])
        self.assertIn("Java_opensource_jenny_Jni_init", exports)
        with self.assertRaisesRegex(ValueError, "below 16 KiB"):
            verify_local_apk.inspect_elf(elf_fixture(alignment=4096))
        with self.assertRaises(ValueError):
            verify_local_apk.inspect_elf(b"not ELF")

    def test_package_hash_and_abi_are_checked(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            library = root / "librust.so"
            library.write_bytes(elf_fixture())

            def package(abi="arm64-v8a", data=None, material_font_size=1_100_000):
                apk = root / "fixture.apk"
                with zipfile.ZipFile(apk, "w") as archive:
                    archive.writestr("AndroidManifest.xml", b"synthetic manifest, not installable")
                    archive.writestr("classes.dex", b"synthetic dex")
                    archive.writestr(f"lib/{abi}/librust.so", library.read_bytes() if data is None else data)
                    archive.writestr(
                        verify_local_apk.FONT_MANIFEST,
                        json.dumps([{
                            "family": "MaterialIcons",
                            "fonts": [{"asset": "fonts/MaterialIcons-Regular.otf"}],
                        }]),
                    )
                    archive.writestr(verify_local_apk.MATERIAL_ICON_FONT, b"font".ljust(material_font_size, b"0"))
                return apk

            self.assertEqual(verify_local_apk.verify(package(), library)["abi"], "arm64-v8a")
            with self.assertRaisesRegex(ValueError, "Unexpected packaged ABI"):
                verify_local_apk.verify(package("x86_64"), library)
            with self.assertRaisesRegex(ValueError, "differs"):
                verify_local_apk.verify(package(data=elf_fixture() + b"changed"), library)
            with self.assertRaisesRegex(ValueError, "tree-shaken"):
                verify_local_apk.verify(package(material_font_size=16_000), library)
            library.write_bytes(elf_fixture(exports=False))
            with self.assertRaisesRegex(ValueError, "Missing JNI"):
                verify_local_apk.verify(package(), library)

    def test_download_resumes_complete_chunks_then_checks_full_hash(self):
        payload = bytes(range(256)) * (4 * 1024 * 1024 // 256) + b"tail"
        expected = hashlib.sha256(payload).hexdigest()
        requests = []

        def response(request, timeout):
            value = request.get_header("Range")
            requests.append(value)
            start, end = map(int, value.removeprefix("bytes=").split("-"))
            stream = io.BytesIO(payload[start:end + 1])
            stream.status = 206
            stream.headers = {"Content-Range": f"bytes {start}-{end}/{len(payload)}"}
            return stream

        with tempfile.TemporaryDirectory() as folder, patch.object(download_verified.urllib.request, "urlopen", response):
            root = Path(folder)
            prefix = root / "download.part"
            prefix.write_bytes(payload[:4 * 1024 * 1024])
            output = root / "archive.zip"
            download_verified.download("https://fixture.invalid/archive", output, len(payload), expected, resume_from=prefix)
            self.assertEqual(output.read_bytes(), payload)
            self.assertEqual(requests, [f"bytes=4194304-{len(payload) - 1}"])
            download_verified.download("https://fixture.invalid/archive", output, len(payload), expected)
            self.assertEqual(len(requests), 1)
            with self.assertRaisesRegex(ValueError, "different digest"):
                download_verified.download("https://fixture.invalid/archive", output, len(payload), "0" * 64)

    def test_corrupt_prefix_never_publishes_an_archive(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(download_verified.urllib.request, "urlopen") as request:
            root = Path(folder)
            prefix = root / "download.part"
            prefix.write_bytes(b"wrong")
            output = root / "archive.zip"
            with self.assertRaisesRegex(ValueError, "digest mismatch"):
                download_verified.download("https://fixture.invalid/archive", output, 5, hashlib.sha256(b"right").hexdigest(), resume_from=prefix)
            self.assertFalse(output.exists())
            request.assert_not_called()

    def test_incomplete_chunk_resumes_and_official_sha1_is_verified(self):
        payload = b"complete tool archive"
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            output = root / "archive.zip"
            chunks = root / "archive.zip.chunks"
            chunks.mkdir()
            (chunks / f"{0:012d}-{len(payload) - 1:012d}.partial").write_bytes(payload[:5])
            def response(request, timeout):
                self.assertEqual(request.get_header("Range"), f"bytes=5-{len(payload) - 1}")
                stream = io.BytesIO(payload[5:])
                stream.status = 206
                stream.headers = {"Content-Range": f"bytes 5-{len(payload) - 1}/{len(payload)}"}
                return stream
            with patch.object(download_verified.urllib.request, "urlopen", response):
                download_verified.download("https://fixture.invalid/archive", output, len(payload), hashlib.sha1(payload).hexdigest(), algorithm="sha1")
            self.assertEqual(output.read_bytes(), payload)


if __name__ == "__main__":
    unittest.main()
