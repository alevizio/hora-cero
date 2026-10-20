extends Control
## The launch screen: the game's name over the level's own scene (the camera drifting along it, the guards on their
## rounds), a short menu, and the pages it opens on the dossier paper: SETTINGS and the questions (TELL US WHAT YOU
## THINK). main.gd shows it on a fresh start and whenever the player leaves a level; HOW TO PLAY and the briefing are
## the HUD's own pages, which this asks for through `command`.
##
## Under the name it says PREVIEW (ADELANTO in Spanish) and the game's line (Missions.title()). The questions are on
## the menu all along, and the pause menu opens them over the paused level (open_questions_over_game), when the answers
## have somewhere to go (Feedback.enabled(): a feedback address is configured; otherwise they are not offered). The two
## languages are on the launch screen itself, ES and EN, top right (Missions.lang_keys()).
##
## Commands: "continue" (the current level's briefing), "howto", "lang:<code>" (from SETTINGS),
## "title_lang:<code>" (from the launch screen's own keys),
## "settings" (sound, voices or text size changed: main applies them), "tap" and "deny" (sounds),
## "questions_closed" (the questions over the game are done with: back to the pause menu).

signal command(name: String)

const HUD = preload("res://scripts/three_d/hud.gd")
const Kit = preload("res://scripts/three_d/action_slot.gd")
const Missions = preload("res://scripts/missions.gd")
const Lang = preload("res://scripts/lang.gd")
const Feedback = preload("res://scripts/feedback.gd")
const ComicInk = preload("res://scripts/three_d/ink.gd")
const ArtPack = preload("res://scripts/three_d/art_pack.gd")
const IVORY := Kit.IVORY
const KHAKI := Kit.KHAKI
const BRASS := Kit.BRASS
const INK := Kit.INK
const DIM := Kit.DIM
## The menu's lines. "feedback" shows only when the answers have somewhere to go (Feedback.enabled()).
const MENU := ["continue", "settings", "howto", "feedback"]
const MENU_WORDS := {"continue": "CONTINUE", "settings": "SETTINGS", "howto": "HOW TO PLAY", "feedback": HUD.QUESTIONS}
const PAGES := ["settings", "feedback"]
## A menu line: a thumb high (the HUD's MIN_TOUCH), a little less where a short screen needs it.
const ITEM_H := 76.0
const ITEM_MIN := 72.0
const ITEM_GAP := 2.0
const SHEET_PAD := Vector2(40, 30)

## Where the next start of the scene lands (read once by main.gd through landing()): "title" (the menu), one of
## its pages ("settings"), or "briefing" (straight to the level's briefing, after one was chosen).
static var resume_to: String = "title"
## Tests: 1 shows the launch screen, 0 never. By default runs started with --script skip it (they test the
## game itself) unless HORACERO_TITLE=1.
static var force: int = -1

## Where this start of the scene should go: "briefing", "title" or a page of the launch screen.
static func landing() -> String:
	var to: String = resume_to
	resume_to = "title"
	var testing: bool = "--script" in OS.get_cmdline_args() and OS.get_environment("HORACERO_TITLE") != "1"
	if force == 0 or (force == -1 and testing and to == "title"):
		return "briefing"
	return to

var hud: Control
var sim: RefCounted
## The answers to the questions (feedback.gd).
var feedback: Node
## "" while the menu shows; otherwise the open page.
var page: String = ""
var items: Dictionary = {}
var shade: Shade
var title_art: Control
var menu_box: VBoxContainer
## The language keys on the launch screen (null where there are none).
var lang_row: HBoxContainer
var pane: ColorRect
var sheet: PanelContainer
var sheet_box: VBoxContainer
var sheet_page: Label
var sheet_title: Label
var body: VBoxContainer
var back_button: Button
var _upright: bool = false
var _queued: bool = false
## The questions (page "feedback"): which of its pages is open, the answers so far, the keys of each question,
## the two writing fields, and the line that says how the sending went.
var fb_step: int = 0
var fb: Dictionary = {}
var fb_keys: Dictionary = {}
var fb_comment: LineEdit
var fb_email: LineEdit
var fb_error: Label
var fb_status: Label
var fb_result: String = ""
var fb_next: Button
var fb_back: Button

