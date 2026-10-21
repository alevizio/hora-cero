extends RefCounted
## Deterministic rules of a level of Hora Cero. The full reference is docs/GAMEPLAY_API.md at the repository root.
## Planar world in "sim units" (32 units = 1 metre). Angles are radians, 0 = +x (east), PI/2 = +y (south).
## Actors are plain Dictionaries so the renderer, animator and HUD can read their fields by name.
## Nothing here is random: the same orders at the same times always give the same mission.

# --- movement ---
const BODY_RADIUS: float = 9.0
const WALK_SPEED: float = 84.0
const SNEAK_SPEED: float = 56.0
const CARRY_SPEED: float = 50.0
const PRISONER_SPEED: float = 72.0
## The informant stops this far behind his escort (closer when the escort is in a bush) and re-paths
## at most every FOLLOW_REPATH seconds once he has dropped FOLLOW_SLACK further back.
const FOLLOW_DISTANCE: float = 25.0
const FOLLOW_DISTANCE_COVER: float = 12.0
const FOLLOW_SLACK: float = 9.0
const FOLLOW_REPATH: float = 0.35
## Guards turn at a finite rate and stop to turn when they are more than TURN_IN_PLACE off their heading.
const GUARD_TURN_RATE: float = 3.2
const TURN_IN_PLACE: float = 0.7
const PURSUIT_REPATH: float = 0.4
# --- sight and detection ---
const BUSH_REVEAL: float = 72.0
const FILL_NEAR_STAND: float = 0.5
const FILL_NEAR_CROUCH: float = 0.9
const FILL_FAR_MIN: float = 1.2
const FILL_FAR_MAX: float = 2.2
const SUSPICION_DRAIN: float = 2.0
const BODY_ALERT_TIME: float = 1.0
## A guard on edge (hunting, on alert, or just woken from a stun) has a wider and longer cone, fills his
## meter ALERT_FILL_SCALE times as fast, and is certain at once of anyone he sees standing.
const ALERT_FOV_BONUS: float = 40.0
const ALERT_RANGE_BONUS: float = 60.0
const ALERT_FILL_SCALE: float = 2.0
# --- operative actions ---
const MELEE_RANGE: float = 30.0
const PICKUP_RANGE: float = 26.0
const PICKUP_TIME: float = 0.7
const DROP_TIME: float = 0.3
const UNLOCK_TIME: float = 1.4
const UNLOCK_REACH: float = 24.0
const RESCUE_TIME: float = 0.8
const RESCUE_RANGE: float = 34.0
const CUT_TIME: float = 3.0
const SABOTAGE_TIME: float = 3.0
const WORK_REACH: float = 20.0
const SHOT_SLACK: float = 20.0
const DISTRACT_RANGE: float = 240.0
const DISTRACT_COOLDOWN: float = 8.0
## A move or a throw aimed at something solid is walked back along its line in steps this long until it
## lands on open ground (see _back_along).
const BACK_STEP: float = 8.0
## Closer than this to where he already stands, a walked-back move is not worth giving.
const BACK_MIN_MOVE: float = 6.0
const DISTRACT_RADIUS: float = 240.0
## A local in his own clothes ("cover" in his data) walks past guards unremarked while he is upright, empty-handed,
## outside the restricted zones and there is no alarm. His cigarette ("chat") stops a calm guard for a smoke:
## he walks up to within CHAT_RANGE, and the guard stands facing him until the cigarette is done.
const CHAT_RANGE: float = 40.0
const CHAT_TIME: float = 7.0
const CHAT_STATES: Array[String] = ["patrol", "post", "return"]
## A guard's uniform (missions with "uniforms" in their data): any operative can take it off a man he has put down
## and walk among the guards in it, upright and empty-handed, like a local in his own clothes ("cover"). It does
## not fool an officer (data uniforms.officers: guard kinds and looks), nor any guard who gets this close to him.
const UNIFORM_TIME: float = 4.0
const UNIFORM_CLOSE: float = 56.0
const SEARCH_TIME: float = 3.2
const LURE_REACT: float = 0.3
const LURE_STAGGER: float = 0.12
# --- trap ---
const TRAP_SET_TIME: float = 1.5
const TRAP_LIFT_TIME: float = 1.0
const TRAP_RADIUS: float = 18.0
const STUN_TIME: float = 20.0
const WAKE_SEARCH_TIME: float = 6.0
# --- alarm ---
const ALARM_TIME: float = 20.0
const ALARM_TIME_RADIO_CUT: float = 12.0
## How far a shout carries: guards within this distance of the trouble come running, the rest stay at
## their work on alert. A gunshot is heard everywhere.
const ALARM_RADIUS: float = 400.0
const HUNT_SPEED_SCALE: float = 1.7
const HUNT_TURN_RATE: float = 5.5
const HUNT_REACT: float = 0.35
const HUNT_STAGGER: float = 0.09
const HUNT_REPATH_TIME: float = 0.6
## However many guards are hunting, at most this many of them look for a new path in one update;
## the others take their turn on the following ones.
const HUNT_SEARCHES_PER_UPDATE: int = 2
const HUNT_REPATH_DISTANCE: float = 48.0
const HUNT_LOOK_TIME: float = 3.0
const HUNT_SEARCH_RADIUS: float = 120.0
const GUARD_AIM_TIME: float = 0.7
const GUARD_FIRE_INTERVAL: float = 1.1
const GUARD_DAMAGE: int = 34
## Once a guard has aimed this long he fires even if he loses sight of the target for up to AIM_GRACE
## seconds; the shot still hits unless something solid has come between them.
const AIM_COMMIT: float = 0.4
const AIM_GRACE: float = 0.4
const FIRE_FLASH_TIME: float = 0.14
const MAX_HEALTH: int = 100
# --- checkpoints and bookkeeping ---
const CHECKPOINT_SUSPICION: float = 0.15
const EVENT_LIMIT: int = 256
## "fallen": a person of the rescue (data "people") who has collapsed in the snow, still alive: carried like a body.
const BODY_STATES: Array[String] = ["dead", "bound", "stunned", "fallen"]
## The people of a rescue (PERSON_STATES) are never on duty either: no cone, no eyes, no alarm; nor are its creatures
## (CREATURE_STATES), who go by their own senses.
const DOWN_STATES: Array[String] = ["dead", "bound", "stunned", "held", "calm", "crowd", "follow", "coming", "panic", "safe", "fallen", "lost",
	"waiting", "prowl", "stalk", "drawn", "stay", "driven", "away"]
## Timed actions during which an operative counts as standing, whatever his stance.
const EXPOSING_ACTIONS: Array[String] = ["takedown", "pickup", "drop"]
const BRIEFING_MESSAGE: String = "Study the patrols. Bring everyone home."

# --- snow (data "snow"), passages (data "passages"), floodlights (data "floodlit") ---
## Footprints in fresh snow: how long they last, how far apart they are laid, how far off a guard notices them
## (in the dark; under a floodlight anywhere in his cone), how far ahead along the trail he goes looking, and how
## many times he follows on before he gives up. All can be set in data "snow".
const TRACK_TTL: float = 50.0
const TRACK_SPACING: float = 24.0
const TRACK_SEE: float = 150.0
const TRACK_FOLLOW: float = 230.0
const TRACK_HOPS: int = 4
const TRACK_LIMIT: int = 360
const TRACK_LOOK_EVERY: float = 0.25
## A man in a white snowsuit, crouched and keeping still in the snow, is seen only at this distance or closer.
const CAMO_REVEAL: float = 36.0
## A rope rigged down a gorge: how slowly it is climbed (a fraction of the usual speed) unless the data says otherwise.
const PASSAGE_SLOW: float = 0.45
const TALK_TIME: float = 3.0
const TALK_RANGE: float = 40.0
## States a civilian talked round is left in: he sits it out and sees nothing (he is not a body: nobody finds him).
const CALM_STATES: Array[String] = ["calm"]

# --- the rescue (data "snowfall", "people", "shelters", "vehicles", "canvases": Plaza de Mayo) ---
## A person of the rescue: standing in the square ("crowd"), led by an operative ("follow"), making for a shelter by
## himself ("coming", called there), running blindly ("panic"), under cover ("safe"), collapsed but alive ("fallen",
## carried like a body) or lost under the snow ("lost").
const PERSON_STATES: Array[String] = ["crowd", "follow", "coming", "panic", "safe", "fallen", "lost"]
## People still out in the snow and on their feet: they can be led or called.
const LEADABLE_STATES: Array[String] = ["crowd", "follow", "coming", "panic"]
## Defaults for data "snowfall": seconds of steady snow (strength 1) to fill the cold (an operative / a person),
## seconds under cover to drain it, seconds a fallen one can still be brought in, and how people are led.
const EXPOSURE_RATE_UNIT: float = 62.0
const EXPOSURE_RATE_PERSON: float = 105.0
const EXPOSURE_RECOVER: float = 28.0
const FALL_GRACE_UNIT: float = 45.0
const FALL_GRACE_PERSON: float = 40.0
const LEAD_DEFAULT: int = 4
const PERSON_SPEED: float = 62.0
const PERSON_RUN: float = 96.0
const PERSON_GAP: float = 22.0
## How close a person must be to the one he joins a group with, and to the one holding a cloth over him.
const GROUP_REACH: float = 192.0
const CANVAS_REACH: float = 64.0
const GUIDE_TIME: float = 0.6
const HELP_TIME: float = 1.5
const CANVAS_TIME: float = 1.0
const CANVAS_REACH_TAKE: float = 30.0
const VEHICLE_SPEED: float = 46.0
## A rescue's creatures (data "creatures", the plaza's cascarudos): not yet come ("waiting"), roaming toward whoever is
## out in the open ("prowl"), going for one they have sensed ("stalk"), drawn by a noise ("drawn"), standing over one
## they have knocked down ("stay"), driven off by a shot ("driven"), gone off the map for a while ("away"), or killed
## ("dead"). Defaults for the data's numbers (sim units, seconds): their walk, their rush at someone sensed, their run
## when driven off; how far they sense people in the open and reach them; how wide they are to the ground they walk
## (they keep out of every shelter and every vehicle, and out of everything solid); how long they stand over the one
## they knocked down; the hits that kill one; how long one driven off stays away; how long one drawn by a noise stays
## there; how often they choose again.
const CREATURE_STATES: Array[String] = ["waiting", "prowl", "stalk", "drawn", "stay", "driven", "away", "dead"]
const CREATURE_SPEED: float = 40.0
const CREATURE_CHARGE: float = 70.0
const CREATURE_FLEE: float = 110.0
const CREATURE_SENSE: float = 640.0
const CREATURE_REACH: float = 64.0
const CREATURE_RADIUS: float = 28.0
const CREATURE_PAUSE: float = 3.5
const CREATURE_HITS: int = 3
const CREATURE_AWAY: float = 35.0
const CREATURE_LINGER: float = 6.0
const CREATURE_THINK: float = 0.5
## An operative in a sealed suit (data units[].suit) knocked down gets up again by himself after this long.
const SUIT_UP: float = 8.0

var data: Dictionary
var phase: String = "briefing"
var paused: bool = true
var time: float = 0.0
var selected_id: String = "wren"
var units: Array = []
var guards: Array = []
var prisoner: Dictionary = {}
## Setting these (the rules do, tests may) refreshes the cached collision and sight geometry.
var door_open: bool = false:
	set(value):
		door_open = value
		_geometry_dirty = true
var fence_cut: bool = false:
	set(value):
		fence_cut = value
		_geometry_dirty = true
var radio_cut: bool = false
## Passages rigged so far (data "passages", a rope down a gorge): passage id -> id of the operative who rigged it.
var rigged: Dictionary = {}
## Footprints in the snow, oldest first: {id, x, y, angle, t (sim time laid), by, kind ("boot" or "ski"), seen}.
var tracks: Array = []
## The fuse burning after the last charge is set (data "fuse"): seconds left, -1 when none is burning, and
## whether it has gone off.
var fuse_left: float = -1.0
var blasted: bool = false
## Charge sites done so far (data "charges"): site id -> id of the operative who planted it.
var planted: Dictionary = {}
## False when the mission has nobody to rescue (no "prisoner" in the data): the informant is then kept
## out of play (never freed, already "aboard"), so the rules that wait on him are satisfied.
var has_prisoner: bool = true
## True for a rescue against the snow (data "snowfall"): see the section "The rescue" below.
var rescue_on: bool = false
## The vehicles of a rescue (data "vehicles"), by id: {x, y (the rectangle's corner now, sim units), stop (index of the
## stop it stands at or left), to (index of the stop it is driving to, -1 standing), dir (+1 east along the stops, -1
## back), driver (unit id)}.
var vehicles: Dictionary = {}
## Cloths taken so far (data "canvases"): canvas id -> unit id. A spent cloth stays on the list.
var canvases_taken: Dictionary = {}
## The gear left about a rescue's square (data "gear": a hood and mask, a rifle) that has been taken: gear id -> who.
var gear_taken: Dictionary = {}
## The snow has buried the square (data snowfall.bury): whoever was out in it is lost.
var buried_square: bool = false
## Serial numbers handed to people as they join a chain behind an operative (the order they walk in).
var _rank_serial: int = 0
var _snow_level: String = ""
var noise: Array = []
var traps: Array = []
var message: String = BRIEFING_MESSAGE
var stats: Dictionary = {}
var alarm: Dictionary = {}
var objectives: Array = []
var events: Array[Dictionary] = []
var lost_reason: String = ""
var checkpoint: Dictionary = {}
var par_time: float = 240.0
## Profiling aid: grid searches run so far (a straight walk does not count). Not part of the mission state.
var path_searches: int = 0

var _cols: int = 40
var _rows: int = 25
var _cell: float = 32.0
var _geometry_dirty: bool = true
var _move_rects: Array[Rect2] = []
## The same rectangles grown by BODY_RADIUS: where the centre of a walker may not be.
var _body_rects: Array[Rect2] = []
var _reach_rects: Array[Rect2] = []
var _sight_rects: Array[Rect2] = []
var _tall_rects: Array[Rect2] = []
var _grid: PackedByteArray = PackedByteArray()
## Walkable cells that can reach each other share a region number (0 = blocked).
var _region: PackedInt32Array = PackedInt32Array()
## The ground as everyone walks it, and as the crew of a passage only they may use walk it (data passages[].crew:
## Biguá's boat). Each {move, body, grid, region}; the fields above are whichever is in use (see _walk_as).
var _geo_base: Dictionary = {}
var _geo_crew: Dictionary = {}
## The ground a rescue's creatures walk: everything solid, every shelter and every vehicle where it stands, grown by their
## width (rebuilt with the rest, and when a vehicle sets off or stops).
var _geo_beast: Dictionary = {}
var _beast_dirty: bool = true
var _crew_on: bool = false
## True when some passage of the mission has a crew: only then is anyone ever walked on the crew's ground.
var _has_crew: bool = false
var _centers: PackedVector2Array = PackedVector2Array()
var _width: float = 1280.0
var _height: float = 800.0
var _cost: PackedFloat32Array = PackedFloat32Array()
var _score: PackedFloat32Array = PackedFloat32Array()
var _parent: PackedInt32Array = PackedInt32Array()
var _seen: PackedInt32Array = PackedInt32Array()
var _closed: PackedInt32Array = PackedInt32Array()
var _search: int = 0
var _spawned: int = 0
var _trap_serial: int = 0
var _loads: int = 0
var _pending_checkpoint: String = ""
var _hunt_searches: int = 0
var _track_serial: int = 0

func _init(mission: Dictionary = {}) -> void:
	data = mission.duplicate(true)
	_cell = float(data.get("cellSize", 32))
	_cols = int(ceil(float(data.get("width", 1280)) / _cell))
	_rows = int(ceil(float(data.get("height", 800)) / _cell))
	var cells: int = _cols * _rows
	_width = float(data.get("width", 1280))
	_height = float(data.get("height", 800))
	_grid.resize(cells)
	_region.resize(cells)
	_centers.resize(cells)
	for index: int in range(cells):
		_centers[index] = _cell_center(index)
	_cost.resize(cells)
	_score.resize(cells)
	_parent.resize(cells)
	_seen.resize(cells)
	_closed.resize(cells)
	par_time = float(data.get("parTime", 240.0))
	has_prisoner = data.has("prisoner")
	rescue_on = data.has("snowfall")
	for passage: Dictionary in data.get("passages", []):
		if not (passage.get("crew", []) as Array).is_empty():
			_has_crew = true
	reset()

# ---------------------------------------------------------------------------------------------
# Mission flow
# ---------------------------------------------------------------------------------------------
func reset() -> void:
	phase = "briefing"
	paused = true
	time = 0.0
	door_open = false
	fence_cut = false
	radio_cut = false
	planted = {}
	rigged = {}
	tracks = []
	fuse_left = -1.0
	blasted = false
	_track_serial = 0
	selected_id = "wren"
	lost_reason = ""
	units.clear()
	guards.clear()
	noise.clear()
	traps.clear()
	events.clear()
	checkpoint = {}
	_spawned = 0
	_trap_serial = 0
	_loads = 0
	_pending_checkpoint = ""
	stats = {"time": 0.0, "kills": 0, "binds": 0, "knockouts": 0, "shots": 0, "alarms": 0, "bodies_found": 0, "distractions": 0, "checkpoints_loaded": 0}
	alarm = {"active": false, "time_left": 0.0, "duration": ALARM_TIME, "count": 0, "reason": "", "x": 0.0, "y": 0.0, "radius": float(data.get("alarm", {}).get("radius", ALARM_RADIUS)), "everyone": false, "reinforce_in": 0.0, "reinforce_pending": 0}
	message = str(data.get("briefingMessage", BRIEFING_MESSAGE))
	for spec: Dictionary in data.get("units", []):
		units.append(_make_unit(spec))
	if not units.is_empty() and unit_by_id(selected_id).is_empty():
		selected_id = str(units[0].id)
	for spec: Dictionary in data.get("guards", []):
		guards.append(_make_guard(spec))
	# the people of a rescue go on the guards' list as civilians (the renderer, the HUD and the recon map know civilians)
	for spec: Dictionary in data.get("people", []):
		guards.append(_make_person(spec))
	# and its creatures, waiting off the map for their time (data "creatures")
	for spec: Dictionary in _creatures().get("arrivals", []):
		guards.append(_make_creature(spec))
	_beast_dirty = true
	vehicles = {}
	for spec: Dictionary in data.get("vehicles", []):
		vehicles[str(spec.id)] = {"x": float(spec.x), "y": float(spec.y), "stop": int(spec.get("start", 0)), "to": -1, "dir": 1, "driver": ""}
	canvases_taken = {}
	gear_taken = {}
	buried_square = false
	_rank_serial = 0
	_snow_level = ""
	prisoner = data.get("prisoner", {}).duplicate(true)
	prisoner.merge({"id": "asset", "name": "The informant", "x": 0.0, "y": 0.0})
	prisoner.merge({"freed": false, "aboard": not has_prisoner, "follow_id": "", "hidden": false, "angle": -PI / 2.0, "path": [], "repath": 0.0, "hp": MAX_HEALTH, "alive": true})
	if not has_prisoner:
		# Out of play, off the map: never freed, never a target, already counted as safe.
		prisoner.x = -10000.0
		prisoner.y = -10000.0
	objectives.clear()
	var listed: Array = data.get("objectives", [])
	if listed.is_empty():
		listed = [
			{"id": "cell", "text": "Open the holding cell"},
			{"id": "informant", "text": "Free the informant"},
			{"id": "extract", "text": "Get everyone to the boat"}]
	for spec: Dictionary in listed:
		objectives.append({"id": str(spec.id), "text": str(spec.get("text", spec.id)), "done": false, "optional": bool(spec.get("optional", false))})

func start() -> void:
	phase = "playing"
	paused = true
	message = str(data.get("startMessage", "Crouched, you are invisible in the pale outer zone of a sight cone."))
	_store_checkpoint("start", true)

func restart() -> void:
	reset()
	start()

func _make_unit(spec: Dictionary) -> Dictionary:
	var unit: Dictionary = spec.duplicate(true)
	var gun: Dictionary = unit.get("gun", {})
	unit.merge({
		"angle": -PI / 2.0, "path": [], "stance": "sneak", "stance_before": "sneak", "hidden": false, "exposed": false,
		"hp": MAX_HEALTH, "alive": true, "carrying": "", "ammo": int(gun.get("ammo", 0)), "traps": 0,
		"cooldown": 0.0, "weapon_cooldown": 0.0, "action": "", "action_time": 0.0, "action_total": 0.0, "acting": false,
		"order": {}, "queued": {}, "repath": 0.0, "pebble": false, "tools": false, "trap_kit": 0, "action_target": Vector2.ZERO})
	unit.traps = int(unit.traps)
	unit.trap_kit = int(unit.traps)
	unit["smokes"] = int(unit.get("chat", {}).get("count", 0))
	# a thrown distraction of his own (data "throw", Merle's bottles): how many are left, -1 = no end of them
	unit["throws"] = int(unit.get("throw", {}).get("count", -1))
	unit["covered"] = false
	unit["blown"] = false
	# on skis right now (data "skis": fast across the snow, upright), keeping still in his snowsuit (data "camo"),
	# and how far he has walked since his last footprint
	unit["skiing"] = false
	unit["camouflaged"] = false
	unit["stride"] = 0.0
	# whose uniform he is wearing ({id, kind, look} of the guard), empty in his own clothes
	unit["disguise"] = {}
	# a rescue (data "snowfall"): the cold he has taken (0..1), down in the snow (seconds left to get him up), lost to it
	# for good, the cloth he holds over himself and the ones behind him, the calls he has left
	unit["exposure"] = float(spec.get("exposure", 0.0))
	unit["fallen"] = false
	unit["fall_left"] = 0.0
	unit["buried"] = false
	unit["canvas"] = {}
	unit["calls"] = int(unit.get("call", {}).get("count", -1))
	# one who comes later in the night (data units[].arrive {at, to}): out of play where his data puts him, at the edge
	# of the map, until his time comes; then he walks in (_arrive)
	unit["away"] = unit.has("arrive")
	if str(spec.get("stance", "")) in ["walk", "sneak"]:
		unit.stance = str(spec.stance)
		unit.stance_before = unit.stance
	return unit

func _make_guard(spec: Dictionary, origin: Variant = null) -> Dictionary:
	var guard: Dictionary = spec.duplicate(true)
	var route: Array = guard.get("route", [])
	var post: Array = guard.get("post", [])
	var at: Vector2 = Vector2.ZERO
	var facing: float = 0.0
	if not post.is_empty():
		at = Vector2(float(post[0]), float(post[1]))
		facing = deg_to_rad(float(post[2])) if post.size() > 2 else 0.0
	elif not route.is_empty():
		at = _route_point(route, 0)
		if route.size() > 1 and _route_point(route, 1).distance_to(at) > 0.5:
			facing = (_route_point(route, 1) - at).angle()
	if origin is Vector2:
		at = origin
	var view_range: float = float(guard.get("range", 190.0))
	var scan: Dictionary = guard.get("scan", {})
	guard.merge({"kind": "patrol", "speed": 34.0, "range": view_range, "near": minf(80.0, view_range * 0.45), "fov": 66.0, "elevation": 0.0,
		"static": false, "lure_immune": false, "melee_immune": false, "trap_immune": false, "alarm_hold": false, "route": route})
	guard.merge({
		"x": at.x, "y": at.y, "angle": wrapf(facing, -PI, PI), "base_fov": float(guard.fov), "base_range": float(guard.range),
		"state": "patrol", "mode": "patrol", "route_index": 1 if route.size() > 1 and not (origin is Vector2) else 0, "wait": 0.0, "wait_angle": facing,
		"has_post": not post.is_empty(), "post_x": at.x, "post_y": at.y, "post_angle": wrapf(facing, -PI, PI),
		"has_return": false, "return_x": at.x, "return_y": at.y,
		"has_scan": not scan.is_empty(), "scan_from": deg_to_rad(float(scan.get("from", 0.0))), "scan_to": deg_to_rad(float(scan.get("to", 0.0))),
		"scan_speed": deg_to_rad(float(scan.get("speed", 10.0))), "scan_pause": float(scan.get("pause", 1.0)), "scan_dir": 1, "scan_wait": 0.0,
		"suspicion": 0.0, "body_alert": 0.0, "seen_id": "", "spotted": false, "jumpy": 0.0,
		"path": [], "goal": at, "react": 0.0, "repath": 0.0,
		"search_time": 0.0, "search_total": SEARCH_TIME, "search_angle": facing, "search_count": 0,
		"target_id": "", "aim_time": 0.0, "aim_total": GUARD_AIM_TIME, "lost_time": 0.0, "fire_cooldown": 0.0, "fire_flash": 0.0,
		"stun_time": 0.0, "held_by": "", "was_stunned": false, "carried_by": "", "hidden": false, "found": false, "responder": false,
		"chat_with": "", "stripped": false, "trail_hops": 0, "track_clock": 0.0})
	if bool(guard.get("civilian", false)):
		# no gun and no business hunting anyone: he shouts, and stays where he is
		guard.alarm_hold = true
	if bool(guard.has_post):
		_set_state(guard, "post")
	if bool(guard.has_scan):
		guard.angle = wrapf(float(guard.scan_from), -PI, PI)
	if bool(guard.get("calm", false)) and bool(guard.get("civilian", false)):
		# a civilian minding his own business from the start (a neighbour out to watch the snow): he sees nothing,
		# raises nothing and is nobody's target (CALM_STATES)
		_set_state(guard, "calm")
	return guard

## A person of the rescue (data "people": {id, x, y, facing, look, group, exposure, flee, panic {at}}), kept on the guards'
## list as a civilian of kind "person" who is never on duty (PERSON_STATES are all DOWN_STATES).
func _make_person(spec: Dictionary) -> Dictionary:
	var entry: Dictionary = spec.duplicate(true)
	entry.merge({"kind": "person", "civilian": true, "person": true, "speed": 0.0, "range": 0.0, "near": 0.0, "fov": 0.0,
		"title": str(data.get("snowfall", {}).get("title", "PERSON"))})
	entry["post"] = [float(spec.x), float(spec.y), float(spec.get("facing", 90.0))]
	var person: Dictionary = _make_guard(entry)
	_set_state(person, "crowd")
	person["exposure"] = float(spec.get("exposure", 0.0))
	person["follow_id"] = ""
	person["rank"] = 0
	person["goal_id"] = ""
	person["shelter"] = ""
	person["fall_left"] = 0.0
	person["panicked"] = false
	person["warm"] = false
	person["calm"] = false
	return person

func selected() -> Dictionary:
	return unit_by_id(selected_id)

func unit_by_id(id: String) -> Dictionary:
	for unit: Dictionary in units:
		if unit.id == id:
			return unit
	return {}

func guard_by_id(id: String) -> Dictionary:
	for guard: Dictionary in guards:
		if guard.id == id:
			return guard
	return {}

func select(id: String) -> void:
	var unit: Dictionary = unit_by_id(id)
	if not unit.is_empty() and not bool(unit.get("away", false)):
		selected_id = id

func toggle_pause() -> void:
	if phase == "playing":
		paused = not paused
		message = "Tactical pause. Give each operative an order, then resume." if paused else "Orders executing. Watch the sight cones."

func toggle_stance() -> void:
	if phase != "playing":
		return
	var unit: Dictionary = selected()
	if bool(unit.get("fallen", false)) or not bool(unit.get("alive", true)):
		message = _snow_text("down", "%s is down in the snow.") % unit.name
		return
	if str(unit.carrying) != "":
		message = "%s cannot crouch while carrying a body." % unit.name
		return
	unit.stance = "walk" if unit.stance == "sneak" else "sneak"
	message = "%s: %s." % [unit.name, "walking: faster, seen across a whole sight cone" if unit.stance == "walk" else "crouched: unseen in the outer zone of a cone"]

# ---------------------------------------------------------------------------------------------
# Orders. Each acts on the selected operative, replaces his current order and returns false
# (with `message` saying why) when it cannot be given. While paused nothing moves, so the
# orders of both operatives begin together on resume.
# ---------------------------------------------------------------------------------------------
func move_to(destination: Vector2) -> bool:
	return _issue(selected(), {"type": "move", "x": destination.x, "y": destination.y})

## Context order kept for the old HUD: unlock (Rook), then free the informant, then head for the boat.
func interact() -> bool:
	if phase != "playing":
		return false
	if _locked_in():
		if not bool(selected().get("tools", false)):
			message = _door_text("refuse", "He does not have the tools for that lock.")
			return false
		return order_unlock()
	if not bool(prisoner.freed):
		return order_rescue()
	return order_extract()

func distract(target: Vector2) -> bool:
	return _issue(selected(), {"type": "distract", "x": target.x, "y": target.y})

func order_takedown(guard_id: String) -> bool:
	return _issue(selected(), {"type": "takedown", "target": guard_id})

func order_shoot(guard_id: String) -> bool:
	return _issue(selected(), {"type": "shoot", "target": guard_id})

func order_pickup(guard_id: String) -> bool:
	return _issue(selected(), {"type": "pickup", "target": guard_id})

## Puts the carried body down where the operative stands.
func drop_body() -> bool:
	return _issue(selected(), {"type": "drop"})

## Carries the body to `point` first, then puts it down (use a bush to hide it).
func order_drop(point: Vector2) -> bool:
	return _issue(selected(), {"type": "drop", "x": point.x, "y": point.y})

func place_trap() -> bool:
	return _issue(selected(), {"type": "trap"})

