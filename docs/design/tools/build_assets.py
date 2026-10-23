"""Extract icons (24/20/16 viewBox inline SVGs, deduped by shape) and illustrations
(larger inline SVGs) from the canvas artboards.

usage: python3 build_assets.py <design/project dir> <out dir> <icon_names.json>
writes <out>/icons/*.svg + manifest.json + index.html and <out>/illustrations/**.svg + manifest.json
"""
import hashlib, html, json, os, pathlib, re, shutil, sys

SRC, OUT, NAMES = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), json.load(open(sys.argv[3]))
SKIP = {"Main.dc.html", "A-Trip.dc.html", "B-Home.dc.html", "B-Trip.dc.html"}
files = sorted(f for f in os.listdir(SRC) if f.endswith(".dc.html") and f not in SKIP)
ICON_VB = ("0 0 24 24", "0 0 16 16", "0 0 20 20")

PASS = {"العادي": "regular", "الحاجة": "hagga", "النايم": "sleeper", "المستعجل": "hurried", "الأفندي أبو ٢٠٠": "effendi_200",
        "الطالب": "student", "أبو سمّاعة": "headphones", "أنا دافع": "claimer", "خليها عليا": "group_payer", "الرغاي": "chatterbox",
        "اللي بيفك": "changer", "الست بالشنط": "bags_lady", "المتهرب": "dodger", "الأم والعيال": "mother_kids",
        "العيلة الكبيرة": "big_family", "المسافر": "traveler", "الزبون الدايم": "regular_customer", "الأمين": "honest"}
CHAR = {"الأسطى": "usta", "سلمى": "salma", "أبو العروسة": "bride_father", "أم العروسة": "bride_mother", "المعلم": "moallem", "بلية": "belya"}
STATE = {"عادي": "idle", "بيتكلم": "talk", "صبره بيخلص": "impatient", "نايم": "sleep", "لابس سماعات": "headphones",
         "ليه باقي ومحطته قربت": "change_due", "خناقة": "fight", "نازل": "alight", "راكب جديد": "board",
         "متنوّر قبل الرمي": "targeted", "شاكر": "happy", "أنا دافع": "claim"}
VEH = {"توكتوك المعلم": "tuktuk", "ميكروباص قديم": "microbus_old", "ميكروباص جديد": "microbus_new", "ميكروباص سفر وفوقه شنط": "microbus_travel"}

for d in ("icons", "illustrations"):
    shutil.rmtree(OUT / d, ignore_errors=True)
(OUT / "icons").mkdir(parents=True)
icons, illus, unnamed = {}, [], []
for f in files:
    stem = f.replace(".dc.html", "")
    body = re.search(r"<x-dc>(.*)</x-dc>", (SRC / f).read_text(), re.S).group(1)
    n = 0
    for m in re.finditer(r"<svg\b[^>]*>.*?</svg>", body, re.S):
        svg = m.group(0)
        tag = re.search(r"<svg\b[^>]*>", svg).group(0)
        vb = re.search(r'viewBox="([^"]+)"', tag)
        vb = vb.group(1) if vb else ""
        inner = re.sub(r"<svg\b[^>]*>", "", svg, count=1)[:-len("</svg>")]
        if vb in ICON_VB:
            canon = re.sub(r"\s+", " ", re.sub(r"#[0-9A-Fa-f]{6}|#[0-9A-Fa-f]{3}\b", "C", vb + inner))
            key = hashlib.md5(canon.encode()).hexdigest()[:8]
            if key in icons:
                icons[key]["uses"].add(stem); continue
            colors = {c.upper() for c in re.findall(r"#[0-9A-Fa-f]{6}", svg)}
            attrs = " ".join(re.findall(r'\b(?:viewBox|fill|stroke|stroke-width|stroke-linecap|stroke-linejoin)="[^"]*"', tag))
            clean = f'<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" {attrs}>{inner}</svg>'
            mono = len(colors) <= 1
            if mono and colors:
                clean = re.sub(r"#[0-9A-Fa-f]{6}", "currentColor", clean)
            name = NAMES.get(key)
            if not name:
                name = "unnamed_" + key; unnamed.append((key, stem))
            (OUT / "icons" / f"{name}.svg").write_text(clean)
            icons[key] = {"name": name, "mono": mono, "colors": sorted(colors), "uses": {stem}}
            continue
        if not vb or len(svg) < 600 or stem in ("Tokens", "Components"):
            continue
        n += 1
        w = re.search(r'\swidth="([\d.]+)"', tag); h = re.search(r'\sheight="([\d.]+)"', tag)
        W = w.group(1) if w else vb.split()[2]; H = h.group(1) if h else vb.split()[3]
        label = re.search(r'aria-label="([^"]*)"', tag)
        label = label.group(1) if label else ""
        if stem == "Passengers" and label in PASS: sub, name = "passengers", PASS[label]
        elif stem == "Characters" and label in CHAR: sub, name = "characters", CHAR[label]
        elif stem == "Characters" and label in STATE: sub, name = "passenger_states", STATE[label]
        elif stem == "Vehicles" and label in VEH: sub, name = "vehicles", VEH[label]
        elif stem == "Vehicles": sub, name = "vehicles", f"seatmap_{n:02d}"
        else: sub, name = "screens", f"{stem}_{n:02d}"
        p = OUT / "illustrations" / sub
        p.mkdir(parents=True, exist_ok=True)
        (p / f"{name}.svg").write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="{vb}">{inner}</svg>')
        illus.append({"file": f"illustrations/{sub}/{name}.svg", "screen": stem, "size": f"{W}x{H}", "label": label})

man = sorted(({"name": v["name"], "file": f"icons/{v['name']}.svg",
               "tint": "currentColor (tint with the text colour of the context)" if v["mono"] else "multicolour, render as-is",
               "designColors": v["colors"], "usedOn": sorted(v["uses"])} for v in icons.values()), key=lambda x: x["name"])
json.dump(man, open(OUT / "icons" / "manifest.json", "w"), ensure_ascii=False, indent=1)
cells = "".join(
    f'<figure><div style="color:#1A4B8C">{(OUT / "icons" / (m["name"] + ".svg")).read_text().replace(chr(34)+"24"+chr(34), chr(34)+"32"+chr(34))}</div><figcaption>{m["name"]}</figcaption></figure>'
    for m in man)
(OUT / "icons" / "index.html").write_text('<!doctype html><meta charset="utf-8"><title>Icons</title><style>body{margin:0;font:12px/1.3 system-ui,sans-serif;background:#fff;color:#1D1A2B}main{display:grid;grid-template-columns:repeat(auto-fill,minmax(120px,1fr));gap:8px;padding:16px}figure{margin:0;display:flex;flex-direction:column;align-items:center;gap:6px;padding:10px;border-radius:14px;background:#E8F4FB}</style><main>' + cells + "</main>")
json.dump(illus, open(OUT / "illustrations" / "manifest.json", "w"), ensure_ascii=False, indent=1)
print(len(man), "icons,", len(illus), "illustrations; unnamed icons:", unnamed)
