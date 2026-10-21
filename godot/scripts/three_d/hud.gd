extends Control
## In-game HUD, built in code: a field kit of drab steel plates, canvas name tapes and a typed
## operations dossier. Shared palette, fonts, glyphs and the nine-slice helper live in action_slot.gd.
##
## Layout (landscape phone, thumbs at the bottom corners):
##   top left      mission clock / detection readout, objectives
##   top right     MENU and MAP keys over the recon map
##   bottom left   the two ID photos with their order tags, view-turn keys beside them (left thumb: who)
##   bottom right  the action bar, PLAN / EXECUTE in the corner (right thumb: what)
##   top centre    one banner (command mode, or the armed weapon's prompt) and the alarm under it
##   above the bar notices and one-time hints
## Upright screens stack the bar in two rows beside the photos and put the view keys above them.
##
## The bar is filled from sim.available_actions() and sim.interactables() on every refresh (about
## 12 Hz); nothing here decides what an operative may do. Taps come back out through the signals.
signal command(name: String)
signal select_operative(id: String)
signal map_focus(point: Vector2)
## A bar slot was tapped: stance | melee | gun | tool | context | plan.
signal slot_pressed(key: String)
const Portraits = preload("res://assets/operatives.webp")
const ActionSlot = preload("res://scripts/three_d/action_slot.gd")
const Recon = preload("res://scripts/three_d/recon.gd")
## One of the squad dressed from the art pack (a licensed slot: Juan Salvo) has its portrait, or a plain plate with the name.
const ArtPack = preload("res://scripts/three_d/art_pack.gd")
const TexPaper := preload("res://assets/ui/paper.png")
const TexStain := preload("res://assets/ui/paper_stain.png")
const TexStampSecret := preload("res://assets/ui/stamp_secret.png")
const TexStampComplete := preload("res://assets/ui/stamp_complete.png")
const TexStampAborted := preload("res://assets/ui/stamp_aborted.png")
const IVORY := ActionSlot.IVORY
const MUTED := ActionSlot.MUTED
const KHAKI := ActionSlot.KHAKI
const BRASS := ActionSlot.BRASS
const RED := ActionSlot.RED
const INK := ActionSlot.INK
const DIM := ActionSlot.DIM
const DARK := Color(0.05,0.06,0.05,0.88)
const MARGIN := 18.0
const GAP := 6.0
const PORTRAIT_SIZE := Vector2(116,158)
const SLOT_SIZE := Vector2(122,92)
const PLAN_WIDTH := 150.0
const TOOL_SIZE := Vector2(140,80)
const CAMERA_SIZE := Vector2(76,76)
const TAG_HEIGHT := 24.0
const STATUS_HEIGHT := 46.0
const SHEET_PAD := Vector2(40,30)
## HOW TO PLAY: one line per card, over a looping clip from the game if there is one. The clips would live in
## HOWTO_DIR as <id>.ogv (Theora video); a card whose clip is missing shows its glyph instead (none ship today).
const HOWTO := [
	{"id":"move","glyph":"tap","line":"Tap one of the neighbours to choose who acts. Then tap the ground to move."},
	{"id":"cones","glyph":"eye","line":"Guards see in cones. Crouched, you can cross the pale edge. The bright part always sees you."},
	{"id":"takedown","glyph":"knife","line":"Get behind a guard and tap him. Each in his own way: Biguá a knife, Lechuza a cord, Hornero the tram's handle."},
	{"id":"body","glyph":"carry","line":"Carry bodies into a bush, or they will be found."},
	{"id":"pebble","glyph":"throw","line":"Hornero's bell and Benteveo's papers draw the guards nearby over to look."},
	{"id":"plan","glyph":"pause","line":"PLAN stops the clock. Give each an order, then EXECUTE: they move together."}]
const HOWTO_DIR := "res://assets/howto/"
## Side of an operative's ID photo on the briefing.
const OPERATIVE_PHOTO := 132.0
const HOWTO_LINE_SIZE := 28
## Room kept for the line when it sits beside the clip.
const HOWTO_SIDE_LINE := 300.0
## A drag this far across the clip turns the card.
const SWIPE := 48.0
## The text-size switch: three keys, an "A" drawn at each size. main.gd turns the choice into the canvas size.
const TEXT_SIZE_NAMES := ["Small text","Medium text","Large text"]
const TEXT_SIZE_LETTERS := [22,30,40]
## The master volume for each step of the VOLUME keys: off, then four steps of 6 dB up to full.
const VOLUME_DB := [-80.0,-18.0,-12.0,-6.0,0.0]
const BANNER_SIZE := Vector2(420,64)
const ALARM_SIZE := Vector2(420,64)
const PROMPT_SIZE := Vector2(460,64)
## Bar slots in display order, and the simulation actions each one can show (first one listed wins).
const SLOT_ORDER := ["stance","melee","gun","tool","context","plan"]
## Each plate takes the first of its actions this operative has (an action goes on one plate only): an operative
## with no gun (Merle) has his cigarette where the gun would be.
const SLOT_ACTIONS := {"stance":["stance"],"melee":["takedown","guide"],"gun":["shoot","chat","talk","call"],"tool":["distract","trap","trap_pickup","chat","rig","canvas","take"]}
## A plate the operative has nothing for (the four of La Boca carry no gun) takes the first of his own skills still off
## the bar, in this order: Hornero's gondola, Lechuza's lamp board. A plate still empty after that is left out, and the
## rest of the bar closes up (_place_bar), so no operative ever has a blank plate.
const SPARE_ACTIONS := ["rig","sabotage","unlock","cut","plant"]
const ACTION_ICONS := {"distract":"throw","trap":"tripwire","trap_pickup":"tripwire","pickup":"carry","drop":"drop","unlock":"key","cut":"cutters","sabotage":"radio","rescue":"rescue","extract":"boat","plant":"charge","chat":"cigarette","uniform":"uniform","rig":"rope","talk":"talk","guide":"hand","call":"talk","drive":"tram","help":"stretcher","canvas":"tarp","take":"hand"}
const THING_ICONS := {"gate":"key","informant":"rescue","fence":"cutters","radio":"radio","trap":"tripwire","body":"carry","bush":"hide","extraction":"boat","limpet":"limpet","charge":"charge","switch":"switch","home":"gate","uniform":"uniform","rope":"rope","civilian":"talk","phone":"phone","evidence":"smg","skis":"skis","window":"window","duct":"duct","door":"key","cellar":"key","person":"hand","fallen":"stretcher","tram":"tram","bus":"tram","canvas":"tarp","creature":"target","rifle":"smg","mask":"uniform"}
## Height above the ground (m) at which a tappable thing's marker floats.
const PIN_LIFT := {"gate":2.5,"informant":2.9,"fence":2.0,"radio":2.4,"trap":0.8,"body":1.0,"bush":1.7,"extraction":1.5,"limpet":1.3,"charge":1.9,"switch":2.4,"rope":1.2,"civilian":2.3,"phone":2.4,"evidence":0.9,"fallen":1.4,"canvas":2.0,"tram":4.2,"bus":3.4,"lights":3.2,"service":2.2,"creature":2.9,"rifle":1.3,"mask":1.4}
const PIN_RADIUS := 18.0
## The context slot offers a nearby thing within this many simulation units (5.5 m), a bush to hide a
## body in within HIDE_NEAR; farther away it falls back to the next objective.
const CONTEXT_NEAR := 176.0
const HIDE_NEAR := 224.0
const OBJECTIVE_ACTIONS := {"cell":"unlock","informant":"rescue","extract":"extract"}
const GUARD_NAMES := {"patrol":"PATROL","sentry":"SENTRY","tower":"TOWER","sergeant":"SERGEANT","reinforcement":"GUARD"}
## By the look the mission gives a guard (data "look", digits dropped): who he is, where that says more.
const LOOK_NAMES := {"sailor":"SAILOR","bootsmann":"BOATSWAIN","ot":"SITE GUARD","watchman":"WATCHMAN"}
const ORDER_NAMES := {"move":"MOVE","distract":"THROW","pickup":"LIFT BODY","drop":"DROP BODY","trap":"SET TRIPWIRE","trap_pickup":"RECOVER WIRE","cut":"CUT WIRE","sabotage":"SABOTAGE","unlock":"PICK LOCK","rescue":"RESCUE","extract":"TO THE BOAT","plant":"SET CHARGE","chat":"SMOKE","uniform":"CHANGING","rig":"RIG ROPE","talk":"A QUIET WORD","guide":"LEAD IN","call":"CALL","drive":"DRIVE","canvas":"TAKE CLOTH","help":"HELP UP","take":"TAKE"}
const HINTS := {
	"start": "Tap one of yours to choose who acts, then tap the ground to move. Drag to look around.",
	"cones": "Yellow cones are what guards see. Crouched, you can pass through the pale outer part.",
	"far_zone": "Crouched, you're unseen in the pale outer zone.",
	"takedown": "Tap a guard to take him down. Best from behind.",
	"body": "Bodies left in the open get found. Carry him into a bush and put him down there.",
	"stunned": "He will wake. Bind him, knife him or be gone by then.",
	"alarm": "Spotted! Break their line of sight: get behind a wall or into a bush. The alarm passes.",
	"cell": "Only one of yours can open the door. Select him, then tap it.",
	"plan": "Plan stops the clock: give each one an order, then Execute to move them all at once.",
	"both": "You command the whole squad. Tap another portrait and use them together.",
	"radio": "Optional: sabotage it, and no reinforcements come.",
	"wire": "The marked span of the wire can be cut. Tap it.",
	"informant": "He can't crouch. Move him from cover to cover."}
## Teaching lines that wait for a quiet moment (none showing) before they appear, in this order of priority.
const COACH_ORDER := ["start","cell","takedown","cones","plan","both","radio"]
const HINT_SECONDS := 9.0
const NOTICE_SECONDS := 6.0
## What the current step of the mission asks for, in a few words, by objective id.
const OBJECTIVE_HOW := {"informant": "Walk into the cell to free him", "extract": "Both operatives and the informant to the boat"}
const BRIEFING_COPY := "Free the informant from the holding cell and get him to the boat. All three of you leave together, or nobody does."
const NOTHING := {}
const OUT_STATES := ["dead","bound","held"]
const OPERATIVES := ["wren","rook"]
const SIGNS := [-1.0,1.0]
const COMPASS := [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]
const ASSET_TAGS := ["INFORMANT","INFORMANT  ·  IN THE OPEN","INFORMANT  ·  IN COVER","ABOARD"]
const ALARM_REASONS := ["spotted","body","gunshot"]
const ARMED_MODES := ["","takedown","shoot","distract"]
const COMMAND_HINTS := ["Clock stopped. Give each operative an order.","One order ready. Execute, or brief the other.","Both have orders. Execute when ready."]
const Missions = preload("res://scripts/missions.gd")
const Feedback = preload("res://scripts/feedback.gd")
const Lang = preload("res://scripts/lang.gd")
## Checkpoint names by label; a level names its own (data "copy"."checkpoints").
const CHECKPOINT_NAMES := {"start":"the landing","gate":"cell gate open","informant":"informant freed"}

## Plate drawn behind a block of text (notices, banners, name tags).
class Backing extends Control:
	const Kit := preload("res://scripts/three_d/action_slot.gd")
	var tint := Color.WHITE
	## Optional accent rule, down the left edge or (bar_top) along the top.
	var bar := Color.TRANSPARENT
	var bar_top: bool = false
	## Small pointer under the plate (floating name tags).
	var pointer: bool = false
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		Kit.nine(self,Kit.TexStrip,Rect2(Vector2.ZERO,size),24.0,8.0,tint)
		if bar.a > 0.0:
			if bar_top: draw_rect(Rect2(3,1,size.x-6,2),bar)
			else: draw_rect(Rect2(1,3,3,size.y-6),bar)
		if pointer:
			var mid: float = roundf(size.x*0.5)
			draw_rect(Rect2(mid-1,size.y,2,5),Color(Kit.IVORY,0.85))

## A control painted by one of the HUD's own functions; redrawn only when the HUD asks.
class Canvas extends Control:
	var painter: Callable
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		if painter.is_valid(): painter.call(self)

## Mission clock and detection readout: indicator lamp, divider and a thin meter.
class Readout extends Control:
	const Kit := preload("res://scripts/three_d/action_slot.gd")
	var level: float = 0.0: set = set_level
	var alarm: bool = false: set = set_alarm
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func set_level(value: float) -> void:
		var stepped: float = roundf(value*50.0)/50.0
		if is_equal_approx(level,stepped): return
		level = stepped
		queue_redraw()
	func set_alarm(value: bool) -> void:
		if alarm == value: return
		alarm = value
		queue_redraw()
	func tone() -> Color:
		# Amber as suspicion builds, red once a guard is close to certain or the alarm is up.
		if alarm: return Kit.RED
		if level <= 0.02: return Color("59634a")
		return Kit.BRASS.lerp(Kit.RED,smoothstep(0.35,0.7,level))
	func _draw() -> void:
		Kit.nine(self,Kit.TexGun,Rect2(Vector2.ZERO,size),24.0,8.0)
		var c := tone()
		var lamp := Vector2(19,19)
		if level > 0.02 or alarm: draw_circle(lamp,10.5,Color(c,0.16),true,-1.0,true)
		draw_circle(lamp,7.5,Color(0.03,0.04,0.03),true,-1.0,true)
		draw_circle(lamp,5.5,c,true,-1.0,true)
		draw_circle(lamp+Vector2(-1.6,-1.8),1.6,Color(1,1,1,0.32),true,-1.0,true)
		draw_rect(Rect2(91,10,1,19),Color(1,1,1,0.13))
		var track := Rect2(12,size.y-10,size.x-24,3)
		draw_rect(track,Color(0.03,0.04,0.03,0.95))
		var fill: float = 1.0 if alarm else level
		if fill > 0.02: draw_rect(Rect2(track.position,Vector2(maxf(3.0,roundf(track.size.x*clampf(fill,0,1))),3)),c)

## The dossier sheet: aged paper, a little foxing and one rubber stamp.
class Sheet extends PanelContainer:
	const Kit := preload("res://scripts/three_d/action_slot.gd")
	var paper: Texture2D
	var stain: Texture2D
	var stamp: Texture2D
	var stamp_tint := Color.WHITE
	var stamp_at := Vector2.ZERO
	var stamp_turn: float = -0.11
	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO,size)
		Kit.nine(self,paper,rect,48.0,20.0)
		draw_texture_rect(stain,rect.grow(-4),false,Color(1,1,1,0.9))
		if stamp:
			draw_set_transform(stamp_at,stamp_turn,Vector2(0.5,0.5))
			draw_texture(stamp,-stamp.get_size()*0.5,stamp_tint)
			draw_set_transform(Vector2.ZERO)

## One key of the text-size switch: a plate with an "A" at its size, lit brass when it is the one chosen.
class SizeKey extends Button:
	const Kit := preload("res://scripts/three_d/action_slot.gd")
	var letter_px: int = 30
	## What the key shows: "A" at its size (text size), or a word (a language: EN, ES).
	var word: String = "A"
	var chosen: bool = false:
		set(value):
			if chosen == value: return
			chosen = value
			queue_redraw()
	func _ready() -> void:
		focus_mode = Control.FOCUS_NONE
		for key: String in ["normal","hover","pressed","hover_pressed","disabled","focus"]:
			add_theme_stylebox_override(key,StyleBoxEmpty.new())
	func _draw() -> void:
		var mode := get_draw_mode()
		var down: bool = mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED
		var tex: Texture2D = Kit.TexPlateArmed if chosen else (Kit.TexPlatePressed if down else Kit.TexPlate)
		Kit.nine(self,tex,Rect2(Vector2.ZERO,size),Kit.PLATE_MARGIN,Kit.PLATE_BLEED,Color(1.12,1.12,1.12) if mode == DRAW_HOVER else Color.WHITE)
		# a word is in the player's language (ON, FASTEST); the letter and the language names stay as they are
		var shown: String = word if word == "A" else tr(word)
		Kit.label(self,Kit.face("stencil",0) if word == "A" else Kit.face("semi",2),shown,size.x*0.5,roundf(size.y*0.5+letter_px*0.36)+(1.0 if down else 0.0),letter_px,Kit.BRASS if chosen else Kit.IVORY)

## The sound key beside the volume bars: a speaker, crossed out (and lit) while the sound is off. No word on it,
## so it reads the same in every language.
class MuteKey extends Button:
	const Kit := preload("res://scripts/three_d/action_slot.gd")
	var chosen: bool = false:
		set(value):
			if chosen == value: return
			chosen = value
			queue_redraw()
	func _ready() -> void:
		focus_mode = Control.FOCUS_NONE
		tooltip_text = tr("SOUND")
		for key: String in ["normal","hover","pressed","hover_pressed","disabled","focus"]:
			add_theme_stylebox_override(key,StyleBoxEmpty.new())
	func _draw() -> void:
		var mode := get_draw_mode()
		var down: bool = mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED
		var tex: Texture2D = Kit.TexPlateArmed if chosen else (Kit.TexPlatePressed if down else Kit.TexPlate)
		Kit.nine(self,tex,Rect2(Vector2.ZERO,size),Kit.PLATE_MARGIN,Kit.PLATE_BLEED,Color(1.12,1.12,1.12) if mode == DRAW_HOVER else Color.WHITE)
		var tone: Color = Kit.BRASS if chosen else Kit.IVORY
		var c := Vector2(roundf(size.x*0.5) - 7.0, roundf(size.y*0.5) + (1.0 if down else 0.0))
		# the speaker: a box and its cone
		draw_rect(Rect2(c + Vector2(-10, -5), Vector2(7, 10)), tone)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-4, -5), c + Vector2(5, -12), c + Vector2(5, 12), c + Vector2(-4, 5)]), tone)
		if chosen:
			# off: a cross where the sound would be
			draw_line(c + Vector2(10, -6), c + Vector2(22, 6), tone, 3.0, true)
			draw_line(c + Vector2(10, 6), c + Vector2(22, -6), tone, 3.0, true)
		else:
			draw_arc(c + Vector2(4, 0), 9.0, -0.8, 0.8, 10, tone, 2.5, true)
			draw_arc(c + Vector2(4, 0), 15.0, -0.8, 0.8, 12, tone, 2.5, true)

## The volume as four rising bars on a plate: tap or drag along it to pick a step (the OFF key beside it mutes).
## The bars up to the step are lit; with the sound off they all show faint.
class VolumeBar extends Control:
	const Kit := preload("res://scripts/three_d/action_slot.gd")
	signal picked(level: int)
	var level: int = 4:
		set(value):
			if level == value: return
			level = value
			queue_redraw()
	var muted: bool = false:
		set(value):
			if muted == value: return
			muted = value
			queue_redraw()
	var _held: bool = false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		tooltip_text = tr("VOLUME")
	func _steps() -> int:
		return VOLUME_DB.size() - 1
	func _level_at(x: float) -> int:
		return clampi(int(ceil(x / maxf(size.x, 1.0) * _steps())), 1, _steps())
	func _gui_input(event: InputEvent) -> void:
		var at: float = -1.0
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_held = (event as InputEventMouseButton).pressed
			if _held: at = (event as InputEventMouseButton).position.x
		elif event is InputEventMouseMotion and _held:
			at = (event as InputEventMouseMotion).position.x
		elif event is InputEventScreenTouch:
			_held = (event as InputEventScreenTouch).pressed
			if _held: at = (event as InputEventScreenTouch).position.x
		elif event is InputEventScreenDrag:
			at = (event as InputEventScreenDrag).position.x
		if at < 0.0: return
		accept_event()
		var pick: int = _level_at(at)
		if pick != level or muted: picked.emit(pick)
	func _draw() -> void:
		Kit.nine(self, Kit.TexPlate, Rect2(Vector2.ZERO, size), Kit.PLATE_MARGIN, Kit.PLATE_BLEED)
		var steps: int = _steps()
		var pad: float = 16.0
		var gap: float = 6.0
		var bar_w: float = (size.x - 2.0 * pad - gap * (steps - 1)) / steps
		var tall: float = size.y * 0.5
		var base: float = roundf(size.y * 0.5 + tall * 0.5)
		for i: int in range(steps):
			var h: float = roundf(tall * (0.3 + 0.7 * float(i) / float(steps - 1)))
			var bar := Rect2(roundf(pad + i * (bar_w + gap)), base - h, roundf(bar_w), h)
			var lit: bool = not muted and i < level
			draw_rect(bar, Kit.BRASS if lit else Color(Kit.IVORY, 0.2))

