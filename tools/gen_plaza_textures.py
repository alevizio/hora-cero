#!/usr/bin/env python3
"""Procedural textures for the Plaza de Mayo kit (scripts/three_d/plaza_kit.gd): the square's landmarks as they stood on
a snowy winter night in 1958, and the city's vehicles of the time.
Usage:  python3 tools/gen_plaza_textures.py           (then `godot --headless --import`, then this again with
        --fix-imports, and `godot --headless --import` once more: mip-maps on, lossless, the wall layers as an array)
Output: godot/assets/tex/plaza/
  pwalls_a.webp / pwalls_n.webp: the tiling surfaces as one array texture (512 px = 2.56 m a layer, like the
      structures kit), the layers named in LAYERS (mirrored in plaza_kit.gd, WALL_LAYERS). Alpha: roughness where the
      kit says so (ROUGH_ALPHA there), else how much snow a texel catches (the colonial tiles' channels).
  plaza_a.png: the detail atlas, 2048 x 1024, cells in ATLAS (mirrored in plaza_kit.gd): windows lit and dark, arched
      windows, doors, signs with invented names, railings, palm fronds, twigs, the flag, vehicle parts.
Everything written on these is invented (no real business, line, company or brand) except the national flag and the
names of public places (Plaza de Mayo)."""
import os
import sys
sys.dont_write_bytecode = True
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from structures_texlib import *
import gen_boca_textures as boca

HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.normpath(os.path.join(HERE, '..', 'godot', 'assets', 'tex'))
OUT = os.path.join(TEX, 'plaza')
N = 512
SERIF = '/usr/share/fonts/truetype/crosextra/Caladea-Bold.ttf'
SANS = '/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf'
COND = os.path.normpath(os.path.join(HERE, '..', 'godot', 'assets', 'fonts', 'BarlowCondensed-SemiBold.ttf'))

# the array's layers, in order (plaza_kit.gd WALL_LAYERS)
LAYERS = ['render', 'rustic', 'ashlar', 'marble', 'teja', 'slate', 'metal', 'bronze', 'snow', 'planks', 'paint', 'bark',
          'leaves', 'rubber', 'stucco', 'stone']

A_W, A_H = 2048, 1024
ATLAS = {
    # tall windows and doors, 128 x 256
    'win_lit0': (0, 0, 128, 256), 'win_lit1': (128, 0, 128, 256), 'win_lit2': (256, 0, 128, 256),
    'win_lit3': (384, 0, 128, 256), 'win_lit4': (512, 0, 128, 256),
    'win_dark0': (640, 0, 128, 256), 'win_dark1': (768, 0, 128, 256), 'win_dark2': (896, 0, 128, 256),
    'arch_lit0': (1024, 0, 128, 256), 'arch_lit1': (1152, 0, 128, 256), 'arch_dark0': (1280, 0, 128, 256),
    'modern_lit': (1408, 0, 128, 256), 'modern_dark': (1536, 0, 128, 256),
    'reja_lit': (1664, 0, 128, 256), 'reja_dark': (1792, 0, 128, 256), 'shutter': (1920, 0, 128, 256),
    'door_panel': (0, 256, 128, 256), 'door_gate_lit': (128, 256, 128, 256), 'door_cabildo': (256, 256, 128, 256),
    'door_church': (384, 256, 128, 256), 'door_bank_lit': (512, 256, 128, 256), 'door_shop_lit': (640, 256, 128, 256),
    'arch_lit2': (768, 256, 128, 256), 'arch_dark1': (896, 256, 128, 256),
    # fronds, twigs, papers, railings
    'frond0': (1024, 256, 256, 128), 'frond1': (1024, 384, 256, 128), 'twigs': (1280, 256, 256, 256),
    'papers': (1536, 256, 256, 128), 'rail_ornate': (1536, 384, 256, 128),
    'fence_hoop': (1792, 256, 256, 64), 'balustrade': (1792, 320, 128, 64), 'grille': (1920, 320, 128, 64),
    'car_glass': (1792, 384, 128, 64), 'bus_win_lit': (1920, 384, 128, 64), 'tram_win_lit': (1792, 448, 128, 64),
    'shop_strip_lit': (1920, 448, 128, 64),
    # signs, 512 x 128
    'sign_subte': (0, 512, 512, 128), 'sign_cafe': (512, 512, 512, 128), 'sign_confiteria': (1024, 512, 512, 128),
    'sign_bar': (1536, 512, 512, 128),
    'filete_side': (0, 640, 256, 128), 'filete_rear': (256, 640, 256, 128), 'sign_soderia': (512, 640, 512, 128),
    'bus_dest': (1024, 640, 256, 64), 'tram_dest': (1024, 704, 256, 64), 'tram_company': (1280, 640, 256, 64),
    'kiosk_sign': (1280, 704, 256, 64), 'clock': (1536, 640, 128, 128), 'taxi_sign': (1664, 640, 128, 64),
    'libre': (1664, 704, 64, 64), 'plate': (1728, 704, 64, 64), 'sun_relief': (1792, 640, 128, 128),
    'laurel': (1920, 640, 128, 128),
    'cafe_lit': (0, 768, 256, 128), 'shop_lit': (256, 768, 256, 128), 'awning_cream': (512, 768, 256, 128),
    'awning_green': (768, 768, 256, 128), 'relief': (1024, 768, 512, 128), 'bus_num': (1536, 768, 128, 64),
    'plaque': (1536, 832, 128, 64), 'headlamp': (1664, 768, 64, 64), 'taillamp': (1728, 768, 64, 64),
    'hubcap': (1664, 832, 64, 64), 'oculus_lit': (1728, 832, 64, 64), 'dormer_lit': (1792, 768, 128, 128),
    'dormer_dark': (1920, 768, 128, 128),
    'glow': (0, 896, 64, 64), 'white': (64, 896, 64, 64), 'dark': (0, 960, 64, 64), 'oculus_dark': (64, 960, 64, 64),
    'flag': (128, 896, 256, 128), 'magazines': (384, 896, 256, 128), 'tiles_lit': (640, 896, 128, 128),
    'tram_num': (768, 896, 128, 64), 'grille_truck': (768, 960, 128, 64), 'crate_side': (896, 896, 128, 64),
    'siphons': (896, 960, 128, 64), 'cafe_glass': (1024, 896, 256, 128), 'bench_iron': (1280, 896, 256, 128),
    'lamp_glass': (1536, 896, 64, 64), 'spokes': (1600, 896, 64, 64),
    # the palms' dry fronds, the iron bars over the Casa Rosada's ground-floor windows
    'frond_dry': (1664, 896, 256, 128), 'bars': (1920, 896, 128, 128),
}


def save_png(name, rgb, alpha=None):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + '.png')
    if alpha is None:
        save_rgb(path, rgb)
    else:
        save_rgba(path, rgb, alpha)
    print('wrote', name)


def c8(hex_str):
    return tuple(int(v * 255) for v in col(hex_str))


# --------------------------------------------------------------------------------------------------------------------
# Tiling layers (near white where the builder's vertex colour gives the colour)
# --------------------------------------------------------------------------------------------------------------------
def tex_render():
    """A well-kept painted render on a public building: smooth, near white, the faintest trowel and damp, a soft grime
    darkening near the foot. V anchored at the ground."""
    shape = (N, N)
    x, y = grid(shape)
    big = fbm(shape, 2.4, 601)
    trowel = fbm(shape, 1.2, 602, ax=3.0, ay=1.0, lo=8)
    v = 0.88 + 0.035 * (big - 0.5) + 0.025 * (trowel - 0.5)
    rgb = np.stack([v, v * 0.99, v * 0.975], -1)
    streak = fbm(shape, 1.4, 603, ax=0.15, ay=5.0, lo=6)
    rgb = rgb * (1 - 0.05 * smooth(streak, 0.6, 0.9))[..., None]
    rgb = painterly(rgb, 0.3, 604)
    h = 0.6 + 0.08 * trowel + 0.05 * big
    return rgb, normal_from_height(h, 2.0), np.full(shape, 0.9, np.float32)


def tex_rustic():
    """Banded rustication: courses 0.64 m high with deep horizontal channels and faint staggered joints, as on the
    ground floors of the palaces. Near white."""
    shape = (N, N)
    x, y = grid(shape)
    ch = N / 4.0
    row = np.floor(y / ch)
    fy = y - row * ch
    blk = N / 2.0
    xs = x + np.mod(row, 2) * blk * 0.5
    fx = np.mod(xs, blk)
    # the channel: a V cut 22 mm deep, its upper lip sharp and its lower one rounded by a century of lime wash
    groove_h = smooth(fy, 0.0, 10.0) * smooth(ch - fy, 0.0, 6.0)
    groove_v = smooth(fx, 0.0, 2.0) * smooth(blk - fx, 0.0, 2.0)
    # (banded: the channels run along the courses; the joints between the blocks are barely there, or it reads as brick)
    face = groove_h * (0.92 + 0.08 * groove_v)
    # each block's face a little cushioned (lighter in the middle), the courses a shade apart
    cushion = smooth(fy, 0.0, ch * 0.5) * smooth(ch - fy, 0.0, ch * 0.5)
    tone = 0.86 + 0.045 * (cell_rand(np.floor(xs / blk), row, 61, 2, 4) - 0.5) + 0.035 * (fbm(shape, 2.0, 611) - 0.5) + 0.03 * cushion
    rgb = np.stack([tone, tone * 0.99, tone * 0.975], -1) * (0.5 + 0.5 * face)[..., None]
    # dirt kept in the channels, a little run down from them
    dirt = (1 - face) + 0.35 * smooth(fy, 10.0, 0.0) * fbm(shape, 1.2, 614, ax=0.2, ay=3.0, lo=4)
    rgb = rgb * (1 - 0.18 * np.clip(dirt, 0, 1))[..., None]
    rgb = painterly(rgb, 0.3, 612)
    h = face * 0.85 + 0.06 * cushion + 0.04 * fbm(shape, 1.5, 613)
    return rgb, normal_from_height(h, 7.0), np.full(shape, 0.9, np.float32)


def tex_ashlar():
    """Dressed stone in courses half a metre high, blocks of random length, fine joints; a granular face, each block a
    shade apart. Pale grey-beige (the bank's and the ministries' stone; tinted for the cathedral)."""
    shape = (N, N)
    x, y = grid(shape)
    ch = N / 5.0
    row = np.floor(y / ch)
    fy = y - row * ch
    # blocks per course: lengths 0.85 .. 1.28 m, the joints staggered course by course
    rng = np.random.default_rng(621)
    jx = np.zeros(shape, np.float32) + 1e9
    bid = np.zeros(shape, np.float32)
    for r in range(5):
        cuts = [0.0]
        while cuts[-1] < N:
            cuts.append(cuts[-1] + rng.choice([170.0, 204.8, 256.0]))
        cuts = np.array(cuts) - rng.uniform(0, 160)
        m = row == r
        for i, c in enumerate(cuts):
            for k in (-N, 0, N):
                d = np.abs(x - (c + k))
                jx = np.where(m, np.minimum(jx, d), jx)
        bid = np.where(m, np.floor((x + rng.uniform(0, 160)) / 200.0) + r * 17, bid)
    joint = 1.0 - smooth(np.minimum(jx, np.minimum(fy, ch - fy)), 0.5, 2.5)
    grain = fbm(shape, 0.7, 622, lo=40) * 0.6 + fbm(shape, 1.6, 623) * 0.4
    tone = 0.82 + 0.035 * (cell_rand(bid, row, 62) - 0.5) + 0.06 * (grain - 0.5)
    rgb = np.stack([tone, tone * 0.985, tone * 0.955], -1)
    rgb = mix(rgb, rgb * 0.62, joint * 0.9)
    stain = smooth(fbm(shape, 1.3, 624, ax=0.2, ay=4.0, lo=4), 0.6, 0.85)
    rgb = rgb * (1 - 0.08 * stain)[..., None]
    rgb = painterly(rgb, 0.25, 625)
    h = (1 - joint) * 0.7 + grain * 0.1
    return rgb, normal_from_height(h, 4.0), np.full(shape, 0.88, np.float32)


def tex_marble():
    """White marble in big blocks: faint grey veins, a cool sheen, joints a hair wide (the Pirámide, the pedestals)."""
    shape = (N, N)
    x, y = grid(shape)
    base = fbm(shape, 2.6, 631)
    w1 = fbm(shape, 2.0, 632) * 60.0
    vein_f = np.sin((x + y * 0.6 + w1) / 23.0)
    vein = smooth(1.0 - np.abs(vein_f), 0.93, 1.0) * smooth(fbm(shape, 1.8, 633), 0.4, 0.7)
    v = 0.9 + 0.04 * (base - 0.5)
    rgb = np.stack([v, v, v * 1.01], -1)
    rgb = mix(rgb, col('9a9c9e'), vein * 0.45)
    ch = N / 4.0
    fy = np.mod(y, ch)
    fx = np.mod(x + np.mod(np.floor(y / ch), 2) * N / 4, N / 2)
    joint = 1.0 - smooth(np.minimum(np.minimum(fy, ch - fy), np.minimum(fx, N / 2 - fx)), 0.4, 1.6)
    rgb = mix(rgb, rgb * 0.75, joint * 0.6)
    rgb = painterly(rgb, 0.2, 634)
    return rgb, normal_from_height((1 - joint) * 0.5 + base * 0.05, 3.0), np.full(shape, 0.45, np.float32)


