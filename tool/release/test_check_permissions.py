"""Tests of check_permissions.py: the privacy promise of the release APK.

The Android build tools and the real APK are not needed: the tests feed the
script the output that aapt prints and the manifest that the build merges.

Run from the repository root:
    python -m unittest discover -s tool/release
"""

import importlib.util
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parent / 'check_permissions.py'
SPEC = importlib.util.spec_from_file_location('check_permissions', MODULE_PATH)
check_permissions = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check_permissions)

# The output that `aapt2 dump permissions` prints for a release APK.
AAPT2_OUTPUT = """
package: name='dev.mainshai.sonoglitch' versionCode='25' versionName='0.2.0'
uses-permission: name='android.permission.CAMERA'
uses-permission: name='android.permission.RECORD_AUDIO'
"""

# The same, with the network permission that the app must never declare.
AAPT2_OUTPUT_WITH_INTERNET = AAPT2_OUTPUT + (
    "uses-permission: name='android.permission.INTERNET'\n"
)

MERGED_MANIFEST = """<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
</manifest>
"""

MERGED_MANIFEST_WITH_INTERNET = MERGED_MANIFEST.replace(
    '</manifest>',
    '    <uses-permission android:name="android.permission.INTERNET" />\n'
    '</manifest>',
)


class ParseAaptPermissionsTest(unittest.TestCase):
    def test_it_reads_the_permissions_of_the_aapt_output(self):
        permissions = check_permissions.parse_aapt_permissions(AAPT2_OUTPUT)
        self.assertEqual(
            permissions,
            {'android.permission.CAMERA', 'android.permission.RECORD_AUDIO'},
        )

    def test_it_reads_the_sdk_permissions_too(self):
        output = (
            "uses-permission-sdk-23: name='android.permission.CAMERA'\n"
            "uses-permission: name='android.permission.RECORD_AUDIO'\n"
        )
        permissions = check_permissions.parse_aapt_permissions(output)
        self.assertEqual(
            permissions,
            {'android.permission.CAMERA', 'android.permission.RECORD_AUDIO'},
        )

    def test_it_ignores_the_other_lines(self):
        output = "package: name='dev.mainshai.sonoglitch' versionCode='25'\n"
        self.assertEqual(check_permissions.parse_aapt_permissions(output), set())


class ManifestPermissionsTest(unittest.TestCase):
    def write_manifest(self, text):
        directory = tempfile.mkdtemp(prefix='check-permissions-')
        self.addCleanup(_remove_tree, directory)
        path = Path(directory) / 'AndroidManifest.xml'
        path.write_text(text, encoding='utf-8')
        return path

    def test_it_reads_the_permissions_of_a_merged_manifest(self):
        path = self.write_manifest(MERGED_MANIFEST)
        self.assertEqual(
            check_permissions.manifest_permissions(path),
            {'android.permission.CAMERA', 'android.permission.RECORD_AUDIO'},
        )

    def test_it_fails_when_the_manifest_is_not_xml(self):
        path = self.write_manifest('not xml at all')
        with self.assertRaises(check_permissions.CheckError):
            check_permissions.manifest_permissions(path)


class CheckPermissionsTest(unittest.TestCase):
    def test_it_accepts_the_permissions_of_the_release(self):
        permissions = {'android.permission.CAMERA', 'android.permission.RECORD_AUDIO'}
        self.assertEqual(check_permissions.check_permissions(permissions), [])

    def test_it_rejects_the_internet_permission(self):
        problems = check_permissions.check_permissions(
            {'android.permission.CAMERA', 'android.permission.INTERNET'}
        )
        self.assertEqual(len(problems), 1)
        self.assertIn('android.permission.INTERNET', problems[0])
        self.assertIn('never to touch the network', problems[0])

    def test_it_rejects_the_network_state_permission(self):
        problems = check_permissions.check_permissions(
            {'android.permission.ACCESS_NETWORK_STATE'}
        )
        self.assertEqual(len(problems), 1)
        self.assertIn('android.permission.ACCESS_NETWORK_STATE', problems[0])

    def test_it_rejects_any_other_permission(self):
        problems = check_permissions.check_permissions(
            {'android.permission.QUERY_ALL_PACKAGES'}
        )
        self.assertEqual(len(problems), 1)
        self.assertIn('not in the allow-list', problems[0])


class ReadPermissionsTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.mkdtemp(prefix='check-permissions-')
        self.addCleanup(_remove_tree, self.directory)
        self.apk = Path(self.directory) / 'app-release.apk'
        self.apk.write_bytes(b'not a real APK')
        self.original_find_aapt = check_permissions.find_aapt

    def tearDown(self):
        check_permissions.find_aapt = self.original_find_aapt

    def test_it_uses_the_build_tools_when_they_are_installed(self):
        check_permissions.find_aapt = lambda: ['aapt2', 'dump', 'permissions']
        calls = []

        def runner(command):
            calls.append(command)
            return 0, AAPT2_OUTPUT, ''

        permissions, source = check_permissions.read_permissions(
            self.apk, runner=runner
        )
        self.assertEqual(calls, [['aapt2', 'dump', 'permissions', str(self.apk)]])
        self.assertEqual(source, 'aapt')
        self.assertEqual(
            permissions,
            {'android.permission.CAMERA', 'android.permission.RECORD_AUDIO'},
        )

    def test_it_falls_back_to_the_merged_manifest(self):
        check_permissions.find_aapt = lambda: None
        manifest = Path(self.directory) / 'AndroidManifest.xml'
        manifest.write_text(MERGED_MANIFEST, encoding='utf-8')

        def runner(command):
            raise AssertionError('the build tools must not be used')

        permissions, source = check_permissions.read_permissions(
            self.apk, manifest=manifest, runner=runner
        )
        self.assertEqual(
            permissions,
            {'android.permission.CAMERA', 'android.permission.RECORD_AUDIO'},
        )
        self.assertIn('merged manifest', source)

    def test_it_fails_when_nothing_can_read_the_permissions(self):
        check_permissions.find_aapt = lambda: None
        with self.assertRaises(check_permissions.CheckError):
            check_permissions.read_permissions(self.apk, runner=lambda command: None)


class MainTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.mkdtemp(prefix='check-permissions-')
        self.addCleanup(_remove_tree, self.directory)
        self.apk = Path(self.directory) / 'app-release.apk'
        self.apk.write_bytes(b'not a real APK')
        self.manifest = Path(self.directory) / 'AndroidManifest.xml'
        self.original_find_aapt = check_permissions.find_aapt
        check_permissions.find_aapt = lambda: None

    def tearDown(self):
        check_permissions.find_aapt = self.original_find_aapt

    def test_it_passes_when_the_apk_only_declares_the_allowed_permissions(self):
        self.manifest.write_text(MERGED_MANIFEST, encoding='utf-8')
        code = check_permissions.main([str(self.apk), '--manifest', str(self.manifest)])
        self.assertEqual(code, 0)

    def test_it_fails_when_the_apk_declares_the_internet_permission(self):
        self.manifest.write_text(MERGED_MANIFEST_WITH_INTERNET, encoding='utf-8')
        code = check_permissions.main([str(self.apk), '--manifest', str(self.manifest)])
        self.assertEqual(code, 1)

    def test_it_fails_when_there_is_no_apk(self):
        code = check_permissions.main([str(Path(self.directory) / 'missing.apk')])
        self.assertEqual(code, 2)


def _remove_tree(directory):
    import shutil

    shutil.rmtree(directory, ignore_errors=True)


if __name__ == '__main__':
    unittest.main()