## A lesser choice on a paper page, drawn in ink instead of as a metal plate, so a page's choices read in order
## of weight: the plates first (which operation), then "segment" (a part of a ruled box, filled with ink when it
## is the one chosen: which board), then "link" (a word, underlined when chosen: which period, or an aside like
## CHANGE). Each is as tall as any key, so a thumb still finds it.
class PaperKey extends Button:
	const Kit := preload("res://scripts/three_d/action_slot.gd")
	var word: String = ""
	var look: String = "segment"
	var letter_px: int = 20
	var chosen: bool = false:
		set(value):
			if chosen == value: return
			chosen = value
			queue_redraw()
	func _ready() -> void:
		focus_mode = Control.FOCUS_NONE
		for key: String in ["normal","hover","pressed","hover_pressed","disabled","focus"]:
			add_theme_stylebox_override(key,StyleBoxEmpty.new())
	func _draw() -> void:
		var mode := get_draw_mode()
		var down: bool = mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED
		var hover: bool = mode == DRAW_HOVER
		var shown: String = tr(word)
		var f: Font = Kit.face("semi",2)
		var nudge: float = 1.0 if down else 0.0
		if look == "segment":
			# a slimmer box than a plate, in the middle of the touch height; neighbours share their rules
			var band := Rect2(0.0,roundf(size.y*0.17),size.x,roundf(size.y*0.66))
			if chosen: draw_rect(band,Color(Kit.INK,0.9))
			elif down: draw_rect(band,Color(Kit.INK,0.18))
			elif hover: draw_rect(band,Color(Kit.INK,0.08))
			draw_rect(band.grow(-1.0),Color(Kit.INK,0.85),false,2.0)
			Kit.label(self,f,shown,size.x*0.5,roundf(band.get_center().y+letter_px*0.36)+nudge,letter_px,Kit.IVORY if chosen else Color(Kit.INK,0.88))
		else:
			var tone: Color = Color(Kit.INK,1.0) if chosen else Color(Kit.INK,0.78 if (hover or down) else 0.58)
			var base: float = roundf(size.y*0.5+letter_px*0.36)+nudge
			Kit.label(self,f,shown,size.x*0.5,base,letter_px,tone)
			var w: float = f.get_string_size(shown,HORIZONTAL_ALIGNMENT_LEFT,-1,letter_px).x
			if chosen: draw_rect(Rect2(roundf(size.x*0.5-w*0.5),base+6.0,roundf(w),2.0),Color(Kit.INK,0.9))
			elif hover: draw_rect(Rect2(roundf(size.x*0.5-w*0.5),base+6.0,roundf(w),1.0),Color(Kit.INK,0.45))

## The closing scene's frame: letterbox bars, a fade to black and one caption at a time.
class Cinema extends Control:
	const Kit := preload("res://scripts/three_d/action_slot.gd")
	var bars: float = 0.0
	var black: float = 0.0
	## a blast's flash across the whole picture (0..1)
	var white: float = 0.0
	var caption: String = ""
	var big: bool = false
	var caption_alpha: float = 0.0
	var _until: float = 0.0
	var _t: float = 0.0
	var _want_bars: float = 0.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
	func show_caption(text: String, seconds: float, large: bool) -> void:
		caption = text
		big = large
		_until = _t + seconds
	func _process(dt: float) -> void:
		if not visible: return
		_t += dt
		var now: float = _t
		bars = move_toward(bars, _want_bars, dt * 1.5)
		var want: float = 1.0 if (caption != "" and now < _until) else 0.0
		caption_alpha = move_toward(caption_alpha, want, dt * 2.2)
		queue_redraw()
	func open(on: bool) -> void:
		_want_bars = 1.0 if on else 0.0
		if on:
			bars = 0.0
			caption = ""
			caption_alpha = 0.0
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if black > 0.0: draw_rect(r, Color(0, 0, 0, black))
		if white > 0.0: draw_rect(r, Color(1.0, 0.95, 0.84, white * 0.85))
		var bar_h: float = roundf(size.y * 0.1 * bars)
		if bar_h > 0.0:
			draw_rect(Rect2(0, 0, size.x, bar_h), Color(0.0, 0.0, 0.0, 0.94))
			draw_rect(Rect2(0, size.y - bar_h, size.x, bar_h), Color(0.0, 0.0, 0.0, 0.94))
		if caption_alpha <= 0.01 or caption == "": return
		var f: Font = Kit.face("stencil", 2) if big else Kit.face("type")
		var px: int = 46 if big else 27
		var lines: PackedStringArray = caption.split("\n")
		var line_h: float = f.get_height(px) * 1.08
		var y0: float = (size.y * 0.5 - line_h * lines.size() * 0.5 + f.get_ascent(px)) if big else (size.y - bar_h - 22.0 - line_h * (lines.size() - 1))
		for i: int in range(lines.size()):
			var w: float = f.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			var at := Vector2(roundf((size.x - w) * 0.5), roundf(y0 + line_h * i))
			draw_string(f, at + Vector2(2, 2), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0, 0, 0, 0.7 * caption_alpha))
			draw_string(f, at, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(Kit.IVORY, caption_alpha))

## Double rule under the dossier header.
class Rule extends Control:
	var ink := Color.BLACK
	var single: bool = false
	func _init() -> void:
		custom_minimum_size = Vector2(0,5)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_rect(Rect2(0,0,size.x,1 if single else 2),ink)
		if not single: draw_rect(Rect2(0,4,size.x,1),Color(ink,ink.a*0.7))

var sim: RefCounted
var camera: Camera3D
## What the next tap in the world will do: "" | "takedown" | "shoot" | "distract". Owned by main.gd.
var armed: String = ""
## Results and seen hints are kept here (Missions.progress_path()); tests point it at a
## scratch file.
var progress_path: String = Missions.progress_path()
var progress := ConfigFile.new()
var hints_enabled: bool = true

var portrait_buttons: Dictionary = {}
var tags: Dictionary = {}
var slots: Dictionary = {}
var slot_ids: Dictionary = {}
var portrait_strip: HBoxContainer
var action_strip: Control
var tools_row: HBoxContainer
var camera_row: Control
var minimap: Control
var readout: Readout
var clock: Label
var status: Label
var objective_block: Canvas
var planning: Canvas
var alarm_banner: Canvas
var prompt: Canvas
var notice: Label
var notice_plate: Backing
var hint_label: Label
var hint_plate: Backing
var toast: Label
var toast_plate: Backing
var overhead: Canvas
var frame: Canvas
var overlay: ColorRect
var modal: PanelContainer
var modal_box: VBoxContainer
var modal_page: Label
var modal_title: Label
var modal_body: Label
var stats_row: Canvas
var badge_row: Canvas
## Briefing: the two operatives, photo, role and kit.
var operatives_row: Canvas
## HOW TO PLAY: the clip in its frame, the line under it and the page dots.
var howto_box: VBoxContainer
## The clip and its line: one above the other, or side by side where the sheet is short and wide.
var howto_body: BoxContainer
var howto_frame: Control
var howto_video: VideoStreamPlayer
var howto_line: Label
var howto_dots: Canvas
var howto_page: int = 0
## The text-size switch, on the briefing and in the pause menu: {row, keys}.
var size_rows: Array[Dictionary] = []
## Every set of VOLUME keys on screen (the pause menu's, the launch screen's), kept in step with each other.
var volume_rows: Array[Dictionary] = []
## The briefing's language keys (EN, ES).
var menu_grid: GridContainer
var menu_buttons: Dictionary = {}
## Under the pause menu's keys, when the answers have somewhere to go (Feedback.enabled()): TELL US WHAT YOU THINK.
var menu_questions: VBoxContainer
## The way to the questions (the launch screen's menu, the pause menu and the debrief all say it).
const QUESTIONS := "TELL US WHAT YOU THINK"
var begin_button: Button
var second_button: Button
var foot: Label
var current_modal: String = "briefing"
var labels: Dictionary = {}
var viewport_size: Vector2
## Device safe-area insets in logical pixels as Vector4(left, top, right, bottom).
## Leave null to read them from the display; set a Vector4 to exercise notch layouts on desktop.
var safe_override: Variant = null
var insets := Vector4.ZERO
## The context slot's present offer: {id, label, icon, enabled, reason, target, active, pin}.
var context: Dictionary = {"id":"","kind":"context","label":"","icon":"","enabled":false,"reason":"","target":null,"active":false,"pin":""}

var _upright: bool = false
## The bar's plates on show, in SLOT_ORDER (those the operative has nothing for are left out), and where layout()
## put the bar: its right edge, top, the width of a plate and of the whole strip, and whether it is two rows.
var _bar_shown: Array[String] = []
var _bar_right: float = 0.0
var _bar_top: float = 0.0
var _bar_slot: float = 0.0
var _bar_across: float = 0.0
var _bar_rows: bool = false
var _pins: Array[Dictionary] = []
var _marked: Array[String] = []
var _caps: Dictionary = {}
var _tag_text: Dictionary = {}
var _tag_object: Dictionary = {}
var _tag_live: Dictionary = {}
var _tag_at: Dictionary = {"asset":Vector2.ZERO}
## The squad of this operation, in data order (two or three).
var operatives: Array[String] = []
var _notice_base := Vector2.ZERO
var _notice_width: float = 600.0
var _block_limit: float = 400.0
var _seen_message: String = ""
var _notice_until: float = 0.0
var _hint_until: float = 0.0
var _toast_until: float = 0.0
var _shown_second: int = -1
var _shown_status: int = -2
var _modal_queued: bool = false
var _howto_back: String = "briefing"
## The pause menu's MAIN MENU wants a second tap (the run is left behind) until this moment.
var _leave_armed_until: float = 0.0
var _clips: Dictionary = {}
var _swipe_from := Vector2.INF
var _restart_armed_until: float = 0.0
var _result_saved: bool = false
## The mission's own words and settings, merged over Breakwater's (built in _ready from sim.data).
var hints: Dictionary = {}
var coach_order: Array = []
var objective_how: Dictionary = {}
var order_names: Dictionary = {}
var action_icons: Dictionary = {}
var thing_icons: Dictionary = {}
## Progress file sections for this mission's badges and best time ("badges", "best" for Breakwater).
var badge_section: String = "badges"
var best_section: String = "best"
## The tab of the operation still to come, and the line under the tabs saying what opens the locked ones.
## The page of the history notes on show (data "history": [{title, body}, ...]).
var history_page: int = 0
var cinema_view: Cinema
var _menu_note: String = ""
# Objective block.
var _obj_key: int = -1
var _obj_title: String = ""
var _obj_how: String = ""
var _obj_how_lines: PackedStringArray = []
var _coach_clock: float = -1.0
var _coach_planned: bool = false
var _coach_ordered: Dictionary = {}
var _obj_lines: Array[String] = []
var _obj_tones: Array[Color] = []
var _obj_marks: Array[int] = []
var _obj_states: Array[int] = []
# Banners.
var _orders_queued: int = 0
var _alarm_second: int = -1
var _alarm_fill: float = 1.0
var _alarm_line: String = ""
var _alarm_key: int = -1
var _prompt_key: int = -1
var _shown_queued: int = -1
var _blocks: Array[Control] = []
var _prompt_title: String = ""
var _prompt_line: String = ""
var _prompt_icon: String = "target"
var _prompt_loud: bool = false
var _asset_state: int = -1
var _frame_state: int = 0
var _pulse: float = 0.0
# Result sheet.
var _stats: Array = []
var _badges: Array[Dictionary] = []
var _new_badges: Array[String] = []
var _operatives_stacked: bool = false
var _cards: Dictionary = {}

func text(value: String, size_px: int = 22, color: Color = IVORY, face: String = "medium", tracking: int = 0) -> Label:
	var l := Label.new()
	l.text=value
	l.add_theme_font_override("font",ActionSlot.face(face,tracking))
	l.add_theme_font_size_override("font_size",size_px)
	l.add_theme_color_override("font_color",color)
	l.add_theme_color_override("font_shadow_color",Color(0,0,0,0.7))
	l.add_theme_constant_override("shadow_offset_x",0)
	l.add_theme_constant_override("shadow_offset_y",1)
	l.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return l

## Typed/printed text on the dossier sheet: ink, no drop shadow.
func ink(value: String, size_px: int, face: String, tracking: int = 0, alpha: float = 1.0) -> Label:
	var l := text(value,size_px,Color(INK,alpha),face,tracking)
	l.add_theme_color_override("font_shadow_color",Color.TRANSPARENT)
	return l

func button(value: String, callback: Callable, min_size: Vector2, style: String = "text") -> ActionSlot:
	var b := ActionSlot.new()
	b.kind=style
	b.text=value
	b.custom_minimum_size=min_size
	b.pressed.connect(callback)
	return b

func canvas(painter: Callable, min_size: Vector2 = Vector2.ZERO) -> Canvas:
	var c := Canvas.new()
	c.painter=painter
	c.custom_minimum_size=min_size
	return c

## Upper-case form of a simulation label, built once per label.
func caps(value: String) -> String:
	if not _caps.has(value): _caps[value]=value.to_upper()
	return _caps[value]

## A line of the level's copy (data "copy"), or the fallback.
func copy(key: String, fallback: String) -> String:
	return str(sim.data.get("copy",{}).get(key,fallback))

func _read_mission() -> void:
	var data: Dictionary=sim.data
	var words: Dictionary=data.get("copy",{})
	hints=HINTS.duplicate()
	hints.merge(words.get("hints",{}),true)
	coach_order=words.get("coach",COACH_ORDER)
	objective_how=OBJECTIVE_HOW.duplicate()
	objective_how.merge(words.get("objectiveHow",{}),true)
	order_names=ORDER_NAMES.duplicate()
	order_names.merge(words.get("orderNames",{}),true)
	action_icons=ACTION_ICONS.duplicate()
	thing_icons=THING_ICONS.duplicate()
	if data.has("radio"):
		var icon: String=str(data.radio.get("icon","radio"))
		action_icons["sabotage"]=icon
		thing_icons[str(data.radio.get("thing","radio"))]=icon
	if data.has("extraction") and data.extraction.has("icon"):
		action_icons["extract"]=str(data.extraction.icon)
		thing_icons["extraction"]=str(data.extraction.icon)
	# a mission's own picture for its door (La Bruma's cellar hatch) and for bringing its man out (a helping hand)
	if data.has("door") and data.door.has("icon"):
		action_icons["unlock"]=str(data.door.icon)
		thing_icons["gate"]=str(data.door.icon)
	if data.has("prisoner") and data.prisoner.has("icon"):
		action_icons["rescue"]=str(data.prisoner.icon)
		thing_icons["informant"]=str(data.prisoner.icon)
	# a passage's marker is the passage's own icon (Lechuza's ladder, the gondola), else the stock one for its kind
	for passage: Dictionary in data.get("passages",[]):
		var kind: String=str(passage.get("kind","rope"))
		thing_icons[kind]=str(passage.icon) if passage.has("icon") else str(thing_icons.get(kind,"rope"))
	# a rescue's vehicles: each kind with its own icon (data vehicles[].icon)
	for vehicle: Dictionary in data.get("vehicles",[]):
		if vehicle.has("icon"): thing_icons[str(vehicle.get("kind","vehicle"))]=str(vehicle.icon)
	var id: String=str(data.get("progressKey",""))
	badge_section="badges" if id=="" else "badges_"+id
	best_section="best" if id=="" else "best_"+id

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	_read_mission()
	load_progress()
	var skin := Theme.new()
	skin.default_font=ActionSlot.face("medium")
	skin.default_font_size=22
	var tip := StyleBoxFlat.new()
	tip.bg_color=Color(0.07,0.08,0.07,0.95)
	tip.border_color=Color(KHAKI,0.35)
	tip.set_border_width_all(1)
	tip.set_content_margin_all(8)
	skin.set_stylebox("panel","TooltipPanel",tip)
	skin.set_color("font_color","TooltipLabel",IVORY)
	skin.set_font_size("font_size","TooltipLabel",18)
	theme=skin
	# Screen-edge mood (alarm glow, command-mode vignette) sits under everything else.
	frame=canvas(_paint_frame)
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Floating marks and name tags go next so the rest of the kit always sits above them.
	overhead=canvas(_paint_overhead)
	add_child(overhead)
	overhead.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	operatives.clear()
	for u: Dictionary in sim.units:
		var uid: String=str(u.id)
		operatives.append(uid)
		_tag_text[uid]=""
		_tag_object[uid]=""
		_tag_live[uid]=false
		_tag_at[uid]=Vector2.ZERO
	for id: String in (operatives+["asset"] if sim.has_prisoner else operatives):
		var l:=text(_name_caps(id) if id!="asset" else _asset_tag(""),16,IVORY if id!="asset" else KHAKI.lightened(0.25),"semi",2)
		l.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		var plate:=Backing.new()
		plate.show_behind_parent=true
		plate.pointer=true
		l.add_child(plate)
		plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.hide()
		add_child(l)
		labels[id]=l
		_size_tag(l)
	# Top left: readout and objectives.
	readout=Readout.new()
	readout.mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(readout)
	clock=text("00:00",22,IVORY,"semi",1)
	readout.add_child(clock)
	clock.position=Vector2(34,6)
	status=text("UNDETECTED",22,MUTED,"semi",2)
	readout.add_child(status)
	status.position=Vector2(102,6)
	objective_block=canvas(_paint_objectives)
	objective_block.mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(objective_block)
	# Top right: menu and map keys over the recon map.
	tools_row=HBoxContainer.new()
	tools_row.add_theme_constant_override("separation",int(GAP))
	add_child(tools_row)
	var menu_key:=button("MENU",func() -> void: command.emit("menu"),TOOL_SIZE)
	menu_key.tooltip_text="Checkpoints, how to play, text size, restart"
	tools_row.add_child(menu_key)
	var map_key:=button("MAP",func() -> void: command.emit("fit"),TOOL_SIZE)
	map_key.tooltip_text=copy("mapTip","Show the whole outpost")
	tools_row.add_child(map_key)
	minimap=Recon.new()
	minimap.sim=sim
	minimap.camera=camera
	minimap.focus_requested.connect(func(point: Vector2) -> void: map_focus.emit(point))
	add_child(minimap)
	# Bottom left: view keys, order tags, ID photos.
	camera_row=Control.new()
	camera_row.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(camera_row)
	for key: String in ["rotate_left","rotate_right"]:
		var b:=button("",func() -> void: command.emit(key),CAMERA_SIZE,key)
		b.tooltip_text="Turn the view left" if key=="rotate_left" else "Turn the view right"
		camera_row.add_child(b)
	portrait_strip=HBoxContainer.new()
	portrait_strip.add_theme_constant_override("separation",8)
	add_child(portrait_strip)
	for id: String in operatives:
		var b: ActionSlot=button(_name_caps(id),func() -> void: select_operative.emit(id),PORTRAIT_SIZE,"portrait")
		_dress_photo(b,id)
		b.tooltip_text="Select "+id.capitalize()
		portrait_strip.add_child(b)
		portrait_buttons[id]=b
		var tag:=canvas(_paint_tag.bind(id))
		add_child(tag)
		tags[id]=tag
	# Bottom right: the action bar.
	action_strip=Control.new()
	action_strip.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(action_strip)
	for key: String in SLOT_ORDER:
		var b:=button("",func() -> void: slot_pressed.emit(key),SLOT_SIZE,"slot")
		action_strip.add_child(b)
		slots[key]=b
		slot_ids[key]=""
	# Banners and lines of text.
	planning=canvas(_paint_planning)
	planning.mouse_filter=Control.MOUSE_FILTER_STOP
	planning.hide()
	add_child(planning)
	alarm_banner=canvas(_paint_alarm)
	alarm_banner.mouse_filter=Control.MOUSE_FILTER_STOP
	alarm_banner.hide()
	add_child(alarm_banner)
	prompt=canvas(_paint_prompt)
	prompt.mouse_filter=Control.MOUSE_FILTER_STOP
	prompt.hide()
	add_child(prompt)
	notice=text("",20,IVORY,"type")
	notice_plate=_line_plate(notice,Color.TRANSPARENT)
	hint_label=text("",21,IVORY,"type")
	hint_plate=_line_plate(hint_label,BRASS)
	toast=text("",17,IVORY,"semi",2)
	toast.auto_translate_mode=Node.AUTO_TRANSLATE_MODE_DISABLED  # show_toast translates (and may fold) the line itself
	toast.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	toast.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	toast_plate=Backing.new()
	toast_plate.show_behind_parent=true
	toast_plate.bar=BRASS
	toast.add_child(toast_plate)
	toast_plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	toast.hide()
	add_child(toast)
	_build_modal()
	# the closing scene draws on its own layer over everything
	var cinema_layer := CanvasLayer.new()
	cinema_layer.name = "Cinema"
	cinema_layer.layer = 3
	add_child(cinema_layer)
	cinema_view = Cinema.new()
	cinema_view.hide()
	cinema_layer.add_child(cinema_view)
	get_viewport().size_changed.connect(layout)
	layout()
	show_modal("briefing")

