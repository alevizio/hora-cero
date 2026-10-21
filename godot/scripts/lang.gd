extends RefCounted
## The game in two languages. English is the source: every text in the code and in the mission data is written in
## English and is its own key, and locale/<lang>.json maps it to the other language (only Spanish so far).
##
## How a text gets translated:
##  - Mission data is translated once, as it is loaded (translate_data): every text field, not ids or signage.
##  - Everything on screen goes through the TranslationServer: Labels and Buttons do that by themselves, the
##    custom-drawn plates and painted panels call tr(). The server asks lookup() below.
##  - lookup() takes a text as it was made: an exact key; a sentence put together from a template
##    ("%s: order cancelled.") and its arguments, matched back to the template and rebuilt in Spanish with the
##    arguments translated in turn; a text in capitals (plates write their labels that way); or several
##    sentences run together, one by one. Whatever it cannot place is shown as it is (and, with `record` on,
##    noted in `misses` so a test can list what still needs translating).
## The choice is kept in the progress file (section "settings", key "language"); the first time, the device's
## language decides. Changing it reloads the scene, so the mission data is read again in the new language.

const LANGS: Array[String] = ["en", "es"]
const NAMES: Dictionary = {"en": "ENGLISH", "es": "ESPAÑOL"}
const SHORT: Dictionary = {"en": "EN", "es": "ES"}
const CATALOG_DIR: String = "res://locale/"
const SECTION: String = "settings"
const KEY: String = "language"
## Mission-data fields that hold ids, codes or names, never text to translate.
const DATA_IDS: Array[String] = ["id", "kind", "look", "type", "icon", "glyph", "thing", "cue", "noise", "style", "sound", "theme",
	"worldName", "progressKey", "color", "material", "_source", "water", "hum", "objective", "by", "who", "unplanted",
	"coach", "coachOrder", "fig", "span", "at", "path", "number", "tab", "x", "y", "stance", "ability", "boat", "prop", "officers",
	"seenBy", "closed", "crew", "group", "dark", "vehicle", "art", "rule", "mode", "from"]
## Whole branches of the data that are layout or signage in the world (painted on walls and signs as they were).
const DATA_SKIP: Array[String] = ["obstacles", "barriers", "bushes", "harbour", "tracks", "ambience", "guards", "fence", "camera", "floodlit",
	"plazaWorld", "people"]

static var current: String = "en"
## Debug and tests: texts asked for in a language that had no translation for them.
static var record: bool = false
static var misses: Dictionary = {}

static var _booted: bool = false
static var _exact: Dictionary = {}
static var _upper: Dictionary = {}
## [RegEx, the translated template, the kind of each placeholder ("s", "d", "f")], longest English first.
static var _templates: Array = []
static var _memo: Dictionary = {}
## For `record`: texts already in the language (the catalog's own, what lookup made, words both share), so a text
## asked for twice (data translated as it loaded, then shown by a Label) is not taken for a miss.
static var _values: Dictionary = {}
static var _produced: Dictionary = {}
static var _keep: Dictionary = {}
static var _value_patterns: Array[RegEx] = []
static var _server_translation: Translation
static var _ARTICLE: RegEx = RegEx.create_from_string("^(El|La|Los|Las|Un|Una) ")

## Once per run: the saved choice, else `default_lang` (the game's own: Missions.start_lang(), Spanish), else the
## device's language. Tests (run with --script) stay in English unless HORACERO_LANG says otherwise.
static func boot(progress_path: String = "user://horacero_progress.cfg", default_lang: String = "") -> void:
	if _booted:
		return
	_booted = true
	var lang: String = "en"
	var forced: String = OS.get_environment("HORACERO_LANG")
	if forced in LANGS:
		lang = forced
	elif not "--script" in OS.get_cmdline_args():
		lang = starting(progress_path, default_lang)
	use(lang)

## The language a run starts in: the choice kept in the progress file, else `default_lang`, else the device's.
static func starting(progress_path: String, default_lang: String = "") -> String:
	var saved := ConfigFile.new()
	if saved.load(progress_path) == OK and str(saved.get_value(SECTION, KEY, "")) in LANGS:
		return str(saved.get_value(SECTION, KEY, ""))
	if default_lang in LANGS:
		return default_lang
	return "es" if OS.get_locale_language() == "es" else "en"

