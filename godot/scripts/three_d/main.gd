extends Node3D
## Native 3D entry point: owns the Simulation, the camera, every input and the flow of the game.
## The shared deterministic mission stays on a ground plane; orders go in through sim.perform().
##
## A tap in the world, in this order of precedence (see _world_tap):
##   pebble armed            the ground point is the target
##   gun or takedown armed   a guard under the finger gets it; anything else lowers the weapon, and
##                           never moves anybody
##   own operative           select him (tap the selected one again to halt him)
##   a living guard          the selected operative's takedown (knife / bind)
##   a body                  lift it
##   a thing or its marker   its order from sim.interactables(): gate, wire, generator, tripwire,
##                           informant, a bush while carrying, the boat
##   open ground             move (inside a bush while carrying: carry it in and put it down)
##
## Desktop shortcuts mirror the buttons: Space plan/execute · 1 2 3 4 5 Tab select · C stance · A takedown ·
## G gun · D pebble or tripwire · E context · Z halt · F whole map · Q R turn the view ·
## Esc lower the weapon, else menu · M menu · K save checkpoint · L load checkpoint.
const Simulation = preload("res://scripts/simulation.gd")
const World = preload("res://scripts/three_d/world.gd")
const HUD = preload("res://scripts/three_d/hud.gd")
const Missions = preload("res://scripts/missions.gd")
const Lang = preload("res://scripts/lang.gd")
const Front = preload("res://scripts/three_d/front.gd")
const Feedback = preload("res://scripts/feedback.gd")
const ComicInk = preload("res://scripts/three_d/ink.gd")
## Stop the clock by itself the moment an alarm goes up, so a phone player gets a beat to react.
const AUTO_COMMAND_ON_ALARM: bool = true
## Finger-sized hit radii in logical pixels (1 px is about 0.1 mm on a 6-inch phone).
const TAP_UNIT: float = 46.0
const TAP_SELF: float = 28.0
const TAP_GUARD: float = 46.0
const TAP_BODY: float = 42.0
const TAP_THING: float = 44.0
## Height (m) of the point a tap is measured against, per kind of tappable thing.
const THING_HEIGHT := {"gate":0.9,"informant":0.9,"fence":0.8,"radio":0.7,"trap":0.1,"rope":0.3,"civilian":0.9,"phone":1.4,"evidence":0.1,"person":0.9,"fallen":0.5,"canvas":0.7,"tram":1.6}
var sim: RefCounted
var world: Node3D
var camera: Camera3D
var hud: Control
## The launch screen (front.gd) and the answers to its questions (feedback.gd).
var front: Control
var feedback: Node
var ui_layer: CanvasLayer
## "title" while the launch screen is up (the scene runs behind it, nobody playing), else "game".
var mode: String = "game"
var _title_clock: float = 0.0
var target:=Vector3(19.5,0,13.0)
var desired_target:=Vector3(19.5,0,13.0)
var yaw: float=PI/4
var desired_yaw: float=PI/4
var zoom: float=29.0
var desired_zoom: float=29.0
var pitch: float=deg_to_rad(52)
## What the next tap in the world does: "" (the usual), "takedown", "shoot" or "distract".
## Mirrored to the HUD (hud.armed) and to the world layer (world.armed_action, world.aiming).
var armed: String=""
## Set false to keep the clock running when an alarm starts (scripted runs do).
var auto_command_on_alarm: bool=AUTO_COMMAND_ON_ALARM
var last_phase: String=""
var hud_timer: float=0.0
var briefing_was_running: bool=false
var pointer_start:=Vector2.ZERO
var pointer_last:=Vector2.ZERO
var mouse_held: bool=false
var mouse_dragged: bool=false
var touch_positions: Dictionary={}
var touch_starts: Dictionary={}
var touch_moved: Dictionary={}
var multi_touch: bool=false
var resize_pending: bool=false
# Best candidate of the tap being resolved (see _scan).
var _hit_kind: String=""
var _hit_id: String=""
var _hit_score: float=INF
var _hit_thing: Dictionary={}

## The map in metres and the camera's limits for the current mission (data "camera", else from the map size).
var map_size:=Vector2(40,25)
var camera_min:=Vector2(4,1)
var camera_max:=Vector2(39,24)
var camera_home:=Vector3(19.5,0,13.0)
var zoom_home: float=29.0
var zoom_max: float=64.0
## The finger's own target during a drag, unclamped; INF between gestures. Past the map's edge the camera
## follows it at EDGE_GIVE of the speed and no farther than EDGE_REACH, and eases back when the finger lifts.
var _pan_raw: Vector3=Vector3.INF
const EDGE_GIVE: float=0.35
const EDGE_REACH: float=2.5

