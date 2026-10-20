extends SceneTree
## The phone controls end to end, through real viewport events on the 3D scene. First Riachuelo: selecting, the slots
## of the neighbours' bars (Biguá's knife, Hornero's handle and bell, Lechuza's cord, the skill a plate takes where
## there is no gun), arming and lowering, taps on guards, bodies, cover and the things an operative can work on (the
## cellar door, the passenger, the lamp board), the automatic pause on an alarm, checkpoints, failure and retry, the
## result sheet with its stamps on disk, one-time hints, the coach, and the layout. Then the Plaza de Mayo: Juan
## Salvo's photo (his portrait where the licensed art is installed, else a plain plate with his name) dark and deaf
## until he comes, his rifle armed from its plate with the square's own words, a cascarudo marked and shot with a tap,
## and a tap on one with nobody armed.
## Situations are staged by placing actors by hand; every order goes in through a click or a touch.
const PROGRESS := "user://hud_test_progress.cfg"
var main: Node3D
var sim: RefCounted
var hud: Control
var failures: int=0
var checks: int=0

func _init() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL: "+label)

func click(point: Vector2) -> void:
	var motion:=InputEventMouseMotion.new()
	motion.position=point
	motion.global_position=point
	root.push_input(motion,true)
	for pressed: bool in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=point
		event.global_position=point
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		root.push_input(event,true)

## A left-button drag from one point to another (a swipe).
func drag(from: Vector2, to: Vector2) -> void:
	for step: Array in [[from,true],[to,false]]:
		var motion:=InputEventMouseMotion.new()
		motion.position=step[0]
		motion.global_position=step[0]
		root.push_input(motion,true)
		var event:=InputEventMouseButton.new()
		event.position=step[0]
		event.global_position=step[0]
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=step[1]
		root.push_input(event,true)

func touch(point: Vector2) -> void:
	for pressed: bool in [true,false]:
		var event:=InputEventScreenTouch.new()
		event.index=0
		event.position=point
		event.pressed=pressed
		root.push_input(event,true)

func key(keycode: Key) -> void:
	var event:=InputEventKey.new()
	event.keycode=keycode
	event.pressed=true
	root.push_input(event,true)

func press(control: Control) -> void:
	click(control.get_global_rect().get_center())

func slot(name: String) -> void:
	press(hud.slots[name])

## Centres the camera on a mission point, close enough for sure taps.
func look(at: Vector2) -> void:
	main.desired_target=Vector3(at.x/32,0,at.y/32)
	main.target=main.desired_target
	main.desired_zoom=16.0
	main.zoom=16.0
	main._update_camera(1.0,true)

func screen(at: Vector2, height: float=0.0) -> Vector2:
	return main.camera.unproject_position(Vector3(at.x/32,height,at.y/32))

## A tap on the world at a mission point (`height` metres up: a standing man's middle is 0.9).
func tap(at: Vector2, height: float=0.0) -> void:
	var point: Vector2=screen(at,height)
	check(not main._point_on_ui(point) and root.get_visible_rect().has_point(point),"Staging: the tap at %s lands on open screen" % str(at))
	click(point)

func advance(seconds: float) -> void:
	for i in range(int(seconds/0.05)):
		sim.update(0.05)
		main.world.update_visuals(0.05)
	hud.refresh()

## A fresh mission with the clock running.
func fresh() -> void:
	main._command("restart_now")
	hud.refresh()

## Takes every guard not named out of the picture, so staged scenes are not disturbed.
func quiet(except: Array=[]) -> void:
	for guard: Dictionary in sim.guards:
		if guard.id in except: continue
		sim._fell(guard,"bound")
		guard.hidden=true

func put(id: String, at: Vector2) -> Dictionary:
	var unit: Dictionary=sim.unit_by_id(id)
	unit.x=at.x
	unit.y=at.y
	unit.path=[]
	return unit

func place(id: String, at: Vector2, facing: float) -> Dictionary:
	var guard: Dictionary=sim.guard_by_id(id)
	guard.x=at.x
	guard.y=at.y
	guard.angle=deg_to_rad(facing)
	guard.path=[]
	return guard

func order(id: String) -> String:
	return str(sim.unit_by_id(id).order.get("type",""))

func target(id: String) -> String:
	return str(sim.unit_by_id(id).order.get("target",""))

## Lets the scene lay itself out and notice a change of phase, as a frame of real play would.
func settle() -> void:
	for i in range(3): await process_frame

