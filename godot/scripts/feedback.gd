extends Node
## The answers to the questions on the launch screen (front.gd, page "feedback"): how much the player enjoyed it,
## whether they would play more levels like these, what confused them or what they would change, and an email to hear
## when more comes. Every answer is optional.
##
## Nothing goes anywhere unless a feedback address is configured: the project setting `hora_cero/feedback/url`
## (empty in this repository), or on the web the page's `window.HORACERO_FEEDBACK_URL`, which
## `tools/web_site_build.py --feedback-url <url>` writes into the page of one build. Without one the questions are not
## offered at all (enabled()). With one, the answers are kept in the progress file (section "feedback") until the
## address has taken them, so answers given offline go out the next time the game is online. They are posted as one
## JSON object (body()); optional request headers come from `hora_cero/feedback/headers` (an array of "Name: value"
## lines) or the page's `window.HORACERO_FEEDBACK_HEADERS` (the same lines in one string, one a line).
##
## Everything here is asynchronous and never stops the game: callers get a signal.

## submit(): {ok: true}, or {ok: false, error} ("offline", "network", "server" and "too often" mean it is kept and
## sent later)
signal feedback_sent(result: Dictionary)

const Missions = preload("res://scripts/missions.gd")
const SECTION: String = "feedback"
const URL_SETTING: String = "hora_cero/feedback/url"
const HEADERS_SETTING: String = "hora_cero/feedback/headers"
const TIMEOUT: float = 10.0
## What the pages offer for each choice; anything else is not sent.
const CHOICES: Dictionary = {"would_play_more": ["yes", "maybe", "no"]}
## False: nothing goes over the network, posts answer {ok: false, error: "offline"}. Runs started with --script
## (tests, tools) are offline unless HORACERO_FEEDBACK_ONLINE=1.
static var online: bool = not ("--script" in OS.get_cmdline_args()) or OS.get_environment("HORACERO_FEEDBACK_ONLINE") == "1"
## Tests and tools: an address in place of the configured one ("" goes by the configuration).
static var address: String = ""

## Whose progress file holds the answers waiting to go: the HUD's (its `progress` and `progress_path`), read afresh
## each time since the HUD reloads it; without one, a file of its own.
var source: Object
var _own := ConfigFile.new()
var _sending: bool = false

var progress: ConfigFile:
	get: return source.get("progress") as ConfigFile if source != null and source.get("progress") != null else _own

func _ready() -> void:
	flush()

## Where the answers go ("" for nowhere): a test's address, the web page's, else the project setting.
static func url() -> String:
	if address != "": return address
	var page: String = str(_page_value("HORACERO_FEEDBACK_URL", ""))
	if page != "": return page
	return str(ProjectSettings.get_setting(URL_SETTING, "")).strip_edges()

## The questions are offered only when the answers have somewhere to go.
static func enabled() -> bool:
	return url().begins_with("https://") or url().begins_with("http://")

static func headers() -> PackedStringArray:
	var out := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	var extra: Variant = _page_value("HORACERO_FEEDBACK_HEADERS", null)
	if extra is String: extra = (extra as String).split("\n", false)
	if extra == null: extra = ProjectSettings.get_setting(HEADERS_SETTING, PackedStringArray())
	if extra is Array or extra is PackedStringArray:
		for line: Variant in extra:
			if str(line).contains(":"): out.append(str(line).strip_edges())
	return out

## A value the web page set on `window` (null off the web, or when the page has none).
static func _page_value(key: String, fallback: Variant) -> Variant:
	if not OS.has_feature("web"): return fallback
	var page: Object = JavaScriptBridge.get_interface("window")
	if page == null: return fallback
	var value: Variant = page.get(key)
	if value == null or value is JavaScriptObject: return fallback
	return value

# --- the device ------------------------------------------------------------------------------------
## A random id made once on this device, sent with the answers so that answering again replaces the earlier answers.
func device() -> String:
	var s: String = str(progress.get_value(SECTION, "device", ""))
	if s.length() < 32:
		s = Crypto.new().generate_random_bytes(24).hex_encode()
		progress.set_value(SECTION, "device", s)
		_save()
	return s

# --- the answers -----------------------------------------------------------------------------------
## Whether to ask after a win: only when the answers have somewhere to go, once the last level is won, unless they
## were answered after a win already (the questions are on the menus all along).
static func due(p: ConfigFile) -> bool:
	if p == null or not enabled(): return false
	return Missions.completed(Missions.last(), p) and not bool(p.get_value(SECTION, "answered_won", false))