## Switches the language for everything from now on (the caller reloads what was already made).
static func use(lang: String) -> void:
	_booted = true
	current = lang if lang in LANGS else "en"
	_memo.clear()
	_exact.clear()
	_upper.clear()
	_templates.clear()
	_values.clear()
	_produced.clear()
	_keep.clear()
	_value_patterns.clear()
	if current != "en":
		_load_catalog(current)
	if _server_translation == null:
		var bridge := Bridge.new()
		bridge.lookup = lookup
		_server_translation = bridge
		# the bridge is a script: it has to leave the server before the engine shuts its scripting down
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.root.tree_exiting.connect(_release, CONNECT_ONE_SHOT)
	else:
		TranslationServer.remove_translation(_server_translation)
	# registered for the language in use, so the server asks it for every text on screen
	_server_translation.locale = current
	TranslationServer.add_translation(_server_translation)
	TranslationServer.set_locale(current)

static func _release() -> void:
	if _server_translation != null:
		TranslationServer.remove_translation(_server_translation)
		(_server_translation as Bridge).lookup = Callable()
		_server_translation = null

## Remembers the choice in the progress file and switches to it.
static func choose(lang: String, progress_path: String) -> void:
	var saved := ConfigFile.new()
	saved.load(progress_path)
	saved.set_value(SECTION, KEY, lang)
	saved.save(progress_path)
	use(lang)

static func _load_catalog(lang: String) -> void:
	var text: String = FileAccess.get_file_as_string(CATALOG_DIR + lang + ".json")
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("Language catalog %s could not be read" % lang)
		return
	var strings: Dictionary = parsed.get("strings", {})
	# names and words the same in both languages (Hornero, Cabildo, PLAN)
	for word: Variant in parsed.get("keep", []):
		_keep[str(word).to_upper()] = true
	var templates: Array = []
	for en: String in strings:
		var to: String = str(strings[en])
		if to == "":
			continue
		_exact[en] = to
		_values[to.strip_edges()] = true
		_values[to.strip_edges().to_upper()] = true
		var up: String = en.to_upper()
		if up != en and not _upper.has(up):
			_upper[up] = to.to_upper()
		# "{left}" is a count the game fills in before showing the line: as a template it is a number
		var tpl_en: String = en.replace("{left}", "%d")
		if tpl_en.contains("%"):
			var made: Array = _template(tpl_en)
			if not made.is_empty():
				var to_tpl: String = to.replace("{left}", "%d")
				templates.append([made[0], to_tpl, made[1], en.length(), _mid_sentence(to_tpl)])
	templates.sort_custom(func(a: Array, b: Array) -> bool: return int(a[3]) > int(b[3]))
	for entry: Array in templates:
		_templates.append([entry[0], entry[1], entry[2], entry[4]])

## For each placeholder of a translated template: does it fall inside a sentence (so "El informante" passed in
## becomes "el informante")?
static func _mid_sentence(tpl: String) -> Array[bool]:
	var out: Array[bool] = []
	var i: int = 0
	while i < tpl.length():
		if tpl[i] == "%" and i + 1 < tpl.length():
			var j: int = i + 1
			while j < tpl.length() and "0123456789.-+ ".contains(tpl[j]):
				j += 1
			if j < tpl.length() and "sdf".contains(tpl[j]):
				var before: String = tpl.left(i).strip_edges(false, true)
				var opens: bool = before == "" or before.ends_with(".") or before.ends_with(":") or before.ends_with("?") or before.ends_with("!")
				out.append(not opens and not tpl.left(i).ends_with("\n"))
				i = j + 1
				continue
			if j < tpl.length() and tpl[j] == "%":
				i = j + 1
				continue
		i += 1
	return out

