"""Replace vendor promotion data and the icon inside the dock tutorial."""

import base64
import io
import json
import xml.etree.ElementTree as ET
from urllib.parse import urlsplit

from PIL import Image, ImageDraw

from glyphs import make_outline


WALLET_LOGOS = (
    'assets/svg-icons/brave-icon.svg',
    'assets/svg-icons/wallet_logo_light.svg',
    'assets/svg-icons/wallet_logo_dark.svg',
    'assets/svg-icons/onboarding/brave-wallet.svg',
    'assets/svg-icons/onboarding/brave-wallet-dark.svg',
    'assets/svg-icons/onboarding/brave-wallet-with-coins.svg',
    'page/screens/send/assets/brave-logo-light.svg',
    'page/screens/send/assets/brave-logo-dark.svg',
)
LEO_LOGO_PATTERNS = ('brave-icon-*.svg', 'social-brave-*.svg', 'brave-origin-*.svg',
                     'pwa-brave-install-color.svg', 'brave-search-big-color.svg', 'brave-ask.svg')


def web_logo_paths(source):
    paths = [source / 'components/brave_wallet_ui' / relative for relative in WALLET_LOGOS]
    directory = source / 'node_modules/@brave/leo/icons'
    icons = sorted({path for pattern in LEO_LOGO_PATTERNS for path in directory.glob(pattern)})
    if not icons:
        raise ValueError('Install the pinned Leo icons before preparing web logos')
    return paths + icons


def prepare_web_logos(source, mark, update):
    outline = make_outline(mark)
    for path in web_logo_paths(source):
        root = ET.fromstring(path.read_bytes())
        if 'viewBox' in root.attrib:
            x, y, width, height = map(float, root.attrib['viewBox'].split())
        else:
            x = y = 0
            width, height = float(root.attrib['width']), float(root.attrib['height'])
        size = min(width, height)
        wordmark = width > height * 2
        left = x if wordmark else x + (width - size) / 2
        top = y + (height - size) / 2
        color = '#ffffff' if 'dark' in path.stem else '#202024'
        fill = 'currentColor' if ('monochrome' in path.stem or 'outline' in path.stem) else '#f3173c'
        label = ''
        if wordmark:
            label = f'<text x="{x + size * 1.1:g}" y="{y + height * .7:g}" fill="{color}" font-family="Arial,sans-serif" font-size="{height * .48:g}" font-weight="700">ATMA</text>'
        svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width:g}" height="{height:g}" '
               f'viewBox="{x:g} {y:g} {width:g} {height:g}" data-atma-logo="true">'
               f'<title>ATMA</title><path fill="{fill}" d="{outline}" '
               f'transform="translate({left:g} {top:g}) scale({size / 24:g})"/>{label}</svg>\n')
        update(path, svg, 'web_product_logos')


def is_vendor_favorite(site):
    host = (urlsplit(site.get('url', '')).hostname or '').lower()
    return host == 'brave.com' or host.endswith('.brave.com')


def prepare_resources(ios, square, update):
    path = ios / 'Sources/Brave/Frontend/Browser/Favorites/Data/top_sites_by_region.json'
    regions = json.loads(path.read_bytes())
    for region in regions:
        region['top_sites'] = [site for site in region['top_sites'] if not is_vendor_favorite(site)]
    update(path, json.dumps(regions, ensure_ascii=False, indent=2) + '\n', 'regional_favorites')

    icon = square.resize((58, 58), Image.Resampling.LANCZOS).convert('RGBA')
    mask = Image.new('L', icon.size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 57, 57), radius=12, fill=255)
    icon.putalpha(mask)
    image_bytes = io.BytesIO()
    icon.save(image_bytes, format='PNG')
    image_url = 'data:image/png;base64,' + base64.b64encode(image_bytes.getvalue()).decode('ascii')
    folder = ios / 'Sources/Onboarding/WelcomeFocus/Resources/LottieAssets'
    for filename in ('onboarding-add-to-dock-light.json', 'onboarding-add-to-dock-dark.json'):
        path = folder / filename
        data = json.loads(path.read_bytes())
        layers = data['layers']
        roots = [layer for layer in layers if layer.get('nm') in ('Brave icon.svg 1', 'ATMA icon')]
        if len(roots) != 1:
            raise ValueError(f'The pinned dock icon structure has changed: {filename}')
        parent = roots[0]
        descendants = {parent['ind']}
        while True:
            expanded = descendants | {layer['ind'] for layer in layers if layer.get('parent') in descendants}
            if expanded == descendants:
                break
            descendants = expanded
        descendants.remove(parent['ind'])
        layers = [layer for layer in layers if layer['ind'] not in descendants]
        parent['nm'] = 'ATMA icon'
        image_layer = {
            'ddd': 0, 'ind': parent['ind'] + 100000, 'ty': 2, 'nm': 'ATMA app icon',
            'refId': 'atma-icon', 'parent': parent['ind'],
            'ks': {'o': {'a': 0, 'k': 100}, 'r': {'a': 0, 'k': 0},
                   'p': {'a': 0, 'k': [0, 0, 0]}, 'a': {'a': 0, 'k': [0, 0, 0]},
                   's': {'a': 0, 'k': [100, 100, 100]}},
            'ao': 0, 'ip': parent.get('ip', data.get('ip', 0)),
            'op': parent.get('op', data['op']), 'st': 0, 'bm': 0,
        }
        layers.insert(layers.index(parent) + 1, image_layer)
        for layer in layers:
            if layer.get('nm') in ('Brave shadow.svg 1', 'ATMA shadow'):
                layer['nm'] = 'ATMA shadow'
                layer['hd'] = True
        data['layers'] = layers
        data['assets'] = [asset for asset in data['assets'] if asset['id'] != 'atma-icon']
        data['assets'].append({'id': 'atma-icon', 'w': 58, 'h': 58, 'u': '', 'p': image_url, 'e': 1})
        update(path, json.dumps(data, separators=(',', ':')) + '\n', 'dock_tutorial_icons')
