extends RefCounted
## The art pack: drawings and models made by people with permission, dropped into godot/art_pack/ and listed in its
## manifest.json (docs/ART_PACK.md). A unit, guard or civilian whose data `look` names a slot ("art:<slot id>") or a
## drawing directly (a .png path, "art_pack/x.png" or "res://..."; or a .glb / .gltf model) is shown as that art
## (operative.gd: the paper cut-out, cutout.gd). A slot whose file is not there yet shows a neutral stand-in: a plain
## grey mannequin card (a plain block for anything that is not a person) with a plate saying the licensed art is
## pending, and the slot's name. The stand-ins are drawn here, by code, and show nothing of what is to come.
##
## manifest.json:
##   {"format": 1, "slots": {"<id>": {"name": "...", "name_en": "...", "kind": "person" | "creature" | "prop",
##     "height_m": 1.75, "length_m": 4.0, "width_m": 1.8, "file": "folder/front.png" (or a .glb),
##     "faces": "right" | "left" | "front", "forward": "+z" | "-z" | "+x" | "-x", "portrait": "folder/photo.png",
##     "views": {"back": "...png", "crouch": "...png", "down": "...png"},
##     "credit": {"author": "...", "licence": "...", "permission": "...", "source": "...", "contact": "..."},
##     "test": false}}}
## A model may also say: "lod": "folder/lighter.glb" (a lighter copy drawn while the camera is far), "clips": {"idle":
## "...", "walk": "...", "run": "..."} (its clips' names, else found by name) and "clip_speed": {"walk": m/s, "run": m/s}
## (the speeds they were made at), "prop": "<mesh name>" (what he carries in his hands: a rifle), "origin": "model" (stand
## it on its own origin rather than centred on its middle), "finish": "cloth" | "chitin" | "pbr" (dressed for our night: see
## cutout.gd).
## Paths are relative to the pack's folder. tools/art_pack.py checks it all (sizes, transparency, credits, a model's
## triangles, its proportions and its animations). length_m and width_m (a creature's) size its stand-in, a plain block
## lying the way it walks; "forward" is the model's front (glTF's +z unless said); "portrait" is the HUD's ID photo for a
## slot worn by one of the squad (a plain plate with the name until it comes).

## The pack's folder; tests point it elsewhere (forget() after).
static var root: String = "res://art_pack/"
const MANIFEST: String = "manifest.json"
## The neutral stand-ins, drawn by tools/art_pack.py (person.png, block.png); the game's own, wherever the pack is.
const STAND_INS: String = "res://art_pack/stand_in/"
## A figure's height in the rig's units: operative.gd's skeleton stands this tall at height 1.0.
const RIG_HEIGHT: float = 1.78
const DEFAULT_HEIGHT := {"person": 1.75, "creature": 2.6, "prop": 1.2}
## A model's front, as the manifest names it, and the turn about the vertical that sets it facing +z (the way the game
## turns every figure it walks): glTF's own custom is +z.
const FORWARDS := {"+z": 0.0, "-z": PI, "+x": -PI / 2.0, "-x": PI / 2.0}

static var _manifest: Dictionary = {}
static var _loaded: bool = false
static var _textures: Dictionary = {}
static var _stand_ins: Dictionary = {}
static var _scenes: Dictionary = {}

static func forget() -> void:
	_loaded = false
	_manifest = {}
	_textures.clear()
	_scenes.clear()

static func manifest() -> Dictionary:
	if _loaded: return _manifest
	_loaded = true
	_manifest = {"format": 1, "slots": {}}
	var path: String = root.path_join(MANIFEST)
	if not FileAccess.file_exists(path): return _manifest
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_warning("art_pack: %s is not a JSON object" % path)
		return _manifest
	_manifest = parsed
	if not _manifest.get("slots") is Dictionary: _manifest["slots"] = {}
	return _manifest

static func slot_ids() -> Array:
	var ids: Array = (manifest().slots as Dictionary).keys()
	ids.sort()
	return ids

