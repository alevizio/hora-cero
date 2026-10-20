extends RefCounted
## A rigged person from the art pack (a model with a person's skeleton and its own clips: stand, walk, run), moved the
## way the game asks on its own skeleton (cutout.gd makes it for a model slot whose skeleton has a person's bones):
##  - its clips, blended by his speed: he walks wherever the squad walks (at its pace, leading people in, carrying
##    someone), his walk played at the squad's stride and cadence for that speed (operative.gd), and runs only when he
##    really runs (from RUN_FROM m/s), his run at the speed it was made for; the two kept in step with each other so the
##    change from one to the other never skips;
##  - for what the clips do not cover, its bones turned here, worked out each frame on top of them:
##     crouched (and sneaking): the hips lowered and drawn back, the back bent over, the knees bent so the feet stay
##       where the clip puts them (two-bone reach of each leg);
##     carrying someone over his shoulder: bent under the weight, his step shorter and slower, the arm on that side over
##       the legs of whoever he carries, the prop (his rifle) hanging from the other hand;
##     aiming and firing: the prop raised to his shoulder and along the line to the target, his shoulders turned into it
##       and his head down to it; each shot kicks it back and up, and he brings it down again;
##     knocked down: thrown back, sitting down hard and flat on his back; then up again by way of sitting and a knee.
##   His arms always reach (two-bone reach) for where its own hands hold the prop, wherever the prop is, so nothing of
##   the model is remade: only its bones are turned.
##   His walk was made for 0.74 m/s and he walks at up to 2.6: his steps lengthen to the squad's stride (scaled to his
##   legs), each foot taken along the clip's own path (measured from it: _measure_walk), drawn out about where the clip
##   centres it and retimed so that it spends a shorter share of the step on the ground as he goes faster (as a brisk
##   walker does); his hips let down as far as his legs need to reach (no more than STRIDE_DROP below his clip's: past
##   that his steps come quicker instead of longer), and each leg reached to it (two-bone reach), so a foot on the ground
##   stays put there as the squad's do.
## The prop's far end (its muzzle) is worked out from its mesh, for the flash of a shot (muzzle()).

## A clip blends into the next over about this long (seconds), as the modellers' player.gd does.
const BLEND: float = 0.16
## The speeds (m/s) its walk and run were made for, unless the slot says (clip_speed).
const WALK_SPEED: float = 0.743
const RUN_SPEED: float = 2.21
## He walks wherever the squad walks (its pace is 2.6 m/s, simulation.gd WALK_SPEED); his run comes in from RUN_FROM and is
## all there is by RUN_FULL (m/s): real running only.
const RUN_FROM: float = 3.0
const RUN_FULL: float = 3.4
## The squad's hips at rest (operative.gd, a figure of height 1): its stride is scaled to his legs by his over theirs.
const SQUAD_HIP: float = 0.95
## How far below where his walk clip has them his hips may go to lengthen his step (m), and the shortest share of a step
## a foot may spend on the ground walking fast (from the clip's own share down to this).
const STRIDE_DROP: float = 0.1
const DUTY_MIN: float = 0.52
## A walk clip whose feet hardly leave the ground (lifted less than SYNTH_LIFT_MIN: a shuffle made in place, as the
## blue-hood model's) has its feet's path drawn instead (_synth_feet): each down and going back for SYNTH_DUTY of the
## cycle over twice SYNTH_HALF (m), then carried forward in an arc SYNTH_LIFT high, half a cycle from the other.
const SYNTH_LIFT_MIN: float = 0.06
const SYNTH_DUTY: float = 0.62
const SYNTH_HALF: float = 0.34
const SYNTH_LIFT: float = 0.11
## How fast (m/s) his hips come back up from the lowest his stride needed: slowly while he walks (a walker's hips bob a
## few centimetres, not as far as his feet spread), quickly once he stops.
const STRIDE_RISE: float = 0.05
const STRIDE_SETTLE: float = 0.8
## Seconds to get back up after being knocked down.
const GET_UP: float = 1.5
## A model's front (the slot's "forward") and the turn that sets it facing +z (as art_pack.gd).
const FORWARDS := {"+z": 0.0, "-z": PI, "+x": -PI / 2.0, "-x": PI / 2.0}

var skel: Skeleton3D
## Canonical (front +z, his right -x, up +y) to the skeleton's own space: the slot's "forward".
var face := Basis.IDENTITY
var n: int = 0
var parent: PackedInt32Array
var order: PackedInt32Array
var rest_p: Array[Vector3] = []
var rest_q: Array[Quaternion] = []
var grest: Array[Transform3D] = []
var lp: Array[Vector3] = []
var lq: Array[Quaternion] = []
var g: Array[Transform3D] = []
## role -> bone: root hips spine chest neck head, arm_r fore_r hand_r arm_l fore_l hand_l, thigh_r shin_r foot_r
## thigh_l shin_l foot_l, prop (any of these may be -1).
var roles: Dictionary = {}
## "idle" / "walk" / "run" -> {"length", "tracks": [[bone, kind (0 position, 1 rotation), Animation, track]]}
var clips: Dictionary = {}
var walk_speed: float = WALK_SPEED
var run_speed: float = RUN_SPEED
## The prop: its muzzle and butt in the prop bone's rest frame, the axis along it and its up, and each hand's hold on
## it (the hand's rest transform relative to the prop bone's).
var has_prop: bool = false
var tip_local := Vector3.ZERO
var butt_local := Vector3.ZERO
var along_local := Vector3(0, 0, 1)
var up_local := Vector3(0, 1, 0)
var grip: String = "r"
var hold: Dictionary = {}
## The other hand's hold while he carries someone: at the prop's middle.
var hang := Transform3D.IDENTITY
## Which side the grip hand is on (-1 his right, +1 his left), canonical.
var grip_side: float = -1.0

