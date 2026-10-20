extends RefCounted
## A creature from the art pack, brought to life from what the rules say it is doing (cutout.gd asks it each frame;
## operative.gd passes the creature's state). The whole of it moves (motion(): a transform of its body); and when its
## model has the skeleton tools/art_pack.py rig-creature gives a one-piece sculpt (the cascarudo: a body, a shell, a head
## and six limbs, the front pair big claws), its legs walk (attach(), pose_legs()):
##  - walking: an alternating tripod (each side's front and rear legs with the other side's middle one; for other
##    counts, every other leg down a side, the sides opposed), driven by how far it has actually gone over the ground:
##    each foot lifts, swings forward to where it will be needed and is set down, and a foot on the ground stays where
##    it was put (no skating); the body bobs and sways in step. Turning on the spot, the feet shuffle round. Rushing
##    someone (stalk) it drops lower and pitches forward into a faster scuttle, its claws flung up as it sets off; driven
##    off by a shot, a fast scurry away;
##  - standing: the shell breathes, now and then a leg shifts its footing, a claw or the head twitches;
##  - alerted (it senses someone or a noise draws it): a quick shudder through it;
##  - over someone it has knocked down (stay): the strike (a lunge down at them), then it rears up on its hind legs,
##    its claws raised, the middle legs off the ground, and comes down again before it moves on;
##  - shot (its hits go up): a stagger back, a jolt to one side and a shudder, its feet planted;
##  - dead: thrown back by the last shot, it rolls over onto its back, its legs curling up, twitching less and less.
## Without a skeleton (a static sculpt, the stand-in block) only the body moves, as a crawl.
## Lengths in metres, its own frame: +z its front, +y up, the origin on the ground under its middle; sized from the slot.

## A leg is in the air this share of its cycle (the rest of it on the ground: a little overlap, so a tripod always
## stands).
const SWING: float = 0.42
## A stride (ground covered in one cycle of the gait) and a foot's lift, in shares of the creature's length and height.
const STRIDE: float = 0.3
const LIFT: float = 0.09

var length_m: float = 4.0
var height_m: float = 3.2
var width_m: float = 3.4

var _clock: float = 0.0
var _started: bool = false
var _state: String = ""
var _state_t: float = 0.0
var _hits: int = -1
var _hit_t: float = -1.0
var _hit_side: float = 1.0
var _rush: float = 0.0
var _flee: float = 0.0
var _roll_side: float = 1.0
var _down_t: float = -1.0
var _alert_t: float = -1.0

# --- the legs (a rigged model)
var skel: Skeleton3D
var rigged: bool = false
## The skeleton in the cutout node's frame (the model turned and scaled is the node's own business).
var skel_local := Transform3D.IDENTITY
## Its front, in the skeleton's own space.
var fwd_s := Vector3(0, 0, -1)
## Metres per unit of the skeleton's space.
var unit: float = 1.0
## {name, coxa, tibia, tarsus, hip, knee, ankle, tip, l1, l2, n0, pole, offset, front, middle, side, raised, curl,
##  foot (world), planted, from, target, solo, solo_from}
var legs: Array = []
var bone_shell: int = -1
var bone_head: int = -1
var _gait: float = 0.0
var _last_root := Vector3.ZERO
var _last_yaw: float = 0.0
var _v := Vector3.ZERO
var _w: float = 0.0
var _travel_rate: float = 0.0
var _radius: float = 1.5
var _have_feet: bool = false
var _idle_next: float = 2.0
var _twitch_t: float = -1.0
var _twitch: Vector3 = Vector3.ZERO
var _claw_twitch: Array = [-1.0, -1.0]
var _rng := RandomNumberGenerator.new()
var _dt: float = 0.0

func _init(length: float, height: float, width: float) -> void:
	length_m = maxf(length, 0.5)
	height_m = maxf(height, 0.3)
	width_m = maxf(width, 0.3)
	_rng.seed = 1958