## A menu line: big stencil words, left-aligned; brass bar and a dark strip under the finger or the focus.
class MenuItem extends Button:
	const Kit := preload("res://scripts/three_d/action_slot.gd")
	var caption: String = ""
	var sub: String = ""
	var lead: bool = false
	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		for key: String in ["normal","hover","pressed","hover_pressed","disabled","focus"]:
			add_theme_stylebox_override(key, StyleBoxEmpty.new())
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
	func _draw() -> void:
		var mode := get_draw_mode()
		var down: bool = mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED
		var hot: bool = down or mode == DRAW_HOVER or has_focus()
		if hot:
			Kit.nine(self, Kit.TexStrip, Rect2(Vector2.ZERO, size), 24.0, 8.0, Color(1, 1, 1, 0.92))
			draw_rect(Rect2(0, 8, 4, size.y - 16), Kit.BRASS)
		var f: Font = Kit.face("stencil", 2)
		var px: int = int(clampf(size.y * 0.6, 30.0, 46.0))
		var shown: String = tr(caption)
		# a long line (TELL US WHAT YOU THINK) is set smaller rather than run past the menu
		while px > 26 and f.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > size.x - 40: px -= 2
		var base: float = roundf(size.y * 0.5 + px * 0.36) + (1.0 if down else 0.0)
		var tone: Color = Kit.IVORY if (hot or lead) else Color(Kit.IVORY, 0.8)
		if disabled: tone = Kit.DIM
		draw_string(f, Vector2(24, base + 2), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0, 0, 0, 0.55))
		draw_string(f, Vector2(24, base), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, px, tone)
		if sub != "":
			var w: float = f.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			var sf: Font = Kit.face("semi", 3)
			var spx: int = 19
			var room: float = size.x - (24 + w + 20) - 12
			var line: String = tr(sub)
			while spx > 14 and sf.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, spx).x > room: spx -= 1
			if sf.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, spx).x <= room:
				draw_string(sf, Vector2(24 + w + 20, base - 2), line, HORIZONTAL_ALIGNMENT_LEFT, -1, spx, Kit.BRASS if lead else Kit.KHAKI)

## The dark the menu sits on: down the left of a landscape screen, top and bottom of an upright one.
class Shade extends Control:
	var upright: bool = false
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _band(a: Vector2, b: Vector2, c: Vector2, d: Vector2, from: float, to: float, along_x: bool) -> void:
		var dark := Color(0.015, 0.02, 0.018)
		var c0 := Color(dark, from)
		var c1 := Color(dark, to)
		if along_x: draw_polygon(PackedVector2Array([a, b, c, d]), PackedColorArray([c0, c1, c1, c0]))
		else: draw_polygon(PackedVector2Array([a, b, c, d]), PackedColorArray([c0, c0, c1, c1]))
	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.12))
		if upright:
			_band(Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.4), Vector2(0, h * 0.4), 0.78, 0.0, false)
			_band(Vector2(0, h * 0.42), Vector2(w, h * 0.42), Vector2(w, h), Vector2(0, h), 0.0, 0.9, false)
		else:
			var reach: float = minf(w * 0.62, 820.0)
			_band(Vector2(0, 0), Vector2(reach, 0), Vector2(reach, h), Vector2(0, h), 0.9, 0.0, true)
			_band(Vector2(0, h * 0.8), Vector2(w, h * 0.8), Vector2(w, h), Vector2(0, h), 0.0, 0.35, false)


# ------------------------------------------------------------------------------------------------------
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade = Shade.new()
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_art = hud.canvas(_paint_title)
	add_child(title_art)
	menu_box = VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", int(ITEM_GAP))
	add_child(menu_box)
	for key: String in MENU:
		var item := MenuItem.new()
		item.caption = MENU_WORDS[key]
		item.custom_minimum_size = Vector2(0, ITEM_H)
		item.lead = key == "continue"
		item.pressed.connect(_menu_pressed.bind(key))
		menu_box.add_child(item)
		items[key] = item
	if Missions.lang_keys():
		lang_row = HBoxContainer.new()
		lang_row.add_theme_constant_override("separation", 6)
		for lang: String in ["es", "en"]:
			var code: String = lang
			lang_row.add_child(_key(code.to_upper(), code == Lang.current, 92, func() -> void: command.emit("title_lang:" + code)))
		add_child(lang_row)
	_build_sheet()
	get_viewport().size_changed.connect(_queue_layout)
	hide()

