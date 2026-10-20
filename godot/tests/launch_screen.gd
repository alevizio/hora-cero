extends SceneTree
## Hora Cero's launch screen (scripts/three_d/front.gd) and the answers to its questions (scripts/feedback.gd),
## headless and offline: the list (the Plaza de Mayo, then Riachuelo, the second opened by winning the first), the
## name and the line under it from one place, Spanish to start with and ES / EN on the launch screen itself; the
## questions offered only when a feedback address is configured, and what would be posted to it (nothing goes
## anywhere without one); the launch screen and its pages at the reference sizes; the questions from the pause menu
## over the paused level (which carries on after) and after the last level is won; and all of it in Spanish.
## Run: godot --headless --path godot --script res://tests/launch_screen.gd
const HUD = preload("res://scripts/three_d/hud.gd")
const Front = preload("res://scripts/three_d/front.gd")
const Feedback = preload("res://scripts/feedback.gd")
const Missions = preload("res://scripts/missions.gd")
const Lang = preload("res://scripts/lang.gd")
const PROGRESS := "user://launch_screen_progress.cfg"
const SIZES := [Vector2i(1280, 800), Vector2i(720, 1080), Vector2i(844, 390), Vector2i(390, 844)]
## An address for the answers, for the time of the test (nothing is sent: the test's Spy, and --script runs are offline).
const ADDRESS := "https://feedback.example/answers"

## The answers' client with the network taken out: every post is noted and answered ok.
class Spy extends "res://scripts/feedback.gd":
	var posts: Array = []
	func _post(payload: Dictionary, done: Callable) -> void:
		if not enabled():
			done.call_deferred({"ok": false, "error": "nowhere"})
			return
		posts.append(payload)
		done.call_deferred({"ok": true})

var main: Node
var checks: int = 0
var failures: int = 0

func _init() -> void:
	call_deferred("run")

func check(value: bool, label_text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label_text)

func frames(n: int) -> void:
	for i in range(n): await process_frame

func press(b: BaseButton) -> void:
	b.pressed.emit()

func run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESS))
	_list()
	await _feedback()
	Front.force = 1
	root.size = Vector2i(1280, 720)
	Feedback.address = ""
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	check(main.hud.progress_path == Missions.PROGRESS, "the game keeps its progress in its own file (%s)" % main.hud.progress_path)
	main.hud.progress_path = PROGRESS
	main.hud.load_progress()
	main.front.open()
	await frames(10)
	await _title()
	Feedback.address = ADDRESS
	await _layout()
	await _pause_questions()
	await _won()
	await _spanish()
	main.queue_free()
	await frames(2)
	Front.force = -1
	Feedback.address = ""
	Missions.choose("plaza", false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESS))
	print("LAUNCH_SCREEN_CHECKS=", checks, " FAILURES=", failures)
	quit(0 if failures == 0 else 1)

