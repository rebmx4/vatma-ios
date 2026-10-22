import argparse
import json
import plistlib
import zipfile
from pathlib import Path


CONFIG = json.loads((Path(__file__).resolve().parent / 'config.json').read_text(encoding='utf-8'))


def verify(path, expected_build):
    with zipfile.ZipFile(path) as archive:
        roots = [name for name in archive.namelist() if name.count('/') == 2 and name.startswith('Payload/') and name.endswith('.app/Info.plist')]
        if len(roots) != 1:
            raise ValueError('Expected exactly one browser application')
        info_path = roots[0]
        info = plistlib.loads(archive.read(info_path))
        expected = {'CFBundleIdentifier': CONFIG['bundle_id'], 'CFBundleDisplayName': CONFIG['product_name'], 'CFBundleName': CONFIG['product_name'], 'CFBundleShortVersionString': CONFIG['marketing_version'], 'CFBundleVersion': str(expected_build)}
        for key, value in expected.items():
            if info.get(key) != value:
                raise ValueError(f'Unexpected {key}: {info.get(key)!r}')
        app_root = info_path.removesuffix('Info.plist')
        core_path = app_root + 'Frameworks/BraveCore.framework/BraveCore'
        try:
            core_size = archive.getinfo(core_path).file_size
        except KeyError as error:
            raise ValueError('Native browser core is missing') from error
        if core_size < 1_000_000:
            raise ValueError('Native browser core is missing')
        if any(name.startswith(app_root + 'PlugIns/') and name.endswith('.appex/Info.plist') for name in archive.namelist()):
            raise ValueError('Unprovisioned service extensions were included')
        return {'ipa': str(path), 'display_name': info['CFBundleDisplayName'], 'bundle_id': info['CFBundleIdentifier'], 'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'], 'native_core_bytes': core_size}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('ipa', type=Path)
    parser.add_argument('--build', required=True)
    arguments = parser.parse_args()
    print(json.dumps(verify(arguments.ipa, arguments.build)))