func _ready() -> void:
	Missions.boot()
	Lang.boot(Missions.progress_path(),Missions.start_lang())
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(Missions.path()))
	if not data is Dictionary:
		push_error("Mission data could not be loaded")
		return
	data=Lang.translate_data(data)
	_read_camera(data)
	sim=Simulation.new(data)
	world=World.new()
	world.sim=sim
	world.name=str(data.get("worldName","CoastalOutpost"))
	add_child(world)
	camera=Camera3D.new()
	camera.name="TacticalCamera"
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.near=0.1
	camera.far=160.0
	camera.keep_aspect=Camera3D.KEEP_HEIGHT
	camera.current=true
	add_child(camera)
	_update_camera(1.0,true)
	ui_layer=CanvasLayer.new()
	ui_layer.name="TacticalInterface"
	add_child(ui_layer)
	hud=HUD.new()
	hud.sim=sim
	hud.camera=camera
	hud.command.connect(_command)
	hud.select_operative.connect(_select)
	hud.map_focus.connect(_focus_ground)
	hud.slot_pressed.connect(_slot)
	ui_layer.add_child(hud)
	world.sim_event.connect(_on_sim_event)
	feedback=Feedback.new()
	feedback.name="Feedback"
	feedback.source=hud
	add_child(feedback)
	var front_layer:=CanvasLayer.new()
	front_layer.name="LaunchScreen"
	front_layer.layer=2
	add_child(front_layer)
	front=Front.new()
	front.hud=hud
	front.sim=sim
	front.feedback=feedback
	front.command.connect(_front_command)
	front_layer.add_child(front)
	feedback.feedback_sent.connect(front.feedback_sent)
	_apply_settings()
	get_viewport().size_changed.connect(_resize)
	_resize()
	world.update_visuals(0.1)
	var landing: String=Front.landing()
	if landing!="briefing": _enter_title("" if landing=="title" else landing)

## How far the 1280 x 720 design canvas shrinks on a small screen, so that type and buttons come out larger
## there. A logical pixel is kept at UI_MIN_POINT points or more: a phone (about 390 points on its short side)
## gets a canvas about 10% smaller, an iPad or a desktop window the full one.
const UI_MIN_POINT: float=0.6
## The player's text size (small, medium, large) as a further factor on the canvas: smaller canvas, larger interface.
const TEXT_CANVAS: Array[float]=[1.14,1.0,0.86]
## The smallest logical canvas the HUD is laid out for: width when upright, height when landscape.
const UPRIGHT_MIN_WIDTH: float=640.0
const LANDSCAPE_MIN_HEIGHT: float=540.0
## Width the top row needs between the safe edges: readout, the widest banner, the menu keys.
const TOP_ROW_MIN: float=1060.0
## Pixels per point of the screen; 0 asks the display. Tools set it to stage a phone on a desktop.
var screen_scale: float=0.0
## The browser build lays out by the size of the browser window instead of stretching the phone design to
## fill it: a bigger window shows more of the outpost and keeps the kit at a steady size on screen.
## -1 asks the platform; tools and tests set 0 or 1 to stage it.
var web_layout: int=-1
## Logical pixels per CSS pixel in the browser: a little over one, so the kit sits a touch smaller than the
## phone-sized design and the world gets the room.
const WEB_DENSITY: float=1.1
## How much more of the world the browser shows than the 720-high design, at most.
const WEB_WORLD_MAX: float=1.8
## In the browser: how much wider the camera looks than the design does (1 = as on a phone). Set on resize.
var world_scale: float=1.0
## In the browser, the 3D picture is drawn at no more than about this many pixels and scaled up, so a large
## high-density window stays smooth; the interface on top stays sharp.
const WEB_3D_PIXELS: float=3686400.0

func is_web() -> bool:
	return web_layout==1 or (web_layout==-1 and OS.has_feature("web"))
func ui_compaction(window: Vector2i) -> float:
	var per_point: float=screen_scale if screen_scale>0.0 else DisplayServer.screen_get_scale()
	var points: float=float(mini(window.x,window.y))/maxf(per_point,1.0)
	return clampf(points/(720.0*UI_MIN_POINT),0.84,1.0)

func _resize() -> void:
	if resize_pending: return
	resize_pending=true
	call_deferred("_apply_resize")

func _apply_resize() -> void:
	resize_pending=false
	var actual: Vector2i=get_window().size
	if is_web():
		_apply_web_resize(actual)
		return
	world_scale=1.0
	var base:=Vector2(720,1080) if actual.y>actual.x else Vector2(1280,720)
	# Never so small a canvas that the kit no longer fits: an upright phone needs the bar beside the photos,
	# a landscape one room for the banner between the readout and the menu keys, inside the safe area.
	var floor_k: float=(UPRIGHT_MIN_WIDTH if actual.y>actual.x else LANDSCAPE_MIN_HEIGHT)/720.0
	if actual.x>=actual.y and actual.y>0:
		var aspect: float=float(actual.x)/float(actual.y)
		var ins: Vector4=hud.safe_insets()
		if hud.safe_override is Vector4:
			# Insets given in logical pixels (tests): they stay that size whatever the canvas.
			floor_k=maxf(floor_k,(TOP_ROW_MIN+maxf(18.0,ins.x)+maxf(18.0,ins.z))/(720.0*aspect))
		else:
			var unsafe: float=clampf((maxf(18.0,ins.x)+maxf(18.0,ins.z))/maxf(get_viewport().get_visible_rect().size.x,1.0),0.0,0.5)
			floor_k=maxf(floor_k,TOP_ROW_MIN/(720.0*aspect*(1.0-unsafe)))
	var k: float=clampf(ui_compaction(actual)*TEXT_CANVAS[hud.text_size()],floor_k,1.2)
	var logical:=Vector2i((base*k).round())
	if get_window().content_scale_size!=logical: get_window().content_scale_size=logical
	hud.layout()

