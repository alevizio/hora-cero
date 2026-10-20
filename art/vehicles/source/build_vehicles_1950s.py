"""The cars of a Buenos Aires street on a winter night in 1958, for Hora Cero.

Built on the friends' Retro Vehicle Pack generator (build_vehicles.py, next to this file, unchanged): its Model, its
materials, its conventions (metres; internally X forward, Y left, Z up; exported Y up, -Z forward; the wheels as their
own nodes pivoting on their axles; the body in the materials named Paint and Paint_dark, so a game can recolour it).
Where the pack's cars are slab-sided cars of 1969-92, these are rounded generic shapes of the 1940s and 50s: no maker's
badge, name, emblem or any grille of a real model.

  11_sedan_49     a big rounded sedan of the late forties: a narrow bonnet between separate wings (the lamps in their
                  noses), the rear wings bulging pods with skirts, a split windscreen, heavy bumpers with guards,
                  whitewall tyres
  12_taxi_49      the same as a Buenos Aires taxi: black, the roof yellow, a small lamp on it, no skirts
  13_saloon_53    a smaller rounded European saloon of the early fifties, the wings in its body, a sloping back
  14_pickup_51    a pickup with separate wings, running boards and a step-side bed
  15_van_51       a delivery van with the same front and separate wings, its body a tall rounded box
  16_coupe_48     a fastback two-door coupé on the big sedan's front
Each has the small things of a real car of the time: chrome round its windows and along its sides, a grille of bars
and (on the big ones) upright teeth, bumpers with overriders, round headlamps with their reflectors and lenses, small
round tail lamps, door handles and the doors' gaps, the bonnet's seams and the boot's lid, a plain chrome mascot (no
maker's emblem), wipers, a mirror, an aerial on the sedan and the coupé, running boards, whitewall or blackwall tyres
with a tread, hubcaps, dark wheel wells, number plates (the game gives them their registrations), a taxi's meter flag;
and, in the node Interior, the cabin's inside to be seen through the glass: the headlining, the dashboard painted the
car's colour with its dial, an ivory steering wheel on the left (Argentina has driven on the right since 1945), the
benches. The smallest of those things are in the node Fine_Details: the game's far copies leave them out, with the
inside.
The pack's own generator (python3 build_vehicles.py) writes its eight cars to the same folder; Hora Cero uses only its
07_microcar and 08_work_pickup.

Python 3 and NumPy; run from anywhere: python3 art/vehicles/source/build_vehicles_1950s.py
Writes art/vehicles/models/<id>.glb and art/vehicles/models/manifest_1950s.json.
"""
from pathlib import Path
import json, math, sys
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_vehicles import Model, vec  # noqa: E402  (the friends' generator)

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / 'models'
MODELS.mkdir(parents=True, exist_ok=True)


# ---------------------------------------------------------------------------------------------------------------
# Small tools

def smooth(keys, x):
    """A smooth curve through (x, value) keys (Catmull-Rom between them, flat beyond the ends)."""
    ks = sorted(keys)
    xs = [k[0] for k in ks]; vs = [k[1] for k in ks]
    if x <= xs[0]: return vs[0]
    if x >= xs[-1]: return vs[-1]
    i = max(j for j in range(len(xs) - 1) if xs[j] <= x)
    x0, x1 = xs[i], xs[i + 1]; v0, v1 = vs[i], vs[i + 1]
    t = (x - x0) / (x1 - x0)
    def slope(j):
        a = max(j - 1, 0); b = min(j + 1, len(xs) - 1)
        return (vs[b] - vs[a]) / (xs[b] - xs[a])
    m0 = slope(i) * (x1 - x0); m1 = slope(i + 1) * (x1 - x0)
    t2 = t * t; t3 = t2 * t
    return (2 * t3 - 3 * t2 + 1) * v0 + (t3 - 2 * t2 + t) * m0 + (-2 * t3 + 3 * t2) * v1 + (t3 - t2) * m1


def loft(m, rings, node, mat, centres, closed=True):
    """Quads between successive rings (each a list of points, all the same length). `mat` a material name or a
    function (band, segment) -> name or None (left open); `centres` a point inside each ring (for the outward side)."""
    n = len(rings[0])
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        c = (vec(centres[i]) + vec(centres[i + 1])) / 2
        for j in range(n if closed else n - 1):
            k = (j + 1) % n
            q = [a[j], a[k], b[k], b[j]]
            name = mat(i, j) if callable(mat) else mat
            if name is None: continue
            m.polygon(q, name, node, np.mean(np.array(q, dtype=float), axis=0) - c)


def fan(m, pts, mat, node, normal, lift=0.0):
    """A closed ring filled from its middle (lifted along `normal` by `lift`): an even fan, so that the smooth
    shading across it shows no streaks."""
    pts = [vec(p) for p in pts]
    c = np.mean(np.array(pts), axis=0) + unit_(normal) * lift
    for a, b in zip(pts, pts[1:] + pts[:1]):
        m.polygon([c, a, b], mat, node, normal)


def lathe_x(m, node, x, y, z, profile, mat, n=12, facing=1):
    """A round thing facing along x (a lamp, a lens, a hubcap seen from the front): `profile` [(radius, depth)] from
    its rim to its middle, depth along `facing`."""
    rings = []
    for rad, d in profile:
        rings.append([(x + facing * d, y + rad * math.cos(t), z + rad * math.sin(t)) for t in np.arange(n) * 2 * math.pi / n])
    centres = [(x - facing * .2, y, z)] * len(rings)
    loft(m, rings, node, mat, centres)
    last = profile[-1]
    if last[0] > 1e-4:
        m.polygon(rings[-1], mat, node, [facing, 0, 0])


def bumper(m, node, x, z, half, wrap, sign, mat='Chrome', rad=.07, guards=True):
    """A chrome bar across the car's end, its ends wrapping back round the corners; two upright guards on it."""
    ys = np.linspace(-half, half, 9)
    pts = [(x - sign * wrap * (abs(y) / half) ** 3, y, z) for y in ys]
    for a, b in zip(pts[:-1], pts[1:]): m.rod(a, b, rad, mat, node, 8)
    if guards:
        for yy in (-half * .42, half * .42):
            m.rod((x + sign * .045, yy, z - .12), (x + sign * .055, yy, z + .13), .042, mat, node, 8, r2=.028)


def headlamp(m, node, x, y, z, rad=.105, facing=1):
    """A round headlamp: its chrome rim, the silvered reflector's bowl inside it, the domed lens with the rings of its
    prisms."""
    lathe_x(m, node, x, y, z, [(rad + .028, 0.0), (rad + .028, .035), (rad + .005, .045)], 'Chrome', 14, facing)
    lathe_x(m, node, x + facing * .03, y, z, [(rad, 0.0), (rad * .5, -.03), (rad * .12, -.04)], 'Reflector', 12, facing)
    lathe_x(m, node, x + facing * .045, y, z, [(rad, 0.0), (rad * .7, .02), (rad * .25, .028)], 'Headlamp', 14, facing)
    for f in (.45, .78):
        pts = [(x + facing * (.047 + .022 * (1 - f * f)), y + rad * f * math.cos(t), z + rad * f * math.sin(t)) for t in np.linspace(0, 2 * math.pi, 15)]
        m.line(pts, .0035, 'Trim', node)


def tail_lamp(m, node, x, y, z, rad=.055, facing=-1):
    lathe_x(m, node, x, y, z, [(rad + .018, 0.0), (rad + .018, .02)], 'Chrome', 10, facing)
    lathe_x(m, node, x + facing * .02, y, z, [(rad, 0.0), (rad * .6, .018), (rad * .2, .022)], 'Tail_light', 10, facing)


