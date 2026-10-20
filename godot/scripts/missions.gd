extends RefCounted
## Hora Cero's levels, in order: the Plaza de Mayo, then Riachuelo. main.gd plays the current one. The first is open
## from the start; winning it opens the next (unlocked()). The choice is remembered in the progress file.
##
## Hora Cero is an early preview (ADELANTO on its launch screen): two levels, more to come. GAME says how it presents
## itself: "brand", its name on the launch screen, the briefing's letterhead and the questions (brand()); "title", the
## line under the name (title()); "lang", the language it starts in until the player picks one (lang.gd); "langKeys",
## ES / EN on the launch screen itself (front.gd); "soon", "more" and "ask", what it says of the levels still to come
## (the closed tab after its levels, that tab's line and the line after the questions, and its question). Their
## Spanish is in locale/es.json.
##
## Tests and dev tools start with --script and always get the first level unless they set `current` themselves (or
## the HORACERO_MISSION environment variable names one): a saved choice never leaks into a test run.

## "best": the progress section a win writes its time to (hud.gd, from the level's progressKey).
const LEVELS: Array[Dictionary] = [
	{"id": "plaza", "path": "res://data/plaza.json", "number": "01", "tab": "PLAZA DE MAYO", "name": "Plaza de Mayo", "best": "best_plaza"},
	{"id": "riachuelo", "path": "res://data/riachuelo.json", "number": "02", "tab": "RIACHUELO", "name": "Operation Riachuelo", "best": "best_riachuelo"},
]
const GAME: Dictionary = {"brand": "Hora Cero", "title": "Invasión Buenos Aires", "lang": "es", "langKeys": true,
	"soon": "MORE LEVELS", "more": "More levels are on the way, following the comic book.",
	"ask": "WOULD YOU PLAY MORE LEVELS LIKE THESE?", "thanks": ["Agustín Linenberg, for the support."]}
## Where the game keeps its progress, settings and answers.
const PROGRESS: String = "user://horacero_progress.cfg"

static var _dev: int = -1
## The levels on the list for this run of the game.
static var LIST: Array[Dictionary] = LEVELS.duplicate()
## The next file in the dossier, not written yet: a tab that cannot be opened (the levels still to come).
static var SOON: Dictionary = {"number": "+", "tab": str(GAME.soon)}

static var current: String = str(LIST[0].id)
static var _booted: bool = false

## The game's name as its screens say it.
static func brand() -> String:
	return str(GAME.brand)

## The line under the game's name on the launch screen (the one place it is written).
static func title() -> String:
	return str(GAME.title)

## The words for what comes after these levels: the closed tab's line, and the line after the questions.
static func more() -> String:
	return str(GAME.more)

## The game's thanks, on the Settings page under the art credits.
static func thanks() -> Array:
	return (GAME.get("thanks", []) as Array).duplicate()

## The question that asks whether the player wants more.
static func ask() -> String:
	return str(GAME.ask)

## The language the game starts in until the player picks one, and whether the launch screen offers ES / EN.
static func start_lang() -> String:
	return str(GAME.lang)

static func lang_keys() -> bool:
	return bool(GAME.langKeys)

## The last level: winning it is winning the game so far.
static func last() -> String:
	return str(LIST.back().id) if not LIST.is_empty() else ""

static func progress_path() -> String:
	return PROGRESS

## Once per run of the game: picks up the level chosen last time.
static func boot() -> void:
	if _booted:
		return
	_booted = true
	var forced: String = OS.get_environment("HORACERO_MISSION")
	if forced != "" and index_of(forced) >= 0:
		current = forced
		return
	if "--script" in OS.get_cmdline_args():
		return
	var saved := ConfigFile.new()
	if saved.load(progress_path()) == OK:
		var id: String = str(saved.get_value("mission", "current", current))
		if index_of(id) >= 0 and unlocked(id, saved):
			current = id

## Won at least once (its best time is on file)?
static func completed(id: String, progress: ConfigFile) -> bool:
	var i: int = index_of(id)
	if i < 0 or progress == null:
		return false
	return progress.has_section_key(str(LIST[i].best), "time") or bool(progress.get_value("won", id, false))

## Open to play: the first level always; each next one once the one before it has been won (or, for testing, all of
## them in a game the Godot editor started: see dev_unlocked()).
static func unlocked(id: String, progress: ConfigFile) -> bool:
	var i: int = index_of(id)
	if i <= 0:
		return i == 0
	return dev_unlocked() or completed(str(LIST[i - 1].id), progress)

## For testing: when the Godot editor runs the game (a debug build with the editor's debugger attached), every level
## is open without winning the one before. Never in an exported game (those are release builds). Tests and tools
## (--script) keep the locks. HORACERO_UNLOCK=1 or 0 overrides.
static func dev_unlocked() -> bool:
	if _dev < 0:
		_dev = 0
		var forced: String = OS.get_environment("HORACERO_UNLOCK")
		if not OS.is_debug_build():
			_dev = 0
		elif forced != "":
			_dev = 1 if forced == "1" else 0
		elif EngineDebugger.is_active():
			# the editor's Run Project attaches its debugger (Godot 4.7 no longer lists --remote-debug among the
			# command-line arguments, so ask the debugger itself)
			_dev = 1
		else:
			for arg: String in OS.get_cmdline_args():
				if arg.begins_with("--remote-debug"): _dev = 1
	return _dev == 1

## The level that has to be won first to open `id` ("" for the first itself).
static func needs(id: String) -> String:
	var i: int = index_of(id)
	return str(LIST[i - 1].name) if i > 0 else ""

static func index_of(id: String) -> int:
	for i: int in range(LIST.size()):
		if str(LIST[i].id) == id:
			return i
	return -1

static func path() -> String:
	var i: int = index_of(current)
	return str(LIST[maxi(i, 0)].path)

## The level after this one, or "" at the end of the list.
static func next_of(id: String) -> String:
	var i: int = index_of(id)
	return str(LIST[i + 1].id) if i >= 0 and i + 1 < LIST.size() else ""

## Makes `id` the current level; with remember, writes it to the progress file for the next start.
static func choose(id: String, remember: bool = true, file: String = "") -> void:
	if index_of(id) < 0:
		return
	current = id
	_booted = true
	if not remember:
		return
	if file == "": file = progress_path()
	var saved := ConfigFile.new()
	saved.load(file)
	saved.set_value("mission", "current", id)
	saved.save(file)

static func load_data(id: String = "") -> Dictionary:
	var file: String = path() if id == "" else str(LIST[maxi(index_of(id), 0)].path)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	return data if data is Dictionary else {}