## A typed line on a dark strip (notices, hints); the strip is fitted to the words in _fit_line.
func _line_plate(l: Label, bar: Color) -> Backing:
	l.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var plate:=Backing.new()
	plate.show_behind_parent=true
	plate.bar=bar
	l.add_child(plate)
	l.hide()
	add_child(l)
	return plate

## A tag as wide as its words on screen (translated: "INFORMANTE  ·  AL DESCUBIERTO" is wider than its English).
func _size_tag(l: Label) -> void:
	l.size=Vector2(ceilf(ActionSlot.face("semi",2).get_string_size(l.atr(l.text),HORIZONTAL_ALIGNMENT_LEFT,-1,16).x)+16,22)

# --- the dossier -----------------------------------------------------------------------------------
func _build_modal() -> void:
	overlay=ColorRect.new()
	overlay.color=Color(0.02,0.03,0.025,0.66)
	overlay.mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sheet:=Sheet.new()
	sheet.paper=TexPaper
	sheet.stain=TexStain
	sheet.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	modal=sheet
	overlay.add_child(modal)
	var margin:=MarginContainer.new()
	margin.add_theme_constant_override("margin_left",int(SHEET_PAD.x))
	margin.add_theme_constant_override("margin_right",int(SHEET_PAD.x))
	margin.add_theme_constant_override("margin_top",int(SHEET_PAD.y))
	margin.add_theme_constant_override("margin_bottom",int(SHEET_PAD.y)-6)
	modal.add_child(margin)
	modal_box=VBoxContainer.new()
	modal_box.add_theme_constant_override("separation",0)
	margin.add_child(modal_box)
	var head:=HBoxContainer.new()
	modal_box.add_child(head)
	var title:=ink(Missions.brand().to_upper()+"  /  FIELD OPERATIONS",16,"semi",2,0.78)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	head.add_child(title)
	modal_page=ink("",16,"semi",2,0.78)
	head.add_child(modal_page)
	modal_box.add_child(_spacer(5))
	var rule:=Rule.new()
	rule.ink=Color(INK,0.78)
	modal_box.add_child(rule)
	modal_box.add_child(_spacer(12))
	modal_title=ink(copy("title",""),58,"stencil",1)
	modal_title.add_theme_constant_override("line_spacing",-12)
	modal_box.add_child(modal_title)
	modal_box.add_child(_spacer(10))
	modal_body=ink("",22,"type")
	modal_body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	modal_body.add_theme_constant_override("line_spacing",2)
	modal_body.custom_minimum_size.x=420
	modal_box.add_child(modal_body)
	modal_box.add_child(_spacer(8))
	operatives_row=canvas(_paint_operatives,Vector2(0,132))
	modal_box.add_child(operatives_row)
	_build_howto()
	stats_row=canvas(_paint_stats,Vector2(0,74))
	modal_box.add_child(stats_row)
	badge_row=canvas(_paint_badges,Vector2(0,136))
	modal_box.add_child(badge_row)
	menu_grid=GridContainer.new()
	menu_grid.columns=2
	menu_grid.add_theme_constant_override("h_separation",8)
	menu_grid.add_theme_constant_override("v_separation",8)
	modal_box.add_child(menu_grid)
	for spec: Array in [["save","SAVE CHECKPOINT"],["load","LOAD CHECKPOINT"],["howto","HOW TO PLAY"],["restart","RESTART MISSION"]]:
		var key: String=spec[0]
		var b:=button(spec[1],_menu_pressed.bind(key),Vector2(0,80),"secondary")
		b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		menu_grid.add_child(b)
		menu_buttons[key]=b
	# the pause menu also asks what the player thinks, for whoever stops before the end (main.gd opens the launch
	# screen's questions over the paused level)
	menu_questions=VBoxContainer.new()
	menu_questions.add_theme_constant_override("separation",0)
	menu_questions.add_child(_spacer(8))
	var ask:=button(QUESTIONS,func() -> void: command.emit("questions"),Vector2(0,80),"secondary")
	ask.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	menu_questions.add_child(ask)
	menu_buttons["questions"]=ask
	modal_box.add_child(menu_questions)
	modal_box.add_child(_size_row())
	modal_box.add_child(_volume_row())
	modal_box.add_child(_spacer(14))
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	modal_box.add_child(row)
	second_button=button("HOW TO PLAY",_second_pressed,Vector2(0,84),"secondary")
	second_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	second_button.size_flags_stretch_ratio=0.62
	row.add_child(second_button)
	begin_button=button("BEGIN OPERATION",_primary_pressed,Vector2(0,84),"primary")
	begin_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(begin_button)
	modal_box.add_child(_spacer(8))
	foot=ink("",16,"type",0,0.72)
	foot.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	foot.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	modal_box.add_child(foot)
	modal.minimum_size_changed.connect(_queue_modal)
	modal_body.resized.connect(_queue_modal)

func _spacer(height: float) -> Control:
	var c:=Control.new()
	c.custom_minimum_size=Vector2(0,height)
	c.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return c

## HOW TO PLAY: the clip, framed like a photo clipped to the dossier, the line under it, and the dots.
func _build_howto() -> void:
	howto_box=VBoxContainer.new()
	howto_box.add_theme_constant_override("separation",0)
	modal_box.add_child(howto_box)
	howto_frame=Control.new()
	howto_frame.mouse_filter=Control.MOUSE_FILTER_STOP
	howto_frame.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	howto_frame.custom_minimum_size=Vector2(560,315)
	howto_frame.gui_input.connect(_on_howto_input)
	howto_body=BoxContainer.new()
	howto_body.vertical=true
	howto_body.add_theme_constant_override("separation",14)
	howto_box.add_child(howto_body)
	howto_body.add_child(howto_frame)
	var poster:=canvas(_paint_howto_poster)
	howto_frame.add_child(poster)
	poster.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	howto_video=VideoStreamPlayer.new()
	howto_video.expand=true
	howto_video.loop=true
	howto_video.mouse_filter=Control.MOUSE_FILTER_IGNORE
	howto_frame.add_child(howto_video)
	howto_video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var keyline:=canvas(_paint_howto_frame)
	howto_frame.add_child(keyline)
	keyline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	howto_line=ink("",HOWTO_LINE_SIZE,"semi")
	howto_line.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	howto_line.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	howto_line.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	howto_line.add_theme_constant_override("line_spacing",0)
	howto_body.add_child(howto_line)
	howto_dots=canvas(_paint_howto_dots,Vector2(0,26))
	howto_box.add_child(howto_dots)
	overlay.visibility_changed.connect(func() -> void:
		if not overlay.visible: howto_video.stop())

## The cards: the mission's own when it has them (data copy.howto, Hora Cero's), Saboteurs' otherwise.
func _howto() -> Array:
	var own: Array=sim.data.get("copy",{}).get("howto",[]) if sim!=null else []
	return own if not own.is_empty() else HOWTO

## Card `index` of HOW TO PLAY: its clip, its line, and what the two buttons do from here.
func show_card(index: int) -> void:
	var cards: Array=_howto()
	howto_page=clampi(index,0,cards.size()-1)
	var card: Dictionary=cards[howto_page]
	modal_page.text=tr("HOW TO PLAY  %d / %d") % [howto_page+1,cards.size()]
	howto_line.text=tr(str(card.line))
	var clip: VideoStream=_clip(str(card.id))
	howto_video.stream=clip
	howto_video.visible=clip!=null
	if clip!=null and overlay.visible: howto_video.play()
	howto_dots.queue_redraw()
	var last: bool=howto_page==cards.size()-1
	if howto_page>0: second_button.text="BACK"
	else: second_button.text="BACK TO MENU" if _howto_back=="menu" else ("MENU" if _howto_back=="title" else "BRIEFING")
	if not last: begin_button.text="NEXT"
	elif _howto_back=="title": begin_button.text="DONE"
	else: begin_button.text="RETURN TO OPERATION" if sim.phase=="playing" else "BEGIN OPERATION"

func _clip(id: String) -> VideoStream:
	if not _clips.has(id):
		var path: String=HOWTO_DIR+id+".ogv"
		_clips[id]=load(path) if ResourceLoader.exists(path) else null
	return _clips[id]

## A swipe across the clip turns the card either way; a plain tap on it moves on.
func _on_howto_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or (event as InputEventMouseButton).button_index!=MOUSE_BUTTON_LEFT: return
	var press:=event as InputEventMouseButton
	if press.pressed:
		_swipe_from=press.position
		return
	if not _swipe_from.is_finite(): return
	var dx: float=press.position.x-_swipe_from.x
	_swipe_from=Vector2.INF
	if dx>SWIPE:
		if howto_page>0: show_card(howto_page-1)
	elif howto_page<_howto().size()-1: show_card(howto_page+1)
	howto_frame.accept_event()

func _paint_howto_poster(c: Canvas) -> void:
	c.draw_rect(Rect2(Vector2.ZERO,c.size),Color(0.1,0.12,0.09))
	ActionSlot.glyph(c,str(_howto()[howto_page].glyph),c.size*0.5,minf(c.size.y*0.4,120.0),Color(IVORY,0.5))

func _paint_howto_frame(c: Canvas) -> void:
	c.draw_rect(Rect2(Vector2(-3,-3),c.size+Vector2(6,6)),Color(INK,0.92),false,3.0)
	c.draw_rect(Rect2(Vector2.ZERO,c.size),Color(0,0,0,0.35),false,1.0)

func _paint_howto_dots(c: Canvas) -> void:
	var gap: float=22.0
	var left: float=c.size.x*0.5-gap*(_howto().size()-1)*0.5
	for i: int in range(_howto().size()):
		var at:=Vector2(left+gap*i,c.size.y*0.5+3.0)
		if i==howto_page: c.draw_circle(at,6.0,INK,true,-1.0,true)
		else: c.draw_circle(at,5.0,Color(INK,0.55),false,1.5,true)

## The squad on the briefing: ID photo, name, role, and the kit as glyphs with its words.
func _paint_operatives(c: Canvas) -> void:
	var m: Dictionary=_cards if not _cards.is_empty() else _card_layout(c.size.x)
	var count: int=sim.units.size()
	var stacked: bool=bool(m.stacked)
	var gap: float=float(m.gap)
	var cols: int=int(m.get("cols",1))
	var rows: int=ceili(float(count)/cols) if stacked else 1
	var cell_w: float=(c.size.x-14.0*(cols-1))/cols if stacked else (c.size.x-gap*(count-1))/count
	var cell_h: float=(c.size.y-gap*(rows-1))/rows if stacked else c.size.y
	var word_size: int=int(m.words)
	for i: int in range(count):
		var u: Dictionary=sim.units[i]
		var at:=Vector2((i%cols)*(cell_w+14.0),(i/cols)*(cell_h+gap)) if stacked else Vector2(i*(cell_w+gap),0)
		var side: float=minf(cell_h,float(m.photo))
		var photo:=Rect2(at,Vector2(side,side))
		var id: String=str(u.id)
		var art: Dictionary=_art_of(id)
		var pic: Dictionary=ArtPack.portrait(art) if not art.is_empty() else {}
		if art.is_empty(): c.draw_texture_rect_region(Portraits,photo.grow(-3),photo_rect(id))
		elif not pic.is_empty(): c.draw_texture_rect_region(pic.texture,photo.grow(-3),_square(pic))
		else:
			# no portrait yet: a plain plate with the name
			c.draw_rect(photo.grow(-3),Color(0.86,0.84,0.78))
			var words: PackedStringArray=ArtPack.display_name(art,Lang.current).to_upper().split(" ",false)
			var px: int=int(clampf(side*0.17,14.0,26.0))
			var top: float=photo.get_center().y-(px+2.0)*words.size()*0.5+px*0.82
			for k: int in range(words.size()):
				ActionSlot.label(c,ActionSlot.face("semi",2),words[k],photo.get_center().x,top+(px+2.0)*k,px,INK)
		c.draw_rect(photo.grow(-1),Color(INK,0.9),false,3.0)
		var x: float=at.x+side+16.0
		var room: float=cell_w-side-16.0
		var f_name: Font=ActionSlot.face("stencil",1)
		c.draw_string(f_name,Vector2(x,at.y+float(m.name_y)),str(u.name).to_upper(),HORIZONTAL_ALIGNMENT_LEFT,room,int(m.name),INK)
		c.draw_string(ActionSlot.face("semi",2),Vector2(x,at.y+float(m.role_y)),str(u.role).to_upper(),HORIZONTAL_ALIGNMENT_LEFT,room,15,Color(INK,0.72))
		var kit: Array=_kit(u)
		var glyph: float=float(m.glyph)
		var gx: float=x+glyph*0.5
		for item: Array in kit:
			if gx>x+room-glyph*0.4: break
			ActionSlot.glyph(c,str(item[0]),Vector2(gx,at.y+float(m.glyph_y)),glyph,Color(INK,0.9))
			gx+=float(m.step)
		var words: PackedStringArray=[]
		for item: Array in kit: words.append(str(item[1]))
		c.draw_multiline_string(ActionSlot.face("medium"),Vector2(x,at.y+float(m.words_y)),", ".join(words),HORIZONTAL_ALIGNMENT_LEFT,room,word_size,int(m.max_lines),Color(INK,0.95))

## How the briefing lays the squad out in `inner` pixels: side by side while each card has room for its kit to
## read, one above the other on an upright phone. Three to a row take a smaller photo and smaller type.
func _card_layout(inner: float) -> Dictionary:
	var count: int=maxi(1,sim.units.size() if sim!=null else 2)
	var three: bool=count>2
	var gap: float=20.0 if three else 24.0
	var across: float=(inner-gap*(count-1))/count
	var stacked: bool=across<(270.0 if three else 308.0)
	# five or more on an upright phone go two to a row, in smaller cards, so the squad fits a screen with its text
	var paired: bool=stacked and count>=5 and inner>=300.0
	var m:={"stacked":stacked,"paired":paired,"cols":2 if paired else 1,"gap":(14.0 if three else 24.0) if stacked else gap,
		"photo":OPERATIVE_PHOTO if not three else (72.0 if paired else (96.0 if stacked else 104.0)),
		"name":32 if not three else (22 if paired else 28),"name_y":30.0 if not three else (21.0 if paired else 27.0),"role_y":52.0 if not three else (37.0 if paired else 47.0),
		"glyph":30.0 if not three else (22.0 if paired else 26.0),"step":38.0 if not three else (27.0 if paired else 32.0),"glyph_y":76.0 if not three else (55.0 if paired else 69.0),
		"words":19 if (not three or (stacked and not paired)) else (15 if paired else 17),"words_y":112.0 if not three else (80.0 if paired else 101.0),
		"max_lines":3 if (not three or (stacked and not paired)) else 4}
	var cell_w: float=(inner-14.0)*0.5 if paired else (inner if stacked else across)
	var room: float=cell_w-float(m.photo)-16.0
	var face: Font=ActionSlot.face("medium")
	var line_h: float=face.get_height(int(m.words))
	var lines: int=1
	if sim!=null:
		for u: Dictionary in sim.units:
			var words: PackedStringArray=[]
			for item: Array in _kit(u): words.append(str(item[1]))
			var block: Vector2=face.get_multiline_string_size(", ".join(words),HORIZONTAL_ALIGNMENT_LEFT,room,int(m.words))
			lines=maxi(lines,mini(int(m.max_lines),ceili(block.y/line_h-0.01)))
	var one: float=maxf(float(m.photo),float(m.words_y)+line_h*(lines-1)+8.0)
	if not three: one=maxf(132.0,one)
	var rows: int=ceili(float(count)/2.0) if paired else count
	m.row_h=ceilf(one*rows+float(m.gap)*(rows-1)) if stacked else ceilf(one)
	return m

## An operative's kit, from the mission data: [glyph, word].
func _kit(u: Dictionary) -> Array:
	var kit: Array=[]
	if u.has("melee"):
		if u.melee.has("kit"): kit.append([str(u.melee.get("icon","bind")),str(u.melee.kit)])
		elif float(u.melee.get("stun",0.0))>0.0: kit.append(["cosh","cosh"])
		else: kit.append(["knife","knife"] if bool(u.melee.get("lethal",false)) else ["bind","rope"])
	if u.has("gun"):
		if u.gun.has("kit"): kit.append([str(u.gun.get("icon","revolver")),str(u.gun.kit)])
		else: kit.append(["revolver","loud revolver"] if bool(u.gun.get("loud",false)) else ["pistol","silenced pistol"])
	if bool(u.get("pebble",false)): kit.append(["throw","pebbles"])
	if int(u.get("traps",0))>0: kit.append(["tripwire","tripwire"])
	if bool(u.get("tools",false)):
		# a mission may name them in its own words (a motorman's keys at La Boca, where there is no wire to cut)
		if u.has("toolsKit"): kit.append(["key",str(u.toolsKit)])
		else:
			kit.append(["key","lock picks"])
			kit.append(["cutters","wire cutters"])
	# his own clothes (data cover.icon: the motorman's cap, the newsboy's): who he is, so they come first (below)
	var clothes: Array=[]
	if u.has("cover"):
		clothes=[str(u.cover.get("icon","walk")),str(u.cover.get("kit","dock clothes"))]
		kit.append(clothes)
	if u.has("chat"): kit.append(["cigarette","%d cigarettes" % int(u.chat.get("count",3))])
	if u.has("throw"): kit.append([str(u.throw.get("icon","bottle")),str(u.throw.get("kit","%d bottles" % int(u.throw.get("count",2))))])
	if u.has("exit"): kit.append(["gate","his own way home"])
	# the ski scout: his rope for the gorge, his skis, his snowsuit, the valley's language
	if sim!=null:
		for passage: Dictionary in sim.passages():
			# (a passage he opens with what he has anyway, lock picks, says nothing new: "kit" empty)
			if str(u.id) in passage.get("by",[]) and str(passage.get("kit","a rope for the gorge"))!="": kit.append([str(passage.get("icon","rope")),str(passage.get("kit","a rope for the gorge"))])
		# the key to what he puts out of action, when the mission names it (Lechuza's key to the lamp board)
		var radio: Dictionary=sim.data.get("radio",{})
		if radio.get("kit") is Dictionary and sim.can_sabotage(u): kit.append([str(radio.kit.get("icon",radio.get("icon","radio"))),str(radio.kit.get("text",""))])
	if u.has("skis"): kit.append(["skis",str(u.skis.get("kit","skis"))])
	if u.has("camo"): kit.append(["snowsuit",str(u.camo.get("kit","white snowsuit"))])
	if u.has("talk"): kit.append(["talk",str(u.talk.get("kit","the local language"))])
	# a local's own clothes are who he is: they come first
	var worn: int=kit.find(clothes)
	if worn>0: kit.push_front(kit.pop_at(worn))
	# what this operation is about comes first: the limpets, the charges (a site's kind drawn as its marker is)
	var carried: Array[String]=[]
	if sim!=null:
		for site: Dictionary in sim.charge_sites():
			var kind: String=str(site.get("kind","charge"))
			if str(u.id) in site.get("by",[]) and not kind in carried: carried.append(kind)
	for kind: String in carried:
		kit.push_front([str(thing_icons.get(kind,kind)),"limpets" if kind=="limpet" else "demolition charges"])
	# in the player's language: a word of the kit is translated on its own ("%d cigarettes" as a template)
	for item: Array in kit: item[1]=tr(str(item[1]))
	if not kit.is_empty():
		var first: String=str(kit[0][1])
		kit[0][1]=first.left(1).to_upper()+first.substr(1)
	return kit

## A text-size switch: "TEXT SIZE" and three keys (the pause menu; the launch screen's Settings has its own).
func _size_row() -> VBoxContainer:
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",int(GAP))
	var size_label:=ink("TEXT SIZE",16,"semi",2,0.78)
	size_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	size_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	# a longer language ("TAMAÑO DEL TEXTO") folds onto two lines rather than widening the dossier
	size_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	size_label.custom_minimum_size.x=48
	row.add_child(size_label)
	var keys: Array[SizeKey]=[]
	for i: int in range(TEXT_SIZE_LETTERS.size()):
		var key:=SizeKey.new()
		key.letter_px=TEXT_SIZE_LETTERS[i]
		key.custom_minimum_size=Vector2(MIN_TOUCH,MIN_TOUCH)
		key.tooltip_text=TEXT_SIZE_NAMES[i]
		key.chosen=i==text_size()
		key.pressed.connect(set_text_size.bind(i))
		row.add_child(key)
		keys.append(key)
	var holder:=VBoxContainer.new()
	holder.add_theme_constant_override("separation",0)
	holder.add_child(_spacer(12))
	holder.add_child(row)
	size_rows.append({"row":holder,"keys":keys})
	return holder