def wheel(m, name, cx, cy, r, tw, side, whitewall, full_cap):
    """A wheel on its own node (pivot on the axle, spinning about Y): the tyre's tread and shoulders, its outer wall
    (a white band on it when `whitewall`), the hubcap's dome (chrome all over, or a painted disc and a small chrome cap)."""
    nd = m.node(name, pivot=(cx, cy, r))
    c = vec([cx, cy, r]); N = 20
    ang = np.arange(N) * 2 * math.pi / N
    # the tread: blocks across it (the middle rings stepping in and out round the tyre) and a groove down its middle
    prof = [(-tw / 2, r * .80), (-tw / 2 * .92, r * .95), (-tw * .3, r), (-tw * .06, r * .986), (tw * .06, r * .986), (tw * .3, r), (tw / 2 * .92, r * .95), (tw / 2, r * .80)]
    def tread(i, j, rad):
        return rad * (.982 if (i in (2, 5) and j % 2 == (0 if i == 2 else 1)) else 1.0)
    rings = [[c + vec([tread(i, j, rad) * math.sin(t), off, tread(i, j, rad) * math.cos(t)]) for j, t in enumerate(ang)] for i, (off, rad) in enumerate(prof)]
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        for j in range(N):
            k = (j + 1) % N
            q = [a[j], a[k], b[k], b[j]]
            nrm = np.mean(np.array(q), axis=0) - c; nrm[1] = 0
            m.polygon(q, 'Rubber', nd, nrm)
    yo = cy + side * tw / 2
    def ring(rad, dy=0.0): return [vec([cx + rad * math.sin(t), yo + side * dy, r + rad * math.cos(t)]) for t in ang]
    bands = [(.80, .68, 'Whitewall' if whitewall else 'Rubber'), (.68, .60, 'Rubber')]
    for r0, r1, mat in bands:
        a, b = ring(r * r0), ring(r * r1)
        for j in range(N):
            k = (j + 1) % N
            m.polygon([a[j], a[k], b[k], b[j]], mat, nd, [0, side, 0])
    dome = [(.60, 0.0), (.54, .022), (.40, .045), (.20, .058)]
    for i in range(len(dome) - 1):
        a = ring(r * dome[i][0], dome[i][1]); b = ring(r * dome[i + 1][0], dome[i + 1][1])
        mat = 'Chrome' if (full_cap or i >= 2) else 'Paint_dark'
        for j in range(N):
            k = (j + 1) % N
            q = [a[j], a[k], b[k], b[j]]
            m.polygon(q, mat, nd, np.mean(np.array(q), axis=0) - (c - vec([0, side * .2, 0])))
    m.polygon(ring(r * dome[-1][0], dome[-1][1]), 'Chrome', nd, [0, side, 0])
    # a plain ring stamped in the hubcap and its centre boss (no maker's emblem)
    m.line(ring(r * .3, .052) + [ring(r * .3, .052)[0]], .006, 'Trim', nd)
    lathe_x_y(m, nd, cx, yo + side * .058, r, [(r * .1, 0.0), (r * .06, .015), (0.0, .018)], 'Chrome', 10, side)
    return nd


def lathe_x_y(m, node, x, y, z, profile, mat, n=10, facing=1):
    """A round thing facing along y (a hubcap's boss): `profile` [(radius, depth)] from its rim in, depth along `facing`."""
    rings = [[(x + rad * math.cos(t), y + facing * d, z + rad * math.sin(t)) for t in np.arange(n) * 2 * math.pi / n] for rad, d in profile]
    loft(m, rings, node, mat, [(x, y - facing * .2, z)] * len(rings))


# ---------------------------------------------------------------------------------------------------------------
# The body: a hull lofted along the car, and the cabin's glasshouse lofted up from its belt

def hull_ring(x, w, zb, zs, zh, tuck=.10):
    """A section of the body at x: half width w, its bottom zb, its shoulder zs (the wings' crowns, or the top's
    edge), its middle zh (the bonnet, the deck, the boot: lower than the shoulders between crowned wings, higher on a
    crowned top); the sides bellied, widest halfway up, tucked under below."""
    yk = .84 * w
    h = zs - zb
    half = [(0.0, zb + .02), (.70 * w, zb), (.90 * w, zb + min(tuck, h * .25)), (w, zb + .48 * h), (.985 * w, zb + .78 * h),
            (.93 * w, zb + .94 * h), (yk, zs)]
    for f in (.72, .46, .22):
        half.append((yk * f, zh + (zs - zh) * f ** 2.0))
    half.append((0.0, zh))
    return [(x, y, z) for y, z in half] + [(x, -y, z) for y, z in half[-2:0:-1]]


def hull(m, node, xs, w_of, zb_of, zs_of, zh_of, wells=()):
    """The body lofted through its sections. (Each quad faces out across its own edge of the section, which runs
    round counter-clockwise seen from the front: a top dished between crowned wings faces up, not in.) Under the
    arches cut in it (`wells`: [(axle, arch)]) its underside is the wheel's dark well."""
    rings = [hull_ring(x, w_of(x), zb_of(x), zs_of(x), zh_of(x)) for x in xs]
    n = len(rings[0])
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        xm = (xs[i] + xs[i + 1]) / 2
        well = any(abs(xm - ax) < ar for ax, ar in wells)
        for j in range(n):
            k = (j + 1) % n
            d = (vec(a[k]) - vec(a[j])) + (vec(b[k]) - vec(b[j]))
            under = well and (j < 2 or j >= n - 2)
            m.polygon([a[j], a[k], b[k], b[j]], 'Wheel_well' if under else 'Paint', node, [0.0, d[2], -d[1]])
    fan(m, rings[0], 'Paint', node, [-1, 0, 0])
    fan(m, rings[-1], 'Paint', node, [1, 0, 0])