func run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESS))
	root.size=Vector2i(1280,720)
	(load("res://scripts/missions.gd") as GDScript).choose("riachuelo", false)
	main=load("res://Main.tscn").instantiate()
	root.add_child(main)
	sim=main.sim
	hud=main.hud
	hud.progress_path=PROGRESS
	hud.load_progress()
	main.auto_command_on_alarm=false
	for i in range(12): await process_frame
	check(hud.overlay.visible and hud.current_modal=="briefing","The briefing opens the game")
	check(hud.operatives_row.visible and hud.modal_body.text!="" and hud.modal_body.text!=hud.BRIEFING_COPY,"The briefing is the level's own words, and the four")
	check(not hud.size_rows[0].row.visible and hud.second_button.text=="MENU","…and MENU beside BEGIN (settings live on the launch screen)")
	main._command("howto")
	check(hud.current_modal=="howto" and hud.howto_box.visible and hud.howto_page==0 and hud.second_button.text=="BRIEFING","HOW TO PLAY over the briefing, card one")
	var clip_on_disk: bool=ResourceLoader.exists(hud.HOWTO_DIR+"move.ogv")
	check(not clip_on_disk or (hud.howto_video.stream!=null and hud.howto_video.is_playing()),"Its clip plays")
	press(hud.begin_button)
	check(hud.howto_page==1 and hud.begin_button.text=="NEXT" and hud.second_button.text=="BACK" and hud.howto_line.text==hud.HOWTO[1].line,"NEXT turns the card")
	var mid: Vector2=hud.howto_frame.get_global_rect().get_center()
	drag(mid,mid+Vector2(-120,0))
	check(hud.howto_page==2,"A swipe to the left turns to the next card")
	drag(mid,mid+Vector2(120,0))
	check(hud.howto_page==1,"…to the right, back one")
	click(mid)
	check(hud.howto_page==2,"A tap on the clip moves on")
	for i in range(8): press(hud.begin_button) if hud.howto_page<hud.HOWTO.size()-1 else null
	check(hud.howto_page==hud.HOWTO.size()-1 and hud.begin_button.text=="BEGIN OPERATION","The last card begins the operation")
	for i in range(hud.HOWTO.size()): press(hud.second_button)
	check(hud.current_modal=="briefing","BACK all the way returns to the briefing")
	main._command("howto")
	check(hud.howto_page==0,"Coming back in starts again at card one")
	press(hud.second_button)
	press(hud.begin_button)
	check(sim.phase=="playing" and not sim.paused and not hud.overlay.visible,"Begin starts live play")
	selecting()
	biguas_bar()
	bodies()
	horneros_bar()
	lechuzas_bar()
	things()
	await alarm()
	await checkpoints()
	await results()
	hints()
	coach()
	back_button()
	icons()
	await layouts()
	await text_sizes()
	await web_layout()
	main.queue_free()
	await process_frame
	await plaza()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESS))
	print("HUD_ACTIONS_CHECKS=",checks," FAILURES=",failures)
	quit(0 if failures==0 else 1)

## Every icon the HUD or an operation's data names has a picture: a flat glyph or a rendered 3D object, and the
## rendered atlases hold what action_slot.gd says they do (tools/icons3d/finish.py atlas builds them).
func icons() -> void:
	var Kit: GDScript = hud.ActionSlot
	var named: Array=hud.ACTION_ICONS.values()+hud.THING_ICONS.values()
	for card: Dictionary in hud.HOWTO: named.append(str(card.glyph))
	for file: String in DirAccess.get_files_at("res://data"):
		if file.ends_with(".json"): _icons_in(JSON.parse_string(FileAccess.get_file_as_string("res://data/"+file)),named)
	var missing: Array=[]
	for name: Variant in named:
		if not (str(name) in Kit.GLYPHS or str(name) in Kit.ICONS3D) and not str(name) in missing: missing.append(str(name))
	check(missing.is_empty(),"Every icon named has a picture (missing: %s)" % ", ".join(missing))
	for name: String in ["lampkey","bell","papers","oars"]:
		check(name in Kit.ICONS3D,"La Boca's %s is in the 3D atlas" % name)
	var rows: int=ceili(float(Kit.ICONS3D.size())/Kit.ICON3D_COLS)
	var atlas: Vector2=Kit.TexIcons3D.get_size()
	check(atlas==Vector2(Kit.ICON3D_COLS,rows*2)*Kit.ICON3D_CELL,"icons3d.png holds the ICONS3D list in colour and in grey (%s)" % atlas)
	check(Kit.TexMedals.get_size()==Vector2(Kit.BADGES.size(),3)*Kit.MEDAL_CELL,"medals.png holds the five medals in three rows")

func _icons_in(value: Variant, into: Array) -> void:
	if value is Dictionary:
		for key: Variant in value:
			if str(key)=="icon" and value[key] is String: into.append(value[key])
			else: _icons_in(value[key],into)
	elif value is Array:
		for item: Variant in value: _icons_in(item,into)

func selecting() -> void:
	press(hud.portrait_buttons.lechuza)
	check(sim.selected_id=="lechuza" and hud.portrait_buttons.lechuza.selected,"A tap on Lechuza's photo selects him")
	press(hud.portrait_buttons.hornero)
	check(sim.selected_id=="hornero","A tap on Hornero's photo selects him")
	var lechuza: Dictionary=sim.unit_by_id("lechuza")
	look(sim.position_of(lechuza)+Vector2(40,-30))
	var held: Vector3=main.desired_target
	tap(sim.position_of(lechuza),0.85)
	check(sim.selected_id=="lechuza","A tap on an operative in the world selects him")
	check(main.desired_target==held,"…without moving the camera")
	tap(sim.position_of(lechuza)+Vector2(60,-50))
	check(order("lechuza")=="move" and not lechuza.path.is_empty(),"A tap on open ground moves the selected operative")
	tap(sim.position_of(lechuza),0.85)
	check(order("lechuza")=="" and lechuza.path.is_empty(),"A tap on the selected operative halts him")
	touch(screen(sim.position_of(lechuza)+Vector2(60,-50)))
	check(order("lechuza")=="move","A finger does what the mouse does")

## Where staged scenes play: the street by the courtyard the four start from, the washing on its line to hide in.
const STAGE := Vector2(3456,300)
const WASHING := Vector2(3336,440)

