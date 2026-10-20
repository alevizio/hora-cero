extends SceneTree
## Every picture the game can ask for exists, in both levels: each icon name in the HUD's tables and in the
## operation's data is a flat glyph or a rendered 3D object (action_slot.gd draws nothing for any other name), every
## kind of thing that can be tapped has a marker of its own, and every operative's briefing kit, prompts and action bar
## have their pictures. A plate an operative has nothing for takes another skill of his, or is left out with the bar
## closing up behind it: no blank plate and no hole, in landscape, upright and on a notched phone. La Boca's four bars
## are checked plate by plate.
## Run: godot --headless --path godot --script res://tests/icons.gd
const Missions = preload("res://scripts/missions.gd")
const Kit = preload("res://scripts/three_d/action_slot.gd")
const PROGRESS := "user://icons_test_progress.cfg"
const OPERATIONS := ["riachuelo", "plaza"]
## La Boca's bars at the start, plate by plate (crouched; nothing to do yet but the cellar, Hornero's): nobody has a
## gun, so the gun plate takes a skill of his own (Hornero's gondola, Lechuza's lamp board), and the bars of the two
## with nothing more (Benteveo, Biguá) close up.
const RIACHUELO_BARS := {
	"hornero": [["stance", "crouch"], ["melee", "handle"], ["gun", "gondola"], ["tool", "bell"], ["context", "cellar"], ["plan", "pause"]],
	"lechuza": [["stance", "crouch"], ["melee", "cord"], ["gun", "lampboard"], ["tool", "ladder"], ["context", "carry"], ["plan", "pause"]],
	"benteveo": [["stance", "crouch"], ["tool", "papers"], ["context", "carry"], ["plan", "pause"]],
	"bigua": [["stance", "crouch"], ["melee", "knife"], ["tool", "oars"], ["context", "carry"], ["plan", "pause"]]}
## Where La Boca's things are drawn from: the briefing kit of each, the markers, the prompts.
const RIACHUELO_KIT := {
	"hornero": ["motorcap", "handle", "key", "bell"],
	"lechuza": ["cord", "ladder", "lampkey"],
	"benteveo": ["flatcap", "papers"],
	"bigua": ["knife", "oars"]}
const RIACHUELO_MARKERS := {"gate": "cellar", "informant": "hand", "lamps": "lampboard", "ladder": "ladder", "gondola": "gondola",
	"boat": "oars", "extraction": "rowboat", "body": "carry"}
## The Plaza de Mayo's markers and actions: a person out in the snow and leading them in are a helping hand, a fallen
## neighbour and helping him up a stretcher, the tram and driving it the tram, a cloth to cross under a tarpaulin; a
## cascarudo in the square, for Juan Salvo's rifle, the reticle (and his rifle on the bar and in his kit).
const PLAZA_MARKERS := {"person": "hand", "fallen": "stretcher", "tram": "tram", "canvas": "tarp", "lights": "lampkey", "service": "key", "creature": "target"}
const PLAZA_ACTIONS := {"guide": "hand", "help": "stretcher", "drive": "tram", "canvas": "tarp"}
## Phone sizes the bar must still fit: [size, safe insets or null].
const PHONES := [[Vector2i(1280, 720), null], [Vector2i(390, 844), null], [Vector2i(844, 390), Vector4(110, 0, 110, 30)], [Vector2i(390, 844), Vector4(0, 109, 0, 63)]]
var main: Node3D
var sim: RefCounted
var hud: Control
var failures: int = 0
var checks: int = 0

func _init() -> void:
	call_deferred("run")

func check(value: bool, label_text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label_text)

func frames(n: int) -> void:
	for i: int in range(n): await process_frame

static func drawn(name: String) -> bool:
	return name in Kit.GLYPHS or name in Kit.ICONS3D

func run() -> void:
	# the atlas holds what action_slot.gd says it holds, and the new objects are in it
	var rows: int = ceili(float(Kit.ICONS3D.size()) / Kit.ICON3D_COLS)
	check(Kit.TexIcons3D.get_size() == Vector2(Kit.ICON3D_COLS, rows * 2) * Kit.ICON3D_CELL, "icons3d.png holds the ICONS3D list in colour and in grey")
	for name: String in ["handle", "cord", "ladder", "cellar", "lampboard", "gondola", "rowboat", "flatcap", "motorcap", "hand", "tram", "subte", "tarp", "stretcher"]:
		check(name in Kit.ICONS3D, "%s is in the 3D atlas" % name)
	var twice: Array = []
	for name: String in Kit.ICONS3D:
		if Kit.ICONS3D.count(name) > 1 and not name in twice: twice.append(name)
	check(twice.is_empty(), "no object twice in the atlas: %s" % str(twice))
	for id: String in OPERATIONS:
		await operation(id)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESS))
	Missions.choose("plaza", false)
	print("ICONS_CHECKS=", checks, " FAILURES=", failures)
	quit(0 if failures == 0 else 1)

