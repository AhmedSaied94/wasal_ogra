"""Generate vehicle and UI Lottie animations from the design art.

usage: python3 gen_ui.py <src dir (has icons/ and illustrations/)> <out lottie dir>
"""
import json, math, os, random, sys
import xml.etree.ElementTree as ET
from svg2lottie import walk, leaf_to_group, group, tr, st, fill, stroke, parse_path, NS, load_svg, parse_transform
from gen_people import anim, vis_keys, C, P, RC

FPS = 30

def comp(name, w, h, total, layers, markers):
    return {"v": "5.9.0", "fr": FPS, "ip": 0, "op": total, "w": w, "h": h, "nm": name, "ddd": 0, "assets": [],
            "layers": layers, "markers": [{"cm": n, "tm": a, "dr": b - a} for n, a, b in markers],
            "meta": {"g": "wassal design handoff (generated)"}}

def layer(name, groups, ind, total, ks=None, parent=None):
    k = {"o": st(100), "r": st(0), "p": st([0, 0, 0]), "a": st([0, 0, 0]), "s": st([100, 100, 100])}
    if ks:
        k.update(ks)
    lay = {"ddd": 0, "ind": ind, "ty": 4, "nm": name, "sr": 1, "ks": k, "ao": 0, "shapes": list(reversed(groups)),
           "ip": 0, "op": total, "st": 0, "bm": 0}
    if parent is not None:
        lay["parent"] = parent
    return lay

def null(name, ind, total, ks, parent=None):
    k = {"o": st(100), "r": st(0), "p": st([0, 0, 0]), "a": st([0, 0, 0]), "s": st([100, 100, 100])}
    k.update(ks)
    lay = {"ddd": 0, "ind": ind, "ty": 3, "nm": name, "sr": 1, "ks": k, "ao": 0, "ip": 0, "op": total, "st": 0, "bm": 0}
    if parent is not None:
        lay["parent"] = parent
    return lay

def svg_groups(path_or_root):
    root = load_svg(path_or_root)[0] if isinstance(path_or_root, str) else path_or_root
    return [g for g in (leaf_to_group(l, s, c) for l, s, c in walk(root)) if g]

def top(layers):
    """Layers are built bottom->top; Lottie wants top first."""
    return list(reversed(layers))