def glasshouse(m, node, g, roof_mat='Paint', inside=None):
    """The cabin over the belt: rings of a rounded oblong rising from the belt to the roof, narrowing and drawing in
    (the windscreen raked, the back window sloping), its corners round, the roof crowned; the glass where the windows
    are, the pillars and the roof in paint. g: belt, top; the windscreen's foot and head (ab, at); the back window's
    head and foot (rt, rb); the half widths at the belt and the roof (w0, w1); corner radii (rf, rr); along the side,
    where its windows and pillars end, front to back, each ('f', distance behind the windscreen's corner), ('x', x) or
    ('r', distance ahead of the back's corner) with what lies before it ('side' glass or 'pillar'); whether the
    windscreen wraps round its corners; its vee (its middle forward of its sides); which bands of the back are glass."""
    belt, top = g['belt'], g['top']
    # (t up the cabin, how far drawn in to round the roof's edge and crown it: along, across)
    levels = [(0.0, 0, 0), (.06, 0, 0), (.55, 0, 0), (.86, 0, 0), (.93, .04, .05), (.98, .11, .13), (1.01, .22, .25),
              (1.04, .45, .50)]
    rings = []; centres = []; tags = None
    for t, fx, fy in levels:
        tt = min(t, 1.0)
        z = belt + (top - .04 - belt) * t
        xf = g['ab'] + (g['at'] - g['ab']) * tt ** .9
        xr = g['rb'] + (g['rt'] - g['rb']) * tt ** .9
        xc = (xf + xr) / 2
        xf = xc + (xf - xc) * (1 - fx); xr = xc + (xr - xc) * (1 - fx)
        hw = (g['w0'] + (g['w1'] - g['w0']) * tt) * (1 - fy)
        rf = min(g['rf'], hw * .6, (xf - xr) * .3); rr = min(g['rr'], hw * .6, (xf - xr) * .3)
        pts = []; zone = []   # each point, and what lies on the way to it
        straight = hw - rf
        for y in (.02, straight * .5, straight):
            pts.append((xf + g['vee'] * (1 - y / max(straight, 1e-3)), y)); zone.append('ws')
        for k in (1, 2, 3):
            a = math.pi / 2 * k / 3
            pts.append((xf - rf + rf * math.cos(a), hw - rf + rf * math.sin(a))); zone.append('wrap' if g['wrap'] else 'pillar')
        lo, hi = xr + rr + .02, xf - rf - .02
        for ref, d, what in g['breaks']:
            x = xf - rf - d if ref == 'f' else xr + rr + d if ref == 'r' else d
            pts.append((min(max(x, lo), hi), hw)); zone.append(what)
        pts.append((xr + rr, hw)); zone.append('pillar')
        for k in (1, 2, 3):
            a = math.pi / 2 + math.pi / 2 * k / 3
            pts.append((xr + rr + rr * math.cos(a), hw - rr + rr * math.sin(a))); zone.append('pillar')
        pts.append((xr, (hw - rr) * .5)); zone.append('back')
        pts.append((xr, 0.0)); zone.append('back')
        n = len(pts)
        # the right side, the left's mirror, back to the front; the windscreen's divider closes the ring
        ring = pts + [(x, -y) for x, y in reversed(pts[:-1])]
        seg = zone[1:] + [zone[n - 1]] + [zone[n - 2 - i] for i in range(n - 2)] + ['div']
        if tags is None: tags = seg
        rings.append([(x, y, z) for x, y in ring])
        centres.append((xc, 0, z))
    glass = {'ws', 'wrap', 'side'}
    back_bands = g.get('back_bands', (1, 2))
    def mat(i, j):
        zone = tags[j]
        if i == 0: return 'Paint'
        if i in (1, 2):
            if zone in glass or (zone == 'back' and i in back_bands): return 'Glass'
            if zone == 'div': return 'Chrome'
            return 'Paint'
        return roof_mat
    loft(m, rings, node, mat, centres)
    fan(m, rings[-1], roof_mat, node, [0, 0, 1], .012)
    if inside is not None:
        # the inside, seen through the glass: the pillars and the roof again facing in (the headlining), and the
        # cabin's floor at the belt (the doors' caps, the parcel shelf: the seats stand on it)
        for i in range(len(rings) - 1):
            a, b = rings[i], rings[i + 1]
            c = vec(centres[i]) / 2 + vec(centres[i + 1]) / 2
            for j in range(len(a)):
                if mat(i, j) == 'Glass': continue
                k = (j + 1) % len(a)
                q = [a[j], a[k], b[k], b[j]]
                m.polygon(q, 'Interior', inside, c - np.mean(np.array(q, dtype=float), axis=0))
        fan(m, rings[-1], 'Interior', inside, [0, 0, -1], -.012)
        c0 = vec(centres[0])
        m.polygon([tuple(c0 + (vec(p) - c0) * .985 + vec([0, 0, .014])) for p in rings[0]], 'Interior', inside, [0, 0, 1])
    return rings, tags


def wing(m, node, xs, yc, fw, base_of, top_of, side, mat='Paint'):
    """A separate wing: an arch-shaped shell along the car over a wheel, `fw` wide round `yc`, from its foot
    (base_of(x): the arch round the wheel) to its crown (top_of(x)); its ends closed."""
    K = 8
    rings = []; centres = []
    for x in xs:
        b, t = base_of(x), top_of(x)
        ring = []
        for k in range(K + 1):
            phi = math.pi * k / K
            y = yc - side * fw / 2 * math.cos(phi)
            z = b + (t - b) * math.sin(phi) ** .5
            ring.append((x, y, z))
        rings.append(ring); centres.append((x, yc, b))
    loft(m, rings, node, mat, centres, closed=False)
    m.polygon(rings[0], mat, node, [-1 if xs[0] < xs[-1] else 1, 0, 0])
    m.polygon(rings[-1], mat, node, [1 if xs[0] < xs[-1] else -1, 0, 0])
    # its underside dark (the wheel's well: mud and shadow, not paint; one of the small things)
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        cc = (vec(centres[i]) + vec(centres[i + 1])) / 2
        for j in range(K):
            q = [a[j], a[j + 1], b[j + 1], b[j]]
            m.polygon(q, 'Wheel_well', getattr(m, 'fine', node), cc - np.mean(np.array(q, dtype=float), axis=0))


def arch_z(x, axle, r, arch):
    d = abs(x - axle)
    return r + math.sqrt(max(0.0, arch * arch - d * d)) if d < arch else None


# ---------------------------------------------------------------------------------------------------------------
# The cars

SPECS = [
    dict(id='11_sedan_49', name='Big Sedan 49', kind='sedan', color=(.10, .11, .12), L=5.00, W=1.90, H=1.64, wb=2.92,
         r=.37, front_axle=1.62, skirts=True, whitewall=True),
    dict(id='12_taxi_49', name='Taxi 49', kind='taxi', color=(.035, .036, .04), L=5.00, W=1.90, H=1.64, wb=2.92,
         r=.37, front_axle=1.62, skirts=False, whitewall=False),
    dict(id='13_saloon_53', name='Small Saloon 53', kind='saloon', color=(.16, .24, .20), L=4.15, W=1.62, H=1.56,
         wb=2.45, r=.33, front_axle=1.38, skirts=False, whitewall=False),
    dict(id='14_pickup_51', name='Pickup 51', kind='pickup', color=(.24, .30, .26), L=4.75, W=1.98, H=1.92, wb=2.90,
         r=.38, front_axle=1.62, skirts=False, whitewall=False),
    dict(id='15_van_51', name='Delivery Van 51', kind='van', color=(.42, .40, .34), L=4.70, W=1.98, H=2.10, wb=2.90,
         r=.38, front_axle=1.60, skirts=False, whitewall=False),
    dict(id='16_coupe_48', name='Fastback Coupe 48', kind='coupe', color=(.30, .10, .09), L=4.95, W=1.88, H=1.60,
         wb=2.90, r=.37, front_axle=1.60, skirts=True, whitewall=True),
]