func operation(id: String) -> void:
	Missions.choose(id, false)
	root.size = Vector2i(1280, 720)
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	hud = main.hud
	sim = main.sim
	hud.progress_path = PROGRESS
	hud.hints_enabled = false
	await frames(8)
	main._command("begin")
	if sim.paused: sim.toggle_pause()
	# nobody notices anything while the pictures are checked
	sim.alarm.radius = 0.0
	for g: Dictionary in sim.guards:
		g.range = 0
		g.near = 0
	await frames(4)
	if id == "plaza":
		# Juan Salvo come, and a cascarudo in the square near him: his bar, his kit, its marker
		sim.time = float(sim.unit_by_id("salvo").arrive.at) + 0.1
		sim.update(0.05)
		var beast: Dictionary = sim.guard_by_id("c1")
		sim._creature_enters(beast, true)
		beast.x = float(sim.unit_by_id("salvo").x) + 400.0
		beast.y = float(sim.unit_by_id("salvo").y)
		await frames(2)
	names(id)
	markers(id)
	for u: Dictionary in sim.units:
		operative(id, u)
	if id == "riachuelo": await riachuelo()
	if id == "plaza": await plaza()
	main.queue_free()
	await frames(2)

## Every icon name the HUD's tables, this operation's version of them and its data hold.
func names(id: String) -> void:
	var named: Dictionary = {}
	for table: Dictionary in [hud.ACTION_ICONS, hud.THING_ICONS, hud.action_icons, hud.thing_icons]:
		for key: Variant in table: named[str(table[key])] = "%s table, %s" % [id, key]
	for card: Dictionary in hud.HOWTO: named[str(card.glyph)] = "HOW TO PLAY"
	_icons_in(JSON.parse_string(FileAccess.get_file_as_string(str(Missions.LIST[Missions.index_of(id)].path))), "data", named)
	var missing: Array = []
	for name: String in named:
		if not drawn(name): missing.append("%s (%s)" % [name, named[name]])
	check(missing.is_empty(), "%s: every icon named has a picture (missing: %s)" % [id, ", ".join(missing)])

func _icons_in(value: Variant, path: String, into: Dictionary) -> void:
	if value is Dictionary:
		for key: Variant in value:
			if str(key) == "icon" and value[key] is String: into[str(value[key])] = path
			else: _icons_in(value[key], path + "." + str(key), into)
	elif value is Array:
		for item: Variant in value: _icons_in(item, path, into)

## Every kind of thing this operation can put a marker on has a picture of its own (not the stock tap).
func markers(id: String) -> void:
	var data: Dictionary = sim.data
	var kinds: Array[String] = ["body", "bush", "extraction"]
	if data.has("door"): kinds.append("gate")
	if sim.has_prisoner: kinds.append("informant")
	if data.has("fence"): kinds.append("fence")
	if data.has("radio"): kinds.append(str(data.radio.get("thing", "radio")))
	if data.has("uniforms"): kinds.append("uniform")
	for site: Dictionary in sim.charge_sites(): kinds.append(str(site.get("kind", "charge")))
	for passage: Dictionary in sim.passages(): kinds.append(str(passage.get("kind", "rope")))
	if data.has("people"): kinds.append_array(["person", "fallen"])
	if data.has("canvases"): kinds.append("canvas")
	for vehicle: Dictionary in data.get("vehicles", []):
		if vehicle.has("by"): kinds.append(str(vehicle.get("kind", "vehicle")))
	for u: Dictionary in sim.units:
		if u.has("talk"): kinds.append("civilian")
		if int(u.get("trap_kit", 0)) > 0: kinds.append("trap")
		if u.has("exit"): kinds.append(str(u.exit.get("type", "extraction")))
	for kind: String in kinds:
		check(hud.thing_icons.has(kind) and drawn(str(hud.thing_icons.get(kind, ""))), "%s: a %s marker has a picture (%s)" % [id, kind, hud.thing_icons.get(kind, "none")])
	# and what can be tapped right now, with the cellar or cell open and the man out of it
	if data.has("door"):
		sim.door_open = true
		sim._geometry_dirty = true
	if sim.has_prisoner: sim.prisoner.freed = true
	for u: Dictionary in sim.units:
		sim.select(str(u.id))
		for thing: Dictionary in sim.interactables():
			check(drawn(str(hud.thing_icons.get(thing.type, "tap"))), "%s, %s: the %s marker is drawn" % [id, u.id, thing.type])
	if data.has("door"):
		sim.door_open = false
		sim._geometry_dirty = true
	if sim.has_prisoner: sim.prisoner.freed = false