## Biguá's bar: stance, his knife, the oars; a body carried and hidden; PLAN and EXECUTE.
func biguas_bar() -> void:
	fresh()
	quiet(["north","middle"])
	press(hud.portrait_buttons.bigua)
	var bigua: Dictionary=put("bigua",STAGE)
	var g1: Dictionary=place("north",STAGE+Vector2(-120,-40),-90.0)
	look(STAGE+Vector2(0,40))
	hud.refresh()
	check(hud.slots.stance.text=="CROUCHED" and hud.slots.melee.text=="KNIFE","Biguá's bar: stance and knife (%s, %s)" % [hud.slots.stance.text,hud.slots.melee.text])
	check(not hud.slots.gun.visible,"…no gun, and no plate left blank for one")
	check(hud.slots.context.text=="CARRY" and hud.slots.context.dimmed,"With nothing to do the context slot offers carrying, dead")
	slot("context")
	check(hud.notice.visible and hud.notice.text=="Nobody to carry." and order("bigua")=="","A dead slot says why when tapped")
	# Stance.
	slot("stance")
	check(bigua.stance=="walk" and hud.slots.stance.text=="STANDING" and hud.slots.stance.symbol=="walk","The stance slot stands him up")
	slot("stance")
	check(bigua.stance=="sneak" and hud.slots.stance.text=="CROUCHED","…and puts him back in a crouch")
	# Knife: arm, cancel.
	slot("melee")
	check(main.armed=="takedown" and hud.slots.melee.armed and hud.slots.melee.text=="CANCEL" and hud.prompt.visible,"The knife slot arms a takedown")
	check(not hud._marked.is_empty() and "north" in hud._marked,"…and marks the guards within reach of it")
	slot("melee")
	check(main.armed=="" and not hud.slots.melee.armed and not hud.prompt.visible,"A second tap on the slot cancels")
	slot("melee")
	key(KEY_ESCAPE)
	check(main.armed=="","Escape lowers it too")
	# Not armed: a tap on a guard is the knife.
	tap(sim.position_of(g1),0.95)
	check(order("bigua")=="takedown" and target("bigua")=="north","Unarmed, a tap on a guard orders the knife")
	check(hud.slots.melee.active and hud._tag_text.bigua=="KNIFE","The order shows on the bar and on his tag (%s)" % str(hud._tag_text.get("bigua","")))
	tap(sim.position_of(bigua),0.85)
	check(order("bigua")=="","Tapping him again calls it off")
	tap(sim.position_of(g1),0.95)
	advance(3.0)
	check(g1.state=="dead" and int(sim.stats.kills)==1,"The knife takes him (%s)" % g1.state)
	# The body he made: the context slot carries it, then hides it in the washing on its line.
	hud.refresh()
	check(hud.slots.context.text=="CARRY" and not hud.slots.context.dimmed and str(hud.context.target)=="north","A body nearby: the context slot offers to carry it")
	slot("context")
	check(order("bigua")=="pickup" and target("bigua")=="north","…and orders it")
	advance(5.0)
	check(bigua.carrying=="north" and hud._tag_text.bigua=="CARRYING","He lifts him")
	check(hud.slots.context.text=="HIDE BODY" and hud.slots.context.symbol=="hide","With cover close by the context slot offers to hide him")
	slot("stance")
	check(hud.notice.text=="Put the body down first." and bigua.stance=="walk","His other slots are dead under the load, and say why")
	slot("context")
	check(order("bigua")=="drop" and sim.in_bush(Vector2(float(bigua.order.x),float(bigua.order.y))),"…and sends him into it")
	advance(8.0)
	check(bigua.carrying=="" and bool(g1.hidden),"The body is hidden")
	# Plan / execute.
	slot("plan")
	check(sim.paused and hud.slots.plan.text=="EXECUTE" and hud.slots.plan.armed and hud.planning.visible,"PLAN stops the clock: command mode")
	slot("plan")
	check(not sim.paused and hud.slots.plan.text=="PLAN" and not hud.planning.visible,"EXECUTE starts it again")

func bodies() -> void:
	fresh()
	quiet(["north"])
	press(hud.portrait_buttons.bigua)
	var bigua: Dictionary=put("bigua",WASHING+Vector2(130,-60))
	var g1: Dictionary=place("north",WASHING+Vector2(100,-70),-90.0)
	sim._fell(g1,"dead")
	look(WASHING+Vector2(80,-40))
	hud.refresh()
	tap(sim.position_of(g1),0.25)
	check(order("bigua")=="pickup" and target("bigua")=="north","A tap on a body orders it carried")
	advance(1.2)
	check(bigua.carrying=="north","He lifts it")
	tap(WASHING)
	check(order("bigua")=="drop" and Vector2(float(bigua.order.x),float(bigua.order.y)).distance_to(WASHING)<3.0,"Carrying, a tap inside cover means hide it there")
	advance(5.0)
	check(bigua.carrying=="" and bool(g1.hidden) and sim.position_of(g1).distance_to(WASHING)<14.0,"The body goes into the cover where he was sent")
	# The marker floating over a thing takes the tap for it.
	var g2: Dictionary=sim.guard_by_id("middle")
	g2.hidden=false
	sim._fell(g2,"dead")
	g2.x=WASHING.x+150.0
	g2.y=WASHING.y-40.0
	hud.refresh()
	var marker: Vector2=Vector2.ZERO
	for thing: Dictionary in sim.interactables():
		if thing.type=="body" and thing.target=="middle": marker=hud._pin_point(thing)
	check(hud.pin_at(marker).get("target","")=="middle","A body left in the open carries a marker")
	click(marker)
	check(order("bigua")=="pickup" and target("bigua")=="middle","A tap on the marker is a tap on the body")