def build(s):
    m = Model(s['id'], s['color'])
    m.mat('Whitewall', (.86, .85, .80), 0, .7)
    m.mat('Taxi_yellow', (.96, .76, .10), .05, .4)
    m.mat('Interior_ivory', (.80, .76, .62), 0, .5)
    m.mat('Interior_paint', tuple(c * .8 for c in s['color']), .1, .5)
    m.mat('Wheel_well', (.022, .022, .024), 0, .95)
    kind = s['kind']
    L, W, H, r = s['L'], s['W'], s['H'], s['r']
    front, rear = L / 2, -L / 2
    fa = s['front_axle']; ra = fa - s['wb']
    w = W / 2
    body = m.node('Body'); trim = m.node('Exterior_Details'); inside = m.node('Interior')
    # the small things a camera sees only close to (the game's far copies leave them out, with the inside)
    m.fine = m.node('Fine_Details')
    if kind in ('sedan', 'taxi', 'coupe'): cab = _classic(m, s, body, trim, inside, front, rear, fa, ra, w)
    elif kind == 'saloon': cab = _pontoon(m, s, body, trim, inside, front, rear, fa, ra, w)
    else: cab = _truck(m, s, body, trim, inside, front, rear, fa, ra, w)
    # the wheels
    track = w - (.16 if kind in ('pickup', 'van') else .15)
    tw = .20 if kind == 'saloon' else .22
    for axle, lab in ((fa, 'F'), (ra, 'R')):
        for side in (1, -1):
            wheel(m, 'Wheel_' + lab + ('L' if side == 1 else 'R'), axle, side * track, r, tw, side, s['whitewall'],
                  kind in ('sedan', 'taxi', 'coupe', 'saloon'))
    for axle in (fa, ra): m.rod((axle, -track + .1, r), (axle, track - .1, r), .035, 'Trim', body, 6)
    # behind each wheel the well's inner wall (dark: nothing shows through under the wings)
    arch = r + (.08 if kind in ('pickup', 'van') else .07)
    for axle in (fa, ra):
        for side in (1, -1):
            yy = side * (track - tw / 2 - .03)
            m.polygon([(axle + arch * math.cos(a), yy, r + arch * math.sin(a)) for a in np.linspace(0, math.pi, 9)],
                      'Wheel_well', body, [0, side, 0])
    _details(m, s, m.fine, inside, cab)
    m.meta.update(id=s['id'], display_name=s['name'], wheel_radius_m=r, wheelbase_m=s['wb'], forward_axis='-Z',
                  up_axis='+Y', units='meters', reference_style=kind, period='1940s-50s, generic',
                  notes='Hora Cero: a generic rounded car of the time, no maker\'s badge, name or grille of a real model. '
                        'Built on the Retro Vehicle Pack generator (build_vehicles.py). The cabin\'s inside (seats, '
                        'dashboard, steering wheel, headlining) in the node Interior.')
    m.export(MODELS / (s['id'] + '.glb'))
    return m.meta


def _stations(front, rear, axles, arch, extra=()):
    xs = set(np.linspace(rear, front, 24).tolist())
    for e in (.03, .09, .18, .3): xs.update([front - e, rear + e])
    for a in axles:
        for t in np.linspace(0, math.pi, 9): xs.add(a + arch * math.cos(t))
    xs.update(extra)
    return sorted(x for x in xs if rear <= x <= front)


def _ends(m, trim, front, rear, w, bz, rad, guards, plate_front_z, plate_rear_z):
    for x, sign in ((front, 1), (rear, -1)):
        bumper(m, trim, x, bz, w * .93, .14, sign, rad=rad, guards=guards)
    m.box((front + rad + .015, 0, plate_front_z), (.012, .36, .11), 'Plate', trim)
    m.box((rear - .012, 0, plate_rear_z), (.012, .36, .11), 'Plate', trim)


