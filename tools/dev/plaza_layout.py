#!/usr/bin/env python3
"""Plaza de Mayo: the night the snow begins in Buenos Aires, 1958. The prologue of the Buenos Aires preview ("Hora Cero ·
Invasión Buenos Aires"), after the comic by H. G. Oesterheld and F. Solano López that began in Hora Cero Semanal in
1957: a snowfall that kills on contact begins over the city centre. Made as a private preview for the comic's rights
holders, who have cleared its characters and creatures for the game: Juan Salvo comes into the square in his insulating
suit early in the night, and from the first minute the cascarudos come up the avenues. Their look comes only from the
art pack's licensed slots ("art:juan_salvo", "art:cascarudo"; godot/art_pack, docs/ART_PACK.md), which show neutral
stand-ins until the files come; the squad from La Boca and everyone else in the square are the game's own.

Writes godot/data/plaza.json. Everything is laid out here in metres (x east, z south) and converted to mission units
(32 per metre). The 3D builder for the plaza theme (scripts/three_d/plaza*.gd) reads the same file, so the scenery and
the rules agree. Edit this script, not the JSON.

A rescue, not a stealth operation: there is nobody to hide from. Half the city has come to the square to see the
first snow in forty years, and within minutes people who stay out in it begin to fall. The four neighbours of
Operation Riachuelo happened to be under cover when it began (Hornero at the controls of a tram that has stopped on
Rivadavia, Lechuza under the Cabildo's arcade, whose lamps have failed, Benteveo selling the Sexta on the Catedral's
steps, Biguá on a colectivo stranded on Hipólito Yrigoyen); they have until the snow buries the square to get as many
people as they can under cover. Early in the night Juan Salvo walks in off Avenida de Mayo and joins them: sealed in his
suit he takes no cold (units[].suit), so he is the one who can cross the open square in a wave to reach the fallen and
carry one in at a time, and he has a rifle with few rounds. From the first minute the cascarudos come up the avenues
("creatures"): they roam toward whoever is out in the open and knock down whoever they reach; they keep out of every
shelter and every vehicle and walk round everything solid; noise draws them (the tram's bell, a shout, a shot), and a
hit from the rifle drives one off the map for a while (three kill it) while the bang draws the others.

Map 280 x 166 m, the real square simplified: Rivadavia along the north side with its two tram tracks, the Catedral and
its portico of twelve columns at the north-west corner (Rivadavia and San Martín), the Banco Nación at the north-east,
the Casa Rosada along the east side beyond Balcarce (its gates shut), the ministries along Hipólito Yrigoyen on the
south side, and on the west, beyond Bolívar, the Palacio Municipal, Avenida de Mayo leaving west with the two stairs of
the subte's Plaza de Mayo station (Línea A, 1913), and the Cabildo with its five arches and its tower. In the square:
the Pirámide de Mayo in the middle (no corner statues in 1958), eight Canary palms round it, the Belgrano monument in
front of the Casa Rosada, the flagpole, lawns, paths and lamps.

The rules (docs/GAMEPLAY_API.md, "Keys a fifth mission may use"): the deadly snowfall ("snowfall": its schedule of
waves and lulls, the exposure it gives, when it buries the square); the people in the square ("people", kept in the
rules' guards as civilians of kind "person"), led by a "guide", rallied or called by the squad's "call", carried by
Biguá or Juan Salvo when they have fallen; the cascarudos ("creatures", kept in the rules' guards as kind "creature"); the "shelters" (the portico, the arcade, the subte's stairs, the tram and the colectivo,
the bank's porch); the "vehicles" (the tram Hornero drives along the Rivadavia tracks); Lechuza's two jobs as
"passages" (the arcade's lights, the subte's service gate); and the cloths that can be held over people for one
crossing ("canvases").
"""
import json, os

U = 32.0


def u(v):
    return int(round(v * U))


def rect(id, x0, z0, x1, z1, kind, **extra):
    d = {"id": id, "x": u(x0), "y": u(z0), "w": u(x1) - u(x0), "h": u(z1) - u(z0), "kind": kind}
    d.update(extra)
    return d


def box(x0, z0, x1, z1, *flags):
    return [u(x0), u(z0), u(x1) - u(x0), u(z1) - u(z0)] + list(flags)


def pt(x, z, *rest):
    return [u(x), u(z)] + list(rest)


W, H = 280.0, 166.0

# --- fixed lines (metres) ---
RIVADAVIA = (22.0, 36.0)            # the street along the north side (z), the full width of the map
RIV_ROAD = (25.5, 32.5)             # its roadway between the pavements (z)
TRACKS_Z = (27.5, 30.5)             # its two tram tracks
PLAZA = (42.0, 36.0, 242.0, 132.0)  # the square itself: x0, z0, x1, z1 (200 x 96 m)
YRIGOYEN = (132.0, 146.0)           # Hipólito Yrigoyen along the south side (z)
YRI_ROAD = (135.5, 142.5)
BOLIVAR = (28.0, 42.0)              # Bolívar along the west side (x)
BOL_ROAD = (31.0, 39.0)
BALCARCE = (242.0, 256.0)           # Balcarce along the east side (x), the Casa Rosada beyond it
BAL_ROAD = (245.0, 253.0)
AV_MAYO = (72.0, 100.0)             # Avenida de Mayo, leaving west from the middle of the west side (z)
AVM_ROAD = (77.0, 95.0)
SAN_MARTIN = (96.0, 104.0)          # streets running north off Rivadavia (x)
RECONQUISTA = (180.0, 188.0)
DEFENSA = (120.0, 128.0)            # and south off Hipólito Yrigoyen

# The landmarks are drawn by the Plaza de Mayo kit (godot/scripts/three_d/plaza_kit*.gd), each fitted to a footprint
# below; the rules' rectangles follow what its builders put where (the portico's columns and steps, the arcade's
# depth and piers, the bank's porch and columns, the Casa Rosada's projections, the monuments' bases), so the walk
# mesh, the cover and the pictures agree. The kit's numbers are quoted where they are used.
# The Catedral (kit catedral, facing south): its front (the foot of its eight steps of 0.2 m, 0.45 m deep) on the
# pavement of Rivadavia; the stylobate 1.6 m up from 3.6 m back; twelve columns 5 m back from the front, spaced over
# the front less 4 % at each end; the wall with the doors 11 m back. Its nave and dome run on north off the map.
CAT_X = (44.0, 96.0)
CAT_FRONT = RIVADAVIA[0]
CAT_DEPTH = 44.0
CATEDRAL_KIT = (CAT_X[0], CAT_FRONT - CAT_DEPTH, CAT_X[1], CAT_FRONT)
_cw = CAT_X[1] - CAT_X[0]
COLUMN_X = [round(CAT_X[0] + _cw * 0.04 + i * _cw * 0.92 / 11.0, 3) for i in range(12)]
COLUMN_HALF = 0.85                          # the shaft's foot (radius 0.8) on its plinth
COLUMNS_Z = (CAT_FRONT - 5.0 - COLUMN_HALF, CAT_FRONT - 5.0 + COLUMN_HALF)
STYLOBATE = 1.6
CATEDRAL = (CAT_X[0], 0.0, CAT_X[1], CAT_FRONT - 11.0)        # the church behind the portico's back wall
PORTICO = (COLUMN_X[0], CAT_FRONT - 11.0, COLUMN_X[-1], CAT_FRONT - 3.6)   # the portico's floor, up on the stylobate
# The Banco de la Nación (kit banco_nacion, facing south): eleven bays of 54/11 m, the middle five set back 4 m as the
# entrance bay behind four great columns (radius 0.95) 0.8 m behind the front, five steps up to it (1 m).
BANCO = (188.0, 0.0, 242.0, 22.0)
_bay = (BANCO[2] - BANCO[0]) / 11.0
BANCO_PORCH = (round(BANCO[0] + 3 * _bay, 3), BANCO[3] - 4.0, round(BANCO[0] + 8 * _bay, 3), BANCO[3])
BANCO_COLUMNS = [round(BANCO_PORCH[0] + i * _bay, 3) for i in range(1, 5)]
BANCO_COLUMN_Z = BANCO[3] - 0.8
MUNICIPAL = (0.0, 36.0, 28.0, AV_MAYO[0])   # the Palacio Municipal, on the corner of Avenida de Mayo and Bolívar
# The Cabildo (kit cabildo, facing east, two arches either side of the middle one): five arches of 5.2 m (0.66 of the
# bay wide, the middle one 0.7), cut through a front 0.8 m thick; the arcade 3.4 m deep to the house's wall, closed
# at its ends by walls 0.4 m thick.
CABILDO_KIT = (4.0, 100.0, 28.0, 126.0)
ARCADE = (CABILDO_KIT[2] - 3.4, 100.0, CABILDO_KIT[2], 126.0)
CABILDO = (CABILDO_KIT[0], 100.0, ARCADE[0], 126.0)         # the house behind its arcade
ARCH_PIERS = [100.0 + 5.2 * i for i in range(6)]   # five arches between six piers
_bayc = 5.2
_arch_w = [_bayc * (0.7 if i == 2 else 0.66) for i in range(5)]
# (the kit counts its arches from the south end: arch i's middle is 126 - (i + 0.5) bays)
PIER_SPANS = []
for _k in range(6):
    _lo = 126.0 - (_k - 0.5) * _bayc - _arch_w[_k - 1] / 2 if _k > 0 else 126.0
    _hi = 126.0 - (_k + 0.5) * _bayc + _arch_w[_k] / 2 if _k < 5 else 100.0
    PIER_SPANS.append((round(_hi, 3), round(_lo, 3)))
