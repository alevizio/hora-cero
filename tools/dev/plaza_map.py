#!/usr/bin/env python3
"""Dev-only: draws the Plaza de Mayo's layout (godot/data/plaza.json) from straight above, as the rules see it, to a
PNG: the buildings and the solid things (grey, named), the carriageways and the tram tracks, the shelters (green, the
dark one dashed red), the service gate and the arcade's fuse box (the passages), the tram at its stops and the
colectivo, the cloths (brown), the lamps, the palms, the people by group with the ones who panic marked (and where
they run), the four starts, and a scale.
    python3 tools/dev/plaza_map.py [out.png] [pixels per metre]"""
import json
import os
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
DATA = os.path.join(ROOT, "godot", "data", "plaza.json")
U = 32.0


def main(out: str, ppm: float) -> None:
    d = json.load(open(DATA, encoding="utf-8"))
    p = d["plazaWorld"]
    W, H = d["width"] / U, d["height"] / U
    pad = 6.0
    img = Image.new("RGB", (int((W + pad * 2) * ppm), int((H + pad * 2) * ppm) + 40), (238, 234, 222))
    dr = ImageDraw.Draw(img, "RGBA")
    try:
        font = ImageFont.truetype(os.path.join(ROOT, "godot", "assets", "fonts", "BarlowCondensed-SemiBold.ttf"), int(ppm * 2.6))
        small = ImageFont.truetype(os.path.join(ROOT, "godot", "assets", "fonts", "BarlowCondensed-SemiBold.ttf"), int(ppm * 2.0))
    except OSError:
        font = small = ImageFont.load_default()

    def xy(x: float, z: float) -> tuple:
        return ((x + pad) * ppm, (z + pad) * ppm)

    def rect(x0, z0, x1, z1, fill=None, outline=None, width=1):
        dr.rectangle([xy(x0, z0), xy(x1, z1)], fill=fill, outline=outline, width=width)

    def units(o):
        return o["x"] / U, o["y"] / U, (o["x"] + o["w"]) / U, (o["y"] + o["h"]) / U

    # the map, the streets, the lawns' square
    rect(0, 0, W, H, fill=(226, 222, 210), outline=(120, 120, 110))
    for key, along in [("rivRoad", "x"), ("yriRoad", "x"), ("avmRoad", "x2"), ("bolRoad", "z"), ("balRoad", "z")]:
        a, b = p[key]
        if along == "x": rect(0, a, W, b, fill=(196, 196, 196))
        elif along == "x2": rect(0, a, p["bolivar"][0], b, fill=(196, 196, 196))
        else: rect(a, p["rivadavia"][1], b, p["yrigoyen"][0], fill=(196, 196, 196))
    x0, z0, x1, z1 = p["plaza"]
    rect(x0, z0, x1, z1, fill=(214, 226, 204), outline=(150, 170, 140))
    for z in p["tracksZ"]:
        for dz in (-0.72, 0.72):
            dr.line([xy(0, z + dz), xy(W, z + dz)], fill=(90, 90, 90), width=max(1, int(ppm * 0.25)))
    # the solid things
    for o in d["obstacles"]:
        a = units(o)
        kind = o["kind"]
        if kind in ("building", "wall"):
            rect(*a, fill=(150, 146, 138), outline=(70, 70, 66), width=2)
            if o.get("label"):
                dr.text(xy((a[0] + a[2]) / 2 - len(o["label"]) * 0.45, (a[1] + a[3]) / 2 - 1.5), o["label"], fill=(30, 30, 28), font=font)
        elif kind in ("monument",):
            rect(*a, fill=(240, 240, 236), outline=(60, 60, 60), width=2)
            dr.text(xy(a[0], a[3] + 0.5), o.get("label", o["id"]), fill=(40, 40, 40), font=small)
        elif kind == "post":
            c = xy((a[0] + a[2]) / 2, (a[1] + a[3]) / 2)
            col = (60, 110, 50) if o["id"].startswith("palm") else ((40, 70, 160) if o["id"] == "flagpole" else (200, 150, 40))
            r = ppm * (1.4 if o["id"].startswith("palm") else 0.8)
            dr.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=col)
        else:
            rect(*a, fill=(110, 110, 104), outline=(50, 50, 50))
    # shelters
    for s in d["shelters"]:
        if "vehicle" in s:
            continue
        a = units(s)
        dark = "dark" in s
        rect(*a, fill=(120, 190, 110, 110), outline=(200, 40, 40) if dark else (40, 120, 40), width=3)
        dr.text(xy(a[0], a[1] - 2.6), s["label"] + (" (dark)" if dark else ""), fill=(30, 90, 30), font=small)
    # passages
    for q in d["passages"]:
        a = units(q)
        rect(a[0] - 0.4, a[1] - 0.4, a[2] + 0.4, a[3] + 0.4, outline=(220, 120, 0), width=3)
        dr.text(xy(a[2] + 0.8, a[1]), q["label"], fill=(170, 80, 0), font=small)
    # vehicles: the tram at each of its stops, the colectivo
    for v in d["vehicles"]:
        a = units(v)
        stops = v.get("stops", [])
        for i, sx in enumerate(stops or [v["x"]]):
            bx = sx / U
            rect(bx, a[1], bx + (a[2] - a[0]), a[3], fill=(60, 110, 70, 200 if i == 0 else 60), outline=(30, 60, 40), width=2)
        dr.text(xy(a[0], a[1] - 2.6), v["label"] + (" (stops %d)" % len(stops) if stops else ""), fill=(30, 60, 40), font=small)
    # cloths
    for c in d["canvases"]:
        cx, cz = c["x"] / U, c["y"] / U
        rect(cx - 1.0, cz - 0.7, cx + 1.0, cz + 0.7, fill=(150, 100, 50), outline=(80, 50, 20))
        dr.text(xy(cx + 1.4, cz - 1.2), c["label"], fill=(110, 70, 30), font=small)
    # people by group, the ones who panic and where they run
    groups = {}
    for person in d["people"]:
        groups.setdefault(person.get("group", ""), []).append(person)
    for g, members in groups.items():
        for person in members:
            c = xy(person["x"] / U, person["y"] / U)
            r = ppm * 0.7
            dr.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=(30, 60, 160))
            if person.get("panic"):
                f = person["panic"].get("flee")
                dr.ellipse([c[0] - r * 1.8, c[1] - r * 1.8, c[0] + r * 1.8, c[1] + r * 1.8], outline=(220, 40, 40), width=2)
                if f:
                    dr.line([c, xy(f[0] / U, f[1] / U)], fill=(220, 40, 40, 160), width=2)
                dr.text((c[0] + r * 2, c[1] - r * 2), "panics %ds" % int(person["panic"]["at"]), fill=(200, 30, 30), font=small)
        mx = sum(m["x"] for m in members) / len(members) / U
        mz = sum(m["y"] for m in members) / len(members) / U
        dr.text(xy(mx - 2, mz + 1.4), g, fill=(30, 50, 130), font=small)
    # the four
    for u in d["units"]:
        c = xy(u["x"] / U, u["y"] / U)
        r = ppm * 1.1
        dr.rectangle([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=(230, 170, 40), outline=(60, 40, 0), width=2)
        dr.text((c[0] + r * 1.4, c[1] - r * 1.4), u.get("name", u["id"]), fill=(120, 70, 0), font=font)
    # scale and title
    y = img.size[1] - 30
    dr.line([(pad * ppm, y), ((pad + 50) * ppm, y)], fill=(0, 0, 0), width=3)
    dr.text((pad * ppm, y + 4), "50 m", fill=(0, 0, 0), font=small)
    dr.text(((pad + 60) * ppm, y - 6), "Plaza de Mayo, 1958 — %d x %d m, %d people, need %d, buried at %ds" % (
        W, H, len(d["people"]), d["snowfall"]["need"], d["snowfall"]["bury"]), fill=(0, 0, 0), font=font)
    img.save(out)
    print("wrote", out, img.size)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "/tmp/plaza_map.png", float(sys.argv[2]) if len(sys.argv) > 2 else 5.0)