def tex_teja():
    """Colonial clay roof tiles (tejas musleras) in their channels: rows of curved caps over pans running down the
    slope (V), the courses overlapping, terracotta from orange to brown with soot and lichen. Alpha: how much snow a
    texel holds (the pans between the caps fill; the caps' crowns stay red)."""
    shape = (N, N)
    x, y = grid(shape)
    per = N / 16.0                       # a cap and a pan every 0.16 m across
    course = N / 6.0                     # courses 0.43 m down the slope
    cx = np.mod(x, per) / per            # 0..1 across one cap+pan
    ix = np.floor(x / per)
    row = np.floor(y / course)
    fy = np.mod(y, course) / course
    # caps: a half cylinder over the first half; pans: a shallow trough over the second
    cap = np.clip(1.0 - ((cx - 0.25) / 0.27) ** 2, 0, 1) ** 0.5
    pan = np.clip(((cx - 0.75) / 0.27) ** 2, 0, 1) * 0.25
    is_cap = cx < 0.5
    h = np.where(is_cap, 0.45 + 0.5 * cap, 0.2 + pan)
    # each tile is wider at its foot (downhill = image bottom) and overlaps the next
    lip = smooth(fy, 0.82, 0.98)
    h = h + lip * 0.12 * is_cap
    tile_tone = cell_rand(ix, row, 64, 16, 6)
    base = mix(col('a24a2c'), col('c8703e'), tile_tone[..., None])
    base = mix(base, col('7a3a26'), (cell_rand(ix + 3, row, 65, 16, 6) < 0.18)[..., None] * 0.6)
    shade = np.where(is_cap, 0.62 + 0.45 * cap, 0.45 + 0.2 * (1 - pan * 4))
    rgb = base * shade[..., None]
    rgb = rgb * (1 - 0.35 * smooth(fy, 0.9, 1.0) * is_cap)[..., None]
    soot = smooth(fbm(shape, 1.6, 641), 0.55, 0.8)
    rgb = mix(rgb, col('3a2a22'), soot * 0.3)
    lichen = smooth(fbm(shape, 1.2, 642, lo=6), 0.72, 0.8) * (1 - is_cap)
    rgb = mix(rgb, col('7a7a5a'), lichen * 0.5)
    rgb = painterly(rgb, 0.3, 643)
    catch = np.where(is_cap, 0.05 + 0.3 * (1 - cap) ** 2, 1.0)
    catch = np.clip(catch * (0.85 + 0.3 * fbm(shape, 1.5, 644)), 0, 1)
    return rgb, normal_from_height(h, 6.0), catch


def tex_bronze():
    """Cast bronze outdoors: dark brown-olive with a warm sheen on the high spots and green verdigris running down from
    every ledge (the statues, the plaques, the lamp fittings). Metallic in the kit."""
    shape = (N, N)
    base = fbm(shape, 2.2, 651)
    rgb = mix(col('3a2c1c'), col('6a5232'), base[..., None])
    streak = fbm(shape, 1.3, 652, ax=0.12, ay=6.0, lo=5)
    verd = smooth(streak * 0.7 + fbm(shape, 1.8, 653) * 0.3, 0.55, 0.8)
    rgb = mix(rgb, col('4f7a66'), verd * 0.7)
    rgb = painterly(rgb, 0.3, 654)
    return rgb, normal_from_height(base * 0.4 + streak * 0.2, 2.0), np.full(shape, 0.5, np.float32)


def tex_paint():
    """Car paint, near white: smooth, the faintest orange peel, road grime rising from the bottom of the tile (the body
    panels' UV start at the sills)."""
    shape = (N, N)
    x, y = grid(shape)
    peel = fbm(shape, 0.9, 661, lo=40)
    v = 0.9 + 0.02 * (fbm(shape, 2.4, 662) - 0.5)
    rgb = np.stack([v, v, v], -1)
    grime = smooth(y, N * 0.75, N) * (0.5 + 0.5 * fbm(shape, 1.4, 663, ax=0.3, ay=3.0))
    rgb = rgb * (1 - 0.35 * grime)[..., None]
    return rgb, normal_from_height(peel * 0.15, 1.0), np.full(shape, 0.3, np.float32)


def tex_bark():
    """A Canary palm's trunk: the diamond pattern of old leaf bases (U round the trunk, V up), fibre in the joints,
    brown-grey. Also does for the plane trees' boles at a distance."""
    shape = (N, N)
    x, y = grid(shape)
    # rotated grid of diamonds: 8 round, 10 up a tile
    u = x / N * 8.0
    v = y / N * 10.0
    a = u + v
    b = u - v
    fa = np.mod(a, 1.0)
    fb = np.mod(b, 1.0)
    d = np.minimum(np.minimum(fa, 1 - fa), np.minimum(fb, 1 - fb))
    scale = smooth(d, 0.0, 0.22)
    lower = smooth(np.mod(v, 1.0), 0.0, 1.0)
    h = scale * (0.6 + 0.4 * lower)
    tone = cell_rand(np.floor(a), np.floor(b), 67)
    base = mix(col('6a5a46'), col('8a7a62'), tone[..., None])
    fibre = fbm(shape, 0.8, 671, ax=0.3, ay=3.0, lo=20)
    rgb = mix(col('3a2e24') * (0.8 + 0.4 * fibre[..., None]), base, scale[..., None])
    rgb = rgb * (0.75 + 0.35 * lower)[..., None]
    rgb = painterly(rgb, 0.3, 672)
    return rgb, normal_from_height(h, 6.0), np.full(shape, 0.95, np.float32)


def tex_stucco():
    """Lime stucco on a palace of the 1890s, washed in its colour (the vertex tint gives the Casa Rosada's dusty rose):
    near white, the wash laid unevenly, patches where it was made good (a shade apart, their edges a little proud),
    the trowel's long sweeps, a fine sandy grain, hairline crazing, a faint run of rain down it. V anchored at the
    ground, 2.56 m a tile; the large-scale blotches are the shader's (world space), so they never repeat."""
    shape = (N, N)
    x, y = grid(shape)
    wash = fbm(shape, 2.2, 701)
    sweeps = fbm(shape, 1.1, 702, ax=3.5, ay=1.0, lo=6)
    grain = fbm(shape, 0.5, 703, lo=60)
    # patches made good: a few blobs of fresher lime, a shade lighter or darker
    blob = fbm(shape, 3.0, 704, lo=2)
    patch = smooth(blob, 0.7, 0.74)
    patch2 = smooth(fbm(shape, 3.0, 705, lo=2), 0.74, 0.78)
    v = 0.87 + 0.04 * (wash - 0.5) + 0.022 * (sweeps - 0.5) + 0.035 * (grain - 0.5) + 0.03 * patch - 0.035 * patch2
    rgb = np.stack([v, v * 0.985, v * 0.975], -1)
    # crazing: a fine net of hairlines in the old wash
    cr = fbm(shape, 1.6, 706, lo=12)
    craze = smooth(np.abs(cr - 0.5), 0.012, 0.0) * smooth(fbm(shape, 2.0, 707), 0.45, 0.7)
    rgb = rgb * (1 - 0.12 * craze)[..., None]
    rain = smooth(fbm(shape, 1.3, 708, ax=0.12, ay=6.0, lo=5), 0.62, 0.92)
    rgb = rgb * (1 - 0.05 * rain)[..., None]
    rgb = painterly(rgb, 0.25, 709)
    edge = np.abs(np.gradient(patch)[0]) + np.abs(np.gradient(patch)[1]) + np.abs(np.gradient(patch2)[0]) + np.abs(np.gradient(patch2)[1])
    h = 0.5 + 0.06 * sweeps + 0.05 * grain + 0.03 * wash + 0.06 * np.clip(edge * 6.0, 0, 1) - 0.04 * craze
    return rgb, normal_from_height(h, 3.0), np.full(shape, 0.92, np.float32)


def tex_stone():
    """Dressed cream limestone for the trims (cornices, string courses, pilasters, window surrounds, balustrades): near
    white for the tint, a fine dense grain with a few shells and darker flecks, faint claw tooling, the blocks long."""
    shape = (N, N)
    x, y = grid(shape)
    grain = fbm(shape, 0.6, 711, lo=50) * 0.6 + fbm(shape, 1.4, 712) * 0.4
    tool = fbm(shape, 1.0, 713, ax=1.0, ay=6.0, lo=20)
    fleck = smooth(white(shape, 714), 0.985, 1.0)
    v = 0.86 + 0.05 * (grain - 0.5) + 0.02 * (tool - 0.5) - 0.12 * fleck
    rgb = np.stack([v, v * 0.985, v * 0.955], -1)
    # joints between blocks every 1.28 m along, hair-fine
    jx = np.minimum(np.mod(x, N / 2), N / 2 - np.mod(x, N / 2))
    joint = 1 - smooth(jx, 0.4, 1.6)
    rgb = mix(rgb, rgb * 0.8, joint[..., None] * 0.6)
    rgb = painterly(rgb, 0.2, 715)
    h = 0.5 + 0.08 * grain + 0.04 * tool - 0.3 * joint
    return rgb, normal_from_height(h, 2.5), np.full(shape, 0.82, np.float32)


def load_layer(folder, name, size=N):
    a = Image.open(os.path.join(folder, name + '_a.png')).convert('RGBA').resize((size, size), Image.LANCZOS)
    n = Image.open(os.path.join(folder, name + '_n.png')).convert('RGB').resize((size, size), Image.LANCZOS)
    arr = np.asarray(a, np.float32) / 255.0
    return arr[..., :3], np.asarray(n, np.float32) / 255.0, arr[..., 3]


def tex_walls_array():
    struct = os.path.join(TEX, 'structures')
    bocad = os.path.join(TEX, 'boca')
    snowd = os.path.join(TEX, 'snow')
    made = {'render': tex_render, 'rustic': tex_rustic, 'ashlar': tex_ashlar, 'marble': tex_marble, 'teja': tex_teja,
            'bronze': tex_bronze, 'paint': tex_paint, 'bark': tex_bark, 'stucco': tex_stucco, 'stone': tex_stone}
    borrowed = {'slate': (struct, 'slate'), 'metal': (struct, 'steel'), 'snow': (snowd, 'snow'),
                'planks': (struct, 'planks'), 'leaves': (bocad, 'leaves'), 'rubber': (struct, 'rubber')}
    albedo = []
    normal = []
    for name in LAYERS:
        if name in made:
            rgb, nrm, a = made[name]()
        else:
            rgb, nrm, a = load_layer(*borrowed[name])
            if name in ('planks', 'leaves', 'rubber', 'snow'):
                a = np.full(rgb.shape[:2], 0.9, np.float32)
        albedo.append(np.dstack([rgb, a]))
        normal.append(nrm)
        print('layer', name)
    a = np.concatenate(albedo, 0)
    Image.fromarray(np.dstack([to8(a[..., :3]), to8(a[..., 3])]), 'RGBA').save(os.path.join(OUT, 'pwalls_a.webp'), quality=92, method=6)
    Image.fromarray(to8(np.concatenate(normal, 0)), 'RGB').save(os.path.join(OUT, 'pwalls_n.webp'), quality=94, method=6)
    print('wrote pwalls_a.webp, pwalls_n.webp')


# --------------------------------------------------------------------------------------------------------------------
# The atlas
# --------------------------------------------------------------------------------------------------------------------
def rgbf(img):
    return np.asarray(img.convert('RGB'), np.float32) / 255.0


def fit_font(d, text, path, size, width):
    f = ImageFont.truetype(path, size)
    while d.textlength(text, font=f) > width and size > 8:
        size -= 2
        f = ImageFont.truetype(path, size)
    return f, size


def cell_arch_window(w, h, seed, lit, frame='2c241c', dim=1.0):
    """A tall round-headed window: two leaves of glazing under a fanlight that follows the arch; outside the arch the
    cell is the frame's colour (the builder covers those corners with the spandrels of the wall)."""
    if lit:
        rgb = boca.interior(w, h, seed, curtain=['f0e2c4', 'c0503a', 'e8d8b0'][seed % 3], dim=dim)
    else:
        xx, yy = grid((h, w))
        rgb = mix(col('8e97b4'), col('262c3c'), smooth(yy / h, 0.0, 0.9)[..., None])
        streak = smooth(np.abs((xx / w + yy / h * 0.35) % 0.6 - 0.3), 0.06, 0.0) * 0.22
        rgb = np.clip(rgb + streak[..., None], 0, 1)
    s = 2
    img = Image.fromarray(to8(rgb)).resize((w * s, h * s))
    d = ImageDraw.Draw(img)
    W, H = w * s, h * s
    fr = c8(frame)
    r = W / 2
    spring = r
    # outside the arch: frame colour
    mask = Image.new('L', (W, H), 255)
    md = ImageDraw.Draw(mask)
    md.ellipse([0, 0, W - 1, 2 * r], fill=0)
    md.rectangle([0, spring, W, H], fill=0)
    img.paste(Image.new('RGB', (W, H), fr), (0, 0), mask)
    d.arc([6, 6, W - 7, 2 * r - 6], 180, 360, fill=fr, width=12)
    d.rectangle([0, spring, 11, H], fill=fr)
    d.rectangle([W - 12, spring, W, H], fill=fr)
    d.rectangle([0, H - 12, W, H], fill=fr)
    # fanlight: a transom at the springing, radiating bars
    d.rectangle([0, spring - 5, W, spring + 5], fill=fr)
    for k in range(1, 4):
        a = np.pi * (1 + k / 4.0)
        d.line([(r, spring), (r + np.cos(a) * r, spring + np.sin(a) * r)], fill=fr, width=5)
    d.rectangle([W / 2 - 5, spring, W / 2 + 5, H], fill=fr)
    for j in range(1, 4):
        yy = spring + (H - spring) * j / 4
        d.line([(0, yy), (W, yy)], fill=fr, width=4)
    out = rgbf(img.resize((w, h), Image.LANCZOS))
    yy = grid((h, w))[1]
    return out * (1 - 0.3 * smooth(yy, h - 12, h))[..., None]


