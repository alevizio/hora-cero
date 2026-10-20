extends SceneTree
## Dev-only (not shipped): photographs a mission straight down, in tiles, so its picture can be laid against what
## the simulation treats as solid (tools/dev/collision_overlay.py draws obstacles, barriers and bushes over it).
## Anything you can see that is not outlined is something the figures walk through.
## Run: xvfb-run -a godot --path godot --rendering-driver opengl3 --resolution 1200x1200 \
##        --script ../tools/dev/collision_map.gd -- <mission id> <out dir> [tile metres]
const Missions = preload("res://scripts/missions.gd")

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var mission: String = args[0] if args.size() > 0 else "riachuelo"
	var out: String = args[1] if args.size() > 1 else "/tmp/collision"
	var tile: float = float(args[2]) if args.size() > 2 else 15.0
	DirAccess.make_dir_recursive_absolute(out)
	Missions.choose(mission, false)
	var main: Node3D = load("res://Main.tscn").instantiate()
	root.add_child(main)
	for i in range(6): await process_frame
	main._command("begin")
	main.hud.visible = false
	main.world.draw_vision = false
	main.world.overlays.visible = false
	for i in range(4): await process_frame
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = tile
	cam.near = 0.5
	cam.far = 200.0
	cam.rotation_degrees = Vector3(-90, 0, 0)
	root.add_child(cam)
	var w: float = float(main.sim.data.width) / 32.0
	var h: float = float(main.sim.data.height) / 32.0
	var cols: int = int(ceil(w / tile))
	var rows: int = int(ceil(h / tile))
	var meta := {"tile": tile, "cols": cols, "rows": rows, "width": w, "height": h}
	for r in range(rows):
		for c in range(cols):
			cam.position = Vector3((c + 0.5) * tile, 80.0, (r + 0.5) * tile)
			cam.make_current()
			for i in range(5): await process_frame
			await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png(out.path_join("tile_%d_%d.png" % [c, r]))
			print("tile ", c, " ", r)
	var f := FileAccess.open(out.path_join("meta.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta))
	f.close()
	Missions.choose("plaza", false)
	quit()