var _clock: float = 0.0
var _started: bool = false
var _gait: float = 0.0
var _idle_t: float = 0.0
var _move: float = 0.0
var _run: float = 0.0
var _down_t: float = -1.0
var _up_t: float = -1.0
var _shot_t: float = -1.0
var _last_recoil: float = -1.0
var _g_prop := Transform3D.IDENTITY
## The walk clip's own stride (metres his planted foot travels in one cycle of it), and per foot: where the clip centres
## it along his front (canonical z), its path through a cycle (skeleton space, _STEPS samples), when it comes down
## (cycle share) and the share of the cycle it is down; 0 / empty if it could not be measured.
var walk_reach: float = 0.0
var _foot_mid: Dictionary = {"r": 0.0, "l": 0.0}
var _foot_path: Dictionary = {"r": [], "l": []}
var _foot_on: Dictionary = {"r": 0.0, "l": 0.0}
var _duty: float = 0.6
## How far (times) a foot's travel may be drawn out before his hips must go lower than STRIDE_DROP; his hips' height
## at rest over the squad's.
var _reach_cap: float = 1.0
var _hip_ratio: float = 1.0
## This frame's step: the stride (m per cycle), how far each foot's travel is drawn out, the share of the cycle a foot is
## down (for tests and dev tools).
var step_stride: float = 0.0
var step_reach: float = 1.0
var step_duty: float = 0.6
const _STEPS: int = 48
var _stride_low: float = 0.0

## True if this skeleton has the bones a person is moved by here (hips, a chest, two legs and two arms).
static func fits(sk: Skeleton3D) -> bool:
	if sk == null: return false
	var r: Dictionary = _find_roles(sk, Basis.IDENTITY)
	for role: String in ["hips", "chest", "thigh_r", "shin_r", "foot_r", "thigh_l", "shin_l", "foot_l", "arm_r", "fore_r", "hand_r", "arm_l", "fore_l", "hand_l"]:
		if int(r.get(role, -1)) < 0: return false
	return true

## `slot` (art_pack.gd): its clips (names), clip_speed and forward; `anim`: the model's AnimationPlayer (its clips are
## read here and it is switched off); `prop_mesh`: the prop's mesh (its far end is the muzzle), or null.
func _init(sk: Skeleton3D, slot: Dictionary, anim: AnimationPlayer, prop_mesh: MeshInstance3D) -> void:
	skel = sk
	face = Basis(Vector3.UP, -float(FORWARDS.get(str(slot.get("forward", "+z")), 0.0)))
	n = sk.get_bone_count()
	parent.resize(n)
	for i: int in range(n):
		parent[i] = sk.get_bone_parent(i)
		var r: Transform3D = sk.get_bone_rest(i)
		rest_p.append(r.origin)
		rest_q.append(r.basis.get_rotation_quaternion())
		grest.append(sk.get_bone_global_rest(i))
		lp.append(r.origin)
		lq.append(rest_q[i])
		g.append(grest[i])
	# parents before children
	var placed: Dictionary = {}
	while order.size() < n:
		var added: bool = false
		for i: int in range(n):
			if placed.has(i): continue
			if parent[i] < 0 or placed.has(parent[i]):
				order.append(i)
				placed[i] = true
				added = true
		if not added: break
	roles = _find_roles(sk, face)
	var speeds: Dictionary = slot.get("clip_speed", {}) if slot.get("clip_speed") is Dictionary else {}
	walk_speed = maxf(0.1, float(speeds.get("walk", WALK_SPEED)))
	run_speed = maxf(0.2, float(speeds.get("run", RUN_SPEED)))
	if anim != null:
		_read_clips(anim, slot.get("clips", {}) if slot.get("clips") is Dictionary else {})
		anim.stop()
		anim.active = false
	if prop_mesh != null and _r("prop") >= 0: _read_prop(prop_mesh)
	_measure_walk()

func _r(role: String) -> int:
	return int(roles.get(role, -1))

## The bones by role, from their names (any case): a person's spine and head, and each arm and leg as a chain; which
## side each is on from where it stands at rest (his right is -x when he faces +z), whatever the names say.
static func _find_roles(sk: Skeleton3D, f: Basis) -> Dictionary:
	var names: Array[String] = []
	for i: int in range(sk.get_bone_count()): names.append(sk.get_bone_name(i).to_lower())
	var out: Dictionary = {}
	out["root"] = _named(names, ["root", "armature"], [])
	out["hips"] = _named(names, ["hips", "pelvis", "hip"], [])
	out["spine"] = _named(names, ["spine", "spine1", "abdomen"], [])
	out["chest"] = _named(names, ["chest", "upperchest", "spine2", "thorax"], [])
	if int(out.chest) < 0: out["chest"] = out.spine
	out["neck"] = _named(names, ["neck"], [])
	out["head"] = _named(names, ["head"], [])
	out["prop"] = _named(names, ["prop", "weapon", "gun", "rifle", "item"], [])
	var inv: Basis = f.inverse()
	for limb: Array in [["arm", ["upperarm", "upper_arm", "arm"], ["fore", "lower", "hand", "shoulder"]], ["thigh", ["thigh", "upleg", "upperleg", "upper_leg"], []]]:
		var tops: Array[int] = []
		for i: int in range(names.size()):
			var nm: String = names[i]
			var hit: bool = false
			for k: String in limb[1]:
				if nm.contains(k): hit = true
			for k: String in limb[2]:
				if nm.contains(k): hit = false
			if hit: tops.append(i)
		if tops.size() != 2: continue
		for top: int in tops:
			var x: float = (inv * sk.get_bone_global_rest(top).origin).x
			var side: String = "r" if x < 0.0 else "l"
			var mid: int = _child(sk, top)
			var end: int = _child(sk, mid) if mid >= 0 else -1
			if limb[0] == "arm":
				out["arm_" + side] = top
				out["fore_" + side] = mid
				out["hand_" + side] = end
			else:
				out["thigh_" + side] = top
				out["shin_" + side] = mid
				out["foot_" + side] = end
	return out

static func _named(names: Array[String], exact: Array, _unused: Array) -> int:
	for k: String in exact:
		var i: int = names.find(k)
		if i >= 0: return i
	for k: String in exact:
		for i: int in range(names.size()):
			if names[i].contains(k): return i
	return -1

## A bone's one child that carries the limb on (the first, if several).
static func _child(sk: Skeleton3D, bone: int) -> int:
	if bone < 0: return -1
	var kids: PackedInt32Array = sk.get_bone_children(bone)
	return kids[0] if kids.size() > 0 else -1

