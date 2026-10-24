"""Generate static App Store support pages from the app's bundled legal text."""
from pathlib import Path
import argparse
import html
import json

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "store/site"


def legal_content():
    source = (ROOT / "BrowserUI/assets/legal.js").read_text(encoding="utf-8")
    prefix = "export default "
    if not source.startswith(prefix) or not source.rstrip().endswith(";"):
        raise ValueError("Expected a JSON-compatible default export for shared legal copy")
    return json.loads(source[len(prefix):].strip()[:-1])


def page(data, language, kind):
    copy = data["locales"][language]
    title = copy["name"] if kind == "index" else copy[kind + "Title"]
    prefix = "../" if language == "en" else ""
    alternate = ("../" if language == "en" else "en/") + kind + ".html"
    sections = copy.get(kind, [])
    content = "".join("<section><h2>" + html.escape(s["title"]) + "</h2>" +
                      "".join("<p>" + html.escape(p) + "</p>" for p in s["paragraphs"]) +
                      "</section>" for s in sections)
    if kind == "index":
        content = "<h1>" + html.escape(copy["homeTitle"]) + "</h1><p class='lead'>" + html.escape(copy["homeText"]) + "</p>"
        content += "<p>" + html.escape(copy["free"]) + "</p><div class='cards'>"
        for name in ("guide", "support", "privacy"):
            content += "<a class='card' href='" + name + ".html'>" + html.escape(copy[name + "Title"]) + " →</a>"
        content += "</div>"
    else:
        content = "<h1>" + html.escape(title) + "</h1><p class='muted'>" + html.escape(copy["updatedLabel"]) + "</p>" + content
    nav = "".join("<a href='" + name + ".html'>" + html.escape(copy[name + "Title"]) + "</a>" for name in ("guide", "support", "privacy"))
    localized_path = ("en/" if language == "en" else "") + ("" if kind == "index" else kind + ".html")
    return f'''<!doctype html>
<html lang="{language}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(title)} · ATMA</title><meta name="description" content="{html.escape(copy['homeText'], quote=True)}">
<link rel="canonical" href="{data['baseUrl']}{localized_path}"><link rel="icon" href="{prefix}assets/atma.png">
<link rel="stylesheet" href="{prefix}assets/site.css"></head>
<body><header><a class="brand" href="index.html"><img src="{prefix}assets/atma.png" alt="" width="40" height="40">ATMA</a>
<a href="{alternate}" lang="{'ru' if language == 'en' else 'en'}">{'Русский' if language == 'en' else 'English'}</a></header>
<main>{content}</main><footer><nav>{nav}</nav><p>{html.escape(copy['contact'])}</p>
<p><a href="mailto:{data['email']}">{data['email']}</a></p>
<p class="muted">© 2026 {html.escape(data['developer'])}</p></footer></body></html>
'''


CSS = '''*{box-sizing:border-box}html{color-scheme:light dark;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#f7f7f3;color:#22251e}body{margin:0}header,main,footer{max-width:900px;margin:auto;padding:28px 32px}header{display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid #d9dccf}a{color:#375746;text-underline-offset:4px}header a{text-decoration:none}.brand{display:flex;align-items:center;gap:12px;color:inherit;font-size:24px;font-weight:750;letter-spacing:.06em}.brand img{border-radius:10px}main{min-height:50vh;padding-top:64px;padding-bottom:64px}h1{font-size:clamp(32px,6vw,56px);line-height:1.08;letter-spacing:-.035em;max-width:750px;margin:0 0 28px}h2{font-size:23px;line-height:1.25;margin:36px 0 12px}p{font-size:17px;line-height:1.75;max-width:76ch;margin:12px 0}.lead{font-size:23px;line-height:1.5;max-width:30em}.muted{color:#62695d;font-size:14px}.cards{display:grid;gap:14px;margin-top:40px}.card{padding:20px 22px;background:#e9eddf;border:1px solid #cfd9bf;border-radius:18px;text-decoration:none;font-size:20px;font-weight:600}footer{border-top:1px solid #d9dccf;padding-bottom:48px}nav{display:flex;flex-wrap:wrap;gap:16px;margin-bottom:24px}nav a{font-size:14px}@media(max-width:500px){header,main,footer{padding-left:22px;padding-right:22px}main{padding-top:42px}h2{font-size:21px}.lead{font-size:21px}}@media(prefers-color-scheme:dark){html{background:#171a16;color:#f0f1e9}header,footer{border-color:#393f33}a{color:#bfd6b5}.muted{color:#adb6a5}.card{background:#252d21;border-color:#435039}}
'''


def expected_files():
    data = legal_content()
    result = {"assets/site.css": CSS.encode(),
              "assets/atma.png": (ROOT / "BrowserUI/assets/atma.png").read_bytes(),
              ".nojekyll": b""}
    for language in ("ru", "en"):
        for kind in ("index", "privacy", "support", "guide"):
            path = ("en/" if language == "en" else "") + kind + ".html"
            result[path] = page(data, language, kind).encode("utf-8")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail when committed pages differ from bundled text")
    args = parser.parse_args()
    files = expected_files()
    for name, value in files.items():
        target = SITE / name
        if args.check:
            if not target.is_file() or target.read_bytes() != value:
                raise SystemExit("Store page differs from shared source: " + name)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(value)
    print(json.dumps({"files": len(files), "sharedPolicy": True, "checked": args.check}))


if __name__ == "__main__":
    main()