## The browser: the canvas follows the window at WEB_DENSITY logical pixels per CSS pixel (times the text size),
## never smaller than the HUD needs, and the camera widens with the window.
func _apply_web_resize(actual: Vector2i) -> void:
	var dpr: float=maxf(screen_scale if screen_scale>0.0 else DisplayServer.screen_get_scale(),1.0)
	var css:=Vector2(maxi(actual.x,1),maxi(actual.y,1))/dpr
	var f: float=WEB_DENSITY*TEXT_CANVAS[hud.text_size()]
	if css.y>css.x:
		f=maxf(f,UPRIGHT_MIN_WIDTH/css.x)
	else:
		var ins: Vector4=hud.safe_override if hud.safe_override is Vector4 else Vector4.ZERO
		f=maxf(f,maxf(LANDSCAPE_MIN_HEIGHT/css.y,(TOP_ROW_MIN+maxf(18.0,ins.x)+maxf(18.0,ins.z))/css.x))
	var logical:=Vector2i((css*f).round())
	if get_window().content_scale_size!=logical: get_window().content_scale_size=logical
	# The world: as much more as the window is bigger than the design, by the window alone (not the text size).
	world_scale=clampf(minf(css.x,css.y)*WEB_DENSITY/720.0,1.0,WEB_WORLD_MAX)
	var pixels: float=float(actual.x)*float(actual.y)
	get_viewport().scaling_3d_scale=clampf(sqrt(WEB_3D_PIXELS/maxf(pixels,1.0)),0.6,1.0)
	hud.layout()
	_update_camera(1.0,true)

func _process(dt: float) -> void:
	if sim==null: return
	if mode=="title":
		# the post at night with nobody playing: the guards on their rounds, the camera drifting along
		sim.idle(dt)
		world.update_visuals(dt)
		_title_camera(dt)
		_update_camera(dt)
		return
	sim.update(dt)
	world.aiming=armed=="distract"
	world.update_visuals(dt)
	_update_camera(dt)
	if sim.phase!=last_phase:
		last_phase=sim.phase
		if sim.phase in ["won","lost"]:
			_arm("",true)
			if sim.phase=="won" and world.has_finale():
				# the closing scene first; the debrief when it is over (or skipped)
				if not world.finale.finished.is_connected(_on_finale_finished): world.finale.finished.connect(_on_finale_finished)
				world.finale.start(self,hud)
			else: hud.show_modal(sim.phase)
	hud_timer+=dt
	if hud_timer>=0.08:
		hud_timer=0
		_check_armed()
		hud.refresh()

func _update_camera(dt: float, instant: bool=false) -> void:
	var t: float=1.0 if instant else minf(dt*10,1.0)
	target=target.lerp(desired_target,t)
	yaw=lerp_angle(yaw,desired_yaw,t)
	zoom=lerpf(zoom,desired_zoom,t)
	# `zoom` is the visible extent across the screen's shorter side, so an upright screen shows people
	# at the same size as a landscape one instead of a sliver of the map.
	var view: Vector2=get_viewport().get_visible_rect().size
	camera.size=zoom*world_scale/minf(1.0,view.x/maxf(1.0,view.y))
	camera.position=target+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*55
	camera.look_at(target,Vector3.UP)

# --- selection, arming, feedback ---------------------------------------------------------------
## Portrait tap: select and bring the camera to him.
func _select(id: String) -> void:
	_select_unit(id,true)

func _select_unit(id: String, focus: bool) -> void:
	if sim.phase!="playing": return
	_arm("",true)
	sim.select(id)
	if focus: _focus_ground(sim.position_of(sim.selected()))
	hud.notify("%s selected · %s" % [sim.selected().name,sim.selected().role],2.5)
	_ui_sound("tap")
	hud.refresh()

## Arms a targeted action ("" lowers it) and tells the HUD and the world layer.
func _arm(action: String, quiet: bool=false) -> void:
	if armed==action: return
	var before: String=armed
	armed=action
	hud.armed=action
	world.aiming=action=="distract"
	world.set("armed_action",action if action in ["shoot","distract"] else "")
	if quiet: return
	if action!="":
		_ui_sound("arm")
		hud.notify("")
	else:
		_ui_sound("tap")
		hud.notify("%s lowered. No shot fired." % str(sim.selected().gun.label) if before=="shoot" else "Cancelled.",2.5)
	hud.refresh()

## Lowers an armed action that can no longer be used (out of rounds, hands full, mission over).
func _check_armed() -> void:
	if armed=="": return
	if sim.phase=="playing":
		for entry: Dictionary in sim.available_actions():
			if entry.id==armed and bool(entry.enabled): return
	_arm("",true)

func _ui_sound(cue: String) -> void:
	var audio: Variant=world.get("audio")
	if audio!=null and audio is Object and audio.has_method("play_ui"): audio.play_ui(cue)

## An order went through (tap) or was refused (deny; the reason is already in the notice line, and the
## operative says no in his own voice).
func _feedback(accepted: bool) -> void:
	_ui_sound("tap" if accepted else "deny")
	if not accepted: _voice_refuse()
	hud.refresh()

func _deny(reason: String) -> void:
	hud.notify(reason if reason!="" else "Not now.")
	_ui_sound("deny")
	_voice_refuse()
	hud.refresh()

func _voice_refuse() -> void:
	var audio: Variant=world.get("audio")
	if audio!=null and audio is Object and audio.has_method("refuse") and sim.selected_id!="": audio.refuse(sim.selected_id)

# --- the action bar -------------------------------------------------------------------------------
func _slot(key: String) -> void:
	if sim.phase!="playing" or hud.overlay.visible: return
	if key=="plan":
		_command("pause")
		return
	var entry: Dictionary=hud.entry_for(key)
	if entry.is_empty() or str(entry.id)=="": return
	var id: String=entry.id
	if armed==id:
		_arm("")
		return
	if not bool(entry.enabled):
		_deny(str(entry.reason))
		return
	# Actions that need a target are armed here and carried out by the next tap in the world; the
	# context slot brings its target with it.
	if key!="context" and str(entry.kind) in ["target_guard","target_point"]:
		_arm(id)
		return
	_arm("",true)
	_feedback(sim.perform(id,entry.get("target")))