def _classic(m, s, body, trim, inside, front, rear, fa, ra, w):
    """The big cars of the late forties: a narrow high bonnet between separate wings, the front ones crowned over the
    wheels with the lamps in their noses and sweeping back into the front doors, the rear ones bulging pods (skirted
    on the big sedan); a rounded body, the cabin's glasshouse on it (a notchback, or the coupé's fastback); heavy
    chrome bumpers with guards, a grille of plain bars under the bonnet's nose."""
    kind = s['kind']; L, H, r = s['L'], s['H'], s['r']
    arch = r + .07
    sill, belt = .42, 1.0
    cowl = fa - .90
    hood_w, body_w = w * .50, w * .80
    coupe = kind == 'coupe'

    def w_of(x):
        if x > cowl + .06:
            e = max(0.0, (x - (front - .35)) / .35)
            return hood_w * (1 - .22 * e ** 2)
        if x > cowl - .10: return hood_w + (body_w - hood_w) * (cowl + .06 - x) / .16
        e = max(0.0, (rear + .5 - x) / .5)
        return body_w * (1 - .24 * e ** 2.2)

    def zb_of(x):
        if x > cowl + .06: return .46 + .08 * max(0.0, (x - (front - .2)) / .2)
        z = sill
        a = arch_z(x, ra, r, arch)
        if a is not None: z = max(z, a)
        e = max(0.0, (rear + .35 - x) / .35)
        return z + .12 * e ** 2

    zh_k = [(front, .80), (front - .08, .90), (front - .35, .98), (cowl + .3, 1.02), (cowl, belt + .01)]
    zs_k = [(front, .74), (front - .08, .84), (front - .35, .92), (cowl + .3, .96), (cowl, belt)]
    if coupe:
        g = dict(belt=belt, top=H, ab=cowl + .02, at=cowl - .52, rt=-.45, rb=rear + .42, w0=body_w * .95,
                 w1=body_w * .72, rf=.18, rr=.50, breaks=[('f', .07, 'pillar'), ('x', -.95, 'side')], wrap=False,
                 vee=.06, back_bands=(1,))
        zh_k += [(rear + .42, belt), (rear + .25, .90), (rear + .1, .76), (rear, .62)]
        zs_k += [(rear + .42, belt - .02), (rear + .25, .86), (rear + .1, .72), (rear, .58)]
        doors = [cowl - .02, -.95]
    else:
        g = dict(belt=belt, top=H, ab=cowl + .02, at=cowl - .50, rt=-1.08, rb=-1.48, w0=body_w * .95,
                 w1=body_w * .74, rf=.18, rr=.30, breaks=[('f', .07, 'pillar'), ('x', -.30, 'side'),
                                                          ('x', -.38, 'pillar'), ('r', .10, 'side')], wrap=False, vee=.06)
        zh_k += [(-1.48, belt), (-1.62, .99), (rear + .55, .95), (rear + .25, .84), (rear + .07, .70), (rear, .62)]
        zs_k += [(-1.48, belt - .02), (-1.62, .96), (rear + .55, .90), (rear + .25, .80), (rear + .07, .66), (rear, .58)]
        doors = [cowl - .02, -.34, -1.12]
    zs_of = lambda x: smooth(zs_k, x)
    zh_of = lambda x: smooth(zh_k, x)
    xs = _stations(front, rear, (ra,), arch, extra=(cowl + .06, cowl - .10, cowl - .02))
    hull(m, body, xs, w_of, zb_of, zs_of, zh_of, wells=((ra, arch),))
    rings, tags = glasshouse(m, body, g, 'Taxi_yellow' if kind == 'taxi' else 'Paint', inside)
    # the wings
    f0, f1 = front - .03, cowl - .55
    r0, r1 = ra + arch + .50, ra - arch - .42
    for side in (1, -1):
        fxs = sorted(set(np.linspace(f1, f0, 16).tolist() + [fa + arch * math.cos(t) for t in np.linspace(0, math.pi, 9)]))
        def ftop(x):
            return smooth([(f0, .70), (f0 - .07, .84), (f0 - .25, .92), (fa, .98), (fa - .55, .90), (f1 + .45, .74), (f1, .52)], x)
        def fbase(x):
            a = arch_z(x, fa, r, arch)
            if a is not None: return a
            return smooth([(f0, .50), (fa + arch, .48)], x) if x > fa else smooth([(fa - arch, .44), (f1, .46)], x)
        yc = side * w * .74
        wing(m, body, [x for x in fxs if f1 <= x <= f0], yc, w * .54, fbase, ftop, side)
        headlamp(m, trim, f0 - .03, yc, ftop(f0 - .03) - .1, .105)
        m.bevel_box((f0 - .01, side * w * .56, .58), (.04, .12, .05), .012, 'Indicator', trim)
        rxs = sorted(set(np.linspace(r1, r0, 14).tolist() + [ra + arch * math.cos(t) for t in np.linspace(0, math.pi, 9)]))
        def rtop(x):
            return smooth([(r0, .50), (r0 - .3, .80), (ra + .2, .93), (ra - .2, .93), (r1 + .3, .80), (r1, .58)], x)
        def rbase(x):
            a = arch_z(x, ra, r, arch)
            if a is None: return .46 if x > ra else .52
            if s['skirts']: return min(a, r + .08 + .2 * (abs(x - ra) / arch) ** 3)
            return a
        wing(m, body, [x for x in rxs if r1 <= x <= r0], side * w * .80, w * .44, rbase, rtop, side)
        if s['skirts']:
            m.line([(ra + arch * .9, side * (w * 1.02 + .002), r + .1), (ra - arch * .9, side * (w * 1.02 + .002), r + .1)], .012, 'Chrome', trim)
        tail_lamp(m, trim, r1 + .02, side * w * .80, rtop(r1 + .02) - .08, .05)
        # chrome along the body, the doors' gaps and handles, a rubber sill between the wings
        zsp = belt - .16
        m.line([(cowl - .05, side * (body_w + .004), zsp), (rear + .6, side * (w_of(rear + .6) + .004), zsp)], .012, 'Chrome', trim)
        for gx in doors:
            m.line([(gx, side * (w_of(gx) + .003), zb_of(gx) + .03), (gx, side * (w_of(gx) + .003), belt - .02)], .006, 'Trim', trim)
        for hx in doors[1:]:
            m.box((hx + (.16 if kind != 'coupe' else .2), side * (body_w + .012), belt - .1), (.13, .02, .025), 'Chrome', trim)
        # the running board under the doors, from the front wing's tail to the rear wing: ribbed rubber on it, a
        # chrome edge
        xa, xb = f1 + .40, r0 - .08
        y0, y1 = body_w - .01, w * .97
        m.bevel_box(((xa + xb) / 2, side * (y0 + y1) / 2, .455), (xa - xb, y1 - y0, .035), .01, 'Paint_dark', body)
        for f in (.25, .5, .75):
            m.rod((xa - .02, side * (y0 + (y1 - y0) * f), .474), (xb + .02, side * (y0 + (y1 - y0) * f), .474), .007, 'Rubber', m.fine, 4)
        m.rod((xa, side * (y1 + .004), .455), (xb, side * (y1 + .004), .455), .012, 'Chrome', m.fine, 5)
        if side == 1:
            mx = g['ab'] - .12
            m.rod((mx, body_w * .98, belt - .02), (mx, body_w + .08, belt + .1), .012, 'Chrome', trim, 5)
            lathe_x(m, trim, mx - .02, body_w + .1, belt + .12, [(.05, 0.0), (.05, .025)], 'Chrome', 8, -1)
    # the drip rail over the side windows
    for side in (1, -1):
        y = side * ((g['w0'] + (g['w1'] - g['w0']) * .87) + .012)
        zr = belt + (H - belt) * .87
        m.line([(g['ab'] + (g['at'] - g['ab']) * .87 - .25, y, zr), (g['rb'] + (g['rt'] - g['rb']) * .87 + .2, y, zr)], .012, 'Chrome', trim)
    # the grille under the bonnet's nose: plain chrome bars across, a chrome surround
    gz, gh, gw = .64, .26, hood_w * .78
    m.bevel_box((front - .005, 0, gz), (.04, gw * 2 + .08, gh + .07), .025, 'Chrome', trim)
    m.box((front + .012, 0, gz), (.02, gw * 2, gh), 'Trim', trim)
    for zz in np.linspace(gz - gh * .38, gz + gh * .38, 5):
        m.rod((front + .03, -gw, zz), (front + .03, gw, zz), .015, 'Chrome', trim, 6)
    # its teeth: upright chrome bars in front of the cross bars, longest in the middle
    for yy in np.linspace(-gw * .86, gw * .86, 11):
        hh = gh * (.46 - .08 * (yy / gw) ** 2)
        m.rod((front + .047, yy, gz - hh), (front + .047, yy, gz + hh), .017, 'Chrome', m.fine, 6, r2=.012)
    m.line([(front - .02, 0, zh_of(front - .02) + .008), (front - .3, 0, zh_of(front - .3) + .012), (cowl + .15, 0, zh_of(cowl + .15) + .012)], .013, 'Chrome', trim)
    _ends(m, trim, front + .09, rear - .08, w, .44, .072, True, .30, .44 + .072 + .068)
    m.box((rear - .01, 0, zh_of(rear + .1) - .02), (.03, .22, .035), 'Chrome', trim)
    if kind == 'taxi':
        # the taxi's lamp on the roof, over the windscreen; the meter's flag on its post by the windscreen (the
        # kerb side), raised: the cab is free
        m.bevel_box((g['at'] - .2, 0, H + .045), (.10, .22, .05), .01, 'Trim', trim)
        m.bevel_box((g['at'] - .2, 0, H + .105), (.13, .30, .08), .02, 'Headlamp', trim)
        fx, fy = g['ab'] + .06, -(body_w - .02)
        m.bevel_box((fx, fy, belt + .07), (.10, .12, .14), .015, 'Trim', m.fine)
        m.rod((fx - .02, fy - .06, belt + .1), (fx - .02, fy - .06, belt + .36), .008, 'Chrome', m.fine, 5)
        m.box((fx - .02, fy - .06 - .002, belt + .30), (.11, .006, .09), 'Tail_light', m.fine)
    return dict(g=g, rings=rings, tags=tags, kind=kind, front=front, rear=rear, w=w, belt=belt, sill=sill, cowl=cowl,
                w_of=w_of, zs_of=zs_of, zh_of=zh_of, hood_w=hood_w, ornament=front - .16,
                hood=(front - .14, cowl + .08), lid=None if coupe else (-1.66, rear + .14, body_w * .62),
                fseat=-.30, rseat=-1.05 if coupe else -1.22, aerial=kind != 'taxi')


