"""Keep upstream patch metadata reads within the build machine process limit."""

import argparse
from pathlib import Path


def prepare_build(source):
    path = source / 'build/commands/lib/gitPatcher.js'
    text = path.read_bytes().decode('utf-8')
    anchor = '      )\n    }\n\n    const patchSets = await Promise.all(prepOps)'
    replacement = '      )\n      if (prepOps.length % 8 === 0) {\n        await Promise.all(prepOps.slice(-8))\n      }\n    }\n\n    const patchSets = await Promise.all(prepOps)'
    if replacement in text:
        return
    if text.count(anchor) != 1:
        raise ValueError('The pinned patch preparation implementation has changed')
    path.write_bytes(text.replace(anchor, replacement).encode('utf-8'))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    prepare_build(parser.parse_args().source)
