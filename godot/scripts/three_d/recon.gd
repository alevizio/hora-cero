extends Control
## Paper reconnaissance map in a steel map-case frame. Tap to move the camera.
## The inked sheet (scenery, the wire, the generator) is drawn by this control and only redrawn when the
## post itself changes; live markers sit on a child layer that redraws when something actually moved,
## at most 20 times a second.
##
## Legend: operatives are ivory dots (ringed when selected), the informant brass. Guards are inked by
## kind (patrol: dot, posted sentry: square, tower: triangle, sergeant: ringed dot, reinforcement:
## diamond), hollow while drawn off by a noise, red once alerted. A cross is a body (red: found; a
## ringed cross will wake up), a brass tick the tripwire, a red ring the alarm's last known position.
signal focus_requested(point: Vector2)
const Kit := preload("res://scripts/three_d/action_slot.gd")
const TexFrame := preload("res://assets/ui/map_frame.png")
const TexPaper := preload("res://assets/ui/map_paper.png")
const FRAME := 7.0
const SEA := Color(0.33,0.46,0.47,0.62)
const SHORE := Color(0.20,0.30,0.31,0.9)
const BUSH := Color(0.38,0.45,0.25,0.62)
const BLOCK := Color(0.17,0.17,0.14)
const CLUTTER := Color(0.36,0.35,0.28)
const TRACK := Color(0.40,0.33,0.20,0.5)
# Cart tracks of the outpost in mission units (hinted only; the terrain owns the real ones).
const TRACKS := [[Vector2(653,0),Vector2(653,800)],[Vector2(160,384),Vector2(1280,384)],[Vector2(160,621),Vector2(1280,621)]]
var sim: RefCounted
var camera: Camera3D
var map_rect: Rect2
var markers: Control
var _factor := Vector2.ONE
var _footprint := PackedVector2Array([Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO])
var _shape := PackedVector2Array([Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO])
var _tri := PackedVector2Array([Vector2.ZERO,Vector2.ZERO,Vector2.ZERO])
var _clock: float = 0.0
var _seen_time: float = -1.0
var _seen_selected: String = ""
var _seen_camera := Transform3D()
var _seen_zoom: float = 0.0
var _seen_static: int = -1
var _seen_alert: float = -1.0
var _seen_guards: int = -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	tooltip_text = "Tap the reconnaissance map to move the camera"
	markers = Control.new()
	markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	markers.clip_contents = true
	markers.draw.connect(_draw_markers)
	add_child(markers)
	resized.connect(_measure)
	_measure()

func _measure() -> void:
	map_rect = Rect2(FRAME,FRAME,size.x-FRAME*2,size.y-FRAME*2)
	if sim != null: _factor = map_rect.size/Vector2(float(sim.data.width),float(sim.data.height))
	queue_redraw()
	if markers:
		# The marker layer covers exactly the sheet and clips to it (camera footprint, sight wedges).
		markers.position = map_rect.position
		markers.size = map_rect.size
		markers.queue_redraw()

func _process(dt: float) -> void:
	if sim == null or camera == null or not is_visible_in_tree(): return
	_clock += dt
	if _clock < 0.05: return
	# The sheet itself changes three times in a mission: gate open, wire cut, generator dead.
	var fixed: int = (1 if sim.door_open else 0)+(2 if sim.fence_cut else 0)+(4 if sim.radio_cut else 0)
	if fixed != _seen_static:
		_seen_static = fixed
		queue_redraw()
	var alert: float = sim.max_suspicion()
	if sim.time == _seen_time and sim.selected_id == _seen_selected and camera.size == _seen_zoom and alert == _seen_alert and sim.guards.size() == _seen_guards and camera.global_transform == _seen_camera: return
	_clock = 0.0
	_seen_time = sim.time
	_seen_selected = sim.selected_id
	_seen_zoom = camera.size
	_seen_alert = alert
	_seen_guards = sim.guards.size()
	_seen_camera = camera.global_transform
	markers.queue_redraw()

## Rail or cart tracks drawn on the sheet: the mission's own ("tracks", in mission units), else the outpost's.
func _tracks() -> Array:
	if not sim.data.has("tracks"): return TRACKS
	var out: Array = []
	for line: Array in sim.data.tracks:
		out.append([Vector2(float(line[0][0]),float(line[0][1])),Vector2(float(line[1][0]),float(line[1][1]))])
	return out

func _at(point: Vector2) -> Vector2:
	return map_rect.position+point*_factor

func _block(item: Dictionary, color: Color) -> void:
	var r: Rect2 = sim.rect_of(item)
	draw_rect(Rect2((map_rect.position+r.position*_factor).round(),(r.size*_factor).round()),color)

