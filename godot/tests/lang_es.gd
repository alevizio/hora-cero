extends SceneTree
## The game in Spanish (scripts/lang.gd, locale/es.json): lookups of every kind, the level data translated without
## touching its ids, the catalog's placeholders and its Rioplatense, and every answer to every order in both levels.
## (Whole playthroughs read in Spanish are the playthrough suites' own: plaza_playthrough.gd, riachuelo_playthrough.gd.)
## Run: godot --headless --path godot --script res://tests/lang_es.gd
const Lang = preload("res://scripts/lang.gd")
const Kit = preload("res://tests/playthrough_kit.gd")

var checks: int = 0
var failures: int = 0
## Spanish that is not Argentine: Spain's vosotros ("-áis", "-éis", "os", "vuestro"), tú ("tienes", "agáchate", "toca"),
## and Spain's words ("aquí", "gafas", "coche", "a por"), anywhere in a text. The Rioplatense forms are "ustedes", "tenés",
## "agachate", "tocá", "acá", "anteojos", "auto". Matched on the lower-cased text, with letters (accents and all) as the
## edges of a word: RegEx's \b only knows ASCII, and would never find "aquí".
## (a bare "toca" is also the third person, "la nieve mata a quien toca": only TU_COMMAND, at a sentence start, takes it)
const NOT_RIOPLATENSE := "(?<!\\p{L})(aquí|allí|vosotros|vosotras|vuestr\\p{L}*|os|tú|ti|contigo|\\p{L}+áis|\\p{L}+éis|tienes|puedes|quieres|eres|sabes|vienes|pierdes|mandas|diriges|caminas|serás|podrás|has visto|te ha|te han|agáchate|muévete|escóndelo|escóndete|déjalo|llévalo|úsalos|tócalo|átalo|quítale|suéltalo|acércate|aléjate|ponte|métete|vete|gánala|entretén|mantén|estudia|libera|silencia|selecciona|elige|arrastra|cronometra|continúa|ejecuta|gafas|ordenador|coche|vale|a por)(?!\\p{L})"
## tú's imperatives that are also a third person or a noun ("no te esconde", "deja sin sentido"): only where a sentence starts.
const TU_COMMAND := "(?:^|[.:;!?¡¿]\\s+|\\n)(toca|esconde|estudia|pisa|corta|libera|silencia|abre|selecciona|elige|arrastra|rompe|lucha|sal|espera|entra|trae|haz|pon|tiende|fuerza|cambia|cronometra|respeta|gana|completa|apunta|continúa|ejecuta|vigila|suelta|coloca|mina|derriba|busca|da|deja|lleva|usa|mira)(?!\\p{L})"

func _init() -> void:
	call_deferred("run")

func check(value: bool, label_text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label_text)

func run() -> void:
	_lookups()
	_catalog()
	_data()
	_orders()
	Lang.use("en")
	check(tr("HOW TO PLAY") == "HOW TO PLAY" and Lang.lookup("Handle") == "Handle", "back in English, nothing is changed")
	print("LANG_ES_CHECKS=", checks, " FAILURES=", failures)
	quit(0 if failures == 0 else 1)

