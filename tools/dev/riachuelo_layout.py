#!/usr/bin/env python3
"""Operation Riachuelo: La Boca, Buenos Aires, a snowy winter night in 1958 (an original story, not history).

Writes godot/data/riachuelo.json. Everything is laid out here in metres (x east, z south) and converted to mission
units (32 per metre). The 3D builder for the boca theme (scripts/three_d/boca*.gd) reads the same file, so the
scenery and the rules agree. Edit this script, not the JSON.

The fourth operation, and a new squad of four La Boca neighbours (research_notes/riachuelo_characters.md): Hornero the
tram motorman (the leader), Lechuza the power company's night lineman, Benteveo the canillita who sells the evening
paper (the invented "La Última", its last edition "la Sexta") and Biguá the boatman (his rowboat, the "Santa Lucía").
"The crossing": a passenger hides in the cellar of Café La Bruma on the Vuelta de Rocha; get him out and across the
Riachuelo under the invented Guardia de Emergencia's curfew, on the night it snows and the barrio is out in the
street throwing snowballs.

Map 240 x 150 m. North (inland): a row of tenement houses (conventillos) with the squad's own courtyard, then a
street, then a sunken railway cutting running east-west, crossed by a footbridge in the west and a lit road bridge in
the east; Lechuza can set his lamp ladder down one side and up the other near the courtyard. South of it, four blocks
of houses cut by three streets running down to the river, a cross street and an alley; the Guardia de Emergencia's
post in the north-east block. The café on the corner of the alley and the riverside avenue, its front on a little
square full of people watching the snow; the cellar behind the café room. Along the river the avenue with its tram
rails (a tram standing on them), then the quay, lit by a row of lamps fed from one board on a lamp column; the boat
shed in the west; the transporter bridge's machine house and its gondola landing in the east. The Riachuelo, with a
river launch moored in it sweeping a searchlight over the water and the quay. The far bank: a path along the shore,
sheds, and the lane where friends wait with a cart (the extraction).

Rules used (all existing keys, see docs/GAMEPLAY_API.md): the cellar door is the "door" and the passenger the
"prisoner"; the lamp board is the "radio" (Lechuza's); "floodlit" rectangles marked "powered" go dark when the board
is cut; "passages" for Lechuza's ladder down the cutting, Hornero's gondola (he works its controls) and Biguá's boat
(only he rows it, and whoever he is escorting: "crew"); "snow" footprints; "cover" for Hornero on the tram streets
and Benteveo in the crowds (their "zones" are everywhere else); civilians, some calm from the start ("calm"), and one informer who shouts.
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
    """[x, y, w, h] in mission units, for the plain rectangle lists (snow, floodlights, zones); a trailing flag such as
    "powered" is kept as a fifth element."""
    return [u(x0), u(z0), u(x1) - u(x0), u(z1) - u(z0)] + list(flags)


def pt(x, z, *rest):
    return [u(x), u(z)] + list(rest)


def outside(keep):
    """The rest of the map once the rectangles in `keep` (x0, z0, x1, z1 in metres) are taken out of it, as boxes: a
    local's "cover" zones are where his cover does not hold, so a cover that holds only in a few places is written as
    everywhere else."""
    xs = sorted({0.0, W} | {r[0] for r in keep} | {r[2] for r in keep})
    zs = sorted({0.0, H} | {r[1] for r in keep} | {r[3] for r in keep})
    bands = []
    for z0, z1 in zip(zs, zs[1:]):
        spans = []
        for x0, x1 in zip(xs, xs[1:]):
            inside = any(r[0] <= x0 and x1 <= r[2] and r[1] <= z0 and z1 <= r[3] for r in keep)
            if inside:
                continue
            if spans and spans[-1][1] == x0:
                spans[-1][1] = x1
            else:
                spans.append([x0, x1])
        if bands and bands[-1][2] == spans and bands[-1][1] == z0:
            bands[-1][1] = z1
        else:
            bands.append([z0, z1, spans])
    return [box(x0, z0, x1, z1) for z0, z1, spans in bands for x0, x1 in spans]


W, H = 240.0, 150.0

# --- fixed lines (metres). Openings are whole metres wide and start on a whole metre, so the 1 m path grid (cell
# centres on the half metre) can always pass them and never step over a wall. ---
ROW_S = 20.0                       # the south face of the north row of houses
NORTH_ST = (20.0, 30.0)            # the street in front of the tenements
CUT = (30.0, 38.0)                 # the sunken railway cutting (its two lips)
FOOTBRIDGE = (30.0, 34.0)          # the footbridge over the cutting (x), west
ROADBRIDGE = (160.0, 168.0)        # the road bridge (x), east, lit
LADDER = (104.0, 106.0)            # where Lechuza sets his ladder down the cutting and up the far side (x)
SOUTH_ST = (38.0, 46.0)            # the street along the cutting's south side
BLOCK_N = (46.0, 64.0)             # the northern half of the blocks
CROSS_ST = (64.0, 70.0)            # the cross street
BLOCK_S = (70.0, 94.0)             # the southern half
WEST_ST = (50.0, 56.0)             # the three streets down to the river (x)
MID_ST = (120.0, 126.0)            # the tram line comes down this one
EAST_ST = (172.0, 178.0)
ALLEY = (80.0, 84.0)               # the alley behind the café (x)
PLAZA = (94.0, 100.0)              # the pavement and the little square in front of the café (z)
AVENUE = (100.0, 105.0)            # the riverside avenue with the tram rails (z)
QUAY = (105.0, 110.0)              # the quay (z)
RIVER = (110.0, 134.0)             # the Riachuelo (z)
FAR = (134.0, 150.0)               # the far bank (z)
RAILS_Z = (101.5, 103.5)           # the two tram tracks along the avenue (z)
RAIL_Z = 34.0                      # the railway down in the cutting (centre line)

# The squad's conventillo: rooms round a courtyard, the hallway (zaguán) out to the street.
CONV = (96.0, 0.0, 124.0, ROW_S)
PATIO = (102.0, 4.0, 118.0, 16.0)
ZAGUAN = (109.0, 111.0)            # x
# The café on the Vuelta de Rocha: the room on the square, the cellar behind it, a back door on the alley.
CAFE = (56.0, 80.0, 80.0, 94.0)    # outer walls
CAFE_FRONT = (66.0, 68.0)          # the door on the square (x)
CAFE_BACK = (86.0, 88.0)           # the back door on the alley (z)
CELLAR = (56.5, 80.5, 66.0, 86.0)  # the cellar room (inside the walls)
CELLAR_DOOR = (60.0, 62.0)         # in the cellar's south wall (x); the "door" of the rules
PASSENGER = (61.0, 83.0)
BOAT_SHED = (36.0, 104.0, 50.0, 108.0)
BOAT = (42.0, 48.0)                # Biguá's crossing (x), from the slip of the boat shed straight over
MACHINE = (134.0, 105.0, 145.0, QUAY[1])   # the transporter bridge's machine house, on the quay
GONDOLA = (146.0, 154.0)           # the gondola's run across the river (x), between the bridge's towers
GUARDIA = (178.0, 46.0, 200.0, 64.0)       # the post of the Guardia de Emergencia
LAMP_BOARD = (122.6, 96.4)         # the lamp column with the quay's board, at the foot of the tram street
LAUNCH = (70.0, 124.0)             # the river launch, moored mid-river off the café
EXTRACT = (100.0, 145.0)           # the lane on the far bank where friends wait with a cart
START = (110.0, 10.0)              # the courtyard
# Lamp posts along the avenue's river kerb, fed from the board: in front of the café and at the gondola's landing (the
# floodlit stretches below). One on the road bridge, on another supply.
QUAY_LAMPS = [60.0, 70.0, 81.0, 92.0, 133.0, 148.0, 160.0]
LAMP_Z = 104.6
BRIDGE_LAMP = (ROADBRIDGE[1] + 0.6, NORTH_ST[1] - 1.0)
CART = (98.4, 148.0, 101.6, H)    # the friends' cart at the end of the lane on the far bank

obstacles = [
    # the north row: tenements and houses, the squad's conventillo among them
    rect("row-1", 0.0, 0.0, 40.0, ROW_S, "building", label="CONVENTILLO"),
    rect("row-2", 40.0, 0.0, 70.0, ROW_S, "building"),
    rect("row-3", 70.0, 0.0, CONV[0], ROW_S, "building"),
    rect("conv-n", CONV[0], 0.0, CONV[2], PATIO[1], "building", label="CONVENTILLO"),
    rect("conv-w", CONV[0], PATIO[1], PATIO[0], ROW_S, "building"),
    rect("conv-e", PATIO[2], PATIO[1], CONV[2], ROW_S, "building"),
    rect("conv-s1", PATIO[0], PATIO[3], ZAGUAN[0], ROW_S, "building"),
    rect("conv-s2", ZAGUAN[1], PATIO[3], PATIO[2], ROW_S, "building"),
    rect("row-4", CONV[2], 0.0, 170.0, ROW_S, "building"),
    rect("row-5", 170.0, 0.0, 205.0, ROW_S, "building"),
    rect("row-6", 205.0, 0.0, W, ROW_S, "building", label="CONVENTILLO"),
    # in the courtyard: the washing trough
    rect("trough", 112.0, 6.0, 115.0, 7.0, "prop", see_through=True),
    # the railway cutting, sheer, everywhere but the two bridges (and Lechuza's stretch, a passage below)
    rect("cut-1", 0.0, CUT[0], FOOTBRIDGE[0], CUT[1], "gorge"),
    rect("cut-2", FOOTBRIDGE[1], CUT[0], LADDER[0], CUT[1], "gorge"),
    rect("cut-3", LADDER[1], CUT[0], ROADBRIDGE[0], CUT[1], "gorge"),
    rect("cut-4", ROADBRIDGE[1], CUT[0], W, CUT[1], "gorge"),
    # the blocks
    rect("block-a-n", 0.0, BLOCK_N[0], WEST_ST[0], BLOCK_N[1], "building"),
    rect("block-a-s", 0.0, BLOCK_S[0], WEST_ST[0], BLOCK_S[1], "building"),
    rect("block-b-n1", WEST_ST[1], BLOCK_N[0], ALLEY[0], BLOCK_N[1], "building"),
    rect("block-b-n2", ALLEY[1], BLOCK_N[0], MID_ST[0], BLOCK_N[1], "building"),
    rect("block-b-s1", WEST_ST[1], BLOCK_S[0], ALLEY[0], CAFE[1], "building"),
    rect("block-b-s2", ALLEY[1], BLOCK_S[0], MID_ST[0], BLOCK_S[1], "building"),
    rect("block-c-n", MID_ST[1], BLOCK_N[0], EAST_ST[0], BLOCK_N[1], "building"),
    rect("block-c-s", MID_ST[1], BLOCK_S[0], EAST_ST[0], BLOCK_S[1], "building"),
    rect("guardia", *GUARDIA, "building", label="GUARDIA DE EMERGENCIA"),
    rect("block-d-n", GUARDIA[2], BLOCK_N[0], W, BLOCK_N[1], "building"),
    rect("block-d-s", EAST_ST[1], BLOCK_S[0], W, BLOCK_S[1], "building"),
    # the café's walls: the door on the square and the back door on the alley are gaps; the cellar behind its own wall
    # and door (the door of the rules, below)
    rect("cafe-w", CAFE[0], CAFE[1], CAFE[0] + 0.5, CAFE[3], "wall"),
    rect("cafe-n", CAFE[0] + 0.5, CAFE[1], CAFE[2], CAFE[1] + 0.5, "wall"),
    rect("cafe-e1", CAFE[2] - 0.5, CAFE[1] + 0.5, CAFE[2], CAFE_BACK[0], "wall"),
    rect("cafe-e2", CAFE[2] - 0.5, CAFE_BACK[1], CAFE[2], CAFE[3], "wall"),
    rect("cafe-s1", CAFE[0] + 0.5, CAFE[3] - 0.5, CAFE_FRONT[0], CAFE[3], "wall"),
    rect("cafe-s2", CAFE_FRONT[1], CAFE[3] - 0.5, CAFE[2] - 0.5, CAFE[3], "wall"),
    rect("cellar-e", CELLAR[2], CAFE[1] + 0.5, CELLAR[2] + 0.5, CELLAR[3] + 0.5, "wall"),
    rect("cellar-s1", CAFE[0] + 0.5, CELLAR[3], CELLAR_DOOR[0], CELLAR[3] + 0.5, "wall"),
    rect("cellar-s2", CELLAR_DOOR[1], CELLAR[3], CELLAR[2], CELLAR[3] + 0.5, "wall"),
    # inside the café: the bar counter (low: it hides nobody)
    rect("bar", 70.0, 82.0, 77.0, 83.0, "prop", see_through=True),
    # the riverside: the boat shed, crates on the quay, the machine house and the feet of the bridge's towers
    rect("boat-shed", *BOAT_SHED, "building", label="BOAT SHED"),
    rect("crates-1", 60.0, 106.0, 63.0, 108.5, "crates"),
    rect("crates-2", 92.0, 106.5, 96.0, 108.5, "crates"),
    rect("crates-3", 104.0, 106.0, 107.0, 108.5, "crates"),
    rect("crates-4", 170.0, 106.0, 174.0, 108.5, "crates"),
    rect("machine-house", *MACHINE, "building", label="MACHINE HOUSE"),
    rect("tower-nw", GONDOLA[0] - 1.0, 108.5, GONDOLA[0], QUAY[1], "post", see_through=True),
    rect("tower-ne", GONDOLA[1], 108.5, GONDOLA[1] + 1.0, QUAY[1], "post", see_through=True),
    rect("lamp-board", LAMP_BOARD[0] - 0.3, LAMP_BOARD[1] - 1.1, LAMP_BOARD[0] + 0.3, LAMP_BOARD[1] - 0.5, "post", see_through=True),
    *[rect("lamp-%d" % i, x - 0.2, LAMP_Z - 0.2, x + 0.2, LAMP_Z + 0.2, "post", see_through=True) for i, x in enumerate(QUAY_LAMPS)],
    rect("lamp-bridge", BRIDGE_LAMP[0] - 0.2, BRIDGE_LAMP[1] - 0.2, BRIDGE_LAMP[0] + 0.2, BRIDGE_LAMP[1] + 0.2, "post", see_through=True),
    # the Riachuelo, everywhere but the boat's crossing and the gondola's run (passages, below)
    rect("river-1", 0.0, RIVER[0], BOAT[0], RIVER[1], "water"),
    rect("river-2", BOAT[1], RIVER[0], GONDOLA[0], RIVER[1], "water"),
    rect("river-3", GONDOLA[1], RIVER[0], W, RIVER[1], "water"),
    # the far bank: the towers' far feet, sheds along the back with the lane in the middle
    rect("tower-sw", GONDOLA[0] - 1.0, RIVER[1], GONDOLA[0], RIVER[1] + 1.5, "post", see_through=True),
    rect("tower-se", GONDOLA[1], RIVER[1], GONDOLA[1] + 1.0, RIVER[1] + 1.5, "post", see_through=True),
    rect("sheds-1", 0.0, 142.0, 40.0, H, "building"),
    rect("sheds-2", 40.0, 143.0, 96.0, H, "building", label="SHEDS"),
    rect("sheds-3", 104.0, 143.0, 145.0, H, "building"),
    rect("sheds-4", 155.0, 142.0, W, H, "building"),
    rect("cart", *CART, "prop", see_through=True),
]


def opening(id, kind, x0, z0, x1, z1, anchor, **spec):
    d = {"id": id, "kind": kind, "x": u(x0), "y": u(z0), "w": u(x1) - u(x0), "h": u(z1) - u(z0), "anchor": anchor,
         "closed": "wall", "checkpoint": False, "slow": 1.0, "radius": 30}
    d.update(spec)
    return d


passages = [
    # Lechuza's ladder: the lineman's folding ladder set down the wall of the cutting and up the far side, by the
    # courtyard. Anyone can climb it once it is there, slowly.
    opening("ladder", "ladder", LADDER[0], CUT[0], LADDER[1], CUT[1], pt((LADDER[0] + LADDER[1]) / 2, CUT[0] - 0.75),
            closed="gorge", by=["lechuza"], time=4.0, slow=0.45, checkpoint=True, depth=4.0,
            label="Ladder", verb="Set ladder", icon="ladder", kit="folding ladder",
            order="%s will set his ladder down the wall of the cutting, and over to the far side.",
            done="The ladder is down. Anyone can climb into the cutting and out of the far side now: slowly.",
            refuse="It is Lechuza's ladder. Only he knows how to set it.",
            already="The ladder is already set.",
            unreachable="%s cannot get to the edge of the cutting from here."),
    # Hornero's gondola: the transporter bridge's gondola, worked from the landing's controls. Once he has it running
    # anyone can ride across, slowly; until then the river is the river.
    opening("gondola", "gondola", GONDOLA[0], RIVER[0], GONDOLA[1], RIVER[1], pt((GONDOLA[0] + GONDOLA[1]) / 2, QUAY[1] - 0.8),
            closed="water", by=["hornero"], time=6.0, slow=0.5, checkpoint=True, radius=40,
            label="Gondola", verb="Work the gondola", icon="gondola", kit="",
            order="%s will work the gondola's controls. A motorman knows a controller when he sees one.",
            done="The gondola is running: the night's last crossing. Anyone can ride it over now, slowly.",
            refuse="Only Hornero can work the gondola's controls.",
            already="The gondola is already running.",
            unreachable="%s cannot get to the gondola's landing from here."),
    # Biguá's boat, the Santa Lucía: launched from the slip of the boat shed and rowed straight over. Only he rows, and
    # only the one he is escorting goes with him ("crew"): for everyone else the river is the river.
    opening("boat", "boat", BOAT[0], RIVER[0], BOAT[1], RIVER[1], pt((BOAT[0] + BOAT[1]) / 2, QUAY[1] - 0.8),
            closed="water", by=["bigua"], crew=["bigua"], time=4.0, slow=0.45, checkpoint=True, radius=40,
            label="Boat", verb="Launch the boat", icon="oars", kit="the Santa Lucía, his rowboat",
            order="%s will run the Santa Lucía down the slip of the shed. Only he rows: the one he escorts goes with him.",
            done="The Santa Lucía is in the water. Biguá can row across, and take whoever follows him: nobody else.",
            refuse="It is Biguá's boat. Nobody else rows the Santa Lucía.",
            already="The boat is already in the water.",
            unreachable="%s cannot get to the slip from here."),
]

bushes = [
    # the courtyard: the washing hung out under the gallery, and a cart under a tarpaulin
    rect("washing", 102.5, 12.0, 106.0, 15.5, "washing"),
    # snow-covered scrub along the lips of the cutting
    rect("scrub-1", 80.0, 28.4, 90.0, NORTH_ST[1], "scrub"),
    rect("scrub-2", 60.0, SOUTH_ST[0], 68.0, 39.6, "scrub"),
    rect("scrub-3", 140.0, SOUTH_ST[0], 150.0, 39.6, "scrub"),
    rect("scrub-4", 112.0, SOUTH_ST[0], 118.0, 39.6, "scrub"),
    # dark doorways (zaguanes) along the streets and the alley
    rect("door-1", WEST_ST[1] - 1.6, 48.0, WEST_ST[1], 52.0, "doorway"),
    rect("door-2", WEST_ST[1] - 1.6, 76.0, WEST_ST[1], 80.0, "doorway"),
    rect("door-3", MID_ST[0], 50.0, MID_ST[0] + 1.6, 54.0, "doorway"),
    rect("door-4", MID_ST[1] - 1.6, 80.0, MID_ST[1], 84.0, "doorway"),
    rect("door-5", EAST_ST[0], 52.0, EAST_ST[0] + 1.6, 56.0, "doorway"),
    rect("door-6", ALLEY[0], 56.0, ALLEY[0] + 1.4, 60.0, "doorway"),
    rect("door-7", ALLEY[1] - 1.4, 72.0, ALLEY[1], 76.0, "doorway"),
    rect("door-8", 90.0, CROSS_ST[0], 96.0, CROSS_ST[0] + 1.4, "doorway"),
    rect("door-9", 140.0, PLAZA[0], 146.0, PLAZA[0] + 1.4, "doorway"),
    # the tram standing on the avenue's rails by the café: a screen to stand behind
    rect("tram", 86.0, 101.0, 100.0, 104.0, "tram"),
    # the coal heap on the quay
    rect("coal", 112.0, 106.0, 118.0, 109.0, "coal"),
    # the boats drawn up by the shed
    rect("hulls", 30.0, 105.5, 35.5, 109.5, "hulls"),
    # reeds along the far shore
    rect("reeds-1", 60.0, RIVER[1], 70.0, 137.0, "reeds"),
    rect("reeds-2", 124.0, RIVER[1], 134.0, 137.0, "reeds"),
    rect("reeds-3", 84.0, RIVER[1], 92.0, 137.0, "reeds"),
]

GUARDIA_MAN = {"speed": 34, "range": 190, "near": 96, "fov": 66}


def patrolman(id, look, route, **extra):
    d = {"id": id, "kind": "patrol", "route": route, "look": look, "title": "PATROLMAN"}
    d.update(GUARDIA_MAN)
    d.update(extra)
    return d


def posted(id, look, at, facing, scan=None, **extra):
    d = {"id": id, "kind": "sentry", "route": [pt(*at)], "post": pt(*at, facing), "look": look, "title": "PATROLMAN"}
    d.update(GUARDIA_MAN)
    d.update({"range": 210, "near": 100})
    if scan:
        d["scan"] = scan
    d.update(extra)
    return d


def neighbour(id, at, facing):
    """A neighbour out in the snow: calm, watching it fall; he sees nothing and minds his own business."""
    return {"id": id, "kind": "civilian", "civilian": True, "calm": True, "look": "watchman", "title": "NEIGHBOUR",
            "route": [pt(*at)], "post": pt(*at, facing), "speed": 0, "range": 120, "near": 60, "fov": 60,
            "spare": "%s will not lay a hand on a neighbour.",
            "calmRefuse": "He is watching the snow. Leave him be."}


# what the lamps feed: a patrolman under them sees further; with the board cut he sees only what a dark night allows
DARKENED = {"range": 160, "near": 80}

guards = [
    # The north street: a patrolman walking its length past the tenements and the snow-watchers, a man posted at the
    # south end of the footbridge, a sentry on the lit road bridge.
    patrolman("north", "winter0", [pt(66.0, 26.0, 2.5, 180), pt(150.0, 26.0, 2.5, 0)]),
    posted("footbridge", "winter1", (32.0, 39.6), 270, {"from": 220, "to": 320, "speed": 8, "pause": 2.5}),
    posted("roadbridge", "winter2", (164.0, 27.0), 90, {"from": 40, "to": 150, "speed": 8, "pause": 2.0}),
    # The south street along the cutting.
    patrolman("cut", "winter2", [pt(40.0, 42.0, 2.0, 180), pt(150.0, 42.0, 2.0, 0)], speed=32),
    # The streets down to the river: the top of the west street, the tram street (with the cross street), the east street.
    patrolman("west", "winter1", [pt(53.0, 47.0, 2.0, 270), pt(53.0, 62.0, 2.5, 90)], speed=33),
    patrolman("middle", "winter0", [pt(123.0, 47.0, 1.5, 270), pt(123.0, 67.0), pt(100.0, 67.0, 2.0, 180), pt(123.0, 67.0),
                                    pt(123.0, 92.0, 2.0, 90), pt(123.0, 67.0)], speed=33),
    patrolman("east", "winter2", [pt(175.0, 47.0, 2.0, 270), pt(175.0, 97.0, 2.0, 90)]),
    # The sergeant goes round the middle: the south street, down the tram street to the river, along the avenue to the
    # café and up the west street.
    {"id": "sergeant", "kind": "sergeant", "look": "winter1", "title": "SERGEANT",
     "route": [pt(53.0, 42.0), pt(123.0, 42.0), pt(123.0, 97.0), pt(70.0, 97.0, 3.0, 90), pt(53.0, 97.0), pt(53.0, 67.0),
               pt(53.0, 42.0)],
     "speed": 38, "range": 230, "near": 130, "fov": 80, "lure_immune": True},
    # The alley behind the café and the corner where it meets the cross street.
    patrolman("alley", "winter0", [pt(82.0, 66.0, 2.0, 270), pt(82.0, 96.0, 2.0, 90)], speed=30),
    # The square in front of the café: a patrolman posted watching the crowd and the avenue.
    posted("square", "winter1", (78.0, 98.0), 180, {"from": 140, "to": 250, "speed": 7, "pause": 2.5}),
    # The avenue and the quay: a patrolman on the tram rails, another on the quay under the lamps.
    patrolman("avenue", "winter2", [pt(58.0, 102.5, 2.0, 180), pt(132.0, 102.5, 2.0, 0)], speed=32),
    patrolman("quay", "winter0", [pt(58.0, 108.4, 2.0, 180), pt(132.0, 108.4, 2.0, 0)], powered=DARKENED),
    # The transporter bridge: one posted on the landing, one walking round the machine house; the lamps light both.
    posted("landing", "winter2", (150.0, 106.0), 90, {"from": 35, "to": 145, "speed": 8, "pause": 2.0}, powered=DARKENED),
    patrolman("machine", "winter1", [pt(157.0, 107.4, 2.0, 0), pt(157.0, 102.5), pt(131.0, 102.5), pt(131.0, 107.4, 2.0, 180),
                                     pt(131.0, 102.5), pt(157.0, 102.5)], speed=30, powered=DARKENED),
    # The river launch, moored off the café: her searchlight sweeps the boat shed's water, the river and the quay, and
    # sees a man inside its beam however low he keeps. Only buildings throw a shadow from up there.
    {"id": "launch", "kind": "searchlight", "look": "winter0", "title": "LAUNCH", "route": [pt(*LAUNCH)], "post": pt(*LAUNCH, 180),
     "scan": {"from": 185, "to": 335, "speed": 8, "pause": 1.6},
     "speed": 0, "range": 1050, "near": 980, "fov": 12, "elevation": 0.6, "static": True,
     "melee_immune": True, "lure_immune": True, "trap_immune": True},
    # The informer (buchón) among the snow-watchers on the square: no gun, but he shouts at anything odd he sees, and
    # he knows Benteveo by sight.
    {"id": "informer", "kind": "civilian", "look": "watchman", "title": "INFORMER", "civilian": True,
     "route": [pt(62.0, 97.0)], "post": pt(62.0, 97.0, 90), "scan": {"from": 20, "to": 160, "speed": 10, "pause": 3.0},
     "speed": 20, "range": 200, "near": 96, "fov": 70,
     "spare": "%s will not knife him. An informer, but a neighbour all the same.",
     "calmRefuse": "He is out of it. Leave him be."},
    # Neighbours out in the snow: on the square, in the café, in front of the tenements.
    neighbour("n1", (58.5, 95.5), 0),
    neighbour("n2", (70.0, 96.0), 200),
    neighbour("n3", (74.5, 95.0), 300),
    neighbour("n4", (88.0, 96.5), 260),
    neighbour("n5", (95.0, 95.5), 180),
    neighbour("n6", (72.0, 88.0), 120),
    neighbour("n7", (75.5, 90.5), 210),
    neighbour("n8", (99.0, 23.0), 90),
    neighbour("n9", (102.0, 24.5), 300),
    neighbour("n10", (121.0, 22.5), 200),
]

# Where Hornero passes as a motorman going to his tram (curfew pass and all): upright on the tram lines only.
TRAM_LINES = [(0.0, AVENUE[0], W, AVENUE[1]), (MID_ST[0], SOUTH_ST[0], MID_ST[1], AVENUE[0])]
# Where Benteveo is one more of the crowd: the square and the café, the tenements' pavement.
CROWDS = [(CAFE[0], PLAZA[0], 100.0, PLAZA[1]), (CAFE[0] + 0.5, CELLAR[3] + 0.5, CAFE[2] - 0.5, CAFE[3] - 0.5),
          (96.0, NORTH_ST[0], 124.0, 26.0)]

data = {
    "_source": "Generated by tools/dev/riachuelo_layout.py - edit that, not this file.",
    "id": "riachuelo-04",
    "progressKey": "riachuelo",
    "title": "Operation Riachuelo",
    "subtitle": "La Boca, Buenos Aires · a winter night, 1958 · 23:40",
    "theme": "boca",
    "worldName": "La Boca",
    "width": u(W), "height": u(H), "cellSize": 32,
    "parTime": 540,
    "camera": {"min": [2.0, 2.0], "max": [W - 2.0, H - 2.0], "start": [START[0], START[1] + 6.0], "zoom": 26.0, "zoomMax": 140.0,
               "title": {"from": [60.0, 104.0], "to": [150.0, 112.0], "zoom": 26.0}},
    "briefingMessage": "Study the patrols, the quay's lamps and the launch's searchlight. Bring the passenger up from the cellar of La Bruma and across the Riachuelo.",
    "startMessage": "Lechuza can set his ladder down into the cutting by the courtyard. On the tram lines Hornero is a motorman going to work; in a crowd Benteveo is just the paper boy. Fresh snow keeps your footprints.",
    "winMessage": "The passenger is across, and so are the four of you. Behind you the snow is still falling on La Boca.",
    "extractMessage": "%s is heading for the far bank.",
    "extraction": {"x": u(EXTRACT[0]), "y": u(EXTRACT[1]), "radius": 110, "label": "Far bank", "icon": "rowboat"},
    "door": {"id": "cellar-door", "x": u(CELLAR_DOOR[0]), "y": u(CELLAR[3]), "w": u(CELLAR_DOOR[1]) - u(CELLAR_DOOR[0]),
             "h": u(CELLAR[3] + 0.5) - u(CELLAR[3]), "interactX": u((CELLAR_DOOR[0] + CELLAR_DOOR[1]) / 2),
             "interactY": u(CELLAR[3] + 1.2),
             "label": "Cellar", "icon": "cellar",
             "order": "%s will go to the cellar door and open the lock.",
             "done": "The cellar door is open. Bring the passenger up, then across the river.",
             "refuse": "Hornero has the keys and the tools for that lock.",
             "already": "The cellar door is already open.",
             "locked": "The cellar door is still locked."},
    "prisoner": {"id": "asset", "name": "The passenger", "icon": "hand", "x": u(PASSENGER[0]), "y": u(PASSENGER[1]),
                 "tag": "PASSENGER", "word": "passenger", "safe": "across",
                 "free": "bring the passenger up", "takeOver": "take over the passenger",
                 "order": "%s will %s. Keep the way to the river clear.",
                 "follows": "The passenger follows %s. He cannot crouch: every cone sees him, unless he stands still in cover.",
                 "following": "The passenger is already following %s.",
                 "already": "The passenger is already across.",
                 "boarded": "The passenger is on the far bank with friends. Bring the others across."},
    "units": [
        # Hornero (Aldo Ferrante): tram motorman, the leader. The keys and tools of a man who keeps trams running, the
        # tram's controller handle for a cosh, and its hand bell to ring where he wants the guards to look.
        # His own figure (tools/mh/figures.py "hornero": overcoat, high scarf, the company's cap) and portrait cell 0.
        {"id": "hornero", "name": "Hornero", "role": "Motorman", "x": u(108.0), "y": u(9.0), "color": "#d9a066",
         "ability": "Tools", "tools": True, "portrait": 0, "stance": "sneak",
         "toolsKit": "his keys and tools", "melee": {"label": "Handle", "time": 0.8, "time_stunned": 0.5, "lethal": False, "stun": 25.0,
                   "icon": "handle", "kit": "the tram's controller handle"},
         "throw": {"label": "Bell", "count": 3, "range": 280, "radius": 320, "cooldown": 6.0, "noise": "bell", "icon": "bell",
                   "kit": "the tram's hand bell",
                   "done": "The tram bell clangs through the snow. It drew %d guard%s: move while they look.",
                   "none": "The bell clangs. Nobody was near enough to come and look.",
                   "empty": "%s has rung the bell enough for one night."},
         "cover": {"label": "Motorman", "icon": "motorcap", "kit": "a motorman's cap and coat", "tag": "MOTORMAN", "zones": outside(TRAM_LINES), "seenBy": ["sergeant"],
                   "inside": "Off the tram lines Hornero is a man out after the curfew: crouch, or he will be stopped.",
                   "blown": "Hornero has been marked. From now on he is seen like anyone else."}},
        # Lechuza (Ernesto Saravia): the power company's night lineman. His key opens the board on the lamp column; his
        # folding ladder goes down any wall; he ties a man up with electrician's cord.
        {"id": "lechuza", "name": "Lechuza", "role": "Lineman", "x": u(112.0), "y": u(10.5), "color": "#b6c3d9",
         "ability": "Lamps", "look": "watchman", "stance": "sneak",
         "melee": {"label": "Bind", "time": 2.0, "time_stunned": 1.0, "lethal": False, "icon": "cord", "kit": "electrician's cord"}},
        # Benteveo ("Tito" Gaudino): the canillita, sixteen, who sells La Última. In a crowd he is one more of it; he can
        # throw a bundle of the Sexta to draw a guard's eye; he knows the informer, and the informer knows him.
        {"id": "benteveo", "name": "Benteveo", "role": "Newsboy", "x": u(108.5), "y": u(12.0), "color": "#e6d36f",
         "ability": "Crowds", "look": "benteveo", "stance": "sneak",
         "throw": {"label": "Papers", "count": 4, "range": 260, "radius": 240, "cooldown": 4.0, "noise": "papers", "icon": "papers",
                   "kit": "bundles of La Última, the Sexta",
                   "done": "A bundle of La Última slaps into the snow and he shouts the Sexta. It drew %d guard%s: move while they look.",
                   "none": "The papers land in the snow. Nobody came to look.",
                   "empty": "%s has no papers left."},
         "cover": {"label": "In the crowd", "icon": "flatcap", "kit": "a newsboy's cap and bag", "tag": "NEWSBOY", "zones": outside(CROWDS), "seenBy": ["informer", "sergeant"],
                   "inside": "Out of the crowd Benteveo is a boy out after the curfew: crouch, or he will be stopped.",
                   "blown": "Benteveo has been marked. From now on he is seen like anyone else."}},
        # Biguá (Cosme Ledesma): the botero. His rowboat, the Santa Lucía, a rope, and a knife.
        {"id": "bigua", "name": "Biguá", "role": "Boatman", "x": u(111.5), "y": u(13.0), "color": "#7fb3a8",
         "ability": "Boat", "look": "sailor2", "stance": "sneak",
         "melee": {"label": "Knife", "time": 0.5, "lethal": True, "icon": "knife", "kit": "knife"}},
    ],
    "obstacles": obstacles,
    "passages": passages,
    "radio": {"x": u(LAMP_BOARD[0]), "y": u(LAMP_BOARD[1]), "time": 4.0, "by": ["lechuza"], "label": "Lamp board", "thing": "lamps",
              "icon": "lampboard", "kit": {"icon": "lampkey", "text": "the lamp board's key"},
              "refuse": "Only Lechuza has the key to the lamp board.",
              "already": "The quay's lamps are already out.",
              "unreachable": "The lamp column cannot be reached from here.",
              "order": "%s will open the board on the lamp column with his sector key.",
              "done": "The quay's lamps go out all together. In the dark the Guardia cannot see where to send more men.",
              "deadReason": "The quay's lamps are out.",
              "badge": "The quay went dark", "sound": "snip"},
    "bushes": bushes,
    "guards": guards,
    "reinforcements": {
        "spawn": [pt(GUARDIA[0] - 1.5, 55.0), pt(GUARDIA[0] - 1.5, 56.5)],
        "delay": 6.0, "first": 2, "later": 1, "cap": 3,
        "message": "Men come running out of the Guardia's post.",
        "guard": {"speed": 37, "range": 200, "near": 100, "fov": 68, "look": "winter1", "title": "PATROLMAN"},
        "routes": [
            [pt(175.0, 55.0), pt(175.0, 97.0), pt(132.0, 102.5), pt(175.0, 97.0)],
            [pt(175.0, 55.0), pt(175.0, 42.0), pt(100.0, 42.0), pt(175.0, 42.0)],
        ],
    },
    "alarm": {"duration": 22, "durationRadioCut": 12, "radius": 560,
              "gunshotMessage": "ALARM: the whole barrio heard that."},
    "objectives": [
        {"id": "cell", "text": "Open the cellar of La Bruma"},
        {"id": "informant", "text": "Bring up the passenger"},
        {"id": "extract", "text": "Everyone across the river"},
        {"id": "radio", "text": "Put out the quay's lamps", "optional": True},
    ],
    "snow": {
        "tracks": True, "ttl": 45.0, "spacing": 24.0, "see": 150.0, "follow": 230.0, "hops": 3,
        # busy cobbles, the tram rails, where the crowd stands and the gondola's landing are trodden to slush: no prints
        "packed": [box(0.0, NORTH_ST[0], W, NORTH_ST[1]), box(0.0, SOUTH_ST[0], W, SOUTH_ST[1]), box(0.0, CROSS_ST[0], W, CROSS_ST[1]),
                   box(MID_ST[0], SOUTH_ST[0], MID_ST[1], PLAZA[1]), box(0.0, PLAZA[0], W, AVENUE[1]),
                   box(FOOTBRIDGE[0], CUT[0], FOOTBRIDGE[1], CUT[1]), box(ROADBRIDGE[0], CUT[0], ROADBRIDGE[1], CUT[1]),
                   box(MACHINE[0] - 6.0, QUAY[0], GONDOLA[1] + 8.0, QUAY[1])],
        "indoors": [box(*CAFE), box(*BOAT_SHED), box(*MACHINE)],
        "seen": "A patrolman has found your footprints in the snow, and he is following them.",
    },
    # the quay's lamps hang from one board: cut it and these go dark; the road bridge and the post's door keep theirs
    "floodlit": [box(CAFE[0], PLAZA[0], 100.0, QUAY[1], "powered"), box(128.0, AVENUE[0], 162.0, QUAY[1], "powered"),
                 box(ROADBRIDGE[0] - 2.0, NORTH_ST[0] + 4.0, ROADBRIDGE[1] + 2.0, SOUTH_ST[0] + 3.0),
                 box(GUARDIA[0] - 3.0, 52.0, GUARDIA[0], 58.0)],
    "tracks": [[pt(0.0, RAIL_Z), pt(W, RAIL_Z)], [pt(0.0, RAILS_Z[0]), pt(W, RAILS_Z[0])], [pt(0.0, RAILS_Z[1]), pt(W, RAILS_Z[1])],
               [pt(MID_ST[0] + 1.5, SOUTH_ST[0]), pt(MID_ST[0] + 1.5, AVENUE[0])], [pt(MID_ST[1] - 1.5, SOUTH_ST[0]), pt(MID_ST[1] - 1.5, AVENUE[0])]],
    # the 3D builder's layout (metres), from the same lines as the rules above
    "bocaWorld": {
        "rowS": ROW_S, "northSt": list(NORTH_ST), "cut": list(CUT), "footbridge": list(FOOTBRIDGE), "roadbridge": list(ROADBRIDGE),
        "ladder": list(LADDER), "southSt": list(SOUTH_ST), "blockN": list(BLOCK_N), "crossSt": list(CROSS_ST), "blockS": list(BLOCK_S),
        "westSt": list(WEST_ST), "midSt": list(MID_ST), "eastSt": list(EAST_ST), "alley": list(ALLEY), "plaza": list(PLAZA),
        "avenue": list(AVENUE), "quay": list(QUAY), "river": list(RIVER), "far": list(FAR), "rails": list(RAILS_Z), "railZ": RAIL_Z,
        "conventillo": list(CONV), "patio": list(PATIO), "zaguan": list(ZAGUAN), "cafe": list(CAFE), "cafeFront": list(CAFE_FRONT),
        "cafeBack": list(CAFE_BACK), "cellar": list(CELLAR), "cellarDoor": list(CELLAR_DOOR), "boatShed": list(BOAT_SHED),
        "boat": list(BOAT), "machine": list(MACHINE), "gondola": list(GONDOLA), "guardia": list(GUARDIA), "lampBoard": list(LAMP_BOARD),
        "launch": list(LAUNCH), "extract": list(EXTRACT), "start": list(START), "cutDepth": 4.0,
        "lamps": [[x, LAMP_Z] for x in QUAY_LAMPS], "bridgeLamp": list(BRIDGE_LAMP), "cart": list(CART),
    },
    "ambience": {
        "water": "amb_harbour", "hum": "amb_hum", "electric": True, "windDb": -2.0,
        "waterRects": [[0.0, RIVER[0], W, RIVER[1]]], "falloff": 14.0,
        "humAt": [[(MACHINE[0] + MACHINE[2]) / 2, (MACHINE[1] + MACHINE[3]) / 2]],
        "radioIsPower": False,
        "every": [14.0, 30.0],
        "calls": [
            {"cue": "creak", "weight": 2, "at": [pt(150.0, 112.0), pt(45.0, 108.0), pt(70.0, 124.0)]},
            {"cue": "clank", "weight": 2, "at": [pt(150.0, 106.0), pt(140.0, 104.0)]},
        ],
    },
    "history": [
        {"title": "LA\nBOCA",
         "body": "La Boca grew where the Riachuelo bends towards the Río de la Plata, at the Vuelta de Rocha. It filled with Italian immigrants, above all from Genoa and the Ligurian coast, who worked the port, the shipyards and the boats. They built houses of timber and corrugated iron, raised on piles, out of what the shipyards and the ships left over, and painted them with whatever was to hand, mostly red and green. Many lived in conventillos: rooms on three floors round a shared patio, with one kitchen for everyone. In 1884 the neighbours founded Argentina's first volunteer fire brigade, under an Italian name and the motto \"Volere è potere\".\n\nThe railway cutting in this level has a real model. A branch line ran along an old stream bed there until 1928; in 1959 the painter Benito Quinquela Martín and his neighbours turned the abandoned track into an open-air museum and named it Caminito, after a tango.",
         "foot": "Café La Bruma and its cellar are made up."},
        {"title": "THE\nTRANSPORTER",
         "body": "The Puente Transbordador Nicolás Avellaneda began carrying people across the Riachuelo in May 1914. It was made in Britain and put together on the spot: two steel towers almost 40 metres high, standing on concrete cylinders sunk 24 metres into the riverbed, joined by a girder high above the water. A carriage ran along the girder on rails, and from it hung a platform eight metres by twelve that took people, carts, cars and even trams from La Boca over to Isla Maciel. On the first day the man driving it fell into the river, and the Prefectura fished him out.\n\nA road bridge opened beside it in 1940, and the transporter stopped running in 1960. It is a national historic monument; in 2017, restored, it carried passengers again for the first time in 57 years.",
         "foot": "Its last crossing of a snowy night in 1958 is made up."},
        {"title": "THE\nBOATMEN",
         "body": "Before the transporter, and for decades after it, rowing boats carried people over the Riachuelo. The boteros took workers from La Boca to Isla Maciel and its meat-packing plants and factories, a crossing of about five minutes, at every hour of the day and night. A neighbour remembers some forty boats and ten thousand passengers a day when the trade was at its height. The boats had names, Rosa María, La Sacra Familia, Don Conrado, and they passed from father to son.\n\nThe Prefectura stopped the crossings in rain and high wind, and the boteros remember the sudestada, the south-easterly gale that pushes the river up into La Boca's streets. The boats were still crossing in 2017.",
         "foot": "The Santa Lucía is made up. The boats are not."},
        {"title": "THE\nNEWSBOYS",
         "body": "Boys first sold newspapers on Buenos Aires street corners in 1868, when La República paid them to, as the New York papers did, and they shouted the headlines to make a sale. They came to be called canillitas after Canillita, a 1902 play by Florencio Sánchez about a newsboy whose thin shins, his canillas, showed below his short trousers. Argentina's newspaper sellers still keep 7 November, the day Sánchez died, as their own day.\n\nThe evening papers came out in several editions a day; La Razón's evening one was the Sexta, the sixth. In 1952 La Razón put out half a million copies a day, more than any other paper in Latin America.",
         "foot": "La Última and its Sexta are made up."},
        {"title": "THE\nSNOW",
         "body": "Snow almost never falls on Buenos Aires: since its records began in 1906, the city's observatory has seen it settle only twice. On 22 June 1918 it began in the afternoon and came again, heavier, that night. People poured out to see it: a snowball fight in the Plaza del Congreso, snowmen, shop clerks out on the pavements, crowds in the Plaza de Mayo and the Palermo woods. Six people died of the cold, among them people sleeping in the street.\n\nOn 9 July 2007 it snowed again, for the first time in 89 years, from mid-afternoon into the night. Whole families went out into the streets and onto their balconies to watch it fall, and again people sleeping rough died of the cold. No snow fell in the 1950s: this operation borrows those two nights for La Boca in 1958.",
         "foot": "The snow of 1958 is made up. The snow of 1918 and 2007 is not."},
        {"title": "THIS\nSTORY",
         "body": "The four neighbours, the passenger and the men hunting him are made up, and so are Café La Bruma, the Santa Lucía, La Última and the Guardia de Emergencia with its curfew. In November 1958 the national government declared a state of siege; the decree, the curfew and the Guardia in this story are invented. Porteños gave everyone a nickname, and these four are birds of the river and the city: the ovenbird, the owl, the kiskadee and the cormorant.\n\nThe rest is as true as we could make it: La Boca and the Vuelta de Rocha, the transporter and its gondola, the boats to Isla Maciel, the trams, the canillitas' cry, and the electric street lamps that men still switched on by hand, with keys, at boards on the lamp columns. The city's last kerosene street lamp had gone out in 1931.",
         "foot": "Lechuza is a lineman, not a lamplighter: by 1958 there were no flames left to light."},
    ],
    "copy": {
        "wonTitle": "CROSSING\nMADE",
        "title": "OPERATION\nRIACHUELO",
        "briefing": "La Boca, a winter night in 1958, and for the first time in forty years it is snowing. A decree keeps everyone indoors after dark, but tonight half the barrio is out in the street throwing snowballs. In the cellar of Café La Bruma, on the Vuelta de Rocha, a man is hiding from the Guardia de Emergencia, and he has to be across the Riachuelo before morning. Four neighbours take him: Hornero, who drives the tram; Lechuza, the power company's night lineman; Benteveo, who sells the evening paper; and Biguá, who rows. Put out the quay's lamps if you can, bring the passenger up, and get him over on the transporter's last crossing, or in Biguá's boat.",
        "mapTip": "Show the whole barrio",
        "debrief": "In the morning the gondola stood at its landing and the Santa Lucía was back in her shed. At La Bruma nobody had seen anything but the snow, and the next evening's Sexta wrote about nothing else. By then the passenger was a long way off, and the snow had filled in the footprints by the river.",
        "failureNote": "Lose any of the four, or the passenger, and the crossing is over. Keep to trodden slush near a patrol, keep out of the lamps and the launch's beam, and stop the clock before you act.",
        "checkpointNote": "Checkpoints are also taken when the ladder is set, the cellar is opened, the passenger is up, and the gondola or the boat is ready.",
        "checkpoints": {"start": "the courtyard", "ladder": "ladder set", "gate": "cellar open", "informant": "passenger up",
                        "gondola": "gondola running", "boat": "boat in the water"},
        "orderNames": {"sabotage": "LAMPS OUT", "extract": "TO THE FAR BANK", "unlock": "OPEN CELLAR", "rescue": "PASSENGER", "rig": "LADDER"},
        "objectiveHow": {
            "cell": {"hornero": "Hornero: through the café's back door on the alley to the cellar door",
                     "": "Hornero has the keys to the cellar: switch to him"},
            "informant": {"": "Into the cellar: tap the passenger to bring him up"},
            "extract": {"bigua": "Biguá: launch the Santa Lucía at the shed and row the passenger across",
                        "hornero": "Hornero: work the gondola's controls on its landing",
                        "": "Everyone across: the gondola, or Biguá's boat for the passenger"},
            "radio": {"lechuza": "Lechuza: the lamp board on the column at the foot of the tram street",
                      "": "Lechuza has the key to the lamp board"},
        },
        "hints": {
            "start": "Tap Hornero, Lechuza, Benteveo or Biguá to choose who acts, then tap the ground to move. Drag to look around.",
            "takedown": "Tap a patrolman to take him down: Hornero's controller handle, Lechuza's cord, Biguá's knife. Best from behind.",
            "both": "You command all four neighbours. Tap another portrait and use them together.",
            "cell": "Only Hornero can open the cellar. Select him, then tap the cellar door.",
            "radio": "Optional: Lechuza can put out the quay's lamps at the board on the lamp column. Then crouching hides you there, and an alarm brings no more men.",
            "informant": "The passenger cannot crouch. Move him from cover to cover: doorways, the tram, the coal heap.",
            "ladder": "The bridges over the cutting are watched. With Lechuza, tap the edge by the courtyard: he sets his ladder down and over, and the others can follow.",
            "hornero": "Hornero walks upright on the tram lines like a motorman going to work, and the patrolmen let him be. Off them he is out after the curfew. The sergeant knows him.",
            "benteveo": "In the crowd on the café's square and in front of the tenements, Benteveo is just the paper boy. The informer among the snow-watchers knows him by sight.",
            "informer": "One of the snow-watchers on the square is an informer. He has no gun, but he shouts for the Guardia at anything odd. Lechuza can tie him up; nobody will knife him.",
            "tracks": "Fresh snow takes footprints, and a patrolman who crosses them follows them. The streets, the tram rails and where the crowd stands are trodden to slush.",
            "searchlight": "The Guardia's launch sweeps its searchlight over the water and the quay. Inside the beam crouching hides nobody: wait for it to pass.",
            "floodlight": "Under the quay's lamps crouching does not hide you. Lechuza can put them out at the board.",
            "gondola": "Hornero works the gondola's controls on the landing by the machine house. Once it runs, anyone can ride across, slowly.",
            "boat": "Biguá's boat, the Santa Lucía, is in the shed west of the café. Only he rows her, and only the one he escorts goes with him: the passenger.",
            "bell": "Hornero's tram bell draws the patrolmen near where it rings. Benteveo can throw a bundle of papers and shout the Sexta.",
            "cosh": "The controller handle knocks a patrolman out. He comes round after 25 seconds and goes looking: hide him, or let Lechuza tie him up.",
        },
        "coach": ["start", "hornero", "benteveo", "ladder", "cones", "tracks", "takedown", "informer", "floodlight", "radio", "searchlight",
                  "plan", "both", "cell", "informant", "gondola", "boat", "bell", "cosh"],
        "hintsWhen": {
            "hornero": {"who": "hornero"},
            "benteveo": {"who": "benteveo"},
            "ladder": {"near": [u(105.0), u(28.0), 360], "after": 15.0},
            "tracks": {"after": 25.0},
            "informer": {"near": [u(64.0), u(96.0), 420]},
            "floodlight": {"near": [u(75.0), u(100.0), 360]},
            "searchlight": {"near": [u(70.0), u(106.0), 420]},
            "gondola": {"near": [u(148.0), u(104.0), 420]},
            "boat": {"near": [u(45.0), u(104.0), 360]},
            "bell": {"who": "hornero", "after": 40.0},
            "cosh": {"who": "hornero", "after": 90.0},
        },
    },
}
# Who wears what (figures baked by tools/mh/mhbake.py from tools/mh/figures.py, dressed by operative.gd). Set here, not
# in the entries above, whose lines carry the level's words: the squad each in a figure of his own (operative.gd knows
# their ids, so no units[].look) with a photo in the portrait atlas; the Guardia de Emergencia's men (guardia0-2, the
# sergeant in his cape), the launch's crew, the informer, the passenger, and the barrio out in the snow (vecino0-5 and
# vecina0-3: five baked figures, the rest the same figures in other colours).
PORTRAITS = {"hornero": 0, "lechuza": 1, "benteveo": 2, "bigua": 3}
LOOKS = {"sergeant": "guardia_sgt", "launch": "guardia1", "informer": "informer",
         "n1": "vecino0", "n2": "vecina0", "n3": "vecino4", "n4": "vecina2", "n5": "vecino2", "n6": "vecino1", "n7": "vecina1",
         "n8": "vecino3", "n9": "vecina3", "n10": "vecino5"}
for i, unit in enumerate(data["units"]):
    # the photo takes the place of the stand-in look each entry still names
    data["units"][i] = {("portrait" if k == "look" else k): v for k, v in unit.items()}
    data["units"][i]["portrait"] = PORTRAITS[unit["id"]]
for guard in data["guards"]:
    # the entries above still name the stand-in winter0-2: each becomes the Guardia man built the same way
    guard["look"] = LOOKS.get(guard["id"], guard["look"].replace("winter", "guardia"))
data["reinforcements"]["guard"]["look"] = "guardia2"
data["prisoner"] = dict([("id", data["prisoner"]["id"]), ("look", "pasajero")] + list(data["prisoner"].items()))

out = os.path.join(os.path.dirname(__file__), "..", "..", "godot", "data", "riachuelo.json")
with open(out, "w") as f:
    json.dump(data, f, indent=1, ensure_ascii=False)
    f.write("\n")
print("wrote", os.path.normpath(out))
