"""Measure every visible box in each exported artboard and write boxes/<Artboard>.json.

Each record: id, parent, depth, tag, role (text|icon|art|box|tap), label, text,
x, y, w, h (logical px, artboard origin) and the computed style that matters
for a Flutter rebuild (background, color, font, radius, shadow, border, opacity).
usage: python3 boxes.py <out dir>
"""
import asyncio, json, os, sys
from playwright.async_api import async_playwright

OUT = sys.argv[1]
JS = r"""
() => {
  const root = document.body.firstElementChild;
  const R0 = root.getBoundingClientRect();
  const recs = []; const ids = new Map();
  const norm = c => c === 'rgba(0, 0, 0, 0)' ? null : c;
  const ownText = el => Array.from(el.childNodes).filter(n => n.nodeType === 3).map(n => n.textContent).join(' ').replace(/\s+/g, ' ').trim();
  const walk = (el, depth, parent) => {
    if (el.tagName === 'SCRIPT' || el.tagName === 'STYLE' || el.tagName === 'LINK') return;
    const r = el.getBoundingClientRect();
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden') return;
    const isSvg = el.tagName.toLowerCase() === 'svg';
    const text = isSvg ? '' : ownText(el);
    const bg = norm(cs.backgroundColor);
    const shadow = cs.boxShadow !== 'none' ? cs.boxShadow : null;
    const border = (parseFloat(cs.borderTopWidth) > 0) ? `${cs.borderTopWidth} ${cs.borderTopStyle} ${cs.borderTopColor}` : null;
    const label = el.getAttribute('aria-label');
    const tap = el.tagName === 'A' || el.tagName === 'BUTTON' || el.getAttribute('role') === 'button';
    const visual = bg || shadow || border || text || label || isSvg || tap || el.tagName === 'INPUT';
    let myId = parent;
    if (visual && r.width > 0 && r.height > 0) {
      myId = recs.length;
      const rec = {
        id: myId, parent, depth, tag: el.tagName.toLowerCase(),
        role: tap ? 'tap' : isSvg ? (r.width <= 32 && r.height <= 32 ? 'icon' : 'art') : text ? 'text' : 'box',
        x: +(r.left - R0.left).toFixed(1), y: +(r.top - R0.top).toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1)
      };
      if (label) rec.label = label;
      if (text) rec.text = text.slice(0, 120);
      if (el.getAttribute('href')) rec.href = el.getAttribute('href').replace('.html', '');
      if (bg) rec.bg = bg;
      if (text || el.tagName === 'INPUT') {
        rec.color = cs.color; rec.font = `${cs.fontFamily.split(',')[0].replace(/"/g,'')} ${cs.fontWeight} ${cs.fontSize}`;
        rec.lineHeight = cs.lineHeight; rec.align = cs.textAlign;
      }
      if (cs.borderTopLeftRadius !== '0px' || cs.borderBottomLeftRadius !== '0px') {
        const rr = [cs.borderTopLeftRadius, cs.borderTopRightRadius, cs.borderBottomRightRadius, cs.borderBottomLeftRadius];
        rec.radius = rr.every(v => v === rr[0]) ? rr[0] : rr.join(' ');
      }
      if (shadow) rec.shadow = shadow;
      if (border) rec.border = border;
      if (cs.opacity !== '1') rec.opacity = +cs.opacity;
      recs.push(rec);
    }
    if (!isSvg) for (const c of el.children) walk(c, depth + 1, myId);
  };
  walk(root, 0, null);
  return recs;
}
"""

async def main():
    manifest = json.load(open(os.path.join(OUT, "manifest.json")))
    os.makedirs(os.path.join(OUT, "boxes"), exist_ok=True)
    async with async_playwright() as p:
        b = await p.chromium.launch()
        for m in manifest:
            pg = await b.new_page(viewport={"width": m["w"], "height": m["h"]})
            await pg.goto("file://" + os.path.abspath(os.path.join(OUT, m["file"])))
            await pg.evaluate("document.fonts.ready")
            recs = await pg.evaluate(JS)
            json.dump({"artboard": m["artboard"], "w": m["w"], "h": m["h"], "units": "logical px, origin top-left of the artboard",
                       "boxes": recs}, open(os.path.join(OUT, "boxes", m["artboard"] + ".json"), "w"), ensure_ascii=False, separators=(",", ":"))
            await pg.close()
        await b.close()
    print("boxes written for", len(manifest), "artboards")

asyncio.run(main())