## A template's English as a pattern: placeholders become groups. Templates with too little fixed text to be
## told apart ("%s." or "%s: %s") are left out.
static func _template(en: String) -> Array:
	var pattern: String = "(?s)^"
	var kinds: Array[String] = []
	var fixed: int = 0
	var i: int = 0
	while i < en.length():
		var c: String = en[i]
		if c == "%":
			var j: int = i + 1
			while j < en.length() and "0123456789.-+ ".contains(en[j]):
				j += 1
			var kind: String = en[j] if j < en.length() else ""
			match kind:
				"%": pattern += "%"
				"s":
					pattern += "(.*?)"
					kinds.append("s")
				"d":
					pattern += "(-?\\d+)"
					kinds.append("d")
				"f":
					pattern += "(-?[\\d.]+)"
					kinds.append("f")
				_:
					pattern += "%"
					i += 1
					continue
			i = j + 1
			continue
		if c.to_lower() != c.to_upper():
			fixed += 1
		pattern += _escape(c)
		i += 1
	if kinds.is_empty() or fixed < 4:
		return []
	var re := RegEx.new()
	if re.compile(pattern + "$") != OK:
		return []
	return [re, kinds]

static func _escape(c: String) -> String:
	return "\\" + c if "\\^$.|?*+()[]{}".contains(c) else c

## The text in the current language (see the top of the file).
static func lookup(text: String) -> String:
	if current == "en" or text == "":
		return text
	if _memo.has(text):
		return _memo[text]
	var out: String = _find(text, 0)
	if _memo.size() > 4000:
		_memo.clear()
	_memo[text] = out
	if not record:
		return out
	if out != text:
		_produced[out] = true
	else:
		_note(text)
	return out

## With `record` on: a text that came out as it went in, and is not already in the language, is a miss.
static func _note(text: String) -> void:
	if record and _wordy(text) and not _exact.has(text) and not _upper.has(text) and not _ours(text):
		misses[text] = true

## Already in the language: a whole text, or every line, item or "Name: " remark of one, that the catalog or lookup
## gave, or a mark, a number or a name kept as it is.
static func _ours(text: String) -> bool:
	text = text.strip_edges()
	if not _wordy(text) or _values.has(text) or _produced.has(text) or _keep.has(text.to_upper()):
		return true
	# lookup adds the closing stop a key may not have ("en marcha" for "moving.")
	if text.ends_with(".") and _values.has(text.left(-1)):
		return true
	# a translated template filled in by the code after tr() ("Punto de control guardado: %s, con %s en el reloj.")
	if _value_patterns.is_empty():
		for to: String in _exact.values():
			if to.contains("%"):
				var made: Array = _template(to.strip_edges())
				if not made.is_empty():
					_value_patterns.append(made[0])
	for re: RegEx in _value_patterns:
		if re.search(text) != null:
			return true
	for sep: String in ["\n", "  ·  ", "  /  ", ", "]:
		if text.contains(sep):
			for part: String in text.split(sep, false):
				if not _ours(part):
					return false
			return true
	# "02  COCKLE": a number in front
	var lead := RegEx.create_from_string("^\\d+\\s+(.+)$")
	var m: RegExMatch = lead.search(text)
	if m != null:
		return _ours(m.get_string(1))
	var colon: int = text.find(": ")
	if colon > 0 and colon < 12 and _a_name(text.substr(0, colon)):
		return _ours(text.substr(colon + 2))
	return false

static func _find(text: String, depth: int) -> String:
	var whole: String = _whole(text, depth)
	if whole != "":
		return whole
	if depth > 3 or not _wordy(text):
		return text
	# several sentences run together ("<a line of the data> Order queued."): the longest run of them that is a key or
	# a template, then the next, a sentence at a time at worst
	var parts: PackedStringArray = _sentences(text)
	if parts.size() > 1:
		var joined: PackedStringArray = []
		var left_alone: PackedStringArray = []
		var i: int = 0
		while i < parts.size():
			var got: String = ""
			var took: int = 1
			for j: int in range(parts.size() - (1 if i == 0 else 0), i + 1, -1):
				got = _whole(" ".join(parts.slice(i, j)), depth + 1)
				if got != "":
					took = j - i
					break
			if got == "":
				got = _find(parts[i], depth + 1)
				if got == parts[i]:
					left_alone.append(got)
			joined.append(got)
			i += took
		if left_alone.size() < joined.size():
			for piece: String in left_alone:
				_note(piece)  # the rest is translated, this sentence is not
			return " ".join(joined)
	# a sentence's closing stop, which the key may not have ("moving." for "moving")
	if text.ends_with(".") and not text.ends_with(".."):
		var bare: String = text.left(-1)
		var got: String = _find(bare, depth + 1)
		if got != bare:
			return got + ("" if got.ends_with(".") else ".")
	# "Wren: moving." - a name, then what he is doing
	var colon: int = text.find(": ")
	if colon > 0 and colon < 12 and _a_name(text.substr(0, colon)):
		var rest: String = _find(text.substr(colon + 2), depth + 1)
		if rest != text.substr(colon + 2):
			return text.substr(0, colon + 2) + rest
	return text