## Recovers an unsprung trap; with no id, the one nearest the operative.
func order_trap_pickup(trap_id: String = "") -> bool:
	return _issue(selected(), {"type": "trap_pickup", "target": trap_id})

func order_cut_fence() -> bool:
	return _issue(selected(), {"type": "cut"})

func order_sabotage() -> bool:
	return _issue(selected(), {"type": "sabotage"})

func order_unlock() -> bool:
	if not data.has("door"):
		return false  # an operation without a cell (Cockle)
	return _issue(selected(), {"type": "unlock"})

func order_rescue() -> bool:
	return _issue(selected(), {"type": "rescue"})

func order_extract() -> bool:
	return _issue(selected(), {"type": "extract"})

## Walks up to a calm guard and stops him for a smoke (an operative with "chat" in his data).
func order_chat(guard_id: String) -> bool:
	return _issue(selected(), {"type": "chat", "target": guard_id})

## Takes the uniform off a guard who is down (dead, bound or stunned) and puts it on (missions with "uniforms").
func order_uniform(guard_id: String) -> bool:
	return _issue(selected(), {"type": "uniform", "target": guard_id})

## Sets a charge at a site from data "charges"; with no id, the nearest one this operative carries charges for.
func order_plant(site_id: String = "") -> bool:
	return _issue(selected(), {"type": "plant", "target": site_id})

## Fixes a rope at a passage's anchor (data "passages"); with no id, the nearest one this operative can rig.
func order_rig(passage_id: String = "") -> bool:
	return _issue(selected(), {"type": "rig", "target": passage_id})

## Walks up to a civilian (data guards[].civilian) and talks him round: he sits it out and raises no alarm
## (an operative with "talk" in his data).
func order_talk(guard_id: String) -> bool:
	return _issue(selected(), {"type": "talk", "target": guard_id})

## A rescue: walks up to a person out in the snow and leads him (and those of his group standing by him) in, behind
## the operative (data "people"; at most units[].lead at once).
func order_guide(person_id: String) -> bool:
	return _issue(selected(), {"type": "guide", "target": person_id})

## A rescue: the operative's call (data units[].call): Benteveo's voice (everyone near follows him), Hornero's tram bell
## (everyone near makes for the tram by himself).
func order_call() -> bool:
	return _issue(selected(), {"type": "call"})

## A rescue: drives a vehicle (data "vehicles", Hornero's tram) to its next stop; with no id, the nearest he can drive.
func order_drive(vehicle_id: String = "") -> bool:
	return _issue(selected(), {"type": "drive", "target": vehicle_id})

## A rescue: takes a cloth (data "canvases") to hold over himself and the few behind him for one crossing.
func order_canvas(canvas_id: String = "") -> bool:
	return _issue(selected(), {"type": "canvas", "target": canvas_id})

## Gear left about the square (data "gear"): go and take it (the one named, or the nearest left he can use).
func order_take(gear_id: String = "") -> bool:
	return _issue(selected(), {"type": "take", "target": gear_id})

## A rescue: helps a squad mate who has fallen in the snow back on his feet.
func order_help(unit_id: String) -> bool:
	return _issue(selected(), {"type": "help", "target": unit_id})

## Drops the selected operative's order (a takedown already in progress is finished first).
func cancel_order() -> bool:
	var unit: Dictionary = selected()
	if phase != "playing" or unit.is_empty():
		return false
	unit.queued = {}
	if _locked(unit):
		return false
	_clear_order(unit)
	unit.path = []
	message = "%s: order cancelled." % unit.name
	return true

## Uniform entry point for the HUD: `action_id` is an id from available_actions() or an `order` from interactables().
func perform(action_id: String, target: Variant = null) -> bool:
	match action_id:
		"stance":
			if phase != "playing" or str(selected().carrying) != "":
				return false
			toggle_stance()
			return true
		"move": return target is Vector2 and move_to(target)
		"distract": return target is Vector2 and distract(target)
		"takedown": return target is String and order_takedown(target)
		"shoot": return target is String and order_shoot(target)
		"pickup": return target is String and order_pickup(target)
		"drop": return order_drop(target) if target is Vector2 else drop_body()
		"trap": return place_trap()
		"trap_pickup": return order_trap_pickup(target if target is String else "")
		"cut": return order_cut_fence()
		"sabotage": return order_sabotage()
		"unlock": return order_unlock()
		"rescue": return order_rescue()
		"extract": return order_extract()
		"plant": return order_plant(target if target is String else "")
		"chat": return target is String and order_chat(target)
		"uniform": return target is String and order_uniform(target)
		"rig": return order_rig(target if target is String else "")
		"talk": return target is String and order_talk(target)
		"guide": return target is String and order_guide(target)
		"call": return order_call()
		"drive": return order_drive(target if target is String else "")
		"canvas": return order_canvas(target if target is String else "")
		"take": return order_take(target if target is String else "")
		"help": return target is String and order_help(target)
		"interact": return interact()
		"cancel": return cancel_order()
	return false

func _locked(unit: Dictionary) -> bool:
	return bool(unit.acting) and unit.action == "takedown"

func _refuse(text: String) -> bool:
	message = text
	return false

func _issue(unit: Dictionary, order: Dictionary) -> bool:
	# routes for a boatman go over his own water (a crew passage); for everyone else it is the river
	var before: bool = _walk_as(_crew_for(str(unit.get("id", ""))))
	var accepted: bool = _issue_order(unit, order)
	_walk_as(before)
	return accepted

func _issue_order(unit: Dictionary, order: Dictionary) -> bool:
	if phase != "playing" or unit.is_empty() or not bool(unit.alive):
		return false
	if bool(unit.get("away", false)):
		return _refuse(str(unit.arrive.get("notYet", "%s is not here yet.")) % unit.name)
	if bool(unit.get("fallen", false)):
		return _refuse(_snow_text("down", "%s is down in the snow.") % unit.name)
	if _locked(unit):
		# A takedown cannot be abandoned half-way; the new order follows it.
		unit.queued = order.duplicate(true)
		message = "%s will do that next." % unit.name
		return true
	var kind: String = order.type
	var here: Vector2 = position_of(unit)
	var carrying: bool = str(unit.carrying) != ""
	if carrying and not kind in ["move", "drop", "extract"]:
		if bool(guard_by_id(str(unit.carrying)).get("person", false)):
			return _refuse(_snow_text("setDown", "%s must set him down first.") % unit.name)
		return _refuse("%s must put the body down first." % unit.name)
	var route: Array = []
	var action: String = kind
	var total: float = 0.0
	var spot: Vector2 = here
	match kind:
		"move":
			spot = Vector2(float(order.x), float(order.y))
			route = find_path(here, spot)
			var short: bool = false
			if route.is_empty():
				# A tap on a roof, the water, the wire or past the edge: go as far as he can along that line.
				var nearer: Vector2 = _back_along(here, spot, BODY_RADIUS, true)
				if not nearer.is_finite() or nearer.distance_to(here) < BACK_MIN_MOVE:
					return _refuse("%s cannot get any closer that way. Buildings, wire and water block movement." % unit.name)
				spot = nearer
				route = find_path(here, spot)
				if route.is_empty():
					return _refuse("%s cannot get any closer that way. Buildings, wire and water block movement." % unit.name)
				short = true
			action = ""
			message = "%s: %s." % [unit.name, ("order ready, resume to move" if paused else "moving") + (", as close as possible" if short else "")]
		"distract":
			spot = Vector2(float(order.x), float(order.y))
			var throw: Dictionary = throw_spec(unit)
			if throw.is_empty():
				return _refuse("%s has nothing to throw." % unit.name)
			if int(unit.get("throws", -1)) == 0:
				return _refuse(str(throw.get("empty", "%s has nothing left to throw.")) % unit.name)
			if float(unit.cooldown) > 0.0:
				return _refuse("Distraction ready in %.1f seconds." % float(unit.cooldown))
			# Past the range circle, into the water or off the map: it lands at the last open spot along the throw.
			if not spot.is_finite():
				return _refuse("Aim the distraction at open ground.")
			if here.distance_to(spot) > float(throw.range):
				spot = here + (spot - here).limit_length(float(throw.range))
			if is_blocked(spot, 2.0):
				spot = _back_along(here, spot, 2.0, false)
				if not spot.is_finite():
					return _refuse("Aim the distraction at open ground.")
			message = "Distraction queued. Resume to throw." if paused else "%s: distraction away." % unit.name
		"takedown":
			var guard: Dictionary = guard_by_id(str(order.get("target", "")))
			if not unit.has("melee"):
				return _refuse("%s has no way to do that." % unit.name)
			if guard.is_empty() or guard.state in ["dead", "bound"]:
				return _refuse("That guard is already out of the fight.")
			if str(guard.state) in CALM_STATES:
				return _refuse(str(guard.get("calmRefuse", "He is no danger to anyone now. Leave him be.")))
			if bool(guard.get("civilian", false)) and bool(unit.melee.get("lethal", false)):
				return _refuse(str(guard.get("spare", "%s will not harm a civilian.")) % unit.name)
			if bool(guard.melee_immune):
				return _refuse("He is out of reach up there. Only a bullet will do it.")
			if guard.state == "held":
				return _refuse("He is already being dealt with.")
			spot = position_of(guard)
			if not _within_reach(here, spot, MELEE_RANGE):
				route = find_path(here, spot)
				if route.is_empty():
					return _refuse("%s cannot reach him from here." % unit.name)
			total = _melee_time(unit, guard)
			message = "%s closes in: %s." % [unit.name, str(unit.melee.get("label", "takedown")).to_lower()]
		"shoot":
			var guard: Dictionary = guard_by_id(str(order.get("target", "")))
			var beast: bool = bool(guard.get("creature", false))
			if not unit.has("gun"):
				if beast: return _refuse(_creature_text("unarmed", "%s has nothing to fight it with. Keep away from it.") % unit.name)
				return _refuse("%s has no firearm." % unit.name)
			if int(unit.ammo) <= 0:
				return _refuse("%s is out of ammunition." % unit.name)
			if beast and str(guard.state) in ["dead", "waiting", "away"]:
				return _refuse(_creature_text("noTarget", "There is nothing there to shoot."))
			if guard.is_empty() or guard.state in ["dead", "bound"]:
				return _refuse("That guard is already out of the fight.")
			if bool(guard.get("civilian", false)):
				return _refuse(str(guard.get("spare", "%s will not harm a civilian.")) % unit.name)
			spot = position_of(guard)
			if not _has_shot(unit, guard):
				route = find_path(here, spot)
				if route.is_empty():
					# Nowhere to walk to (the tower): the player has to find the firing position himself.
					if here.distance_to(spot) > float(unit.gun.get("range", 240.0)):
						return _refuse("Too far for the %s. Move closer first." % str(unit.gun.get("label", "gun")).to_lower())
					return _refuse("%s has no line of fire from here." % unit.name)
			total = float(unit.gun.get("aim", 0.5))
			message = "%s takes aim." % unit.name if route.is_empty() else "%s moves up for a shot." % unit.name
		"pickup":
			var body: Dictionary = guard_by_id(str(order.get("target", "")))
			if body.is_empty() or not body.state in BODY_STATES or bool(body.get("creature", false)):
				return _refuse("There is nobody there to carry.")
			if float(body.elevation) > 0.0:
				return _refuse("He stays where he fell, up in the tower.")
			if str(body.carried_by) != "":
				return _refuse("He is already being carried.")
			if bool(body.hidden):
				# Hidden is hidden: a tap into that bush means "get in", never "dig him out again".
				return _refuse("He is hidden in the bush. Leave him there.")
			var fallen_person: bool = bool(body.get("person", false))
			if fallen_person and not bool(unit.get("carries", false)):
				return _refuse(_snow_text("carry", "Only Biguá is strong enough to carry him in."))
			spot = position_of(body)
			if not _within_reach(here, spot, PICKUP_RANGE):
				route = find_path(here, spot)
				if route.is_empty():
					return _refuse("%s cannot reach the body." % unit.name)
			total = PICKUP_TIME
			message = (_snow_text("lift", "%s will lift him onto his shoulders and carry him in.") if fallen_person else "%s will carry him. A body in a bush is never found.") % unit.name
		"drop":
			if not carrying:
				return _refuse("%s is not carrying anyone." % unit.name)
			if order.has("x"):
				spot = Vector2(float(order.x), float(order.y))
				route = find_path(here, spot)
				if route.is_empty():
					return _refuse("No clear route to carry him there.")
			total = DROP_TIME
			message = "%s will put him down %s." % [unit.name, "in cover" if in_bush(spot) else "there"]
		"trap":
			if int(unit.traps) <= 0:
				return _refuse("%s has no tripwire left." % unit.name)
			total = TRAP_SET_TIME
			message = "%s sets the tripwire here. The first guard to walk over it drops." % unit.name
		"trap_pickup":
			if int(unit.trap_kit) <= 0:
				return _refuse("He has no tripwire.")
			var trap: Dictionary = _trap_for(str(order.get("target", "")), here)
			if trap.is_empty():
				return _refuse("There is no tripwire to recover.")
			order = order.duplicate()
			order["target"] = str(trap.id)
			spot = Vector2(float(trap.x), float(trap.y))
			if here.distance_to(spot) > WORK_REACH:
				route = find_path(here, spot)
				if route.is_empty():
					return _refuse("%s cannot reach the tripwire." % unit.name)
			total = TRAP_LIFT_TIME
			message = "%s will recover the tripwire." % unit.name
		"cut":
			if not data.has("fence"):
				return _refuse("There is no wire to cut here.")
			if not bool(unit.tools):
				return _refuse(str(data.fence.get("refuse", "He has no wire cutters.")))
			if fence_cut:
				return _refuse(str(data.fence.get("already", "The wire is already cut.")))
			# The span can be cut from either side; take whichever is the shorter walk.
			var best: float = INF
			for point: Vector2 in _fence_points():
				var close: bool = _within_reach(here, point, WORK_REACH)
				var candidate: Array = [] if close else find_path(here, point)
				if not close and candidate.is_empty():
					continue
				var length: float = _path_length(here, candidate)
				if length < best:
					best = length
					route = candidate
					spot = point
			if best == INF:
				return _refuse("The cuttable span of the fence cannot be reached from here.")
			total = float(data.fence.get("time", CUT_TIME))
			message = _named(str(data.fence.get("order", "%s will cut the wire. It takes a few seconds.")), str(unit.name))
		"sabotage":
			if not data.has("radio"):
				return _refuse("There is nothing to sabotage here.")
			if not can_sabotage(unit):
				return _refuse(str(data.radio.get("refuse", "He does not have the tools for that.")))
			if radio_cut:
				return _refuse(str(data.radio.get("already", "The radio is already dead.")))
			spot = Vector2(float(data.radio.x), float(data.radio.y))
			if here.distance_to(spot) > WORK_REACH:
				route = find_path(here, spot)
				if route.is_empty():
					return _refuse(str(data.radio.get("unreachable", "The generator cannot be reached from here.")))
			total = float(data.radio.get("time", SABOTAGE_TIME))
			message = str(data.radio.get("order", "%s will kill the generator. No radio, no reinforcements.")) % unit.name
		"plant":
			var site: Dictionary = _site_for(unit, str(order.get("target", "")), here)
			if site.is_empty():
				return _refuse(_plant_refusal(unit, str(order.get("target", ""))))
			order = order.duplicate()
			order["target"] = str(site.id)
			spot = Vector2(float(site.x), float(site.y))
			if here.distance_to(spot) > WORK_REACH:
				route = find_path(here, spot)
				if route.is_empty():
					return _refuse("%s cannot reach that from here." % unit.name)
			total = float(site.get("time", SABOTAGE_TIME))
			message = str(site.get("order", "%s will set the charge.")) % unit.name
		"unlock":
			if not bool(unit.tools):
				return _refuse(_door_text("refuse", "He does not have the tools for that lock."))
			if door_open:
				return _refuse(_door_text("already", "The cell is already open."))
			spot = Vector2(float(data.door.interactX), float(data.door.interactY))
			if here.distance_to(spot) > 1.0:
				route = find_path(here, spot)
				if route.is_empty():
					return _refuse("The objective cannot be reached from here. Move to open ground.")
			total = UNLOCK_TIME
			message = _named(_door_text("order", "%s will move to the cell gate and pick the lock."), str(unit.name))
		"rescue":
			if _locked_in():
				return _refuse(_door_text("locked", "The cell is still locked."))
			if not bool(prisoner.alive):
				return false
			if bool(prisoner.aboard):
				return _refuse(_prisoner_text("already", "The informant is already in the boat."))
			if bool(prisoner.freed) and str(prisoner.follow_id) == str(unit.id):
				return _refuse(_named(_prisoner_text("following", "The informant is already following %s."), str(unit.name)))
			spot = position_of(prisoner)
			if not _within_reach(here, spot, RESCUE_RANGE):
				route = find_path(here, spot)
				if route.is_empty():
					return _refuse("The objective cannot be reached from here. Move to open ground.")
			total = RESCUE_TIME
			var task: String = _prisoner_text("takeOver", "take over the escort") if bool(prisoner.freed) else _prisoner_text("free", "free the informant")
			message = _prisoner_text("order", "%s will %s. Keep the return route clear.") % [unit.name, task]
		"chat":
			var guard: Dictionary = guard_by_id(str(order.get("target", "")))
			var chat: Dictionary = unit.get("chat", {})
			if chat.is_empty():
				return _refuse("%s has nothing to offer him." % unit.name)
			if int(unit.smokes) <= 0:
				return _refuse(str(chat.get("empty", "%s has no cigarettes left.")) % unit.name)
			if guard.is_empty() or not _is_able(guard):
				return _refuse("He is in no state for a smoke.")
			if float(guard.elevation) > 0.0:
				return _refuse(str(chat.get("high", "He is up out of reach. %s cannot call him down.")) % unit.name)
			if bool(alarm.active) or not str(guard.state) in CHAT_STATES:
				return _refuse(str(chat.get("edgy", "He is on edge. Not now.")))
			if str(guard.chat_with) != "":
				return _refuse("He is already having a smoke.")
			if _restricted(unit, position_of(guard)):
				return _refuse(str(chat.get("restricted", "%s has no business in there.")) % unit.name)
			if carrying:
				return _refuse("%s must put the body down first." % unit.name)
			spot = position_of(guard)
			if not _within_reach(here, spot, CHAT_RANGE):
				route = find_path(here, spot)
				if route.is_empty():
					return _refuse("%s cannot get to him from here." % unit.name)
			total = float(chat.get("time", CHAT_TIME))
			# a docker strolls over: upright, unremarkable
			unit.stance = "walk"
			unit.stance_before = "walk"
			message = str(chat.get("order", "%s strolls over with a cigarette.")) % unit.name
		"uniform":
			var spec: Dictionary = data.get("uniforms", {})
			var body: Dictionary = guard_by_id(str(order.get("target", "")))
			if spec.is_empty():
				return _refuse("There is no time for that tonight.")
			if body.is_empty() or not body.state in BODY_STATES:
				return _refuse(str(spec.get("standing", "Put him down first. Then his uniform is yours.")))
			if bool(body.stripped):
				return _refuse(str(spec.get("taken", "His uniform is already gone.")))
			if float(body.elevation) > 0.0:
				return _refuse("He is out of reach up there.")
			if str(body.carried_by) != "":
				return _refuse("Put him down first.")
			spot = position_of(body)
			if not _within_reach(here, spot, PICKUP_RANGE):
				route = find_path(here, spot)
				if route.is_empty():
					return _refuse("%s cannot reach him." % unit.name)
			total = float(spec.get("time", UNIFORM_TIME))
			message = str(spec.get("order", "%s will take his uniform.")) % unit.name
		"rig":
			var passage: Dictionary = _passage_for(unit, str(order.get("target", "")), here)
			if passage.is_empty():
				return _refuse(_rig_refusal(unit, str(order.get("target", ""))))
			order = order.duplicate()
			order["target"] = str(passage.id)
			spot = passage_anchor(passage)
			if here.distance_to(spot) > WORK_REACH:
				route = find_path(here, spot)
				if route.is_empty():
					return _refuse(_named(str(passage.get("unreachable", "%s cannot get to the anchor from here.")), str(unit.name)))
			# a quieter way for those who know it (Rook cutting the glass out instead of breaking it): slower, silent
			var quiet: Dictionary = passage.get("quiet", {})
			if quiet.has(str(unit.id)):
				total = float(quiet[str(unit.id)])
				message = _named(str(passage.get("orderQuiet", passage.get("order", "%s will fix the rope."))), str(unit.name))
			else:
				total = float(passage.get("time", SABOTAGE_TIME))
				message = _named(str(passage.get("order", "%s will fix the rope.")), str(unit.name))
		"talk":
			var guard: Dictionary = guard_by_id(str(order.get("target", "")))
			var talk: Dictionary = unit.get("talk", {})
			if talk.is_empty():
				return _refuse("%s has nothing to say to him." % unit.name)
			if guard.is_empty() or not bool(guard.get("civilian", false)):
				return _refuse(str(talk.get("soldier", "He is a soldier. Talk will not stop him.")))
			if str(guard.state) in CALM_STATES:
				return _refuse(str(talk.get("already", "He is already keeping still.")))
			if not _is_able(guard):
				return _refuse("He is in no state to listen.")
			if carrying:
				return _refuse("%s must put the body down first." % unit.name)
			spot = position_of(guard)
			if not _within_reach(here, spot, TALK_RANGE):
				route = find_path(here, spot)
				if route.is_empty():
					return _refuse("%s cannot get to him from here." % unit.name)
			total = float(talk.get("time", TALK_TIME))
			message = str(talk.get("order", "%s goes to have a quiet word with him.")) % unit.name
		"extract":
			var exit: Dictionary = unit.get("exit", data.get("extraction", {}))
			if exit.is_empty():
				return false
			spot = Vector2(float(exit.x), float(exit.y))
			# Stand side by side in the ring instead of on one spot.
			var slot: Vector2 = spot + Vector2(-16.0 + 32.0 * float(units.find(unit)), 0.0)
			if not unit.has("exit") and not is_blocked(slot):
				spot = slot
			if here.distance_to(spot) > 1.0:
				route = find_path(here, spot)
				if route.is_empty():
					return _refuse("The objective cannot be reached from here. Move to open ground.")
			message = (str(exit.get("order", "%s is on his way out.")) if unit.has("exit") else str(data.get("extractMessage", "%s is heading to extraction. Bring both operatives and the informant."))) % unit.name
		"guide":
			var person: Dictionary = guard_by_id(str(order.get("target", "")))
			if not rescue_on or person.is_empty() or not bool(person.get("person", false)):
				return _refuse(_snow_text("nobody", "There is nobody there to lead."))
			match str(person.state):
				"safe": return _refuse(_snow_text("already", "They are already under cover."))
				"fallen": return _refuse(_snow_text("fallenRefuse", "They have fallen. Only Biguá can carry them in now."))
				"lost": return _refuse(_snow_text("lostRefuse", "The snow has covered them."))
			if str(person.state) == "follow" and str(person.follow_id) == str(unit.id):
				return _refuse(_snow_text("following", "They are already following %s.") % unit.name)
			if bool(person.get("stuck", false)):
				return _refuse(_snow_text("stuckRefuse", "They are too far gone to walk another step. Bring the colectivo to them."))
			if followers_of(str(unit.id)).size() >= lead_of(unit):
				return _refuse(_snow_text("full", "%s is leading as many as he can. Bring them in first.") % unit.name)
			spot = position_of(person)
			if not _within_reach(here, spot, RESCUE_RANGE):
				route = find_path(here, spot)
				if route.is_empty():
					return _refuse("%s cannot get to him from here." % unit.name)
			total = float(_snowfall().get("guideTime", GUIDE_TIME))
			message = _snow_text("guide", "%s goes to bring them in.") % unit.name
		"call":
			var call: Dictionary = unit.get("call", {})
			if call.is_empty() or not rescue_on:
				return _refuse("%s has no way to call them." % unit.name)
			if int(unit.get("calls", -1)) == 0:
				return _refuse(str(call.get("empty", "%s has called enough.")) % unit.name)
			if float(unit.cooldown) > 0.0:
				return _refuse(_snow_text("callWait", "Ready to call again in %.1f seconds.") % float(unit.cooldown))
			var from: String = str(call.get("from", ""))
			if from != "" and vehicle_at(here) != from:
				return _refuse(str(call.get("away", "%s has to be there to do that.")) % unit.name)
			if str(call.get("mode", "follow")) == "follow" and followers_of(str(unit.id)).size() >= lead_of(unit):
				return _refuse(str(call.get("full", "%s cannot lead any more at once.")) % unit.name)
			message = _snow_text("callReady", "%s calls them.") % unit.name
		"drive":
			var vehicle: Dictionary = _vehicle_for(unit, str(order.get("target", "")))
			if vehicle.is_empty():
				return _refuse(_drive_refusal(unit, str(order.get("target", ""))))
			if int(vehicles[str(vehicle.id)].to) >= 0:
				return _refuse(str(vehicle.get("moving", "It is already moving.")))
			order = order.duplicate()
			order["target"] = str(vehicle.id)
			var inside: Rect2 = vehicle_rect(str(vehicle.id))
			spot = inside.get_center()
			if not inside.has_point(here):
				route = find_path(here, spot)
				if route.is_empty():
					return _refuse(_named(str(vehicle.get("unreachable", "%s cannot get to it from here.")), str(unit.name)))
			else:
				spot = here
			total = float(vehicle.get("time", 1.0))
			message = _named(str(vehicle.get("order", "%s will drive it on.")), str(unit.name))
		"canvas":
			if not (unit.get("canvas", {}) as Dictionary).is_empty():
				return _refuse(_snow_text("holding", "%s is already holding a cloth over them.") % unit.name)
			var canvas: Dictionary = _canvas_for(str(order.get("target", "")), here)
			if canvas.is_empty():
				return _refuse(_snow_text("noCanvas", "There is no cloth left to take."))
			order = order.duplicate()
			order["target"] = str(canvas.id)
			var cloth: Vector2 = Vector2(float(canvas.x), float(canvas.y))
			spot = cloth
			if here.distance_to(cloth) > CANVAS_REACH_TAKE:
				route = find_path(here, cloth)
				if route.is_empty():
					return _refuse("%s cannot get to it from here." % unit.name)
			total = float(_snowfall().get("canvasTime", CANVAS_TIME))
			message = _named(str(canvas.get("order", "%s goes for the cloth.")), str(unit.name))
		"take":
			var item: Dictionary = _gear_for(str(order.get("target", "")), here)
			if item.is_empty():
				return _refuse(_snow_text("noGear", "There is nothing left there to take."))
			var why: String = _gear_refusal(unit, item)
			if why != "":
				return _refuse(why)
			order = order.duplicate()
			order["target"] = str(item.id)
			var thing := Vector2(float(item.x), float(item.y))
			spot = thing
			if here.distance_to(thing) > CANVAS_REACH_TAKE:
				route = find_path(here, thing)
				if route.is_empty():
					return _refuse("%s cannot get to it from here." % unit.name)
			total = float(item.get("time", 1.5))
			message = _named(str(item.get("order", "%s goes for it.")), str(unit.name))
		"help":
			var mate: Dictionary = unit_by_id(str(order.get("target", "")))
			if mate.is_empty() or str(mate.id) == str(unit.id) or not bool(mate.get("fallen", false)) or not bool(mate.alive):
				return _refuse(_snow_text("helpNobody", "Nobody there to help up."))
			spot = position_of(mate)
			if not _within_reach(here, spot, RESCUE_RANGE):
				route = find_path(here, spot)
				if route.is_empty():
					return _refuse("%s cannot get to him from here." % unit.name)
			total = float(_snowfall().get("helpTime", HELP_TIME))
			message = _snow_text("helpOrder", "%s goes to get %s back on his feet.") % [unit.name, mate.name]
		_:
			return false
	if paused and kind != "move" and kind != "distract":
		message += " Order queued."
	unit.path = route
	unit.action = action
	unit.action_time = 0.0
	unit.action_total = total
	unit.acting = false
	unit.repath = PURSUIT_REPATH
	unit.queued = {}
	var record: Dictionary = order.duplicate(true)
	record["x"] = spot.x
	record["y"] = spot.y
	unit.order = record
	if kind == "distract":
		unit.action_target = spot
	return true

func _melee_time(unit: Dictionary, guard: Dictionary) -> float:
	var melee: Dictionary = unit.melee
	if guard.state == "stunned" or (guard.state == "held" and bool(guard.was_stunned)):
		return float(melee.get("time_stunned", melee.get("time", 0.5)))
	return float(melee.get("time", 0.5))

func _trap_for(id: String, near_point: Vector2) -> Dictionary:
	var found: Dictionary = {}
	var best: float = INF
	for trap: Dictionary in traps:
		if id != "" and trap.id != id:
			continue
		var distance: float = near_point.distance_to(Vector2(float(trap.x), float(trap.y)))
		if distance < best:
			best = distance
			found = trap
	return found

func _fence_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	if data.has("fence"):
		for point: Array in data.fence.get("interact", []):
			points.append(Vector2(float(point[0]), float(point[1])))
	return points

func _path_length(from: Vector2, route: Array) -> float:
	var total: float = 0.0
	var cursor: Vector2 = from
	for point: Vector2 in route:
		total += cursor.distance_to(point)
		cursor = point
	return total

func _clear_order(unit: Dictionary) -> void:
	unit.action = ""
	unit.action_time = 0.0
	unit.action_total = 0.0
	unit.acting = false
	unit.order = {}