## Shows the menu, or one of its pages ("settings", "feedback").
func open(which: String = "") -> void:
	show()
	page = ""
	over_game = false
	shade.show()
	# the questions are on the menu all along, when the answers have somewhere to go
	(items["feedback"] as Control).visible = Feedback.enabled()
	if which == "feedback" and not Feedback.enabled(): which = ""
	var played: bool = false
	for entry: Dictionary in Missions.LIST:
		played = played or hud.progress.has_section(str(entry.best)) or hud.progress.has_section_key("won", str(entry.id))
	var current: Dictionary = Missions.LIST[maxi(Missions.index_of(Missions.current), 0)]
	var item: MenuItem = items["continue"]
	item.caption = "CONTINUE" if played else "PLAY"
	item.sub = "%s  %s" % [str(current.number), tr(str(current.tab))]
	for key: String in items: (items[key] as MenuItem).queue_redraw()
	pane.hide()
	title_art.show()
	menu_box.show()
	if lang_row != null: lang_row.show()
	layout()
	if which == "feedback": _start_feedback()
	elif which in PAGES: _open_page(which)
	elif not DisplayServer.is_touchscreen_available(): (items["continue"] as MenuItem).grab_focus()

## Android's Back and Esc: a page goes back to the menu (the questions a page back); at the menu, false
## (main.gd leaves the game).
func back() -> bool:
	if page == "feedback" and fb_step > 0 and fb_step < _feedback_steps().size():
		_feedback_go(fb_step - 1)
		return true
	if page == "feedback" and over_game:
		_close_questions()
		return true
	if page != "":
		open()
		return true
	return false

func _menu_pressed(key: String) -> void:
	match key:
		"continue": command.emit("continue")
		"howto": command.emit("howto")
		"feedback": _start_feedback()
		_: _open_page(key)

## The lines of the menu on show.
func _shown_items() -> int:
	var n: int = 0
	for key: String in MENU:
		if (items[key] as Control).visible: n += 1
	return n

# --- layout ---------------------------------------------------------------------------------------
func _queue_layout() -> void:
	if _queued: return
	_queued = true
	call_deferred("layout")

func layout() -> void:
	_queued = false
	if not is_inside_tree(): return
	var view: Vector2 = get_viewport_rect().size
	_upright = view.y > view.x
	shade.upright = _upright
	shade.queue_redraw()
	var ins: Vector4 = hud.insets if hud.insets is Vector4 else Vector4.ZERO
	var left: float = maxf(48.0, ins.x + 32.0)
	var right: float = view.x - maxf(48.0, ins.z + 32.0)
	var top: float = maxf(36.0, ins.y + 20.0)
	var bottom: float = view.y - maxf(36.0, ins.w + 20.0)
	var avail: float = bottom - top
	var item_h: float = ITEM_H
	var title_h: float = 230.0
	var count: int = _shown_items()
	if not _upright:
		# the title gives way first on a short screen, then the lines of the menu (never below ITEM_MIN)
		title_h = clampf(view.y * 0.36, 190.0, 300.0)
		var lines: float = count * ITEM_H + (count - 1) * ITEM_GAP
		if title_h + 18.0 + lines > avail: title_h = maxf(110.0, avail - 18.0 - lines)
		if title_h + 18.0 + lines > avail:
			item_h = clampf(floorf((avail - 18.0 - title_h - (count - 1) * ITEM_GAP) / count), ITEM_MIN, ITEM_H)
	for key: String in items: (items[key] as Control).custom_minimum_size.y = item_h
	var menu_h: float = count * item_h + (count - 1) * ITEM_GAP
	if _upright:
		var width: float = minf(600.0, right - left)
		menu_box.position = Vector2(roundf((left + right - width) * 0.5), bottom - menu_h)
		menu_box.size = Vector2(width, menu_h)
		title_art.position = Vector2(left, top + (view.y * 0.08))
		title_art.size = Vector2(right - left, title_h)
	else:
		var width: float = minf(560.0, (right - left) * 0.5)
		var block: float = title_h + 18.0 + menu_h
		var y0: float = maxf(top, roundf((top + bottom - block) * 0.5))
		title_art.position = Vector2(left - 6, y0)
		title_art.size = Vector2(maxf(width, 620.0), title_h)
		menu_box.position = Vector2(left - 24, y0 + title_h + 18.0)
		menu_box.size = Vector2(width, menu_h)
	if lang_row != null:
		var row_w: float = 92.0 * 2.0 + 6.0
		lang_row.size = Vector2(row_w, HUD.MIN_TOUCH)
		lang_row.position = Vector2(roundf(right - row_w), top)
	title_art.queue_redraw()
	if pane.visible: _place_sheet()

