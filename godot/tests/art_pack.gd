extends SceneTree
## The art pack (scripts/three_d/art_pack.gd), the paper cut-outs (cutout.gd, operative.gd) and comic ink (ink.gd):
##  - the manifest: slots read and filled in, pending slots, looks that name a slot or a drawing, the credits;
##  - the neutral stand-ins and their plate (a creature with a length: a plain block of its size, its plate turned to
##    the camera);
##  - models: the neutral test models (tools/art_pack.py test-models) scaled to their slot, stood on the ground and
##    centred, their front ("forward") turned the way they walk, a static one moved by the game (a step and a sway; a
##    crawl), a rigged one playing its own animations by name, a creature rolling onto its side when it falls;
##  - a whole level (Riachuelo) whose data dresses people in the pack's drawings: cut-outs in place of the bodies, every
##    state (walking, turned, crouched, hidden, carried, down, dead), the x-ray, the selection ring, the cones;
##  - comic ink: on from the data, off and on again, the settings key, the Settings page's toggle and credits;
##  - the licensed models of the Plaza de Mayo (Juan Salvo, the cascarudo) as the game moves them: Juan on his own
##    skeleton (his clips in step with his speed; crouched with his feet kept on the ground; his rifle raised to his
##    shoulder and toward the target, kicked up by a shot, its muzzle where the flash goes; carrying someone, an arm up
##    over his shoulder and the rifle hanging from the other hand; knocked down flat and up again), his own materials
##    through the finish; the cascarudo moved whole (rearing over the one it knocks down, staggered back by a shot, rolled onto
##    its back dead), its lighter copy far off. Those two are licensed art (Santiago Siri's models, in the
##    repository with permission): in a build without them their slots are pending (the neutral stand-ins show)
##    and the checks of the models themselves are skipped (the suite says so).
## Besides those two, only neutral test drawings and models are used (art_pack/test, made by tools/art_pack.py test-art
## and test-models).
## Run: godot --headless --path godot --script res://tests/art_pack.gd
const ArtPack = preload("res://scripts/three_d/art_pack.gd")
const ComicInk = preload("res://scripts/three_d/ink.gd")
const Operative = preload("res://scripts/three_d/operative.gd")
const Missions = preload("res://scripts/missions.gd")
const Cutout = preload("res://scripts/three_d/cutout.gd")
const DATA: String = "user://art_pack_test_mission.json"
const PACK: String = "user://art_pack_test/"

var main: Node3D
var sim: RefCounted
## Whether the licensed models (Juan Salvo, the cascarudo) are in this checkout (README.md).
var licensed: bool = false
var world: Node3D
var failures: int = 0
var checks: int = 0

func _init() -> void:
	call_deferred("run")

func check(value: bool, label_text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label_text)

func step(seconds: float, dt: float = 0.05) -> void:
	for i in range(int(round(seconds / dt))):
		sim.update(dt)
		world.update_visuals(dt)

func visuals(seconds: float, dt: float = 0.05) -> void:
	for i in range(int(round(seconds / dt))):
		world.update_visuals(dt)

func run() -> void:
	ArtPack.root = "res://art_pack/"
	ArtPack.forget()
	licensed = bool(ArtPack.slot("juan_salvo").get("ready", false)) and bool(ArtPack.slot("cascarudo").get("ready", false))
	if not licensed: print("art_pack: the licensed models are not installed: their own checks are skipped, their slots checked as pending")
	_manifest()
	_pack_elsewhere()
	_stand_ins()
	_block()
	_models()
	_licensed_models()
	await _in_game()
	_cleanup()
	print("ART_PACK_CHECKS=", checks, " FAILURES=", failures)
	quit(0 if failures == 0 else 1)

