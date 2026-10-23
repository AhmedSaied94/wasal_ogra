"""Generate animated Lottie files for passengers and story characters from the design SVGs.

Each output = one Lottie JSON (30 fps, 200x240) with named markers (segments) and the
layer-name contract from HANDOFF §6.2. The type's own art (shirt, hair, hijab, props,
glasses, moustache...) comes from its SVG; the face features are replaced by the shared
animated set so every type supports every segment.

usage: python3 gen_people.py <illustrations dir> <out dir>
"""
import json, math, os, re, sys
from svg2lottie import (load_svg, walk, leaf_to_group, group, tr, st, fill, stroke, parse_path, NS)

FPS = 30
W, H = 200, 240
CX, CY = 100, 100           # head centre inside the artboard
INK, HAIR = "#1D1A2B", "#2B2238"

SEGMENTS = [("idle", 0, 60), ("talk", 60, 75), ("impatient_1", 75, 105), ("impatient_2", 105, 135),
            ("sleep", 135, 195), ("wake", 195, 215), ("headphones", 215, 275), ("call_1", 275, 290),
            ("call_2", 290, 305), ("change_due", 305, 335), ("fight", 335, 365), ("happy", 365, 395),
            ("claim", 395, 425), ("targeted", 425, 440), ("board", 440, 458), ("alight", 458, 476)]
CHAR_EXTRA = [("surprised", 476, 506), ("angry", 506, 536)]
LOOPS = {"idle", "talk", "impatient_1", "impatient_2", "sleep", "headphones", "change_due", "fight", "claim", "surprised", "angry"}

# ------------------------------------------------------------------ keyframes
EASE_I = {"x": [0.4], "y": [1]}
EASE_O = {"x": [0.6], "y": [0]}

def anim(keys, dims=1):
    """keys: list of (t, value, hold). value scalar or list."""
    keys = sorted(keys, key=lambda k: k[0])
    out = []
    for n, (t, v, hold) in enumerate(keys):
        s = v if isinstance(v, list) else [v]
        k = {"t": t, "s": s}
        if n < len(keys) - 1:
            if hold:
                k["h"] = 1
            else:
                k["i"] = {"x": [0.4] * len(s), "y": [1] * len(s)}
                k["o"] = {"x": [0.6] * len(s), "y": [0] * len(s)}
                if len(s) >= 2:
                    k["to"] = [0] * len(s); k["ti"] = [0] * len(s)
        out.append(k)
    return {"a": 1, "k": out}

def vis_keys(ranges, total):
    """Opacity hold keyframes: 100 inside ranges [(a,b)), 0 elsewhere."""
    pts = {0: 0}
    for a, b in sorted(ranges):
        pts[a] = 100
        pts[b] = 0
    keys = sorted(pts.items())
    clean = []
    for t, v in keys:
        if t > total:
            continue
        if clean and clean[-1][1] == v:
            continue
        clean.append((t, v))
    if len(clean) == 1:
        return st(clean[0][1])
    return anim([(t, v, True) for t, v in clean])

def seg(name, segs):
    for n, a, b in segs:
        if n == name:
            return a, b
    raise KeyError(name)

# ------------------------------------------------------------------ shared face features (base coords, head r 42)
def P(d, *paint, name="path"):
    return group([{"ty": "sh", "nm": "Path", "ks": st(sp)} for sp in parse_path(d)] + list(paint), name)

def C(cx, cy, r, color, op=100):
    return group([{"ty": "el", "nm": "Ellipse", "p": st([cx, cy]), "s": st([2 * r, 2 * r]), "d": 1}, fill(color, op)], "circle")

def E(cx, cy, rx, ry, color):
    return group([{"ty": "el", "nm": "Ellipse", "p": st([cx, cy]), "s": st([2 * rx, 2 * ry]), "d": 1}, fill(color)], "ellipse")

def RC(x, y, w, h, r, color):
    return group([{"ty": "rc", "nm": "Rect", "p": st([x + w / 2, y + h / 2]), "s": st([w, h]), "r": st(r), "d": 1}, fill(color)], "rect")

