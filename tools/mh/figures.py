"""The cast, as MakeHuman settings. Paths are inside the CC0 system asset pack.

macro: age (years), muscle / weight / height / proportions (0..1, 0.5 average).
mods: modelling modifiers at -1..1 (MakeHuman's modeling_modifiers.json names).
"""

SUIT = "clothes/male_casualsuit05/male_casualsuit05.mhclo"
BOOTS = "clothes/shoes03/shoes03.mhclo"
LASHES = "eyelashes/eyelashes01/eyelashes01.mhclo"
EYES = "eyes/high-poly/high-poly.mhclo"

# the rig's legs are a little short for MakeHuman's men: every figure gets these
LEGS = {"armslegs/upperlegs-height": -0.55, "armslegs/lowerlegs-height": -0.45, "torso/torso-scale-vert": 0.35}


def _mods(extra):
    out = dict(LEGS)
    out.update(extra)
    return out


# The cast of Hora Cero (the figures operative.gd dresses: the four neighbours, the Guardia de Emergencia, the informer,
# the passenger and the barrio), filled in below.
FIGURES = {}

# --- the shared builder ---------------------------------------------------------------------------------
# guard(): a uniformed man (MakeHuman's buttoned shirt and jeans, re-dyed), the base the Guardia de Emergencia's men
# are built on (guardia() below). Skins are shared three ways (guard_young / mid / old), so a whole force costs three
# skin textures.
SHIRT = "clothes/male_casualsuit01/male_casualsuit01.mhclo"
EYES_LOW = "eyes/low-poly/low-poly.mhclo"
SKINS = {"young": "skins/young_caucasian_male/young_caucasian_male.mhmat",
         "mid": "skins/middleage_caucasian_male/middleage_caucasian_male.mhmat",
         "old": "skins/old_caucasian_male/old_caucasian_male.mhmat"}
WEATHER = {"young": {"stubble": 0.35, "sun": 0.25, "grime": 0.2, "socket": 0.2, "crease": 0.3},
           "mid": {"stubble": 0.55, "sun": 0.35, "grime": 0.24, "socket": 0.24, "crease": 0.38},
           "old": {"stubble": 0.5, "sun": 0.4, "grime": 0.24, "socket": 0.26, "crease": 0.45}}
TUNIC = ["5a5f51", "5a5f51", "5e6254", "575d52", "5b6053", "585e54"]
TROUSERS = "52564e"
HELMET = "3d443e"


def guard(age, muscle, weight, height=0.5, proportions=0.5, face=None, skin="young", eye="grey", hair="hair/short02/short02.mhclo",
          brows="eyebrows/eyebrow003/eyebrow003.mhclo", top=TUNIC[1], legs=TROUSERS, hat="helmet", hat_color=HELMET, tilt=0.0, roll=0.0,
          coat=None, tache=None, mul=(0.92, 0.80, 0.70), boots="1b1917", collar="2f362f"):
    if top in ("8e8b79", "576059"):
        collar = None   # shirt sleeves, or a tunic thrown open
    spec = {
        "macro": dict(age_years=age, muscle=muscle, weight=weight, height=height, proportions=proportions),
        "mods": _mods(face or {}),
        "skin": SKINS[skin], "skin_tex": skin, "skin_share": "guard_" + skin, "skin_size": 1024, "weather": WEATHER[skin],
        "stubble_rgb": [0.15, 0.12, 0.10] if skin != "old" else [0.32, 0.30, 0.28],
        "eye_color": eye, "eyes": EYES_LOW, "hair": hair, "brows": brows, "lashes": LASHES,
        "suit": SHIRT, "boots": BOOTS, "jackboots": boots,
        "colors": {"jacket": top, "shirt": collar if collar else top, "trousers": legs},
        "skin_mul": list(mul), "grip": 0.9, "collar": collar,
    }
    if hat and hat != "bare":
        spec.update({"hat": hat, "hat_color": hat_color, "hat_tilt": tilt, "hat_roll": roll})
    elif hat == "bare":
        spec["hat"] = "bare"
    if coat:
        spec["coat"] = coat
    elif top != "8e8b79":
        spec["tunic_skirt"] = top
    if tache:
        spec["tache"] = tache
    return spec


