#!/usr/bin/env python3
"""Run offline provider, unmodified Weather-core and installer checks."""
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def run(command):
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    if result.returncode:
        raise SystemExit(result.stdout + result.stderr)
    return result.stdout


def main():
    print(run(['perl', '-c', str(ROOT / 'lib/FHEM/APIs/Weather/GeoSphereAPI.pm')]).strip())
    suites = sorted(str(path) for path in (ROOT / 'tests').glob('*.t') if path.name != 'weather_contract.t')
    output = run(['prove', '-q', *suites])
    match = re.search(r'Files=\d+, Tests=(\d+)', output)
    count = int(match[1])
    print(output.strip())
    for name in ['CoreWeather.pm', '2022_Weather.pm']:
        output = run(['perl', str(ROOT / 'tests/weather_contract.t'), str(ROOT / 'references' / name)])
        tests = int(re.search(r'^1\.\.(\d+)$', output, re.M)[1])
        count += tests
        print(f'{name}: {tests} assertions passed')
    run(['python3', str(ROOT / 'tests/release_tools.py')])
    print(f'TOTAL: {count} Perl assertions; 1 Python installer test passed. No production FHEM changes.')


if __name__ == '__main__':
    main()