## One operative: his kit on the briefing, the prompt of everything he aims, the picture of every action he has, and
## his bar: a picture on every plate shown, and the plates closed up.
func operative(id: String, u: Dictionary) -> void:
	sim.select(str(u.id))
	hud.refresh()
	for item: Array in hud._kit(u):
		check(drawn(str(item[0])), "%s, %s: the kit's %s has a picture (%s)" % [id, u.id, item[1], item[0]])
	for entry: Dictionary in sim.available_actions():
		check(drawn(hud._icon_for(str(entry.id), u)), "%s, %s: the %s action has a picture (%s)" % [id, u.id, entry.id, hud._icon_for(str(entry.id), u)])
	bar_ok("%s, %s" % [id, u.id])

## The bar on screen now: every plate shown has a picture and words, none is shown empty, and the plates close up.
func bar_ok(who: String) -> void:
	var shown: Array = []
	for key: String in hud.SLOT_ORDER:
		var b: Kit = hud.slots[key]
		if b.visible:
			shown.append(b)
			check(drawn(b.symbol) and b.text != "", "%s: the %s plate shows a picture (%s) and words" % [who, key, b.symbol])
		else:
			check(not key in ["stance", "context", "plan"] and hud.entry_for(key).is_empty(), "%s: the %s plate is only left out when he has nothing for it" % [who, key])
	check(shown.size() >= 4, "%s: at least four plates on the bar (%d)" % [who, shown.size()])
	# rows of plates: each starts at the strip's left edge, ends at its right edge, one GAP between plates
	var strip: Vector2 = hud.action_strip.size
	var by_row: Dictionary = {}
	for b: Kit in shown: by_row[int(b.position.y)] = by_row.get(int(b.position.y), []) + [b]
	for y: int in by_row:
		var row: Array = by_row[y]
		var ok: bool = is_zero_approx((row[0] as Kit).position.x) and absf((row[row.size() - 1] as Kit).position.x + (row[row.size() - 1] as Kit).size.x - strip.x) < 0.6
		for i: int in range(1, row.size()):
			var before: Kit = row[i - 1]
			ok = ok and absf((row[i] as Kit).position.x - before.position.x - before.size.x - hud.GAP) < 0.6
		check(ok, "%s: the bar has no hole (row at %d)" % [who, y])
	for b: Kit in shown:
		check(b.size.x >= hud.MIN_TOUCH - 0.5 and b.size.y >= hud.MIN_TOUCH - 0.5, "%s: the %s plate is a thumb wide (%s)" % [who, b.text, b.size])