## "sent" once the address has the answers, "waiting" while they wait to go, "" before any.
func state() -> String:
	if bool(progress.get_value(SECTION, "sent", false)) and not progress.has_section_key(SECTION, "pending"): return "sent"
	if progress.has_section_key(SECTION, "pending"): return "waiting"
	return ""

## Files the answers (keys: rating 1-5, would_play_more, comment, email; any may be missing) and posts them.
func submit(answers: Dictionary) -> void:
	progress.set_value(SECTION, "pending", answers.duplicate())
	progress.set_value(SECTION, "answered_at", int(Time.get_unix_time_from_system()))
	if Missions.completed(Missions.last(), progress):
		progress.set_value(SECTION, "answered_won", true)
	_save()
	flush()

## Posts the answers waiting, if there are any and somewhere to send them.
func flush() -> void:
	if _sending or not progress.has_section_key(SECTION, "pending"): return
	var answers: Dictionary = progress.get_value(SECTION, "pending", {})
	_sending = true
	_post(body(answers, device(), won()), func(answer: Dictionary) -> void:
		_sending = false
		var error: String = str(answer.get("error", ""))
		# taken, or refused for good: either way it leaves the queue; no address, a network failure, a server error
		# or "too often" keeps it for the next start
		if bool(answer.get("ok", false)) or not error in ["offline", "network", "too often", "server", "nowhere"]:
			progress.erase_section_key(SECTION, "pending")
			progress.set_value(SECTION, "sent", bool(answer.get("ok", false)))
			_save()
		feedback_sent.emit(answer))

## The levels won on this device, in order.
func won() -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in Missions.LIST:
		if Missions.completed(str(entry.id), progress): out.append(str(entry.id))
	return out

## What is posted for a set of answers: only what the pages offer, empty answers as null; the level being played, the
## levels won, the language, the platform and the build.
static func body(answers: Dictionary, device_id: String, won_levels: Array) -> Dictionary:
	var out: Dictionary = {"game": "hora-cero", "device": device_id, "won": won_levels, "level": Missions.current,
		"platform": OS.get_name(), "lang": TranslationServer.get_locale(), "build": build_label()}
	var rating: int = int(answers.get("rating", 0))
	out["rating"] = rating if rating >= 1 and rating <= 5 else null
	for key: String in CHOICES:
		var value: String = str(answers.get(key, ""))
		out[key] = value if value in CHOICES[key] else null
	var comment: String = str(answers.get("comment", "")).strip_edges().left(1000)
	out["comment"] = comment if comment != "" else null
	var email: String = str(answers.get("email", "")).strip_edges()
	out["email"] = email if looks_like_email(email) else null
	return out

## The build named with the answers: on the web the label its page carries (window.HORACERO_BUILD, which
## tools/web_site_build.py writes: "web 2026-10-18 abc1234"), else the project's version, else "dev".
static func build_label() -> String:
	var label: String = str(_page_value("HORACERO_BUILD", ""))
	if label == "": label = str(ProjectSettings.get_setting("application/config/version", ""))
	return (label if label != "" else "dev").left(40)

## Something@something.something, no spaces.
static func looks_like_email(value: String) -> bool:
	var re := RegEx.create_from_string("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")
	return value.length() <= 254 and re.search(value) != null

# --- the wire --------------------------------------------------------------------------------------
func _post(payload: Dictionary, done: Callable) -> void:
	if not enabled():
		done.call.call_deferred({"ok": false, "error": "nowhere"})
		return
	if not online or not is_inside_tree():
		done.call.call_deferred({"ok": false, "error": "offline"})
		return
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, _raw: PackedByteArray) -> void:
		http.queue_free()
		var answer: Dictionary = {"ok": false, "error": "network"}
		if result == HTTPRequest.RESULT_SUCCESS:
			if code >= 200 and code < 300: answer = {"ok": true}
			elif code == 429: answer = {"ok": false, "error": "too often", "code": code}
			elif code >= 500: answer = {"ok": false, "error": "server", "code": code}
			else: answer = {"ok": false, "error": "refused", "code": code}
		done.call(answer))
	if http.request(url(), headers(), HTTPClient.METHOD_POST, JSON.stringify(payload)) != OK:
		http.queue_free()
		done.call.call_deferred({"ok": false, "error": "network"})

func _save() -> void:
	if source != null and str(source.get("progress_path")) != "": progress.save(str(source.get("progress_path")))