## The clips by role (the slot's names, else found by name), and which bone each track moves.
func _read_clips(anim: AnimationPlayer, named: Dictionary) -> void:
	var list: PackedStringArray = anim.get_animation_list()
	for role: String in ["idle", "walk", "run"]:
		var want: String = str(named.get(role, ""))
		var found: String = ""
		for nm: String in list:
			if (want != "" and nm.get_file() == want) or (want == "" and nm.get_file().to_lower().contains(role)):
				found = nm
				break
		if found == "": continue
		var a: Animation = anim.get_animation(found)
		var tracks: Array = []
		for t: int in range(a.get_track_count()):
			var path: String = str(a.track_get_path(t))
			var bone: int = skel.find_bone(path.get_slice(":", path.get_slice_count(":") - 1))
			if bone < 0: continue
			match a.track_get_type(t):
				Animation.TYPE_POSITION_3D: tracks.append([bone, 0, a, t])
				Animation.TYPE_ROTATION_3D: tracks.append([bone, 1, a, t])
		clips[role] = {"length": maxf(a.length, 0.05), "tracks": tracks}

## The walk clip's own stride and each foot's path, from the clip itself: one cycle of it sampled; how fast a foot that
## is down (within a centimetre of its lowest) travels back along his front while it is (as the ground covered in a
## cycle), when each foot comes down and for what share of the cycle; where the clip centres each foot; and how far the
## feet's travel may be drawn out before his hips must go lower than STRIDE_DROP to reach (_reach_cap).
func _measure_walk() -> void:
	_hip_ratio = grest[_r("hips")].origin.y / SQUAD_HIP if _r("hips") >= 0 else 1.0
	if not clips.has("walk"): return
	var steps: int = _STEPS
	var zs: Dictionary = {"r": [], "l": []}
	var ys: Dictionary = {"r": [], "l": []}
	var tops: Dictionary = {"r": [], "l": []}
	var inv: Basis = face.inverse()
	for side: String in ["r", "l"]: _foot_path[side] = []
	for i: int in range(steps):
		for b: int in range(n):
			lp[b] = rest_p[b]
			lq[b] = rest_q[b]
		var walk: Dictionary = _sample("walk", float(i) / steps * _len("walk"))
		for key: Variant in walk:
			var bone: int = int(key) >> 1
			if (int(key) & 1) == 1: lq[bone] = walk[key]
			else: lp[bone] = walk[key]
		_fk()
		for side: String in ["r", "l"]:
			var f: Transform3D = g[_r("foot_" + side)]
			var c: Vector3 = inv * f.origin
			zs[side].append(c.z)
			ys[side].append(c.y)
			tops[side].append(inv * g[_r("thigh_" + side)].origin)
			(_foot_path[side] as Array).append(f)
	var lift: float = 0.0
	for side: String in ["r", "l"]: lift = maxf(lift, float((ys[side] as Array).max()) - float((ys[side] as Array).min()))
	if lift < SYNTH_LIFT_MIN: _synth_feet(steps, zs, ys, inv)
	var travel: float = 0.0
	var share: float = 0.0
	var duty: float = 0.0
	for side: String in ["r", "l"]:
		var low: float = (ys[side] as Array).min()
		var mid: float = 0.0
		for z: float in zs[side]: mid += z
		_foot_mid[side] = mid / steps
		var down: Array[bool] = []
		for i: int in range(steps): down.append(float(ys[side][i]) < low + 0.01)
		var count: int = 0
		for i: int in range(steps):
			if down[i]: count += 1
			if down[i] and not down[(i - 1 + steps) % steps]: _foot_on[side] = float(i) / steps
			var j: int = (i + 1) % steps
			if down[i] and down[j]:
				travel += maxf(0.0, float(zs[side][i]) - float(zs[side][j]))
				share += 1.0
		duty += float(count) / steps * 0.5
	# how far a planted foot goes back in a sample, over a whole cycle: the ground he covers in one (its stride)
	walk_reach = travel / share * steps if share >= steps * 0.3 else 0.0
	_duty = clampf(duty, 0.5, 0.8)
	# the drop his hips need to reach the feet drawn out k times about their middles, over the cycle (beyond what the
	# clip itself needs)
	var need := func(k: float) -> float:
		var worst: float = -INF
		for side: String in ["r", "l"]:
			var length: float = _leg(side)
			for i: int in range(steps):
				var top: Vector3 = tops[side][i]
				var foot := Vector3(0.0, float(ys[side][i]), float(_foot_mid[side]) + (float(zs[side][i]) - float(_foot_mid[side])) * k)
				foot.x = (inv * (_foot_path[side][i] as Transform3D).origin).x
				var d: Vector3 = foot - top
				var upright: float = sqrt(maxf(length * length - d.x * d.x - d.z * d.z, 0.0))
				worst = maxf(worst, -d.y - upright)
		return worst
	var base: float = maxf(need.call(1.0), 0.0)
	_reach_cap = 1.0
	var k: float = 1.0
	while k < 3.0:
		k += 0.02
		if need.call(k) - base > STRIDE_DROP: break
		_reach_cap = k
	for i: int in range(n):
		lp[i] = rest_p[i]
		lq[i] = rest_q[i]
		g[i] = grest[i]

## A walker's path for each foot in place of a shuffling clip's (see SYNTH_LIFT_MIN), about where the clip centres it
## and as it is turned at the start of the clip: down at its lowest and going back, then lifted forward in an arc.
func _synth_feet(steps: int, zs: Dictionary, ys: Dictionary, inv: Basis) -> void:
	for side: String in ["r", "l"]:
		var low: float = (ys[side] as Array).min()
		var mid: float = 0.0
		for z: float in zs[side]: mid += z
		mid /= steps
		var first: Transform3D = _foot_path[side][0]
		var x: float = (inv * first.origin).x
		var off: float = 0.0 if side == "r" else 0.5
		for i: int in range(steps):
			var ph: float = fposmod(float(i) / steps - off, 1.0)
			var z: float = mid + SYNTH_HALF - 2.0 * SYNTH_HALF * ph / SYNTH_DUTY
			var y: float = low
			if ph >= SYNTH_DUTY:
				var u: float = (ph - SYNTH_DUTY) / (1.0 - SYNTH_DUTY)
				z = mid - SYNTH_HALF + 2.0 * SYNTH_HALF * smoothstep(0.0, 1.0, u)
				y = low + SYNTH_LIFT * sin(PI * u)
			zs[side][i] = z
			ys[side][i] = y
			_foot_path[side][i] = Transform3D(first.basis, face * Vector3(x, y, z))