# --- Operation Riachuelo: the neighbours of La Boca, winter 1958 -----------------------------------------
# Hornero: Aldo Ferrante, a tram motorman of La Boca from a Genoese family, about forty, a father. Broad and solid
# rather than tall; a square open face with a strong, slightly hooked nose, heavy dark brows, warm brown eyes with
# the lines of a man who laughs, a full dark moustache, a day's stubble. A dark navy wool overcoat to the knee, a
# rust-red knitted scarf (the ovenbird's colour) wound high, one end thrown back over the shoulder, a navy flat cap
# with the tram company's small brass oval on the front, dark leather gloves, black work boots.
FIGURES["hornero"] = {
    "macro": dict(age_years=41, muscle=0.70, weight=0.60, height=0.50, proportions=0.5),
    "mods": _mods({
        "head/head-square": 0.45, "head/head-fat": 0.05, "head/head-age": 0.45,
        "forehead/forehead-nubian": 0.3, "eyebrows/eyebrows-trans|forward": 0.3, "eyebrows/eyebrows-angle": -0.15,
        "nose/nose-scale-vert": 0.30, "nose/nose-hump": 0.40, "nose/nose-width1": 0.15, "nose/nose-scale-depth": 0.25,
        "nose/nose-volume": 0.2, "nose/nose-point-width": 0.1,
        "cheek/l-cheek-bones": 0.35, "cheek/r-cheek-bones": 0.35, "cheek/l-cheek-volume": -0.1, "cheek/r-cheek-volume": -0.1,
        "chin/chin-width": 0.35, "chin/chin-prominent": 0.25, "chin/chin-bones": 0.3,
        "eyes/l-eye-bag|decr": 0.25, "eyes/r-eye-bag|decr": 0.25, "eyes/l-eye-push1": -0.15, "eyes/r-eye-push1": -0.15,
        "mouth/mouth-laugh-lines": 0.6, "mouth/mouth-scale-horiz": 0.1, "mouth/mouth-angles": 0.1,
        "neck/neck-scale-horiz": 0.4, "neck/neck-scale-depth": 0.25,
        "torso/torso-vshape": 0.3, "torso/torso-muscle-dorsi": 0.3, "stomach/stomach-pregnant": 0.15,
    }),
    "skin": "skins/middleage_caucasian_male/middleage_caucasian_male.mhmat", "skin_tex": "middleage",
    "eye_color": "brownlight", "eyes": EYES,
    "hair": "hair/short01/short01.mhclo", "brows": "eyebrows/eyebrow009/eyebrow009.mhclo", "lashes": LASHES,
    "suit": SUIT, "boots": BOOTS,
    "colors": {"jacket": "262c38", "shirt": "4a4e57", "trousers": "2b2b2f"},
    "coat": "262c38", "coat_fit": "trunk", "coat_belt": "222733", "skirt_patch": (0.09, 0.36),
    "skin_mul": [0.93, 0.78, 0.65], "tache": "full", "tache_thick": 0.0050, "hat_band": 0.05,
    "hat": "flat", "hat_color": "222736", "cap_badge": True,
    "scarf": "96502d", "scarf_high": True, "scarf_end": True,
    "gloves": "2a221c",
    "weather": {"stubble": 0.6, "sun": 0.35, "grime": 0.2, "socket": 0.28, "crease": 0.45},
    "stubble_rgb": [0.11, 0.09, 0.07],
    "grip": 0.9,
}