# --- flow ------------------------------------------------------------------------------------------
func _focus_ground(point: Vector2) -> void:
	desired_target=Vector3(point.x/32,0,point.y/32)
	_clamp_target()
	desired_zoom=minf(desired_zoom,19.0)

## The first view of an operation when its data asks for one (camera.begin {at, zoom, yaw}): framed as given, then
## moved along the screen just enough that whoever is selected stands well inside it (an upright phone sees less
## across than a landscape screen). False when the data has none: the camera goes to the selected one instead.
func _begin_view() -> bool:
	var spec: Dictionary=sim.data.get("camera",{}).get("begin",{})
	if spec.is_empty(): return false
	var at: Array=spec.get("at",[camera_home.x,camera_home.z])
	desired_target=Vector3(float(at[0]),0,float(at[1]))
	desired_zoom=clampf(float(spec.get("zoom",zoom_home)),10.0,zoom_max)
	desired_yaw=deg_to_rad(float(spec.get("yaw",45.0)))
	var unit: Vector2=sim.position_of(sim.selected())/32.0
	var view: Vector2=get_viewport().get_visible_rect().size
	var ratio: float=view.x/maxf(1.0,view.y)
	var size: float=desired_zoom*world_scale/minf(1.0,ratio)
	# where he stands on the screen (metres across from the middle, and up), and how far from it he may stand
	var d: Vector2=unit-Vector2(desired_target.x,desired_target.z)
	var sy: float=sin(desired_yaw)
	var cy: float=cos(desired_yaw)
	var across: float=d.x*cy-d.y*sy
	var up: float=-(d.x*sy+d.y*cy)*sin(pitch)
	var room: Vector2=Vector2(size*ratio,size)*0.5*float(spec.get("keep",0.7))
	var shift_across: float=across-clampf(across,-room.x,room.x)
	var shift_up: float=up-clampf(up,-room.y,room.y)
	desired_target+=Vector3(cy,0,-sy)*shift_across+Vector3(-sy,0,-cy)*(shift_up/sin(pitch))
	_clamp_target()
	return true

func _fit_camera() -> void:
	desired_target=Vector3(map_size.x*0.5,0,map_size.y*0.5)
	var extent_x: float=map_size.x*absf(cos(desired_yaw))+map_size.y*absf(sin(desired_yaw))
	var extent_y: float=(map_size.x*absf(sin(desired_yaw))+map_size.y*absf(cos(desired_yaw)))*sin(pitch)+4
	var ratio: float=get_viewport().get_visible_rect().size.x/get_viewport().get_visible_rect().size.y
	desired_zoom=clampf(maxf(extent_y,extent_x/ratio)*1.10*minf(1.0,ratio)/world_scale,10,zoom_max)

func _read_camera(data: Dictionary) -> void:
	map_size=Vector2(float(data.get("width",1280)),float(data.get("height",800)))/32.0
	var spec: Dictionary=data.get("camera",{})
	var lo: Array=spec.get("min",[4,1])
	var hi: Array=spec.get("max",[map_size.x-1,map_size.y-1])
	var home: Array=spec.get("start",[19.5,13.0])
	camera_min=Vector2(float(lo[0]),float(lo[1]))
	camera_max=Vector2(float(hi[0]),float(hi[1]))
	camera_home=Vector3(float(home[0]),0,float(home[1]))
	zoom_home=float(spec.get("zoom",29.0))
	zoom_max=float(spec.get("zoomMax",64.0))
	target=camera_home
	desired_target=camera_home
	zoom=zoom_home
	desired_zoom=zoom_home

## Opens a dossier page over the game, stopping the clock and remembering whether it was running.
func _open_sheet(page: String) -> void:
	_arm("",true)
	if not hud.overlay.visible:
		briefing_was_running=sim.phase=="playing" and not sim.paused
		if briefing_was_running: sim.toggle_pause()
	hud.show_modal(page)

## Back to the game from a dossier page, the clock as it was.
func _resume() -> void:
	if briefing_was_running and sim.paused: sim.toggle_pause()
	briefing_was_running=false
	hud.overlay.hide()
	hud.notify("")