## A slot as the game uses it, every field filled: {id, name, name_en, kind, height_m, file, model, views {back, crouch,
## down}, faces, credit, test, ready (its file is there)}. {} for an id the manifest does not have.
static func slot(id: String) -> Dictionary:
	var raw: Variant = (manifest().slots as Dictionary).get(id)
	if not raw is Dictionary: return {}
	return _normal(id, raw)

static func _normal(id: String, raw: Dictionary) -> Dictionary:
	var kind: String = str(raw.get("kind", "person"))
	if not kind in DEFAULT_HEIGHT: kind = "person"
	var file: String = str(raw.get("file", ""))
	var views: Dictionary = {}
	var raw_views: Variant = raw.get("views", {})
	for view: String in ["back", "crouch", "down"]:
		var v: String = str((raw_views as Dictionary).get(view, "")) if raw_views is Dictionary else ""
		views[view] = _path(v) if v != "" and _exists(_path(v)) else ""
	var path: String = _path(file) if file != "" else ""
	var model: bool = path.get_extension().to_lower() in ["glb", "gltf"]
	var credit: Dictionary = raw.get("credit", {}) if raw.get("credit") is Dictionary else {}
	var portrait: String = str(raw.get("portrait", ""))
	var forward: String = str(raw.get("forward", "+z"))
	if not forward in FORWARDS: forward = "+z"
	var height: float = clampf(float(raw.get("height_m", DEFAULT_HEIGHT[kind])), 0.3, 30.0)
	var lod: String = str(raw.get("lod", ""))
	var origin: String = str(raw.get("origin", "centre"))
	var finish: String = str(raw.get("finish", ""))
	return {"id": id, "name": str(raw.get("name", id)), "name_en": str(raw.get("name_en", raw.get("name", id))), "kind": kind,
		"height_m": height, "length_m": clampf(float(raw.get("length_m", 0.0)), 0.0, 60.0),
		"width_m": clampf(float(raw.get("width_m", 0.0)), 0.0, 30.0), "file": path, "model": model,
		"views": views, "faces": str(raw.get("faces", "right")), "forward": forward, "credit": credit, "test": bool(raw.get("test", false)),
		"portrait": _path(portrait) if portrait != "" and _exists(_path(portrait)) else "",
		"lod": _path(lod) if lod != "" and _exists(_path(lod)) else "",
		"clips": raw.get("clips", {}) if raw.get("clips") is Dictionary else {},
		"clip_speed": raw.get("clip_speed", {}) if raw.get("clip_speed") is Dictionary else {},
		"prop": str(raw.get("prop", "")), "origin": origin if origin in ["centre", "model"] else "centre",
		"finish": finish if finish in ["cloth", "chitin", "pbr"] else "",
		"ready": path != "" and _exists(path)}

static func _path(file: String) -> String:
	if file.begins_with("res://") or file.begins_with("user://") or file.is_absolute_path(): return file
	return root.path_join(file)

static func _exists(path: String) -> bool:
	return ResourceLoader.exists(path) or FileAccess.file_exists(path)

## What a data `look` asks of the art pack: the slot it names ("art:<id>"), or a slot made up on the spot for a drawing
## or model named by its path; {} for any other look (the game's own figures).
static func parse_look(look: String) -> Dictionary:
	if look.begins_with("art:"):
		var id: String = look.substr(4)
		var s: Dictionary = slot(id)
		if s.is_empty():
			# a slot the manifest does not list yet: pending, under its id
			s = _normal(id, {"name": id})
		return s
	var ext: String = look.get_extension().to_lower()
	if ext in ["png", "glb", "gltf"]:
		var path: String = look if look.begins_with("res://") or look.begins_with("user://") or look.is_absolute_path() else "res://" + look.trim_prefix("/")
		var base: String = path.get_basename()
		var raw: Dictionary = {"name": path.get_file().get_basename(), "file": path, "views": {}}
		# the other views by name, beside it: walker.png, walker_back.png, walker_crouch.png, walker_down.png
		for view: String in ["back", "crouch", "down"]:
			if _exists(base + "_" + view + ".png"): raw.views[view] = base + "_" + view + ".png"
		return _normal(path.get_file().get_basename(), raw)
	return {}