## Takes over a model's own skeleton if it is the kind rig-creature makes (bones <L|R><n>_coxa, _tibia, _tarsus, _tip,
## and shell, head); `local` is the skeleton's transform in the cutout node's frame, `forward` the model's front (its
## own axes), `model_scale` metres per model unit. False (and only the body moves) for any other.
func attach(sk: Skeleton3D, local: Transform3D, forward: Vector3, model_scale: float) -> bool:
	if sk == null: return false
	skel = sk
	skel_local = local
	fwd_s = forward.normalized()
	unit = model_scale
	bone_shell = sk.find_bone("shell")
	bone_head = sk.find_bone("head")
	var left_s: Vector3 = Vector3.UP.cross(fwd_s)
	legs.clear()
	for i: int in range(sk.get_bone_count()):
		var nm: String = sk.get_bone_name(i)
		if not nm.ends_with("_coxa"): continue
		var base: String = nm.trim_suffix("_coxa")
		var tib: int = sk.find_bone(base + "_tibia")
		var tar: int = sk.find_bone(base + "_tarsus")
		var tip: int = sk.find_bone(base + "_tip")
		if tib < 0 or tar < 0 or tip < 0: continue
		var hip: Vector3 = sk.get_bone_global_rest(i).origin
		var knee: Vector3 = sk.get_bone_global_rest(tib).origin
		var ankle: Vector3 = sk.get_bone_global_rest(tar).origin
		var foot: Vector3 = sk.get_bone_global_rest(tip).origin
		var index: int = int(base.substr(1)) if base.substr(1).is_valid_int() else 1
		var side: float = 1.0 if (foot - Vector3(0, foot.y, 0)).dot(left_s) > 0.0 else -1.0
		var leg := {"name": base, "coxa": i, "tibia": tib, "tarsus": tar, "hip": hip, "knee": knee, "ankle": ankle, "tip": foot,
			"index": index, "side": side, "l1": hip.distance_to(knee), "l2": knee.distance_to(ankle),
			"foot": Vector3.ZERO, "planted": true, "from": Vector3.ZERO, "target": Vector3.ZERO, "solo": -1.0, "solo_from": Vector3.ZERO}
		# the knee bends toward where it is at rest, away from the line from hip to ankle (and a little out and up)
		var mid: Vector3 = (hip + ankle) * 0.5
		var out: Vector3 = Vector3(foot.x - hip.x, 0, foot.z - hip.z).normalized()
		leg["pole"] = knee + (knee - mid) + (out + Vector3.UP) * 0.1 * hip.distance_to(ankle)
		var dir: Vector3 = (ankle - hip).normalized()
		var pp: Vector3 = (leg.pole as Vector3) - hip
		pp = (pp - dir * dir.dot(pp)).normalized()
		leg["n0"] = pp.cross(dir).normalized()
		legs.append(leg)
	if legs.size() < 2:
		legs.clear()
		return false
	# front to back on each side
	var per_side: int = 0
	for leg: Dictionary in legs: per_side = maxi(per_side, int(leg.index))
	for leg: Dictionary in legs:
		var n: int = int(leg.index)
		leg["front"] = n == 1
		leg["middle"] = n > 1 and n < per_side
		# the tripod: every other leg down a side, the two sides opposed
		leg["offset"] = 0.5 * float((n - 1 + (0 if float(leg.side) > 0.0 else 1)) % 2)
		var hip: Vector3 = leg.hip
		var foot: Vector3 = leg.tip
		# raised (a claw flung up): up and forward of where it stands, held over the head
		leg["raised"] = foot + Vector3.UP * (hip.y * 0.62) + fwd_s * (0.32 * hip.distance_to(foot))
		# (flung higher as it sets off on a rush than when it rears, the whole of it tipped up already)
		leg["raised_rush"] = foot + Vector3.UP * (hip.y * 1.0) + fwd_s * (0.36 * hip.distance_to(foot))
		# curled (dead): folded in toward the belly
		var c: Vector3 = hip + (foot - hip) * 0.42
		leg["curl"] = Vector3(c.x * 0.75, c.y + 0.12 * hip.y, c.z)
	var r: float = 0.0
	for leg: Dictionary in legs: r += Vector2((leg.tip as Vector3).x, (leg.tip as Vector3).z).length()
	_radius = r / legs.size() * unit
	rigged = true
	return true