func _command(command_name: String) -> void:
	if command_name.begins_with("mission:"):
		_switch_mission(command_name.substr(8))
		return
	if command_name.begins_with("lang:"):
		_switch_language(command_name.substr(5))
		return
	match command_name:
		"title":
			_enter_title("")
			return
		"feedback":
			# after the last level's story: the questions, on the launch screen's paper
			_enter_title("feedback")
			return
		"questions":
			# the pause menu: the questions over the paused level, which carries on after
			_ui_sound("tap")
			front.open_questions_over_game()
			return
		"begin":
			if sim.phase=="lost" and sim.has_checkpoint():
				# Retry from the last checkpoint: the simulation comes back paused, in command mode.
				_load_checkpoint()
				return
			var fresh: bool=sim.phase!="playing"
			if sim.phase in ["won","lost"]: sim.restart()
			if sim.phase=="briefing": sim.start()
			if fresh:
				if sim.paused: sim.toggle_pause()
				briefing_was_running=false
				if not _begin_view(): _focus_ground(sim.position_of(sim.selected()))
				hud.overlay.hide()
			else: _resume()
		"briefing": _open_sheet("briefing")
		"menu": _open_sheet("menu")
		"howto", "notes": _open_sheet("howto")
		"save":
			if sim.save_checkpoint():
				if hud.overlay.visible: _resume()
				_ui_sound("tap")
			else: _deny(str(sim.message))
		"load":
			if sim.has_checkpoint(): _load_checkpoint()
			else: _deny("No checkpoint yet.")
		"restart_now":
			# Straight back to the landing, clock running, without the briefing.
			_arm("",true)
			sim.restart()
			if sim.paused: sim.toggle_pause()
			briefing_was_running=false
			desired_zoom=zoom_home
			if not _begin_view(): _focus_ground(sim.position_of(sim.selected()))
			hud.overlay.hide()
		"restart":
			_arm("",true)
			sim.reset()
			desired_target=camera_home
			desired_zoom=zoom_home
			hud.show_modal("briefing")
		"text_size": _resize()
		"settings":
			_apply_settings()
			_ui_sound("tap")
		"pause":
			sim.toggle_pause()
			_ui_sound("tap")
		"deny": _ui_sound("deny")
		"tap": _ui_sound("tap")
		"fit": _fit_camera()
		"rotate_left": desired_yaw-=PI/4
		"rotate_right": desired_yaw+=PI/4
	# A restart or a retry changes the phase here and now; do not wait for the next frame to notice.
	if sim.phase=="playing" or sim.phase=="briefing": last_phase=sim.phase
	hud.refresh()

## The other language from the dossier: remembered, then the scene starts over in it (the mission data is read
## again, translated). Only offered on the briefing, before the operation begins.
func _switch_language(lang: String) -> void:
	if not lang in Lang.LANGS or lang==Lang.current: return
	Lang.choose(lang,hud.progress_path)
	_ui_sound("tap")
	if get_tree().current_scene==self: get_tree().call_deferred("reload_current_scene")
	else: hud.refresh()

## Another level (NEXT OPERATION on the debrief): remembered for the next start, then the scene starts over on it.
func _switch_mission(id: String) -> void:
	if Missions.index_of(id)<0 or id==Missions.current: return
	# a locked level does not open
	if not Missions.unlocked(id,hud.progress):
		_ui_sound("deny")
		return
	Missions.choose(id,true,hud.progress_path)
	_ui_sound("tap")
	if get_tree().current_scene==self: get_tree().call_deferred("reload_current_scene")

func _load_checkpoint() -> void:
	_arm("",true)
	sim.load_checkpoint()
	briefing_was_running=false
	last_phase=sim.phase
	_focus_ground(sim.position_of(sim.selected()))
	hud.overlay.hide()
	_ui_sound("tap")
	hud.refresh()

## Every simulation event, once, as the world re-emits it.
func _on_sim_event(event: Dictionary) -> void:
	hud.on_sim_event(event)
	if event.type=="alarm_start" and auto_command_on_alarm and sim.phase=="playing" and not sim.paused and not hud.overlay.visible:
		# Once per alarm: stop the clock so the player can drop, run or fight on his own terms.
		sim.toggle_pause()
		hud.notify("Alarm — orders?",6.0)
		hud.refresh()

# --- taps in the world ---------------------------------------------------------------------------------
func ground_at(screen_point: Vector2) -> Variant:
	return Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(screen_point),camera.project_ray_normal(screen_point))

func _consider(kind: String, id: String, at: Vector3, radius: float, bias: float, screen_point: Vector2) -> bool:
	if camera.is_position_behind(at): return false
	var d: float=camera.unproject_position(at).distance_to(screen_point)
	if d>radius or d/radius+bias>=_hit_score: return false
	_hit_kind=kind
	_hit_id=id
	_hit_score=d/radius+bias
	return true

## Finds what is under the finger. Each candidate has a finger-sized radius; the closest one relative
## to its radius wins, with a small bias in the order operative, guard, body, thing.
func _scan(screen_point: Vector2, ground: Vector2, guards_only: bool=false) -> void:
	_hit_kind=""
	_hit_id=""
	_hit_score=INF
	_hit_thing={}
	for guard: Dictionary in sim.guards:
		if str(guard.carried_by)!="": continue
		var at:=Vector3(float(guard.x)/32,float(guard.elevation),float(guard.y)/32)
		# a rescue's people: under cover or lost to the snow, nothing to tap; one fallen is lifted like a body
		if bool(guard.get("person",false)) and str(guard.state) in ["safe","lost"]: continue
		if guard.state=="dead" or guard.state=="bound" or (guard.state=="fallen" and bool(guard.get("person",false))):
			# A body hidden in a bush is not a target: a tap there means "into the bush".
			if not guards_only and float(guard.elevation)<=0.0 and not bool(guard.hidden): _consider("body",guard.id,at+Vector3(0,0.25,0),TAP_BODY,0.1,screen_point)
		else: _consider("guard",guard.id,at+Vector3(0,0.3 if guard.state=="stunned" else 0.95,0),TAP_GUARD,0.05,screen_point)
	if guards_only: return
	for unit: Dictionary in sim.units:
		if not bool(unit.alive): continue
		var own: bool=unit.id==sim.selected_id
		_consider("unit",unit.id,Vector3(float(unit.x)/32,0.85,float(unit.y)/32),TAP_SELF if own else TAP_UNIT,0.3 if own else 0.0,screen_point)
	# A tap on a floating marker is a tap on its thing.
	var pin: Dictionary=hud.pin_at(screen_point)
	if not pin.is_empty() and _hit_score>0.02:
		_hit_kind="thing"
		_hit_score=0.02
		_hit_thing=pin
	var per_metre: float=get_viewport().get_visible_rect().size.y/camera.size
	for thing: Dictionary in sim.interactables():
		var type: String=thing.type
		if type=="body" or type=="bush" or type=="uniform": continue
		var where:=Vector2(float(thing.x),float(thing.y))
		if type=="extraction":
			# The ring is ground: inside it means "to your place on the stage", after anything standing in it.
			var d: float=ground.distance_to(where)/float(thing.radius)
			if d<=1.0 and 0.6+0.3*d<_hit_score:
				_hit_kind="thing"
				_hit_score=0.6+0.3*d
				_hit_thing=thing
			continue
		if _consider("thing",str(thing.id),Vector3(where.x/32,float(THING_HEIGHT.get(type,0.5)),where.y/32),maxf(TAP_THING,float(thing.radius)/32*per_metre),0.15,screen_point): _hit_thing=thing