## The Plaza de Mayo, then Riachuelo; the game's name, its line and its words for what comes next, from one place.
func _list() -> void:
	var ids: Array = Missions.LIST.map(func(e: Dictionary) -> String: return str(e.id))
	check(ids == ["plaza", "riachuelo"], "the list holds the Plaza de Mayo, then Riachuelo (%s)" % str(ids))
	check(Missions.current == "plaza" and Missions.path() == "res://data/plaza.json", "the Plaza de Mayo chosen from the start")
	var none := ConfigFile.new()
	check(Missions.unlocked("plaza", none) and not Missions.unlocked("riachuelo", none), "the plaza open, Riachuelo shut until the plaza is won")
	var won := ConfigFile.new()
	won.set_value("won", "plaza", true)
	check(Missions.unlocked("riachuelo", won) and Missions.completed("plaza", won), "winning the plaza opens Riachuelo")
	check(Missions.next_of("plaza") == "riachuelo" and Missions.next_of("riachuelo") == "" and Missions.last() == "riachuelo", "the plaza leads on to Riachuelo, the last")
	Missions.choose("elsewhere", false)
	check(Missions.current == "plaza", "choosing a level the game does not have does nothing")
	check(Missions.progress_path() == "user://horacero_progress.cfg", "a progress file of its own (%s)" % Missions.progress_path())
	check(Missions.title() == "Invasión Buenos Aires" and str(Missions.GAME.title) == Missions.title(), "its line, from one place (%s)" % Missions.title())
	check(Missions.brand() == "Hora Cero", "its own name (%s)" % Missions.brand())
	check(str(Missions.SOON.tab) == "MORE LEVELS" and Missions.more() == "More levels are on the way, following the comic book." and Missions.ask() == "WOULD YOU PLAY MORE LEVELS LIKE THESE?", "more levels to come")
	Lang.use("es")
	for pair: Array in [["HORA CERO  /  FIELD OPERATIONS", "HORA CERO  /  OPERACIONES DE CAMPO"], ["MORE LEVELS", "MÁS NIVELES"],
			[Missions.more(), "Vienen más niveles, siguiendo la historieta."], [Missions.ask(), "¿JUGARÍAS MÁS NIVELES COMO ESTOS?"],
			["Only to tell you when %s launches." % Missions.brand(), "Solo para avisarte cuando salga Hora Cero."],
			["Your answers are on file. Thank you for playing %s." % Missions.brand(), "Ya tenemos tus respuestas. Gracias por jugar a Hora Cero."]]:
		check(Lang.lookup(str(pair[0])) == str(pair[1]), "in Spanish: %s" % pair[1])
	Lang.use("en")
	check(Missions.start_lang() == "es" and Missions.lang_keys(), "it starts in Spanish and offers both on its launch screen")
	check(Lang.starting("user://no_such_progress.cfg", Missions.start_lang()) == "es", "a first visit starts in Spanish, whatever the device")
	var chose := ConfigFile.new()
	chose.set_value(Lang.SECTION, Lang.KEY, "en")
	chose.save(PROGRESS)
	check(Lang.starting(PROGRESS, Missions.start_lang()) == "en", "a visitor who picked English keeps English")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESS))

## The answers: nowhere to go without an address (not offered, nothing sent, kept on the device); with one, posted as
## one JSON object of what the pages offer; asked after the last level is won, unless answered after a win already.
func _feedback() -> void:
	Feedback.address = ""
	check(Feedback.url() == "" and not Feedback.enabled(), "this repository configures no feedback address")
	var spy := Spy.new()
	root.add_child(spy)
	await frames(2)
	var after_plaza := ConfigFile.new()
	after_plaza.set_value("won", "plaza", true)
	after_plaza.set_value("won", "riachuelo", true)
	check(not Feedback.due(after_plaza), "without an address the questions are never asked")
	spy.submit({"rating": 4, "would_play_more": "maybe"})
	await frames(3)
	check(spy.posts.is_empty() and spy.state() == "waiting", "answers given anyway are kept on the device, sent nowhere (%s)" % spy.state())
	spy._own.erase_section("feedback")
	# with an address
	Feedback.address = ADDRESS
	check(Feedback.enabled() and Feedback.url() == ADDRESS, "an address turns the questions on")
	check(Feedback.headers().has("Content-Type: application/json"), "the answers go as JSON")
	check(Feedback.build_label() == "dev", "a debug run's build label (%s)" % Feedback.build_label())
	var plaza_only := ConfigFile.new()
	plaza_only.set_value("won", "plaza", true)
	check(not Feedback.due(plaza_only), "the questions wait while Riachuelo is still to play")
	check(Feedback.due(after_plaza), "…and are asked once it is won")
	spy.submit({"rating": 4, "would_play_more": "maybe", "comment": "  Where was the gondola?  ", "email": "", "price_game": "4.99", "favourite": "elsewhere"})
	await frames(3)
	check(spy.posts.size() == 1, "the answers are posted")
	var body: Dictionary = spy.posts[0] if not spy.posts.is_empty() else {}
	check(body.get("rating") == 4 and body.get("would_play_more") == "maybe" and body.get("comment") == "Where was the gondola?" and body.get("email") == null,
		"rating, more levels, the comment trimmed, no email (%s)" % str(body))
	check(body.get("game") == "hora-cero" and body.get("level") == "plaza" and body.get("won") == [] and str(body.get("device", "")).length() >= 32, "the game, the level being played, nothing won yet, the device's id")
	check(not body.has("price_game") and not body.has("favourite") and str(body.get("lang", "")) == "en", "only what the pages offer, and the language")
	check(spy.state() == "sent", "taken (%s)" % spy.state())
	spy._own.set_value("won", "plaza", true)
	spy._own.set_value("won", "riachuelo", true)
	check(Feedback.due(spy._own), "after the last win the questions are asked, even if answered before")
	spy.submit({"rating": 5, "would_play_more": "yes"})
	await frames(3)
	check(spy.posts.size() == 2 and spy.posts[1].get("won") == ["plaza", "riachuelo"] and spy.posts[1].get("rating") == 5, "…and the answers then say both were won")
	check(not Feedback.due(spy._own), "answered after the win: not asked again")
	check(Feedback.looks_like_email("tester@example.com") and not Feedback.looks_like_email("tester@") and not Feedback.looks_like_email("a b@c.d"), "an email that looks like one")
	spy.queue_free()
	Feedback.address = ""

