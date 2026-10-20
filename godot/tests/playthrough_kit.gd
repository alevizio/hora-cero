extends RefCounted
## A small script player for whole-mission tests: gives orders the way the HUD does (select, then
## perform), steps the simulation in fixed 0.05 s ticks and keeps a log of what happened.
## Used by tests/solutions.gd and tests/playthroughs.gd; handy for trying a plan by hand too
## (run a playthrough with "verbose", or call scan() to see how wide a timing window is).

const Simulation = preload("res://scripts/simulation.gd")
const STEP: float = 0.05

var game: RefCounted
var title: String = ""
var verbose: bool = false
## Every event of the run in order (the kit drains game.events as the 3D world does).
var history: Array[Dictionary] = []
## Orders that were refused and waits that timed out; a clean run leaves this empty.
var problems: Array[String] = []
## Highest suspicion any guard reached since the last mark(), and who it was.
var peak: float = 0.0
var peak_guard: String = ""
var run_peak: float = 0.0
## Checks made by a solution script on its way (see check()).
var checks: int = 0
var failed: Array[String] = []
## Called after every tick; a test that drives the real 3D scene refreshes its visuals here.
var after_step: Callable = Callable()
## False when the kit drives somebody else's simulation: the events are then left for that owner
## to drain (the 3D world does), who may feed them to record().
var drains_events: bool = true
## Way-points still to be walked by operatives sent off with follow(), by operative id.
var trails: Dictionary = {}

## With `existing` the kit drives that simulation (already started) instead of making its own.
func _init(mission: Dictionary, run_title: String = "", chatty: bool = false, existing: RefCounted = null) -> void:
	title = run_title
	verbose = chatty
	game = existing if existing != null else Simulation.new(mission)
	drains_events = existing == null
	if game.phase != "playing":
		game.start()
	if game.paused:
		game.toggle_pause()
	_drain()

func unit(id: String) -> Dictionary:
	return game.unit_by_id(id)

func guard(id: String) -> Dictionary:
	return game.guard_by_id(id)

func at(id: String) -> Vector2:
	if id == "asset":
		return game.position_of(game.prisoner)
	var actor: Dictionary = game.unit_by_id(id)
	return game.position_of(actor if not actor.is_empty() else game.guard_by_id(id))

func note(text: String) -> void:
	if verbose:
		print("  [%s %6.2f] %s" % [title, game.time, text])

func problem(text: String) -> void:
	problems.append("t=%.2f %s" % [game.time, text])
	note("PROBLEM: " + text)

## Records a fact the run is supposed to establish; the caller turns `failed` into test failures.
func check(condition: bool, explanation: String) -> void:
	checks += 1
	if not condition:
		failed.append("t=%.2f %s" % [game.time, explanation])
		note("CHECK FAILED: " + explanation)

func mark() -> void:
	peak = 0.0
	peak_guard = ""

func step() -> void:
	game.update(STEP)
	for watcher: Dictionary in game.guards:
		if float(watcher.suspicion) > peak and not watcher.state in game.DOWN_STATES:
			peak = float(watcher.suspicion)
			peak_guard = "%s sees %s" % [watcher.id, watcher.seen_id]
	run_peak = maxf(run_peak, peak)
	_drain()
	for id: String in trails.keys():
		if idle(id):
			var point: Vector2 = trails[id].pop_front()
			if trails[id].is_empty():
				trails.erase(id)
			order(id, "move", point)
	if after_step.is_valid():
		after_step.call()

func _drain() -> void:
	if not drains_events:
		return
	for event: Dictionary in game.events:
		record(event)
	game.events.clear()

func record(event: Dictionary) -> void:
	history.append(event)
	if verbose and not event.type in ["checkpoint"]:
		var extra: String = ""
		if event.type == "spotted":
			extra = "  guard at %s, %s at %s" % [at(str(event.guard)), event.target, at(str(event.target))]
		print("  [%s %6.2f] EVENT %s%s" % [title, game.time, event, extra])

func wait(seconds: float) -> void:
	for tick: int in range(int(round(seconds / STEP))):
		if game.phase != "playing":
			return
		step()

## Steps until `done` is true. Records a problem (and returns false) if `limit` seconds pass or the mission ends first.
func until(done: Callable, limit: float = 60.0, what: String = "") -> bool:
	for tick: int in range(int(limit / STEP)):
		if done.call():
			return true
		if game.phase != "playing":
			break
		step()
	if done.call():
		return true
	problem("gave up waiting%s (phase %s)" % ["" if what == "" else " for " + what, game.phase])
	return false

func idle(id: String) -> bool:
	var actor: Dictionary = unit(id)
	return actor.path.is_empty() and actor.action == "" and actor.queued.is_empty()

## True when the operative has finished everything, including a trail given with follow().
func arrived(id: String) -> bool:
	return idle(id) and not trails.has(id)