func _world_tap(screen_point: Vector2) -> void:
	if sim.phase!="playing" or hud.overlay.visible: return
	var hit: Variant=ground_at(screen_point)
	if not hit is Vector3: return
	var point:=Vector2(hit.x,hit.z)*32
	if armed=="distract":
		# The pebble goes where the finger lands; a refused throw (too far, a wall) keeps it in hand.
		var thrown: bool=sim.perform("distract",point)
		if thrown: _arm("",true)
		_feedback(thrown)
		return
	if armed!="":
		# A weapon is up: only a guard under the finger is acted on, and nobody moves by mistake.
		_scan(screen_point,point,true)
		if _hit_kind=="guard":
			var done: bool=sim.perform(armed,_hit_id)
			if done: _arm("",true)
			_feedback(done)
			return
		_scan(screen_point,point)
		if _hit_kind=="unit" and _hit_id!=sim.selected_id: _select_unit(_hit_id,false)
		else: _arm("")
		return
	_scan(screen_point,point)
	match _hit_kind:
		"unit":
			# a mate down in the snow: the selected operative goes to get him up
			if _hit_id!=sim.selected_id and bool(sim.unit_by_id(_hit_id).get("fallen",false)): _feedback(sim.perform("help",_hit_id))
			elif _hit_id!=sim.selected_id: _select_unit(_hit_id,false)
			elif not sim.selected().order.is_empty() or not sim.selected().path.is_empty(): _feedback(sim.perform("cancel"))
		"guard":
			# a docker with no knife offers a cigarette instead; a man who speaks the valley's language has a word
			# with one of its people (the watchman) rather than laying hands on him; one of a rescue's people is led in
			var who: Dictionary=sim.selected()
			var target: Dictionary=sim.guard_by_id(_hit_id)
			if bool(target.get("person",false)): _feedback(sim.perform("guide",_hit_id))
			# a rescue's creature: one with a gun fires at it (and one without is told to keep away)
			elif bool(target.get("creature",false)): _feedback(sim.perform("shoot",_hit_id))
			elif who.has("talk") and bool(target.get("civilian",false)): _feedback(sim.perform("talk",_hit_id))
			else: _feedback(sim.perform("chat" if who.has("chat") and not who.has("melee") else "takedown",_hit_id))
		"body": _feedback(sim.perform("pickup",_hit_id))
		"thing":
			if bool(_hit_thing.enabled): _feedback(sim.perform(str(_hit_thing.order),_hit_thing.target))
			elif not sim.is_blocked(point): _ground_tap(point)
			else: _deny(str(_hit_thing.reason))
		_: _ground_tap(point)

func _ground_tap(point: Vector2) -> void:
	# With a body on his shoulders a tap into a bush means "hide it there".
	if str(sim.selected().carrying)!="" and sim.in_bush(point): _feedback(sim.perform("drop",point))
	else: _feedback(sim.perform("move",point))

# --- camera gestures ---------------------------------------------------------------------------------------
func _pan_pixels(delta: Vector2, give: bool=true) -> void:
	var middle: Vector2=get_viewport().get_visible_rect().size/2
	var a: Variant=ground_at(middle)
	var b: Variant=ground_at(middle+delta)
	if a is Vector3 and b is Vector3:
		if not give:
			desired_target+=a-b
			_clamp_target()
			_update_camera(1,true)
			return
		if not _pan_raw.is_finite(): _pan_raw=desired_target
		_pan_raw+=a-b
		var inside:=Vector3(clampf(_pan_raw.x,camera_min.x,camera_max.x),0,clampf(_pan_raw.z,camera_min.y,camera_max.y))
		var over: Vector3=_pan_raw-inside
		over=Vector3(_give(over.x),0,_give(over.z))
		desired_target=inside+over
		if over!=Vector3.ZERO: hud.hint("map_edge")
		_update_camera(1,true)

## The finger lifts: the camera eases back inside the map (the lerp in _update_camera does the easing).
func _pan_release() -> void:
	if not _pan_raw.is_finite(): return
	_pan_raw=Vector3.INF
	_clamp_target()

## How far the camera goes past the edge for a finger `raw` metres past it: EDGE_GIVE of the way at first, never
## beyond EDGE_REACH, and always still answering the finger.
func _give(raw: float) -> float:
	return signf(raw)*EDGE_REACH*(1.0-exp(-absf(raw)*EDGE_GIVE/EDGE_REACH))

func _clamp_target() -> void:
	desired_target.x=clampf(desired_target.x,camera_min.x,camera_max.x)
	desired_target.z=clampf(desired_target.z,camera_min.y,camera_max.y)