FEATURES = {
    "blush": [C(-26, 18, 7, "#E9967A", 60), C(26, 18, 7, "#E9967A", 60)],
    "eyes": [C(-15, 6, 5.5, INK), C(15, 6, 5.5, INK), C(-13, 4, 1.8, "#FFFFFF"), C(17, 4, 1.8, "#FFFFFF")],
    "eyes_wide": [C(-15, 6, 7, INK), C(15, 6, 7, INK), C(-12.5, 3.5, 2.2, "#FFFFFF"), C(17.5, 3.5, 2.2, "#FFFFFF")],
    "eyes_closed": [P("M-21 6 H-9 M9 6 H21", stroke(INK, 5, "round", "round"))],
    "eyes_sleep": [P("M-23 6 Q-15 14 -7 6 M7 6 Q15 14 23 6", stroke(INK, 4.6, "round", "round"))],
    "eyes_happy": [P("M-22 6 Q-15 0 -8 6 M8 6 Q15 0 22 6", stroke(INK, 4.6, "round", "round"))],
    "eyes_shifty": [C(-8, 6, 5.5, INK), C(22, 6, 5.5, INK)],
    "brows_angry": [P("M-26 -12 L-8 -5 M8 -5 L26 -12", stroke(HAIR, 5.5, "round", "round"))],
    "brow_raised": [P("M-26 -10 L-8 -10 M8 -16 L26 -10", stroke(HAIR, 5, "round", "round"))],
    "mouth_smile": [P("M-12 22 Q0 32 12 22", stroke(INK, 4.4, "round", "round"))],
    "mouth_talk": [P("M-6 28 Q0 31 6 28", stroke("#F2542D", 3, "round", "round")), P("M-13 18 Q0 36 13 18 Z", fill(INK))],
    "mouth_frown": [P("M-12 30 Q0 20 12 30", stroke(INK, 4.4, "round", "round"))],
    "mouth_teeth": [P("M-10 22 V32 M0 22 V32 M10 22 V32", stroke("#FFFFFF", 2)), RC(-16, 22, 32, 10, 3, INK)],
    "mouth_sleep": [E(0, 25, 6, 7, INK)],
    "mouth_big": [P("M-14 18 Q0 38 14 18 Z", fill(INK))],
    "mouth_smirk": [P("M-10 26 Q4 30 14 20", stroke(INK, 4.4, "round", "round"))],
    "mouth_o": [E(0, 26, 7, 8, INK)],
}

def z_shape(x, y, s):
    return P(f"M{x} {y} h{10*s} l{-10*s} {12*s} h{10*s}", stroke("#7C6FB0", 3.2 * s, "round", "round"), name="z")

FX = {
    "fx_sweat": [P("M38 -26 Q47 -11 38 -4 Q29 -11 38 -26 Z", fill("#7CC5E8"))],
    "fx_z": [z_shape(46, -70, 1.3), z_shape(32, -48, 1.0)],
    "fx_sparks": [P("M44 -40 l6 -10 M52 -30 l10 -4 M40 -54 l2 -10", stroke("#F2542D", 4, "round", "round"))],
    "fx_heart": [P("M50 -30 q6 -10 12 0 q6 10 -6 16 q-12 -6 -6 -16 Z", fill("#F2542D"))],
}

# ------------------------------------------------------------------ classify the type's own art
def center(leaf):
    tag = leaf.tag.replace(NS, "")
    g = lambda k: float(leaf.get(k, 0))
    if tag == "circle":
        return g("cx"), g("cy")
    if tag == "ellipse":
        return g("cx"), g("cy")
    if tag == "rect":
        return g("x") + g("width") / 2, g("y") + g("height") / 2
    if tag == "path":
        xs, ys = [], []
        for sp in parse_path(leaf.get("d")):
            for x, y in sp["v"]:
                xs.append(x); ys.append(y)
        return (sum(xs) / len(xs), sum(ys) / len(ys)) if xs else (0, 0)
    return 0, 0

def chain_offset(chain):
    dx = dy = 0
    for t, _ in chain:
        if t:
            p = t["p"]["k"]; dx += p[0]; dy += p[1]
    return dx, dy

def norm(c):
    return (c or "").upper()