# ------------------------------------------------------------------ vehicles
def vehicle(svg_path, name):
    root, vb = load_svg(svg_path)
    g = [ch for ch in root if ch.tag == NS + "g"][0]
    gt = parse_transform(g.get("transform"))
    total = 84
    marks = [("idle", 0, 36), ("drive", 36, 48), ("brake", 48, 66), ("honk", 66, 84)]
    shadow, body, wheels = [], [], []
    hubs = []
    leaves = list(walk(g))
    for leaf, stl, chain in leaves:
        tag = leaf.tag.replace(NS, "")
        f = (stl.get("fill") or "").upper()
        if tag == "ellipse" and f in ("#C9BCA3",):
            shadow.append(leaf_to_group(leaf, stl, chain)); continue
        if tag == "circle" and f in ("#2A2633", "#D9D4E2") and float(leaf.get("r")) >= 7 and float(leaf.get("cy")) > 140:
            cx, cy, r = float(leaf.get("cx")), float(leaf.get("cy")), float(leaf.get("r"))
            key = (round(cx), round(cy))
            wheels.append((key, leaf_to_group(leaf, stl, chain), f, r))
            continue
        body.append(leaf_to_group(leaf, stl, chain))
    by = {}
    for key, gr, f, r in wheels:
        by.setdefault(key, []).append((gr, f, r))
    gp, gs = gt["p"]["k"], gt["s"]["k"]
    L = []
    ind = 1
    L.append(null("vehicle", 1, total, {"p": st([gp[0], gp[1], 0]), "s": st([gs[0], gs[1], 100])}))
    ind += 1
    L.append(layer("shadow", shadow, ind, total, parent=1)); ind += 1
    bob = [(0, [0, 0, 0], False), (18, [0, -3, 0], False), (35, [0, 0, 0], True)]
    for t in range(36, 48, 6):
        bob += [(t, [0, 0, 0], False), (t + 3, [0, -1.5, 0], False)]
    bob += [(47, [0, 0, 0], True), (48, [0, 0, 0], False), (65, [0, 0, 0], True),
            (66, [0, 0, 0], False), (69, [0, 2, 0], False), (74, [0, -2, 0], False), (80, [0, 0, 0], False), (83, [0, 0, 0], True)]
    # brake: tilt forward around the front wheel contact point
    wheel_keys = sorted(by.keys())
    front = wheel_keys[0]
    rot = [(0, 0, True), (48, 0, False), (52, -2.5, False), (60, 0.8, False), (65, 0, True), (66, 0, True)]
    L.append(layer("body", body, ind, total, {"p": anim(bob), "r": anim(rot), "a": st([front[0], front[1], 0]),
                                                "s": anim([(0, [100, 100, 100], True), (66, [100, 100, 100], False), (70, [103, 97, 100], False), (76, [100, 100, 100], False), (83, [100, 100, 100], True)])},
                   parent=1))
    # body anchor moved to the front wheel: compensate position
    L[-1]["ks"]["p"] = anim([(t, [v[0] + front[0], v[1] + front[1], 0], h) for t, v, h in bob])
    ind += 1
    for key in wheel_keys:
        parts = by[key]
        r_hub = min(r for _, f, r in parts if f == "#D9D4E2")
        spoke = group([{"ty": "rc", "nm": "Rect", "p": st([key[0], key[1]]), "s": st([r_hub * 1.7, r_hub * 0.45]), "r": st(2), "d": 1}, fill("#8A84A0")], "spoke")
        grs = [gr for gr, _, _ in parts] + [spoke]
        LIN = {"i": {"x": [1], "y": [1]}, "o": {"x": [0], "y": [0]}}
        EOUT = {"i": {"x": [0.2], "y": [1]}, "o": {"x": [0.4], "y": [0]}}
        rotk = [{"t": 0, "s": [0], "h": 1}, dict({"t": 36, "s": [0]}, **LIN), dict({"t": 48, "s": [360]}, **EOUT),
                {"t": 58, "s": [500], "h": 1}, {"t": 66, "s": [0]}]
        L.append(layer(f"wheel_{len(L)}", grs, ind, total, {"a": st([key[0], key[1], 0]), "p": st([key[0], key[1], 0]),
                                                            "r": {"a": 1, "k": rotk}}, parent=1))
        ind += 1
    beep = P("M14 70 l-16 -10 M10 96 h-20 M14 122 l-16 10", stroke("#1D1A2B", 6, "round", "round"), name="beep")
    L.append(layer("fx_honk", [beep], ind, total, {"o": anim([(0, 0, True), (66, 0, False), (69, 100, True), (72, 0, True), (74, 100, True), (80, 0, True)])}, parent=1))
    return comp(name, 236, 150, total, top(L), marks)

# ------------------------------------------------------------------ UI
def icon_groups(src, name):
    return svg_groups(os.path.join(src, "icons", name + ".svg"))

def stars(src):
    total = 30
    star_d = "M12 2.5l2.9 5.9 6.5.9-4.7 4.6 1.1 6.5L12 17.3l-5.8 3.1 1.1-6.5L2.6 9.3l6.5-.9z"
    def star(color, lip=None):
        items = [P(star_d, stroke(color, 1.5, "round", "round"), fill(color))]
        if lip:
            items.insert(0, group([{"ty": "sh", "ks": st(sp), "nm": "p"} for sp in parse_path(star_d)] + [stroke(lip, 1.5, "round", "round"), fill(lip)], "lip", tr((0, 1.2))))
        return items
    L = []
    pos = [(50, 58, 260), (120, 46, 330), (190, 58, 260)]
    ind = 0
    for i, (x, y, s) in enumerate(pos):
        ind += 1
        L.append(layer(f"slot_{i+1}", [P(star_d, stroke("#C7DDEA", 1.6, "round", "round"))], ind, total,
                       {"a": st([12, 12, 0]), "p": st([x, y, 0]), "s": st([s, s, 100])}))
    for i, (x, y, s) in enumerate(pos):
        ind += 1
        t0 = i * 8
        L.append(layer(f"star_{i+1}", star("#F5B301", "#D9A800"), ind, total, {
            "a": st([12, 12, 0]), "p": st([x, y, 0]),
            "s": anim([(0, [0, 0, 100], True), (t0, [0, 0, 100], False), (t0 + 7, [s * 1.25, s * 1.25, 100], False), (t0 + 11, [s, s, 100], False), (total - 1, [s, s, 100], True)]),
            "r": anim([(0, -30, True), (t0, -30, False), (t0 + 11, 0, False), (total - 1, 0, True)])}))
    return comp("stars", 240, 100, total, top(L), [("one", 0, 12), ("two", 0, 20), ("three", 0, 30)])