## A leg's reach from the hip to the ankle, as two-bone reach leaves it (a little short of straight).
func _leg(side: String) -> float:
	var thigh: int = _r("thigh_" + side)
	var shin: int = _r("shin_" + side)
	var foot: int = _r("foot_" + side)
	return (grest[shin].origin.distance_to(grest[thigh].origin) + grest[foot].origin.distance_to(grest[shin].origin)) * 0.985

## The squad's stride (m per cycle of two steps) at a speed, crouched and carrying, as operative.gd walks them, scaled to
## his legs.
func _squad_stride(speed: float, crouch: float, carry: float) -> float:
	var u: float = smoothstep(1.35, 2.3, speed)
	var upright: float = lerpf(clampf(0.72 + 0.42 * speed, 0.9, 1.4), 0.82 + 0.36 * speed, u)
	return lerpf(lerpf(upright, 0.58 + 0.38 * speed, crouch), 1.02, carry) * _hip_ratio

## A foot's place at a time in the walk (cycle share), its time on the ground retimed from the clip's share to `duty`:
## the clip's own path (skeleton space), sampled smoothly.
func _foot_at(side: String, phase: float, duty: float) -> Transform3D:
	var path: Array = _foot_path[side]
	var r: float = fposmod(phase - float(_foot_on[side]), 1.0)
	var q: float = r * _duty / duty if r < duty else _duty + (r - duty) * (1.0 - _duty) / maxf(1.0 - duty, 0.01)
	var at: float = fposmod(float(_foot_on[side]) + q, 1.0) * path.size()
	var i: int = int(at) % path.size()
	return (path[i] as Transform3D).interpolate_with(path[(i + 1) % path.size()], at - floorf(at))

## The prop's mesh, as it lies at rest: its two ends (the far one, from the grip hand, is the muzzle), the axis along
## it, and each hand's hold on it.
func _read_prop(mesh_i: MeshInstance3D) -> void:
	var prop: int = _r("prop")
	var arrays: Array = mesh_i.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty(): return
	var to_prop: Transform3D = grest[prop].affine_inverse()
	# the long axis: from the vertex farthest from the middle to the one farthest from it
	var mid := Vector3.ZERO
	for v: Vector3 in verts: mid += v
	mid /= verts.size()
	var a: Vector3 = verts[0]
	for v: Vector3 in verts:
		if v.distance_squared_to(mid) > a.distance_squared_to(mid): a = v
	var b: Vector3 = verts[0]
	for v: Vector3 in verts:
		if v.distance_squared_to(a) > b.distance_squared_to(a): b = v
	var axis: Vector3 = (b - a).normalized()
	# the ends: the mean of the tenth of the vertices at each end, along the axis
	var lo_t: float = INF
	var hi_t: float = -INF
	for v: Vector3 in verts:
		lo_t = minf(lo_t, axis.dot(v))
		hi_t = maxf(hi_t, axis.dot(v))
	var span: float = hi_t - lo_t
	var end_a := Vector3.ZERO
	var end_b := Vector3.ZERO
	var na: int = 0
	var nb: int = 0
	for v: Vector3 in verts:
		var t: float = axis.dot(v)
		if t < lo_t + span * 0.08:
			end_a += v
			na += 1
		elif t > hi_t - span * 0.08:
			end_b += v
			nb += 1
	end_a /= maxi(na, 1)
	end_b /= maxi(nb, 1)
	# the butt is the broad end (a stock), the muzzle the thin one (a barrel): how far each end's vertices spread about
	# the axis. A prop whose ends are much alike has its butt at the end nearer a hand. The grip hand is the one nearer
	# the butt.
	var thick_a: float = 0.0
	var thick_b: float = 0.0
	for v: Vector3 in verts:
		var t: float = axis.dot(v)
		if t < lo_t + span * 0.08:
			var d: Vector3 = v - end_a
			thick_a = maxf(thick_a, (d - axis * axis.dot(d)).length())
		elif t > hi_t - span * 0.08:
			var d: Vector3 = v - end_b
			thick_b = maxf(thick_b, (d - axis * axis.dot(d)).length())
	var hr: Vector3 = grest[_r("hand_r")].origin
	var hl: Vector3 = grest[_r("hand_l")].origin
	var a_is_butt: bool = minf(hr.distance_to(end_a), hl.distance_to(end_a)) <= minf(hr.distance_to(end_b), hl.distance_to(end_b))
	if maxf(thick_a, thick_b) > 1.5 * minf(thick_a, thick_b): a_is_butt = thick_a > thick_b
	var butt: Vector3 = end_a if a_is_butt else end_b
	var tip: Vector3 = end_b if a_is_butt else end_a
	grip = "r" if hr.distance_to(butt) <= hl.distance_to(butt) else "l"
	grip_side = -1.0 if grip == "r" else 1.0
	butt_local = to_prop * butt
	tip_local = to_prop * tip
	along_local = (to_prop.basis * (tip - butt)).normalized()
	# its up: the way the mesh stands out from its axis most, toward the world's up at rest
	var up: Vector3 = to_prop.basis * Vector3.UP
	up_local = (up - along_local * along_local.dot(up)).normalized()
	for side: String in ["r", "l"]:
		hold[side] = grest[prop].affine_inverse() * grest[_r("hand_" + side)]
	# carrying someone, the other hand holds it at its middle (_prop_hanging): that hand's grip slid along it to there
	var h: Transform3D = hold["l" if grip == "r" else "r"]
	hang = Transform3D(h.basis, h.origin + along_local * ((tip_local - butt_local).length() * 0.5 - along_local.dot(h.origin - butt_local)))
	has_prop = true