func _draw() -> void:
	if sim == null: return
	_factor = map_rect.size/Vector2(float(sim.data.width),float(sim.data.height))
	# Sheet (2x paper tile at half scale).
	draw_set_transform(map_rect.position,0.0,Vector2(0.5,0.5))
	draw_texture_rect(TexPaper,Rect2(Vector2.ZERO,map_rect.size*2.0),true)
	draw_set_transform(Vector2.ZERO)
	# Survey grid every five metres.
	var grid := Color(Kit.INK,0.09)
	var step: float = 160.0
	var gx: float = step
	while gx < float(sim.data.width):
		draw_line(_at(Vector2(gx,0)).round()+Vector2(0.5,0),_at(Vector2(gx,sim.data.height)).round()+Vector2(0.5,0),grid,1.0)
		gx += step
	var gy: float = step
	while gy < float(sim.data.height):
		draw_line(_at(Vector2(0,gy)).round()+Vector2(0,0.5),_at(Vector2(sim.data.width,gy)).round()+Vector2(0,0.5),grid,1.0)
		gy += step
	for track: Array in _tracks():
		draw_dashed_line(_at(track[0]),_at(track[1]),TRACK,1.25,4.0,true,true)
	for bush: Dictionary in sim.data.bushes:
		_block(bush,BUSH)
		var r: Rect2 = sim.rect_of(bush)
		draw_rect(Rect2((map_rect.position+r.position*_factor).round()+Vector2(0.5,0.5),(r.size*_factor).round()-Vector2.ONE),Color(BUSH,0.9),false,1.0)
	for item: Dictionary in sim.data.obstacles:
		match String(item.kind):
			"water":
				_block(item,SEA)
				var r: Rect2 = sim.rect_of(item)
				var x: float = roundf(_at(r.end).x)
				draw_line(Vector2(x,map_rect.position.y),Vector2(x,map_rect.end.y),SHORE,1.5)
				# Two sounding lines offshore.
				for k: int in [1,2]:
					var sx: float = roundf(x-k*r.size.x*_factor.x*0.3)+0.5
					draw_dashed_line(Vector2(sx,map_rect.position.y),Vector2(sx,map_rect.end.y),Color(SHORE,0.35),1.0,3.0)
			"building", "wall": _block(item,BLOCK)
			_: _block(item,CLUTTER)
	if not sim.door_open and sim.data.has("door"): _block(sim.data.door,Color(Kit.BRASS.darkened(0.25),0.95))
	_draw_wire()
	if sim.data.has("radio"):
		# The generator behind the radio post: a brass bolt while it runs, struck out once it is dead.
		var at: Vector2 = _at(Vector2(float(sim.data.radio.x),float(sim.data.radio.y))).round()
		var tone: Color = Color(Kit.INK,0.55) if sim.radio_cut else Kit.BRASS.darkened(0.3)
		draw_circle(at,5.0,Color(Kit.IVORY,0.85),true,-1.0,true)
		draw_polyline(PackedVector2Array([at+Vector2(1.5,-4),at+Vector2(-2,0.5),at+Vector2(2,-0.5),at+Vector2(-1.5,4)]),tone,1.5,true)
		if sim.radio_cut: draw_line(at+Vector2(-4,4),at+Vector2(4,-4),Color(Kit.INK,0.8),1.25,true)
	# Extraction point: broken ring on the shore (a rescue has none).
	if sim.data.has("extraction"):
		var boat: Vector2 = _at(Vector2(float(sim.data.extraction.x),float(sim.data.extraction.y)))
		var ring: float = float(sim.data.extraction.radius)*_factor.x
		for k: int in range(6):
			draw_arc(boat,ring,k*TAU/6.0+0.12,(k+1)*TAU/6.0-0.12,6,Color(Kit.INK,0.75),1.25,true)
		draw_line(boat+Vector2(-3,-3),boat+Vector2(3,3),Color(Kit.INK,0.8),1.25,true)
		draw_line(boat+Vector2(-3,3),boat+Vector2(3,-3),Color(Kit.INK,0.8),1.25,true)
	Kit.nine(self,TexFrame,Rect2(Vector2.ZERO,size),36.0,8.0,Color.WHITE,false)