## Selects the operative and gives the order, exactly as a HUD would. A refusal is a problem.
func order(id: String, action: String, target: Variant = null) -> bool:
	game.select(id)
	var accepted: bool = game.perform(action, target)
	if not accepted:
		problem("%s refused %s %s: %s" % [id, action, "" if target == null else str(target), game.message])
	else:
		note("%s: %s %s" % [id, action, "" if target == null else str(target)])
	return accepted

func stance(id: String, wanted: String) -> void:
	if unit(id).stance != wanted:
		order(id, "stance")

## Gives the order and waits until the operative has nothing left to do.
func do(id: String, action: String, target: Variant = null, limit: float = 60.0) -> bool:
	if not order(id, action, target):
		return false
	var done: bool = until(func() -> bool: return idle(id), limit, "%s to finish %s" % [id, action])
	note("%s done %s at %s  peak %.2f %s" % [id, action, at(id), peak, peak_guard])
	return done

func go(id: String, x: float, y: float, limit: float = 60.0) -> bool:
	return do(id, "move", Vector2(x, y), limit)

## Walks the operative through a list of points, one move order after another.
func walk(id: String, points: Array, limit: float = 90.0) -> bool:
	for point: Vector2 in points:
		if not go(id, point.x, point.y, limit):
			return false
	return true

## Sends the operative along the points in the background, one move order after another, while the
## script goes on with the other one. idle() stays false until the last point is reached.
func follow(id: String, points: Array) -> void:
	var rest: Array = points.duplicate()
	var first: Vector2 = rest.pop_front()
	if rest.is_empty():
		trails.erase(id)
	else:
		trails[id] = rest
	order(id, "move", first)

## Both operatives get a move order on the same tick; waits for both.
func go_both(first: Vector2, second: Vector2, limit: float = 60.0) -> bool:
	order("wren", "move", first)
	order("rook", "move", second)
	return until(func() -> bool: return idle("wren") and idle("rook"), limit, "both to arrive")

func events_of(type: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: Dictionary in history:
		if event.type == type:
			found.append(event)
	return found

func heading_of(id: String) -> float:
	return rad_to_deg(float(guard(id).angle))

## True when the guard is within `radius` of the point.
func guard_near(id: String, x: float, y: float, radius: float = 12.0) -> bool:
	return at(id).distance_to(Vector2(x, y)) <= radius

## True when nobody able would see a person at the point (standing if `exposed`).
func unseen_at(x: float, y: float, exposed: bool) -> bool:
	return game.threats_at(Vector2(x, y), exposed).is_empty()

## Remembers this moment so a plan can be tried again from it (see rewind).
func save() -> Dictionary:
	return {"state": game.snapshot(), "history": history.size(), "problems": problems.size(), "run_peak": run_peak, "trails": trails.duplicate(true)}

func rewind(saved: Dictionary) -> void:
	game.restore(saved.state)
	trails = saved.trails.duplicate(true)
	history.resize(int(saved.history))
	problems.resize(int(saved.problems))
	run_peak = float(saved.run_peak)
	mark()

## Tuning aid: tries `plan` from this moment after waiting 0, step, 2 x step ... seconds, rewinding each
## time, and returns a line such as "0:ok(0.2) 2:g3@940,605 4:ok(0.0)" (peak suspicion, or who raised
## the alarm and where the victim stood). The run itself is left where it was.
func scan(span: float, pause: float, plan: Callable) -> String:
	var saved: Dictionary = save()
	var chatty: bool = verbose
	verbose = false
	var line: String = ""
	var delay: float = 0.0
	while delay <= span:
		rewind(saved)
		wait(delay)
		mark()
		var alarms: int = int(game.stats.alarms)
		var spotted_before: int = events_of("spotted").size()
		plan.call()
		if int(game.stats.alarms) > alarms or game.phase == "lost":
			var seen: Array[Dictionary] = events_of("spotted")
			if seen.size() > spotted_before:
				var sighting: Dictionary = seen[spotted_before]
				line += "%d:%s@%d,%d " % [int(delay), sighting.guard, int(at(str(sighting.target)).x), int(at(str(sighting.target)).y)]
			else:
				line += "%d:alarm " % int(delay)
		elif problems.size() > int(saved.problems):
			line += "%d:stuck " % int(delay)
		else:
			line += "%d:ok(%.1f) " % [int(delay), peak]
		delay += pause
	rewind(saved)
	verbose = chatty
	return line

func badges() -> Array[String]:
	var earned: Array[String] = []
	for badge: Dictionary in game.result_badges():
		if bool(badge.earned):
			earned.append(str(badge.id))
	return earned

func summary() -> String:
	var seconds: int = int(game.time)
	return "%s: %s in %d:%02d (%.1f s)  alarms %d  kills %d  binds %d  shots %d  pebbles %d  bodies found %d  badges %s" % [
		title, game.phase, floori(float(seconds) / 60.0), seconds % 60, game.time, int(game.stats.alarms), int(game.stats.kills), int(game.stats.binds),
		int(game.stats.shots), int(game.stats.distractions), int(game.stats.bodies_found), str(badges())]