func _lookups() -> void:
	Lang.use("es")
	check(Lang.current == "es", "Spanish chosen")
	check(Lang.lookup("HOW TO PLAY") == "CÓMO JUGAR", "an exact key")
	check(tr("SHOOT") == "DISPARAR", "through the TranslationServer, as Labels and plates ask")
	check(Lang.lookup("HANDLE") == "MANIJA", "a label written in capitals on a plate")
	check(Lang.lookup("Hornero takes the controller and coaxes the tram along the rails to the next stop.") == "Hornero agarra la manija y lleva el tranvía despacito por las vías hasta la parada siguiente.", "a sentence made from a data template")
	check(Lang.lookup("Hornero: order cancelled.") == "Hornero: orden cancelada.", "a sentence made from a code template")
	check(Lang.lookup("Hornero: moving.") == "Hornero: en marcha.", "a name, then what he is doing")
	check(Lang.lookup("Hornero: guard knocked out, for 25 seconds. Hide the body before it is found.") == "Hornero: guardia inconsciente durante 25 segundos. Escondé el cuerpo antes de que lo encuentren.", "a name, a template and a second sentence")
	check(Lang.lookup("The noise drew 2 guards. Move while they investigate.") == "El ruido atrajo a 2 guardias. Movete mientras investigan.", "a count with its plural")
	check(Lang.lookup("Distraction ready in 3.5 seconds.") == "Distracción lista en 3.5 segundos.", "a decimal")
	check(Lang.lookup("Biguá closes in: knife. Order queued.") == "Biguá se acerca: cuchillo. Orden en cola.", "a template ending in a sentence does not swallow the next one")
	check(Lang.lookup("Hornero: moving. Order queued.") == "Hornero: en marcha. Orden en cola.", "a name, a remark, then another sentence")
	check(Lang.lookup("CHECKPOINT  ·  BOAT IN THE WATER") == "PUNTO DE CONTROL  ·  BOTE EN EL AGUA", "a template whose argument is in capitals too")
	check(Lang.lookup("DETECTION 40%") == "DETECCIÓN 40%", "a percent sign")
	check(Lang.lookup("00:42") == "00:42" and Lang.lookup("Hornero") == "Hornero", "clocks and names are left alone")
	check(Lang.lookup("The passenger was shot dead by a guard.") == "Un guardia mató al pasajero de un tiro.", "a name with its article inside a sentence: lower case, 'a el' written 'al'")
	check(Lang.lookup("El pasajero was shot dead by a guard.") == "Un guardia mató al pasajero de un tiro.", "the same with the name already in Spanish (the data is translated as it loads)")
	# the recorder (tests list what is still in English): Spanish shown twice, names and filled-in templates are not misses
	Lang.record = true
	Lang.misses.clear()
	for shown: String in ["PUNTO DE CONTROL\nBOTE EN EL AGUA", "Punto de control guardado.", "02  RIACHUELO", "Hornero", "Hornero: en marcha."]:
		Lang.lookup(shown)
	Lang.lookup("A sentence nobody has translated yet.")
	check(Lang.misses.keys() == ["A sentence nobody has translated yet."], "only real English is noted as a miss: %s" % str(Lang.misses.keys()))
	Lang.record = false

## Every entry keeps its placeholders, in order, and says something.
func _catalog() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://locale/es.json"))
	check(parsed is Dictionary and parsed.has("strings"), "the catalog reads")
	var strings: Dictionary = parsed.get("strings", {})
	check(strings.size() > 400, "hundreds of texts (%d)" % strings.size())
	var spec := RegEx.new()
	spec.compile("%[-+ 0-9.]*[sdf%]|\\{left\\}")
	var bad: Array[String] = []
	for en: String in strings:
		var a: PackedStringArray = []
		var b: PackedStringArray = []
		for m: RegExMatch in spec.search_all(en): a.append(m.get_string())
		for m: RegExMatch in spec.search_all(str(strings[en])): b.append(m.get_string())
		if a != b or str(strings[en]).strip_edges() == "": bad.append(en)
	check(bad.is_empty(), "placeholders match in every entry: %s" % str(bad))
	# the whole game in Argentine Spanish, as La Boca always was: voseo for the player, ustedes for a squad
	var not_ours := RegEx.create_from_string(NOT_RIOPLATENSE)
	var tu := RegEx.create_from_string(TU_COMMAND)
	for spain: String in ["Toca a un guardia.", "Esconde el cuerpo antes de que lo encuentren.", "Agáchate.", "Desde aquí no se llega.", "Os vais los tres juntos.", "Iréis por otro camino: cargad las celdas.", "Diriges a los tres.", "Pisa nieve apisonada.", "Se le habían perdido las gafas."]:
		check(not_ours.search(spain.to_lower()) != null or tu.search(spain.to_lower()) != null, "the check knows Spain's Spanish: %s" % spain)
	for ours: String in ["Tocá a un guardia.", "Escondé el cuerpo antes de que lo encuentren.", "Agachate.", "Desde acá no se llega.", "Se van los tres juntos.", "No te esconde.", "La cachiporra deja sin sentido a un guardia.", "Los dos, a la lancha."]:
		check(not_ours.search(ours.to_lower()) == null and tu.search(ours.to_lower()) == null, "and lets Argentine Spanish be: %s" % ours)
	var odd: Array[String] = []
	for en: String in strings:
		var said: String = str(strings[en]).to_lower()
		if not_ours.search(said) != null or tu.search(said) != null: odd.append(str(strings[en]))
	check(odd.is_empty(), "every text speaks Rioplatense, voseo and ustedes (%d texts): %s" % [strings.size(), str(odd)])