func _paint_title(c: Control) -> void:
	var f: Font = Kit.face("stencil", 4)
	var title_text: String = Missions.brand().to_upper()
	var px: int = int(clampf(c.size.x * 0.17 if _upright else c.size.y * 0.5, 72.0, 150.0))
	while px > 48 and f.get_string_size(title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > c.size.x: px -= 2
	var w: float = f.get_string_size(title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var x: float = roundf((c.size.x - w) * 0.5) if _upright else 0.0
	var base: float = roundf(c.size.y * 0.5 + px * 0.28)
	c.draw_string(f, Vector2(x + 3, base + 4), title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0, 0, 0, 0.6))
	c.draw_string(f, Vector2(x, base), title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, IVORY)
	_paint_preview_tag(c, x, base)

## What the title says under the name: PREVIEW stamped in a brass box, then the game's line (one place:
## Missions.title()).
func preview_tag() -> Array[String]:
	return [tr("PREVIEW"), tr(Missions.title()).to_upper()]

func _paint_preview_tag(c: Control, x: float, base: float) -> void:
	var words: Array[String] = preview_tag()
	var sf: Font = Kit.face("semi", 6)
	var stamp_px: int = 19
	var name_px: int = 22
	var sw: float = sf.get_string_size(words[0], HORIZONTAL_ALIGNMENT_LEFT, -1, stamp_px).x
	var box := Vector2(sw + 22.0, 32.0)
	var gap: float = 14.0
	var nw: float = sf.get_string_size(words[1], HORIZONTAL_ALIGNMENT_LEFT, -1, name_px).x
	var whole: float = box.x + gap + nw
	var rule_w: float = 56.0
	var x0: float = x + 4
	if _upright:
		x0 = roundf((c.size.x - whole) * 0.5)
		c.draw_rect(Rect2(roundf(c.size.x * 0.5 - rule_w * 0.5), base + 14, rule_w, 3), BRASS)
	else:
		c.draw_rect(Rect2(x0, base + 14, rule_w, 3), BRASS)
	var top: float = base + 26.0
	var stamp := Rect2(Vector2(x0, top), box)
	c.draw_rect(stamp, Color(0, 0, 0, 0.35))
	c.draw_rect(stamp.grow(-1.0), BRASS, false, 2.0)
	c.draw_string(sf, Vector2(x0 + 11.0, top + 23.0), words[0], HORIZONTAL_ALIGNMENT_LEFT, -1, stamp_px, BRASS)
	c.draw_string(sf, Vector2(x0 + box.x + gap, top + 24.0), words[1], HORIZONTAL_ALIGNMENT_LEFT, -1, name_px, KHAKI)

# --- the pages --------------------------------------------------------------------------------------
## The pages are the whole screen: dossier paper from edge to edge, the page's column centred on it (drawn
## smaller when a short screen cannot hold it).
func _build_sheet() -> void:
	pane = ColorRect.new()
	pane.color = Color(0.02, 0.03, 0.025, 1.0)
	pane.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(pane)
	pane.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var paper := HUD.Sheet.new()
	paper.paper = HUD.TexPaper
	paper.stain = HUD.TexStain
	paper.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet = paper
	pane.add_child(sheet)
	sheet_box = VBoxContainer.new()
	sheet_box.add_theme_constant_override("separation", 0)
	pane.add_child(sheet_box)
	var head := HBoxContainer.new()
	sheet_box.add_child(head)
	var t: Label = hud.ink(Missions.brand().to_upper() + "  /  FIELD OPERATIONS", 16, "semi", 2, 0.78)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	sheet_page = hud.ink("", 16, "semi", 2, 0.78)
	head.add_child(sheet_page)
	sheet_box.add_child(hud._spacer(5))
	var rule := HUD.Rule.new()
	rule.ink = Color(INK, 0.78)
	sheet_box.add_child(rule)
	sheet_box.add_child(hud._spacer(12))
	sheet_title = hud.ink("", 52, "stencil", 1)
	sheet_title.add_theme_constant_override("line_spacing", -12)
	sheet_box.add_child(sheet_title)
	sheet_box.add_child(hud._spacer(12))
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	sheet_box.add_child(body)
	sheet_box.add_child(hud._spacer(18))
	back_button = hud.button("BACK", open.bind(""), Vector2(0, 80), "secondary")
	sheet_box.add_child(back_button)
	sheet_box.minimum_size_changed.connect(_queue_layout)
	pane.hide()

func _open_page(which: String) -> void:
	page = which
	for child: Node in body.get_children():
		body.remove_child(child)
		child.queue_free()
	fb_keys.clear()
	fb_comment = null
	fb_email = null
	fb_error = null
	fb_status = null
	fb_next = null
	fb_back = null
	back_button.visible = which != "feedback"
	match which:
		"settings": _fill_settings()
		"feedback": _fill_feedback()
	title_art.hide()
	menu_box.hide()
	if lang_row != null: lang_row.hide()
	pane.show()
	_place_sheet()
	_queue_layout()

func _place_sheet() -> void:
	var view: Vector2 = get_viewport_rect().size
	var ins: Vector4 = hud.insets if hud.insets is Vector4 else Vector4.ZERO
	# the paper runs past every edge (its torn rim and shadow off screen)
	sheet.position = Vector2(-16, -16)
	sheet.size = view + Vector2(32, 32)
	var left: float = maxf(28.0, ins.x + 20.0)
	var right: float = view.x - maxf(28.0, ins.z + 20.0)
	var top: float = maxf(24.0, ins.y + 16.0)
	var bottom: float = view.y - maxf(20.0, ins.w + 12.0)
	var width: float = _column_width()
	sheet_box.size = Vector2(width, 0)
	var most: float = 1.0 if not _upright else (right - left) / width
	var fit: float = minf(most, (bottom - top) / maxf(sheet_box.size.y, 1.0))
	sheet_box.scale = Vector2(fit, fit)
	var y: float = top if sheet_box.size.y * fit > (bottom - top) * 0.82 else roundf(top + ((bottom - top) - sheet_box.size.y * fit) * 0.35)
	# a field being written in stays above the on-screen keyboard: the page slides up as far as it needs
	var typing: LineEdit = _typing_field()
	if typing != null:
		var keyboard: float = _keyboard_height()
		if keyboard > 0.0:
			var local_y: float = (typing.global_position.y - sheet_box.global_position.y) / maxf(sheet_box.scale.y, 0.01)
			var field_bottom: float = y + (local_y + typing.size.y) * fit
			var limit: float = view.y - keyboard - 16.0
			if field_bottom > limit: y -= field_bottom - limit
	sheet_box.position = Vector2(roundf((left + right - width * fit) * 0.5), y)

## The column the pages are set in: upright, at a phone's width (and drawn larger to fill the screen, so its type
## stays readable); on its side, up to 920 wide.
func _column_width() -> float:
	var view: Vector2 = get_viewport_rect().size
	var ins: Vector4 = hud.insets if hud.insets is Vector4 else Vector4.ZERO
	var room: float = view.x - maxf(28.0, ins.x + 20.0) - maxf(28.0, ins.z + 20.0)
	return minf(920.0, room) if not _upright else minf(460.0, room)

## The writing field that has the keyboard, if any.
func _typing_field() -> LineEdit:
	for edit: LineEdit in [fb_comment, fb_email]:
		if edit != null and is_instance_valid(edit) and edit.has_focus(): return edit
	return null

## The on-screen keyboard's height in the canvas's units (0 with none, or a hardware keyboard). The browser's display
## server cannot tell (asked, it only warns, every frame a field is being written in): 0 there.
func _keyboard_height() -> float:
	if OS.has_feature("web") or not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD): return 0.0
	var shown: int = DisplayServer.virtual_keyboard_get_height()
	if shown <= 0: return 0.0
	var window: Vector2i = DisplayServer.window_get_size()
	return float(shown) * get_viewport_rect().size.y / maxf(float(window.y), 1.0)