# Lechuza: Ernesto Saravia, a night lineman of the (invented) Compañía de Electricidad del Sur, about fifty-five, a
# widower of Galician stock. Long, thin and a little stooped, the head carried forward; a long narrow face, hollow
# cheeks, a long nose, pale grey eyes behind round steel spectacles (operative.gd), deep lines, grey stubble. A long
# grey-brown canvas work coat over a bottle-green wool jumper, a brown knitted cap with ear flaps, fingerless wool
# gloves, old black boots.
FIGURES["lechuza"] = {
    "macro": dict(age_years=56, muscle=0.38, weight=0.24, height=0.66, proportions=0.45),
    "mods": _mods({
        "head/head-oval": 0.55, "head/head-age": 0.95, "head/head-fat": -0.7, "head/head-scale-horiz": -0.08,
        "cheek/l-cheek-volume": -0.85, "cheek/r-cheek-volume": -0.85, "cheek/l-cheek-bones": 0.55, "cheek/r-cheek-bones": 0.55,
        "cheek/l-cheek-inner": -0.5, "cheek/r-cheek-inner": -0.5,
        "nose/nose-scale-vert": 0.45, "nose/nose-scale-depth": 0.30, "nose/nose-hump": 0.15, "nose/nose-width1": -0.15,
        "nose/nose-point-width": -0.2,
        "chin/chin-prominent": 0.15, "chin/chin-width": -0.15, "chin/chin-height": 0.2,
        "eyebrows/eyebrows-trans|forward": 0.2, "eyebrows/eyebrows-angle": 0.25,
        "eyes/l-eye-bag|decr": 0.55, "eyes/r-eye-bag|decr": 0.55, "eyes/l-eye-push1": -0.2, "eyes/r-eye-push1": -0.2,
        "mouth/mouth-laugh-lines": 0.9, "mouth/mouth-angles": -0.25, "mouth/mouth-lowerlip-volume": -0.3, "mouth/mouth-upperlip-volume": -0.2,
        "neck/neck-scale-horiz": -0.25, "neck/neck-trans|forward": 0.45, "head/head-trans|forward": 0.25, "neck/neck-trans|down": -0.25,
        "torso/torso-vshape": -0.3, "torso/torso-scale-depth": -0.1,
    }),
    "skin": "skins/old_caucasian_male/old_caucasian_male.mhmat", "skin_tex": "old",
    "eye_color": "grey", "eyes": EYES,
    "hair": "hair/short04/short04.mhclo", "brows": "eyebrows/eyebrow009/eyebrow009.mhclo", "lashes": LASHES,
    "suit": SUIT, "boots": BOOTS,
    "colors": {"jacket": "6b6251", "shirt": "37443a", "trousers": "3b3832"},
    "coat": "6b6251", "coat_fit": "trunk", "coat_hem": 0.38, "coat_ell": 0.82, "coat_window": 0.015, "coat_room": 0.012, "coat_belt": "3d2c1f", "skirt_patch": (0.09, 0.36),
    "skin_mul": [0.95, 0.82, 0.72], "hat_band": 0.05,
    "hat": "earflap", "hat_color": "5a4a3c",
    "gloves": "5d564c", "gloves_cut": True, "gloves_tex": "weave_knit",
    "weather": {"stubble": 0.7, "sun": 0.22, "grime": 0.2, "socket": 0.38, "crease": 0.62},
    "stubble_rgb": [0.50, 0.48, 0.45],
    "grip": 0.9,
}

# Benteveo: "Tito" Gaudino, a canillita of sixteen who sells the evening paper at the tram stop by the café. Slight
# and quick, a round young face, a short nose, bright brown eyes, red cheeks from the cold, no beard to speak of. A
# flat cap a size too big, a hand-me-down brown tweed jacket over a rust jumper, a long mustard scarf striped in
# brown hanging down his front, brown corduroy trousers tucked into grey wool socks, worn boots.
FIGURES["benteveo"] = {
    "macro": dict(age_years=19, muscle=0.42, weight=0.30, height=0.40, proportions=0.55),
    "mods": _mods({
        "head/head-age": -0.75, "head/head-round": 0.35, "head/head-fat": 0.05, "head/head-scale-vert": -0.04,
        "cheek/l-cheek-volume": 0.25, "cheek/r-cheek-volume": 0.25, "cheek/l-cheek-bones": -0.1, "cheek/r-cheek-bones": -0.1,
        "nose/nose-scale-vert": -0.30, "nose/nose-width1": -0.15, "nose/nose-point-width": -0.15, "nose/nose-scale-depth": -0.15,
        "nose/nose-point": 0.3,
        "chin/chin-prominent": -0.15, "chin/chin-width": -0.2, "chin/chin-bones": -0.2,
        "eyes/l-eye-scale": 0.15, "eyes/r-eye-scale": 0.15, "eyebrows/eyebrows-angle": 0.35, "eyebrows/eyebrows-trans|forward": -0.2,
        "mouth/mouth-scale-horiz": -0.08, "mouth/mouth-upperlip-volume": 0.2, "mouth/mouth-angles": 0.35, "mouth/mouth-dimples": 0.3,
        "neck/neck-scale-horiz": -0.35, "neck/neck-scale-depth": -0.2,
        "torso/torso-vshape": -0.25, "torso/torso-scale-horiz": -0.06,
    }),
    "skin": "skins/young_caucasian_male/young_caucasian_male.mhmat", "skin_tex": "young",
    "eye_color": "brownlight", "eyes": EYES,
    "hair": "hair/short02/short02.mhclo", "brows": "eyebrows/eyebrow001/eyebrow001.mhclo", "lashes": LASHES,
    "suit": SUIT, "boots": BOOTS,
    "colors": {"jacket": "6a5642", "shirt": "7c3a28", "trousers": "57452f"},
    "skin_mul": [0.98, 0.84, 0.75], "hat_band": 0.05,
    "hat": "flat", "hat_color": "57524a", "cap_big": True,
    "scarf": "b08a34", "scarf_long": True, "scarf_stripe": "7a2c22",
    "socks": "6f6a62",
    "weather": {"stubble": 0.05, "sun": 0.10, "grime": 0.16, "socket": 0.16, "crease": 0.18, "cold": 0.55, "saturation": 0.85},
    "stubble_rgb": [0.20, 0.15, 0.11],
    "grip": 0.9,
}