ARCADE_FRONT = 0.8
CASA_ROSADA = (256.0, 36.0, W, 132.0)
# The Casa Rosada (kit casa_rosada, facing west, 96 m): the wings' ground floor 2.4 m behind the front, the end
# pavilions (0.12 of it, 11.52 m) 1.2 m, Tamburini's block in the middle (0.17 of it) on the front with its arch
# (0.4 of the block) and two pairs of columns on pedestals 1.3 m square standing out 0.1 to 1.4 m before it.
_rw = CASA_ROSADA[3] - CASA_ROSADA[1]
_rc = (CASA_ROSADA[1] + CASA_ROSADA[3]) / 2.0
_cwr = min(max(_rw * 0.17, 14.0), 20.0)
_pwr = min(max(_rw * 0.12, 9.0), 15.0)
_awr = min(7.0, _cwr * 0.4)
ROSADA_ARCH = (round(_rc - _awr / 2, 3), round(_rc + _awr / 2, 3))   # Tamburini's central arch (z), its gates shut
ROSADA_CENTRE = (round(_rc - _cwr / 2, 3), round(_rc + _cwr / 2, 3))
ROSADA_PAVILION = round(_pwr, 3)
ROSADA_PEDESTALS = [(round(_rc - _awr / 2 - 1.3 - 1.55 - 0.65, 3), round(_rc - _awr / 2 - 1.3 + 0.65, 3)),
                    (round(_rc + _awr / 2 + 1.3 - 0.65, 3), round(_rc + _awr / 2 + 1.3 + 1.55 + 0.65, 3))]
MINISTRY_W = (28.0, 146.0, DEFENSA[0], H)
MINISTRY_E = (DEFENSA[1], 146.0, BALCARCE[0], H)
PIRAMIDE = (142.0, 84.0)                    # the Pirámide de Mayo, in the middle
PIRAMIDE_FENCE = 6.4                        # half the side of its railing (the kit's: 6.2 m to the middle of its kerb)
BELGRANO = (229.0, 84.0)                    # the equestrian monument in front of the Casa Rosada, looking west
BELGRANO_BASE = (3.7, 2.1)                  # half its granite step (7.4 m along the horse, 4.2 across)
FLAGPOLE = (196.0, 56.0)
FLAGPOLE_BASE = 1.2                         # half its stepped stone base
PALMS = []
for i in range(8):
    import math
    a = math.radians(22.5 + 45.0 * i)
    PALMS.append((round(PIRAMIDE[0] + math.cos(a) * 25.0, 2), round(PIRAMIDE[1] + math.sin(a) * 19.0, 2)))
# the subte's Plaza de Mayo station (Línea A): its two street stairs on Avenida de Mayo's pavements, going down west,
# and a service stair at the square's south-west corner behind a locked gate
SUBTE_N = (6.0, 73.0, 15.0, 76.0)
SUBTE_S = (6.0, 96.0, 15.0, 99.0)
SUBTE_SERVICE = (43.0, 128.0, 51.0, 131.0)
SERVICE_GATE = (51.0, 52.0)                  # x: the gate across the head of the service stair
# (the kit's stairs: 4.2 m down in 24 steps of 0.29 m from 0.15 m inside the head, the landing at the foot)
STAIR_DEPTH = 4.2
# the stopped tram on the north track of Rivadavia (west end x at each stop), the stranded colectivo on Yrigoyen
TRAM_LEN, TRAM_W = 14.0, 2.6
TRAM_STOPS = [98.0, 136.0, 174.0]
TRAM_Z = TRACKS_Z[0]
COLECTIVO = (199.3, 136.95, 207.7, 139.45)   # (the kit's colectivo, 7.6 x 2.24 m, a tenth larger)
KIOSK = (150.3, 33.4, 152.7, 35.1)          # a newspaper kiosk on Rivadavia's south pavement (the kit's, 2.4 x 1.7 m)
CART = (88.0, 140.0, 92.0, 142.2)           # a vendor's cart left on Hipólito Yrigoyen
AWNING = (22.0, 73.6)                       # a café's awning on the corner of Avenida de Mayo
# cars of the time parked at the kerbs, the snow settling on them (x, z, heading in degrees: 0 south, 90 east; kind):
# official cars before the Casa Rosada, a taxi rank on Bolívar, cars and a soda truck along Yrigoyen's far kerb
PARKED = [(252.1, 44.0, 180, "sedan"), (252.1, 50.6, 180, "sedan"), (252.1, 57.2, 180, "sedan"),
          (252.1, 112.0, 0, "sedan"), (252.1, 118.6, 0, "saloon"),
          (32.0, 42.0, 180, "taxi"), (32.0, 48.6, 180, "taxi"), (32.0, 55.2, 180, "taxi"),
          (58.0, 141.6, 90, "sedan"), (65.0, 141.6, 90, "saloon"), (150.0, 141.6, 90, "truck"),
          (162.0, 141.6, 90, "sedan"), (226.0, 141.6, 90, "saloon")]
CAR_SIZE = {"sedan": (5.05, 1.92), "taxi": (5.05, 1.92), "saloon": (3.95, 1.56), "truck": (6.4, 2.1)}
# benches by the walks (x, z, the way they face in degrees: 0 south, 90 east, 180 north, 270 west)
BENCHES = [(62.0, 78.2, 0), (98.0, 78.2, 0), (186.0, 78.2, 0), (206.0, 78.2, 0),
           (62.0, 89.8, 180), (98.0, 89.8, 180), (186.0, 89.8, 180), (206.0, 89.8, 180),
           (137.2, 48.0, 90), (137.2, 120.0, 90), (146.8, 48.0, 270), (146.8, 120.0, 270)]