def classify(leaf, stl, chain, state, kind):
    tag = leaf.tag.replace(NS, "")
    d = leaf.get("d", "")
    fillc, strokec = norm(stl.get("fill")), norm(stl.get("stroke"))
    sw = float(stl.get("stroke-width", 0) or 0)
    cx, cy = center(leaf)
    ox, oy = chain_offset(chain)
    gx, gy = cx + ox, cy + oy
    r = float(leaf.get("r", 0) or 0)
    top = not chain
    # torso
    if tag == "path" and re.match(r"M-(46|50|40) 1(08|10)", d):
        return "shirt"
    # head / face circle
    if top and tag == "circle" and r in (32, 34, 36, 42) and abs(float(leaf.get("cx", 0))) < 0.1 and not state.get("skin"):
        state["skin"] = {"r": r, "cy": float(leaf.get("cy", 0)), "color": stl.get("fill")}
        return "skin"
    if tag == "path" and (d.startswith("M-52 12 Q-52 -56") or d.startswith("M-54 20 Q-56 -60")):
        return "acc_hijab"
    if top and state.get("skin"):
        # standard features -> dropped (replaced by animated ones)
        if tag in ("circle",) and fillc == INK and 3.5 <= r <= 6.5 and -12 <= cy <= 12 and abs(cx) <= 26:
            return None
        if tag == "circle" and fillc == "#FFFFFF" and r <= 2.3 and abs(cy) <= 10:
            return None
        if tag == "circle" and fillc == "#E9967A":
            return None
        if tag == "path" and strokec == INK and fillc in ("NONE", "") and -2 <= cy <= 36 and abs(cx) <= 25:
            return None
        if tag in ("path", "ellipse") and fillc == INK and 14 <= cy <= 34 and abs(cx) <= 16:
            return None
        if tag in ("path", "rect") and fillc == "#FFFFFF" and 10 <= cy <= 30 and abs(cx) <= 12 and tag != "circle":
            return None
        if tag == "path" and strokec in ("#2B2238", "#5A3A28") and sw >= 5 and -20 <= cy <= -2:
            return None
        if tag == "path" and fillc == "#7CC5E8" and cx > 30 and cy < 0:
            return None   # sweat drop -> fx_sweat
    if not state.get("skin"):
        return "body_back" if state.get("shirt") is None else "shirt"
    # after the face: head or body attached
    if kind == "headphones" and ((tag == "path" and strokec == "#2A2633" and sw >= 8) or
                                 (tag == "rect" and fillc == "#F5B301" and abs(gx) >= 40 and gy < 30) or
                                 (fillc == "#7C6FB0" and gy < -20)):
        return "acc_headphones"
    return "acc_head" if gy < 44 else "acc_front"

# ------------------------------------------------------------------ build
def shape_layer(name, groups, ind, parent, ks_extra=None, op_total=0):
    ks = {"o": st(100), "r": st(0), "p": st([0, 0, 0]), "a": st([0, 0, 0]), "s": st([100, 100, 100])}
    if ks_extra:
        ks.update(ks_extra)
    lay = {"ddd": 0, "ind": ind, "ty": 4, "nm": name, "sr": 1, "ks": ks, "ao": 0,
           "shapes": list(reversed(groups)), "ip": 0, "op": op_total, "st": 0, "bm": 0}
    if parent is not None:
        lay["parent"] = parent
    return lay

def null_layer(name, ind, parent, ks, op_total):
    lay = {"ddd": 0, "ind": ind, "ty": 3, "nm": name, "sr": 1, "ks": ks, "ao": 0, "ip": 0, "op": op_total, "st": 0, "bm": 0}
    if parent is not None:
        lay["parent"] = parent
    return lay

def wiggle(a, b, step, amp, start_sign=1):
    keys = []
    sign = start_sign
    for t in range(a, b, step):
        keys.append((t, amp * sign, False)); sign = -sign
    keys[0] = (a, 0, False)
    keys.append((b - 1, 0, True))
    return keys