# Biguá: Cosme Ledesma, a botero of about thirty-five who rows workers across to Isla Maciel, as his father did.
# Broad and strong, a square weathered face, a heavy jaw, a broad nose once broken, dark eyes under straight brows,
# clean-shaven with the dark shadow of a short beard. A dark navy knitted jumper with a roll neck, an ochre oilskin
# jacket worn open, a dark wool beanie, dark trousers and black rubber boots to below the knee.
FIGURES["bigua"] = {
    "macro": dict(age_years=36, muscle=0.88, weight=0.62, height=0.60, proportions=0.55),
    "mods": _mods({
        "head/head-square": 0.6, "head/head-age": 0.35, "head/head-fat": 0.1,
        "chin/chin-width": 0.5, "chin/chin-prominent": 0.3, "chin/chin-bones": 0.45, "chin/chin-jaw-drop": 0.1,
        "nose/nose-width1": 0.35, "nose/nose-width2": 0.2, "nose/nose-hump": 0.25, "nose/nose-volume": 0.25, "nose/nose-curve": 0.3,
        "nose/nose-nostrils-width": 0.25,
        "cheek/l-cheek-bones": 0.45, "cheek/r-cheek-bones": 0.45, "cheek/l-cheek-volume": -0.25, "cheek/r-cheek-volume": -0.25,
        "eyebrows/eyebrows-trans|forward": 0.4, "eyebrows/eyebrows-angle": -0.45, "forehead/forehead-nubian": 0.3,
        "eyes/l-eye-push1": -0.2, "eyes/r-eye-push1": -0.2, "eyes/l-eye-height2": -0.2, "eyes/r-eye-height2": -0.2,
        "mouth/mouth-scale-horiz": 0.1, "mouth/mouth-lowerlip-volume": 0.1, "mouth/mouth-laugh-lines": 0.4,
        "neck/neck-scale-horiz": 0.6, "neck/neck-scale-depth": 0.4,
        "torso/torso-vshape": 0.6, "torso/torso-muscle-dorsi": 0.55, "torso/torso-muscle-pectoral": 0.35,
    }),
    "skin": "skins/middleage_caucasian_male/middleage_caucasian_male.mhmat", "skin_tex": "middleage",
    "eye_color": "brown", "eyes": EYES,
    "hair": "hair/short02/short02.mhclo", "brows": "eyebrows/eyebrow001/eyebrow001.mhclo", "lashes": LASHES,
    "suit": SUIT, "boots": BOOTS,
    "colors": {"jacket": "6e6232", "shirt": "1d2333", "trousers": "2a2a2a"},
    "suit_gloss": 0.7,
    "skin_mul": [0.92, 0.77, 0.64], "hat_band": 0.05,
    "hat": "beanie", "hat_color": "24262b",
    "scarf": "1d2333", "scarf_roll": True,
    "jackboots": "161716", "boot_height": 0.27, "boot_straight": True,
    "weather": {"stubble": 0.8, "sun": 0.55, "grime": 0.22, "socket": 0.28, "crease": 0.42},
    "stubble_rgb": [0.07, 0.06, 0.05],
    "grip": 0.9,
}