# ------------------------------------------------------------------------------------------------ the manifest
func _manifest() -> void:
	ArtPack.root = "res://art_pack/"
	ArtPack.forget()
	var ids: Array = ArtPack.slot_ids()
	check("test_walker" in ids and "test_blob" in ids and "juan_salvo" in ids, "The manifest lists its slots")
	var w: Dictionary = ArtPack.slot("test_walker")
	check(bool(w.ready) and str(w.file) == "res://art_pack/test/walker.png" and absf(float(w.height_m) - 1.76) < 0.001, "A slot with its drawing is ready, its path inside the pack, its height in metres")
	check(str(w.views.back).ends_with("walker_back.png") and str(w.views.crouch).ends_with("walker_crouch.png") and str(w.views.down).ends_with("walker_down.png"), "…with its back, crouch and down views")
	check(str(w.kind) == "person" and str(w.faces) == "right" and bool(w.test), "…a person, drawn facing right, a test drawing")
	var p: Dictionary = ArtPack.slot("juan_salvo")
	if licensed: check(bool(p.ready) and bool(p.model) and str(p.file) == "res://art_pack/juan_salvo/juan_salvo.glb" and str(p.name) == "Juan Salvo", "Juan Salvo's slot has its licensed model")
	else: check(not bool(p.ready) and str(p.file) == "" and str(p.name) == "Juan Salvo", "Juan Salvo's slot is pending: no licensed model in this checkout")
	check(str(p.origin) == "model" and str((p.clips as Dictionary).get("walk", "")) == "Walk" and absf(float((p.clip_speed as Dictionary).get("run", 0.0)) - 5.206) < 0.001 and str(p.prop) == "Rifle" and str(p.finish) == "pbr",
		"…standing on its own origin, its clips named and the speed its run was made at, its prop, dressed through its own maps")
	check(ArtPack.slot("nobody").is_empty(), "No slot for an id the manifest does not have")
	# looks
	check(str(ArtPack.parse_look("art:test_blob").id) == "test_blob" and str(ArtPack.parse_look("art:test_blob").kind) == "creature", "art:<slot> names a slot")
	var unknown: Dictionary = ArtPack.parse_look("art:not_yet")
	check(not unknown.is_empty() and not bool(unknown.ready) and str(unknown.name) == "not_yet", "art:<id> the manifest does not list yet is a pending slot under its id")
	var by_path: Dictionary = ArtPack.parse_look("art_pack/test/walker.png")
	check(bool(by_path.ready) and str(by_path.file) == "res://art_pack/test/walker.png" and str(by_path.views.back).ends_with("walker_back.png"), "A look can be a drawing's path; its other views are found beside it by name")
	check(ArtPack.parse_look("guardia1").is_empty() and ArtPack.parse_look("").is_empty() and ArtPack.parse_look("hornero").is_empty(), "The game's own looks are not the art pack's")
	# the drawings
	var d: Dictionary = ArtPack.drawing(str(w.file))
	check(d.texture is ImageTexture and (d.texture as ImageTexture).get_image().has_mipmaps(), "A drawing loads as a texture with mipmaps")
	var used: Rect2 = d.used
	check(used.size.x < 0.75 and used.size.y > 0.85 and absf(float(d.aspect) - 294.0 / 1164.0) < 0.02, "…its transparent margins trimmed (%s, aspect %.3f)" % [used, float(d.aspect)])
	check(ArtPack.drawing("res://art_pack/test/missing.png").is_empty(), "A missing drawing is nothing, not an error")
	# credits: test drawings stay out; the licensed slots with who made them, the licence and the permission
	var en: Array[String] = ArtPack.credit_lines("en")
	var credit: String = "Santiago Siri · permiso para usar en Hora Cero · concedido a Ale, octubre de 2026"
	var hood: String = "The hooded survivor · Ale (Alejandro Vizio), hecho con Codex a partir de fotos de una figura de un amigo artista (por confirmar) · propio; la base de la cabeza, la piel y los ojos son de MakeHuman (CC0 1.0) · de Ale, octubre de 2026"
	if licensed:
		check(en.size() == 3 and en[0] == "Cascarudo · " + credit and en[1] == "Juan Salvo · " + credit and en[2] == hood and not "Test" in " ".join(en) and not "pending" in " ".join(en),
			"The credits name the licensed art, its makers, licence and permission, and leave the test drawings and models out: %s" % [en])
	else:
		check(en == ["Licensed art pending: Cascarudo, Juan Salvo.", hood] or en == [hood, "Licensed art pending: Cascarudo, Juan Salvo."], "No licensed art installed: the credits say what is pending, and leave the test drawings and models out: %s" % [en])
	# the slots of the Plaza de Mayo: Juan Salvo (a person, his portrait rendered from his model) and the cascarudo (a
	# creature 4 m long, as high and wide as its model comes out at that, with a lighter copy for far off)
	var juan: Dictionary = ArtPack.slot("juan_salvo")
	var photo: Dictionary = ArtPack.portrait(juan)
	if licensed:
		check(str(juan.kind) == "person" and str(juan.portrait).ends_with("juan_salvo/portrait.png") and not photo.is_empty() and (photo.size as Vector2i).x >= 464 and (photo.size as Vector2i).y >= 632,
			"Juan Salvo's slot: a person, with his portrait (%s)" % str(photo.get("size", "none")))
	else:
		check(str(juan.kind) == "person" and str(juan.portrait) == "" and photo.is_empty(), "Juan Salvo's slot: a person, no portrait yet (the HUD shows a plain plate with his name)")
	var beast: Dictionary = ArtPack.slot("cascarudo")
	check(bool(beast.ready) == licensed and str(beast.kind) == "creature" and absf(float(beast.height_m) - 3.27) < 0.001 and absf(float(beast.length_m) - 4.0) < 0.001 and absf(float(beast.width_m) - 3.53) < 0.001,
		"the cascarudo's slot: a creature 4 m long (%.2f m high, %.2f wide), its model %s" % [float(beast.height_m), float(beast.width_m), "installed" if licensed else "pending"])
	check((str(beast.lod).ends_with("cascarudo/cascarudo_lod.glb") if licensed else str(beast.lod) == "") and str(beast.forward) == "-z" and str(beast.finish) == "chitin", "…its lighter copy (when installed), its front at -z, dressed as chitin")
	var stand_in: Dictionary = ArtPack.parse_look("art:cascarudo")
	check(licensed or (not bool(stand_in.ready) and float(stand_in.length_m) > float(stand_in.height_m)), "…pending, its stand-in is a plain block as long as the creature")
	check(str(ArtPack.parse_look("art:juan_salvo").credit.get("source", "")).contains("tools/juan_suit.py"), "…and where Juan Salvo's files came from")
	check(ArtPack.slot("criatura_pendiente").is_empty(), "the old pending creature's slot is gone")
	check(is_zero_approx(ArtPack.forward_turn({"forward": "+z"})) and is_equal_approx(ArtPack.forward_turn({"forward": "-z"}), PI) and is_equal_approx(ArtPack.forward_turn({"forward": "+x"}), -PI / 2.0) and is_zero_approx(ArtPack.forward_turn({"forward": "sideways"})), "a model's front: +z by glTF's custom, or as the slot says")