def cell_modern(w, h, seed, lit):
    """A ministry's steel window of the thirties: a tall grid of small panes, an opening light in the middle."""
    if lit:
        rgb = boca.interior(w, h, seed, blind=0.18 if seed % 2 else 0.0, dim=0.95)
    else:
        xx, yy = grid((h, w))
        rgb = mix(col('9aa2bc'), col('20263a'), smooth(yy / h, 0.0, 0.95)[..., None])
    img = Image.fromarray(to8(rgb))
    d = ImageDraw.Draw(img)
    fr = c8('22262a')
    d.rectangle([0, 0, w - 1, h - 1], outline=fr, width=5)
    for i in range(1, 3):
        d.line([(w * i / 3, 0), (w * i / 3, h)], fill=fr, width=3)
    for j in range(1, 6):
        d.line([(0, h * j / 6), (w, h * j / 6)], fill=fr, width=3)
    return rgbf(img)


def cell_reja(w, h, seed, lit):
    """A colonial window behind its iron bars (the Cabildo): wooden leaves with small panes, a grille of square bars
    standing out in front."""
    if lit:
        rgb = boca.interior(w, h, seed, curtain='e8d8b8', dim=0.85)
    else:
        xx, yy = grid((h, w))
        rgb = mix(col('7a84a0'), col('1e222c'), smooth(yy / h, 0.0, 0.9)[..., None])
    img = Image.fromarray(to8(rgb))
    d = ImageDraw.Draw(img)
    wood = c8('3a4a32')
    d.rectangle([0, 0, w - 1, h - 1], outline=wood, width=8)
    d.line([(w / 2, 0), (w / 2, h)], fill=wood, width=6)
    for j in range(1, 4):
        d.line([(0, h * j / 4), (w, h * j / 4)], fill=wood, width=4)
    iron = c8('16181a')
    for i in range(1, 6):
        d.line([(w * i / 6, 0), (w * i / 6, h)], fill=iron, width=5)
    for j in (0.12, 0.5, 0.88):
        d.line([(0, h * j), (w, h * j)], fill=iron, width=5)
    return rgbf(img)


def cell_shutter_closed(w, h, seed):
    return boca.cell_shutter(w, h, seed, True)


def cell_door_panel(w, h, seed, ground='4a3020', arched=True):
    """A palace's double door: varnished wood in raised panels, a dark fanlight over it."""
    xx, yy = grid((h, w))
    base = col(ground) * (0.85 + 0.25 * fbm((h, w), 1.0, seed, ax=0.2, ay=4.0, lo=6))[..., None]
    fan = h * 0.24
    glass = yy < fan
    base = np.where(glass[..., None], col('22283a') * (0.8 + 0.4 * (1 - yy / fan))[..., None], base)
    for (a, b) in ((fan + 14, h * 0.55), (h * 0.6, h - 16)):
        for (l, r) in ((12, w * 0.5 - 8), (w * 0.5 + 8, w - 12)):
            m = (xx > l) & (xx < r) & (yy > a) & (yy < b)
            edge = (np.abs(xx - l) < 3) | (np.abs(yy - a) < 3)
            edge2 = (np.abs(xx - r) < 3) | (np.abs(yy - b) < 3)
            base = np.where(m[..., None], base * 1.12, base)
            base = np.where((m & edge)[..., None], base * 0.6, base)
            base = np.where((m & edge2)[..., None], base * 1.3, base)
    base = np.where((np.abs(xx - w * 0.5) < 2.5)[..., None], base * 0.4, base)
    base = np.where((np.abs(yy - fan) < 5)[..., None], col('2a1a10'), base)
    knob = np.sqrt((xx - w * 0.44) ** 2 + (yy - h * 0.6) ** 2) < 4
    base = np.where(knob[..., None], col('c9a050'), base)
    return np.clip(base, 0, 1)


def cell_door_cabildo(w, h, seed):
    """The Cabildo's colonial door: heavy boards painted dark green, iron studs in rows, a wicket outlined in it."""
    xx, yy = grid((h, w))
    board = np.mod(xx, w / 5.0) < 2.5
    base = col('2c3c2a') * (0.85 + 0.25 * fbm((h, w), 1.0, seed, ax=0.15, ay=5.0, lo=5))[..., None]
    base = np.where(board[..., None], base * 0.55, base)
    studs = (np.sqrt((np.mod(xx, w / 5.0) - w / 10.0) ** 2 + (np.mod(yy, h / 9.0) - h / 18.0) ** 2) < 3.2)
    base = np.where(studs[..., None], col('1a1a18'), base)
    hi = (np.sqrt((np.mod(xx, w / 5.0) - w / 10.0 + 1) ** 2 + (np.mod(yy, h / 9.0) - h / 18.0 + 1) ** 2) < 1.5)
    base = np.where(hi[..., None], col('8a8a80'), base)
    wick = ((np.abs(xx - w * 0.2) < 2) | (np.abs(xx - w * 0.8) < 2)) & (yy > h * 0.3) | ((np.abs(yy - h * 0.3) < 2) & (xx > w * 0.2) & (xx < w * 0.8))
    base = np.where(wick[..., None], base * 0.4, base)
    return np.clip(base, 0, 1)


def cell_door_church(w, h, seed):
    xx, yy = grid((h, w))
    base = col('3a2618') * (0.8 + 0.3 * fbm((h, w), 1.0, seed, ax=0.2, ay=4.0, lo=6))[..., None]
    for j in range(5):
        a, b = 12 + j * (h - 24) / 5.0, 12 + (j + 1) * (h - 24) / 5.0 - 8
        for (l, r) in ((12, w * 0.5 - 8), (w * 0.5 + 8, w - 12)):
            m = (xx > l) & (xx < r) & (yy > a) & (yy < b)
            edge = (np.abs(xx - l) < 3) | (np.abs(yy - a) < 3)
            base = np.where(m[..., None], base * 1.1, base)
            base = np.where((m & edge)[..., None], base * 0.55, base)
    base = np.where((np.abs(xx - w * 0.5) < 3)[..., None], base * 0.35, base)
    ring = np.abs(np.sqrt((xx - w * 0.38) ** 2 + (yy - h * 0.55) ** 2) - 7) < 1.6
    ring |= np.abs(np.sqrt((xx - w * 0.62) ** 2 + (yy - h * 0.55) ** 2) - 7) < 1.6
    return np.where(ring[..., None], col('a08040'), np.clip(base, 0, 1))


def cell_door_gate(w, h, seed, bank=False):
    """A wrought-iron (or bronze) gate with the lit hall behind it."""
    inner = boca.interior(w, h, seed, dim=0.9 if bank else 0.7)
    xx, yy = grid((h, w))
    metal = col('8a6a3a') if bank else col('141618')
    bars = (np.mod(xx, w / 8.0) < 3.5) | (np.abs(yy - h * 0.25) < 3) | (np.abs(yy - h * 0.7) < 3)
    ring = np.abs(np.sqrt((np.mod(xx, w / 2.0) - w / 4.0) ** 2 + (yy - h * 0.48) ** 2) - w * 0.14) < 2.0
    frame = (np.minimum(xx, w - xx) < 6) | (yy < 6) | (np.abs(xx - w / 2) < 3)
    m = bars | ring | frame
    return np.where(m[..., None], metal, inner)