## One word that can be a name in front of a remark ("Wren: moving."), accents and all ("Biguá: moving.").
static func _a_name(word: String) -> bool:
	return word.is_valid_identifier() or _keep.has(word.to_upper())

## A text that is a key (as written, in capitals, or with its first letter lowered: "bind" for "Bind"), or a template
## filled in; "" when it is neither.
static func _whole(text: String, depth: int) -> String:
	if _exact.has(text):
		return _exact[text]
	if _upper.has(text):
		return _upper[text]
	var first: String = text.left(1)
	if first != first.to_upper():
		var raised: String = first.to_upper() + text.substr(1)
		if _exact.has(raised):
			var to: String = _exact[raised]
			return to.left(1).to_lower() + to.substr(1)
	if depth > 3 or not _wordy(text):
		return ""
	for entry: Array in _templates:
		var m: RegExMatch = (entry[0] as RegEx).search(text)
		if m == null:
			continue
		var kinds: Array = entry[2]
		# a template ending in "%s." would swallow the sentences after it ("... the knife. Order queued."): _find
		# takes those texts a run of sentences at a time
		var swallows: bool = false
		for k: int in range(kinds.size()):
			swallows = swallows or (str(kinds[k]) == "s" and _sentences(m.get_string(k + 1)).size() > 1)
		if swallows:
			continue
		var args: Array = []
		var mid: Array = entry[3]
		for k: int in range(kinds.size()):
			var got: String = m.get_string(k + 1)
			match str(kinds[k]):
				"d": args.append(int(got))
				"f": args.append(float(got))
				_:
					var said: String = _find(got, depth + 1)
					if said == got:
						_note(got)  # the line around it is translated, this piece is not
					# an article starts a name in a list or a title, not inside a sentence
					if k < mid.size() and mid[k] and _ARTICLE.search(said) != null:
						said = said.left(1).to_lower() + said.substr(1)
					args.append(said)
		var made: String = str(entry[1]) % args
		# "a el" and "de el" are written "al" and "del"
		return made.replace(" a el ", " al ").replace(" de el ", " del ")
	return ""

static func _sentences(text: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var start: int = 0
	for i: int in range(text.length() - 1):
		if ".!?".contains(text[i]) and text[i + 1] == " ":
			out.append(text.substr(start, i + 1 - start))
			start = i + 2
	if start < text.length():
		out.append(text.substr(start))
	return out

## Has letters worth translating (not a clock, a count or a mark).
static func _wordy(text: String) -> bool:
	var letters: int = 0
	for c: String in text:
		if c.to_lower() != c.to_upper():
			letters += 1
			if letters >= 2:
				return true
	return false

## The mission data with its texts in the current language: a copy, ids and signage left alone.
static func translate_data(data: Dictionary) -> Dictionary:
	if current == "en":
		return data
	return _walk(data, "") as Dictionary

static func _walk(value: Variant, key: String) -> Variant:
	if key in DATA_IDS or key in DATA_SKIP:
		return value
	if value is Dictionary:
		var out: Dictionary = {}
		for k: Variant in value:
			out[k] = _walk(value[k], str(k))
		return out
	if value is Array:
		var out: Array = []
		for item: Variant in value:
			out.append(_walk(item, key))
		return out
	if value is String:
		return lookup(value)
	return value

## The TranslationServer's way in: Labels, Buttons and tr() all end up here.
class Bridge extends Translation:
	var lookup: Callable
	func _get_message(src_message: StringName, _context: StringName) -> StringName:
		return StringName(lookup.call(String(src_message)))