## The data is translated as it loads; its ids are not: the Plaza de Mayo, then La Boca.
func _data() -> void:
	Lang.use("es")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/plaza.json"))
	var data: Dictionary = Lang.translate_data(raw)
	check(str(raw.units[0].id) == "hornero" and str(data.units[0].id) == "hornero" and str(data.units[0].name) == "Hornero", "the original is left as it was, ids and names the same")
	check(str(data.objectives[0].id) == str(raw.objectives[0].id) and str(data.objectives[0].text) != str(raw.objectives[0].text), "objectives: text in Spanish, id the same")
	check(data.people == raw.people and data.obstacles == raw.obstacles and data.copy.coach == raw.copy.coach, "the people, the layout and the hint ids left alone")
	check(str(data.history[0].body) != str(raw.history[0].body) and str(data.history[1].title) != str(raw.history[1].title), "history pages in Spanish")
	var miss: Array[String] = []
	_untranslated(data, "", miss)
	check(miss.is_empty(), "every text of the Plaza de Mayo has its Spanish: %s" % str(miss))
	_riachuelo_data()

## La Boca in Rioplatense Spanish: the data as it loads, and the words the loader leaves to the screen (the guards' names
## and refusals, a hint called "tracks", a checkpoint called "boat"), which a Label or tr() translates when shown.
func _riachuelo_data() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/riachuelo.json"))
	var data: Dictionary = Lang.translate_data(raw)
	check(str(data.objectives[0].text) == "Abrí el sótano de La Bruma" and str(data.objectives[0].id) == "cell", "Riachuelo: the objective in voseo, its id the same")
	check(str(data.units[1].role) == "Liniero" and str(data.units[1].name) == "Lechuza" and str(data.units[2].role) == "Canillita", "Lechuza the lineman, Benteveo the canillita")
	check(str(data.units[0].melee.label) == "Manija" and str(data.units[0].cover.tag) == "MOTORMAN" and str(data.units[0].toolsKit) == "sus llaves y herramientas", "Hornero's handle, his tag and his tools")
	check(str(data.prisoner.name) == "El pasajero" and str(data.door.label) == "Sótano" and str(data.passages[1].label) == "Barquilla", "the passenger, the cellar, the gondola")
	check(str(data.history[1].title) == "EL\nTRANSBORDADOR" and (data.history as Array).size() == 6, "six pages of the real story")
	var miss: Array[String] = []
	_untranslated(data, "", miss)
	for guard: Dictionary in raw.guards:
		for field: String in ["title", "spare", "calmRefuse"]:
			if guard.has(field) and Lang.lookup(str(guard[field])) == str(guard[field]): miss.append(str(guard[field]))
	for words: String in ["hints", "checkpoints", "orderNames"]:
		for text: Variant in (raw.copy[words] as Dictionary).values():
			if Lang.lookup(str(text)) == str(text) and not Lang._keep.has(str(text).to_upper()): miss.append(str(text))
	check(miss.is_empty(), "every text of La Boca has its Spanish: %s" % str(miss))
	# the tag over the passenger: the mission's word (already Spanish) in front of the stock line
	check(Lang.lookup("PASAJERO  ·  IN THE OPEN") == "PASAJERO  ·  AL DESCUBIERTO" and Lang.lookup("PASAJERO  ·  IN COVER") == "PASAJERO  ·  A CUBIERTO", "the passenger's tag in Spanish")
	check(Lang.lookup("Benteveo will bring the passenger up. Keep the way to the river clear.") == "Benteveo va a sacar al pasajero. Mantené libre el camino al río.", "a line made from the passenger's words")
	check(Lang.lookup("CHECKPOINT  ·  BOAT IN THE WATER") == "PUNTO DE CONTROL  ·  BOTE EN EL AGUA", "a checkpoint the loader skips, read off the screen")
	# Rioplatense: ustedes and voseo, never vosotros (Spain's "-áis", "-éis", "vuestro"), tú nor "aquí", as the data loads too
	var texts: Array[String] = []
	_texts(raw, "", texts)
	var peninsular := RegEx.create_from_string(NOT_RIOPLATENSE)
	var tu := RegEx.create_from_string(TU_COMMAND)
	var odd: Array[String] = []
	for text: String in texts:
		var said: String = Lang.lookup(text).to_lower()
		if peninsular.search(said) != null or tu.search(said) != null: odd.append(Lang.lookup(text))
	check(texts.size() > 100 and odd.is_empty(), "La Boca speaks Rioplatense (%d texts): %s" % [texts.size(), str(odd)])