## This frame's transform of the creature's body (its own frame). `p`: clock (s), state (the rules'), move (0..1),
## speed (m/s), phase (steps walked, in cycles: for an unrigged model), hits, root and offset (where it stands), yaw.
func motion(p: Dictionary) -> Transform3D:
	var clock: float = float(p.get("clock", 0.0))
	var dt: float = clampf(clock - _clock, 0.0, 0.1) if _started else 0.0
	_clock = clock
	_dt = dt
	var state: String = str(p.get("state", ""))
	var hits: int = int(p.get("hits", 0))
	if not _started:
		_started = true
		_state = state
		# already lying dead (a game loaded), or standing over someone: as it is by now
		_state_t = 10.0
		_hits = hits
	if state != _state:
		# sensing someone, or drawn by a noise: a shudder runs through it
		if (state == "stalk" and _state in ["prowl", "drawn", ""]) or (state == "drawn" and _state in ["prowl", ""]): _alert_t = 0.0
		_state = state
		_state_t = 0.0
		if state == "dead": _roll_side = -1.0 if fposmod(clock * 7.3, 2.0) < 1.0 else 1.0
	else:
		_state_t += dt
	if _alert_t >= 0.0:
		_alert_t += dt
		if _alert_t > 0.6: _alert_t = -1.0
	if hits > _hits and _hits >= 0:
		_hit_t = 0.0
		_hit_side = -1.0 if fposmod(clock * 13.7, 2.0) < 1.0 else 1.0
	elif hits < _hits:
		_hit_t = -1.0
	_hits = hits
	if _hit_t >= 0.0:
		_hit_t += dt
		if _hit_t > 1.2: _hit_t = -1.0
	var k: float = 1.0 - exp(-dt / 0.25) if dt > 0.0 else 1.0
	_rush = lerpf(_rush, 1.0 if state == "stalk" else 0.0, k)
	_flee = lerpf(_flee, 1.0 if state == "driven" else 0.0, k)
	if rigged: _drive(p, dt, state)
	if state == "dead": return _dead(_state_t, clock)
	if float(p.get("lie", 0.0)) > 0.5:
		# down with no state of its own for it (a creature model worn by anyone else): dead all the same
		if _down_t < 0.0: _down_t = 0.0
		_down_t += dt
		return _dead(_down_t, clock)
	_down_t = -1.0
	var move: float = clampf(float(p.get("move", 0.0)), 0.0, 1.0)
	var h: float = height_m
	var still: float = 1.0 - move
	var hurry: float = maxf(_rush, _flee)
	var lift: float
	var roll: float
	var pitch: float
	var yaw: float
	if rigged:
		# carried on its legs: a bob at each tripod's push, a sway toward the tripod on the ground, a small nod
		var cyc: float = _gait * TAU
		var amp: float = clampf(_travel_rate / maxf(0.4, STRIDE * length_m), 0.0, 1.0) * (1.0 + 0.4 * hurry)
		lift = (0.5 - 0.5 * cos(cyc * 2.0)) * 0.012 * h * amp - 0.04 * h * _rush * move
		roll = sin(cyc) * 0.025 * amp
		pitch = sin(cyc * 2.0 + 0.8) * 0.012 * amp - (0.07 * _rush + 0.04 * _flee) * move
		yaw = sin(cyc + 0.4) * 0.015 * amp
	else:
		# a crawl (bigger and lower in a rush)
		var cyc: float = float(p.get("phase", 0.0)) * TAU
		var amp: float = move * (1.0 + 0.6 * hurry)
		lift = absf(sin(cyc * 2.0)) * 0.018 * h * amp - 0.035 * h * _rush * move
		roll = sin(cyc) * 0.05 * amp
		pitch = sin(cyc * 2.0 + 0.6) * 0.025 * amp - (0.07 * _rush + 0.04 * _flee) * move
		yaw = sin(cyc + 0.4) * 0.05 * amp
	var ahead: float = 0.0
	# --- at rest: a slow heave (on a skeleton, the shell breathes instead), the front swaying, now and then a twitch
	var heave: float = sin(clock * 1.25) * still
	lift += (0.003 if rigged else 0.008) * h * heave
	pitch += (0.005 if rigged else 0.012) * heave
	yaw += 0.05 * sin(clock * 0.53 + 1.1) * still * (0.4 if rigged else 1.0)
	var twitch: float = _span(fposmod(clock * 0.19 + 0.3, 1.0), 0.0, 0.02, 0.04, 0.08) * still
	yaw += 0.06 * twitch * sin(clock * 31.0)
	# --- alerted: a shudder
	if _alert_t >= 0.0:
		var sh: float = _span(_alert_t, 0.0, 0.04, 0.3, 0.6)
		roll += 0.035 * sh * sin(_alert_t * 63.0)
		yaw += 0.025 * sh * sin(_alert_t * 51.0 + 1.3)
		lift += 0.006 * h * sh * sin(_alert_t * 77.0)
	# --- setting off on a rush: a lunge
	if state == "stalk":
		var lunge: float = _span(_state_t, 0.0, 0.12, 0.2, 0.55)
		ahead += 0.18 * length_m * lunge
		pitch -= 0.1 * lunge
		lift -= 0.03 * h * lunge
	# --- over the one it knocked down: strike, rear up and stand, come down
	var rear: float = _rear()
	if state == "stay":
		var t: float = _state_t
		var strike: float = _span(t, 0.0, 0.1, 0.18, 0.4)
		ahead += 0.1 * length_m * strike
		pitch -= 0.16 * strike
		var sway: float = rear * smoothstep(0.7, 1.0, t)
		pitch += 0.05 * sin(t * 3.1) * sway
		roll += 0.06 * sin(t * 2.2) * sway
		yaw += 0.10 * sin(t * 1.4) * sway
		ahead += 0.04 * length_m * rear
	# --- shot: a stagger back, a jolt to one side, a shudder
	if _hit_t >= 0.0:
		var jolt: float = smoothstep(0.0, 0.05, _hit_t) * exp(-_hit_t * 4.5)
		ahead -= 0.12 * length_m * jolt
		roll += 0.2 * _hit_side * jolt
		pitch += 0.14 * jolt
		yaw += 0.05 * sin(_hit_t * 42.0) * exp(-_hit_t * 3.0)
	var body := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, roll) * Basis(Vector3.RIGHT, -pitch)
	var xf := Transform3D(body, Vector3(0, lift, ahead))
	if rear > 0.0:
		# reared on its hind end: turned up about the back of it, on the ground
		var pivot := Vector3(0, 0, -0.42 * length_m)
		var up := Transform3D(Basis(Vector3.RIGHT, -0.62 * rear), Vector3.ZERO)
		xf = Transform3D(Basis.IDENTITY, pivot) * up * Transform3D(Basis.IDENTITY, -pivot) * xf
	return xf