func _finish_order(unit: Dictionary) -> void:
	_clear_order(unit)
	unit.path = []
	var next: Dictionary = unit.queued
	unit.queued = {}
	if not next.is_empty():
		_issue(unit, next)

func _fail_order(unit: Dictionary, text: String) -> void:
	_clear_order(unit)
	unit.path = []
	unit.queued = {}
	message = text

# ---------------------------------------------------------------------------------------------
# Simulation step
# ---------------------------------------------------------------------------------------------
func update(delta: float) -> void:
	if phase != "playing" or paused:
		return
	var dt: float = minf(delta, 0.06)
	time += dt
	stats.time = time
	_hunt_searches = 0
	for unit: Dictionary in units:
		var crew: bool = _walk_as(_crew_for(str(unit.id)))
		_update_unit(unit, dt)
		_walk_as(crew)
	# the one being got out goes where his escort goes: over the boatman's water too, behind the boatman
	var with_crew: bool = _walk_as(_crew_for(str(prisoner.get("follow_id", ""))))
	_update_prisoner(dt)
	_walk_as(with_crew)
	if rescue_on:
		_update_vehicles(dt)
		_update_people(dt)
		_expose(dt)
		_watch_snow()
		_creatures_hear()
	_update_alarm(dt)
	for index: int in range(guards.size()):
		_update_guard(guards[index], index, dt)
		if phase != "playing":
			return
	_spring_traps()
	for guard: Dictionary in guards:
		_perceive(guard, dt)
		_notice_tracks(guard, dt)
	_burn_fuse(dt)
	if phase != "playing":
		return
	for index: int in range(noise.size() - 1, -1, -1):
		noise[index].ttl -= dt
		if float(noise[index].ttl) <= 0.0:
			noise.remove_at(index)
	_check_extraction()
	_check_rescue()
	if _pending_checkpoint != "" and phase == "playing" and can_save_checkpoint():
		var label: String = _pending_checkpoint
		_pending_checkpoint = ""
		_store_checkpoint(label, true)

## Behind the launch screen: the guards walk their rounds and keep their posts, nothing else moves and nobody
## notices anything. Only before the operation starts (phase "briefing"); reset() puts them back.
func idle(delta: float) -> void:
	if phase != "briefing":
		return
	var dt: float = minf(delta, 0.06)
	for index: int in range(guards.size()):
		_update_guard(guards[index], index, dt)

# --- operatives ---
func _update_unit(unit: Dictionary, dt: float) -> void:
	if not bool(unit.alive):
		return
	if bool(unit.get("away", false)):
		# not here yet: he comes in when his time comes
		if time >= float(unit.arrive.get("at", 0.0)):
			_arrive(unit)
		return
	unit.cooldown = maxf(0.0, float(unit.cooldown) - dt)
	unit.weapon_cooldown = maxf(0.0, float(unit.weapon_cooldown) - dt)
	if bool(unit.get("fallen", false)):
		# down in the snow: he kneels where he fell until a mate gets him up or the snow covers him
		unit.hidden = false
		unit.exposed = true
		unit.covered = false
		return
	if unit.action == "distract":
		_throw_distraction(unit)
	elif unit.action == "call":
		_call_people(unit)
	var carrying: bool = str(unit.carrying) != ""
	var before: Vector2 = position_of(unit)
	if not bool(unit.acting):
		var speed: float = CARRY_SPEED if carrying else (SNEAK_SPEED if unit.stance == "sneak" else WALK_SPEED)
		# leading people in, he keeps to their pace (they are slower than he is)
		if rescue_on and not followers_of(str(unit.id)).is_empty():
			speed = minf(speed, float(_snowfall().get("speed", PERSON_SPEED)))
		unit["skiing"] = skiing(unit)
		if bool(unit.skiing):
			speed *= float(unit.skis.get("speed", 1.5))
		_advance(unit, speed, dt)
	_lay_tracks(unit, before)
	if carrying:
		var body: Dictionary = guard_by_id(str(unit.carrying))
		body.x = unit.x
		body.y = unit.y
	_process_action(unit, dt)
	# a rescue: carrying a fallen person in under cover, he sets him down there as soon as he stops
	if rescue_on and str(unit.carrying) != "" and str(unit.action) == "" and (unit.path as Array).is_empty() and shelter_at(position_of(unit), true) != "":
		if bool(guard_by_id(str(unit.carrying)).get("person", false)):
			_issue(unit, {"type": "drop"})
	unit.hidden = unit.stance == "sneak" and str(unit.carrying) == "" and in_bush(position_of(unit))
	unit["camouflaged"] = camouflaged(unit)
	if bool(unit.camouflaged):
		unit.hidden = true
	unit.exposed = is_exposed(unit)
	unit.covered = covered(unit)

func _process_action(unit: Dictionary, dt: float) -> void:
	var here: Vector2 = position_of(unit)
	match str(unit.action):
		"":
			if unit.path.is_empty() and not unit.order.is_empty():
				unit.order = {}
		"extract":
			if unit.path.is_empty():
				_finish_order(unit)
		"unlock":
			if door_open:
				_finish_order(unit)
			elif _work_at(unit, Vector2(float(data.door.interactX), float(data.door.interactY)), UNLOCK_REACH, dt):
				door_open = true
				_complete_objective("cell")
				_emit({"type": "unlock", "by": unit.id})
				_pending_checkpoint = "gate"
				_finish_order(unit)
				message = _door_text("done", "Cell unlocked. Free the informant, then get everyone to the boat.")
		"rescue":
			if _approach(unit, position_of(prisoner), RESCUE_RANGE, dt) and _tick_action(unit, dt):
				var first: bool = not bool(prisoner.freed)
				prisoner.freed = true
				prisoner.follow_id = unit.id
				prisoner.path = []
				if first:
					_complete_objective("informant")
					_emit({"type": "rescued", "by": unit.id})
					_pending_checkpoint = "informant"
				else:
					_emit({"type": "escort", "by": unit.id})
				_finish_order(unit)
				message = _named(_prisoner_text("follows", "The informant follows %s. He cannot crouch: every cone sees him, unless he stands still in a bush."), str(unit.name))
		"takedown":
			_process_takedown(unit, dt)
		"shoot":
			_process_shot(unit, dt)
		"pickup":
			var body: Dictionary = guard_by_id(str(unit.order.get("target", "")))
			if body.is_empty() or not body.state in BODY_STATES or str(body.carried_by) != "":
				_fail_order(unit, "%s: nobody there to carry any more." % unit.name)
			elif _approach(unit, position_of(body), PICKUP_RANGE, dt) and _tick_action(unit, dt):
				unit.carrying = body.id
				unit.stance_before = unit.stance
				unit.stance = "walk"
				body.carried_by = unit.id
				body.hidden = false
				body.x = unit.x
				body.y = unit.y
				_emit({"type": "pickup", "by": unit.id, "body": body.id})
				_finish_order(unit)
				message = "%s is carrying a body: slow, upright and easy to see." % unit.name
		"drop":
			if _work_at(unit, here, INF, dt):
				_put_down(unit)
				_finish_order(unit)
		"trap":
			if _work_at(unit, here, INF, dt):
				_trap_serial += 1
				traps.append({"id": "trap%d" % _trap_serial, "x": here.x, "y": here.y, "by": unit.id})
				unit.traps = int(unit.traps) - 1
				_emit({"type": "trap_set", "by": unit.id, "trap": "trap%d" % _trap_serial, "x": here.x, "y": here.y})
				_finish_order(unit)
				message = "Tripwire set. The first guard across it is out for %d seconds." % int(STUN_TIME)
		"trap_pickup":
			var trap: Dictionary = _trap_for(str(unit.order.get("target", "")), here)
			if trap.is_empty() or trap.id != str(unit.order.get("target", "")):
				_fail_order(unit, "The tripwire is gone.")
			elif _work_at(unit, Vector2(float(trap.x), float(trap.y)), WORK_REACH, dt):
				traps.erase(trap)
				unit.traps = int(unit.traps) + 1
				_emit({"type": "trap_lifted", "by": unit.id, "trap": trap.id})
				_finish_order(unit)
				message = "%s has the tripwire back." % unit.name
		"cut":
			if fence_cut:
				_finish_order(unit)
			elif _work_at(unit, Vector2(float(unit.order.x), float(unit.order.y)), WORK_REACH, dt):
				fence_cut = true
				_emit({"type": "fence_cut", "by": unit.id})
				_finish_order(unit)
				message = str(data.fence.get("done", "The wire is cut. Anyone can slip through the gap now."))
		"sabotage":
			if radio_cut:
				_finish_order(unit)
			elif _work_at(unit, Vector2(float(data.radio.x), float(data.radio.y)), WORK_REACH, dt):
				radio_cut = true
				alarm.reinforce_pending = 0
				_cut_power()
				_complete_objective("radio")
				_emit({"type": "radio_cut", "by": unit.id})
				_finish_order(unit)
				message = str(data.radio.get("done", "The generator is dead. An alarm will bring no reinforcements now."))
		"chat":
			_process_chat(unit, dt)
		"rig":
			var passage: Dictionary = passage_by_id(str(unit.order.get("target", "")))
			if passage.is_empty() or rigged.has(str(passage.id)):
				_finish_order(unit)
			elif _work_at(unit, passage_anchor(passage), WORK_REACH, dt):
				rigged[str(passage.id)] = str(unit.id)
				_geometry_dirty = true
				# a passage that is an objective of its own (a rescue: the arcade's lights, the service gate)
				if str(passage.get("objective", "")) != "":
					_complete_objective(str(passage.objective))
				var anchor: Vector2 = passage_anchor(passage)
				var quietly: bool = (passage.get("quiet", {}) as Dictionary).has(str(unit.id))
				_emit({"type": "rigged", "by": unit.id, "passage": str(passage.id), "kind": str(passage.get("kind", "rope")), "quiet": quietly,
					"x": anchor.x, "y": anchor.y})
				if bool(passage.get("checkpoint", true)):
					_pending_checkpoint = str(passage.id)
				_finish_order(unit)
				message = str(passage.get("doneQuiet", passage.get("done", "")) if quietly else passage.get("done", "The rope is fixed. Anyone can climb across now."))
				# breaking a window is heard: guards near enough come to look (not when it was done the quiet way)
				if float(passage.get("noise", 0.0)) > 0.0 and not quietly:
					_lure_guards(anchor, float(passage.noise), false, str(passage.get("sound", "glass")))
		"talk":
			var guard: Dictionary = guard_by_id(str(unit.order.get("target", "")))
			var talk: Dictionary = unit.get("talk", {})
			var calmed: bool = not guard.is_empty() and str(guard.state) in CALM_STATES
			if guard.is_empty() or (not calmed and not _is_able(guard)):
				_fail_order(unit, "%s: there is nobody to talk to now." % unit.name)
			elif not calmed:
				if _approach(unit, position_of(guard), TALK_RANGE, dt):
					# a word in his own language, close and quiet: he stops where he is and keeps still
					_set_state(guard, "calm")
					guard.path = []
					guard.suspicion = 0.0
					guard.seen_id = ""
					guard.spotted = false
					guard["calm_by"] = str(unit.id)
					_face_point(guard, position_of(unit), PI)
					_emit({"type": "talk", "by": unit.id, "guard": guard.id, "x": float(guard.x), "y": float(guard.y)})
					message = str(talk.get("start", "%s speaks to him quietly in his own language.")) % unit.name
			elif _tick_action(unit, dt):
				_emit({"type": "calmed", "by": unit.id, "guard": guard.id})
				_finish_order(unit)
				message = str(talk.get("done", "He will keep still and raise no alarm."))
		"uniform":
			var body: Dictionary = guard_by_id(str(unit.order.get("target", "")))
			if body.is_empty() or not body.state in BODY_STATES or str(body.carried_by) != "" or bool(body.stripped):
				_fail_order(unit, "%s: his uniform is out of reach now." % unit.name)
			elif _approach(unit, position_of(body), PICKUP_RANGE, dt) and _tick_action(unit, dt):
				_put_on_uniform(unit, body)
				_finish_order(unit)
		"guide":
			var person: Dictionary = guard_by_id(str(unit.order.get("target", "")))
			if person.is_empty() or not str(person.state) in LEADABLE_STATES or (str(person.state) == "follow" and str(person.follow_id) == str(unit.id)):
				_fail_order(unit, _snow_text("gone", "%s: there is nobody there to lead now.") % unit.name)
			elif followers_of(str(unit.id)).size() >= lead_of(unit):
				_fail_order(unit, _snow_text("full", "%s is leading as many as he can. Bring them in first.") % unit.name)
			elif _approach(unit, position_of(person), RESCUE_RANGE, dt) and _tick_action(unit, dt):
				var joined: int = _lead(unit, person)
				_finish_order(unit)
				message = (_snow_text("guided", "%d follow %s. Lead them in under cover.") % [joined, unit.name]) if joined > 1 else (_snow_text("guidedOne", "One follows %s. Lead them in under cover.") % unit.name)
		"drive":
			var vid: String = str(unit.order.get("target", ""))
			var state: Dictionary = vehicles.get(vid, {})
			if state.is_empty():
				_fail_order(unit, "%s could not get there." % unit.name)
			elif bool(unit.order.get("started", false)):
				# at the controls while it runs; the order is done when it stops
				if int(state.to) < 0:
					state.driver = ""
					_finish_order(unit)
					message = str(vehicle_spec(vid).get("done", "It stops."))
			elif int(state.to) >= 0:
				_fail_order(unit, str(vehicle_spec(vid).get("moving", "It is already moving.")))
			elif _work_at(unit, position_of(unit), INF, dt):
				if not vehicle_rect(vid).has_point(position_of(unit)):
					_fail_order(unit, "%s could not get there." % unit.name)
				else:
					_start_vehicle(vid, unit)
					unit.order["started"] = true
		"canvas":
			var canvas: Dictionary = canvas_by_id(str(unit.order.get("target", "")))
			if canvas.is_empty() or canvases_taken.has(str(canvas.id)):
				_fail_order(unit, _snow_text("canvasGone", "The cloth is gone."))
			elif _work_at(unit, Vector2(float(canvas.x), float(canvas.y)), CANVAS_REACH_TAKE + 2.0, dt):
				canvases_taken[str(canvas.id)] = str(unit.id)
				unit["canvas"] = {"id": str(canvas.id), "left": float(canvas.get("time", 50.0)), "holds": int(canvas.get("holds", 3)), "out": false}
				_emit({"type": "canvas", "by": str(unit.id), "canvas": str(canvas.id), "x": float(canvas.x), "y": float(canvas.y)})
				_finish_order(unit)
				message = _named(str(canvas.get("take", "%s takes the cloth.")), str(unit.name))
		"take":
			var item: Dictionary = gear_by_id(str(unit.order.get("target", "")))
			if item.is_empty() or gear_taken.has(str(item.id)):
				_fail_order(unit, _snow_text("gearGone", "Somebody has taken it already."))
			elif _work_at(unit, Vector2(float(item.x), float(item.y)), CANVAS_REACH_TAKE + 2.0, dt):
				_take_gear(unit, item)
				_finish_order(unit)
		"help":
			var mate: Dictionary = unit_by_id(str(unit.order.get("target", "")))
			if mate.is_empty() or not bool(mate.get("fallen", false)) or not bool(mate.alive):
				_fail_order(unit, _snow_text("helpNobody", "Nobody there to help up."))
			elif _approach(unit, position_of(mate), RESCUE_RANGE, dt) and _tick_action(unit, dt):
				_help_up(mate, unit)
				_finish_order(unit)
		"plant":
			var site: Dictionary = charge_site(str(unit.order.get("target", "")))
			if site.is_empty() or planted.has(str(site.id)):
				_finish_order(unit)
			elif _work_at(unit, Vector2(float(site.x), float(site.y)), WORK_REACH, dt):
				planted[str(site.id)] = str(unit.id)
				var objective: String = str(site.get("objective", ""))
				var left: int = sites_left(objective)
				_emit({"type": "planted", "by": unit.id, "site": str(site.id), "kind": str(site.get("kind", "charge")), "objective": objective, "left": left, "x": float(site.x), "y": float(site.y)})
				if objective != "" and left == 0:
					_complete_objective(objective)
					_emit({"type": "objective", "id": objective})
					_pending_checkpoint = objective
				_finish_order(unit)
				var lit: bool = _light_fuse()
				var label: String = str(site.get("label", "Charge"))
				if lit:
					message = str(data.fuse.get("lit", "The fuses are lit. {seconds} seconds: get clear.")).replace("{seconds}", str(int(fuse_left)))
				elif left == 0:
					message = str(site.get("finished", "%s set." % label))
				else:
					message = str(site.get("done", label + " set. {left} to go.")).replace("{left}", str(left))

## The cigarette: walk up to him (he may be walking), stop him, stand with him until it is smoked.
func _process_chat(unit: Dictionary, dt: float) -> void:
	var guard: Dictionary = guard_by_id(str(unit.order.get("target", "")))
	var chat: Dictionary = unit.get("chat", {})
	var talking: bool = not guard.is_empty() and str(guard.chat_with) == str(unit.id)
	if guard.is_empty() or not _is_able(guard) or bool(alarm.active) or (not talking and not str(guard.state) in CHAT_STATES):
		if talking: _end_chat(guard)
		_fail_order(unit, str(chat.get("broken", "The smoke is off.")))
		return
	if not talking:
		if not _approach(unit, position_of(guard), CHAT_RANGE, dt):
			return
		# he stops; they light up
		unit.smokes = int(unit.smokes) - 1
		guard.chat_with = unit.id
		guard.path = []
		guard.wait = 0.0
		guard.has_return = true
		guard.return_x = guard.x
		guard.return_y = guard.y
		_set_state(guard, "chat")
		_emit({"type": "chat", "by": unit.id, "guard": guard.id, "x": float(guard.x), "y": float(guard.y), "left": int(unit.smokes)})
		message = str(chat.get("start", "%s offers a light. The guard stops for a smoke.")) % unit.name
		return
	if _tick_action(unit, dt):
		_end_chat(guard)
		_finish_order(unit)
		message = str(chat.get("done", "The cigarette is done. He goes back to his round."))

## Lets a guard go back to his round after a smoke (or when it is cut short).
func _end_chat(guard: Dictionary) -> void:
	var with: String = str(guard.chat_with)
	guard.chat_with = ""
	if str(guard.state) == "chat":
		_resume_duty(guard, 0.0)
	_emit({"type": "chat_end", "guard": guard.id, "by": with})

## True when guards take no notice of this operative: he has "cover" (a local in his own clothes), is
## upright and empty-handed, is not at a job that would give him away, stands outside the zones where he has no
## business, and no alarm is up.
## Cover holds through an alarm somebody else raised (the guards are looking for men off the river, not for a
## docker on his shift), but once a guard has marked the man himself it is gone for good.
func covered(unit: Dictionary) -> bool:
	if not unit.has("cover") or not bool(unit.get("alive", true)) or bool(unit.get("blown", false)):
		return false
	if str(unit.get("stance", "")) != "walk" or str(unit.get("carrying", "")) != "":
		return false
	if bool(unit.get("acting", false)) and str(unit.get("action", "")) != "chat":
		return false
	return not _restricted(unit, position_of(unit))

## He is in the guard's uniform now: guards take him for one of their own while he walks upright and empty-handed.
## A fresh uniform is a fresh face, so a man who was marked is unmarked again; the guard lies in his shirt.
func _put_on_uniform(unit: Dictionary, body: Dictionary) -> void:
	var spec: Dictionary = data.get("uniforms", {})
	body.stripped = true
	unit.disguise = {"id": str(body.id), "kind": str(body.get("kind", "patrol")), "look": str(body.get("look", ""))}
	unit["cover"] = {"label": str(spec.get("label", "In uniform")), "uniform": true, "zones": [],
		"blown": str(spec.get("blown", "%s has been seen through. The uniform fools nobody now.")) % str(unit.name)}
	unit.blown = false
	unit.stance = "walk"
	unit.stance_before = "walk"
	_emit({"type": "uniform", "by": str(unit.id), "guard": str(body.id), "x": float(body.x), "y": float(body.y)})
	message = str(spec.get("done", "%s is in his uniform. Walk upright and the guards take him for one of their own. Officers, and anyone close, are not fooled.")) % unit.name

## A uniform (not a local's own clothes) does not fool an officer, nor any guard who gets close enough to see the face.
func sees_through(guard: Dictionary, target: Dictionary) -> bool:
	# a local's cover (data cover.seenBy): these men know him for what he is all the same
	var seen_by: Array = target.get("cover", {}).get("seenBy", [])
	if not seen_by.is_empty() and (str(guard.get("id", "")) in seen_by or str(guard.get("kind", "")) in seen_by or str(guard.get("look", "")) in seen_by):
		return true
	if not bool(target.get("cover", {}).get("uniform", false)):
		return false
	var spec: Dictionary = data.get("uniforms", {})
	var officers: Array = spec.get("officers", ["sergeant"])
	if str(guard.get("kind", "")) in officers or str(guard.get("look", "")) in officers:
		return true
	return position_of(guard).distance_to(position_of(target)) < float(spec.get("close", UNIFORM_CLOSE))

## A guard has marked this man: whatever cover he had is gone for the rest of the night.
func _blow_cover(target: Dictionary) -> void:
	if not target.has("cover") or bool(target.get("blown", false)):
		return
	target["blown"] = true
	target["covered"] = false
	_emit({"type": "cover_blown", "id": str(target.id)})
	message = str(target.cover.get("blown", "%s has been marked: from now on he is seen like anyone else." % target.name))

## Would this operative go unremarked standing at `point` (his cover, his stance and load as they are now)?
func covered_at(unit: Dictionary, point: Vector2) -> bool:
	return unit.has("cover") and not bool(unit.get("blown", false)) and str(unit.get("stance", "")) == "walk" and str(unit.get("carrying", "")) == "" and not _restricted(unit, point)

## The zones where an operative's cover does not hold, as rectangles in sim units.
func restricted_zones(unit: Dictionary) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for zone: Array in unit.get("cover", {}).get("zones", []):
		out.append(Rect2(float(zone[0]), float(zone[1]), float(zone[2]), float(zone[3])))
	return out

## Inside one of the operative's restricted zones (data cover.zones: [x, y, w, h] in sim units)?
func _restricted(unit: Dictionary, point: Vector2) -> bool:
	for zone: Array in unit.get("cover", {}).get("zones", []):
		if Rect2(float(zone[0]), float(zone[1]), float(zone[2]), float(zone[3])).has_point(point):
			return true
	return false

## The charge sites of the mission (data "charges"), in data order. Each: {id, x, y, time, by, objective, label,
## kind, ...}; (x, y) is where the operative works from, (tx, ty) the point he works on.
func charge_sites() -> Array:
	return data.get("charges", [])

func charge_site(id: String) -> Dictionary:
	for site: Dictionary in charge_sites():
		if str(site.id) == id:
			return site
	return {}

## True when this operative carries what the site needs ("by" lists who may plant it; empty: anybody).
func can_plant(unit: Dictionary, site: Dictionary) -> bool:
	var by: Array = site.get("by", [])
	return by.is_empty() or str(unit.get("id", "")) in by

## Sites of an objective (all sites when objective is "") not planted yet.
func sites_left(objective: String = "") -> int:
	var count: int = 0
	for site: Dictionary in charge_sites():
		if (objective == "" or str(site.get("objective", "")) == objective) and not planted.has(str(site.id)):
			count += 1
	return count

## [planted, total] for an objective's sites; [0, 0] for an objective without any. A rescue's "people": [saved, all].
func objective_progress(objective: String) -> Array[int]:
	if rescue_on and objective == "people":
		var counts: Dictionary = rescue_counts()
		return [int(counts.saved), int(counts.total)]
	var total: int = 0
	var done: int = 0
	for site: Dictionary in charge_sites():
		if str(site.get("objective", "")) != objective:
			continue
		total += 1
		if planted.has(str(site.id)):
			done += 1
	return [done, total]

## True when the operative may do the optional "radio" job (data radio.by, else whoever carries the tools).
func can_sabotage(unit: Dictionary) -> bool:
	if not data.has("radio"):
		return false
	var by: Array = data.radio.get("by", [])
	return str(unit.get("id", "")) in by if not by.is_empty() else bool(unit.get("tools", false))

## The site an order means: the one named, or (with no id) the nearest unplanted one this operative can do.
func _site_for(unit: Dictionary, id: String, here: Vector2) -> Dictionary:
	if id != "":
		var named: Dictionary = charge_site(id)
		return named if not named.is_empty() and not planted.has(id) and can_plant(unit, named) else {}
	var best: Dictionary = {}
	var best_d: float = INF
	for site: Dictionary in charge_sites():
		if planted.has(str(site.id)) or not can_plant(unit, site):
			continue
		var d: float = here.distance_to(Vector2(float(site.x), float(site.y)))
		if d < best_d:
			best = site
			best_d = d
	return best

func _plant_refusal(unit: Dictionary, id: String) -> String:
	var site: Dictionary = charge_site(id)
	if id != "" and site.is_empty():
		return "There is nothing to set there."
	if id != "" and planted.has(id):
		return "That one is already set."
	if id != "" and not can_plant(unit, site):
		return str(site.get("refuse", "%s does not carry those." % unit.name))
	for other: Dictionary in charge_sites():
		if can_plant(unit, other):
			return "%s has set everything he carried." % unit.name
	return "%s carries no charges." % unit.name

## The power is off: guards marked "powered" (a searchlight crew) lose what the light gave them.
func _cut_power() -> void:
	for guard: Dictionary in guards:
		var spec: Dictionary = guard.get("powered", {})
		if spec.is_empty() or bool(guard.get("dark", false)):
			continue
		guard.dark = true
		guard.base_range = float(spec.get("range", guard.base_range))
		guard.base_fov = float(spec.get("fov", guard.base_fov))
		guard.near = float(spec.get("near", guard.near))
		guard.range = guard.base_range
		guard.fov = guard.base_fov
		if spec.has("scan"):
			guard.has_scan = bool(spec.scan)

# ---------------------------------------------------------------------------------------------
# Snow, ropes and floodlights (Operation Gunnerside). All of it is switched on by the mission data:
# "snow" (footprints and skis), "passages" (a rope rigged down a gorge), "floodlit" (lit ground), "fuse".
# ---------------------------------------------------------------------------------------------
## The passages of the mission (data "passages"): a stretch of gorge as sheer as the rest until someone who
## carries the rope ("by") rigs it from its anchor; then anyone can climb across, slowly.
## Each: {id, x, y, w, h, anchor: [x, y], by, time, slow, label, order, done, refuse, unreachable}.
func passages() -> Array:
	return data.get("passages", [])

func passage_by_id(id: String) -> Dictionary:
	for passage: Dictionary in passages():
		if str(passage.id) == id:
			return passage
	return {}

func passage_anchor(passage: Dictionary) -> Vector2:
	var at: Array = passage.get("anchor", [])
	if at.size() < 2:
		return rect_of(passage).get_center()
	return Vector2(float(at[0]), float(at[1]))

func can_rig(unit: Dictionary, passage: Dictionary) -> bool:
	var by: Array = passage.get("by", [])
	return by.is_empty() or str(unit.get("id", "")) in by

## The passage an order means: the one named, or (with no id) the nearest unrigged one this operative can rig.
func _passage_for(unit: Dictionary, id: String, here: Vector2) -> Dictionary:
	if id != "":
		var named: Dictionary = passage_by_id(id)
		return named if not named.is_empty() and not rigged.has(id) and can_rig(unit, named) else {}
	var best: Dictionary = {}
	var best_d: float = INF
	for passage: Dictionary in passages():
		if rigged.has(str(passage.id)) or not can_rig(unit, passage):
			continue
		var d: float = here.distance_to(passage_anchor(passage))
		if d < best_d:
			best = passage
			best_d = d
	return best

func _rig_refusal(unit: Dictionary, id: String) -> String:
	var passage: Dictionary = passage_by_id(id)
	if id != "" and passage.is_empty():
		return "There is nothing to rig there."
	if id != "" and rigged.has(id):
		return str(passage.get("already", "The rope is already fixed."))
	if id != "" and not can_rig(unit, passage):
		return _named(str(passage.get("refuse", "%s does not carry the rope.")), str(unit.name))
	for other: Dictionary in passages():
		if can_rig(unit, other):
			return str(other.get("already", "The rope is already fixed."))
	return "%s does not carry a rope." % unit.name

## A data sentence with the operative's name put in where it has a %s (and left as it is where it has none).
static func _named(text: String, name: String) -> String:
	return text % name if text.contains("%s") else text

## The mission's own words for its cell door (data door.order, done, refuse, already, locked), else Breakwater's.
func _door_text(key: String, fallback: String) -> String:
	return str(data.get("door", {}).get(key, fallback))

## The mission's own words for the one being got out (data prisoner.free, takeOver, order, follows, following, already,
## boarded: the informant at Breakwater, the passenger at La Boca), else Breakwater's.
func _prisoner_text(key: String, fallback: String) -> String:
	return str(data.get("prisoner", {}).get(key, fallback))

## The prisoner is still shut in: his door (data "door") is locked. A mission with a prisoner and no door has nothing
## to unlock, and he can be freed at once.
func _locked_in() -> bool:
	return data.has("door") and not door_open

## Speed on the ground at `point`: a fraction of it while climbing a rigged passage, else 1.
func _climb_factor(point: Vector2) -> float:
	for passage: Dictionary in passages():
		if rigged.has(str(passage.id)) and rect_of(passage).has_point(point):
			return float(passage.get("slow", PASSAGE_SLOW))
	return 1.0