## The VOLUME controls: the sound key (mute) and the bars beside it (the pause menu and the launch screen's Settings each
## have a set, kept in step with each other).
func volume_controls() -> Array[Control]:
	var off:=MuteKey.new()
	off.custom_minimum_size=Vector2(MIN_TOUCH,MIN_TOUCH)
	off.chosen=volume()==0
	off.pressed.connect(toggle_sound)
	var bar:=VolumeBar.new()
	bar.custom_minimum_size=Vector2(150,MIN_TOUCH)
	bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	bar.level=volume() if volume()>0 else _volume_before_off()
	bar.muted=volume()==0
	bar.picked.connect(set_volume)
	volume_rows.append({"off":off,"bar":bar})
	return [off,bar]

## The pause menu's VOLUME row: in a game, the sound goes down or off without leaving the operation.
func _volume_row() -> VBoxContainer:
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",int(GAP))
	var caption:=ink("VOLUME",16,"semi",2,0.78)
	caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	caption.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	caption.custom_minimum_size.x=48
	row.add_child(caption)
	for control: Control in volume_controls(): row.add_child(control)
	var holder:=VBoxContainer.new()
	holder.add_theme_constant_override("separation",0)
	holder.add_child(_spacer(8))
	holder.add_child(row)
	volume_rows[volume_rows.size()-1]["row"]=holder
	return holder

## 0 is off; 1 to 4 are steps up to full (the default). An older progress file only knows sound on or off.
func volume() -> int:
	if progress.has_section_key("settings","volume"):
		return clampi(int(progress.get_value("settings","volume",VOLUME_DB.size()-1)),0,VOLUME_DB.size()-1)
	return VOLUME_DB.size()-1 if bool(progress.get_value("settings","sound",true)) else 0

func set_volume(choice: int) -> void:
	choice=clampi(choice,0,VOLUME_DB.size()-1)
	var live: Array[Dictionary]=[]
	for entry: Dictionary in volume_rows:
		if not is_instance_valid(entry.off) or not is_instance_valid(entry.bar): continue
		live.append(entry)
		(entry.off as MuteKey).chosen=choice==0
		(entry.bar as VolumeBar).muted=choice==0
		if choice>0: (entry.bar as VolumeBar).level=choice
	volume_rows=live
	if choice>0: progress.set_value("settings","volume_on",choice)
	progress.set_value("settings","volume",choice)
	progress.set_value("settings","sound",choice>0)
	_save_progress()
	command.emit("settings")

## OFF mutes; pressed again, the sound comes back at the step it had.
func toggle_sound() -> void:
	set_volume(0 if volume()>0 else _volume_before_off())

func _volume_before_off() -> int:
	return clampi(int(progress.get_value("settings","volume_on",VOLUME_DB.size()-1)),1,VOLUME_DB.size()-1)

## 0 small, 1 medium (the default), 2 large. Kept with the progress file.
func text_size() -> int:
	return clampi(int(progress.get_value("settings","text_size",1)),0,TEXT_SIZE_LETTERS.size()-1)

func set_text_size(choice: int) -> void:
	choice=clampi(choice,0,TEXT_SIZE_LETTERS.size()-1)
	for entry: Dictionary in size_rows:
		for i: int in range((entry.keys as Array).size()): (entry.keys[i] as SizeKey).chosen=i==choice
	if choice==text_size(): return
	progress.set_value("settings","text_size",choice)
	_save_progress()
	command.emit("text_size")

# --- progress on disk ------------------------------------------------------------------------------
func load_progress() -> void:
	progress=ConfigFile.new()
	progress.load(progress_path)

func _save_progress() -> void:
	progress.save(progress_path)

## {earned: bool, runs: int, best_time: float} for a badge id; empty if it was never earned.
func badge_record(id: String) -> Dictionary:
	return progress.get_value(badge_section,id,{})

## Writes this run's badges and time to the progress file (once per win).
func record_result() -> void:
	if _result_saved or sim.phase!="won": return
	_result_saved=true
	_new_badges.clear()
	for entry: Dictionary in sim.result_badges():
		if not bool(entry.earned): continue
		var record: Dictionary=badge_record(str(entry.id))
		if record.is_empty(): _new_badges.append(str(entry.id))
		record["earned"]=true
		record["runs"]=int(record.get("runs",0))+1
		record["best_time"]=minf(float(record.get("best_time",INF)),float(sim.time))
		progress.set_value(badge_section,str(entry.id),record)
	progress.set_value(best_section,"time",minf(float(progress.get_value(best_section,"time",INF)),float(sim.time)))
	progress.set_value(best_section,"runs",int(progress.get_value(best_section,"runs",0))+1)
	# the ghost best: no alarm raised and nobody killed
	if int(sim.stats.alarms)==0 and int(sim.stats.kills)==0:
		progress.set_value(best_section,"ghost",minf(float(progress.get_value(best_section,"ghost",INF)),float(sim.time)))
	_save_progress()

# --- layout ------------------------------------------------------------------------------------------
## The ID photo on an operative's portrait: his own in the portrait atlas; for one dressed from the art pack (data look
## "art:<slot>"), the slot's portrait if it has come (its head and shoulders cut square: _square), else a plain plate
## with his name.
func _dress_photo(b: ActionSlot, id: String) -> void:
	var art: Dictionary=_art_of(id)
	if art.is_empty():
		b.photo=Portraits
		b.photo_region=photo_rect(id)
		return
	var pic: Dictionary=ArtPack.portrait(art)
	if pic.is_empty():
		b.photo=null
		b.photo_plate=ArtPack.display_name(art,Lang.current).to_upper()
		return
	b.photo=pic.texture
	b.photo_region=_square(pic)

## The art pack's slot an operative wears (data look "art:<slot>"), {} for one in his own figure.
func _art_of(id: String) -> Dictionary:
	var u: Dictionary=sim.unit_by_id(id) if sim!=null else {}
	return ArtPack.parse_look(str(u.get("look",""))) if not u.is_empty() and str(u.get("look","")).begins_with("art:") else {}

## The square of a portrait drawing (pixels) for the photo's window: across the middle of a wide one; at the top of a
## tall one (a bust: the head and shoulders, as the squad's photos are framed), just under its top edge.
static func _square(pic: Dictionary) -> Rect2:
	var size: Vector2=Vector2(pic.size)
	var used: Rect2=pic.used
	var r := Rect2(used.position*size,used.size*size)
	var side: float=minf(r.size.x,r.size.y)
	var at: Vector2=r.get_center()-Vector2(side,side)*0.5
	if r.size.y>r.size.x: at.y=r.position.y+(r.size.y-side)*0.06
	return Rect2(at,Vector2(side,side))

## Where an operative's photo is in the portrait atlas (384 px squares side by side): data "portrait", else his
## place in the squad.
func photo_rect(id: String) -> Rect2:
	var u: Dictionary=sim.unit_by_id(id) if sim!=null else {}
	var i: int=int(u.get("portrait",operatives.find(id))) if not u.is_empty() else 0
	return Rect2(384*maxi(i,0),0,384,384)

## Notch / Dynamic Island / home-indicator insets in logical canvas pixels (left, top, right, bottom).
func safe_insets() -> Vector4:
	var area := Vector4.ZERO
	if safe_override is Vector4:
		area=safe_override
	elif OS.has_feature("mobile"):
		# The display reports its safe rectangle in device pixels; the window is the whole screen.
		var screen: Vector2=Vector2(DisplayServer.screen_get_size())
		var origin: Vector2=Vector2(DisplayServer.screen_get_position())
		var safe: Rect2=Rect2(DisplayServer.get_display_safe_area())
		var window: Vector2=Vector2(get_window().size)
		if screen.x>0 and screen.y>0 and window.x>0 and window.y>0 and safe.size.x>0 and safe.size.y>0:
			var scale_x: float=viewport_size.x/window.x
			var scale_y: float=viewport_size.y/window.y
			area=Vector4((safe.position.x-origin.x)*scale_x,(safe.position.y-origin.y)*scale_y,(origin.x+screen.x-safe.end.x)*scale_x,(origin.y+screen.y-safe.end.y)*scale_y)
	# Never let a bad report eat the screen: cap each side at a sixth of that dimension.
	var cap_x: float=viewport_size.x/6.0
	var cap_y: float=viewport_size.y/6.0
	return Vector4(clampf(area.x,0,cap_x),clampf(area.y,0,cap_y),clampf(area.z,0,cap_x),clampf(area.w,0,cap_y))

func layout() -> void:
	viewport_size=get_viewport_rect().size
	_upright=viewport_size.y>viewport_size.x
	insets=safe_insets()
	var left: float=roundf(maxf(MARGIN,insets.x))
	var top: float=roundf(maxf(MARGIN,insets.y))
	var right: float=roundf(viewport_size.x-maxf(MARGIN,insets.z))
	var bottom: float=roundf(viewport_size.y-maxf(MARGIN,insets.w))
	var center: float=roundf((left+right)*0.5)
	var tools_width: float=TOOL_SIZE.x*2+GAP
	# Two photos at full size; a third squeezes them so the block stays about as wide (never below a thumb).
	var count: int=maxi(1,operatives.size())
	var photo_w: float=PORTRAIT_SIZE.x
	# Four on an upright phone: the photos take the bottom row to themselves (the view keys beside them, one over
	# the other) and the action bar goes across the screen above them.
	var four_up: bool=_upright and count>=4
	if count>2:
		if four_up:
			photo_w=clampf(floorf((right-left-8-CAMERA_SIZE.x-8*(count-1))/count),MIN_TOUCH,PORTRAIT_SIZE.x)
		elif _upright:
			photo_w=maxf(MIN_TOUCH,floorf((PORTRAIT_SIZE.x*2+8-8*(count-1))/count)+4)
		else:
			var room: float=(right-left)-(8+CAMERA_SIZE.x+12)-(76.0*5+PLAN_WIDTH+GAP*5)
			photo_w=clampf(floorf((room-8*(count-1))/count),MIN_TOUCH,PORTRAIT_SIZE.x)
	for b: Control in portrait_strip.get_children():
		b.custom_minimum_size=Vector2(photo_w,PORTRAIT_SIZE.y)
	var photos_width: float=photo_w*count+8*(count-1)
	var block_width: float=photos_width if (_upright and not four_up) else photos_width+8+CAMERA_SIZE.x
	# Top left: clock and detection, objectives underneath.
	readout.position=Vector2(left,top)
	readout.size=Vector2(264,STATUS_HEIGHT)
	objective_block.position=Vector2(left,top+STATUS_HEIGHT+8)
	_block_limit=maxf(220.0,right-tools_width-14-left)
	# Landscape: the banners hang top centre, level with the block; it stops short of the widest of them.
	if not _upright: _block_limit=maxf(264.0,minf(_block_limit,center-PROMPT_SIZE.x*0.5-10-left))
	_obj_key=-1
	# Top right: menu and map keys over the recon map, one column.
	tools_row.position=Vector2(right-tools_width,top)
	tools_row.size=Vector2(tools_width,TOOL_SIZE.y)
	var sheet_width: float=tools_width-Recon.FRAME*2
	minimap.position=Vector2(right-tools_width,top+TOOL_SIZE.y+GAP)
	minimap.size=Vector2(tools_width,roundf(sheet_width*float(sim.data.height)/float(sim.data.width))+Recon.FRAME*2)
	# Bottom left: ID photos under their order tags; the view keys beside them (above, when upright).
	portrait_strip.position=Vector2(left,bottom-PORTRAIT_SIZE.y)
	portrait_strip.size=Vector2(photos_width,PORTRAIT_SIZE.y)
	var tag_top: float=bottom-PORTRAIT_SIZE.y-4-TAG_HEIGHT
	var index: int=0
	for id: String in tags:
		var tag: Canvas=tags[id]
		tag.position=Vector2(left+index*(photo_w+8),tag_top)
		tag.size=Vector2(photo_w,TAG_HEIGHT)
		index+=1
	var turn_left: Control=camera_row.get_child(0)
	var turn_right: Control=camera_row.get_child(1)
	if _upright and not four_up:
		var key_width: float=floorf((photos_width-GAP)*0.5)
		camera_row.position=Vector2(left,tag_top-GAP-CAMERA_SIZE.y)
		camera_row.size=Vector2(photos_width,CAMERA_SIZE.y)
		turn_left.position=Vector2.ZERO
		turn_left.size=Vector2(key_width,CAMERA_SIZE.y)
		turn_right.position=Vector2(key_width+GAP,0)
		turn_right.size=Vector2(key_width,CAMERA_SIZE.y)
	else:
		camera_row.position=Vector2(left+photos_width+8,bottom-PORTRAIT_SIZE.y)
		camera_row.size=Vector2(CAMERA_SIZE.x,PORTRAIT_SIZE.y)
		turn_left.position=Vector2.ZERO
		turn_left.size=CAMERA_SIZE
		turn_right.position=Vector2(0,PORTRAIT_SIZE.y-CAMERA_SIZE.y)
		turn_right.size=CAMERA_SIZE
	# Bottom right: the action bar; two rows of three beside the photos when the screen is upright.
	var bar_left: float=left+block_width+12
	var bar_top: float
	_bar_right=right
	_bar_rows=_upright
	if _upright:
		var across: float=(right-left) if four_up else (right-bar_left)
		_bar_slot=floorf((across-GAP*2)/3.0)
		_bar_across=_bar_slot*3+GAP*2
		bar_top=(tag_top-GAP-SLOT_SIZE.y*2-GAP) if four_up else bottom-SLOT_SIZE.y*2-GAP
	else:
		# Full-size plates where they fit; a notch on a short screen narrows them, never below a thumb.
		_bar_slot=clampf(floorf((right-bar_left-PLAN_WIDTH-GAP*5)/5.0),76.0,SLOT_SIZE.x)
		_bar_across=_bar_slot*5+PLAN_WIDTH+GAP*5
		bar_top=bottom-SLOT_SIZE.y
	_bar_top=bar_top
	_place_bar()
	# Banners: top centre, or under the top blocks when the screen is upright.
	var banner_top: float=top if not _upright else minimap.position.y+minimap.size.y+12
	planning.position=Vector2(roundf(center-BANNER_SIZE.x*0.5),banner_top)
	planning.size=BANNER_SIZE
	alarm_banner.size=ALARM_SIZE
	# The armed weapon's prompt takes the banner's place while it is up.
	prompt.position=Vector2(roundf(center-PROMPT_SIZE.x*0.5),banner_top)
	prompt.size=PROMPT_SIZE
	# Notices and hints are centred on the screen above the bar. In landscape, when the photos leave too narrow a
	# gap beside them (four of them on a phone), the lines go up above the photos' tags instead, as wide as the
	# right-hand column allows.
	var lines_top: float=(bar_top if four_up else camera_row.position.y) if _upright else bar_top
	_notice_width=minf(760.0,right-left-36) if _upright else minf(760.0,(center-left-block_width-18)*2)
	if not _upright and _notice_width<520.0:
		_notice_width=minf(760.0,(right-tools_width-14-center)*2)
		lines_top=tag_top
	_notice_base=Vector2(center,lines_top-14)
	_place_toast()
	_place_lines()
	_place_banners()
	_place_modal()
	frame.queue_redraw()
	refresh()

## Lays out the bar's plates where layout() put the bar. A plate the operative has nothing for is left out
## (_bar_shown; every plate before the first refresh) and the others close up: upright, two rows sharing the strip's
## width, the top row taking the odd plate (fewer than three to a row are wider); landscape, one row against the right
## edge, PLAN the wide plate in the corner.
func _place_bar() -> void:
	var keys: Array[String]=[]
	for key: String in SLOT_ORDER:
		var on: bool=_bar_shown.is_empty() or key in _bar_shown
		(slots[key] as ActionSlot).visible=on
		if on: keys.append(key)
	if _bar_rows:
		action_strip.position=Vector2(_bar_right-_bar_across,_bar_top)
		action_strip.size=Vector2(_bar_across,SLOT_SIZE.y*2+GAP)
		var first_row: int=ceili(keys.size()*0.5)
		for i: int in range(keys.size()):
			var row: int=0 if i<first_row else 1
			var count: int=first_row if row==0 else keys.size()-first_row
			var at: int=i if row==0 else i-first_row
			var w: float=_bar_slot if count==3 else floorf((_bar_across-GAP*(count-1))/count)
			var b: ActionSlot=slots[keys[i]]
			# (the last of a row sits flush with the strip's right edge)
			b.position=Vector2(at*(w+GAP) if at<count-1 else _bar_across-w,row*(SLOT_SIZE.y+GAP))
			# (its minimum size goes down with it, or the plate keeps its full width and the next one covers its end)
			b.custom_minimum_size=Vector2(w,SLOT_SIZE.y)
			b.size=Vector2(w,SLOT_SIZE.y)
	else:
		var width: float=GAP*(keys.size()-1)
		for key: String in keys: width+=PLAN_WIDTH if key=="plan" else _bar_slot
		action_strip.position=Vector2(_bar_right-width,_bar_top)
		action_strip.size=Vector2(width,SLOT_SIZE.y)
		var x: float=0.0
		for key: String in keys:
			var b: ActionSlot=slots[key]
			var w: float=PLAN_WIDTH if key=="plan" else _bar_slot
			b.position=Vector2(x,0)
			b.custom_minimum_size=Vector2(w,SLOT_SIZE.y)
			b.size=Vector2(w,SLOT_SIZE.y)
			x+=w+GAP

func _place_banners() -> void:
	var live: bool=sim.phase=="playing" and not overlay.visible
	prompt.visible=live and armed!=""
	planning.visible=live and sim.paused and armed==""
	alarm_banner.visible=live and bool(sim.alarm.active)
	var center: float=planning.position.x+BANNER_SIZE.x*0.5
	alarm_banner.position=Vector2(roundf(center-ALARM_SIZE.x*0.5),planning.position.y+((BANNER_SIZE.y+8) if (planning.visible or prompt.visible) else 0.0))

## Stacks the lines of text upward from the bar: the notice, then a hint.
func _place_lines() -> void:
	_fit_line(hint_label,hint_plate,_fit_line(notice,notice_plate,_notice_base.y))

## Wraps a line inside the notice width and hugs its strip to the typed text, growing upward from
## `floor_y`. Returns the y above it for the next line. The text is measured as the Label shows it, in the
## player's language: a hint or a notice is set in English and translated on screen, and Spanish runs longer.
func _fit_line(l: Label, plate: Backing, floor_y: float) -> float:
	if not l.visible: return floor_y
	var f: Font=l.get_theme_font("font")
	var px: int=l.get_theme_font_size("font_size")
	var inner: float=_notice_width-36
	var block: Vector2=f.get_multiline_string_size(l.atr(l.text),HORIZONTAL_ALIGNMENT_CENTER,inner,px)
	var height: float=ceilf(block.y)
	l.size=Vector2(inner,height)
	l.position=Vector2(roundf(_notice_base.x-inner*0.5),roundf(floor_y-height-7))
	var width: float=minf(inner,ceilf(block.x))+36
	plate.position=Vector2(roundf((inner-width)*0.5),-9)
	plate.size=Vector2(width,height+16)
	return l.position.y-9-10

func _queue_modal() -> void:
	if _modal_queued: return
	_modal_queued=true
	call_deferred("_place_modal")