## The launch screen: HORA CERO, PREVIEW and its line under the name; PLAY, SETTINGS, HOW TO PLAY; the questions only
## with an address; ES and EN top right.
func _title() -> void:
	var front: Control = main.front
	check(main.mode == "title" and front.visible and front.page == "", "the game opens on the launch screen")
	check(str(main.sim.data.get("id", "")) == "plaza-05", "over the Plaza de Mayo's own scene (%s)" % str(main.sim.data.get("id", "")))
	check(front.preview_tag() == ["PREVIEW", "INVASIÓN BUENOS AIRES"], "PREVIEW, INVASIÓN BUENOS AIRES under the name (%s)" % str(front.preview_tag()))
	var first: Front.MenuItem = front.items["continue"]
	check(first.caption == "PLAY" and first.sub.contains("PLAZA DE MAYO"), "PLAY: the Plaza de Mayo (%s / %s)" % [first.caption, first.sub])
	check((front.items["settings"] as Control).visible and (front.items["howto"] as Control).visible, "SETTINGS and HOW TO PLAY")
	check(not (front.items["feedback"] as Control).visible and front._shown_items() == 3, "no address: no questions on the menu, three lines (%d)" % front._shown_items())
	front.open("feedback")
	await frames(2)
	check(front.page == "", "…and they do not open")
	Feedback.address = ADDRESS
	front.open()
	await frames(2)
	var ask: Front.MenuItem = front.items["feedback"]
	check(ask.visible and ask.caption == "TELL US WHAT YOU THINK" and front._shown_items() == 4, "with an address: TELL US WHAT YOU THINK, four lines (%d)" % front._shown_items())
	check(front.lang_row != null and front.lang_row.visible and front.lang_row.get_child_count() == 2, "ES and EN on the launch screen")
	var view := Rect2(Vector2.ZERO, front.get_viewport_rect().size)
	check(view.encloses(front.lang_row.get_global_rect()) and not front.lang_row.get_global_rect().intersects(front.menu_box.get_global_rect()), "the keys on the screen, clear of the menu")
	front._open_page("settings")
	await frames(3)
	var fields: int = 0
	var pending: Array[Node] = [front.body]
	while not pending.is_empty():
		var n: Node = pending.pop_back()
		pending.append_array(n.get_children())
		if n is LineEdit: fields += 1
	check(fields == 0, "SETTINGS has nothing to write in: no leaderboard, no callsign")
	front.open()
	await frames(2)
	press(ask)
	await frames(2)
	check(front.page == "feedback" and front.fb_step == 0 and front.sheet_page.text == "REPORT  1 / 2" and not front.over_game, "from the menu: two pages of questions (%s)" % front.sheet_page.text)
	check(front.fb_keys.has("rating") and front.fb_keys.has("would_play_more"), "the first: did you enjoy it, would you play more levels like these")
	press(front.fb_back)
	await frames(2)
	check(front.page == "" and front.visible and main.mode == "title", "NOT NOW: back to the menu")
	# the language keys
	press(front.lang_row.get_child(0))
	await frames(2)
	var saved := ConfigFile.new()
	saved.load(PROGRESS)
	check(Lang.current == "es" and str(saved.get_value(Lang.SECTION, Lang.KEY, "")) == "es" and Front.resume_to == "title", "ES: Spanish, kept, back to the launch screen")
	check(front.preview_tag() == ["ADELANTO", "INVASIÓN BUENOS AIRES"], "the title in Spanish (%s)" % str(front.preview_tag()))
	press(front.lang_row.get_child(1))
	await frames(2)
	check(Lang.current == "en", "EN: English again")
	Front.resume_to = "title"
	Feedback.address = ""