# the square's lamps (cast-iron candelabra): round its edge and along the walks
LAMPS = [(48.0, 40.0), (95.0, 40.0), (142.0, 40.0), (189.0, 40.0), (236.0, 40.0),
         (48.0, 128.0), (95.0, 128.0), (142.0, 128.0), (189.0, 128.0), (236.0, 128.0),
         (48.0, 70.0), (48.0, 98.0), (236.0, 70.0), (236.0, 98.0),
         (110.0, 66.0), (174.0, 66.0), (110.0, 102.0), (174.0, 102.0)]
START = {"hornero": (104.0, 27.6), "lechuza": (25.8, 112.6), "benteveo": (70.0, 14.4), "bigua": (203.5, 138.2)}
# Juan Salvo: off the map at the head of Avenida de Mayo until his time, then he walks in to the square's west edge
SALVO_FROM, SALVO_TO, SALVO_AT = (1.5, 86.0), (44.0, 86.0), 30.0
# The cascarudos: when each comes (the first a quarter of a minute in, before Juan Salvo), from which avenue (the edge
# of the map), and its first spot in the square
CASCARUDOS = [
    ("c1", 15.0, (278.5, 34.0), (226.0, 48.0), "A cascarudo comes along Rivadavia from the east, as big as a car."),
    ("c2", 75.0, (278.5, 139.0), (232.0, 118.0), "Another cascarudo comes up Hipólito Yrigoyen from the east."),
    ("c3", 160.0, (1.5, 89.0), (52.0, 88.0), "A third cascarudo comes in off Avenida de Mayo."),
]

obstacles = [
    # north of Rivadavia: the corner block, the Catedral (its wings either side of the portico), the block between San
    # Martín and Reconquista, the Banco Nación round its porch, the block north of the Casa Rosada
    rect("north-w", 0.0, 0.0, CATEDRAL[0], RIVADAVIA[0], "building"),
    rect("catedral", *CATEDRAL, "building", label="CATEDRAL"),
    # (the ends of the portico beyond its outer columns: the stylobate stands 1.6 m sheer there)
    rect("catedral-wing-w", CAT_X[0], PORTICO[1], COLUMN_X[0] - COLUMN_HALF, PORTICO[3], "building"),
    rect("catedral-wing-e", COLUMN_X[-1] + COLUMN_HALF, PORTICO[1], CAT_X[1], PORTICO[3], "building"),
    *[rect("column-%d" % i, x - COLUMN_HALF, COLUMNS_Z[0], x + COLUMN_HALF, COLUMNS_Z[1], "column") for i, x in enumerate(COLUMN_X)],
    rect("north-mid", SAN_MARTIN[1], 0.0, RECONQUISTA[0], RIVADAVIA[0], "building"),
    rect("banco-w", BANCO[0], 0.0, BANCO_PORCH[0], RIVADAVIA[0], "building", label="BANCO DE LA NACIÓN"),
    rect("banco-n", BANCO_PORCH[0], 0.0, BANCO_PORCH[2], BANCO_PORCH[1], "building"),
    rect("banco-e", BANCO_PORCH[2], 0.0, BANCO[2], RIVADAVIA[0], "building"),
    *[rect("banco-column-%d" % i, x - 1.0, BANCO_COLUMN_Z - 1.0, x + 1.0, BANCO_COLUMN_Z + 0.95, "column") for i, x in enumerate(BANCO_COLUMNS)],
    rect("north-e", BALCARCE[1], 0.0, W, RIVADAVIA[0], "building"),
    # west of Bolívar: the Palacio Municipal, the Cabildo (the arcade's piers in front of it), the corner south of it
    rect("municipal", *MUNICIPAL, "building", label="PALACIO MUNICIPAL"),
    rect("cabildo", *CABILDO, "building", label="CABILDO"),
    *[rect("pier-%d" % i, ARCADE[2] - ARCADE_FRONT, lo, ARCADE[2], hi, "pier") for i, (lo, hi) in enumerate(PIER_SPANS)],
    rect("arcade-n", ARCADE[0], ARCADE[1], ARCADE[2], ARCADE[1] + 0.4, "wall"),
    rect("arcade-s", ARCADE[0], ARCADE[3] - 0.4, ARCADE[2], ARCADE[3], "wall"),
    rect("south-w", 0.0, 128.0, BOLIVAR[0], H, "building"),
    # east: the Casa Rosada, its gates shut: the wings set back, the pavilions and Tamburini's block standing out, the
    # pedestals of its columns on the pavement
    rect("casa-rosada", CASA_ROSADA[0] + 2.4, CASA_ROSADA[1], CASA_ROSADA[2], CASA_ROSADA[3], "building", label="CASA ROSADA"),
    rect("rosada-pavilion-n", CASA_ROSADA[0] + 1.2, CASA_ROSADA[1], CASA_ROSADA[0] + 2.4, CASA_ROSADA[1] + ROSADA_PAVILION, "building"),
    rect("rosada-pavilion-s", CASA_ROSADA[0] + 1.2, CASA_ROSADA[3] - ROSADA_PAVILION, CASA_ROSADA[0] + 2.4, CASA_ROSADA[3], "building"),
    rect("rosada-centre", CASA_ROSADA[0], ROSADA_CENTRE[0], CASA_ROSADA[0] + 2.4, ROSADA_CENTRE[1], "building"),
    *[rect("rosada-columns-%d" % i, CASA_ROSADA[0] - 1.4, a, CASA_ROSADA[0], b, "column") for i, (a, b) in enumerate(ROSADA_PEDESTALS)],
    # south of Hipólito Yrigoyen: the ministries either side of Defensa, the block beyond Balcarce
    rect("ministry-w", *MINISTRY_W, "building", label="MINISTERIO"),
    rect("ministry-e", *MINISTRY_E, "building", label="MINISTERIO DE HACIENDA"),
    rect("south-e", BALCARCE[1], 146.0, W, H, "building"),
    # in the square: the Pirámide's railing, the Belgrano monument, the flagpole, the palms, the lamps
    rect("piramide", PIRAMIDE[0] - PIRAMIDE_FENCE, PIRAMIDE[1] - PIRAMIDE_FENCE, PIRAMIDE[0] + PIRAMIDE_FENCE, PIRAMIDE[1] + PIRAMIDE_FENCE, "monument", label="PIRÁMIDE DE MAYO"),
    rect("belgrano", BELGRANO[0] - BELGRANO_BASE[0], BELGRANO[1] - BELGRANO_BASE[1], BELGRANO[0] + BELGRANO_BASE[0], BELGRANO[1] + BELGRANO_BASE[1], "monument", label="BELGRANO"),
    rect("flagpole", FLAGPOLE[0] - FLAGPOLE_BASE, FLAGPOLE[1] - FLAGPOLE_BASE, FLAGPOLE[0] + FLAGPOLE_BASE, FLAGPOLE[1] + FLAGPOLE_BASE, "post", see_through=True),
    *[rect("palm-%d" % i, x - 0.8, z - 0.8, x + 0.8, z + 0.8, "post", see_through=True) for i, (x, z) in enumerate(PALMS)],
    *[rect("lamp-%d" % i, x - 0.42, z - 0.42, x + 0.42, z + 0.42, "post", see_through=True) for i, (x, z) in enumerate(LAMPS)],
    # the benches by the walks, the cars parked at the kerbs
    *[rect("bench-%d" % i, *((x - 1.0, z - 0.4, x + 1.0, z + 0.4) if f in (0, 180) else (x - 0.4, z - 1.0, x + 0.4, z + 1.0)), "bench", see_through=True)
      for i, (x, z, f) in enumerate(BENCHES)],
    *[rect("car-%d" % i, *((x - CAR_SIZE[k][1] / 2, z - CAR_SIZE[k][0] / 2, x + CAR_SIZE[k][1] / 2, z + CAR_SIZE[k][0] / 2) if h in (0, 180)
                            else (x - CAR_SIZE[k][0] / 2, z - CAR_SIZE[k][1] / 2, x + CAR_SIZE[k][0] / 2, z + CAR_SIZE[k][1] / 2)), "car", see_through=True)
      for i, (x, z, h, k) in enumerate(PARKED)],
    # the subte's stairs: railings round three sides of each, open at the head (the service stair's head is its gate)
    rect("subte-n-rail-n", SUBTE_N[0], SUBTE_N[1] - 0.3, SUBTE_N[2], SUBTE_N[1], "rail", see_through=True),
    rect("subte-n-rail-s", SUBTE_N[0], SUBTE_N[3], SUBTE_N[2], SUBTE_N[3] + 0.3, "rail", see_through=True),
    rect("subte-n-rail-w", SUBTE_N[0] - 0.3, SUBTE_N[1] - 0.3, SUBTE_N[0], SUBTE_N[3] + 0.3, "rail", see_through=True),
    rect("subte-s-rail-n", SUBTE_S[0], SUBTE_S[1] - 0.3, SUBTE_S[2], SUBTE_S[1], "rail", see_through=True),
    rect("subte-s-rail-s", SUBTE_S[0], SUBTE_S[3], SUBTE_S[2], SUBTE_S[3] + 0.3, "rail", see_through=True),
    rect("subte-s-rail-w", SUBTE_S[0] - 0.3, SUBTE_S[1] - 0.3, SUBTE_S[0], SUBTE_S[3] + 0.3, "rail", see_through=True),
    rect("service-rail-n", SUBTE_SERVICE[0], SUBTE_SERVICE[1] - 0.3, SERVICE_GATE[1], SUBTE_SERVICE[1], "rail", see_through=True),
    rect("service-rail-s", SUBTE_SERVICE[0], SUBTE_SERVICE[3], SERVICE_GATE[1], SUBTE_SERVICE[3] + 0.3, "rail", see_through=True),
    rect("service-rail-w", SUBTE_SERVICE[0] - 0.3, SUBTE_SERVICE[1] - 0.3, SUBTE_SERVICE[0], SUBTE_SERVICE[3] + 0.3, "rail", see_through=True),
    # the newspaper kiosk on Rivadavia, the vendor's cart on Yrigoyen
    rect("kiosk", *KIOSK, "kiosk"),
    rect("cart", *CART, "cart", see_through=True),
]