func _place_modal() -> void:
	_modal_queued=false
	if not is_instance_valid(modal): return
	var left: float=maxf(MARGIN,insets.x)
	var top: float=maxf(8.0,insets.y)
	var right: float=viewport_size.x-maxf(MARGIN,insets.z)
	var bottom: float=viewport_size.y-maxf(8.0,insets.w)
	# A short screen (a phone, on its smaller canvas) has width to spare and no height: the sheets go wider
	# and the big title and buttons give way, so the text itself can stay large.
	var compact: bool=bottom-top<690.0
	var want: float=760.0
	match current_modal:
		"howto": want=1000.0
		"won", "history": want=860.0
		"menu", "lost": want=700.0
		"briefing": want=760.0 if sim==null or sim.units.size()<3 else 1120.0
	if compact: want=maxf(want,980.0)
	var title: int=44 if compact else 58
	if modal_title.get_theme_font_size("font_size")!=title: modal_title.add_theme_font_size_override("font_size",title)
	for b: Button in [second_button,begin_button]:
		if b.custom_minimum_size.y!=(MIN_TOUCH if compact else 84.0): b.custom_minimum_size.y=MIN_TOUCH if compact else 84.0
	var width: float=minf(want,right-left-16)
	var inner: float=width-SHEET_PAD.x*2
	if current_modal=="briefing":
		_cards=_card_layout(inner)
		_operatives_stacked=bool(_cards.stacked)
		var row_h: float=float(_cards.row_h)
		if operatives_row.custom_minimum_size.y!=row_h: operatives_row.custom_minimum_size.y=row_h
		operatives_row.queue_redraw()
	if current_modal=="howto":
		# The clip takes what the screen can spare after the header, the dots and the buttons; the line goes
		# under it (two lines kept) or, where that would leave the clip small, beside it.
		var line_h: float=ceilf(ActionSlot.face("semi").get_height(HOWTO_LINE_SIZE))*2.0
		var fixed: float=SHEET_PAD.y*2.0+44.0+26.0+14.0+begin_button.custom_minimum_size.y+14.0
		var under: float=floorf(clampf(minf(inner*9.0/16.0,(bottom-top)-fixed-14.0-line_h),150.0,520.0))
		var beside: float=floorf(clampf(minf((inner-HOWTO_SIDE_LINE-24.0)*9.0/16.0,(bottom-top)-fixed),150.0,520.0))
		var side: bool=beside>=under
		var clip_h: float=beside if side else under
		var clip:=Vector2(floorf(clip_h*16.0/9.0),clip_h)
		howto_body.vertical=not side
		howto_body.add_theme_constant_override("separation",24 if side else 14)
		howto_frame.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN if side else Control.SIZE_SHRINK_CENTER
		howto_line.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT if side else HORIZONTAL_ALIGNMENT_CENTER
		howto_line.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var line_min:=Vector2(inner-clip.x-24.0,0) if side else Vector2(0,line_h)
		if howto_frame.custom_minimum_size!=clip: howto_frame.custom_minimum_size=clip
		if howto_line.custom_minimum_size!=line_min: howto_line.custom_minimum_size=line_min
	# Height 0 collapses the sheet to its content; the body re-wraps for the new width first.
	modal.size=Vector2(width,0)
	# Still taller than the screen: the whole sheet is drawn smaller rather than cut off.
	var fit: float=minf(1.0,(bottom-top)/maxf(modal.size.y,1.0))
	modal.scale=Vector2(fit,fit)
	modal.position=Vector2(roundf((left+right-width*fit)*0.5),roundf(maxf(top,(top+bottom-modal.size.y*fit)*0.5)))
	var sheet:=modal as Sheet
	var at:=Vector2(width-SHEET_PAD.x-sheet.stamp.get_size().x*0.25-8,SHEET_PAD.y+74) if sheet.stamp else Vector2.ZERO
	if at!=sheet.stamp_at:
		sheet.stamp_at=at
		sheet.queue_redraw()

# --- dossier pages -------------------------------------------------------------------------------------
## briefing | howto ("notes" is the old name) | menu | won | lost
func show_modal(page: String) -> void:
	if page=="notes": page="howto"
	var entering: bool=page=="howto" and current_modal!="howto"
	if entering: _howto_back=current_modal if current_modal in ["briefing","menu"] else "briefing"
	current_modal=page
	var sheet:=modal as Sheet
	var running: bool=sim.phase=="playing"
	sheet.stamp=null
	stats_row.hide()
	badge_row.hide()
	operatives_row.hide()
	howto_box.hide()
	howto_video.stop()
	for entry: Dictionary in size_rows: (entry.row as Control).hide()
	for entry: Dictionary in volume_rows:
		if entry.has("row"): (entry.row as Control).hide()
	menu_grid.hide()
	menu_questions.hide()
	modal_title.show()
	modal_body.show()
	second_button.show()
	begin_button.text="RETURN TO OPERATION" if running else "BEGIN OPERATION"
	modal_title.add_theme_font_size_override("font_size",58)
	foot.text="Tap to move  ·  PLAN to stop the clock  ·  Stay out of the cones"
	match page:
		"briefing":
			modal_page.text=copy("briefingPage","BRIEFING")
			modal_title.text=copy("title","")
			modal_body.text=copy("briefing",BRIEFING_COPY)
			operatives_row.show()
			# before the operation: back to the launch screen; once it runs, the pause menu has the way out
			second_button.text="MENU" if not running else "HOW TO PLAY"
			foot.text=""
			sheet.stamp=_stamp(TexStampSecret,"stamp_secret")
			sheet.stamp_tint=Color(INK,0.55)
		"howto":
			modal_title.hide()
			modal_body.hide()
			howto_box.show()
			foot.text=""
			show_card(0 if entering else howto_page)
		"history":
			_fill_history()
		"menu":
			modal_page.text="PAUSED"
			modal_title.text="OPERATION\nPAUSED"
			_menu_note=""
			_refresh_menu()
			menu_grid.show()
			menu_questions.visible=Feedback.enabled()
			(size_rows[0].row as Control).show()
			for entry: Dictionary in volume_rows:
				if entry.has("row"): (entry.row as Control).show()
			second_button.text="MAIN MENU"
			_leave_armed_until=0.0
			begin_button.text="RESUME"
			foot.text=copy("checkpointNote","Checkpoints are also taken at the cell gate and when the informant is freed.")
		"won":
			record_result()
			_collect_result()
			modal_page.text="DEBRIEF"
			modal_title.text=copy("wonTitle","MISSION\nCOMPLETE")
			var earned: PackedStringArray=[]
			for entry: Dictionary in _badges:
				if bool(entry.earned): earned.append(tr(str(entry.label)))  # a list the Label cannot split: each in the player's language
			_won_earned=earned
			modal_body.text=_won_body()
			stats_row.show()
			badge_row.show()
			# History first where the level has some; otherwise straight on to the next level, if any. After the last
			# one, the questions for the makers (once, until answered, when they have somewhere to go).
			var next: String=Missions.next_of(Missions.current)
			var asking: bool=next=="" and Feedback.due(progress)
			if sim.data.has("history"):
				second_button.text="THE REAL STORY"
				second_button.show()
			elif next!="":
				second_button.text="NEXT OPERATION"
				second_button.show()
			else:
				second_button.text=_questions_word() if asking else "MAIN MENU"
				second_button.show()
			begin_button.text="PLAY AGAIN"
			foot.text="A stamp stays on file once earned. Faint stamps were earned on an earlier run."
			if asking and sim.data.has("history"):
				foot.text="After the real story, a few quick questions from the people making the game."
			sheet.stamp=_stamp(TexStampComplete,"stamp_complete")
			sheet.stamp_tint=Color(0.22,0.31,0.19,0.72)
		_:
			modal_page.text="REPORT"
			modal_title.text="OPERATION\nFAILED"
			var mark: Dictionary=sim.checkpoint
			var where: String="" if mark.is_empty() else tr("\n\nLast checkpoint: %s, %s on the clock.") % [tr(_checkpoint_name(str(mark.get("label","")))),_clock_text(float(mark.get("time",0.0)))]
			modal_body.text="%s\n\n%s%s" % [tr(str(sim.lost_reason)),tr(copy("failureNote","Nobody gets left behind: lose one of the three and it is over. Watch the cones, use the bushes, and stop the clock before you act.")),where]
			second_button.text="RESTART MISSION"
			begin_button.text="RETRY FROM CHECKPOINT" if sim.has_checkpoint() else "RETRY OPERATION"
			foot.text="Retry returns you to the checkpoint with the clock stopped."
			sheet.stamp=_stamp(TexStampAborted,"stamp_aborted")
			sheet.stamp_tint=Color(RED.darkened(0.22),0.8)
	foot.visible=foot.text!=""
	sheet.queue_redraw()
	overlay.show()
	if page=="howto" and howto_video.stream!=null: howto_video.play()
	planning.hide()
	alarm_banner.hide()
	prompt.hide()
	notice.hide()
	hint_label.hide()
	toast.hide()
	for l: Label in labels.values(): l.hide()
	overhead.queue_redraw()
	_queue_modal()

## Closing scene: the kit goes away and the letterbox comes in (or the other way round).
var _before_cinema: Dictionary = {}
func cinema(on: bool) -> void:
	if on:
		_before_cinema.clear()
		for child: Node in get_children():
			if child is CanvasItem:
				_before_cinema[child] = (child as CanvasItem).visible
				(child as CanvasItem).visible = false
	else:
		for child: Variant in _before_cinema:
			if is_instance_valid(child): (child as CanvasItem).visible = bool(_before_cinema[child])
		_before_cinema.clear()
	cinema_view.visible = on
	cinema_view.open(on)
	if not on:
		cinema_view.black = 0.0
		layout()

func caption(value: String, seconds: float, big: bool = false) -> void:
	cinema_view.show_caption(tr(value), seconds, big)

func fade_black(alpha: float) -> void:
	cinema_view.black = alpha

func flash_white(alpha: float) -> void:
	cinema_view.white = alpha

func in_cinema() -> bool:
	return cinema_view != null and cinema_view.visible

var _won_earned: PackedStringArray = []
## The debrief's words: the level's own, the stamps and the best time on file.
func _won_body() -> String:
	var best: float=float(progress.get_value(best_section,"time",sim.time))
	return "%s\n%s Best time on file %s." % [copy("debrief","Everyone is safe."),"Commended: %s." % ", ".join(_won_earned) if not _won_earned.is_empty() else "No commendations this time.",_clock_text(best)]

## One page of the history notes that follow the debrief.
func show_history(index: int) -> void:
	history_page=index
	show_modal("history")

func _fill_history() -> void:
	var pages: Array=sim.data.get("history",[])
	history_page=clampi(history_page,0,maxi(pages.size()-1,0))
	var entry: Dictionary=pages[history_page] if not pages.is_empty() else {}
	modal_page.text="THE REAL STORY  %d / %d" % [history_page+1,pages.size()]
	modal_title.text=str(entry.get("title",""))
	modal_body.text=str(entry.get("body",""))
	foot.text=str(entry.get("foot",""))
	var next: String=Missions.next_of(Missions.current)
	if history_page+1<pages.size(): second_button.text="NEXT PAGE"
	elif next!="": second_button.text="NEXT OPERATION"
	elif Feedback.due(progress): second_button.text=_questions_word()
	else: second_button.text="MAIN MENU"
	begin_button.text="PLAY AGAIN"

## An operative's name in capitals as the HUD shows it: the data's name (BIGUÁ, with its accent), else the id.
func _name_caps(id: String) -> String:
	for unit: Dictionary in sim.units:
		if str(unit.id)==id: return str(unit.get("name",id)).to_upper()
	return id.to_upper()

## The debrief's way to the questions: the words the menus use.
func _questions_word() -> String:
	return QUESTIONS

func _clock_text(seconds: float) -> String:
	return "%02d:%02d" % [floori(seconds/60.0),int(seconds)%60]

func _checkpoint_name(label: String) -> String:
	var names: Dictionary=sim.data.get("copy",{}).get("checkpoints",{})
	if names.has(label): return str(names[label])
	return str(CHECKPOINT_NAMES.get(label,"saved by hand"))

func _refresh_menu() -> void:
	var mark: Dictionary=sim.checkpoint
	var can_save: bool=sim.can_save_checkpoint()
	(menu_buttons.save as ActionSlot).dimmed=not can_save
	(menu_buttons.load as ActionSlot).dimmed=mark.is_empty()
	(menu_buttons.restart as ActionSlot).text="RESTART MISSION"
	_restart_armed_until=0.0
	var line: String=tr("No checkpoint yet.") if mark.is_empty() else tr("Checkpoint on file: %s, %s on the clock.") % [tr(_checkpoint_name(str(mark.get("label","")))),_clock_text(float(mark.get("time",0.0)))]
	if _menu_note!="": line+="\n"+tr(_menu_note)
	elif not can_save and sim.phase=="playing": line+=tr("\nNo new checkpoint while the post is stirred up.")
	else: line+=tr("\nLoading returns you there with the clock stopped.")
	modal_body.text=line

func _menu_pressed(key: String) -> void:
	match key:
		"save":
			if sim.can_save_checkpoint(): command.emit("save")
			else:
				sim.save_checkpoint()
				_menu_note=str(sim.message)
				_seen_message=sim.message
				_refresh_menu()
				command.emit("deny")
		"load":
			if sim.has_checkpoint(): command.emit("load")
			else: command.emit("deny")
		"howto": show_modal("howto")
		"restart":
			# Two taps, so a slip of the thumb does not throw the mission away.
			var now: float=Time.get_ticks_msec()
			if now<_restart_armed_until: command.emit("restart_now")
			else:
				_restart_armed_until=now+3500
				(menu_buttons.restart as ActionSlot).text="TAP AGAIN TO RESTART"

func _second_pressed() -> void:
	match current_modal:
		"briefing":
			if sim.phase=="playing": show_modal("howto")
			else: command.emit("title")
		"menu":
			# Two taps, so a slip of the thumb does not throw the run away.
			var now: float=Time.get_ticks_msec()
			if now<_leave_armed_until: command.emit("title")
			else:
				_leave_armed_until=now+3500
				second_button.text="TAP AGAIN TO LEAVE"
		"won":
			if sim.data.has("history"): show_history(0)
			elif Missions.next_of(Missions.current)!="": command.emit("mission:"+Missions.next_of(Missions.current))
			else: command.emit("feedback" if Feedback.due(progress) else "title")
		"history":
			if history_page+1<(sim.data.get("history",[]) as Array).size(): show_history(history_page+1)
			elif Missions.next_of(Missions.current)!="": command.emit("mission:"+Missions.next_of(Missions.current))
			else: command.emit("feedback" if Feedback.due(progress) else "title")
		"howto":
			if howto_page>0: show_card(howto_page-1)
			elif _howto_back=="title": command.emit("title")
			else: show_modal(_howto_back)
		"lost": command.emit("restart_now")

## HOW TO PLAY opened from the launch screen: its first BACK and its last button lead back there.
func show_howto_from_title() -> void:
	show_modal("howto")
	_howto_back="title"
	show_card(0)

## The brass button: NEXT through the cards, otherwise begin (or return to) the operation.
func _primary_pressed() -> void:
	if current_modal=="howto" and howto_page<_howto().size()-1: show_card(howto_page+1)
	elif current_modal=="howto" and _howto_back=="title": command.emit("title")
	else: command.emit("begin")

## Gathers the figures and stamps of the run just won.
func _collect_result() -> void:
	var s: Dictionary=sim.stats
	_stats=[[tr("TIME"),_clock_text(float(sim.time))],[tr("KILLS"),str(int(s.kills))],[tr("BOUND"),str(int(s.binds))],[tr("SHOTS"),str(int(s.shots))],[tr("ALARMS"),str(int(s.alarms))],[tr("RELOADS"),str(int(s.checkpoints_loaded))]]
	if bool(sim.get("rescue_on")):
		# a rescue's figures: the time, how many were brought under cover of how many, who was lost, who fell
		var counts: Dictionary=sim.rescue_counts()
		_stats=[[tr("TIME"),_clock_text(float(sim.time))],[tr("SAVED"),"%d/%d" % [int(counts.saved),int(counts.total)]],[tr("LOST"),str(int(counts.lost))],
			[tr("FELL"),str(int(s.get("fallen",0)))],[tr("SQUAD"),"%d/%d" % [sim.units.size()-int(s.get("squad_lost",0)),sim.units.size()]],[tr("RELOADS"),str(int(s.checkpoints_loaded))]]
	_badges=sim.result_badges()
	stats_row.queue_redraw()
	badge_row.queue_redraw()

func _paint_stats(c: Canvas) -> void:
	if _stats.is_empty(): return
	var cell: float=c.size.x/_stats.size()
	c.draw_rect(Rect2(0,6,c.size.x,1),Color(INK,0.55))
	c.draw_rect(Rect2(0,c.size.y-5,c.size.x,1),Color(INK,0.55))
	for i: int in range(_stats.size()):
		var mid: float=roundf(cell*(i+0.5))
		ActionSlot.label(c,ActionSlot.face("stencil",1),_stats[i][1],mid,44,34,INK)
		ActionSlot.label(c,ActionSlot.face("semi",2),_stats[i][0],mid,62,14,Color(INK,0.72))
		if i>0: c.draw_rect(Rect2(roundf(cell*i),16,1,c.size.y-30),Color(INK,0.25))

## One medal: struck from the medals' sheet when it has one of that art, else its symbol in a stamped ring.
func _medal(c: Canvas, art: String, at: Vector2, px: float, tint: Color) -> void:
	if art in ActionSlot.BADGES:
		ActionSlot.badge(c,art,at,px,tint)
		return
	c.draw_arc(at,px*0.46,0.0,TAU,40,Color(tint,tint.a*0.9),3.0,true)
	c.draw_arc(at,px*0.38,0.0,TAU,40,Color(tint,tint.a*0.6),1.5,true)
	ActionSlot.glyph(c,art,at,px*0.5,tint)

## Five stamps: inked if earned on this run, faint if earned on an earlier one, an empty ring if never.
func _paint_badges(c: Canvas) -> void:
	if _badges.is_empty(): return
	var cell: float=c.size.x/_badges.size()
	var stamp: float=minf(84.0,cell-18.0)
	for i: int in range(_badges.size()):
		var entry: Dictionary=_badges[i]
		var id: String=entry.id
		var at:=Vector2(roundf(cell*(i+0.5)),stamp*0.5+6)
		var earned: bool=bool(entry.earned)
		var before: bool=not badge_record(id).is_empty()
		if earned:
			c.draw_set_transform(at,[-0.14,0.09,-0.05,0.12,-0.1][i%5],Vector2.ONE)
			_medal(c,str(entry.get("art",id)),Vector2.ZERO,stamp,Color(0.2,0.3,0.17,0.9))
			c.draw_set_transform(Vector2.ZERO)
		elif before:
			_medal(c,str(entry.get("art",id)),at,stamp,Color(INK,0.2))
		else:
			for k: int in range(18):
				c.draw_arc(at,stamp*0.5-4,k*TAU/18.0,(k+0.55)*TAU/18.0,4,Color(INK,0.34),1.5,true)
		var tone:=Color(INK,0.95 if earned else 0.5)
		# the name and the line under it keep to their own column: smaller, then on two or three lines (a phone,
		# a longer language)
		var room: float=cell-6.0
		var name_face: Font=ActionSlot.face("semi",1)
		var title: String=caps(tr(str(entry.label)))
		var name_px: int=17
		while name_px>12 and name_face.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,name_px).x>room: name_px-=1
		var names: PackedStringArray=_wrap(title,name_face,name_px,room,2)
		var y: float=stamp+28.0-(name_px+1)*(names.size()-1)*0.5
		for part: String in names:
			ActionSlot.label(c,name_face,part,at.x,y,name_px,tone)
			y+=name_px+1
		var line: String=tr(str(entry.text))
		if earned and id in _new_badges: line=tr("First time: on file")
		elif not earned and before: line=tr("Earned before")
		var style: Font=ActionSlot.face("medium")
		var px: int=15 if style.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x<=room else 13
		var lines: PackedStringArray=_wrap(line,style,px,room,3)
		y+=16.0-name_px
		for part: String in lines:
			ActionSlot.label(c,style,part,at.x,y,px,Color(INK,0.74 if earned else 0.5))
			y+=px

# --- messages --------------------------------------------------------------------------------------------
## Shows a line in the notice strip (the simulation's own messages arrive there by themselves).
func notify(value: String, seconds: float = 4.5) -> void:
	# The simulation's line of the same moment is superseded, not queued.
	_seen_message=sim.message
	_show_notice(value,seconds)

func _show_notice(value: String, seconds: float) -> void:
	notice.text=value
	_notice_until=Time.get_ticks_msec()+seconds*1000.0
	notice.visible=not overlay.visible and not value.is_empty()
	_place_lines()

## A one-time teaching line; remembered on disk so it never nags.
func hint(id: String) -> void:
	if not hints_enabled or not hints.has(id) or bool(progress.get_value("hints",id,false)): return
	progress.set_value("hints",id,true)
	_save_progress()
	hint_label.text=hints[id]
	_hint_until=Time.get_ticks_msec()+HINT_SECONDS*1000.0
	hint_label.visible=not overlay.visible
	_place_lines()

## The checkpoint tag hangs under the recon map; upright, where the banners live there, under the objectives.
func _place_toast() -> void:
	if _upright: toast.position=Vector2(objective_block.position.x,objective_block.position.y+objective_block.size.y+8)
	else: toast.position=Vector2(minimap.position.x+minimap.size.x-toast.size.x,minimap.position.y+minimap.size.y+8)