## How far up it is reared (0..1): over the one it knocked down.
func _rear() -> float:
	if _state != "stay": return 0.0
	return smoothstep(0.25, 0.8, _state_t) * (1.0 - smoothstep(2.6, 3.3, _state_t))

## How high its front claws are flung (0..1): setting off on a rush, striking, reared.
func _claws_up() -> float:
	if _state == "stalk": return _span(_state_t, 0.0, 0.1, 0.32, 0.62)
	if _state == "stay": return maxf(_span(_state_t, 0.0, 0.05, 0.12, 0.3) * 0.8, smoothstep(0.2, 0.7, _state_t) * (1.0 - smoothstep(2.5, 3.2, _state_t)))
	return 0.0

## Dead: thrown back by the shot, then over onto its back about its length, lying on its shell with its legs up,
## twitching less and less.
func _dead(t: float, clock: float) -> Transform3D:
	var jolt: float = smoothstep(0.0, 0.05, t) * exp(-t * 4.0)
	var over: float = smoothstep(0.2, 1.25, t)
	# a little past its side and on over, to lie a bit tipped (a domed back does not lie square)
	var angle: float = _roll_side * PI * 0.86 * (over * over * (3.0 - 2.0 * over))
	var twitch: float = 0.05 * sin(t * 9.0) * exp(-maxf(t - 1.3, 0.0) * 0.9) * smoothstep(1.2, 1.5, t)
	angle += twitch * _roll_side
	var h2: float = height_m * 0.5
	var w2: float = width_m * 0.5
	# its middle at the height that keeps the lowest of it on the ground (an ellipse round its section), a hop as it
	# goes over
	var rest_h: float = sqrt(pow(h2 * cos(angle), 2.0) + pow(w2 * 0.8 * sin(angle), 2.0))
	var hop: float = 0.12 * height_m * sin(clampf((t - 0.2) / 1.05, 0.0, 1.0) * PI)
	var centre := Vector3(0, h2, 0)
	var roll := Transform3D(Basis(Vector3.BACK, angle) * Basis(Vector3.RIGHT, 0.12 * jolt + 0.04 * twitch), Vector3.ZERO)
	var back: float = -0.15 * length_m * jolt - 0.08 * length_m * over
	return Transform3D(Basis.IDENTITY, Vector3(0, rest_h + hop, back)) * roll * Transform3D(Basis.IDENTITY, -centre)

