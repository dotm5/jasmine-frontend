"""Compatibility entry point; the implementation belongs to the backend repo."""
from pathlib import Path
import runpy

if __name__ == "__main__":
    runpy.run_path(
        str(Path(__file__).resolve().parents[1] / "native/scripts/sync_downloader_profile.py"),
        run_name="__main__",
    )
