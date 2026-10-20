extends SceneTree
## The world layer's bookkeeping, checked in the real 3D scene of Riachuelo: models and cones stay in step with the
## guards (reinforcements, checkpoint restore), cones follow state and the on-edge range, the cellar door follows the
## rules both ways, order previews and armed-action markers are planned for the right things, and nothing creates
## nodes while the game runs.
## Run: godot --headless --path godot --script res://tests/world_visuals.gd
var main: Node3D
var sim: RefCounted
var world: Node3D
var failures: int=0
var checks: int=0
func _init() -> void:
	call_deferred("run")
func check(value: bool, label_text: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL: "+label_text)
func count_nodes(node: Node) -> int:
	var total: int=1
	for child: Node in node.get_children(): total+=count_nodes(child)
	return total
func step(seconds: float, dt: float=0.05) -> void:
	for i in range(int(round(seconds/dt))):
		sim.update(dt)
		world.update_visuals(dt)
func longest(lengths: PackedFloat32Array) -> float:
	var best: float=0.0
	for value: float in lengths: best=maxf(best,value)
	return best
func shortest(lengths: PackedFloat32Array) -> float:
	var best: float=INF
	for value: float in lengths: best=minf(best,value)
	return best
func marks(shape: int) -> Array:
	return world._attached.filter(func(entry: Array) -> bool: return int(entry[1])==shape)
func run() -> void:
	(load("res://scripts/missions.gd") as GDScript).choose("riachuelo", false)
	main=load("res://Main.tscn").instantiate()
	root.add_child(main)
	main.set("auto_command_on_alarm", false)   # scripted run: never auto-pause on an alarm
	for i in range(8): await process_frame
	sim=main.sim
	world=main.world
	main.set_process(false)          # the test drives the simulation and the visuals itself
	main._command("begin")
	world.update_visuals(0.1)
	# --- models and cones --------------------------------------------------------------------------------
	var guards0: int=sim.guards.size()
	var actors0: int=sim.units.size()+guards0+(1 if sim.has_prisoner else 0)
	check(world.actors.size()==actors0 and world.cone_nodes.size()==guards0,"A model for everyone and a cone for every guard at the start (%d models, %d cones)" % [world.actors.size(),world.cone_nodes.size()])
	check("armed_action" in world and world.armed_action=="","The controls' armed_action hook exists")
	var g: Dictionary=sim.guard_by_id("north")
	check(absf(float(world.cone_nodes.north.material_override.get_shader_parameter("near_m"))-float(g.near)/32.0)<0.001,"A cone's near zone is the guard's")
	check(absf(longest(world.cone_lengths("north"))-float(g.range)/32.0)<0.01,"A calm cone along the street reaches the guard's range")
	var quiet_nodes: int=count_nodes(world)
	check(sim.save_checkpoint(),"A checkpoint in the quiet start")
	var seen: Array[String]=[]
	world.sim_event.connect(func(event: Dictionary) -> void: seen.append(str(event.type)))
	# an alarm: on-edge cones, reinforcements out of the Guardia's post
	sim._raise_alarm("spotted",sim.position_of(g)+Vector2(60,0))
	var first: int=int(sim.data.reinforcements.get("first",2))
	step(float(sim.data.reinforcements.get("delay",6.0))+1.5)
	var extra: Array=[]
	for guard: Dictionary in sim.guards:
		if not world.cone_nodes.has(str(guard.id)): extra.append(str(guard.id))
	var added: Array=[]
	for guard: Dictionary in sim.guards: added.append(str(guard.id))
	added=added.slice(guards0)
	check(sim.guards.size()==guards0+first and extra.is_empty() and added.all(func(id: String) -> bool: return world.actors.has(id)),"Reinforcements get models and cones (%s)" % str(added))
	check(seen.has("alarm_start") and seen.has("reinforcements") and sim.events.is_empty(),"Events are re-emitted and drained")
	g=sim.guard_by_id("north")
	world.update_visuals(0.1)   # (a long frame re-traces every cone at once)
	check(float(g.range)>float(g.base_range) and absf(longest(world.cone_lengths("north"))-float(g.range)/32.0)<0.05,"An on-edge cone grows with the guard's range (%.2f, range %.2f)" % [longest(world.cone_lengths("north")),float(g.range)/32.0])
	check(absf(float(world.cone_nodes.north.material_override.get_shader_parameter("fov"))-deg_to_rad(float(g.fov)))<0.001,"…and widens with his field of view (%.3f, %.3f)" % [float(world.cone_nodes.north.material_override.get_shader_parameter("fov")),deg_to_rad(float(g.fov))])
	check(world.cone_look(g)==2 and (added.is_empty() or world.cone_look(sim.guard_by_id(str(added[0])))==2),"Alarmed guards get the alarm look")
	check(count_nodes(world)>quiet_nodes,"The extra men are extra nodes")
	# cones of downed guards
	sim._fell(sim.guard_by_id("cut"),"dead")
	sim._fell(sim.guard_by_id("middle"),"bound")
	sim._fell(sim.guard_by_id("east"),"stunned")
	world.update_visuals(0.1)
	check(not world.cone_nodes.cut.visible and not world.cone_nodes.middle.visible and not world.cone_nodes.east.visible,"Dead, bound and stunned guards have no cone")
	check(world.cone_nodes.north.visible and world.cone_nodes.sergeant.visible,"Standing guards keep theirs")
	world.draw_vision=false
	world.update_visuals(0.1)
	check(not world.cone_nodes.north.visible,"draw_vision hides every cone")
	world.draw_vision=true
	# the rules props, forward: the cellar door opens with the rules
	var structures: Node3D=world.structures
	check(structures.gate!=null and is_zero_approx(structures.gate.rotation.y),"The cellar door starts shut")
	sim.door_open=true
	step(1.0)
	check(absf(structures.gate.rotation.y)>1.0,"The cellar door swings open with the rules (%.2f)" % structures.gate.rotation.y)
	# back to the checkpoint: everything returns
	check(sim.load_checkpoint(),"The checkpoint loads")
	world.update_visuals(0.1)
	for i in range(3): await process_frame
	world.update_visuals(0.1)
	check(sim.guards.size()==guards0 and world.actors.size()==actors0 and world.cone_nodes.size()==guards0 and added.all(func(id: String) -> bool: return not world.actors.has(id)),"A restore removes the reinforcements' models and cones")
	check(count_nodes(world)==quiet_nodes,"…and leaks no node: %d against %d" % [count_nodes(world),quiet_nodes])
	check(world.cone_nodes.cut.visible and world.cone_nodes.middle.visible,"Restored guards get their cones back")
	check(not sim.door_open,"The cellar door is shut again in the rules")
	step(1.0)
	check(absf(structures.gate.rotation.y)<0.01,"…and in the scene (%.2f)" % structures.gate.rotation.y)
	g=sim.guard_by_id("north")
	check(absf(longest(world.cone_lengths("north"))-float(g.base_range)/32.0)<0.05,"Cones are back to their calm range")
	# --- order previews (command mode) -------------------------------------------------------------------
	check(sim.paused,"The restored level waits in command mode")
	var bigua: Dictionary=sim.unit_by_id("bigua")
	var near: Dictionary=sim.guard_by_id("north")
	near.x=float(bigua.x)-120.0
	near.y=float(bigua.y)+20.0
	near.path=[]
	sim.select("bigua")
	check(sim.order_takedown("north"),"Biguá is ordered to take the north patrolman down")
	sim.select("lechuza")
	check(sim.move_to(sim.position_of(sim.unit_by_id("lechuza"))+Vector2(-90,40)),"Lechuza is ordered to move")
	world.update_visuals(0.1)
	check(world.plan_previews.get("bigua","")=="takedown" and world.plan_previews.get("lechuza","")=="move","Both orders are previewed: "+str(world.plan_previews))
	check(marks(world.BRACKET).any(func(entry: Array) -> bool: return entry[0]=="north"),"The takedown target is bracketed")
	check(world._slow_marks.used>=1 and world._slow_marks.nodes[0].visible,"The move order has its destination marker")
	sim.select("bigua")
	sim.cancel_order()
	sim.select("lechuza")
	sim.cancel_order()
	world.update_visuals(0.1)
	check(world.plan_previews.is_empty() and marks(world.BRACKET).is_empty() and marks(world.RETICLE).is_empty(),"Cancelled orders leave no preview")
	# --- armed action ------------------------------------------------------------------------------------
	sim.select("hornero")
	world.armed_action="distract"
	world.update_visuals(0.02)
	check(world.valid_targets.is_empty() and marks(world.RETICLE).is_empty(),"The armed bell marks no guard")
	world.armed_action=""
	world.update_visuals(0.02)
	check(world.valid_targets.is_empty() and marks(world.RETICLE).is_empty(),"Nothing armed, nothing marked")
	# --- no node is created while the game runs ----------------------------------------------------------
	sim.restart()
	if sim.paused: sim.toggle_pause()
	world.update_visuals(0.1)
	for i in range(3): await process_frame
	var before: int=count_nodes(world)
	sim.select("hornero")
	sim.distract(sim.position_of(sim.unit_by_id("hornero"))+Vector2(-120,40))
	sim.select("lechuza")
	sim.move_to(sim.position_of(sim.unit_by_id("lechuza"))+Vector2(-90,40))
	for i in range(200):
		sim.update(0.016)
		world.update_visuals(0.016)
	check(count_nodes(world)==before,"200 refreshes create no node: %d against %d" % [count_nodes(world),before])
	var all_traced: bool=true
	for guard: Dictionary in sim.guards:
		# (the barrio's people out in the snow look at nobody: they carry no cone to trace)
		if bool(guard.get("civilian", false)) or str(guard.get("kind", "")) == "civilian": continue
		if world.cone_nodes.has(str(guard.id)) and longest(world.cone_lengths(str(guard.id)))<=0.0: all_traced=false
	check(all_traced,"Every cone has been traced by the per-frame budget")
	main.queue_free()
	await process_frame
	print("WORLD_VISUALS_CHECKS=",checks," FAILURES=",failures)
	quit(0 if failures==0 else 1)