## The muzzle (skeleton space) as posed this frame; Vector3.INF without a prop.
func muzzle_local() -> Vector3:
	return _g_prop * tip_local if has_prop else Vector3.INF

# ------------------------------------------------------------------------------------------------ the frame
## Poses the skeleton for this frame. `p` (cutout.gd, from operative.gd): clock (s), move (0..1), speed (m/s), crouch
## (0..1), hold (0..1: carrying someone), aim (0..1), pitch (rad, up to the target), recoil (s since a shot, or < 0),
## down (0..1: knocked down).
func pose(p: Dictionary) -> void:
	var clock: float = float(p.get("clock", 0.0))
	var dt: float = clampf(clock - _clock, 0.0, 0.1) if _started else 0.0
	_clock = clock
	var down: bool = float(p.get("down", 0.0)) > 0.5
	if not _started:
		_started = true
		if down: _down_t = 5.0
	# --- knocked down, and up again
	if down:
		_up_t = -1.0
		_down_t = 0.0 if _down_t < 0.0 else _down_t + dt
	elif _down_t >= 0.0:
		_down_t = -1.0
		_up_t = 0.0
	elif _up_t >= 0.0:
		_up_t += dt
		if _up_t > GET_UP: _up_t = -1.0
	var carry: float = clampf(float(p.get("hold", 0.0)), 0.0, 1.0)
	var crouch: float = clampf(float(p.get("crouch", 0.0)), 0.0, 1.0)
	var aim: float = clampf(float(p.get("aim", 0.0)), 0.0, 1.0)
	var pitch: float = clampf(float(p.get("pitch", 0.0)), -0.6, 0.6)
	var speed: float = maxf(float(p.get("speed", 0.0)), 0.0)
	var move_to: float = clampf(float(p.get("move", 0.0)), 0.0, 1.0)
	var lying: float = _lying()
	if lying > 0.0:
		move_to *= 1.0 - lying
		aim *= 1.0 - lying
		crouch *= 1.0 - lying
		carry *= 1.0 - lying
	# --- the clips' weights: moving or standing, walking or running (never running bowed under a load or crouched)
	var k: float = 1.0 - exp(-dt / BLEND) if dt > 0.0 else 1.0
	_move = lerpf(_move, move_to, k)
	var run_to: float = smoothstep(RUN_FROM, RUN_FULL, speed) * (1.0 - carry) * (1.0 - crouch)
	_run = lerpf(_run, run_to, k)
	# in step: walking, the squad's stride for his speed (scaled to his legs), as far as his legs reach it: each foot's
	# travel drawn out (reach) and its time on the ground shortened (duty) toward it; past what his legs reach, quicker
	# steps instead of longer ones. Running, his run's own stride.
	var walk_stride: float = walk_speed * _len("walk")
	var duty: float = _duty
	var reach: float = 1.0
	if walk_reach > 0.0:
		var want: float = _squad_stride(maxf(speed, 0.05), crouch, carry) / walk_reach
		duty = clampf(_duty * _reach_cap / maxf(want, 0.001), minf(DUTY_MIN, _duty), _duty)
		reach = clampf(want * duty / _duty, 0.6, _reach_cap)
		walk_stride = reach * walk_reach * _duty / duty
	step_stride = walk_stride
	step_reach = reach
	step_duty = duty
	var stride: float = lerpf(walk_stride, run_speed * _len("run"), _run)
	var natural: float = lerpf(1.0 / _len("walk"), 1.0 / _len("run"), _run)
	var cadence: float = clampf(speed / maxf(stride, 0.05), natural * 0.3, natural * 2.5)
	if _move > 0.01: _gait = fposmod(_gait + cadence * dt, 1.0)
	_idle_t = fposmod(_idle_t + dt, _len("idle"))
	# --- from the rest pose, the clips
	for i: int in range(n):
		lp[i] = rest_p[i]
		lq[i] = rest_q[i]
	_clips()
	# --- what the clips do not have
	var spine: int = _r("spine")
	var chest: int = _r("chest")
	var head: int = _r("head")
	var neck: int = _r("neck")
	var recoil: float = float(p.get("recoil", -1.0))
	var kick: float = smoothstep(0.0, 0.03, recoil) * exp(-recoil * 9.0) if recoil >= 0.0 else 0.0
	var bolt: float = _span(recoil, 0.25, 0.4, 0.6, 0.9) if recoil >= 0.0 else 0.0
	# bowed under a load
	_bend(spine, Vector3.RIGHT, 0.12 * carry)
	_bend(chest, Vector3.RIGHT, 0.10 * carry)
	_bend(head, Vector3.RIGHT, -0.12 * carry)
	# crouched: bent over, looking ahead
	_bend(spine, Vector3.RIGHT, 0.30 * crouch)
	_bend(chest, Vector3.RIGHT, 0.10 * crouch)
	_bend(head, Vector3.RIGHT, -0.28 * crouch)
	# aiming: the shoulders turned into the shot (the hand on the fore-end forward), the head down to the sights and
	# still on the target; leaning back to aim high; the shot rocks him
	var twist: float = 0.46 * aim * grip_side * -1.0
	_bend(spine, Vector3.UP, -twist * 0.45)
	_bend(chest, Vector3.UP, -twist * 0.55)
	_bend(head if neck < 0 else neck, Vector3.UP, twist * 0.6)
	_bend(head, Vector3.UP, twist * 0.4)
	_bend(head, Vector3.RIGHT, 0.12 * aim)
	_bend(chest, Vector3.RIGHT, (-pitch * 0.6 - 0.08 * kick) * aim)
	_bend(spine, Vector3.RIGHT, 0.04 * aim)
	# where his feet are, from the clips, before the hips go down; walking, each foot along the clip's own path at its
	# retimed share of the step, its travel drawn out to his stride about where the clip centres it (the foot on the
	# ground keeps its place), and the hips let down as far as his legs need to reach them
	_fk()
	var feet: Dictionary = {}
	var hips: int = _r("hips")
	var walking: float = _move * (1.0 - _run) if _down_t < 0.0 and _up_t < 0.0 else 0.0
	var paced: bool = walking > 0.01 and walk_reach > 0.0 and not (_foot_path.r as Array).is_empty()
	var inv: Basis = face.inverse()
	var stride_drop: float = 0.0
	for side: String in ["r", "l"]:
		var foot: int = _r("foot_" + side)
		var f: Transform3D = g[foot]
		if paced:
			var w: Transform3D = _foot_at(side, _gait, duty)
			var c: Vector3 = inv * w.origin
			c.z = float(_foot_mid[side]) + (c.z - float(_foot_mid[side])) * reach
			w.origin = face * c
			f = f.interpolate_with(w, walking)
			var top: Vector3 = g[_r("thigh_" + side)].origin
			var d: Vector3 = inv * (f.origin - top)
			var length: float = _leg(side)
			var upright: float = sqrt(maxf(length * length - d.x * d.x - d.z * d.z, 0.0))
			stride_drop = maxf(stride_drop, -d.y - upright)
		feet[side] = f
	# the lowest his stride has needed of late, coming back up slowly (his hips bob a little, not with every spread of his
	# feet); then the lower of his posture's (crouched, bowed under a load) and his stride's
	_stride_low = maxf(stride_drop, _stride_low - dt * lerpf(STRIDE_SETTLE, STRIDE_RISE, walking))
	var drop: float = maxf((0.36 * crouch + 0.06 * carry) * lerpf(1.0, 0.7, _move), _stride_low)
	if drop > 0.0001:
		lp[hips] += Vector3(0, -drop, 0) + face * Vector3(0, 0, -0.10 * crouch)
	# knocked down / getting up: the whole of him about the hips, and his limbs, toward the keyed poses
	if lying > 0.0 or _down_t >= 0.0 or _up_t >= 0.0:
		_fallen(clock)
	_fk()
	# the legs bend to keep the feet where they were (not on the ground), or where his stride sets them
	if (drop > 0.0001 or paced) and _down_t < 0.0 and _up_t < 0.0:
		for side: String in ["r", "l"]:
			var f: Transform3D = feet[side]
			_reach(_r("thigh_" + side), _r("shin_" + side), _r("foot_" + side), f.origin, g[_r("thigh_" + side)].origin + face * Vector3(0, -0.2, 1.0), face * Vector3.RIGHT)
			_set_global_rot(_r("foot_" + side), f.basis)
		_fk()
	# --- the prop and the hands on it
	if has_prop:
		var prop: int = _r("prop")
		# (lying on his back he holds it down on his chest)
		var carried := Transform3D(Basis(lq[prop]), lp[prop] + face * Vector3(0, 0.06, -0.2) * lying)
		var gp: Transform3D = g[parent[prop]] * carried if parent[prop] >= 0 else carried
		if carry > 0.0: gp = gp.interpolate_with(_prop_hanging(), carry)
		if aim > 0.0: gp = gp.interpolate_with(_prop_aimed(pitch, kick, bolt), aim)
		_g_prop = gp
		var hand_g: Transform3D = gp * (hold[grip] as Transform3D)
		var other: String = "l" if grip == "r" else "r"
		var hand_o: Transform3D = gp * (hold[other] as Transform3D).interpolate_with(hang, carry)
		var c_g: Transform3D = g[chest]
		if carry > 0.0:
			# the grip arm over the legs of whoever rides on that shoulder (operative.gd carry_xf: the right)
			var over := Transform3D(c_g.basis * face * Basis(Vector3.RIGHT, -1.2) * face.inverse(), c_g * (face * Vector3(grip_side * 0.12, 0.1, 0.22)))
			hand_g = hand_g.interpolate_with(over, carry)
		# the elbows toward where they are at rest; aiming, the grip elbow up and out, the other under the fore-end
		# (carrying, the elbow down and ahead of him, the forearm up over the legs on his shoulder)
		var pole_g: Vector3 = _elbow(grip, c_g) + c_g.basis * (face * (Vector3(grip_side * (0.25 + 0.2 * aim), 0.3 * aim, -0.1 * aim) * (1.0 - carry) + Vector3(grip_side * 0.08, -0.3, 0.4) * carry))
		var pole_o: Vector3 = _elbow(other, c_g) + c_g.basis * (face * Vector3(-grip_side * 0.2, -0.25 * aim - 0.2 * carry, 0.15 * aim))
		_reach(_r("arm_" + grip), _r("fore_" + grip), _r("hand_" + grip), hand_g.origin, pole_g, Vector3.ZERO)
		_reach(_r("arm_" + other), _r("fore_" + other), _r("hand_" + other), hand_o.origin, pole_o, Vector3.ZERO)
		_set_global_rot(_r("hand_" + grip), hand_g.basis)
		_set_global_rot(_r("hand_" + other), hand_o.basis)
		var pl: Transform3D = g[parent[prop]].affine_inverse() * gp if parent[prop] >= 0 else gp
		lp[prop] = pl.origin
		lq[prop] = pl.basis.orthonormalized().get_rotation_quaternion()
	for i: int in range(n):
		skel.set_bone_pose_position(i, lp[i])
		skel.set_bone_pose_rotation(i, lq[i])