## The turn that sets a slot's model facing +z (its "forward").
static func forward_turn(s: Dictionary) -> float:
	return float(FORWARDS.get(str(s.get("forward", "+z")), 0.0))

## The slot's ID photo for the HUD ({texture, used, aspect, size} as drawing() gives it), {} while it has none.
static func portrait(s: Dictionary) -> Dictionary:
	var path: String = str(s.get("portrait", ""))
	return drawing(path) if path != "" else {}

## The slot's name as the player's language has it.
static func display_name(s: Dictionary, lang: String) -> String:
	return str(s.get("name_en", s.get("name", ""))) if lang == "en" else str(s.get("name", ""))

# ------------------------------------------------------------------------------------------------ drawings
## A drawing as a texture with mipmaps (cards are small on screen), and the rectangle of it that is drawn on (its
## transparent margins trimmed): {"texture", "used" (Rect2 in UV), "aspect" (used width / used height)}. Cached.
## {} if the file is missing or not an image.
static func drawing(path: String) -> Dictionary:
	if path == "": return {}
	if _textures.has(path): return _textures[path]
	var image: Image = null
	if ResourceLoader.exists(path):
		var tex: Variant = load(path)
		if tex is Texture2D: image = (tex as Texture2D).get_image()
	if image == null and FileAccess.file_exists(path):
		image = Image.load_from_file(path)
	if image == null or image.is_empty():
		_textures[path] = {}
		return {}
	if image.is_compressed(): image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8: image.convert(Image.FORMAT_RGBA8)
	var used: Rect2i = image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0: used = Rect2i(Vector2i.ZERO, image.get_size())
	image.generate_mipmaps()
	var size := Vector2(image.get_size())
	var entry: Dictionary = {"texture": ImageTexture.create_from_image(image), "used": Rect2(Vector2(used.position) / size, Vector2(used.size) / size),
		"aspect": float(used.size.x) / float(used.size.y), "size": image.get_size()}
	_textures[path] = entry
	return entry

## A model (a .glb or .gltf) as a scene to instance, imported or read at run time; null if it cannot be read.
static func model(path: String) -> PackedScene:
	if _scenes.has(path): return _scenes[path]
	var scene: PackedScene = null
	if ResourceLoader.exists(path):
		var res: Variant = load(path)
		if res is PackedScene: scene = res
	if scene == null and FileAccess.file_exists(path):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(ProjectSettings.globalize_path(path), state) == OK:
			var node: Node = doc.generate_scene(state)
			if node != null:
				scene = PackedScene.new()
				_own(node, node)
				if scene.pack(node) != OK: scene = null
				node.free()
	_scenes[path] = scene
	return scene