## The menu, the title and the question pages on the screen at the reference sizes, with and without a notch.
func _layout() -> void:
	var front: Control = main.front
	var cases: Array = []
	for dims: Vector2i in SIZES: cases.append([dims, null])
	cases.append([Vector2i(844, 390), Vector4(110, 0, 110, 30)])
	cases.append([Vector2i(390, 844), Vector4(0, 109, 0, 63)])
	for case: Array in cases:
		main.hud.safe_override = case[1]
		root.size = case[0]
		await frames(8)
		front.open()
		await frames(4)
		var view := Rect2(Vector2.ZERO, front.get_viewport_rect().size)
		var ins: Vector4 = main.hud.insets
		var safe := Rect2(Vector2(ins.x, ins.y), view.size - Vector2(ins.x + ins.z, ins.y + ins.w)).grow(0.5)
		var tag: String = str(case)
		var menu: Rect2 = front.menu_box.get_global_rect()
		var title: Rect2 = front.title_art.get_global_rect()
		check(safe.encloses(menu), "%s: the menu inside the safe area (%s in %s)" % [tag, menu, safe])
		check(not menu.intersects(title), "%s: title and menu apart" % tag)
		for step: int in range(3):
			front._start_feedback()
			front.fb = {"rating": 3}
			front.fb_step = step
			front._open_page("feedback")
			await frames(4)
			var box: Control = front.sheet_box
			var drawn := Rect2(box.global_position, box.size * box.scale)
			check(view.grow(0.5).encloses(drawn), "%s page %d: on the screen (%s)" % [tag, step + 1, drawn])
			check(box.scale.x >= (0.55 if view.size.y < view.size.x else 0.9), "%s page %d: drawn at a readable size (%.2f)" % [tag, step + 1, box.scale.x])
			check(front.fb_next != null and front.fb_next.size.y * box.scale.y >= 40.0, "%s page %d: its button a thumb high" % [tag, step + 1])
			for key: String in front.fb_keys:
				for v: Variant in front.fb_keys[key]:
					var k: Control = front.fb_keys[key][v]
					check(k.size.y * box.scale.y >= 40.0 and k.size.x * box.scale.x >= 40.0, "%s: %s %s a thumb wide and high" % [tag, key, str(v)])
	main.hud.safe_override = null
	root.size = Vector2i(1280, 720)
	await frames(8)
	front.open()
	await frames(2)