var _keyboard_seen: float = 0.0
func _process(_dt: float) -> void:
	# the keyboard slides in and out: follow it while a field is being written in
	if not visible or not pane.visible: return
	var k: float = _keyboard_height() if _typing_field() != null else 0.0
	if absf(k - _keyboard_seen) > 1.0:
		_keyboard_seen = k
		_place_sheet()

func _row(label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var caption: Label = hud.ink(label, 18, "semi", 2, 0.85)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.custom_minimum_size.x = 120
	row.add_child(caption)
	body.add_child(row)
	return row

func _key(word: String, chosen: bool, width: float, callback: Callable, letter_px: int = 22) -> Button:
	var key := HUD.SizeKey.new()
	key.word = word
	key.letter_px = letter_px
	key.chosen = chosen
	key.custom_minimum_size = Vector2(width, HUD.MIN_TOUCH)
	key.pressed.connect(callback)
	return key

## SETTINGS: language, text size, volume, voices, comic ink, and the credits for the art the game shows (the art
## pack's, scripts/three_d/art_pack.gd).
func _fill_settings() -> void:
	sheet_page.text = "SETTINGS"
	sheet_title.text = "SETTINGS"
	(sheet as HUD.Sheet).stamp = null
	var row: HBoxContainer = _row("LANGUAGE")
	for lang: String in Lang.LANGS:
		row.add_child(_key(str(Lang.NAMES[lang]), lang == Lang.current, 150, func() -> void: command.emit("lang:" + lang)))
	row = _row("TEXT SIZE")
	var sizes: Array[Button] = []
	for i: int in range(HUD.TEXT_SIZE_LETTERS.size()):
		var key: Button = _key("A", i == hud.text_size(), HUD.MIN_TOUCH, func() -> void:
			hud.set_text_size(i)
			for k: int in range(sizes.size()): (sizes[k] as HUD.SizeKey).chosen = k == hud.text_size(), int(HUD.TEXT_SIZE_LETTERS[i]))
		sizes.append(key)
		row.add_child(key)
	# the volume: off or one of four steps (the same keys as the pause menu's, so a change shows in both)
	row = _row("VOLUME")
	for control: Control in hud.volume_controls(): row.add_child(control)
	for setting: String in ["voices"]:
		row = _row("VOICES")
		var on: bool = bool(hud.progress.get_value("settings", setting, true))
		var pair: Array[Button] = []
		for value: bool in [true, false]:
			var key: Button = _key("ON" if value else "OFF", on == value, 110, func() -> void:
				hud.progress.set_value("settings", setting, value)
				hud._save_progress()
				(pair[0] as HUD.SizeKey).chosen = value
				(pair[1] as HUD.SizeKey).chosen = not value
				command.emit("settings"))
			pair.append(key)
			row.add_child(key)
	_ink_row()
	_credits()

## COMIC INK: the level drawn in black ink on newsprint (scripts/three_d/ink.gd), the interface left in colour.
## Off by default; a level or a build that asks for it has it on, and the choice is not the player's there.
func _ink_row() -> void:
	var row: HBoxContainer = _row("COMIC INK")
	var data: Dictionary = sim.data if sim != null else {}
	var forced: int = ComicInk.forced(data)
	var on: bool = ComicInk.wanted(data, hud.progress)
	var pair: Array[Button] = []
	for value: bool in [true, false]:
		var key: Button = _key("ON" if value else "OFF", on == value, 110, func() -> void:
			if forced >= 0:
				command.emit("deny")
				return
			hud.progress.set_value("settings", ComicInk.SETTING, value)
			hud._save_progress()
			(pair[0] as HUD.SizeKey).chosen = value
			(pair[1] as HUD.SizeKey).chosen = not value
			command.emit("settings"))
		pair.append(key)
		row.add_child(key)
	var line: String = "Black ink on newsprint. The interface keeps its colours." if forced < 0 else "This operation is drawn in comic ink."
	var note: Label = hud.ink(line, 16, "type", 0, 0.7)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)