## On a rigged passage right now (climbing): for the renderer and the HUD.
func climbing(actor: Dictionary) -> bool:
	return _climb_factor(position_of(actor)) < 1.0

static func _in_rects(list: Array, point: Vector2) -> bool:
	for r: Array in list:
		if point.x >= float(r[0]) and point.y >= float(r[1]) and point.x <= float(r[0]) + float(r[2]) and point.y <= float(r[1]) + float(r[3]):
			return true
	return false

## Snow underfoot (a mission with "snow", outside its "indoors" rectangles).
func on_snow(point: Vector2) -> bool:
	if not data.has("snow"):
		return false
	return not _in_rects(data.snow.get("indoors", []), point)

## Fresh snow that takes a footprint: snow, but not the packed roads, railway and yards (data snow.packed),
## nor a rope down a gorge.
func fresh_snow(point: Vector2) -> bool:
	return on_snow(point) and not _in_rects(data.snow.get("packed", []), point) and _climb_factor(point) >= 1.0

## Ground under a floodlight (data "floodlit"): crouching does not hide a man there, a snowsuit does not either,
## and footprints are seen right across a guard's cone.
## A lamp fed from the mission's board (an entry [x, y, w, h, "powered"]) goes dark once the board (the "radio") is cut.
func floodlit(point: Vector2) -> bool:
	for r: Array in data.get("floodlit", []):
		if radio_cut and r.size() > 4 and str(r[4]) == "powered":
			continue
		if point.x >= float(r[0]) and point.y >= float(r[1]) and point.x <= float(r[0]) + float(r[2]) and point.y <= float(r[1]) + float(r[3]):
			return true
	return false

## On his skis (data "skis") and running: upright, empty-handed, on snow and not on a rope.
func skiing(unit: Dictionary) -> bool:
	if not unit.has("skis") or str(unit.get("stance", "")) != "walk" or str(unit.get("carrying", "")) != "":
		return false
	var here: Vector2 = position_of(unit)
	return on_snow(here) and _climb_factor(here) >= 1.0

## In his snowsuit (data "camo") he melts into the snow: crouched, empty-handed and keeping still, out of the
## floodlights. A guard then sees him only from CAMO_REVEAL or closer.
func camouflaged(unit: Dictionary) -> bool:
	if not unit.has("camo") or not bool(unit.get("alive", true)):
		return false
	if str(unit.get("stance", "")) != "sneak" or str(unit.get("carrying", "")) != "":
		return false
	if not (unit.get("path", []) as Array).is_empty() or bool(unit.get("acting", false)):
		return false
	var here: Vector2 = position_of(unit)
	return on_snow(here) and not floodlit(here) and _climb_factor(here) >= 1.0

func _track_setting(key: String, fallback: float) -> float:
	return float(data.get("snow", {}).get(key, fallback))

## Footprints: every so many units walked on fresh snow, one more print (skis leave a ski track).
func _lay_tracks(unit: Dictionary, before: Vector2) -> void:
	if not data.has("snow") or not bool(data.snow.get("tracks", true)):
		return
	var here: Vector2 = position_of(unit)
	var moved: float = before.distance_to(here)
	if moved <= 0.0:
		return
	unit.stride = float(unit.stride) + moved
	if float(unit.stride) < _track_setting("spacing", TRACK_SPACING):
		return
	unit.stride = 0.0
	if not fresh_snow(here):
		return
	_track_serial += 1
	tracks.append({"id": _track_serial, "x": here.x, "y": here.y, "angle": (here - before).angle(), "t": time,
		"by": str(unit.id), "kind": "ski" if bool(unit.get("skiing", false)) else "boot", "seen": false})
	if tracks.size() > TRACK_LIMIT:
		tracks.pop_front()
	# the oldest have been snowed over
	var ttl: float = _track_setting("ttl", TRACK_TTL)
	while not tracks.is_empty() and time - float(tracks[0].t) > ttl:
		tracks.pop_front()

## Footprints still to be seen in the snow (younger than the snow's ttl), oldest first.
func live_tracks() -> Array:
	var ttl: float = _track_setting("ttl", TRACK_TTL)
	var out: Array = []
	for print_: Dictionary in tracks:
		if time - float(print_.t) <= ttl:
			out.append(print_)
	return out

## A guard on his round who sees fresh footprints goes to look where they lead: the newest print of the same
## trail within reach of the one he saw. Once there he looks about, and if he sees the trail go on he follows it
## on, a few times, before he gives up.
func _notice_tracks(guard: Dictionary, dt: float) -> void:
	if tracks.is_empty() or not _is_able(guard) or bool(alarm.active):
		return
	if bool(guard.static) or float(guard.elevation) > 0.0 or bool(guard.get("civilian", false)):
		return
	if not str(guard.state) in ["patrol", "post", "return", "search"]:
		return
	guard.track_clock = float(guard.track_clock) - dt
	if float(guard.track_clock) > 0.0:
		return
	guard.track_clock = TRACK_LOOK_EVERY
	if int(guard.trail_hops) >= int(_track_setting("hops", TRACK_HOPS)):
		return
	var here: Vector2 = position_of(guard)
	var ttl: float = _track_setting("ttl", TRACK_TTL)
	var see: float = _track_setting("see", TRACK_SEE)
	var half_fov: float = deg_to_rad(float(guard.fov) * 0.5)
	var found: Dictionary = {}
	for index: int in range(tracks.size() - 1, -1, -1):
		var print_: Dictionary = tracks[index]
		if bool(print_.seen):
			continue
		if time - float(print_.t) > ttl:
			break
		var at: Vector2 = Vector2(float(print_.x), float(print_.y))
		var offset: Vector2 = at - here
		var distance: float = offset.length()
		if distance > (float(guard.range) if floodlit(at) else minf(see, float(guard.range))):
			continue
		if distance > 1.0 and absf(wrapf(offset.angle() - float(guard.angle), -PI, PI)) > half_fov:
			continue
		if not sight_clear_for(guard, at):
			continue
		found = print_
		break
	if found.is_empty():
		return
	# where the trail leads: the newest print of the same man within reach of this one
	var from: Vector2 = Vector2(float(found.x), float(found.y))
	var follow: float = _track_setting("follow", TRACK_FOLLOW)
	var lead: Dictionary = found
	for print_: Dictionary in tracks:
		if str(print_.by) != str(found.by) or time - float(print_.t) > ttl:
			continue
		if from.distance_to(Vector2(float(print_.x), float(print_.y))) <= follow and float(print_.t) >= float(lead.t):
			lead = print_
	for print_: Dictionary in tracks:
		if str(print_.by) == str(found.by) and float(print_.t) <= float(lead.t) and from.distance_to(Vector2(float(print_.x), float(print_.y))) <= follow + 40.0:
			print_.seen = true
	var goal: Vector2 = Vector2(float(lead.x), float(lead.y))
	if is_blocked(goal):
		return
	var first: bool = int(guard.trail_hops) == 0
	guard.trail_hops = int(guard.trail_hops) + 1
	if guard.state == "patrol":
		guard.has_return = true
		guard.return_x = guard.x
		guard.return_y = guard.y
	_set_state(guard, "investigate")
	guard.goal = goal
	guard.path = []
	guard.wait = 0.0
	guard.react = LURE_REACT
	_emit({"type": "tracks", "guard": guard.id, "by": str(found.by), "x": goal.x, "y": goal.y, "first": first})
	if first:
		message = str(data.snow.get("seen", "A guard has found tracks in the snow. He is following them."))

## The fuse (data "fuse"): lit as the last charge of its objective is set. When it burns down the charges go off:
## everyone in the blast's room is lost with it, guards near enough come to look, and every guard is on edge for a
## while. It raises no alarm (they take it for a mine set off by the snow).
func _light_fuse() -> bool:
	if not data.has("fuse") or fuse_left >= 0.0 or blasted:
		return false
	var objective: String = str(data.fuse.get("objective", ""))
	if (sites_left(objective) if objective != "" else required_sites_left()) > 0:
		return false
	fuse_left = float(data.fuse.get("time", 30.0))
	var at: Array = data.fuse.get("at", [0, 0])
	_emit({"type": "fuse_lit", "seconds": fuse_left, "x": float(at[0]), "y": float(at[1])})
	return true

func _burn_fuse(dt: float) -> void:
	if fuse_left < 0.0 or blasted:
		return
	fuse_left = maxf(0.0, fuse_left - dt)
	if fuse_left > 0.0:
		return
	fuse_left = -1.0
	blasted = true
	var spec: Dictionary = data.fuse
	var at: Array = spec.get("at", [0, 0])
	var point: Vector2 = Vector2(float(at[0]), float(at[1]))
	_emit({"type": "blast", "x": point.x, "y": point.y})
	_complete_objective(str(spec.get("completes", "")))
	for unit: Dictionary in units:
		if bool(unit.alive) and _in_rects(spec.get("danger", []), position_of(unit)):
			_lose(str(spec.get("caught", "%s was caught in the blast.")) % unit.name)
			return
	# the guards come to the spot they can get to (data fuse.lure: in front of a sealed building), not into the blast
	var lure: Array = spec.get("lure", at)
	_lure_guards(Vector2(float(lure[0]), float(lure[1])), float(spec.get("radius", 600.0)), false, "blast")
	_turn_out_search(spec.get("search", {}))
	for guard: Dictionary in guards:
		if _is_able(guard):
			guard.jumpy = maxf(float(guard.jumpy), float(spec.get("jumpy", 40.0)))
	message = str(spec.get("done", "The charges go off. The guards are on edge now: get out."))

## After the blast (data fuse.search {spawn, guard, routes, message}): men turn out of the barracks and search, each
## on his own round (the gorge's lip, the railway, round the plant). No alarm: they are looking, not hunting.
func _turn_out_search(plan: Dictionary) -> void:
	var spawn: Array = plan.get("spawn", [])
	var routes: Array = plan.get("routes", [])
	if spawn.is_empty() or routes.is_empty():
		return
	var ids: Array[String] = []
	for index: int in range(routes.size()):
		var spec: Dictionary = plan.get("guard", {}).duplicate(true)
		spec["id"] = "s%d" % (index + 1)
		spec["kind"] = "search"
		spec["route"] = routes[index]
		var point: Array = spawn[index % spawn.size()]
		var guard: Dictionary = _make_guard(spec, Vector2(float(point[0]), float(point[1])))
		guards.append(guard)
		ids.append(str(guard.id))
	_geometry_dirty = true
	var first: Array = spawn[0]
	_emit({"type": "search", "ids": ids, "x": float(first[0]), "y": float(first[1])})

## True once everything the mission needs before leaving is done (the cell open, the informant out, every
## charge set): from then on getting everyone to the extraction point wins.
func ready_to_leave() -> bool:
	if data.has("door") and not door_open:
		return false
	if has_prisoner and not bool(prisoner.freed):
		return false
	return required_sites_left() == 0

## Sites still to do that the operation cannot be left without (those of an optional objective may stay undone).
func required_sites_left() -> int:
	var count: int = 0
	for site: Dictionary in charge_sites():
		if not planted.has(str(site.id)) and not _optional_objective(str(site.get("objective", ""))):
			count += 1
	return count

func _optional_objective(id: String) -> bool:
	if id == "":
		return false
	for objective: Dictionary in objectives:
		if str(objective.id) == id:
			return bool(objective.get("optional", false))
	return false

## A timed job done at a fixed spot: starts once the operative has arrived. True on the tick it completes.
func _work_at(unit: Dictionary, spot: Vector2, reach: float, dt: float) -> bool:
	if not bool(unit.acting):
		if not unit.path.is_empty():
			return false
		var offset: Vector2 = spot - position_of(unit)
		if offset.length() > reach:
			_fail_order(unit, "%s could not get there." % unit.name)
			return false
		unit.acting = true
		if offset.length() > 1.0:
			unit.angle = offset.angle()
	return _tick_action(unit, dt)

func _tick_action(unit: Dictionary, dt: float) -> bool:
	unit.action_time = float(unit.action_time) + dt
	return float(unit.action_time) >= float(unit.action_total) - 0.0001

## Closes on a target that may move. True once the operative is within `reach` with nothing solid between
## (the action then starts and he stops); until then he re-paths at most every PURSUIT_REPATH seconds.
func _approach(unit: Dictionary, target: Vector2, reach: float, dt: float) -> bool:
	if bool(unit.acting):
		return true
	var here: Vector2 = position_of(unit)
	if _within_reach(here, target, reach):
		unit.path = []
		unit.acting = true
		if here.distance_to(target) > 1.0:
			unit.angle = (target - here).angle()
		return true
	_chase(unit, target, dt)
	return false

func _chase(unit: Dictionary, target: Vector2, dt: float) -> void:
	unit.repath = float(unit.repath) - dt
	if float(unit.repath) > 0.0:
		return
	if unit.path.is_empty() or (unit.path.back() as Vector2).distance_to(target) > 10.0:
		unit.repath = PURSUIT_REPATH
		unit.path = find_path(position_of(unit), target)
		if unit.path.is_empty():
			_fail_order(unit, "%s lost the way to the target." % unit.name)

func _within_reach(from: Vector2, to: Vector2, reach: float) -> bool:
	return from.distance_to(to) <= reach and _reach_clear(from, to)

func _process_takedown(unit: Dictionary, dt: float) -> void:
	var guard: Dictionary = guard_by_id(str(unit.order.get("target", "")))
	if guard.is_empty() or guard.state in ["dead", "bound"] or (guard.state == "held" and str(guard.held_by) != str(unit.id)):
		_fail_order(unit, "%s: the target is already down." % unit.name)
		return
	var started: bool = bool(unit.acting)
	if not _approach(unit, position_of(guard), MELEE_RANGE, dt):
		return
	if not started:
		# A guard who is looking at his attacker when he is grabbed gets a shout off: the takedown still
		# goes through, but the alarm is up. If the alarm is up already he has his weapon ready and
		# fires as he is seized. Come at him from outside his cone.
		if _is_able(guard) and _zone(guard, position_of(unit), true) > 0:
			var armed: bool = guard.state in ["hunt", "alert"]
			guard.spotted = true
			_emit({"type": "spotted", "guard": guard.id, "target": unit.id})
			_blow_cover(unit)
			_raise_alarm("spotted", position_of(unit))
			if armed:
				_guard_fire(guard, unit)
				if phase != "playing":
					return
		# From this moment the target is held and can do nothing.
		guard.was_stunned = guard.state == "stunned"
		unit.action_total = _melee_time(unit, guard)
		unit.action_time = 0.0
		_set_state(guard, "held")
		guard.held_by = unit.id
		guard.path = []
		guard.target_id = ""
		guard.aim_time = 0.0
		guard.suspicion = 0.0
		guard.body_alert = 0.0
		guard.seen_id = ""
		return
	if not _tick_action(unit, dt):
		return
	var lethal: bool = bool(unit.melee.get("lethal", false))
	# a cosh (melee "stun": seconds) only knocks him out: he comes round on his own and goes looking
	var stun: float = float(unit.melee.get("stun", 0.0))
	guard.held_by = ""
	if lethal:
		_fell(guard, "dead")
		stats.kills += 1
	elif stun > 0.0:
		_fell(guard, "stunned")
		guard.stun_time = stun
		stats.knockouts += 1
	else:
		_fell(guard, "bound")
		stats.binds += 1
	_emit({"type": "takedown", "by": unit.id, "target": guard.id, "lethal": lethal, "stun": stun > 0.0})
	var what: String = "guard killed" if lethal else ("guard knocked out, for %d seconds" % int(stun) if stun > 0.0 else "guard bound and gagged")
	message = "%s: %s. %s" % [unit.name, what, "Hidden by the bush." if bool(guard.hidden) else "Hide the body before it is found."]
	_finish_order(unit)

func _process_shot(unit: Dictionary, dt: float) -> void:
	var guard: Dictionary = guard_by_id(str(unit.order.get("target", "")))
	if guard.is_empty() or guard.state in ["dead", "bound"]:
		_fail_order(unit, "%s: no target." % unit.name)
		return
	var target: Vector2 = position_of(guard)
	var here: Vector2 = position_of(unit)
	if not bool(unit.acting):
		if not _has_shot(unit, guard):
			_chase(unit, target, dt)
			return
		unit.path = []
		if float(unit.weapon_cooldown) > 0.0:
			return
		unit.acting = true
	unit.angle = (target - here).angle()
	if not _tick_action(unit, dt):
		return
	var gun: Dictionary = unit.gun
	var loud: bool = bool(gun.get("loud", false))
	var hit: bool = here.distance_to(target) <= float(gun.get("range", 240.0)) + SHOT_SLACK and _sight_clear(here, target, float(guard.elevation) > 0.0)
	unit.ammo = int(unit.ammo) - 1
	unit.weapon_cooldown = float(gun.get("recover", 0.7))
	stats.shots += 1
	_emit({"type": "shot", "by": unit.id, "x": here.x, "y": here.y, "tx": target.x, "ty": target.y, "loud": loud, "hit_id": guard.id if hit else ""})
	if bool(guard.get("creature", false)):
		# a rescue's creature: a hit drives it off (enough of them kill it); the bang carries across the square
		_creature_shot(unit, guard, hit)
		_finish_order(unit)
		return
	if hit:
		if guard.state == "held":
			# Someone else was working on him; that takedown has nothing left to do.
			guard.held_by = ""
		_fell(guard, "dead")
		stats.kills += 1
	message = "%s fires: %s." % [unit.name, "guard down" if hit else "missed"]
	if loud:
		noise.append({"x": here.x, "y": here.y, "radius": 480.0, "ttl": 1.6, "max_ttl": 1.6, "kind": "gunshot"})
		# The alarm needs someone to raise it: with every guard already down, the last shot goes unanswered.
		if guards.any(_is_able):
			_raise_alarm("gunshot", here)
		else:
			message += " Nobody is left to hear it."
	else:
		var radius: float = float(gun.get("noise", 110.0))
		noise.append({"x": here.x, "y": here.y, "radius": radius, "ttl": 1.2, "max_ttl": 1.2, "kind": "shot"})
		_lure_guards(here, radius, false)
	_finish_order(unit)

func _has_shot(unit: Dictionary, guard: Dictionary) -> bool:
	var here: Vector2 = position_of(unit)
	var target: Vector2 = position_of(guard)
	return here.distance_to(target) <= float(unit.gun.get("range", 240.0)) and _sight_clear(here, target, float(guard.elevation) > 0.0)

func _put_down(unit: Dictionary) -> void:
	var body: Dictionary = guard_by_id(str(unit.carrying))
	unit.carrying = ""
	unit.stance = unit.stance_before
	if body.is_empty():
		return
	body.carried_by = ""
	body.x = unit.x
	body.y = unit.y
	body.hidden = in_bush(position_of(body))
	_emit({"type": "drop", "by": unit.id, "body": body.id, "hidden": bool(body.hidden)})
	if bool(body.get("person", false)):
		# a fallen person set down: under cover he is saved and comes round; in the open the snow goes on covering him
		var shelter: String = shelter_at(position_of(body), true)
		if shelter != "":
			_save(body, shelter)
		else:
			message = _snow_text("setDownOpen", "Set down in the open. Get them under cover before the snow covers them.")
		return
	message = "Hidden. Nobody will find him in there." if bool(body.hidden) else "Body down in the open: any guard who sees it raises the alarm."

## What this operative throws to draw guards: Wren's pebbles (no end of them, a cooldown), or a mission's own
## (data units[].throw {label, count, range, radius, cooldown, noise, icon, done, none, empty}). Empty: nothing.
func throw_spec(unit: Dictionary) -> Dictionary:
	var spec: Dictionary = {}
	if unit.has("throw"):
		spec = (unit.throw as Dictionary).duplicate()
	elif bool(unit.get("pebble", false)):
		spec = {"label": "Pebble", "noise": "pebble", "icon": "throw"}
	else:
		return {}
	for key: String in ["range", "radius", "cooldown"]:
		if not spec.has(key): spec[key] = {"range": DISTRACT_RANGE, "radius": DISTRACT_RADIUS, "cooldown": DISTRACT_COOLDOWN}[key]
	return spec

func _throw_distraction(unit: Dictionary) -> void:
	var target: Vector2 = unit.action_target
	var throw: Dictionary = throw_spec(unit)
	var kind: String = str(throw.get("noise", "pebble"))
	var radius: float = float(throw.radius)
	noise.append({"x": target.x, "y": target.y, "radius": radius, "ttl": 2.4, "max_ttl": 2.4, "kind": kind})
	unit.cooldown = float(throw.cooldown)
	if int(unit.get("throws", -1)) > 0: unit["throws"] = int(unit.throws) - 1
	unit.angle = (target - position_of(unit)).angle()
	_clear_order(unit)
	stats.distractions += 1
	_emit({"type": "pebble", "by": unit.id, "x": target.x, "y": target.y, "noise": kind})
	var heard: int = _lure_guards(target, radius, true)
	if heard > 0:
		message = str(throw.get("done", "The noise drew %d guard%s. Move while they investigate.")) % [heard, "" if heard == 1 else "s"]
	else:
		message = str(throw.get("none", "Pebble thrown. No guard was close enough to hear it."))

## Sends every free, mobile guard within `radius` of `point` to look. Returns how many went.
func _lure_guards(point: Vector2, radius: float, is_pebble: bool, noise_kind: String = "") -> int:
	var heard: int = 0
	var ids: Array[String] = []
	for guard: Dictionary in guards:
		if not guard.state in ["patrol", "post", "return", "investigate", "search"] or bool(guard.static):
			continue
		if is_pebble and bool(guard.lure_immune):
			continue
		if position_of(guard).distance_to(point) > radius:
			continue
		if guard.state == "patrol":
			# He will come back to this spot before carrying on with his round.
			guard.has_return = true
			guard.return_x = guard.x
			guard.return_y = guard.y
		_set_state(guard, "investigate")
		guard.goal = point
		guard.path = []
		guard.wait = 0.0
		guard.react = LURE_REACT + LURE_STAGGER * float(heard)
		heard += 1
		ids.append(str(guard.id))
	if heard > 0:
		_emit({"type": "heard", "guards": ids, "x": point.x, "y": point.y, "noise": noise_kind if noise_kind != "" else ("pebble" if is_pebble else "shot")})
	return heard

# --- the informant ---
func _update_prisoner(dt: float) -> void:
	if not bool(prisoner.freed) or not bool(prisoner.alive) or bool(prisoner.aboard):
		return
	var leader: Dictionary = unit_by_id(str(prisoner.follow_id))
	if not leader.is_empty():
		# He keeps a few steps behind his escort, and closes right up when the escort stops in a bush.
		var keep: float = FOLLOW_DISTANCE_COVER if in_bush(position_of(leader)) else FOLLOW_DISTANCE
		var separation: float = position_of(prisoner).distance_to(position_of(leader))
		prisoner.repath = float(prisoner.repath) - dt
		if separation > keep + FOLLOW_SLACK and float(prisoner.repath) <= 0.0:
			prisoner.path = find_path(position_of(prisoner), position_of(leader))
			prisoner.repath = FOLLOW_REPATH
		if separation > keep:
			_advance(prisoner, PRISONER_SPEED, dt)
		else:
			prisoner.path = []
	# He cannot crouch-walk, but standing still in a bush he keeps down and is as hard to see as a
	# crouched operative there.
	prisoner.hidden = prisoner.path.is_empty() and in_bush(position_of(prisoner))
	if data.has("extraction") and position_of(prisoner).distance_to(Vector2(float(data.extraction.x), float(data.extraction.y))) <= float(data.extraction.radius):
		# At the landing stage he gets into the boat and lies low: nobody can see him there, and his
		# escort is free to wait for the other operative.
		prisoner.aboard = true
		prisoner.hidden = false
		prisoner.follow_id = ""
		prisoner.path = []
		_emit({"type": "boarded", "id": prisoner.id})
		message = _prisoner_text("boarded", "The informant is in the boat. Bring both operatives to the landing stage.")

func _advance(actor: Dictionary, speed: float, dt: float, face: bool = true) -> void:
	var budget: float = speed * dt * _climb_factor(position_of(actor))
	while budget > 0.0 and not actor.path.is_empty():
		var target: Vector2 = actor.path[0]
		var offset: Vector2 = target - position_of(actor)
		var distance: float = offset.length()
		if face and distance > 0.05:
			actor.angle = offset.angle()
		if distance <= budget + 0.001:
			actor.x = target.x
			actor.y = target.y
			actor.path.pop_front()
			budget -= distance
		else:
			var point: Vector2 = position_of(actor) + offset.normalized() * budget
			actor.x = point.x
			actor.y = point.y
			budget = 0.0

# --- guards ---
func _set_state(guard: Dictionary, state: String) -> void:
	guard.state = state
	guard.mode = state

func _is_able(guard: Dictionary) -> bool:
	return not guard.state in DOWN_STATES

func _turn(guard: Dictionary, want: float, amount: float) -> float:
	var diff: float = wrapf(want - float(guard.angle), -PI, PI)
	guard.angle = wrapf(float(guard.angle) + clampf(diff, -amount, amount), -PI, PI)
	return diff

## Walks a guard along his path. He turns at a finite rate and stops to turn when the corner is sharp,
## so a sight cone always sweeps round instead of flipping.
func _advance_guard(guard: Dictionary, speed: float, turn_rate: float, dt: float) -> void:
	if guard.path.is_empty():
		return
	var offset: Vector2 = (guard.path[0] as Vector2) - position_of(guard)
	if offset.length() > 0.5:
		if absf(_turn(guard, offset.angle(), turn_rate * dt)) > TURN_IN_PLACE:
			return
	_advance(guard, speed, dt, false)

func _update_guard(guard: Dictionary, index: int, dt: float) -> void:
	if bool(guard.get("person", false)):
		return  # the people of a rescue move by their own rules (_update_people)
	if bool(guard.get("creature", false)):
		if phase == "playing": _update_creature(guard, dt)
		return
	guard.fire_flash = maxf(0.0, float(guard.fire_flash) - dt)
	guard.fire_cooldown = maxf(0.0, float(guard.fire_cooldown) - dt)
	guard.jumpy = maxf(0.0, float(guard.jumpy) - dt)
	match str(guard.state):
		"dead", "bound", "held", "calm":
			return
		"stunned":
			guard.stun_time = float(guard.stun_time) - dt
			if float(guard.stun_time) <= 0.0:
				_wake(guard, "")
			return
		"hunt":
			_update_hunt(guard, index, dt)
		"alert":
			# Too far from the trouble to run to it: he carries on with his duty, on edge. If it comes
			# within earshot (or he sees someone himself, which moves it to where he is) he joins the hunt.
			if _called_out(guard):
				_enter_hunt(guard, index)
			else:
				_stand_duty(guard, dt)
		"investigate":
			if float(guard.react) > 0.0:
				# A beat of "what was that?" before he sets off; also spreads the path-finding over frames.
				guard.react = float(guard.react) - dt
				var toward: Vector2 = (guard.goal as Vector2) - position_of(guard)
				if toward.length() > 1.0:
					_turn(guard, toward.angle(), GUARD_TURN_RATE * dt)
				if float(guard.react) <= 0.0:
					guard.path = find_path(position_of(guard), guard.goal)
			elif guard.path.is_empty():
				_begin_search(guard, SEARCH_TIME)
			else:
				_advance_guard(guard, float(guard.speed), GUARD_TURN_RATE, dt)
		"search":
			guard.search_time = float(guard.search_time) - dt
			guard.angle = wrapf(float(guard.search_angle) + sin((float(guard.search_total) - float(guard.search_time)) * 1.7) * 0.42, -PI, PI)
			if float(guard.search_time) <= 0.0:
				_resume_duty(guard, 0.0)
		"post":
			_hold_post(guard, dt)
		"chat":
			var mate: Dictionary = unit_by_id(str(guard.chat_with))
			if mate.is_empty() or str(mate.action) != "chat" or not bool(mate.alive):
				_end_chat(guard)
			else:
				_face_point(guard, position_of(mate), GUARD_TURN_RATE * dt)
		"return":
			if _walk_home(guard, dt):
				guard.has_return = false
				guard.trail_hops = 0
				_set_state(guard, "post" if bool(guard.has_post) else "patrol")
		_:
			_patrol(guard, dt)

## Walks a guard back to his post, or to the spot on his round that a noise drew him from; true once
## he is there.
func _walk_home(guard: Dictionary, dt: float) -> bool:
	if not guard.path.is_empty():
		_advance_guard(guard, float(guard.speed), GUARD_TURN_RATE, dt)
		return false
	var home: Vector2 = Vector2(float(guard.post_x), float(guard.post_y)) if bool(guard.has_post) else Vector2(float(guard.return_x), float(guard.return_y))
	if position_of(guard).distance_to(home) < 4.0:
		return true
	if float(guard.repath) > 0.0:
		guard.repath = float(guard.repath) - dt
		return false
	guard.path = find_path(position_of(guard), home)
	if guard.path.is_empty():
		guard.repath = 1.0
	return false

## Ordinary duty for a guard on alert: his post (walking back to it first if need be) or his round.
func _stand_duty(guard: Dictionary, dt: float) -> void:
	if not bool(guard.has_post):
		_patrol(guard, dt)
	elif _walk_home(guard, dt):
		_hold_post(guard, dt)