## Where an arm's elbow is at rest, carried with the chest as posed.
func _elbow(side: String, c_g: Transform3D) -> Vector3:
	return c_g * (grest[_r("chest")].affine_inverse() * grest[_r("fore_" + side)].origin)

func _len(role: String) -> float:
	return float(clips[role].length) if clips.has(role) else 1.0

## The clips at their times, blended: standing and moving, and moving between walking and running.
func _clips() -> void:
	var idle: Dictionary = _sample("idle", _idle_t)
	var walk: Dictionary = _sample("walk", _gait * _len("walk"))
	var run: Dictionary = _sample("run", _gait * _len("run"))
	var keys: Dictionary = {}
	for d: Dictionary in [idle, walk, run]:
		for key: Variant in d: keys[key] = true
	for key: Variant in keys:
		var bone: int = int(key) >> 1
		var is_rot: bool = (int(key) & 1) == 1
		if is_rot:
			var rest: Quaternion = rest_q[bone]
			var qm: Quaternion = (walk.get(key, rest) as Quaternion).slerp(run.get(key, rest), _run)
			lq[bone] = (idle.get(key, rest) as Quaternion).slerp(qm, _move).normalized()
		else:
			var rest: Vector3 = rest_p[bone]
			var pm: Vector3 = (walk.get(key, rest) as Vector3).lerp(run.get(key, rest), _run)
			lp[bone] = (idle.get(key, rest) as Vector3).lerp(pm, _move)

