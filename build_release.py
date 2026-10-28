#!/usr/bin/env python3
"""Build the source release, excluding local backups and interpreter caches."""
import hashlib
from pathlib import Path
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent
VERSION = '0.2.13'


def included(path):
    relative = path.relative_to(ROOT)
    return (path.is_file() and not path.is_symlink()
            and '__pycache__' not in relative.parts
            and '.git' not in relative.parts
            and not any('.bak' in part for part in relative.parts)
            and path.suffix not in {'.pyc', '.ERR', '.LOG', '.tdy'}
            and path.name != 'SHA256SUMS')


def main():
    files = sorted(path for path in ROOT.rglob('*') if included(path))
    manifest = ROOT / 'SHA256SUMS'
    manifest.write_text(''.join(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(ROOT).as_posix()}\n'
                                for path in files), encoding='utf-8')
    files.append(manifest)
    target = ROOT.parent / f'GeoSphereAPI-{VERSION}.zip'
    if target.exists():
        raise SystemExit(f'Refusing to overwrite existing release: {target}')
    with tempfile.TemporaryDirectory(prefix='geosphere-release-') as directory:
        temporary = Path(directory) / target.name
        with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED) as archive:
            for path in files:
                name = f'GeoSphereAPI-{VERSION}/{path.relative_to(ROOT).as_posix()}'
                archive.write(path, name)
        with zipfile.ZipFile(temporary) as archive:
            if archive.testzip() is not None:
                raise SystemExit('ZIP integrity check failed')
            for line in manifest.read_text().splitlines():
                digest, name = line.split('  ', 1)
                data = archive.read(f'GeoSphereAPI-{VERSION}/{name}')
                if hashlib.sha256(data).hexdigest() != digest:
                    raise SystemExit(f'Checksum mismatch: {name}')
        target.write_bytes(temporary.read_bytes())
    print(f'{target}: {len(files)} files, {target.stat().st_size} bytes')
    print(f'SHA256: {hashlib.sha256(target.read_bytes()).hexdigest()}')


if __name__ == '__main__':
    main()
