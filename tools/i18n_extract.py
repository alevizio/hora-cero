#!/usr/bin/env python3
"""Lists the English texts of the game that need a translation: the text fields of the mission data (the same
fields scripts/lang.gd translates) and the string literals of the scripts that put words on screen.

    python3 tools/i18n_extract.py            # prints the texts missing from godot/locale/es.json
    python3 tools/i18n_extract.py --all      # prints every text found
    python3 tools/i18n_extract.py --check    # the same as the first, failing if anything is missing

Literals are found by a simple rule (letters and a space, or capitals; ids and paths left out), so the list may
hold a few that never reach the screen: a translation for those does no harm."""
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot")
SCRIPTS = ["scripts/three_d/hud.gd", "scripts/simulation.gd", "scripts/three_d/main.gd", "scripts/missions.gd",
           "scripts/three_d/front.gd"]
DATA = ["data/plaza.json", "data/riachuelo.json"]
DATA_IDS = {"id", "kind", "look", "type", "icon", "glyph", "thing", "cue", "noise", "style", "sound", "theme", "worldName",
            "progressKey", "color", "material", "_source", "water", "hum", "objective", "by", "who", "unplanted", "coach",
            "coachOrder", "fig", "span", "at", "path", "number", "tab", "x", "y", "stance", "ability", "boat", "prop",
            "officers", "seenBy", "closed", "crew", "group", "dark", "vehicle", "art", "rule", "mode", "from"}
DATA_SKIP = {"obstacles", "barriers", "bushes", "harbour", "tracks", "ambience", "guards", "fence", "camera", "floodlit",
             "plazaWorld", "people"}
## Literals that are names, layout reports for tests, or bare formats: never shown as words to translate.
IGNORE = {"Hornero", "Lechuza", "Benteveo", "Biguá", "Hora Cero", "HORACERO_UNLOCK", "HORACERO_FEEDBACK_ONLINE", "HORACERO_FEEDBACK_URL",
          "HORACERO_FEEDBACK_HEADERS", "HORACERO_BUILD", "TowerCrane", "Girders", "Fore", "Aft", "TooltipPanel", "TooltipLabel",
          "%s  %s", "  %d/%d", "%s  ·  %s", "%s  ·  %s%s",
          "view keys", "menu keys", "command banner", "alarm banner", "armed prompt", "checkpoint tag", "tag ",
          "%s %s leaves the safe area %s", "%s overlaps %s", "button %s is only %s", "button %s is off screen",
          "%s: %s.", "%s: %s. %s", "HORACERO_MISSION", "HORACERO_TITLE", "too often",
          "%02d:%02d", "#%d", "%s   %s", "···", "Content-Type: application/json", "Accept: application/json",
          # put together with the game's name before they are shown: the catalog has them whole ("HORA CERO  /  FIELD
          # OPERATIONS", "Only to tell you when Hora Cero launches.", ...); the game's line is the same in both languages
          "  /  FIELD OPERATIONS", "Only to tell you when %s launches.", "Your answers are on file. Thank you for playing %s.",
          "Invasión Buenos Aires"}
LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')
SKIP_LINE = re.compile(r"^\s*(#|##)|preload\(|load\(|push_error|print\(|get_value\(|set_value\(|has_method\(|"
                       r"add_theme_|get_node\(|\.name\s*=|tracing|trace\.append")


def wordy(text):
    letters = sum(1 for c in text if c.isalpha())
    if letters < 2:
        return False
    if re.fullmatch(r"[a-z0-9_:/.\-]+", text):          # ids, keys, paths
        return False
    if re.fullmatch(r"#?[0-9a-fA-F]{6}", text):
        return False
    if text.startswith(("res://", "user://", "lang:", "mission:")):
        return False
    return " " in text or re.search(r"[A-Z]{2}", text) is not None or text[:1].isupper()


def from_scripts():
    found = []
    for rel in SCRIPTS:
        for line in open(os.path.join(ROOT, rel), encoding="utf-8"):
            if SKIP_LINE.search(line):
                continue
            for m in LITERAL.finditer(line):
                text = bytes(m.group(1), "utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8")
                if wordy(text):
                    found.append(text)
    return found


## Dictionaries of the copy keyed by names, not fields: a hint called "tracks" or a checkpoint called "boat" is still
## text. The HUD shows them through a Label (tr()), so they need their Spanish even though translate_data skips them.
NAMED = {"hints", "checkpoints", "objectiveHow", "orderNames"}


def walk(value, key, out, named=False):
    if not named and (key in DATA_IDS or key in DATA_SKIP):
        return
    if isinstance(value, dict):
        for k, v in value.items():
            walk(v, k, out, key in NAMED)
    elif isinstance(value, list):
        for v in value:
            walk(v, key, out)
    elif isinstance(value, str) and sum(1 for c in value if c.isalpha()) >= 2:
        out.append(value)


def from_data():
    found = []
    for rel in DATA:
        walk(json.load(open(os.path.join(ROOT, rel), encoding="utf-8")), "", found)
    return found


def texts():
    seen = {}
    for t in from_data() + from_scripts():
        if t not in IGNORE:
            seen.setdefault(t, True)
    return list(seen)


def main():
    have = {}
    path = os.path.join(ROOT, "locale", "es.json")
    if os.path.exists(path):
        have = json.load(open(path, encoding="utf-8")).get("strings", {})
    every = "--all" in sys.argv
    missing = 0
    for t in texts():
        if every or t not in have:
            print(json.dumps(t, ensure_ascii=False))
            missing += t not in have
    if "--check" in sys.argv and missing:
        print("%d texts have no Spanish yet" % missing)
        sys.exit(1)


if __name__ == "__main__":
    main()