def coach_hand():
    total = 30
    hand = P("M22 4 a5 5 0 0 1 10 0 V26 l12 2 a7 7 0 0 1 6 8 l-3 16 a9 9 0 0 1 -9 8 H24 a9 9 0 0 1 -7 -4 L5 38 a5 5 0 0 1 8 -6 l9 8 Z",
             stroke("#1D1A2B", 3, "round", "round"), fill("#FFFFFF"))
    ring = group([{"ty": "el", "nm": "e", "p": st([0, 0]), "s": st([30, 30]), "d": 1}, stroke("#FFD23F", 4)], "ring")
    L = [layer("ripple", [ring], 1, total, {"p": st([47, 26, 0]),
                                            "s": anim([(0, [40, 40, 100], True), (10, [40, 40, 100], False), (24, [160, 160, 100], True), (29, [40, 40, 100], True)]),
                                            "o": anim([(0, 0, True), (10, 100, False), (24, 0, True)])}),
         layer("hand", [hand], 2, total, {"a": st([27, 4, 0]),
                                          "p": anim([(0, [52, 34, 0], False), (10, [47, 28, 0], False), (16, [47, 28, 0], False), (29, [52, 34, 0], True)]),
                                          "s": anim([(0, [100, 100, 100], False), (10, [90, 90, 100], False), (16, [90, 90, 100], False), (29, [100, 100, 100], True)])})]
    return comp("coach_hand", 100, 100, total, top(L), [("tap", 0, 30)])

def loading_wheel():
    total = 30
    grs = [C(0, 0, 30, "#2A2633"), C(0, 0, 13, "#D9D4E2")]
    spokes = [group([{"ty": "rc", "nm": "r", "p": st([0, 0]), "s": st([24, 5]), "r": st(2.5), "d": 1}, fill("#8A84A0")], "spoke", tr((0, 0), (0, 0), (100, 100), a)) for a in (0, 60, 120)]
    L = [layer("wheel", grs + spokes, 1, total, {"p": st([40, 40, 0]), "r": {"a": 1, "k": [{"t": 0, "s": [0], "i": {"x": [1], "y": [1]}, "o": {"x": [0], "y": [0]}}, {"t": 30, "s": [360]}]}})]
    return comp("loading_wheel", 80, 80, total, L, [("loop", 0, 30)])

def burst(src, icon, name, n=10):
    total = 26
    rnd = random.Random(7)
    L = []
    for i in range(n):
        ang = 2 * math.pi * i / n + rnd.uniform(-0.2, 0.2)
        dist = rnd.uniform(60, 85)
        x1, y1 = 100 + math.cos(ang) * dist, 100 + math.sin(ang) * dist
        s = rnd.uniform(110, 160)
        d0 = rnd.randint(0, 3)
        L.append(layer(f"{icon}_{i}", icon_groups(src, icon), i + 1, total, {
            "a": st([12, 12, 0]),
            "p": anim([(0, [100, 100, 0], True), (d0, [100, 100, 0], False), (d0 + 16, [x1, y1, 0], False), (total - 1, [x1, y1 + 6, 0], True)]),
            "s": anim([(0, [0, 0, 100], True), (d0, [40, 40, 100], False), (d0 + 6, [s, s, 100], False), (total - 1, [s * 0.8, s * 0.8, 100], True)]),
            "o": anim([(0, 0, True), (d0, 100, False), (total - 6, 100, False), (total - 1, 0, True)]),
            "r": anim([(0, 0, True), (d0, 0, False), (total - 1, rnd.uniform(-40, 40), True)])}))
    return comp(name, 200, 200, total, top(L), [("burst", 0, total)])

def confetti():
    total = 48
    rnd = random.Random(3)
    cols = ["#FFD23F", "#F2542D", "#1A4B8C", "#5FAE4E", "#A9DDF3", "#F5B301", "#E8846B", "#7C6FB0"]
    L = []
    for i in range(28):
        x = rnd.uniform(10, 380); y0 = rnd.uniform(-60, -10); y1 = rnd.uniform(220, 320)
        d0 = rnd.randint(0, 10)
        piece = RC(-4, -7, 8, 14, 2, cols[i % len(cols)])
        L.append(layer(f"piece_{i}", [piece], i + 1, total, {
            "p": anim([(0, [x, y0, 0], True), (d0, [x, y0, 0], False), (total - 1, [x + rnd.uniform(-30, 30), y1, 0], True)]),
            "r": anim([(0, 0, True), (d0, 0, False), (total - 1, rnd.uniform(-540, 540), True)]),
            "o": anim([(0, 100, True), (total - 8, 100, False), (total - 1, 0, True)])}))
    return comp("confetti", 390, 300, total, top(L), [("burst", 0, total)])