def opening(id, kind, x0, z0, x1, z1, anchor, **spec):
    d = {"id": id, "kind": kind, "x": u(x0), "y": u(z0), "w": u(x1) - u(x0), "h": u(z1) - u(z0), "anchor": anchor,
         "closed": "wall", "checkpoint": True, "slow": 1.0, "radius": 34}
    d.update(spec)
    return d


passages = [
    # Lechuza's two jobs. The arcade's lamps: the fuse box on the Cabildo's wall inside the arcade (the passage's
    # rectangle lies inside the wall, so opening it changes nobody's way); with the light back, people will go in.
    opening("cabildo-lights", "lights", ARCADE[0] - 0.6, 112.0, ARCADE[0], 113.0, pt(ARCADE[0] + 1.0, 112.5),
            closed="building", by=["lechuza"], time=4.0, objective="lights",
            label="Arcade lights", verb="Restore the lights", icon="lampkey", kit="his sector key and a pocket of fuses",
            order="%s will open the fuse box on the Cabildo's wall and put the arcade's lights back.",
            done="The arcade's lamps come on. Now people will go in under the arches.",
            refuse="Only Lechuza knows that fuse box.",
            already="The arcade's lamps are already on.",
            unreachable="%s cannot get to the fuse box from here."),
    # the gate across the head of the subte's service stair, at the square's south-west corner
    opening("subte-gate", "service", SERVICE_GATE[0], SUBTE_SERVICE[1], SERVICE_GATE[1], SUBTE_SERVICE[3], pt(SERVICE_GATE[1] + 1.0, 129.5),
            closed="wall", by=["lechuza"], time=3.0, objective="gate",
            label="Service gate", verb="Open the gate", icon="key", kit="",
            order="%s will open the service gate. The subte's locks take the power company's key.",
            done="The service gate is open: a stair down into the subte, close to the south-west corner.",
            refuse="Lechuza has the key to the subte's service gate.",
            already="The service gate is already open.",
            unreachable="%s cannot get to the service gate from here."),
]

# Shelter: where the snow cannot reach. A person who walks into one is saved; anyone in one gets his warmth back.
# "dark": a passage that has to be opened first before people will go in (the arcade, until its lamps are back);
# "vehicle": a shelter that is a vehicle and goes where it goes; "inside": where people make for once in.
shelters = [
    {"id": "catedral", "label": "Catedral", "kind": "portico", "x": u(PORTICO[0]), "y": u(PORTICO[1]),
     "w": u(PORTICO[2]) - u(PORTICO[0]), "h": u(COLUMNS_Z[0]) - u(PORTICO[1]), "inside": pt(70.0, 13.4)},
    {"id": "cabildo", "label": "Cabildo", "kind": "arcade", "x": u(ARCADE[0]), "y": u(ARCADE[1] + 0.4),
     "w": u(ARCADE[2] - ARCADE_FRONT) - u(ARCADE[0]), "h": u(ARCADE[3] - 0.4) - u(ARCADE[1] + 0.4), "inside": pt(ARCADE[0] + 1.3, 113.0), "dark": "cabildo-lights"},
    {"id": "subte-n", "label": "Subte", "kind": "subte", "x": u(SUBTE_N[0]), "y": u(SUBTE_N[1]),
     "w": u(SUBTE_N[2]) - u(SUBTE_N[0]), "h": u(SUBTE_N[3]) - u(SUBTE_N[1]), "inside": pt(7.0, 74.5)},
    {"id": "subte-s", "label": "Subte", "kind": "subte", "x": u(SUBTE_S[0]), "y": u(SUBTE_S[1]),
     "w": u(SUBTE_S[2]) - u(SUBTE_S[0]), "h": u(SUBTE_S[3]) - u(SUBTE_S[1]), "inside": pt(7.0, 97.5)},
    {"id": "subte-service", "label": "Service stair", "kind": "subte", "x": u(SUBTE_SERVICE[0]), "y": u(SUBTE_SERVICE[1]),
     "w": u(SERVICE_GATE[0]) - u(SUBTE_SERVICE[0]), "h": u(SUBTE_SERVICE[3]) - u(SUBTE_SERVICE[1]), "inside": pt(44.0, 129.5)},
    {"id": "banco", "label": "Banco Nación", "kind": "porch", "x": u(BANCO_PORCH[0]), "y": u(BANCO_PORCH[1]),
     "w": u(BANCO_PORCH[2]) - u(BANCO_PORCH[0]), "h": u(BANCO_PORCH[3] - 0.6) - u(BANCO_PORCH[1]), "inside": pt(215.0, 19.0)},
    {"id": "tram", "label": "Tram", "kind": "tram", "vehicle": "tram"},
    {"id": "colectivo", "label": "Colectivo", "kind": "bus", "vehicle": "colectivo"},
]

