"""Minimal SVG -> Lottie shape conversion for the flat art in this project.

Supports: path (M L H V Q T C S A Z, absolute and relative), circle, ellipse, rect (rx),
<g> with transform (translate/scale/rotate incl. rotate(a cx cy)), fill/stroke/opacity
inheritance, stroke-dasharray, stroke-linecap/linejoin. Text is skipped.
Every element becomes one Lottie group; groups are returned in SVG paint order.
"""
import math, re
import xml.etree.ElementTree as ET

NS = "{http://www.w3.org/2000/svg}"

# ------------------------------------------------------------------ colours
def hex2rgba(h, alpha=1.0):
    h = h.strip()
    if h.startswith("rgba"):
        r, g, b, a = [float(x) for x in re.findall(r"[\d.]+", h)]
        return [round(r / 255, 4), round(g / 255, 4), round(b / 255, 4), 1], a
    h = h.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    return [round(int(h[i:i + 2], 16) / 255, 4) for i in (0, 2, 4)] + [1], alpha

# ------------------------------------------------------------------ path parsing
TOK = re.compile(r"[MmLlHhVvQqTtCcSsAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?")

def _arc_to_cubic(x1, y1, rx, ry, phi, fa, fs, x2, y2):
    if rx == 0 or ry == 0:
        return [((x1, y1), (x2, y2), (x2, y2))]
    phi = math.radians(phi)
    cp, sp = math.cos(phi), math.sin(phi)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p, y1p = cp * dx + sp * dy, -sp * dx + cp * dy
    rx, ry = abs(rx), abs(ry)
    lam = x1p ** 2 / rx ** 2 + y1p ** 2 / ry ** 2
    if lam > 1:
        rx, ry = rx * math.sqrt(lam), ry * math.sqrt(lam)
    num = rx ** 2 * ry ** 2 - rx ** 2 * y1p ** 2 - ry ** 2 * x1p ** 2
    den = rx ** 2 * y1p ** 2 + ry ** 2 * x1p ** 2
    co = math.sqrt(max(0, num / den)) * (-1 if fa == fs else 1)
    cxp, cyp = co * rx * y1p / ry, -co * ry * x1p / rx
    cx = cp * cxp - sp * cyp + (x1 + x2) / 2
    cy = sp * cxp + cp * cyp + (y1 + y2) / 2
    def ang(u, v):
        a = math.atan2(u[0] * v[1] - u[1] * v[0], u[0] * v[0] + u[1] * v[1])
        return a
    t1 = ang((1, 0), ((x1p - cxp) / rx, (y1p - cyp) / ry))
    dt = ang(((x1p - cxp) / rx, (y1p - cyp) / ry), ((-x1p - cxp) / rx, (-y1p - cyp) / ry))
    if not fs and dt > 0:
        dt -= 2 * math.pi
    elif fs and dt < 0:
        dt += 2 * math.pi
    segs = max(1, int(math.ceil(abs(dt) / (math.pi / 2))))
    d = dt / segs
    out = []
    for i in range(segs):
        a1, a2 = t1 + i * d, t1 + (i + 1) * d
        k = 4 / 3 * math.tan((a2 - a1) / 4)
        p1 = (math.cos(a1) - k * math.sin(a1), math.sin(a1) + k * math.cos(a1))
        p2 = (math.cos(a2) + k * math.sin(a2), math.sin(a2) - k * math.cos(a2))
        p3 = (math.cos(a2), math.sin(a2))
        def tr(p):
            x, y = p[0] * rx, p[1] * ry
            return (cp * x - sp * y + cx, sp * x + cp * y + cy)
        out.append((tr(p1), tr(p2), tr(p3)))
    return out