## The credits for the art the game shows: every drawing or model of the art pack that has its file, with its author,
## its licence and the permission it is shown under (art_pack/manifest.json); then the game's thanks. Nothing when the
## pack has none yet and the game thanks nobody.
func _credits() -> void:
	var lines: Array[String] = ArtPack.credit_lines(Lang.current)
	if not lines.is_empty():
		body.add_child(hud._spacer(10))
		body.add_child(hud.ink("ART CREDITS", 18, "semi", 2, 0.85))
	for line: String in lines:
		# (names, and the credit as the makers gave it: never looked up in the language)
		var l: Label = hud.ink("", 15, "type", 0, 0.75)
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.text = line
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(l)
	var thanks: Array = Missions.thanks()
	if thanks.is_empty(): return
	body.add_child(hud._spacer(10))
	body.add_child(hud.ink("THANKS", 18, "semi", 2, 0.85))
	for line: Variant in thanks:
		var l: Label = hud.ink(str(line), 15, "type", 0, 0.75)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(l)

# --- TELL US WHAT YOU THINK -------------------------------------------------------------------------
## The questions for the people making the game, asked of anyone, finished or not (from the menu, from the pause menu
## over the paused level, and after the last level is won), when the answers have somewhere to go
## (Feedback.enabled()): two pages, how it went (did you enjoy it, would you play more levels like these) and the
## player's own words (what confused you or what you would change, an email to hear when more comes). Every answer
## is optional; NOT NOW leaves at any time. SEND files the answers with feedback.gd, which posts them now or the next
## time the game is online.
const FEEDBACK_TITLES := {"verdict": "YOUR VERDICT", "words": "YOUR WORDS"}
const LEAD := "A few questions about this operation, however far you got. Every answer is optional."