vehicles = [
    # the tram stopped on Rivadavia's north track: Hornero can take it on along the rails to the next stop, east or back
    # west, slowly, on what current the wire still carries; everyone aboard goes with it
    {"id": "tram", "label": "Tram", "kind": "tram", "x": u(TRAM_STOPS[0]), "y": u(TRAM_Z - TRAM_W / 2), "w": u(TRAM_LEN), "h": u(TRAM_W),
     "stops": [u(x) for x in TRAM_STOPS], "speed": 46.0, "by": ["hornero"], "time": 1.2, "icon": "tram", "verb": "Drive the tram",
     "order": "%s takes the controller and coaxes the tram along the rails to the next stop.",
     "done": "The tram stops. Everyone aboard came with it.",
     "moving": "The tram is already moving.",
     "refuse": "Only Hornero can drive the tram.",
     "unreachable": "%s cannot get to the tram from here."},
    # the colectivo stranded on Hipólito Yrigoyen, its doors open: it goes nowhere
    {"id": "colectivo", "label": "Colectivo", "kind": "bus", "x": u(COLECTIVO[0]), "y": u(COLECTIVO[1]),
     "w": u(COLECTIVO[2]) - u(COLECTIVO[0]), "h": u(COLECTIVO[3]) - u(COLECTIVO[1])},
]

# Cloths to hold over people for one crossing: taken, they keep the snow off whoever carries one and the few closest
# behind him until he is under cover again (or the cloth is soaked through).
canvases = [
    {"id": "awning", "label": "Awning", "kind": "awning", "x": u(AWNING[0]), "y": u(AWNING[1]), "time": 50.0, "holds": 3,
     "order": "%s goes for the café's awning.",
     "take": "%s pulls the café's awning cloth down off its frame. It will keep the snow off a few, for one crossing."},
    {"id": "tarpaulin", "label": "Tarpaulin", "kind": "tarpaulin", "x": u((KIOSK[0] + KIOSK[2]) / 2), "y": u(KIOSK[3] + 1.0), "time": 50.0, "holds": 3,
     "order": "%s goes for the kiosk's tarpaulin.",
     "take": "%s pulls the tarpaulin off the newspaper kiosk. It will keep the snow off a few, for one crossing."},
    {"id": "cart-cover", "label": "Cart cover", "kind": "tarpaulin", "x": u((CART[0] + CART[2]) / 2), "y": u(CART[1] - 1.0), "time": 50.0, "holds": 3,
     "order": "%s goes for the cover on the cart.",
     "take": "%s drags the cover off the vendor's cart. It will keep the snow off a few, for one crossing."},
]

# The people in the square: who, where, how chilled they are already, and the few who run off when a wave comes.
# "flee": where a person runs in a panic (into the open, to the Casa Rosada's shut gates or the Pirámide's railing);
# "panic": {at}: a time at which he runs there of his own accord if nobody has him yet.
LOOKS = ["vecino0", "vecina0", "vecino1", "vecina1", "vecino2", "vecino3", "vecina2", "vecino4", "vecina3", "vecino5"]
GROUPS = [
    # group, [(x, z, facing, exposure, extra)]
    ("piramide-w", [(124.0, 80.0, 30, 0.10, {}), (125.6, 83.2, 0, 0.18, {}), (123.4, 85.8, 340, 0.06, {}),
                    (126.8, 87.4, 300, 0.22, {"panic": {"at": 236.0}, "flee": pt(142.0, 92.0)})]),
    ("piramide-e", [(152.0, 81.0, 180, 0.12, {}), (153.6, 84.6, 200, 0.24, {"panic": {"at": 94.0}, "flee": pt(250.0, 86.0)}),
                    (151.0, 87.6, 160, 0.08, {})]),
    ("palms-n", [(150.0, 58.0, 90, 0.20, {}), (152.6, 59.6, 120, 0.05, {}), (148.0, 61.2, 60, 0.15, {})]),
    ("flag", [(195.0, 63.0, 270, 0.12, {}), (197.6, 61.6, 240, 0.28, {}),
              (198.4, 65.4, 280, 0.10, {"panic": {"at": 96.0}, "flee": pt(250.0, 74.0)})]),
    ("belgrano", [(216.0, 98.0, 0, 0.18, {}), (219.0, 100.0, 330, 0.08, {}), (214.4, 101.2, 20, 0.26, {})]),
    ("rosada", [(237.0, 112.0, 0, 0.30, {}), (238.6, 108.8, 20, 0.14, {})]),
    ("sw", [(72.0, 114.0, 200, 0.16, {}), (69.4, 116.2, 160, 0.06, {}), (74.2, 117.6, 220, 0.22, {})]),
    ("nw", [(66.0, 50.0, 90, 0.10, {}), (68.6, 48.0, 120, 0.20, {}), (63.4, 52.2, 60, 0.04, {})]),
    ("south", [(114.0, 118.0, 270, 0.14, {}), (116.6, 120.2, 300, 0.26, {})]),
]
people = []
n = 0
for group, members in GROUPS:
    for (x, z, facing, chill, extra) in members:
        n += 1
        p = {"id": "p%d" % n, "group": group, "x": u(x), "y": u(z), "facing": facing, "exposure": chill,
             "look": LOOKS[(n * 3) % len(LOOKS)]}
        p.update(extra)
        people.append(p)

# How the snow falls: [seconds, strength] (1 = steady; waves near 2, lulls near 0.4); exposure fills in `rate` seconds
# of steady snow (squad / people), drains in `recover` seconds under cover; a person or an operative who has fallen
# can still be brought in for `grace` seconds; at `bury` the snow buries the square and whoever is out in it.
SCHEDULE = [[0.0, 0.3], [20.0, 0.6], [45.0, 1.0], [75.0, 1.0], [92.0, 1.8], [112.0, 1.8], [126.0, 0.35], [168.0, 0.4],
            [186.0, 1.1], [222.0, 1.2], [238.0, 2.0], [262.0, 2.0], [276.0, 0.45], [324.0, 0.6], [345.0, 1.3],
            [372.0, 2.2], [392.0, 2.2], [404.0, 0.8], [430.0, 1.4], [462.0, 2.6], [480.0, 3.2]]
BURY = 480.0