func _patrol(guard: Dictionary, dt: float) -> void:
	if float(guard.wait) > 0.0:
		guard.wait = float(guard.wait) - dt
		_turn(guard, float(guard.wait_angle), GUARD_TURN_RATE * dt)
		return
	if guard.path.is_empty():
		if float(guard.repath) > 0.0:
			guard.repath = float(guard.repath) - dt
			return
		var route: Array = guard.route
		if route.is_empty():
			return
		var target: Vector2 = _route_point(route, int(guard.route_index))
		if position_of(guard).distance_to(target) < 4.0:
			var reached: Array = route[int(guard.route_index)]
			guard.route_index = (int(guard.route_index) + 1) % route.size()
			target = _route_point(route, int(guard.route_index))
			# Optional third and fourth numbers on a route point: seconds to wait there and the way to face.
			if reached.size() > 2 and float(reached[2]) > 0.0:
				guard.wait = float(reached[2])
				guard.wait_angle = deg_to_rad(float(reached[3])) if reached.size() > 3 else float(guard.angle)
				return
			if position_of(guard).distance_to(target) < 4.0:
				return
		guard.path = find_path(position_of(guard), target)
		if guard.path.is_empty():
			guard.repath = 1.0
			return
	_advance_guard(guard, float(guard.speed), GUARD_TURN_RATE, dt)

static func _route_point(route: Array, index: int) -> Vector2:
	var point: Array = route[index]
	return Vector2(float(point[0]), float(point[1]))

func _hold_post(guard: Dictionary, dt: float) -> void:
	if not bool(guard.has_scan):
		_turn(guard, float(guard.post_angle), GUARD_TURN_RATE * dt)
		return
	if float(guard.scan_wait) > 0.0:
		guard.scan_wait = float(guard.scan_wait) - dt
		return
	var goal: float = float(guard.scan_to) if int(guard.scan_dir) > 0 else float(guard.scan_from)
	var amount: float = float(guard.scan_speed) * dt
	if absf(_turn(guard, goal, amount)) <= amount:
		guard.scan_dir = -int(guard.scan_dir)
		guard.scan_wait = float(guard.scan_pause)

func _begin_search(guard: Dictionary, seconds: float) -> void:
	_set_state(guard, "search")
	guard.path = []
	guard.search_angle = float(guard.angle)
	guard.search_time = seconds
	guard.search_total = seconds

## Back to work after a diversion: the hunt if an alarm is on; otherwise a sentry walks back to his
## post and a patrol to the spot a noise drew him from (if any), then on along his route.
func _resume_duty(guard: Dictionary, delay: float) -> void:
	guard.path = []
	guard.repath = delay
	guard.wait = 0.0
	guard.target_id = ""
	guard.aim_time = 0.0
	if bool(alarm.active):
		_join_alarm(guard, guards.find(guard))
	elif bool(guard.has_post) or bool(guard.has_return):
		_set_state(guard, "return")
	else:
		_set_state(guard, "patrol")

func _fell(guard: Dictionary, state: String) -> void:
	_set_state(guard, state)
	guard.path = []
	guard.suspicion = 0.0
	guard.body_alert = 0.0
	guard.seen_id = ""
	guard.spotted = false
	guard.target_id = ""
	guard.aim_time = 0.0
	guard.jumpy = 0.0
	guard.wait = 0.0
	guard.has_return = false
	guard.stun_time = STUN_TIME if state == "stunned" else 0.0
	# A man down in the tower cabin or in a bush cannot be seen from the ground.
	guard.hidden = float(guard.elevation) > 0.0 or (str(guard.carried_by) == "" and in_bush(position_of(guard)))

## A stunned guard comes round, on his own (found_by == "") or because a comrade found him.
func _wake(guard: Dictionary, found_by: String) -> void:
	var carrier: Dictionary = unit_by_id(str(guard.carried_by))
	if not carrier.is_empty():
		carrier.carrying = ""
		carrier.stance = carrier.stance_before
		message = "He has come round and broken free of %s!" % carrier.name
	guard.carried_by = ""
	guard.hidden = false
	guard.stun_time = 0.0
	_emit({"type": "woke", "guard": guard.id, "found_by": found_by})
	if bool(alarm.active):
		_join_alarm(guard, guards.find(guard))
		return
	guard.jumpy = WAKE_SEARCH_TIME
	_begin_search(guard, WAKE_SEARCH_TIME)

func _spring_traps() -> void:
	for index: int in range(traps.size() - 1, -1, -1):
		var trap: Dictionary = traps[index]
		var at: Vector2 = Vector2(float(trap.x), float(trap.y))
		for guard: Dictionary in guards:
			if not _is_able(guard) or bool(guard.trap_immune) or bool(guard.static) or float(guard.elevation) > 0.0:
				continue
			if position_of(guard).distance_to(at) > TRAP_RADIUS:
				continue
			traps.remove_at(index)
			_fell(guard, "stunned")
			_emit({"type": "trap_sprung", "guard": guard.id, "trap": trap.id, "x": at.x, "y": at.y})
			message = "The tripwire took a guard down. He will wake in %d seconds unless someone deals with him." % int(STUN_TIME)
			break

# --- alarm ---
func _raise_alarm(reason: String, at: Vector2) -> void:
	alarm.x = at.x
	alarm.y = at.y
	if reason == "gunshot":
		alarm.everyone = true
	if bool(alarm.active):
		alarm.time_left = float(alarm.duration)
		return
	alarm.active = true
	alarm.everyone = reason == "gunshot"
	alarm.count = int(alarm.count) + 1
	alarm.reason = reason
	alarm.duration = float(data.get("alarm", {}).get("durationRadioCut", ALARM_TIME_RADIO_CUT)) if radio_cut else float(data.get("alarm", {}).get("duration", ALARM_TIME))
	alarm.time_left = float(alarm.duration)
	stats.alarms += 1
	_emit({"type": "alarm_start", "reason": reason, "x": at.x, "y": at.y, "count": int(alarm.count)})
	var plan: Dictionary = data.get("reinforcements", {})
	var cap: int = int(plan.get("cap", 3))
	alarm.reinforce_pending = 0
	if not radio_cut and not plan.is_empty() and _spawned < cap:
		alarm.reinforce_pending = mini(int(plan.get("first", 2)) if int(alarm.count) == 1 else int(plan.get("later", 1)), cap - _spawned)
		alarm.reinforce_in = float(plan.get("delay", 4.0))
	match reason:
		"body": message = "ALARM: a body has been found. Every guard is hunting."
		"gunshot": message = str(data.get("alarm", {}).get("gunshotMessage", "ALARM: that shot was heard across the post."))
		_: message = "ALARM: you have been seen. Break their line of sight or fight."
	for index: int in range(guards.size()):
		if _is_able(guards[index]):
			_join_alarm(guards[index], index)

## True when this guard should run to the trouble: he is within earshot of it, it was a gunshot, or he
## was sent out for it.
func _called_out(guard: Dictionary) -> bool:
	if bool(alarm.everyone) or bool(guard.responder):
		return true
	return position_of(guard).distance_to(Vector2(float(alarm.x), float(alarm.y))) <= float(alarm.radius)

## Brings a guard into a running alarm: hunting if he is called out, otherwise on alert at his work.
func _join_alarm(guard: Dictionary, index: int) -> void:
	guard.has_return = false
	if _called_out(guard):
		_enter_hunt(guard, index)
		return
	_set_state(guard, "alert")
	guard.path = []
	guard.repath = 0.0
	guard.target_id = ""
	guard.aim_time = 0.0
	guard.lost_time = 0.0

func _enter_hunt(guard: Dictionary, index: int) -> void:
	_set_state(guard, "hunt")
	guard.path = []
	guard.wait = 0.0
	guard.react = HUNT_REACT + HUNT_STAGGER * float(maxi(index, 0))
	guard.repath = 0.0
	guard.goal = Vector2(INF, INF)
	guard.search_time = HUNT_LOOK_TIME
	guard.search_total = HUNT_LOOK_TIME
	guard.search_count = 0
	guard.target_id = ""
	guard.aim_time = 0.0
	guard.lost_time = 0.0

func _update_alarm(dt: float) -> void:
	if not bool(alarm.active):
		return
	if int(alarm.reinforce_pending) > 0:
		alarm.reinforce_in = float(alarm.reinforce_in) - dt
		if float(alarm.reinforce_in) <= 0.0:
			_spawn_reinforcements(int(alarm.reinforce_pending))
			alarm.reinforce_pending = 0
	var sighted: bool = false
	for guard: Dictionary in guards:
		if not _confirmed(guard):
			continue
		var target: Dictionary = _target_by_id(str(guard.seen_id))
		if target.is_empty():
			continue
		sighted = true
		alarm.x = target.x
		alarm.y = target.y
		break
	if sighted:
		alarm.time_left = float(alarm.duration)
		return
	alarm.time_left = float(alarm.time_left) - dt
	if float(alarm.time_left) > 0.0:
		return
	alarm.active = false
	alarm.everyone = false
	alarm.time_left = 0.0
	alarm.reinforce_pending = 0
	_emit({"type": "alarm_end"})
	message = "The alarm has died down. The guards are going back to their rounds."
	var delay: float = 0.0
	for guard: Dictionary in guards:
		guard.responder = false
		if guard.state in ["hunt", "alert"]:
			# Spread the walk home over a few frames so the path-finding is too.
			_resume_duty(guard, delay)
			delay += HUNT_STAGGER

func _spawn_reinforcements(count: int) -> void:
	var plan: Dictionary = data.get("reinforcements", {})
	var spawn: Array = plan.get("spawn", [])
	var routes: Array = plan.get("routes", [])
	if spawn.is_empty():
		return
	var ids: Array[String] = []
	for index: int in range(count):
		var spec: Dictionary = plan.get("guard", {}).duplicate(true)
		spec["id"] = "r%d" % (_spawned + 1)
		spec["kind"] = "reinforcement"
		spec["route"] = routes[_spawned % routes.size()] if not routes.is_empty() else []
		var point: Array = spawn[_spawned % spawn.size()]
		var guard: Dictionary = _make_guard(spec, Vector2(float(point[0]), float(point[1])))
		guard.responder = true
		guards.append(guard)
		_enter_hunt(guard, guards.size() - 1)
		ids.append(str(guard.id))
		_spawned += 1
	var first: Array = spawn[0]
	_emit({"type": "reinforcements", "ids": ids, "x": float(first[0]), "y": float(first[1])})
	message = str(plan.get("message", "Reinforcements are pouring out of the barracks."))

func _confirmed(guard: Dictionary) -> bool:
	return _is_able(guard) and str(guard.seen_id) != "" and float(guard.suspicion) >= 1.0

## Aiming and firing at whoever he has in sight. True while he is busy with a target (he stands still for it).
## A civilian (the night watchman) has no gun: he raises the alarm and keeps out of the way.
func _engage(guard: Dictionary, dt: float) -> bool:
	if bool(guard.get("civilian", false)):
		return false
	var sees: String = str(guard.seen_id) if float(guard.suspicion) >= 1.0 else ""
	if sees != "":
		guard.lost_time = 0.0
		if str(guard.target_id) != sees and float(guard.aim_time) < AIM_COMMIT:
			guard.target_id = sees
			guard.aim_time = 0.0
	else:
		guard.lost_time = float(guard.lost_time) + dt
	if str(guard.target_id) == "":
		return false
	var target: Dictionary = _target_by_id(str(guard.target_id))
	var holding: bool = sees == str(guard.target_id) or (float(guard.aim_time) >= AIM_COMMIT and float(guard.lost_time) <= AIM_GRACE)
	if target.is_empty() or not holding:
		guard.target_id = ""
		guard.aim_time = 0.0
		return false
	guard.path = []
	guard.goal = Vector2(INF, INF)
	if sees == str(guard.target_id):
		_turn(guard, (position_of(target) - position_of(guard)).angle(), HUNT_TURN_RATE * dt)
	guard.aim_time = minf(float(guard.aim_time) + dt, GUARD_AIM_TIME)
	if float(guard.aim_time) >= GUARD_AIM_TIME and float(guard.fire_cooldown) <= 0.0:
		_guard_fire(guard, target)
	return true

func _update_hunt(guard: Dictionary, index: int, dt: float) -> void:
	if _engage(guard, dt):
		return
	var last_known: Vector2 = Vector2(float(alarm.x), float(alarm.y))
	if float(guard.react) > 0.0:
		guard.react = float(guard.react) - dt
		_face_point(guard, last_known, HUNT_TURN_RATE * dt)
		return
	if bool(guard.static) or bool(guard.alarm_hold):
		# Sentries who do not leave their post watch the direction of the trouble instead.
		var toward: Vector2 = last_known - position_of(guard)
		if toward.length() > 1.0:
			_turn(guard, toward.angle() + sin(time * 0.9 + float(index)) * 0.35, GUARD_TURN_RATE * dt)
		return
	guard.repath = float(guard.repath) - dt
	var slot: Vector2 = last_known + Vector2.from_angle(float(index) * 2.4) * 28.0
	if is_blocked(slot):
		slot = last_known
	if (guard.goal as Vector2).distance_to(slot) > HUNT_REPATH_DISTANCE and float(guard.repath) <= 0.0 and _hunt_searches < HUNT_SEARCHES_PER_UPDATE:
		_hunt_searches += 1
		guard.goal = slot
		guard.repath = HUNT_REPATH_TIME
		guard.search_time = HUNT_LOOK_TIME
		guard.search_count = 0
		guard.path = find_path(position_of(guard), slot)
	if not guard.path.is_empty():
		_advance_guard(guard, float(guard.speed) * HUNT_SPEED_SCALE, HUNT_TURN_RATE, dt)
		guard.search_angle = float(guard.angle)
		return
	# Arrived (or nowhere to go): look around, then try the next spot of a ring around the last sighting.
	guard.search_time = float(guard.search_time) - dt
	guard.angle = wrapf(float(guard.search_angle) + sin((HUNT_LOOK_TIME - float(guard.search_time)) * 2.1) * 0.9, -PI, PI)
	if float(guard.search_time) > 0.0 or float(guard.repath) > 0.0 or _hunt_searches >= HUNT_SEARCHES_PER_UPDATE:
		return
	_hunt_searches += 1
	guard.search_time = HUNT_LOOK_TIME
	guard.search_count = int(guard.search_count) + 1
	guard.repath = HUNT_REPATH_TIME
	var spot: Vector2 = last_known + Vector2.from_angle(float(index * 3 + int(guard.search_count)) * TAU / 8.0) * HUNT_SEARCH_RADIUS
	if not is_blocked(spot):
		guard.path = find_path(position_of(guard), spot)

func _face_point(guard: Dictionary, point: Vector2, amount: float) -> void:
	var toward: Vector2 = point - position_of(guard)
	if toward.length() > 1.0:
		_turn(guard, toward.angle(), amount)

func _guard_fire(guard: Dictionary, target: Dictionary) -> void:
	var from: Vector2 = position_of(guard)
	var to: Vector2 = position_of(target)
	var hit: bool = sight_clear_for(guard, to) and from.distance_to(to) <= float(guard.range) + SHOT_SLACK
	guard.fire_cooldown = GUARD_FIRE_INTERVAL
	guard.fire_flash = FIRE_FLASH_TIME
	_emit({"type": "guard_shot", "by": guard.id, "target": target.id, "hit": hit, "x": from.x, "y": from.y, "tx": to.x, "ty": to.y})
	if not hit:
		return
	target.hp = maxi(0, int(target.hp) - GUARD_DAMAGE)
	_emit({"type": "hurt", "id": target.id, "hp": int(target.hp), "by": guard.id})
	message = "%s is hit! Get out of their sight." % target.name
	if int(target.hp) > 0:
		return
	target.alive = false
	target.path = []
	_emit({"type": "death", "id": target.id, "by": guard.id})
	_lose("%s was shot dead by a guard." % target.name)

func _lose(reason: String) -> void:
	phase = "lost"
	paused = true
	lost_reason = reason
	message = reason
	_emit({"type": "lost", "reason": reason})

# --- perception ---
## Everyone a guard could notice: living operatives and the informant once he is out of the cell.
func _targets() -> Array:
	var result: Array = []
	for unit: Dictionary in units:
		if bool(unit.alive):
			result.append(unit)
	if bool(prisoner.get("freed", false)) and bool(prisoner.alive) and not bool(prisoner.aboard):
		result.append(prisoner)
	return result

func _target_by_id(id: String) -> Dictionary:
	if id == str(prisoner.get("id", "")):
		return prisoner if bool(prisoner.alive) and not bool(prisoner.aboard) else {}
	var unit: Dictionary = unit_by_id(id)
	return unit if not unit.is_empty() and bool(unit.alive) else {}

## True when the actor counts as standing for detection: walking, carrying, mid-takedown, aiming or
## having just fired a loud gun, or the informant (unless he is keeping still in a bush).
func is_exposed(actor: Dictionary) -> bool:
	if not actor.has("stance"):
		return not bool(actor.get("hidden", false))
	if actor.stance != "sneak" or str(actor.get("carrying", "")) != "":
		return true
	var acting: bool = bool(actor.get("acting", false))
	var action: String = str(actor.get("action", ""))
	# He stands to aim a loud gun, and its flash and report give him away until he has recovered.
	if _loud_gun(actor) and (float(actor.get("weapon_cooldown", 0.0)) > 0.0 or (acting and action == "shoot")):
		return true
	return acting and action in EXPOSING_ACTIONS

func _loud_gun(actor: Dictionary) -> bool:
	return bool(actor.get("gun", {}).get("loud", false))

## How `guard` sees `target` right now: 0 = not at all, 1 = in the far zone, 2 = in the near zone.
func visibility(guard: Dictionary, target: Dictionary) -> int:
	if bool(target.get("camouflaged", false)) and position_of(guard).distance_to(position_of(target)) > CAMO_REVEAL:
		return 0
	return zone_at(guard, position_of(target), is_exposed(target))

## The same test for any point: would a standing (exposed) or crouched person there be seen?
func zone_at(guard: Dictionary, point: Vector2, exposed: bool) -> int:
	if not _is_able(guard):
		return 0
	return _zone(guard, point, exposed)

## Ids of the guards who would see a person at `point`; for previews in command mode.
func threats_at(point: Vector2, exposed: bool) -> Array[String]:
	var result: Array[String] = []
	for guard: Dictionary in guards:
		if zone_at(guard, point, exposed) > 0:
			result.append(str(guard.id))
	return result

func _zone(guard: Dictionary, point: Vector2, exposed: bool) -> int:
	var offset: Vector2 = point - position_of(guard)
	var distance: float = offset.length()
	if distance > float(guard.range):
		return 0
	if distance > 1.0 and absf(wrapf(offset.angle() - float(guard.angle), -PI, PI)) > deg_to_rad(float(guard.fov) * 0.5):
		return 0
	var near: bool = distance <= float(guard.near)
	if not exposed:
		# Crouched: unseen in the far zone (unless he is under a floodlight), and a bush hides all but the closest look.
		if (not near and not floodlit(point)) or (distance > BUSH_REVEAL and in_bush(point)):
			return 0
	if not sight_clear_for(guard, point):
		return 0
	return 2 if near else 1

func _fill_time(guard: Dictionary, zone: int, exposed: bool, distance: float) -> float:
	if zone == 2:
		return FILL_NEAR_STAND if exposed else FILL_NEAR_CROUCH
	var span: float = maxf(1.0, float(guard.range) - float(guard.near))
	return lerpf(FILL_FAR_MIN, FILL_FAR_MAX, clampf((distance - float(guard.near)) / span, 0.0, 1.0))

func _perceive(guard: Dictionary, dt: float) -> void:
	if not _is_able(guard):
		return
	var alert: bool = guard.state in ["hunt", "alert"] or float(guard.jumpy) > 0.0
	guard.fov = float(guard.base_fov) + (ALERT_FOV_BONUS if alert else 0.0)
	guard.range = float(guard.base_range) + (ALERT_RANGE_BONUS if alert else 0.0)
	var scale: float = ALERT_FILL_SCALE if alert else 1.0
	var here: Vector2 = position_of(guard)
	var best_rate: float = 0.0
	var best_id: String = ""
	for target: Dictionary in _targets():
		if covered(target) and not sees_through(guard, target):
			continue
		if bool(target.get("camouflaged", false)) and here.distance_to(position_of(target)) > CAMO_REVEAL:
			continue
		var exposed: bool = is_exposed(target)
		var zone: int = _zone(guard, position_of(target), exposed)
		if zone == 0:
			continue
		var rate: float = 1.0 / _fill_time(guard, zone, exposed, here.distance_to(position_of(target)))
		if alert and exposed:
			# No second look needed at a figure standing in plain view once the guard is on edge.
			rate = INF
		if rate > best_rate:
			best_rate = rate
			best_id = str(target.id)
	guard.seen_id = best_id
	if best_id != "":
		guard.suspicion = 1.0 if best_rate == INF else minf(1.0, float(guard.suspicion) + best_rate * scale * dt)
	else:
		guard.suspicion = maxf(0.0, float(guard.suspicion) - dt / SUSPICION_DRAIN)
	if float(guard.suspicion) >= 1.0 and best_id != "":
		if not bool(guard.spotted):
			guard.spotted = true
			var target: Dictionary = _target_by_id(best_id)
			_emit({"type": "spotted", "guard": guard.id, "target": best_id})
			_blow_cover(target)
			_raise_alarm("spotted", position_of(target))
	elif float(guard.suspicion) < 0.5:
		guard.spotted = false
	# A comrade lying in the open, anywhere in the cone, is noticed within a second.
	var sighted: Dictionary = {}
	for body: Dictionary in guards:
		if not body.state in BODY_STATES or bool(body.hidden) or bool(body.found) or str(body.carried_by) != "":
			continue
		var offset: Vector2 = position_of(body) - here
		if offset.length() > float(guard.range):
			continue
		if offset.length() > 1.0 and absf(wrapf(offset.angle() - float(guard.angle), -PI, PI)) > deg_to_rad(float(guard.fov) * 0.5):
			continue
		if sight_clear_for(guard, position_of(body)):
			sighted = body
			break
	if sighted.is_empty():
		guard.body_alert = maxf(0.0, float(guard.body_alert) - dt / SUSPICION_DRAIN)
		return
	guard.body_alert = float(guard.body_alert) + scale * dt / BODY_ALERT_TIME
	if float(guard.body_alert) < 1.0:
		return
	guard.body_alert = 0.0
	sighted.found = true
	stats.bodies_found += 1
	_emit({"type": "body_found", "guard": guard.id, "body": sighted.id, "x": float(sighted.x), "y": float(sighted.y)})
	_raise_alarm("body", position_of(sighted))
	if sighted.state == "stunned":
		_wake(sighted, str(guard.id))

# ---------------------------------------------------------------------------------------------
# The rescue (Plaza de Mayo; data "snowfall", "people", "shelters", "vehicles", "canvases"). A snowfall that kills on
# contact: whoever is out in it takes the cold (exposure, 0..1) at the snow's strength of the moment, and gets warm
# again under cover; full, he falls. The people in the square are led in behind an operative ("guide", a chain of at
# most units[].lead), called (units[].call: a voice everyone near follows, a bell they come running to), carried in by
# whoever "carries" once they have fallen, and saved the moment they are under cover. A fallen operative can be helped
# up by a mate. At snowfall.bury the snow buries the square and whoever is still out in it; the operation is won once
# the people are all in or lost and the squad is under cover (or at the burial) with at least snowfall.need saved.
# ---------------------------------------------------------------------------------------------
func _snowfall() -> Dictionary:
	return data.get("snowfall", {})

## The mission's own words for the rescue (data snowfall.<key>), else the fallback.
func _snow_text(key: String, fallback: String) -> String:
	return str(_snowfall().get(key, fallback))

## Strength of the snowfall at `at` seconds into the mission (now when negative): data snowfall.schedule, [seconds,
## strength] points joined by straight lines; 1 is steady snow, waves are about 2, lulls under 0.6. 0 without a rescue.
func snow_intensity(at: float = -1.0) -> float:
	if not rescue_on:
		return 0.0
	var t: float = time if at < 0.0 else at
	var schedule: Array = _snowfall().get("schedule", [])
	if schedule.is_empty():
		return 1.0
	if t <= float(schedule[0][0]):
		return float(schedule[0][1])
	for i: int in range(1, schedule.size()):
		var a: Array = schedule[i - 1]
		var b: Array = schedule[i]
		if t <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), (t - float(a[0])) / maxf(0.001, float(b[0]) - float(a[0])))
	return float(schedule.back()[1])

## "wave" (at or above snowfall.heavy), "lull" (at or below snowfall.lull) or "steady"; "" without a rescue.
func snow_level(at: float = -1.0) -> String:
	if not rescue_on:
		return ""
	var strength: float = snow_intensity(at)
	if strength >= float(_snowfall().get("heavy", 1.5)):
		return "wave"
	if strength <= float(_snowfall().get("lull", 0.6)):
		return "lull"
	return "steady"

## Seconds until the next wave begins (the strength rising to snowfall.heavy), 0 while one is falling, -1 when no
## other comes before the snow buries the square. Read off the schedule, to the tenth of a second.
func next_wave() -> float:
	if not rescue_on:
		return -1.0
	if snow_level() == "wave":
		return 0.0
	var t: float = time
	var end: float = bury_time()
	while t < end:
		t += 0.1
		if snow_intensity(t) >= float(_snowfall().get("heavy", 1.5)):
			return t - time
	return -1.0

## When the snow buries the square (data snowfall.bury, seconds), and how long until it does.
func bury_time() -> float:
	return float(_snowfall().get("bury", INF))

func bury_left() -> float:
	return maxf(0.0, bury_time() - time)

## The places the snow cannot reach (data "shelters"): {id, label, kind, x, y, w, h, inside, dark, vehicle}.
func shelters() -> Array:
	return data.get("shelters", [])

func shelter_by_id(id: String) -> Dictionary:
	for shelter: Dictionary in shelters():
		if str(shelter.id) == id:
			return shelter
	return {}

## Where a shelter is now (a vehicle's goes where the vehicle goes).
func shelter_rect(shelter: Dictionary) -> Rect2:
	if shelter.has("vehicle"):
		return vehicle_rect(str(shelter.vehicle))
	return rect_of(shelter)

## True when people will go in: not a dark one (data shelters[].dark: a passage) whose lights are still out.
func shelter_open(shelter: Dictionary) -> bool:
	var dark: String = str(shelter.get("dark", ""))
	return dark == "" or rigged.has(dark)

## The shelter at `point`, or "": for people only those open to them, for the squad any (dark or not, it keeps the
## snow off).
func shelter_at(point: Vector2, for_people: bool) -> String:
	for shelter: Dictionary in shelters():
		if shelter_rect(shelter).has_point(point) and (not for_people or shelter_open(shelter)):
			return str(shelter.id)
	return ""

## A spot inside a shelter to make for: its "inside" point (a vehicle's middle).
func shelter_inside(shelter: Dictionary) -> Vector2:
	if shelter.has("vehicle"):
		return vehicle_rect(str(shelter.vehicle)).get_center()
	var at: Array = shelter.get("inside", [])
	return Vector2(float(at[0]), float(at[1])) if at.size() >= 2 else rect_of(shelter).get_center()

## People will not walk into a dark shelter (data shelters[].dark): they stop at its edge, out in the snow.
func _dark_at(point: Vector2) -> bool:
	for shelter: Dictionary in shelters():
		if not shelter_open(shelter) and shelter_rect(shelter).has_point(point):
			return true
	return false

## The vehicles (data "vehicles": {id, label, kind, x, y, w, h, stops, speed, by, time, ...}).
func vehicle_spec(id: String) -> Dictionary:
	for spec: Dictionary in data.get("vehicles", []):
		if str(spec.id) == id:
			return spec
	return {}

## Where a vehicle is now, as a rectangle in sim units.
func vehicle_rect(id: String) -> Rect2:
	var spec: Dictionary = vehicle_spec(id)
	var state: Dictionary = vehicles.get(id, {})
	if spec.is_empty() or state.is_empty():
		return Rect2()
	return Rect2(float(state.x), float(state.y), float(spec.w), float(spec.h))

## The vehicle at `point` (its id), or "".
func vehicle_at(point: Vector2) -> String:
	for id: String in vehicles:
		if vehicle_rect(id).has_point(point):
			return id
	return ""

## The vehicle an order means: the one named, or (with no id) the nearest this operative can drive.
func _vehicle_for(unit: Dictionary, id: String) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for spec: Dictionary in data.get("vehicles", []):
		if (spec.get("stops", []) as Array).size() < 2 or not str(unit.get("id", "")) in (spec.get("by", []) as Array):
			continue
		if id != "" and str(spec.id) != id:
			continue
		var d: float = position_of(unit).distance_to(vehicle_rect(str(spec.id)).get_center())
		if d < best_d:
			best = spec
			best_d = d
	return best

func _drive_refusal(unit: Dictionary, id: String) -> String:
	var spec: Dictionary = vehicle_spec(id) if id != "" else {}
	if id != "" and spec.is_empty():
		return "There is nothing to drive there."
	if not spec.is_empty() and (spec.get("stops", []) as Array).size() < 2:
		return _snow_text("stranded", "It is going nowhere tonight.")
	if not spec.is_empty():
		return _named(str(spec.get("refuse", "%s cannot drive it.")), str(unit.get("name", "")))
	for other: Dictionary in data.get("vehicles", []):
		if (other.get("stops", []) as Array).size() >= 2:
			return _named(str(other.get("refuse", "%s cannot drive it.")), str(unit.get("name", "")))
	return "There is nothing to drive here."