## Into the Plaza de Mayo; the pause menu asks too, over the paused level, and the level carries on after.
func _pause_questions() -> void:
	var front: Control = main.front
	var hud: Control = main.hud
	var sim: RefCounted = main.sim
	press(front.items["continue"])
	await frames(2)
	check(main.mode == "game" and hud.current_modal == "briefing" and hud.menu_questions != null and not hud.menu_questions.visible, "PLAY: the Plaza de Mayo's briefing")
	press(hud.begin_button)
	await frames(2)
	for i in range(20): main._process(0.05)
	check(sim.phase == "playing" and sim.time > 0.0, "the level runs")
	main._command("menu")
	await frames(2)
	var ask: Button = hud.menu_buttons["questions"]
	check(hud.current_modal == "menu" and hud.menu_questions.visible and ask.is_visible_in_tree() and ask.text == "TELL US WHAT YOU THINK", "the pause menu: TELL US WHAT YOU THINK")
	var view := Rect2(Vector2.ZERO, hud.get_viewport_rect().size)
	check(view.grow(0.5).encloses(ask.get_global_rect()), "…on the screen")
	var clock: float = sim.time
	press(ask)
	await frames(2)
	check(front.visible and front.over_game and front.page == "feedback" and front.fb_step == 0, "the questions over the level")
	check(main.mode == "game" and sim.phase == "playing" and sim.paused, "…which waits, paused")
	press(front.fb_keys["rating"][2])
	press(front.fb_next)
	await frames(2)
	check(front.fb_step == 1 and front.fb_comment != null and front.fb_email != null and front.fb_next.text == "SEND", "the second page: your words, an email, SEND")
	main._shortcut(KEY_ESCAPE)
	await frames(2)
	check(front.visible and front.fb_step == 0 and int(front.fb.get("rating", 0)) == 2, "Esc: a page back, the answer kept")
	main._shortcut(KEY_ESCAPE)
	await frames(2)
	check(not front.visible and not front.over_game and hud.overlay.visible and hud.current_modal == "menu" and main.mode == "game", "Esc on the first page: back to the pause menu")
	check(sim.paused and sim.time == clock and not hud.progress.has_section_key("feedback", "pending"), "the clock where it was, nothing filed")
	press(ask)
	await frames(2)
	press(front.fb_keys["rating"][3])
	press(front.fb_keys["would_play_more"]["maybe"])
	press(front.fb_next)
	await frames(2)
	check(front.fb_comment.max_length >= 1000, "room for a long comment")
	front.fb_comment.text = "I did not see that the tram takes them all at once."
	front.fb_email.text = ""
	press(front.fb_next)
	await frames(3)
	var filed: Dictionary = hud.progress.get_value("feedback", "pending", {})
	var sent: bool = bool(hud.progress.get_value("feedback", "sent", false))
	check(front.sheet_title.text == "THANK YOU" and (int(filed.get("rating", 0)) == 3 or sent), "SEND: filed (%s)" % str(filed))
	check(filed.is_empty() or (filed.get("would_play_more") == "maybe" and str(filed.get("comment", "")).contains("tram")), "…the answers as given")
	var body: Dictionary = Feedback.body(filed, "s".repeat(40), main.feedback.won())
	check(body.won == [] and body.level == "plaza" and body.email == null, "what goes: nothing won yet, the plaza being played, no email")
	var more_line: bool = false
	for child: Node in front.body.get_children():
		if child is Label and (child as Label).text == Missions.more(): more_line = true
	check(more_line and front.fb_next.text == "BACK TO THE OPERATION", "thanks, more levels to come, and BACK TO THE OPERATION")
	press(front.fb_next)
	await frames(2)
	check(not front.visible and hud.current_modal == "menu" and hud.overlay.visible and sim.paused, "back to the pause menu")
	press(hud.begin_button)
	await frames(2)
	for i in range(10): main._process(0.05)
	check(sim.phase == "playing" and not sim.paused and sim.time > clock and not hud.overlay.visible, "RESUME: the level carries on (%.2f > %.2f)" % [sim.time, clock])