def parse_path(d):
    """Return list of subpaths; each = dict(v=[], i=[], o=[], c=bool) with absolute coords."""
    toks = TOK.findall(d)
    i = 0
    subs = []
    cur = None
    x = y = sx = sy = 0.0
    last_ctrl = None
    cmd = None
    def num():
        nonlocal i
        v = float(toks[i]); i += 1; return v
    def start(px, py):
        nonlocal cur
        cur = {"pts": [(px, py)], "in": [(0, 0)], "out": [(0, 0)], "c": False}
        subs.append(cur)
    def cubic(c1, c2, p):
        nonlocal x, y
        cur["out"][-1] = (c1[0] - x, c1[1] - y)
        cur["pts"].append(p)
        cur["in"].append((c2[0] - p[0], c2[1] - p[1]))
        cur["out"].append((0, 0))
        x, y = p
    def line(p):
        cubic((x, y), p, p)
    while i < len(toks):
        t = toks[i]
        if re.match(r"[A-Za-z]", t):
            cmd = t; i += 1
            if cmd in "Zz":
                if cur:
                    cur["c"] = True
                x, y = sx, sy
                last_ctrl = None
                continue
        rel = cmd.islower()
        C = cmd.upper()
        if C == "M":
            px, py = num(), num()
            if rel: px += x; py += y
            x, y, sx, sy = px, py, px, py
            start(px, py)
            cmd = "l" if rel else "L"
            last_ctrl = None
        elif C == "L":
            px, py = num(), num()
            if rel: px += x; py += y
            line((px, py)); last_ctrl = None
        elif C == "H":
            px = num(); px = px + x if rel else px
            line((px, y)); last_ctrl = None
        elif C == "V":
            py = num(); py = py + y if rel else py
            line((x, py)); last_ctrl = None
        elif C in "QT":
            if C == "Q":
                qx, qy = num(), num()
                if rel: qx += x; qy += y
            else:
                qx, qy = (2 * x - last_ctrl[0], 2 * y - last_ctrl[1]) if last_ctrl and last_ctrl[2] == "Q" else (x, y)
            px, py = num(), num()
            if rel: px += x; py += y
            c1 = (x + 2 / 3 * (qx - x), y + 2 / 3 * (qy - y))
            c2 = (px + 2 / 3 * (qx - px), py + 2 / 3 * (qy - py))
            cubic(c1, c2, (px, py)); last_ctrl = (qx, qy, "Q")
        elif C in "CS":
            if C == "C":
                c1 = (num(), num())
                if rel: c1 = (c1[0] + x, c1[1] + y)
            else:
                c1 = (2 * x - last_ctrl[0], 2 * y - last_ctrl[1]) if last_ctrl and last_ctrl[2] == "C" else (x, y)
            c2 = (num(), num()); p = (num(), num())
            if rel:
                c2 = (c2[0] + x, c2[1] + y); p = (p[0] + x, p[1] + y)
            cubic(c1, c2, p); last_ctrl = (c2[0], c2[1], "C")
        elif C == "A":
            rx, ry, phi, fa, fs, px, py = num(), num(), num(), num(), num(), num(), num()
            if rel: px += x; py += y
            for c1, c2, p in _arc_to_cubic(x, y, rx, ry, phi, int(fa), int(fs), px, py):
                cubic(c1, c2, p)
            last_ctrl = None
    out = []
    for s in subs:
        pts, ins, outs = s["pts"], s["in"], s["out"]
        if s["c"] and len(pts) > 1 and abs(pts[-1][0] - pts[0][0]) < 1e-6 and abs(pts[-1][1] - pts[0][1]) < 1e-6:
            ins[0] = ins[-1]
            pts, ins, outs = pts[:-1], ins[:-1], outs[:-1]
        out.append({"v": [[round(a, 3), round(b, 3)] for a, b in pts],
                    "i": [[round(a, 3), round(b, 3)] for a, b in ins],
                    "o": [[round(a, 3), round(b, 3)] for a, b in outs],
                    "c": s["c"]})
    return out

# ------------------------------------------------------------------ lottie helpers
def st(v):
    return {"a": 0, "k": v}

def tr(p=(0, 0), a=(0, 0), s=(100, 100), r=0, o=100):
    return {"ty": "tr", "p": st(list(p)), "a": st(list(a)), "s": st(list(s)), "r": st(r), "o": st(o),
            "sk": st(0), "sa": st(0), "nm": "Transform"}

def fill(color, opacity=100):
    rgba, a = hex2rgba(color)
    return {"ty": "fl", "c": st(rgba), "o": st(round(opacity * a, 2)), "r": 1, "nm": "Fill"}

def stroke(color, width, cap="butt", join="miter", opacity=100, dash=None):
    rgba, a = hex2rgba(color)
    s = {"ty": "st", "c": st(rgba), "o": st(round(opacity * a, 2)), "w": st(width),
         "lc": {"butt": 1, "round": 2, "square": 3}[cap], "lj": {"miter": 1, "round": 2, "bevel": 3}[join], "ml": 4, "nm": "Stroke"}
    if dash:
        s["d"] = [{"n": "d", "nm": "dash", "v": st(dash[0])}, {"n": "g", "nm": "gap", "v": st(dash[1] if len(dash) > 1 else dash[0])},
                  {"n": "o", "nm": "offset", "v": st(0)}]
    return s

def group(items, name="g", transform=None):
    return {"ty": "gr", "nm": name, "it": items + [transform or tr()], "np": len(items)}

