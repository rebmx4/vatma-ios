"""Replace vendor promotion data and the icon inside the dock tutorial."""

import base64
import io
import json
from urllib.parse import urlsplit

from PIL import Image, ImageDraw


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