# --- The Guardia de Emergencia (an invented curfew force) ---------------------------------------------------
# Charcoal-green greatcoats to the knee with a black belt, matching trousers over black boots, soft peaked caps of the
# same cloth with a black leather chin strap and a plain silver disc; a white "G.E." armband and the rest of the kit
# are operative.gd's. Nothing blue, no emblem, no jackboots, no helmets: not the Policía Federal, not an army. The
# garrison's three shared skins (guard_young / mid / old) serve them, untouched.
GE_COAT = "30362f"
GE_LEGS = "2a2f2a"
GE_CAP = "2b302b"


def guardia(age, muscle, weight, height=0.5, proportions=0.5, face=None, skin="young", eye="grey", hair="hair/short02/short02.mhclo",
            tache=None, mul=(0.92, 0.80, 0.70), cape=None, brows="eyebrows/eyebrow003/eyebrow003.mhclo"):
    spec = guard(age, muscle, weight, height, proportions, face=face, skin=skin, eye=eye, hair=hair, brows=brows, top=GE_COAT, legs=GE_LEGS,
                 hat="peaked", hat_color=GE_CAP, coat=GE_COAT, tache=tache, mul=mul, collar=None)
    spec.pop("jackboots")
    # the greatcoat's upper half is the jacket of the jacket-and-shirt suit (lapels buttoned over a dark front)
    spec.update({"suit": SUIT, "colors": {"jacket": GE_COAT, "shirt": "262c27", "trousers": GE_LEGS}, "skirt_patch": (0.09, 0.36),
                 "coat_fit": "trunk", "coat_hem": 0.40, "coat_ell": 0.84, "coat_window": 0.018, "coat_room": 0.018, "coat_belt": "151514",
                 "cap_disc": "b7bcc0", "cap_band": GE_CAP, "skin_reuse": True})
    if cape:
        spec.update({"cape": cape, "cape_hem": 1.0})
    return spec


FIGURES.update({
    # a lean young patrolman, long-faced
    "guardia0": guardia(24, 0.5, 0.36, 0.6, face={"head/head-oval": 0.4, "cheek/l-cheek-volume": -0.45, "cheek/r-cheek-volume": -0.45,
                                                  "nose/nose-hump": 0.3, "nose/nose-scale-vert": 0.2, "chin/chin-prominent": 0.25},
                        eye="brown", mul=(0.93, 0.79, 0.68)),
    # a stocky one, square-faced, a clipped moustache
    "guardia1": guardia(36, 0.68, 0.64, 0.38, face={"head/head-square": 0.5, "nose/nose-width1": 0.35, "chin/chin-width": 0.4,
                                                    "neck/neck-scale-horiz": 0.4, "eyebrows/eyebrows-trans|forward": 0.3},
                        skin="mid", eye="brownlight", hair="hair/short01/short01.mhclo", tache="brush", mul=(0.94, 0.79, 0.67)),
    # a tall heavy-jawed one
    "guardia2": guardia(29, 0.78, 0.52, 0.8, 0.55, face={"chin/chin-width": 0.5, "chin/chin-prominent": 0.35, "head/head-square": 0.3,
                                                         "nose/nose-hump": 0.35, "forehead/forehead-nubian": 0.35},
                        skin="mid", eye="grey", hair="hair/short02/short02.mhclo", mul=(0.92, 0.78, 0.68)),
    # the sergeant: the cape over his greatcoat, heavy, fifty, a grey moustache, ruddy
    "guardia_sgt": guardia(50, 0.6, 0.78, 0.55, face={"head/head-fat": 0.35, "head/head-square": 0.4, "nose/nose-volume": 0.4,
                                                      "nose/nose-width1": 0.3, "eyes/l-eye-bag|decr": 0.5, "eyes/r-eye-bag|decr": 0.5,
                                                      "mouth/mouth-angles": -0.45, "neck/neck-double": 0.3},
                           skin="old", eye="grey", hair="hair/short01/short01.mhclo", tache="brush", mul=(0.98, 0.77, 0.66),
                           cape="2b332c", brows="eyebrows/eyebrow009/eyebrow009.mhclo"),
})


