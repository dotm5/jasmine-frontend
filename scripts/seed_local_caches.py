"""Seed project caches from existing locked dependencies, without network/installers.

Shared sources stay untouched. Credentials, global configuration and unrelated
packages are not copied. Existing destination cache files are preserved.
"""
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tomllib
from urllib.parse import urlparse


def sha256(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


class Seeder:
    def __init__(self, root):
        self.root = root.resolve()
        self.tools = (self.root / '.toolchains').resolve()
        if not self.tools.is_relative_to(self.root):
            raise ValueError('Toolchain directory escapes workspace')
        self.copied = 0
        self.reused = 0
        self.bytes = 0

    def copy(self, source, target):
        if source.is_symlink() or getattr(source, 'is_junction', lambda: False)():
            raise ValueError(f'Reparse point in source cache: {source}')
        if not target.resolve().is_relative_to(self.tools):
            raise ValueError(f'Cache destination escapes workspace: {target}')
        if target.exists():
            self.reused += 1
            return
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        if sha256(source) != sha256(target):
            raise ValueError(f'Copy verification failed: {target}')
        self.copied += 1
        self.bytes += target.stat().st_size

    def tree(self, source, target):
        if source.is_symlink() or getattr(source, 'is_junction', lambda: False)():
            raise ValueError(f'Reparse point in source cache: {source}')
        for entry in source.iterdir():
            if entry.is_symlink() or getattr(entry, 'is_junction', lambda: False)():
                raise ValueError(f'Reparse point in source cache: {entry}')
            destination = target / entry.name
            if entry.is_dir():
                self.tree(entry, destination)
            else:
                self.copy(entry, destination)


def index_name(name):
    if len(name) < 3:
        return f'{len(name)}/{name}'
    if len(name) == 3:
        return f'3/{name[0]}/{name}'
    return f'{name[:2]}/{name[2:4]}/{name}'


def main():
    root = Path(__file__).resolve().parents[1]
    config = json.loads((root / '.toolchains/toolchain-paths.json').read_text('utf-8-sig'))
    seed = Seeder(root)
    cargo_source = Path(config['seedSources']['cargoHome']).resolve()
    pub_source = Path(config['seedSources']['pubCache']).resolve()
    cargo = root / '.toolchains/cargo-home'
    pub = root / '.toolchains/pub-cache'
    if cargo_source == cargo.resolve() or pub_source == pub.resolve():
        raise ValueError('Seed source must be the existing read-only cache, not the destination')
    lock = tomllib.loads((root / 'native/Cargo.lock').read_text('utf-8'))
    registry = [p for p in lock['package'] if p.get('source', '').startswith('registry+')]
    git = [p for p in lock['package'] if p.get('source', '').startswith('git+')]
    missing_crates = []
    archive_count = 0
    index_dirs = list((cargo_source / 'registry/index').glob('index.crates.io-*'))
    for package in registry:
        if package['source'] != 'registry+https://github.com/rust-lang/crates.io-index':
            raise ValueError('Unexpected registry; credentials are not copied')
        filename = f"{package['name']}-{package['version']}.crate"
        found = False
        for index in index_dirs:
            configuration = index / 'config.json'
            if configuration.exists():
                data = json.loads(configuration.read_text('utf-8'))
                if urlparse(data['dl']).hostname not in ('static.crates.io', 'crates.io'):
                    raise ValueError('Unexpected crate download origin in shared index')
                seed.copy(configuration, cargo / 'registry/index' / index.name / 'config.json')
            entry = index / '.cache' / index_name(package['name'])
            if entry.exists():
                seed.copy(entry, cargo / 'registry/index' / index.name / '.cache' / index_name(package['name']))
            archive = cargo_source / 'registry/cache' / index.name / filename
            if archive.exists():
                if sha256(archive) != package['checksum']:
                    raise ValueError(f'Existing crate differs from Cargo.lock: {filename}')
                destination = cargo / 'registry/cache' / index.name / filename
                seed.copy(archive, destination)
                if sha256(destination) != package['checksum']:
                    raise ValueError(f'Project crate differs from Cargo.lock: {filename}')
                found = True
                archive_count += 1
                break
        if not found:
            missing_crates.append(filename)
    git_sources = []
    for package in git:
        if not package['source'].startswith('git+https://github.com/lanyeeee/lopdf?'):
            raise ValueError('Unexpected Git dependency; select its cache explicitly')
        commit = package['source'].split('#')[-1]
        candidates = list((cargo_source / 'git/db').glob('lopdf-*'))
        source = next((p for p in candidates if subprocess.run(
            ['git', '--git-dir', str(p), 'cat-file', '-e', commit + '^{commit}'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0), None)
        if source is None:
            raise ValueError('Pinned lopdf commit is not in the existing cache')
        if (source / 'objects/info/alternates').exists():
            raise ValueError('Git seed has external object alternates; inspect before copying')
        seed.tree(source, cargo / 'git/db' / source.name)
        git_sources.append({'name': package['name'], 'commit': commit})
    pub_lock = (root / 'pubspec.lock').read_text('utf-8')
    hosted_count = 0
    missing_pub = []
    for name, block in re.findall(r'^  ([\w_]+):\r?\n(.*?)(?=^  [\w_]+:|^sdks:|\Z)', pub_lock, re.M | re.S):
        if not re.search(r'^    source: hosted\s*$', block, re.M):
            continue
        version = re.search(r'^    version: ["\']?([^"\'\s]+)', block, re.M).group(1)
        checksum = re.search(r'^      sha256: ["\']?([0-9a-f]{64})', block, re.M).group(1)
        url = re.search(r'^      url: ["\']?([^"\'\s]+)', block, re.M).group(1)
        if url != 'https://pub.dev':
            raise ValueError('Unexpected Pub host; credentials are not copied')
        package = f'{name}-{version}'
        source = pub_source / 'hosted/pub.dev' / package
        hash_file = pub_source / 'hosted-hashes/pub.dev' / (package + '.sha256')
        if not source.is_dir() or not hash_file.is_file():
            missing_pub.append(package)
            continue
        if hash_file.read_text('utf-8').strip() != checksum:
            raise ValueError(f'Existing Pub archive receipt differs from lock: {package}')
        seed.tree(source, pub / 'hosted/pub.dev' / package)
        seed.copy(hash_file, pub / 'hosted-hashes/pub.dev' / hash_file.name)
        hosted_count += 1
    report = {
        'strategy': 'copy only selected cache data; no installers, downloads or source modification',
        'filesCopied': seed.copied, 'filesAlreadyPresent': seed.reused, 'bytesCopied': seed.bytes,
        'cargoArchivesReused': archive_count, 'cargoLockRegistryEntries': len(registry),
        'notPresentInSharedCargoCache': missing_crates, 'gitDependencies': git_sources,
        'pubPackagesReused': hosted_count, 'notPresentInSharedPubCache': missing_pub,
        'cargoLockSha256': sha256(root / 'native/Cargo.lock'), 'pubLockSha256': sha256(root / 'pubspec.lock'),
    }
    (root / '.toolchains/cache-seed-report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2), flush=True)


if __name__ == '__main__':
    main()