## Starts a vehicle for its next stop along its line (back the other way from the end), with `unit` at the controls.
func _start_vehicle(id: String, unit: Dictionary) -> void:
	var state: Dictionary = vehicles[id]
	var stops: Array = vehicle_spec(id).get("stops", [])
	var next: int = int(state.stop) + int(state.dir)
	if next < 0 or next >= stops.size():
		state.dir = -int(state.dir)
		next = int(state.stop) + int(state.dir)
	state.to = next
	state.driver = str(unit.id)
	_beast_dirty = true
	_emit({"type": "drive", "by": str(unit.id), "vehicle": id, "to": next, "x": float(stops[next]), "y": float(state.y)})

## Moves the vehicles under way, and everyone aboard with them: the squad and the people inside their rectangles.
func _update_vehicles(dt: float) -> void:
	for id: String in vehicles:
		var state: Dictionary = vehicles[id]
		if int(state.to) < 0:
			continue
		var spec: Dictionary = vehicle_spec(id)
		var goal: float = float((spec.get("stops", []) as Array)[int(state.to)])
		var speed: float = float(spec.get("speed", VEHICLE_SPEED))
		var step: float = clampf(goal - float(state.x), -speed * dt, speed * dt)
		var aboard: Rect2 = vehicle_rect(id)
		var shift := Vector2(step, 0.0)
		for unit: Dictionary in units:
			if bool(unit.alive) and aboard.has_point(position_of(unit)):
				_shift(unit, shift)
		for person: Dictionary in guards:
			if bool(person.get("person", false)) and str(person.state) != "lost" and str(person.get("carried_by", "")) == "" and aboard.has_point(position_of(person)):
				if bool(person.get("stuck", false)) and str(person.state) == "crowd": continue
				_shift(person, shift)
		state.x = float(state.x) + step
		if absf(goal - float(state.x)) < 0.01:
			state.x = goal
			state.stop = int(state.to)
			state.to = -1
			_beast_dirty = true
			_emit({"type": "arrived", "vehicle": id, "stop": int(state.stop), "x": float(state.x), "y": float(state.y)})

func _shift(actor: Dictionary, by: Vector2) -> void:
	actor.x = float(actor.x) + by.x
	actor.y = float(actor.y) + by.y
	var moved: Array = []
	for point: Vector2 in actor.get("path", []):
		moved.append(point + by)
	actor.path = moved
	if actor.has("spot") and actor.spot is Vector2:
		actor.spot = (actor.spot as Vector2) + by

## The cloths (data "canvases": {id, label, kind, x, y, time, holds, order, take}).
func canvases() -> Array:
	return data.get("canvases", [])

func canvas_by_id(id: String) -> Dictionary:
	for canvas: Dictionary in canvases():
		if str(canvas.id) == id:
			return canvas
	return {}

## The cloth an order means: the one named (if nobody has taken it), or the nearest left.
func _canvas_for(id: String, here: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for canvas: Dictionary in canvases():
		if canvases_taken.has(str(canvas.id)) or (id != "" and str(canvas.id) != id):
			continue
		var d: float = here.distance_to(Vector2(float(canvas.x), float(canvas.y)))
		if d < best_d:
			best = canvas
			best_d = d
	return best

## The cloth has done its crossing (or is soaked through): it is spent.
func _spend_canvas(unit: Dictionary) -> void:
	if (unit.get("canvas", {}) as Dictionary).is_empty():
		return
	_emit({"type": "canvas_spent", "by": str(unit.id), "canvas": str(unit.canvas.get("id", ""))})
	unit["canvas"] = {}

## The gear left about the square for whoever gets to it first (data "gear": {id, kind, label, x, y, time, order,
## take} and what it gives: "suit" true, with a "look", for a hood and mask; "gun" for a rifle).
func gear() -> Array:
	return data.get("gear", [])

func gear_by_id(id: String) -> Dictionary:
	for item: Dictionary in gear():
		if str(item.id) == id:
			return item
	return {}

## The gear an order means: the one named (if nobody has taken it), or the nearest left.
func _gear_for(id: String, here: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for item: Dictionary in gear():
		if gear_taken.has(str(item.id)) or (id != "" and str(item.id) != id):
			continue
		var d: float = here.distance_to(Vector2(float(item.x), float(item.y)))
		if d < best_d:
			best = item
			best_d = d
	return best

## Why this operative has no use for that gear ("" when he has): a rifle for one with a gun, a suit for Juan Salvo.
func _gear_refusal(unit: Dictionary, item: Dictionary) -> String:
	if item.has("gun") and unit.has("gun"):
		return _named(str(item.get("armed", "%s has a gun already.")), str(unit.name))
	if bool(item.get("suit", false)) and bool(unit.get("suit", false)):
		return _named(str(item.get("sealed", "%s is sealed against the snow already.")), str(unit.name))
	return ""

## He takes it. A rifle makes him a second gun against the cascarudos (with its rounds); a hood and mask seal him
## against the snow like Juan Salvo's suit, and he is seen in them from then on (the look the gear names, worn the
## way a uniform is: units[].disguise), the cloth he held no longer needed.
func _take_gear(unit: Dictionary, item: Dictionary) -> void:
	gear_taken[str(item.id)] = str(unit.id)
	var worn: Array = unit.get("gear", [])
	worn.append(str(item.get("kind", item.id)))
	unit["gear"] = worn
	if item.has("gun"):
		unit["gun"] = (item.gun as Dictionary).duplicate(true)
		unit.ammo = int(unit.gun.get("ammo", 0))
		unit.weapon_cooldown = 0.0
	if bool(item.get("suit", false)):
		unit["suit"] = true
		unit.exposure = 0.0
		_spend_canvas(unit)
		if str(item.get("look", "")) != "":
			unit["disguise"] = {"id": str(item.id), "kind": "", "look": str(item.look)}
	stats["gear"] = int(stats.get("gear", 0)) + 1
	_emit({"type": "took", "by": str(unit.id), "gear": str(item.id), "kind": str(item.get("kind", "")), "x": float(item.x), "y": float(item.y)})
	message = _named(str(item.get("take", "%s takes it.")), str(unit.name))

## The people of the rescue (data "people"), as they are kept on the guards' list.
func people() -> Array:
	var out: Array = []
	for guard: Dictionary in guards:
		if bool(guard.get("person", false)):
			out.append(guard)
	return out

func person_by_id(id: String) -> Dictionary:
	var guard: Dictionary = guard_by_id(id)
	return guard if bool(guard.get("person", false)) else {}

## The people following an operative, in the order they walk behind him.
func followers_of(unit_id: String) -> Array:
	var out: Array = []
	for guard: Dictionary in guards:
		if bool(guard.get("person", false)) and str(guard.state) == "follow" and str(guard.follow_id) == unit_id:
			out.append(guard)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.rank) < int(b.rank))
	return out

## How many an operative can lead at once (data units[].lead, else snowfall.lead).
func lead_of(unit: Dictionary) -> int:
	return int(unit.get("lead", _snowfall().get("lead", LEAD_DEFAULT)))

## The operative leads this person in, and with him whoever of his group stands near him and is not yet led
## (as many as the operative can lead). Returns how many joined.
func _lead(unit: Dictionary, person: Dictionary) -> int:
	var room: int = lead_of(unit) - followers_of(str(unit.id)).size()
	if room <= 0:
		return 0
	var joined: Array[String] = []
	_join(unit, person)
	joined.append(str(person.id))
	room -= 1
	var group: String = str(person.get("group", ""))
	if group != "":
		var near: Array = []
		for other: Dictionary in guards:
			if not bool(other.get("person", false)) or str(other.id) == str(person.id) or str(other.get("group", "")) != group:
				continue
			if not str(other.state) in ["crowd", "panic", "coming"] or bool(other.get("stuck", false)):
				continue
			if position_of(other).distance_to(position_of(person)) <= GROUP_REACH:
				near.append(other)
		near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return position_of(a).distance_to(position_of(person)) < position_of(b).distance_to(position_of(person)))
		for other: Dictionary in near:
			if room <= 0:
				break
			_join(unit, other)
			joined.append(str(other.id))
			room -= 1
	_emit({"type": "guided", "by": str(unit.id), "ids": joined})
	return joined.size()

## One person falls in at the back of an operative's chain.
func _join(unit: Dictionary, person: Dictionary) -> void:
	_rank_serial += 1
	_set_state(person, "follow")
	person.follow_id = str(unit.id)
	person.rank = _rank_serial
	person.goal_id = ""
	person.path = []
	person.repath = 0.0

## He stops following (his leader fell, or he panicked): he stands where he is, out in the snow.
func _release(person: Dictionary) -> void:
	_set_state(person, "crowd")
	person.follow_id = ""
	person.goal_id = ""
	person.path = []

## Under cover: saved. He goes on in to a spot of his own inside, and gets his warmth back there.
func _save(person: Dictionary, shelter_id: String) -> void:
	var shelter: Dictionary = shelter_by_id(shelter_id)
	_set_state(person, "safe")
	person.follow_id = ""
	person.goal_id = ""
	person.shelter = shelter_id
	person.fall_left = 0.0
	person.path = []
	var count: int = 0
	for other: Dictionary in guards:
		if bool(other.get("person", false)) and str(other.state) == "safe" and str(other.get("shelter", "")) == shelter_id:
			count += 1
	person["spot"] = _spot_in(shelter, count - 1)
	var counts: Dictionary = rescue_counts()
	_emit({"type": "saved", "id": str(person.id), "shelter": shelter_id, "x": float(person.x), "y": float(person.y), "saved": int(counts.saved)})
	message = _snow_text("savedCount", "Under cover: %d of %d.") % [int(counts.saved), int(counts.total)]
	if int(counts.saved) >= int(counts.need):
		_complete_objective("people")
	if bool(person.get("stuck", false)):
		var waiting: bool = false
		for other: Dictionary in guards:
			if bool(other.get("stuck", false)) and str(other.state) != "safe": waiting = true
		if not waiting: _complete_objective("stop")

## The k-th spot inside a shelter: round its "inside" point, inside its rectangle, on open ground.
func _spot_in(shelter: Dictionary, k: int) -> Vector2:
	var rect: Rect2 = shelter_rect(shelter).grow(-12.0)
	var center: Vector2 = shelter_inside(shelter)
	for attempt: int in range(6):
		var n: int = k + attempt * 7
		var offset: Vector2 = Vector2.from_angle(float(n) * 2.39996) * 20.0 * sqrt(float(n))
		var at: Vector2 = Vector2(clampf(center.x + offset.x, rect.position.x, rect.end.x), clampf(center.y + offset.y, rect.position.y, rect.end.y))
		if not is_blocked(at):
			return at
	return center

## People: their own moves. Called once per update, after the squad and the vehicles.
func _update_people(dt: float) -> void:
	var wave: bool = snow_intensity() >= float(_snowfall().get("panic", 1.6))
	var chilled: float = float(_snowfall().get("panicExposure", 0.55))
	var speed: float = float(_snowfall().get("speed", PERSON_SPEED))
	for person: Dictionary in guards:
		if not bool(person.get("person", false)):
			continue
		match str(person.state):
			"crowd":
				var plan: Dictionary = person.get("panic", {})
				if not plan.is_empty() and not bool(person.panicked) and time >= float(plan.get("at", INF)):
					_panic(person)
				# one too far gone to walk (data people[].stuck) is saved where he stands when cover comes to him: the colectivo
				elif bool(person.get("stuck", false)) and shelter_at(position_of(person), true) != "":
					_save(person, shelter_at(position_of(person), true))
			"follow":
				_follow(person, speed, dt)
				if str(person.state) == "follow" and wave and float(person.exposure) >= chilled and not bool(person.warm):
					_panic(person)
			"coming":
				_come(person, speed, dt)
			"panic":
				_advance(person, float(_snowfall().get("run", PERSON_RUN)), dt)
				if (person.path as Array).is_empty():
					_set_state(person, "crowd")
			"safe":
				var spot: Variant = person.get("spot")
				if spot is Vector2 and position_of(person).distance_to(spot) > 2.0:
					if (person.path as Array).is_empty():
						person.path = [spot]
					_advance(person, speed * 0.7, dt)
		if str(person.state) in ["follow", "coming", "panic"]:
			var shelter: String = shelter_at(position_of(person), true)
			if shelter != "":
				_save(person, shelter)

## A person walking behind an operative: a few steps behind the one in front of him in the chain (the operative
## himself for the first). He will not step into a dark shelter.
func _follow(person: Dictionary, speed: float, dt: float) -> void:
	var leader: Dictionary = unit_by_id(str(person.follow_id))
	if leader.is_empty() or not bool(leader.alive) or bool(leader.get("fallen", false)):
		_release(person)
		return
	var chain: Array = followers_of(str(leader.id))
	var index: int = -1
	for i: int in range(chain.size()):
		if str(chain[i].id) == str(person.id):
			index = i
	var ahead: Dictionary = leader if index <= 0 else chain[index - 1]
	var target: Vector2 = position_of(ahead)
	var keep: float = float(_snowfall().get("follow", PERSON_GAP))
	var separation: float = position_of(person).distance_to(target)
	person.repath = float(person.repath) - dt
	if separation > keep + FOLLOW_SLACK and float(person.repath) <= 0.0:
		person.path = find_path(position_of(person), target)
		person.repath = FOLLOW_REPATH
	if separation > keep:
		var before: Vector2 = position_of(person)
		_advance(person, speed, dt)
		if _dark_at(position_of(person)):
			person.x = before.x
			person.y = before.y
			person.path = []
	else:
		person.path = []

## A person called to a shelter (the tram's bell): he makes for it by himself, the vehicle wherever it is now.
func _come(person: Dictionary, speed: float, dt: float) -> void:
	var shelter: Dictionary = shelter_by_id(str(person.goal_id))
	if shelter.is_empty():
		_release(person)
		return
	var goal: Vector2 = shelter_inside(shelter)
	person.repath = float(person.repath) - dt
	if float(person.repath) <= 0.0 or (person.path as Array).is_empty():
		person.path = find_path(position_of(person), goal)
		person.repath = 0.5
	_advance(person, speed, dt)

## A person panics: he breaks away from whoever led him and runs to his "flee" point out in the snow (or freezes where
## he is), and stands there until somebody comes for him again.
func _panic(person: Dictionary) -> void:
	person.panicked = true
	person.follow_id = ""
	person.goal_id = ""
	var flee: Array = person.get("flee", [])
	person.path = find_path(position_of(person), Vector2(float(flee[0]), float(flee[1]))) if flee.size() >= 2 else []
	_set_state(person, "panic" if not (person.path as Array).is_empty() else "crowd")
	_emit({"type": "panic", "id": str(person.id), "x": float(person.x), "y": float(person.y)})
	message = _snow_text("panicked", "Someone panics and runs off into the snow.")

## Is this person under a cloth: following its holder, among the first `holds` behind him, close enough?
func _under_canvas(person: Dictionary) -> bool:
	if str(person.state) != "follow":
		return false
	var leader: Dictionary = unit_by_id(str(person.follow_id))
	if leader.is_empty() or (leader.get("canvas", {}) as Dictionary).is_empty():
		return false
	var chain: Array = followers_of(str(leader.id))
	var holds: int = int(leader.canvas.get("holds", 3))
	for i: int in range(mini(holds, chain.size())):
		if str(chain[i].id) == str(person.id):
			return position_of(person).distance_to(position_of(leader)) <= CANVAS_REACH * float(i + 1)
	return false

## The cold: out in the snow it rises at the snow's strength (data snowfall.rate: seconds of steady snow to fill it);
## under cover, or under a cloth, it does not, and under cover it drains (snowfall.recover). Full, he falls; a fallen
## one not brought in is lost when his time is up (snowfall.grace).
func _expose(dt: float) -> void:
	if buried_square:
		return
	var spec: Dictionary = _snowfall()
	var strength: float = snow_intensity()
	var rate_unit: float = float(spec.get("rate", {}).get("unit", EXPOSURE_RATE_UNIT))
	var rate_person: float = float(spec.get("rate", {}).get("person", EXPOSURE_RATE_PERSON))
	var recover: float = float(spec.get("recover", EXPOSURE_RECOVER))
	for unit: Dictionary in units:
		if not bool(unit.alive) or bool(unit.get("away", false)):
			continue
		var suit: bool = bool(unit.get("suit", false))
		if bool(unit.get("fallen", false)):
			unit.fall_left = float(unit.fall_left) - dt
			if float(unit.fall_left) <= 0.0:
				# sealed in his suit the snow cannot get at him: knocked down, he gets up again by himself
				if suit: _help_up(unit, unit)
				else: _unit_lost(unit)
			continue
		if suit:
			# the snow does not touch him (data units[].suit): no cold, wherever he goes
			unit.exposure = 0.0
			continue
		var cloth: Dictionary = unit.get("canvas", {})
		if shelter_at(position_of(unit), false) != "":
			unit.exposure = maxf(0.0, float(unit.exposure) - dt / recover)
			# under cover again with the cloth: its crossing is done
			if not cloth.is_empty() and bool(cloth.get("out", false)):
				_spend_canvas(unit)
		elif not cloth.is_empty():
			cloth["out"] = true
			cloth["left"] = float(cloth.get("left", 0.0)) - dt
			if float(cloth.left) <= 0.0:
				_spend_canvas(unit)
		else:
			unit.exposure = float(unit.exposure) + strength * dt / rate_unit
			if float(unit.exposure) >= 1.0:
				_unit_falls(unit)
	for person: Dictionary in guards:
		if not bool(person.get("person", false)):
			continue
		match str(person.state):
			"crowd", "follow", "coming", "panic":
				person.warm = _under_canvas(person)
				if not bool(person.warm):
					person.exposure = float(person.exposure) + strength * dt / rate_person
					if float(person.exposure) >= 1.0:
						_person_falls(person)
			"safe":
				person.warm = true
				person.exposure = maxf(0.0, float(person.exposure) - dt / recover)
			"fallen":
				# carried, he is out of the snow on his bearer's shoulders: his time stands still
				if str(person.get("carried_by", "")) == "":
					person.fall_left = float(person.fall_left) - dt
					if float(person.fall_left) <= 0.0:
						_person_lost(person)

func _grace(kind: String, fallback: float) -> float:
	return float(_snowfall().get("grace", {}).get(kind, fallback))

## An operative falls in the snow: he lets go of everything (the ones he led stand where they are, a man he carried is
## set down, the cloth is lost) and kneels there; a mate can still get him up.
func _unit_falls(unit: Dictionary) -> void:
	if str(unit.carrying) != "":
		_put_down(unit)
	for person: Dictionary in followers_of(str(unit.id)):
		_release(person)
	_spend_canvas(unit)
	_clear_order(unit)
	unit.path = []
	unit.queued = {}
	var suit: bool = bool(unit.get("suit", false))
	unit.exposure = 0.0 if suit else 1.0
	unit.fallen = true
	unit.fall_left = float(_snowfall().get("suitUp", SUIT_UP)) if suit else _grace("unit", FALL_GRACE_UNIT)
	unit.stance = "walk"
	stats["fallen"] = int(stats.get("fallen", 0)) + 1
	_emit({"type": "fallen", "id": str(unit.id), "unit": true, "x": float(unit.x), "y": float(unit.y)})
	message = _snow_text("fellUnit", "%s has fallen in the snow. Get to him before it covers him.") % unit.name

## Nobody got to him in time: the snow has covered him. He is lost (not alive), and the operation goes on without him.
func _unit_lost(unit: Dictionary) -> void:
	unit.fallen = false
	unit.buried = true
	unit.alive = false
	unit.hp = 0
	unit.path = []
	stats["squad_lost"] = int(stats.get("squad_lost", 0)) + 1
	_emit({"type": "buried", "id": str(unit.id), "unit": true, "x": float(unit.x), "y": float(unit.y)})
	message = _snow_text("buriedUnit", "The snow has covered %s. He is gone.") % unit.name

## A mate gets him up: on his feet again, chilled through (data snowfall.helped, the cold he is left with).
func _help_up(mate: Dictionary, by: Dictionary) -> void:
	var suit: bool = bool(mate.get("suit", false))
	mate.fallen = false
	mate.fall_left = 0.0
	mate.exposure = 0.0 if suit else float(_snowfall().get("helped", 0.7))
	_emit({"type": "helped", "by": str(by.id), "id": str(mate.id), "x": float(mate.x), "y": float(mate.y)})
	if suit and str(by.id) == str(mate.id):
		message = _snow_text("upAgain", "%s gets to his feet again.") % mate.name
	else:
		message = _snow_text("helped", "%s is on his feet again. Get him under cover.") % mate.name

func _person_falls(person: Dictionary) -> void:
	_set_state(person, "fallen")
	person.exposure = 1.0
	person.follow_id = ""
	person.goal_id = ""
	person.path = []
	person.fall_left = _grace("person", FALL_GRACE_PERSON)
	stats["fallen"] = int(stats.get("fallen", 0)) + 1
	_emit({"type": "fallen", "id": str(person.id), "unit": false, "x": float(person.x), "y": float(person.y)})
	message = _snow_text("fell", "Someone has fallen in the snow. Biguá can still carry them in.")

func _person_lost(person: Dictionary) -> void:
	var bearer: Dictionary = unit_by_id(str(person.get("carried_by", "")))
	if not bearer.is_empty():
		bearer.carrying = ""
		bearer.stance = bearer.stance_before
		person.carried_by = ""
	_set_state(person, "lost")
	person.path = []
	person.fall_left = 0.0
	stats["lost"] = int(stats.get("lost", 0)) + 1
	_emit({"type": "buried", "id": str(person.id), "unit": false, "x": float(person.x), "y": float(person.y)})
	message = _snow_text("buried", "The snow has covered someone.")

## The operative's call (data units[].call {mode, radius, count, cooldown, from, noise}): "follow", everyone near him
## out in the snow falls in behind him (as many as he can lead); "come", he rings from the vehicle he must be in
## (call.from) and everyone near it makes for it by himself.
func _call_people(unit: Dictionary) -> void:
	var call: Dictionary = unit.get("call", {})
	_clear_order(unit)
	unit.cooldown = float(call.get("cooldown", 12.0))
	if int(unit.get("calls", -1)) > 0:
		unit.calls = int(unit.calls) - 1
	var here: Vector2 = position_of(unit)
	var radius: float = float(call.get("radius", 384.0))
	var mode: String = str(call.get("mode", "follow"))
	var from: String = str(call.get("from", ""))
	var center: Vector2 = vehicle_rect(from).get_center() if from != "" and vehicles.has(from) else here
	var near: Array = []
	for person: Dictionary in guards:
		if not bool(person.get("person", false)):
			continue
		var state: String = str(person.state)
		if bool(person.get("stuck", false)) or not (state in ["crowd", "panic"] or (mode == "follow" and state == "coming")):
			continue
		if position_of(person).distance_to(center) <= radius:
			near.append(person)
	near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da: float = position_of(a).distance_to(center)
		var db: float = position_of(b).distance_to(center)
		return da < db if absf(da - db) > 0.001 else str(a.id) < str(b.id))
	var count: int = 0
	if mode == "come":
		var goal: String = ""
		for shelter: Dictionary in shelters():
			if str(shelter.get("vehicle", "")) == from: goal = str(shelter.id)
		for person: Dictionary in near:
			_set_state(person, "coming")
			person.goal_id = goal
			person.follow_id = ""
			person.path = []
			person.repath = 0.0
			count += 1
	else:
		var room: int = lead_of(unit) - followers_of(str(unit.id)).size()
		for person: Dictionary in near:
			if room <= 0:
				break
			_join(unit, person)
			room -= 1
			count += 1
	noise.append({"x": center.x, "y": center.y, "radius": radius, "ttl": 2.4, "max_ttl": 2.4, "kind": str(call.get("noise", "voice"))})
	_emit({"type": "call", "by": str(unit.id), "mode": mode, "noise": str(call.get("noise", "voice")), "x": center.x, "y": center.y, "count": count})
	message = (str(call.get("done", "%d answer the call.")) % count) if count > 0 else str(call.get("none", "Nobody near enough answered."))

## Messages as the snow turns into a wave or eases into a lull (event "snowfall" {level, strength}).
func _watch_snow() -> void:
	var level: String = snow_level()
	if level == _snow_level:
		return
	var first: bool = _snow_level == ""
	_snow_level = level
	if first or buried_square:
		return
	_emit({"type": "snowfall", "level": level, "strength": snow_intensity()})
	if level == "wave":
		message = _snow_text("wave", "A heavy wave of snow is coming down.")
	elif level == "lull":
		message = _snow_text("lullNow", "A lull. Bring them in now.")

## {saved, lost, out (on their feet in the snow), fallen (down, not yet lost), total, need}.
func rescue_counts() -> Dictionary:
	var counts: Dictionary = {"saved": 0, "lost": 0, "out": 0, "fallen": 0, "total": 0, "need": int(_snowfall().get("need", 0))}
	for person: Dictionary in guards:
		if not bool(person.get("person", false)):
			continue
		counts.total = int(counts.total) + 1
		match str(person.state):
			"safe": counts.saved = int(counts.saved) + 1
			"lost": counts.lost = int(counts.lost) + 1
			"fallen": counts.fallen = int(counts.fallen) + 1
			_: counts.out = int(counts.out) + 1
	if not _snowfall().has("need"):
		counts.need = int(counts.total)
	return counts

## The end of a rescue: the square buried (whoever is out is lost), or nobody left out in the snow and the squad
## under cover. Won with at least snowfall.need saved; lost with fewer, or as soon as there are too few left to save,
## or when all four of the squad are lost.
func _check_rescue() -> void:
	if not rescue_on or phase != "playing":
		return
	if not buried_square and time >= bury_time():
		_bury_square()
	var standing: int = 0
	for unit: Dictionary in units:
		if bool(unit.alive):
			standing += 1
	if standing == 0:
		_lose(_snow_text("lostAll", "The snow has taken all four of you."))
		return
	var counts: Dictionary = rescue_counts()
	if buried_square:
		if int(counts.saved) >= int(counts.need): _win_rescue()
		else: _lose(_snow_text("tooFew", "The snow has buried the square, and too few were brought in."))
		return
	if int(counts.total) == 0:
		return  # nobody in the square to bring in: only the burial ends it
	if int(counts.saved) + int(counts.out) + int(counts.fallen) < int(counts.need):
		_lose(_snow_text("lostTooMany", "Too many have been lost to the snow."))
		return
	var squad_in: bool = true
	for unit: Dictionary in units:
		if bool(unit.alive) and not bool(unit.get("away", false)) and (bool(unit.get("fallen", false)) or shelter_at(position_of(unit), false) == ""):
			squad_in = false
	if int(counts.out) == 0 and int(counts.fallen) == 0 and squad_in:
		if int(counts.saved) >= int(counts.need):
			_win_rescue()
		else:
			_lose(_snow_text("tooFew", "The snow has buried the square, and too few were brought in."))

## The snow buries the square: whoever is still out in it, the squad included, is lost.
func _bury_square() -> void:
	buried_square = true
	for unit: Dictionary in units:
		if bool(unit.alive) and not bool(unit.get("away", false)) and (bool(unit.get("fallen", false)) or shelter_at(position_of(unit), false) == ""):
			_unit_lost(unit)
	for person: Dictionary in guards:
		if bool(person.get("person", false)) and not str(person.state) in ["safe", "lost"]:
			_person_lost(person)
	_emit({"type": "square_buried"})

func _win_rescue() -> void:
	phase = "won"
	paused = true
	_complete_objective("people")
	_complete_objective("shelter")
	message = str(data.get("winMessage", "Everyone who could be brought in is under cover."))
	_emit({"type": "won", "time": time})

## One of the squad comes later in the night (data units[].arrive {at, to, text, notYet, checkpoint}): in from where his
## data puts him, at the edge of the map, walking on to `to`; then he is the player's like the others. With "checkpoint"
## true a checkpoint is taken as he comes, under his id.
func _arrive(unit: Dictionary) -> void:
	var arrive: Dictionary = unit.arrive
	unit.away = false
	var to: Vector2 = _pt(arrive.get("to", [unit.x, unit.y]))
	unit.path = find_path(position_of(unit), to)
	if not (unit.path as Array).is_empty():
		unit.order = {"type": "move", "x": to.x, "y": to.y}
		unit.angle = (to - position_of(unit)).angle()
	_emit({"type": "arrival", "id": str(unit.id), "x": float(unit.x), "y": float(unit.y)})
	var said: String = str(arrive.get("text", "%s is here."))
	message = said % unit.name if said.contains("%s") else said
	if bool(arrive.get("checkpoint", false)):
		_pending_checkpoint = str(unit.id)