## La Boca, plate by plate, kit by kit and marker by marker, on every phone size.
func riachuelo() -> void:
	for kind: String in RIACHUELO_MARKERS:
		check(str(hud.thing_icons.get(kind, "")) == RIACHUELO_MARKERS[kind], "La Boca: the %s marker is the %s (%s)" % [kind, RIACHUELO_MARKERS[kind], hud.thing_icons.get(kind, "")])
	check(hud.action_icons.rescue == "hand" and hud.action_icons.unlock == "cellar" and hud.action_icons.extract == "rowboat", "La Boca: bringing the passenger up is a helping hand, the cellar its hatch, the far bank a rowing boat")
	for phone: Array in PHONES:
		hud.safe_override = phone[1]
		root.size = phone[0]
		await frames(10)
		for u: Dictionary in sim.units:
			var uid: String = str(u.id)
			u.stance = "sneak"
			sim.select(uid)
			hud.refresh()
			var want: Array = RIACHUELO_BARS[uid]
			var got: Array = []
			for key: String in hud.SLOT_ORDER:
				if (hud.slots[key] as Kit).visible: got.append([key, (hud.slots[key] as Kit).symbol])
			check(got == want, "%s %s: %s's bar is %s (got %s)" % [phone[0], phone[1], uid, str(want), str(got)])
			bar_ok("La Boca %s %s, %s" % [phone[0], phone[1], uid])
			for problem: String in hud.layout_problems():
				check(false, "La Boca %s %s, %s: %s" % [phone[0], phone[1], uid, problem])
	hud.safe_override = null
	root.size = Vector2i(1280, 720)
	await frames(6)
	for u: Dictionary in sim.units:
		var kit: Array = []
		for item: Array in hud._kit(u): kit.append(str(item[0]))
		check(kit == RIACHUELO_KIT[str(u.id)], "La Boca: %s's kit is drawn as %s (got %s)" % [u.id, str(RIACHUELO_KIT[str(u.id)]), str(kit)])
	# the gun plate's own skill works from the plate: Hornero to the gondola, Lechuza to the lamp board
	for pair: Array in [["hornero", "rig"], ["lechuza", "sabotage"]]:
		sim.select(str(pair[0]))
		hud.refresh()
		check(str(hud.entry_for("gun").get("id", "")) == pair[1] and hud.slot_ids.gun == pair[1], "%s's third plate is his %s" % [pair[0], pair[1]])
		main._slot("gun")
		check(str(sim.unit_by_id(str(pair[0])).order.get("type", "")) == pair[1], "…and a tap on it sends %s to do it (%s)" % [pair[0], sim.unit_by_id(str(pair[0])).order])
		sim.cancel_order()
	# the prompts of what they aim: the controller handle, the cord, the bell, the papers, the knife
	for pair: Array in [["hornero", "takedown", "handle"], ["hornero", "distract", "bell"], ["lechuza", "takedown", "cord"], ["benteveo", "distract", "papers"], ["bigua", "takedown", "knife"]]:
		sim.select(str(pair[0]))
		main._arm(str(pair[1]), true)
		hud.refresh()
		hud._refresh_prompt(sim.selected())
		check(hud.prompt.visible and hud._prompt_icon == pair[2], "%s aiming the %s: the prompt shows the %s (%s)" % [pair[0], pair[1], pair[2], hud._prompt_icon])
		main._arm("", true)

## The Plaza de Mayo: its markers and actions by name, and every bar whole on every phone size.
func plaza() -> void:
	for kind: String in PLAZA_MARKERS:
		check(str(hud.thing_icons.get(kind, "")) == PLAZA_MARKERS[kind], "Plaza de Mayo: the %s marker is the %s (%s)" % [kind, PLAZA_MARKERS[kind], hud.thing_icons.get(kind, "")])
	for action: String in PLAZA_ACTIONS:
		check(str(hud.action_icons.get(action, "")) == PLAZA_ACTIONS[action], "Plaza de Mayo: %s is the %s (%s)" % [action, PLAZA_ACTIONS[action], hud.action_icons.get(action, "")])
	var juan: Dictionary = sim.unit_by_id("salvo")
	sim.select("salvo")
	hud.refresh()
	check(sim.selected_id == "salvo" and hud._icon_for("shoot", juan) == "target", "Juan Salvo's rifle on the bar is the reticle (%s)" % hud._icon_for("shoot", juan))
	var kit: Array = hud._kit(juan)
	check(not kit.is_empty() and str(kit[0][0]) == "target" and drawn(str(kit[0][0])), "and in his kit: %s" % str(kit))
	var marked: bool = false
	for thing: Dictionary in sim.interactables():
		if str(thing.type) == "creature": marked = drawn(str(hud.thing_icons.get("creature", "tap")))
	check(marked, "a cascarudo in the square has its marker for him")
	for phone: Array in PHONES:
		hud.safe_override = phone[1]
		root.size = phone[0]
		await frames(10)
		for u: Dictionary in sim.units:
			sim.select(str(u.id))
			hud.refresh()
			bar_ok("Plaza de Mayo %s %s, %s" % [phone[0], phone[1], u.id])
			for problem: String in hud.layout_problems():
				check(false, "Plaza de Mayo %s %s, %s: %s" % [phone[0], phone[1], u.id, problem])
	hud.safe_override = null
	root.size = Vector2i(1280, 720)
	await frames(6)