def _pontoon(m, s, body, trim, inside, front, rear, fa, ra, w):
    """The small European saloon of the early fifties: one rounded body with the wings in it (crowned a little over
    the front wheels, the lamps in them), a round nose and a sloping back, a small grille, slim bumpers."""
    L, H, r = s['L'], s['H'], s['r']
    arch = r + .07
    sill, belt = .36, .90
    zs_k = [(front, .66), (front - .08, .78), (front - .3, .87), (fa, .90), (.6, .90), (-.6, .89), (ra, .88),
            (rear + .45, .80), (rear + .15, .70), (rear, .60)]
    zh_k = [(front, .62), (front - .08, .72), (front - .35, .81), (.95, .86), (.80, .90), (rear + .42, .90),
            (rear + .25, .80), (rear + .1, .68), (rear, .58)]
    g = dict(belt=belt, top=H, ab=.80, at=.30, rt=-.40, rb=rear + .42, w0=w * .90, w1=w * .68, rf=.20, rr=.55,
             breaks=[('f', .07, 'pillar'), ('x', -.30, 'side'), ('x', -.37, 'pillar'), ('r', .12, 'side')],
             wrap=False, vee=.04, back_bands=(1,))
    doors = [.78, -.34, -1.12]
    zs_of = lambda x: smooth(zs_k, x)
    zh_of = lambda x: smooth(zh_k, x)

    def w_of(x):
        e = max(0.0, abs(x) - (L / 2 - .55)) / .55
        return w * (1 - .24 * e ** 2.2)

    def zb_of(x):
        z = sill
        for axle in (fa, ra):
            a = arch_z(x, axle, r, arch)
            if a is not None: z = max(z, a)
        e = max(0.0, abs(x) - (L / 2 - .3)) / .3
        return z + .1 * e ** 2

    xs = _stations(front, rear, (fa, ra), arch)
    hull(m, body, xs, w_of, zb_of, zs_of, zh_of, wells=((fa, arch), (ra, arch)))
    rings, tags = glasshouse(m, body, g, 'Paint', inside)
    for side in (1, -1):
        m.line([(front - .4, side * (w_of(front - .4) + .005), .64), (rear + .5, side * (w_of(rear + .5) + .005), .62)], .011, 'Chrome', trim)
        for gx in doors:
            m.line([(gx, side * (w_of(gx) + .003), zb_of(gx) + .03), (gx, side * (w_of(gx) + .003), belt - .02)], .006, 'Trim', trim)
        for hx in doors[1:]:
            m.box((hx + .14, side * (w + .012), belt - .09), (.12, .02, .025), 'Chrome', trim)
        y = side * ((g['w0'] + (g['w1'] - g['w0']) * .87) + .01)
        zr = belt + (H - belt) * .87
        m.line([(g['ab'] + (g['at'] - g['ab']) * .87 - .2, y, zr), (g['rb'] + (g['rt'] - g['rb']) * .87 + .2, y, zr)], .01, 'Chrome', trim)
        headlamp(m, trim, front - .06, side * w * .64, zs_of(front - .06) - .1, .09)
        m.bevel_box((front - .01, side * w * .40, .50), (.04, .10, .04), .01, 'Indicator', trim)
        tail_lamp(m, trim, rear + .03, side * w * .62, zs_of(rear + .03) - .08, .045)
        if side == 1:
            mx = g['ab'] - .1
            m.rod((mx, w * .97, belt - .02), (mx, w + .06, belt + .09), .011, 'Chrome', trim, 5)
            lathe_x(m, trim, mx - .02, w + .08, belt + .11, [(.045, 0.0), (.045, .022)], 'Chrome', 8, -1)
    # a small grille: an upright oval of chrome bars, under a chrome strip down the bonnet
    for k, zz in enumerate(np.linspace(.42, .62, 6)):
        c = (k - 2.5) / 2.5
        wid = w * .55 * (1 - .55 * c * c)
        m.rod((front + .005, -wid / 2, zz), (front + .005, wid / 2, zz), .013, 'Chrome', trim, 6)
    m.line([(front - .02, 0, zh_of(front - .02) + .006), (front - .3, 0, zh_of(front - .3) + .01), (.75, 0, zh_of(.75) + .01)], .011, 'Chrome', trim)
    _ends(m, trim, front + .06, rear - .06, w, .40, .05, True, .27, .40 + .05 + .068)
    return dict(g=g, rings=rings, tags=tags, kind='saloon', front=front, rear=rear, w=w, belt=belt, sill=sill,
                cowl=.80, w_of=w_of, zs_of=zs_of, zh_of=zh_of, hood_w=w * .62, ornament=front - .12,
                hood=(front - .12, .86), lid=(rear + .40, rear + .12, w * .55), fseat=-.30, rseat=-1.12, aerial=False)