## Hornero's bar: the tram's handle (a stun), the gondola on the third plate, the bell thrown to draw the guards.
func horneros_bar() -> void:
	fresh()
	quiet(["middle"])
	press(hud.portrait_buttons.hornero)
	var hornero: Dictionary=put("hornero",STAGE)
	look(STAGE+Vector2(0,40))
	hud.refresh()
	check(hud.slots.melee.text=="HANDLE" and hud.slots.tool.text=="BELL","Hornero's bar: the handle and the bell (%s, %s)" % [hud.slots.melee.text,hud.slots.tool.text])
	check(hud.slots.gun.visible and hud.slots.gun.symbol=="gondola","No gun: his third plate is a skill of his own, the gondola (%s)" % hud.slots.gun.symbol)
	check(hud.slots.tool.count==3,"The bell plate carries its three rings (%d)" % hud.slots.tool.count)
	# The bell: armed, the range ring; a ring too far still goes, and lands on the ring; then the plate cools down.
	slot("tool")
	check(main.armed=="distract" and main.world.aiming and hud.slots.tool.armed,"The bell slot arms a throw and shows the range ring")
	tap(STAGE+Vector2(260,-200))
	advance(0.1)
	var rung: Array=sim.noise.filter(func(n: Dictionary) -> bool: return str(n.kind)=="bell")
	check(main.armed=="" and not main.world.aiming and float(hornero.cooldown)>0.0 and rung.size()==1,"Out of range: the bell rings all the same (%s)" % str(sim.noise))
	var reach: float=float(hornero.throw.range)
	check(not rung.is_empty() and sim.position_of(hornero).distance_to(Vector2(float(rung[0].x),float(rung[0].y)))<=reach+0.5,"…no further than the ring")
	check(hud.slots.tool.dimmed and hud.slots.tool.wait>0 and hud.slots.tool.count==2,"The plate shows the cooldown and one ring fewer")
	slot("tool")
	check(main.armed=="" and hud.notice.text=="Not ready yet.","A cooling bell says so and does not arm")
	# The handle: a guard knocked out for a while.
	var g: Dictionary=place("middle",STAGE+Vector2(-110,-30),-90.0)
	look(STAGE+Vector2(-40,20))
	slot("melee")
	check(main.armed=="takedown" and "middle" in hud._marked,"The handle slot arms, the guard in reach is marked")
	tap(sim.position_of(g),0.95)
	check(order("hornero")=="takedown" and target("hornero")=="middle" and main.armed=="","…and the tap on him orders it")
	advance(3.0)
	check(g.state=="stunned","The handle knocks him out (%s)" % g.state)

## Lechuza's bar: his cord (a guard bound for good), the lamp board on the third plate, the ladder.
func lechuzas_bar() -> void:
	fresh()
	quiet(["middle"])
	press(hud.portrait_buttons.lechuza)
	put("lechuza",STAGE)
	look(STAGE+Vector2(0,40))
	hud.refresh()
	check(hud.slots.melee.text=="BIND" and hud.slots.melee.symbol=="cord","Lechuza's bar: his cord binds (%s, %s)" % [hud.slots.melee.text,hud.slots.melee.symbol])
	check(hud.slots.gun.symbol=="lampboard" and hud.slots.tool.symbol=="ladder","…the lamp board and the ladder on the other plates (%s, %s)" % [hud.slots.gun.symbol,hud.slots.tool.symbol])
	slot("stance")
	check(sim.unit_by_id("lechuza").stance=="walk","Lechuza's stance slot works")
	slot("stance")
	var g: Dictionary=place("middle",STAGE+Vector2(-110,-30),-90.0)
	look(STAGE+Vector2(-40,20))
	slot("melee")
	check(main.armed=="takedown","The cord slot arms")
	tap(sim.position_of(g),0.95)
	check(order("lechuza")=="takedown" and target("lechuza")=="middle" and main.armed=="","…and the tap on the guard orders it")
	check(hud._tag_text.lechuza=="BIND","His tag names the order (%s)" % str(hud._tag_text.get("lechuza","")))
	advance(5.0)
	check(g.state=="bound" and int(sim.stats.binds)==1,"The guard is bound (%s)" % g.state)

## Where the marker of the first thing of a kind floats on screen (a tap there is a tap on the thing).
func _pin_of(kind: String) -> Vector2:
	for thing: Dictionary in sim.interactables():
		if str(thing.type)==kind: return hud._pin_point(thing)
	return Vector2(-1,-1)

## The things of La Boca: the cellar door (Benteveo told whose job it is, Hornero opens it), the passenger brought up,
## the lamp board put out.
func things() -> void:
	fresh()
	quiet()
	var door := Vector2(float(sim.data.door.interactX),float(sim.data.door.interactY))
	press(hud.portrait_buttons.benteveo)
	put("benteveo",door+Vector2(40,60))
	look(door+Vector2(0,30))
	hud.refresh()
	hud.refresh()
	# (a tap on the door itself, in the wall: on open ground in front of it a tap is a walk there)
	tap(Vector2(float(sim.data.door.x)+16.0,float(sim.data.door.y)),0.0)
	check(order("benteveo")=="" and hud.notice.text==str(sim.data.door.refuse),"Benteveo tapping the cellar door is told whose job it is (%s)" % hud.notice.text)
	press(hud.portrait_buttons.hornero)
	put("hornero",door+Vector2(-40,60))
	look(door+Vector2(0,30))
	hud.refresh()
	check(hud.slots.context.symbol=="cellar" and not hud.slots.context.dimmed,"At the door Hornero's context slot is the cellar (%s)" % hud.slots.context.symbol)
	click(_pin_of("gate"))
	check(order("hornero")=="unlock","A tap on the door sends Hornero to open it")
	advance(4.0)
	check(sim.door_open and bool(sim.objectives[0].done),"The cellar is open")
	check(hud.toast.visible and hud.toast.text!="","The automatic checkpoint is announced (%s)" % hud.toast.text)
	# The passenger.
	hud.refresh()
	check(hud.slots.context.symbol==str(sim.data.prisoner.icon),"With the door open the context slot brings the passenger up (%s)" % hud.slots.context.symbol)
	look(sim.position_of(sim.prisoner)+Vector2(0,60))
	tap(sim.position_of(sim.prisoner),0.9)
	check(order("hornero")=="rescue","A tap on the passenger orders it")
	advance(8.0)
	check(bool(sim.prisoner.freed) and sim.prisoner.follow_id=="hornero","He is up and follows Hornero")
	# The lamp board, Lechuza's.
	var board := Vector2(float(sim.data.radio.x),float(sim.data.radio.y))
	press(hud.portrait_buttons.lechuza)
	put("lechuza",board+Vector2(0,70))
	look(board+Vector2(0,40))
	hud.refresh()
	slot("gun")
	check(order("lechuza")=="sabotage","His third plate sends him to the lamp board")
	advance(8.0)
	check(sim.radio_cut,"The quay's lamps are out")