# ------------------------------------------------------------------------------------------------ the legs
## The gait's clock: how far it has gone over the ground (along it, and round as it turns, at its feet's radius), in
## strides; and its velocity, to send each swinging foot to where it will be needed.
func _drive(p: Dictionary, dt: float, state: String) -> void:
	var root: Vector3 = (p.get("root", Vector3.ZERO) as Vector3) + (p.get("offset", Vector3.ZERO) as Vector3)
	var yaw: float = float(p.get("yaw", 0.0))
	var stride: float = STRIDE * length_m
	if not _have_feet or root.distance_to(_last_root) > 3.0:
		# (put down somewhere else: its feet are set where they belong there)
		_have_feet = false
		_last_root = root
		_last_yaw = yaw
		_v = Vector3.ZERO
		_w = 0.0
		return
	var d := Vector3(root.x - _last_root.x, 0.0, root.z - _last_root.z)
	var dyaw: float = wrapf(yaw - _last_yaw, -PI, PI)
	_last_root = root
	_last_yaw = yaw
	if dt <= 0.0: return
	var k: float = 1.0 - exp(-dt / 0.15)
	_v = _v.lerp(d / dt, k)
	_w = lerpf(_w, dyaw / dt, k)
	var travel: float = d.length() + absf(dyaw) * _radius
	_travel_rate = lerpf(_travel_rate, travel / dt, k)
	if state == "dead": return
	var step: float = travel / stride
	# stopped with a foot in the air: it finishes the step and sets it down
	if travel / dt < 0.05 and _any_swinging():
		step = maxf(step, dt * 1.6)
	_gait += step

func _any_swinging() -> bool:
	for leg: Dictionary in legs:
		if fposmod(_gait - float(leg.offset), 1.0) < SWING: return true
	return false

## Where a foot whose home is `home` (world) should land, `lead` metres of travel from now (its velocity and turn).
func _ahead(home: Vector3, root: Vector3, lead: float) -> Vector3:
	var speed: float = _v.length() + absf(_w) * _radius
	if speed < 0.05: return home
	var t: float = lead / speed
	var rel: Vector3 = (home - root).rotated(Vector3.UP, _w * t)
	return root + rel + _v * t