## A pack somewhere else (as a test or a drop-in folder would have it): a slot with credit and its file, one whose file
## is missing, one with a model that cannot be read.
func _pack_elsewhere() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PACK))
	var src: Image = (load("res://art_pack/test/blob.png") as Texture2D).get_image()
	src.save_png(PACK + "thing.png")
	var manifest := {"format": 1, "slots": {
		"cosa": {"name": "Cosa", "name_en": "Thing", "kind": "prop", "height_m": 1.1, "file": "thing.png",
			"credit": {"author": "A. Person", "licence": "CC BY 4.0", "permission": "Written permission, 2026-10-01"}},
		"falta": {"name": "Falta", "kind": "person", "file": "missing.png", "portrait": "thing.png"},
		"modelo": {"name": "Modelo", "kind": "creature", "height_m": 4.0, "file": "missing.glb"}}}
	# a plain box saved as a GLB, as a model dropped into the pack would be
	var box_scene := Node3D.new()
	var box := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1.0, 2.0, 0.5)
	box.mesh = box_mesh
	box.name = "Box"
	box_scene.add_child(box)
	box.owner = box_scene
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	check(doc.append_from_scene(box_scene, state) == OK and doc.write_to_filesystem(state, ProjectSettings.globalize_path(PACK + "box.glb")) == OK, "A test model is written as a GLB")
	box_scene.free()
	manifest.slots["caja"] = {"name": "Caja", "kind": "prop", "height_m": 1.5, "file": "box.glb", "credit": {"author": "x", "licence": "CC0", "permission": "own"}}
	var f := FileAccess.open(PACK + "manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest))
	f.close()
	ArtPack.root = PACK
	ArtPack.forget()
	var cosa: Dictionary = ArtPack.slot("cosa")
	check(bool(cosa.ready) and str(cosa.file) == PACK + "thing.png" and str(cosa.kind) == "prop", "A pack in another folder: its files are read from there")
	check(not bool(ArtPack.slot("falta").ready), "A slot whose file is not there is pending")
	var photo: Dictionary = ArtPack.portrait(ArtPack.slot("falta"))
	check(not photo.is_empty() and photo.texture is Texture2D, "A slot's portrait (the HUD's photo) is read from the pack, art or no art")
	check(bool(ArtPack.slot("modelo").model) and not bool(ArtPack.slot("modelo").ready), "A model slot is known as one")
	var es: Array[String] = ArtPack.credit_lines("es")
	check(es.size() == 3 and es[1] == "Cosa · A. Person · CC BY 4.0 · Written permission, 2026-10-01" and "Falta" in es[2] and "Modelo" in es[2], "Credits: name, author, licence, permission; then what is pending: %s" % [es])
	check(ArtPack.credit_lines("en")[1].begins_with("Thing · "), "…named in the player's language")
	# a model slot: read at run time, stood up at the slot's height
	var caja: Dictionary = ArtPack.slot("caja")
	check(bool(caja.ready) and bool(caja.model) and ArtPack.model(str(caja.file)) is PackedScene, "A GLB dropped into the pack is read at run time")
	var figure: Node3D = Cutout.new()
	figure.setup(caja)
	check(figure.model != null and figure.card == null and absf(float(figure.width_m) - 0.75) < 0.01, "A model slot stands the model in place of a card, scaled to its height (%.2f m wide)" % float(figure.width_m))
	figure.pose({"root": Vector3(3, 0, 4), "offset": Vector3.ZERO, "yaw": 0.5, "phase": 0.0, "move": 0.0, "run": 0.0, "crouch": 0.0, "lie": 0.0,
		"carried": 0.0, "carry": Transform3D.IDENTITY, "hidden": 0.0, "covered": false, "clock": 0.0, "camera": null})
	check(figure.transform.origin.is_equal_approx(Vector3(3, 0, 4)) and absf(figure.transform.basis.get_scale().y - 0.75) < 0.01, "…on the ground where he stands, turned his way")
	figure.pose({"root": Vector3(3, 0, 4), "offset": Vector3.ZERO, "yaw": 0.5, "phase": 0.0, "move": 0.0, "run": 0.0, "crouch": 0.0, "lie": 1.0,
		"carried": 0.0, "carry": Transform3D.IDENTITY, "hidden": 0.0, "covered": false, "clock": 0.0, "camera": null})
	check(absf(figure.transform.basis.y.normalized().y) < 0.05, "…and laid down when he falls")
	figure.free()
	ArtPack.root = "res://art_pack/"
	ArtPack.forget()

## A creature's slot with a length and no art: a plain grey block of its size (no card), its ink edge, its plate; lying the
## way it walks, the plate turned to the camera; rolled onto its side, resting on its flank, when it falls.
func _block() -> void:
	var beast: Dictionary = ArtPack._normal("bloque", {"name": "Bloque", "kind": "creature", "height_m": 2.0, "length_m": 4.0, "width_m": 1.8})
	var figure: Node3D = Cutout.new()
	root.add_child(figure)
	figure.setup(beast)
	check(figure.card == null and figure.model != null and figure.pending and (figure.block_size as Vector3).is_equal_approx(Vector3(float(beast.width_m), 2.0, 4.0)), "A creature's stand-in is a plain block of its slot's size (%s)" % str(figure.block_size))
	var grey: StandardMaterial3D = (figure.model.get_node("Body") as MeshInstance3D).material_override
	check(grey.albedo_color.s < 0.05 and grey.albedo_texture == null, "plain grey, nothing drawn on it")
	var words: Array[String] = []
	for child: Node in figure.plate.get_children():
		if child is Label3D: words.append((child as Label3D).text)
	check(words == ["LICENSED ART PENDING", "BLOQUE"], "with its plate: %s" % str(words))
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_transform = Transform3D(Basis.looking_at(Vector3(-1, -1, -1).normalized()), Vector3(20, 20, 20))
	var p := {"root": Vector3(3, 0, 4), "offset": Vector3.ZERO, "yaw": PI / 2.0, "phase": 0.0, "move": 0.0, "run": 0.0, "crouch": 0.0, "lie": 0.0,
		"carried": 0.0, "carry": Transform3D.IDENTITY, "hidden": 0.0, "covered": false, "clock": 0.0, "camera": cam}
	figure.pose(p)
	check(figure.global_basis.z.normalized().x > 0.99, "walking east, it lies east-west")
	var to_cam := Vector3(cam.global_basis.z.x, 0, cam.global_basis.z.z).normalized()
	check(figure.plate.global_basis.z.normalized().dot(to_cam) > 0.99 and figure.plate.global_position.distance_to(Vector3(3, 1, 4)) < 2.6, "its plate stands on the side the camera sees")
	p.lie = 1.0
	figure.pose(p)
	var body: MeshInstance3D = figure.model.get_node("Body")
	var low: AABB = body.global_transform * body.get_aabb()
	check(absf(figure.global_basis.y.normalized().y) < 0.3 and absf(low.position.y) < 0.35, "fallen, it lies on its side on the ground (lowest %.2f m)" % low.position.y)
	cam.free()
	figure.free()

## The neutral test models: a static capsule (centimetres, off its origin), a static block with its front at +x, a rigged
## post with its own "Idle" and "Walk".
func _models() -> void:
	ArtPack.forget()
	var capsule: Dictionary = ArtPack.slot("test_capsule")
	check(bool(capsule.ready) and bool(capsule.model) and ArtPack.model(str(capsule.file)) is PackedScene, "The test capsule (a .glb in the pack) loads")
	var figure: Node3D = Cutout.new()
	root.add_child(figure)
	figure.setup(capsule)
	var p := {"root": Vector3(10, 0, 10), "offset": Vector3.ZERO, "yaw": 0.0, "phase": 0.0, "move": 0.0, "run": 0.0, "crouch": 0.0, "lie": 0.0,
		"carried": 0.0, "carry": Transform3D.IDENTITY, "hidden": 0.0, "covered": false, "clock": 0.0, "camera": null}
	figure.pose(p)
	var box: AABB = _bounds(figure.model)
	check(absf(box.size.y - 1.8) < 0.03 and absf(box.position.y) < 0.03, "modelled 170 units tall and 30 off the ground, it stands 1.8 m tall on the ground (%s)" % str(box))
	check(Vector2(box.get_center().x - 10.0, box.get_center().z - 10.0).length() < 0.12, "centred on his spot, though modelled 50 units to the side")
	# static: it steps and sways as he walks, breathes standing still
	var tops: Array[float] = []
	var rolls: Array[float] = []
	for i: int in range(12):
		p.move = 1.0
		p.phase = float(i) / 12.0
		figure.pose(p)
		tops.append(figure.global_position.y)
		rolls.append(figure.global_basis.x.normalized().y)
	check(tops.max() - tops.min() > 0.02 and rolls.max() - rolls.min() > 0.03 and str(figure.playing) == "", "a static model steps and sways as he walks (%.3f m, %.3f)" % [tops.max() - tops.min(), rolls.max() - rolls.min()])
	p.move = 0.0
	var heights: Array[float] = []
	for i: int in range(8):
		p.clock = float(i) * 0.5
		figure.pose(p)
		heights.append(figure.global_basis.y.length())
	check((heights.max() - heights.min()) / heights.max() > 0.01, "and breathes standing still")
	figure.free()
	# the block, its front at +x: turned so that its front leads
	var block: Dictionary = ArtPack.slot("test_crawler")
	check(str(block.forward) == "+x" and str(block.kind) == "creature", "The test block's front is +x")
	var crawler: Node3D = Cutout.new()
	root.add_child(crawler)
	crawler.setup(block)
	p.yaw = PI / 2.0
	p.move = 0.0
	p.phase = 0.0
	crawler.pose(p)
	var front: Vector3 = (crawler.global_basis * Vector3(1, 0, 0)).normalized()
	check(front.x > 0.97, "walking east, its front (+x as modelled) leads (%s)" % str(front))
	var rolls2: Array[float] = []
	for i: int in range(12):
		p.move = 1.0
		p.phase = float(i) / 12.0
		crawler.pose(p)
		rolls2.append(crawler.global_basis.y.normalized().dot((crawler.global_basis * Vector3(0, 0, 1)).normalized().cross(Vector3.UP).normalized()))
	check(rolls2.max() - rolls2.min() > 0.04, "a static creature crawls: it rolls from side to side (%.3f)" % (rolls2.max() - rolls2.min()))
	p.move = 0.0
	p.lie = 1.0
	for i: int in range(60):
		p.clock = float(i) * 0.05
		crawler.pose(p)
	check(crawler.global_basis.y.normalized().y < -0.5, "dead, a creature rolls over onto its back (%.2f)" % crawler.global_basis.y.normalized().y)
	p.clock = 0.0
	crawler.free()
	# the rigged post: its own animations, by name in any case
	var post: Node3D = Cutout.new()
	root.add_child(post)
	post.setup(ArtPack.slot("test_rigged"))
	p.lie = 0.0
	p.yaw = 0.0
	check(post.get("_anim") != null, "The rigged post keeps its animation player")
	p.move = 1.0
	post.pose(p)
	check(str(post.playing) == "Walk", "walking: its own \"Walk\" (%s)" % str(post.playing))
	p.move = 0.0
	post.pose(p)
	check(str(post.playing) == "Idle", "standing: its own \"Idle\" (%s)" % str(post.playing))
	p.lie = 1.0
	post.pose(p)
	check(str(post.playing) == "" and absf(post.global_basis.y.normalized().y) < 0.1, "down with no animation for it: laid down by the game")
	post.free()

## The two licensed models as the game moves them (cutout.gd, rig_person.gd, creature_body.gd); skipped where they are
## not installed.
func _licensed_models() -> void:
	ArtPack.root = "res://art_pack/"
	ArtPack.forget()
	if not licensed: return
	var juan: Node3D = Cutout.new()
	root.add_child(juan)
	juan.setup(ArtPack.slot("juan_salvo"))
	check(juan.rig != null and juan.rig.has_prop and str(juan.rig.grip) == "r", "Juan Salvo's model: moved on his own skeleton, his rifle in his hands, his right on the stock (its butt the broad end)")
	check(juan.call("_model_meshes").size() <= 14, "…his parts on his skeleton (%d)" % juan.call("_model_meshes").size())
	var clock: Array[float] = [0.0]
	var pose := func(extra: Dictionary, seconds: float) -> void:
		for i: int in range(int(round(seconds / 0.05))):
			clock[0] += 0.05
			var p := {"root": Vector3.ZERO, "offset": Vector3.ZERO, "yaw": 0.0, "phase": 0.0, "move": 0.0, "run": 0.0, "crouch": 0.0,
				"lie": 0.0, "carried": 0.0, "carry": Transform3D.IDENTITY, "hidden": 0.0, "covered": false, "clock": clock[0], "camera": null,
				"speed": 0.0, "aim": 0.0, "pitch": 0.0, "recoil": -1.0, "hold": 0.0, "down": 0.0, "state": "", "hits": 0}
			p.merge(extra, true)
			juan.pose(p)
	var sk: Skeleton3D = juan.rig.skel
	var bone := func(role: String) -> Vector3: return sk.global_transform * sk.get_bone_global_pose(int(juan.rig.roles[role])).origin
	pose.call({}, 1.0)
	var head_up: float = (bone.call("head") as Vector3).y
	var tip: Vector3 = juan.muzzle()
	# (his head bone is at the base of his skull, and his Idle stands with soft knees)
	check(head_up > 1.45 and tip.y < 1.3, "standing: his own Idle, the rifle held low across him (head %.2f, muzzle %.2f m up)" % [head_up, tip.y])
	# walking at the squad's pace (2.6 m/s): his Walk, not his Run, at the neighbours' cadence (operative.gd: about 3 steps
	# a second), the feet passing each other, a foot on the ground staying where it was put (he stands still here: the
	# ground goes by under him at his speed)
	var walk_at := func(speed: float, extra: Dictionary) -> Dictionary:
		var gaps: Array[float] = []
		var low := {"l": INF, "r": INF}
		var trail := {"l": [], "r": []}
		var t: float = 0.0
		extra.merge({"move": 1.0, "speed": speed}, true)
		pose.call(extra, 1.0)
		for i: int in range(48):
			pose.call(extra, 0.05)
			t += 0.05
			gaps.append((bone.call("foot_l") as Vector3).distance_to(bone.call("foot_r")))
			for side: String in ["l", "r"]:
				var f: Vector3 = bone.call("foot_" + side)
				low[side] = minf(float(low[side]), f.y)
				(trail[side] as Array).append(Vector3(f.x, f.y, f.z + speed * t))
		# the most a foot drifts over the ground while it is down (within 1 cm of its lowest)
		var drift: float = 0.0
		for side: String in ["l", "r"]:
			var at := Vector3.INF
			for f: Vector3 in trail[side]:
				if f.y < float(low[side]) + 0.01:
					if at == Vector3.INF: at = f
					drift = maxf(drift, Vector2(f.x - at.x, f.z - at.z).length())
				else:
					at = Vector3.INF
		return {"spread": gaps.max() - gaps.min(), "steps": 2.0 * speed / juan.rig.step_stride, "drift": drift, "run": juan.rig._run}
	var w: Dictionary = walk_at.call(2.6, {})
	check(float(w.run) < 0.05 and float(w.spread) > 0.3, "walking at the squad's pace: his Walk, not his Run, the feet passing each other (%.2f m)" % float(w.spread))
	check(float(w.steps) > 2.7 and float(w.steps) < 3.6, "…at the neighbours' cadence (%.2f steps a second; theirs about 3)" % float(w.steps))
	check(float(w.drift) < 0.05, "…a foot on the ground staying put (it drifts %.3f m)" % float(w.drift))
	# his Run only for real running, past the squad's pace
	check(float(walk_at.call(2.9, {}).run) < 0.05, "still walking just past the squad's pace (2.9 m/s)")
	var r: Dictionary = walk_at.call(3.6, {})
	check(float(r.run) > 0.9 and float(r.spread) > 0.3, "running (3.6 m/s): his Run, stride by stride (%.2f m)" % float(r.spread))
	# carrying someone (1.56 m/s): walking, at the neighbours' cadence carrying (about 3 steps a second)
	var c: Dictionary = walk_at.call(1.56, {"hold": 1.0})
	check(float(c.run) < 0.05 and float(c.steps) > 2.6 and float(c.steps) < 3.5 and float(c.drift) < 0.05,
		"carrying at the neighbours' cadence: %.2f steps a second, a foot on the ground drifting %.3f m" % [float(c.steps), float(c.drift)])
	pose.call({}, 1.0)
	# crouched: the head down, the feet still on the ground
	pose.call({"crouch": 1.0}, 1.0)
	check((bone.call("head") as Vector3).y < head_up - 0.25 and (bone.call("foot_l") as Vector3).y < 0.25 and (bone.call("foot_r") as Vector3).y < 0.25,
		"crouched: lower by %.2f m, his feet kept on the ground" % (head_up - (bone.call("head") as Vector3).y))
	# aiming: the rifle up at his shoulder and out along the line he faces (+z here); a shot kicks the muzzle up
	pose.call({"aim": 1.0}, 1.0)
	tip = juan.muzzle()
	var shoulder: float = (bone.call("arm_r") as Vector3).y
	check(absf(tip.y - shoulder) < 0.2 and tip.z > 0.75 and absf(tip.x) < 0.4, "aiming: the muzzle out ahead at his shoulder's height (%s)" % str(tip))
	pose.call({"aim": 1.0, "recoil": 0.05}, 0.05)
	check((juan.muzzle() as Vector3).y > tip.y + 0.03, "a shot kicks it up (%.2f m)" % ((juan.muzzle() as Vector3).y - tip.y))
	# carrying someone over his right shoulder: that hand up by it, the rifle down in the other hand
	pose.call({"hold": 1.0, "move": 1.0, "speed": 1.56}, 1.0)
	var grip: String = str(juan.rig.grip)
	var other: String = "l" if grip == "r" else "r"
	# (his shoulder: the upper arm's root, which sits a little higher on a skeleton with collarbones)
	check((bone.call("hand_" + grip) as Vector3).y > shoulder - 0.2 and (bone.call("hand_" + other) as Vector3).y < 1.15 and juan.rig._run < 0.1,
		"carrying: an arm up over the one on his shoulder, the rifle hanging from the other hand, walking (hands %.2f and %.2f m, shoulder %.2f, run %.2f, grip %s)" % [(bone.call("hand_" + grip) as Vector3).y, (bone.call("hand_" + other) as Vector3).y, shoulder, juan.rig._run, grip])
	# knocked down: flat on the ground; then up again
	pose.call({"down": 1.0}, 2.0)
	check((bone.call("head") as Vector3).y < 0.55 and (bone.call("hips") as Vector3).y < 0.5, "knocked down: flat on his back (head %.2f m up)" % (bone.call("head") as Vector3).y)
	pose.call({}, 0.75)
	var rising: float = (bone.call("head") as Vector3).y
	pose.call({}, 1.2)
	check(rising > 0.55 and rising < head_up - 0.2 and (bone.call("head") as Vector3).y > head_up - 0.05, "and up again by way of a knee (%.2f m half way)" % rising)
	juan.free()
	# the cascarudo
	var beast: Node3D = Cutout.new()
	root.add_child(beast)
	beast.setup(ArtPack.slot("cascarudo"))
	check(beast.beast != null and beast.get("_lod_mesh") is Mesh, "the cascarudo's model: moved whole, with its lighter copy")
	var t: Array[float] = [0.0]
	var crawl := func(extra: Dictionary, seconds: float) -> void:
		for i: int in range(int(round(seconds / 0.05))):
			t[0] += 0.05
			var p := {"root": Vector3.ZERO, "offset": Vector3.ZERO, "yaw": 0.0, "phase": t[0], "move": 0.0, "run": 0.0, "crouch": 0.0, "lie": 0.0,
				"carried": 0.0, "carry": Transform3D.IDENTITY, "hidden": 0.0, "covered": false, "clock": t[0], "camera": null, "speed": 0.0,
				"state": "prowl", "hits": 0}
			p.merge(extra, true)
			beast.pose(p)
	crawl.call({}, 0.5)
	var front: Vector3 = (beast.global_basis * Vector3(0, 0, -1)).normalized()
	check(front.z > 0.95 and absf(beast.global_position.y) < 0.05, "facing the way it goes, on the ground")
	# its legs, rigged by tools/art_pack.py rig-creature: six, in two tripods
	var body: RefCounted = beast.beast
	var tripods: Array[float] = []
	for leg: Dictionary in body.legs: tripods.append(float(leg.offset))
	check(bool(body.rigged) and body.legs.size() == 6 and tripods.count(0.0) == 3 and tripods.count(0.5) == 3, "its six legs on its own skeleton, in two tripods (%s)" % str(tripods))
	var bsk: Skeleton3D = body.skel
	var feet := func() -> Array:
		var out: Array = []
		for leg: Dictionary in body.legs: out.append(bsk.global_transform * bsk.get_bone_global_pose(int(bsk.find_bone(str(leg.name) + "_tip"))).origin)
		return out
	var at: Array = [Vector3.ZERO, 0.0]
	var walk := func(extra: Dictionary, seconds: float, speed: float, turn: float, track: Array) -> void:
		for i: int in range(int(round(seconds / 0.05))):
			t[0] += 0.05
			at[1] = float(at[1]) + turn * 0.05
			at[0] = (at[0] as Vector3) + Vector3(sin(float(at[1])), 0, cos(float(at[1]))) * speed * 0.05
			var p := {"root": at[0], "offset": Vector3.ZERO, "yaw": at[1], "phase": 0.0, "move": 1.0 if speed > 0.0 else 0.0, "run": 0.0,
				"crouch": 0.0, "lie": 0.0, "carried": 0.0, "carry": Transform3D.IDENTITY, "hidden": 0.0, "covered": false, "clock": t[0],
				"camera": null, "speed": speed, "state": "prowl", "hits": 0}
			p.merge(extra, true)
			beast.pose(p)
			track.append(feet.call())
	var steps: Array = []
	walk.call({}, 3.0, 1.25, 0.0, steps)
	var lift: float = 0.0
	var skate: float = 0.0
	var kept: Array[bool] = []
	for k: int in range(6): kept.append(true)
	for f: int in range(1, steps.size()):
		for k: int in range(6):
			var a: Vector3 = steps[f - 1][k]
			var b: Vector3 = steps[f][k]
			lift = maxf(lift, b.y)
			# on the ground in both frames: it must not have slid
			if a.y < 0.02 and b.y < 0.02: skate = maxf(skate, Vector2(b.x - a.x, b.z - a.z).length())
	var first: Array = steps[0]
	var last: Array = steps[steps.size() - 1]
	var kept_up: bool = true
	for k: int in range(6): kept_up = kept_up and ((last[k] as Vector3).z - (first[k] as Vector3).z) > 2.0
	check(lift > 0.2 and skate < 0.02 and kept_up, "walking: each foot lifts (%.2f m), swings forward and is set down; one on the ground never slides (%.3f m a frame)" % [lift, skate])
	# turning on the spot: the feet shuffle round
	var turning: Array = []
	walk.call({}, 2.0, 0.0, 1.5, turning)
	var moved: int = 0
	for k: int in range(6):
		if (turning[0][k] as Vector3).distance_to(turning[turning.size() - 1][k]) > 0.3: moved += 1
	check(moved >= 5, "turning on the spot its feet shuffle round (%d of 6 moved)" % moved)
	# alerted, it rushes with its front claws flung up
	var rush: Array = []
	walk.call({"state": "stalk"}, 0.3, 2.2, 0.0, rush)
	var fronts: Array = []
	for k: int in range(6):
		if bool(body.legs[k].front): fronts.append(k)
	var high: float = 0.0
	for f: Array in rush:
		var lowest: float = INF
		for k: int in fronts: lowest = minf(lowest, (f[k] as Vector3).y)
		high = maxf(high, lowest)
	check(fronts.size() == 2 and high > 0.6, "rushing, its front claws flung up (%.2f m off the ground)" % high)
	at[0] = Vector3.ZERO
	at[1] = 0.0
	crawl.call({}, 0.3)
	crawl.call({"state": "stay"}, 1.2)
	front = (beast.global_basis * Vector3(0, 0, -1)).normalized()
	check(front.y > 0.35, "over the one it knocked down it rears up (%.2f)" % front.y)
	crawl.call({"state": "stay"}, 3.0)
	crawl.call({"state": "driven", "hits": 1}, 0.15)
	check(beast.global_position.z < -0.15, "shot, it staggers back (%.2f m)" % beast.global_position.z)
	crawl.call({"state": "dead", "hits": 3}, 3.0)
	check(beast.global_basis.y.normalized().y < -0.7, "dead, it lies on its back, its legs in the air (%.2f)" % beast.global_basis.y.normalized().y)
	beast.free()

static func _bounds(model: Node3D) -> AABB:
	var box := AABB()
	var first: bool = true
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var b: AABB = mi.global_transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
	return box

func _stand_ins() -> void:
	var person: Dictionary = ArtPack.stand_in("person")
	var block: Dictionary = ArtPack.stand_in("creature")
	check(person.texture is Texture2D and float(person.aspect) < 0.5, "The stand-in for a person is a tall mannequin card")
	check(block.texture is Texture2D and float(block.aspect) > 0.6 and ArtPack.stand_in("prop") == block, "…for anything else, a plain block")
	# the stand-in is plain grey: no colour, no dark details (nothing that hints at a face, a mask or a visor)
	var image: Image = (person.texture as Texture2D).get_image()
	if image.is_compressed(): image.decompress()
	var lo: float = 1.0
	var hi: float = 0.0
	var tinted: bool = false
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var c: Color = image.get_pixel(x, y)
			if c.a < 0.9: continue
			lo = minf(lo, c.get_luminance())
			hi = maxf(hi, c.get_luminance())
			tinted = tinted or maxf(absf(c.r - c.g), absf(c.g - c.b)) > 0.03
	check(not tinted and hi - lo < 0.2 and lo > 0.35, "The stand-in is a flat grey (%.2f..%.2f), with nothing drawn on it" % [lo, hi])

# ------------------------------------------------------------------------------------------------ in the game
func _in_game() -> void:
	# Riachuelo, dressed from the data in the pack's drawings, and asking for comic ink: Biguá in the test drawing,
	# Lechuza as Juan Salvo, guards as the test creature, a drawing by its path and a slot with no art
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/riachuelo.json"))
	data["ink"] = true
	for unit: Dictionary in data.units:
		if str(unit.id) == "bigua": unit["look"] = "art:test_walker"
		if str(unit.id) == "lechuza": unit["look"] = "art:juan_salvo"
	for guard: Dictionary in data.guards:
		if str(guard.id) == "north":
			guard["look"] = "art:test_blob"
			guard["look_height"] = 3.0
		if str(guard.id) == "west": guard["look"] = "art_pack/test/walker.png"
		if str(guard.id) == "east": guard["look"] = "art:aun_no"
	var f := FileAccess.open(DATA, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	Missions.LIST.append({"id": "art_pack_test", "path": DATA, "number": "99", "tab": "ART PACK", "name": "Art pack test", "best": "best_art_pack_test"})
	Missions.choose("art_pack_test", false)
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	main.set("auto_command_on_alarm", false)
	for i in range(8): await process_frame
	sim = main.sim
	world = main.world
	main.set_process(false)
	main._command("begin")
	world.update_visuals(0.1)
	var walker: Node3D = world.actors.bigua
	var bearer: Node3D = world.actors.lechuza
	var g1: Node3D = world.actors.north
	var g2: Node3D = world.actors.west
	# --- dressed from the data
	check(walker.cutout != null and not walker.body.visible and walker.cutout.card != null and not walker.cutout.pending, "Biguá's data look is the test drawing: a cut-out in place of his body")
	check(walker.cutout.views.has("front") and walker.cutout.views.has("back") and walker.cutout.views.has("crouch") and walker.cutout.views.has("down"), "…with all four of its views")
	check(absf(float(walker.cutout.height_m) - 1.76) < 0.001 and absf(float(walker.height) - 1.76 / ArtPack.RIG_HEIGHT) < 0.001, "…as tall as the slot says, his rig sized to it")
	if licensed:
		check(bearer.cutout != null and not bearer.cutout.pending and bearer.cutout.plate == null and bearer.cutout.model != null and bearer.cutout.rig != null and not bearer.body.visible,
			"Lechuza in Juan Salvo's licensed model: moved on its own skeleton, no plate")
		check(bearer.cutout.muzzle() is Vector3, "…his rifle in his hands, its muzzle known for the flash")
	else:
		check(bearer.cutout != null and bearer.cutout.pending and bearer.cutout.plate != null and not bearer.body.visible, "Lechuza as Juan Salvo, not installed: the neutral mannequin with its plate")
	var g4: Node3D = world.actors.east
	check(g4.cutout != null and g4.cutout.pending and g4.cutout.plate != null, "A slot with no art yet: the stand-in, with its plate")
	var words: Array[String] = []
	for child: Node in g4.cutout.plate.get_children():
		if child is Label3D: words.append((child as Label3D).text)
	check(words.size() == 2 and words[0] == "LICENSED ART PENDING" and words[1] == "AUN_NO", "The plate reads LICENSED ART PENDING and the slot's name: %s" % [words])
	check(g1.cutout != null and absf(float(g1.cutout.height_m) - 3.0) < 0.001 and g1.ui_scale > 1.5, "A guard as the big test creature, %.1f m from the data's look_height; his ring and shadow grow with him" % float(g1.cutout.height_m))
	check(g2.cutout != null and not g2.cutout.pending and g2.cutout.views.has("back"), "A guard dressed by a drawing's path")
	check(world.actors.middle.cutout == null and world.actors.middle.body.visible, "Everyone else keeps his modelled figure")
	check(world.cone_nodes.has("north") and world.cone_nodes.north.visible, "A cut-out guard has his sight cone like any other")
	# --- standing, then walking: bob, rock, lean; turned the way he walks
	var card: Node3D = walker.cutout
	var still_y: float = card.global_position.y - walker.global_position.y
	check(absf(still_y) < 0.05 and card.global_basis.y.normalized().y > 0.98, "Standing, the card stands upright on his spot")
	var cam: Camera3D = root.get_camera_3d()
	var to_cam := Vector3(cam.global_basis.z.x, 0, cam.global_basis.z.z).normalized()
	check(card.global_basis.z.normalized().dot(to_cam) > 0.97, "…turned to the camera")
	sim.select("bigua")
	sim.unit_by_id("bigua").stance = "walk"
	var right := Vector3.UP.cross(to_cam).normalized()
	var start: Vector2 = sim.position_of(sim.unit_by_id("bigua"))
	sim.move_to(start + Vector2(right.x, right.z) * 160.0)
	var ys: Array[float] = []
	var tilts: Array[float] = []
	for i in range(30):
		step(0.05)
		ys.append(card.global_position.y - walker.global_position.y)
		tilts.append(card.global_basis.x.normalized().y)
	check(ys.max() - ys.min() > 0.02, "Walking, the card bobs at each step (%.3f m)" % (ys.max() - ys.min()))
	check(tilts.max() - tilts.min() > 0.03, "…and rocks from foot to foot")
	check(not card.flipped, "Walking to the right of the screen, the drawing (drawn facing right) is as drawn")
	sim.move_to(sim.position_of(sim.unit_by_id("bigua")) - Vector2(right.x, right.z) * 200.0)
	step(1.0)
	check(card.flipped, "…walking to the left, it is mirrored")
	sim.move_to(sim.position_of(sim.unit_by_id("bigua")) - Vector2(to_cam.x, to_cam.z) * 160.0)
	step(1.2)
	check(card.view == "back", "Walking away from the camera, his back view")
	sim.unit_by_id("bigua").path = []
	sim.unit_by_id("bigua").order = {}
	step(0.6)
	# --- crouched: the crouch drawing
	sim.unit_by_id("bigua").stance = "sneak"
	step(1.0)
	check(card.view == "crouch", "Crouched, the crouch drawing")
	sim.unit_by_id("bigua").stance = "walk"
	step(1.0)
	check(card.view != "crouch", "…and up again")
	# a drawing without a crouch view is squashed instead
	var blob: Node3D = g1.cutout
	check(not blob.views.has("crouch"), "The test creature has no crouch view")
	# --- hidden in cover: dulled
	sim.unit_by_id("bigua").hidden = true
	visuals(1.0)
	check(card._tint.r < 0.95, "In cover the cut-out is dulled")
	sim.unit_by_id("bigua").hidden = false
	visuals(1.0)
	check(card._tint.is_equal_approx(Color(1, 1, 1, 1)), "…and himself again out of it")
	# --- x-ray: the card has the figures' two passes, and the tint
	check(card.card.material_overlay != null and card.card.material_overlay.next_pass != null, "The card carries the x-ray's mark and tint passes")
	world.draw_vision = false
	world.update_visuals(0.05)
	check(card.card.material_overlay == null, "…none while the cones are off")
	world.draw_vision = true
	world.update_visuals(0.05)
	check(card.card.material_overlay != null, "…and back with them")
	# --- down: a guard's card falls flat
	sim._fell(sim.guard_by_id("west"), "dead")
	visuals(2.0)
	var down: Node3D = g2.cutout
	check(down.view == "down" and absf(down.global_basis.y.normalized().y) < 0.1, "A dead guard's card lies flat on the ground, his down view")
	check(not world.cone_nodes.west.visible, "…and his cone is gone")
	sim._fell(sim.guard_by_id("north"), "stunned")
	visuals(2.0)
	check(absf(blob.global_basis.y.normalized().y) < 0.1 and blob.view == "front", "A card with no down view is laid flat as it is")
	# --- carried: over the bearer's shoulder
	var g1d: Dictionary = sim.guard_by_id("north")
	var bearer_d: Dictionary = sim.unit_by_id("lechuza")
	g1d.x = bearer_d.x + 10.0
	g1d.y = bearer_d.y
	g1d.state = "dead"
	g1d.carried_by = "lechuza"
	bearer_d.carrying = "north"
	visuals(2.0)
	check(g1.w_carried > 0.99 and blob.global_position.distance_to(bearer.global_position) < 2.5 and blob.global_position.y > 0.8, "Carried, the creature's card rides on the bearer (at %s, bearer at %s)" % [blob.global_position, bearer.global_position])
	check(absf(blob.global_basis.x.normalized().y) > 0.9, "…lying across his shoulder")
	g1d.carried_by = ""
	bearer_d.carrying = ""
	visuals(2.0)
	check(blob.global_position.y < 0.5, "Put down, it is on the ground again")
	# --- an operative's death: his own down view
	sim.unit_by_id("bigua").alive = false
	visuals(2.0)
	check(card.view == "down" and absf(card.global_basis.y.normalized().y) < 0.1, "A fallen operative's cut-out lies down")
	# --- a re-dress back to a modelled figure frees the cut-out
	var plain: Dictionary = Operative._look("middle", true, "patrol", "guardia0")
	g2._dress(plain, "west")
	check(g2.cutout == null and g2.body.visible and g2.body.mesh != null, "Dressed in a modelled figure again, the body is back and the card gone")
	# --- comic ink: on from the data
	var ink: Node3D = world.comic_ink
	check(world.ink_enabled() and ink.quad.visible and ink.paper_layer.visible, "The data's \"ink\": true draws the operation in comic ink")
	var grade: CanvasLayer = world.atmosphere.get("_grade_layer")
	var env: Environment = world.atmosphere.environment.environment
	check(not grade.visible and env.tonemap_mode == Environment.TONE_MAPPER_LINEAR and env.tonemap_exposure == 1.0 and not env.glow_enabled, "…the grade gives way to the print pass, the tonemapper passes the drawing through")
	check(ink.lines_material.render_priority == ComicInk.PRIORITY and ink.lines_material.render_priority < world.cone_nodes.middle.material_override.render_priority, "The drawing pass comes before the sight cones, which keep their colour over it")
	var cream: Color = world._spot(world.INK)
	var blue: Color = world._spot(Color("#b6c3d9"))
	check(cream.is_equal_approx(Color(world.SPOT_INK, 1.0)) and blue.r > blue.b and blue.s > 0.6, "In ink the game's pale marks print in vermilion, a blue one in red-violet (the print pass keeps warm colour)")
	check(Operative._ui_material.albedo_color != Color.WHITE, "…and the selection ring too")
	world.set_ink(false)
	check(not ink.quad.visible and not ink.paper_layer.visible and grade.visible and env.tonemap_mode == Environment.TONE_MAPPER_ACES, "Off, the scene is as it was: its grade and tonemapper (La Boca's night: ACES) back")
	check(world._spot(world.INK) == world.INK and Operative._ui_material.albedo_color == Color.WHITE, "…and the marks are their own colours again")
	world.set_ink(true)
	check(ink.quad.visible and env.tonemap_mode == Environment.TONE_MAPPER_LINEAR, "…and on again")
	# the choice: the settings file, unless the data decides
	var progress := ConfigFile.new()
	check(ComicInk.forced({}) == -1 and not ComicInk.wanted({}, progress), "Off by default")
	progress.set_value("settings", "ink", true)
	check(ComicInk.wanted({}, progress), "On when the settings file says so")
	check(ComicInk.forced({"ink": true}) == 1 and ComicInk.wanted({"ink": true}, ConfigFile.new()), "An operation's data can ask for it")
	check(ComicInk.forced({"id": "x", "preview": {"ink": true}}) == -1, "Nothing else in the data turns it on")
	main.hud.progress.set_value("settings", "ink", false)
	main._apply_settings()
	check(world.ink_enabled(), "main applies it: the data's wish wins over the settings file")
	# the Settings page: the toggle, and the credits
	main.front.open("settings")
	var texts: Array[String] = []
	var pending: Array[Node] = [main.front.body]
	while not pending.is_empty():
		var n: Node = pending.pop_back()
		pending.append_array(n.get_children())
		if n is Label: texts.append((n as Label).text)
	check("COMIC INK" in texts and "This operation is drawn in comic ink." in texts, "Settings has COMIC INK, and says when the operation decides")
	check("ART CREDITS" in texts, "Settings has the art credits (or what is still pending)")
	check("THANKS" in texts and "Agustín Linenberg, for the support." in texts, "…then the game's thanks")
	main.front.hide()
	main.queue_free()
	await process_frame

func _cleanup() -> void:
	for file: String in ["thing.png", "box.glb", "manifest.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PACK + file))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PACK))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DATA))