## The perimeter wire as a ticked line; the one span Rook can cut is brass until it is cut, then a gap.
func _draw_wire() -> void:
	for barrier: Dictionary in sim.data.get("barriers",[]):
		var r: Rect2 = sim.rect_of(barrier)
		match String(barrier.get("kind","")):
			"fence":
				var y: float = roundf(_at(r.get_center()).y)+0.5
				var from: float = _at(r.position).x
				var to: float = _at(r.end).x
				var weak: bool = bool(barrier.get("cuttable",false))
				if weak and sim.fence_cut:
					for edge: float in [from,to]: draw_line(Vector2(roundf(edge)+0.5,y-3),Vector2(roundf(edge)+0.5,y+3),Color(Kit.INK,0.8),1.0)
					continue
				draw_line(Vector2(from,y),Vector2(to,y),Kit.BRASS.darkened(0.35) if weak else Color(Kit.INK,0.7),2.0 if weak else 1.0)
				if weak: continue
				var x: float = from+4.0
				while x < to-2.0:
					draw_line(Vector2(roundf(x)-1.5,y-1.5),Vector2(roundf(x)+1.5,y+1.5),Color(Kit.INK,0.55),1.0)
					x += 9.0
			"tower":
				# The watchtower's footprint.
				draw_rect(Rect2((map_rect.position+r.position*_factor).round()+Vector2(0.5,0.5),(r.size*_factor).round()),Color(Kit.INK,0.6),false,1.0)

func _guard_mark(at: Vector2, kind: String, radius: float, color: Color, filled: bool) -> void:
	match kind:
		"sentry":
			var box := Rect2(at-Vector2(radius,radius)*0.9,Vector2(radius,radius)*1.8)
			if filled: markers.draw_rect(box,color)
			else: markers.draw_rect(box.grow(-0.6),color,false,1.3)
		"tower":
			_tri[0] = at+Vector2(0,-radius*1.25)
			_tri[1] = at+Vector2(radius*1.15,radius*0.85)
			_tri[2] = at+Vector2(-radius*1.15,radius*0.85)
			if filled: markers.draw_colored_polygon(_tri,color)
			else:
				for i: int in range(3): markers.draw_line(_tri[i],_tri[(i+1)%3],color,1.3,true)
		"reinforcement":
			_shape[0] = at+Vector2(0,-radius*1.25)
			_shape[1] = at+Vector2(radius*1.25,0)
			_shape[2] = at+Vector2(0,radius*1.25)
			_shape[3] = at+Vector2(-radius*1.25,0)
			if filled: markers.draw_colored_polygon(_shape,color)
			else:
				for i: int in range(4): markers.draw_line(_shape[i],_shape[(i+1)%4],color,1.3,true)
		_:
			if filled: markers.draw_circle(at,radius,color,true,-1.0,true)
			else: markers.draw_arc(at,radius-0.5,0.0,TAU,16,color,1.4,true)

