extends RefCounted
## Baked figures (tools/mh/mhbake.py): realistic bodies, heads and clothes made from MakeHuman's
## CC0 assets, already posed, sized and weighted for operative.gd's 19-bone rig. A .fig file holds
## the surfaces (skin, suit, boots, hair, eyebrows, eyelashes, eyes) and the measurements the
## procedural kit needs to fit them (torso cross-sections, head, face, neck, shoulders).
const DIR := "res://assets/figures/"
const SKIN_SHADER: Shader = preload("res://shaders/character_skin.gdshader")
const CLOTH_SHADER: Shader = preload("res://shaders/character_cloth.gdshader")
const HAIR_SHADER: Shader = preload("res://shaders/character_hair.gdshader")
const WEAVE_SHADER: Shader = preload("res://shaders/character_weave.gdshader")
## tiles per metre of each tiling cloth (its texture's repeat)
const WEAVE_SCALE := {"weave_felt": 16.0, "weave_twill": 24.0, "weave_knit": 10.5, "weave_steel": 8.0, "weave_leather": 10.0}
const WEAVE_ROUGH := {"weave_steel": 0.62, "weave_leather": 0.42}
const COVER_TINT := Color(0.50, 0.58, 0.46)

static var _figs: Dictionary = {}
static var _materials: Dictionary = {}
static var _covers: Dictionary = {}

static func has(name: String) -> bool:
	return ResourceLoader.exists(DIR + name + ".fig") or FileAccess.file_exists(DIR + name + ".fig")

## {"meta": Dictionary, "surfaces": [{"name", "arrays"}]} (cached; arrays are shared, never edit them)
static func load_fig(name: String) -> Dictionary:
	if _figs.has(name): return _figs[name]
	var f := FileAccess.open(DIR + name + ".fig", FileAccess.READ)
	if f == null: return {}
	var magic := f.get_buffer(4).get_string_from_ascii()
	if magic != "SFG1" and magic != "SFG2": return {}
	var packed := magic == "SFG2" # each surface's arrays deflated as one block
	var head_len := f.get_32()
	var count := f.get_32()
	var meta: Dictionary = JSON.parse_string(f.get_buffer(head_len).get_string_from_utf8())
	var surfaces: Array = []
	for s: int in range(count):
		var name_len := f.get_32()
		var n := f.get_32()
		var ni := f.get_32()
		var raw_len := 0
		var comp_len := 0
		if packed:
			raw_len = f.get_32()
			comp_len = f.get_32()
		var sname := f.get_buffer(name_len).get_string_from_utf8()
		var data: PackedByteArray
		if packed:
			data = f.get_buffer(comp_len).decompress(raw_len, FileAccess.COMPRESSION_DEFLATE)
		else:
			data = f.get_buffer(n * 96 + ni * 4)
		var at := 0
		var pos := data.slice(at, at + n * 12).to_float32_array()
		at += n * 12
		var nrm := data.slice(at, at + n * 12).to_float32_array()
		at += n * 12
		var tng := data.slice(at, at + n * 16).to_float32_array()
		at += n * 16
		var uvf := data.slice(at, at + n * 8).to_float32_array()
		at += n * 8
		var colf := data.slice(at, at + n * 16).to_float32_array()
		at += n * 16
		var bones := data.slice(at, at + n * 16).to_int32_array()
		at += n * 16
		var weights := data.slice(at, at + n * 16).to_float32_array()
		at += n * 16
		var idx := data.slice(at, at + ni * 4).to_int32_array()
		var v := PackedVector3Array()
		var nn := PackedVector3Array()
		var uv := PackedVector2Array()
		var col := PackedColorArray()
		v.resize(n)
		nn.resize(n)
		uv.resize(n)
		col.resize(n)
		for i: int in range(n):
			v[i] = Vector3(pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2])
			nn[i] = Vector3(nrm[i * 3], nrm[i * 3 + 1], nrm[i * 3 + 2])
			uv[i] = Vector2(uvf[i * 2], uvf[i * 2 + 1])
			col[i] = Color(colf[i * 4], colf[i * 4 + 1], colf[i * 4 + 2], colf[i * 4 + 3])
		# MakeHuman winds its faces counter-clockwise; Godot's front faces are clockwise
		for t: int in range(0, idx.size(), 3):
			var keep := idx[t + 1]
			idx[t + 1] = idx[t + 2]
			idx[t + 2] = keep
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = nn
		arrays[Mesh.ARRAY_TANGENT] = tng
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_COLOR] = col
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		arrays[Mesh.ARRAY_INDEX] = idx
		surfaces.append({"name": sname, "arrays": arrays})
	var fig := {"meta": meta, "surfaces": surfaces}
	_figs[name] = fig
	return fig

static func _tex(name: String) -> Texture2D:
	return load(DIR + "tex/" + name + ".png")