## Win the plaza: its real story, then NEXT OPERATION opens Riachuelo; win that: after its story, the questions.
func _won() -> void:
	var hud: Control = main.hud
	var sim: RefCounted = main.sim
	sim.time = 300.0
	sim.phase = "won"
	main._process(0.05)
	await frames(3)
	for i in range(40):
		if hud.current_modal == "won" and hud.overlay.visible: break
		main._process(0.05)
		await process_frame
	check(hud.current_modal == "won" and Missions.completed("plaza", hud.progress), "the plaza's debrief, the win on file")
	check(not hud.modal_body.text.to_lower().contains("leaderboard"), "the debrief says nothing of a leaderboard")
	check(not Feedback.due(hud.progress), "no questions yet: Riachuelo is next")
	check(hud.second_button.text == "THE REAL STORY", "the plaza's real story first")
	press(hud.second_button)
	await frames(2)
	for i in range((sim.data.get("history", []) as Array).size() - 1):
		press(hud.second_button)
		await frames(2)
	check(hud.second_button.text == "NEXT OPERATION", "the story's last page: NEXT OPERATION (%s)" % hud.second_button.text)
	press(hud.second_button)
	await frames(2)
	check(Missions.current == "riachuelo" and Missions.unlocked("riachuelo", hud.progress), "NEXT OPERATION: Riachuelo, open now")
	# the scene starts over on Riachuelo
	main.queue_free()
	await frames(2)
	Front.force = 0
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	main.hud.progress_path = PROGRESS
	main.hud.load_progress()
	await frames(8)
	hud = main.hud
	sim = main.sim
	var front: Control = main.front
	check(str(sim.data.get("id", "")) == "riachuelo-04", "Riachuelo's own scene (%s)" % str(sim.data.get("id", "")))
	press(hud.begin_button)
	await frames(2)
	sim.time = 300.0
	sim.phase = "won"
	main._process(0.05)
	await frames(3)
	for i in range(40):
		if hud.current_modal == "won" and hud.overlay.visible: break
		main._process(0.05)
		await process_frame
	check(hud.current_modal == "won" and Missions.completed("riachuelo", hud.progress), "Riachuelo's debrief, the win on file")
	check(hud.second_button.text == "THE REAL STORY" and hud.foot.text.contains("a few quick questions"), "after the story, the questions (%s)" % hud.foot.text)
	press(hud.second_button)
	await frames(2)
	for i in range((sim.data.get("history", []) as Array).size() - 1):
		press(hud.second_button)
		await frames(2)
	check(hud.current_modal == "history" and hud.second_button.text == "TELL US WHAT YOU THINK", "the story's last page: TELL US WHAT YOU THINK (%s)" % hud.second_button.text)
	press(hud.second_button)
	await frames(3)
	check(main.mode == "title" and front.visible and front.page == "feedback" and front.fb_step == 0 and not front.over_game, "…on the launch screen's paper")
	press(front.fb_keys["rating"][5])
	press(front.fb_keys["would_play_more"]["yes"])
	press(front.fb_next)
	await frames(2)
	front.fb_comment.text = "More of the comic, please."
	front.fb_email.text = "tester@example.com"
	press(front.fb_next)
	await frames(3)
	var filed: Dictionary = hud.progress.get_value("feedback", "pending", {})
	var body: Dictionary = Feedback.body(filed, "s".repeat(40), main.feedback.won())
	check(body.won == ["plaza", "riachuelo"] and body.rating == 5 and body.would_play_more == "yes" and body.email == "tester@example.com", "the answers say both were won (%s)" % str(body))
	check(front.fb_next.text == "MAIN MENU" and not Feedback.due(hud.progress), "MAIN MENU, and not asked again")
	press(front.fb_next)
	await frames(2)
	check(front.page == "" and (front.items["feedback"] as Control).visible and front._shown_items() == 4, "the menu, still offering the questions")
	Front.force = 1

## Every word of the launch screen, the questions (from the menu and over the game) and SETTINGS in Spanish.
func _spanish() -> void:
	var front: Control = main.front
	main._command("title")
	await frames(2)
	Lang.use("es")
	# (what was already on screen turns to Spanish first: the level's own words are not this suite's business)
	await frames(3)
	Lang.record = true
	Lang.misses.clear()
	front.open()
	await frames(3)
	for over: bool in [false, true]:
		if over: front.open_questions_over_game()
		else: front._start_feedback()
		for step: int in range(3):
			front.fb_step = step
			front._open_page("feedback")
			await frames(3)
		front.open()
		await frames(2)
	front._open_page("settings")
	await frames(3)
	front.open()
	check(Lang.misses.is_empty(), "the launch screen and the questions all in Spanish: %s" % str(Lang.misses.keys()))
	Lang.record = false
	check(tr(HUD.QUESTIONS) == "CONTANOS QUÉ TE PARECIÓ", "the pause menu's line in Spanish")
	for line: String in ["After the real story, a few quick questions from the people making the game.", "BACK TO THE OPERATION", "MORE LEVELS",
			"WHAT CONFUSED YOU, OR WHAT WOULD YOU CHANGE?", Front.LEAD, Missions.more()]:
		check(Lang.lookup(line) != line, "in Spanish: %s" % line)
	for card: Dictionary in HUD.HOWTO:
		check(Lang.lookup(str(card.line)) != str(card.line), "HOW TO PLAY in Spanish: %s" % card.line)
	Lang.use("en")
	front.open()
	await frames(2)
