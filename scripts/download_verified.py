"""Resumable parallel HTTPS range download with a required pinned digest.

Complete chunks and partial chunk ranges are resumed. Old single-stream
downloads may seed chunks; publication requires the complete pinned digest.
"""
import argparse
from concurrent.futures import CancelledError, ThreadPoolExecutor, as_completed
import hashlib
import json
from pathlib import Path
import shutil
import threading
import time
import urllib.request


def digest(path, algorithm="sha256"):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, algorithm).hexdigest()


def download(url, output, size, sha256, workers=8, resume_from=None, algorithm="sha256"):
    if not url.startswith("https://") or size <= 0:
        raise ValueError("A HTTPS URL and positive pinned size are required")
    # Android's legacy repository publishes SHA-1. Use that official digest over
    # HTTPS when required, then record an additional local SHA-256; never skip it.
    if algorithm not in ("sha256", "sha1") or len(sha256) != {"sha256": 64, "sha1": 40}.get(algorithm) or any(c not in "0123456789abcdef" for c in sha256):
        raise ValueError("A supported pinned digest is required")
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        if output.stat().st_size == size and digest(output, algorithm) == sha256:
            print(f"Verified cache: {output.name}", flush=True)
            return
        raise ValueError(f"Existing output has a different digest: {output}")
    chunk_size = 4 * 1024 * 1024
    chunks = output.with_name(output.name + ".chunks")
    chunks.mkdir(exist_ok=True)
    manifest = chunks / "manifest.json"
    expected = {"url": url, "size": size, "sha256": sha256, "chunk_size": chunk_size}
    if algorithm != "sha256":
        expected = {"url": url, "size": size, "sha1": sha256, "chunk_size": chunk_size}
    if manifest.exists():
        if json.loads(manifest.read_text(encoding="utf-8")) != expected:
            raise ValueError("Chunk cache belongs to another download")
    else:
        manifest.write_text(json.dumps(expected, indent=2), encoding="utf-8")
    ranges = [(start, min(start + chunk_size, size) - 1) for start in range(0, size, chunk_size)]

    def chunk_path(start, end):
        return chunks / f"{start:012d}-{end:012d}.bin"

    # Import complete prefix chunks only; never change the old partial file.
    if resume_from and resume_from.is_file():
        prefix_size = resume_from.stat().st_size
        with resume_from.open("rb") as prefix:
            for start, end in ranges:
                if end >= prefix_size:
                    break
                target = chunk_path(start, end)
                if not target.exists():
                    prefix.seek(start)
                    data = prefix.read(end - start + 1)
                    if len(data) == end - start + 1:
                        target.write_bytes(data)

    stopped = threading.Event()

    def get_chunk(start, end):
        if stopped.is_set():
            raise CancelledError("Another range failed; chunks retained")
        target = chunk_path(start, end)
        length = end - start + 1
        if target.exists() and target.stat().st_size == length:
            return length
        last_error = None
        for attempt in range(4):
            try:
                if stopped.is_set():
                    raise CancelledError("Another range failed; chunks retained")
                started = time.monotonic()
                temporary = target.with_suffix(".partial")
                received = temporary.stat().st_size if temporary.exists() else 0
                if received > length:
                    raise ValueError("Partial chunk is larger than its declared range")
                if received == length:
                    temporary.replace(target)
                    return length
                request_start = start + received
                request = urllib.request.Request(url, headers={
                    "Range": f"bytes={request_start}-{end}", "Accept-Encoding": "identity",
                    "User-Agent": "JasmineLocal-ToolchainDownloader/1.0",
                })
                with urllib.request.urlopen(request, timeout=45) as response:
                    if response.status != 206 or response.headers.get("Content-Range") != f"bytes {request_start}-{end}/{size}":
                        raise ValueError("Server did not honor the exact byte range")
                    with temporary.open("ab") as stream:
                        while received < length:
                            if stopped.is_set():
                                raise CancelledError("Another range failed; partial chunk retained")
                            if time.monotonic() - started > 150:
                                raise TimeoutError("Chunk exceeded its total time budget")
                            data = response.read(min(64 * 1024, length - received))
                            if not data:
                                raise ValueError(f"Short chunk: {received} != {length}")
                            stream.write(data)
                            received += len(data)
                temporary.replace(target)
                return length
            except CancelledError:
                raise
            except Exception as error:
                last_error = error
                print(f"Retry range {start}-{end} ({attempt + 1}/4): {error}", flush=True)
                if attempt < 3:
                    time.sleep(min(attempt + 1, 3))
        stopped.set()
        raise RuntimeError(f"Range {start}-{end} failed: {last_error}")

    completed = 0
    with ThreadPoolExecutor(max_workers=max(1, min(workers, 12))) as executor:
        futures = [executor.submit(get_chunk, start, end) for start, end in ranges]
        try:
            for future in as_completed(futures):
                try:
                    completed += future.result()
                except CancelledError:
                    # The original failed range will surface its precise error.
                    continue
                print(f"{output.name}: {completed * 100 // size}% ({completed}/{size})", flush=True)
        except BaseException:
            stopped.set()
            # Do not drain hundreds of queued network retries after one range
            # exhausts its budget; active reads retain the normal socket timeout.
            for future in futures:
                future.cancel()
            raise
    assembled = output.with_name(output.name + ".assembled")
    with assembled.open("wb") as destination:
        for start, end in ranges:
            with chunk_path(start, end).open("rb") as source:
                shutil.copyfileobj(source, destination)
    if assembled.stat().st_size != size or digest(assembled, algorithm) != sha256:
        raise ValueError("Complete archive digest mismatch; evidence and chunks retained")
    if output.exists():
        raise FileExistsError("Output appeared during download; leaving it unchanged")
    assembled.rename(output)
    print(f"{algorithm.upper()} verified: {sha256}  {output.name}", flush=True)
    if algorithm != "sha256":
        print(f"Local SHA256: {digest(output)}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url")
    parser.add_argument("output", type=Path)
    parser.add_argument("--size", type=int, required=True)
    checksums = parser.add_mutually_exclusive_group(required=True)
    checksums.add_argument("--sha256")
    checksums.add_argument("--sha1")
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--resume-from", type=Path)
    args = parser.parse_args()
    download(args.url, args.output, args.size, (args.sha256 or args.sha1).lower(), args.workers, args.resume_from,
             algorithm="sha256" if args.sha256 else "sha1")


if __name__ == "__main__":
    main()