func _zoom(factor: float) -> void:
	desired_zoom=clampf(desired_zoom/factor,10.0,zoom_max)

func _input(event: InputEvent) -> void:
	# Release a map gesture even when the pointer ends over a HUD control.
	if event is InputEventMouseButton and not event.pressed and mouse_held and _point_on_ui(event.position):
		mouse_held=false
	if event is InputEventScreenTouch and not event.pressed and touch_positions.has(event.index) and _point_on_ui(event.position):
		touch_positions.erase(event.index)
		touch_starts.erase(event.index)
		touch_moved.erase(event.index)
		if touch_positions.is_empty(): multi_touch=false
	if event is InputEventKey and event.pressed and not event.echo and _shortcut(event.keycode):
		get_viewport().set_input_as_handled()

## Desktop shortcuts; each one presses the button it names (see the list at the top of this file).
func _shortcut(keycode: int) -> bool:
	if mode=="title" or front.visible:
		# (the questions are on the launch screen's paper over the paused level: Esc goes back there too)
		if keycode==KEY_ESCAPE and front.visible: return front.back()
		return false
	if hud.overlay.visible:
		if keycode==KEY_ESCAPE and hud.current_modal in ["menu","howto"] and sim.phase=="playing": _command("begin")
		else: return false
		return true
	match keycode:
		KEY_SPACE: _slot("plan")
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			var i: int=keycode-KEY_1
			if i<sim.units.size(): _select(str(sim.units[i].id))
		KEY_TAB:
			var at: int=0
			for i: int in range(sim.units.size()):
				if str(sim.units[i].id)==sim.selected_id: at=i
			# the next one in the square (one who has not come yet is passed over)
			for step: int in range(1,sim.units.size()+1):
				var next: Dictionary=sim.units[(at+step)%sim.units.size()]
				if not bool(next.get("away",false)):
					_select(str(next.id))
					break
		KEY_C: _slot("stance")
		KEY_A: _slot("melee")
		KEY_G: _slot("gun")
		KEY_D: _slot("tool")
		KEY_E: _slot("context")
		KEY_Z:
			if sim.phase=="playing": _feedback(sim.perform("cancel"))
		KEY_F: _command("fit")
		KEY_Q: _command("rotate_left")
		KEY_R: _command("rotate_right")
		KEY_M: _command("menu")
		KEY_K: _command("save")
		KEY_L: _command("load")
		KEY_ESCAPE:
			if armed!="": _arm("")
			else: _command("menu")
		_: return false
	return true

func _on_finale_finished() -> void:
	hud.show_modal("won")
	desired_zoom=minf(desired_zoom,zoom_home*1.6)

func _unhandled_input(event: InputEvent) -> void:
	if mode=="title": return
	if world!=null and world.finale_running():
		# any tap or key skips the closing scene
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed) or (event is InputEventKey and event.pressed):
			world.finale.skip()
		return
	if sim==null or sim.phase!="playing" or hud.overlay.visible: return
	if event is InputEventMouse and event.device==-1: return
	if event is InputEventMagnifyGesture:
		_zoom(event.factor)
	elif event is InputEventPanGesture:
		_pan_pixels(-event.delta*24.0,false)
	elif event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_RIGHT]:
			if event.pressed:
				mouse_held=true
				mouse_dragged=event.button_index!=MOUSE_BUTTON_LEFT
				pointer_start=event.position
				pointer_last=event.position
			else:
				if mouse_held and not mouse_dragged and event.button_index==MOUSE_BUTTON_LEFT: _world_tap(event.position)
				mouse_held=false
				_pan_release()
		elif event.pressed:
			if event.button_index==MOUSE_BUTTON_WHEEL_UP: _zoom(1.12)
			elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN: _zoom(1/1.12)
	elif event is InputEventMouseMotion and mouse_held:
		if event.position.distance_to(pointer_start)>8: mouse_dragged=true
		if mouse_dragged: _pan_pixels(event.position-pointer_last)
		pointer_last=event.position
	elif event is InputEventScreenTouch:
		if event.pressed:
			touch_positions[event.index]=event.position
			touch_starts[event.index]=event.position
			touch_moved[event.index]=false
			if touch_positions.size()>1: multi_touch=true
		else:
			if touch_positions.has(event.index) and not multi_touch and not touch_moved.get(event.index,false): _world_tap(event.position)
			touch_positions.erase(event.index)
			touch_starts.erase(event.index)
			touch_moved.erase(event.index)
			if touch_positions.is_empty():
				multi_touch=false
				_pan_release()
	elif event is InputEventScreenDrag and touch_positions.has(event.index):
		if touch_positions.size()>=2:
			var keys: Array=touch_positions.keys()
			var a: Vector2=touch_positions[keys[0]]
			var b: Vector2=touch_positions[keys[1]]
			var old_center: Vector2=(a+b)/2
			var old_distance: float=a.distance_to(b)
			touch_positions[event.index]=event.position
			var c: Vector2=touch_positions[keys[0]]
			var d: Vector2=touch_positions[keys[1]]
			if old_distance>1: _zoom(c.distance_to(d)/old_distance)
			_pan_pixels((c+d)/2-old_center)
		else:
			var previous: Vector2=touch_positions[event.index]
			touch_positions[event.index]=event.position
			if event.position.distance_to(touch_starts[event.index])>12: touch_moved[event.index]=true
			if touch_moved[event.index]: _pan_pixels(event.position-previous)

