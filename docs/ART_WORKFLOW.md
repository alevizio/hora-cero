# Making the characters and the vehicles better: the workflow on this Mac

How a model gets from an idea into Hora Cero, and which tool does what. The art pack itself (slots, the manifest, the
budgets, what the rigs and the finish do to a model) is explained in `docs/ART_PACK.md`; this is the practical route,
written on October 22, 2026, when the Figma kit's Juan was redone from the game's own renders.

## The tools

- **Blender** (free, blender.org) is the hub: cleanup, scale and units, UVs, decimating, posing, re-rigging, baking,
  export to glTF. `/Applications/Blender.app` is a 5.3 beta Ale downloaded on October 20; `~/.local/bin/blender` is a
  wrapper that starts it, so `tools/art_pack.py decimate` and `convert` can call it (a symlink does not work: Blender
  looks for its files next to its real binary). If the beta misbehaves, install the stable release.
- **Mixamo** (free, Adobe account, in the browser): rigs a humanoid and gives it clips. Upload the character in an
  A or T pose (FBX or OBJ, under 100k triangles), download the rigged model "with skin" as FBX, then the clips "without
  skin": Idle, Walking, Running, Jump, Falling, Looking Around (the game's Inspect). Import all in Blender, name the
  actions `Idle`, `Walk`, `Run`, `Jump`, `Fall`, `Inspect`, export one .glb with them. `tools/juan_suit.py` shows what
  a Mixamo-skeleton model needs on the way in (metres and Y up, a standing rest pose, the rifle on a bone).
- **Textures**: the "more texture, more detail" step. Substance 3D Painter (paid, runs natively on Apple Silicon) bakes
  the mesh maps and paints leather, wool, canvas and wear in minutes; its "glTF PBR Metal Roughness" export writes the
  colour, normal and packed occlusion/roughness/metal maps the game reads. The free way: Blender's texture paint with
  CC0 materials from Poly Haven or ambientCG, baked to the same three maps. 2K colour at most; the prepare tools
  scale down (normals half, packed maps a quarter).
- **Optional**: an AI generator (Meshy, Tripo, Rodin) for a first body and clothes from a concept image, always
  followed by Blender; Plasticity for hard-surface cars; Nomad Sculpt on an iPad for sculpting.
