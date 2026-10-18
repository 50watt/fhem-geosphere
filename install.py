#!/usr/bin/env python3
"""Install only GeoSphereAPI.pm; never issue FHEM commands or edit its configuration."""
import argparse
import datetime as dt
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fhem-root', type=Path, default=Path('/opt/fhem'))
    parser.add_argument('--check-only', action='store_true')
    args = parser.parse_args()
    root = args.fhem_root.resolve()
    weather = root / 'FHEM/59_Weather.pm'
    if not weather.is_file():
        raise SystemExit(f'Abbruch: {weather} fehlt.')
    code = weather.read_text(encoding='utf-8')
    core = root / 'lib/FHEM/Core/Weather.pm'
    if 'require FHEM::Core::Weather' in code:
        if not core.is_file():
            raise SystemExit(f'Abbruch: {core} fehlt.')
        code = core.read_text(encoding='utf-8')
    if "FHEM/APIs/Weather/" not in code or 'FHEM::APIs::Weather::' not in code:
        raise SystemExit('Abbruch: Weather-API-Ladeschnittstelle nicht erkannt; nichts geändert.')
    source = Path(__file__).resolve().parent / 'lib/FHEM/APIs/Weather/GeoSphereAPI.pm'
    # Run the required Perl syntax check before touching an installed file.
    subprocess.run(['perl', '-c', str(source)], check=True)
    target = root / 'lib/FHEM/APIs/Weather/GeoSphereAPI.pm'
    print(f'Weather-Schnittstelle erkannt. Ziel: {target}', flush=True)
    if args.check_only:
        print('Prüfung erfolgreich; keine Dateien geändert.')
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.is_symlink():
        raise SystemExit('Abbruch: Zieldatei ist ein symbolischer Link.')
    if target.exists():
        if target.read_bytes() == source.read_bytes():
            print('Identische Version bereits installiert; keine Änderung.')
            return
        backup = target.with_name(target.name + '.bak_' + dt.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
        # Exclusive creation prevents accidental overwrite of a previous backup.
        with backup.open('xb') as output, target.open('rb') as old:
            shutil.copyfileobj(old, output)
        shutil.copystat(target, backup)
        print(f'Sicherung: {backup}')
    handle, temporary = tempfile.mkstemp(prefix='.GeoSphereAPI.', dir=target.parent)
    try:
        with os.fdopen(handle, 'wb') as output:
            output.write(source.read_bytes())
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print(f'Installiert: {target}')
    print(f'SHA256: {hashlib.sha256(target.read_bytes()).hexdigest()}')
    print('Keine FHEM-Konfiguration geändert; kein Reload ausgeführt.')


if __name__ == '__main__':
    main()
