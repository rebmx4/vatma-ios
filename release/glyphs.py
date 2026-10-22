"""Replace branded SF Symbol outlines without changing the symbol template."""

import re
import xml.etree.ElementTree as ET

from PIL import Image, ImageOps


SVG = "{http://www.w3.org/2000/svg}"


def make_outline(mark):
    fitted = ImageOps.contain(mark, (112, 112), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (128, 128))
    canvas.paste(fitted, ((128 - fitted.width) // 2, (128 - fitted.height) // 2))
    alpha = canvas.getchannel("A")
    commands = []
    unit = 24 / 128
    for y in range(128):
        x = 0
        while x < 128:
            if alpha.getpixel((x, y)) < 96:
                x += 1
                continue
            start = x
            while x < 128 and alpha.getpixel((x, y)) >= 96:
                x += 1
            commands.append(f"M{start*unit:g} {y*unit:g}H{x*unit:g}V{(y+1)*unit:g}H{start*unit:g}Z")
    return "".join(commands)


def replace_symbol_outlines(source, mark, update):
    directory = source / "node_modules/@brave/leo-sf-symbols/symbols"
    paths = sorted(directory.glob("*brave*.svg"))
    if not paths:
        raise ValueError("Install the pinned iOS dependencies before preparing the SF Symbols")
    outline = make_outline(mark)
    count = 0
    for path in paths:
        text = path.read_bytes().decode("utf-8")
        tree = ET.fromstring(text)
        symbols = next((g for g in tree.iter(SVG + "g") if g.get("id") == "Symbols"), None)
        if symbols is None:
            raise ValueError(f"Unexpected SF Symbol template: {path.name}")
        for old in {p.get("d") for p in symbols.iter(SVG + "path")}:
            if not old:
                raise ValueError(f"Empty glyph in {path.name}")
            text = text.replace('d="' + old + '"', 'd="' + outline + '"')
        update(path, text, "native_symbol_logos")
        count += 1
    return count