## Poses the legs for this frame: `rest` is the cutout node's transform as it stands undisturbed (where its feet belong),
## `now` its transform with the body's motion this frame (the feet stay where they are on the ground under it).
func pose_legs(p: Dictionary, rest: Transform3D, now: Transform3D) -> void:
	if not rigged: return
	var clock: float = _clock
	var root: Vector3 = (p.get("root", Vector3.ZERO) as Vector3) + (p.get("offset", Vector3.ZERO) as Vector3)
	var ground: float = (p.get("root", Vector3.ZERO) as Vector3).y
	var w_rest: Transform3D = rest * skel_local
	var w_now: Transform3D = now * skel_local
	var to_skel: Transform3D = w_now.affine_inverse()
	var stride: float = STRIDE * length_m
	var lift_h: float = LIFT * height_m * (1.0 + 0.3 * maxf(_rush, _flee))
	var dead: bool = _state == "dead" or float(p.get("lie", 0.0)) > 0.5
	var t_dead: float = _state_t if _state == "dead" else maxf(_down_t, 0.0)
	var curl: float = smoothstep(0.3, 1.4, t_dead) if dead else 0.0
	var claws: float = _claws_up()
	var rear: float = _rear()
	var shudder: float = _span(_alert_t, 0.0, 0.04, 0.3, 0.6) if _alert_t >= 0.0 else 0.0
	var moving: bool = _travel_rate > 0.05
	# idle: now and then a leg shifts its footing, a claw or the head twitches
	if not moving and not dead and _have_feet:
		_idle_next -= _dt
		if _idle_next <= 0.0:
			_idle_next = _rng.randf_range(2.0, 5.0)
			var pick: Dictionary = legs[_rng.randi_range(0, legs.size() - 1)]
			if float(pick.solo) < 0.0 and not bool(pick.front): _start_solo(pick)
			elif bool(pick.front): _claw_twitch[0 if float(pick.side) > 0.0 else 1] = 0.0
			if _rng.randf() < 0.6: _twitch_t = 0.0
	for leg: Dictionary in legs:
		var home: Vector3 = w_rest * (leg.tip as Vector3)
		home.y = ground
		if not _have_feet:
			leg.foot = home
			leg.planted = true
			leg.solo = -1.0
		var psi: float = fposmod(_gait - float(leg.offset), 1.0)
		var foot: Vector3 = leg.foot
		if dead:
			pass
		elif float(leg.solo) >= 0.0:
			# a step of its own (a shift of footing, or catching up): to its home
			leg.solo = float(leg.solo) + _dt / 0.32
			var u: float = clampf(float(leg.solo), 0.0, 1.0)
			foot = (leg.solo_from as Vector3).lerp(home, _smooth(u)) + Vector3.UP * lift_h * 0.6 * sin(PI * u)
			if float(leg.solo) >= 1.0:
				leg.solo = -1.0
				foot = home
				leg.planted = true
			leg.foot = foot
		elif psi < SWING and (moving or not bool(leg.planted)):
			# in the air: from where it lifted to where it will be needed, over an arc
			if bool(leg.planted):
				leg.planted = false
				leg.from = leg.foot
			var u: float = psi / SWING
			var lead: float = ((SWING - psi) + (1.0 - SWING) * 0.5) * stride
			var target: Vector3 = _ahead(home, root, lead)
			target.y = ground
			leg.target = target
			foot = (leg.from as Vector3).lerp(target, _smooth(u)) + Vector3.UP * lift_h * sin(PI * u)
			leg.foot = foot
		else:
			if not bool(leg.planted):
				leg.planted = true
				leg.foot = leg.target
				foot = leg.target
			# left too far behind (a jump, a sharp turn): it catches up
			if (foot - home).length() > stride * 0.95: _start_solo(leg)
		var tip_s: Vector3 = to_skel * foot
		# the ankle from the foot as it stands at rest, the foot kept level on the ground
		var off_rest: Vector3 = (leg.ankle as Vector3) - (leg.tip as Vector3)
		var off_s: Vector3 = to_skel.basis * (w_rest.basis * off_rest)
		# a claw flung up, a middle leg off the ground as it rears, a leg curled dead: held as the body holds it
		var hold: float = 0.0
		if bool(leg.front) and claws > 0.0:
			var up_s: Vector3 = (leg.raised_rush as Vector3).lerp(leg.raised as Vector3, clampf(rear * 2.0, 0.0, 1.0))
			tip_s = tip_s.lerp(up_s, claws)
			hold = claws
		elif bool(leg.middle) and rear > 0.0:
			tip_s = tip_s.lerp((leg.tip as Vector3) + Vector3.UP * 0.12 * (leg.hip as Vector3).y + fwd_s * 0.1 * (leg.l1 as float), rear)
			hold = rear
		if curl > 0.0:
			var wig: float = 0.06 * sin(t_dead * 7.0 + float(leg.index) * 1.7) * exp(-maxf(t_dead - 1.4, 0.0) * 0.7)
			tip_s = tip_s.lerp((leg.curl as Vector3) + Vector3.UP * wig * (leg.hip as Vector3).y, curl)
			hold = maxf(hold, curl)
		if bool(leg.front):
			var ci: int = 0 if float(leg.side) > 0.0 else 1
			if float(_claw_twitch[ci]) >= 0.0:
				_claw_twitch[ci] = float(_claw_twitch[ci]) + _dt
				var tw: float = _span(float(_claw_twitch[ci]), 0.0, 0.06, 0.14, 0.35)
				tip_s += (Vector3.UP * 0.07 + fwd_s * 0.04) * (leg.hip as Vector3).y * tw
				if float(_claw_twitch[ci]) > 0.4: _claw_twitch[ci] = -1.0
		if shudder > 0.0:
			tip_s += Vector3(sin(clock * 71.0 + float(leg.index)), 0.0, cos(clock * 59.0 + float(leg.side))) * 0.012 * shudder * (leg.hip as Vector3).y
		off_s = off_s.lerp(off_rest, hold)
		_pose_leg(leg, tip_s, tip_s + off_s)
	_have_feet = true
	# the shell breathes; the head twitches now and then
	if bone_shell >= 0:
		var b: float = sin(clock * 1.3) * (0.4 if moving else 1.0)
		skel.set_bone_pose_scale(bone_shell, Vector3(1.0 + 0.010 * b, 1.0 + 0.016 * b, 1.0 + 0.008 * b))
		skel.set_bone_pose_position(bone_shell, skel.get_bone_rest(bone_shell).origin + Vector3.UP * 0.004 * b)
	if bone_head >= 0:
		if _twitch_t >= 0.0:
			if _twitch_t == 0.0: _twitch = Vector3(_rng.randf_range(-0.12, 0.08), _rng.randf_range(-0.18, 0.18), _rng.randf_range(-0.08, 0.08))
			_twitch_t += _dt
			if _twitch_t > 0.45: _twitch_t = -1.0
		var tw: float = _span(_twitch_t, 0.0, 0.05, 0.25, 0.45) if _twitch_t >= 0.0 else 0.0
		var nod: float = -0.18 * _span(_state_t, 0.0, 0.08, 0.2, 0.4) if _state == "stay" else 0.0
		var e: Vector3 = _twitch * tw + Vector3(nod + 0.03 * sin(clock * 2.3) * shudder * 3.0, 0.02 * sin(clock * 0.9), 0.0)
		skel.set_bone_pose_rotation(bone_head, Quaternion.from_euler(e))