func _sample(role: String, t: float) -> Dictionary:
	var out: Dictionary = {}
	if not clips.has(role): return out
	for tr: Array in clips[role].tracks:
		var a: Animation = tr[2]
		var bone: int = tr[0]
		if int(tr[1]) == 1: out[(bone << 1) | 1] = a.rotation_track_interpolate(tr[3], t).normalized()
		else: out[bone << 1] = a.position_track_interpolate(tr[3], t)
	return out

## Turns a bone about a canonical axis (front +z), in its own frame as it stood at rest.
func _bend(bone: int, axis: Vector3, angle: float) -> void:
	if bone < 0 or absf(angle) < 0.00001: return
	var local_axis: Vector3 = (grest[bone].basis.inverse() * (face * axis)).normalized()
	lq[bone] = (lq[bone] * Quaternion(local_axis, angle)).normalized()

func _fk() -> void:
	for i: int in order:
		var local := Transform3D(Basis(lq[i]), lp[i])
		g[i] = g[parent[i]] * local if parent[i] >= 0 else local

## Sets a bone's turn so that its global basis is `want` (its parent as posed).
func _set_global_rot(bone: int, want: Basis) -> void:
	if bone < 0: return
	var pb: Basis = g[parent[bone]].basis if parent[bone] >= 0 else Basis.IDENTITY
	lq[bone] = (pb.inverse() * want.orthonormalized()).get_rotation_quaternion()
	g[bone] = Transform3D(want.orthonormalized(), g[bone].origin)

## Two-bone reach: turns bone a and its child b so that c (b's child) comes to `target`, bending toward `pole`.
## `bend` is the axis the chain bends about at rest (canonical; ZERO: worked out from its rest shape).
func _reach(a: int, b: int, c: int, target: Vector3, pole: Vector3, bend: Vector3) -> void:
	if a < 0 or b < 0 or c < 0: return
	var u0: Vector3 = grest[b].origin - grest[a].origin
	var v0: Vector3 = grest[c].origin - grest[b].origin
	var l1: float = u0.length()
	var l2: float = v0.length()
	var n0: Vector3 = bend if bend != Vector3.ZERO else u0.cross(v0)
	if n0.length_squared() < 0.000001: n0 = face * Vector3.RIGHT
	var pa: Transform3D = g[parent[a]] if parent[a] >= 0 else Transform3D.IDENTITY
	var at: Vector3 = pa * lp[a]
	var to: Vector3 = target - at
	var dist: float = clampf(to.length(), absf(l1 - l2) + 0.001, (l1 + l2) * 0.999)
	var dir: Vector3 = to.normalized() if to.length_squared() > 0.000001 else (u0 + v0).normalized()
	var cos_a: float = clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var sin_a: float = sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var pp: Vector3 = pole - at
	pp -= dir * dir.dot(pp)
	if pp.length_squared() < 0.000001: pp = dir.cross(face * Vector3.RIGHT)
	pp = pp.normalized()
	var elbow: Vector3 = at + dir * (l1 * cos_a) + pp * (l1 * sin_a)
	var end: Vector3 = at + dir * dist
	var nn: Vector3 = pp.cross(dir).normalized()
	var ra: Basis = _frame(elbow - at, nn) * _frame(u0, n0).transposed()
	var rb: Basis = _frame(end - elbow, nn) * _frame(v0, n0).transposed()
	var ga: Basis = ra * grest[a].basis
	var gb: Basis = rb * grest[b].basis
	lq[a] = (pa.basis.inverse() * ga).orthonormalized().get_rotation_quaternion()
	lq[b] = (ga.inverse() * gb).orthonormalized().get_rotation_quaternion()
	g[a] = Transform3D(ga, at)
	g[b] = Transform3D(gb, elbow)
	g[c] = Transform3D(g[c].basis, end)

static func _frame(x: Vector3, nrm: Vector3) -> Basis:
	var ax: Vector3 = x.normalized()
	var ay: Vector3 = (nrm - ax * ax.dot(nrm)).normalized()
	return Basis(ax, ay, ax.cross(ay))

## The prop raised to the grip shoulder and along the line to the target (pitch up), kicked back and up by a shot and
## dipped while he works the action.
func _prop_aimed(pitch: float, kick: float, bolt: float) -> Transform3D:
	var dir: Vector3 = face * Vector3(0, sin(pitch), cos(pitch))
	var up: Vector3 = face * Vector3(0, cos(pitch), -sin(pitch))
	var b: Basis = _frame(dir, up) * _frame(along_local, up_local).transposed()
	var turn: Vector3 = dir.cross(up).normalized()
	b = Basis(turn, 0.24 * kick - 0.16 * bolt) * b
	var c_g: Transform3D = g[_r("chest")]
	var butt: Vector3 = c_g * (face * Vector3(grip_side * 0.13, 0.05, 0.13)) - dir * (0.07 * kick + 0.04 * bolt)
	return Transform3D(b, butt - b * butt_local)

## The prop hanging from the other hand while he carries someone: held at its middle, pointing down ahead of him.
func _prop_hanging() -> Transform3D:
	var c_g: Transform3D = g[_r("chest")]
	var hand: Vector3 = c_g * (face * Vector3(-grip_side * 0.31, -0.46, 0.10))
	var dir: Vector3 = c_g.basis * (face * Vector3(-grip_side * 0.08, -0.62, 0.78)).normalized()
	var up: Vector3 = c_g.basis * (face * Vector3(-grip_side * 0.5, 0.6, 0.5))
	var b: Basis = _frame(dir, up) * _frame(along_local, up_local).transposed()
	return Transform3D(b, hand - b * hang.origin)