static func _pt(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	var at: Array = value if value is Array else []
	return Vector2(float(at[0]), float(at[1])) if at.size() >= 2 else Vector2.ZERO

# --- a rescue's creatures (data "creatures") ---
## The creatures (data "creatures": {look, title, speed, charge, flee, sense, reach, radius, pause, hits, away, linger,
## roam [x, y, w, h], hear {noise kind: how far it is heard}, arrivals [{id, at, from, to, text}], and their words}). They
## are kept on the guards' list as kind "creature", so that the renderer, the HUD and the recon map show them, but none
## of their states is a guard's: they see nothing, raise nothing and are nobody's to talk to.
func _creatures() -> Dictionary:
	return data.get("creatures", {})

func _creature_text(key: String, fallback: String) -> String:
	return str(_creatures().get(key, fallback))

func _make_creature(spec: Dictionary) -> Dictionary:
	var rules: Dictionary = _creatures()
	var from: Vector2 = _pt(spec.get("from", [0.0, 0.0]))
	var to: Vector2 = _pt(spec.get("to", [from.x, from.y]))
	var entry: Dictionary = {"id": str(spec.id), "kind": "creature", "creature": true, "look": str(rules.get("look", "")),
		"title": str(rules.get("title", "CREATURE")), "speed": 0.0, "range": 0.0, "near": 0.0, "fov": 0.0, "static": true,
		"lure_immune": true, "melee_immune": true, "trap_immune": true, "post": [from.x, from.y, rad_to_deg((to - from).angle())]}
	var beast: Dictionary = _make_guard(entry)
	_set_state(beast, "waiting")
	beast["at"] = float(spec.get("at", 0.0))
	beast["home"] = from
	beast["entry"] = to
	beast["text"] = str(spec.get("text", ""))
	beast["hits"] = 0
	beast["think"] = 0.0
	beast["pause_left"] = 0.0
	beast["away_left"] = 0.0
	beast["linger_left"] = 0.0
	beast["noise_kind"] = ""
	beast["roams"] = 0
	# who it has knocked down lately (id -> until when it leaves him be): one who gets up again is not set on at once
	beast["spared"] = {}
	return beast

## The creatures in the square now (come in, not driven off the map, not dead).
func creatures_about() -> Array:
	var out: Array = []
	for guard: Dictionary in guards:
		if bool(guard.get("creature", false)) and str(guard.state) in ["prowl", "stalk", "drawn", "stay", "driven"]:
			out.append(guard)
	return out

func _creature_number(key: String, fallback: float) -> float:
	return float(_creatures().get(key, fallback))

func _update_creature(beast: Dictionary, dt: float) -> void:
	match str(beast.state):
		"waiting":
			if time >= float(beast.at):
				_creature_enters(beast, true)
			return
		"dead":
			return
		"away":
			beast.away_left = float(beast.away_left) - dt
			if float(beast.away_left) <= 0.0:
				_creature_enters(beast, false)
			return
		"driven":
			_creature_walk(beast, _creature_number("flee", CREATURE_FLEE), dt)
			if (beast.path as Array).is_empty():
				# off the map the way it came; back when it has got over it
				_set_state(beast, "away")
				beast.away_left = _creature_number("away", CREATURE_AWAY)
				var home: Vector2 = beast.home
				beast.x = home.x
				beast.y = home.y
				_emit({"type": "creature_gone", "id": str(beast.id), "x": home.x, "y": home.y})
			return
		"stay":
			beast.pause_left = float(beast.pause_left) - dt
			if float(beast.pause_left) <= 0.0:
				_set_state(beast, "prowl")
				beast.think = 0.0
			return
		"drawn":
			if (beast.path as Array).is_empty():
				beast.linger_left = float(beast.linger_left) - dt
				if float(beast.linger_left) <= 0.0:
					_set_state(beast, "prowl")
					beast.noise_kind = ""
					beast.think = 0.0
			else:
				_creature_walk(beast, _creature_number("charge", CREATURE_CHARGE), dt)
			_creature_reaches(beast)
			return
	# "prowl" and "stalk": choose again now and then, walk, and knock down whoever it reaches
	beast.think = float(beast.think) - dt
	if float(beast.think) <= 0.0:
		_creature_think(beast)
	var stalking: bool = str(beast.state) == "stalk"
	_creature_walk(beast, _creature_number("charge" if stalking else "speed", CREATURE_CHARGE if stalking else CREATURE_SPEED), dt)
	_creature_reaches(beast)

## In from the edge of the map where it came (or comes back), walking on to its first spot in the square.
func _creature_enters(beast: Dictionary, first: bool) -> void:
	var from: Vector2 = beast.home
	var to: Vector2 = beast.entry
	beast.x = from.x
	beast.y = from.y
	_set_state(beast, "prowl")
	beast.target_id = ""
	beast.noise_kind = ""
	beast.goal = to
	beast.path = _creature_path(from, to)
	beast.angle = (to - from).angle()
	beast.think = 2.0
	_emit({"type": "creature", "id": str(beast.id), "x": from.x, "y": from.y, "again": not first})
	if first:
		message = str(beast.text) if str(beast.text) != "" else _creature_text("arrive", "A creature comes into the square.")
	else:
		message = _creature_text("back", "A cascarudo is back in the square.")

## Who a creature can go for: everyone of the square on his feet and out in the open (under no cover at all, not in a
## vehicle), the squad among them; nobody under cover, nobody down already, nobody carried, nobody it knocked down a
## moment ago (data creatures.spare seconds).
func _creature_prey(beast: Dictionary) -> Array:
	var out: Array = []
	var spared: Dictionary = beast.get("spared", {})
	for person: Dictionary in guards:
		if not bool(person.get("person", false)) or not str(person.state) in LEADABLE_STATES:
			continue
		if shelter_at(position_of(person), false) == "" and float(spared.get(str(person.id), -1.0)) < time:
			out.append(person)
	for unit: Dictionary in units:
		if not bool(unit.alive) or bool(unit.get("away", false)) or bool(unit.get("fallen", false)):
			continue
		if shelter_at(position_of(unit), false) == "" and float(spared.get(str(unit.id), -1.0)) < time:
			out.append(unit)
	return out

## Choose: the nearest one out in the open within its sense goes for him at a rush ("stalk"); else it roams toward the
## nearest one out in the open anywhere ("prowl"); with nobody out at all, it wanders the square.
func _creature_think(beast: Dictionary) -> void:
	beast.think = _creature_number("think", CREATURE_THINK)
	var here: Vector2 = position_of(beast)
	var best: Dictionary = {}
	var best_d: float = INF
	for prey: Dictionary in _creature_prey(beast):
		var d: float = here.distance_to(position_of(prey))
		if d < best_d:
			best = prey
			best_d = d
	var goal: Vector2
	if best.is_empty():
		_set_state(beast, "prowl")
		beast.target_id = ""
		var path: Array = beast.path
		if not path.is_empty() and (beast.goal as Vector2).distance_to(here) > 48.0:
			return  # still on its way to the last spot it chose
		goal = _creature_wander(beast)
	else:
		_set_state(beast, "stalk" if best_d <= _creature_number("sense", CREATURE_SENSE) else "prowl")
		beast.target_id = str(best.id) if str(beast.state) == "stalk" else ""
		goal = position_of(best)
	var route: Array = beast.path
	if route.is_empty() or (route.back() as Vector2).distance_to(goal) > 24.0:
		beast.path = _creature_path(here, goal)
	beast.goal = goal

## A spot in the square to wander to (data creatures.roam: [x, y, w, h]), a different one each time.
func _creature_wander(beast: Dictionary) -> Vector2:
	var roam: Array = _creatures().get("roam", [0.0, 0.0, _width, _height])
	var area := Rect2(float(roam[0]), float(roam[1]), float(roam[2]), float(roam[3]))
	for attempt: int in range(8):
		beast.roams = int(beast.roams) + 1
		var h: int = hash("%s:%d" % [str(beast.id), int(beast.roams)])
		var at: Vector2 = area.position + area.size * Vector2(float(h & 0xffff) / 65535.0, float((h >> 16) & 0xffff) / 65535.0)
		if not is_blocked(at, _creature_number("radius", CREATURE_RADIUS)):
			return at
	return area.get_center()

## Walks a creature along its path. A vehicle under way is not walked into (its ground has it where it last stopped):
## it waits; one that has driven into it pushes it aside.
func _creature_walk(beast: Dictionary, speed: float, dt: float) -> void:
	var before: Vector2 = position_of(beast)
	_advance(beast, speed, dt)
	var radius: float = _creature_number("radius", CREATURE_RADIUS)
	for id: String in vehicles:
		var box: Rect2 = vehicle_rect(id).grow(radius)
		if not box.has_point(position_of(beast)):
			continue
		if box.has_point(before):
			beast.y = box.position.y - 1.0 if float(beast.y) < box.get_center().y else box.end.y + 1.0
		else:
			beast.x = before.x
			beast.y = before.y
		beast.path = []
		beast.think = minf(float(beast.think), 0.2)

## Knocks down whoever it has reached (the nearest, with nothing solid between): a person falls in the snow, one of the
## squad goes down. Then it stands over them a moment.
func _creature_reaches(beast: Dictionary) -> void:
	var here: Vector2 = position_of(beast)
	var reach: float = _creature_number("reach", CREATURE_REACH)
	var hit: Dictionary = {}
	var best: float = INF
	for prey: Dictionary in _creature_prey(beast):
		var d: float = here.distance_to(position_of(prey))
		if d <= reach and d < best and _reach_clear(here, position_of(prey)):
			hit = prey
			best = d
	if not hit.is_empty():
		_creature_strikes(beast, hit)

func _creature_strikes(beast: Dictionary, victim: Dictionary) -> void:
	var is_unit: bool = not unit_by_id(str(victim.id)).is_empty()
	if is_unit:
		_unit_falls(victim)
		message = _creature_text("strikeUnit", "A cascarudo has knocked %s down in the snow.") % victim.name
	else:
		_person_falls(victim)
		message = _creature_text("strike", "A cascarudo has knocked someone down in the snow. Carry them in before it covers them.")
	_set_state(beast, "stay")
	beast.pause_left = _creature_number("pause", CREATURE_PAUSE)
	(beast.spared as Dictionary)[str(victim.id)] = time + _creature_number("spare", 20.0)
	beast.target_id = ""
	beast.path = []
	beast.angle = (position_of(victim) - position_of(beast)).angle() if position_of(victim).distance_to(position_of(beast)) > 1.0 else float(beast.angle)
	stats["struck"] = int(stats.get("struck", 0)) + 1
	_emit({"type": "struck", "by": str(beast.id), "id": str(victim.id), "unit": is_unit, "x": float(victim.x), "y": float(victim.y)})

## Noise draws them (data creatures.hear: how far each kind of noise is heard): the tram's bell, a shout, a shot. Every
## creature in the square that hears a new one goes to it and stays about there a while, ignoring everyone it does not
## walk into on the way. Each noise is heard once.
func _creatures_hear() -> void:
	var hear: Dictionary = _creatures().get("hear", {})
	if hear.is_empty():
		return
	for sound: Dictionary in noise:
		if bool(sound.get("beasts", false)):
			continue
		sound["beasts"] = true
		var kind: String = str(sound.get("kind", ""))
		var reach: float = float(hear.get(kind, 0.0))
		if reach <= 0.0:
			continue
		var at := Vector2(float(sound.x), float(sound.y))
		var drawn: Array[String] = []
		for beast: Dictionary in guards:
			if not bool(beast.get("creature", false)) or not str(beast.state) in ["prowl", "stalk", "drawn"]:
				continue
			if position_of(beast).distance_to(at) > reach:
				continue
			var route: Array = _creature_path(position_of(beast), at)
			if route.is_empty():
				continue
			_set_state(beast, "drawn")
			beast.path = route
			beast.goal = route.back()
			beast.target_id = ""
			beast.noise_kind = kind
			beast.linger_left = _creature_number("linger", CREATURE_LINGER)
			drawn.append(str(beast.id))
		if not drawn.is_empty():
			_emit({"type": "drawn", "ids": drawn, "noise": kind, "x": at.x, "y": at.y})
			var said: String = str(_creatures().get("drawnBy", {}).get(kind, ""))
			if said != "":
				message = (message + " " + said).strip_edges() if message != said else said

## A shot at a creature (_process_shot): a hit drives it off the way it came, the last of data creatures.hits kills it;
## hit or not, the bang is heard across the square (a noise of the gun's "sound", data gun.noise far) and draws the
## others to the one who fired.
func _creature_shot(unit: Dictionary, beast: Dictionary, hit: bool) -> void:
	var here: Vector2 = position_of(unit)
	if hit:
		beast.hits = int(beast.hits) + 1
		beast.target_id = ""
		if int(beast.hits) >= int(_creature_number("hits", CREATURE_HITS)):
			_set_state(beast, "dead")
			beast.path = []
			stats["creatures_killed"] = int(stats.get("creatures_killed", 0)) + 1
			_emit({"type": "creature_dead", "id": str(beast.id), "by": str(unit.id), "x": float(beast.x), "y": float(beast.y)})
			message = _creature_text("killed", "%s's shot brings the cascarudo down. It does not get up again.") % unit.name
		else:
			_set_state(beast, "driven")
			beast.path = _creature_path(position_of(beast), beast.home)
			_emit({"type": "creature_hit", "id": str(beast.id), "by": str(unit.id), "hits": int(beast.hits), "x": float(beast.x), "y": float(beast.y)})
			message = _creature_text("driven", "Hit, the cascarudo turns and makes off the way it came.")
	else:
		message = _creature_text("missed", "%s fires, and misses.") % unit.name
	var gun: Dictionary = unit.get("gun", {})
	noise.append({"x": here.x, "y": here.y, "radius": float(gun.get("noise", 2880.0)), "ttl": 1.6, "max_ttl": 1.6, "kind": str(gun.get("sound", "rifle"))})

## A path over the creatures' ground (_beast_ground): round everything solid, every shelter and every vehicle. A goal on
## something it cannot walk on (the tram it was drawn to) becomes the nearest open spot by it. [] when there is no way.
func _creature_path(from: Vector2, to: Vector2) -> Array:
	_ensure_geometry()
	if _beast_dirty or _geo_beast.is_empty():
		_beast_dirty = false
		_geo_beast = _beast_ground()
	var keep: Dictionary = {"move": _move_rects, "body": _body_rects, "grid": _grid, "region": _region}
	_use_ground(_geo_beast)
	var goal: Vector2 = to
	if _blocked(goal, BODY_RADIUS):
		goal = _open_near(to)
	var route: Array = find_path(from, goal) if goal.is_finite() else []
	_use_ground(keep)
	return route

## Whether a creature could stand at `point` (the creatures' ground).
func creature_ground_open(point: Vector2) -> bool:
	_ensure_geometry()
	if _beast_dirty or _geo_beast.is_empty():
		_beast_dirty = false
		_geo_beast = _beast_ground()
	for rect: Rect2 in (_geo_beast.body as Array[Rect2]):
		if rect.has_point(point):
			return false
	return not _blocked(point, 1.0)

func _beast_ground() -> Dictionary:
	var move: Array[Rect2] = []
	for rect: Rect2 in (_geo_base.get("move", []) as Array[Rect2]):
		move.append(rect)
	for shelter: Dictionary in shelters():
		if not shelter.has("vehicle"):
			move.append(rect_of(shelter))
	for id: String in vehicles:
		move.append(vehicle_rect(id))
	return _ground(move, _creature_number("radius", CREATURE_RADIUS))

## The nearest open spot (on the ground now in use) round `point`, in rings out to 10 m; a non-finite vector if none.
func _open_near(point: Vector2) -> Vector2:
	for ring: int in range(1, 11):
		for k: int in range(16):
			var at: Vector2 = point + Vector2.from_angle(TAU * float(k) / 16.0) * 32.0 * float(ring)
			if not _blocked(at, BODY_RADIUS):
				return at
	return Vector2(INF, INF)

# --- objectives, results, checkpoints ---
func _complete_objective(id: String) -> void:
	for objective: Dictionary in objectives:
		if objective.id == id:
			objective.done = true

func _check_extraction() -> void:
	if phase != "playing" or not data.has("extraction") or not ready_to_leave():
		return
	var center: Vector2 = Vector2(float(data.extraction.x), float(data.extraction.y))
	var radius: float = float(data.extraction.radius)
	for unit: Dictionary in units:
		# a local goes home his own way (data "exit") and does not hold up the boat: once the others are aboard he
		# slips off home from wherever he is
		if unit.has("exit"):
			continue
		if position_of(unit).distance_to(center) > radius:
			return
	if not bool(prisoner.aboard) and position_of(prisoner).distance_to(center) > radius:
		return
	for unit: Dictionary in units:
		if not unit.has("exit") or not bool(unit.get("alive", true)): continue
		var exit: Dictionary = unit.exit
		var home: bool = position_of(unit).distance_to(Vector2(float(exit.x), float(exit.y))) <= float(exit.get("radius", radius))
		unit["home"] = true
		if not home: _emit({"type": "slipped_home", "id": str(unit.id)})
	phase = "won"
	paused = true
	_complete_objective("extract")
	message = str(data.get("winMessage", "Everyone is safe."))
	_emit({"type": "won", "time": time})

## The five result badges with their earned flags; meaningful once phase == "won". A mission with "medals" in its data
## has its own instead: {id, art (the medal drawn, else a glyph), label, text, rule}, the rules "everyone" (nobody in the
## square lost), "squad" (none of the squad lost), "time" (done within parTime; the text takes the minutes and seconds).
func result_badges() -> Array[Dictionary]:
	if data.has("medals"):
		var own: Array[Dictionary] = []
		var counts: Dictionary = rescue_counts()
		for medal: Dictionary in data.medals:
			var earned: bool = false
			var text: String = str(medal.get("text", ""))
			match str(medal.get("rule", "")):
				"everyone": earned = int(counts.lost) == 0 and int(counts.out) == 0 and int(counts.fallen) == 0
				"squad": earned = int(stats.get("squad_lost", 0)) == 0
				"time":
					earned = time <= par_time
					if text.contains("%d"): text = text % [floori(par_time / 60.0), int(par_time) % 60]
			own.append({"id": str(medal.id), "label": str(medal.get("label", medal.id)), "text": text, "earned": earned, "art": str(medal.get("art", medal.id))})
		return own
	return [
		{"id": "ghost", "label": "Ghost", "text": "No alarm was raised", "earned": int(stats.alarms) == 0},
		{"id": "clean_hands", "label": "Clean hands", "text": "Nobody was killed", "earned": int(stats.kills) == 0},
		{"id": "not_a_shot", "label": "Not a shot", "text": "No round was fired", "earned": int(stats.shots) == 0},
		{"id": "saboteur", "label": "Saboteur", "text": str(data.get("radio", {}).get("badge", "The radio was silenced")), "earned": radio_cut},
		{"id": "swift", "label": "Swift", "text": "Out in under %d:%02d" % [floori(par_time / 60.0), int(par_time) % 60], "earned": time <= par_time}]

func badge_earned(id: String) -> bool:
	for badge: Dictionary in result_badges():
		if badge.id == id:
			return bool(badge.earned)
	return false

## Deep copy of everything that changes during a mission. Feed it back to restore().
func snapshot() -> Dictionary:
	return {
		"phase": phase, "paused": paused, "time": time, "selected_id": selected_id, "message": message, "lost_reason": lost_reason,
		"door_open": door_open, "fence_cut": fence_cut, "radio_cut": radio_cut, "planted": planted.duplicate(),
		"rigged": rigged.duplicate(), "tracks": tracks.duplicate(true), "fuse_left": fuse_left, "blasted": blasted, "track_serial": _track_serial,
		"units": units.duplicate(true), "guards": guards.duplicate(true), "prisoner": prisoner.duplicate(true),
		"noise": noise.duplicate(true), "traps": traps.duplicate(true), "alarm": alarm.duplicate(true),
		"objectives": objectives.duplicate(true), "stats": stats.duplicate(true),
		"spawned": _spawned, "trap_serial": _trap_serial, "pending_checkpoint": _pending_checkpoint,
		"vehicles": vehicles.duplicate(true), "canvases_taken": canvases_taken.duplicate(), "gear_taken": gear_taken.duplicate(), "buried_square": buried_square,
		"rank_serial": _rank_serial, "snow_level": _snow_level}

## Puts the mission back exactly as snapshot() saw it. Actor dictionaries are replaced, so drop any references to them.
func restore(saved: Dictionary) -> void:
	phase = saved.phase
	paused = saved.paused
	time = saved.time
	selected_id = saved.selected_id
	message = saved.message
	lost_reason = saved.lost_reason
	door_open = saved.door_open
	fence_cut = saved.fence_cut
	radio_cut = saved.radio_cut
	planted = saved.get("planted", {}).duplicate()
	rigged = saved.get("rigged", {}).duplicate()
	_geometry_dirty = true
	tracks = saved.get("tracks", []).duplicate(true)
	fuse_left = float(saved.get("fuse_left", -1.0))
	blasted = bool(saved.get("blasted", false))
	_track_serial = int(saved.get("track_serial", 0))
	units = saved.units.duplicate(true)
	guards = saved.guards.duplicate(true)
	prisoner = saved.prisoner.duplicate(true)
	noise = saved.noise.duplicate(true)
	traps = saved.traps.duplicate(true)
	alarm = saved.alarm.duplicate(true)
	objectives = saved.objectives.duplicate(true)
	stats = saved.stats.duplicate(true)
	_spawned = saved.spawned
	_trap_serial = saved.trap_serial
	_pending_checkpoint = saved.pending_checkpoint
	vehicles = saved.get("vehicles", {}).duplicate(true)
	canvases_taken = saved.get("canvases_taken", {}).duplicate()
	gear_taken = saved.get("gear_taken", {}).duplicate()
	buried_square = bool(saved.get("buried_square", false))
	_rank_serial = int(saved.get("rank_serial", 0))
	_snow_level = str(saved.get("snow_level", ""))
	events.clear()

## Checkpoints are refused during an alarm and while any guard is growing suspicious.
func can_save_checkpoint() -> bool:
	return phase == "playing" and not bool(alarm.active) and max_suspicion() <= CHECKPOINT_SUSPICION

func save_checkpoint() -> bool:
	if phase != "playing":
		return false
	if bool(alarm.active):
		return _refuse("No checkpoint during an alarm.")
	if max_suspicion() > CHECKPOINT_SUSPICION:
		return _refuse("No checkpoint while a guard is suspicious.")
	_store_checkpoint("manual", false)
	message = "Checkpoint saved."
	return true

func has_checkpoint() -> bool:
	return not checkpoint.is_empty()

## Returns to the last checkpoint and pauses. The count of loads survives the reload.
func load_checkpoint() -> bool:
	if checkpoint.is_empty():
		return false
	restore(checkpoint.state)
	_loads += 1
	stats.checkpoints_loaded = _loads
	phase = "playing"
	paused = true
	message = "Back at the checkpoint. Give your orders, then resume."
	_emit({"type": "checkpoint", "action": "load", "label": checkpoint.label, "auto": checkpoint.auto})
	return true

func _store_checkpoint(label: String, auto: bool) -> void:
	stats.checkpoints_loaded = _loads
	checkpoint = {"label": label, "auto": auto, "time": time, "state": snapshot()}
	_emit({"type": "checkpoint", "action": "save", "label": label, "auto": auto})

func _emit(event: Dictionary) -> void:
	event["time"] = time
	events.append(event)
	if events.size() > EVENT_LIMIT:
		events.pop_front()

# ---------------------------------------------------------------------------------------------
# Queries for the HUD and the renderer
# ---------------------------------------------------------------------------------------------
func max_suspicion() -> float:
	var value: float = 0.0
	for guard: Dictionary in guards:
		if _is_able(guard):
			value = maxf(value, float(guard.suspicion))
	return value

## The action bar of an operative (the selected one by default), in display order. Each entry is
## {id, label, kind, enabled, reason, count, cooldown, cooldown_total, context, active}; see GAMEPLAY_API.md.
func available_actions(unit_id: String = "") -> Array[Dictionary]:
	var unit: Dictionary = selected() if unit_id == "" else unit_by_id(unit_id)
	var list: Array[Dictionary] = []
	if unit.is_empty():
		return list
	var live: bool = phase == "playing" and bool(unit.alive)
	var blocked: String = "" if live else "The mission is not running."
	var carrying: bool = str(unit.carrying) != ""
	var loaded: String = _loaded_reason(unit)
	var current: String = str(unit.order.get("type", ""))
	if live and bool(unit.get("fallen", false)):
		blocked = _snow_text("down", "%s is down in the snow.") % unit.name
	if live and bool(unit.get("away", false)):
		blocked = str(unit.arrive.get("notYet", "%s is not here yet.")) % unit.name
	list.append(_action("stance", "Stand" if unit.stance == "sneak" else "Crouch", "instant", _first(blocked, loaded)))
	if rescue_on:
		# the rescue's own: lead people in (tap a person), the call, the tram, a cloth
		var full: bool = followers_of(str(unit.id)).size() >= lead_of(unit)
		var guide: Dictionary = _action("guide", _snow_text("guideLabel", "Lead in"), "target_guard", _first(blocked, loaded,
			(_snow_text("full", "%s is leading as many as he can. Bring them in first.") % unit.name) if full else ""))
		guide.count = followers_of(str(unit.id)).size()
		list.append(guide)
		if unit.has("call"):
			var call: Dictionary = unit.call
			var from: String = str(call.get("from", ""))
			var away: bool = from != "" and vehicle_at(position_of(unit)) != from
			var none_left: bool = int(unit.get("calls", -1)) == 0
			var entry: Dictionary = _action("call", str(call.get("label", "Call")), "instant", _first(blocked, loaded,
				(str(call.get("empty", "Nothing left.")) % unit.name) if none_left else ((str(call.get("away", "Not from here.")) % unit.name) if away else ("Not ready yet." if float(unit.cooldown) > 0.0 else ""))))
			entry.cooldown = float(unit.cooldown)
			entry.cooldown_total = float(call.get("cooldown", 12.0))
			entry.range = float(call.get("radius", 0.0))
			if int(unit.get("calls", -1)) >= 0: entry.count = int(unit.calls)
			list.append(entry)
		var drives: Dictionary = _vehicle_for(unit, "")
		if not drives.is_empty():
			var moving: bool = int(vehicles[str(drives.id)].to) >= 0
			var entry: Dictionary = _action("drive", str(drives.get("label", "Drive")), "context", _first(blocked, loaded, str(drives.get("moving", "It is moving.")) if moving and str(unit.order.get("type", "")) != "drive" else ""))
			entry.context = true
			list.append(entry)
		if not canvases().is_empty():
			var holding: bool = not (unit.get("canvas", {}) as Dictionary).is_empty()
			var left: int = 0
			for canvas: Dictionary in canvases():
				if not canvases_taken.has(str(canvas.id)): left += 1
			var entry: Dictionary = _action("canvas", _snow_text("canvasLabel", "Cloth"), "context", _first(blocked, loaded,
				(_snow_text("holding", "%s is already holding a cloth over them.") % unit.name) if holding else (_snow_text("noCanvas", "There is no cloth left to take.") if left == 0 else "")))
			entry.context = true
			entry.count = left
			list.append(entry)
		if not gear().is_empty():
			# the gear left about the square: the plate names the nearest piece he can use
			var left_gear: int = 0
			for item: Dictionary in gear():
				if not gear_taken.has(str(item.id)): left_gear += 1
			var nearest: Dictionary = _gear_for("", position_of(unit))
			var entry: Dictionary = _action("take", str(nearest.get("label", "")) if not nearest.is_empty() else _snow_text("takeLabel", "Take"), "context", _first(blocked, loaded,
				_snow_text("noGear", "There is nothing left there to take.") if left_gear == 0 else _gear_refusal(unit, nearest)))
			entry.context = true
			entry.count = left_gear
			list.append(entry)
	if unit.has("melee"):
		list.append(_action("takedown", str(unit.melee.get("label", "Takedown")), "target_guard", _first(blocked, loaded)))
	if unit.has("gun"):
		var gun: Dictionary = unit.gun
		var entry: Dictionary = _action("shoot", str(gun.get("label", "Shoot")), "target_guard", _first(blocked, loaded, "Out of ammunition." if int(unit.ammo) <= 0 else ""))
		entry.count = int(unit.ammo)
		entry.cooldown = float(unit.weapon_cooldown)
		entry.cooldown_total = float(gun.get("recover", 0.7))
		entry.range = float(gun.get("range", 240.0))
		list.append(entry)
	var throw: Dictionary = throw_spec(unit)
	if not throw.is_empty():
		var none_left: bool = int(unit.get("throws", -1)) == 0
		var entry: Dictionary = _action("distract", str(throw.get("label", "Pebble")), "target_point", _first(blocked, loaded,
			"Nothing left to throw." if none_left else ("Not ready yet." if float(unit.cooldown) > 0.0 else "")))
		entry.cooldown = float(unit.cooldown)
		entry.cooldown_total = float(throw.cooldown)
		entry.range = float(throw.range)
		if int(unit.get("throws", -1)) >= 0: entry.count = int(unit.throws)
		list.append(entry)
	if int(unit.trap_kit) > 0:
		if int(unit.traps) <= 0 and not traps.is_empty():
			list.append(_action("trap_pickup", "Recover trap", "instant", _first(blocked, loaded)))
		else:
			var entry: Dictionary = _action("trap", "Tripwire", "instant", _first(blocked, loaded, "No tripwire left." if int(unit.traps) <= 0 else ""))
			entry.count = int(unit.traps)
			list.append(entry)
	if carrying:
		list.append(_action("drop", "Drop body", "instant", blocked))
	else:
		var any_body: bool = false
		for guard: Dictionary in guards:
			if guard.state in BODY_STATES and str(guard.carried_by) == "" and float(guard.elevation) <= 0.0 and not bool(guard.hidden):
				# a fallen person is carried in only by one strong enough (data units[].carries); a creature by nobody
				if bool(guard.get("person", false)) and not bool(unit.get("carries", false)): continue
				if bool(guard.get("creature", false)): continue
				any_body = true
		list.append(_action("pickup", "Carry", "target_guard", _first(blocked, "" if any_body else "Nobody to carry.")))
	# What tapping the world would do, for bars that want one context button.
	if bool(unit.tools):
		var entry: Dictionary
		if data.has("door"):
			entry = _action("unlock", str(data.door.get("label", "Unlock")), "context", _first(blocked, loaded, _door_text("already", "The cell is open.") if door_open else ""))
			entry.context = true
			list.append(entry)
		if data.has("fence"):
			entry = _action("cut", "Cut wire", "context", _first(blocked, loaded, "The wire is cut." if fence_cut else ""))
			entry.context = true
			list.append(entry)
	if can_sabotage(unit):
		var entry: Dictionary = _action("sabotage", str(data.radio.get("label", "Sabotage")), "context", _first(blocked, loaded, str(data.radio.get("deadReason", "The radio is dead.")) if radio_cut else ""))
		entry.context = true
		list.append(entry)
	var carries: Array = []
	for site: Dictionary in charge_sites():
		if can_plant(unit, site):
			carries.append(site)
	if not carries.is_empty():
		var left: int = 0
		for site: Dictionary in carries:
			if not planted.has(str(site.id)):
				left += 1
		var entry: Dictionary = _action("plant", str(carries[0].get("label", "Plant")), "context", _first(blocked, loaded, "All set." if left == 0 else ""))
		entry.context = true
		entry.count = left
		list.append(entry)
	var ropes: Array = []
	for passage: Dictionary in passages():
		if can_rig(unit, passage) and not (passage.get("by", []) as Array).is_empty():
			ropes.append(passage)
	if not ropes.is_empty():
		var left: int = 0
		for passage: Dictionary in ropes:
			if not rigged.has(str(passage.id)):
				left += 1
		var entry: Dictionary = _action("rig", str(ropes[0].get("label", "Rope")), "context", _first(blocked, loaded, "The rope is fixed." if left == 0 else ""))
		entry.context = true
		entry.count = left
		list.append(entry)
	if unit.has("talk"):
		var talk: Dictionary = unit.talk
		var anyone: bool = false
		for guard: Dictionary in guards:
			if bool(guard.get("civilian", false)) and _is_able(guard):
				anyone = true
		var word: Dictionary = _action("talk", str(talk.get("label", "Talk")), "target_guard", _first(blocked, loaded, "" if anyone else str(talk.get("nobody", "Nobody here to talk to."))))
		word.range = TALK_RANGE
		list.append(word)
	if unit.has("chat"):
		var chat: Dictionary = unit.chat
		var smoke: Dictionary = _action("chat", str(chat.get("label", "Cigarette")), "target_guard", _first(blocked, loaded,
			"No cigarettes left." if int(unit.smokes) <= 0 else ("Not during an alarm." if bool(alarm.active) else "")))
		smoke.count = int(unit.smokes)
		smoke.range = CHAT_RANGE
		list.append(smoke)
	if has_prisoner:
		var rescue: Dictionary = _action("rescue", "Escort" if bool(prisoner.freed) else "Rescue", "context", _first(blocked, loaded, _door_text("locked", "The cell is locked.") if _locked_in() else ("He is in the boat." if bool(prisoner.aboard) else ("Already following." if str(prisoner.follow_id) == str(unit.id) else ""))))
		rescue.context = true
		list.append(rescue)
	if data.has("extraction") or unit.has("exit"):
		var leave: Dictionary = _action("extract", str(unit.get("exit", data.get("extraction", {})).get("label", "To the boat")), "context", blocked)
		leave.context = true
		list.append(leave)
	for entry: Dictionary in list:
		entry.active = entry.id == current
	return list

## Why an operative with something on his shoulders cannot do anything else ("" with his hands free).
func _loaded_reason(unit: Dictionary) -> String:
	if str(unit.get("carrying", "")) == "":
		return ""
	if bool(guard_by_id(str(unit.carrying)).get("person", false)):
		return _snow_text("setDownReason", "Set them down under cover first.")
	return "Put the body down first."

func _action(id: String, label: String, kind: String, reason: String) -> Dictionary:
	return {"id": id, "label": label, "kind": kind, "enabled": reason == "", "reason": reason, "count": -1, "cooldown": 0.0, "cooldown_total": 0.0, "range": 0.0, "context": false, "active": false}

func _first(a: String, b: String = "", c: String = "") -> String:
	return a if a != "" else (b if b != "" else c)

## World things that can be tapped right now, for the selected operative. Each entry is
## {id, type, label, x, y, radius, order, target, enabled, reason}: call perform(order, target).
func interactables() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	if phase != "playing":
		return list
	var unit: Dictionary = selected()
	var carrying: bool = str(unit.get("carrying", "")) != ""
	var loaded: String = _loaded_reason(unit)
	var tools: String = "" if bool(unit.get("tools", false)) else _door_text("refuse", "He does not have the tools.")
	if rescue_on:
		_rescue_things(unit, list, loaded)
	if data.has("door") and not door_open:
		var gate: Rect2 = rect_of(data.door)
		list.append(_interactable("cell-gate", "gate", str(data.door.get("label", "Unlock")), gate.get_center(), 40.0, "unlock", null, _first(loaded, tools)))
	if has_prisoner and not _locked_in() and bool(prisoner.alive) and not bool(prisoner.aboard) and str(prisoner.follow_id) != str(unit.get("id", "")):
		list.append(_interactable("asset", "informant", "Escort" if bool(prisoner.freed) else "Rescue", position_of(prisoner), 26.0, "rescue", null, loaded))
	if data.has("fence") and not fence_cut:
		var span: Dictionary = _barrier(str(data.fence.get("span", "")))
		if not span.is_empty():
			list.append(_interactable(str(span.id), "fence", "Cut wire", rect_of(span).get_center(), 44.0, "cut", null, _first(loaded, tools)))
	if data.has("radio") and not radio_cut:
		var refuse: String = "" if can_sabotage(unit) else str(data.radio.get("refuse", "He does not have the tools."))
		list.append(_interactable("radio", str(data.radio.get("thing", "radio")), str(data.radio.get("label", "Sabotage")), Vector2(float(data.radio.x), float(data.radio.y)), 30.0, "sabotage", null, _first(loaded, refuse)))
	for site: Dictionary in charge_sites():
		if planted.has(str(site.id)):
			continue
		var refuse: String = "" if can_plant(unit, site) else str(site.get("refuse", "%s does not carry those." % str(unit.get("name", ""))))
		var at: Vector2 = Vector2(float(site.get("tx", site.x)), float(site.get("ty", site.y)))
		list.append(_interactable(str(site.id), str(site.get("kind", "charge")), str(site.get("label", "Plant")), at, float(site.get("radius", 30.0)), "plant", str(site.id), _first(loaded, refuse)))
	for passage: Dictionary in passages():
		if rigged.has(str(passage.id)):
			continue
		var refuse: String = "" if can_rig(unit, passage) else _named(str(passage.get("refuse", "%s does not carry the rope.")), str(unit.get("name", "")))
		list.append(_interactable(str(passage.id), str(passage.get("kind", "rope")), str(passage.get("label", "Rope")), passage_anchor(passage), float(passage.get("radius", 30.0)), "rig", str(passage.id), _first(loaded, refuse)))
	if unit.has("talk"):
		for guard: Dictionary in guards:
			if bool(guard.get("civilian", false)) and _is_able(guard):
				list.append(_interactable(str(guard.id), "civilian", str(unit.talk.get("label", "Talk")), position_of(guard), 26.0, "talk", str(guard.id), loaded))
	for trap: Dictionary in traps:
		list.append(_interactable(str(trap.id), "trap", "Recover trap", Vector2(float(trap.x), float(trap.y)), 22.0, "trap_pickup", str(trap.id), _first(loaded, "" if int(unit.get("trap_kit", 0)) > 0 else "He has no tripwire.")))
	for guard: Dictionary in guards:
		if guard.state in BODY_STATES and str(guard.carried_by) == "" and float(guard.elevation) <= 0.0 and not bool(guard.hidden) and not bool(guard.get("creature", false)):
			var refuse: String = loaded
			if bool(guard.get("person", false)) and not bool(unit.get("carries", false)):
				refuse = _first(loaded, _snow_text("carry", "Only Biguá is strong enough to carry them in."))
			list.append(_interactable(str(guard.id), "body", "Carry", position_of(guard), 24.0, "pickup", str(guard.id), refuse))
	if data.has("uniforms"):
		# his uniform, as long as nobody has taken it (a hidden man can still be stripped in his bush)
		for guard: Dictionary in guards:
			if guard.state in BODY_STATES and str(guard.carried_by) == "" and float(guard.elevation) <= 0.0 and not bool(guard.stripped):
				list.append(_interactable(str(guard.id), "uniform", str(data.uniforms.get("action", "Uniform")), position_of(guard), 24.0, "uniform", str(guard.id), loaded))
	if carrying:
		# With a body on his shoulders every bush is a hiding place: perform("drop", its centre).
		var bushes: Array = data.get("bushes", [])
		for index: int in range(bushes.size()):
			var bush: Rect2 = rect_of(bushes[index])
			list.append(_interactable("bush-%d" % index, "bush", "Hide body", bush.get_center(), minf(bush.size.x, bush.size.y) * 0.5, "drop", bush.get_center(), ""))
	if data.has("extraction") and (bool(prisoner.freed) or (not has_prisoner and ready_to_leave())):
		var exit: Dictionary = unit.get("exit", data.extraction)
		list.append(_interactable("extraction", str(exit.get("type", "extraction")), str(exit.get("label", "To the boat")), Vector2(float(exit.x), float(exit.y)), float(exit.get("radius", data.extraction.radius)), "extract", null, ""))
	return list

## The rescue's tappable things: the people out in the snow ("person", lead them in), a mate down in the snow
## ("fallen", help him up), the cloths left ("canvas"), the vehicles this operative can drive (their kind, "tram").
func _rescue_things(unit: Dictionary, list: Array[Dictionary], loaded: String) -> void:
	var down: String = (_snow_text("down", "%s is down in the snow.") % str(unit.get("name", ""))) if bool(unit.get("fallen", false)) else ""
	var full: String = (_snow_text("full", "%s is leading as many as he can. Bring them in first.") % str(unit.get("name", ""))) if followers_of(str(unit.get("id", ""))).size() >= lead_of(unit) else ""
	for person: Dictionary in guards:
		if not bool(person.get("person", false)) or not str(person.state) in LEADABLE_STATES:
			continue
		if str(person.state) == "follow" and str(person.follow_id) == str(unit.get("id", "")):
			continue
		var stuck: String = _snow_text("stuck", "Too far gone to walk: bring the colectivo to them.") if bool(person.get("stuck", false)) else ""
		list.append(_interactable(str(person.id), "person", _snow_text("guideLabel", "Lead in"), position_of(person), 26.0, "guide", str(person.id), _first(down, loaded, _first(stuck, full))))
	for mate: Dictionary in units:
		if bool(mate.alive) and bool(mate.get("fallen", false)) and str(mate.id) != str(unit.get("id", "")):
			list.append(_interactable(str(mate.id), "fallen", _snow_text("helpLabel", "Help up"), position_of(mate), 28.0, "help", str(mate.id), _first(down, loaded)))
	if (unit.get("canvas", {}) as Dictionary).is_empty():
		for canvas: Dictionary in canvases():
			if canvases_taken.has(str(canvas.id)):
				continue
			list.append(_interactable(str(canvas.id), "canvas", str(canvas.get("label", "Cloth")), Vector2(float(canvas.x), float(canvas.y)), 30.0, "canvas", str(canvas.id), _first(down, loaded)))
	for spec: Dictionary in data.get("vehicles", []):
		if (spec.get("stops", []) as Array).size() < 2 or not str(unit.get("id", "")) in (spec.get("by", []) as Array):
			continue
		if int(vehicles[str(spec.id)].to) >= 0:
			continue
		list.append(_interactable(str(spec.id), str(spec.get("kind", "vehicle")), str(spec.get("label", "Drive")), vehicle_rect(str(spec.id)).get_center(), 48.0, "drive", str(spec.id), _first(down, loaded)))
	# the gear left about the square (a rifle, a hood and mask), for whoever can use it
	for item: Dictionary in gear():
		if gear_taken.has(str(item.id)):
			continue
		list.append(_interactable(str(item.id), str(item.get("kind", "gear")), str(item.get("label", "Take")), Vector2(float(item.x), float(item.y)), 30.0, "take", str(item.id), _first(down, loaded, _gear_refusal(unit, item))))
	# the creatures in the square, for one who has a gun to drive them off with
	if unit.has("gun"):
		var empty: String = "" if int(unit.get("ammo", 0)) > 0 else "%s is out of ammunition." % str(unit.get("name", ""))
		for beast: Dictionary in creatures_about():
			list.append(_interactable(str(beast.id), "creature", _creature_text("shootLabel", "Shoot"), position_of(beast), 48.0, "shoot", str(beast.id), _first(down, loaded, empty)))

func _interactable(id: String, type: String, label: String, at: Vector2, radius: float, order: String, target: Variant, reason: String) -> Dictionary:
	return {"id": id, "type": type, "label": label, "x": at.x, "y": at.y, "radius": radius, "order": order, "target": target, "enabled": reason == "", "reason": reason}

func _barrier(id: String) -> Dictionary:
	for barrier: Dictionary in data.get("barriers", []):
		if str(barrier.get("id", "")) == id:
			return barrier
	return {}

func in_bush(point: Vector2) -> bool:
	for bush: Dictionary in data.get("bushes", []):
		if rect_of(bush).has_point(point):
			return true
	return false

# ---------------------------------------------------------------------------------------------
# Geometry: movement, sight and path-finding
# ---------------------------------------------------------------------------------------------
## Solid scenery as mission dictionaries (buildings, walls, props, water and the closed cell gate).
func get_obstacles() -> Array:
	var result: Array = data.get("obstacles", []).duplicate()
	if not door_open and data.has("door"):
		result.append(data.door)
	# a gorge is crossed where a rope has been rigged; until then that stretch of it is as sheer as the rest. A passage
	# with a crew (a boat) stays what it was for everyone else: only its crew walk it (see _walk_as)
	for passage: Dictionary in passages():
		if not rigged.has(str(passage.id)) or _crew_only(passage):
			result.append({"id": str(passage.id), "x": passage.x, "y": passage.y, "w": passage.w, "h": passage.h,
				"kind": str(passage.get("closed", "gorge")), "passage": str(passage.id)})
	return result

## Things that stop feet but not eyes: the wire fence (minus its span once cut) and the tower's legs.
func get_barriers() -> Array:
	var result: Array = []
	for barrier: Dictionary in data.get("barriers", []):
		if fence_cut and bool(barrier.get("cuttable", false)):
			continue
		result.append(barrier)
	return result

func _ensure_geometry() -> void:
	if not _geometry_dirty:
		return
	_geometry_dirty = false
	var crew_on: bool = _crew_on
	var move: Array[Rect2] = []
	var crew_move: Array[Rect2] = []
	_reach_rects = []
	_sight_rects = []
	_tall_rects = []
	for obstacle: Dictionary in get_obstacles():
		var rect: Rect2 = rect_of(obstacle)
		var kind: String = obstacle.get("kind", "wall")
		move.append(rect)
		# a crew passage once rigged (the boat in the water) is open water for its crew alone
		if not (obstacle.has("passage") and rigged.has(str(obstacle.passage)) and _crew_only(passage_by_id(str(obstacle.passage)))):
			crew_move.append(rect)
		# water and a gorge stop feet, not eyes (nor a hand reaching across a gorge's lip)
		if not kind in ["water", "gorge"]:
			_reach_rects.append(rect)
			# posts and open frames (a lamp post, a scaffold) are in the way but hide nobody
			if not bool(obstacle.get("see_through", false)):
				_sight_rects.append(rect)
		if kind == "building":
			_tall_rects.append(rect)
	# roofs (data "roofs": [x, y, w, h]): a hall built of separate walls still has a roof, and a man up on a tower
	# sees neither into it nor through it
	for roof: Array in data.get("roofs", []):
		_tall_rects.append(Rect2(float(roof[0]), float(roof[1]), float(roof[2]), float(roof[3])))
	for barrier: Dictionary in get_barriers():
		move.append(rect_of(barrier))
		crew_move.append(rect_of(barrier))
		_reach_rects.append(rect_of(barrier))
	_geo_base = _ground(move)
	_geo_crew = _geo_base if crew_move.size() == move.size() else _ground(crew_move)
	_use_ground(_geo_crew if crew_on else _geo_base)
	_beast_dirty = true

## The walking ground for a set of solid rectangles: {move, body (grown by BODY_RADIUS), grid, region}. A cell is
## blocked when its centre is too near the edge of the map or inside a grown rectangle (the same test as _blocked).
func _ground(move: Array[Rect2], grow: float = BODY_RADIUS) -> Dictionary:
	var body: Array[Rect2] = []
	for rect: Rect2 in move:
		body.append(rect.grow(grow))
	var grid: PackedByteArray = PackedByteArray()
	grid.resize(_cols * _rows)
	grid.fill(0)
	for index: int in range(grid.size()):
		var c: Vector2 = _centers[index]
		if c.x < BODY_RADIUS or c.y < BODY_RADIUS or c.x > _width - BODY_RADIUS or c.y > _height - BODY_RADIUS:
			grid[index] = 1
	# each rectangle marks the cells whose centres it holds (a few cells either way are tested, the rest skipped)
	for rect: Rect2 in body:
		var x0: int = maxi(0, floori(rect.position.x / _cell - 0.5) - 1)
		var x1: int = mini(_cols - 1, ceili(rect.end.x / _cell) + 1)
		var y0: int = maxi(0, floori(rect.position.y / _cell - 0.5) - 1)
		var y1: int = mini(_rows - 1, ceili(rect.end.y / _cell) + 1)
		for cy: int in range(y0, y1 + 1):
			for cx: int in range(x0, x1 + 1):
				var index: int = cy * _cols + cx
				if grid[index] == 0 and rect.has_point(_centers[index]):
					grid[index] = 1
	return {"move": move, "body": body, "grid": grid, "region": _regions_of(grid)}

func _use_ground(ground: Dictionary) -> void:
	_move_rects = ground.move
	_body_rects = ground.body
	_grid = ground.grid
	_region = ground.region

## Path-finding from here on as everyone walks (false) or as a crew passage's crew walk (true); returns which it
## was, to be put back. Without crew passages in the mission it changes nothing.
func _walk_as(crew: bool) -> bool:
	var before: bool = _crew_on
	if not _has_crew:
		return before
	_ensure_geometry()
	if crew != _crew_on:
		_crew_on = crew
		_use_ground(_geo_crew if crew else _geo_base)
	return before

## A passage only some may use (data passages[].crew): the boat, rowed by Biguá alone.
static func _crew_only(passage: Dictionary) -> bool:
	return not (passage.get("crew", []) as Array).is_empty()

## True when this operative (an id) is the crew of some passage: he walks its water once it is open.
func _crew_for(id: String) -> bool:
	if not _has_crew or id == "":
		return false
	for passage: Dictionary in passages():
		if id in (passage.get("crew", []) as Array):
			return true
	return false

## True when a passage is open to this actor: rigged, and (a crew passage) he is its crew, or the one its crew is
## escorting.
func passage_open_to(passage: Dictionary, actor: Dictionary) -> bool:
	if not rigged.has(str(passage.get("id", ""))):
		return false
	if not _crew_only(passage):
		return true
	var id: String = str(actor.get("id", ""))
	if actor.has("follow_id") and not actor.has("stance"):
		id = str(actor.get("follow_id", ""))
	return id in (passage.get("crew", []) as Array)

## Flood-fills the walkable cells so that find_path can tell at once when two places are not connected
## (the yard behind the locked gate, the far side of the wire) instead of searching the whole map.
func _regions_of(grid: PackedByteArray) -> PackedInt32Array:
	var region: PackedInt32Array = PackedInt32Array()
	region.resize(grid.size())
	region.fill(0)
	var label: int = 0
	var stack: Array[int] = []
	for origin: int in range(grid.size()):
		if grid[origin] == 1 or region[origin] != 0:
			continue
		label += 1
		region[origin] = label
		stack.append(origin)
		while not stack.is_empty():
			var current: int = stack.pop_back()
			var cx: int = current % _cols
			var cy: int = floori(float(current) / float(_cols))
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					var nx: int = cx + dx
					var ny: int = cy + dy
					if (dx == 0 and dy == 0) or nx < 0 or nx >= _cols or ny < 0 or ny >= _rows:
						continue
					var neighbor: int = ny * _cols + nx
					if grid[neighbor] == 1 or region[neighbor] != 0:
						continue
					# The same rule as the search: no cutting a corner between two blocked cells.
					if dx != 0 and dy != 0 and (grid[cy * _cols + nx] == 1 or grid[ny * _cols + cx] == 1):
						continue
					region[neighbor] = label
					stack.append(neighbor)
	return region

func is_blocked(point: Vector2, margin: float = BODY_RADIUS) -> bool:
	_ensure_geometry()
	return _blocked(point, margin)

func _blocked(point: Vector2, margin: float) -> bool:
	if not point.is_finite():
		return true
	if point.x < margin or point.y < margin or point.x > _width - margin or point.y > _height - margin:
		return true
	if margin == BODY_RADIUS:
		for rect: Rect2 in _body_rects:
			if rect.has_point(point):
				return true
		return false
	for rect: Rect2 in _move_rects:
		if rect.grow(margin).has_point(point):
			return true
	return false

## Ground-level sight between two points: buildings, walls, props and the closed gate block it; wire and water do not.
func line_of_sight(from: Vector2, to: Vector2) -> bool:
	return _sight_clear(from, to, false)

func sight_endpoint(from: Vector2, to: Vector2) -> Vector2:
	return _sight_end(from, to, false)

## Sight from a particular guard: the elevated tower sentry sees over everything except buildings.
func sight_clear_for(guard: Dictionary, to: Vector2) -> bool:
	return _sight_clear(position_of(guard), to, float(guard.get("elevation", 0.0)) > 0.0)

## Where that guard's line of sight toward `to` stops; use it to draw his cone truthfully.
func sight_endpoint_for(guard: Dictionary, to: Vector2) -> Vector2:
	return _sight_end(position_of(guard), to, float(guard.get("elevation", 0.0)) > 0.0)

func _sight_clear(from: Vector2, to: Vector2, elevated: bool) -> bool:
	_ensure_geometry()
	for rect: Rect2 in (_tall_rects if elevated else _sight_rects):
		# A man posted up on a roof looks out over the building he stands on.
		if elevated and rect.has_point(from):
			continue
		if segment_rect_fraction(from, to, rect) < 0.999:
			return false
	return true

func _sight_end(from: Vector2, to: Vector2, elevated: bool) -> Vector2:
	_ensure_geometry()
	var fraction: float = 1.0
	for rect: Rect2 in (_tall_rects if elevated else _sight_rects):
		if elevated and rect.has_point(from):
			continue
		fraction = minf(fraction, segment_rect_fraction(from, to, rect))
	return from.lerp(to, fraction)

## Nothing solid (wire included) between two points an arm's length apart.
func _reach_clear(from: Vector2, to: Vector2) -> bool:
	_ensure_geometry()
	for rect: Rect2 in _reach_rects:
		if segment_rect_fraction(from, to, rect) < 0.999:
			return false
	return true

func _clear_segment(from: Vector2, to: Vector2) -> bool:
	for rect: Rect2 in _body_rects:
		if segment_rect_fraction(from, to, rect) < 0.999:
			return false
	return not _blocked(to, BODY_RADIUS)

static func segment_rect_fraction(from: Vector2, to: Vector2, rect: Rect2) -> float:
	var low: float = 0.0
	var high: float = 1.0
	var direction: Vector2 = to - from
	for axis: int in range(2):
		if absf(direction[axis]) < 0.000001:
			if from[axis] < rect.position[axis] or from[axis] > rect.end[axis]:
				return INF
		else:
			var first: float = (rect.position[axis] - from[axis]) / direction[axis]
			var last: float = (rect.end[axis] - from[axis]) / direction[axis]
			low = maxf(low, minf(first, last))
			high = minf(high, maxf(first, last))
			if low > high:
				return INF
	return low

## A* over the 32-unit grid, then string-pulled. Returns [] when `to` is blocked or unreachable.
## The blocked grid is cached and the search reuses its buffers, so a call allocates only the result.
func find_path(from: Vector2, to: Vector2) -> Array:
	_ensure_geometry()
	if _blocked(to, BODY_RADIUS):
		return []
	if _clear_segment(from, to):
		return [to]
	var first: int = _nearest_cell(from)
	var last: int = _nearest_cell(to)
	if first < 0 or last < 0 or _region[first] != _region[last]:
		return []
	_search += 1
	path_searches += 1
	var last_center: Vector2 = _centers[last]
	var open: Array[int] = [first]
	_seen[first] = _search
	_cost[first] = 0.0
	_score[first] = _centers[first].distance_to(last_center)
	var found: bool = false
	while not open.is_empty():
		var best_index: int = 0
		var best_score: float = _score[open[0]]
		for index: int in range(1, open.size()):
			if _score[open[index]] < best_score:
				best_index = index
				best_score = _score[open[index]]
		var current: int = open[best_index]
		open.remove_at(best_index)
		if current == last:
			found = true
			break
		_closed[current] = _search
		var cx: int = current % _cols
		var cy: int = floori(float(current) / float(_cols))
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nx: int = cx + dx
				var ny: int = cy + dy
				if nx < 0 or nx >= _cols or ny < 0 or ny >= _rows:
					continue
				var neighbor: int = ny * _cols + nx
				if _closed[neighbor] == _search or _grid[neighbor] == 1:
					continue
				if dx != 0 and dy != 0 and (_grid[cy * _cols + nx] == 1 or _grid[ny * _cols + cx] == 1):
					continue
				var candidate: float = _cost[current] + _cell * (1.41421356 if dx != 0 and dy != 0 else 1.0)
				var fresh: bool = _seen[neighbor] != _search
				if fresh or candidate < _cost[neighbor]:
					_parent[neighbor] = current
					_cost[neighbor] = candidate
					_score[neighbor] = candidate + _centers[neighbor].distance_to(last_center)
					if fresh:
						_seen[neighbor] = _search
						open.append(neighbor)
	if not found:
		return []
	var raw: Array[Vector2] = [to]
	var cursor_cell: int = last
	while cursor_cell != first:
		raw.push_front(_centers[cursor_cell])
		cursor_cell = _parent[cursor_cell]
	raw.push_front(_centers[first])
	var result: Array = []
	var cursor: Vector2 = from
	var index: int = 0
	while index < raw.size():
		var furthest: int = index
		for probe: int in range(index, raw.size()):
			if _clear_segment(cursor, raw[probe]):
				furthest = probe
			else:
				break
		result.append(raw[furthest])
		cursor = raw[furthest]
		index = furthest + 1
	return result

func _nearest_cell(point: Vector2) -> int:
	var cx: int = int(floor(point.x / _cell))
	var cy: int = int(floor(point.y / _cell))
	var best: int = -1
	var distance: float = INF
	for radius: int in range(0, 5):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				var nx: int = cx + dx
				var ny: int = cy + dy
				if nx < 0 or nx >= _cols or ny < 0 or ny >= _rows:
					continue
				var cell: int = ny * _cols + nx
				if _grid[cell] == 1:
					continue
				var center: Vector2 = _centers[cell]
				var candidate: float = center.distance_squared_to(point)
				if candidate < distance and _clear_segment(point, center):
					best = cell
					distance = candidate
		if best >= 0:
			return best
	return -1

## Where a move or a throw aimed at something solid (a roof, the water, the wire, past the edge of the map)
## really ends: walking back along the line from `to` toward `from`, the first spot open by `margin` and,
## when `need_route`, one he can walk to. Then it is pushed forward again as far as a straight walk allows,
## so he stops right at the wall. A non-finite vector when there is no such spot.
func _back_along(from: Vector2, to: Vector2, margin: float, need_route: bool) -> Vector2:
	_ensure_geometry()
	var none := Vector2(INF, INF)
	if not from.is_finite() or not to.is_finite():
		return none
	var span: float = from.distance_to(to)
	if span < 0.001:
		return none
	var home: int = -1
	if need_route:
		var first_cell: int = _nearest_cell(from)
		if first_cell < 0:
			return none
		home = _region[first_cell]
	var steps: int = maxi(1, ceili(span / BACK_STEP))
	for step: int in range(1, steps + 1):
		var point: Vector2 = to.lerp(from, float(step) / float(steps))
		if _blocked(point, margin):
			continue
		if not need_route:
			return point
		# The cheap test first: the cell it is in must be open and joined to where he stands.
		var cell: int = _cell_index(point)
		if cell < 0 or _grid[cell] == 1 or _region[cell] != home or find_path(from, point).is_empty():
			continue
		var forward: Vector2 = (to - point).normalized()
		var reach: Vector2 = point
		var room: float = minf(point.distance_to(to), _cell * 2.0)
		for push: int in range(1, int(room / 4.0) + 1):
			var further: Vector2 = point + forward * 4.0 * float(push)
			if _blocked(further, margin) or not _clear_segment(reach, further):
				break
			reach = further
		return reach
	return none

func _cell_index(point: Vector2) -> int:
	var cx: int = int(floor(point.x / _cell))
	var cy: int = int(floor(point.y / _cell))
	if cx < 0 or cy < 0 or cx >= _cols or cy >= _rows:
		return -1
	return cy * _cols + cx

func _cell_center(index: int) -> Vector2:
	return Vector2((float(index % _cols) + 0.5) * _cell, (floorf(float(index) / float(_cols)) + 0.5) * _cell)

static func position_of(actor: Dictionary) -> Vector2:
	return Vector2(float(actor.get("x", 0.0)), float(actor.get("y", 0.0)))

static func rect_of(item: Dictionary) -> Rect2:
	return Rect2(float(item.x), float(item.y), float(item.w), float(item.h))