# --- Civilians of La Boca: the informer, the passenger, the barrio out in the snow ------------------------
# Men in the shared garrison skins (nothing new painted for them), the jacket-and-shirt suit (casualsuit05) under their
# coats; the women in a skin of their own (vecina), a blouse and skirt under the coat. Each records what it was baked
# in ("tints") so that operative.gd can dress a second neighbour in other colours from the same bake.
def civilian(age, muscle, weight, height=0.5, proportions=0.5, face=None, skin="mid", eye="brown", hair="hair/short01/short01.mhclo",
             brows="eyebrows/eyebrow003/eyebrow003.mhclo", coat=None, jacket=None, shirt="b4ad9c", legs="34322f", hat=None, hat_color="2c2b2a",
             scarf=None, tache=None, mul=(0.93, 0.80, 0.70), hem=0.38, belt=None):
    jacket = jacket or coat
    spec = guard(age, muscle, weight, height, proportions, face=face, skin=skin, eye=eye, hair=hair, brows=brows, top=jacket, legs=legs,
                 hat=hat or "bare", hat_color=hat_color, tache=tache, mul=mul, collar=None)
    spec.pop("jackboots")
    spec.pop("tunic_skirt", None)
    spec.update({"suit": SUIT, "colors": {"jacket": jacket, "shirt": shirt, "trousers": legs}, "skin_reuse": True, "tints": True,
                 "skirt_patch": (0.09, 0.36)})
    if coat:
        spec.update({"coat": coat, "coat_fit": "trunk", "coat_hem": hem, "coat_ell": 0.82, "coat_window": 0.015, "coat_room": 0.018,
                     "coat_belt": belt or coat})
    if scarf:
        spec["scarf"] = scarf
    return spec


def vecina(age, weight, height=0.45, face=None, eye="brownlight", coat="5a2e33", blouse="8f8273", stockings="2b2523", scarf="b7a587",
           mul=(0.96, 0.82, 0.74)):
    """A woman of the barrio out in the snow: a belted coat to mid-calf (the jacket-and-shirt suit, its shirt the blouse
    at the neck, the legs below the hem dark stockings), a headscarf tied under the chin, black boots."""
    return {
        "macro": dict(age_years=age, muscle=0.4, weight=weight, height=height, proportions=0.5, gender=0.0),
        "mods": _mods(dict({"hip/hip-scale-horiz": -0.35, "hip/hip-scale-depth": -0.15, "armslegs/l-upperarm-scale-horiz": -0.1,
                            "armslegs/r-upperarm-scale-horiz": -0.1}, **(face or {}))),
        "skin": "skins/middleage_caucasian_female/middleage_caucasian_female.mhmat", "skin_tex": "female", "skin_share": "vecina",
        "skin_size": 1024, "skin_reuse": True,
        "weather": {"stubble": 0.0, "sun": 0.12, "grime": 0.10, "socket": 0.22, "crease": 0.34, "cold": 0.25},
        "eye_color": eye, "eyes": EYES_LOW, "hair": "hair/short04/short04.mhclo", "brows": "eyebrows/eyebrow010/eyebrow010.mhclo",
        "lashes": LASHES, "suit": SUIT, "boots": BOOTS,
        "colors": {"jacket": coat, "shirt": blouse, "trousers": stockings}, "tints": True,
        "coat": coat, "coat_fit": "trunk", "coat_hem": 0.31, "coat_belt": coat, "coat_ell": 0.78, "coat_window": 0.008, "coat_fine": True, "coat_room": 0.05, "skirt_patch": (0.09, 0.36),
        "hat": "headscarf", "hat_color": scarf,
        "skin_mul": list(mul), "grip": 0.85,
    }


