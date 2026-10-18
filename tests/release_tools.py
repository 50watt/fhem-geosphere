#!/usr/bin/env python3
"""Check that the API installer backs up its target and preserves Weather core."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ReleaseTools(unittest.TestCase):
    def test_installer_upgrade(self):
        with tempfile.TemporaryDirectory(prefix='geosphere-install-test-') as directory:
            root = Path(directory)
            (root / 'FHEM').mkdir()
            (root / 'FHEM/59_Weather.pm').write_text('require FHEM::Core::Weather;')
            core = root / 'lib/FHEM/Core/Weather.pm'
            core.parent.mkdir(parents=True)
            core.write_bytes((ROOT / 'references/CoreWeather.pm').read_bytes())
            target = root / 'lib/FHEM/APIs/Weather/GeoSphereAPI.pm'
            target.parent.mkdir(parents=True)
            original = b'# installed previous version\n1;\n'
            target.write_bytes(original)
            command = ['python3', str(ROOT / 'install.py'), '--fhem-root', str(root)]
            subprocess.run(command + ['--check-only'], check=True, capture_output=True)
            self.assertEqual(target.read_bytes(), original)
            subprocess.run(command, check=True, capture_output=True)
            self.assertEqual(target.read_bytes(), (ROOT / 'lib/FHEM/APIs/Weather/GeoSphereAPI.pm').read_bytes())
            backups = list(target.parent.glob('GeoSphereAPI.pm.bak_*'))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_bytes(), original)
            self.assertEqual(core.read_bytes(), (ROOT / 'references/CoreWeather.pm').read_bytes())
            subprocess.run(command, check=True, capture_output=True)
            self.assertEqual(len(list(target.parent.glob('GeoSphereAPI.pm.bak_*'))), 1)


if __name__ == '__main__':
    unittest.main()