data = {
    "_source": "Generated by tools/dev/plaza_layout.py - edit that, not this file.",
    "id": "plaza-05",
    "progressKey": "plaza",
    "title": "Plaza de Mayo",
    "subtitle": "Buenos Aires · a winter night, 1958 · 21:10",
    "theme": "plaza",
    "worldName": "Plaza de Mayo",
    "width": u(W), "height": u(H), "cellSize": 32,
    "parTime": 330,
    # (zoomMax: as far out as the game's camera goes before the ground leaves the bottom of the view; the title
    # drifts across the square looking east, the Casa Rosada at the back; the first view of the night (begin) looks
    # east-north-east over the square from the south-west: Hornero's tram on Rivadavia on the left, the palms and the
    # Pirámide de Mayo on the right with the first groups out in the snow, so it reads as the Plaza de Mayo at once)
    "camera": {"min": [2.0, 2.0], "max": [W - 2.0, H - 2.0], "start": [140.0, 70.0], "zoom": 34.0, "zoomMax": 140.0,
               "title": {"from": [232.0, 76.0], "to": [238.0, 96.0], "zoom": 62.0, "yaw": -70.0},
               "begin": {"at": [126.5, 54.0], "zoom": 54.0, "yaw": -45.0}},
    "briefingMessage": "The snow is falling on the square, and it kills whoever it touches. Watch the waves, and bring the people in under cover.",
    "startMessage": "Tap someone out in the snow to lead them in: the Catedral's portico, the Cabildo's arcade, the subte, the tram, the colectivo. Lead in the lulls; the waves are coming.",
    "winMessage": "The square is white and empty. Under the arches, on the stairs and in the tram, the ones you brought in are still breathing.",
    "people": people,
    "shelters": shelters,
    "vehicles": vehicles,
    "canvases": canvases,
    "snowfall": {
        "schedule": SCHEDULE, "bury": BURY,
        "rate": {"unit": 75.0, "person": 300.0}, "recover": 28.0,
        "grace": {"unit": 45.0, "person": 40.0},
        "panic": 1.6, "panicExposure": 0.55, "warn": 12.0, "heavy": 1.5, "lull": 0.6,
        "need": 18,
        "lead": 4, "follow": 22.0, "speed": 62.0, "run": 96.0, "helpTime": 1.5, "guideTime": 0.6, "canvasTime": 1.0,
        "fell": "Someone has fallen in the snow. Biguá or Juan Salvo can still carry them in.",
        "carry": "Only Biguá and Juan Salvo can carry them in.",
        "fallenRefuse": "They have fallen. Only Biguá or Juan Salvo can carry them in now.",
        "upAgain": "%s gets to his feet again.", "suitUp": 8.0,
        "fellUnit": "%s has fallen in the snow. Get to him before it covers him.",
        "buried": "The snow has covered someone.",
        "buriedUnit": "The snow has covered %s. He is gone.",
        "savedCount": "Under cover: %d of %d.",
        "panicked": "Someone panics and runs off into the snow.",
        "dark": "The arcade is dark. People will not go in until the lights are back.",
        "lostAll": "The snow has taken the whole squad.",
        "tooFew": "The snow has buried the square, and too few were brought in.",
        "lostTooMany": "Too many have been lost to the snow.",
        "wave": "A heavy wave of snow is coming.",
        "lullNow": "A lull. Bring them in now.",
    },
    "objectives": [
        {"id": "people", "text": "Get everyone under cover"},
        {"id": "shelter", "text": "The squad under cover when the square is buried"},
        {"id": "lights", "text": "Put the arcade's lights back", "optional": True},
        {"id": "gate", "text": "Open the subte's service gate", "optional": True},
    ],
    "medals": [
        {"id": "everyone", "art": "clean_hands", "label": "Nobody left out", "text": "Everyone in the square was brought in", "rule": "everyone"},
        {"id": "all_four", "art": "rescue", "label": "The whole squad", "text": "None of the squad was lost", "rule": "squad"},
        {"id": "swift", "art": "swift", "label": "Swift", "text": "Done in under %d:%02d", "rule": "time"},
    ],
    "units": [
        # Hornero (Aldo Ferrante): tram motorman, the leader. At the controls of the tram that stopped on Rivadavia: he
        # can take it on along the rails, and ring its hand bell to call people to it.
        {"id": "hornero", "name": "Hornero", "role": "Motorman", "x": u(START["hornero"][0]), "y": u(START["hornero"][1]), "color": "#d9a066",
         "ability": "Tram", "stance": "walk", "lead": 4,
         "call": {"label": "Bell", "mode": "come", "from": "tram", "radius": u(40.0), "count": 4, "cooldown": 18.0, "noise": "bell", "icon": "bell",
                  "kit": "the tram's hand bell",
                  "done": "The tram's bell clangs across the square. %d come running for the tram.",
                  "none": "The bell clangs. Nobody near enough heard it.",
                  "empty": "%s has rung the bell enough. They have heard it.",
                  "away": "%s has to be in the tram to ring its bell."}},
        # Lechuza (Ernesto Saravia): the power company's night lineman, under the Cabildo's arcade when its lamps failed.
        {"id": "lechuza", "name": "Lechuza", "role": "Lineman", "x": u(START["lechuza"][0]), "y": u(START["lechuza"][1]), "color": "#b6c3d9",
         "ability": "Lights", "stance": "walk", "lead": 4},
        # Benteveo ("Tito" Gaudino): the canillita, sixteen, selling the Sexta on the Catedral's steps. The voice that
        # sells the evening paper carries across a square: everyone near him follows him at once.
        {"id": "benteveo", "name": "Benteveo", "role": "Newsboy", "x": u(START["benteveo"][0]), "y": u(START["benteveo"][1]), "color": "#e6d36f",
         "ability": "Voice", "stance": "walk", "lead": 8,
         "call": {"label": "Rally", "mode": "follow", "radius": u(12.0), "count": -1, "cooldown": 12.0, "noise": "voice", "icon": "talk",
                  "kit": "the voice that sells the Sexta",
                  "done": "Benteveo shouts them over like he shouts the Sexta. %d follow him.",
                  "none": "He shouts, but nobody near enough needs him.",
                  "full": "%s cannot lead any more at once."}},
        # Biguá (Cosme Ledesma): the botero, on his way home to La Boca on the colectivo. Strong enough to carry a fallen
        # man in on his shoulders.
        {"id": "bigua", "name": "Biguá", "role": "Boatman", "x": u(START["bigua"][0]), "y": u(START["bigua"][1]), "color": "#7fb3a8",
         "ability": "Carry", "stance": "walk", "lead": 4, "carries": True},
        # Juan Salvo: comes in off Avenida de Mayo early in the night, sealed in an insulating suit that keeps the snow
        # off him (no cold, wave or no wave), strong enough to carry the fallen in, with a rifle and few rounds. His look
        # is the art pack's licensed slot (a neutral stand-in until its files come); he leads only two at a time.
        {"id": "salvo", "name": "Juan Salvo", "role": "Neighbour", "x": u(SALVO_FROM[0]), "y": u(SALVO_FROM[1]), "color": "#a9b6bc",
         "ability": "Suit", "stance": "walk", "lead": 2, "carries": True, "suit": True, "look": "art:juan_salvo",
         "arrive": {"at": SALVO_AT, "to": pt(*SALVO_TO), "checkpoint": True,
                    "text": "Juan Salvo comes in off Avenida de Mayo in his insulating suit. The snow does not touch him.",
                    "notYet": "%s is not here yet."},
         "gun": {"label": "Rifle", "ammo": 6, "range": u(30.0), "aim": 0.8, "recover": 2.0, "loud": True, "noise": u(95.0), "sound": "rifle",
                 "icon": "target", "kit": "a rifle and six rounds",
                 "prompt": "Loud: every cascarudo hears it. Tap a marked one.",
                 "promptNone": "No cascarudo in range and in sight. Tap away to lower it."}},
    ],
    # The cascarudos: they come up the avenues from the first minute and go for whoever is out in the open. Their look
    # is the art pack's licensed slot (a plain grey block with its plate until the files come). Numbers in sim units and
    # seconds: their walk, their rush at someone within `sense`, their run when driven off; how close they knock someone
    # down; how wide they are to the ground (they keep out of every shelter and vehicle); how long they stand over the
    # one they knocked down; hits to kill one; how long one driven off stays away; how long one drawn by a noise stays
    # by it; how far each noise is heard; where they wander when nobody is out (the square).
    "creatures": {
        "look": "art:cascarudo", "title": "CASCARUDO",
        "speed": 40.0, "charge": 70.0, "flee": 110.0, "sense": u(20.0), "reach": u(2.8), "radius": 56.0,
        "pause": 3.5, "hits": 3, "away": 35.0, "linger": 7.0, "think": 0.5,
        "hear": {"bell": u(80.0), "voice": u(16.0), "rifle": u(120.0)},
        "roam": [u(PLAZA[0] + 2.0), u(PLAZA[1] + 2.0), u(PLAZA[2] - PLAZA[0] - 4.0), u(PLAZA[3] - PLAZA[1] - 4.0)],
        "arrivals": [{"id": cid, "at": at, "from": pt(*a), "to": pt(*b), "text": text} for (cid, at, a, b, text) in CASCARUDOS],
        "arrive": "A cascarudo comes into the square.",
        "back": "A cascarudo is back in the square.",
        "strike": "A cascarudo has knocked someone down in the snow. Carry them in before it covers them.",
        "strikeUnit": "A cascarudo has knocked %s down in the snow.",
        "driven": "Hit, the cascarudo turns and makes off the way it came.",
        "killed": "%s's shot brings the cascarudo down. It does not get up again.",
        "missed": "%s fires, and misses.",
        "unarmed": "%s has nothing to fight it with. Keep away from it.",
        "noTarget": "There is nothing there to shoot.",
        "shootLabel": "Shoot",
        "drawnBy": {"bell": "The bell draws the cascarudos to the tram.", "rifle": "The shot draws the other cascarudos.",
                    "voice": "The shout draws a cascarudo."},
    },
    "obstacles": obstacles,
    "passages": passages,
    "bushes": [],
    "guards": [],
    "snow": {
        "tracks": True, "ttl": 60.0, "spacing": 24.0,
        # the streets' setts and the walks are trodden to slush already; the lawns take prints
        "packed": [box(0.0, RIVADAVIA[0], W, RIVADAVIA[1]), box(0.0, YRIGOYEN[0], W, YRIGOYEN[1]), box(BOLIVAR[0], 0.0, BOLIVAR[1], H),
                   box(BALCARCE[0], 0.0, BALCARCE[1], H), box(0.0, AV_MAYO[0], BOLIVAR[0], AV_MAYO[1])],
        "indoors": [box(*PORTICO), box(*ARCADE), box(*SUBTE_N), box(*SUBTE_S), box(*SUBTE_SERVICE), box(*BANCO_PORCH)],
        "seen": "",
    },
    "tracks": [[pt(0.0, TRACKS_Z[0]), pt(W, TRACKS_Z[0])], [pt(0.0, TRACKS_Z[1]), pt(W, TRACKS_Z[1])]],
    # the 3D builder's layout (metres), from the same lines as the rules above
    "plazaWorld": {
        "rivadavia": list(RIVADAVIA), "rivRoad": list(RIV_ROAD), "tracksZ": list(TRACKS_Z), "plaza": list(PLAZA),
        "yrigoyen": list(YRIGOYEN), "yriRoad": list(YRI_ROAD), "bolivar": list(BOLIVAR), "bolRoad": list(BOL_ROAD),
        "balcarce": list(BALCARCE), "balRoad": list(BAL_ROAD), "avMayo": list(AV_MAYO), "avmRoad": list(AVM_ROAD),
        "sanMartin": list(SAN_MARTIN), "reconquista": list(RECONQUISTA), "defensa": list(DEFENSA),
        "catedral": list(CATEDRAL_KIT), "portico": list(PORTICO), "columnsZ": list(COLUMNS_Z), "columnX": COLUMN_X,
        "stylobate": STYLOBATE, "banco": list(BANCO), "bancoPorch": list(BANCO_PORCH), "municipal": list(MUNICIPAL),
        "cabildo": list(CABILDO_KIT), "arcade": list(ARCADE), "archPiers": ARCH_PIERS, "casaRosada": list(CASA_ROSADA),
        "rosadaArch": list(ROSADA_ARCH), "parked": [list(c) for c in PARKED], "benches": [list(b) for b in BENCHES],
        "ministryW": list(MINISTRY_W), "ministryE": list(MINISTRY_E), "piramide": list(PIRAMIDE), "piramideFence": PIRAMIDE_FENCE,
        "belgrano": list(BELGRANO), "flagpole": list(FLAGPOLE), "palms": [list(p) for p in PALMS], "lamps": [list(p) for p in LAMPS],
        "subteN": list(SUBTE_N), "subteS": list(SUBTE_S), "subteService": list(SUBTE_SERVICE), "serviceGate": list(SERVICE_GATE),
        "tramStops": TRAM_STOPS, "tramZ": TRAM_Z, "tramLen": TRAM_LEN, "tramW": TRAM_W, "colectivo": list(COLECTIVO),
        "kiosk": list(KIOSK), "cart": list(CART), "awning": list(AWNING), "start": {k: list(v) for k, v in START.items()},
        "stairDepth": STAIR_DEPTH,
    },
    "ambience": {
        "water": "amb_wind", "hum": "amb_transformer", "electric": True, "windDb": 1.0,
        "waterRects": [], "falloff": 14.0,
        "humAt": [[105.0, 27.5]], "radioIsPower": False,
        "every": [16.0, 34.0],
        "calls": [{"cue": "clank", "weight": 1, "at": [pt(105.0, 27.5), pt(203.0, 138.0)]}],
    },
    "history": [
        {"title": "PLAZA\nDE MAYO",
         "body": "The square is bounded by Rivadavia, Bolívar, Hipólito Yrigoyen and Balcarce, and three avenues leave its west side: Avenida de Mayo and the two diagonals. The arcade of the old Recova that once crossed it was pulled down in 1883, and the modern square was laid out the next year. Round it stand the Casa Rosada, the Cabildo, the Catedral, the Palacio Municipal and the Banco de la Nación; under it run the subte's Plaza de Mayo, Catedral and Bolívar stations.\n\nThe Casa Rosada is pink, and nobody agrees why: some say Sarmiento chose it to mix the Federalists' red with the Unitarians' white, others that the paint was mixed with cow's blood against the damp. Tamburini's central arch, finished in 1898, joined two older buildings into one.",
         "foot": "The night of the snow is made up. The square is not."},
        {"title": "THE\nPIRÁMIDE",
         "body": "The Pirámide de Mayo is the oldest monument in the city, raised in 1811 for the first anniversary of the May Revolution. Prilidiano Pueyrredón rebuilt it larger in 1856 over the old core, with the national arms on all four sides of its base. It is 18.76 metres to the tip of the cap of its Liberty, who is 3.6 metres tall. A golden sun faces the Casa Rosada; laurel crowns are on the other three faces.\n\nIn November 1912 it was moved some 63 metres east, on rails, to the middle of the square. Its four corner statues were taken away that year and only came back in 2018, so in 1958 it stood without them. The eight Canary palms round it were planted between 1900 and 1904.",
         "foot": "In 1958 the Pirámide had no statues at its corners."},
        {"title": "THE\nCABILDO",
         "body": "The Cabildo was the town hall of colonial Buenos Aires, and the May Revolution of 1810 was argued under its roof. The city kept cutting it back: three of its northern arches went in 1889 to open Avenida de Mayo, and its tall tower with them; three more went from the south end in 1931. Only five of the original arches were left.\n\nIn 1939 and 1940 the architect Mario Buschiazzo restored what remained: the tower was rebuilt, the red colonial roof tiles put back, with iron bars on the windows and wooden doors and shutters made after the old ones. The Cabildo of 1958, with its five arches, is that one.",
         "foot": "The arcade's fuse box is made up."},
        {"title": "THE\nSUBTE",
         "body": "The first underground railway in Latin America, and in the southern hemisphere, opened under Avenida de Mayo on 1 December 1913, from Plaza de Mayo to Plaza Miserere. It was the Anglo-Argentina's Línea A, and its wooden cars ran for nearly a hundred years. Its first station lies under the head of the avenue, at the square.\n\nThe trams that ran on Rivadavia in 1958 were nearly at their end: the network was renewed between 1955 and 1961, and then broken up. The last trams in the city ran in February 1963.",
         "foot": "The service stair at the corner of the square is made up."},
        {"title": "THE\nSNOW",
         "body": "Snow almost never falls on Buenos Aires. On 22 June 1918 it began in the afternoon and came again, heavier, at night; people poured out to see it, and there were crowds in the Plaza de Mayo, a snowball fight in the Plaza del Congreso, shop clerks out on the pavements. A photograph of that day shows the Plaza de Mayo white. Six people died of the cold, among them people sleeping in the street.\n\nIt snowed again on 9 July 2007, for the first time in 89 years, and again whole families went out to watch it fall. No snow fell in 1958.",
         "foot": "This snow is not that snow."},
        {"title": "THE\nCOMIC",
         "body": "The comic by Héctor Germán Oesterheld and Francisco Solano López, which began to appear in Hora Cero Semanal in 1957, on 4 September, brings down on Buenos Aires a luminous snow that kills whatever it touches, and a handful of neighbours band together to live through it. It ran in 106 weekly instalments into 1959: on a winter night in 1958 it was at the kiosks.\n\nThis prologue borrows its snowfall for one night in the Plaza de Mayo and, with its rights holders' permission, its Juan Salvo and its cascarudos. The four neighbours from La Boca and everyone in the square are the game's own.",
         "foot": "A private preview, made to be shown to the comic's rights holders."},
    ],
    "copy": {
        "wonTitle": "UNDER\nCOVER",
        "title": "PLAZA\nDE MAYO",
        "briefing": "Buenos Aires, a winter night in 1958, and for the first time in forty years it is snowing. Half the city has come to the Plaza de Mayo to see it. Within minutes the ones who stay out in it begin to fall: the snow kills whoever it touches. Four neighbours from La Boca happened to be under cover when it began: Hornero at the controls of a tram stopped on Rivadavia, Lechuza under the Cabildo's arcade, Benteveo selling the Sexta on the Catedral's steps, Biguá on a colectivo stranded on Hipólito Yrigoyen. Early in the night Juan Salvo comes in off Avenida de Mayo, sealed in an insulating suit: the snow cannot touch him, he can carry in whoever has fallen, and he has a rifle with a few rounds. Soon the cascarudos come up the avenues, each as big as a car, and knock down whoever they find out in the open. They will not go under the arches or the portico, down into the subte or into the tram, and noise draws them. Bring in as many as you can before the snow buries the square. Watch the waves; move in the lulls.",
        "mapTip": "Show the whole square",
        "debrief": "By midnight the square was a field of snow, and the Pirámide stood up out of it like a post in a river. Nobody came out from under the arches that night, or down from the tram. In the subte they listened to the snow through the gratings and waited for the morning, and the five of them counted heads.",
        "failureNote": "Lose the whole squad, or bring in too few before the snow buries the square, and it is over. Watch the snow: move in the lulls, wait out the waves under cover, and stop the clock to give orders.",
        "checkpointNote": "Checkpoints are also taken when Juan Salvo comes, when the arcade's lights come on and when the service gate opens.",
        "checkpoints": {"start": "the first flakes", "salvo": "Juan Salvo in the square", "cabildo-lights": "the arcade lit", "subte-gate": "the service gate open"},
        "orderNames": {"guide": "LEAD IN", "call": "CALL", "drive": "DRIVE", "canvas": "TAKE CLOTH", "help": "HELP UP", "rig": "LIGHTS"},
        "objectiveHow": {
            "people": {"benteveo": "Benteveo: rally a group with his voice, then lead them in",
                       "hornero": "Hornero: take the tram along Rivadavia and ring its bell",
                       "bigua": "Biguá: carry in anyone who has fallen",
                       "salvo": "Juan Salvo: cross in a wave and carry in whoever has fallen",
                       "": "Tap a person in the snow to lead them under cover"},
            "shelter": {"": "Everyone under cover before the square is buried"},
            "lights": {"lechuza": "Lechuza: the fuse box on the Cabildo's wall, inside the arcade",
                       "": "Lechuza can put the arcade's lights back"},
            "gate": {"lechuza": "Lechuza: the service stair at the square's south-west corner",
                     "": "Lechuza has the key to the service gate"},
        },
        "hints": {
            "start": "Tap Hornero, Lechuza, Benteveo or Biguá to choose who acts, then tap a person out in the snow: they follow him in. Drag to look around.",
            "exposure": "The ring over each head is the cold. It fills out in the snow, faster in a wave, and empties again under cover. Full, they fall.",
            "waves": "The snow comes in waves. Wait out the heavy ones under cover, and lead people across in the lulls.",
            "shelters": "Under cover: the Catedral's portico, the Cabildo's arcade, the subte's stairs, the bank's porch, the tram and the colectivo.",
            "benteveo": "Benteveo's voice carries: one shout and everyone near him follows him at once.",
            "hornero": "Hornero can take the tram along the Rivadavia tracks, and ring its bell to bring people running to it.",
            "lechuza": "The Cabildo's arcade is dark, and people will not go in. Lechuza can put its lights back at the fuse box.",
            "bigua": "Biguá can carry in anyone who has fallen, if he gets to them before the snow covers them.",
            "fallen": "Someone has fallen. The snow covers the fallen within seconds: send Biguá or Juan Salvo.",
            "salvo": "Juan Salvo's suit keeps the snow off him: he takes no cold, wave or no wave. Send him across the square for whoever has fallen; he carries one at a time.",
            "cascarudos": "A cascarudo goes for whoever is out in the open and knocks them down in the snow. Nobody under cover is in its reach. Keep people away from it, or draw it off.",
            "rifle": "Juan Salvo's rifle has few rounds. A hit drives a cascarudo off for a while, three bring it down, and every shot draws the others to him.",
            "lure": "The tram's bell draws the cascarudos as well as the people. Ring it from a stop away from the ones being brought in.",
            "canvas": "An awning or a tarpaulin keeps the snow off whoever holds it and the few close behind him, for one crossing.",
            "gate": "Lechuza has the key to the subte's service stair at the south-west corner: another way under cover.",
            "panic": "In a heavy wave, people already half frozen panic and break away. Lead them in the lulls.",
            "squad": "One of the squad is down in the snow. Another can help him up, if he gets there in time.",
        },
        "coach": ["start", "exposure", "shelters", "benteveo", "hornero", "lechuza", "waves", "bigua", "salvo", "fallen", "cascarudos", "rifle", "lure",
                  "canvas", "gate", "panic", "squad", "plan"],
        "hintsWhen": {
            "exposure": {"after": 8.0},
            "shelters": {"after": 16.0},
            "benteveo": {"who": "benteveo"},
            "hornero": {"who": "hornero"},
            "lechuza": {"who": "lechuza"},
            "bigua": {"who": "bigua"},
            "waves": {"after": 70.0},
            "salvo": {"after": SALVO_AT + 2.0},
            "cascarudos": {"after": CASCARUDOS[0][1] + 2.0},
            "rifle": {"who": "salvo", "after": CASCARUDOS[0][1] + 3.0},
            "lure": {"who": "hornero", "after": CASCARUDOS[0][1] + 10.0},
            "canvas": {"after": 120.0},
            "gate": {"near": [u(52.0), u(129.5), 600]},
        },
    },
}
# Who wears what: the squad in their own figures (operative.gd knows their ids) with their photos in the portrait atlas.
PORTRAITS = {"hornero": 0, "lechuza": 1, "benteveo": 2, "bigua": 3}
# (Juan Salvo's photo is the art pack's: its slot's portrait when it comes, a plain plate with his name until then)
for unit in data["units"]:
    if unit["id"] in PORTRAITS:
        unit["portrait"] = PORTRAITS[unit["id"]]

out = os.path.join(os.path.dirname(__file__), "..", "..", "godot", "data", "plaza.json")
with open(out, "w") as f:
    json.dump(data, f, indent=1, ensure_ascii=False)
    f.write("\n")
print("wrote", os.path.normpath(out), "-", len(people), "people,", len(obstacles), "obstacles")