# ------------------------------------------------------------------------------------------------ knocked down
## How flat on the ground he is (0..1), for the clips and the arms.
func _lying() -> float:
	if _down_t >= 0.0: return smoothstep(0.1, 0.5, _down_t)
	if _up_t >= 0.0: return 1.0 - smoothstep(0.2, 1.2, _up_t)
	return 0.0

## The keyed poses of a fall and of getting up, blended in order over the clips: the whole of him turned about the
## hips and set down ("tilt", "seat": the hips' place), and his spine and legs turned (canonical axes, radians).
const POSES := {
	"stagger": {"tilt": Vector3(-0.38, 0, 0), "seat": Vector3(0, 0.84, -0.22),
		"bones": {"spine": Vector3(-0.2, 0, 0), "chest": Vector3(-0.1, 0, 0), "head": Vector3(0.25, 0, 0),
			"thigh_r": Vector3(-0.35, 0, 0), "shin_r": Vector3(0.3, 0, 0), "thigh_l": Vector3(0.15, 0, 0), "shin_l": Vector3(0.25, 0, 0)}},
	"sit": {"tilt": Vector3(-0.16, 0, 0), "seat": Vector3(0, 0.17, -0.12),
		"bones": {"spine": Vector3(-0.12, 0, 0), "chest": Vector3(0.05, 0, 0), "head": Vector3(0.12, 0, 0),
			"thigh_r": Vector3(-1.38, 0.06, 0), "shin_r": Vector3(0.75, 0, 0), "foot_r": Vector3(-0.25, 0, 0),
			"thigh_l": Vector3(-1.5, -0.1, 0), "shin_l": Vector3(0.3, 0, 0), "foot_l": Vector3(-0.35, 0, 0)}},
	"lie": {"tilt": Vector3(-1.46, 0, 0.22), "seat": Vector3(0, 0.22, -0.42),
		"bones": {"spine": Vector3(0.04, 0, 0), "chest": Vector3(-0.06, 0.12, 0), "head": Vector3(-0.15, 0.55, 0),
			"thigh_r": Vector3(-0.62, 0.1, 0), "shin_r": Vector3(1.15, 0, 0), "foot_r": Vector3(-0.3, 0, 0),
			"thigh_l": Vector3(-0.1, -0.08, 0), "shin_l": Vector3(0.22, 0, 0), "foot_l": Vector3(-0.5, 0, 0)}},
	"kneel": {"tilt": Vector3(0.12, 0, 0), "seat": Vector3(0, 0.5, -0.12),
		"bones": {"spine": Vector3(0.28, 0, 0), "chest": Vector3(0.08, 0, 0), "head": Vector3(-0.25, 0, 0),
			"thigh_l": Vector3(-1.42, -0.12, 0), "shin_l": Vector3(1.45, 0, 0), "foot_l": Vector3(0.0, 0, 0),
			"thigh_r": Vector3(0.32, 0.08, 0), "shin_r": Vector3(1.6, 0, 0), "foot_r": Vector3(0.55, 0, 0)}},
}

func _fallen(clock: float) -> void:
	var w: Array = []
	if _down_t >= 0.0:
		var t: float = _down_t
		w = [["stagger", _span(t, 0.0, 0.08, 0.12, 0.3)], ["sit", _span(t, 0.1, 0.24, 0.3, 0.55)], ["lie", smoothstep(0.26, 0.62, t)]]
	elif _up_t >= 0.0:
		var s: float = _up_t
		w = [["lie", 1.0 - smoothstep(0.0, 0.42, s)], ["sit", _span(s, 0.0, 0.32, 0.45, 0.72)], ["kneel", _span(s, 0.45, 0.78, 1.0, GET_UP)]]
	# (each pose laid over the one before it: the fading one first, the coming one over it)
	var hips: int = _r("hips")
	var hips_at: Vector3 = lp[hips]
	var tilt := Quaternion.IDENTITY
	var seat: Vector3 = hips_at
	for entry: Array in w:
		var weight: float = clampf(float(entry[1]), 0.0, 1.0)
		if weight <= 0.0: continue
		var key: Dictionary = POSES[entry[0]]
		var e: Vector3 = key.tilt
		var q := Quaternion(face * Vector3.RIGHT, e.x) * Quaternion(face * Vector3.UP, e.y) * Quaternion(face * Vector3.BACK, e.z)
		tilt = tilt.slerp(q, weight)
		seat = seat.lerp(face * (key.seat as Vector3), weight)
		var bones: Dictionary = key.bones
		for role: String in bones:
			var bone: int = _r(role)
			if bone < 0: continue
			var r: Vector3 = bones[role]
			# a leg's sideways turn mirrors from one side to the other
			var mirror: float = -1.0 if role.ends_with("_l") else 1.0
			var want: Quaternion = rest_q[bone] * Quaternion(_axis(bone, Vector3.RIGHT), r.x) * Quaternion(_axis(bone, Vector3.UP), r.y * mirror) * Quaternion(_axis(bone, Vector3.BACK), r.z * mirror)
			lq[bone] = lq[bone].slerp(want, weight)
	# lying there: a slow breath, the head rolling
	if _down_t > 0.6:
		_bend(_r("chest"), Vector3.RIGHT, 0.04 * sin(clock * 1.6))
		_bend(_r("head"), Vector3.UP, 0.18 * sin(clock * 0.7))
	var root: int = _r("root")
	if root >= 0 and root != hips and _is_above(root, hips):
		lq[root] = tilt
		lp[root] = seat - tilt * hips_at
	else:
		# no root bone above the hips: the hips carry the whole of him
		lq[hips] = (tilt * lq[hips]).normalized()
		lp[hips] = seat

func _axis(bone: int, axis: Vector3) -> Vector3:
	return (grest[bone].basis.inverse() * (face * axis)).normalized()

func _is_above(top: int, bone: int) -> bool:
	var b: int = parent[bone]
	while b >= 0:
		if b == top: return true
		b = parent[b]
	return false

## A window: rises over [a, b], holds, falls over [c, d].
static func _span(x: float, a: float, b: float, c: float, d: float) -> float:
	return smoothstep(a, b, x) * (1.0 - smoothstep(c, d, x))