## Small tag (checkpoints).
func show_toast(value: String) -> void:
	var shown: String=tr(value)
	var f: Font=ActionSlot.face("semi",2)
	var wide: float=ceilf(f.get_string_size(shown,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x)+30
	# the tag hangs under the map (upright, under the objectives, left of the map): one too long for that (often in
	# Spanish) goes on two lines
	var room: float=(minimap.position.x-8.0-objective_block.position.x) if _upright else minimap.size.x
	var tall: float=30.0
	if wide>room and shown.contains("  ·  "):
		shown=shown.replace("  ·  ","\n")
		wide=0.0
		for part: String in shown.split("\n"): wide=maxf(wide,ceilf(f.get_string_size(part,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x)+30)
		tall=52.0
	# the text first: a Label is never made smaller than what its old text needed
	toast.text=shown
	toast.size=Vector2(wide,tall)
	_place_toast()
	_toast_until=Time.get_ticks_msec()+3200.0
	toast.visible=not overlay.visible

## Simulation events forwarded by main.gd: toasts and one-time hints.
func on_sim_event(event: Dictionary) -> void:
	match str(event.type):
		"checkpoint":
			if str(event.get("action",""))=="save" and str(event.get("label",""))!="start":
				show_toast("CHECKPOINT  ·  %s" % _checkpoint_name(str(event.get("label",""))).to_upper())
		"takedown": hint("body")
		"shot":
			# a guard shot down leaves a body to hide; a cascarudo hit makes off (the Plaza de Mayo has no bodies, no bushes)
			var hit: String=str(event.get("hit_id",""))
			if hit!="" and not bool(sim.guard_by_id(hit).get("creature",false)): hint("body")
		"trap_sprung": hint("stunned")
		"alarm_start": hint("alarm")
		"rescued": hint("informant")
		# the fuses burning: what comes next (a mission's own line, if it has one)
		"fuse_lit": hint("search")

# --- the action bar ------------------------------------------------------------------------------------------
func _action(list: Array[Dictionary], id: String) -> Dictionary:
	for entry: Dictionary in list:
		if entry.id==id: return entry
	return NOTHING

func _unit_index(id: String) -> int:
	for i: int in range(sim.units.size()):
		if sim.units[i].id==id: return i
	return -1

## The simulation's action behind a bar slot, read fresh (main.gd calls this when a slot is tapped).
## For the context slot it is the HUD's present offer, which carries its own target.
func entry_for(key: String) -> Dictionary:
	if key=="context":
		_refresh_context(sim.selected(),sim.available_actions(),sim.interactables())
		return context
	return _bar_entries(sim.available_actions()).get(key,NOTHING)

## The simulation's action on each plate of the bar (SLOT_ACTIONS keys; {} for none): each plate takes the first of its
## actions the operative has, one plate to an action; a plate left empty takes his first SPARE_ACTIONS skill still off
## the bar.
func _bar_entries(list: Array[Dictionary]) -> Dictionary:
	var bar: Dictionary={}
	var placed: Array[String]=[]
	for key: String in SLOT_ACTIONS:
		var entry: Dictionary=NOTHING
		for e: Dictionary in list:
			if e.id in SLOT_ACTIONS[key] and not str(e.id) in placed:
				entry=e
				break
		if not entry.is_empty(): placed.append(str(entry.id))
		bar[key]=entry
	for key: String in SLOT_ACTIONS:
		if not (bar[key] as Dictionary).is_empty(): continue
		for id: String in SPARE_ACTIONS:
			var spare: Dictionary=_action(list,id)
			if not spare.is_empty() and not id in placed:
				bar[key]=spare
				placed.append(id)
				break
	return bar

func _icon_for(id: String, unit: Dictionary) -> String:
	match id:
		"stance": return "crouch" if unit.stance=="sneak" else "walk"
		"takedown":
			if unit.melee.has("icon"): return str(unit.melee.icon)
			if float(unit.melee.get("stun",0.0))>0.0: return "cosh"
			return "knife" if bool(unit.melee.get("lethal",false)) else "bind"
		"distract":
			if unit.has("throw"): return str(unit.throw.get("icon","bottle"))
		"shoot":
			if unit.gun.has("icon"): return str(unit.gun.icon)
			return "revolver" if bool(unit.gun.get("loud",false)) else "pistol"
		"call": return str(unit.get("call",{}).get("icon","talk"))
		"rig":
			for passage: Dictionary in sim.passages():
				if str(unit.id) in passage.get("by",[]): return str(passage.get("icon","rope"))
		"plant":
			# the next site he can still do, drawn as its marker is (Gunnerside's gun left on the floor: the gun)
			var kind: String=""
			for site: Dictionary in sim.charge_sites():
				if sim.can_plant(unit,site) and (kind=="" or not sim.planted.has(str(site.id))):
					kind=str(site.get("kind","charge"))
					if not sim.planted.has(str(site.id)): break
			if kind!="": return str(thing_icons.get(kind,action_icons.get(id,"")))
		"extract":
			# a local goes home his own way: the gate, not the boat
			if unit.has("exit"): return thing_icons.get(str(unit.exit.get("type","")),action_icons.get(id,""))
	return action_icons.get(id,"")

func _fill_slot(key: String, entry: Dictionary, unit: Dictionary, locked: bool) -> void:
	var b: ActionSlot=slots[key]
	b.disabled=locked
	if entry.is_empty():
		slot_ids[key]=""
		b.symbol=""
		b.text=""
		b.dimmed=true
		b.armed=false
		b.active=false
		b.count_max=0
		b.progress=-1.0
		return
	var id: String=entry.id
	slot_ids[key]=id
	var live: bool=armed==id and not locked
	b.symbol=_icon_for(id,unit)
	b.armed=live
	if live: b.text="CANCEL"
	elif id=="stance": b.text="CROUCHED" if unit.stance=="sneak" else "STANDING"
	else: b.text=caps(str(entry.label))
	b.dimmed=not bool(entry.enabled)
	b.active=bool(entry.active)
	b.count=int(entry.count)
	b.count_max=_count_max(id,unit) if int(entry.count)>=0 else 0
	var wait: float=float(entry.cooldown)
	var total: float=float(entry.cooldown_total)
	if wait>0.0 and total>0.0:
		b.progress=1.0-wait/total
		b.wait=ceili(wait) if total>=2.0 else -1
	else:
		b.progress=-1.0
		b.wait=-1

## How many pips a slot's count is drawn out of: rounds, tripwires; in a rescue the people he can lead, the calls
## he has, the cloths there are.
func _count_max(id: String, unit: Dictionary) -> int:
	match id:
		"shoot": return int(unit.gun.get("ammo",0))
		"guide": return int(sim.lead_of(unit))
		"call": return int(unit.get("call",{}).get("count",-1))
		"canvas": return sim.canvases().size()
		"take": return sim.gear().size()
	return int(unit.trap_kit)

func _offer(id: String, label: String, icon: String, enabled: bool, reason: String, target: Variant, pin: String) -> void:
	context.id=id
	context.label=label
	context.icon=icon
	context.enabled=enabled
	context.reason=reason
	context.target=target
	context.pin=pin

## Picks the one context action worth a slot right now: what is on his shoulders, else the nearest
## thing he can work on, else the next objective. All of it comes from the simulation's two lists.
func _refresh_context(unit: Dictionary, list: Array[Dictionary], things: Array[Dictionary]) -> void:
	var here: Vector2=sim.position_of(unit)
	context.active=false
	if str(unit.carrying)!="":
		var drop: Dictionary=_action(list,"drop")
		var ok: bool=not drop.is_empty() and bool(drop.enabled)
		var why: String=str(drop.get("reason",""))
		context.active=bool(drop.get("active",false))
		if sim.in_bush(here):
			_offer("drop","HIDE BODY","hide",ok,why,null,"")
			return
		var best: Dictionary={}
		var best_d: float=HIDE_NEAR
		for thing: Dictionary in things:
			if thing.type!="bush": continue
			var d: float=here.distance_to(Vector2(float(thing.x),float(thing.y)))-float(thing.radius)
			if d<best_d:
				best=thing
				best_d=d
		if bool(sim.guard_by_id(str(unit.carrying)).get("person",false)): _offer("drop","SET DOWN","drop",ok,why,null,"")
		elif best.is_empty(): _offer("drop","DROP BODY","drop",ok,why,null,"")
		else: _offer("drop","HIDE BODY","hide",ok,why,best.target,str(best.id))
		return
	var near: Dictionary={}
	var near_d: float=CONTEXT_NEAR
	for thing: Dictionary in things:
		if not bool(thing.enabled) or thing.type=="bush" or thing.type=="trap": continue
		if thing.type=="body" and not _body_wants_moving(str(thing.target)): continue
		var d: float=maxf(0.0,here.distance_to(Vector2(float(thing.x),float(thing.y)))-float(thing.radius))
		# beside a man who is down, his uniform comes before carrying him off
		if thing.type=="uniform": d-=1.0
		if d<near_d:
			near=thing
			near_d=d
	if not near.is_empty():
		var order: String=near.order
		_offer(order,caps(str(near.label)),thing_icons.get(near.type,""),true,"",near.target,str(near.id))
		context.active=bool(_action(list,order).get("active",false))
		return
	# Nothing in reach: the next objective, if this operative can do it, else carrying.
	var want: String=""
	for objective: Dictionary in sim.objectives:
		if not bool(objective.done) and not bool(objective.get("optional",false)):
			if sim.objective_progress(str(objective.id))[1]>0:
				# Charges: this operative's job only if he carries the charges for it; else the next objective.
				var mine: bool=false
				for site: Dictionary in sim.charge_sites():
					if str(site.get("objective",""))==str(objective.id) and not sim.planted.has(str(site.id)) and sim.can_plant(unit,site): mine=true
				if not mine: continue
				want="plant"
				break
			want=OBJECTIVE_ACTIONS.get(objective.id,"")
			break
	var entry: Dictionary=_action(list,want) if want!="" else NOTHING
	if entry.is_empty() or (want=="rescue" and not sim.door_open):
		entry=_action(list,"pickup")
		var body: String=_nearest_body(here)
		if entry.is_empty(): _offer("","","",false,"",null,"")
		else: _offer("pickup",caps(str(entry.label)),"carry",bool(entry.enabled) and body!="",str(entry.reason) if str(entry.reason)!="" else "Nobody to carry.",body,body)
	else:
		_offer(want,caps(str(entry.label)),_icon_for(want,unit),bool(entry.enabled),str(entry.reason),null,"")
	context.active=bool(entry.get("active",false))

## A body still lying where it can be found (not hidden, not the stunned man with his own timer).
func _body_wants_moving(id: String) -> bool:
	var guard: Dictionary=sim.guard_by_id(id)
	return not guard.is_empty() and not bool(guard.hidden)

func _nearest_body(here: Vector2) -> String:
	var best: String=""
	var best_d: float=INF
	for guard: Dictionary in sim.guards:
		if not guard.state in sim.BODY_STATES or str(guard.carried_by)!="" or float(guard.elevation)>0.0 or bool(guard.hidden): continue
		var d: float=here.distance_squared_to(sim.position_of(guard))
		if d<best_d:
			best=guard.id
			best_d=d
	return best

# --- refresh (about 12 times a second) ----------------------------------------------------------------------------
func refresh(_unused: Variant = null) -> void:
	if in_cinema(): return
	var playing: bool=sim.phase=="playing"
	var locked: bool=not playing or overlay.visible
	var unit: Dictionary=sim.selected()
	var list: Array[Dictionary]=sim.available_actions()
	_pins=sim.interactables()
	var now: float=Time.get_ticks_msec()
	var rescue: bool=bool(sim.get("rescue_on"))
	if playing: _result_saved=false
	# ID photos and their tags.
	_orders_queued=0
	for u: Dictionary in sim.units:
		var b: ActionSlot=portrait_buttons[u.id]
		b.selected=u.id==sim.selected_id
		b.disabled=locked
		b.health=0 if (not bool(u.alive) or bool(u.get("fallen",false))) else clampi(ceili(float(u.hp)/34.0),1,3)
		# sealed in his suit the snow does not touch him: his health, not the cold
		b.cold=float(u.get("exposure",0.0)) if rescue and not bool(u.get("suit",false)) else -1.0
		# not here yet: his photo dark, a band saying so, and no tapping him
		var away: bool=bool(u.get("away",false))
		b.band="ON HIS WAY" if away else ""
		if away: b.disabled=true
		if not u.order.is_empty(): _orders_queued+=1
		_refresh_tag(u)
	# The bar: a plate this operative has nothing for is left out and the rest close up.
	var bar: Dictionary=_bar_entries(list)
	var plates: Array[String]=[]
	for key: String in SLOT_ORDER:
		if key in bar:
			_fill_slot(key,bar[key],unit,locked)
			if (bar[key] as Dictionary).is_empty(): continue
		plates.append(key)
	if plates!=_bar_shown:
		_bar_shown=plates
		_place_bar()
	_refresh_context(unit,list,_pins)
	var c: ActionSlot=slots.context
	c.disabled=locked
	c.symbol=context.icon
	c.text=context.label
	c.dimmed=not bool(context.enabled)
	c.active=bool(context.active)
	slot_ids.context=context.id
	var p: ActionSlot=slots.plan
	p.disabled=locked
	p.symbol="play" if sim.paused else "pause"
	p.text="EXECUTE" if sim.paused else "PLAN"
	p.armed=sim.paused and not locked
	_refresh_marked(unit)
	_refresh_objectives()
	# Clock and detection.
	var suspicion: float=sim.max_suspicion()
	var alarmed: bool=bool(sim.alarm.active)
	var second: int=int(sim.time)
	if second!=_shown_second:
		_shown_second=second
		clock.text="%02d:%02d" % [floori(second/60.0),second%60]
	var shown: int=1000 if alarmed else (int(suspicion*100) if suspicion>0.02 else -1)
	if rescue:
		# the snow in place of the guards: how hard it falls (the readout's bar), the next wave or the lull
		suspicion=clampf(float(sim.snow_intensity())/3.2,0.0,1.0)
		var level: String=str(sim.snow_level())
		var wave_in: float=float(sim.next_wave())
		shown=100000+int(sim.rescue_counts().saved)*1000+(1 if level=="wave" else (2 if level=="lull" else 3))*100+(mini(99,ceili(wave_in)) if level!="wave" and wave_in>=0.0 else 0)
	if shown!=_shown_status:
		_shown_status=shown
		if rescue: status.text=_snow_status()
		else: status.text="ALARM" if alarmed else ("DETECTION %d%%" % shown if shown>=0 else "UNDETECTED")
	readout.level=suspicion
	readout.alarm=alarmed
	var tone: Color=MUTED if (suspicion<=0.02 and not alarmed) else readout.tone().lightened(0.12)
	if status.get_theme_color("font_color")!=tone: status.add_theme_color_override("font_color",tone)
	# Banners.
	var live: bool=playing and not overlay.visible
	if alarmed: _refresh_alarm()
	_place_banners()
	if planning.visible and _orders_queued!=_shown_queued:
		_shown_queued=_orders_queued
		planning.queue_redraw()
	var mood: int=(4 if armed=="shoot" else 0)+(2 if alarmed else 0)+(1 if sim.paused else 0) if live else 0
	if mood!=_frame_state:
		_frame_state=mood
		frame.queue_redraw()
	# Lines above the bar.
	if prompt.visible: _refresh_prompt(unit)
	if _seen_message!=sim.message:
		_seen_message=sim.message
		_show_notice(_seen_message,NOTICE_SECONDS)
	var show_notice: bool=now<_notice_until and not overlay.visible and not notice.text.is_empty()
	var show_hint: bool=now<_hint_until and not overlay.visible
	if show_notice!=notice.visible or show_hint!=hint_label.visible:
		notice.visible=show_notice
		hint_label.visible=show_hint
		_place_lines()
	toast.visible=now<_toast_until and not overlay.visible
	if overlay.visible and current_modal=="menu" and _restart_armed_until>0.0 and now>_restart_armed_until: _refresh_menu()
	if live and hints_enabled: _watch_for_hints()
	_refresh_asset_tag()
	_track_labels()

## Guards the armed action could be used on right now (drawn with brackets; counted in the prompt).
func _refresh_marked(unit: Dictionary) -> void:
	_marked.clear()
	if armed!="shoot" and armed!="takedown": return
	var here: Vector2=sim.position_of(unit)
	var reach: float=float(unit.gun.get("range",0.0)) if unit.has("gun") else 0.0
	for guard: Dictionary in sim.guards:
		if guard.state in OUT_STATES or str(guard.carried_by)!="": continue
		if bool(guard.get("civilian",false)) or str(guard.state) in ["waiting","away"]: continue
		if armed=="shoot":
			if here.distance_to(sim.position_of(guard))<=reach and sim.sight_clear_for(guard,here): _marked.append(str(guard.id))
		elif not bool(guard.melee_immune): _marked.append(str(guard.id))

func _refresh_tag(u: Dictionary) -> void:
	var id: String=u.id
	var verb: String=""
	var object: String=""
	var order: Dictionary=u.order
	if not bool(u.alive): verb=""
	elif bool(u.get("fallen",false)): verb="DOWN"
	elif not order.is_empty():
		var type: String=order.type
		match type:
			"takedown":
				verb=caps(str(u.melee.get("label","Takedown")))
				object=_guard_name(str(order.get("target","")))
			"shoot":
				verb="SHOOT"
				object=_guard_name(str(order.get("target","")))
			"drop":
				# a rescue's fallen, carried in: set down (under cover), not a body dropped
				if bool(sim.guard_by_id(str(u.carrying)).get("person",false)): verb="SET DOWN"
				else: verb="HIDE BODY" if sim.in_bush(Vector2(float(order.x),float(order.y))) else "DROP BODY"
			"rescue": verb="ESCORT" if bool(sim.prisoner.freed) else "RESCUE"
			"chat", "talk":
				verb=order_names.get(type,"SMOKE")
				object=_guard_name(str(order.get("target","")))
			"rig":
				# a rope, a window, a grille, a lock: each passage names its own work
				var passage: Dictionary=sim.passage_by_id(str(order.get("target","")))
				verb=caps(str(passage.get("verb",""))) if passage.has("verb") else order_names.get(type,"RIG ROPE")
			"plant":
				# a charge is set; evidence (the gun left on the floor) is put down, under its own label
				var site: Dictionary=sim.charge_site(str(order.get("target","")))
				verb=caps(str(site.get("label","Leave"))) if str(site.get("kind",""))=="evidence" else order_names.get(type,"SET CHARGE")
			_: verb=order_names.get(type,caps(type))
	elif str(u.carrying)!="": verb="CARRYING"
	elif bool(sim.get("rescue_on")) and not sim.followers_of(id).is_empty():
		verb="LEADING"
		object=str(sim.followers_of(id).size())
	elif bool(u.hidden): verb="IN COVER"
	elif u.has("cover") and u.stance=="walk":
		# a docker at work, a man in a guard's uniform, or a man where he has no business
		if bool(u.get("covered",false)): verb="IN UNIFORM" if bool(u.cover.get("uniform",false)) else str(u.cover.get("tag","DOCKER"))
		else: verb="MARKED" if bool(u.get("blown",false)) else "OUT OF PLACE"
	elif sim.paused and sim.phase=="playing": verb="NO ORDER"
	var live: bool=not order.is_empty()
	var tag: Canvas=tags[id]
	tag.visible=verb!="" and sim.phase=="playing" and not overlay.visible
	verb=tr(verb)
	object=tr(object)
	if verb==_tag_text[id] and object==_tag_object[id] and live==_tag_live[id]: return
	_tag_text[id]=verb
	_tag_object[id]=object
	_tag_live[id]=live
	tag.queue_redraw()

## The one being got out, in the mission's words (data prisoner.tag / word): INFORMANT at Breakwater, PASSENGER at
## La Boca. `line` is one of ASSET_TAGS (or "" for the bare name), its INFORMANT swapped for the mission's tag.
func _asset_tag(line: String) -> String:
	var tag: String=str(sim.data.get("prisoner",{}).get("tag","INFORMANT"))
	if line=="": return tag
	if line=="ABOARD" and sim.data.get("prisoner",{}).has("safe"): return str(sim.data.prisoner.safe).to_upper()
	return line.replace("INFORMANT",tag) if line.begins_with("INFORMANT") else line

func _asset_word() -> String:
	return str(sim.data.get("prisoner",{}).get("word","informant"))

func _guard_name(id: String) -> String:
	var guard: Dictionary=sim.guard_by_id(id)
	if guard.has("title"): return str(guard.title)
	var look: String=str(guard.get("look","")).rstrip("0123456789")
	if LOOK_NAMES.has(look): return LOOK_NAMES[look]
	return GUARD_NAMES.get(guard.get("kind",""),"GUARD")

func _paint_tag(c: Canvas, id: String) -> void:
	var verb: String=_tag_text[id]
	var object: String=_tag_object[id]
	var live: bool=_tag_live[id]
	ActionSlot.nine(c,ActionSlot.TexStrip,Rect2(Vector2.ZERO,c.size),24.0,8.0)
	if live: c.draw_rect(Rect2(3,1,c.size.x-6,2),BRASS)
	var f: Font=ActionSlot.face("semi",1)
	var tone: Color=BRASS if live else (IVORY if verb!=tr("NO ORDER") else DIM)
	var px: int=15
	if object=="":
		ActionSlot.label(c,f,verb,c.size.x*0.5,c.size.y-7,px,tone)
		return
	# "KNIFE → SENTRY": the arrow is drawn, the faces have none.
	var a: float=f.get_string_size(verb,HORIZONTAL_ALIGNMENT_LEFT,-1,px).x
	var b: float=f.get_string_size(object,HORIZONTAL_ALIGNMENT_LEFT,-1,px).x
	if a+b+20>c.size.x-8:
		px=13
		a=f.get_string_size(verb,HORIZONTAL_ALIGNMENT_LEFT,-1,px).x
		b=f.get_string_size(object,HORIZONTAL_ALIGNMENT_LEFT,-1,px).x
	var x: float=roundf((c.size.x-(a+b+20))*0.5)
	var y: float=c.size.y-7
	c.draw_string(f,Vector2(x,y),verb,HORIZONTAL_ALIGNMENT_LEFT,-1,px,tone)
	var mid:=Vector2(x+a+10,y-5)
	c.draw_line(mid+Vector2(-6,0),mid+Vector2(5,0),tone,1.5,true)
	c.draw_line(mid+Vector2(5,0),mid+Vector2(1,-3.5),tone,1.5,true)
	c.draw_line(mid+Vector2(5,0),mid+Vector2(1,3.5),tone,1.5,true)
	c.draw_string(f,Vector2(x+a+20,y),object,HORIZONTAL_ALIGNMENT_LEFT,-1,px,IVORY)

# --- objectives ---------------------------------------------------------------------------------------------------
func _refresh_objectives() -> void:
	var asset: Dictionary=sim.prisoner
	var key: int=0
	for objective: Dictionary in sim.objectives: key=key*2+(1 if bool(objective.done) else 0)
	var state: int=0
	if bool(asset.freed): state=3 if bool(asset.aboard) else (2 if bool(asset.hidden) else 1)
	key=key*8+state
	key=key*4+clampi(ceili(float(asset.hp)/34.0),0,3)
	key=key*4+(_unit_index(str(asset.follow_id))+1)
	var chosen: Dictionary=sim.selected()
	key=key*2+(1 if bool(chosen.get("tools",false)) else 0)
	key=key*64+sim.planted.size()*4+_unit_index(str(chosen.get("id","")))+1
	if bool(sim.get("rescue_on")): key=key*128+int(sim.rescue_counts().saved)
	if key==_obj_key: return
	_obj_key=key
	_obj_title=tr("Mission complete")
	_obj_how=""
	_obj_lines.clear()
	_obj_tones.clear()
	_obj_marks.clear()
	_obj_states.clear()
	var found: bool=false
	# Where two jobs run side by side (charges carried by different operatives), the selected operative's own
	# job is the one in the title; the other shows as a line below with its count.
	var lead_id: String=""
	for objective: Dictionary in sim.objectives:
		if bool(objective.done) or bool(objective.get("optional",false)): continue
		if lead_id=="": lead_id=str(objective.id)
		if sim.objective_progress(str(objective.id))[1]==0: break
		var mine: bool=false
		for site: Dictionary in sim.charge_sites():
			if str(site.get("objective",""))==str(objective.id) and not sim.planted.has(str(site.id)) and sim.can_plant(chosen,site): mine=true
		if mine:
			lead_id=str(objective.id)
			break
	var side_lines: Array[String]=[]
	for objective: Dictionary in sim.objectives:
		var done: bool=bool(objective.done)
		var count: Array[int]=sim.objective_progress(str(objective.id))
		var tally: String="  %d/%d" % [count[0],count[1]] if count[1]>0 else ""
		if bool(objective.get("optional",false)):
			_obj_lines.append("%s  ·  %s" % [tr("done") if done else tr("optional"),_lower_first(str(objective.text))])
			_obj_tones.append(BRASS.lerp(IVORY,0.25) if done else MUTED)
			_obj_marks.append(2 if done else 1)
			continue
		if not done and not found and str(objective.id)==lead_id:
			found=true
			_obj_title=str(objective.text)+tally
			_obj_how=tr(_objective_how(str(objective.get("id","")),chosen))
			_obj_states.append(1)
		else:
			_obj_states.append(2 if done else 0)
			if not done and count[1]>0: side_lines.append("%s  ·  %s%s" % [tr("also"),_lower_first(str(objective.text)),tally])
	for i: int in range(side_lines.size()):
		_obj_lines.insert(i,side_lines[i])
		_obj_tones.insert(i,IVORY.lerp(MUTED,0.35))
		_obj_marks.insert(i,0)
	if state>0:
		var hp: int=int(asset.hp)
		var hurt: String="" if hp>67 else ("  ·  "+(tr("hurt") if hp>34 else tr("badly hurt")))
		match state:
			3: _obj_lines.append("%s  ·  %s" % [tr(_asset_word()),tr(str(sim.data.get("prisoner",{}).get("safe","in the boat")))])
			2: _obj_lines.append("%s  ·  %s" % [tr(_asset_word()),tr("in cover")]+hurt)
			_:
				var escort: Dictionary=sim.unit_by_id(str(asset.follow_id))
				_obj_lines.append("%s  ·  %s%s" % [tr(_asset_word()),tr("with %s, in the open") % str(escort.get("name",tr("nobody"))),hurt])
		_obj_tones.append(RED.lightened(0.25) if (hp<=34 and state!=3) else (IVORY if state==1 else KHAKI.lightened(0.2)))
		_obj_marks.append(0)
	var widest: float=ActionSlot.face("semi").get_string_size(_obj_title,HORIZONTAL_ALIGNMENT_LEFT,-1,26).x
	# The how-to line breaks once (at a word) rather than run past the block.
	_obj_how_lines=_wrap(_obj_how,ActionSlot.face("medium"),18,_block_limit-26.0,2) if _obj_how!="" else PackedStringArray()
	for line: String in _obj_how_lines: widest=maxf(widest,ActionSlot.face("medium").get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x)
	for line: String in _obj_lines: widest=maxf(widest,ActionSlot.face("medium").get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,19).x+16)
	var lines: int=_obj_lines.size()+_obj_how_lines.size()
	objective_block.size=Vector2(clampf(ceilf(widest)+32,264.0,_block_limit),58.0+22.0*lines+(6.0 if lines>0 else 0.0))
	objective_block.queue_redraw()
	# upright, the checkpoint tag hangs under the block: it follows when the block grows or shrinks
	if _upright: _place_toast()

## The current step in a few words: for the locked door it depends on who is selected (who has the tools).
func _objective_how(id: String, chosen: Dictionary) -> String:
	if id=="cell" and not objective_how.has("cell"): return "Tap the door to open it" if bool(chosen.get("tools",false)) else "Another of yours has the keys: switch to him"
	var how: Variant=objective_how.get(id,"")
	if how is Dictionary:
		# Per operative: {"wren": "...", "rook": "...", "": fallback}
		return str(how.get(str(chosen.get("id","")),how.get("","")))
	return str(how)

## A rubber stamp in the player's language (assets/ui/<name>_<lang>.png), the English one otherwise.
func _stamp(english: Texture2D, stamp_name: String) -> Texture2D:
	var path: String="res://assets/ui/%s_%s.png" % [stamp_name,Lang.current]
	if Lang.current!="en" and ResourceLoader.exists(path): return load(path)
	return english

## "Mine the Dresden" -> "mine the Dresden": a sentence run on after a dot, names and U-boats left alone.
static func _lower_first(line_text: String) -> String:
	return line_text.left(1).to_lower()+line_text.substr(1)

## `text` broken at spaces into lines no wider than `width` (at most `most` lines; the last takes the rest).
static func _wrap(line_text: String, font: Font, font_size: int, width: float, most: int) -> PackedStringArray:
	var out: PackedStringArray=[]
	var line: String=""
	for word: String in line_text.split(" ",false):
		var trial: String=word if line=="" else line+" "+word
		if line!="" and out.size()<most-1 and font.get_string_size(trial,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>width:
			out.append(line)
			line=word
		else: line=trial
	if line!="": out.append(line)
	return out

func _paint_objectives(c: Canvas) -> void:
	ActionSlot.nine(c,ActionSlot.TexStrip,Rect2(Vector2.ZERO,c.size),24.0,8.0)
	c.draw_rect(Rect2(1,3,3,c.size.y-6),BRASS)
	c.draw_string(ActionSlot.face("semi",2),Vector2(16,20),tr("OBJECTIVE"),HORIZONTAL_ALIGNMENT_LEFT,-1,15,KHAKI)
	# One box per step of the mission: ticked, current, still to come.
	var x: float=104.0
	for state: int in _obj_states:
		var box:=Rect2(x,10,10,10)
		if state==2:
			c.draw_rect(box,BRASS)
			c.draw_line(box.position+Vector2(2,5),box.position+Vector2(4.5,7.5),INK,1.5,true)
			c.draw_line(box.position+Vector2(4.5,7.5),box.position+Vector2(8,2.5),INK,1.5,true)
		else: c.draw_rect(box.grow(-0.75),IVORY if state==1 else Color(MUTED,0.55),false,1.5)
		x+=16.0
	c.draw_string(ActionSlot.face("semi"),Vector2(16,48),_obj_title,HORIZONTAL_ALIGNMENT_LEFT,c.size.x-28,26,IVORY)
	var y: float=71.0
	for line: String in _obj_how_lines:
		c.draw_string(ActionSlot.face("medium"),Vector2(16,y),line,HORIZONTAL_ALIGNMENT_LEFT,c.size.x-26,18,BRASS.lerp(IVORY,0.35))
		y+=22.0
	for i: int in range(_obj_lines.size()):
		var lead: float=16.0
		var mark: int=_obj_marks[i]
		if mark>0:
			# Diamond: an optional task, filled once it is done.
			var mid:=Vector2(21,y-6)
			var diamond:=PackedVector2Array([mid+Vector2(0,-5),mid+Vector2(5,0),mid+Vector2(0,5),mid+Vector2(-5,0),mid+Vector2(0,-5)])
			if mark==2: c.draw_colored_polygon(diamond,BRASS)
			else: c.draw_polyline(diamond,_obj_tones[i],1.25,true)
			lead=32.0
		c.draw_string(ActionSlot.face("medium"),Vector2(lead,y),_obj_lines[i],HORIZONTAL_ALIGNMENT_LEFT,c.size.x-lead-10,19,_obj_tones[i])
		y+=22.0

# --- banners --------------------------------------------------------------------------------------------------------
func _paint_planning(c: Canvas) -> void:
	ActionSlot.nine(c,ActionSlot.TexStrip,Rect2(Vector2.ZERO,c.size),24.0,8.0)
	c.draw_rect(Rect2(3,1,c.size.x-6,3),BRASS)
	ActionSlot.glyph(c,"pause",Vector2(34,c.size.y*0.5+1),34,BRASS)
	var mid: float=c.size.x*0.5+14
	ActionSlot.label(c,ActionSlot.face("semi",3),tr("COMMAND MODE"),mid,30,26,BRASS)
	ActionSlot.label(c,ActionSlot.face("medium"),tr(COMMAND_HINTS[clampi(_orders_queued,0,2)]),mid,53,19,IVORY)

func _refresh_alarm() -> void:
	var alarm: Dictionary=sim.alarm
	var left: float=float(alarm.time_left)
	var total: float=maxf(0.1,float(alarm.duration))
	var second: int=ceili(left)
	var pending: int=int(alarm.reinforce_pending)
	var held: bool=left>=total-0.01
	var wait: int=ceili(float(alarm.reinforce_in)) if pending>0 else 0
	var key: int=(wait*4+(2 if held else 0)+(1 if pending>0 else 0))*8+ALARM_REASONS.find(str(alarm.reason))+1
	if key!=_alarm_key:
		_alarm_key=key
		if pending>0: _alarm_line=tr("reinforcements in %d s") % wait
		elif held: _alarm_line=tr("they have you in sight: break the line")
		else:
			match str(alarm.reason):
				"body": _alarm_line=tr("a body was found. They are searching.")
				"gunshot": _alarm_line=tr("that shot was heard. Every guard is out.")
				_: _alarm_line=tr("they lost you. Stay low until it passes.")
		alarm_banner.queue_redraw()
	var fill: float=roundf(left/total*100.0)/100.0
	if second!=_alarm_second or fill!=_alarm_fill:
		_alarm_second=second
		_alarm_fill=fill
		alarm_banner.queue_redraw()

func _paint_alarm(c: Canvas) -> void:
	ActionSlot.nine(c,ActionSlot.TexStrip,Rect2(Vector2.ZERO,c.size),24.0,8.0,Color(1.0,0.86,0.84))
	c.draw_rect(Rect2(3,1,c.size.x-6,3),RED)
	c.draw_string(ActionSlot.face("stencil",2),Vector2(18,32),tr("ALARM"),HORIZONTAL_ALIGNMENT_LEFT,-1,32,RED.lightened(0.18))
	var f: Font=ActionSlot.face("semi",1)
	var figure: String=ActionSlot.number(_alarm_second)
	var w: float=f.get_string_size(figure,HORIZONTAL_ALIGNMENT_LEFT,-1,30).x
	c.draw_string(f,Vector2(c.size.x-30-w,31),figure,HORIZONTAL_ALIGNMENT_LEFT,-1,30,IVORY)
	c.draw_string(ActionSlot.face("semi"),Vector2(c.size.x-27,31),"s",HORIZONTAL_ALIGNMENT_LEFT,-1,19,MUTED)
	var track:=Rect2(112,17,c.size.x-112-30-w-12,6)
	c.draw_rect(track,Color(0.03,0.04,0.03,0.95))
	c.draw_rect(Rect2(track.position,Vector2(roundf(track.size.x*clampf(_alarm_fill,0.0,1.0)),track.size.y)),RED)
	c.draw_string(ActionSlot.face("medium"),Vector2(18,54),_alarm_line,HORIZONTAL_ALIGNMENT_LEFT,c.size.x-36,19,IVORY)

func _refresh_prompt(unit: Dictionary) -> void:
	var key: int=((ARMED_MODES.find(armed)*4+_unit_index(str(unit.id)))*64+int(unit.ammo))*64+_marked.size()
	if key==_prompt_key: return
	_prompt_key=key
	_prompt_loud=false
	match armed:
		"shoot":
			var gun: Dictionary=unit.gun
			var rounds: int=int(unit.ammo)
			_prompt_loud=bool(gun.get("loud",false))
			_prompt_icon="target"
			_prompt_title="%s ARMED  ·  %d %s" % [caps(str(gun.label)),rounds,"ROUND" if rounds==1 else "ROUNDS"]
			# (a mission's gun may say it in its own words: data gun.prompt, gun.promptNone)
			if _marked.is_empty(): _prompt_line=str(gun.get("promptNone","Nobody in range and in sight. Tap away to lower it."))
			elif gun.has("prompt"): _prompt_line=str(gun.prompt)
			elif _prompt_loud: _prompt_line="Loud: the whole post will hear it. Tap a marked guard."
			else: _prompt_line="Tap a marked guard. Tap anywhere else to lower it."
		"takedown":
			_prompt_icon=_icon_for("takedown",unit)
			_prompt_title="%s  ·  TAP A GUARD" % caps(str(unit.melee.label))
			_prompt_line="Come from behind or the side. Tap elsewhere to cancel."
		_:
			var throw: Dictionary=sim.throw_spec(unit)
			var what: String=str(throw.get("label","Pebble"))
			_prompt_icon=_icon_for("distract",unit)
			_prompt_title="%s  ·  TAP THE GROUND" % caps(what)
			_prompt_line="Inside the ring. Tap the %s plate again to cancel." % what.to_lower()
	prompt.queue_redraw()

func _paint_prompt(c: Canvas) -> void:
	var tone: Color=RED.lightened(0.15) if _prompt_loud else BRASS
	ActionSlot.nine(c,ActionSlot.TexStrip,Rect2(Vector2.ZERO,c.size),24.0,8.0)
	c.draw_rect(Rect2(1,3,4,c.size.y-6),tone)
	ActionSlot.glyph(c,_prompt_icon,Vector2(32,c.size.y*0.5),34,tone)
	c.draw_string(ActionSlot.face("semi",2),Vector2(60,23),tr(_prompt_title),HORIZONTAL_ALIGNMENT_LEFT,c.size.x-70,20,tone)
	c.draw_string(ActionSlot.face("medium"),Vector2(60,44),tr(_prompt_line),HORIZONTAL_ALIGNMENT_LEFT,c.size.x-70,18,IVORY)

## Screen-edge mood: a soft dark vignette in command mode, a red glow that breathes during an alarm,
## brass while a firearm is armed (the next tap on a guard is a shot).
func _paint_frame(c: Canvas) -> void:
	var rect:=Rect2(Vector2.ZERO,c.size)
	if _frame_state&1!=0: ActionSlot.nine(c,ActionSlot.TexEdge,rect,56.0,0.0,Color(0.02,0.03,0.03,0.55),false)
	if _frame_state&4!=0: ActionSlot.nine(c,ActionSlot.TexEdge,rect,56.0,0.0,Color(BRASS,0.62),false)
	elif _frame_state&2!=0: ActionSlot.nine(c,ActionSlot.TexEdge,rect,56.0,0.0,Color(RED,0.9),false)

# --- one-time hints ---------------------------------------------------------------------------------------------------
func _watch_for_hints() -> void:
	if hints.has("inside") and not bool(progress.get_value("hints","inside",false)) and not bool(sim.alarm.active):
		# a local standing where he has no business: his cover is gone
		for u: Dictionary in sim.units:
			if u.has("cover") and u.stance=="walk" and str(u.carrying)=="" and not bool(u.get("blown",false)) and not bool(u.get("covered",true)):
				hint("inside")
				break
	if not bool(progress.get_value("hints","far_zone",false)):
		for u: Dictionary in sim.units:
			if u.stance!="sneak" or sim.is_exposed(u): continue
			var at: Vector2=sim.position_of(u)
			for guard: Dictionary in sim.guards:
				if sim.zone_at(guard,at,true)==1 and sim.zone_at(guard,at,false)==0:
					hint("far_zone")
					return
	if not sim.fence_cut and not bool(progress.get_value("hints","wire",false)):
		for thing: Dictionary in _pins:
			if thing.type!="fence": continue
			for u: Dictionary in sim.units:
				if bool(u.tools) and sim.position_of(u).distance_to(Vector2(float(thing.x),float(thing.y)))<300.0: hint("wire")
	_coach()

## The first-run coach: what the player has done so far this run, and the next teaching line whose moment
## has come. Lines wait until no other line is showing, so they never cut each other off.
func _coach() -> void:
	var t: float=float(sim.time)
	if t<_coach_clock-0.01:
		_coach_planned=false
		_coach_ordered.clear()
	_coach_clock=t
	if sim.paused: _coach_planned=true
	for u: Dictionary in sim.units:
		if not (u.order as Dictionary).is_empty(): _coach_ordered[str(u.id)]=true
	if Time.get_ticks_msec()<_hint_until+1200.0: return
	# The first line ("how to play at all") always comes first.
	var opened: bool=bool(progress.get_value("hints","start",false))
	for id: String in coach_order:
		if bool(progress.get_value("hints",id,false)): continue
		if id!="start" and not opened: return
		if _coach_due(id,t):
			hint(id)
			return

func _coach_due(id: String, t: float) -> bool:
	match id:
		"start": return t>=0.6
		"cell":
			if sim.door_open or not sim.data.has("door"): return false
			var gate:=Vector2(float(sim.data.door.interactX),float(sim.data.door.interactY))
			for u: Dictionary in sim.units:
				if not bool(u.tools) and bool(u.alive) and sim.position_of(u).distance_to(gate)<220.0: return true
			return false
		"takedown":
			var unit: Dictionary=sim.selected()
			return not unit.is_empty() and _awake_guard_within(sim.position_of(unit),200.0)
		"cones":
			for u: Dictionary in sim.units:
				if bool(u.alive) and _awake_guard_within(sim.position_of(u),280.0): return true
			return t>=20.0
		"plan": return t>=40.0 and not _coach_planned
		"uniform":
			# the first time a man is down with his uniform still on him
			if not sim.data.has("uniforms"): return false
			for guard: Dictionary in sim.guards:
				if str(guard.state) in sim.BODY_STATES and not bool(guard.get("stripped",false)): return true
			return false
		"both": return t>=55.0 and _coach_ordered.size()<sim.units.size()
		"radio":
			if sim.radio_cut or not sim.data.has("radio"): return false
			var radio:=Vector2(float(sim.data.radio.x),float(sim.data.radio.y))
			for u: Dictionary in sim.units:
				if bool(u.alive) and sim.position_of(u).distance_to(radio)<300.0: return true
			return t>=90.0
	# A mission's own lines: "when" {"after": seconds, "near": [x, y, radius], "who": id, "unplanted": objective};
	# "who" alone: while that operative is selected
	var when: Dictionary=sim.data.get("copy",{}).get("hintsWhen",{}).get(id,{})
	if when.is_empty(): return false
	# about one operative and nowhere in particular: when he is the one selected (and after its time, if any)
	if when.has("who") and not when.has("near"):
		var hand: Dictionary=sim.selected()
		if hand.is_empty() or str(hand.id)!=str(when.who): return false
		if when.has("unplanted") and sim.objective_progress(str(when.unplanted))[0]>=sim.objective_progress(str(when.unplanted))[1]: return false
		return t>=float(when.get("after",0.0))
	if when.has("unplanted") and sim.objective_progress(str(when.unplanted))[0]>=sim.objective_progress(str(when.unplanted))[1]: return false
	if when.has("near"):
		var spot:=Vector2(float(when.near[0]),float(when.near[1]))
		for u: Dictionary in sim.units:
			if when.has("who") and str(u.id)!=str(when.who): continue
			if bool(u.alive) and sim.position_of(u).distance_to(spot)<float(when.near[2]): return true
	return when.has("after") and t>=float(when.after)

func _awake_guard_within(at: Vector2, reach: float) -> bool:
	for guard: Dictionary in sim.guards:
		if str(guard.state) in ["dead","bound","held","stunned"] or str(guard.carried_by)!="" or bool(guard.get("hidden",false)): continue
		if at.distance_to(Vector2(float(guard.x),float(guard.y)))<reach: return true
	return false

# --- floating marks ------------------------------------------------------------------------------------------------------
func _refresh_asset_tag() -> void:
	if not sim.has_prisoner: return
	var asset: Dictionary=sim.prisoner
	var state: int=0
	if bool(asset.freed): state=3 if bool(asset.aboard) else (2 if bool(asset.hidden) else 1)
	if state==_asset_state: return
	_asset_state=state
	var l: Label=labels.asset
	l.text=_asset_tag(ASSET_TAGS[state])
	l.add_theme_color_override("font_color",IVORY if state==1 else KHAKI.lightened(0.25))
	_size_tag(l)

## Name tags follow their people every frame so they do not lag behind a camera pan; the marks drawn
## over guards and tappable things are repainted with them.
func _process(dt: float) -> void:
	if sim==null or camera==null or overlay.visible: return
	_track_labels()
	overhead.queue_redraw()
	if _frame_state&6!=0:
		_pulse=fmod(_pulse+dt*2.6,TAU)
		frame.self_modulate.a=0.72+0.28*sin(_pulse)
	elif frame.self_modulate.a!=1.0: frame.self_modulate.a=1.0

func _track_labels() -> void:
	for id: String in labels:
		var actor: Dictionary=sim.prisoner if id=="asset" else sim.unit_by_id(id)
		var p:=Vector3(float(actor.x)/32,1.95,float(actor.y)/32)
		var l: Label=labels[id]
		var wanted: bool=id==sim.selected_id or id=="asset" or bool(actor.get("acting",false))
		l.visible=wanted and sim.phase=="playing" and not overlay.visible and not camera.is_position_behind(p) and bool(actor.get("alive",true))
		if l.visible:
			l.position=(camera.unproject_position(p)-Vector2(l.size.x*0.5,l.size.y+7)).round()
			if id=="asset":
				# Walking at his escort's shoulder: lift his tag clear of theirs.
				for other: String in operatives:
					var theirs: Label=labels[other]
					if theirs.visible and Rect2(l.position,l.size).grow(3).intersects(Rect2(theirs.position,theirs.size)): l.position.y=theirs.position.y-l.size.y-8
			_tag_at[id]=l.position

func _paint_overhead(c: Canvas) -> void:
	if sim==null or camera==null or sim.phase!="playing" or overlay.visible: return
	var view: Vector2=viewport_size
	var semi: Font=ActionSlot.face("semi")
	# Things worth a tap for the selected operative.
	for thing: Dictionary in _pins:
		if not _pin_shown(thing): continue
		var at: Vector2=_pin_point(thing)
		if at.x<-30 or at.y<-30 or at.x>view.x+30 or at.y>view.y+30: continue
		var chosen: bool=str(thing.id)==str(context.pin)
		c.draw_rect(Rect2(at.x-1,at.y+PIN_RADIUS-1,2,7),Color(IVORY,0.8))
		c.draw_circle(at,PIN_RADIUS,DARK,true,-1.0,true)
		# the icon is a full-colour object, so the chosen pin says so with a brass disc behind it
		if chosen: c.draw_circle(at,PIN_RADIUS-2.0,Color(BRASS,0.22),true,-1.0,true)
		c.draw_arc(at,PIN_RADIUS-1.0,0.0,TAU,28,BRASS if chosen else Color(KHAKI,0.75),3.0 if chosen else 1.25,true)
		ActionSlot.glyph(c,thing_icons.get(thing.type,"tap"),at,26,BRASS if chosen else IVORY)
	if bool(sim.get("rescue_on")): _paint_cold(c,view,semi)
	# Guards: what each one knows, and who the armed action can reach.
	for guard: Dictionary in sim.guards:
		if bool(guard.get("person",false)): continue
		if bool(guard.get("creature",false)):
			_paint_creature(c,guard,view,semi)
			continue
		var state: String=guard.state
		if state=="dead" or state=="bound" or state=="held" or str(guard.carried_by)!="": continue
		var lying: bool=state=="stunned"
		var ground:=Vector3(float(guard.x)/32,float(guard.elevation),float(guard.y)/32)
		if camera.is_position_behind(ground): continue
		var at: Vector2=camera.unproject_position(ground+Vector3(0,1.05 if lying else 2.45,0)).round()
		if at.x<-40 or at.y<-40 or at.x>view.x+40 or at.y>view.y+40: continue
		if not _marked.is_empty() and str(guard.id) in _marked:
			_brackets(c,camera.unproject_position(ground+Vector3(0,0.35 if lying else 0.95,0)).round(),armed=="shoot")
		if lying:
			# Out cold, for now: the ring drains to the moment he wakes.
			var left: float=float(guard.stun_time)
			c.draw_circle(at,20.0,DARK,true,-1.0,true)
			ActionSlot.ring(c,at,16.5,left/float(sim.STUN_TIME),3.5,RED if left<5.0 else BRASS)
			ActionSlot.label(c,semi,ActionSlot.number(ceili(left)),at.x,at.y+7,21,IVORY)
			continue
		var level: float=maxf(float(guard.suspicion),float(guard.body_alert))
		var sure: bool=bool(guard.spotted) or float(guard.suspicion)>=1.0
		if state=="hunt" or sure:
			var aiming: bool=str(guard.target_id)!=""
			if aiming or sure:
				c.draw_circle(at,16.0,DARK,true,-1.0,true)
				c.draw_circle(at,13.5,RED,true,-1.0,true)
				ActionSlot.label(c,semi,"!",at.x,at.y+9,26,IVORY)
				# The ring closes as he takes aim: when it is full he fires.
				if aiming and float(guard.aim_total)>0.0: ActionSlot.ring(c,at,19.5,float(guard.aim_time)/float(guard.aim_total),3.0,IVORY,Color(0.03,0.04,0.03,0.55))
			else:
				c.draw_circle(at,12.5,DARK,true,-1.0,true)
				c.draw_arc(at,11.0,0.0,TAU,24,Color(RED,0.9),1.75,true)
				ActionSlot.label(c,semi,"!",at.x,at.y+7,20,RED.lightened(0.2))
		elif level>0.03:
			var tone: Color=BRASS.lerp(RED,smoothstep(0.35,0.75,level))
			c.draw_circle(at,18.0,DARK,true,-1.0,true)
			ActionSlot.ring(c,at,14.5,level,3.5,tone)
			ActionSlot.glyph(c,"eye",at,19,tone)
		elif state=="investigate" or state=="search":
			c.draw_circle(at,15.5,DARK,true,-1.0,true)
			if state=="search" and float(guard.search_total)>0.0: ActionSlot.ring(c,at,13.5,float(guard.search_time)/float(guard.search_total),2.5,KHAKI,Color(0.03,0.04,0.03,0.4))
			else: c.draw_arc(at,13.5,0.0,TAU,24,Color(KHAKI,0.8),1.5,true)
			ActionSlot.label(c,semi,"?",at.x,at.y+9,25,BRASS)
	# Timed work: a ring beside the operative's name tag.
	for u: Dictionary in sim.units:
		if not bool(u.acting) or float(u.action_total)<=0.0: continue
		var l: Label=labels[u.id]
		if not l.visible: continue
		var at: Vector2=_tag_at[u.id]+Vector2(-20,l.size.y*0.5)
		c.draw_circle(at,17.0,DARK,true,-1.0,true)
		ActionSlot.ring(c,at,13.0,float(u.action_time)/float(u.action_total),4.5,BRASS)
	# The informant's wounds, under his tag.
	var asset: Dictionary=sim.prisoner
	if sim.has_prisoner and int(asset.hp)<100 and bool(asset.alive) and (labels.asset as Label).visible:
		var l: Label=labels.asset
		var base: Vector2=_tag_at.asset+Vector2(l.size.x*0.5-17,-9)
		var left: int=clampi(ceili(float(asset.hp)/34.0),0,3)
		c.draw_rect(Rect2(base-Vector2(2,2),Vector2(38,9)),DARK)
		for i: int in range(3): c.draw_rect(Rect2(base+Vector2(i*12,0),Vector2(10,5)),(RED if left==1 else BRASS) if i<left else Color(0.26,0.12,0.09))

## A rescue's creature (a cascarudo), over its back: going for someone, a red disc with "!"; roaming, a red ring with an
## eye (it is looking for someone out in the open); drawn by a noise, a ring with what it heard (the bell, a shot, a
## shout); standing over one it knocked down, a beating red ring; running off, a pale ring. The armed action's brackets
## too, when a shot can reach it.
func _paint_creature(c: Canvas, guard: Dictionary, view: Vector2, semi: Font) -> void:
	var state: String=str(guard.state)
	if not state in ["prowl","stalk","drawn","stay","driven"]: return
	var ground:=Vector3(float(guard.x)/32,0.0,float(guard.y)/32)
	if camera.is_position_behind(ground): return
	var at: Vector2=camera.unproject_position(ground+Vector3(0,2.9,0)).round()
	if at.x<-40 or at.y<-40 or at.x>view.x+40 or at.y>view.y+40: return
	if not _marked.is_empty() and str(guard.id) in _marked:
		_brackets(c,camera.unproject_position(ground+Vector3(0,1.0,0)).round(),armed=="shoot")
	match state:
		"stalk":
			c.draw_circle(at,16.0,DARK,true,-1.0,true)
			c.draw_circle(at,13.5,RED,true,-1.0,true)
			ActionSlot.label(c,semi,"!",at.x,at.y+9,26,IVORY)
		"stay":
			var beat: float=0.5+0.5*sin(Time.get_ticks_msec()*0.008)
			c.draw_circle(at,15.0,DARK,true,-1.0,true)
			c.draw_arc(at,12.0+2.0*beat,0.0,TAU,28,Color(RED,0.6+0.4*beat),3.0,true)
		"driven":
			c.draw_circle(at,13.0,DARK,true,-1.0,true)
			c.draw_arc(at,11.0,0.0,TAU,24,Color(KHAKI,0.8),1.75,true)
		_:
			var heard: String=str(guard.get("noise_kind",""))
			var icon: String={"bell":"bell","rifle":"target","voice":"talk"}.get(heard,"eye") if state=="drawn" else "eye"
			c.draw_circle(at,18.0,DARK,true,-1.0,true)
			c.draw_arc(at,15.0,0.0,TAU,28,Color(RED,0.85),2.5,true)
			ActionSlot.glyph(c,icon,at,20,RED.lightened(0.25) if icon=="eye" else IVORY)

## A rescue: over each person still out in the snow, a small ring filling with the cold they have taken (pale, then
## brass, then red); over one who has fallen, the time left to get to them draining away, red; a chevron over those
## following an operative. The squad's own cold rides beside their name tags; one of them down, his time left.
func _paint_cold(c: Canvas, view: Vector2, semi: Font) -> void:
	var grace: Dictionary=sim.data.get("snowfall",{}).get("grace",{})
	for person: Dictionary in sim.people():
		var state: String=str(person.state)
		if state=="safe" or state=="lost" or str(person.get("carried_by",""))!="": continue
		var ground:=Vector3(float(person.x)/32,0.0,float(person.y)/32)
		if camera.is_position_behind(ground): continue
		var down: bool=state=="fallen"
		var at: Vector2=camera.unproject_position(ground+Vector3(0,1.2 if down else 2.25,0)).round()
		if at.x<-30 or at.y<-30 or at.x>view.x+30 or at.y>view.y+30: continue
		if down:
			var left: float=float(person.get("fall_left",0.0))/maxf(1.0,float(grace.get("person",40.0)))
			c.draw_circle(at,15.0,DARK,true,-1.0,true)
			ActionSlot.ring(c,at,11.5,left,3.0,RED)
			ActionSlot.label(c,semi,"!",at.x,at.y+7,19,RED.lightened(0.2))
			continue
		var cold: float=float(person.get("exposure",0.0))
		if cold<0.03 and state!="follow" and state!="panic": continue
		var tone: Color=ActionSlot.COLD.lerp(BRASS,smoothstep(0.35,0.6,cold)).lerp(RED,smoothstep(0.7,0.9,cold))
		c.draw_circle(at,9.5,Color(DARK,0.7),true,-1.0,true)
		ActionSlot.ring(c,at,7.0,cold,2.5,tone,Color(0.03,0.04,0.03,0.6))
		if state=="follow":
			c.draw_polyline(PackedVector2Array([at+Vector2(-4,-13),at+Vector2(0,-17),at+Vector2(4,-13)]),IVORY,1.75,true)
		elif state=="panic":
			ActionSlot.label(c,semi,"!",at.x,at.y-12,16,RED.lightened(0.15))
	for u: Dictionary in sim.units:
		if not bool(u.alive) or not labels.has(u.id) or not (labels[u.id] as Label).visible: continue
		var l: Label=labels[u.id]
		var at: Vector2=_tag_at[u.id]+Vector2(l.size.x*0.5+14,l.size.y*0.5)
		if bool(u.get("fallen",false)):
			var left: float=float(u.get("fall_left",0.0))/maxf(1.0,float(grace.get("unit",45.0)))
			c.draw_circle(at,15.0,DARK,true,-1.0,true)
			ActionSlot.ring(c,at,11.5,left,3.0,RED)
			ActionSlot.label(c,semi,"!",at.x,at.y+7,19,RED.lightened(0.2))
			continue
		var cold: float=float(u.get("exposure",0.0))
		if cold<0.03: continue
		var tone: Color=ActionSlot.COLD.lerp(BRASS,smoothstep(0.35,0.6,cold)).lerp(RED,smoothstep(0.7,0.9,cold))
		c.draw_circle(at,11.0,DARK,true,-1.0,true)
		ActionSlot.ring(c,at,8.0,cold,3.0,tone,Color(0.03,0.04,0.03,0.6))

## The status line in a rescue: under cover so far, and the snow (falling hard / the next wave / easing off).
func _snow_status() -> String:
	var counts: Dictionary=sim.rescue_counts()
	var level: String=str(sim.snow_level())
	var wave_in: float=float(sim.next_wave())
	var snow: String=tr("WAVE")
	if level=="lull": snow=tr("LULL")
	elif level!="wave": snow=tr("WAVE IN %d") % ceili(wave_in) if wave_in>=0.0 and wave_in<60.0 else tr("SNOWING")
	return tr("SAFE %d/%d") % [int(counts.saved),int(counts.total)]+" · "+snow

## Corner brackets around a guard the armed action can reach; a shot adds the centre tick marks.
func _brackets(c: Canvas, at: Vector2, shot: bool) -> void:
	var half:=Vector2(22,27)
	var arm: float=9.0
	for sx: float in SIGNS:
		for sy: float in SIGNS:
			var corner: Vector2=at+Vector2(half.x*sx,half.y*sy)
			for pass_index: int in range(2):
				var tone: Color=Color(0.03,0.04,0.03,0.8) if pass_index==0 else BRASS
				var w: float=5.0 if pass_index==0 else 3.0
				c.draw_line(corner,corner-Vector2(arm*sx,0),tone,w)
				c.draw_line(corner,corner-Vector2(0,arm*sy),tone,w)
	if shot:
		for d: Vector2 in COMPASS:
			c.draw_line(at+Vector2(d.x*half.x,d.y*half.y),at+Vector2(d.x*(half.x-7),d.y*(half.y-7)),BRASS,2.0)

func _pin_shown(thing: Dictionary) -> bool:
	if not bool(thing.enabled): return false
	var type: String=thing.type
	if type=="body": return _body_wants_moving(str(thing.target)) and sim.guard_by_id(str(thing.target)).state!="stunned"
	if type=="extraction": return bool(sim.prisoner.freed) if sim.has_prisoner else sim.ready_to_leave()
	# the people of a rescue carry their own marks overhead (the cold); they are tapped on, not on a pin; so are its
	# creatures (what each is doing, over its back: _paint_creature)
	if type=="person" or type=="creature": return false
	return true

func _pin_point(thing: Dictionary) -> Vector2:
	return camera.unproject_position(Vector3(float(thing.x)/32,float(PIN_LIFT.get(thing.type,1.6)),float(thing.y)/32)).round()

## The tappable thing whose floating marker is under `point`, or {}.
func pin_at(point: Vector2) -> Dictionary:
	if sim.phase!="playing" or overlay.visible: return {}
	var best: Dictionary={}
	var best_d: float=PIN_RADIUS+13.0
	for thing: Dictionary in sim.interactables():
		if not _pin_shown(thing): continue
		var d: float=_pin_point(thing).distance_to(point)
		if d<best_d:
			best=thing
			best_d=d
	return best

## Every block that swallows a tap or the end of a map gesture (see main.gd); check visibility.
func touch_blocks() -> Array[Control]:
	if _blocks.is_empty(): _blocks=[portrait_strip,action_strip,tools_row,camera_row,minimap,readout,objective_block,planning,alarm_banner,prompt]
	return _blocks

# --- layout self-check (tests and tools/check_layout.gd) ------------------------------------------------------------
const MIN_TOUCH := 76.0

func _visible_buttons(node: Node, found: Array[Button]) -> void:
	if node is Button and (node as Button).is_visible_in_tree(): found.append(node)
	for child: Node in node.get_children(): _visible_buttons(child,found)

## Everything wrong with what is on screen right now, in words: a block outside the safe rectangle, two
## blocks overlapping, a button smaller than a thumb. Empty when all is well.
func layout_problems() -> Array[String]:
	var problems: Array[String]=[]
	var safe:=Rect2(Vector2(insets.x,insets.y),viewport_size-Vector2(insets.x+insets.z,insets.y+insets.w)).grow(0.5)
	var blocks: Dictionary={}
	if overlay.visible: blocks["dossier"]=modal
	else:
		blocks={"photos":portrait_strip,"view keys":camera_row,"readout":readout,"objectives":objective_block,"menu keys":tools_row,"map":minimap,"bar":action_strip}
		for entry: Array in [["command banner",planning],["alarm banner",alarm_banner],["armed prompt",prompt],["checkpoint tag",toast]]:
			if (entry[1] as Control).visible: blocks[entry[0]]=entry[1]
		for id: String in tags:
			if (tags[id] as Control).visible: blocks["tag "+id]=tags[id]
		if notice.visible: blocks["notice"]=notice_plate
		if hint_label.visible: blocks["hint"]=hint_plate
	var names: Array=blocks.keys()
	for i: int in range(names.size()):
		var rect: Rect2=(blocks[names[i]] as Control).get_global_rect()
		if not safe.encloses(rect): problems.append("%s %s leaves the safe area %s" % [names[i],rect,safe])
		for k: int in range(i+1,names.size()):
			if rect.intersects((blocks[names[k]] as Control).get_global_rect()): problems.append("%s overlaps %s" % [names[i],names[k]])
	var found: Array[Button]=[]
	_visible_buttons(self,found)
	for b: Button in found:
		if b.size.x<MIN_TOUCH-0.5 or b.size.y<MIN_TOUCH-0.5: problems.append("button %s is only %s" % [b.text,b.size])
		if not Rect2(Vector2.ZERO,viewport_size).grow(0.5).encloses(b.get_global_rect()): problems.append("button %s is off screen" % b.text)
	return problems

func view_blocks_fit() -> bool:
	return layout_problems().is_empty()