func alarm() -> void:
	fresh()
	quiet()
	main.auto_command_on_alarm=true
	sim._raise_alarm("spotted",Vector2(600,600))
	main.world.update_visuals(0.05)
	hud.refresh()
	check(sim.paused,"An alarm stops the clock by itself")
	check(hud.planning.visible and hud.alarm_banner.visible and not hud.planning.get_global_rect().intersects(hud.alarm_banner.get_global_rect()),"Command banner and alarm banner show together")
	check(hud.notice.text=="Alarm — orders?" and hud.status.text=="ALARM","The notice asks for orders; the readout says ALARM")
	var lasts: int=int(sim.data.get("alarm",{}).get("duration",20))
	check(hud._frame_state&2!=0 and hud._alarm_second==lasts,"Red edge and the level's countdown (%d, want %d)" % [hud._alarm_second,lasts])
	slot("plan")
	advance(1.0)
	check(not sim.paused and hud._alarm_second<lasts,"EXECUTE resumes, and the same alarm does not stop the clock again")
	check(hud._alarm_line.contains("reinforcements in"),"Reinforcements are announced")
	# No checkpoint while it lasts, and the menu says so.
	press(hud.tools_row.get_child(0))
	await settle()
	check(hud.overlay.visible and hud.current_modal=="menu" and sim.paused,"MENU opens the dossier and stops the clock")
	check(hud.menu_buttons.save.dimmed,"Save is dead during an alarm")
	press(hud.menu_buttons.save)
	check(hud.current_modal=="menu" and hud.modal_body.text.contains("alarm") and sim.checkpoint.label=="start","…and says why")
	press(hud.begin_button)
	check(not hud.overlay.visible and not sim.paused,"RESUME returns to the running game")
	main.auto_command_on_alarm=false
	advance(25.0)
	sim._raise_alarm("body",Vector2(600,600))
	main.world.update_visuals(0.05)
	check(not sim.paused,"With the option off an alarm leaves the clock running")

func checkpoints() -> void:
	fresh()
	quiet()
	press(hud.portrait_buttons.lechuza)
	var start: Vector2=sim.position_of(sim.unit_by_id("lechuza"))
	look(start+Vector2(-80,40))
	tap(start+Vector2(-180,0))
	advance(1.5)
	var saved_at: Vector2=sim.position_of(sim.unit_by_id("lechuza"))
	check(saved_at.distance_to(start)>40.0,"(Lechuza has walked off)")
	press(hud.tools_row.get_child(0))
	await settle()
	check(not hud.menu_buttons.save.dimmed and not hud.menu_buttons.load.dimmed,"All quiet: save and load are live")
	press(hud.menu_buttons.save)
	check(sim.checkpoint.label=="manual" and not hud.overlay.visible and not sim.paused,"SAVE CHECKPOINT saves and returns to the game")
	advance(1.5)
	check(sim.position_of(sim.unit_by_id("lechuza")).distance_to(saved_at)>20.0,"(he walks on)")
	press(hud.tools_row.get_child(0))
	await settle()
	press(hud.menu_buttons.load)
	check(sim.position_of(sim.unit_by_id("lechuza")).distance_to(saved_at)<1.0 and sim.paused and not hud.overlay.visible,"LOAD CHECKPOINT puts him back, in command mode")
	check(int(sim.stats.checkpoints_loaded)==1,"The reload is counted")
	# Restart needs two taps.
	press(hud.tools_row.get_child(0))
	await settle()
	press(hud.menu_buttons.restart)
	check(hud.current_modal=="menu" and sim.time>0.0 and hud.menu_buttons.restart.text=="TAP AGAIN TO RESTART","One tap on RESTART only asks again")
	press(hud.menu_buttons.restart)
	check(sim.phase=="playing" and sim.time==0.0 and not hud.overlay.visible,"The second restarts the mission")
	# Lost: why, retry from the checkpoint, or restart.
	advance(1.0)
	sim._lose("Lechuza was shot dead by a guard.")
	await settle()
	check(hud.overlay.visible and hud.current_modal=="lost" and hud.modal_body.text.contains("Lechuza was shot dead"),"Losing shows why")
	check(hud.begin_button.text=="RETRY FROM CHECKPOINT" and hud.second_button.visible and hud.second_button.text=="RESTART MISSION","Retry is the main button, restart the other")
	press(hud.begin_button)
	check(sim.phase=="playing" and sim.paused and not hud.overlay.visible and hud.planning.visible,"Retry returns to the checkpoint in command mode")
	sim._lose("Biguá was shot dead by a guard.")
	await settle()
	press(hud.second_button)
	check(sim.phase=="playing" and sim.time==0.0 and not sim.paused and not hud.overlay.visible,"RESTART MISSION starts over from the beginning")