## The questions opened from the pause menu, over the paused level (main.gd): closing them hides this screen again and
## hands the game back ("questions_closed").
var over_game: bool = false

## The pause menu: the questions over the paused level, without leaving it.
func open_questions_over_game() -> void:
	show()
	over_game = true
	page = ""
	shade.hide()
	title_art.hide()
	menu_box.hide()
	if lang_row != null: lang_row.hide()
	_start_feedback()

## NOT NOW, or done: back to the menu, or (over the game) back to the paused level.
func _close_questions() -> void:
	if not over_game:
		open()
		return
	over_game = false
	page = ""
	pane.hide()
	shade.show()
	hide()
	command.emit("questions_closed")

## The pages of questions, in order.
func _feedback_steps() -> Array[String]:
	var steps: Array[String] = ["verdict", "words"]
	return steps

## From the menu, or straight after the last level's story: the first page, nothing answered yet.
func _start_feedback() -> void:
	fb_comment = null
	fb_email = null
	fb = {}
	fb_result = ""
	_feedback_go(0)

func _feedback_go(step: int) -> void:
	_keep_words()
	fb_step = clampi(step, 0, _feedback_steps().size())
	_open_page("feedback")

func _fill_feedback() -> void:
	(sheet as HUD.Sheet).stamp = null
	var steps: Array[String] = _feedback_steps()
	if fb_step >= steps.size():
		_fill_feedback_thanks()
		return
	var step: String = steps[fb_step]
	sheet_page.text = "REPORT  %d / %d" % [fb_step + 1, steps.size()]
	sheet_title.text = str(FEEDBACK_TITLES[step])
	match step:
		"verdict":
			var lead: Label = hud.ink(LEAD, 19, "type", 0, 0.88)
			lead.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.add_child(lead)
			body.add_child(hud._spacer(4))
			var marks: Array = []
			for n: int in range(1, 6): marks.append([n, str(n)])
			_question("DID YOU ENJOY IT?", "rating", marks, 5, 24)
			var ends := HBoxContainer.new()
			var low: Label = hud.ink("1  NOT AT ALL", 16, "semi", 1, 0.65)
			low.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ends.add_child(low)
			ends.add_child(hud.ink("VERY MUCH  5", 16, "semi", 1, 0.65))
			body.add_child(ends)
			body.add_child(hud._spacer(6))
			_question(Missions.ask(), "would_play_more", [["yes", "YES"], ["maybe", "MAYBE"], ["no", "NO"]], 3)
		"words":
			_caption("WHAT CONFUSED YOU, OR WHAT WOULD YOU CHANGE?")
			fb_comment = _text_field(str(fb.get("comment", "")), 1000, "Optional")
			body.add_child(fb_comment)
			body.add_child(hud._spacer(6))
			_caption("YOUR EMAIL, TO HEAR WHEN IT LAUNCHES")
			fb_email = _text_field(str(fb.get("email", "")), 254, "Optional")
			fb_email.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
			fb_email.text_submitted.connect(func(_value: String) -> void: _feedback_next())
			body.add_child(fb_email)
			fb_error = hud.ink("That email does not look right.", 16, "semi", 1, 1.0)
			fb_error.add_theme_color_override("font_color", Color(Kit.RED.darkened(0.25), 0.95))
			fb_error.hide()
			body.add_child(fb_error)
			var note: Label = hud.ink("Only to tell you when %s launches." % Missions.brand(), 15, "type", 0, 0.65)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.add_child(note)
	_feedback_nav(fb_step == 0, step == "words")