def cell_frond(w, h, seed, dry=False):
    """A Canary palm's frond seen flat: the pale rachis along U (base at the left), the leaflets close-set, stiff and
    narrow, angled forward on both sides (the geometry folds the two sides up into the V they make along the rachis),
    turned into stout yellow spines toward the base, shortening to the tip. Olive to blue-green and dull, as the palm's
    fronds are; a dry frond (`dry`) straw-brown, its leaflets fewer, ragged and hanging back. Cut-out."""
    s = 3
    W, H = w * s, h * s
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(seed)
    cy = H / 2
    n = 70 if dry else 120
    for i in range(n):
        t = i / (n - 1)
        x0 = W * (0.03 + 0.95 * t)
        L = H * 0.47 * np.sin(np.pi * (0.1 + 0.86 * t)) ** 0.55 + H * 0.02
        spine = t < 0.17
        if spine:
            L = H * (0.08 + 0.12 * t / 0.17)
        for sgn in (-1, 1):
            if dry and rng.random() < 0.25:
                continue
            ang = np.radians(rng.uniform(28, 40) if not dry else rng.uniform(50, 80))
            Li = L * (rng.uniform(0.85, 1.05) if not dry else rng.uniform(0.5, 1.0))
            x1 = x0 + np.cos(ang) * Li
            y1 = cy + sgn * np.sin(ang) * Li
            g = rng.uniform(0.82, 1.12)
            if spine:
                colr = (int(150 * g), int(132 * g), int(78 * g), 255)
            elif dry:
                colr = (int(112 * g), int(90 * g), int(64 * g), 255)
            else:
                # olive to a blue-grey green, a few yellowed
                k = rng.random()
                base = (80, 102, 58) if k < 0.6 else ((66, 94, 70) if k < 0.9 else (104, 106, 54))
                colr = tuple(int(c * g) for c in base) + (255,)
            width = max(3, int((7 if not spine else 6) * (1.0 - 0.4 * t)))
            d.line([(x0, cy), (x1, y1)], fill=colr, width=width)
            # the leaflet's paler midrib catching the light
            if not spine and not dry:
                d.line([(x0, cy), ((x0 + x1) / 2, (cy + y1) / 2)], fill=tuple(min(255, int(c * 1.18)) for c in colr[:3]) + (255,), width=max(1, width // 3))
    rach = (170, 158, 110, 255) if not dry else (128, 104, 74, 255)
    d.line([(W * 0.01, cy), (W * 0.99, cy)], fill=rach, width=9)
    d.line([(W * 0.45, cy), (W * 0.99, cy)], fill=tuple(int(c * 0.85) for c in rach[:3]) + (255,), width=5)
    a = np.asarray(img.resize((w, h), Image.LANCZOS), np.float32) / 255.0
    rgb = a[..., :3] / np.maximum(a[..., 3:4], 1e-3)
    return np.clip(rgb, 0, 1), a[..., 3]


def cell_bars(w, h):
    """Wrought-iron bars over a window: square uprights with a collar where the two rails cross them, each rail a flat
    bar with a scroll between the uprights at the top. Cut-out, near black (tinted by the builder)."""
    s = 4
    W, H = w * s, h * s
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    iron = (38, 38, 40, 255)
    n = 6
    for i in range(n):
        x = (i + 0.5) * W / n
        d.rectangle([x - 7, 0, x + 7, H], fill=iron)
    for yy in (H * 0.08, H * 0.92):
        d.rectangle([0, yy - 8, W, yy + 8], fill=iron)
        for i in range(n):
            x = (i + 0.5) * W / n
            d.rectangle([x - 12, yy - 14, x + 12, yy + 14], fill=iron)
    for i in range(n):
        x = (i + 1.0) * W / n
        d.arc([x - 26, H * 0.08 + 6, x + 26, H * 0.08 + 58], 200, 340, fill=iron, width=6)
    a = np.asarray(img.resize((w, h), Image.LANCZOS), np.float32) / 255.0
    rgb = a[..., :3] / np.maximum(a[..., 3:4], 1e-3)
    return np.clip(rgb, 0, 1), a[..., 3]


def tex_grime():
    """The weathering of a stuccoed front (plaza/grime.png, 512 x 512, drawn multiplied over the walls by
    plaza_grime.gdshader): four strips 128 px high, each tiling along U (a strip is 4 m of wall), alpha how dark, the
    colour the dirt's own. 0: the streaks the rain carries down from a sill (a dark lip at the top, drips of every
    length); 1: soot and damp under a cornice or a string course (dark at the top, fading down in runs); 2: rising damp
    at a wall's foot (dark at the bottom up to a ragged tide line); 3: blotchy grime for recesses and soffits."""
    W, Hs = 512, 128
    rows = []
    rng = np.random.default_rng(731)
    shape = (Hs, W)
    x, y = grid(shape)
    t = y / (Hs - 1)                      # 0 at the strip's top, 1 at its foot
    # 0: sill streaks
    # (streaks a few centimetres to a decimetre wide, so that they still read from across the square; a soft wash of
    # the same dirt spreading under the whole sill)
    a = np.zeros(shape, np.float32)
    for k in range(46):
        cx = rng.uniform(0, W)
        L = rng.uniform(0.25, 1.0) ** 1.4
        wd = rng.uniform(3.0, 11.0)
        dx = np.minimum(np.abs(x - cx), W - np.abs(x - cx))
        a = np.maximum(a, smooth(wd - dx, 0.0, wd * 0.8) * smooth(L - t, 0.0, 0.3 * L + 0.02) * rng.uniform(0.45, 0.95))
    a = blur(a, 1.5)
    lip = smooth(0.18 - t, 0.0, 0.18) * (0.7 + 0.3 * fbm(shape, 1.5, 732))
    wash = smooth(0.7 - t, 0.0, 0.7) ** 1.5 * (0.6 + 0.4 * fbm(shape, 2.2, 741, ax=0.4, ay=1.5)) * 0.42
    noise = 0.7 + 0.6 * fbm(shape, 1.4, 733, ax=0.3, ay=2.0)
    rows.append(np.clip(np.maximum(np.maximum(a * noise, lip * 0.8), wash), 0, 1))
    # 1: soot under a cornice
    # (a broad soft fall from under the moulding down the whole strip, so that from across the square it reads as a
    # band of shadow and dirt, not a line; runs of it lower down)
    runs = blur(fbm(shape, 2.4, 734, ax=0.15, ay=2.5), 1.5)
    fall = np.clip(1.0 - t, 0.0, 1.0) ** 1.15 * smooth(t, -0.02, 0.06)
    b = fall * (0.55 + 0.45 * runs) + smooth(runs, 0.62, 0.85) * smooth(0.95 - t, 0.0, 0.6) * 0.3
    rows.append(np.clip(blur(b, 2.0) * (0.85 + 0.25 * fbm(shape, 2.4, 735)), 0, 1))
    # 2: rising damp
    tide = 0.45 + 0.2 * blur(fbm((8, W), 2.6, 736), 1.0)[0][None, :] + 0.03 * fbm(shape, 2.4, 737)
    damp = smooth(t, tide - 0.05, tide + 0.2) * (0.65 + 0.35 * fbm(shape, 2.2, 738))
    line = smooth(0.035 - np.abs(t - tide), 0.0, 0.035) * 0.3
    rows.append(np.clip(damp * 0.85 + line, 0, 1))
    # 3: blotches
    bl = smooth(fbm(shape, 2.4, 739), 0.35, 0.85)
    rows.append(np.clip(bl * (0.6 + 0.4 * fbm(shape, 1.0, 740, lo=20)), 0, 1))
    alpha = np.zeros((4 * Hs, W), np.float32)
    rgb = np.zeros((4 * Hs, W, 3), np.float32)
    tints = [col('3a332c'), col('2a2624'), col('3c3a34'), col('34302c')]
    for i, r in enumerate(rows):
        # a little clear margin at both ends of each strip, so its neighbours never bleed in
        m = smooth(t, 0.0, 0.03) * smooth(1.0 - t, 0.0, 0.03) if i != 0 else smooth(1.0 - t, 0.0, 0.03) * smooth(t, -0.01, 0.01)
        alpha[i * Hs:(i + 1) * Hs] = r * m
        rgb[i * Hs:(i + 1) * Hs] = tints[i]
    save_rgba(os.path.join(OUT, 'grime.png'), rgb, alpha)
    print('wrote grime.png')


def cell_twigs(w, h):
    a = Image.open(os.path.join(TEX, 'boca', 'twigs_a.png')).convert('RGBA').resize((w, h), Image.LANCZOS)
    arr = np.asarray(a, np.float32) / 255.0
    return arr[..., :3], arr[..., 3]


def cell_papers(w, h, seed, magazines=False):
    """A kiosk's front: newspapers and magazines hung on cords with pegs. The mastheads are a bar of black ink, the
    columns grey lines: nothing is legible (the papers are invented)."""
    rng = np.random.default_rng(seed)
    s = 2
    W, H = w * s, h * s
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for row in range(2):
        y0 = 8 + row * H / 2
        d.line([(0, y0), (W, y0)], fill=(60, 60, 60, 255), width=2)
        x = 4
        while x < W - 30:
            pw = rng.uniform(46, 70)
            ph = H / 2 - 18
            if magazines:
                c = tuple(int(v) for v in rng.choice([[200, 60, 50], [230, 190, 60], [60, 110, 170], [240, 230, 210], [60, 140, 90], [200, 120, 160]]))
                d.rectangle([x, y0 + 2, x + pw, y0 + ph], fill=c + (255,))
                d.rectangle([x + 4, y0 + 6, x + pw - 4, y0 + 18], fill=(250, 250, 240, 255))
                d.ellipse([x + pw * 0.2, y0 + ph * 0.35, x + pw * 0.8, y0 + ph * 0.85], fill=tuple(int(v * 0.7) for v in c) + (255,))
            else:
                d.rectangle([x, y0 + 2, x + pw, y0 + ph], fill=(222, 218, 204, 255))
                d.rectangle([x + 4, y0 + 6, x + pw - 4, y0 + 16], fill=(20, 20, 20, 255))
                for li in range(int((ph - 30) / 5)):
                    yy = y0 + 24 + li * 5
                    if rng.random() < 0.12:
                        continue
                    d.line([(x + 4, yy), (x + pw - 4, yy)], fill=(120, 118, 110, 255), width=2)
                if rng.random() < 0.5:
                    d.rectangle([x + 6, y0 + 26, x + pw * 0.55, y0 + ph * 0.6], fill=(70, 70, 66, 255))
            d.rectangle([x + pw * 0.5 - 2, y0 - 3, x + pw * 0.5 + 2, y0 + 6], fill=(170, 140, 90, 255))
            x += pw + rng.uniform(3, 7)
    a = np.asarray(img.resize((w, h), Image.LANCZOS), np.float32) / 255.0
    return np.clip(a[..., :3] / np.maximum(a[..., 3:4], 1e-3), 0, 1), a[..., 3]


def cell_rail_ornate(w, h):
    """Cast-iron railing with spear-headed bars, a lower rail and a band of rings (the Pirámide's fence, the Subte's
    stairs, the lawns' gates). Cut-out; repeats along U."""
    s = 2
    W, H = w * s, h * s
    img = Image.new('L', (W, H), 0)
    d = ImageDraw.Draw(img)
    d.rectangle([0, int(H * 0.2), W, int(H * 0.2) + 7], fill=255)
    d.rectangle([0, H - 22, W, H - 14], fill=255)
    n = 12
    for i in range(n):
        x = (i + 0.5) * W / n
        d.rectangle([x - 3, H * 0.08, x + 3, H - 14], fill=255)
        d.polygon([(x - 8, H * 0.1), (x, H * 0.0 + 2), (x + 8, H * 0.1)], fill=255)
    for i in range(n):
        x = (i + 1.0) * W / n
        d.ellipse([x - 13, H * 0.62 - 13, x + 13, H * 0.62 + 13], outline=255, width=5)
    a = np.asarray(img.resize((w, h), Image.LANCZOS), np.float32) / 255.0
    return np.full((h, w, 3), 0.85, np.float32), a


def cell_fence_hoop(w, h):
    """The low hoop fence round a lawn: overlapping iron hoops between a ground rail and a top wire."""
    s = 2
    W, H = w * s, h * s
    img = Image.new('L', (W, H), 0)
    d = ImageDraw.Draw(img)
    n = 8
    for i in range(n):
        x = i * W / n
        d.arc([x - W / n * 0.1, 8, x + W / n * 1.1, H * 2 - 8], 180, 360, fill=255, width=6)
    d.rectangle([0, H - 10, W, H - 4], fill=255)
    a = np.asarray(img.resize((w, h), Image.LANCZOS), np.float32) / 255.0
    return np.full((h, w, 3), 0.85, np.float32), a


def cell_grille(w, h, seed):
    """A car's grille, generic: horizontal chrome bars in a dark mouth; no badge, no name."""
    xx, yy = grid((h, w))
    dark = col('141416')
    bars = (np.mod(yy, h / 5.0) < h / 10.0)
    chrome = mix(col('5a5e66'), col('e8ecf0'), smooth(np.mod(yy, h / 5.0) / (h / 10.0), 0.0, 0.6)[..., None])
    rgb = np.where(bars[..., None], chrome, dark)
    edge = (np.minimum(xx, w - xx) < 5) | (np.minimum(yy, h - yy) < 4)
    return np.where(edge[..., None], col('c8ccd0'), rgb)


def cell_glass(w, h, seed):
    """A car's glass by night: the dark cab, the sky's sheen sliding across the top."""
    xx, yy = grid((h, w))
    # (no sharp streaks: laid over a curved pane they break into facets; one broad soft sheen instead)
    rgb = mix(col('5a6480'), col('141824'), smooth(yy / h, 0.0, 0.9)[..., None])
    sheen = np.exp(-((xx / w - 0.35) ** 2) / 0.05) * 0.06
    return np.clip(rgb + sheen[..., None], 0, 1)


def cell_lamp(w, h, red=False):
    xx, yy = grid((h, w))
    r = np.sqrt((xx - w / 2) ** 2 + (yy - h / 2) ** 2) / (w / 2)
    if red:
        rgb = mix(col('ff5040'), col('6a0c08'), smooth(r, 0.0, 0.9)[..., None])
    else:
        rgb = mix(col('fff4dc'), col('c8b890'), smooth(r, 0.2, 0.85)[..., None])
    rim = (r > 0.86)
    return np.where(rim[..., None], col('d8dce0'), rgb)


def cell_hubcap(w, h):
    xx, yy = grid((h, w))
    r = np.sqrt((xx - w / 2) ** 2 + (yy - h / 2) ** 2) / (w / 2)
    a = np.arctan2(yy - h / 2, xx - w / 2)
    # a small domed chrome cap, the black tyre round it, a narrow whitewall, the tread's dark edge
    rgb = mix(col('f4f6f8'), col('7a7e84'), smooth(r, 0.0, 0.42)[..., None])
    rgb = rgb * (0.85 + 0.15 * np.cos(a * 6))[..., None]
    rgb = np.where((r > 0.44)[..., None], col('1c1c1e'), rgb)
    rgb = np.where(((r > 0.64) & (r < 0.8))[..., None], col('dcdcd4'), rgb)
    return np.where((r > 0.8)[..., None], col('141416'), rgb)


def cell_spokes(w, h):
    """The tram's and the truck's plain steel wheel disc."""
    xx, yy = grid((h, w))
    r = np.sqrt((xx - w / 2) ** 2 + (yy - h / 2) ** 2) / (w / 2)
    rgb = mix(col('4a4c50'), col('202224'), smooth(r, 0.1, 0.9)[..., None])
    holes = (np.abs(r - 0.55) < 0.12) & (np.cos(np.arctan2(yy - h / 2, xx - w / 2) * 6) > 0.6)
    return np.where(holes[..., None], col('0c0c0e'), rgb)


def cell_enamel(w, h, text, ground='1c2e5c', ink='f2f0e8', font=COND, size_frac=0.62, spacing=0.06):
    """An enamel sign: a white letter on a deep ground, a white double line round it with rounded corners, the enamel
    chipped black at the edges and the bolt holes. The lettering is the kit's own: tall condensed capitals, widely
    tracked (no real system's sign is copied)."""
    s = 3
    W, H = w * s, h * s
    img = Image.new('RGB', (W, H), c8(ground))
    d = ImageDraw.Draw(img)
    ink8 = c8(ink)
    d.rounded_rectangle([6, 6, W - 7, H - 7], radius=26, outline=ink8, width=9)
    d.rounded_rectangle([24, 24, W - 25, H - 25], radius=16, outline=ink8, width=4)
    size = int(H * size_frac)
    f = ImageFont.truetype(font, size)
    track = size * spacing

    def width_of(fnt, tr):
        return sum(d.textlength(ch, font=fnt) for ch in text) + tr * (len(text) - 1)
    while width_of(f, track) > W - 110 and size > 10:
        size -= 2
        f = ImageFont.truetype(font, size)
        track = size * spacing
    x = (W - width_of(f, track)) / 2
    y = H / 2 - size * 0.62
    for ch in text:
        d.text((x, y), ch, font=f, fill=ink8)
        x += d.textlength(ch, font=f) + track
    for bx in (48, W - 48):
        d.ellipse([bx - 9, H / 2 - 9, bx + 9, H / 2 + 9], fill=c8('101010'), outline=ink8, width=2)
    rgb = rgbf(img.resize((w, h), Image.LANCZOS))
    xx, yy = grid((h, w))
    edge = np.minimum(np.minimum(xx, w - xx), np.minimum(yy, h - yy))
    chip = smooth(fbm((h, w), 1.4, 707, lo=6) - edge * 0.06, 0.62, 0.66)
    rgb = mix(rgb, col('141414'), chip[..., None] * 0.9)
    gloss = smooth(yy / h, 0.0, 0.5) * 0.08
    return np.clip(rgb + (0.06 - gloss)[..., None], 0, 1)


def cell_gilded(w, h, text, ground='0c0c0e', ink='e0b860', font=SERIF, ornament=True):
    """Gold leaf on black glass over a café or a shop: shaded serif capitals, a fine gilt line round them."""
    s = 2
    W, H = w * s, h * s
    img = Image.new('RGB', (W, H), c8(ground))
    d = ImageDraw.Draw(img)
    gold = c8(ink)
    d.rectangle([8, 8, W - 9, H - 9], outline=gold, width=3)
    d.rectangle([18, 18, W - 19, H - 19], outline=tuple(int(v * 0.6) for v in gold), width=2)
    f, size = fit_font(d, text, font, int(H * 0.5), W - (220 if ornament else 70))
    tw = d.textlength(text, font=f)
    tx, ty = (W - tw) / 2, H / 2 - size * 0.62
    for o in range(1, 4):
        d.text((tx + o, ty + o), text, font=f, fill=(40, 26, 10))
    d.text((tx, ty), text, font=f, fill=gold)
    if ornament:
        for cx, fl in ((60, 1.0), (W - 60, -1.0)):
            boca.scroll(d, cx, H / 2, 30, 1.4, gold, 5, fl, 0.5)
            boca.scroll(d, cx + fl * 34, H / 2, 16, 1.2, gold, 3, -fl, 2.0)
    rgb = rgbf(img.resize((w, h), Image.LANCZOS))
    yy = grid((h, w))[1]
    return np.clip(rgb + (0.05 * (1 - yy / h))[..., None], 0, 1)



def filete_flourish(d, cx, cy, r, fl, gold, cream, orn):
    """The fileteador's commonest figure, drawn from scratch: a spiral whose outer end sweeps on toward the middle in a
    long tail ending in a small curl, three acanthus leaves fanning from where they meet, a row of dots under it."""
    a0 = -np.pi * 0.5
    spiral = []
    for i in range(70):
        t = i / 69.0
        ang = a0 - fl * t * 2.0 * np.pi * 1.4
        rr = r * (1.0 - 0.78 * t)
        spiral.append((cx + np.cos(ang) * rr * fl, cy + np.sin(ang) * rr))
    x0, y0 = cx, cy - r
    tail = []
    for i in range(40):
        t = i / 39.0
        tail.append((x0 + fl * t * r * 2.6, y0 + np.sin(t * np.pi) * r * 0.5 + t * r * 0.7))
    ex, ey = tail[-1]
    curl = [(ex + fl * np.sin(t * 5.0) * r * 0.25 * (1 - t * 0.5), ey - (1 - np.cos(t * 5.0)) * r * 0.25 * (1 - t * 0.5)) for t in np.linspace(0, 1, 16)]
    wide = max(3, int(r * 0.14))
    for pts in (spiral, tail + curl):
        d.line(pts, fill=gold, width=wide, joint='curve')
        d.line(pts, fill=(255, 250, 232), width=max(1, wide // 3), joint='curve')
    for j, (ang, c) in enumerate(((-0.95, orn[0]), (-0.35, orn[1]), (0.35, orn[3]))):
        av = ang if fl > 0 else np.pi - ang
        boca.leaf(d, x0 + fl * r * 0.15, y0, av, r * 1.15, c, (250, 244, 228))
    dot = max(2, r * 0.07)
    d.ellipse([x0 - dot * 1.6, y0 - dot * 1.6, x0 + dot * 1.6, y0 + dot * 1.6], fill=cream)
    for k in range(3):
        dx = cx - fl * r * 0.2 + fl * k * dot * 3.2
        d.ellipse([dx - dot, cy + r * 1.05 - dot, dx + dot, cy + r * 1.05 + dot], fill=orn[2])

def cell_filete(w, h, seed, motto, rear=False, squeeze=1.0):
    """A colectivo's fileteado, painted straight onto the bus (cut-out: the paint shows between the strokes): fine
    lining in gold, scrolls ending in acanthus leaves in four colours with white highlights, a ribbon in the flag's
    colours and an invented motto in cream capitals shaded black."""
    # (`squeeze`: the panel's height over its width, against the cell's: drawn at the panel's proportions)
    s = 3
    W, H = w * s, int(h * s * squeeze)
    img = Image.new('RGBA', (W, H), (232, 210, 160, 0))
    d = ImageDraw.Draw(img)
    gold, cream, red = c8('e8b830'), c8('f4ead0'), c8('d8402e')
    orn = [c8(o) for o in ('d8402e', '3a9a58', 'e8b830', '3a7ac0')]
    rng = np.random.default_rng(seed)
    # fine double lining with rounded corners
    d.rounded_rectangle([8, 8, W - 9, H - 9], radius=24, outline=gold, width=5)
    d.rounded_rectangle([22, 22, W - 23, H - 23], radius=16, outline=cream, width=2)
    r = H * (0.19 if rear else 0.25)

    def flourish(cx, cy, fl):
        filete_flourish(d, cx, cy, r, fl, gold, cream, orn)

    fy = H * (0.42 if rear else 0.6)
    flourish(W * 0.06 + r * 1.1, fy, 1.0)
    flourish(W * 0.94 - r * 1.1, fy, -1.0)
    # (on the back the motto goes underneath, big; on the flank between the flourishes)
    inner = W * 0.9 if rear else W - 2 * (W * 0.06 + r * 4.0)
    f, size = fit_font(d, motto, SERIF, int(H * (0.26 if rear else 0.3)), inner * 0.92)
    tw = d.textlength(motto, font=f)
    tx, ty = (W - tw) / 2, (H * 0.64 if rear else H * 0.58 - size * 0.62)
    # the ribbon in the flag's colours under the motto, as wide as it
    ry = ty + size * 1.12
    for k, c in enumerate(('74acdf', 'f4f4f0', '74acdf')):
        d.rectangle([W / 2 - tw / 2, ry + k * 6, W / 2 + tw / 2, ry + k * 6 + 6], fill=c8(c) + (255,))
    for o in range(1, 6):
        d.text((tx + o, ty + o), motto, font=f, fill=(20, 14, 10))
    d.text((tx, ty), motto, font=f, fill=cream)
    small = img.resize((w, h), Image.LANCZOS)
    arr = np.asarray(small, np.float32) / 255.0
    a = np.clip(arr[..., 3] * 1.3, 0, 1)
    rgb = arr[..., :3] / np.maximum(arr[..., 3:4], 1e-3)
    rgb = np.where(arr[..., 3:4] > 0.02, np.clip(rgb, 0, 1), np.array([0.85, 0.7, 0.4], np.float32))
    return rgb, a


def cell_clock(w, h):
    """The Cabildo's clock: a white dial, black Roman hours, the hands at ten past six."""
    s = 3
    W, H = w * s, h * s
    img = Image.new('RGB', (W, H), c8('e8e2d0'))
    d = ImageDraw.Draw(img)
    cx, cy, r = W / 2, H / 2, W / 2 - 6
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=c8('f2eee2'), outline=c8('2a2a2a'), width=8)
    f = ImageFont.truetype(SERIF, int(r * 0.24))
    nums = ['XII', 'I', 'II', 'III', 'IIII', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI']
    for i, n in enumerate(nums):
        a = i / 12.0 * 2 * np.pi - np.pi / 2
        tx, ty = cx + np.cos(a) * r * 0.74, cy + np.sin(a) * r * 0.74
        tw = d.textlength(n, font=f)
        d.text((tx - tw / 2, ty - r * 0.14), n, font=f, fill=c8('1a1a1a'))
    for i in range(60):
        a = i / 60.0 * 2 * np.pi
        r0 = r * (0.9 if i % 5 else 0.86)
        d.line([(cx + np.cos(a) * r0, cy + np.sin(a) * r0), (cx + np.cos(a) * r * 0.96, cy + np.sin(a) * r * 0.96)], fill=c8('1a1a1a'), width=3)
    for frac, length, width in ((6 + 10 / 60.0, 0.5, 12), (10 / 60.0 * 12, 0.78, 7)):
        a = frac / 12.0 * 2 * np.pi - np.pi / 2
        d.line([(cx, cy), (cx + np.cos(a) * r * length, cy + np.sin(a) * r * length)], fill=c8('101010'), width=width)
    d.ellipse([cx - 10, cy - 10, cx + 10, cy + 10], fill=c8('101010'))
    return rgbf(img.resize((w, h), Image.LANCZOS))


def relief_shade(hmap, base, light=(-0.6, -0.7), strength=3.0):
    """Shade a heightfield as low relief lit from the upper left."""
    gy, gx = np.gradient(hmap)
    lam = 0.75 - (gx * light[0] + gy * light[1]) * strength
    return np.clip(base * lam[..., None], 0, 1)


def cell_sun_relief(w, h):
    """The golden sun on the Pirámide's east face: a disc with a calm face and sixteen rays, straight and flamed, on
    the white marble."""
    s = 3
    W, H = w * s, h * s
    img = Image.new('RGB', (W, H), c8('e2e0da'))
    d = ImageDraw.Draw(img)
    gold = c8('d8a838')
    cx, cy = W / 2, H / 2
    for i in range(16):
        a = i / 16.0 * 2 * np.pi
        L = W * (0.46 if i % 2 == 0 else 0.4)
        if i % 2 == 0:
            p = [(cx + np.cos(a - 0.08) * W * 0.18, cy + np.sin(a - 0.08) * W * 0.18), (cx + np.cos(a) * L, cy + np.sin(a) * L),
                 (cx + np.cos(a + 0.08) * W * 0.18, cy + np.sin(a + 0.08) * W * 0.18)]
            d.polygon(p, fill=gold)
        else:
            pts = []
            for k in range(12):
                t = k / 11.0
                rr = W * 0.18 + (L - W * 0.18) * t
                off = np.sin(t * np.pi * 3) * 0.08
                pts.append((cx + np.cos(a + off) * rr, cy + np.sin(a + off) * rr))
            d.line(pts, fill=gold, width=8)
    d.ellipse([cx - W * 0.2, cy - W * 0.2, cx + W * 0.2, cy + W * 0.2], fill=gold, outline=c8('8a5a18'), width=4)
    dk = c8('8a5a18')
    for ex in (-0.07, 0.07):
        d.arc([cx + W * ex - 12, cy - W * 0.06 - 6, cx + W * ex + 12, cy - W * 0.06 + 6], 0, 180, fill=dk, width=4)
    d.line([(cx, cy - W * 0.04), (cx - 4, cy + W * 0.04), (cx + 4, cy + W * 0.045)], fill=dk, width=3)
    d.arc([cx - W * 0.06, cy + W * 0.02, cx + W * 0.06, cy + W * 0.1], 20, 160, fill=dk, width=4)
    rgb = rgbf(img.resize((w, h), Image.LANCZOS))
    lum = rgb.mean(-1)
    hmap = blur(np.clip((0.9 - lum) * 2.0, 0, 1), 1.0, False)
    return relief_shade(hmap, rgb, strength=2.0)


def cell_laurel(w, h):
    """A laurel crown in high relief on marble (the Pirámide's other faces): pairs of leaves round a ring, a ribbon tied
    at the foot. White on white: the shading carries it."""
    s = 3
    W, H = w * s, h * s
    hm = Image.new('L', (W, H), 0)
    d = ImageDraw.Draw(hm)
    cx, cy, r = W / 2, H / 2, W * 0.32
    for side in (-1, 1):
        for i in range(10):
            t = i / 9.0
            a = np.pi / 2 + side * (0.35 + t * 2.4)
            px, py = cx + np.cos(a) * r, cy + np.sin(a) * r
            for off in (-0.5, 0.5):
                la = a + side * np.pi / 2 + off
                pts = []
                for k in range(10):
                    u = k / 9.0
                    ww = np.sin(u * np.pi) * 9
                    pts.append((u * 34, ww))
                pts += [(p[0], -p[1]) for p in reversed(pts)]
                ca, sa = np.cos(la), np.sin(la)
                d.polygon([(px + p[0] * ca - p[1] * sa, py + p[0] * sa + p[1] * ca) for p in pts], fill=200)
    d.ellipse([cx - 12, cy + r - 12, cx + 12, cy + r + 12], fill=255)
    d.line([(cx, cy + r), (cx - 30, cy + r + 50)], fill=230, width=9)
    d.line([(cx, cy + r), (cx + 30, cy + r + 50)], fill=230, width=9)
    hmap = blur(np.asarray(hm.resize((w, h), Image.LANCZOS), np.float32) / 255.0, 0.8, False)
    base = np.full((h, w, 3), 0.88, np.float32)
    return relief_shade(hmap, base, strength=3.5)


def cell_relief(w, h, seed):
    """The cathedral pediment's sculpture, as massing only: a crowd of draped standing and kneeling forms in low relief
    toward the middle, grey stone on stone. No scene is copied."""
    rng = np.random.default_rng(seed)
    xx, yy = grid((h, w))
    hmap = np.zeros((h, w), np.float32)
    n = 13
    for i in range(n):
        t = (i + 0.5) / n
        x0 = w * (0.08 + 0.84 * t) + rng.uniform(-6, 6)
        mid = 1.0 - abs(t - 0.5) * 2.0
        top = h * (0.92 - 0.72 * (0.25 + 0.75 * mid)) + rng.uniform(-4, 4)
        bw = w * 0.026 * rng.uniform(0.8, 1.2)
        body = np.clip(1.0 - ((xx - x0) / bw) ** 2, 0, 1) * smooth(yy, top + bw * 1.6, top + bw * 2.4) * (yy < h - 6)
        head = np.clip(1.0 - ((xx - x0) ** 2 + (yy - top - bw * 0.9) ** 2) / (bw * 0.8) ** 2, 0, 1)
        fold = 0.85 + 0.15 * np.sin((xx - x0) / bw * 6.0 + yy * 0.08)
        hmap = np.maximum(hmap, np.maximum(body * fold, head) * (0.6 + 0.4 * mid))
    hmap = blur(hmap, 1.6, False) * 0.55
    base = np.full((h, w, 3), 0.86, np.float32) * col('d8d0c0')
    rgb = relief_shade(hmap, base, strength=3.0)
    # the frame of the tympanum: its floor band
    return np.where((yy > h - 6)[..., None], base * 0.85, rgb)


def cell_flag(w, h):
    """The national flag: sky blue, white, sky blue, the Sun of May in the middle (its sixteen straight and sixteen
    flamed rays, a face)."""
    s = 4
    W, H = w * s, h * s
    img = Image.new('RGB', (W, H), c8('74acdf'))
    d = ImageDraw.Draw(img)
    d.rectangle([0, H / 3, W, 2 * H / 3], fill=c8('f6f6f2'))
    gold = c8('f6b40e')
    brown = c8('85340a')
    cx, cy = W / 2, H / 2
    R = H * 0.15
    r = R * 0.42
    for i in range(32):
        a = i / 32.0 * 2 * np.pi - np.pi / 2
        if i % 2 == 0:
            p = [(cx + np.cos(a - 0.09) * r * 1.02, cy + np.sin(a - 0.09) * r * 1.02), (cx + np.cos(a) * R, cy + np.sin(a) * R),
                 (cx + np.cos(a + 0.09) * r * 1.02, cy + np.sin(a + 0.09) * r * 1.02)]
            d.polygon(p, fill=gold, outline=brown)
        else:
            pts = []
            for k in range(14):
                t = k / 13.0
                rr = r * 1.02 + (R * 0.95 - r * 1.02) * t
                off = np.sin(t * np.pi * 3) * 0.07 * (1 - t * 0.5)
                pts.append((cx + np.cos(a + off) * rr, cy + np.sin(a + off) * rr))
            d.line(pts, fill=brown, width=7)
            d.line(pts, fill=gold, width=4)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=gold, outline=brown, width=3)
    lw = 3
    for ex in (-0.35, 0.35):
        d.arc([cx + r * ex - r * 0.18, cy - r * 0.32, cx + r * ex + r * 0.18, cy - r * 0.08], 200, 340, fill=brown, width=lw)
        d.ellipse([cx + r * ex - 4, cy - r * 0.16, cx + r * ex + 4, cy - r * 0.08], fill=brown)
    d.line([(cx, cy - r * 0.1), (cx - r * 0.08, cy + r * 0.2), (cx + r * 0.05, cy + r * 0.22)], fill=brown, width=lw)
    d.arc([cx - r * 0.3, cy + r * 0.1, cx + r * 0.3, cy + r * 0.5], 20, 160, fill=brown, width=lw)
    return rgbf(img.resize((w, h), Image.LANCZOS))


def cell_text(w, h, text, ground, ink, font=SANS, border=True, frac=0.6):
    s = 3
    W, H = w * s, h * s
    img = Image.new('RGB', (W, H), c8(ground))
    d = ImageDraw.Draw(img)
    f, size = fit_font(d, text, font, int(H * frac), W - 24)
    tw = d.textlength(text, font=f)
    if border:
        d.rectangle([4, 4, W - 5, H - 5], outline=c8(ink), width=4)
    d.text(((W - tw) / 2, H * 0.5 - size * 0.62), text, font=f, fill=c8(ink))
    return rgbf(img.resize((w, h), Image.LANCZOS))


def cell_cafe(w, h, seed, word, stretch=2.46):
    """A café's big front window lit from inside, seen from the pavement: globe lamps hanging from the ceiling, the
    mirror and the bottles behind the bar, the counter with a man in a hat leaning on it, marble tables and bentwood
    chairs in front with two more men sitting, the café's word in gold on the transom. The cell is squeezed into a
    2:1 slot but stretched back over a window about 2.6 m wide and 3.2 m tall (`stretch`), so it is drawn at the
    window's own proportions and squeezed."""
    th = int(h * stretch)
    rgb = boca.interior(w, th, seed, dim=1.0)
    s = 2
    W, H = w * s, th * s
    img = Image.fromarray(to8(rgb)).resize((W, H))
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(seed)
    sil = (52, 28, 15)
    # (eye level is two thirds of the way down: the far things gather there, the near ones fill the bottom)
    # the mirror over the bar, a paler band, and the shelves of bottles in front of it
    d.rectangle([0, H * 0.36, W, H * 0.6], fill=(236, 196, 140))
    for shelf in (0.46, 0.555):
        d.rectangle([0, H * shelf, W, H * shelf + 4], fill=(96, 56, 30))
        x = 6.0
        while x < W - 6:
            bw = rng.uniform(5, 9)
            bh = rng.uniform(0.045, 0.07) * H
            c = [(70, 90, 40), (120, 50, 30), (150, 110, 60), (60, 40, 30)][int(rng.integers(0, 4))]
            d.rectangle([x, H * shelf - bh, x + bw, H * shelf], fill=c)
            d.rectangle([x + bw * 0.3, H * shelf - bh - 7, x + bw * 0.7, H * shelf - bh], fill=c)
            x += bw + rng.uniform(2, 7)
    # the counter, dark wood with a brass rail
    d.rectangle([0, H * 0.62, W, H * 0.76], fill=(78, 40, 20))
    d.rectangle([0, H * 0.62, W, H * 0.635], fill=(150, 104, 52))
    d.line([(0, H * 0.73), (W, H * 0.73)], fill=(200, 160, 80), width=3)
    # globe lamps on long stems
    for i in range(3):
        lx = W * (0.17 + 0.33 * i) + rng.uniform(-8, 8)
        ly = H * rng.uniform(0.2, 0.26)
        d.line([(lx, 0), (lx, ly)], fill=(40, 24, 14), width=3)
        d.ellipse([lx - 15, ly - 4, lx + 15, ly + 22], fill=(255, 240, 200))

    def man(x, top, height, hat=True, seated=False):
        hw = height * 0.055 * H / 1.0
        head = height * 0.085 * H
        d.ellipse([x - head * 0.42, top, x + head * 0.42, top + head], fill=sil)
        if hat:
            d.ellipse([x - head * 0.8, top + head * 0.12, x + head * 0.8, top + head * 0.32], fill=(30, 18, 10))
            d.rectangle([x - head * 0.45, top - head * 0.25, x + head * 0.45, top + head * 0.25], fill=(30, 18, 10))
        sh = top + head * 1.05
        body = height * (0.45 if seated else 0.85) * H
        d.polygon([(x - hw * 1.6, sh + head * 0.2), (x + hw * 1.6, sh + head * 0.2), (x + hw * 1.4, sh + body), (x - hw * 1.4, sh + body)], fill=sil)
        d.ellipse([x - hw * 1.7, sh - head * 0.05, x + hw * 1.7, sh + head * 0.6], fill=sil)

    # a man at the bar, further off and so smaller
    man(W * rng.uniform(0.55, 0.8), H * 0.47, 0.32)
    # marble tables, bentwood chairs and two men sitting, near the glass
    for i in range(2):
        x = W * (0.22 + 0.56 * i) + rng.uniform(-10, 10)
        if rng.uniform() < 0.8:
            man(x + (28 if i == 0 else -28), H * 0.69, 0.42, seated=True)
        d.ellipse([x - 52, H * 0.86, x + 52, H * 0.885], fill=(226, 214, 196))
        d.rectangle([x - 52, H * 0.872, x + 52, H * 0.885], fill=(120, 100, 80))
        d.rectangle([x - 4, H * 0.885, x + 4, H], fill=sil)
        for sx in (-70, 70):
            d.arc([x + sx - 18, H * 0.8, x + sx + 18, H * 0.9], 180, 360, fill=sil, width=5)
            d.line([(x + sx - 16, H * 0.85), (x + sx - 16, H)], fill=sil, width=5)
            d.line([(x + sx + 16, H * 0.85), (x + sx + 16, H)], fill=sil, width=5)
        # a cup on the table
        d.rectangle([x - 8, H * 0.845, x + 8, H * 0.865], fill=(250, 246, 236))
    # the frame: a transom bar near the top, the mullion below it
    d.rectangle([0, 0, W - 1, H - 1], outline=(30, 20, 14), width=10)
    d.rectangle([0, H * 0.17, W, H * 0.185], fill=(30, 20, 14))
    d.rectangle([W / 2 - 4, H * 0.18, W / 2 + 4, H], fill=(30, 20, 14))
    if word:
        f, size = fit_font(d, word, SERIF, int(H * 0.09), W * 0.5)
        tw = d.textlength(word, font=f)
        d.text(((W - tw) / 2 + 2, H * 0.035 + 2), word, font=f, fill=(90, 50, 20))
        d.text(((W - tw) / 2, H * 0.035), word, font=f, fill=(240, 200, 104))
    return rgbf(img.resize((w, h), Image.LANCZOS))


def cell_tiles_lit(w, h):
    """The Subte's lit passage seen down the stairs: white glazed tiles, a frieze band, warm light."""
    xx, yy = grid((h, w))
    tile = (np.mod(xx, 16) < 1.2) | (np.mod(yy, 8) < 1.0)
    rgb = np.where(tile[..., None], col('b8a890'), col('f4ecd8'))
    rgb = np.where((np.abs(yy - h * 0.35) < 5)[..., None], col('2e5a8a'), rgb)
    glow = 1.0 - 0.45 * smooth(np.abs(xx - w / 2) / (w / 2), 0.2, 1.0)
    return rgb * glow[..., None]


def cell_bench_iron(w, h):
    """A plaza bench's cast-iron end frame: legs curling into the arm, cut-out."""
    s = 2
    W, H = w * s, h * s
    img = Image.new('L', (W, H), 0)
    d = ImageDraw.Draw(img)
    d.line([(W * 0.1, H), (W * 0.2, H * 0.55), (W * 0.15, H * 0.1)], fill=255, width=14)
    d.line([(W * 0.9, H), (W * 0.75, H * 0.55)], fill=255, width=14)
    d.line([(W * 0.15, H * 0.55), (W * 0.85, H * 0.55)], fill=255, width=12)
    d.arc([W * 0.6, H * 0.15, W * 0.95, H * 0.6], 180, 360, fill=255, width=12)
    d.ellipse([W * 0.08, H * 0.04, W * 0.22, H * 0.18], outline=255, width=10)
    a = np.asarray(img.resize((w, h), Image.LANCZOS), np.float32) / 255.0
    return np.full((h, w, 3), 0.8, np.float32), a


def cell_crate(w, h, seed):
    """A soda crate's side: wooden slats painted, a stencilled number (the bottler is invented)."""
    xx, yy = grid((h, w))
    base = col('8a3a28') * (0.8 + 0.3 * fbm((h, w), 1.0, seed, ax=4.0, ay=0.3, lo=4))[..., None]
    slat = np.mod(yy, h / 3.0) < 2.0
    return np.where(slat[..., None], base * 0.4, base)


def cell_siphons(w, h):
    """Soda siphons standing in a crate, seen from the side: green and blue glass, the chrome heads."""
    s = 2
    W, H = w * s, h * s
    img = Image.new('RGB', (W, H), c8('3a2a20'))
    d = ImageDraw.Draw(img)
    for i in range(6):
        x = (i + 0.5) * W / 6
        c = c8(['3a7a6a', '4a6a9a', '3a7a6a', '5a8a7a', '4a6a9a', '3a7a6a'][i])
        d.rounded_rectangle([x - 16, H * 0.35, x + 16, H], radius=10, fill=c)
        d.rectangle([x - 6, H * 0.12, x + 8, H * 0.36], fill=c8('c8ccd0'))
        d.line([(x + 6, H * 0.2), (x + 20, H * 0.24)], fill=c8('c8ccd0'), width=5)
        d.line([(x - 8, H * 0.45), (x - 8, H * 0.95)], fill=(220, 240, 240), width=3)
    return rgbf(img.resize((w, h), Image.LANCZOS))


def tex_atlas():
    rgb = np.zeros((A_H, A_W, 3), np.float32)
    alpha = np.ones((A_H, A_W), np.float32)

    def put(name, cell, a=None):
        x, y, w, h = ATLAS[name]
        rgb[y:y + h, x:x + w] = cell[:h, :w]
        if a is not None:
            alpha[y:y + h, x:x + w] = a[:h, :w]

    for i in range(5):
        put('win_lit%d' % i, boca.cell_window(128, 256, 900 + i, True, i))
    for i in range(3):
        put('win_dark%d' % i, boca.cell_window(128, 256, 910 + i, False, i))
    put('arch_lit0', cell_arch_window(128, 256, 920, True))
    put('arch_lit1', cell_arch_window(128, 256, 921, True, '2a2a26'))
    put('arch_lit2', cell_arch_window(128, 256, 922, True, '3a2a1a', 0.8))
    put('arch_dark0', cell_arch_window(128, 256, 923, False))
    put('arch_dark1', cell_arch_window(128, 256, 924, False, '1e2620'))
    put('modern_lit', cell_modern(128, 256, 930, True))
    put('modern_dark', cell_modern(128, 256, 931, False))
    put('reja_lit', cell_reja(128, 256, 932, True))
    put('reja_dark', cell_reja(128, 256, 933, False))
    put('shutter', cell_shutter_closed(128, 256, 934))
    put('door_panel', cell_door_panel(128, 256, 940))
    put('door_gate_lit', cell_door_gate(128, 256, 941))
    put('door_cabildo', cell_door_cabildo(128, 256, 942))
    put('door_church', cell_door_church(128, 256, 943))
    put('door_bank_lit', cell_door_gate(128, 256, 944, True))
    put('door_shop_lit', boca.cell_door(128, 256, 945, 'shop'))
    c, a = cell_frond(256, 128, 950)
    put('frond0', c, a)
    c, a = cell_frond(256, 128, 951)
    put('frond1', c, a)
    c, a = cell_frond(256, 128, 952, dry=True)
    put('frond_dry', c, a)
    c, a = cell_bars(128, 128)
    put('bars', c, a)
    c, a = cell_twigs(256, 256)
    put('twigs', c, a)
    c, a = cell_papers(256, 128, 952)
    put('papers', c, a)
    c, a = cell_papers(256, 128, 953, True)
    put('magazines', c, a)
    c, a = cell_rail_ornate(256, 128)
    put('rail_ornate', c, a)
    c, a = cell_fence_hoop(256, 64)
    put('fence_hoop', c, a)
    c, a = boca.cell_balustrade(128, 64)
    put('balustrade', c, a)
    put('grille', cell_grille(128, 64, 954))
    put('car_glass', cell_glass(128, 64, 955))
    put('bus_win_lit', boca.interior(128, 64, 956, dim=0.95))
    put('tram_win_lit', boca.interior(128, 64, 957, dim=0.85))
    put('shop_strip_lit', boca.interior(128, 64, 958, curtain='f0e0c0'))
    # (the names are invented or only the trade: no real café, bar, hotel, company or line is meant)
    put('sign_subte', cell_enamel(512, 128, 'SUBTERRÁNEO · LÍNEA A · PLAZA DE MAYO'))
    put('sign_cafe', cell_gilded(512, 128, 'CAFÉ · BILLARES'))
    put('sign_confiteria', cell_gilded(512, 128, 'CONFITERÍA', '1a2a20', 'e8c870'))
    put('sign_bar', cell_gilded(512, 128, 'BAR AMERICANO', '2a1214', 'e0b860'))
    put('filete_side', *cell_filete(256, 128, 960, 'DE A POCO SE LLEGA LEJOS', squeeze=0.46))
    put('filete_rear', *cell_filete(256, 128, 961, 'ADIÓS, PIBA', rear=True))
    put('sign_soderia', boca.cell_sign(512, 128, 'SODERÍA · A DOMICILIO', 962, ground='1c2a3a', letter='f4e4b0', shade='8a2a1a'))
    put('bus_dest', cell_text(256, 64, 'PLAZA DE MAYO', '101010', 'f2ecd8', COND, False, 0.66))
    put('tram_dest', cell_text(256, 64, 'PLAZA DE MAYO', '141414', 'f0e8d0', COND, True, 0.62))
    put('tram_company', cell_text(256, 64, 'TRANVÍAS RIBERA', '2f4f3a', 'e8c870', SERIF, False, 0.5))
    put('kiosk_sign', cell_text(256, 64, 'DIARIOS · REVISTAS', '1f3a2c', 'f0ead8', COND, True, 0.6))
    put('clock', cell_clock(128, 128))
    put('taxi_sign', cell_text(128, 64, 'TAXI', 'f2ead0', 'a01c14', COND, True, 0.7))
    put('libre', cell_text(64, 64, 'LIBRE', 'b0201a', 'f4f0e8', COND, False, 0.4))
    put('plate', cell_text(64, 64, '·', '1a1a1a', 'e8e8e0', SANS, True, 0.3))
    put('sun_relief', cell_sun_relief(128, 128))
    put('laurel', cell_laurel(128, 128))
    put('cafe_lit', cell_cafe(256, 128, 970, 'CAFÉ'))
    put('shop_lit', cell_cafe(256, 128, 971, ''))
    c, a = boca.cell_awning(256, 128, 'e8e0c8', '8a3a2a')
    put('awning_cream', c, a)
    c, a = boca.cell_awning(256, 128, '2f6a44', 'e8e0c8')
    put('awning_green', c, a)
    put('relief', cell_relief(512, 128, 972))
    put('bus_num', cell_text(128, 64, '212', 'f2ecd8', '101010', COND, True, 0.8))
    put('tram_num', cell_text(128, 64, '214', '2f4f3a', 'e8c870', COND, False, 0.75))
    put('plaque', cell_text(128, 64, '', '4a3a22', '8a7040', SERIF, True, 0.5))
    put('headlamp', cell_lamp(64, 64))
    put('taillamp', cell_lamp(64, 64, True))
    put('hubcap', cell_hubcap(64, 64))
    put('spokes', cell_spokes(64, 64))
    put('oculus_lit', boca.cell_porthole(64, 64, True, 973))
    put('oculus_dark', boca.cell_porthole(64, 64, False, 974))
    put('dormer_lit', boca.cell_small_window(128, 128, 975, True, False))
    put('dormer_dark', boca.cell_small_window(128, 128, 976, False, False))
    xx, yy = grid((64, 64))
    r = np.sqrt((xx - 32) ** 2 + (yy - 32) ** 2) / 32.0
    put('glow', np.clip(mix(col('fff8ec'), col('ffe2b0'), smooth(r, 0.0, 1.0)[..., None]), 0, 1))
    put('white', np.full((64, 64, 3), 0.92, np.float32))
    put('dark', np.full((64, 64, 3), 0.06, np.float32))
    put('flag', cell_flag(256, 128))
    put('tiles_lit', cell_tiles_lit(128, 128))
    put('grille_truck', cell_grille(128, 64, 977))
    put('crate_side', cell_crate(128, 64, 978))
    put('siphons', cell_siphons(128, 64))
    put('cafe_glass', cell_cafe(256, 128, 979, ''))
    c, a = cell_bench_iron(256, 128)
    put('bench_iron', c, a)
    put('lamp_glass', np.clip(mix(col('fffaf0'), col('f0d8a8'), smooth(r, 0.0, 1.0)[..., None]), 0, 1))
    save_png('plaza_a', rgb, alpha)


LAYER_COUNT = len(LAYERS)
IMPORT_ARRAY = """[remap]

importer="2d_array_texture"
type="CompressedTexture2DArray"

[deps]

source_file="res://assets/tex/plaza/{name}.webp"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
slices/horizontal=1
slices/vertical={slices}
"""



def tex_powder():
    """Fresh powder for the square's ground (plaza_ground.gdshader): a tile 6 m across, seamless, of soft lumps and
    hollows (wavelengths of half a metre to three) with a fine grain over them. RGB: the normal; alpha: the height.
    The shader lays it twice, at two scales and turned against each other, so no repeat shows."""
    n = 512
    rng = np.random.default_rng(1958)
    fy = np.fft.fftfreq(n)[:, None] * n
    fx = np.fft.fftfreq(n)[None, :] * n
    f = np.sqrt(fx * fx + fy * fy)

    def band(lo, hi, seed, power=1.0):
        r = np.random.default_rng(seed).standard_normal((n, n))
        spec = np.fft.fft2(r)
        w = np.exp(-((np.log(np.maximum(f, 0.5)) - np.log(np.sqrt(lo * hi))) ** 2) / (2 * (np.log(hi / lo) / 2.0) ** 2))
        h = np.real(np.fft.ifft2(spec * w / np.maximum(f, 1.0) ** (power * 0.0)))
        return (h - h.mean()) / (h.std() + 1e-9)

    lumps = band(2.0, 10.0, 11) * 1.0 + band(8.0, 24.0, 12) * 0.35
    grain = band(120.0, 240.0, 13) * 0.06 + band(40.0, 100.0, 14) * 0.08
    h = lumps + grain
    h = (h - h.min()) / (h.max() - h.min())
    # the normal from the slope (metres: 512 px over 6 m; the lumps a few centimetres high)
    px = 6.0 / n
    depth = 0.05
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) / (2 * px) * depth
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) / (2 * px) * depth
    nz = 1.0 / np.sqrt(gx * gx + gy * gy + 1.0)
    nrm = np.stack([-gx * nz, gy * nz, nz], -1) * 0.5 + 0.5
    save_png('powder_n', np.clip(nrm, 0, 1), np.clip(h, 0, 1))


# --------------------------------------------------------------------------------------------------------------------
# The second atlas: the city's own small things (plaza_details.gd, and the colectivo's fileteado)
# --------------------------------------------------------------------------------------------------------------------
B_W, B_H = 1024, 640
ATLAS_B = {
    # enamel street plates, 256 x 64: the street names of the square and round it (factual)
    'st_rivadavia': (0, 0, 256, 64), 'st_yrigoyen': (256, 0, 256, 64), 'st_bolivar': (512, 0, 256, 64), 'st_balcarce': (768, 0, 256, 64),
    'st_defensa': (0, 64, 256, 64), 'st_reconquista': (256, 64, 256, 64), 'st_25mayo': (512, 64, 256, 64), 'st_avmayo': (768, 64, 256, 64),
    'st_diagnorte': (0, 128, 256, 64), 'st_diagsur': (256, 128, 256, 64), 'st_sanmartin': (512, 128, 256, 64), 'st_peru': (768, 128, 256, 64),
    # the evening papers on the kiosks, their names invented
    'paper0': (0, 192, 160, 208), 'paper1': (160, 192, 160, 208), 'paper2': (320, 192, 160, 208), 'paper3': (480, 192, 160, 208),
    # fileteado: a kiosk's fascia, a strip of ornament (cut-out), the colectivo's back (cut-out)
    'filete_fascia': (640, 192, 384, 96), 'filete_strip': (640, 288, 384, 48), 'subte_linea': (640, 336, 384, 64),
    'poster_tango': (0, 400, 128, 192), 'poster_cine': (128, 400, 128, 192), 'filete_bus_rear': (256, 400, 256, 128),
    'obras': (256, 528, 256, 64), 'disc_a': (512, 400, 128, 128), 'hoarding': (640, 400, 384, 192),
    'podium': (512, 528, 128, 64),
    # the cars' number plates, 128 x 40 (vehicles.gd PLATE_CELL; plaza_vehicle.gdshader picks one a car): invented
    # registrations, styled after the plates of the time, not a real number
    **{'plate%d' % i: (128 * i, 596, 128, 40) for i in range(8)},
}
PLATES = ['48·217', '31·905', '62·148', '7·336', '55·071', '19·482', '84·630', '26·759']


def cell_paper(w, h, seed, masthead, headline, sub):
    """An evening paper's front page as it hangs on a kiosk: newsprint going grey, the paper's name across the top in
    heavy serif capitals, the headline big under it, a photograph's grey block, columns of print too small to read."""
    s = 3
    W, H = w * s, h * s
    rng = np.random.default_rng(seed)
    img = Image.new('RGB', (W, H), c8('e4dcc8'))
    d = ImageDraw.Draw(img)
    f, size = fit_font(d, masthead, SERIF, int(H * 0.09), W * 0.9)
    tw = d.textlength(masthead, font=f)
    d.text(((W - tw) / 2, H * 0.03), masthead, font=f, fill=c8('141210'))
    y = H * 0.03 + size * 1.15
    d.line([(W * 0.04, y), (W * 0.96, y)], fill=c8('141210'), width=4)
    fs = ImageFont.truetype(SANS, int(H * 0.022))
    line = 'BUENOS AIRES · 1958 · QUINTA EDICIÓN'
    tw = d.textlength(line, font=fs)
    d.text(((W - tw) / 2, y + 6), line, font=fs, fill=c8('3a3630'))
    y += H * 0.045
    d.line([(W * 0.04, y), (W * 0.96, y)], fill=c8('141210'), width=2)
    words = headline.split(' ')
    rows = [' '.join(words[:len(words) // 2 + len(words) % 2]), ' '.join(words[len(words) // 2 + len(words) % 2:])]
    for r in rows:
        if not r: continue
        fh, hs = fit_font(d, r, COND, int(H * 0.11), W * 0.92)
        tw = d.textlength(r, font=fh)
        d.text(((W - tw) / 2, y + H * 0.01), r, font=fh, fill=c8('101010'))
        y += hs * 1.02
    fsub, ss = fit_font(d, sub, SERIF, int(H * 0.04), W * 0.9)
    tw = d.textlength(sub, font=fsub)
    d.text(((W - tw) / 2, y + H * 0.01), sub, font=fsub, fill=c8('2a2622'))
    y += ss * 1.6
    # the photograph and the columns
    px0, px1 = W * 0.06, W * (0.5 + rng.uniform(0.0, 0.2))
    d.rectangle([px0, y, px1, y + H * 0.2], fill=c8('7a766e'))
    d.rectangle([px0 + W * 0.05, y + H * 0.08, px0 + W * 0.2, y + H * 0.2], fill=c8('4a4640'))
    cols = 3
    cw = (W * 0.9) / cols
    for c in range(cols):
        cx0 = W * 0.05 + c * cw
        yy = y + (H * 0.22 if cx0 < px1 else 0.0)
        while yy < H * 0.96:
            d.line([(cx0 + 4, yy), (cx0 + cw - 8 - rng.uniform(0, cw * 0.3), yy)], fill=c8('8a857c'), width=3)
            yy += 9
    rgb = rgbf(img.resize((w, h), Image.LANCZOS))
    yy, xx = np.mgrid[0:h, 0:w]
    age = 0.92 + 0.08 * fbm((h, w), 1.2, seed)
    return np.clip(rgb * age[..., None], 0, 1)


def cell_filete_fascia(w, h, words, ground='1d3a27'):
    """A kiosk's fascia, painted by a fileteador: a deep green ground, a gold line round it, a flourish at each end and
    the words in cream capitals shaded in red, the flag's ribbon under them."""
    s = 3
    W, H = w * s, h * s
    img = Image.new('RGB', (W, H), c8(ground))
    d = ImageDraw.Draw(img)
    gold, cream = c8('e8b830'), c8('f4ead0')
    orn = [c8(o) for o in ('d8402e', '3a9a58', 'e8b830', '3a7ac0')]
    d.rounded_rectangle([8, 8, W - 9, H - 9], radius=20, outline=gold, width=6)
    d.rounded_rectangle([22, 22, W - 23, H - 23], radius=12, outline=cream, width=2)
    r = H * 0.2
    filete_flourish(d, W * 0.035 + r * 1.1, H * 0.6, r, 1.0, gold, cream, orn)
    filete_flourish(d, W * 0.965 - r * 1.1, H * 0.6, r, -1.0, gold, cream, orn)
    f, size = fit_font(d, words, SERIF, int(H * 0.46), W - 2 * (W * 0.035 + r * 3.3))
    tw = d.textlength(words, font=f)
    tx, ty = (W - tw) / 2, H * 0.5 - size * 0.66
    for o in range(1, 6):
        d.text((tx + o, ty + o), words, font=f, fill=c8('b02a1e'))
    d.text((tx, ty), words, font=f, fill=cream)
    ry = ty + size * 1.12
    for k, c in enumerate(('74acdf', 'f4f4f0', '74acdf')):
        d.rectangle([W / 2 - tw / 2, ry + k * 7, W / 2 + tw / 2, ry + k * 7 + 7], fill=c8(c))
    return rgbf(img.resize((w, h), Image.LANCZOS))


def cell_filete_strip(w, h):
    """A band of ornament to run along a kiosk's eaves or a bus's trim (cut-out): a gold pinstripe either side, small
    scrolls in turn facing left and right between, dots in the flag's blue."""
    s = 4
    W, H = w * s, h * s
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    gold, cream = (232, 184, 48, 255), (244, 234, 208, 255)
    orn = [(216, 64, 46, 255), (58, 154, 88, 255), (232, 184, 48, 255), (58, 122, 192, 255)]
    d.line([(0, H * 0.1), (W, H * 0.1)], fill=gold, width=5)
    d.line([(0, H * 0.9), (W, H * 0.9)], fill=gold, width=5)
    n = 6
    for i in range(n):
        cx = (i + 0.5) * W / n
        fl = 1.0 if i % 2 == 0 else -1.0
        boca.scroll(d, cx - fl * H * 0.18, H * 0.5, H * 0.28, 1.4, gold, 7, fl, 1.2)
        boca.leaf(d, cx + fl * H * 0.12, H * 0.5, 0.0 if fl > 0 else np.pi, H * 0.5, orn[i % 2], cream)
        d.ellipse([cx + fl * W / n * 0.42 - 7, H * 0.5 - 7, cx + fl * W / n * 0.42 + 7, H * 0.5 + 7], fill=(116, 172, 223, 255))
    small = img.resize((w, h), Image.LANCZOS)
    arr = np.asarray(small, np.float32) / 255.0
    a = np.clip(arr[..., 3] * 1.4, 0, 1)
    rgb = arr[..., :3] / np.maximum(arr[..., 3:4], 1e-3)
    rgb = np.where(arr[..., 3:4] > 0.02, np.clip(rgb, 0, 1), np.array([0.9, 0.72, 0.2], np.float32))
    return rgb, a


def cell_poster(w, h, seed, top, big, lines, ground='e8dcc0', ink='1a1410', accent='b0282a'):
    """A paper poster on a hoarding (invented): a band of colour, a big word, smaller lines; torn at a corner, faded."""
    s = 3
    W, H = w * s, h * s
    img = Image.new('RGB', (W, H), c8(ground))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, H * 0.16], fill=c8(accent))
    f, size = fit_font(d, top, COND, int(H * 0.1), W * 0.9)
    tw = d.textlength(top, font=f)
    d.text(((W - tw) / 2, H * 0.02), top, font=f, fill=c8(ground))
    fb, bs = fit_font(d, big, SERIF, int(H * 0.2), W * 0.9)
    tw = d.textlength(big, font=fb)
    d.text(((W - tw) / 2, H * 0.24), big, font=fb, fill=c8(ink))
    y = H * 0.24 + bs * 1.3
    for ln in lines:
        fl, ls = fit_font(d, ln, COND, int(H * 0.07), W * 0.86)
        tw = d.textlength(ln, font=fl)
        d.text(((W - tw) / 2, y), ln, font=fl, fill=c8(accent if ln == lines[0] else ink))
        y += ls * 1.25
    rgb = rgbf(img.resize((w, h), Image.LANCZOS))
    yy, xx = np.mgrid[0:h, 0:w]
    torn = (xx > w * 0.7) & (yy > h * 0.82) & ((xx - w * 0.7) + (yy - h * 0.82) * 1.4 > w * 0.12 + 6 * fbm((h, w), 3.0, seed))
    rgb = np.where(torn[..., None], col('2c4632'), rgb)
    return np.clip(rgb * (0.85 + 0.12 * fbm((h, w), 1.3, seed + 1))[..., None], 0, 1)


def cell_hoarding(w, h, seed):
    """The boards of a works hoarding: planks painted dark green, weathered, a stencil along them (SE PROHÍBE FIJAR
    CARTELES), two posters pasted on regardless."""
    xx, yy = grid((h, w))
    plank = np.floor(xx / (w / 14.0))
    tone = 0.85 + 0.15 * cell_rand(plank, plank * 0, seed, 1, 6)
    rgb = col('2e4a36') * tone[..., None] * (0.8 + 0.2 * fbm((h, w), 2.2, seed))[..., None]
    gap = (np.mod(xx, w / 14.0) < 1.2)
    rgb = np.where(gap[..., None], col('141a16'), rgb)
    img = Image.fromarray(to8(rgb)).resize((w * 2, h * 2))
    d = ImageDraw.Draw(img)
    W, H = w * 2, h * 2
    words = 'SE PROHÍBE FIJAR CARTELES'
    f, size = fit_font(d, words, COND, int(H * 0.09), W * 0.7)
    tw = d.textlength(words, font=f)
    d.text(((W - tw) / 2, H * 0.82), words, font=f, fill=c8('d8d2bc'))
    out = rgbf(img.resize((w, h), Image.LANCZOS))
    p1 = cell_poster(int(w * 0.3), int(h * 0.62), seed + 3, 'GRAN BAILE', 'TANGO', ['SÁBADO A LAS 22', 'ORQUESTA TÍPICA', 'LOS DEL SUD'])
    out[int(h * 0.08):int(h * 0.08) + p1.shape[0], int(w * 0.12):int(w * 0.12) + p1.shape[1]] = p1
    p2 = cell_poster(int(w * 0.26), int(h * 0.55), seed + 4, 'CINE', 'ESTRENO', ['AMOR EN LA RIBERA', 'FUNCIÓN CONTINUADA'], ground='f0e6c8', accent='1f4a7a')
    out[int(h * 0.14):int(h * 0.14) + p2.shape[0], int(w * 0.6):int(w * 0.6) + p2.shape[1]] = p2
    return out


def cell_disc(w, h, letter):
    """The subte's round enamel plate: the line's letter, white on a deep blue ground in a white ring (cut-out round)."""
    s = 4
    W, H = w * s, h * s
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([4, 4, W - 5, H - 5], fill=c8('1c2e5c') + (255,), outline=c8('f2f0e8') + (255,), width=int(W * 0.06))
    d.ellipse([W * 0.13, H * 0.13, W * 0.87, H * 0.87], outline=c8('f2f0e8') + (255,), width=int(W * 0.015))
    f = ImageFont.truetype(COND, int(H * 0.62))
    tw = d.textlength(letter, font=f)
    d.text(((W - tw) / 2, H * 0.5 - H * 0.42), letter, font=f, fill=c8('f2f0e8') + (255,))
    small = img.resize((w, h), Image.LANCZOS)
    arr = np.asarray(small, np.float32) / 255.0
    rgb = arr[..., :3] / np.maximum(arr[..., 3:4], 1e-3)
    return np.clip(rgb, 0, 1), np.clip(arr[..., 3] * 1.3, 0, 1)


def cell_plate(w, h, number):
    """A number plate in the manner of the time: black enamel, a thin cream rim, the district's word small across the
    top, the number big under it in cream (the numbers are invented)."""
    s = 4
    W, H = w * s, h * s
    img = Image.new('RGB', (W, H), c8('d9d0b4'))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([int(W * .025), int(H * .07), int(W * .975), int(H * .93)], radius=int(H * .1), fill=c8('121214'))
    d.rounded_rectangle([int(W * .05), int(H * .15), int(W * .95), int(H * .85)], radius=int(H * .07), outline=c8('d9d0b4'), width=max(2, int(H * .03)))
    fs = ImageFont.truetype(COND, int(H * 0.17))
    tw = d.textlength('CAPITAL', font=fs)
    d.text(((W - tw) / 2, H * 0.16), 'CAPITAL', font=fs, fill=c8('d9d0b4'))
    f, size = fit_font(d, number, COND, int(H * 0.52), W * 0.84)
    tw = d.textlength(number, font=f)
    d.text(((W - tw) / 2, H * 0.30), number, font=f, fill=c8('ece4c8'))
    small = img.resize((w, h), Image.LANCZOS)
    return np.asarray(small, np.float32) / 255.0


def cell_podium(w, h):
    """The traffic policeman's podium's drum: white, a black band round it, the city's stripes."""
    xx, yy = grid((h, w))
    rgb = np.where(((yy / h > 0.42) & (yy / h < 0.6))[..., None], col('141414'), col('ece8dc'))
    stripe = (np.mod(xx / w * 8.0, 1.0) < 0.5) & (yy / h < 0.2)
    return np.where(stripe[..., None], col('b0282a'), rgb)


def tex_atlas_b():
    rgb = np.zeros((B_H, B_W, 3), np.float32)
    alpha = np.ones((B_H, B_W), np.float32)

    def put(name, cell, a=None):
        x, y, w, h = ATLAS_B[name]
        rgb[y:y + h, x:x + w] = cell[:h, :w]
        if a is not None:
            alpha[y:y + h, x:x + w] = a[:h, :w]
    streets = {'st_rivadavia': 'RIVADAVIA', 'st_yrigoyen': 'HIPÓLITO YRIGOYEN', 'st_bolivar': 'BOLÍVAR', 'st_balcarce': 'BALCARCE',
               'st_defensa': 'DEFENSA', 'st_reconquista': 'RECONQUISTA', 'st_25mayo': '25 DE MAYO', 'st_avmayo': 'AVENIDA DE MAYO',
               'st_diagnorte': 'DIAGONAL NORTE', 'st_diagsur': 'DIAGONAL SUR', 'st_sanmartin': 'SAN MARTÍN', 'st_peru': 'PERÚ'}
    for key, name in streets.items():
        put(key, cell_enamel(256, 64, name, ground='1c2e5c', size_frac=0.56, spacing=0.05))
    put('paper0', cell_paper(160, 208, 801, 'EL ECO DE MAYO', 'OLA DE FRÍO SOBRE LA CIUDAD', 'Se esperan temperaturas bajo cero'))
    put('paper1', cell_paper(160, 208, 802, 'LA VOZ DEL SUD', '¿NEVARÁ ESTA NOCHE?', 'El Servicio Meteorológico no lo descarta'))
    put('paper2', cell_paper(160, 208, 803, 'DIARIO DE LA RIBERA', 'EL FRÍO MÁS INTENSO DEL SIGLO', 'Braseros encendidos en el puerto'))
    put('paper3', cell_paper(160, 208, 804, 'LA TARDE PORTEÑA', 'CIELO PLOMIZO Y VIENTO DEL SUR', 'Suspendidos los partidos del domingo'))
    put('filete_fascia', cell_filete_fascia(384, 96, 'DIARIOS Y REVISTAS'))
    put('filete_strip', *cell_filete_strip(384, 48))
    put('subte_linea', cell_enamel(384, 64, 'LÍNEA A · A PRIMERA JUNTA', ground='1c2e5c', size_frac=0.56, spacing=0.05))
    put('poster_tango', cell_poster(128, 192, 811, 'GRAN BAILE', 'TANGO', ['SÁBADO A LAS 22', 'ORQUESTA TÍPICA', 'LOS DEL SUD']))
    put('poster_cine', cell_poster(128, 192, 812, 'CINE', 'ESTRENO', ['AMOR EN LA RIBERA', 'FUNCIÓN CONTINUADA'], ground='f0e6c8', accent='1f4a7a'))
    put('filete_bus_rear', *cell_filete(256, 128, 813, 'SIN APURO PERO SIN PAUSA', rear=True))
    put('obras', cell_enamel(256, 64, 'PELIGRO · OBRAS', ground='a82820', size_frac=0.56, spacing=0.06))
    put('disc_a', *cell_disc(128, 128, 'A'))
    put('hoarding', cell_hoarding(384, 192, 820))
    put('podium', cell_podium(128, 64))
    for i, number in enumerate(PLATES):
        put('plate%d' % i, cell_plate(128, 40, number))
    save_png('plaza_b', rgb, alpha)

def fix_imports():
    """Mipmaps on, lossless, no automatic re-compression; the wall layers as an array. Run after `godot --import` has
    written the .import files, then import again."""
    import glob
    import re
    for path in sorted(glob.glob(os.path.join(OUT, '*.png.import'))):
        name = os.path.basename(path)[:-len('.png.import')]
        text = open(path).read()
        new = re.sub(r"mipmaps/generate=\w+", "mipmaps/generate=true", text)
        new = re.sub(r"compress/normal_map=\d", "compress/normal_map=2", new)
        new = re.sub(r"compress/mode=\d", "compress/mode=0", new)
        new = re.sub(r"detect_3d/compress_to=\d", "detect_3d/compress_to=0", new)
        if new != text:
            open(path, 'w').write(new)
            print('patched', name)
    for name in ('pwalls_a', 'pwalls_n'):
        path = os.path.join(OUT, name + '.webp.import')
        text = open(path).read() if os.path.exists(path) else ''
        if 'importer="2d_array_texture"' not in text or 'slices/vertical=%d' % LAYER_COUNT not in text:
            new = IMPORT_ARRAY.format(name=name, slices=LAYER_COUNT)
            # (keeping the texture's uid, so that nothing that refers to it by uid loses it)
            m = re.search(r'uid="uid://\w+"', text)
            if m:
                new = new.replace('type="CompressedTexture2DArray"\n', 'type="CompressedTexture2DArray"\n%s\n' % m.group(0), 1)
            open(path, 'w').write(new)
            print('array import', name)


if __name__ == '__main__':
    if sys.argv[1:] == ['--fix-imports']:
        fix_imports()
        sys.exit(0)
    os.makedirs(OUT, exist_ok=True)
    if sys.argv[1:] in ([], ['atlas']):
        tex_atlas()
    if sys.argv[1:] in ([], ['walls']):
        tex_walls_array()
    if sys.argv[1:] in ([], ['powder']):
        tex_powder()
    if sys.argv[1:] in ([], ['atlas_b']):
        tex_atlas_b()
    if sys.argv[1:] in ([], ['grime']):
        tex_grime()
    fix_imports()