- **The repository's own**: `tools/dev/glb_facts.py <file.glb>` says what is inside a GLB (triangles per mesh,
  materials and maps, bones, clips, bounds and which way is up; `--vehicle` adds the part each material becomes);
  `tools/art_pack.py check | decimate | convert`; `tools/juan_blue_hood.py` (the template of a "prepare a character"
  tool: gltfpack simplification, textures scaled, detail baked into the colour maps); `tools/vehicles.gd` (vehicle
  sources to game meshes); `tools/dev/turntable.gd` and `turntable_encode.py` (the landing's turning figures);
  `tools/dev/salvo_kit_cards.py` (the kit's cards).

## Budgets (the web game runs on an iPhone)

| What | Triangles | Maps | Notes |
|---|---|---|---|
| a person | 20,000 to 40,000 | colour 1K to 2K, normals half, ORM a quarter | `check` warns over 40k; Juan at 75k is the ceiling and the exception |
| a creature | up to 60,000 | same | the cascarudo has a 13k far copy |
| a prop | up to 20,000 | | |
| a car source | 8,000 to 14,000 with its interior | none: flat materials, named | the converter makes a far copy (~3k) and a near one (7.5k to 10.5k) |

Metres, +Y up, the front toward +Z (in Blender: Z up, facing -Y; the exporter converts), standing on y = 0 with the
origin between the feet, a person 1.75 to 1.85 m. Textures are what weigh: a model file wants to be a few MB.

## The rules that decide the tool

- The cascarudo and the Plaza's vehicles are Santiago Siri's files: improve them in Blender (textures, rig, fewer
  triangles), never regenerate them. Comic characters come only from provided art. Juan is Ale's own model; the
  four neighbours are invented, so anything goes for them.
- Every file carries its author, licence and permission in its manifest slot (`check` refuses one without), and the
  credits in Settings, the landing and NOTICE follow. A bought model cannot go in the public repository: prefer
  CC0 or CC-BY sources and credit them.
- Nothing from the 2025 TV series. No real company names or trademarks on vehicles (the converter already removes a
  maker's star and badge from the colectivo).

## Route A: a neighbour as a 3D model (Hornero first)

1. **Reference sheet** in Figma: front, side and back of Hornero at Juan's scale, from the kit's "The squad" row and
   his portrait. Decide the garments (coat, cap, scarf, trousers, boots) and his kit; keep them as separate objects,
   as Juan's are (Coat, Hood, Trousers, Boots, Backpack: `glb_facts.py godot/art_pack/juan_salvo/juan_salvo.glb`).
2. **Body and clothes**: a MakeHuman base (CC0, what Juan's head and skin are) dressed in Blender, or an AI draft from
   the sheet, cleaned in Blender. Apply scale, feet on the floor, facing -Y, a Decimate modifier (Collapse) to the
   budget, UVs per garment (one 2K atlas, or one map per garment like Juan).
3. **Rig and clips** in Mixamo as above; export .glb from Blender with: Format glb, +Y up, Apply Modifiers, Materials
   exported with images, Skinning on, Animation on with the actions as NLA tracks.
4. **Textures**: bake AO, curvature and thickness, paint the materials, export colour, normal and ORM at 2K.
5. **Into the game**: a prepare tool like `tools/juan_blue_hood.py` (its gltfpack line, the texture sizes, the
   names) writing `godot/art_pack/hornero/hornero.glb`; a slot in `godot/art_pack/manifest.json` (copy
   `juan_salvo`: `kind person`, `height_m`, `forward "+z"`, the `clips` map, `clip_speed` as `juan_suit.py` prints
   it, the credit); `python3 tools/art_pack.py check`; then `"look": "art:hornero"` on his unit in
   `tools/dev/plaza_layout.py` (the way Juan has `art:juan_salvo`), which rewrites `godot/data/plaza.json`.
6. **Look and test**: `tools/dev/turntable.gd` renders the figure the game builds; the suites `art_pack`,
   `plaza_scene`, `plaza_rules` and `preview_mode` (with `HOME=<a fresh empty folder>`); the plaza itself in the
   editor. The kit's cards and the landing's turning figure come from the same renders (`salvo_kit_cards.py` is
   Juan's framing; a neighbour gets his own constants).

## Route B: a car

1. **Blueprints** (the-blueprints.com: Fords, Chevrolets and Dodges of 1946 to 1955; the colectivos were Bedford and
   Chevrolet chassis with local bodies). Box-model the body in Blender, wings, wheels and interior as separate objects
   named like the generated cars (`Body`, `Exterior_Details`, `Interior`, `Fine_Details`, `Wheel_FL` ... `Wheel_RR`).
2. **Materials by name**, flat colours, no textures: `Paint` (takes each car's own colour in the game), `Paint_dark`,
   `Chrome` or `steel`, `Rubber` or `tire`, `Glass`, `Headlamp`, `Tail_light`, `Indicator`, `Plate`, `Interior`,
   `Seat_fabric`, and `Lettering` or `Sign` for a bus. `glb_facts.py --vehicle file.glb` shows what the converter will
   make of each.
3. **Into the game**: the .glb goes to `art/vehicles/models/<nn>_<name>.glb`; add it to `CARS_1950S` in
   `tools/vehicles.gd` (source, game name, the far copy's triangles) and its period colours to `period_paint` in
   `godot/scripts/three_d/plaza_city.gd`; run `godot --headless --path godot --script ../tools/vehicles.gd`; place
   it in `PARKED` in `tools/dev/plaza_layout.py` or the city's fleets; `tools/dev/car_cutouts.gd` renders it for the
   landing's line of cars. Credit it in `godot/assets/vehicles/CREDITS.txt`.

## A first weekend

- Saturday morning: open Juan's model in Blender to see how a finished one is built, make Hornero's sheet.
- Saturday afternoon: body and clothes blocked out, decimated, unwrapped.
- Sunday morning: Mixamo, the clips, one .glb; `glb_facts.py` and `check` on it.
- Sunday afternoon: textures, the prepare tool, `look: art:hornero`, the suites, Hornero next to Juan in the plaza
  and in the kit. Decide from that comparison whether the other three follow.