static func _own(node: Node, owner: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner
		_own(child, owner)

## The neutral stand-in for a slot whose art is not here yet: a plain grey mannequin (a person) or a plain rounded block
## (anything else), drawn here as a flat card with an ink edge. Nothing on it hints at clothes, a face or a shape of what
## is to come. Cached per kind.
static func stand_in(kind: String) -> Dictionary:
	var key: String = "person" if kind == "person" else "block"
	if _stand_ins.has(key): return _stand_ins[key]
	# drawn ahead of time (tools/art_pack.py test-art), else here, smaller
	var made: Dictionary = drawing(STAND_INS + key + ".png")
	if not made.is_empty():
		_stand_ins[key] = made
		return made
	# small: the edge is a smooth ramp of alpha, so the card's cut stays clean however far it is enlarged
	var w: int = 96 if key == "person" else 160
	var h: int = 256 if key == "person" else 200
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var fill := Color(0.62, 0.62, 0.62)
	var shade := Color(0.52, 0.52, 0.52)
	for y: int in range(h):
		for x: int in range(w):
			var p := Vector2(x + 0.5, y + 0.5)
			var d: float = _mannequin(p, w, h) if key == "person" else _block(p, w, h)
			if d > 1.0: continue
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			# a soft side shade so the card reads as a shape, nothing more
			var c: Color = fill.lerp(shade, smoothstep(0.35, 1.0, p.x / w))
			image.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	image.generate_mipmaps()
	var entry: Dictionary = {"texture": ImageTexture.create_from_image(image), "used": Rect2(0, 0, 1, 1), "aspect": float(w) / float(h), "size": Vector2i(w, h)}
	_stand_ins[key] = entry
	return entry

## Signed distance (pixels, <= 0 inside; > 1 outside) of a plain artist's mannequin: an oval head, a neck, a tapered
## trunk, arms hanging, two legs. Proportions of an average adult, nothing else.
static func _mannequin(p: Vector2, w: int, h: int) -> float:
	var s: float = float(h) / 512.0
	var cx: float = w * 0.5
	var d: float = _ellipse(p, Vector2(cx, 44 * s), Vector2(27, 34) * s)
	d = minf(d, _box(p, Vector2(cx, 88 * s), Vector2(11, 12) * s, 4 * s))
	d = minf(d, _taper(p, Vector2(cx, 100 * s), Vector2(cx, 268 * s), 46 * s, 36 * s))
	for side: float in [-1.0, 1.0]:
		d = minf(d, _taper(p, Vector2(cx + side * 50 * s, 112 * s), Vector2(cx + side * 58 * s, 262 * s), 13 * s, 10 * s))
		d = minf(d, _taper(p, Vector2(cx + side * 19 * s, 262 * s), Vector2(cx + side * 21 * s, 500 * s), 17 * s, 11 * s))
		d = minf(d, _ellipse(p, Vector2(cx + side * 25 * s, 502 * s), Vector2(17, 8) * s))
	return d

static func _block(p: Vector2, w: int, h: int) -> float:
	return _box(p, Vector2(w, h) * 0.5, Vector2(w * 0.5 - 3.0, h * 0.5 - 3.0), 22.0)

static func _ellipse(p: Vector2, c: Vector2, r: Vector2) -> float:
	var q: Vector2 = (p - c) / r
	return (q.length() - 1.0) * minf(r.x, r.y)

static func _box(p: Vector2, c: Vector2, half: Vector2, corner: float) -> float:
	var q: Vector2 = (p - c).abs() - half + Vector2(corner, corner)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - corner

## A rounded segment from a to b whose radius goes from ra to rb.
static func _taper(p: Vector2, a: Vector2, b: Vector2, ra: float, rb: float) -> float:
	var ab: Vector2 = b - a
	var t: float = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return (p - (a + ab * t)).length() - lerpf(ra, rb, t)

# ------------------------------------------------------------------------------------------------ credits
## The credits for the art in the pack, one line each, for the Settings page: every slot whose file is there (not the
## test drawings) with its author, licence and permission; then one line naming the slots still waiting for art.
static func credit_lines(lang: String) -> Array[String]:
	var out: Array[String] = []
	var pending: Array[String] = []
	for id: String in slot_ids():
		var s: Dictionary = slot(id)
		if bool(s.test): continue
		if not bool(s.ready):
			pending.append(display_name(s, lang))
			continue
		var c: Dictionary = s.credit
		var parts: Array[String] = [display_name(s, lang)]
		for field: String in ["author", "licence", "permission"]:
			var v: String = str(c.get(field, "")).strip_edges()
			if v != "": parts.append(v)
		out.append(" · ".join(parts))
	if not pending.is_empty():
		out.append(TranslationServer.translate("Licensed art pending: %s.") % ", ".join(pending))
	return out