func _texts(value: Variant, key: String, out: Array[String]) -> void:
	if key in Lang.DATA_IDS or key in ["obstacles", "barriers", "bushes", "tracks", "ambience", "camera", "floodlit", "bocaWorld"]:
		return
	if value is Dictionary:
		for k: Variant in value: _texts(value[k], str(k), out)
	elif value is Array:
		for v: Variant in value: _texts(v, key, out)
	elif value is String and Lang._wordy(value):
		out.append(value)

func _untranslated(value: Variant, key: String, out: Array[String]) -> void:
	if key in Lang.DATA_IDS or key in Lang.DATA_SKIP:
		return
	if value is Dictionary:
		for k: Variant in value: _untranslated(value[k], str(k), out)
	elif value is Array:
		for v: Variant in value: _untranslated(v, key, out)
	elif value is String and Lang._wordy(value) and not Lang._keep.has(value.to_upper()) and Lang._exact.find_key(value) == null:
		out.append(value)

## Every order each operative can be given, paused and running, aimed at the nearest guard, a spot beside him or
## each charge site: what the game answers (accepted or refused) reads in Spanish, every piece of it.
func _orders() -> void:
	Lang.use("es")
	Lang.record = true
	Lang.misses.clear()
	var seen: Dictionary = {}
	for file: String in ["res://data/plaza.json", "res://data/riachuelo.json"]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file))
		for paused: bool in [true, false]:
			var k: RefCounted = Kit.new(data, "orders")
			var game: RefCounted = k.game
			for unit: Dictionary in game.units:
				var id: String = str(unit.id)
				var here := Vector2(float(unit.x), float(unit.y))
				var nearest: String = ""
				var best: float = INF
				for guard: Dictionary in game.guards:
					var d: float = Vector2(float(guard.x), float(guard.y)).distance_to(here)
					if d < best:
						best = d
						nearest = str(guard.id)
				var sites: Array = [""]
				for site: Dictionary in game.charge_sites(): sites.append(str(site.id))
				var tries: Array = [["stance", null], ["takedown", nearest], ["shoot", nearest], ["distract", here + Vector2(90, 0)],
					["trap", null], ["trap_pickup", ""], ["cut", null], ["sabotage", null], ["unlock", null], ["rescue", null],
					["extract", null], ["chat", nearest], ["pickup", nearest], ["drop", null], ["interact", null], ["move", here + Vector2(60, 0)]]
				for site: String in sites: tries.append(["plant", site])
				# the ways across that somebody opens (La Boca: the ladder, the gondola, the boat), and the people in the street
				for passage: Dictionary in game.passages(): tries.append(["rig", str(passage.id)])
				for guard: Dictionary in game.guards:
					if bool(guard.get("civilian", false)): tries.append(["takedown", str(guard.id)])
				for t: Array in tries:
					game.select(id)
					if paused != bool(game.paused): game.toggle_pause()
					game.message = ""
					game.perform(str(t[0]), t[1])
					seen[str(game.message)] = true
					game.select(id)
					game.perform("cancel")
					seen[str(game.message)] = true
	var english: Array[String] = []
	for message: String in seen:
		if message != "" and Lang._wordy(message) and Lang.lookup(message) == message: english.append(message)
	check(seen.size() > 30, "plenty of answers to orders (%d)" % seen.size())
	check(english.is_empty() and Lang.misses.is_empty(), "every answer to an order in Spanish: %s %s" % [str(english), str(Lang.misses.keys())])
	Lang.record = false
