#!/usr/bin/env python3
"""Stitches tools/dev/collision_map.gd's tiles and draws the mission's solid things over them: obstacles red,
barriers (fences) orange, bushes (hiding places you walk into) green, guard routes blue, charge sites yellow.
    python3 tools/dev/collision_overlay.py <tiles dir> <mission json> <out.png>"""
import json, os, sys
from PIL import Image, ImageDraw
d, mission, out = sys.argv[1], sys.argv[2], sys.argv[3]
meta = json.load(open(os.path.join(d, "meta.json")))
m = json.load(open(mission))
t0 = Image.open(os.path.join(d, "tile_0_0.png"))
px = t0.size[0]
ppm = px / meta["tile"]
W, H = int(meta["cols"] * px), int(meta["rows"] * px)
img = Image.new("RGB", (W, H))
for r in range(meta["rows"]):
    for c in range(meta["cols"]):
        img.paste(Image.open(os.path.join(d, "tile_%d_%d.png" % (c, r))).convert("RGB"), (c * px, r * px))
ov = Image.new("RGBA", img.size, (0, 0, 0, 0))
dr = ImageDraw.Draw(ov)
def box(o, col, w=3):
    x0, y0 = o["x"] / 32 * ppm, o["y"] / 32 * ppm
    x1, y1 = (o["x"] + o["w"]) / 32 * ppm, (o["y"] + o["h"]) / 32 * ppm
    dr.rectangle([x0, y0, x1, y1], outline=col, width=w)
    dr.text((x0 + 4, y0 + 2), str(o.get("id", ""))[:18], fill=col)
for o in m.get("obstacles", []): box(o, (255, 40, 40, 255))
for o in m.get("barriers", []): box(o, (255, 160, 0, 255))
for o in m.get("bushes", []): box(o, (60, 255, 80, 255))
for g in m.get("guards", []):
    pts = [(p[0] / 32 * ppm, p[1] / 32 * ppm) for p in g.get("route", [])]
    if len(pts) > 1: dr.line(pts + [pts[0]], fill=(80, 160, 255, 220), width=3)
    if pts: dr.ellipse([pts[0][0] - 8, pts[0][1] - 8, pts[0][0] + 8, pts[0][1] + 8], outline=(80, 160, 255, 255), width=3); dr.text((pts[0][0] + 10, pts[0][1]), g["id"], fill=(120, 190, 255, 255))
for c in m.get("charges", []):
    x, y = c["x"] / 32 * ppm, c["y"] / 32 * ppm
    dr.ellipse([x - 6, y - 6, x + 6, y + 6], fill=(255, 230, 0, 255))
img = Image.alpha_composite(img.convert("RGBA"), ov).convert("RGB")
img.save(out, quality=88)
print("wrote", out, img.size, "px/m", ppm)