## The material for one baked surface of this figure (shared between figures that look alike).
static func material(slot: String, meta: Dictionary, hair_hex: String) -> Material:
	var tex: Dictionary = meta.textures
	var key: String = slot + ":" + str(tex.get(slot, slot)) + ":" + hair_hex + ":" + str(meta.get("skin_mul", []))
	if slot == "suit" and meta.has("suit_gloss"): key += ":gloss" + str(meta.suit_gloss)
	if _materials.has(key): return _materials[key]
	var m := ShaderMaterial.new()
	match slot:
		"suit":
			m.shader = CLOTH_SHADER
			m.set_shader_parameter("detail_tex", _tex(str(tex.suit) + "_detail"))
			m.set_shader_parameter("normal_tex", _tex(str(tex.suit) + "_normal"))
			# an oilskin jacket: the jacket's part of the suit (and a coat's skirt) shines where it catches the light
			if meta.has("suit_gloss"): m.set_shader_parameter("jacket_gloss", float(meta.suit_gloss))
		"hat", "scarf", "gaiters", "jackboots", "coat", "gloves", "cape", "socks":
			var weave := str(tex[slot])
			m.shader = WEAVE_SHADER
			m.set_shader_parameter("detail_tex", _tex(weave))
			m.set_shader_parameter("normal_tex", _tex(weave + "_normal"))
			m.set_shader_parameter("uv_scale", float(WEAVE_SCALE.get(weave, 16.0)))
			m.set_shader_parameter("normal_strength", {"weave_knit": 1.4, "weave_felt": 0.35, "weave_steel": 0.25}.get(weave, 0.8) if slot != "cape" else 0.25)
			m.set_shader_parameter("roughness_value", float(WEAVE_ROUGH.get(weave, 0.95)))
			if weave == "weave_leather": m.set_shader_parameter("sheen", 0.35)
		"hair", "brows", "lashes", "tache":
			m.shader = HAIR_SHADER
			m.set_shader_parameter("albedo_tex", _tex(str(tex[slot])))
			m.set_shader_parameter("hair_color", Color(hair_hex))
			m.set_shader_parameter("recolor", 0.0 if slot == "lashes" else 0.85)
			m.set_shader_parameter("alpha_cut", 0.3 if slot != "hair" else 0.45)
			if slot == "tache":
				m.set_shader_parameter("recolor", 0.45)
				m.set_shader_parameter("alpha_cut", 0.5)
				m.set_shader_parameter("roughness_value", 0.7)
		"eyes":
			# eyeball and cornea; the cornea's part of the texture is clear
			m.shader = HAIR_SHADER
			m.set_shader_parameter("albedo_tex", _tex(str(tex.eyes)))
			m.set_shader_parameter("recolor", 0.0)
			m.set_shader_parameter("alpha_cut", 0.5)
			m.set_shader_parameter("roughness_value", 0.2)
			m.set_shader_parameter("tint", Color(0.80, 0.78, 0.76)) # whites in shadow, not paper
		"boots":
			m.shader = SKIN_SHADER
			m.set_shader_parameter("albedo_tex", _tex(str(tex.boots)))
			m.set_shader_parameter("roughness_value", 0.45)
			m.set_shader_parameter("specular_value", 0.45)
		_:
			m.shader = SKIN_SHADER
			m.set_shader_parameter("albedo_tex", _tex(str(tex.get(slot, "skin_young"))))
			var mul: Array = meta.get("skin_mul", [1.0, 1.0, 1.0])
			m.set_shader_parameter("color_mul", Color(mul[0], mul[1], mul[2]))
	_materials[key] = m
	return m

## The same material, dulled for a body hidden in cover.
static func cover(m: Material) -> Material:
	if _covers.has(m): return _covers[m]
	var c: Material = m.duplicate()
	if c is ShaderMaterial:
		var was: Variant = (m as ShaderMaterial).get_shader_parameter("tint")
		var base: Color = was if was is Color else Color.WHITE
		(c as ShaderMaterial).set_shader_parameter("tint", base * COVER_TINT)
	_covers[m] = c
	return c

## A new mesh with every baked surface of the figure, each with its material. `tints` dyes the figure's clothes
## other colours (a second neighbour from the same bake): {"jacket", "shirt", "trousers", "hat_color", "scarf", "cape":
## "rrggbb"}, each part's baked colour (meta "tints") turned into the new one, its light and shade kept.
static func mesh(name: String, hair_hex: String, tints: Dictionary = {}) -> ArrayMesh:
	var fig := load_fig(name)
	var out := ArrayMesh.new()
	var base: Dictionary = fig.meta.get("tints", {})
	for s: Dictionary in fig.surfaces:
		var arrays: Array = s.arrays
		if not tints.is_empty() and not base.is_empty():
			arrays = _dyed(str(s.name), arrays, base, tints)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, material(s.name, fig.meta, hair_hex))
	return out

## A surface's arrays with its vertex colours dyed (a copy; the cached arrays are never touched). The suit's colour
## alpha says which part of the outfit a vertex is (0 jacket and coat, 1 shirt, 2 trousers); the hat, scarf and cape
## are one cloth each (their metal, alpha 0, is left alone).
static func _dyed(sname: String, arrays: Array, base: Dictionary, tints: Dictionary) -> Array:
	var parts: Array = []
	match sname:
		"suit": parts = ["jacket", "shirt", "trousers"]
		"hat": parts = ["hat_color"]
		"scarf": parts = ["scarf"]
		"cape": parts = ["cape"]
		_: return arrays
	var ratio: Array[Color] = []
	var any := false
	for p: String in parts:
		if tints.has(p) and base.has(p):
			var a := Color(str(base[p]))
			var b := Color(str(tints[p]))
			ratio.append(Color(b.r / maxf(a.r, 0.004), b.g / maxf(a.g, 0.004), b.b / maxf(a.b, 0.004)))
			any = true
		else:
			ratio.append(Color(1, 1, 1))
	if not any: return arrays
	var out := arrays.duplicate()
	var col: PackedColorArray = (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).duplicate()
	for i: int in range(col.size()):
		var c := col[i]
		var r: Color
		if sname == "suit": r = ratio[clampi(roundi(c.a), 0, 2)]
		elif c.a > 0.75: r = ratio[0]
		else: continue
		col[i] = Color(c.r * r.r, c.g * r.g, c.b * r.b, c.a)
	out[Mesh.ARRAY_COLOR] = col
	return out