func _start_solo(leg: Dictionary) -> void:
	leg.solo = 0.0
	leg.solo_from = leg.foot
	leg.planted = false

## A leg's bones turned so its ankle comes to `ankle` and its foot points to `tip` (the skeleton's space): a two-bone
## reach for hip and knee, bending toward the knee's own side; the foot turned the shortest way from its rest.
func _pose_leg(leg: Dictionary, tip: Vector3, ankle: Vector3) -> void:
	var hip: Vector3 = leg.hip
	var knee0: Vector3 = leg.knee
	var ankle0: Vector3 = leg.ankle
	var tip0: Vector3 = leg.tip
	var l1: float = leg.l1
	var l2: float = leg.l2
	var to: Vector3 = ankle - hip
	var dist: float = clampf(to.length(), absf(l1 - l2) + 0.001, (l1 + l2) * 0.999)
	var dir: Vector3 = to.normalized() if to.length_squared() > 0.000001 else (ankle0 - hip).normalized()
	var cos_a: float = clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var sin_a: float = sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var pp: Vector3 = (leg.pole as Vector3) - hip
	pp -= dir * dir.dot(pp)
	if pp.length_squared() < 0.000001: pp = dir.cross(Vector3.RIGHT)
	pp = pp.normalized()
	var knee: Vector3 = hip + dir * (l1 * cos_a) + pp * (l1 * sin_a)
	var end: Vector3 = hip + dir * dist
	var nn: Vector3 = pp.cross(dir).normalized()
	var n0: Vector3 = leg.n0
	var ra: Basis = _frame(knee - hip, nn) * _frame(knee0 - hip, n0).transposed()
	var rb: Basis = _frame(end - knee, nn) * _frame(ankle0 - knee0, n0).transposed()
	# the foot: from its rest direction to the one it has now
	var rest_dir: Vector3 = (tip0 - ankle0).normalized()
	var want: Vector3 = (tip - end)
	var rc := Basis.IDENTITY
	if want.length_squared() > 0.000001:
		var q := Quaternion(rest_dir, want.normalized()) if rest_dir.dot(want.normalized()) > -0.999 else Quaternion(Vector3.UP, PI)
		rc = Basis(q)
	# rests have no turn: a bone's local turn is its parent's global turn undone (the body's is none)
	skel.set_bone_pose_rotation(int(leg.coxa), ra.orthonormalized().get_rotation_quaternion())
	skel.set_bone_pose_rotation(int(leg.tibia), (ra.inverse() * rb).orthonormalized().get_rotation_quaternion())
	skel.set_bone_pose_rotation(int(leg.tarsus), (rb.inverse() * rc).orthonormalized().get_rotation_quaternion())

static func _frame(x: Vector3, nrm: Vector3) -> Basis:
	var ax: Vector3 = x.normalized()
	var ay: Vector3 = (nrm - ax * ax.dot(nrm)).normalized()
	return Basis(ax, ay, ax.cross(ay))

static func _smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

static func _span(x: float, a: float, b: float, c: float, d: float) -> float:
	return smoothstep(a, b, x) * (1.0 - smoothstep(c, d, x))
