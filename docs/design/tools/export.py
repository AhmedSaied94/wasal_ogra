"""Convert Claude Design .dc.html artboards (style C) into standalone HTML files
with bundled fonts, then render 2x PNG screenshots.

usage: python3 export.py <design/project dir> <out dir>
"""
import json, re, shutil, sys, pathlib, asyncio

SRC = pathlib.Path(sys.argv[1])
OUT = pathlib.Path(sys.argv[2])
FONTPKG = pathlib.Path(__file__).parent / "fontpkg/node_modules/@fontsource"  # npm i @fontsource/marhey@5.3.0 @fontsource/readex-pro@5.3.0 (in tools/fontpkg)
SKIP = {"Main.dc.html", "A-Trip.dc.html", "B-Home.dc.html", "B-Trip.dc.html"}  # rejected style directions

canvas = json.loads((SRC / "canvas.json").read_text())
boards = canvas["boards"]

screens = OUT / "screens"
fonts = screens / "fonts"
png = OUT / "png"
for d in (screens, fonts, png):
    d.mkdir(parents=True, exist_ok=True)

# ---- fonts.css from fontsource (woff2 only, arabic + latin subsets) ----
css_parts = []
for fam, weights in (("marhey", (500, 600, 700)), ("readex-pro", (400, 500, 600, 700))):
    for w in weights:
        css = (FONTPKG / fam / f"{w}.css").read_text()
        for block in re.findall(r"/\*.*?\*/\s*@font-face\s*\{.*?\}", css, re.S):
            if "latin-ext" in block or "vietnamese" in block:
                continue
            m = re.search(r"url\(\./files/([^)]+?\.woff2)\)", block)
            if not m:
                continue
            fname = m.group(1)
            shutil.copy(FONTPKG / fam / "files" / fname, fonts / fname)
            block = re.sub(r"src:[^;]+;", f"src: url(./fonts/{fname}) format('woff2');", block)
            css_parts.append(block)
(screens / "fonts.css").write_text("\n\n".join(css_parts) + "\n")

PAGE_ORDER = {p["id"]: i for i, p in enumerate(canvas["pages"])}
manifest = []

for name in canvas["order"]:
    if name in SKIP:
        continue
    b = boards[name]
    src = (SRC / name).read_text()
    helmet = re.search(r"<helmet>(.*?)</helmet>", src, re.S).group(1)
    helmet = re.sub(r'<link[^>]+fonts\.googleapis[^>]+>', '<link rel="stylesheet" href="./fonts.css">', helmet)
    body = re.search(r"<x-dc>(.*?)</x-dc>", src, re.S).group(1)
    body = body.replace(re.search(r"<helmet>.*?</helmet>", body, re.S).group(0), "")
    body = re.sub(r'href="([A-Za-z0-9-]+)\.dc\.html"', r'href="\1.html"', body)
    title = re.search(r"<title>(.*?)</title>", src, re.S)
    title = title.group(1) if title else b["title"]
    stem = name.replace(".dc.html", "")
    html_tag = re.search(r"<html[^>]*>", src).group(0)
    html = f"""<!doctype html>
{html_tag}
<head>
<meta charset="utf-8">
<meta name="viewport" content="width={b['w']}">
<title>{title}</title>
<!-- Exported from the Claude Design canvas «وصّل الأجرة — Design». Artboard {b['w']}x{b['h']}. Do not edit; edit the canvas and re-export. -->
{helmet.strip()}
<style>html,body{{margin:0;background:#1D1A2B}}</style>
</head>
<body>
{body.strip()}
</body>
</html>
"""
    (screens / f"{stem}.html").write_text(html)
    manifest.append({"file": f"screens/{stem}.html", "png": f"png/{stem}.png", "artboard": stem,
                     "title": b["title"], "page": b["page"], "w": b["w"], "h": b["h"]})

(OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1))


async def render():
    from playwright.async_api import async_playwright
    async with async_playwright() as p:
        browser = await p.chromium.launch()
        for m in manifest:
            page = await browser.new_page(viewport={"width": m["w"], "height": m["h"]}, device_scale_factor=2)
            await page.goto((OUT / m["file"]).resolve().as_uri())
            await page.evaluate("document.fonts.ready")
            await page.wait_for_timeout(150)
            await page.screenshot(path=str(OUT / m["png"]), clip={"x": 0, "y": 0, "width": m["w"], "height": m["h"]})
            await page.close()
        await browser.close()

asyncio.run(render())
print(len(manifest), "screens exported")