def fuel_fill():
    total = 36
    track = group([{"ty": "sh", "nm": "p", "ks": st(parse_path("M30 92 A48 48 0 0 1 126 92")[0])}, stroke("#E3EEF5", 14, "round", "round")], "track")
    fill_arc = group([{"ty": "sh", "nm": "p", "ks": st(parse_path("M30 92 A48 48 0 0 1 126 92")[0])},
                      {"ty": "tm", "nm": "trim", "s": st(0), "e": anim([(0, 2, True), (2, 2, False), (30, 100, False), (35, 100, True)]), "o": st(0), "m": 1},
                      stroke("#5FAE4E", 14, "round", "round")], "fill")
    needle = group([{"ty": "sh", "nm": "p", "ks": st(parse_path("M78 92 L78 52")[0])}, stroke("#1D1A2B", 5, "round", "round")], "needle")
    L = [layer("track", [track], 1, total),
         layer("fill", [fill_arc], 2, total),
         layer("needle", [needle], 3, total, {"a": st([78, 92, 0]), "p": st([78, 92, 0]),
                                              "r": anim([(0, -84, True), (2, -84, False), (30, 84, False), (32, 78, False), (35, 80, True)])}),
         layer("hub", [C(78, 92, 8, "#1D1A2B")], 4, total)]
    return comp("fuel_fill", 156, 110, total, top(L), [("empty", 0, 1), ("fill", 0, total)])

def gift_open(src):
    total = 30
    base = [RC(4.5, 12, 15, 9, 1.5, "#FFD23F"), P("M12 12v9", stroke("#F2542D", 2.4))]
    lid = [RC(3, 8, 18, 5, 1.5, "#F2542D"),
           P("M12 8C10.5 4.5 7 4 7 6.2S10 8 12 8c2 0 5-.2 5-1.8S13.5 4.5 12 8", stroke("#F2542D", 2, "butt", "round"))]
    L = [null("gift", 1, total, {"p": st([80, 140, 0]), "a": st([12, 21, 0]),
                                  "s": anim([(0, [500, 500, 100], False), (6, [540, 470, 100], False), (10, [500, 500, 100], False), (29, [500, 500, 100], True)])}),
         layer("box", base, 2, total, parent=1),
         layer("lid", lid, 3, total, {"a": st([12, 10, 0]), "p": anim([(0, [12, 10, 0], True), (8, [12, 10, 0], False), (16, [10, 3, 0], False), (29, [10, 4, 0], True)]),
                                      "r": anim([(0, 0, True), (8, 0, False), (16, -16, False), (29, -12, True)])}, parent=1)]
    for i, (dx, dy) in enumerate([(-34, -50), (0, -64), (34, -50)]):
        L.append(layer(f"spark_{i}", [P("M0 -8 L2 -2 L8 0 L2 2 L0 8 L-2 2 L-8 0 L-2 -2 Z", fill("#FFD23F"))], 4 + i, total, {
            "p": anim([(0, [80, 100, 0], True), (12, [80, 100, 0], False), (22, [80 + dx, 100 + dy * 0.8, 0], True)]),
            "s": anim([(0, [0, 0, 100], True), (12, [0, 0, 100], False), (20, [160, 160, 100], False), (29, [0, 0, 100], True)])}))
    return comp("gift_open", 160, 160, total, top(L), [("open", 0, total)])

def sparkle_place():
    total = 24
    spk = lambda: [P("M0 -10 L2.5 -2.5 L10 0 L2.5 2.5 L0 10 L-2.5 2.5 L-10 0 L-2.5 -2.5 Z", fill("#FFD23F"))]
    pts = [(30, 30, 0), (90, 26, 4), (96, 86, 8), (26, 90, 12), (60, 58, 2)]
    L = []
    for i, (x, y, d0) in enumerate(pts):
        L.append(layer(f"spark_{i}", spk(), i + 1, total, {"p": st([x, y, 0]),
                                                       "s": anim([(0, [0, 0, 100], True), (d0, [0, 0, 100], False), (d0 + 6, [140, 140, 100], False), (d0 + 12, [0, 0, 100], True)]),
                                                       "r": anim([(0, 0, True), (d0, 0, False), (d0 + 12, 90, True)])}))
    return comp("sparkle_place", 120, 120, total, top(L), [("place", 0, total)])