def _truck(m, s, body, trim, inside, front, rear, fa, ra, w):
    """The working vehicles: a narrow bonnet between separate wings, running boards, a rounded cab; the pickup's
    step-side bed with its wings outside it, or the van's tall rounded body."""
    kind = s['kind']; L, H, r = s['L'], s['H'], s['r']
    van = kind == 'van'
    arch = r + .08
    sill = .50
    cowl = front - 1.42
    cab_back = cowl - 1.26
    belt = 1.16
    hood_w = w * .56
    cab_w = w * .86

    def w_of(x):
        if x > cowl + .04: return hood_w * (1 - .12 * max(0.0, (x - (front - .3)) / .3) ** 2)
        if x > cowl - .04: return hood_w + (cab_w - hood_w) * (cowl + .04 - x) / .08
        return cab_w * (1 - .05 * max(0.0, (rear + .25 - x) / .25) ** 2)

    def zb_of(x):
        if x > cowl: return .56 + .06 * max(0.0, (x - (front - .3)) / .3)
        if van:
            a = arch_z(x, ra, r, arch)
            if a is not None: return max(sill, a)
        return sill

    zs_k = [(front, .98), (front - .1, 1.04), (front - .5, 1.08), (cowl + .05, 1.11), (cowl - .05, belt), (rear, belt)]
    zh_k = [(front, 1.03), (front - .1, 1.10), (front - .5, 1.15), (cowl + .05, 1.18), (cowl - .05, belt), (rear, belt)]
    body_end = rear if van else cab_back
    xs = _stations(front, body_end, (ra,) if van else (), arch, extra=(cowl + .04, cowl - .04, cowl))
    hull(m, body, xs, w_of, zb_of, lambda x: smooth(zs_k, x), lambda x: smooth(zh_k, x), wells=((ra, arch),) if van else ())
    if van:
        g = dict(belt=belt, top=H, ab=cowl - .02, at=cowl - .36, rt=rear + .05, rb=rear + .01, w0=cab_w * .98,
                 w1=cab_w * .92, rf=.20, rr=.14, breaks=[('f', .06, 'pillar'), ('x', cowl - 1.02, 'side')],
                 wrap=False, vee=.03, back_bands=(2,))
    else:
        g = dict(belt=belt, top=H, ab=cowl - .02, at=cowl - .32, rt=cab_back + .10, rb=cab_back + .02, w0=cab_w * .97,
                 w1=cab_w * .88, rf=.16, rr=.14, breaks=[('f', .06, 'pillar'), ('r', .22, 'side')],
                 wrap=False, vee=.03, back_bands=(2,))
    rings, tags = glasshouse(m, body, g, 'Paint', inside)
    if van:
        # the van's back doors: their split, their handles
        m.line([(rear - .004, 0, sill + .05), (rear - .004, 0, H - .12)], .01, 'Trim', trim)
        for side in (1, -1):
            m.box((rear - .01, side * .1, belt - .05), (.03, .03, .1), 'Chrome', trim)
            m.line([(cowl - 1.08, side * (cab_w * .98 + .004), sill + .04), (cowl - 1.08, side * (cab_w * .98 + .004), H - .25)], .006, 'Trim', trim)
    else:
        # the bed: its floor, its sides with their rolled tops, its front, the tailgate with a chrome catch
        bf, bb = cab_back - .08, rear + .04
        bw = w * .66; floor = .72; tops = 1.10
        m.box(((bf + bb) / 2, 0, floor), (bf - bb, bw * 2, .06), 'Paint_dark', body)
        for side in (1, -1):
            m.box(((bf + bb) / 2, side * (bw - .025), (floor + tops) / 2), (bf - bb, .05, tops - floor), 'Paint', body)
            m.rod((bf, side * bw, tops + .02), (bb, side * bw, tops + .02), .03, 'Paint', body, 6)
        m.box((bf, 0, (floor + tops) / 2), (.05, bw * 2, tops - floor), 'Paint', body)
        m.box((bb, 0, (floor + tops) / 2 - .02), (.05, bw * 2, tops - floor - .04), 'Paint', body)
        m.box((bb - .03, 0, tops - .12), (.02, .2, .04), 'Chrome', trim)
        for side in (1, -1): tail_lamp(m, trim, bb - .025, side * (bw - .1), .9, .045)
    # the wings, separate: the front ones from beside the grille over the wheel and down to the running board; the
    # rear ones over the rear wheels, outside the bed or the body
    f0, f1 = front - .02, cowl - .55
    r0, r1 = ra + arch + .22, ra - arch - .18
    for side in (1, -1):
        fxs = sorted(set(np.linspace(f1, f0, 14).tolist() + [fa + arch * math.cos(t) for t in np.linspace(0, math.pi, 7)]))
        def ftop(x):
            return smooth([(f0, .80), (f0 - .08, .96), (f0 - .25, 1.02), (fa, 1.06), (fa - .45, .98), (f1 + .35, .72), (f1, .54)], x)
        def fbase(x):
            a = arch_z(x, fa, r, arch)
            if a is not None: return a
            return .60 if x > fa else smooth([(fa - arch, r + .02), (f1, .49)], x)
        yc = side * (w - .19)
        wing(m, body, [x for x in fxs if f1 <= x <= f0], yc, .44, fbase, ftop, side)
        headlamp(m, trim, f0 - .03, yc, ftop(f0 - .03) - .1, .105)
        rxs = sorted(set(np.linspace(r1, r0, 10).tolist() + [ra + arch * math.cos(t) for t in np.linspace(0, math.pi, 7)]))
        def rtop(x):
            return smooth([(r0, .60), (r0 - .2, .86), (ra, .99), (r1 + .25, .86), (r1, .64)], x)
        def rbase(x):
            a = arch_z(x, ra, r, arch)
            return a if a is not None else .52
        wing(m, body, [x for x in rxs if r1 <= x <= r0], side * (w - (.10 if van else .15)), .34 if van else .40, rbase, rtop, side)
        # the running board between the wings: ribbed rubber on it
        m.box(((f1 + r0) / 2, side * (w - .15), .47), (f1 - r0 + .1, .30, .04), 'Paint_dark', body)
        for f in (-.09, -.03, .03, .09):
            m.rod((f1 + .04, side * (w - .15 + f), .492), (r0 - .04, side * (w - .15 + f), .492), .008, 'Rubber', m.fine, 4)
        # the bonnet's side louvres
        for k in range(5):
            zz = .80 + k * .055
            m.rod((cowl + .22, side * (hood_w + .006), zz), (cowl + .62, side * (hood_w + .006), zz), .007, 'Trim', m.fine, 4)
        # the door's gap and handle; the driver's mirror on its arm
        for gx in (cowl - .03, cowl - 1.0):
            m.line([(gx, side * (cab_w + .004), sill + .04), (gx, side * (cab_w + .004), belt - .03)], .006, 'Trim', trim)
        m.box((cowl - .85, side * (cab_w + .012), belt - .1), (.12, .02, .025), 'Chrome', trim)
        if side == 1:
            m.rod((cowl - .06, cab_w * .97, belt + .05), (cowl - .03, w + .08, belt + .22), .012, 'Trim', trim, 5)
            lathe_x(m, trim, cowl - .05, w + .1, belt + .24, [(.06, 0.0), (.06, .03)], 'Chrome', 8, -1)
    # the grille: plain chrome bars across the bonnet's front, between the wings
    m.bevel_box((front - .005, 0, .80), (.03, hood_w * 1.7, .42), .02, 'Trim', trim)
    for zz in np.linspace(.62, .98, 6):
        m.rod((front + .012, -hood_w * .8, zz), (front + .012, hood_w * .8, zz), .02, 'Chrome', trim, 6)
    # the bumpers (painted steel on a working vehicle), the plates, the van's tail lamps, a strip down the bonnet
    bumper(m, trim, front + .12, .52, w * 1.0, .06, 1, 'Wheel_steel', .06, guards=False)
    bumper(m, trim, rear - .07, .52, w * .96, .04, -1, 'Wheel_steel', .055, guards=False)
    m.box((front + .17, 0, .38), (.012, .36, .12), 'Plate', trim)
    m.box((rear - .03, 0, .74 if van else .64), (.012, .36, .12), 'Plate', trim)
    if van:
        for side in (1, -1): tail_lamp(m, trim, rear - .005, side * (cab_w - .1), .80, .05)
    m.line([(front - .02, 0, 1.05), (front - .5, 0, 1.165), (cowl + .1, 0, 1.19)], .012, 'Chrome', trim)
    zh = lambda x: smooth(zh_k, x)
    zs = lambda x: smooth(zs_k, x)
    return dict(g=g, rings=rings, tags=tags, kind=kind, front=front, rear=rear, w=w, belt=belt, sill=sill, cowl=cowl,
                w_of=w_of, zs_of=zs, zh_of=zh, hood_w=hood_w, ornament=front - .12, hood=(front - .10, cowl + .06),
                lid=None, fseat=cowl - 1.02, rseat=None, aerial=False)


# ---------------------------------------------------------------------------------------------------------------
# The small things on every car: chrome round its windows, the bonnet's seams and the boot's lid, its mascot, the wipers,
# an aerial; inside, the dashboard, the steering wheel and the benches

def _top_z(cab, x, y):
    """The height of the body's top at (x, y) (the hull's section: crowned between its shoulders)."""
    w = cab['w_of'](x); zs, zh = cab['zs_of'](x), cab['zh_of'](x)
    f = min(1.0, abs(y) / (.84 * w))
    return zh + (zs - zh) * f * f


