import importlib.util
import os
import plistlib
import tempfile
import unittest
import zipfile
from pathlib import Path


MODULE = Path(__file__).resolve().parents[1] / 'release/verify_ipa.py'
spec = importlib.util.spec_from_file_location('atma_ipa', MODULE)
ipa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ipa)


class ArtifactVerificationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR') or os.environ.get('TEMP'))
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / 'fixture.ipa'

    def make_archive(self, bundle=None, build='9', core=True, extension=False):
        config = ipa.CONFIG
        info = {
            'CFBundleIdentifier': bundle or config['bundle_id'],
            'CFBundleDisplayName': config['product_name'],
            'CFBundleName': config['product_name'],
            'CFBundleShortVersionString': config['marketing_version'],
            'CFBundleVersion': build,
        }
        with zipfile.ZipFile(self.path, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr('Payload/Client.app/Info.plist', plistlib.dumps(info))
            if core:
                archive.writestr('Payload/Client.app/Frameworks/BraveCore.framework/BraveCore', b'fixture' * 150_000)
            if extension:
                archive.writestr('Payload/Client.app/PlugIns/Unknown.appex/Info.plist', plistlib.dumps({}))

    def test_accepts_expected_browser_metadata(self):
        self.make_archive()
        self.assertEqual(ipa.verify(self.path, '9')['bundle_id'], ipa.CONFIG['bundle_id'])

    def test_rejects_a_different_apple_app(self):
        self.make_archive(bundle='com.example.other-app')
        with self.assertRaisesRegex(ValueError, 'CFBundleIdentifier'):
            ipa.verify(self.path, '9')

    def test_rejects_unexpected_build_number(self):
        self.make_archive(build='8')
        with self.assertRaisesRegex(ValueError, 'CFBundleVersion'):
            ipa.verify(self.path, '9')

    def test_rejects_an_app_without_native_browser_core(self):
        self.make_archive(core=False)
        with self.assertRaisesRegex(ValueError, 'core'):
            ipa.verify(self.path, '9')

    def test_rejects_unprovisioned_extensions(self):
        self.make_archive(extension=True)
        with self.assertRaisesRegex(ValueError, 'extensions'):
            ipa.verify(self.path, '9')


if __name__ == '__main__':
    unittest.main()