func _draw_markers() -> void:
	if sim == null: return
	# Everything here is in sheet-local coordinates; the layer clips to the sheet.
	if camera:
		# Camera footprint on the ground plane.
		var view: Vector2 = camera.get_viewport().get_visible_rect().size
		var count: int = 0
		for i: int in range(5):
			var p := Vector2(view.x if (i == 1 or i == 2) else 0.0,view.y if (i == 2 or i == 3) else 0.0)
			var hit: Variant = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(p),camera.project_ray_normal(p))
			if hit is Vector3:
				_footprint[count] = Vector2(hit.x,hit.z)*32*_factor
				count += 1
		if count == 5:
			markers.draw_polyline(_footprint,Color(Kit.IVORY,0.35),3.0,true)
			markers.draw_polyline(_footprint,Color(Kit.INK,0.62),1.0,true)
	if bool(sim.alarm.active):
		# Where the hunters are heading: the last place anyone was seen.
		var last: Vector2 = Vector2(float(sim.alarm.x),float(sim.alarm.y))*_factor
		markers.draw_circle(last,9.0,Color(Kit.RED,0.16),true,-1.0,true)
		markers.draw_arc(last,9.0,0.0,TAU,24,Kit.RED,1.5,true)
		markers.draw_arc(last,4.0,0.0,TAU,16,Color(Kit.RED,0.8),1.0,true)
	for trap: Dictionary in sim.traps:
		var at: Vector2 = Vector2(float(trap.x),float(trap.y))*_factor
		markers.draw_line(at+Vector2(-5,0),at+Vector2(5,0),Kit.INK,3.0)
		markers.draw_line(at+Vector2(-4,0),at+Vector2(4,0),Kit.BRASS,1.5)
		markers.draw_line(at+Vector2(-4.5,-3),at+Vector2(-4.5,3),Kit.INK,1.5)
		markers.draw_line(at+Vector2(4.5,-3),at+Vector2(4.5,3),Kit.INK,1.5)
	for guard: Dictionary in sim.guards:
		var at: Vector2 = sim.position_of(guard)*_factor
		var state: String = guard.state
		if bool(guard.get("creature", false)):
			# a rescue's creature in the square: a red blot, ringed while it goes for someone; nothing while it is off the map
			if state in ["waiting", "away"]: continue
			if state == "dead":
				markers.draw_line(at+Vector2(-3,-3),at+Vector2(3,3),Color(Kit.RED,0.7),1.5,true)
				markers.draw_line(at+Vector2(-3,3),at+Vector2(3,-3),Color(Kit.RED,0.7),1.5,true)
				continue
			markers.draw_circle(at,5.0,Kit.INK,true,-1.0,true)
			markers.draw_circle(at,3.8,Kit.RED if state != "driven" else Kit.KHAKI,true,-1.0,true)
			if state == "stalk": markers.draw_arc(at,7.5,0.0,TAU,20,Kit.RED,1.5,true)
			continue
		if state in sim.DOWN_STATES:
			# Out of the fight: a cross where he lies. Nothing for a body hidden for good or on someone's
			# shoulders; red once it has been found; ringed while he is only stunned.
			if state == "held" or bool(guard.hidden) or str(guard.carried_by) != "": continue
			var ink: Color = Kit.RED if bool(guard.found) else Color(Kit.INK,0.8)
			markers.draw_line(at+Vector2(-3,-3),at+Vector2(3,3),ink,1.5,true)
			markers.draw_line(at+Vector2(-3,3),at+Vector2(3,-3),ink,1.5,true)
			if state == "stunned": markers.draw_arc(at,5.5,0.0,TAU,16,Kit.BRASS.darkened(0.3),1.25,true)
			continue
		# Red is kept for a guard who is noticing someone or answering an alarm; one drawn off his
		# round by a noise is shown hollow instead.
		var hot: bool = float(guard.suspicion) > 0.1 or state == "hunt" or state == "alert"
		var tone: Color = Kit.RED if hot else Kit.INK
		var kind: String = guard.kind
		# A small open wedge shows where he is looking.
		var heading: float = float(guard.angle)
		markers.draw_line(at,at+Vector2.from_angle(heading-0.5)*10.0,Color(tone,0.8),1.25,true)
		markers.draw_line(at,at+Vector2.from_angle(heading+0.5)*10.0,Color(tone,0.8),1.25,true)
		_guard_mark(at,kind,4.3,Color(Kit.IVORY,0.92),true)
		_guard_mark(at,kind,3.1,tone,hot or not state in ["investigate","search","return"])
		if kind == "sergeant": markers.draw_arc(at,6.2,0.0,TAU,20,tone,1.25,true)
	if sim.has_prisoner:
		var asset: Vector2 = sim.position_of(sim.prisoner)*_factor
		markers.draw_circle(asset,4.8,Kit.INK,true,-1.0,true)
		markers.draw_circle(asset,3.6,Kit.BRASS,true,-1.0,true)
		markers.draw_circle(asset,1.4,Kit.INK,true,-1.0,true)
	# Charge sites: a brass ring to do, a filled brass dot once set.
	for site: Dictionary in sim.charge_sites():
		var at: Vector2 = Vector2(float(site.get("tx",site.x)),float(site.get("ty",site.y)))*_factor
		if sim.planted.has(str(site.id)):
			markers.draw_circle(at,3.4,Kit.INK,true,-1.0,true)
			markers.draw_circle(at,2.4,Kit.BRASS,true,-1.0,true)
		else:
			markers.draw_arc(at,3.0,0.0,TAU,12,Kit.BRASS.darkened(0.15),1.5,true)
	for unit: Dictionary in sim.units:
		if bool(unit.get("away", false)): continue  # not in the square yet (a rescue: Juan Salvo before he comes)
		var at: Vector2 = sim.position_of(unit)*_factor
		var active: bool = unit.id == sim.selected_id
		if active: markers.draw_arc(at,7.2,0.0,TAU,24,Kit.INK,1.5,true)
		markers.draw_circle(at,4.8,Kit.INK,true,-1.0,true)
		markers.draw_circle(at,3.6,(Kit.IVORY if active else Color("c9cdb6")) if bool(unit.alive) else Kit.RED.darkened(0.2),true,-1.0,true)

func _gui_input(event: InputEvent) -> void:
	var point: Vector2
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed: point=event.position
	elif event is InputEventScreenTouch and event.pressed: point=event.position
	else: return
	if map_rect.has_point(point):
		focus_requested.emit((point-map_rect.position)/map_rect.size*Vector2(float(sim.data.width),float(sim.data.height)))
	accept_event()