## When Android's Back was last handled (see _notification).
var _back_at: int=-1000

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_PAUSED and sim!=null and sim.phase=="playing" and not sim.paused:
		sim.toggle_pause()
	if what==NOTIFICATION_WM_GO_BACK_REQUEST:
		# Android delivers one Back press twice (Godot 4.7.2's key handler and the activity's own dispatch, 95 ms
		# apart): a second request within a fifth of a second is the same press, or the second one would quit
		# the game from the menu the first one just returned to
		var now: int=Time.get_ticks_msec()
		if now-_back_at<200: return
		_back_at=now
		_go_back()

## Android's Back: out of an armed action, back a page in the dossier, otherwise into the pause menu. Only
## the briefing before a mission (or the debrief) leaves the app.
func _go_back() -> void:
	if sim==null or hud==null: return
	if mode=="title":
		if ui_layer.visible:
			# HOW TO PLAY over the launch screen
			hud._second_pressed()
		elif not front.back(): get_tree().quit()
		return
	if front.visible:
		# the questions over the paused level
		front.back()
		return
	if hud.overlay.visible:
		match hud.current_modal:
			"howto": hud._second_pressed()
			"menu": _command("begin")
			"briefing":
				if sim.phase=="playing": _command("begin")
				else: _enter_title("")
			"won": get_tree().quit()
			_:
				if sim.phase=="playing": _command("menu")
				else: get_tree().quit()
		return
	if armed!="":
		_arm("")
		return
	if sim.phase=="playing": _command("menu")

func _point_on_ui(point: Vector2) -> bool:
	if hud==null: return false
	if mode=="title": return true
	if hud.overlay.visible: return true
	for control: Control in hud.touch_blocks():
		if control.is_visible_in_tree() and control.get_global_rect().has_point(point): return true
	return false

# --- the launch screen ---------------------------------------------------------------------------------
## Puts the launch screen up (or one of its pages): the operation goes back to its start, the kit away, and the
## camera drifts over the scene while the guards walk their rounds.
func _enter_title(page: String) -> void:
	_arm("",true)
	if world.finale_running(): world.finale.skip()
	sim.reset()
	last_phase=sim.phase
	briefing_was_running=false
	mode="title"
	_title_clock=0.0
	# no cones, rings or markers over the scene: it is a picture here
	world.overlays.visible=false
	world.draw_vision=false
	hud.overlay.hide()
	ui_layer.visible=false
	front.open(page)
	_title_camera(0.0)
	_update_camera(1.0,true)

## From the launch screen into the game: to the current operation's briefing, or to HOW TO PLAY over the scene.
func _leave_title(to: String) -> void:
	if to=="howto":
		front.hide()
		ui_layer.visible=true
		hud.show_howto_from_title()
		return
	mode="game"
	front.hide()
	ui_layer.visible=true
	world.overlays.visible=true
	world.draw_vision=true
	sim.reset()
	last_phase=sim.phase
	desired_target=camera_home
	desired_zoom=zoom_home
	desired_yaw=PI/4
	target=desired_target
	zoom=desired_zoom
	yaw=desired_yaw
	_update_camera(1.0,true)
	hud.show_modal("briefing")
	hud.refresh()

func _front_command(cmd: String) -> void:
	if cmd.begins_with("lang:"):
		Front.resume_to="settings"
		_switch_language(cmd.substr(5))
		return
	if cmd.begins_with("title_lang:"):
		# the launch screen's own keys: back to the launch screen in the other language
		Front.resume_to="title"
		_switch_language(cmd.substr(11))
		return
	match cmd:
		"continue":
			_ui_sound("tap")
			_leave_title("briefing")
		"howto":
			_ui_sound("tap")
			_leave_title("howto")
		"settings":
			_apply_settings()
			_ui_sound("tap")  # after: the tap is heard at the new volume
		"deny": _ui_sound("deny")

## Comic ink, volume and voices from the progress file (Settings, or the pause menu), onto the world, the sound
## module and the master bus. Off stops the sound altogether; the other steps turn the whole mix down together.
func _apply_settings() -> void:
	world.call("set_ink",ComicInk.wanted(sim.data,hud.progress))
	var step: int=hud.volume()
	AudioServer.set_bus_volume_db(0,float(HUD.VOLUME_DB[step]))
	var audio: Variant=world.get("audio")
	if audio==null or not audio is Object: return
	audio.set("enabled",step>0)
	audio.set("voices_on",bool(hud.progress.get_value("settings","voices",true)))

## The slow drift behind the launch screen: along the mission's title stretch (data camera.title: from, to, zoom,
## yaw in degrees, 45 unless given) and back, the view turning a little either way.
func _title_camera(dt: float) -> void:
	_title_clock+=dt
	var spec: Dictionary=sim.data.get("camera",{}).get("title",{})
	var a: Array=spec.get("from",[camera_home.x,camera_home.z])
	var b: Array=spec.get("to",[map_size.x*0.5,map_size.y*0.5])
	var s: float=0.5-0.5*cos(_title_clock*TAU/80.0)
	var from:=Vector3(float(a[0]),0,float(a[1]))
	var to:=Vector3(float(b[0]),0,float(b[1]))
	desired_target=from.lerp(to,s)
	desired_yaw=deg_to_rad(float(spec.get("yaw",45.0)))+0.2*sin(_title_clock*TAU/57.0)
	desired_zoom=float(spec.get("zoom",zoom_home*1.25))*(1.0+0.05*sin(_title_clock*TAU/43.0))
	if dt==0.0:
		target=desired_target
		yaw=desired_yaw
		zoom=desired_zoom
