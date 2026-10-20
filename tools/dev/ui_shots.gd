extends SceneTree
## Dev-only: photographs the HUD's screens (dossier pages and the game with its banners) at one window size, in
## the language and operation the environment asks for, to look at a translation or a layout by eye.
## Run (rendered, not headless):
##   HORACERO_LANG=es HORACERO_MISSION=riachuelo xvfb-run -a -s "-screen 0 1700x1100x24" godot --path godot \
##     --rendering-driver opengl3 --script ../tools/dev/ui_shots.gd -- <out dir> <width> <height> [state ...]
## States: title settings (the launch screen) briefing howto play command menu won history lost (all of them when
## none is named); history2.. for the later pages of the real story. The questions (shown with a stand-in feedback
## address, nothing is sent): questions (the menu with its line), feedback1, feedback2 (each page, sample answers
## chosen), thanks.
const ALL := ["title", "settings", "briefing", "howto", "play", "command", "menu", "won", "history", "lost"]
const LAUNCH := ["title", "settings", "questions", "feedback1", "feedback2", "thanks"]
const ANSWERS := {"rating": 4, "would_play_more": "maybe", "comment": "More of the comic, please.", "email": "you@example.com"}
const PROGRESS := "user://ui_shots_progress.cfg"
var main: Node

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/ui_shots"
	var dims := Vector2i(int(args[1]) if args.size() > 1 else 1280, int(args[2]) if args.size() > 2 else 720)
	var states: Array = Array(args.slice(3)) if args.size() > 3 else ALL
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESS))
	root.size = dims
	var Front: GDScript = load("res://scripts/three_d/front.gd")
	Front.set("force", 0)
	(load("res://scripts/feedback.gd") as GDScript).set("address", "https://feedback.example/answers")
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	main.hud.progress_path = PROGRESS
	main.hud.load_progress()
	for i in range(10): await process_frame
	for state: String in states:
		# "history2".."history9": that page of the real story (stage it as "history", then turn to it)
		var page: int = int(state.substr(7)) - 1 if state.begins_with("history") and state.length() > 7 else 0
		if page > 0: state = "history"
		stage(state)
		main.hud.refresh()
		for i in range(8 if not state in LAUNCH else 40): await process_frame
		# a win that plays a closing scene first: skip it, as a tap would, then the page asked for
		if state in ["won", "history"] and main.world.finale_running():
			main.world.finale.skip()
			for i in range(4): await process_frame
			if state == "history": main.hud.show_history(0)
			else: main.hud.show_modal("won")
			for i in range(6): await process_frame
		elif state == "history":
			# the HUD answers the win with the debrief a frame later: turn to the page after it, as a tap would
			main.hud.show_history(page)
			for i in range(4): await process_frame
		if not state in LAUNCH: main.hud.refresh()
		await RenderingServer.frame_post_draw
		var shot: String = state + (str(page + 1) if page > 0 else "")
		root.get_texture().get_image().save_png("%s/%s.png" % [out, shot])
		print("SHOT ", shot)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESS))
	quit()

func stage(state: String) -> void:
	var sim: RefCounted = main.sim
	var hud: Control = main.hud
	if state in ["questions", "thanks"] or state.begins_with("feedback"):
		var last: String = str(main.front.Missions.LIST[main.front.Missions.LIST.size() - 1].id)
		hud.progress.set_value("won", last, true)
		if hud.progress.has_section("feedback"): hud.progress.erase_section("feedback")
		if state == "questions":
			main._enter_title("")
			return
		main._enter_title("feedback")
		main.front.fb = ANSWERS.duplicate()
		main.front.fb_result = "sent"
		main.front.fb_step = main.front._feedback_steps().size() if state == "thanks" else int(state.substr(8)) - 1
		main.front._open_page("feedback")
		return
	if state in LAUNCH:
		main._enter_title("" if state == "title" else state)
		return
	if main.mode == "title": main._leave_title("briefing")
	if state in ["briefing", "howto"]:
		main._command("restart")
		if state == "howto": hud.show_modal("howto")
		return
	main._command("restart_now")
	var first: String = str(sim.units[0].id)
	match state:
		"play":
			sim.select(first)
			hud.hint(str(sim.data.get("copy", {}).get("hintsWhen", {}).keys().front()) if sim.data.get("copy", {}).has("hintsWhen") else "informant")
			var names: Dictionary = sim.data.get("copy", {}).get("checkpoints", {})
			hud.show_toast("CHECKPOINT  ·  %s" % str(names.values().back() if not names.is_empty() else "informant freed").to_upper())
			sim.select(first)
			sim.move_to(Vector2(sim.units[0].x, sim.units[0].y) + Vector2(400, 0))
			hud._toast_until = Time.get_ticks_msec() + 60000.0
			hud._notice_until = Time.get_ticks_msec() + 60000.0
		"command":
			main._command("pause")
			sim.select(first)
		"menu": main._command("menu")
		"won":
			sim.phase = "won"
			hud.show_modal("won")
		"history":
			sim.phase = "won"
			hud.show_history(0)
		"lost":
			sim._lose("%s was shot dead by a guard." % str(sim.units[0].name))
			hud.show_modal("lost")