## Puts all four on the far bank with the passenger across: the next tick wins.
func win(alarms: int) -> void:
	sim.door_open=true
	sim.prisoner.freed=true
	sim.prisoner.aboard=true
	sim.stats.alarms=alarms
	var far := Vector2(float(sim.data.extraction.x),float(sim.data.extraction.y))
	var i: int=0
	for unit: Dictionary in sim.units:
		put(str(unit.id),far+Vector2(-36.0+24.0*i,0.0))
		i+=1
	sim.update(0.05)
	main.world.update_visuals(0.05)

func results() -> void:
	fresh()
	win(0)
	for i in range(3): await process_frame
	check(sim.phase=="won" and hud.overlay.visible and hud.current_modal=="won","Winning shows the result sheet")
	check(hud.stats_row.visible and hud.badge_row.visible and hud._badges.size()==5 and hud._stats.size()==6,"Six figures and five stamps")
	var typed: bool=true
	for entry: Dictionary in hud._badges:
		if bool(entry.earned): typed=typed and hud.modal_body.text.contains(str(entry.label))
	check(typed and hud.modal_body.text.contains("Ghost"),"The commendations are typed out")
	var unearned: Array=hud._badges.filter(func(e: Dictionary) -> bool: return not bool(e.earned))
	check("ghost" in hud._new_badges and bool(hud.badge_record("ghost").get("earned",false)) and (unearned.is_empty() or hud.badge_record(str(unearned[0].id)).is_empty()),"Earned stamps go on file; the others stay off it")
	var file:=ConfigFile.new()
	check(file.load(PROGRESS)==OK and file.has_section_key(hud.badge_section,"ghost") and file.has_section_key(hud.best_section,"time"),"The progress file is on disk (%s, %s)" % [hud.badge_section,hud.best_section])
	check(hud.view_blocks_fit(),"The sheet fits the screen")
	press(hud.begin_button)
	check(sim.phase=="playing" and sim.time==0.0 and not hud.overlay.visible,"PLAY AGAIN starts a fresh mission")
	advance(1.0)
	win(1)
	for i in range(3): await process_frame
	check(sim.phase=="won" and not sim.badge_earned("ghost"),"(a second win, this time with an alarm)")
	check(not ("ghost" in hud._new_badges) and int(hud.badge_record("ghost").get("runs",0))==1 and int(hud.badge_record("swift").get("runs",0))==2,"Ghost stays on file from the first run; Swift is counted twice (%d)" % int(hud.badge_record("swift").get("runs",0)))
	check(not hud.modal_body.text.contains("Ghost"),"…and is not claimed for this one")
	press(hud.begin_button)

func hints() -> void:
	fresh()
	quiet(["north"])
	for id: String in hud.coach_order: hud.progress.set_value("hints",id,true)
	hud.progress.set_value("hints","far_zone",false)
	hud._hint_until=0.0
	hud.refresh()
	check(not hud.hint_label.visible,"(no hint showing)")
	var g1: Dictionary=place("north",STAGE+Vector2(-150,0),0.0)
	g1.route=[[STAGE.x-150,STAGE.y,60,0],[STAGE.x-148,STAGE.y,60,0]]
	g1.route_index=0
	var bigua: Dictionary=put("bigua",STAGE)
	bigua.stance="sneak"
	sim.select("bigua")
	hud.refresh()
	check(hud.hint_label.visible and hud.hint_label.text==hud.hints.far_zone,"Crouched in a pale outer zone for the first time: the hint (%s)" % hud.hint_label.text)
	hud._hint_until=0.0
	hud.refresh()
	hud.refresh()
	check(not hud.hint_label.visible,"…shown once")
	var file:=ConfigFile.new()
	file.load(PROGRESS)
	check(bool(file.get_value("hints","far_zone",false)) and bool(file.get_value("hints","start",false)),"Seen hints are remembered on disk")

## The first-run coach: one line at a time, each when its moment comes, the first one first; the cellar door's line
## when somebody without the keys stands at it.
func coach() -> void:
	fresh()
	quiet()
	for id: String in hud.coach_order: hud.progress.set_value("hints",id,false)
	hud._hint_until=0.0
	hud.refresh()
	check(not hud.hint_label.visible,"Coach: nothing in the first instant")
	advance(1.0)
	check(hud.hint_label.visible and hud.hint_label.text==hud.hints.start,"Coach: how to play comes first")
	advance(2.0)
	check(hud.hint_label.text==hud.hints.start,"Coach: a line is not cut off by the next one")
	for id: String in hud.coach_order:
		if id!="cell": hud.progress.set_value("hints",id,true)
	hud._hint_until=0.0
	hud.refresh()
	check(not hud.hint_label.visible,"Coach: then quiet until something calls for a line")
	sim.select("benteveo")
	put("benteveo",Vector2(float(sim.data.door.interactX),float(sim.data.door.interactY))+Vector2(-60,40))
	hud.refresh()
	check(hud.hint_label.visible and hud.hint_label.text==hud.hints.cell,"Coach: Benteveo at the cellar door is told who opens it (%s)" % hud.hint_label.text)
	check(hud._obj_how!="","The objective says how: %s" % hud._obj_how)

## Android's Back button: lowers an armed weapon, steps back through the dossier, opens and closes the menu.
func back_button() -> void:
	fresh()
	main._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(hud.overlay.visible and hud.current_modal=="menu" and sim.paused,"Back opens the pause menu")
	main._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(not hud.overlay.visible and not sim.paused,"…and Back again returns to the operation")
	main._command("menu")
	hud._menu_pressed("howto")
	hud.show_card(2)
	main._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(hud.current_modal=="howto" and hud.howto_page==1,"Back turns HOW TO PLAY back a card")
	main._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	main._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(hud.current_modal=="menu","…and from the first card returns to the menu")
	main._command("begin")
	main._slot("melee")
	check(main.armed=="takedown","(a takedown armed)")
	main._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(main.armed=="" and not hud.overlay.visible,"Back lowers what is armed before anything else")

