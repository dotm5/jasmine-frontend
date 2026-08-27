"""Verify an ARM64 APK contains exactly the supplied backend JNI library.

Static package checks only. Signature and ZIP alignment checks are performed by
Android's apksigner/zipalign in build-android.ps1; device tests are separate.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def inspect_elf(data):
    require(len(data) >= 64 and data[:6] == b"\x7fELF\x02\x01", "Expected little-endian ELF64")
    elf_type, machine = struct.unpack_from("<HH", data, 16)
    require(elf_type == 3 and machine == 183, "Expected ARM64 shared library")
    phoff, shoff = struct.unpack_from("<QQ", data, 32)
    phsize, phnum, shsize, shnum, _ = struct.unpack_from("<HHHHH", data, 54)
    require(phsize >= 56 and shsize >= 64, "Invalid ELF entry sizes")
    require(phoff + phsize * phnum <= len(data) and shoff + shsize * shnum <= len(data), "Truncated ELF tables")
    alignments = []
    for index in range(phnum):
        kind, _, offset, virtual, _, _, _, alignment = struct.unpack_from("<IIQQQQQQ", data, phoff + phsize * index)
        if kind == 1:
            require(alignment >= 16384 and alignment & (alignment - 1) == 0, "PT_LOAD alignment below 16 KiB")
            require(offset % alignment == virtual % alignment, "PT_LOAD offset/address alignment mismatch")
            alignments.append(alignment)
    require(alignments, "ELF has no loadable segment")
    sections = [struct.unpack_from("<IIQQQQIIQQ", data, shoff + shsize * i) for i in range(shnum)]
    exports = set()
    for section in sections:
        if section[1] != 11:  # SHT_DYNSYM
            continue
        require(section[9] >= 24 and section[6] < len(sections), "Invalid dynamic symbol table")
        strings_section = sections[section[6]]
        strings = data[strings_section[4]:strings_section[4] + strings_section[5]]
        for offset in range(section[4], section[4] + section[5], section[9]):
            name, info, _, index, _, _ = struct.unpack_from("<IBBHQQ", data, offset)
            if index != 0 and info & 15 == 2 and info >> 4 in (1, 2):
                exports.add(strings[name:].split(b"\0", 1)[0].decode("utf-8", "replace"))
    return {"machine": "AArch64", "load_segment_alignments": alignments}, exports


def verify(apk, library):
    expected = hashlib.sha256(library.read_bytes()).hexdigest()
    native_entry = "lib/arm64-v8a/librust.so"
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), "Duplicate APK ZIP entries")
        native_files = [name for name in names if name.startswith("lib/") and name.endswith(".so")]
        require({name.split("/")[1] for name in native_files} == {"arm64-v8a"}, "Unexpected packaged ABI")
        require(native_entry in names and "AndroidManifest.xml" in names and "classes.dex" in names, "Incomplete APK")
        libraries = {}
        for name in native_files:
            data = archive.read(name)
            report, exports = inspect_elf(data)
            report["sha256"] = hashlib.sha256(data).hexdigest()
            report["size"] = len(data)
            report["zip_compressed"] = archive.getinfo(name).compress_type != zipfile.ZIP_STORED
            if name == native_entry:
                require(report["sha256"] == expected, "Packaged JNI library differs from the supplied backend")
                required_exports = {"Java_opensource_jenny_Jni_init", "Java_opensource_jenny_Jni_invoke"}
                require(required_exports <= exports, "Missing JNI exports")
                report["jni_exports"] = sorted(required_exports)
                report["matches_supplied_library"] = True
            libraries[name] = report
    return {
        "apk_sha256": hashlib.sha256(apk.read_bytes()).hexdigest(),
        "expected_library_sha256": expected, "abi": "arm64-v8a", "libraries": libraries,
        "scope": "Static package/ELF checks only; no device execution or live API validation",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    report = verify(args.apk, args.library)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