def _details(m, s, trim, inside, cab):
    g = cab['g']; kind = cab['kind']
    belt, top = g['belt'], g['top']
    rings, tags = cab['rings'], cab['tags']
    n = len(tags)
    # chrome round the glass: along the windows' feet and heads, up their ends where a pillar starts
    bands = {'ws': (1, 2), 'wrap': (1, 2), 'side': (1, 2), 'back': tuple(g.get('back_bands', (1, 2)))}
    def out(p, c, d=.006):
        p = vec(p); dv = p - vec(c); dv[2] = 0
        return p + dv / max(np.linalg.norm(dv), 1e-6) * d
    for j in range(n):
        zone = tags[j]
        if zone not in bands: continue
        lo, hi = min(bands[zone]), max(bands[zone]) + 1
        for ri in (lo, hi):
            ring = rings[ri]; c = (np.mean(np.array(ring)[:, 0]), 0, ring[0][2])
            m.rod(out(ring[j], c), out(ring[(j + 1) % n], c), .009 if ri == lo else .007, 'Chrome', trim, 4)
        for e in (j, (j + 1) % n):
            other = tags[e - 1] if e == j else tags[e]
            if other in bands and other == zone: continue
            if zone == 'ws' and other == 'div': continue
            cl = (np.mean(np.array(rings[lo])[:, 0]), 0, rings[lo][0][2]); ch = (np.mean(np.array(rings[hi])[:, 0]), 0, rings[hi][0][2])
            m.rod(out(rings[lo][e], cl), out(rings[hi][e], ch), .007, 'Chrome', trim, 4)
    # the windscreen's plane (for the wipers, the mirror inside it)
    d = unit_(vec([g['at'] - g['ab'], 0, top - .04 - belt]))
    nrm = vec([d[2], 0, -d[0]])
    def ws(t, y): return vec([g['ab'] + (g['at'] - g['ab']) * t, y, belt + (top - .04 - belt) * t])
    # the wipers, parked across the windscreen's foot: each arm from its pivot in the scuttle to its blade
    for y0 in (g['w0'] * .62, g['w0'] * .02):
        piv = ws(-.02, y0) + nrm * .02
        b0, b1 = ws(.07, y0 - .02) + nrm * .016, ws(.11, y0 - .40) + nrm * .016
        m.rod(b0, b1, .008, 'Trim', trim, 4)
        m.rod(piv, (b0 + b1) / 2 + nrm * .006, .006, 'Chrome', trim, 4)
        m.rod(piv - nrm * .01, piv + nrm * .012, .014, 'Chrome', trim, 6)
    # the mirror inside the windscreen's head
    mp = ws(.80, 0) - nrm * .08
    m.box(tuple(mp), (.03, .20, .06), 'Interior', inside)
    m.rod(tuple(mp + vec([0, 0, .03])), tuple(ws(.95, 0) - nrm * .02), .008, 'Chrome', inside, 4)
    # the bonnet's seams (its sides, its back at the scuttle) and the boot's lid
    hw = cab['hood_w'] * .80
    x0, x1 = cab['hood']
    for side in (1, -1):
        pts = [(x, side * hw, _top_z(cab, x, hw) + .004) for x in np.linspace(x0, x1, 7)]
        m.line(pts, .0045, 'Trim', trim)
    m.line([(x1, y, _top_z(cab, x1, y) + .004) for y in np.linspace(-hw, hw, 7)], .0045, 'Trim', trim)
    if cab['lid']:
        lx0, lx1, lw = cab['lid']
        for side in (1, -1):
            m.line([(x, side * lw, _top_z(cab, x, lw) + .004) for x in np.linspace(lx0, lx1, 6)], .0045, 'Trim', trim)
        m.line([(lx0, y, _top_z(cab, lx0, y) + .004) for y in np.linspace(-lw, lw, 6)], .0045, 'Trim', trim)
        # its handle, the lamp over the plate below it
        m.box((lx1 + .02, 0, _top_z(cab, lx1 + .02, 0) - .03), (.05, .12, .03), 'Chrome', trim)
    # the bonnet's mascot: a plain swept chrome shape on its nose (no maker's emblem)
    ox = cab['ornament']; oz = _top_z(cab, ox, 0)
    if kind in ('pickup', 'van'):
        lathe_x(m, trim, ox, 0, oz + .02, [(.035, 0.0), (.03, .03), (.012, .045)], 'Chrome', 8, 1)
    else:
        m.rod((ox + .04, 0, oz + .015), (ox - .13, 0, oz + .05), .014, 'Chrome', trim, 6, r2=.004)
        for side in (1, -1):
            m.polygon([(ox - .02, side * .003, oz + .03), (ox - .12, side * .003, oz + .05), (ox - .11, side * .003, oz + .10)], 'Chrome', trim, [0, side, 0])
    # the radio's aerial, up from the scuttle on the kerb side
    if cab['aerial']:
        ab = vec([g['ab'] + .02, -(g['w0'] + .03), belt + .01])
        m.rod(tuple(ab), tuple(ab + vec([-.02, -.01, .05])), .016, 'Chrome', trim, 6)
        m.rod(tuple(ab + vec([-.02, -.01, .05])), tuple(ab + vec([-.24, -.03, .82])), .0045, 'Chrome', trim, 4, r2=.003)
    # inside: the dashboard (painted, the colour of the car) under the windscreen, its dial; the steering wheel
    # (ivory, the driver on the left: Argentina has driven on the right since 1945); the benches' backs
    dx = g['ab'] - .13 - .12
    m.box((dx, 0, belt + .045), (.24, g['w0'] * 1.86, .17), 'Interior_paint', inside)
    m.box((dx - .12, 0, belt + .12), (.04, g['w0'] * 1.8, .03), 'Chrome', inside)
    yd = g['w0'] * .45
    lathe_x(m, inside, dx - .121, yd, belt + .06, [(.06, 0.0), (.05, .004)], 'Chrome', 10, -1)
    lathe_x(m, inside, dx - .126, yd, belt + .06, [(.05, 0.0), (.0, .002)], 'Interior_ivory', 10, -1)
    a = math.radians(38)
    u, v = vec([0, 1, 0]), vec([math.sin(a), 0, math.cos(a)])
    cw = vec([dx - .40, yd, belt + .07])
    ring = [cw + .19 * (math.cos(t) * u + math.sin(t) * v) for t in np.linspace(0, 2 * math.pi, 17)]
    m.line(ring, .011, 'Interior_ivory', inside)
    for t in (0.0, math.pi, -math.pi / 2):
        m.rod(tuple(cw), tuple(cw + .185 * (math.cos(t) * u + math.sin(t) * v)), .008, 'Chrome', inside, 4)
    m.rod(tuple(cw), tuple(cw + vec([.3, 0, -.22])), .022, 'Interior', inside, 6)
    lean = math.radians(14)
    rot = np.array([[math.cos(lean), 0, math.sin(lean)], [0, 1, 0], [-math.sin(lean), 0, math.cos(lean)]])
    def back_x(z):
        # where the back window is at height z (the rear bench's back stays a hand ahead of it)
        tt = min(max((z - belt) / (top - .04 - belt), 0.0), 1.0)
        return g['rb'] + (g['rt'] - g['rb']) * tt ** .9
    for sx, hgt in ((cab['fseat'], .30), (cab['rseat'], .27 if kind != 'coupe' else .2)):
        if sx is None: continue
        sx = max(sx, back_x(belt + hgt + .05) + .16)
        half = min(g['w0'] * .88, _cabin_half(g, sx - .12, belt + hgt + .04) - .09, _cabin_half(g, sx + .08, belt + hgt) - .08)
        m.box((sx, 0, belt + hgt / 2 - .03), (.13, half * 2, hgt + .06), 'Seat_fabric', inside, rot)
        zt = belt + hgt - .03
        m.rod((sx - math.sin(lean) * (hgt / 2 + .03), -half, zt), (sx - math.sin(lean) * (hgt / 2 + .03), half, zt), .066, 'Seat_fabric', inside, 6)
        # the pleats down its back
        for f in np.linspace(-.8, .8, 7):
            m.rod((sx + .07, f * half, belt + .02), (sx + .07 - math.sin(lean) * hgt, f * half, belt + hgt - .04), .006, 'Interior', inside, 4)


def _cabin_half(g, x, z):
    """The cabin's half width inside at (x, z): the glasshouse's ring there, its corners rounded."""
    belt, top = g['belt'], g['top']
    tt = min(max((z - belt) / (top - .04 - belt), 0.0), 1.0)
    xf = g['ab'] + (g['at'] - g['ab']) * tt ** .9
    xr = g['rb'] + (g['rt'] - g['rb']) * tt ** .9
    hw = g['w0'] + (g['w1'] - g['w0']) * tt
    rf = min(g['rf'], hw * .6, (xf - xr) * .3); rr = min(g['rr'], hw * .6, (xf - xr) * .3)
    if x > xf - rf: d = min(x - (xf - rf), rf); return hw - rf + math.sqrt(max(rf * rf - d * d, 0.0))
    if x < xr + rr: d = min(xr + rr - x, rr); return hw - rr + math.sqrt(max(rr * rr - d * d, 0.0))
    return hw


def unit_(v):
    v = vec(v); return v / max(np.linalg.norm(v), 1e-9)


if __name__ == '__main__':
    only = sys.argv[1:]
    manifest = [build(s) for s in SPECS if not only or s['id'] in only]
    (MODELS / 'manifest_1950s.json').write_text(json.dumps(manifest, indent=2))
    for meta in manifest:
        print(meta['id'], meta['triangles'], 'triangles', meta['dimensions_m'])