## The browser build: the canvas follows the window (in CSS pixels), the camera shows more of the barrio in a
## bigger window, and taps still land where they should.
func web_layout() -> void:
	main.web_layout=1
	main.screen_scale=2.0
	for dims: Vector2i in [Vector2i(2880,1620),Vector2i(3600,1974),Vector2i(1280,720)]:
		root.size=dims
		for i in range(12): await process_frame
		var css:=Vector2(dims)/2.0
		var want:=Vector2i((css*maxf(main.WEB_DENSITY,maxf(main.LANDSCAPE_MIN_HEIGHT/css.y,(main.TOP_ROW_MIN+36.0)/css.x))).round())
		check(root.content_scale_size==want,"Browser %s: the canvas follows the window (%s, want %s)" % [str(dims),str(root.content_scale_size),str(want)])
		fresh()
		main._update_camera(1.0,true)
		check(is_equal_approx(main.camera.size,main.zoom*main.world_scale) and main.world_scale>=1.0 and main.world_scale<=main.WEB_WORLD_MAX,"…the camera widens by %.2f" % main.world_scale)
		check(hud.view_blocks_fit(),"…and the kit fits: %s" % str(hud.layout_problems()))
	root.size=Vector2i(2880,1620)
	for i in range(12): await process_frame
	fresh()
	var lechuza: Dictionary=sim.unit_by_id("lechuza")
	look(sim.position_of(lechuza))
	tap(sim.position_of(lechuza),0.85)
	check(sim.selected_id=="lechuza","In the browser a click on an operative still selects him")
	main.web_layout=0
	main.screen_scale=0.0
	root.size=Vector2i(1280,720)
	for i in range(12): await process_frame
	check(main.world_scale==1.0 and root.content_scale_size==Vector2i(1280,720),"Back to the app layout: %s, %.2f" % [str(root.content_scale_size),main.world_scale])

## The text-size switch: LARGE shrinks the logical canvas (so everything is drawn bigger), is remembered, and
## every screen still fits on a phone.
func text_sizes() -> void:
	for dims: Vector2i in [Vector2i(844,390),Vector2i(390,844)]:
		root.size=dims
		for i in range(12): await process_frame
		fresh()
		var medium: Vector2i=root.content_scale_size
		main._command("menu")
		for i in range(4): await process_frame
		press(hud.size_rows[0].keys[2])
		for i in range(8): await process_frame
		check(hud.text_size()==2 and root.content_scale_size.y<medium.y and root.content_scale_size.x<medium.x,"LARGE draws the interface bigger at %s (canvas %s, was %s)" % [str(dims),str(root.content_scale_size),str(medium)])
		check(bool(hud.size_rows[0].keys[2].chosen) and not bool(hud.size_rows[0].keys[1].chosen),"…the switch shows it")
		var file:=ConfigFile.new()
		file.load(PROGRESS)
		check(int(file.get_value("settings","text_size",-1))==2,"…and it is remembered")
		check(hud.view_blocks_fit(),"The menu fits with large text at %s: %s" % [str(dims),str(hud.layout_problems())])
		hud.show_modal("howto")
		for i in range(4): await process_frame
		check(hud.view_blocks_fit(),"HOW TO PLAY fits with large text at %s: %s" % [str(dims),str(hud.layout_problems())])
		hud.show_modal("briefing")
		for i in range(4): await process_frame
		check(hud.view_blocks_fit(),"The briefing fits with large text at %s: %s" % [str(dims),str(hud.layout_problems())])
		main._command("begin")
		main._command("pause")
		sim.perform("takedown","sergeant")
		hud.refresh()
		for i in range(4): await process_frame
		check(hud.view_blocks_fit(),"Command mode fits with large text at %s: %s" % [str(dims),str(hud.layout_problems())])
		main._command("pause")
		hud.set_text_size(0)
		for i in range(8): await process_frame
		check(root.content_scale_size.y>medium.y,"SMALL draws it smaller at %s" % str(dims))
		hud.refresh()
		check(hud.view_blocks_fit(),"Play fits with small text at %s: %s" % [str(dims),str(hud.layout_problems())])
		hud.set_text_size(1)
		for i in range(8): await process_frame
		check(root.content_scale_size==medium,"MEDIUM is the default canvas again")

func layouts() -> void:
	for dims: Vector2i in [Vector2i(1280,720),Vector2i(720,1080),Vector2i(844,390),Vector2i(390,844)]:
		root.size=dims
		for i in range(12): await process_frame
		fresh()
		main._command("pause")
		sim.perform("takedown","sergeant")
		hud.refresh()
		check(hud.view_blocks_fit(),"Command mode fits %s: %s" % [str(dims),str(hud.layout_problems())])
		main._slot("tool")
		hud.refresh()
		check(hud.prompt.visible and hud.view_blocks_fit(),"An armed throw fits %s: %s" % [str(dims),str(hud.layout_problems())])
		main._arm("",true)
		main._command("menu")
		for i in range(4): await process_frame
		check(hud.view_blocks_fit(),"The menu fits %s: %s" % [str(dims),str(hud.layout_problems())])
		hud.show_modal("howto")
		for i in range(4): await process_frame
		check(hud.view_blocks_fit(),"HOW TO PLAY fits %s: %s" % [str(dims),str(hud.layout_problems())])
		main._command("begin")

