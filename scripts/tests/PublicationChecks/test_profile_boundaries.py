from pathlib import Path
import re
import unittest

import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts"))
import names  # noqa: E402  architecture/names.json


class ProfileBoundaries(unittest.TestCase):
    def test_launcher_storage_and_default_preferences_are_centralized(self):
        unexpected = []
        files = [file for module in names.MODULES.values() for file in (ROOT / module['path']).rglob('*.swift')]
        self.assertTrue(files)
        for file in files:
            if file.name == 'AppDataProfile.swift':
                continue
            source = file.read_text()
            if 'UserDefaults.standard' in source or re.search(r'UserDefaults\s*=\s*\.standard', source):
                unexpected.append(str(file.relative_to(ROOT)) + ': unscoped preferences')
            if re.search(r'\.appendingPathComponent\("Library/Application Support/NXLibrary(?:/|"|\-)', source):
                unexpected.append(str(file.relative_to(ROOT)) + ': unscoped launcher directory')
        self.assertEqual(unexpected, [], '\n'.join(unexpected))