def build(svg_path, kind, character=False):
    segs = SEGMENTS + (CHAR_EXTRA if character else [])
    total = segs[-1][2]
    root, vb = load_svg(svg_path)
    state = {}
    buckets = {k: [] for k in ("body_back", "shirt", "acc_hijab", "skin", "hair", "acc_head", "acc_headphones", "acc_front")}
    order = []
    hair_done = False
    for leaf, stl, chain in walk(root):
        cls = classify(leaf, stl, chain, state, kind)
        if cls == "shirt":
            state["shirt"] = True
        if cls is None:
            continue
        # first big dark/grey path right after skin = hair
        if cls == "acc_head" and not hair_done and leaf.tag.endswith("path"):
            d = leaf.get("d", "")
            if re.match(r"M-(42|36|34|44|30) -?\d", d) and center(leaf)[1] < 0:
                cls = "hair"; hair_done = True
        gr = leaf_to_group(leaf, stl, chain)
        if gr is None:
            continue
        buckets[cls].append(gr)
        if cls not in order:
            order.append(cls)

    skin = state.get("skin") or {"r": 42, "cy": 0, "color": "#C68B5E"}
    s = skin["r"] / 42
    face_dy = skin["cy"] - 3 * (1 if skin["r"] == 32 else 0) if skin["r"] != 42 else 0
    if skin["r"] == 32:
        face_dy = skin["cy"] - 3
    elif skin["r"] == 34:
        face_dy = skin["cy"] - 3
    elif skin["r"] == 36:
        face_dy = 0

    A = lambda name: seg(name, segs)
    vis = {
        "eyes": [(0, 40), (46, 60), A("talk"), A("impatient_1"), A("impatient_2"), (203, 215), (280, 290), A("call_2"),
                 A("change_due"), A("fight"), A("targeted"), A("board"), A("alight")] + ([A("angry")] if character else []),
        "eyes_closed": [(40, 46), A("headphones"), (275, 280)],
        "eyes_sleep": [A("sleep"), (195, 203)],
        "eyes_happy": [A("happy")],
        "eyes_shifty": [A("claim")],
        "eyes_wide": [A("surprised")] if character else [],
        "brows_angry": [A("impatient_1"), A("impatient_2"), A("change_due"), A("fight")] + ([A("angry")] if character else []),
        "brow_raised": [A("claim")] + ([A("surprised")] if character else []),
        "mouth_smile": [A("idle"), (64, 67), (71, 75), (203, 215), A("headphones"), A("call_1"), A("call_2"), A("targeted"), A("board"), A("alight")],
        "mouth_talk": [(60, 64), (67, 71), A("change_due")],
        "mouth_frown": [A("impatient_1"), A("impatient_2")] + ([A("angry")] if character else []),
        "mouth_teeth": [A("fight")],
        "mouth_sleep": [A("sleep"), (195, 203)],
        "mouth_big": [A("happy")],
        "mouth_smirk": [A("claim")],
        "mouth_o": [A("surprised")] if character else [],
        "blush": [(0, A("fight")[0]), (A("fight")[1], total)],
    }

    layers = []
    ind = 10
    BODY, HEAD, FACE = 1, 2, 3
    layers.append(null_layer("body", BODY, None, {"o": st(100), "r": st(0), "p": st([CX, CY, 0]), "a": st([0, 0, 0]), "s": st([100, 100, 100])}, total))
    # head rotation
    hk = [(0, 0, True)]
    a, b = A("impatient_1"); hk += wiggle(a, b, 5, 2)
    a, b = A("impatient_2"); hk += wiggle(a, b, 3, 4)
    a, b = A("sleep"); hk += [(a, 18, True)]
    a, b = A("wake"); hk += [(a, 18, False), (a + 8, -4, False), (a + 14, 0, False), (b - 1, 0, True)]
    a, b = A("headphones"); hk += [(a, 0, False), (a + 15, 3, False), (a + 30, 0, False), (a + 45, -3, False), (b - 1, 0, True)]
    a, b = A("fight"); hk += wiggle(a, b, 3, 5)
    if character:
        a, b = A("surprised"); hk += [(a, 0, False), (a + 4, -3, False), (a + 10, 0, False), (b - 1, 0, True)]
        a, b = A("angry"); hk += wiggle(a, b, 4, 3)
    # make sure value returns to 0 at segment starts that don't animate
    for n, a, b in segs:
        if not any(k[0] == a for k in hk):
            hk.append((a, 0, True))
    layers.append(null_layer("head", HEAD, BODY, {"o": st(100), "r": anim(hk), "p": st([0, 0, 0]), "a": st([0, 0, 0]), "s": st([100, 100, 100])}, total))
    layers.append(null_layer("face", FACE, HEAD, {"o": st(100), "r": st(0), "p": st([0, face_dy, 0]), "a": st([0, 0, 0]), "s": st([s * 100, s * 100, 100])}, total))

    def add(name, groups, parent, ks_extra=None):
        nonlocal ind
        ind += 1
        layers.append(shape_layer(name, groups, ind, parent, ks_extra, total))

    # paint order bottom -> top
    if buckets["body_back"]:
        add("acc_back", buckets["body_back"], BODY)
    add("shirt", buckets["shirt"], BODY)
    if buckets["acc_hijab"]:
        add("acc_hijab", buckets["acc_hijab"], HEAD)
    add("skin", buckets["skin"], HEAD)
    flush = [group([{"ty": "el", "nm": "Ellipse", "p": st([0, skin["cy"]]), "s": st([2 * skin["r"], 2 * skin["r"]]), "d": 1}, fill("#E0543A")], "flush")]
    fa, fb = A("fight")
    fl_keys = [(0, 0, True), (fa, 0, False), (fa + 4, 45, False), (fb - 1, 45, True), (fb, 0, True)]
    if character:
        ga, gb = A("angry"); fl_keys += [(ga, 0, False), (ga + 4, 30, False), (gb - 1, 30, True)]
    add("fx_flush", flush, HEAD, {"o": anim(fl_keys)})
    if buckets["hair"]:
        add("hair", buckets["hair"], HEAD)
    add("blush", FEATURES["blush"], FACE, {"o": vis_keys(vis["blush"], total)})
    if buckets["acc_head"]:
        add("acc_face", buckets["acc_head"], HEAD)
    for fname in ("eyes", "eyes_wide", "eyes_closed", "eyes_sleep", "eyes_happy", "brows_angry", "brow_raised",
                  "mouth_smile", "mouth_talk", "mouth_frown", "mouth_teeth", "mouth_sleep", "mouth_big", "mouth_smirk", "mouth_o"):
        if fname in ("eyes_wide", "mouth_o") and not character:
            continue
        add(fname, FEATURES[fname], FACE, {"o": vis_keys(vis[fname], total)})
    # shifty eyes slide
    ca, cb = A("claim")
    add("eyes_shifty", FEATURES["eyes_shifty"], FACE, {
        "o": vis_keys(vis["eyes_shifty"], total),
        "p": anim([(0, [0, 0, 0], True), (ca, [0, 0, 0], False), (ca + 10, [-8, 0, 0], False), (ca + 20, [0, 0, 0], False), (cb - 1, [0, 0, 0], True)])})
    if buckets["acc_headphones"]:
        c1a, c1b = A("call_1"); c2a, c2b = A("call_2")
        add("acc_headphones", buckets["acc_headphones"], HEAD, {
            "p": anim([(0, [0, 0, 0], True), (c1a, [0, 0, 0], False), (c1a + 4, [0, -6, 0], False), (c1b - 1, [0, 0, 0], True),
                       (c2a, [0, 0, 0], False), (c2a + 10, [0, -28, 0], False), (c2b - 1, [0, -28, 0], True), (c2b, [0, 0, 0], True)]),
            "o": anim([(0, 100, True), (c2a, 100, False), (c2a + 10, 0, False), (c2b - 1, 0, True), (c2b, 100, True)])})
    if buckets["acc_front"]:
        add("acc_front", buckets["acc_front"], BODY)
    # fx
    i1a, i1b = A("impatient_1"); i2a, i2b = A("impatient_2")
    add("fx_sweat", FX["fx_sweat"], HEAD, {
        "o": vis_keys([A("impatient_1"), A("impatient_2")], total),
        "p": anim([(0, [0, 0, 0], True), (i1a, [0, 0, 0], False), (i1b - 1, [0, 6, 0], True),
                   (i2a, [0, 0, 0], False), (i2a + 14, [0, 6, 0], True), (i2a + 15, [0, 0, 0], False), (i2b - 1, [0, 6, 0], True), (i2b, [0, 0, 0], True)])})
    sa, sb = A("sleep"); wa, wb = A("wake")
    add("fx_z", FX["fx_z"], HEAD, {
        "o": anim([(0, 0, True), (sa, 0, False), (sa + 10, 100, False), (sb - 10, 100, False), (sb - 1, 0, True), (wa, 60, False), (wa + 8, 0, True)]),
        "p": anim([(0, [0, 0, 0], True), (sa, [0, 6, 0], False), (sb - 1, [4, -8, 0], True), (wa, [4, -8, 0], False), (wa + 8, [8, -16, 0], True), (wa + 9, [0, 0, 0], True)])})
    fa, fb = A("fight")
    spark_o = [(0, 0, True)] + [(t, 100 if (t - fa) % 6 < 3 else 40, True) for t in range(fa, fb, 3)] + [(fb, 0, True)]
    add("fx_sparks", FX["fx_sparks"], HEAD, {"o": anim(spark_o)})
    ha, hb = A("happy")
    add("fx_heart", FX["fx_heart"], HEAD, {
        "a": st([56, -24, 0]), "p": anim([(0, [56, -24, 0], True), (ha, [56, -24, 0], False), (hb - 1, [58, -40, 0], True), (hb, [56, -24, 0], True)]),
        "s": anim([(0, [0, 0, 100], True), (ha, [0, 0, 100], False), (ha + 6, [120, 120, 100], False), (ha + 10, [100, 100, 100], False), (hb - 1, [100, 100, 100], True), (hb, [0, 0, 100], True)]),
        "o": anim([(0, 0, True), (ha, 100, False), (hb - 8, 100, False), (hb - 1, 0, True)])})

    rig_layers = list(reversed(layers))

    # main comp: precomp layer with bob / board / alight, halo underneath
    pk = [(0, [CX, CY, 0], False), (30, [CX, CY - 1.5, 0], False), (59, [CX, CY, 0], True)]
    a, b = A("talk"); pk += [(a, [CX, CY, 0], False), (a + 7, [CX, CY - 1, 0], False), (b - 1, [CX, CY, 0], True)]
    a, b = A("sleep"); pk += [(a, [CX, CY, 0], False), (a + 30, [CX, CY + 1.5, 0], False), (b - 1, [CX, CY, 0], True)]
    a, b = A("change_due")
    for t in range(a, b, 10):
        pk += [(t, [CX, CY, 0], False), (t + 5, [CX, CY - 4, 0], False)]
    pk += [(b - 1, [CX, CY, 0], True)]
    a, b = A("board"); pk += [(a, [CX + 70, CY, 0], False), (a + 12, [CX, CY, 0], False), (b - 1, [CX, CY, 0], True)]
    a, b = A("alight"); pk += [(a, [CX, CY, 0], False), (b - 1, [CX, CY - 12, 0], True)]
    for n, a, b in segs:
        if not any(k[0] == a for k in pk):
            pk.append((a, [CX, CY, 0], True))
    ba, bb = A("board"); la, lb = A("alight")
    ok = [(0, 100, True), (ba, 0, False), (ba + 6, 100, True), (la, 100, False), (lb - 1, 0, True)]
    if character:
        ok.append((lb, 100, True))
    pre = {"ddd": 0, "ind": 1, "ty": 0, "nm": "passenger" if not character else "character", "refId": "rig", "sr": 1,
           "ks": {"o": anim(ok), "r": st(0), "p": anim(pk), "a": st([CX, CY, 0]), "s": st([100, 100, 100])},
           "ao": 0, "w": W, "h": H, "ip": 0, "op": total, "st": 0, "bm": 0}
    ta, tb = A("targeted")
    halo = shape_layer("fx_halo", [C(0, 0, 60, "#FFE27A")], 2, None, {
        "p": st([CX, CY + 8, 0]),
        "o": anim([(0, 0, True), (ta, 0, False), (ta + 4, 100, False), (tb - 1, 0, True)]),
        "s": anim([(0, [80, 80, 100], True), (ta, [80, 80, 100], False), (ta + 4, [105, 105, 100], False), (tb - 1, [115, 115, 100], True)])}, total)
    return {
        "v": "5.9.0", "fr": FPS, "ip": 0, "op": total, "w": W, "h": H, "nm": os.path.basename(svg_path)[:-4], "ddd": 0,
        "assets": [{"id": "rig", "nm": "rig", "layers": rig_layers}],
        "layers": [pre, halo],
        "markers": [{"cm": n, "tm": a, "dr": b - a} for n, a, b in segs],
        "meta": {"g": "wassal design handoff (generated from illustrations/*.svg)", "loops": sorted(LOOPS & {n for n, _, _ in segs})},
    }


if __name__ == "__main__":
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(os.path.join(out, "passengers"), exist_ok=True)
    os.makedirs(os.path.join(out, "characters"), exist_ok=True)
    n = 0
    for f in sorted(os.listdir(os.path.join(src, "passengers"))):
        kind = f[:-4]
        data = build(os.path.join(src, "passengers", f), kind)
        json.dump(data, open(os.path.join(out, "passengers", kind + ".json"), "w"), separators=(",", ":"))
        n += 1
    for f in sorted(os.listdir(os.path.join(src, "characters"))):
        kind = f[:-4]
        data = build(os.path.join(src, "characters", f), kind, character=True)
        json.dump(data, open(os.path.join(out, "characters", kind + ".json"), "w"), separators=(",", ":"))
        n += 1
    print(n, "files")