# ------------------------------------------------------------------ svg walking
def parse_transform(t):
    """Return Lottie tr dict for an SVG transform string (subset)."""
    if not t:
        return None
    p = [0, 0]; s = [100, 100]; r = 0; a = [0, 0]
    for fn, args in re.findall(r"(\w+)\(([^)]*)\)", t):
        v = [float(x) for x in re.findall(r"-?[\d.]+(?:e-?\d+)?", args)]
        if fn == "translate":
            p = [p[0] + v[0], p[1] + (v[1] if len(v) > 1 else 0)]
        elif fn == "scale":
            s = [s[0] * v[0], s[1] * (v[1] if len(v) > 1 else v[0])]
        elif fn == "rotate":
            r += v[0]
            if len(v) == 3:
                a = [v[1], v[2]]; p = [p[0] + v[1], p[1] + v[2]]
    return tr(p, a, s, r)

def style_of(el, inh):
    stl = dict(inh)
    for k in ("fill", "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin", "stroke-dasharray", "opacity", "fill-opacity"):
        if el.get(k) is not None:
            stl[k] = el.get(k)
    if el.get("style"):
        for decl in el.get("style").split(";"):
            if ":" in decl:
                k, v = decl.split(":", 1); stl[k.strip()] = v.strip()
    return stl

def paint_items(stl):
    items = []
    op = float(stl.get("opacity", 1)) * 100
    if stl.get("stroke") not in (None, "none"):
        dash = None
        if stl.get("stroke-dasharray"):
            dash = [float(x) for x in re.findall(r"[\d.]+", stl["stroke-dasharray"])]
        items.append(stroke(stl["stroke"], float(stl.get("stroke-width", 1)), stl.get("stroke-linecap", "butt"),
                            stl.get("stroke-linejoin", "miter"), 100, dash))
    f = stl.get("fill", "#000000")
    if f not in ("none",):
        items.append(fill(f, float(stl.get("fill-opacity", 1)) * 100))
    return items, op

def shape_items(el):
    tag = el.tag.replace(NS, "")
    g = lambda k, d=0: float(el.get(k, d))
    if tag == "path":
        return [{"ty": "sh", "nm": "Path", "ks": st(sp)} for sp in parse_path(el.get("d"))]
    if tag == "circle":
        return [{"ty": "el", "nm": "Ellipse", "p": st([g("cx"), g("cy")]), "s": st([2 * g("r"), 2 * g("r")]), "d": 1}]
    if tag == "ellipse":
        return [{"ty": "el", "nm": "Ellipse", "p": st([g("cx"), g("cy")]), "s": st([2 * g("rx"), 2 * g("ry")]), "d": 1}]
    if tag == "rect":
        w, h = g("width"), g("height")
        rx = float(el.get("rx", el.get("ry", 0)))
        return [{"ty": "rc", "nm": "Rect", "p": st([g("x") + w / 2, g("y") + h / 2]), "s": st([w, h]), "r": st(rx), "d": 1}]
    return []

def element_group(el, stl, name=None):
    """One Lottie group for a leaf element (shape + paint + own transform)."""
    shapes = shape_items(el)
    if not shapes:
        return None
    paints, op = paint_items(stl)
    t = parse_transform(el.get("transform")) or tr()
    t["o"] = st(op)
    return group(shapes + paints, name or el.tag.replace(NS, ""), t)

def walk(el, inh=None):
    """Yield (leaf_element, style, group_transforms[]) in paint order."""
    inh = inh or {"fill": "#000000"}
    for ch in el:
        tag = ch.tag.replace(NS, "")
        stl = style_of(ch, inh)
        if tag == "g":
            gt = parse_transform(ch.get("transform"))
            gop = float(ch.get("opacity", 1))
            sub_inh = dict(stl); sub_inh.pop("opacity", None)
            for leaf, lstl, chain in walk(ch, sub_inh):
                if gt is None and gop == 1:
                    yield leaf, lstl, chain          # plain <g>: flatten
                else:
                    yield leaf, lstl, [(gt, gop)] + chain
        elif tag in ("path", "circle", "ellipse", "rect"):
            yield ch, stl, []

def leaf_to_group(leaf, stl, chain, name=None):
    gr = element_group(leaf, stl, name)
    if gr is None:
        return None
    for gt, gop in reversed(chain):
        t = gt or tr()
        t = dict(t); t["o"] = st(gop * 100)
        gr = group([gr], "g", t)
    return gr

def load_svg(path):
    txt = open(path).read()
    # the sleeper is drawn with its head pre-tilted; the rig tilts the head in the `sleep` segment instead
    txt = txt.replace('<g transform="rotate(18)">', '<g>')
    root = ET.fromstring(txt)
    vb = [float(x) for x in root.get("viewBox").split()]
    return root, vb