## The Plaza de Mayo through the controls: Juan Salvo's photo before and after he comes, his rifle against a cascarudo.
func plaza() -> void:
	var Missions: GDScript = load("res://scripts/missions.gd")
	var ArtPack: GDScript = load("res://scripts/three_d/art_pack.gd")
	var licensed: bool = bool(ArtPack.slot("juan_salvo").get("ready", false))
	Missions.choose("plaza", false)
	main=load("res://Main.tscn").instantiate()
	root.add_child(main)
	sim=main.sim
	hud=main.hud
	hud.progress_path=PROGRESS
	hud.hints_enabled=false
	for i in range(10): await process_frame
	main._command("begin")
	if sim.paused: sim.toggle_pause()
	hud.refresh()
	await settle()
	var photo: Control=hud.portrait_buttons.salvo
	if licensed: check(photo.photo!=null and str(photo.photo_plate)=="" and str(photo.band)=="ON HIS WAY" and photo.disabled,"Plaza: Juan Salvo's photo is his portrait, ON HIS WAY, not to be tapped")
	else: check(photo.photo==null and str(photo.photo_plate)=="JUAN SALVO" and str(photo.band)=="ON HIS WAY" and photo.disabled,"Plaza: Juan Salvo's photo is a plate with his name (no licensed portrait), ON HIS WAY, not to be tapped")
	var before: String=sim.selected_id
	press(photo)
	check(sim.selected_id==before,"…and a tap on it chooses nobody")
	key(KEY_5)
	check(sim.selected_id==before,"…nor does his key")
	advance(float(sim.unit_by_id("salvo").arrive.at)-float(sim.time)+0.2)
	await settle()
	check(str(photo.band)=="" and not photo.disabled,"He comes: his photo can be tapped")
	press(photo)
	check(sim.selected_id=="salvo" and photo.selected,"A tap on it chooses him")
	var juan: Dictionary=put("salvo",Vector2(150*32,60*32))
	var beast: Dictionary=sim.guard_by_id("c1")
	sim._creature_enters(beast,true)
	beast.x=165*32.0
	beast.y=60*32.0
	beast.path=[]
	beast.think=30.0
	look(Vector2(162*32,61*32))
	advance(0.1)
	await settle()
	check(hud.slots.gun.text=="RIFLE" and hud.slots.gun.symbol=="target" and hud.slots.gun.count==6 and hud.slots.gun.count_max==6,"His bar: the rifle, its six rounds (%s %s %d)" % [hud.slots.gun.text,hud.slots.gun.symbol,hud.slots.gun.count])
	slot("gun")
	check(main.armed=="shoot" and hud._prompt_title.contains("RIFLE ARMED") and hud._prompt_line.contains("cascarudo"),"The rifle armed, in the square's own words: %s" % hud._prompt_line)
	check("c1" in hud._marked,"The cascarudo in range is marked")
	var marked_people: bool=false
	for p: Dictionary in sim.people():
		if str(p.id) in hud._marked: marked_people=true
	check(not marked_people,"…and nobody of the square")
	tap(Vector2(165*32,60*32),1.0)
	check(order("salvo")=="shoot" and target("salvo")=="c1" and main.armed=="","A tap on it fires at it")
	advance(1.2)
	check(int(juan.ammo)==5 and str(beast.state)=="driven","Hit: it is driven off (%s, %d rounds left)" % [beast.state,int(juan.ammo)])
	# …and no word about hiding a body in a bush (the stealth operations' hint): a cascarudo hit leaves none
	hud.hints_enabled=true
	if hud.progress.has_section_key("hints","body"): hud.progress.erase_section_key("hints","body")
	hud.hint_label.text=""
	hud.on_sim_event({"type":"shot","by":"salvo","x":juan.x,"y":juan.y,"tx":beast.x,"ty":beast.y,"loud":true,"hit_id":"c1"})
	check(hud.hint_label.text!=str(hud.hints.get("body","")),"A cascarudo hit gives no hint about bodies and bushes (%s)" % hud.hint_label.text)
	hud.hints_enabled=false
	# a tap on one with nobody armed: he fires; one without a gun says to keep away
	sim._set_state(beast,"prowl")
	beast.x=165*32.0
	beast.y=60*32.0
	beast.path=[]
	beast.think=30.0
	juan.weapon_cooldown=0.0
	advance(0.1)
	await settle()
	tap(Vector2(165*32,60*32),1.0)
	check(order("salvo")=="shoot","Unarmed, a tap on a cascarudo is a shot for Juan Salvo")
	press(hud.portrait_buttons.hornero)
	var hornero: Dictionary=put("hornero",Vector2(158*32,64*32))
	hornero.order={}
	look(Vector2(162*32,61*32))
	advance(0.1)
	await settle()
	tap(Vector2(165*32,60*32),1.0)
	check(order("hornero")=="" and hud.notice.text.contains("Keep away"),"For Hornero, who has nothing to fight it with, a word to keep away: %s" % hud.notice.text)
	# a long label (Lechuza's arcade lights are LUCES DE LA RECOVA in Spanish) leaves its plate the width the bar gave it:
	# the next plate is not laid over its end, and the next operative's bar is not left with a wide plate
	press(hud.portrait_buttons.lechuza)
	await settle()
	for key: String in ["gun","context"]:
		var plate: Control=hud.slots[key]
		plate.text="LUCES DE LA RECOVA DEL CABILDO"
	await process_frame
	var widest: float=0.0
	for key: String in ["stance","melee","gun","tool","context"]:
		var plate: Control=hud.slots[key]
		if plate.visible: widest=maxf(widest,maxf(plate.size.x,plate.get_combined_minimum_size().x))
	check(widest<=hud._bar_slot+0.5,"A long label leaves its plate the bar's width (%d of %d)" % [int(widest),int(hud._bar_slot)])
	main.queue_free()
	await process_frame
	Missions.choose("plaza", false)