FIGURES.update({
    # the informer (buchón): forty-five, a camel overcoat belted, a grey felt hat, a pencil moustache; a newspaper always
    "informer": civilian(46, 0.42, 0.58, 0.45, face={"head/head-oval": 0.3, "eyes/l-eye-height2": -0.3, "eyes/r-eye-height2": -0.3,
                                                     "mouth/mouth-lowerlip-volume": -0.4, "mouth/mouth-upperlip-volume": -0.3,
                                                     "nose/nose-point-width": -0.3, "nose/nose-scale-depth": 0.25, "cheek/l-cheek-volume": -0.2,
                                                     "cheek/r-cheek-volume": -0.2, "chin/chin-prominent": -0.15},
                         skin="mid", eye="brownlight", hair="hair/short04/short04.mhclo", coat="9c7a50", shirt="c9c2b2", legs="4a4744",
                         hat="fedora", hat_color="707069", tache="pencil", mul=(0.95, 0.80, 0.69), hem=0.40),
    # the passenger: thirty-odd, thin, a mild long face (round spectacles: operative.gd), bareheaded, a borrowed overcoat
    # too big for him, long and wide, its belt hanging loose
    "pasajero": civilian(33, 0.32, 0.20, 0.55, face={"head/head-oval": 0.45, "cheek/l-cheek-volume": -0.3, "cheek/r-cheek-volume": -0.3,
                                                      "nose/nose-scale-vert": 0.3, "nose/nose-width1": -0.15, "chin/chin-prominent": -0.1,
                                                      "eyebrows/eyebrows-angle": 0.3, "mouth/mouth-scale-horiz": -0.05,
                                                      "neck/neck-scale-horiz": -0.2},
                         skin="young", eye="brown", hair="hair/short02/short02.mhclo", coat="4d4a42", shirt="cfcabd", legs="383735",
                         mul=(0.94, 0.81, 0.72), hem=0.31, belt="3e3b35"),
    # the barrio's men: fifty, a charcoal overcoat, a dark felt hat, a grey scarf, a clipped moustache
    "vecino0": civilian(50, 0.5, 0.62, 0.5, face={"head/head-square": 0.3, "nose/nose-volume": 0.3, "mouth/mouth-laugh-lines": 0.5,
                                                   "eyes/l-eye-bag|decr": 0.3, "eyes/r-eye-bag|decr": 0.3},
                        skin="mid", eye="brown", hair="hair/short01/short01.mhclo", coat="36383b", legs="2f2e2d",
                        hat="fedora", hat_color="2a2928", scarf="6f6b64", tache="brush", mul=(0.94, 0.80, 0.69)),
    # an old man: a brown overcoat, a flat cap, a dark red scarf, a grey walrus moustache
    "vecino1": civilian(67, 0.38, 0.55, 0.42, face={"head/head-round": 0.3, "head/head-age": 0.9, "neck/neck-double": 0.4,
                                                     "eyes/l-eye-bag|decr": 0.5, "eyes/r-eye-bag|decr": 0.5, "nose/nose-volume": 0.4,
                                                     "mouth/mouth-angles": -0.3},
                        skin="old", eye="grey", hair="hair/short04/short04.mhclo", brows="eyebrows/eyebrow009/eyebrow009.mhclo",
                        coat="5a4636", legs="3a352f", hat="flat", hat_color="4d4842", scarf="6a2e28", tache="walrus", mul=(0.96, 0.80, 0.70)),
    # a young worker: no coat, a short dark jacket over a jumper, a black beret, a scarf
    "vecino2": civilian(27, 0.62, 0.45, 0.55, face={"nose/nose-hump": 0.3, "chin/chin-prominent": 0.25, "cheek/l-cheek-bones": 0.3,
                                                     "cheek/r-cheek-bones": 0.3},
                        skin="young", eye="brown", hair="hair/short02/short02.mhclo", jacket="474852", shirt="8b8270", legs="3a3836",
                        hat="beret", hat_color="1f2126", scarf="8a7a5a", mul=(0.93, 0.79, 0.69)),
    # the barrio's women: forty, a wine-red coat, a faded blue headscarf; sixty, a black coat, a grey headscarf
    "vecina0": vecina(41, 0.5, 0.42, face={"cheek/l-cheek-volume": 0.15, "cheek/r-cheek-volume": 0.15, "nose/nose-scale-vert": 0.1,
                                           "mouth/mouth-laugh-lines": 0.3}, scarf="76808f"),
    "vecina1": vecina(62, 0.62, 0.35, face={"head/head-age": 0.8, "head/head-fat": 0.25, "neck/neck-double": 0.35, "eyes/l-eye-bag|decr": 0.4,
                                            "eyes/r-eye-bag|decr": 0.4, "mouth/mouth-angles": -0.3, "nose/nose-volume": 0.25},
                      eye="grey", coat="28272b", blouse="8e8a84", scarf="4b4b52", mul=(0.97, 0.83, 0.75)),
})
FIGURES["vecino2"]["hat_badge"] = False
FIGURES["pasajero"]["coat_ell"] = 1.05   # cut for a bigger man