def ring_shine(src):
    total = 45
    ring = icon_groups(src, "ring_gem")
    L = [layer("ring", ring, 1, total, {"a": st([12, 12, 0]), "p": st([60, 62, 0]), "s": st([420, 420, 100]),
                                        "r": anim([(0, -4, False), (22, 4, False), (44, -4, True)])}),
         layer("glint", [P("M0 -9 L2 -2 L9 0 L2 2 L0 9 L-2 2 L-9 0 L-2 -2 Z", fill("#FFFFFF"))], 2, total, {
             "p": st([70, 26, 0]),
             "s": anim([(0, [0, 0, 100], True), (8, [0, 0, 100], False), (16, [130, 130, 100], False), (24, [0, 0, 100], True)]),
             "r": anim([(0, 0, True), (8, 0, False), (24, 90, True)])})]
    return comp("ring_shine", 120, 120, total, top(L), [("loop", 0, total)])

def notif_bell():
    total = 30
    bell = [P("M18 4 a12 12 0 0 1 12 12 v8 l5 7 H1 l5 -7 v-8 a12 12 0 0 1 12 -12 z", fill("#FFD23F")), C(18, 35, 4, "#F5B301")]
    waves = [P("M36 6 q6 6 4 14 M0 6 q-6 6 -4 14", stroke("#F2542D", 2.6, "round", "round"))]
    L = [layer("bell", bell, 1, total, {"a": st([18, 2, 0]), "p": st([30, 14, 0]),
                                        "r": anim([(0, 0, False), (4, 16, False), (9, -14, False), (14, 10, False), (19, -6, False), (24, 0, False), (29, 0, True)])}),
         layer("waves", waves, 2, total, {"p": st([12, 12, 0]), "o": anim([(0, 0, True), (3, 100, False), (20, 100, False), (26, 0, True)])})]
    return comp("notif_bell", 60, 60, total, top(L), [("ring", 0, total)])

def splash_drive(src):
    total = 12
    v = vehicle(os.path.join(src, "illustrations", "vehicles", "microbus_old.svg"), "x")
    # reuse the vehicle's layers, looping the 'drive' segment, plus road lines
    lay = []
    for l in v["layers"]:
        l = json.loads(json.dumps(l))
        l["st"] = -36            # play the drive segment from frame 0
        l["op"] = total; l["ip"] = 0
        lay.append(l)
    road = [P("M0 0 H34", stroke("#FFFFFF", 6, "round"))]
    roads = []
    for i, x in enumerate((20, 100, 180, 260)):
        roads.append(layer(f"road_{i}", road, 50 + i, total, {"p": anim([(0, [x, 144, 0], False), (total, [x - 80, 144, 0], True)])}))
    return comp("splash_drive", 236, 150, total, lay + roads, [("loop", 0, total)])


if __name__ == "__main__":
    src, out = sys.argv[1], sys.argv[2]
    for d in ("vehicles", "ui"):
        os.makedirs(os.path.join(out, d), exist_ok=True)
    for vid in ("tuktuk", "microbus_old", "microbus_new", "microbus_travel"):
        json.dump(vehicle(os.path.join(src, "illustrations", "vehicles", vid + ".svg"), vid),
                  open(os.path.join(out, "vehicles", vid + ".json"), "w"), separators=(",", ":"))
    ui = {"stars": stars(src), "coach_hand": coach_hand(), "loading_wheel": loading_wheel(),
          "coins_burst": burst(src, "coin", "coins_burst"), "bonat_burst": burst(src, "bonat", "bonat_burst"),
          "confetti": confetti(), "fuel_fill": fuel_fill(), "gift_open": gift_open(src), "sparkle_place": sparkle_place(),
          "ring_shine": ring_shine(src), "notif_bell": notif_bell(), "splash_drive": splash_drive(src)}
    for k, v in ui.items():
        json.dump(v, open(os.path.join(out, "ui", k + ".json"), "w"), separators=(",", ":"))
    print("vehicles 4, ui", len(ui))