## NOT NOW (first page) or BACK, and NEXT or SEND, side by side like the debrief's.
func _feedback_nav(first: bool, last: bool) -> void:
	body.add_child(hud._spacer(10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	fb_back = hud.button("NOT NOW" if first else "BACK", func() -> void:
		command.emit("tap")
		if fb_step == 0: _close_questions()
		else: _feedback_go(fb_step - 1), Vector2(0, 80), "secondary")
	fb_back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fb_back.size_flags_stretch_ratio = 0.62
	row.add_child(fb_back)
	fb_next = hud.button("SEND" if last else "NEXT", _feedback_next, Vector2(0, 80), "primary")
	fb_next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(fb_next)
	body.add_child(row)

func _feedback_next() -> void:
	var steps: Array[String] = _feedback_steps()
	if fb_step < steps.size() and steps[fb_step] == "words":
		_keep_words()
		var email: String = str(fb.get("email", ""))
		if email != "" and not Feedback.looks_like_email(email):
			if fb_error != null: fb_error.show()
			command.emit("deny")
			return
		fb_result = "sending"
		command.emit("tap")
		if feedback != null: feedback.submit(fb)
		_feedback_go(steps.size())
		return
	command.emit("tap")
	_feedback_go(fb_step + 1)

## What was written in the fields so far, kept while the pages turn.
func _keep_words() -> void:
	if fb_comment != null and is_instance_valid(fb_comment): fb["comment"] = fb_comment.text.strip_edges()
	if fb_email != null and is_instance_valid(fb_email): fb["email"] = fb_email.text.strip_edges()

## One question: its line, then its answers as ruled boxes, `columns` across. A second tap takes an answer back.
func _question(line: String, key: String, options: Array, columns: int, letter_px: int = 20) -> void:
	_caption(line)
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 0)
	body.add_child(grid)
	var keys: Dictionary = {}
	for option: Array in options:
		var value: Variant = option[0]
		var k := HUD.PaperKey.new()
		k.word = str(option[1])
		k.look = "segment"
		k.letter_px = letter_px
		k.custom_minimum_size = Vector2(0, HUD.MIN_TOUCH)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		k.chosen = fb.has(key) and fb[key] == value
		k.pressed.connect(_answer.bind(key, value))
		grid.add_child(k)
		keys[value] = k
	fb_keys[key] = keys

func _caption(line: String) -> void:
	var l: Label = hud.ink(line, 18, "semi", 2, 0.85)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(l)

func _answer(key: String, value: Variant) -> void:
	if fb.has(key) and fb[key] == value: fb.erase(key)
	else: fb[key] = value
	command.emit("tap")
	var keys: Dictionary = fb_keys.get(key, {})
	for v: Variant in keys: (keys[v] as HUD.PaperKey).chosen = fb.has(key) and fb[key] == v

func _text_field(value: String, length: int, hint: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = value
	edit.max_length = length
	edit.placeholder_text = hint
	edit.custom_minimum_size = Vector2(0, HUD.MIN_TOUCH)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_field(edit)
	edit.add_theme_font_size_override("font_size", 22)
	edit.add_theme_color_override("font_placeholder_color", Color(INK, 0.4))
	edit.focus_entered.connect(_queue_layout)
	edit.focus_exited.connect(_queue_layout)
	return edit

## The look of a writing field on the dossier: ink on a pale box, brass-rimmed while it has the keyboard.
func _style_field(edit: LineEdit) -> void:
	edit.add_theme_font_override("font", Kit.face("semi", 3))
	edit.add_theme_font_size_override("font_size", 26)
	edit.add_theme_color_override("font_color", INK)
	edit.add_theme_color_override("caret_color", INK)
	edit.add_theme_color_override("selection_color", Color(BRASS, 0.45))
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 0.22)
	box.border_color = Color(INK, 0.55)
	box.set_border_width_all(2)
	box.set_content_margin_all(10)
	edit.add_theme_stylebox_override("normal", box)
	var lit: StyleBoxFlat = box.duplicate()
	lit.border_color = BRASS.darkened(0.2)
	edit.add_theme_stylebox_override("focus", lit)

## After SEND: thanks, how the sending went (feedback.gd answers through feedback_sent), and what comes next.
func _fill_feedback_thanks() -> void:
	sheet_page.text = "REPORT"
	sheet_title.text = "THANK YOU"
	fb_status = hud.ink(_feedback_line(), 20, "type", 0, 0.9)
	fb_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(fb_status)
	body.add_child(hud._spacer(6))
	var more: Label = hud.ink(Missions.more(), 20, "type", 0, 0.9)
	more.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(more)
	body.add_child(hud._spacer(10))
	fb_next = hud.button("BACK TO THE OPERATION" if over_game else "MAIN MENU", func() -> void:
		command.emit("tap")
		_close_questions(), Vector2(0, 80), "primary")
	body.add_child(fb_next)

func _feedback_line() -> String:
	match fb_result:
		"sending": return "Sending your answers…"
		"saved": return "Saved on this device: your answers go out the next time the game is online."
		_: return "Your answers are on file. Thank you for playing %s." % Missions.brand()

## feedback.gd's answer to the questions.
func feedback_sent(answer: Dictionary) -> void:
	var error: String = str(answer.get("error", ""))
	fb_result = "sent" if bool(answer.get("ok", false)) or not error in ["offline", "network", "too often", "server"] else "saved"
	if fb_status != null and is_instance_valid(fb_status): fb_status.text = _feedback_line()

