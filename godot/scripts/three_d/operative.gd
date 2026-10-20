extends Node3D
## Procedural 1940s figure. Each outfit is ONE skinned, vertex-coloured mesh (lofted cloth, limbs,
## gear, weapon and tools) on a flat 19-bone rig, so a character costs a single draw call plus its
## shadow pass. Every frame a small analytic animation system poses the rig from the simulation's
## actor dictionary alone:
##  - locomotion: distance-driven gait with IK feet, IK arms, eased blends between stances;
##  - work: weapons (draw, aim, recoil, bolt), tools, takedowns, carrying, wounds;
##  - bodies: key poses in body space (held, falling, lying dead / bound / stunned, carried) laid
##    over the locomotion pose, with the rig tipped onto the ground by the Rig node's transform.
## Paired actions (attacker and held guard, carrier and body) find the partner's model through a
## registry of live instances; nothing but plain values is ever kept from an actor dictionary.
const BODY_SHADER: Shader = preload("res://shaders/character_body.gdshader")
const BLOB_SHADER: Shader = preload("res://shaders/character_blob.gdshader")
const FLASH_SHADER: Shader = preload("res://shaders/character_flash.gdshader")
const Figure := preload("res://scripts/three_d/figure.gd")
## The art pack (drawings and models made by others, with permission) and the paper cut-outs made from its drawings: a
## figure whose data `look` names one ("art:<slot>", or a .png / .glb path) keeps this rig, invisible, for everything it
## does, and shows the cut-out (cutout.gd) in place of the modelled body.
const ArtPack := preload("res://scripts/three_d/art_pack.gd")
const Cutout := preload("res://scripts/three_d/cutout.gd")

enum { HIPS, SPINE, CHEST, HEAD, ARM_L, FORE_L, HAND_L, ARM_R, FORE_R, HAND_R, THIGH_L, SHIN_L, FOOT_L, THIGH_R, SHIN_R, FOOT_R, PROP, TOOL, TOOL_B, BONE_COUNT }
## Joint pivots of the bind pose (metres, arms and legs hanging straight down, facing +Z, left = +X).
const JOINT: Array[Vector3] = [
	Vector3(0, 0.95, 0), Vector3(0, 1.08, 0), Vector3(0, 1.24, 0), Vector3(0, 1.525, -0.005),
	Vector3(0.185, 1.445, 0), Vector3(0.185, 1.15, 0), Vector3(0.185, 0.885, 0),
	Vector3(-0.185, 1.445, 0), Vector3(-0.185, 1.15, 0), Vector3(-0.185, 0.885, 0),
	Vector3(0.095, 0.93, 0), Vector3(0.095, 0.50, 0), Vector3(0.095, 0.085, 0),
	Vector3(-0.095, 0.93, 0), Vector3(-0.095, 0.50, 0), Vector3(-0.095, 0.085, 0),
	Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
const L_ARM: float = 0.295
const L_FORE: float = 0.265
const L_THIGH: float = 0.43
const L_SHIN: float = 0.415
const ANKLE: float = 0.085
const BALL: float = 0.12 # ankle-to-ball-of-foot distance, the pivot while the heel is up
# Gait tables: [patrol walk, brisk trot, crouched sneak]; blended by speed and crouch weight.
const G_BETA: Array[float] = [0.62, 0.40, 0.60]   # share of the cycle a foot is planted
const G_LIFT: Array[float] = [0.075, 0.20, 0.07]  # swing foot clearance
const G_SHIFT: Array[float] = [0.06, 0.09, 0.02]  # stance window sits slightly behind the hips
const G_PITCH: Array[float] = [1.0, 1.25, 0.40]   # heel-strike / toe-off amount
const G_FOOTX: Array[float] = [0.09, 0.075, 0.125]
const G_DROP: Array[float] = [0.035, 0.075, 0.37] # how far the pelvis rides below standing
const G_BOB: Array[float] = [0.016, -0.02, 0.008]
const G_SWAY: Array[float] = [0.016, 0.008, 0.028]
const G_LEAN: Array[float] = [0.04, 0.19, 0.74]
const G_PELV: Array[float] = [0.10, 0.15, 0.08]
const G_TWIST: Array[float] = [0.08, 0.14, 0.05]
const G_ROLL: Array[float] = [0.035, 0.03, 0.03]
const G_SWING: Array[float] = [0.40, 0.78, 0.16]
const G_ELBOW: Array[float] = [0.30, 1.25, 1.05]

const FLASH_TIME: float = 0.075
enum { GUN_NONE, GUN_RIFLE, GUN_PISTOL, GUN_REVOLVER }
enum { TOOL_NONE, TOOL_KNIFE, TOOL_CUTTERS, TOOL_GLASSES, TOOL_ROPE, TOOL_COSH }
enum { CL_NONE, CL_HELD, CL_FALL, CL_LIE, CL_RISE, CL_CARRIED, CL_KNEEL }

static var _meshes: Dictionary = {}
static var _body_material: ShaderMaterial
static var _cover_material: ShaderMaterial
static var _blob_material: ShaderMaterial
static var _flash_material: ShaderMaterial
static var _ui_material: StandardMaterial3D
static var _marker_material: StandardMaterial3D
static var _blob_mesh: QuadMesh
static var _flash_mesh: QuadMesh
static var _ring_mesh: ArrayMesh
static var _ring_cover_mesh: ArrayMesh
static var _marker_mesh: ArrayMesh
static var _marker_cover_mesh: ArrayMesh
static var _skin: Skin
static var _skins: Dictionary = {} # bind poses per shoulder width
static var _rifle_port: Transform3D
static var _rifle_ready: Transform3D
static var _rifle_aim: Transform3D
static var _rifle_slung: Transform3D
static var _rifle_order: Transform3D
static var _rifle_ground: Transform3D
static var _side_ready: Transform3D
static var _side_aim2: Transform3D
static var _side_aim1: Transform3D
static var _kp: PackedVector3Array
## Live models by actor id: how the two halves of a paired action find each other.
static var _live: Dictionary = {}
## Things an operative kneels at, in metres (X, Z): "unlock", "cut", "sabotage". Found once from the
## mission data (see _find_sites); the integrator may also set them.
static var sites: Dictionary = {}
static var sites_known: bool = false
## Until this time (ms) one figure keeps a speck of muzzle flash under the ground, so the flash shader
## is compiled at the start of the mission rather than on the first shot.
static var _flash_warm_until: int = -1

var skel: Skeleton3D
var body: MeshInstance3D
## The paper cut-out (or the art pack's model) shown in place of the body; null for a modelled figure.
var cutout: Node3D
## The selection ring and the contact shadow are this much larger under a big cut-out (a creature).
var ui_scale: float = 1.0
var blob: MeshInstance3D
var ring: MeshInstance3D
var marker: MeshInstance3D
var flash: MeshInstance3D
var flash_warming: bool = false
var phase: float = 0.0
var enemy: bool = false
var kind: String = "wren"       # the look: "wren", "rook", "asset" or "guard"
var guard_kind: String = ""     # patrol / tower / sentry / sergeant / reinforcement
var look_key: String = ""
var actor_id: String = ""
var initialized: bool = false
var was_stopped: bool = false
var pause_mark: int = 0
var thaw: float = 0.0          # seconds of real-time blending left after a change made while paused
var real_dt: float = 0.0
var selected: bool = false
var height: float = 1.0
var girth: float = 1.0
var shape: Dictionary = SHAPE
var baked: bool = false         # a figure baked from MakeHuman (several textured surfaces)
var baked_covered: bool = false
var _xray_tint := Color(0, 0, 0, -1)
## What he has on, if not his own clothes: the id of the guard whose uniform it is, or "shirt" for a stripped guard.
var _clothes: String = ""
var shoulder_x: float = 0.185  # this build's shoulder joints
var head_scale: float = 1.0
var stance_w: float = 0.0      # feet set this much wider than the stock walk and stance
var sway_k: float = 1.0
var arm_out: float = 0.0       # hanging arms held this much further out (a belly, a big chest)
var lie_front: float = 0.128   # hips above the ground lying face down / on the back / on the side
var lie_back: float = 0.128
var lie_side: float = 0.205
var seed_a: float = 0.0
var key_bank: int = 0           # 0, or KP_COUNT for the mirror-image key poses
var gun: int = GUN_NONE
var tool_kit: int = TOOL_NONE
var two_hands: bool = false     # sidearm fired from both hands
var muzzle: Vector3
var stow_prop: Transform3D      # holster, in hips space
var stow_tool: Transform3D      # sheath (hips space) or strap (chest space)
var clock: float = 0.0
var ui_clock: float = 0.0
var speed: float = 0.0
var stride_len: float = 1.3
var vis_yaw: float = 0.0  # where the feet and pelvis face
var face_yaw: float = 0.0 # where the simulation (or a paired action) wants him to face
var turn: float = 0.0     # how far the shoulders and head lead the feet towards face_yaw
# what the simulation says, kept as plain values (a partner's model reads these, never a dictionary)
var st_state: String = ""
var st_action: String = ""
var st_p: float = 0.0
var st_target: String = ""
var st_lethal: bool = false
## A cosh (melee "stun"): one blow to the head, and he is out.
var st_stun: bool = false
var st_carrying: String = ""
var st_elevation: float = 0.0
# last frame's values, to catch changes
var last_cooldown: float = 0.0
var last_hp: float = 100.0
var last_ammo: int = 0
var last_fire: float = 0.0
# one-shot clocks (-1 = idle)
var throw_t: float = -1.0
var recoil_t: float = -1.0
var beast_hits: int = 0            # a creature's: the shots it has taken (the rules' "hits")
var flinch_t: float = -1.0
var flash_t: float = -1.0
var flash_roll: float = 0.0
# blend weights
var act_kind: String = ""
var act_p: float = 0.0
var w_move: float = 0.0
var w_crouch: float = 0.0
var w_hidden: float = 0.0
var w_act: float = 0.0
var w_ready: float = 0.0
var w_aim: float = 0.0
var w_edge: float = 0.0
var w_search: float = 0.0
var w_order: float = 0.0
var w_slung: float = 0.0
var w_gdrop: float = 0.0
var w_hold: float = 0.0
var w_sit: float = 0.0
var w_boat: float = 0.0
var w_wound: float = 0.0
var w_smoke: float = 0.0
var w_tool: float = 0.0
var w_tied: float = 0.0
var w_gun: float = 0.0
var w_gaim: float = 0.0
var w_td: float = 0.0
var w_pick: float = 0.0
var w_drop: float = 0.0
var w_carry: float = 0.0
var w_carried: float = 0.0
var aim_pitch: float = 0.0
var aim_to: float = 0.0
# paired actions
var td_on: bool = false
var td_low: bool = false        # the man being knifed or tied is already on the ground
var td_p: float = 0.0
var pick_p: float = 0.0
var drop_p: float = 0.0
var pair_yaw: float = 0.0
var pair_gap: float = 0.0
var hold_id: String = ""
var hold_p: float = 0.0
var hold_lethal: bool = false
var held_low: bool = false
var stun_left: float = 0.0
var grab_from: Node3D           # the model lifting or carrying this body
var grab_p: float = 0.0
var grab_ttl: int = 0
var bonds_out: bool = true      # the rope bones need (re)placing
var slung: bool = false         # his rifle went with him when he was carried off
var fallen: bool = false        # an operative or the informant, dead
# body clip
var clip: int = CL_NONE
var clip_t: float = 0.0
var fall_time: float = 0.6
var settle_t: float = 9.0
var lie_pose: int = KP_DEAD_F
var lie: float = 0.0            # 0 upright .. 1 on the ground
var lie_from: float = 0.0
var lie_sign: float = 1.0       # +1 the Rig tips forward (face down), -1 backward
var roll: float = 0.0           # how far the lying body is turned about its spine
var plant: float = 0.0          # feet kept on the ground under a key pose
var key_w: float = 0.0          # key pose over locomotion
var key_t: float = 1.0          # blend from the pose he was in (_k0) to the clip's pose (_kt)
var key_rate: float = 5.0
var _k := PackedVector3Array()
var _k0 := PackedVector3Array()
var _kt := PackedVector3Array()
var rig_off := Vector3.ZERO     # root-space nudge of the Rig towards a partner
var lie_off := Vector3.ZERO     # where a body put down ends up, relative to the root
var carry_xf := Transform3D.IDENTITY # where a body rides on this figure, in root space
var carry_g := Transform3D.IDENTITY  # last global Rig transform while carried
var a_head := Vector3(0, 1.525, 0)   # anchors in root space: head pivot (the marker hovers above it),
var a_chest := Vector3(0, 1.24, 0)   # chest joint,
var a_hands := Vector3(0, 0.9, 0.2)  # midpoint of the wrists
var _fz: float = 0.0
var _fy: float = 0.0
var _fp: float = 0.0
var _ik_mid: Vector3
var _ik_end: Vector3
var _ik_perp: Vector3
var _hand_b: Basis
var _hand_o: Vector3
var _rig := Transform3D.IDENTITY
var _rig_inv := Transform3D.IDENTITY
var _rig_inv_ok: bool = false
var _rolled: bool = false
var _roll_b: Basis
var _chest: Transform3D
var _hips_x: Transform3D
var _wl: Vector3
var _wr: Vector3
var _pl: Vector3
var _pr: Vector3
var _gl: Vector3
var _gr: Vector3
var _hl: float = 0.0
var _hr: float = 0.0

## Body-shape arithmetic, shared by the mesh kit and the figure.
class Body:
	## [rx, rz, cz] of a table of torso rows [y, rx, rz, cz, ...] at height y.
	static func rows_at(rows: Array, y: float) -> Vector3:
		var i := 0
		while i < rows.size() - 2 and y > float(rows[i + 1][0]): i += 1
		var a: Array = rows[i]
		var b: Array = rows[i + 1]
		var t := clampf((y - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0)
		return Vector3(lerpf(a[1], b[1], t), lerpf(a[2], b[2], t), lerpf(a[3], b[3], t))

	## Torso width factor at height y: seat below the belt, waist at it, chest above.
	static func wf(s: Dictionary, y: float) -> float:
		if s.has("rows"): return rows_at(s.rows, y).x / rows_at(STOCK_TORSO, y).x
		if y < 1.0: return lerpf(s.seat, s.waist, smoothstep(0.92, 1.0, y))
		var w := lerpf(s.waist, s.chest, smoothstep(1.10, 1.30, y))
		# over the top the shoulders round off into the arms: a broad man is not a box
		return lerpf(w, lerpf(1.0, s.chest, 0.45), smoothstep(1.40, 1.50, y))

	## Torso depth factor at height y.
	static func df(s: Dictionary, y: float) -> float:
		if s.has("rows"): return rows_at(s.rows, y).y / rows_at(STOCK_TORSO, y).y
		if y < 1.0: return lerpf(s.seat, s.waist, smoothstep(0.92, 1.0, y))
		return lerpf(s.waist, s.deep, smoothstep(1.10, 1.30, y))

	## How far the front of the torso swells out at height y (belly low, chest high), in metres.
	static func bulge(s: Dictionary, y: float) -> float:
		if s.has("rows"): return 0.0 # a measured body has its belly in its rows
		# a belly hangs: it swells slowly from the chest and tucks in quickly under itself
		return s.belly * exp(-pow((y - 1.10) / (0.13 if y > 1.10 else 0.085), 2.0)) + s.pecs * exp(-pow((y - 1.35) / 0.075, 2.0))

	## Moves a point placed on (or just off) the stock torso on to this body: gear follows the man.
	static func fit(s: Dictionary, gr: float, p: Vector3) -> Vector3:
		if s.has("rows"):
			var m := rows_at(s.rows, p.y)
			var k := rows_at(STOCK_TORSO, p.y)
			return Vector3(p.x * m.x / k.x, p.y, m.z + (p.z - k.z) * m.y / k.y)
		var b := bulge(s, p.y)
		return Vector3(p.x * gr * wf(s, p.y) + signf(p.x) * 0.3 * b * clampf(absf(p.x) / 0.16, 0.0, 1.0), p.y,
			p.z * gr * df(s, p.y) + b * clampf(p.z / 0.11, 0.0, 1.0))

# ----------------------------------------------------------------------------------------------
# Mesh kit: lofted tubes (elliptic / super-elliptic rings), boxes and straps with per-vertex
# colour, roughness/metal and skin weights.
# ----------------------------------------------------------------------------------------------
class Kit extends RefCounted:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var bn := PackedInt32Array()
	var wt := PackedFloat32Array()
	var idx := PackedInt32Array()
	var tint := Color.WHITE
	var surf := Vector2(0.92, 0.0)
	var b0: int = 0
	var b1: int = 0
	var bl: int = -1 # optional left/right bones for skirts: vertices follow the thigh on their side
	var br: int = -1
	var xf := Transform3D.IDENTITY
	var pre := Transform3D.IDENTITY # applied after xf: fits stock-sized headgear to another head
	var mx: float = 1.0 # -1 mirrors the following geometry to the right side
	var ox: float = 0.0 # X of the limb axis for yr()/ytube()
	var gr: float = 1.0 # girth multiplier for yr()/ytube()
	var _n: int = 8
	var _sq: float = 2.0
	var _rs := PackedInt32Array()
	var _rc := PackedVector3Array()
	var _v0: int = 0
	var _i0: int = 0
	var weather: float = 1.0 # 0 switches off cloth mottling and ground dirt (used for the rifle)
	var mat: float = MAT_WOOL # surface texture the shader draws (see character_body.gdshader)
	var mt := PackedFloat32Array()
	var profile: Array = [] # torso rows [y, rx, rz, cz, blend] that ribbon() wraps webbing around
	var _wrap_blend: float = 0.0
	var shape: Dictionary = SHAPE
	var drape: bool = false # cloth hanging from the waist falls straight down off a belly

	## A point placed against the stock torso, moved on to this body.
	func fit(p: Vector3) -> Vector3:
		return Body.fit(shape, gr, p)

	## One torso cross-section given in stock measurements; the body shape is applied here.
	func trunk(y: float, rx: float, rz: float, cz: float = 0.0, blend: float = 0.0, shade: float = 1.0) -> Vector3:
		if shape.has("rows"):
			var m := Body.rows_at(shape.rows, y)
			var st := Body.rows_at(STOCK_TORSO, y)
			var q := Vector3(m.x * rx / st.x, m.y * rz / st.y, m.z + (cz - st.z) * m.y / st.y)
			ring(Vector3(0, y, q.z), Vector3(q.x, 0, 0), Vector3(0, 0, q.y), blend, shade)
			return q
		var b := Body.bulge(shape, y) if not drape else Body.bulge(shape, maxf(y, 1.04)) * lerpf(0.55, 1.0, smoothstep(0.8, 1.04, y))
		var r := Vector3(rx * gr * Body.wf(shape, y) + 0.3 * b, rz * gr * Body.df(shape, y) + 0.5 * b, cz + 0.5 * b)
		ring(Vector3(0, y, r.z), Vector3(r.x, 0, 0), Vector3(0, 0, r.y), blend, shade)
		return r

	## rows: [y, rx, rz, cz = 0, blend = 0, shade = 1] in stock measurements. Returns the shaped rows
	## as [y, rx, rz, cz, blend].
	func trunk_tube(rows: Array, n: int, squareness: float, cap0: float = -1.0, cap1: float = -1.0) -> Array:
		begin(n, squareness)
		var out: Array = []
		for row: Array in rows:
			var count := row.size()
			var blend: float = row[4] if count > 4 else 0.0
			var r := trunk(row[0], row[1], row[2], row[3] if count > 3 else 0.0, blend, row[5] if count > 5 else 1.0)
			out.append([row[0], r.x, r.y, r.z, blend])
		finish(cap0, cap1)
		return out

	## Half width, half depth and centre depth of the torso at height y (from the profile).
	func at(y: float) -> Vector3:
		var i := 0
		while i < profile.size() - 2 and y > float(profile[i + 1][0]): i += 1
		var a: Array = profile[i]
		var b: Array = profile[i + 1]
		var t := clampf((y - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0)
		return Vector3(lerpf(a[1], b[1], t), lerpf(a[2], b[2], t), lerpf(a[3], b[3], t))

	func paint(hex: String, rough: float = 0.93, metal: float = 0.0) -> void:
		tint = Color(hex)
		surf = Vector2(rough, metal)
		if metal > 0.1: mat = MAT_PLAIN
		elif rough < 0.66: mat = MAT_LEATHER
		elif rough < 0.76: mat = MAT_SKIN
		else: mat = MAT_WOOL

	func bind(a: int, b: int = -1) -> void:
		b0 = a
		b1 = a if b < 0 else b
		bl = -1

	func bind_split(base: int, left: int, right: int) -> void:
		b0 = base
		b1 = base
		bl = left
		br = right

	func _world(p: Vector3) -> Vector3:
		var q: Vector3 = pre * (xf * p)
		q.x *= mx
		return q

	func _put(p: Vector3, blend: float, shade: float) -> int:
		var i := v.size()
		v.append(p)
		nrm.append(Vector3.ZERO)
		mt.append(mat)
		# weathering: matte cloth is slightly mottled, and everything near the ground carries dust
		var worn := shade
		if surf.x > 0.8: worn *= 1.0 + (fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0) - 0.5) * 0.09 * weather
		var dirt := pow(clampf((0.46 - p.y) / 0.46, 0.0, 1.0), 1.4) * 0.38 * weather
		col.append(Color(lerpf(tint.r * worn, 0.36, dirt), lerpf(tint.g * worn, 0.31, dirt), lerpf(tint.b * worn, 0.23, dirt)))
		uv.append(Vector2(lerpf(surf.x, 0.95, dirt), surf.y))
		if bl >= 0:
			var mid := absf(p.x) < 0.02
			bn.append(b0)
			bn.append(bl if (mid or p.x > 0.0) else br)
			bn.append(br if mid else 0)
			bn.append(0)
			wt.append(1.0 - blend)
			wt.append(blend * 0.5 if mid else blend)
			wt.append(blend * 0.5 if mid else 0.0)
			wt.append(0.0)
		else:
			bn.append(b0)
			bn.append(b1)
			bn.append(0)
			bn.append(0)
			wt.append(1.0 - blend)
			wt.append(blend)
			wt.append(0.0)
			wt.append(0.0)
		return i

	func _copy(src: int, p: Vector3) -> int:
		var i := v.size()
		v.append(p)
		nrm.append(Vector3.ZERO)
		mt.append(mt[src])
		col.append(col[src])
		uv.append(uv[src])
		for j: int in range(4):
			bn.append(bn[src * 4 + j])
			wt.append(wt[src * 4 + j])
		return i

	## Adds a triangle wound so that `out` is its front side.
	func _tri(a: int, b: int, c: int, out: Vector3) -> void:
		idx.append(a)
		if (v[b] - v[a]).cross(v[c] - v[a]).dot(out) > 0.0:
			idx.append(c)
			idx.append(b)
		else:
			idx.append(b)
			idx.append(c)

	func begin(n: int = 8, squareness: float = 2.0) -> void:
		_n = n
		_sq = squareness
		_rs.clear()
		_rc.clear()
		_v0 = v.size()
		_i0 = idx.size()

	## One cross-section: centre plus two radius vectors. `blend` = weight of the second bone.
	func ring(center: Vector3, u: Vector3, w: Vector3, blend: float = 0.0, shade: float = 1.0) -> void:
		_rs.append(v.size())
		_rc.append(_world(center))
		var e := 2.0 / _sq
		for i: int in range(_n):
			var a := TAU * (float(i) + 0.5) / float(_n)
			var ca := cos(a)
			var sa := sin(a)
			_put(_world(center + u * (signf(ca) * pow(absf(ca), e)) + w * (signf(sa) * pow(absf(sa), e))), blend, shade)

	## Horizontal ring on the current limb axis.
	func yr(y: float, rx: float, rz: float, cz: float = 0.0, blend: float = 0.0, shade: float = 1.0) -> void:
		ring(Vector3(ox, y, cz), Vector3(rx * gr, 0, 0), Vector3(0, 0, rz * gr), blend, shade)

	## Stitches the rings since begin(); cap values are dome heights (negative = leave open).
	func finish(cap0: float = -1.0, cap1: float = -1.0) -> void:
		var count := _rs.size()
		for r: int in range(count - 1):
			var mid := (_rc[r] + _rc[r + 1]) * 0.5
			for i: int in range(_n):
				var a := _rs[r] + i
				var b := _rs[r] + (i + 1) % _n
				var c := _rs[r + 1] + i
				var d := _rs[r + 1] + (i + 1) % _n
				var out := (v[a] + v[d]) * 0.5 - mid
				_tri(a, b, d, out)
				_tri(a, d, c, out)
		for end: int in range(2):
			var dome := cap0 if end == 0 else cap1
			if dome < 0.0 or count < 2: continue
			var r := 0 if end == 0 else count - 1
			var axis := (_rc[r] - _rc[1 if end == 0 else count - 2]).normalized()
			var tip := _copy(_rs[r], _rc[r] + axis * dome)
			for i: int in range(_n):
				_tri(tip, _rs[r] + i, _rs[r] + (i + 1) % _n, axis)
		# smooth normals from the faces of this tube only
		for t: int in range(_i0, idx.size(), 3):
			var fa := idx[t]
			var fb := idx[t + 1]
			var fc := idx[t + 2]
			var fn := (v[fc] - v[fa]).cross(v[fb] - v[fa])
			nrm[fa] += fn
			nrm[fb] += fn
			nrm[fc] += fn
		for i: int in range(_v0, v.size()):
			nrm[i] = nrm[i].normalized() if nrm[i].length_squared() > 0.0 else Vector3.UP

	## rows: [y, rx, rz, cz = 0, blend = 0, shade = 1]
	func ytube(rows: Array, n: int = 8, squareness: float = 2.0, cap0: float = -1.0, cap1: float = -1.0) -> void:
		begin(n, squareness)
		for row: Array in rows:
			var count := row.size()
			yr(row[0], row[1], row[2], row[3] if count > 3 else 0.0, row[4] if count > 4 else 0.0, row[5] if count > 5 else 1.0)
		finish(cap0, cap1)

	## Hard-edged box (crates of gear, pouches, rifle furniture).
	func box(center: Vector3, half: Vector3, rot: Basis = Basis.IDENTITY, shade: float = 1.0) -> void:
		for axis: int in range(3):
			for dir: float in [-1.0, 1.0]:
				var nloc := Vector3.ZERO
				nloc[axis] = dir
				var ua := Vector3.ZERO
				var va := Vector3.ZERO
				ua[(axis + 1) % 3] = half[(axis + 1) % 3]
				va[(axis + 2) % 3] = half[(axis + 2) % 3]
				var face := center + rot * (nloc * half[axis])
				var out := (pre.basis * xf.basis) * (rot * nloc)
				out.x *= mx
				out = out.normalized()
				var first := v.size()
				for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
					var i := _put(_world(face + rot * (ua * corner.x + va * corner.y)), 0.0, shade)
					nrm[i] = out
				_tri(first, first + 1, first + 2, out)
				_tri(first, first + 2, first + 3, out)

	## Flat strap from a to b lying against a surface whose outward direction is `face`.
	func strap(a: Vector3, b: Vector3, width: float, face: Vector3, thick: float = 0.012) -> void:
		var y := (b - a).normalized()
		var x := y.cross(face).normalized()
		box((a + b) * 0.5, Vector3(width * 0.5, a.distance_to(b) * 0.5, thick * 0.5), Basis(x, y, x.cross(y)))

	## Point on the torso surface at `deg` around the body (90 = front, 0 = left side, 270 = back).
	func hug(deg: float, y: float, lift: float) -> Vector3:
		var i := 0
		while i < profile.size() - 2 and y > float(profile[i + 1][0]): i += 1
		var a: Array = profile[i]
		var b: Array = profile[i + 1]
		var t := clampf((y - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0)
		_wrap_blend = lerpf(a[4], b[4], t)
		var ca := cos(deg_to_rad(deg))
		var sa := sin(deg_to_rad(deg))
		return Vector3((lerpf(a[1], b[1], t) + lift) * signf(ca) * pow(absf(ca), 0.8), y, lerpf(a[3], b[3], t) + (lerpf(a[2], b[2], t) + lift) * signf(sa) * pow(absf(sa), 0.8))

	## Webbing that hugs the torso: path = [[deg, y], ...]. Bind SPINE -> CHEST before calling.
	func ribbon(path: Array, width: float, lift: float = 0.007, shade: float = 1.0) -> void:
		var pts: Array[Vector2] = []
		for i: int in range(path.size() - 1):
			var from := Vector2(path[i][0], path[i][1])
			var to := Vector2(path[i + 1][0], path[i + 1][1])
			var steps := maxi(2, int(ceil(maxf(absf(to.x - from.x) / 12.0, absf(to.y - from.y) / 0.045))))
			for j: int in range(steps):
				pts.append(from.lerp(to, float(j) / float(steps)))
		pts.append(Vector2(path[-1][0], path[-1][1]))
		var first := v.size()
		for i: int in range(pts.size()):
			var p := hug(pts[i].x, pts[i].y, lift)
			var blend := _wrap_blend
			var out := (hug(pts[i].x, pts[i].y, lift + 0.02) - p).normalized()
			var before := pts[maxi(i - 1, 0)]
			var after := pts[mini(i + 1, pts.size() - 1)]
			var along := (hug(after.x, after.y, lift) - hug(before.x, before.y, lift)).normalized()
			var side := along.cross(out).normalized() * width * 0.5
			out = (pre.basis * xf.basis) * out
			out.x *= mx
			for sgn: float in [-1.0, 1.0]:
				var index := _put(_world(p + side * sgn), blend, shade)
				nrm[index] = out
			if i > 0:
				var q := first + i * 2
				_tri(q - 2, q - 1, q + 1, out)
				_tri(q - 2, q + 1, q, out)

	func torus(center: Vector3, rot: Basis, big: float, small: float, major: int = 10, minor: int = 5) -> void:
		begin(minor)
		for j: int in range(major + 1):
			var a := TAU * float(j) / float(major)
			var dir := rot * Vector3(cos(a), 0, sin(a))
			ring(center + dir * big, dir * small, rot.y * small)
		finish()

	## One cross-section from explicit points (local coordinates, as many as begin() was given).
	func ring_points(center: Vector3, pts: Array, blend: float = 0.0, shade: float = 1.0) -> void:
		_rs.append(v.size())
		_rc.append(_world(center))
		for p: Vector3 in pts:
			_put(_world(p), blend, shade)

	func commit() -> ArrayMesh:
		# CUSTOM0: where each vertex sits in the bind pose (so cloth texture stays put on a moving
		# figure) and which surface it is
		var custom := PackedFloat32Array()
		custom.resize(v.size() * 4)
		for i: int in range(v.size()):
			custom[i * 4] = v[i].x
			custom[i * 4 + 1] = v[i].y
			custom[i * 4 + 2] = v[i].z
			custom[i * 4 + 3] = mt[i]
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = nrm
		arrays[Mesh.ARRAY_COLOR] = col
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_BONES] = bn
		arrays[Mesh.ARRAY_WEIGHTS] = wt
		arrays[Mesh.ARRAY_INDEX] = idx
		arrays[Mesh.ARRAY_CUSTOM0] = custom
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		return mesh

# ----------------------------------------------------------------------------------------------
# Outfits
# ----------------------------------------------------------------------------------------------
## Surfaces the body shader textures differently (CUSTOM0.w).
const MAT_WOOL: float = 0.0
const MAT_CANVAS: float = 1.0
const MAT_LEATHER: float = 2.0
const MAT_SKIN: float = 3.0
const MAT_HAIR: float = 4.0
const MAT_PLAIN: float = 5.0

const SKIN_TONES: Array[String] = ["b48c6e", "aa8062", "ba9578", "a17658", "b79274"]
const HAIR_TONES: Array[String] = ["2b221b", "4b3827", "6a5236", "241d18", "3a2c20"]

## The stock torso's cross-sections [y, rx, rz, cz] (seat, then tunic) that kit is placed against;
## a baked figure's measured torso replaces it through the ratio of the two.
const STOCK_TORSO: Array = [[0.80, 0.152, 0.110, -0.006], [0.868, 0.156, 0.110, -0.006], [0.90, 0.162, 0.112, -0.006], [0.96, 0.170, 0.118, -0.010],
	[1.012, 0.164, 0.110, -0.004], [1.035, 0.160, 0.108, 0.0], [1.075, 0.159, 0.107, 0.0], [1.13, 0.160, 0.108, 0.002], [1.20, 0.172, 0.116, 0.006],
	[1.30, 0.190, 0.128, 0.010], [1.38, 0.196, 0.128, 0.008], [1.43, 0.190, 0.116, 0.002], [1.462, 0.160, 0.100, -0.004],
	[1.488, 0.108, 0.084, -0.007], [1.506, 0.072, 0.070, -0.008]]

## Body shape. The stock figure is all ones and zeros; a build lists only what it changes.
const SHAPE: Dictionary = {
	"shoulder": 0.185, # shoulder joints out from the spine (m): this moves the skeleton itself
	"chest": 1.0,      # upper torso width
	"deep": 1.0,       # upper torso depth
	"pecs": 0.0,       # chest standing proud at the front (m)
	"waist": 1.0,      # width and depth at the belt
	"belly": 0.0,      # paunch: how far the belly swells out in front (m)
	"seat": 1.0,       # hips and seat
	"trap": 0.0,       # neck-to-shoulder slope filled with muscle (m)
	"delt": 0.0,       # shoulder caps (m)
	"arm": 1.0,        # upper arm
	"fore": 1.0,       # forearm
	"hand": 1.0,
	"thigh": 1.0,
	"calf": 1.0,
	"neck": 1.0,
	"jaw": 1.0,        # lower face width
	"jowl": 0.0,       # fullness under the jaw (m)
	"face": 1.0,       # cheekbone width
	"head": 1.0,       # head size (scales the head bone, hat and all)
	"stance": 0.0,     # feet set wider apart (m)
	"sway": 1.0,       # side-to-side roll of the walk
	"splay": 0.0,      # hanging arms held further out from the body
}
## Builds, so that the cast reads apart at a glance: silhouette first, faces second.
const BUILDS: Dictionary = {
	# Wren: a scout who climbs and runs. Broad shoulders over a narrow waist, heavy arms, thick neck.
	"athlete": {"shoulder": 0.204, "chest": 1.15, "deep": 1.10, "pecs": 0.016, "waist": 0.90, "seat": 0.95, "trap": 0.024, "delt": 0.012,
		"arm": 1.27, "fore": 1.18, "hand": 1.08, "thigh": 1.10, "calf": 1.08, "neck": 1.24, "jaw": 1.04, "face": 0.98, "head": 0.97,
		"stance": 0.006, "sway": 0.8, "splay": 0.10},
	# Rook: the engineer, soft and heavy. A round belly over the belt, wide seat, short thick neck, full face.
	"heavy": {"shoulder": 0.186, "chest": 1.05, "deep": 1.10, "pecs": 0.008, "waist": 1.34, "belly": 0.10, "seat": 1.12, "trap": 0.004,
		"arm": 1.20, "fore": 1.10, "hand": 1.12, "thigh": 1.20, "calf": 1.10, "neck": 1.40, "jaw": 1.16, "jowl": 0.013, "face": 1.10, "head": 1.03,
		"stance": 0.026, "sway": 1.7, "splay": 0.30},
	# the garrison
	"wiry": {"chest": 0.95, "waist": 0.92, "seat": 0.96, "arm": 0.92, "fore": 0.94, "thigh": 0.95, "neck": 0.95, "jaw": 0.95, "face": 0.95},
	"stocky": {"shoulder": 0.192, "chest": 1.14, "deep": 1.10, "waist": 1.14, "seat": 1.08, "trap": 0.008, "arm": 1.14, "fore": 1.10, "hand": 1.05,
		"thigh": 1.14, "calf": 1.08, "neck": 1.22, "jaw": 1.10, "face": 1.05, "stance": 0.016, "sway": 1.25, "splay": 0.06},
	"lanky": {"chest": 0.85, "deep": 0.88, "waist": 0.83, "seat": 0.88, "arm": 0.83, "fore": 0.86, "hand": 0.96, "thigh": 0.86, "calf": 0.88,
		"neck": 0.88, "jaw": 0.92, "face": 0.92, "head": 1.02, "sway": 0.9},
	"paunch": {"deep": 1.04, "waist": 1.24, "belly": 0.078, "seat": 1.08, "neck": 1.12, "jowl": 0.006, "face": 1.04, "jaw": 1.04, "thigh": 1.06,
		"stance": 0.012, "sway": 1.3, "splay": 0.14},
	"big": {"shoulder": 0.198, "chest": 1.14, "deep": 1.10, "pecs": 0.006, "waist": 1.04, "seat": 1.04, "trap": 0.012, "delt": 0.008,
		"arm": 1.18, "fore": 1.12, "hand": 1.08, "thigh": 1.12, "calf": 1.10, "neck": 1.22, "jaw": 1.10, "head": 0.98, "stance": 0.008, "splay": 0.04},
	"brute": {"shoulder": 0.207, "chest": 1.20, "deep": 1.13, "pecs": 0.012, "waist": 1.05, "seat": 1.03, "trap": 0.026, "delt": 0.014,
		"arm": 1.27, "fore": 1.18, "hand": 1.10, "thigh": 1.15, "calf": 1.10, "neck": 1.34, "jaw": 1.15, "head": 0.95, "stance": 0.014, "splay": 0.08},
	"barrel": {"shoulder": 0.196, "chest": 1.13, "deep": 1.14, "waist": 1.25, "belly": 0.07, "seat": 1.12, "trap": 0.012,
		"arm": 1.12, "fore": 1.06, "hand": 1.05, "thigh": 1.10, "calf": 1.04, "neck": 1.30, "jaw": 1.10, "jowl": 0.010, "face": 1.06,
		"stance": 0.012, "sway": 0.8, "splay": 0.18},
	"slight": {"chest": 0.91, "deep": 0.92, "waist": 0.88, "seat": 0.92, "arm": 0.88, "fore": 0.90, "thigh": 0.91, "calf": 0.92, "neck": 0.90,
		"jaw": 0.93, "face": 0.95},
	# the barrio's women: the arms carried a little out from a coat that is wider at the hips than the shoulders
	"woman": {"chest": 0.92, "arm": 0.86, "fore": 0.88, "hand": 0.88, "neck": 0.88, "jaw": 0.9, "face": 0.94, "stance": -0.004, "sway": 1.2,
		"splay": 0.34},
}

static func _shape(build_name: String) -> Dictionary:
	var s: Dictionary = SHAPE.duplicate()
	if BUILDS.has(build_name): s.merge(BUILDS[build_name], true)
	return s

static func _guard_kind(id: String) -> String:
	if id == "tower" or id == "sentry" or id == "sergeant": return id
	if id.length() > 1 and id.begins_with("r") and id.substr(1).is_valid_int(): return "reinforcement"
	return "patrol"

## Everything that tells one figure from another. `gkind` is the guard's kind from the simulation;
## left empty it is derived from the id (g1..g5, tower, sentry, sergeant, r1..r3).
static func _look(id: String, is_enemy: bool, gkind: String = "", look_name: String = "") -> Dictionary:
	var art: Dictionary = ArtPack.parse_look(look_name)
	if not art.is_empty():
		# the rig of the figure the id would have (his weapon, his ways), sized to the drawing, which shows instead
		var o: Dictionary = _look(id, is_enemy, gkind, "-").duplicate()
		o.erase("fig")
		o.erase("fig_meta")
		o["shape"] = _shape(str(o.build))
		return _art_look(o, art, float(art.height_m))
	if is_enemy:
		if gkind == "": gkind = _guard_kind(id)
		var digits := id.substr(1)
		var n := maxi(int(digits), 1) if digits.is_valid_int() else 1 + absi(hash(id)) % 5
		# every man on the post is built differently: wiry, stocky, lanky, paunchy, big
		var eo := {
			"key": "guard%d" % n, "kind": "guard", "gk": gkind, "n": n,
			"top": ["5a5f51", "5a5f51", "5e6254", "575d52", "5b6053", "585e54"][n % 6], "legs": "5f625a", "skin": SKIN_TONES[n % 5], "hair": HAIR_TONES[(n + 2) % 5],
			"boot": "1a1918", "web": "211f1c", "girth": 1.0, "build": ["wiry", "wiry", "stocky", "lanky", "paunch", "big"][n % 6],
			"height": [1.0, 1.0, 0.935, 1.075, 0.985, 1.03][n % 6], "coat": n == 2 or n == 5, "tache": "brush" if n == 2 else "",
			"button": "7d7f78", "strap": "2f3a31", "chevron": n == 5, "grenade": n == 2 or n == 5, "messtin": n == 1 or n == 3,
			"face": [{}, {"brow_in": -0.002, "cheek": 1.2, "hollow": 1.0}, {"brow_in": -0.003, "nose_w": 0.008, "nose_tip": 0.012, "hollow": -0.4, "jawline": 1.2},
				{"brow_in": -0.0015, "nose_out": 0.023, "cheek": 1.3, "hollow": 1.3, "chin": 1.3}, {"brow_in": -0.002, "hollow": -0.5, "cheek": 0.7, "nose_tip": 0.011},
				{"brow_in": -0.003, "jawline": 1.4, "chin": 1.3, "brow": 1.4}][n % 6],
			"hat": "helmet", "gun": "rifle", "shirt": false, "kit": true, "bino": false}
		match gkind:
			"tower": # greatcoat, scarf, binoculars: the lookout, long and thin
				eo.merge({"key": "tower", "n": 5, "coat": true, "bino": true, "build": "slight", "height": 1.035, "tache": "", "chevron": false, "grenade": false, "skin": SKIN_TONES[1], "hair": HAIR_TONES[0]}, true)
			"sentry": # full marching order, the biggest man on the post
				eo.merge({"key": "sentry", "n": 3, "coat": false, "build": "brute", "height": 1.06, "tache": "", "chevron": true, "grenade": true, "skin": SKIN_TONES[4], "hair": HAIR_TONES[1]}, true)
			"sergeant": # peaked cap, darker tunic over pale breeches, cross strap and holster, no rifle; barrel-chested, grey moustache
				eo.merge({"key": "sergeant", "n": 0, "coat": false, "hat": "cap", "gun": "pistol", "kit": false, "top": "414a52", "legs": "7b7b6c",
					"web": "5b3f29", "build": "barrel", "height": 1.035, "tache": "brush", "skin": SKIN_TONES[2], "hair": "8f897c", "ruddy": 0.7, "strap": "8e9089", "chevron": false, "grenade": false,
					"breeches": true, "messtin": false, "face": {"brow": 1.3, "cheek": 0.8, "hollow": -0.3, "brow_in": -0.0032, "nose_w": 0.0075, "nose_out": 0.022, "nose_tip": 0.011, "mouth": 0.0018}}, true)
			"reinforcement": # turned out in a hurry: shirt sleeves and braces, or bare-headed with the collar open
				var r := (n - 1) % 3
				eo.merge({"key": "relief%d" % r, "n": [1, 4, 3][r], "coat": false, "kit": false, "hat": ["bare", "helmet", "bare"][r], "shirt": r != 2,
					"top": "8e8b79" if r != 2 else "576059", "build": ["slight", "stocky", "paunch"][r], "height": [1.005, 0.965, 1.0][r],
					"tache": ["", "", "walrus"][r], "chevron": false, "grenade": false, "messtin": false}, true)
				if r == 0: eo.hat = "fieldcap"
		# the baked figure for this look (tools/mh/figures.py); the procedural man if it is missing
		match gkind:
			"tower", "sentry", "sergeant": eo["fig"] = gkind
			"reinforcement": eo["fig"] = "relief%d" % ((n - 1) % 3)
			_: eo["fig"] = "guard%d" % (n % 6)
		# a look of the mission's own (data guards[].look): the navy on the quay, the Organisation Todt on the site
		match look_name.rstrip("0123456789"):
			"sailor", "bootsmann":
				# a navy-blue pea coat, double-breasted with brass buttons, belt and pouches over it
				eo.merge({"key": look_name, "top": "1f2534", "legs": "1c212c", "coat": true, "coat_button": "a88f4e",
					"hat": "sailor", "grenade": false, "messtin": false, "chevron": false, "web": "171614", "tache": ""}, true)
				if look_name == "bootsmann": eo.merge({"hat": "cap", "gun": "pistol", "kit": false}, true)
				if gkind == "lookout": eo.bino = true
				# the Sperrbrecher's deck sentry: a signal torch buttoned to the front of his coat
				if gkind == "torch": eo["torch"] = true
				eo["fig"] = look_name
			"ot":
				# earth-brown uniform, a plain armband, side cap
				eo.merge({"key": look_name, "top": "5e5440", "legs": "4e4636", "coat": false, "armband": true,
					"hat": "fieldcap", "grenade": false, "chevron": false, "button": "6f6a58", "strap": "4a4130"}, true)
				eo["fig"] = look_name
			"winter":
				# the garrison at Vemork in February: greatcoats to the knee, wool scarves, soft caps
				eo.merge({"key": look_name, "top": "5a5e52", "legs": "52564e", "coat": true, "hat": "fieldcap", "grenade": false,
					"messtin": false, "chevron": false}, true)
				eo["fig"] = look_name
			"watchman":
				# the plant's night watchman: a man of the valley in his own clothes, spectacles, no gun and no kit
				eo.merge({"key": "watchman", "top": "3c3e41", "legs": "37342f", "coat": false, "hat": "flat", "gun": "none", "kit": false,
					"grenade": false, "messtin": false, "chevron": false, "web": "2a2724", "build": "paunch", "height": 0.97, "tache": "walrus",
					"specs": true, "civilian": true}, true)
				eo["fig"] = "watchman"
			"guardia", "guardia_sgt":
				# Riachuelo's Guardia de Emergencia (an invented curfew force): charcoal-green greatcoats with black belts, soft
				# peaked caps with a plain silver disc, a white G.E. armband, a carbine and a baton; the sergeant in a cape, with
				# a whistle and a pistol. Nothing blue, no emblem: not the Policía Federal, not an army of the war
				var gs := look_name.trim_prefix("guardia")
				var gi := clampi(int(gs), 0, 2) if gs.is_valid_int() else 0
				eo.merge({"key": look_name, "top": "30362f", "legs": "2a2f2a", "coat": true, "hat": "", "gun": "rifle", "kit": false,
					"grenade": false, "messtin": false, "chevron": false, "bino": false, "web": "151514", "tache": "", "outfit": "guardia",
					"armband": "ge", "build": ["slight", "stocky", "big"][gi], "height": [1.02, 0.97, 1.045][gi],
					"hair": ["2a2018", "1f1915", "2b231c"][gi], "skin": SKIN_TONES[gi + 1]}, true)
				eo["fig"] = "guardia%d" % gi
				if look_name == "guardia_sgt" or gkind == "sergeant":
					eo.merge({"key": "guardia_sgt", "gun": "pistol", "build": "barrel", "height": 1.03, "hair": "6e6862", "cape": true}, true)
					eo["fig"] = "guardia_sgt"
			"informer":
				# the informer (buchón): a camel overcoat belted, a grey felt hat, the evening paper always in his hand
				eo.merge({"key": "informer", "top": "9c7a50", "legs": "4a4744", "coat": true, "hat": "", "gun": "none", "kit": false,
					"grenade": false, "messtin": false, "chevron": false, "bino": false, "web": "6e5232", "build": "", "height": 0.985,
					"tache": "", "hair": "1c1814", "civilian": true, "outfit": "civil", "paper": true}, true)
				eo["fig"] = "informer"
			"vecino", "vecina":
				# the barrio out in the snow: three men and two women baked, each also in other colours (the same figure dyed:
				# vecino3-5 are vecino0-2, vecina2-3 are vecina0-1)
				var woman := look_name.begins_with("vecina")
				var vs := look_name.trim_prefix("vecina" if woman else "vecino")
				var vi := int(vs) if vs.is_valid_int() else 0
				var base := vi % (2 if woman else 3)
				eo.merge({"key": look_name, "coat": true, "hat": "", "gun": "none", "kit": false, "grenade": false, "messtin": false,
					"chevron": false, "bino": false, "web": "2a2622", "tache": "", "civilian": true, "outfit": "civil"}, true)
				if woman:
					eo.merge({"build": "woman", "height": [0.95, 0.935][base], "hair": "3a2c22", "top": ["5a2e33", "28272b"][base], "legs": "2b2523"}, true)
					if vi >= 2: eo["tints"] = [{"jacket": "2e4a3f", "shirt": "a89c8a", "hat_color": "8a5038"}, {"jacket": "4b3a2c", "hat_color": "5e3b36"}][base]
				else:
					eo.merge({"build": ["stocky", "paunch", "slight"][base], "height": [1.0, 0.965, 1.01][base], "hair": ["3a332c", "8e8a84", "1e1a17"][base],
						"top": ["36383b", "5a4636", "474852"][base], "legs": "33312e"}, true)
					if vi >= 3:
						eo["tints"] = [{"jacket": "3a4150", "hat_color": "4a3c30", "scarf": "8b8579"}, {"jacket": "3f4136", "hat_color": "5d554c", "scarf": "2f3a4e"},
							{"jacket": "5a4636", "shirt": "6a6d74", "hat_color": "33363f", "scarf": "7a3a30"}][base]
						eo.merge({"hair": ["5a5550", "2a2420", "3a2a1e"][base], "height": [1.025, 0.985, 0.99][base]}, true)
				eo["fig"] = ("vecina%d" if woman else "vecino%d") % base
		eo["shape"] = _shape(eo.build)
		_apply_fig(eo)
		return eo
	var o: Dictionary
	match id:
		"rook":
			o = {"key": "rook", "kind": "rook", "n": 0, "top": "7d7250", "legs": "756a4b", "skin": "ac7a5a",
				"hair": "3b3129", "boot": "2b231d", "web": "a09870", "girth": 1.0, "height": 0.95, "coat": false, "build": "heavy", "tache": "walrus",
				"ruddy": 0.85, "burns": 0.022, "iris": "3a2e24", "button": "4a3f2a", "flash": "7a2a20", "flash2": "34507a", "fig": "rook",
				"face": {"brow": 1.5, "cheek": 0.6, "hollow": -0.9, "jawline": 0.5, "chin": 0.7, "nose_w": 0.0086, "nose_out": 0.0215, "nose_tip": 0.0135,
					"wings": 0.0165, "brow_in": -0.0036, "brow_h": 0.0037, "mouth": 0.0014, "stubble": 0.35}}
		"merle":
			# the docker: lean, weathered, a flat cap and a cigarette
			o = {"key": "merle", "kind": "merle", "n": 0, "top": "41608f", "legs": "4a4236", "skin": "a87c5e",
				"hair": "241c16", "boot": "3a2a1e", "web": "3a2f24", "girth": 1.0, "height": 1.0, "coat": false, "build": "slight", "tache": "",
				"face": {"cheek": 1.3, "hollow": 1.4, "stubble": 0.7}, "fig": "merle"}
		"rype":
			# the ski scout: tall and lean, all in white, the hood up
			o = {"key": "rype", "kind": "rype", "n": 0, "top": "e6e9eb", "legs": "dbdee1", "skin": "b88a70",
				"hair": "b08a58", "boot": "3a2a1e", "web": "c9cdd2", "girth": 0.98, "height": 1.04, "coat": false, "build": "athlete", "tache": "",
				"face": {"cheek": 1.3, "hollow": 1.1, "jawline": 1.2, "chin": 1.2, "stubble": 0.4}, "fig": "rype"}
		"hornero":
			# the tram motorman: solid, forty, a long dark overcoat, a rust scarf wound high, the company's flat cap;
			# the controller handle in his coat pocket and the bell from the tram at his hip
			o = {"key": "hornero", "kind": "hornero", "n": 0, "top": "262c38", "legs": "2b2b2f", "skin": "a87a5a",
				"hair": "2a211b", "boot": "1d1a17", "web": "2c2219", "girth": 1.0, "height": 1.0, "coat": false, "build": "stocky", "tache": "",
				"face": {"cheek": 1.0, "hollow": 0.6, "jawline": 1.2, "chin": 1.1, "nose_w": 0.0080, "nose_out": 0.0225, "stubble": 0.6}, "fig": "hornero"}
		"lechuza":
			# the night lineman: long, thin and stooped, fifty-five, a grey-brown canvas work coat with his tool belt over it,
			# a knitted cap with ear flaps, round steel spectacles, fingerless gloves; the folding ladder on his shoulder
			o = {"key": "lechuza", "kind": "lechuza", "n": 0, "top": "6b6251", "legs": "3b3832", "skin": "b08a72",
				"hair": "8f8a83", "boot": "211e1b", "web": "3d2c1f", "girth": 1.0, "height": 1.03, "coat": false, "build": "lanky", "tache": "",
				"face": {"cheek": 1.3, "hollow": 1.3, "stubble": 0.7}, "fig": "lechuza", "specs": true}
		"benteveo":
			# the newspaper seller: sixteen, slight and quick, a cap too big, a long striped scarf, the bag of the late edition
			o = {"key": "benteveo", "kind": "benteveo", "n": 0, "top": "6a5642", "legs": "57452f", "skin": "c09878",
				"hair": "3a2a1e", "boot": "2e241c", "web": "7d6c4c", "girth": 0.96, "height": 0.95, "coat": false, "build": "slight", "tache": "",
				"face": {"cheek": 0.8, "hollow": 0.3, "stubble": 0.0}, "fig": "benteveo"}
		"bigua":
			# the boatman: broad and strong, thirty-five, an oilskin open over a roll-neck jumper, a beanie, rubber boots; a
			# coil of rope over his shoulder and a sheath knife on his belt
			o = {"key": "bigua", "kind": "bigua", "n": 0, "top": "6e6232", "legs": "2a2a2a", "skin": "a47658",
				"hair": "1e1a17", "boot": "161716", "web": "2a2019", "girth": 1.02, "height": 1.01, "coat": false, "build": "big", "tache": "",
				"face": {"cheek": 1.1, "hollow": 0.5, "jawline": 1.4, "chin": 1.2, "stubble": 0.8}, "fig": "bigua"}
		"asset":
			o = {"key": "asset", "kind": "asset", "n": 0, "top": "b5af9a", "legs": "403b38", "skin": "bb9a7e",
				"hair": "3a2d22", "boot": "2a231e", "web": "5b4632", "girth": 0.93, "height": 0.965, "coat": false, "build": "", "tache": "",
				"face": {"cheek": 0.9, "hollow": 0.8, "brow_in": 0.0022, "mouth": 0.0012, "stubble": 0.45}, "fig": "asset"}
		_:
			o = {"key": "wren", "kind": "wren", "n": 0, "top": "545a3e", "legs": "4f5139", "skin": "b48d6f",
				"hair": "3a2a1e", "boot": "2a221c", "web": "8f8a63", "girth": 1.0, "height": 1.03, "coat": false, "build": "athlete", "tache": "", "stubble": true,
				"ruddy": 0.2, "burns": 0.013, "iris": "4b524a", "button": "3a3226", "flash": "7a2a20", "flash2": "2a3150", "fig": "wren",
				"face": {"brow": 1.25, "cheek": 1.35, "hollow": 1.15, "jawline": 1.35, "chin": 1.25, "cleft": 1.0, "nose_w": 0.0060, "nose_out": 0.0205,
					"nose_tip": 0.0085, "wings": 0.0105, "brow_in": -0.0026, "brow_h": 0.0028, "mouth": 0.0007, "stubble": 0.6}}
			if id != "wren":
				# an operative this file has no look for yet (a later operation's squad): a civilian with Merle's kit, in
				# the figure his data names (units[].look), never silently Wren in battledress
				if look_name == "": push_warning("operative.gd: unit '%s' has no look of its own; give it units[].look" % id)
				o.merge({"key": "merle", "kind": "merle", "build": "slight", "tache": "", "fig": "merle"}, true)
	# a look of the mission's own for an operative (data units[].look): Merle in a winter coat at Vemork
	if look_name != "" and look_name != str(o.key):
		o["key"] = look_name
		o["fig"] = look_name
		# a figure a guard may wear too (the watchman, a sailor): the operative's mesh, with his kit, is his own
		if not id in ["wren", "rook", "merle", "rype", "asset"]: o["key"] = "%s:%s" % [id, look_name]
		# the passenger Riachuelo's squad gets across: a borrowed overcoat too big for him, round spectacles, no braces
		if id == "asset" and look_name == "pasajero":
			o.merge({"top": "4d4a42", "legs": "383735", "hair": "2a2018", "specs": true, "overcoat": true, "height": 0.985}, true)
	o["shape"] = _shape(o.build)
	_apply_fig(o)
	return o

## A look shown as the art pack's drawing or model, `h` metres tall (the slot's height, or the actor's `look_height`).
static func _art_look(o: Dictionary, art: Dictionary, h: float) -> Dictionary:
	var a: Dictionary = art.duplicate()
	a["height_m"] = clampf(h, 0.3, 30.0)
	o["cutout"] = a
	o["key"] = "art:%s@%.2f" % [str(a.id), float(a.height_m)]
	o["height"] = float(a.height_m) / ArtPack.RIG_HEIGHT
	return o

## The look the actor's data asks for: his own (`_look`), with the height of a drawing taken from `look_height` if set.
static func _look_of(actor: Dictionary, id: String, is_enemy: bool) -> Dictionary:
	var o: Dictionary = _look(id, is_enemy, str(actor.get("kind", "")), str(actor.get("look", "")))
	if o.has("cutout") and float(actor.get("look_height", 0.0)) > 0.0:
		o = _art_look(o, o.cutout, float(actor.look_height))
	return o

## Comic ink (ink.gd): the selection ring and the marker over the head printed in the second colour, vermilion.
static func ink_cues(on: bool) -> void:
	_shared()
	# and the art pack's models printed for it (cutout.gd)
	Cutout.ink_mode(on)
	var tint := Color(0.92, 0.3, 0.14) if on else Color.WHITE
	_ui_material.albedo_color = tint
	_marker_material.albedo_color = tint

## The x-ray overlay, two passes: the stencil mark of where every figure is what the camera sees (drawn for all of
## them first: render priority below the x-ray and below every other blended thing), then the tinted figure seen
## through the world (shaders/xray_mark.gdshader, shaders/xray.gdshader).
static var _xray: ShaderMaterial
static func _xray_material() -> ShaderMaterial:
	if _xray == null:
		var tint := ShaderMaterial.new()
		tint.shader = preload("res://shaders/xray.gdshader")
		_xray = ShaderMaterial.new()
		_xray.shader = preload("res://shaders/xray_mark.gdshader")
		_xray.render_priority = -3
		_xray.next_pass = tint
	return _xray

## The tint he shows through whatever hides him from the camera (alpha 0: nothing shows).
func set_xray(tint: Color) -> void:
	if tint == _xray_tint: return
	_xray_tint = tint
	body.set_instance_shader_parameter("xray_tint", tint)
	if cutout != null: cutout.set_xray(tint)

## Whether he takes part in the x-ray at all: off while nobody shows through anything (the launch screen, the
## closing scene), which spares drawing every body twice more.
func use_xray(on: bool) -> void:
	var want: Material = _xray_material() if on else null
	if body.material_overlay != want: body.material_overlay = want
	if cutout != null: cutout.use_xray(on, _xray_material())

## The look for what the actor is wearing now. An operative in a guard's uniform has the guard's figure and clothes
## but stays himself (his own weapons, tools and ways); a guard whose uniform was taken lies in shirt sleeves.
func _clothed(actor: Dictionary) -> Dictionary:
	var id := str(actor.get("id", actor_id))
	var own := _look_of(actor, id, enemy)
	if enemy:
		if not bool(actor.get("stripped", false)): return own
		# the turned-out-in-a-hurry figure: shirt, braces, no tunic, no kit
		var shirt := _look("r1", true, "reinforcement").duplicate()
		shirt.kind = "guard"
		shirt.gk = own.gk
		shirt.gun = own.gun
		shirt.bino = false
		return shirt
	var disguise: Dictionary = actor.get("disguise", {})
	if disguise.is_empty(): return own
	var dressed := _look(str(disguise.get("id", "")), true, str(disguise.get("kind", "")), str(disguise.get("look", ""))).duplicate()
	dressed.kind = own.kind
	dressed.gk = ""
	return dressed

## A look with a baked figure takes its shoulders, torso and head from the figure's measurements.
static func _apply_fig(o: Dictionary) -> void:
	if not o.has("fig"): return
	if not Figure.has(o.fig):
		o.erase("fig")
		return
	var meta: Dictionary = Figure.load_fig(o.fig).meta
	var sh: Dictionary = o.shape.duplicate()
	sh.shoulder = float(meta.shoulder_x)
	sh.head = 1.0
	var rows: Array = []
	for r: Array in meta.torso:
		rows.append([float(r[0]), float(r[1]), float(r[2]), float(r[3])])
	sh.rows = rows
	o.shape = sh
	o["fig_meta"] = meta

## True when the look is a baked figure that brings this surface (its own hat, scarf...).
static func _fig_part(o: Dictionary, surface: String) -> bool:
	return o.has("fig_meta") and _fig_has(o, surface)

static func _fig_has(o: Dictionary, surface: String) -> bool:
	for s: Dictionary in o.fig_meta.surfaces:
		if s.name == surface: return true
	return false

## Where stock-sized headgear goes on a baked figure's head (identity for a procedural one).
static func _head_fit(o: Dictionary) -> Transform3D:
	if not o.has("fig_meta"): return Transform3D.IDENTITY
	# headgear was made for the stock head: brows at 1.684, crown at 1.794, 0.077 wide, 0.198 deep
	var h: Dictionary = o.fig_meta.head
	var sx := (float(h.half_width) + 0.006) / 0.077
	var sz := (float(h.front) - float(h.back) + 0.006) / 0.198
	var brow := float(h.get("brow", float(h.top) - 0.11))
	var sy := clampf((float(h.top) + 0.004 - brow) / 0.110, 0.8, 1.25)
	var to := Vector3(0, brow, (float(h.front) + float(h.back)) * 0.5)
	return Transform3D(Basis.from_scale(Vector3(sx, sy, sz)), to) * Transform3D(Basis.IDENTITY, Vector3(0, -1.684, 0))

static func _mesh_for(o: Dictionary) -> ArrayMesh:
	if _meshes.has(o.key): return _meshes[o.key]
	var k := Kit.new()
	k.gr = o.girth
	k.shape = o.shape
	var is_baked := o.has("fig_meta")
	if is_baked:
		# the body, head and clothes are the baked figure; only the kit is built here, against
		# the figure's measured torso
		k.gr = 1.0
		for r: Array in o.shape.rows:
			k.profile.append([r[0], r[1], r[2], r[3], smoothstep(1.10, 1.30, float(r[0]))])
		if not (o.fig_meta.textures as Dictionary).has("tache") or not _fig_has(o, "tache"):
			_build_tache(k, o, {"grid": o.fig_meta.face, "lm": o.fig_meta.landmarks})
		if o.kind == "guard" and not o.has("outfit"):
			_baked_tunic(k, o)
	else:
		_build_torso(k, o)
		_build_legs(k, o)
		_build_arms(k, o)
		_build_head(k, o)
	match o.kind:
		"wren": _gear_wren(k, o)
		"rook": _gear_rook(k, o)
		"merle":
			_gear_merle(k, o)
			_build_cosh(k)
		"rype": _gear_rype(k, o)
		"hornero":
			_gear_hornero(k, o)
			_build_controller(k)
		"lechuza": _gear_lechuza(k, o)
		"benteveo": _gear_benteveo(k, o)
		"bigua":
			_gear_bigua(k, o)
			_build_knife(k)
		"guard":
			match str(o.get("outfit", "")):
				"guardia": _gear_guardia(k, o)
				"civil": _gear_civil(k, o)
				_: _gear_guard(k, o)
		_: _gear_asset(k, o)
	_paint_pass(k, o)
	var mesh := k.commit()
	if is_baked:
		var full := Figure.mesh(o.fig, o.hair, o.get("tints", {}))
		var arrays := mesh.surface_get_arrays(0)
		full.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		full.surface_set_material(full.get_surface_count() - 1, _body_material)
		mesh = full
	_meshes[o.key] = mesh
	return mesh

## Painted shading baked into the vertex colours, the way the portraits are lit: a little darker
## low and lighter high, shadow where cloth folds in (armpits, crotch, under the belt and a belly,
## behind the knees, inside the elbows) and mud where a man kneels and walks.
static func _paint_pass(k: Kit, o: Dictionary) -> void:
	var sh: Dictionary = o.shape
	var operative: bool = o.kind in ["wren", "rook", "merle", "rype", "hornero", "lechuza", "benteveo", "bigua", "asset"]
	var mud := Color(0.30, 0.25, 0.18)
	var belt_y: float = 1.05 - minf(sh.belly, 0.06) * 0.7 if o.kind == "rook" else 1.05
	var shoulder: float = sh.shoulder
	for i: int in range(k.v.size()):
		var bone := k.bn[i * 4]
		if bone >= PROP: continue # weapons and tools keep their own finish
		var p := k.v[i]
		var ax := absf(p.x)
		var f := lerpf(0.86, 1.06, smoothstep(0.25, 1.65, p.y))
		var dirt := 0.0
		match bone:
			ARM_L, FORE_L, ARM_R, FORE_R:
				# the inside of the arm, against the body, and the crease inside the elbow
				var inside := smoothstep(0.005, 0.035, shoulder - ax) * (1.0 - smoothstep(1.40, 1.46, p.y)) * smoothstep(1.02, 1.12, p.y)
				f *= 1.0 - 0.24 * inside
				f *= 1.0 - 0.20 * exp(-pow((p.y - 1.15) / 0.02, 2.0)) * smoothstep(0.0, 0.03, p.z)
			SPINE, CHEST:
				# the flanks under the arms
				if p.y > 1.12 and p.y < 1.44:
					var side := ax / maxf(k.at(p.y).x, 0.05)
					f *= 1.0 - 0.24 * smoothstep(0.70, 0.98, side) * smoothstep(1.12, 1.22, p.y) * (1.0 - smoothstep(1.38, 1.44, p.y))
			THIGH_L, THIGH_R, SHIN_L, SHIN_R:
				# inner thighs, the back of the knee, the knee itself (scuffed by kneeling)
				var inner := smoothstep(0.0, 0.03, 0.095 - ax) * smoothstep(0.62, 0.80, p.y)
				f *= 1.0 - 0.20 * inner
				var knee := exp(-pow((p.y - 0.50) / 0.04, 2.0))
				f *= 1.0 - 0.22 * knee * smoothstep(0.0, -0.03, p.z)
				dirt = maxf(dirt, knee * smoothstep(0.015, 0.05, p.z) * (0.48 if operative else 0.14))
			FOOT_L, FOOT_R:
				dirt = maxf(dirt, (1.0 - smoothstep(0.0, 0.08, p.y)) * (0.38 if operative else 0.14))
		if bone == HIPS or bone == SPINE:
			# crotch, and the shadow a belt (or the belly over it) throws
			f *= 1.0 - 0.24 * smoothstep(0.06, 0.0, ax) * (1.0 - smoothstep(0.86, 0.95, p.y))
			f *= 1.0 - 0.18 * exp(-pow((p.y - (belt_y - 0.045)) / 0.02, 2.0))
		if sh.belly > 0.0 and p.z > 0.0:
			f *= 1.0 - 1.3 * sh.belly * exp(-pow((p.y - 0.985) / 0.045, 2.0)) * smoothstep(0.02, 0.10, p.z)
		var c := k.col[i]
		c = Color(c.r * f, c.g * f, c.b * f)
		if dirt > 0.0: c = c.lerp(mud, dirt)
		k.col[i] = c

static func _build_torso(k: Kit, o: Dictionary) -> void:
	var style: String = o.kind
	var shirt: bool = o.get("shirt", false)
	var sh: Dictionary = o.shape
	# seat and waist (trouser cloth)
	k.paint(o.legs)
	k.bind(HIPS, SPINE)
	k.trunk_tube([[0.868, 0.10, 0.085, -0.005, 0, 0.78], [0.90, 0.158, 0.108, -0.006, 0, 0.9], [0.96, 0.170, 0.118, -0.010],
		[1.02, 0.158, 0.108, -0.004, 0.4], [1.075, 0.148, 0.100, 0, 1]], 12, 2.4, 0.02, 0.0)
	k.paint(o.top)
	if (style == "guard" and not shirt) or style == "rook":
		# tunic skirt (greatcoat, field jacket) hangs from the hips and follows the thighs on each side
		var grow := 0.014 if o.coat else 0.0
		var legs := maxf(0.0, sh.thigh - 1.0) * 0.11 # a skirt is cut wide enough for the man's thighs
		k.bind_split(HIPS, THIGH_L, THIGH_R)
		k.drape = true
		k.begin(12, 2.5)
		if o.coat:
			k.trunk(0.40, 0.215 + legs, 0.165 + legs, -0.008, 0.72, 0.82)
			k.trunk(0.56, 0.21 + legs, 0.158 + legs, -0.008, 0.62, 0.92)
			k.trunk(0.74, 0.20 + legs, 0.148 + legs, -0.008, 0.45)
		else:
			k.trunk(0.815, 0.188 + legs, 0.134 + legs, -0.008, 0.42, 0.84 if style == "guard" else 0.93)
		k.trunk(0.90, 0.184 + grow + legs, 0.130 + grow + legs, -0.008, 0.2)
		k.trunk(0.97, 0.178 + grow + legs * 0.5, 0.124 + grow + legs * 0.5, -0.008, 0.0)
		k.bind(HIPS, SPINE)
		k.trunk(1.03, 0.164 + grow, 0.112 + grow, -0.003, 0.5)
		k.trunk(1.065, 0.158 + grow, 0.106 + grow, 0.0, 1.0)
		k.finish(0.0, 0.0)
		k.drape = false
	var loose := 0.014 if style in ["wren", "rook"] or shirt else (0.012 if o.coat else 0.004) # blouse overhang
	var chest := 0.012 if o.coat else 0.0
	var trap: float = sh.trap
	k.bind(SPINE, CHEST)
	var rows: Array = [[1.012, 0.150, 0.100, 0, 0, 0.8], [1.035, 0.156 + loose, 0.104 + loose, 0, 0, 1], [1.075, 0.156 + loose * 0.8, 0.104 + loose * 0.8, 0, 0, 1],
		[1.13, 0.160 + chest, 0.108 + chest, 0.002, 0.3, 1], [1.20, 0.172 + chest, 0.116 + chest, 0.006, 0.8, 1],
		[1.30, 0.190 + chest, 0.128 + chest, 0.010, 1, 1], [1.38, 0.196 + chest, 0.128 + chest, 0.008, 1, 1],
		[1.43, 0.190 + chest, 0.116 + chest, 0.002, 1, 1], [1.462, 0.160 + chest + trap * 0.8, 0.100 + chest + trap * 0.3, -0.004, 1, 1],
		[1.488, 0.108 + chest + trap * 1.6, 0.084 + chest + trap * 0.4, -0.007, 1, 1], [1.506, (0.072 + chest) * lerpf(1.0, sh.neck, 0.7) + trap * 0.5, (0.070 + chest) * lerpf(1.0, sh.neck, 0.7), -0.008, 1, 0.82]]
	if sh.belly > 0.0 or sh.pecs > 0.0:
		# a paunch or a big chest needs more sections to read round
		rows.insert(3, [1.105, 0.158 + chest * 0.5 + loose * 0.4, 0.106 + chest * 0.5 + loose * 0.4, 0.001, 0.15, 1])
		rows.insert(5, [1.165, 0.166 + chest, 0.112 + chest, 0.004, 0.55, 1])
		rows.insert(7, [1.25, 0.181 + chest, 0.122 + chest, 0.008, 0.9, 1])
		rows.insert(9, [1.34, 0.193 + chest, 0.128 + chest, 0.009, 1, 1])
	k.profile = k.trunk_tube(rows, 12, 2.5, 0.0, 0.0)
	if style != "asset" and not shirt:
		# patch pockets on the chest, each flap held by a button
		for deg: float in [62.0, 118.0]:
			k.ribbon([[deg, 1.375], [deg, 1.275]], 0.082, 0.004, 0.93)
			k.ribbon([[deg, 1.385], [deg, 1.345]], 0.088, 0.007, 0.85)
		var button := Color(o.get("button", "3a3226"))
		for deg: float in [62.0, 118.0]:
			k.tint = button
			k.surf = Vector2(0.5, 0.2)
			k.box(k.hug(deg, 1.356, 0.010), Vector3(0.0055, 0.0055, 0.0025), Basis(Vector3.UP, deg_to_rad(90.0 - deg)))
		# shoulder straps from the collar to the shoulder seam, buttoned at the neck
		if not o.coat:
			if style == "guard":
				# shoulder boards piped in white
				k.paint("c9c7b5" if o.gk != "sergeant" else "b9bab3", 0.8, 0.0 if o.gk != "sergeant" else 0.3)
				for deg: float in [0.0, 180.0]:
					k.ribbon([[deg, 1.503], [deg, 1.474], [deg, 1.446]], 0.041, 0.0082, 1.0)
			k.paint(o.get("strap", o.top), 0.9)
			for deg: float in [0.0, 180.0]:
				k.ribbon([[deg, 1.501], [deg, 1.474], [deg, 1.449]], 0.034, 0.009, 0.9)
			k.tint = button
			k.surf = Vector2(0.5, 0.2)
			k.bind(CHEST)
			for deg: float in [0.0, 180.0]:
				k.box(k.hug(deg, 1.495, 0.013), Vector3(0.006, 0.004, 0.006))
	_collar(k, o)

## Collars: a guard's dark standing collar with pale tabs (silver-edged for the sergeant), Rook's
## jacket collar open over his shirt.
static func _collar(k: Kit, o: Dictionary) -> void:
	if o.kind == "guard" and (o.kit or o.gk == "sergeant") and not o.coat and not o.get("shirt", false):
		k.paint("2c322e", 0.9)
		k.bind(CHEST, HEAD)
		_neck_wrap(k, o, [[1.486, 0.084, 0.080, -0.006, 0, 0.9], [1.532, 0.072, 0.072, -0.010, 0.22]], 10)
		var grow := lerpf(1.0, o.shape.neck, 0.85)
		var front := -0.008 + 0.077 * grow
		k.paint("a7a99b" if o.gk != "sergeant" else "b9bab3", 0.6, 0.1)
		k.bind(CHEST)
		for side: float in [1.0, -1.0]:
			k.box(Vector3(side * 0.031 * grow, 1.508, front - 0.004), Vector3(0.011, 0.007, 0.0016), Basis(Vector3.UP, side * 0.45) * Basis(Vector3.RIGHT, -0.25))
		if o.gk == "sergeant":
			k.paint("aeb0a8", 0.45, 0.4) # braid round the top of the collar
			k.bind(CHEST, HEAD)
			_neck_wrap(k, o, [[1.524, 0.0738, 0.0738, -0.0096, 0.2], [1.534, 0.0725, 0.0725, -0.0101, 0.22]], 10)
	elif o.kind == "rook":
		# the jacket's fold-down collar, open at the throat over a darker shirt
		k.paint(o.top, 0.95)
		k.bind(CHEST, HEAD)
		_neck_wrap(k, o, [[1.474, 0.090, 0.088, -0.006, 0, 0.82], [1.512, 0.080, 0.078, -0.010, 0.18, 0.96]], 10)
		var grow := lerpf(1.0, o.shape.neck, 0.85)
		k.paint("5e583e", 0.95)
		k.bind(CHEST)
		var throat := Vector3(0, 1.488, -0.008 + 0.084 * grow + 0.0015)
		for side: float in [1.0, -1.0]:
			k.box(throat + Vector3(side * 0.008, 0, 0), Vector3(0.008, 0.022, 0.0016), Basis(Vector3.BACK, side * 0.42) * Basis(Vector3.RIGHT, -0.3))

static func _build_legs(k: Kit, o: Dictionary) -> void:
	var style: String = o.kind
	var baggy := 1.07 if style in ["wren", "rook"] else 1.0
	var th: float = o.shape.thigh
	var ca: float = o.shape.calf
	k.ox = 0.095
	for side: float in [1.0, -1.0]:
		k.mx = side
		var thigh := THIGH_L if side > 0.0 else THIGH_R
		k.paint(o.legs)
		k.bind(thigh, thigh + 1)
		k.begin(8)
		k.yr(0.955, 0.070 * th, 0.080 * th, 0, 0, 0.85)
		k.yr(0.90, 0.088 * baggy * th, 0.096 * baggy * th, 0, 0, 0.9)
		if o.get("breeches", false):
			# riding breeches: full over the thigh, flaring out at the side, tight at the knee
			for row: Array in [[0.80, 1.22, 0.010], [0.70, 1.30, 0.016], [0.60, 1.10, 0.008]]:
				k.ring(Vector3(k.ox + float(row[2]), row[0], 0.0), Vector3(0.080 * th * float(row[1]) * k.gr, 0, 0), Vector3(0, 0, 0.088 * th * lerpf(1.0, float(row[1]), 0.5) * k.gr))
		else:
			k.yr(0.80, 0.083 * baggy * th, 0.092 * baggy * th)
			k.yr(0.68, 0.072 * baggy * th, 0.080 * baggy * th)
		k.yr(0.57, 0.062 * baggy * lerpf(th, 1.0, 0.4), 0.068 * baggy * lerpf(th, 1.0, 0.4), 0.002)
		k.yr(0.535, 0.060 * baggy * lerpf(th, ca, 0.5), 0.068 * baggy * lerpf(th, ca, 0.5), 0.005, 0.25)
		k.yr(0.50, 0.060 * baggy * ca, 0.072 * baggy * ca, 0.007, 0.5)
		k.yr(0.465, 0.058 * baggy * ca, 0.067 * baggy * ca, 0.002, 0.75)
		k.yr(0.43, 0.057 * baggy * ca, 0.063 * baggy * ca, -0.004, 1)
		if style == "guard":
			k.yr(0.415, 0.066 * maxf(ca, 1.0), 0.072 * maxf(ca, 1.0), -0.004, 1)
			k.yr(0.39, 0.050, 0.055, 0, 1, 0.8)
			k.finish(0.02, 0.0)
			k.paint(o.boot, 0.5) # jackboot shaft
			k.bind(thigh + 1)
			var shaft := lerpf(1.0, ca, 0.6) # a big man's boots are cut wider in the leg
			k.ytube([[0.405, 0.060 * shaft, 0.066 * shaft, -0.004, 0, 0.9], [0.33, 0.057 * shaft, 0.065 * shaft, -0.010], [0.20, 0.047 * shaft, 0.053 * shaft, -0.004], [0.10, 0.044, 0.051]], 8)
		elif style == "asset":
			k.yr(0.34, 0.056, 0.062, -0.006, 1)
			k.yr(0.20, 0.052, 0.057, -0.002, 1)
			k.yr(0.075, 0.055, 0.062, 0.004, 1, 0.88)
			k.finish(0.02, 0.0)
		else:
			k.yr(0.34, 0.063 * ca, 0.069 * ca, -0.008 - 0.01 * (ca - 1.0), 1)
			k.yr(0.245, 0.062 * lerpf(1.0, ca, 0.5), 0.066 * lerpf(1.0, ca, 0.5), -0.006, 1)
			k.yr(0.21, 0.047, 0.051, -0.002, 1, 0.8)
			k.finish(0.02, 0.0)
			k.paint(o.web, 0.9) # canvas anklet
			k.bind(thigh + 1)
			k.ytube([[0.225, 0.049, 0.054, -0.002], [0.15, 0.045, 0.050], [0.10, 0.045, 0.051]], 8)
		# boot: ankle collar plus a foot lofted heel -> toe
		k.paint(o.boot, 0.5)
		k.bind(thigh + 1, thigh + 2)
		k.ytube([[0.135, 0.044, 0.050, 0, 0.3], [0.09, 0.044, 0.054, 0.004, 0.7], [0.05, 0.043, 0.056, 0.006, 1]], 8)
		k.bind(thigh + 2)
		var low := 0.85 if style == "asset" else 1.0
		k.begin(8, 3.0)
		for row: Array in [[-0.078, 0.034, 0.036], [-0.035, 0.044, 0.056 * low], [0.03, 0.047, 0.050 * low], [0.10, 0.051, 0.037], [0.168, 0.047, 0.030], [0.205, 0.032, 0.022]]:
			k.ring(Vector3(0.095, row[2] + 0.001, row[0]), Vector3(row[1], 0, 0), Vector3(0, row[2], 0), 0.0, 0.9)
		k.finish(0.012, 0.014)
		if style in ["wren", "rook"]:
			# laces across the instep
			k.paint("b9ad92", 0.85)
			for lace: Vector2 in [Vector2(0.034, 0.1005), Vector2(0.054, 0.0955), Vector2(0.074, 0.0895)]:
				k.box(Vector3(0.095, lace.y + 0.0012, lace.x), Vector3(0.019, 0.0016, 0.0026), Basis(Vector3.RIGHT, -0.32))
			# two buckled straps round each canvas anklet
			k.bind(thigh + 1)
			for y: float in [0.205, 0.158]:
				k.paint(o.web, 0.9)
				k.box(Vector3(0.095 + 0.049 + 0.0022, y, -0.006), Vector3(0.0022, 0.0065, 0.024))
				k.paint("6f6650", 0.45, 0.5)
				k.box(Vector3(0.095 + 0.049 + 0.0045, y, -0.012), Vector3(0.0018, 0.0075, 0.006))
	k.mx = 1.0

static func _build_arms(k: Kit, o: Dictionary) -> void:
	var rolled: bool = o.kind == "asset" or o.get("shirt", false)
	var bulk := 0.006 if o.coat else 0.0
	var sh: Dictionary = o.shape
	var up: float = sh.arm
	var lo: float = sh.fore
	var cap: float = sh.delt
	var curl := (up - 1.0) * 0.012 # a big biceps fills the front of the sleeve
	k.ox = sh.shoulder
	for side: float in [1.0, -1.0]:
		k.mx = side
		var arm := ARM_L if side > 0.0 else ARM_R
		k.paint(o.top)
		k.bind(arm, CHEST)
		k.begin(8)
		k.yr(1.480, 0.028 * up + cap * 0.6, 0.034 * up + cap * 0.6, 0, 0.7, 0.95)
		k.yr(1.462, 0.047 * up + bulk + cap, 0.055 * up + bulk + cap, 0, 0.5)
		k.yr(1.42, 0.054 * up + bulk + cap, 0.061 * up + bulk + cap * 0.8, 0, 0.2)
		k.bind(arm, arm + 1)
		k.yr(1.34, 0.051 * up + bulk + cap * 0.3, 0.057 * up + bulk + curl * 0.5, curl * 0.3, 0, 0.92)
		k.yr(1.26, 0.047 * up + bulk, 0.053 * up + bulk + curl, curl * 0.6)
		k.yr(1.19, 0.045 * lerpf(up, lo, 0.4) + bulk, 0.050 * lerpf(up, lo, 0.4) + bulk, -0.002, 0.25)
		k.yr(1.15, 0.045 * lerpf(up, lo, 0.6) + bulk, 0.053 * lerpf(up, lo, 0.6) + bulk, -0.005, 0.5)
		k.yr(1.11, 0.044 * lo + bulk, 0.049 * lo + bulk, -0.002, 0.75)
		if rolled:
			k.yr(1.095, 0.051 * lo, 0.055 * lo, 0, 0.9)
			k.yr(1.07, 0.051 * lo, 0.055 * lo, 0, 1)
			k.yr(1.06, 0.040 * lo, 0.043 * lo, 0, 1, 0.8)
			k.finish(0.008, 0.0)
			k.paint(o.skin, 0.72)
			k.bind(arm + 1)
			k.ytube([[1.075, 0.038 * lo, 0.041 * lo], [1.01, 0.040 * lo, 0.042 * lo], [0.95, 0.033 * lerpf(lo, 1.0, 0.3), 0.035 * lerpf(lo, 1.0, 0.3)], [0.90, 0.027, 0.031]], 8)
		else:
			k.yr(1.07, 0.043 * lo * (1.0 + (lo - 1.0) * 0.3) + bulk, 0.046 * lo * (1.0 + (lo - 1.0) * 0.3) + bulk, 0, 1)
			k.yr(0.98, 0.039 * lo + bulk, 0.042 * lo + bulk, 0, 1)
			k.yr(0.915, 0.036 * lerpf(lo, 1.0, 0.3) + bulk, 0.039 * lerpf(lo, 1.0, 0.3) + bulk, 0, 1)
			k.yr(0.90, 0.029 * lerpf(lo, 1.0, 0.5), 0.033 * lerpf(lo, 1.0, 0.5), 0, 1, 0.78)
			k.finish(0.008, 0.0)
			# turned cuff
			var cr := 0.036 * lerpf(lo, 1.0, 0.3) + bulk
			k.ytube([[0.946, cr + 0.0032, cr * 1.08 + 0.0032, 0, 1, 0.84], [0.903, cr + 0.0038, cr * 1.08 + 0.0038, 0, 1, 0.78]], 8)
			if o.kind == "wren" and side > 0.0:
				# wristwatch worn over the cuff
				k.paint("3a2a1c", 0.6)
				k.ytube([[0.932, cr + 0.0062, cr * 1.08 + 0.0062, 0, 1], [0.921, cr + 0.0062, cr * 1.08 + 0.0062, 0, 1]], 8)
				k.paint("cfc8ad", 0.3, 0.4)
				k.box(Vector3(sh.shoulder + cr * k.gr + 0.0075, 0.9265, 0.0), Vector3(0.0022, 0.0075, 0.0075))
		# patches high on the outer sleeve: a coloured shoulder title for the commandos, chevrons for a guard of rank
		var outer: float = sh.shoulder + (0.0525 * up + bulk + cap * 0.55) * k.gr + 0.0012
		var flash_col: String = o.get("flash", "")
		if flash_col != "" and not rolled:
			k.paint(flash_col, 0.85)
			k.bind(arm)
			k.box(Vector3(outer, 1.392, 0.0), Vector3(0.0018, 0.0085, 0.024), Basis(Vector3.BACK, -0.08))
			k.paint(o.get("flash2", flash_col), 0.85)
			k.box(Vector3(outer - 0.0015, 1.352, 0.0), Vector3(0.0018, 0.014, 0.017), Basis(Vector3.BACK, -0.06))
		if o.get("chevron", false) and side > 0.0 and not rolled:
			k.paint("a5a79a", 0.6, 0.1)
			k.bind(arm)
			for lean: float in [0.75, -0.75]:
				k.box(Vector3(outer - 0.001, 1.335, 0.0095 * signf(lean)), Vector3(0.0016, 0.0035, 0.015), Basis(Vector3.RIGHT, lean))
		# mitten hand with the fingers curling forward, plus a thumb
		k.paint(o.skin, 0.72)
		k.bind(arm + 2)
		var g := k.gr
		var hs: float = sh.hand
		k.gr = 1.0
		k.begin(6, 2.6)
		for row: Array in [[0.908, 0.022, 0.027, 0.0], [0.865, 0.021, 0.038, 0.002], [0.822, 0.021, 0.039, 0.008], [0.782, 0.019, 0.034, 0.020], [0.758, 0.014, 0.026, 0.030]]:
			k.ring(Vector3(sh.shoulder - row[3] * hs, 0.908 - (0.908 - float(row[0])) * hs, 0.004), Vector3(row[1] * hs, 0, 0), Vector3(0, 0, row[2] * hs))
		k.finish(-1.0, 0.008)
		k.box(Vector3(sh.shoulder - 0.009 * hs, 0.908 - 0.062 * hs, 0.042 * hs), Vector3(0.009, 0.022, 0.009) * hs, Basis(Vector3.RIGHT, 0.5)) # thumb
		k.gr = g
	k.mx = 1.0

## Depth of the face surface at (x, y) over a set of head rows [y, rx, rz, cz, ...] (squareness 2.2).
static func _face_z(rows: Array, x: float, y: float) -> float:
	var i := 0
	while i < rows.size() - 2 and y > float(rows[i + 1][0]): i += 1
	var a: Array = rows[i]
	var b: Array = rows[i + 1]
	var t := clampf((y - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0)
	var rx := lerpf(a[1], b[1], t)
	var across := pow(clampf(absf(x) / rx, 0.0, 1.0), 2.2)
	return lerpf(a[3], b[3], t) + lerpf(a[2], b[2], t) * pow(1.0 - across, 1.0 / 2.2)

## Half width of the head at height y.
static func _face_w(rows: Array, y: float) -> float:
	var i := 0
	while i < rows.size() - 2 and y > float(rows[i + 1][0]): i += 1
	var t := clampf((y - float(rows[i][0])) / (float(rows[i + 1][0]) - float(rows[i][0])), 0.0, 1.0)
	return lerpf(rows[i][1], rows[i + 1][1], t)

## The head's rows for this face: jaw, jowls and cheekbones from the shape.
static func _head_rows(o: Dictionary) -> Array:
	var sh: Dictionary = o.shape
	var jw: float = sh.jaw
	var jl: float = sh.jowl
	var fc: float = sh.face
	var dark := 0.84 if o.get("stubble", false) else 1.0 # a day's beard darkens the jaw
	return [[1.548, 0.030 * jw + jl * 1.4, 0.034 + jl * 0.6, 0.046 - jl * 0.3, 0, 0.86 * dark], [1.566, 0.054 * jw + jl * 1.2, 0.062 + jl * 0.4, 0.027, 0, 0.9 * dark],
		[1.60, 0.067 * lerpf(jw, fc, 0.5) + jl * 0.5, 0.084, 0.013, 0, lerpf(1.0, dark, 0.6)], [1.65, 0.074 * fc, 0.094, 0.006],
		[1.70, 0.076 * lerpf(fc, 1.0, 0.5), 0.097, 0.0], [1.745, 0.069, 0.090, -0.004], [1.776, 0.042, 0.056, -0.008]]

## Relief carved into the head: how strongly each feature shows (1 = average).
const FACE: Dictionary = {"brow": 1.0, "cheek": 1.0, "hollow": 0.5, "jawline": 1.0, "chin": 1.0, "cleft": 0.0,
	"nose_w": 0.0068, "nose_out": 0.019, "nose_tip": 0.0095, "wings": 0.0115, "brow_in": 0.0, "brow_h": 0.0026,
	"eye": 1.0, "mouth": 0.0, "stubble": 0.0}

## Everything the head is built from: the row profile, the relief and the resolution.
static func _head_def(o: Dictionary) -> Dictionary:
	var f: Dictionary = FACE.duplicate()
	f.merge(o.get("face", {}), true)
	var fine: bool = o.kind != "guard"
	var ys: Array = [1.546, 1.551, 1.557, 1.564, 1.572, 1.580, 1.588, 1.595, 1.602, 1.609, 1.617, 1.625, 1.633, 1.641, 1.649, 1.657,
		1.664, 1.670, 1.676, 1.682, 1.688, 1.695, 1.703, 1.714, 1.727, 1.741, 1.755, 1.767, 1.776, 1.782]
	if not fine:
		ys = [1.546, 1.556, 1.568, 1.580, 1.592, 1.603, 1.615, 1.628, 1.641, 1.654, 1.665, 1.675, 1.686, 1.700, 1.720, 1.742, 1.762, 1.776, 1.782]
	return {"rows": _head_rows(o), "f": f, "n": 24 if fine else 16, "ys": ys}

## Catmull-Rom through one column of the head rows.
static func _row_at(rows: Array, y: float, col: int) -> float:
	var n := rows.size()
	var i := 0
	while i < n - 2 and y > float(rows[i + 1][0]): i += 1
	var t := clampf((y - float(rows[i][0])) / (float(rows[i + 1][0]) - float(rows[i][0])), 0.0, 1.0)
	var p0: float = rows[maxi(i - 1, 0)][col]
	var p1: float = rows[i][col]
	var p2: float = rows[i + 1][col]
	var p3: float = rows[mini(i + 2, n - 1)][col]
	return 0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t)

static func _bump(ap: float, c: float, w: float, y: float, cy: float, h: float) -> float:
	return exp(-pow((ap - c) / w, 2.0) - pow((y - cy) / h, 2.0))

## How far the face stands out (+) or sinks in (-) at angle phi round the head (0 = the front).
static func _relief(f: Dictionary, phi: float, y: float) -> float:
	var ap := absf(wrapf(phi, -PI, PI))
	var d := 0.0
	d -= 0.0056 * _bump(ap, 0.40, 0.19, y, 1.669, 0.0105)                  # eye sockets
	d += 0.0036 * float(f.brow) * _bump(ap, 0.34, 0.30, y, 1.686, 0.0072)   # brow ridge
	d += 0.0012 * float(f.brow) * _bump(ap, 0.0, 0.16, y, 1.680, 0.006)     # between the brows
	d += 0.0046 * float(f.cheek) * _bump(ap, 0.88, 0.30, y, 1.645, 0.013)   # cheekbones
	d -= 0.0042 * float(f.hollow) * _bump(ap, 0.92, 0.28, y, 1.612, 0.012)  # under them (a full face: negative)
	d += 0.0046 * float(f.jawline) * _bump(ap, 1.22, 0.22, y, 1.574, 0.010) # the corner of the jaw
	d += 0.0050 * float(f.chin) * _bump(ap, 0.0, 0.26, y, 1.557, 0.0095)    # chin
	d -= 0.0018 * float(f.cleft) * _bump(ap, 0.0, 0.05, y, 1.556, 0.006)    # and its cleft
	d += 0.0030 * _bump(ap, 0.0, 0.42, y, 1.600, 0.013)                     # the mouth over the teeth
	d -= 0.0016 * _bump(ap, 0.0, 0.14, y, 1.5875, 0.004)                    # the dip under the lower lip
	d -= 0.0018 * _bump(ap, 1.05, 0.25, y, 1.692, 0.014)                    # temples
	return d

static func _head_at(hd: Dictionary, phi: float, y: float) -> Vector3:
	var rows: Array = hd.rows
	var rx := _row_at(rows, y, 1)
	var rz := _row_at(rows, y, 2)
	var cz := _row_at(rows, y, 3)
	var a := phi + PI / 2.0
	var ca := cos(a)
	var sa := sin(a)
	var e := 2.0 / 2.2
	var x := rx * signf(ca) * pow(absf(ca), e)
	var z := rz * signf(sa) * pow(absf(sa), e)
	var out := Vector2(x, z).normalized() if absf(x) + absf(z) > 0.0001 else Vector2(0, 1)
	var d := _relief(hd.f, phi, y)
	return Vector3(x + out.x * d, y, z + cz + out.y * d)

## The point of the face at height y and sideways offset x (front half), with its outward direction.
static func _face_point(hd: Dictionary, x: float, y: float) -> Vector3:
	if hd.has("grid"):
		var g: Dictionary = hd.grid
		var fx := clampf((x - float(g.x0)) / float(g.step), 0.0, float(g.nx) - 1.001)
		var fy := clampf((y - float(g.y0)) / float(g.step), 0.0, float(g.ny) - 1.001)
		var ix := int(fx)
		var iy := int(fy)
		var tx := fx - ix
		var ty := fy - iy
		var z: Array = g.z
		var a := lerpf(z[iy][ix], z[iy][ix + 1], tx)
		var b := lerpf(z[iy + 1][ix], z[iy + 1][ix + 1], tx)
		return Vector3(x, y, lerpf(a, b, ty))
	var lo := -PI / 2.0
	var hi := PI / 2.0
	for i: int in range(24):
		var mid := (lo + hi) * 0.5
		if _head_at(hd, mid, y).x > x: lo = mid
		else: hi = mid
	return _head_at(hd, (lo + hi) * 0.5, y)

static func _face_normal(hd: Dictionary, x: float, y: float) -> Vector3:
	var p := _face_point(hd, x, y)
	var dx := _face_point(hd, x + 0.002, y) - _face_point(hd, x - 0.002, y)
	var dy := _face_point(hd, x, y + 0.002) - _face_point(hd, x, y - 0.002)
	var n := dy.cross(dx).normalized()
	if n.z < 0.0: n = -n
	return n if p.length() > 0.0 else Vector3.BACK

## A dab of colour lying on the face from a to b (both given as face x, y), `h` tall.
static func _face_stroke(k: Kit, hd: Dictionary, a: Vector2, b: Vector2, h: float, lift: float, depth: float) -> void:
	var pa := _face_point(hd, a.x, a.y)
	var pb := _face_point(hd, b.x, b.y)
	var n := _face_normal(hd, (a.x + b.x) * 0.5, (a.y + b.y) * 0.5)
	k.strap(pa + n * lift, pb + n * lift, h, n, depth)

## Moustache, drawn on the face (procedural or baked) at the height of the upper lip.
static func _build_tache(k: Kit, o: Dictionary, hd: Dictionary) -> void:
	var lip := 1.6150
	var tache_scale := 1.0
	if hd.has("lm"):
		# a baked face: from under the nose to the line of the lips, as wide as the mouth
		var lm: Dictionary = hd.lm
		var top: float = lm.nose_base[1]
		var bottom: float = lm.mouth[1]
		var half: float = lm.corner[0]
		var mid := (top + bottom) * 0.5
		var h := (top - bottom) * 0.95
		match str(o.get("tache", "")):
			"walrus":
				k.paint(o.hair, 0.85)
				k.mat = MAT_HAIR
				k.bind(HEAD)
				for side: float in [1.0, -1.0]:
					_face_stroke(k, hd, Vector2(0.0, mid + h * 0.08), Vector2(side * half * 0.95, mid - h * 0.08), h, 0.0045, 0.007)
					_face_stroke(k, hd, Vector2(side * half * 0.85, mid - h * 0.05), Vector2(side * half * 1.3, bottom - h * 0.45), h * 0.7, 0.004, 0.0065)
			"brush":
				k.paint(o.hair, 0.8)
				k.mat = MAT_HAIR
				k.bind(HEAD)
				_face_stroke(k, hd, Vector2(-half * 0.85, mid + h * 0.1), Vector2(half * 0.85, mid + h * 0.1), h * 0.6, 0.003, 0.005)
		return
	match str(o.get("tache", "")):
		"walrus":
			# a thick moustache that hides the upper lip and droops past the corners of the mouth
			k.paint(o.hair, 0.85)
			k.mat = MAT_HAIR
			k.bind(HEAD)
			for side: float in [1.0, -1.0]:
				_face_stroke(k, hd, Vector2(0.0, lip), Vector2(side * 0.021 * tache_scale, lip - 0.004), 0.0125 * tache_scale, 0.0046, 0.0065)
				_face_stroke(k, hd, Vector2(side * 0.019 * tache_scale, lip - 0.003), Vector2(side * 0.029 * tache_scale, lip - 0.0155), 0.0100 * tache_scale, 0.0038, 0.006)
		"brush":
			k.paint(o.hair, 0.8)
			k.mat = MAT_HAIR
			k.bind(HEAD)
			_face_stroke(k, hd, Vector2(-0.019 * tache_scale, lip), Vector2(0.019 * tache_scale, lip), 0.0085 * tache_scale, 0.0028, 0.005)

## A baked face's upper lip: under the nose tip (the face's most forward point on the midline in
## the lower half of the face), where the profile is deepest before the lips stand out again.
static func _lip_y(hd: Dictionary) -> float:
	var tip_y := 1.63
	var tip_z := -1.0
	for y: float in range(1560, 1680, 2):
		var z := _face_point(hd, 0.0, y / 1000.0).z
		if z > tip_z:
			tip_z = z
			tip_y = y / 1000.0
	var best := tip_y - 0.012
	var deep := 1.0
	for y: float in range(int(tip_y * 1000) - 26, int(tip_y * 1000) - 6, 1):
		var z := _face_point(hd, 0.0, y / 1000.0).z
		if z < deep:
			deep = z
			best = y / 1000.0
	return best - 0.004

static func _build_head(k: Kit, o: Dictionary) -> void:
	var g := k.gr
	var sh: Dictionary = o.shape
	var nk: float = sh.neck
	var jl: float = sh.jowl
	k.gr = 1.0
	k.ox = 0.0
	k.paint(o.skin, 0.72)
	k.bind(CHEST, HEAD)
	k.ytube([[1.47, 0.056 * nk, 0.060 * nk, -0.012, 0, 0.85], [1.525, 0.052 * nk, 0.056 * nk + jl, -0.012 + jl * 0.6, 0.5, 0.85], [1.58, 0.050 * nk, 0.056 * nk + jl * 0.6, -0.010 + jl * 0.4, 1, 0.8]], 8)
	k.bind(HEAD)
	var hd := _head_def(o)
	var f: Dictionary = hd.f
	var n: int = hd.n
	var face_from := k.v.size()
	k.begin(n)
	for y: float in hd.ys:
		var pts: Array = []
		for i: int in range(n):
			pts.append(_head_at(hd, TAU * (float(i) + 0.5) / float(n) - PI / 2.0, y))
		k.ring_points(Vector3(0, y, _row_at(hd.rows, y, 3)), pts)
	k.finish(0.006, 0.01)
	# painted on the skin: warm cheeks and nose (a ruddy man more than most), shadowed eye sockets,
	# a day's beard on the jaw and lip
	var ruddy: float = o.get("ruddy", 0.35)
	var beard: float = f.stubble
	for i: int in range(face_from, k.v.size()):
		var p := k.v[i]
		if p.z < 0.0: continue
		var ax := absf(p.x)
		var cheek := exp(-pow((ax - 0.042) / 0.022, 2.0) - pow((p.y - 1.628) / 0.026, 2.0))
		var nose := exp(-pow(ax / 0.012, 2.0) - pow((p.y - 1.632) / 0.012, 2.0))
		var socket := exp(-pow((ax - 0.029) / 0.016, 2.0) - pow((p.y - 1.672) / 0.011, 2.0))
		var jaw := (1.0 - smoothstep(1.596, 1.632, p.y)) * smoothstep(0.0, 0.05, p.z) * (1.0 - 0.6 * exp(-pow(ax / 0.012, 2.0) - pow((p.y - 1.604) / 0.006, 2.0)))
		var ap := absf(atan2(-p.x, p.z))
		var model := 1.0
		model -= 0.11 * maxf(float(f.hollow), 0.0) * _bump(ap, 0.92, 0.30, p.y, 1.612, 0.015) # hollow cheeks
		model -= 0.13 * (1.0 - smoothstep(1.547, 1.567, p.y))                                  # under the jaw
		model -= 0.07 * exp(-pow(ax / 0.009, 2.0) - pow((p.y - 1.6135) / 0.0045, 2.0))         # under the nose
		model -= 0.06 * exp(-pow(ax / 0.014, 2.0) - pow((p.y - 1.5880) / 0.004, 2.0))         # under the lip
		model -= 0.06 * smoothstep(0.9, 1.5, ap) * (1.0 - smoothstep(1.62, 1.68, p.y))          # the side of the jaw turning away
		model += 0.05 * smoothstep(1.695, 1.725, p.y) * (1.0 - smoothstep(0.6, 1.2, ap))       # forehead catching the light
		var c := k.col[i] * model
		c = c.lerp(Color(c.r * 1.07, c.g * 0.90, c.b * 0.87), clampf((cheek + 0.5 * nose) * ruddy * 0.75, 0.0, 1.0))
		c = c * (1.0 - 0.18 * socket)
		if beard > 0.0: c = c.lerp(Color(c.r * 0.72, c.g * 0.72, c.b * 0.76), clampf(jaw * beard, 0.0, 1.0))
		k.col[i] = c
	var skin := Color(o.skin)
	var shadow := Color(skin.r * 0.52, skin.g * 0.40, skin.b * 0.36)
	# nose: a loft from the bridge to the tip, then under it to the nostrils
	var nw: float = f.nose_w
	var nout: float = f.nose_out
	k.paint(o.skin, 0.72)
	k.begin(8)
	for row: Array in [[1.680, 0.0, 0.70], [1.672, 0.18, 0.75], [1.662, 0.38, 0.82], [1.651, 0.58, 0.90], [1.641, 0.78, 0.98], [1.634, 0.94, 1.0], [1.628, 1.0, 1.0], [1.623, 0.80, 1.05], [1.619, 0.45, 1.1]]:
		var y: float = row[0]
		var t: float = row[1]
		var base := _face_point(hd, 0.0, y)
		var out := lerpf(0.0025, nout, pow(t, 0.85))
		var w := lerpf(nw * float(row[2]), f.nose_tip, smoothstep(0.75, 1.0, t))
		k.ring(Vector3(0, y, base.z - 0.004 + out * 0.5), Vector3(w, 0, 0), Vector3(0, 0, out * 0.5 + 0.004))
	k.finish(-1.0, 0.003)
	for side: float in [1.0, -1.0]:
		# the wings of the nose
		var base := _face_point(hd, side * f.wings * 0.75, 1.624)
		k.begin(6)
		for row: Array in [[1.631, 0.0030, 0.0042], [1.625, 0.0046, 0.0062], [1.619, 0.0036, 0.0048]]:
			k.ring(Vector3(side * f.wings * 0.78, row[0], base.z + 0.0015), Vector3(row[1], 0, 0), Vector3(0, 0, row[2]))
		k.finish(0.002, 0.002)
		k.tint = shadow
		k.box(Vector3(side * 0.0042, 1.6185, _face_point(hd, 0.0, 1.62).z + nout * 0.42), Vector3(0.0017, 0.0009, 0.0024)) # nostril
		k.paint(o.skin, 0.72)
	# ears: a rim and a lobe standing off the side of the head, angled back
	var ear_x := _face_w(hd.rows, 1.652) + 0.004
	for side: float in [1.0, -1.0]:
		k.xf = Transform3D(Basis(Vector3.UP, side * -0.32) * Basis(Vector3.BACK, side * 0.10), Vector3(side * ear_x, 1.652, -0.006))
		k.begin(8)
		for row: Array in [[-0.026, 0.0038, 0.0075], [-0.019, 0.0050, 0.0105], [-0.006, 0.0058, 0.0145], [0.010, 0.0058, 0.0150], [0.022, 0.0048, 0.0118], [0.029, 0.0030, 0.0065]]:
			k.ring(Vector3(0, row[0], 0), Vector3(row[1], 0, 0), Vector3(0, 0, row[2]))
		k.finish(0.002, 0.002)
		k.tint = Color(skin.r * 0.84, skin.g * 0.72, skin.b * 0.68)
		k.box(Vector3(side * 0.0046, 0.003, 0.001), Vector3(0.0010, 0.010, 0.0050)) # the hollow
		k.xf = Transform3D.IDENTITY
		k.paint(o.skin, 0.72)
	# eyes: socket-set whites, irises, a dark lash line under the upper lid
	var es: float = f.eye
	var eye_x := 0.029 * lerpf(1.0, sh.face, 0.5)
	for side: float in [1.0, -1.0]:
		var s := _face_point(hd, side * eye_x, 1.670)
		var eye_turn := Basis(Vector3.UP, side * 0.34)
		k.paint("d8d0bd", 0.45)
		k.mat = MAT_PLAIN
		k.box(s + eye_turn * Vector3(0, 0, -0.0012), Vector3(0.0102 * es, 0.0041 * es, 0.0028), eye_turn)
		k.paint(o.get("iris", "3b2f25"), 0.35)
		k.mat = MAT_PLAIN
		k.box(s + eye_turn * Vector3(-side * 0.0009, -0.0003, 0.0019), Vector3(0.0042 * es, 0.0040 * es, 0.0009), eye_turn)
		k.tint = Color(0.06, 0.05, 0.045)
		k.box(s + eye_turn * Vector3(-side * 0.0009, -0.0003, 0.0029), Vector3(0.0017 * es, 0.0017 * es, 0.0004), eye_turn) # pupil
		k.tint = shadow
		k.box(s + eye_turn * Vector3(0, 0.0046 * es, 0.0006), Vector3(0.0112 * es, 0.0015, 0.0024), eye_turn * Basis(Vector3.BACK, side * -0.07)) # upper lid
		k.tint = Color(skin.r * 0.86, skin.g * 0.78, skin.b * 0.74)
		k.mat = MAT_SKIN
		k.box(s + eye_turn * Vector3(0, -0.0047 * es, 0.0004), Vector3(0.0096 * es, 0.0011, 0.0022), eye_turn) # lower lid
	# brows: two strokes each, the inner end lowered for a scowl (raised for a worried man)
	k.paint(o.hair, 0.8)
	k.mat = MAT_HAIR
	var bh: float = f.brow_h
	var bin: float = f.brow_in
	for side: float in [1.0, -1.0]:
		var inner := Vector2(side * 0.010, 1.6835 + bin)
		var mid := Vector2(side * 0.026, 1.6875)
		var outer := Vector2(side * 0.045, 1.6855)
		_face_stroke(k, hd, inner, mid, bh * 1.05, 0.0012, 0.0035)
		_face_stroke(k, hd, mid, outer, bh * 0.85, 0.0012, 0.0035)
	# mouth: the line of the lips and a fuller lower lip
	var mw := 0.0185 * lerpf(1.0, sh.jaw, 0.4)
	var droop: float = f.mouth
	k.tint = shadow
	k.surf = Vector2(0.6, 0.0)
	k.mat = MAT_SKIN
	_face_stroke(k, hd, Vector2(-mw, 1.5990 - droop), Vector2(-mw * 0.35, 1.5996), 0.0019, 0.0005, 0.002)
	_face_stroke(k, hd, Vector2(-mw * 0.35, 1.5996), Vector2(mw * 0.35, 1.5996), 0.0019, 0.0005, 0.002)
	_face_stroke(k, hd, Vector2(mw * 0.35, 1.5996), Vector2(mw, 1.5990 - droop), 0.0019, 0.0005, 0.002)
	k.tint = Color(skin.r * 0.86, skin.g * 0.64, skin.b * 0.60)
	_face_stroke(k, hd, Vector2(-mw * 0.6, 1.5953), Vector2(mw * 0.6, 1.5953), 0.0040, 0.0001, 0.0026) # lower lip
	# sideburns in front of the ears
	k.paint(o.hair, 0.8)
	k.mat = MAT_HAIR
	var burn: float = o.get("burns", 0.016)
	for side: float in [1.0, -1.0]:
		k.box(Vector3(side * (_face_w(hd.rows, 1.664) - 0.0015), 1.676 - burn, 0.012), Vector3(0.0035, burn, 0.0085))
	_build_tache(k, o, hd)
	# hair sits over the back and crown, leaving the face clear
	k.paint(o.hair, 0.8)
	k.mat = MAT_HAIR
	var hw := [lerpf(1.0, sh.face, 0.5), sh.face, lerpf(sh.face, 1.0, 0.5), 1.0, 1.0]
	k.ytube([[1.615, 0.058 * hw[0], 0.044, -0.052, 0, 0.9], [1.65, 0.078 * hw[1], 0.060, -0.045], [1.70, 0.080 * hw[2], 0.076, -0.034], [1.75, 0.074, 0.092, -0.010], [1.782, 0.046, 0.060, -0.010]], 10, 2.2, -1.0, 0.012)
	k.gr = g

## Belt in stock measurements; it follows the waist (and goes round a belly).
static func _belt(k: Kit, hex: String, rough: float, rx: float, rz: float, y: float = 1.05) -> void:
	k.paint(hex, rough)
	k.bind(SPINE, HIPS)
	k.trunk_tube([[y - 0.024, rx, rz, 0, 0.5], [y + 0.024, rx, rz, 0, 0.3]], 12, 2.5)

## Brass buckle on the front of a belt (stock measurements, like _belt).
static func _buckle(k: Kit, rz: float, y: float = 1.05) -> void:
	k.paint("9a8248", 0.35, 0.55)
	k.bind(SPINE)
	k.box(k.fit(Vector3(0, y, rz + 0.006)), Vector3(0.021, 0.019, 0.0045))
	k.paint("6a5a30", 0.4, 0.5)
	k.box(k.fit(Vector3(0, y, rz + 0.0105)), Vector3(0.0035, 0.012, 0.0015))

## A buckle or keeper on a strap that hugs the torso, between two points of its path.
static func _strap_buckle(k: Kit, a: Vector2, b: Vector2, width: float) -> void:
	var p := k.hug(lerpf(a.x, b.x, 0.5), lerpf(a.y, b.y, 0.5), 0.011)
	var along := (k.hug(b.x, b.y, 0.011) - k.hug(a.x, a.y, 0.011)).normalized()
	var out := (k.hug(lerpf(a.x, b.x, 0.5), lerpf(a.y, b.y, 0.5), 0.03) - p).normalized()
	k.paint("8e7a46", 0.35, 0.5)
	k.strap(p - along * 0.009, p + along * 0.009, width + 0.008, out, 0.006)

## A pouch standing on the torso at `deg` round the body (90 = front), `y` up.
static func _pouch_on(k: Kit, deg: float, y: float, half: Vector3) -> void:
	_pouch(k, k.hug(deg, y, half.z + 0.003), half, deg_to_rad(90.0 - deg))

## Steel helmet: a round bowl over a skirt that flares out and comes down over the ears and the
## nape, cut short and high over the eyes. Bind HEAD (and set any tilt in k.xf) before calling.
static func _steel_helmet(k: Kit) -> void:
	var c := Vector3(0, 1.716, -0.008)
	var rx := 0.105
	var rz := 0.124
	var top := 0.118
	var rim := func(phi: float) -> float:
		var ap := absf(phi)
		return 1.703 - 0.048 * smoothstep(0.45, 1.05, ap) - 0.027 * smoothstep(1.3, 2.9, ap)
	var flare := func(phi: float) -> float:
		return 0.06 + 0.075 * smoothstep(0.40, 1.20, absf(phi))
	var hn := 22
	var _rows: Array = [] # [y from rim (or -1 for the dome), how far up the skirt, radius scale]
	k.begin(hn)
	for step: int in range(5):
		var pts: Array = []
		for i: int in range(hn):
			var phi := TAU * (float(i) + 0.5) / float(hn) - PI
			var r0: float = rim.call(phi)
			var fl: float = flare.call(phi)
			var y: float = [r0 + 0.006, r0, r0 + 0.004, lerpf(r0, c.y, 0.45), c.y - 0.003][step]
			var sc: float = [0.93, 1.0 + fl, 1.0 + fl * 0.95, 1.0 + fl * 0.40, 1.012][step]
			pts.append(Vector3(-sin(phi) * rx * sc, y, c.z + cos(phi) * rz * sc))
		k.ring_points(Vector3(0, c.y - 0.03, c.z), pts, 0.0, [0.55, 0.8, 0.95, 1.0, 1.0][step])
	for deg: float in [12.0, 26.0, 40.0, 54.0, 67.0, 79.0]:
		var th := deg_to_rad(deg)
		var pts: Array = []
		for i: int in range(hn):
			var phi := TAU * (float(i) + 0.5) / float(hn) - PI
			pts.append(Vector3(-sin(phi) * rx * cos(th), c.y + top * sin(th), c.z + cos(phi) * rz * cos(th)))
		k.ring_points(Vector3(0, c.y + top * sin(th), c.z), pts)
	k.finish(-1.0, 0.012)
	for side: float in [1.0, -1.0]:
		k.box(Vector3(side * rx * cos(0.36) * 1.005, c.y + top * sin(0.36), c.z), Vector3(0.003, 0.0055, 0.0055)) # vent lug

## Peaked service cap: dark band piped in white, a crown that rises high at the front, a glossy
## peak, a silver cord, and the cap badges.
static func _peaked_cap(k: Kit, o: Dictionary) -> void:
	k.paint("2b3a2f", 0.8)
	k.ytube([[1.711, 0.082, 0.102, -0.002, 0, 0.85], [1.757, 0.085, 0.105, -0.003]], 14, 2.2)
	k.paint("c9c7b5", 0.7)
	for y: float in [1.712, 1.756]:
		k.ytube([[y - 0.0015, 0.0835, 0.1035, -0.002], [y + 0.0015, 0.0835, 0.1035, -0.002]], 14, 2.2)
	k.paint(o.top, 0.92)
	var hn := 18
	k.begin(hn)
	for step: int in range(4):
		var pts: Array = []
		for i: int in range(hn):
			var phi := TAU * (float(i) + 0.5) / float(hn) - PI
			var rise := exp(-pow(phi / 0.75, 2.0)) # the saddle: high in front
			var y: float = [1.756, 1.792 + 0.022 * rise, 1.810 + 0.034 * rise, 1.818 + 0.032 * rise][step]
			var sc: float = [1.0, 1.36, 1.42, 1.28][step]
			pts.append(Vector3(-sin(phi) * 0.086 * sc, y, 0.002 + cos(phi) * 0.104 * sc))
		k.ring_points(Vector3(0, 1.78, 0.002), pts, 0.0, [0.8, 0.95, 1.0, 1.0][step])
	k.finish(-1.0, 0.004)
	k.paint("c9c7b5", 0.7) # piping round the crown
	k.begin(hn)
	for lift: float in [-0.0016, 0.0016]:
		var pts: Array = []
		for i: int in range(hn):
			var phi := TAU * (float(i) + 0.5) / float(hn) - PI
			var rise := exp(-pow(phi / 0.75, 2.0))
			pts.append(Vector3(-sin(phi) * 0.086 * 1.425, 1.810 + 0.034 * rise + lift, 0.002 + cos(phi) * 0.104 * 1.425))
		k.ring_points(Vector3(0, 1.81, 0.002), pts)
	k.finish()
	k.paint("101010", 0.25) # peak
	k.box(Vector3(0, 1.716, 0.122), Vector3(0.070, 0.0045, 0.034), Basis(Vector3.RIGHT, 0.55))
	k.paint("b9bab3", 0.35, 0.6) # chin cord and its buttons
	k.box(Vector3(0, 1.722, 0.104), Vector3(0.062, 0.0018, 0.0022))
	for side: float in [1.0, -1.0]:
		k.box(Vector3(side * 0.064, 1.722, 0.088), Vector3(0.002, 0.0035, 0.0035), Basis(Vector3.UP, side * 0.6))
	k.box(Vector3(0, 1.738, 0.1065), Vector3(0.0058, 0.0058, 0.0016)) # a plain cockade: no national insignia on the enemy (App Store 1.1.2)

## Side cap: a soft boat-shaped cap worn on top of the head, tipped to the right, its turned-up
## flap round the bottom, a plain cockade on the front.
static func _field_cap(k: Kit, o: Dictionary) -> void:
	k.xf = Transform3D(Basis(Vector3.BACK, 0.20), Vector3(-0.006, 1.70, 0.0)) * Transform3D(Basis.IDENTITY, Vector3(0, -1.70, 0))
	k.paint(o.get("cap_top", "5a5f51"), 0.95)
	var cap_shape := [[-0.0745, 0.0], [-0.066, 0.42], [-0.006, 1.0], [0.006, 1.0], [0.066, 0.42], [0.0745, 0.0]]
	k.begin(cap_shape.size())
	for z: float in [-0.092, -0.080, -0.05, 0.0, 0.05, 0.072, 0.082]:
		var end := smoothstep(0.06, 0.092, absf(z))
		var h := lerpf(0.056, 0.034, end)
		var wb := lerpf(0.075, 0.060, end)
		var y0 := 1.779 - 6.0 * z * z
		var pts: Array = []
		for row: Array in cap_shape:
			pts.append(Vector3(float(row[0]) / 0.0745 * wb, y0 + float(row[1]) * h, z))
		k.ring_points(Vector3(0, y0 + h * 0.4, z), pts, 0.0, 1.0)
	k.finish(0.0, 0.0)
	k.paint("4f5447", 0.95) # the turned-up flap
	for side: float in [1.0, -1.0]:
		k.box(Vector3(side * 0.0755, 1.783, 0.0), Vector3(0.0015, 0.0085, 0.078))
	k.paint("b9bab3", 0.6, 0.2)
	k.box(Vector3(0.0765, 1.783, 0.050), Vector3(0.0012, 0.0045, 0.0045)) # cockade
	k.xf = Transform3D.IDENTITY

## A baked guard's tunic marks, on the figure's own cloth: pale collar patches, piped shoulder
## straps along the tops of the shoulders, pocket flaps and buttons.
static func _baked_tunic(k: Kit, o: Dictionary) -> void:
	if o.get("shirt", false): return
	var meta: Dictionary = o.fig_meta
	var sergeant: bool = o.gk == "sergeant"
	var button := Color(o.get("button", "7d7f78"))
	k.bind(CHEST)
	if meta.has("collar"):
		# collar patches: two pale bars on each front of the collar
		k.paint("a7a99b" if not sergeant else "c3c4bc", 0.6, 0.1)
		for t: Array in meta.collar.tabs:
			var at := Vector3(float(t[0]), float(t[1]), float(t[2]))
			var side := signf(at.x)
			k.box(at + Vector3(-side * 0.004, -0.002, 0.003), Vector3(0.010, 0.0065, 0.0016), Basis(Vector3.UP, side * 0.5) * Basis(Vector3.RIGHT, -0.5))
	var line: Array = meta.get("shoulder_line", [])
	if line.size() >= 3 and not o.coat:
		var a: Array = line[0]
		var b: Array = line[min(4, line.size() - 1)]
		for side: float in [1.0, -1.0]:
			var p0 := Vector3(side * float(a[0]), float(a[1]) + 0.004, float(a[2]))
			var p1 := Vector3(side * float(b[0]), float(b[1]) + 0.004, float(b[2]))
			k.paint("c9c7b5" if not sergeant else "b9bab3", 0.8, 0.0 if not sergeant else 0.3)
			k.strap(p0, p1, 0.041, Vector3.UP, 0.0022)
			k.paint(o.get("strap", o.top), 0.9)
			k.strap(p0 + Vector3(0, 0.001, 0), p1 + Vector3(0, 0.001, 0), 0.034, Vector3.UP, 0.0024)
			k.tint = button
			k.surf = Vector2(0.5, 0.2)
			k.box(p0.lerp(p1, 0.12) + Vector3(0, 0.003, 0), Vector3(0.0055, 0.003, 0.0055))
	if not o.coat:
		k.paint(o.top, 0.95)
		for deg: float in [62.0, 118.0]:
			k.ribbon([[deg, 1.385], [deg, 1.345]], 0.088, 0.007, 0.85) # pocket flaps
		k.tint = button
		k.surf = Vector2(0.5, 0.2)
		for deg: float in [62.0, 118.0]:
			k.box(k.hug(deg, 1.356, 0.010), Vector3(0.0055, 0.0055, 0.0025), Basis(Vector3.UP, deg_to_rad(90.0 - deg)))

## A collar, scarf or similar ring of cloth round the neck, sized for this man's neck.
static func _neck_wrap(k: Kit, o: Dictionary, rows: Array, n: int) -> void:
	var grow := lerpf(1.0, o.shape.neck, 0.85)
	var shaped: Array = []
	for row: Array in rows:
		var r := row.duplicate()
		r[1] = float(row[1]) * grow
		r[2] = float(row[2]) * grow
		shaped.append(r)
	k.ytube(shaped, n)

static func _pouch(k: Kit, at: Vector3, half: Vector3, yaw: float) -> void:
	var rot := Basis(Vector3.UP, yaw)
	k.box(at, half, rot)
	k.box(at + rot * Vector3(0, half.y * 0.55, half.z * 0.25), Vector3(half.x * 1.06, half.y * 0.5, half.z * 0.95), rot, 0.9) # flap

static func _gear_wren(k: Kit, o: Dictionary) -> void:
	# beret, pulled down over the right ear (a baked figure wears its own, shaped to the head)
	if not _fig_part(o, "hat"):
		k.pre = _head_fit(o)
		k.bind(HEAD)
		k.xf = Transform3D(Basis(Vector3.BACK, -0.16), Vector3(0, 1.74, 0)) * Transform3D(Basis.IDENTITY, Vector3(0, -1.74, 0))
		k.paint("1f2a20", 0.85)
		k.ytube([[1.722, 0.080, 0.100, -0.002], [1.748, 0.082, 0.102, -0.002]], 10, 2.2)
		k.paint("38493a", 0.95)
		k.ytube([[1.744, 0.083, 0.103, -0.002, 0, 0.85], [1.762, 0.108, 0.118, -0.006], [1.782, 0.112, 0.120, -0.010], [1.798, 0.080, 0.090, -0.012]], 10, 2.2, -1.0, 0.008)
		k.xf = Transform3D(Basis(Vector3.BACK, -0.16), Vector3(-0.022, 1.74, 0)) * Transform3D(Basis.IDENTITY, Vector3(0, -1.74, 0))
		k.paint("38493a", 0.95)
		k.ytube([[1.765, 0.11, 0.115, -0.008], [1.788, 0.108, 0.112, -0.010]], 10, 2.2, -1.0, 0.012)
		k.xf = Transform3D.IDENTITY
		k.pre = Transform3D.IDENTITY
	# drab neck scarf
	if not _fig_part(o, "scarf"):
		k.paint("6c6a4b", 0.97)
		k.bind(CHEST, HEAD)
		_neck_wrap(k, o, [[1.478, 0.082, 0.080, -0.006, 0.0, 0.85], [1.505, 0.072, 0.074, -0.006, 0.15], [1.535, 0.062, 0.066, -0.008, 0.4, 0.9]], 8)
	# light webbing: belt, two small pouches, cross strap to a satchel of throwables on the left hip
	_belt(k, o.web, 0.9, 0.178, 0.125)
	_buckle(k, 0.125)
	k.paint("6f6a4a", 0.9)
	k.bind(SPINE)
	_pouch(k, k.fit(Vector3(0.09, 1.05, 0.128)), Vector3(0.036, 0.042, 0.02), 0.25)
	_pouch(k, k.fit(Vector3(-0.09, 1.05, 0.128)), Vector3(0.036, 0.042, 0.02), -0.25)
	k.paint(o.web, 0.9)
	k.bind(SPINE, CHEST)
	k.ribbon([[148, 1.492], [128, 1.40], [78, 1.20], [22, 1.07]], 0.04)
	k.ribbon([[212, 1.492], [232, 1.40], [282, 1.20], [338, 1.07]], 0.04)
	_strap_buckle(k, Vector2(128, 1.40), Vector2(78, 1.20), 0.04)
	# water bottle on the back of the right hip
	k.bind(HIPS)
	k.paint("525a44", 0.8)
	k.begin(8)
	for row: Array in [[0.865, 0.028], [0.885, 0.043], [0.985, 0.043], [1.005, 0.018]]:
		k.ring(k.fit(Vector3(-0.150, row[0], -0.105)), Vector3(row[1] * 0.72, 0, 0), Vector3(0, 0, row[1]))
	k.finish(0.006, 0.008)
	k.paint("2b2a24", 0.5)
	k.box(k.fit(Vector3(-0.150, 1.013, -0.105)), Vector3(0.010, 0.008, 0.010))
	k.paint(o.web, 0.9)
	k.box(k.fit(Vector3(-0.150, 0.955, -0.105)) + Vector3(0, 0, 0), Vector3(0.033, 0.006, 0.045))
	k.bind(HIPS)
	k.paint("77714f", 0.92)
	var bag := Basis(Vector3.UP, 0.35)
	k.xf = Transform3D(bag, k.fit(Vector3(0.205, 0.965, -0.03)))
	k.begin(8, 3.4)
	for row: Array in [[-0.085, 0.040, 0.085], [-0.06, 0.052, 0.10], [0.06, 0.052, 0.10], [0.085, 0.040, 0.085]]:
		k.ring(Vector3(0, row[0], 0), Vector3(row[1], 0, 0), Vector3(0, 0, row[2]))
	k.finish(0.004, 0.004)
	k.paint("686344", 0.92)
	k.box(Vector3(0.03, 0.035, 0), Vector3(0.030, 0.055, 0.094)) # flap
	k.paint("2f2a22", 0.6)
	k.box(Vector3(0.062, 0.0, 0), Vector3(0.003, 0.012, 0.012))
	k.xf = Transform3D.IDENTITY
	# holster on the right hip, knife sheath across the back of the belt
	k.paint("2f251d", 0.55)
	k.bind(HIPS, THIGH_R)
	k.box(k.fit(Vector3(-0.192, 0.885, 0.035)), Vector3(0.020, 0.085, 0.034), Basis(Vector3.RIGHT, 0.06))
	k.bind(HIPS)
	k.box(k.fit(Vector3(-0.02, 1.03, -0.132)), Vector3(0.105, 0.019, 0.010), Basis(Vector3.BACK, 0.22))
	_build_pistol(k, true)
	_build_knife(k)

static func _gear_rook(k: Kit, o: Dictionary) -> void:
	# soft peaked field cap
	if not _fig_part(o, "hat"):
		k.pre = _head_fit(o)
		k.bind(HEAD)
		k.paint("6c6345", 0.95)
		k.ytube([[1.722, 0.081, 0.101, -0.002, 0, 0.85], [1.75, 0.084, 0.104, -0.004], [1.792, 0.080, 0.100, -0.008], [1.80, 0.066, 0.086, -0.008]], 10, 2.6, -1.0, 0.004)
		k.box(Vector3(0, 1.738, 0.118), Vector3(0.066, 0.006, 0.040), Basis(Vector3.RIGHT, 0.28), 0.9)
		k.pre = Transform3D.IDENTITY
	# webbing: belt (slung low under the belly), braces, two utility pouches
	var belt_y: float = 1.05 - minf(o.shape.belly, 0.06) * 0.7
	_belt(k, o.web, 0.9, 0.178, 0.125, belt_y)
	_buckle(k, 0.125, belt_y)
	# a carpenter's pencil in the left breast pocket
	k.bind(CHEST)
	k.paint("b8933a", 0.6)
	k.box(k.hug(64.0, 1.393, 0.005), Vector3(0.0028, 0.020, 0.0028), Basis(Vector3.BACK, 0.12))
	k.paint("2a2620", 0.5)
	k.box(k.hug(64.0, 1.393, 0.005) + Vector3(-0.0026, 0.021, 0), Vector3(0.0022, 0.003, 0.0022))
	k.paint(o.web, 0.9)
	k.bind(SPINE, CHEST)
	for side: float in [1.0, -1.0]:
		k.ribbon([[90 - side * 52, 1.494], [90 - side * 36, 1.40], [90 - side * 36, 1.08]], 0.045)
		k.ribbon([[270 + side * 52, 1.494], [270 + side * 38, 1.42], [270 + side * 30, 1.34]], 0.045)
	k.paint("8d8660", 0.9)
	k.bind(SPINE)
	_pouch_on(k, 6.0, belt_y + 0.004, Vector3(0.040, 0.052, 0.020))
	_pouch_on(k, 174.0, belt_y + 0.004, Vector3(0.040, 0.052, 0.020))
	# engineer's pack with tool roll, rope coil and wire cutters
	k.bind(CHEST)
	k.paint("837d57", 0.93)
	k.begin(8, 3.6)
	for row: Array in [[1.13, 0.13, 0.060], [1.17, 0.15, 0.082], [1.38, 0.15, 0.082], [1.43, 0.135, 0.066]]:
		k.ring(k.fit(Vector3(0, row[0], -0.186)), Vector3(row[1], 0, 0), Vector3(0, 0, row[2]))
	k.finish(0.006, 0.006)
	k.paint("77714e", 0.93)
	k.box(k.fit(Vector3(0, 1.385, -0.196)), Vector3(0.152, 0.055, 0.086)) # flap
	k.paint(o.web, 0.9)
	for side: float in [1.0, -1.0]:
		k.box(k.fit(Vector3(0, 1.30, -0.273)) + Vector3(side * 0.075, 0, 0), Vector3(0.012, 0.11, 0.005))
	k.paint("5d5a45", 0.95) # tool roll
	k.begin(7)
	for row: Array in [[-0.165, 0.030], [-0.15, 0.048], [0.15, 0.048], [0.165, 0.030]]:
		k.ring(k.fit(Vector3(0, 1.492, -0.181)) + Vector3(row[0], 0, 0), Vector3(0, row[1], 0), Vector3(0, 0, row[1]))
	k.finish(0.004, 0.004)
	k.paint("2f2a22", 0.6)
	for x: float in [-0.09, 0.09]:
		k.box(k.fit(Vector3(0, 1.492, -0.181)) + Vector3(x, 0, 0), Vector3(0.012, 0.051, 0.051))
	k.paint("b6a77d", 0.97) # rope
	k.torus(k.fit(Vector3(0, 1.255, -0.277)), Basis(Vector3.RIGHT, PI / 2), 0.082, 0.02, 12, 5)
	k.torus(k.fit(Vector3(0, 1.255, -0.299)) + Vector3(0.004, 0, 0), Basis(Vector3.RIGHT, PI / 2 + 0.1), 0.074, 0.018, 12, 5)
	k.paint(o.web, 0.9) # loop that holds the wire cutters against the side of the pack
	k.box(k.fit(Vector3(0, 1.25, -0.19)) + Vector3(0.158, 0, 0), Vector3(0.012, 0.02, 0.03))
	# water bottle on the right hip
	k.bind(HIPS)
	k.paint("4f5540", 0.8)
	k.begin(7)
	for row: Array in [[0.87, 0.030], [0.89, 0.046], [1.0, 0.046], [1.02, 0.02]]:
		k.ring(k.fit(Vector3(-0.185, row[0], -0.07)), Vector3(row[1] * 0.75, 0, 0), Vector3(0, 0, row[1]))
	k.finish(0.006, 0.01)
	# revolver holster on the left hip
	k.paint("4a3323", 0.6)
	k.bind(HIPS, THIGH_L)
	k.box(k.fit(Vector3(0.192, 0.90, 0.03)), Vector3(0.022, 0.08, 0.036), Basis(Vector3.RIGHT, 0.06))
	_build_revolver(k)
	_build_cutters(k)

## Rype: the ski scout's kit over his white anorak: a white webbing belt, the straps of his rucksack, the rucksack in
## its white cover with the climbing rope coiled on top, and snow goggles pushed up on the hood.
static func _gear_rype(k: Kit, o: Dictionary) -> void:
	_belt(k, o.web, 0.9, 0.182, 0.128)
	_buckle(k, 0.128)
	k.paint("c3c8cc", 0.95)
	k.bind(SPINE, CHEST)
	k.ribbon([[32, 1.492], [26, 1.37], [36, 1.21]], 0.034)
	k.ribbon([[328, 1.492], [334, 1.37], [324, 1.21]], 0.034)
	k.bind(CHEST)
	k.paint("d2d6d9", 0.95)
	var pack := k.fit(Vector3(0, 1.27, -0.205))
	k.box(pack, Vector3(0.135, 0.16, 0.065))
	k.paint("c0c5c9", 0.95)
	k.box(pack + Vector3(0, 0.13, 0.01), Vector3(0.12, 0.035, 0.06))
	k.box(pack + Vector3(0, -0.03, -0.07), Vector3(0.09, 0.07, 0.012))
	# the rope, coiled and strapped on top of the pack
	k.paint("b8a77a", 0.9)
	var top := pack + Vector3(0, 0.19, 0.0)
	k.begin(6)
	for i: int in range(17):
		var a := TAU * float(i) / 16.0
		var radial := Vector3(cos(a), 0, sin(a) * 0.62)
		k.ring(top + radial * 0.105, Vector3(cos(a), 0, sin(a)) * 0.024, Vector3(0, 0.024, 0))
	k.finish()
	# snow goggles up on the hood
	if o.has("fig_meta"):
		var head: Dictionary = o.fig_meta.get("head", {})
		var y: float = float(head.get("brow", 1.65)) + 0.034
		var z: float = float(head.get("front", 0.1)) + 0.016
		k.bind(HEAD)
		k.paint("2b2e33", 0.3, 0.3)
		for sx: float in [-0.031, 0.031]:
			k.box(Vector3(sx, y, z), Vector3(0.022, 0.014, 0.008))
		k.paint("5a5650", 0.8)
		k.box(Vector3(0, y, z - 0.002), Vector3(0.012, 0.006, 0.006))

## The watchman's spectacles: two round wire rims, the bridge, the arms back to his ears.
static func _spectacles(k: Kit, o: Dictionary, hex: String = "3a332a") -> void:
	if not o.has("fig_meta"): return
	var head: Dictionary = o.fig_meta.get("head", {})
	var y: float = float(head.get("brow", 1.65)) - 0.024
	var z: float = float(head.get("front", 0.1)) + 0.004
	k.bind(HEAD)
	k.paint(hex, 0.4, 0.5)
	for sx: float in [-0.031, 0.031]:
		k.begin(4)
		for i: int in range(13):
			var a := TAU * float(i) / 12.0
			k.ring(Vector3(sx + cos(a) * 0.016, y + sin(a) * 0.014, z), Vector3(0, 0, 0.0016), Vector3(cos(a), sin(a), 0) * 0.0016)
		k.finish()
		k.box(Vector3(sx * 2.25, y + 0.004, z - 0.04), Vector3(0.0015, 0.0015, 0.042))
	k.box(Vector3(0, y + 0.004, z + 0.002), Vector3(0.008, 0.0015, 0.0015))

## Merle: a cigarette in the corner of his mouth (its tip glowing), a docker's hook through his belt, a canvas
## musette bag on a strap across his chest. Cap, scarf and clothes are the baked figure's.
static func _gear_merle(k: Kit, o: Dictionary) -> void:
	if o.has("fig_meta"):
		var lm: Dictionary = o.fig_meta.landmarks
		var corner := Vector3(-absf(float(lm.corner[0])) * 0.55, float(lm.mouth[1]) + 0.001, float(lm.mouth[2]) + 0.002)
		var along := Vector3(-0.30, -0.22, 1.0).normalized()
		var rot := Basis(Vector3.UP, atan2(along.x, along.z)) * Basis(Vector3.RIGHT, asin(-along.y))
		k.bind(HEAD)
		k.paint("d9d3c3", 0.8)
		k.begin(6, 1.0)
		for t: float in [0.0, 0.004, 0.050, 0.054]:
			var r: float = 0.0042 if t > 0.0 and t < 0.054 else 0.0032
			k.ring(corner + along * t, rot * Vector3(r, 0, 0), rot * Vector3(0, r, 0))
		k.finish(0.0, 0.0)
		k.paint("e0682a", 0.4)
		k.box(corner + along * 0.057, Vector3(0.0040, 0.0040, 0.0030), rot)
	# belt
	_belt(k, o.web, 0.85, 0.172, 0.122)
	_buckle(k, 0.122)
	# the docker's hook: a wooden T-handle pushed through the belt on the right, the steel hook hanging below
	k.bind(HIPS)
	k.paint("6b5236", 0.8)
	k.box(k.fit(Vector3(-0.150, 1.05, 0.085)), Vector3(0.042, 0.011, 0.011), Basis(Vector3.BACK, 0.25))
	k.paint("4f4d48", 0.4, 0.6)
	k.box(k.fit(Vector3(-0.152, 0.995, 0.090)), Vector3(0.004, 0.045, 0.004))
	k.begin(6)
	for row: Array in [[0.95, 0.0, 0.004], [0.935, 0.012, 0.004], [0.94, 0.026, 0.0035], [0.958, 0.030, 0.003]]:
		k.ring(k.fit(Vector3(-0.152, row[0], 0.090 + row[1])), Vector3(row[2], 0, 0), Vector3(0, 0, row[2]))
	k.finish(0.002, 0.002)
	# canvas musette bag on the left hip, its strap over the right shoulder
	k.paint("6e674f", 0.95)
	k.bind(SPINE, CHEST)
	k.ribbon([[142, 1.492], [116, 1.37], [62, 1.18], [20, 1.07]], 0.03, 0.006)
	k.ribbon([[218, 1.492], [244, 1.37], [300, 1.18], [340, 1.07]], 0.03, 0.006)
	k.bind(HIPS)
	k.paint("736c53", 0.95)
	k.xf = Transform3D(Basis(Vector3.UP, 0.4), k.fit(Vector3(0.200, 0.955, 0.0)))
	k.begin(8, 3.2)
	for row: Array in [[-0.075, 0.035, 0.085], [-0.05, 0.046, 0.10], [0.05, 0.046, 0.10], [0.075, 0.036, 0.085]]:
		k.ring(Vector3(0, row[0], 0), Vector3(row[1], 0, 0), Vector3(0, 0, row[2]))
	k.finish(0.004, 0.004)
	k.paint("665f47", 0.95)
	k.box(Vector3(0.03, 0.03, 0), Vector3(0.026, 0.05, 0.09))
	k.xf = Transform3D.IDENTITY
	# two empty wine bottles from the shift, their necks out of the coat's left pocket
	k.bind(HIPS)
	k.paint("1e3326", 0.3, 0.1)
	for b: Array in [[Vector3(0.085, 0.985, 0.172), 0.12], [Vector3(0.122, 0.98, 0.165), -0.2]]:
		k.xf = Transform3D(Basis(Vector3.BACK, float(b[1])) * Basis(Vector3.RIGHT, 0.18), k.fit(b[0]))
		k.begin(8, 1.0)
		for row: Array in [[-0.03, 0.018], [0.0, 0.0095], [0.06, 0.0082], [0.066, 0.0102], [0.074, 0.007]]:
			k.ring(Vector3(0, row[0], 0), Vector3(row[1], 0, 0), Vector3(0, 0, row[1]))
		k.finish(0.0, 0.003)
	k.xf = Transform3D.IDENTITY

## Hornero: the bell from his tram, a brass hand bell with a turned wooden handle, hung mouth down on a short leather
## strap from the coat's belt at the front of his left hip (a little over scale, so that its brass reads from the
## camera). Cap, scarf, gloves and the belted coat are the baked figure's; the controller handle is _build_controller.
static func _gear_hornero(k: Kit, o: Dictionary) -> void:
	# placed on the baked coat as measured (tools/mh: the belt's front stands at z 0.22 over the left thigh, the
	# skirt below it at 0.19-0.22); the jacket's torso rows say too little about a coat this full
	var top := Vector3(0.150, 1.050, 0.229)
	var out := Vector3(0.66, 0.0, 0.75).normalized()
	var hang := Vector3(0.152, 0.990, 0.236)
	var yaw := atan2(out.x, out.z)
	k.weather = 0.0
	# the strap, a flat loop of leather from the belt to the handle's eye
	k.bind(HIPS)
	k.paint(o.web, 0.6)
	k.strap(top + Vector3(0, 0.012, 0), hang + out * 0.002, 0.016, out, 0.005)
	# the bell: handle on top, the brass cup below, its lip rolled out (local: y up, mouth down); it swings a little
	# with the left thigh
	k.bind(HIPS, THIGH_L)
	k.xf = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -0.08), hang)
	k.paint("4a2c18", 0.55)
	k.begin(8)
	for row: Array in [[0.002, 0.006], [-0.006, 0.010], [-0.020, 0.0125], [-0.034, 0.010], [-0.040, 0.0095]]:
		k.ring(Vector3(0, row[0], 0), Vector3(row[1], 0, 0), Vector3(0, 0, row[1]), 0.12)
	k.finish(0.003, 0.0)
	k.paint("b88c3e", 0.32, 0.75)
	k.begin(12)
	for row: Array in [[-0.040, 0.011], [-0.046, 0.019], [-0.056, 0.026], [-0.075, 0.029], [-0.093, 0.035], [-0.100, 0.040], [-0.103, 0.038], [-0.100, 0.031]]:
		k.ring(Vector3(0, row[0], 0), Vector3(row[1], 0, 0), Vector3(0, 0, row[1]), 0.15)
	k.finish(-1.0, 0.004)
	k.xf = Transform3D.IDENTITY
	k.weather = 1.0

## The tram's controller handle in TOOL space, swung like a cosh: the fist round its flat bronze arm, the brass socket
## that fits over the controller's shaft at the far end (+Z, the weight of it), and the turned wooden knob the
## motorman drives with standing off the near end (-Y). Only the shape of the thing; no maker's marks.
static func _build_controller(k: Kit) -> void:
	k.weather = 0.0
	k.bind(TOOL)
	k.paint("7a6034", 0.40, 0.7)
	k.begin(6, 3.0)
	for row: Array in [[-0.085, 0.012, 0.0055], [0.05, 0.013, 0.006], [0.150, 0.016, 0.0075]]:
		k.ring(Vector3(0, 0, row[0]), Vector3(row[1], 0, 0), Vector3(0, row[2], 0))
	k.finish(0.004, 0.0)
	# the socket: a short brass drum across the arm's end, a dark square hole through it
	k.paint("b08a46", 0.34, 0.75)
	k.begin(12)
	for row: Array in [[-0.017, 0.019], [-0.014, 0.024], [0.014, 0.024], [0.017, 0.019]]:
		k.ring(Vector3(0, row[0], 0.168), Vector3(row[1], 0, 0), Vector3(0, 0, row[1]))
	k.finish(0.0, 0.0)
	k.paint("15130f", 0.6)
	k.box(Vector3(0, 0, 0.168), Vector3(0.0075, 0.0175, 0.0075))
	# the knob, on a brass ferrule
	k.paint("b08a46", 0.34, 0.75)
	k.begin(8)
	for row: Array in [[0.0, 0.0085], [-0.010, 0.0085]]:
		k.ring(Vector3(0, row[0], -0.075), Vector3(row[1], 0, 0), Vector3(0, 0, row[1]))
	k.finish(0.0, -1.0)
	k.paint("4a2c18", 0.5)
	k.begin(8)
	for row: Array in [[-0.010, 0.010], [-0.022, 0.0135], [-0.052, 0.0145], [-0.074, 0.0130], [-0.080, 0.009]]:
		k.ring(Vector3(0, row[0], -0.075), Vector3(row[1], 0, 0), Vector3(0, 0, row[1]))
	k.finish(-1.0, 0.003)
	k.weather = 1.0

## The outside of a baked figure's clothes as a coarse map round the body's axis: in each sector of angle (from his
## left round by the front) and height, the furthest any vertex of the suit, coat, scarf or cape stands from the axis
## (the arms left out). For kit that wraps round him (a bag's strap, a coil of rope), where the torso rows the figure
## was measured by say too little of a jacket's back.
const SHELL_Y0: float = 0.80
const SHELL_DY: float = 0.02
const SHELL_NY: int = 40
const SHELL_NA: int = 48
static var _shells: Dictionary = {}

static func _shell(o: Dictionary) -> Dictionary:
	var fig := str(o.get("fig", ""))
	if _shells.has(fig): return _shells[fig]
	var f := Figure.load_fig(fig)
	var r := PackedFloat32Array()
	r.resize(SHELL_NA * SHELL_NY)
	var lo := 1e9
	var hi := -1e9
	var clothes: Array = []
	for sf: Dictionary in f.get("surfaces", []):
		if str(sf.name) in ["suit", "scarf", "cape"]: clothes.append(sf.arrays)
	# the axis: half-way between the front and the back of the chest
	for arrays: Array in clothes:
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for p: Vector3 in v:
			if absf(p.x) < 0.05 and p.y > 1.25 and p.y < 1.35:
				lo = minf(lo, p.z)
				hi = maxf(hi, p.z)
	var cz := (lo + hi) * 0.5 if hi > lo else 0.02
	for arrays: Array in clothes:
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for i: int in range(v.size()):
			var b := bones[i * 4]
			if b >= ARM_L and b <= HAND_R and weights[i * 4] > 0.5: continue
			var p := v[i]
			var iy := int((p.y - SHELL_Y0) / SHELL_DY)
			if iy < 0 or iy >= SHELL_NY: continue
			var ia := int(fposmod(atan2(p.z - cz, p.x), TAU) / TAU * SHELL_NA) % SHELL_NA
			var d := Vector2(p.x, p.z - cz).length()
			if d > r[iy * SHELL_NA + ia]: r[iy * SHELL_NA + ia] = d
	# a sector no vertex fell in takes the furthest of its neighbours (the clothes are sparse in places)
	for _round: int in range(3):
		var filled := r.duplicate()
		for iy: int in range(SHELL_NY):
			for ia: int in range(SHELL_NA):
				if r[iy * SHELL_NA + ia] > 0.0: continue
				var best := 0.0
				for dy: int in [-1, 0, 1]:
					var y2 := iy + dy
					if y2 < 0 or y2 >= SHELL_NY: continue
					for da: int in [-1, 0, 1]:
						best = maxf(best, r[y2 * SHELL_NA + (ia + da + SHELL_NA) % SHELL_NA])
				filled[iy * SHELL_NA + ia] = best
		r = filled
	var out := {"r": r, "cz": cz}
	_shells[fig] = out
	return out

## A point standing `lift` off the outside of his clothes at `deg` round the body (0 his left, 90 the front, 270 the
## back) and `y` up: the furthest the clothes reach in the sectors round it, so nothing comes through.
static func _on_shell(o: Dictionary, deg: float, y: float, lift: float) -> Vector3:
	var sh := _shell(o)
	var r: PackedFloat32Array = sh.r
	var a := deg_to_rad(deg)
	var iy := clampi(int((y - SHELL_Y0) / SHELL_DY), 0, SHELL_NY - 2)
	var ia := int(fposmod(a, TAU) / TAU * SHELL_NA)
	var best := 0.0
	for dy: int in [0, 1]:
		for da: int in [-1, 0, 1]:
			best = maxf(best, r[(iy + dy) * SHELL_NA + (ia + da + SHELL_NA) % SHELL_NA])
	if best <= 0.0: best = 0.15
	return Vector3(cos(a) * (best + lift), y, float(sh.cz) + sin(a) * (best + lift))

## A flat strap laid round the outside of his clothes along `path` ([[deg, y], ...]), shared between the spine and the
## chest as it climbs. Bind SPINE -> CHEST before calling.
static func _shell_strap(k: Kit, o: Dictionary, path: Array, width: float, lift: float) -> void:
	var pts: Array[Vector2] = []
	for i: int in range(path.size() - 1):
		var from := Vector2(path[i][0], path[i][1])
		var to := Vector2(path[i + 1][0], path[i + 1][1])
		var steps := maxi(2, int(ceil(maxf(absf(to.x - from.x) / 8.0, absf(to.y - from.y) / 0.03))))
		for j: int in range(steps):
			pts.append(from.lerp(to, float(j) / float(steps)))
	pts.append(Vector2(path[-1][0], path[-1][1]))
	var first := k.v.size()
	for i: int in range(pts.size()):
		var p := _on_shell(o, pts[i].x, pts[i].y, lift)
		var out := Vector3(cos(deg_to_rad(pts[i].x)), 0.0, sin(deg_to_rad(pts[i].x)))
		var before := pts[maxi(i - 1, 0)]
		var after := pts[mini(i + 1, pts.size() - 1)]
		var along := (_on_shell(o, after.x, after.y, lift) - _on_shell(o, before.x, before.y, lift)).normalized()
		var side := along.cross(out).normalized() * width * 0.5
		var blend := smoothstep(1.10, 1.30, pts[i].y)
		for sgn: float in [-1.0, 1.0]:
			var index := k._put(k._world(p + side * sgn), blend, 1.0)
			k.nrm[index] = out
		if i > 0:
			var q := first + i * 2
			k._tri(q - 2, q - 1, q + 1, out)
			k._tri(q - 2, q + 1, q, out)

## Where Riachuelo's kit hangs from a baked coat's belt: its height and how far it stands off the jacket's torso rows
## (the coat's skirt and the belt round it are wider than the jacket they are measured from).
static func _belt_line(k: Kit, o: Dictionary) -> Vector2:
	var belt: Array = o.fig_meta.get("coat_belt", [1.056, 0.0]) if o.has("fig_meta") else [1.056, 0.0]
	var y := float(belt[0])
	var lift := maxf(float(belt[1]) - k.hug(90.0, y, 0.0).z, 0.0) if float(belt[1]) > 0.0 else 0.012
	return Vector2(y, lift)

## Lechuza: the night lineman's kit. Round steel spectacles; on the leather tool belt over his coat (the baked figure's)
## a pouch with the pliers' insulated grips standing out of it on his right hip, the board's sector key and two smaller
## keys on a steel ring at the front of his left hip, a coil of black electrician's cord on the left side; and the short
## folding wooden ladder on his right shoulder, standing on edge with its lower rail on the shoulder, hinged at the
## middle of each rail. He ties guards up with the cord (melee bind): no tool to draw.
static func _gear_lechuza(k: Kit, o: Dictionary) -> void:
	_spectacles(k, o, "8b8e90")
	var bl := _belt_line(k, o)
	k.weather = 0.0
	# the pliers' pouch, its flap open, two red grips standing out of it
	k.bind(HIPS, THIGH_R)
	var deg := 148.0
	var turn := Basis(Vector3.UP, deg_to_rad(90.0 - deg))
	var at := k.hug(deg, bl.x - 0.075, bl.y + 0.016)
	k.paint("3b2a1c", 0.62)
	k.box(at, Vector3(0.034, 0.060, 0.014), turn)
	k.box(at + turn * Vector3(0, 0.050, -0.012), Vector3(0.036, 0.018, 0.004), turn * Basis(Vector3.RIGHT, -0.5))
	k.paint("8e2b20", 0.6)
	for dx: float in [-0.009, 0.009]:
		k.box(at + turn * Vector3(dx, 0.083, -0.002), Vector3(0.0055, 0.032, 0.0055), turn * Basis(Vector3.BACK, dx * 9.0))
	k.paint("6f7376", 0.4, 0.6)
	k.box(at + turn * Vector3(0, 0.050, -0.002), Vector3(0.012, 0.006, 0.004), turn)
	# the keys: a steel ring hanging from the belt, the long T-handled sector key and two small keys on it
	k.bind(HIPS, THIGH_L)
	deg = 58.0
	turn = Basis(Vector3.UP, deg_to_rad(90.0 - deg))
	at = k.hug(deg, bl.x - 0.050, bl.y + 0.012)
	k.paint("9a9c9e", 0.35, 0.8)
	k.torus(at, turn * Basis(Vector3.RIGHT, PI / 2.0), 0.020, 0.0028, 12, 4)
	k.box(at + turn * Vector3(0.004, -0.070, 0.004), Vector3(0.0045, 0.052, 0.0045), turn * Basis(Vector3.BACK, 0.10))
	k.box(at + turn * Vector3(0.010, -0.122, 0.004), Vector3(0.020, 0.005, 0.005), turn * Basis(Vector3.BACK, 0.10))
	k.paint("b49a5a", 0.35, 0.7)
	k.box(at + turn * Vector3(-0.014, -0.036, 0.003), Vector3(0.006, 0.022, 0.002), turn * Basis(Vector3.BACK, -0.35))
	k.box(at + turn * Vector3(-0.004, -0.040, 0.006), Vector3(0.006, 0.024, 0.002), turn * Basis(Vector3.BACK, -0.12))
	# the cord: a coil of black rubber cable on the left side, hung flat against the coat
	deg = 18.0
	turn = Basis(Vector3.UP, deg_to_rad(90.0 - deg))
	at = k.hug(deg, bl.x - 0.105, bl.y + 0.030)
	k.paint("1d1c1b", 0.55)
	for i: int in range(3):
		k.torus(at + turn * Vector3(0.004 * i, -0.004 * i, 0.010 * i - 0.010), turn * Basis(Vector3.BACK, PI / 2.0), 0.056 - 0.004 * i, 0.0075, 14, 5)
	k.paint("3b2a1c", 0.62)
	k.box(at + turn * Vector3(0, 0.060, 0.0), Vector3(0.010, 0.020, 0.004), turn)
	# the ladder, carried on the right shoulder: front end a little down, more of it behind him than in front
	k.bind(CHEST)
	var along := Vector3(0, -0.20, 1.0).normalized()
	var up := (Basis(along, 0.38) * Vector3(0, 1.0, 0.20)).normalized()
	var base := Vector3(-o.shape.shoulder - 0.010, 1.515, -0.04)
	var rot := Basis(up.cross(along).normalized(), up, along)
	var s0 := -0.66
	var s1 := 0.50
	var gap := 0.29
	k.paint("75614a", 0.85)
	for r: int in range(2):
		var mid := base + up * (gap * float(r)) + along * ((s0 + s1) * 0.5)
		k.box(mid, Vector3(0.015, 0.024, (s1 - s0) * 0.5), rot)
	k.paint("65523d", 0.85)
	var s := s0 + 0.07
	while s < s1 - 0.04:
		k.begin(6)
		var c := base + along * s
		k.ring(c + up * 0.012, rot.x * 0.012, along * 0.012)
		k.ring(c + up * (gap - 0.012), rot.x * 0.012, along * 0.012)
		k.finish()
		s += 0.235
	# the hinge on each rail where the two halves fold, and the iron shoes at the feet
	k.paint("4f5355", 0.4, 0.6)
	for r: int in range(2):
		var h := base + up * (gap * float(r)) + along * (-0.05)
		k.box(h, Vector3(0.018, 0.028, 0.022), rot)
		k.box(base + up * (gap * float(r)) + along * (s0 + 0.02), Vector3(0.017, 0.026, 0.02), rot)
	k.weather = 1.0

## Benteveo: the canillita's canvas bag on a strap from his left shoulder, across his chest and his back, to the
## front of his right hip, the late edition folded in it and standing out of the top. Cap, scarf and clothes are the
## baked figure's. He never carries a weapon: his takedown is none, his lure is a bundle of the papers.
static func _gear_benteveo(k: Kit, o: Dictionary) -> void:
	k.paint(o.web, 0.9)
	k.bind(SPINE, CHEST)
	_shell_strap(k, o, [[30, 1.505], [52, 1.42], [100, 1.22], [138, 1.04]], 0.036, 0.008)
	_shell_strap(k, o, [[330, 1.505], [308, 1.42], [258, 1.22], [202, 1.06], [160, 1.03]], 0.036, 0.020)
	k.bind(HIPS, THIGH_R)
	var deg := 142.0
	var turn := Basis(Vector3.UP, deg_to_rad(90.0 - deg))
	var at := k.hug(deg, 0.985, 0.040)
	# the bag: a flat canvas satchel, its flap thrown back behind the papers
	k.paint("6c6150", 0.92)
	k.box(at, Vector3(0.125, 0.090, 0.026), turn)
	k.paint("5f5546", 0.92)
	k.box(at + turn * Vector3(0, 0.086, -0.032), Vector3(0.125, 0.009, 0.026), turn * Basis(Vector3.RIGHT, 0.6))
	k.paint(o.web, 0.9)
	for sx: float in [-1.0, 1.0]:
		k.box(at + turn * Vector3(sx * 0.127, 0.06, 0), Vector3(0.006, 0.04, 0.022), turn)
	# the papers: three folded bundles of the evening edition, a dark print line along each fold
	k.weather = 0.0
	for i: int in range(3):
		var p := at + turn * Vector3(-0.06 + 0.06 * float(i), 0.106 + 0.012 * float(i % 2), -0.008 + 0.010 * float(i))
		var lean := turn * Basis(Vector3.BACK, 0.10 * float(i - 1)) * Basis(Vector3.RIGHT, -0.12)
		k.paint("d8d2c1", 0.95)
		k.box(p, Vector3(0.052, 0.040, 0.006), lean)
		k.paint("3c3936", 0.95)
		k.box(p + lean * Vector3(0, 0.028, 0.0075), Vector3(0.050, 0.006, 0.0008), lean)
		k.box(p + lean * Vector3(-0.012, 0.006, 0.0075), Vector3(0.036, 0.0025, 0.0008), lean)
	k.weather = 1.0

## Where Biguá's sheath hangs (body space): the front of his right hip, the knife's handle standing out of its top.
const BIGUA_SHEATH := Vector3(-0.128, 1.045, 0.214)

## Biguá: a dark leather belt under the open oilskin, the long sheath of his rope knife hanging from it on the front of
## his right hip; a coil of manila rope over his right shoulder and across his body to the left hip, front and back.
## Beanie, roll neck, oilskin and boots are the baked figure's; the knife itself is _build_knife (drawn for a lethal
## takedown).
static func _gear_bigua(k: Kit, o: Dictionary) -> void:
	_belt(k, o.web, 0.6, 0.150, 0.104)
	_buckle(k, 0.104)
	# the sheath, a strap of leather round the belt and its body down the thigh
	k.bind(HIPS, THIGH_R)
	k.paint("3a2618", 0.62)
	k.box(BIGUA_SHEATH + Vector3(0.0, -0.155, 0.0), Vector3(0.019, 0.112, 0.019))
	k.box(BIGUA_SHEATH + Vector3(0.0, -0.060, 0.0), Vector3(0.022, 0.016, 0.021))
	k.paint("2a1b12", 0.6)
	k.box(BIGUA_SHEATH + Vector3(0.0, 0.0, -0.020), Vector3(0.012, 0.034, 0.003))
	# the rope: three turns of it, a loop from the right shoulder over the chest and the back to the left hip
	k.weather = 0.0
	var front := [[178.0, 1.475], [150.0, 1.45], [118.0, 1.37], [80.0, 1.23], [40.0, 1.10], [12.0, 1.02], [356.0, 1.00]]
	var back := [[182.0, 1.475], [210.0, 1.45], [242.0, 1.37], [280.0, 1.23], [320.0, 1.10], [348.0, 1.02], [356.0, 1.00]]
	var coarse: Array = front.duplicate()
	for i: int in range(back.size() - 2, -1, -1): coarse.append(back[i])
	# finely along it, so that the rope's lay shows as it turns
	var path: Array = []
	for i: int in range(coarse.size()):
		var a: Array = coarse[i]
		var b: Array = coarse[(i + 1) % coarse.size()]
		var da := wrapf(float(b[0]) - float(a[0]), -180.0, 180.0)
		for j: int in range(5):
			var t := float(j) / 5.0
			path.append([fposmod(float(a[0]) + da * t, 360.0), lerpf(float(a[1]), float(b[1]), t)])
	for strand: int in range(3):
		k.paint(["a99670", "9c8963", "b0a079"][strand], 0.9)
		k.bind(SPINE, CHEST)
		var lift := 0.024 + 0.019 * float(strand % 2) + (0.010 if strand == 2 else 0.0)
		var dy := 0.024 * float(strand - 1)
		var pts: Array[Vector3] = []
		for q: Array in path:
			var y: float = float(q[1]) + dy
			var p := _on_shell(o, float(q[0]), y, lift - 0.010)
			if absf(float(q[0]) - 180.0) < 20.0: p.y += 0.035 + 0.012 * float(strand) # up over the top of the shoulder
			pts.append(p)
		pts.append(pts[0])
		k.begin(6)
		for i: int in range(pts.size()):
			var prev: Vector3 = pts[maxi(i - 1, 0)] if i > 0 else pts[pts.size() - 2]
			var next: Vector3 = pts[mini(i + 1, pts.size() - 1)] if i < pts.size() - 1 else pts[1]
			var t := (next - prev).normalized()
			var u := t.cross(Vector3.UP).normalized() if absf(t.y) < 0.95 else Vector3.RIGHT
			var w := t.cross(u).normalized()
			k.ring(pts[i], u * 0.0150, w * 0.0150, smoothstep(1.30, 1.10, pts[i].y), 0.80 if (i + strand) % 2 == 0 else 1.06)
		k.finish()
	k.weather = 1.0

## The Guardia de Emergencia's kit: a plain steel buckle on the black belt of the greatcoat (the baked figure's), a
## white armband on the left arm stencilled "G.E." in black, a turned wooden baton hanging at the left hip; the
## sergeant's whistle on a chain at his collar and his pistol's holster on his right hip, below his cape. The carbine
## (the rifle) or the pistol is drawn for him as for any guard, and the rope for when he is tied up.
static func _gear_guardia(k: Kit, o: Dictionary) -> void:
	var bl := _belt_line(k, o)
	var belt_z: float = float(o.fig_meta.get("coat_belt", [1.056, 0.22])[1]) if o.has("fig_meta") else 0.2
	var sergeant := bool(o.get("cape", false))
	k.bind(SPINE, HIPS)
	k.paint("9a9d9f", 0.35, 0.7)
	k.box(Vector3(0, bl.x, belt_z + 0.004), Vector3(0.026, 0.022, 0.003))
	k.paint("15151a", 0.5)
	k.box(Vector3(0, bl.x, belt_z + 0.0075), Vector3(0.016, 0.012, 0.0012))
	# the armband round the coat's sleeve, high on the left arm, and its stencil
	k.bind(ARM_L)
	var ax: float = o.shape.shoulder - 0.008
	var az := -0.008
	var rx := 0.074
	var rz := 0.092
	k.paint("e2e0d8", 0.95)
	k.begin(16)
	for row: Array in [[1.300, 0.0], [1.304, 0.0035], [1.392, 0.0035], [1.396, 0.0]]:
		k.ring(Vector3(ax, row[0], az), Vector3(rx + row[1], 0, 0), Vector3(0, 0, rz + row[1]))
	k.finish(-1.0, -1.0)
	k.paint("17171a", 0.9)
	var ox := ax + rx + 0.0040
	for b: Array in _ge_strokes():
		# read from his left side, "across" runs from his front towards his back
		var z: float = az - float(b[0]) * 1.5
		var ya: float = 1.348 + float(b[1]) * 1.5
		var across := (az - z) / rz
		var bend := sqrt(maxf(1.0 - across * across, 0.0))
		k.box(Vector3(ax + (ox - ax) * bend, ya, z), Vector3(0.0009, float(b[3]) * 1.5, float(b[2]) * 1.5), Basis(Vector3.UP, asin(clampf(across, -1.0, 1.0))))
	# the baton: a turned stick hanging from a leather frog at the left hip, its knob up
	k.bind(HIPS, THIGH_L)
	var deg := 16.0
	var turn := Basis(Vector3.UP, deg_to_rad(90.0 - deg))
	var top := k.hug(deg, bl.x - 0.02, bl.y + 0.020)
	k.paint("15151a", 0.55)
	k.box(top, Vector3(0.016, 0.026, 0.008), turn)
	k.paint("2a1d14", 0.55)
	k.begin(8)
	for row: Array in [[0.035, 0.010], [0.020, 0.016], [0.0, 0.013], [-0.06, 0.0145], [-0.30, 0.0165], [-0.40, 0.016]]:
		k.ring(top + turn * Vector3(0.0, float(row[0]), 0.020), turn * Vector3(float(row[1]), 0, 0), turn * Vector3(0, 0, float(row[1])))
	k.finish(0.004, 0.006)
	if sergeant:
		# the whistle on its chain, in the cape's opening below his collar
		k.bind(CHEST)
		var cz := k.hug(90.0, 1.40, 0.0).z
		k.paint("b9bcbe", 0.3, 0.8)
		k.strap(Vector3(0.0, 1.455, cz + 0.004), Vector3(0.010, 1.33, k.hug(90.0, 1.33, 0.0).z + 0.010), 0.004, Vector3(0, 0, 1), 0.002)
		k.begin(8)
		var w := Vector3(0.012, 1.315, k.hug(90.0, 1.32, 0.0).z + 0.013)
		for row: Array in [[0.0, 0.0065], [-0.030, 0.0065], [-0.034, 0.004]]:
			k.ring(w + Vector3(0, float(row[0]), 0), Vector3(float(row[1]), 0, 0), Vector3(0, 0, float(row[1])))
		k.finish(0.003, 0.002)
		# the holster on the right hip, outside the coat (the pistol rides in it: _dress)
		k.bind(HIPS, THIGH_R)
		k.paint("15151a", 0.5)
		k.box(GUARDIA_HOLSTER + Vector3(0, -0.018, -0.002), Vector3(0.020, 0.072, 0.036), Basis(Vector3.RIGHT, 0.06))
	_build_bonds(k)
	if o.gun == "rifle": _build_rifle(k)
	elif o.gun != "none": _build_pistol(k, false)

## Where the Guardia sergeant's holster rides (body space), out on the right hip over his greatcoat.
const GUARDIA_HOLSTER := Vector3(-0.276, 0.965, 0.045)

## The stencil on the Guardia's armband, "G.E.", as strokes on the band's outer face: [across, up, half width, half
## height] in metres (across = along the band round the arm, from the front).
static func _ge_strokes() -> Array:
	var w := 0.0019
	return [
		# G: top, left side, bottom, the right side's lower half and the bar going in from it
		[-0.0125, 0.0115, 0.0085, w], [-0.0205, 0.0, w, 0.0115], [-0.0125, -0.0115, 0.0085, w], [-0.0045, -0.0055, w, 0.0060],
		[-0.0075, -0.0005, 0.0035, w],
		# .
		[0.0010, -0.0115, w, w],
		# E
		[0.0070, 0.0, w, 0.0115], [0.0125, 0.0115, 0.0055, w], [0.0115, 0.0, 0.0045, w], [0.0125, -0.0115, 0.0055, w],
		# .
		[0.0215, -0.0115, w, w]]

## The barrio's people and the informer: nothing in their hands but the informer's evening paper, folded long in his
## left hand; spectacles for whoever wears them; the rope for when one is tied up.
static func _gear_civil(k: Kit, o: Dictionary) -> void:
	if bool(o.get("paper", false)):
		# the evening paper folded long and tucked under his left arm, between the sleeve and the coat
		k.bind(ARM_L, CHEST)
		k.weather = 0.0
		var hx: float = o.shape.shoulder - 0.012
		var turn := Basis(Vector3.RIGHT, 0.20) * Basis(Vector3.BACK, -0.08)
		var c := Vector3(hx, 1.262, 0.070)
		k.paint("d6d0bf", 0.95)
		k.box(c, Vector3(0.016, 0.062, 0.215), turn)
		k.paint("37342f", 0.95)
		for row: Array in [[0.040, 0.008, 0.150], [0.012, 0.0025, 0.13], [-0.004, 0.0025, 0.13], [-0.030, 0.012, 0.05]]:
			for sx: float in [-1.0, 1.0]:
				k.box(c + turn * Vector3(sx * 0.0166, float(row[0]), 0.0), Vector3(0.0006, float(row[1]), float(row[2])), turn)
		k.weather = 1.0
	if bool(o.get("specs", false)): _spectacles(k, o)
	_build_bonds(k)

static func _gear_asset(k: Kit, o: Dictionary) -> void:
	if o.get("overcoat", false):
		# Riachuelo's passenger: nothing but his spectacles (the coat is the baked figure's)
		_spectacles(k, o, "2a2420")
		return
	# braces: two straps up the front, crossing at the back
	k.paint(o.web, 0.7)
	k.bind(SPINE, CHEST)
	for side: float in [1.0, -1.0]:
		k.ribbon([[90 - side * 48, 1.492], [90 - side * 32, 1.40], [90 - side * 30, 1.03]], 0.028, 0.005)
		k.ribbon([[270 + side * 48, 1.492], [270 + side * 30, 1.40], [270 - side * 8, 1.20], [270 - side * 16, 1.03]], 0.028, 0.005)
	# shirt tail pulled loose on one side, open collar
	k.paint(o.top, 0.95)
	k.bind(HIPS)
	k.box(k.fit(Vector3(-0.07, 1.0, -0.106)), Vector3(0.055, 0.05, 0.006), Basis(Vector3.RIGHT, -0.08), 0.9)
	if o.has("fig_meta"): return # a baked figure has its own collar and hair
	k.bind(CHEST)
	for side: float in [1.0, -1.0]:
		k.box(Vector3(side * 0.045, 1.487, 0.062), Vector3(0.034, 0.008, 0.026), Basis(Vector3.BACK, side * 0.35) * Basis(Vector3.RIGHT, 0.5))
	# unkempt hair
	k.paint(o.hair, 0.85)
	k.bind(HEAD)
	k.box(Vector3(0.03, 1.782, 0.045), Vector3(0.04, 0.016, 0.04), Basis(Vector3.BACK, 0.3) * Basis(Vector3.UP, 0.4))
	k.box(Vector3(-0.045, 1.775, -0.02), Vector3(0.035, 0.018, 0.05), Basis(Vector3.BACK, -0.35))
	k.box(Vector3(0.0, 1.76, 0.075), Vector3(0.05, 0.014, 0.022), Basis(Vector3.RIGHT, 0.5))

static func _gear_guard(k: Kit, o: Dictionary) -> void:
	var n: int = o.n
	var coat: float = 0.014 if o.coat else 0.0
	var shirt: bool = o.shirt
	var sergeant: bool = o.gk == "sergeant"
	var is_baked := o.has("fig_meta")
	k.pre = _head_fit(o)
	match "" if is_baked else str(o.hat):
		"":
			pass
		"helmet":
			# steel helmet: deep bowl with a flared rim, worn at a slightly different angle by each man
			var tilt := Basis(Vector3.RIGHT, [0.0, 0.03, -0.09, 0.10, 0.05, -0.04][n % 6]) * Basis(Vector3.BACK, [0.0, 0.0, 0.05, -0.06, 0.12 if shirt else 0.0, 0.07][n % 6])
			k.xf = Transform3D(tilt, Vector3(0, 1.72, 0)) * Transform3D(Basis.IDENTITY, Vector3(0, -1.72, 0))
			k.bind(HEAD)
			k.paint("3d443e", 0.55, 0.25)
			_steel_helmet(k)
			if not shirt:
				k.paint("1c1b19", 0.6) # chin strap (the men turned out of their bunks have not done theirs up)
				var strap := maxf(0.074, _face_w(_head_rows(o), 1.61) + 0.004)
				k.box(Vector3(strap, 1.61, 0.03), Vector3(0.004, 0.065, 0.008), Basis(Vector3.RIGHT, -0.25))
				k.box(Vector3(-strap, 1.61, 0.03), Vector3(0.004, 0.065, 0.008), Basis(Vector3.RIGHT, -0.25))
			k.xf = Transform3D.IDENTITY
		"cap":
			k.bind(HEAD)
			_peaked_cap(k, o)
		"fieldcap":
			k.bind(HEAD)
			_field_cap(k, o)
		_:
			# bare-headed: hair on end
			k.bind(HEAD)
			k.paint(o.hair, 0.85)
			k.box(Vector3(0.03, 1.786, 0.04), Vector3(0.045, 0.016, 0.045), Basis(Vector3.BACK, 0.25) * Basis(Vector3.UP, 0.4))
			k.box(Vector3(-0.04, 1.78, -0.025), Vector3(0.04, 0.018, 0.05), Basis(Vector3.BACK, -0.3))
	k.pre = Transform3D.IDENTITY
	if o.coat and not is_baked:
		# turned-up greatcoat collar
		k.paint(o.top)
		k.bind(CHEST, HEAD)
		_neck_wrap(k, o, [[1.47, 0.098, 0.092, -0.008, 0, 0.85], [1.53, 0.086, 0.086, -0.016, 0.2], [1.565, 0.082, 0.080, -0.022, 0.3, 0.85]], 10)
	# belt and buckle
	_belt(k, o.web, 0.5, 0.166 + coat + (0.012 if shirt else 0.0), 0.114 + coat + (0.012 if shirt else 0.0))
	k.paint("8b8c84", 0.45, 0.4)
	k.bind(SPINE)
	k.box(k.fit(Vector3(0, 1.05, 0.116 + coat + (0.012 if shirt else 0.0))), Vector3(0.022, 0.02, 0.006))
	if o.kit:
		# ammunition pouches
		k.paint("26221e", 0.5)
		for side: float in [1.0, -1.0]:
			for i: int in range(3):
				var a := side * (0.42 + 0.30 * float(i))
				var at := k.fit(Vector3(sin(a) * (0.172 + coat), 1.045, cos(a) * (0.122 + coat)))
				_pouch(k, at, Vector3(0.019, 0.034, 0.016), a)
	k.bind(SPINE, CHEST)
	if shirt:
		# braces over a collarless shirt, the tunic left on its peg
		k.paint("2f2a25", 0.7)
		for side: float in [1.0, -1.0]:
			k.ribbon([[90 - side * 46, 1.492], [90 - side * 30, 1.40], [90 - side * 28, 1.07]], 0.036, 0.006)
			k.ribbon([[270 + side * 46, 1.492], [270 + side * 28, 1.40], [270 - side * 8, 1.20], [270 - side * 16, 1.07]], 0.036, 0.006)
		k.paint(o.top, 0.95)
		k.bind(HIPS)
		k.box(k.fit(Vector3(0.08, 1.0, -0.118)), Vector3(0.06, 0.055, 0.006), Basis(Vector3.RIGHT, -0.1), 0.9) # shirt tail out
	elif sergeant:
		# cross strap from the right shoulder to the left hip, a row of buttons
		k.paint(o.web, 0.5)
		k.ribbon([[142, 1.492], [116, 1.37], [62, 1.18], [20, 1.07]], 0.034, 0.006)
		k.ribbon([[218, 1.492], [244, 1.37], [300, 1.18], [340, 1.07]], 0.034, 0.006)
		k.paint("8d8f88", 0.45, 0.4)
		for y: float in [1.44, 1.36, 1.28, 1.20, 1.12]:
			k.ribbon([[90, y + 0.010], [90, y - 0.010]], 0.022, 0.005)
	else:
		k.paint(o.web, 0.5)
		if o.kit:
			for side: float in [1.0, -1.0]:
				k.ribbon([[90 - side * 50, 1.494], [90 - side * 34, 1.40], [90 - side * 36, 1.07]], 0.028, 0.005)
				k.ribbon([[270 + side * 50, 1.494], [270 + side * 34, 1.42], [270 + side * 3, 1.30]], 0.028, 0.005)
			k.ribbon([[270, 1.31], [270, 1.07]], 0.03, 0.005)
		if o.coat:
			k.paint(o.top) # double-breasted front: overlap seam and two rows of dull buttons
			k.ribbon([[97, 1.47], [99, 1.10]], 0.012, 0.004, 0.72)
			k.paint(o.get("coat_button", "7d7f78"), 0.5, 0.3)
			for deg: float in [78.0, 104.0]:
				for y: float in [1.40, 1.30, 1.20, 1.12]:
					k.ribbon([[deg, y + 0.012], [deg, y - 0.012]], 0.024, 0.006)
		else:
			k.paint("7d7f78", 0.5, 0.3)
			for y: float in ([1.36, 1.28, 1.20, 1.12] if not o.kit else [1.44, 1.36, 1.28, 1.20, 1.12]):
				k.ribbon([[90, y + 0.010], [90, y - 0.010]], 0.02, 0.005)
			if not o.kit:
				# collar thrown open over the shirt
				k.paint("8e8b79", 0.95)
				k.bind(CHEST)
				k.box(k.fit(Vector3(0, 1.465, 0.098)), Vector3(0.034, 0.03, 0.01), Basis(Vector3.RIGHT, -0.3))
	if o.kit:
		# hip kit: haversack with water bottle behind the right hip, spade on the left
		k.bind(HIPS)
		k.paint("6d6b54", 0.93)
		k.xf = Transform3D(Basis(Vector3.UP, -0.5), k.fit(Vector3(-0.12, 0.955, -(0.135 + coat))))
		k.begin(8, 3.4)
		for row: Array in [[-0.075, 0.075, 0.030], [-0.05, 0.09, 0.042], [0.06, 0.09, 0.042], [0.075, 0.08, 0.032]]:
			k.ring(Vector3(0, row[0], 0), Vector3(row[1], 0, 0), Vector3(0, 0, row[2]))
		k.finish(0.004, 0.004)
		k.paint("4a4334", 0.85)
		k.begin(7)
		for row: Array in [[-0.06, 0.028], [-0.04, 0.04], [0.05, 0.04], [0.075, 0.022]]:
			k.ring(Vector3(-0.035, row[0] - 0.01, -0.075), Vector3(row[1], 0, 0), Vector3(0, 0, row[1] * 0.75))
		k.finish(0.006, 0.008)
		if o.get("messtin", false):
			# mess tin strapped on the bread bag
			k.paint("3c463b", 0.55, 0.15)
			k.begin(8, 2.8)
			for row: Array in [[0.072, 0.040, 0.020], [0.080, 0.052, 0.026], [0.118, 0.052, 0.026], [0.126, 0.044, 0.020]]:
				k.ring(Vector3(0.0, row[0], -0.050), Vector3(row[1], 0, 0), Vector3(0, 0, row[2]))
			k.finish(0.003, 0.004)
			k.paint("23211d", 0.6)
			k.box(Vector3(0.0, 0.10, -0.050), Vector3(0.008, 0.032, 0.029))
		k.xf = Transform3D.IDENTITY
		k.paint("3c423f", 0.5, 0.3)
		k.box(k.fit(Vector3(0.175 + coat, 0.90, -0.06)), Vector3(0.008, 0.085, 0.055), Basis(Vector3.RIGHT, 0.12))
		k.paint("54402b", 0.7)
		k.box(k.fit(Vector3(0.178 + coat, 1.01, -0.045)), Vector3(0.012, 0.06, 0.012), Basis(Vector3.RIGHT, 0.12))
		# bayonet in its frog beside the spade
		k.paint("23221f", 0.45, 0.3)
		k.box(k.fit(Vector3(0.184 + coat, 0.93, 0.0)), Vector3(0.008, 0.11, 0.013), Basis(Vector3.RIGHT, 0.22))
		k.paint("5c4630", 0.7)
		k.box(k.fit(Vector3(0.184 + coat, 1.045, 0.025)), Vector3(0.009, 0.028, 0.011), Basis(Vector3.RIGHT, 0.22))
		if o.get("grenade", false):
			# a stick grenade pushed through the belt
			k.bind(SPINE)
			var at := k.fit(Vector3(0.075, 1.05, 0.124 + coat)) + Vector3(0, 0, 0.012)
			var tilt := Basis(Vector3.BACK, 0.28)
			k.paint("6d5537", 0.75)
			k.box(at + tilt * Vector3(0, -0.02, 0), Vector3(0.0105, 0.095, 0.0105), tilt)
			k.paint("444a46", 0.5, 0.3)
			k.begin(8)
			for row: Array in [[0.07, 0.012], [0.078, 0.026], [0.125, 0.026], [0.132, 0.016]]:
				k.ring(at + tilt * Vector3(0, row[0], 0), tilt * Vector3(row[1], 0, 0), tilt * Vector3(0, 0, row[1]))
			k.finish(0.004, 0.004)
		# per-man variation
		k.bind(CHEST)
		if n == 1 or n == 4:
			# ribbed kit canister slung across the small of the back
			k.bind(SPINE)
			k.paint("48504c", 0.55, 0.2)
			k.begin(8)
			for row: Array in [[-0.125, 0.045], [-0.115, 0.058], [-0.04, 0.055], [-0.035, 0.059], [0.035, 0.059], [0.04, 0.055], [0.115, 0.058], [0.125, 0.045]]:
				k.ring(k.fit(Vector3(0, 1.115, -0.165)) + Vector3(row[0], row[0] * 0.22, 0), Vector3(0, row[1], 0), Vector3(0, 0, row[1]))
			k.finish(0.004, 0.004)
			k.bind(CHEST)
		if n == 3:
			# shelter cape rolled and strapped high on the back
			k.paint("5a5846", 0.96)
			k.begin(8)
			for row: Array in [[-0.17, 0.03], [-0.155, 0.052], [0.155, 0.052], [0.17, 0.03]]:
				k.ring(k.fit(Vector3(0, 1.395, -0.165)) + Vector3(row[0], 0, 0), Vector3(0, row[1], 0), Vector3(0, 0, row[1]))
			k.finish(0.004, 0.004)
			k.paint(o.web, 0.5)
			for x: float in [-0.08, 0.08]:
				k.box(k.fit(Vector3(0, 1.395, -0.165)) + Vector3(x, 0, 0), Vector3(0.01, 0.055, 0.055))
		if n == 4:
			# small field pack
			k.paint("5f5f50", 0.93)
			k.begin(8, 3.6)
			for row: Array in [[1.20, 0.12, 0.05], [1.23, 0.135, 0.066], [1.40, 0.135, 0.066], [1.435, 0.12, 0.05]]:
				k.ring(k.fit(Vector3(0, row[0], -0.185)), Vector3(row[1], 0, 0), Vector3(0, 0, row[2]))
			k.finish(0.005, 0.005)
			k.paint("55554a", 0.93)
			k.box(k.fit(Vector3(0, 1.39, -0.19)), Vector3(0.137, 0.045, 0.07))
		if n == 5:
			k.paint("6e6a5a", 0.97) # scarf
			k.bind(CHEST, HEAD)
			_neck_wrap(k, o, [[1.50, 0.092, 0.090, -0.010, 0.1, 0.9], [1.545, 0.084, 0.084, -0.016, 0.3], [1.58, 0.070, 0.074, -0.014, 0.5, 0.9]], 8)
	if o.get("armband", false):
		# a plain cloth band round the left upper arm
		k.bind(ARM_L)
		var sx: float = o.shape.shoulder + 0.004
		k.paint("c2b99c", 0.95)
		k.begin(10)
		for row: Array in [[1.355, 0.050], [1.37, 0.053], [1.41, 0.053], [1.425, 0.050]]:
			k.ring(Vector3(sx, row[0], -0.004), Vector3(row[1], 0, 0), Vector3(0, 0, row[1] * 0.95))
		k.finish(-1.0, -1.0)
		k.paint("6a2b22", 0.9)
		k.begin(10)
		for row: Array in [[1.381, 0.0545], [1.392, 0.0545]]:
			k.ring(Vector3(sx, row[0], -0.004), Vector3(row[1], 0, 0), Vector3(0, 0, row[1] * 0.95))
		k.finish(-1.0, -1.0)
	if sergeant:
		# holster on the right hip, map case on the left
		k.paint(o.web, 0.5)
		k.bind(HIPS, THIGH_R)
		k.box(k.fit(Vector3(-0.196, 0.915, 0.02)), Vector3(0.022, 0.075, 0.04), Basis(Vector3.RIGHT, 0.06))
		k.bind(HIPS, THIGH_L)
		k.box(k.fit(Vector3(0.196, 0.90, -0.03)), Vector3(0.012, 0.08, 0.065))
		k.paint("3d2a1c", 0.5)
		k.box(k.fit(Vector3(0.206, 0.935, -0.03)), Vector3(0.006, 0.04, 0.068))
	if bool(o.get("torch", false)):
		# a flat service torch buttoned to the chest, lens forward, its leather tab over the button
		k.bind(CHEST)
		k.paint("23251f", 0.5, 0.3)
		k.box(k.fit(Vector3(0.075, 1.345, 0.142 + coat)), Vector3(0.036, 0.058, 0.026))
		k.paint("e9dfb9", 0.2)
		k.box(k.fit(Vector3(0.075, 1.352, 0.156 + coat)), Vector3(0.024, 0.024, 0.004))
		k.paint("3a2c1e", 0.7)
		k.box(k.fit(Vector3(0.075, 1.383, 0.146 + coat)), Vector3(0.012, 0.022, 0.008))
	if o.bino:
		# neck strap; the glasses themselves ride on their own bone
		k.paint("1c1b19", 0.6)
		k.bind(CHEST)
		k.ribbon([[72, 1.50], [84, 1.345]], 0.014, 0.012 + coat)
		k.ribbon([[108, 1.50], [96, 1.345]], 0.014, 0.012 + coat)
		_build_binoculars(k)
	else:
		_build_bonds(k)
	if o.gun == "rifle": _build_rifle(k)
	elif o.gun != "none": _build_pistol(k, false)
	if bool(o.get("specs", false)): _spectacles(k, o)

## Bolt-action rifle in PROP space: +Z muzzle, +Y sights, origin at the grip behind the trigger.
static func _build_rifle(k: Kit) -> void:
	k.weather = 0.0
	k.bind(PROP)
	k.paint("4d3724", 0.6)
	k.begin(6, 2.6)
	for row: Array in [[-0.30, 0.017, 0.052, -0.050], [-0.27, 0.018, 0.054, -0.046], [-0.11, 0.017, 0.032, -0.020], [0.0, 0.017, 0.024, -0.004],
			[0.10, 0.021, 0.029, 0.0], [0.34, 0.019, 0.023, 0.004], [0.60, 0.016, 0.018, 0.006]]:
		k.ring(Vector3(0, row[3], row[0]), Vector3(row[1], 0, 0), Vector3(0, row[2], 0))
	k.finish(0.004, 0.004)
	k.paint("27292b", 0.4, 0.55)
	k.begin(6)
	for row: Array in [[0.02, 0.013], [0.16, 0.011], [0.60, 0.009], [0.80, 0.008]]:
		k.ring(Vector3(0, 0.022, row[0]), Vector3(row[1], 0, 0), Vector3(0, row[1], 0))
	k.finish(0.0, 0.0)
	k.box(Vector3(0, 0.030, 0.06), Vector3(0.014, 0.012, 0.075)) # receiver
	k.box(Vector3(-0.030, 0.022, 0.015), Vector3(0.020, 0.006, 0.006), Basis(Vector3.BACK, 0.5)) # bolt handle
	k.box(Vector3(0, -0.036, 0.075), Vector3(0.007, 0.012, 0.038)) # magazine floor / trigger guard
	k.box(Vector3(0, 0.012, 0.61), Vector3(0.019, 0.02, 0.012)) # muzzle band
	k.box(Vector3(0, 0.038, 0.775), Vector3(0.003, 0.008, 0.006)) # front sight
	k.paint("2c231b", 0.6) # sling hanging under the stock
	k.strap(Vector3(0.012, -0.085, -0.20), Vector3(0.012, -0.075, 0.15), 0.022, Vector3(1, 0, 0), 0.005)
	k.strap(Vector3(0.012, -0.075, 0.15), Vector3(0.012, -0.012, 0.52), 0.022, Vector3(1, 0, 0), 0.005)
	k.weather = 1.0

## Sidearm in PROP space: +Z muzzle, +Y sights, origin inside the fist round the grip.
## Slightly over scale, like the rifle's furniture, so that it still reads at 60 px.
static func _build_pistol(k: Kit, suppressed: bool) -> void:
	k.weather = 0.0
	k.bind(PROP)
	k.paint("2a2c2e", 0.4, 0.55)
	k.box(Vector3(0, 0.052, 0.05), Vector3(0.016, 0.02, 0.105)) # slide and barrel
	k.box(Vector3(0, 0.02, 0.055), Vector3(0.005, 0.016, 0.028)) # trigger guard
	k.paint("3a2c20", 0.6)
	k.box(Vector3(0, -0.022, -0.016), Vector3(0.015, 0.06, 0.025), Basis(Vector3.RIGHT, 0.22)) # grip
	if suppressed:
		k.paint("151617", 0.55, 0.3)
		k.begin(6)
		for row: Array in [[0.15, 0.016], [0.16, 0.026], [0.37, 0.026], [0.38, 0.018]]:
			k.ring(Vector3(0, 0.054, row[0]), Vector3(row[1], 0, 0), Vector3(0, row[1], 0))
		k.finish(0.0, 0.0)
	k.weather = 1.0

static func _build_revolver(k: Kit) -> void:
	k.weather = 0.0
	k.bind(PROP)
	k.paint("303234", 0.38, 0.6)
	k.box(Vector3(0, 0.05, 0.035), Vector3(0.013, 0.024, 0.055)) # frame
	k.begin(6)
	for row: Array in [[0.0, 0.03], [0.07, 0.03]]:
		k.ring(Vector3(0, 0.05, row[0]), Vector3(row[1], 0, 0), Vector3(0, row[1], 0))
	k.finish(0.0, 0.0) # cylinder
	k.begin(6)
	for row: Array in [[0.07, 0.014], [0.24, 0.012]]:
		k.ring(Vector3(0, 0.064, row[0]), Vector3(row[1], 0, 0), Vector3(0, row[1], 0))
	k.finish(0.0, 0.0) # barrel
	k.box(Vector3(0, 0.082, 0.228), Vector3(0.003, 0.007, 0.008)) # front sight
	k.paint("4a3323", 0.6)
	k.box(Vector3(0, -0.024, -0.022), Vector3(0.016, 0.062, 0.026), Basis(Vector3.RIGHT, 0.32)) # grip
	k.weather = 1.0

## A leather cosh in TOOL space: lead-weighted head toward +Z, origin in the fist, the wrist loop behind it.
static func _build_cosh(k: Kit) -> void:
	k.weather = 0.0
	k.bind(TOOL)
	k.paint("2b2119", 0.75)
	k.begin(8, 1.0)
	for row: Array in [[-0.03, 0.011], [0.0, 0.012], [0.05, 0.011], [0.08, 0.015], [0.12, 0.019], [0.155, 0.017], [0.17, 0.008]]:
		k.ring(Vector3(0, 0, row[0]), Vector3(row[1], 0, 0), Vector3(0, row[1], 0))
	k.finish(0.004, 0.003)
	k.paint("3a2c1f", 0.7)
	k.box(Vector3(0, -0.012, -0.05), Vector3(0.004, 0.03, 0.02))
	k.weather = 1.0

## Fighting knife in TOOL space: blade +Z, origin in the fist.
static func _build_knife(k: Kit) -> void:
	k.weather = 0.0
	k.bind(TOOL)
	k.paint("241d18", 0.6)
	k.box(Vector3(0, 0, -0.012), Vector3(0.012, 0.014, 0.055))
	k.paint("3b3d3c", 0.4, 0.5)
	k.box(Vector3(0, 0, 0.048), Vector3(0.006, 0.028, 0.006))
	k.paint("c6cbce", 0.28, 0.85)
	k.box(Vector3(0, 0.002, 0.15), Vector3(0.0035, 0.016, 0.098))
	k.weather = 1.0

## Long-handled wire cutters as two halves that pivot at the shared origin of TOOL and TOOL_B:
## jaws towards +Z, handles towards -Z, opening in the XZ plane.
static func _build_cutters(k: Kit) -> void:
	k.weather = 0.0
	for half: int in range(2):
		var side := 1.0 if half == 0 else -1.0
		k.bind(TOOL + half)
		k.paint("33383b", 0.4, 0.6)
		k.box(Vector3(side * 0.007, 0, 0.055), Vector3(0.009, 0.013, 0.06)) # jaw
		k.box(Vector3(side * 0.013, 0, -0.17), Vector3(0.008, 0.009, 0.18)) # shank
		k.paint("9a3524", 0.7)
		k.box(Vector3(side * 0.013, 0, -0.46), Vector3(0.013, 0.014, 0.125)) # grip
	k.weather = 1.0

## The rope a bound guard ends up in: a lashing for the wrists (TOOL) and one for the ankles (TOOL_B).
## Both bones are shrunk to nothing until he is tied.
static func _build_bonds(k: Kit) -> void:
	k.weather = 0.0
	k.paint("d2c49a", 0.95)
	k.bind(TOOL)
	for x: float in [-0.016, 0.016]:
		k.torus(Vector3(x, 0, 0), Basis(Vector3.BACK, -PI / 2.0), 0.052, 0.019, 6, 3)
	k.box(Vector3(0, 0.01, -0.06), Vector3(0.02, 0.02, 0.016))
	k.bind(TOOL_B)
	for y: float in [-0.016, 0.016]:
		k.begin(3)
		for j: int in range(9):
			var a := TAU * float(j) / 8.0
			var dir := Vector3(cos(a), 0, sin(a))
			k.ring(Vector3(dir.x * 0.085, y, dir.z * 0.058), dir * 0.019, Vector3.UP * 0.019)
		k.finish()
	k.box(Vector3(0, 0, 0.07), Vector3(0.022, 0.022, 0.016))
	k.weather = 1.0

## Field glasses in TOOL space: objectives +Z, eyepieces -Z.
static func _build_binoculars(k: Kit) -> void:
	k.weather = 0.0
	k.bind(TOOL)
	k.paint("1d1e20", 0.5, 0.2)
	for side: float in [1.0, -1.0]:
		k.begin(6)
		for row: Array in [[-0.06, 0.017], [-0.02, 0.022], [0.035, 0.033], [0.085, 0.035]]:
			k.ring(Vector3(side * 0.039, 0, row[0]), Vector3(row[1], 0, 0), Vector3(0, row[1], 0))
		k.finish(0.0, 0.0)
	k.box(Vector3(0, 0.004, 0.0), Vector3(0.024, 0.011, 0.03))
	k.weather = 1.0

# ----------------------------------------------------------------------------------------------
# Shared resources
# ----------------------------------------------------------------------------------------------
## Frame for something held: origin at the grip, +Z along `bore`, +Y towards `up`.
static func _aim_xf(grip: Vector3, bore: Vector3, up: Vector3) -> Transform3D:
	var z := bore.normalized()
	var x := up.cross(z).normalized()
	return Transform3D(Basis(x, z.cross(x), z), grip)

## Bind pose of one joint for a given shoulder width (only the arms move).
static func _joint_at(i: int, sx: float) -> Vector3:
	var j := JOINT[i]
	if i >= ARM_L and i <= HAND_R: j.x = signf(j.x) * sx
	return j

static func _skin_for(sx: float) -> Skin:
	var key := int(round(sx * 1000.0))
	if _skins.has(key): return _skins[key]
	var skin := Skin.new()
	for i: int in range(BONE_COUNT):
		skin.add_bind(i, Transform3D(Basis.IDENTITY, -_joint_at(i, sx)))
	_skins[key] = skin
	return skin

static func _shared() -> void:
	if _skin != null: return
	_skin = _skin_for(JOINT[ARM_L].x)
	_body_material = ShaderMaterial.new()
	_body_material.shader = BODY_SHADER
	# a body nobody can find: sunk into the leaves and dulled until it is just a shape
	_cover_material = ShaderMaterial.new()
	_cover_material.shader = BODY_SHADER
	_cover_material.set_shader_parameter("tint", Color(0.50, 0.58, 0.46))
	_blob_material = ShaderMaterial.new()
	_blob_material.shader = BLOB_SHADER
	_blob_material.render_priority = -1
	_blob_mesh = QuadMesh.new()
	_blob_mesh.size = Vector2.ONE
	_blob_mesh.orientation = PlaneMesh.FACE_Y
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = FLASH_SHADER
	_flash_material.render_priority = 4
	_flash_mesh = QuadMesh.new()
	_flash_mesh.size = Vector2.ONE
	_ui_material = StandardMaterial3D.new()
	_ui_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ui_material.vertex_color_use_as_albedo = true
	_ui_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ui_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ui_material.render_priority = 3
	_marker_material = _ui_material.duplicate()
	_marker_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_marker_material.no_depth_test = true
	_ring_mesh = _make_ring(false)
	_ring_cover_mesh = _make_ring(true)
	_marker_mesh = _make_marker(Color("f3f6e6"))
	_marker_cover_mesh = _make_marker(Color("8fd06a"))
	# rifle carries in chest space: (grip position, muzzle direction, sights direction)
	_rifle_port = _aim_xf(Vector3(-0.13, -0.235, 0.165), Vector3(0.60, 0.74, 0.30), Vector3(-0.5, 0.2, 1.0))
	_rifle_ready = _aim_xf(Vector3(-0.135, -0.14, 0.05), Vector3(0.30, -0.09, 0.95), Vector3(-0.15, 1.0, 0.0))
	_rifle_aim = _aim_xf(Vector3(0.004, 0.168, 0.318), Vector3(sin(0.6), -0.02, cos(0.6)), Vector3(-0.06, 1.0, 0.0))
	_rifle_slung = _aim_xf(Vector3(-0.09, -0.15, -0.175), Vector3(0.40, 0.91, -0.02), Vector3(0.15, 0.0, -1.0))
	# ... and in ground space: butt grounded by the right boot (a sentry at ease), dropped beside a fallen man
	_rifle_order = _aim_xf(Vector3(-0.25, 0.37, 0.10), Vector3(0.05, 1.0, 0.03), Vector3(0.0, 0.0, 1.0))
	_rifle_ground = _aim_xf(Vector3(0.50, 0.035, 0.30), Vector3(0.45, 0.0, 0.89), Vector3(0.89, 0.25, -0.45))
	# sidearm: low ready in chest space; the aims in a level frame at the chest joint (two hands / one hand)
	_side_ready = _aim_xf(Vector3(-0.06, -0.12, 0.27), Vector3(0.10, -0.55, 0.83), Vector3(0.0, 0.83, 0.55))
	_side_aim2 = _aim_xf(Vector3(-0.02, 0.17, 0.46), Vector3(0.0, 0.0, 1.0), Vector3.UP)
	_side_aim1 = _aim_xf(Vector3(-0.20, 0.215, 0.50), Vector3(0.0, 0.0, 1.0), Vector3(0.14, 1.0, 0.0))
	_define_keys()
	# the men who turn out for an alarm are dressed now, so that their arrival does not cost a frame mid-fight
	for id: String in ["r1", "r2", "r3"]:
		_mesh_for(_look(id, true, "reinforcement"))

# ----------------------------------------------------------------------------------------------
# Key poses: whole-body poses in body space for everything that is not locomotion. Fourteen
# vectors each: hips position and Euler angles; spine, chest and head angles (each relative to the
# bone below); ankle targets and knee directions in hips space; feet (pitch L, pitch R, splay);
# wrist targets and elbow directions in chest space. The second half of the table holds the mirror
# images, used by half of the cast so that no two bodies lie alike.
# ----------------------------------------------------------------------------------------------
enum { KP_STAND, KP_SEIZED, KP_STIFF, KP_SAG, KP_FLAIL, KP_CHOKED, KP_KNEES, KP_PRONE, KP_BOUND, KP_STUN, KP_STIR, KP_DEAD_F, KP_DEAD_B, KP_DEAD_S, KP_CARRIED, KP_COUNT }
const KN: int = 14
enum { K_HIPS, K_HIPS_E, K_SPINE_E, K_CHEST_E, K_HEAD_E, K_FOOT_L, K_FOOT_R, K_KNEE_L, K_KNEE_R, K_FEET, K_WRIST_L, K_WRIST_R, K_ELBOW_L, K_ELBOW_R }
## How each lying pose rests: which way the Rig is tipped (+1 face down, -1 on the back) and how far
## the body is then rolled about its spine (radians; 1.57 = fully on its side).
const KP_SIGN: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, -1.0, 1.0, 1.0]
const KP_ROLL: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.15, 0.0, 0.12, 0.90, -0.22, 1.05, 0.0]

static func _key(id: int, rows: Array[Vector3]) -> void:
	var a := id * KN
	var b := (id + KP_COUNT) * KN
	for i: int in range(KN):
		_kp[a + i] = rows[i]
	_kp[b + K_HIPS] = rows[K_HIPS] * Vector3(-1, 1, 1)
	for i: int in range(K_HIPS_E, K_HEAD_E + 1):
		_kp[b + i] = rows[i] * Vector3(1, -1, -1)
	for i: int in [K_FOOT_L, K_KNEE_L, K_WRIST_L, K_ELBOW_L]:
		_kp[b + i] = rows[i + 1] * Vector3(-1, 1, 1)
		_kp[b + i + 1] = rows[i] * Vector3(-1, 1, 1)
	_kp[b + K_FEET] = Vector3(rows[K_FEET].y, rows[K_FEET].x, rows[K_FEET].z)

static func _define_keys() -> void:
	_kp = PackedVector3Array()
	_kp.resize(KP_COUNT * KN * 2)
	var z := Vector3.ZERO
	var hip := Vector3(0, 0.95, 0)
	_key(KP_STAND, [Vector3(0, 0.94, 0), z, z, z, z,
		Vector3(0.10, -0.855, 0.03), Vector3(-0.10, -0.855, -0.03), Vector3(0.1, 0, 1), Vector3(-0.1, 0, 1), Vector3(0, 0, 0.12),
		Vector3(0.21, -0.33, 0.04), Vector3(-0.21, -0.33, 0.04), Vector3(0.35, -0.25, -1), Vector3(-0.35, -0.25, -1)])
	# seized from behind: head wrenched back, one hand clawing at the hand over his mouth
	_key(KP_SEIZED, [Vector3(0, 0.93, 0.04), Vector3(-0.08, 0, 0), Vector3(-0.14, 0, 0), Vector3(-0.16, 0.12, 0), Vector3(-0.32, 0.25, 0.05),
		Vector3(0.11, -0.84, 0.06), Vector3(-0.11, -0.84, -0.02), Vector3(0.15, 0, 1), Vector3(-0.15, 0, 1), Vector3(0.25, 0.10, 0.14),
		Vector3(0.09, 0.28, 0.17), Vector3(-0.27, -0.03, 0.17), Vector3(0.7, -0.7, -0.2), Vector3(-0.9, -0.4, -0.3)])
	# the blade goes in: up on his toes, back arched, arms rigid
	_key(KP_STIFF, [Vector3(0, 0.955, 0.08), Vector3(-0.12, 0, 0), Vector3(-0.20, 0, 0), Vector3(-0.20, 0, 0), Vector3(-0.42, 0.1, 0),
		Vector3(0.11, -0.86, 0.02), Vector3(-0.11, -0.86, -0.06), Vector3(0.15, 0, 1), Vector3(-0.15, 0, 1), Vector3(0.5, 0.45, 0.1),
		Vector3(0.33, -0.12, 0.10), Vector3(-0.34, -0.08, 0.12), Vector3(0.8, -0.3, -0.6), Vector3(-0.8, -0.3, -0.6)])
	# knees giving way
	_key(KP_SAG, [Vector3(0, 0.60, 0.02), Vector3(0.18, 0, 0.06), Vector3(0.25, 0, 0.05), Vector3(0.25, 0.05, 0.05), Vector3(0.5, 0.1, 0.1),
		Vector3(0.12, -0.52, 0.14), Vector3(-0.12, -0.54, 0.04), Vector3(0.3, 0, 1), Vector3(-0.35, 0, 1), Vector3(0.3, 0.5, 0.2),
		Vector3(0.22, -0.44, 0.12), Vector3(-0.25, -0.42, 0.06), Vector3(0.5, -0.2, -1), Vector3(-0.5, -0.2, -1)])
	# arms thrown out by a fall (only the arms of this one are used)
	_key(KP_FLAIL, [Vector3(0, 0.94, 0), z, z, z, z,
		Vector3(0.10, -0.855, 0.03), Vector3(-0.10, -0.855, -0.03), Vector3(0.1, 0, 1), Vector3(-0.1, 0, 1), Vector3(0, 0, 0.12),
		Vector3(0.38, 0.10, 0.20), Vector3(-0.34, 0.0, 0.25), Vector3(0.8, -0.6, -0.2), Vector3(-0.8, -0.6, -0.2)])
	# an arm locked round his neck: dragged back off balance, both hands at the forearm
	_key(KP_CHOKED, [Vector3(0, 0.90, 0.07), Vector3(-0.12, 0, 0), Vector3(-0.16, 0, 0), Vector3(-0.12, 0, 0), Vector3(-0.22, 0, 0),
		Vector3(0.14, -0.80, 0.14), Vector3(-0.13, -0.82, 0.06), Vector3(0.15, 0, 1), Vector3(-0.15, 0, 1), Vector3(0.1, 0.3, 0.2),
		Vector3(0.06, 0.25, 0.16), Vector3(-0.07, 0.24, 0.16), Vector3(0.6, -0.8, 0), Vector3(-0.6, -0.8, 0)])
	# forced down: folded at the hips (kneeling once the Rig is half tipped), arms dragged behind
	_key(KP_KNEES, [hip, z, Vector3(0.22, 0, 0), Vector3(0.15, 0, 0), Vector3(0.1, 0.4, 0),
		Vector3(0.11, -0.62, 0.03), Vector3(-0.11, -0.62, 0.03), Vector3(0.15, 0, 1), Vector3(-0.15, 0, 1), Vector3(1.2, 1.2, 0.1),
		Vector3(0.07, -0.22, -0.15), Vector3(-0.07, -0.24, -0.15), Vector3(1, -0.2, -0.5), Vector3(-1, -0.2, -0.5)])
	# face down, wrists crossed in the small of his back
	_key(KP_PRONE, [hip, z, Vector3(-0.04, 0, 0), Vector3(-0.05, 0, 0), Vector3(-0.1, 0.75, 0),
		Vector3(0.13, -0.85, -0.02), Vector3(-0.13, -0.85, -0.02), Vector3(0.1, 0, 1), Vector3(-0.1, 0, 1), Vector3(1.3, 1.3, 0.25),
		Vector3(0.04, -0.24, -0.15), Vector3(-0.04, -0.26, -0.15), Vector3(1, -0.2, -0.5), Vector3(-1, -0.2, -0.5)])
	# trussed: on his side, knees drawn up, ankles together, wrists behind
	_key(KP_BOUND, [hip, Vector3(0.1, 0, 0), Vector3(0.22, 0, 0), Vector3(0.18, 0, 0), Vector3(0.2, 0.15, 0),
		Vector3(0.035, -0.66, 0.10), Vector3(-0.035, -0.63, 0.14), Vector3(0.05, 0.1, 1), Vector3(-0.05, 0.1, 1), Vector3(0.9, 0.9, 0.05),
		Vector3(0.035, -0.25, -0.15), Vector3(-0.035, -0.27, -0.15), Vector3(1, -0.2, -0.5), Vector3(-1, -0.2, -0.5)])
	# tripped: flat on his face, limbs anyhow
	_key(KP_STUN, [hip, z, Vector3(-0.03, 0, 0.06), Vector3(-0.03, 0, 0.06), Vector3(-0.08, -0.85, 0),
		Vector3(0.16, -0.85, -0.02), Vector3(-0.40, -0.54, 0.02), Vector3(0.1, 0, 1), Vector3(-1, -0.2, 0.3), Vector3(1.3, 1.0, 0.3),
		Vector3(0.40, 0.33, 0.07), Vector3(-0.40, 0.0, 0.08), Vector3(1, -0.4, -0.25), Vector3(-0.8, -0.9, -0.25)])
	# coming round: head up, hands under him
	_key(KP_STIR, [hip, z, Vector3(-0.10, 0, 0.03), Vector3(-0.16, 0, 0), Vector3(-0.32, -0.3, 0),
		Vector3(0.15, -0.83, -0.02), Vector3(-0.30, -0.62, 0.05), Vector3(0.1, 0, 1), Vector3(-1, -0.2, 0.3), Vector3(1.2, 0.9, 0.3),
		Vector3(0.27, 0.10, 0.12), Vector3(-0.30, 0.04, 0.12), Vector3(1, -0.3, -0.5), Vector3(-1, -0.4, -0.5)])
	# dead, folded forward: slumped over on to one side, the upper arm and knee fallen in front of him,
	# the other arm trapped out past his head
	_key(KP_DEAD_F, [hip, Vector3(0.05, 0, 0), Vector3(0.12, 0.15, 0), Vector3(0.10, 0.20, 0), Vector3(0.15, 0.5, 0.2),
		Vector3(0.08, -0.52, 0.32), Vector3(-0.10, -0.84, 0.0), Vector3(0.6, 0, 0.8), Vector3(-0.1, 0, 1), Vector3(0.9, 1.2, 0.2),
		Vector3(0.11, -0.05, 0.36), Vector3(-0.20, 0.70, 0.10), Vector3(0.6, -0.8, 0.1), Vector3(-1, 0, -0.3)])
	# dead, thrown backward: flat on his back, arms flung wide, one knee up, head lolled
	_key(KP_DEAD_B, [hip, z, Vector3(-0.05, 0, 0.08), Vector3(-0.03, 0.05, 0.06), Vector3(-0.15, 0.6, 0.1),
		Vector3(0.17, -0.85, 0.02), Vector3(-0.22, -0.52, 0.30), Vector3(0.3, 0, 1), Vector3(-0.3, 0, 1), Vector3(-0.3, 0.2, 0.5),
		Vector3(0.50, 0.12, -0.06), Vector3(-0.40, -0.22, -0.06), Vector3(1, -1, 0), Vector3(-1, -0.3, 0)])
	# one of ours down: on his side, knees drawn up a little, an arm across his body
	_key(KP_DEAD_S, [hip, Vector3(0.1, 0, 0), Vector3(0.22, 0.05, 0.05), Vector3(0.18, 0.1, 0), Vector3(0.3, 0.3, 0.1),
		Vector3(0.05, -0.60, 0.30), Vector3(-0.08, -0.74, 0.12), Vector3(0.5, 0, 0.9), Vector3(-0.1, 0, 1), Vector3(0.8, 1.0, 0.1),
		Vector3(0.03, -0.10, 0.33), Vector3(-0.24, 0.30, 0.22), Vector3(0.6, -0.8, 0.1), Vector3(-1, -0.3, -0.2)])
	# over a shoulder: folded at the waist, arms and head hanging down the bearer's back
	_key(KP_CARRIED, [hip, z, Vector3(0.7, 0, 0), Vector3(0.6, 0, 0), Vector3(0.3, 0.2, 0),
		Vector3(0.10, -0.16, 0.80), Vector3(-0.09, -0.21, 0.79), Vector3(0.1, 1, 0.3), Vector3(-0.1, 1, 0.3), Vector3(0.6, 0.6, 0.2),
		Vector3(0.20, 0.70, 0.12), Vector3(-0.22, 0.68, 0.10), Vector3(1, 0.2, -0.3), Vector3(-1, 0.2, -0.3)])

## Selection ring, flat on the ground: four bright arcs with soft edges and a faint inner hairline;
## the "in cover" variant is broken into short dashes and dimmer.
static func _make_ring(dashed: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bright := Color("a9dc86") if dashed else Color("eef4e2")
	var radii: Array[float] = [0.405, 0.418, 0.448, 0.461]
	var peak := 0.8 if dashed else 0.95
	var alphas: Array[float] = [0.0, peak, peak, 0.0]
	var arcs := 16 if dashed else 4
	var gap := 0.11 if dashed else 0.16
	var steps := 3 if dashed else 10
	for arc: int in range(arcs):
		var from := float(arc) * TAU / float(arcs) + gap
		var span := TAU / float(arcs) - gap * 2.0
		for i: int in range(steps):
			var a0 := from + span * float(i) / float(steps)
			var a1 := from + span * float(i + 1) / float(steps)
			for band: int in range(3):
				_ring_quad(st, a0, a1, radii[band], radii[band + 1], Color(bright, alphas[band]), Color(bright, alphas[band + 1]))
	if not dashed:
		for i: int in range(40):
			var a0 := TAU * float(i) / 40.0
			var a1 := TAU * float(i + 1) / 40.0
			_ring_quad(st, a0, a1, 0.352, 0.362, Color(bright, 0.0), Color(bright, 0.42))
			_ring_quad(st, a0, a1, 0.362, 0.372, Color(bright, 0.42), Color(bright, 0.0))
	return st.commit()

static func _ring_quad(st: SurfaceTool, a0: float, a1: float, r0: float, r1: float, c0: Color, c1: Color) -> void:
	var d0 := Vector3(cos(a0), 0, sin(a0))
	var d1 := Vector3(cos(a1), 0, sin(a1))
	for corner: Array in [[d0, r0, c0], [d1, r0, c0], [d1, r1, c1], [d0, r0, c0], [d1, r1, c1], [d0, r1, c1]]:
		st.set_color(corner[2])
		st.add_vertex(corner[0] * float(corner[1]))

## Above-head marker: a small down-pointing chevron with a dark keyline, billboarded
## (pale normally, leaf green while the operative is hidden in cover).
static func _make_marker(tone: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for pass_index: int in range(2):
		var grow := 0.016 if pass_index == 0 else 0.0
		var c := Color(0.04, 0.05, 0.04, 0.7) if pass_index == 0 else tone
		var w := 0.075 + grow
		var top := 0.085 + grow * 0.6
		var thick := 0.044 + grow * 1.6
		var tip := -grow * 1.3
		var z := -0.002 if pass_index == 0 else 0.0
		for side: float in [-1.0, 1.0]:
			var quad: Array[Vector3] = [Vector3(side * w, top, z), Vector3(0, tip + thick, z), Vector3(0, tip, z), Vector3(side * w, top - thick * 0.9, z)]
			for i: int in [0, 1, 2, 0, 2, 3]:
				st.set_color(c)
				st.add_vertex(quad[i])
	return st.commit()

# ----------------------------------------------------------------------------------------------
# Instance
# ----------------------------------------------------------------------------------------------
## `of_kind` is the simulation's kind of guard ("patrol", "tower", "sentry", "sergeant",
## "reinforcement"); left empty the look is derived from the id. Whatever is passed here, the first
## sync() checks the actor's own id and kind and re-dresses the figure if they say otherwise.
func build(id: String, is_enemy: bool = false, of_kind: String = "", look_name: String = "") -> void:
	_shared()
	enemy = is_enemy
	skel = Skeleton3D.new()
	skel.name = "Rig"
	for i: int in range(BONE_COUNT):
		skel.add_bone("b%d" % i)
		skel.set_bone_rest(i, Transform3D(Basis.IDENTITY, JOINT[i]))
	skel.reset_bone_poses()
	add_child(skel)
	body = MeshInstance3D.new()
	body.name = "Body"
	body.skin = _skin
	body.material_override = _body_material
	body.extra_cull_margin = 1.2
	# seen through a building or a ship in a flat tint (world.gd sets it each frame with set_xray)
	body.material_overlay = _xray_material()
	skel.add_child(body)
	blob = MeshInstance3D.new()
	blob.name = "ContactShadow"
	blob.mesh = _blob_mesh
	blob.material_override = _blob_material
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.position.y = 0.02
	add_child(blob)
	ring = MeshInstance3D.new()
	ring.name = "SelectionRing"
	ring.mesh = _ring_mesh
	ring.material_override = _ui_material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = 0.04
	ring.visible = false
	add_child(ring)
	marker = MeshInstance3D.new()
	marker.name = "SelectionMarker"
	marker.mesh = _marker_mesh
	marker.material_override = _marker_material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.position.y = 1.97
	marker.visible = false
	add_child(marker)
	_k.resize(KN)
	_k0.resize(KN)
	_kt.resize(KN)
	_dress(_look(id, is_enemy, of_kind, look_name), id)
	_claim(id)
	if _flash_warm_until < 0:
		_flash_warm_until = Time.get_ticks_msec() + 1500
		_make_flash()
		flash.scale = Vector3.ONE * 0.02
		flash.position.y = -0.3
		flash_warming = true

## Mesh, proportions and where this figure keeps its weapon and tools.
func _dress(o: Dictionary, id: String) -> void:
	look_key = o.key
	kind = o.kind
	guard_kind = o.get("gk", "")
	height = o.height
	girth = o.girth
	shape = o.shape
	shoulder_x = shape.shoulder
	head_scale = shape.head
	stance_w = shape.stance
	sway_k = shape.sway
	arm_out = shape.splay
	for i: int in range(ARM_L, HAND_R + 1):
		skel.set_bone_rest(i, Transform3D(Basis.IDENTITY, _joint_at(i, shoulder_x)))
	body.skin = _skin_for(shoulder_x)
	# lying down, the hips rest on whatever is thickest under them: a belly, a broad back
	lie_front = 0.128 * girth * Body.df(shape, 1.0) + 0.7 * Body.bulge(shape, 1.08)
	lie_back = 0.128 * girth * Body.df(shape, 1.0)
	lie_side = 0.205 * girth * maxf(Body.wf(shape, 1.0), lerpf(1.0, shape.chest, 0.5))
	var chance := absi(hash(id))
	seed_a = float(chance % 1000) / 1000.0 * TAU
	key_bank = KP_COUNT if (chance >> 10) % 2 == 1 else 0
	phase = 0.11 + seed_a / TAU # every character starts its cycles somewhere else
	clock = seed_a * 3.0
	if cutout != null:
		cutout.queue_free()
		cutout = null
	ui_scale = 1.0
	if o.has("cutout"):
		# the art pack's drawing (or model) stands in for the body: the rig stays, unseen, to drive it
		body.mesh = null
		body.visible = false
		cutout = Cutout.new()
		cutout.name = "Cutout"
		add_child(cutout)
		cutout.setup(o.cutout)
		# a model throws a shadow from the sky's light only where the figures do (not on the Plaza de Mayo: world.gd)
		cutout.set_shadows(body.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		cutout.use_xray(body.material_overlay != null, _xray_material())
		if _xray_tint.a >= 0.0: cutout.set_xray(_xray_tint)
		ui_scale = clampf(float(cutout.width_m) / 0.8, 1.0, 5.0)
	else:
		body.visible = true
		body.mesh = _mesh_for(o)
	baked = o.has("fig_meta")
	baked_covered = false
	body.material_override = null if baked else _body_material
	if body.mesh != null:
		for i: int in range(body.mesh.get_surface_count()):
			body.set_surface_override_material(i, null)
	var coat: float = 0.014 if o.coat else 0.0
	gun = GUN_NONE
	tool_kit = TOOL_NONE
	match kind:
		"merle":
			# the cosh rides in his right coat pocket, the grip just showing
			tool_kit = TOOL_COSH
			stow_tool = _aim_xf(_in_hips(Vector3(-0.105, 0.09, 0.18)), Vector3(-0.03, -1.0, -0.3), Vector3(0, 0, 1))
		"hornero":
			# the tram's controller handle, swung like a cosh: carried head down in his right coat pocket under the
			# belt, the arm's end and its wooden knob standing out of the pocket
			# (hips space, on the baked coat as measured: its front is at z 0.20-0.225 below the belt)
			tool_kit = TOOL_COSH
			stow_tool = _aim_xf(Vector3(-0.114, 0.0, 0.214), Vector3(-0.03, -1.0, -0.37), Vector3(1, 0, 0))
		"bigua":
			# the sheath knife: point down in its sheath on the front of his right hip, the handle standing out of it
			tool_kit = TOOL_KNIFE
			stow_tool = _aim_xf(BIGUA_SHEATH - JOINT[HIPS], Vector3(0.0, -1.0, 0.0), Vector3(-0.45, 0, 1))
		"wren":
			gun = GUN_PISTOL
			two_hands = true
			muzzle = Vector3(0, 0.054, 0.40)
			stow_prop = _aim_xf(_in_hips(Vector3(-0.2, 0.015, 0.04)), Vector3(0, -1, 0.06), Vector3(0, 0, 1))
			tool_kit = TOOL_KNIFE
			stow_tool = _aim_xf(_in_hips(Vector3(-0.155, 0.05, -0.132), true), Vector3(0.976, 0.218, 0), Vector3(0, 0, -1))
		"rook":
			gun = GUN_REVOLVER
			two_hands = false
			muzzle = Vector3(0, 0.064, 0.26)
			stow_prop = _aim_xf(_in_hips(Vector3(0.2, 0.02, 0.04)), Vector3(0, -1, 0.06), Vector3(0, 0, 1))
			tool_kit = TOOL_CUTTERS
			var on_pack := Body.fit(shape, girth, Vector3(0, JOINT[CHEST].y + 0.27, -0.29)) - JOINT[CHEST]
			stow_tool = _aim_xf(on_pack + Vector3(0.13, 0, 0), Vector3(0.5, 0.86, 0), Vector3(0, 0, -1))
		"guard":
			if o.gun == "rifle":
				gun = GUN_RIFLE
				muzzle = Vector3(0, 0.022, 0.84)
			elif o.gun == "none":
				gun = GUN_NONE
			else:
				gun = GUN_PISTOL
				two_hands = false
				muzzle = Vector3(0, 0.052, 0.17)
				stow_prop = _aim_xf(_in_hips(Vector3(-0.205, 0.035, 0.03)), Vector3(0, -1, 0.06), Vector3(0, 0, 1))
				# the Guardia sergeant's holster is out over his greatcoat
				if str(o.get("outfit", "")) == "guardia":
					stow_prop = _aim_xf(GUARDIA_HOLSTER + Vector3(0, 0.03, 0.0) - JOINT[HIPS], Vector3(0, -1, 0.06), Vector3(0, 0, 1))
			if o.bino:
				tool_kit = TOOL_GLASSES
				stow_tool = _aim_xf(Body.fit(shape, girth, Vector3(0, JOINT[CHEST].y + 0.085, 0.165 + coat)) - JOINT[CHEST], Vector3(0, -1, 0.12), Vector3(0, 0.12, 1))
			else:
				tool_kit = TOOL_ROPE
				bonds_out = true

## A point given in stock hips space (x scaled by girth), moved on to this body. `centred` keeps x
## as it is (a sheath across the back of the belt).
func _in_hips(p: Vector3, centred: bool = false) -> Vector3:
	var at := Body.fit(shape, girth, p + JOINT[HIPS]) - JOINT[HIPS]
	if centred: at.x = p.x
	return at

## Registers this model under its actor id so that the other half of a paired action can find it.
func _claim(id: String) -> void:
	if id == actor_id: return
	if _live.get(actor_id) == self: _live.erase(actor_id)
	actor_id = id
	if id != "": _live[id] = self

func _exit_tree() -> void:
	if _live.get(actor_id) == self: _live.erase(actor_id)

static func _mate(id: String) -> Node3D:
	if id == "": return null
	var other: Variant = _live.get(id)
	if other == null or not is_instance_valid(other): return null
	return other

func sync(actor: Dictionary, active: bool, dt: float, stopped: bool) -> void:
	var first := not initialized
	if first:
		# The actor has the last word on who this is (the caller may have passed a stand-in look).
		var id := str(actor.get("id", actor_id))
		var want := _look_of(actor, id, enemy)
		if want.key != look_key: _dress(want, id)
		_claim(id)
	# A change of clothes: an operative in a guard's uniform, a guard left in his shirt sleeves.
	var clothes := str(actor.get("disguise", {}).get("id", "")) if not enemy else ("shirt" if bool(actor.get("stripped", false)) else "")
	if clothes != _clothes:
		_clothes = clothes
		_dress(_clothed(actor), str(actor.get("id", actor_id)))
	var px := float(actor.get("x", 0.0)) / 32.0
	var pz := float(actor.get("y", 0.0)) / 32.0
	var travel := Vector2(px - position.x, pz - position.z).length()
	# first frame, restart, checkpoint or teleport: jump straight to the new pose instead of blending
	var snap := first or travel > 1.5 or _restored(actor)
	position = Vector3(px, position.y, pz) # the height is the world layer's (the tower sentry stands on his platform)
	initialized = true
	var cover: bool = actor.get("hidden", false)
	if active != selected:
		selected = active
		ring.visible = active
		marker.visible = active
	if active:
		# the selection cue keeps moving in command mode so the chosen operative stays obvious
		# Both cues grow a little when the camera pulls back so they survive at overview zoom.
		ui_clock += dt
		var cam := get_viewport().get_camera_3d()
		var grow := clampf(cam.size / 15.0, 0.85, 1.8) if cam != null else 1.0
		var pulse := (1.0 + 0.035 * sin(ui_clock * 3.2)) * maxf(1.0, grow * 0.8)
		# in cover the ring breaks into dashes and both cues turn leaf green: "nobody can see me here"
		var want_ring := _ring_cover_mesh if cover else _ring_mesh
		if ring.mesh != want_ring:
			ring.mesh = want_ring
			marker.mesh = _marker_cover_mesh if cover else _marker_mesh
		ring.rotation.y = ui_clock * (0.25 if cover else 0.55)
		ring.scale = Vector3(pulse * ui_scale, 1.0, pulse * ui_scale)
		marker.scale = Vector3.ONE * grow
		marker.position = a_head + Vector3(0, 0.33 * height + 0.014 * sin(ui_clock * 3.2), 0)
	# Paused, everything stands still: gait, idling, every clip, every blend. Only if something is
	# changed in command mode (a stance toggled, an order given, a checkpoint loaded) do the blends
	# run on, in real time, until the figure has settled into its new state.
	real_dt = 0.0 if snap else minf(dt, 0.1)
	var step := 0.0 if stopped else real_dt
	var blend := real_dt
	if stopped and not snap:
		var mark := _signature(actor)
		if was_stopped and mark != pause_mark: thaw = 0.7
		pause_mark = mark
		if thaw > 0.0: thaw -= dt
		else: blend = 0.0
	was_stopped = stopped
	_read_state(actor, travel if step > 0.0 else 0.0, step, blend, snap)
	_pose()
	if cutout != null: _pose_cutout()

## The cut-out (cutout.gd) placed from what the rig worked out this frame; a model on its own skeleton is also told his
## speed, his aim (raised for a shot and kept up while he recovers), the shot, whom he carries and whether he has been
## knocked down; a creature its state and the hits it has taken. The flash of a shot then comes from the model's muzzle.
func _pose_cutout() -> void:
	var low: float = maxf(_ease(w_crouch), _ease(w_act) if w_act > 0.0 else 0.0)
	var stoop: float = w_pick * _span(pick_p, 0.0, 0.3, 0.42, 0.9) if w_pick > 0.0 else 0.0
	var lower: float = w_drop * smoothstep(0.0, 0.7, drop_p) if w_drop > 0.0 else 0.0
	cutout.pose({"root": global_position, "offset": rig_off + lie_off * lie, "yaw": vis_yaw, "phase": phase, "move": _ease(w_move),
		"run": smoothstep(1.35, 2.3, speed), "crouch": maxf(low, maxf(stoop, lower * 0.8)), "lie": lie, "carried": w_carried, "carry": skel.global_transform,
		"hidden": w_hidden, "covered": w_hidden > 0.5 and lie > 0.5, "clock": clock,
		"camera": get_viewport().get_camera_3d() if is_inside_tree() else null,
		"speed": speed, "aim": maxf(_ease(w_gaim), _ease(w_gun)), "pitch": aim_pitch, "recoil": recoil_t, "hold": _ease(w_carry),
		"down": 1.0 if clip == CL_KNEEL else 0.0, "state": st_state, "hits": beast_hits})
	if flash != null and flash.visible: _show_flash()

## Everything about an actor that can be changed while the game is paused, folded into one number.
func _signature(actor: Dictionary) -> int:
	var mark := hash(actor.get("stance", "")) + 3 * hash(actor.get("state", "")) + 5 * hash(actor.get("carried_by", "")) + 7 * hash(actor.get("carrying", ""))
	mark += 11 * hash(actor.get("action", "")) + 13 * hash(actor.get("angle", 0.0)) + 17 * hash(actor.get("hp", 0))
	var order: Variant = actor.get("order")
	if order is Dictionary: mark += 19 * hash(order.get("type", ""))
	return mark + (23 if actor.get("hidden", false) else 0) + (29 if actor.get("freed", false) else 0) + (31 if actor.get("aboard", false) else 0)

## True when the actor's state has gone back in time (a checkpoint was loaded or the mission restarted).
func _restored(actor: Dictionary) -> bool:
	if enemy:
		return (st_state == "dead" or st_state == "bound") and actor.get("state", "") != st_state
	if float(actor.get("hp", 100)) > last_hp + 0.5 or int(actor.get("ammo", 0)) > last_ammo: return true
	if fallen and actor.get("alive", true): return true
	return kind == "asset" and ((w_boat > 0.5 and not actor.get("aboard", false)) or (w_sit < 0.5 and not actor.get("freed", false)))

static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)

static func _toward(value: float, target: float, step: float, seconds: float, snap: bool) -> float:
	return target if snap else move_toward(value, target, step / seconds)

static func _gp(table: Array[float], u: float, c: float) -> float:
	return lerpf(lerpf(table[0], table[1], u), table[2], c)

## A window: rises over [a, b], holds, falls over [c, d].
static func _span(x: float, a: float, b: float, c: float, d: float) -> float:
	return smoothstep(a, b, x) * (1.0 - smoothstep(c, d, x))

# ----------------------------------------------------------------------------------------------
# State: the actor's fields become blend weights, clip clocks and one-shot triggers
# ----------------------------------------------------------------------------------------------
func _read_state(actor: Dictionary, travel: float, step: float, blend: float, snap: bool) -> void:
	clock += step
	var moving := travel > 0.0004
	if moving:
		speed = lerpf(speed, clampf(travel / maxf(step, 0.001), 0.0, 3.4), 1.0 - exp(-step * 9.0))
		phase += travel / (stride_len * height)
	elif snap:
		var route: Variant = actor.get("path")
		speed = (1.1 if enemy else 2.0) if route is Array and not route.is_empty() else 0.0
	if step > 0.0 or snap:
		w_move = _toward(w_move, 1.0 if moving else 0.0, step, 0.22 if moving else 0.30, snap)
	var cover: bool = actor.get("hidden", false)
	w_hidden = _toward(w_hidden, 1.0 if cover else 0.0, blend, 0.4, snap)
	st_elevation = float(actor.get("elevation", 0.0))
	face_yaw = PI / 2.0 - float(actor.get("angle", 0.0))
	aim_to = 0.0
	if enemy: _read_guard(actor, step, blend, snap, moving)
	else: _read_operative(actor, blend, snap)
	_run_clip(real_dt if fallen else step, snap) # the mission ends on a death, but the fall is still played
	# one-shots
	if throw_t >= 0.0:
		throw_t += step / 0.9
		if throw_t >= 1.0 or snap: throw_t = -1.0
	if recoil_t >= 0.0:
		recoil_t += step
		if recoil_t >= 1.0 or snap: recoil_t = -1.0
	if flinch_t >= 0.0:
		flinch_t += step / 0.5
		if flinch_t >= 1.0 or snap: flinch_t = -1.0
	if flash_t >= 0.0:
		flash_t += real_dt # real time: a flash must never hang in the air while the game is paused
		if flash_t >= FLASH_TIME or snap: flash_t = -1.0
	aim_pitch = aim_to if snap else lerpf(aim_pitch, aim_to, 1.0 - exp(-blend * 10.0))
	# Facing: on the move the whole body turns promptly. Standing, the head and shoulders turn
	# first and the feet only shuffle round once the twist gets uncomfortable (a searching guard
	# sweeps from the waist instead of spinning on the spot). A man on the ground stays as he fell.
	if snap:
		vis_yaw = face_yaw
		turn = 0.0
	elif lie > 0.3 or w_carried > 0.0:
		turn = lerpf(turn, 0.0, 1.0 - exp(-blend * 12.0))
	else:
		var off := wrapf(face_yaw - vis_yaw, -PI, PI)
		var rate := (9.0 if enemy else 13.0) if moving or w_hold > 0.0 else 0.8 + 10.0 * smoothstep(0.5, 1.0, absf(off))
		vis_yaw += off * (1.0 - exp(-blend * rate))
		turn = lerpf(turn, clampf(wrapf(face_yaw - vis_yaw, -PI, PI), -1.1, 1.1), 1.0 - exp(-blend * 12.0))

## Elevation angle from this figure's weapon to another figure's chest.
func _pitch_to(other: Node3D) -> float:
	var rel: Vector3 = other.global_position - global_position
	var chest_y: float = other.a_chest.y
	return atan2(rel.y + chest_y - 1.38 * height * (1.0 - 0.38 * w_crouch), maxf(0.6, Vector2(rel.x, rel.z).length()))

func _fire() -> void:
	recoil_t = 0.0
	flash_t = 0.0
	flash_roll = fposmod(clock * 37.0, TAU)

func _read_operative(actor: Dictionary, blend: float, snap: bool) -> void:
	# --- health: a hit staggers him, wounds show, the last one drops him
	var hp := float(actor.get("hp", 100))
	if hp < last_hp - 0.5 and not snap: flinch_t = 0.0
	last_hp = hp
	w_wound = _toward(w_wound, clampf((100.0 - hp) / 66.0, 0.0, 1.0), blend, 0.6, snap)
	# a smoke with a guard: standing easy, the cigarette to his lips now and then
	var smoking: bool = str(actor.get("action", "")) == "chat" and bool(actor.get("acting", false))
	w_smoke = _toward(w_smoke, 1.0 if smoking else 0.0, blend, 0.35, snap)
	var alive: bool = actor.get("alive", true)
	# in a rescue the snow does not kill outright: he sinks to his knees, and if nobody gets to him it covers him there
	var snowed: bool = bool(actor.get("fallen", false)) or bool(actor.get("buried", false))
	if snowed and clip != CL_KNEEL:
		fallen = not alive
		_kneel(snap)
	elif not snowed and clip == CL_KNEEL and alive:
		fallen = false
		_stand_up(snap)
	elif not alive and not fallen and not snowed:
		fallen = true
		_go_down(KP_DEAD_B if _shot_from_front() else KP_DEAD_S, 0.85, snap)
	elif alive and fallen and not snowed:
		fallen = false
		_stand_up(true)
	# --- orders
	var action: String = actor.get("action", "")
	var acting: bool = actor.get("acting", false)
	var total := float(actor.get("action_total", 0.0))
	st_action = action if acting and alive else ""
	st_p = clampf(float(actor.get("action_time", 0.0)) / total, 0.0, 1.0) if acting and total > 0.0 else 0.0
	var order_type := ""
	st_target = ""
	var order: Variant = actor.get("order")
	if order is Dictionary and not order.is_empty():
		order_type = str(order.get("type", ""))
		st_target = str(order.get("target", ""))
	# --- stance: the simulation's "exposed" covers every case in which a crouched man is shown standing
	var low: bool = actor.get("stance", "walk") == "sneak" and not actor.get("exposed", false)
	w_crouch = _toward(w_crouch, 1.0 if low else 0.0, blend, 0.40 if low else 0.28, snap)
	# --- kneeling work
	var work := st_action == "unlock" or st_action == "rescue" or st_action == "trap" or st_action == "trap_pickup" or st_action == "cut" or st_action == "sabotage" or st_action == "plant"
	if work:
		act_kind = st_action
		act_p = st_p
		if act_kind == "plant": _face_charge(st_target)
		elif act_kind != "rescue" and act_kind != "trap" and act_kind != "trap_pickup": _face_site(act_kind)
	w_act = _toward(w_act, 1.0 if work else 0.0, blend, 0.28, snap)
	var tooled := work and (act_kind == "cut" or (act_kind == "sabotage" and tool_kit == TOOL_CUTTERS))
	# --- takedown: stands for it; the partner is the guard in his grip
	var taking := st_action == "takedown"
	var other: Node3D = null
	if taking or st_action == "pickup" or order_type == "shoot": other = _mate(st_target)
	if taking:
		var melee: Variant = actor.get("melee")
		st_lethal = melee is Dictionary and bool(melee.get("lethal", false))
		st_stun = melee is Dictionary and float(melee.get("stun", 0.0)) > 0.0
		td_p = st_p
		if other != null:
			var rel: Vector3 = other.global_position - global_position
			if not td_on:
				var lying: float = other.lie
				td_low = lying > 0.5
			pair_gap = Vector2(rel.x, rel.z).length()
			if pair_gap > 0.05: pair_yaw = atan2(rel.x, rel.z)
		elif not td_on:
			td_low = false
			pair_gap = 0.0
		td_on = true
		tooled = tooled or st_lethal or st_stun
		if pair_gap > 0.05: face_yaw = pair_yaw
	else:
		td_on = false
	w_td = _toward(w_td, 1.0 if taking else 0.0, blend, 0.10 if taking else 0.40, snap)
	w_tool = _toward(w_tool, 1.0 if tooled else 0.0, blend, 0.16 if tooled else 0.3, snap)
	# --- bodies: lifting, carrying, putting down
	st_carrying = actor.get("carrying", "")
	if st_action == "pickup":
		pick_p = st_p
		if other != null:
			# tell the body who is lifting it: it cannot know before the simulation hands it over
			other.grab_from = self
			other.grab_p = st_p
			other.grab_ttl = 3
	w_pick = _toward(w_pick, 1.0 if st_action == "pickup" else 0.0, blend, 0.12 if st_action == "pickup" else 0.25, snap)
	if st_action == "drop": drop_p = st_p
	w_drop = _toward(w_drop, 1.0 if st_action == "drop" else 0.0, blend, 0.08 if st_action == "drop" else 0.35, snap)
	w_carry = _toward(w_carry, 1.0 if st_carrying != "" else 0.0, blend, 0.22, snap)
	# --- sidearm: drawn for the order, aimed for the timed part, kept up while he recovers
	var ammo := int(actor.get("ammo", 0))
	if ammo < last_ammo and not snap: _fire()
	last_ammo = ammo
	var recover := float(actor.get("weapon_cooldown", 0.0))
	var drawn := alive and (order_type == "shoot" or recover > 0.25)
	var aiming := st_action == "shoot" or (recoil_t >= 0.0 and recoil_t < 0.32)
	w_gun = _toward(w_gun, 1.0 if drawn else 0.0, blend, 0.16 if drawn else 0.30, snap)
	w_gaim = _toward(w_gaim, 1.0 if aiming else 0.0, blend, 0.15 if aiming else 0.28, snap)
	if order_type == "shoot" and other != null: aim_to = _pitch_to(other)
	# the simulation resolves a throw instantly; the cooldown jumping up is our cue to play it
	var cooldown := float(actor.get("cooldown", 0.0))
	if cooldown > last_cooldown + 1.0 and not snap: throw_t = 0.0
	last_cooldown = cooldown
	if kind == "asset":
		w_sit = _toward(w_sit, 0.0 if actor.get("freed", false) else 1.0, blend, 0.9, snap)
		w_boat = _toward(w_boat, 1.0 if actor.get("aboard", false) else 0.0, blend, 0.8, snap)

func _read_guard(actor: Dictionary, step: float, blend: float, snap: bool, moving: bool) -> void:
	var state: String = actor.get("state", "patrol")
	beast_hits = int(actor.get("hits", 0))
	var suspicion := float(actor.get("suspicion", 0.0))
	var on_edge := state == "hunt" or state == "alert" or float(actor.get("jumpy", 0.0)) > 0.0
	var target_id: String = actor.get("target_id", "")
	var down := state == "dead" or state == "bound" or state == "stunned" or state == "held"
	hold_id = actor.get("held_by", "")
	stun_left = float(actor.get("stun_time", 0.0))
	if state != st_state or snap:
		_guard_change(st_state, state, snap)
		st_state = state
	# --- carried: lifted (the bearer tells us), on his shoulder, put down again
	var bearer_id: String = actor.get("carried_by", "")
	if grab_ttl > 0: grab_ttl -= 1
	if bearer_id != "":
		var bearer := _mate(bearer_id)
		if bearer != null: grab_from = bearer
		w_carried = 1.0
		slung = true
		if clip != CL_CARRIED: _clip(CL_CARRIED, 6.0)
		if snap: key_t = 1.0
	elif grab_ttl > 0 and grab_from != null and is_instance_valid(grab_from) and not snap:
		w_carried = smoothstep(0.3, 1.0, grab_p)
		if clip != CL_CARRIED and grab_p > 0.3:
			slung = true
			_clip(CL_CARRIED, 5.0)
	elif w_carried > 0.0:
		if clip == CL_CARRIED and not snap:
			# laid across in front of whoever was carrying him
			if grab_from != null and is_instance_valid(grab_from):
				var bearer_yaw: float = grab_from.vis_yaw
				vis_yaw = bearer_yaw + (PI / 2.0 if key_bank == 0 else -PI / 2.0)
				lie_off = Basis(Vector3.UP, bearer_yaw) * Vector3(0, 0, 0.62)
			if down:
				lie = 1.0
				roll = 0.0
				_clip(CL_LIE, 3.2)
				settle_t = 0.25
			elif st_state == "fallen" or st_state == "lost":
				# set down again out in the snow: back on his knees
				_kneel(false)
		w_carried = 0.0 if snap else move_toward(w_carried, 0.0, step / 0.42)
	# --- weapon and bearing
	var looking := state == "investigate" or state == "search"
	var ready_to := maxf(smoothstep(0.03, 0.22, suspicion), 1.0 if on_edge else (0.85 if looking else 0.0))
	w_ready = _toward(w_ready, 0.0 if down else ready_to, blend, 0.25 if on_edge else 0.4, snap)
	var aim_w := 1.0 if target_id != "" else smoothstep(0.42, 0.75, suspicion)
	w_aim = _toward(w_aim, 0.0 if down else aim_w, blend, 0.3 if target_id != "" else 0.45, snap)
	w_edge = _toward(w_edge, 1.0 if on_edge and not down else 0.0, blend, 0.5, snap)
	var searching := state == "search" or (state == "hunt" and not moving and target_id == "")
	w_search = _toward(w_search, 1.0 if searching else 0.0, blend, 0.4, snap)
	var at_post := state == "post" and suspicion < 0.03 and not moving
	w_order = _toward(w_order, 1.0 if at_post and guard_kind == "sentry" else 0.0, blend, 0.6, snap)
	var lookout := at_post and tool_kit == TOOL_GLASSES
	w_slung = _toward(w_slung, 1.0 if lookout or (slung and down) else 0.0, blend, 0.45, snap)
	w_tool = _toward(w_tool, 1.0 if lookout and sin(clock * 0.5 + seed_a) > -0.45 else 0.0, blend, 0.55, snap)
	w_gdrop = _toward(w_gdrop, 1.0 if down and not slung else 0.0, blend, 0.22 if down else 0.5, snap)
	w_hold = _toward(w_hold, 1.0 if state == "held" and not held_low else 0.0, blend, 0.12 if state == "held" else 0.5, snap)
	var tied := state == "bound" or (state == "held" and not hold_lethal and hold_p > 0.72)
	w_tied = _toward(w_tied, 1.0 if tied else 0.0, blend, 0.2, snap)
	if gun == GUN_PISTOL:
		w_gun = w_ready
		w_gaim = w_aim
	# --- shots: the fire timer jumping up is the shot
	var fire := float(actor.get("fire_cooldown", 0.0))
	if fire > last_fire + 0.5 and not snap: _fire()
	last_fire = fire
	if target_id != "":
		var quarry := _mate(target_id)
		if quarry != null: aim_to = _pitch_to(quarry)
	# --- seized: turned away from whoever has him
	if state == "held" and not held_low:
		var taker := _mate(hold_id)
		if taker != null:
			var rel: Vector3 = global_position - taker.global_position
			pair_gap = Vector2(rel.x, rel.z).length()
			if pair_gap > 0.05:
				pair_yaw = atan2(rel.x, rel.z)
				face_yaw = pair_yaw

## The work an operative kneels to: he turns to the thing itself (gate, wire, generator), wherever
## he happened to be walking when he got there.
func _face_site(action: String) -> void:
	if not sites_known: _find_sites()
	var site: Variant = sites.get(action)
	if site is Vector2:
		var rel := Vector2(site.x - position.x, site.y - position.z)
		if rel.length_squared() > 0.01: face_yaw = atan2(rel.x, rel.y)

## Setting a charge: he turns to the hull or the pier face the charge goes on (the site's tx, ty).
func _face_charge(site_id: String) -> void:
	var world := get_parent()
	while world != null and not "sim" in world: world = world.get_parent()
	if world == null: return
	var sim: Variant = world.get("sim")
	if sim == null or not sim.has_method("charge_site"): return
	var site: Dictionary = sim.charge_site(site_id)
	if site.is_empty(): return
	var rel := Vector2(float(site.get("tx", site.x)) / 32.0 - position.x, float(site.get("ty", site.y)) / 32.0 - position.z)
	if rel.length_squared() > 0.01: face_yaw = atan2(rel.x, rel.y)

## Looks up, once, where the gate, the cuttable span and the generator stand (metres, X/Z), from the
## mission data of the simulation the world layer holds. Read-only; without it he keeps his heading.
## The integrator may also fill `sites` directly: {"unlock": Vector2, "cut": Vector2, "sabotage": Vector2}.
func _find_sites() -> void:
	sites_known = true
	var world := get_parent()
	while world != null and not "sim" in world: world = world.get_parent()
	if world == null: return
	var sim: Variant = world.get("sim")
	if sim == null or not "data" in sim: return
	var data: Dictionary = sim.data
	var door: Dictionary = data.get("door", {})
	if door.has("w"): sites["unlock"] = Vector2(float(door.x) + float(door.w) * 0.5, float(door.y) + float(door.h) * 0.5) / 32.0
	var span: String = str(data.get("fence", {}).get("span", ""))
	for barrier: Dictionary in data.get("barriers", []):
		if str(barrier.get("id", "")) == span:
			sites["cut"] = Vector2(float(barrier.x) + float(barrier.w) * 0.5, float(barrier.y) + float(barrier.h) * 0.5) / 32.0
	var radio: Dictionary = data.get("radio", {})
	if radio.has("x"):
		# the generator set stands against the nearest wall of the nearest building
		var spot := Vector2(float(radio.x), float(radio.y))
		var best := INF
		for item: Dictionary in data.get("obstacles", []):
			if str(item.get("kind", "")) != "building": continue
			var rect := Rect2(float(item.x), float(item.y), float(item.w), float(item.h))
			var near := Vector2(clampf(spot.x, rect.position.x, rect.end.x), clampf(spot.y, rect.position.y, rect.end.y))
			if near.distance_to(spot) < best:
				best = near.distance_to(spot)
				sites["sabotage"] = near / 32.0

## Whoever just fired at this figure stands in front of it (so it is knocked backwards).
func _shot_from_front() -> bool:
	for id: String in _live:
		var other: Node3D = _live[id]
		if other == self or not is_instance_valid(other) or other.enemy == enemy: continue
		# an operative's shot has just kicked; a guard (posed later in the frame) is still levelled at us
		var fresh: float = other.recoil_t
		var levelled: float = other.w_aim
		if (fresh < 0.0 or fresh > 0.2) if enemy else levelled < 0.6: continue
		var rel: Vector3 = other.global_position - global_position
		return rel.x * sin(vis_yaw) + rel.z * cos(vis_yaw) > 0.0
	return key_bank == 0

# ----------------------------------------------------------------------------------------------
# Body clips: held, falling, lying, getting up, carried
# ----------------------------------------------------------------------------------------------
func _clip(id: int, rate: float) -> void:
	clip = id
	clip_t = 0.0
	key_rate = rate
	if key_w > 0.2:
		for i: int in range(KN): _k0[i] = _k[i]
		key_t = 0.0
	else:
		key_t = 1.0

## Starts a fall to the given lying pose; with `settled` he is simply found lying there.
func _go_down(pose: int, seconds: float, settled: bool) -> void:
	lie_pose = pose
	lie_sign = KP_SIGN[pose]
	lie_off = Vector3.ZERO
	if settled:
		clip = CL_LIE
		clip_t = 0.0
		settle_t = 9.0
		lie = 1.0
		key_t = 1.0
		key_w = 1.0
		roll = KP_ROLL[pose] * (1.0 if key_bank == 0 else -1.0)
		_kt_set(pose)
		for i: int in range(KN): _k[i] = _kt[i]
	else:
		lie_from = lie
		fall_time = seconds
		_clip(CL_FALL, 7.0)

## Down on his knees in the snow, hunched, arms round himself (a rescue's fall: no lying, nothing graphic).
func _kneel(snap: bool) -> void:
	lie_sign = 1.0
	lie_from = lie
	_clip(CL_KNEEL, 2.2)
	if snap: key_t = 1.0

func _stand_up(at_once: bool) -> void:
	slung = false
	if at_once or lie < 0.3:
		clip = CL_NONE
		if at_once:
			lie = 0.0
			roll = 0.0
			key_w = 0.0
			w_carried = 0.0
			lie_off = Vector3.ZERO
	else:
		lie_from = lie
		_clip(CL_RISE, 5.0)

func _guard_change(from: String, to: String, snap: bool) -> void:
	if snap: slung = false
	match to:
		"held":
			held_low = lie > 0.5
			hold_p = 0.0
			if not held_low:
				lie_sign = 1.0
				lie_from = lie
			_clip(CL_HELD, 9.0)
			if snap: key_t = 1.0
		"fallen", "lost":
			# a rescue's people, given out in the snow: down on their knees, hunched over (never thrown down)
			_kneel(snap)
		"dead", "bound", "stunned":
			var pose := KP_BOUND if to == "bound" else KP_STUN
			if snap:
				if to == "dead": pose = KP_DEAD_F if key_bank == 0 else KP_DEAD_B
				_go_down(pose, 0.0, true)
			elif lie > 0.5:
				# already on the ground (tied where he was lowered, or finished off where he lay)
				if to == "dead": pose = KP_DEAD_F if lie_sign > 0.0 else KP_DEAD_B
				lie_pose = pose
				_clip(CL_LIE, 2.4 if to == "bound" else 4.0)
				settle_t = 9.0
			elif to == "stunned":
				_go_down(KP_STUN, 0.5, false) # tripped: pitches forward
			elif to == "dead":
				# knifed from behind he folds forward, away from the blade; shot, he goes down away from the gun
				_go_down(KP_DEAD_F if from == "held" or not _shot_from_front() else KP_DEAD_B, 0.72 if from == "held" else 0.6, false)
			else:
				_go_down(pose, 0.6, false)
		_:
			_stand_up(snap)

func _kt_set(pose: int) -> void:
	var a := (pose + key_bank) * KN
	for i: int in range(KN): _kt[i] = _kp[a + i]

func _kt_mix(pose: int, t: float) -> void:
	if t <= 0.0: return
	var a := (pose + key_bank) * KN
	for i: int in range(KN): _kt[i] = _kt[i].lerp(_kp[a + i], t)

func _run_clip(step: float, snap: bool) -> void:
	if clip == CL_NONE and key_w <= 0.0:
		if lie > 0.0: lie = maxf(0.0, lie - step * 3.0)
		roll = 0.0
		return
	clip_t += step
	key_t = minf(1.0, key_t + step * key_rate)
	var mirror := 1.0 if key_bank == 0 else -1.0
	var want := 1.0
	var roll_to := 0.0
	plant = 0.0
	match clip:
		CL_NONE:
			want = 0.0
			lie = maxf(0.0, lie - step * 3.0)
		CL_HELD:
			var taker := _mate(hold_id)
			var lethal := hold_lethal
			if taker != null and taker.st_action == "takedown":
				hold_p = taker.st_p
				# a man coshed folds the way a man knifed does: all at once, out cold
				lethal = taker.st_lethal or taker.st_stun
				hold_lethal = lethal
			var p := hold_p
			if held_low:
				# worked on where he lies
				lie = 1.0
				_kt_set(lie_pose)
				if lethal:
					var jolt := _span(p, 0.3, 0.42, 0.5, 0.9)
					_kt[K_CHEST_E].x -= 0.14 * jolt
					_kt[K_HEAD_E].x -= 0.3 * jolt
					roll_to = KP_ROLL[lie_pose] * mirror
				else:
					_kt_mix(KP_PRONE, smoothstep(0.05, 0.5, p))
			elif lethal:
				# hand over the mouth, the knife in: he stiffens, then starts to fold
				_kt_set(KP_SEIZED)
				_kt_mix(KP_STIFF, smoothstep(0.26, 0.46, p))
				_kt_mix(KP_SAG, 0.55 * smoothstep(0.74, 1.0, p))
				plant = 1.0
				lie = lie_from * (1.0 - smoothstep(0.0, 0.3, p))
			else:
				# choked out, lowered on to his face, wrists pulled behind him
				_kt_set(KP_CHOKED)
				var fight := 1.0 - smoothstep(0.16, 0.34, p)
				_kt[K_CHEST_E].y += 0.17 * fight * sin(clock * 15.0)
				_kt[K_HIPS].x += 0.025 * fight * sin(clock * 15.0 + 1.0)
				_kt[K_WRIST_R].y += 0.03 * fight * sin(clock * 21.0)
				_kt_mix(KP_KNEES, smoothstep(0.24, 0.48, p))
				_kt_mix(KP_PRONE, smoothstep(0.48, 0.76, p))
				lie = lie_from + (1.0 - lie_from) * smoothstep(0.26, 0.64, p)
				plant = 1.0 - smoothstep(0.26, 0.46, p)
		CL_FALL:
			var s := clip_t / fall_time
			if s >= 1.0:
				s = 1.0
				clip = CL_LIE
				settle_t = 0.0
			# the knees go first, the trunk follows, the arms come down last
			_kt_set(KP_SAG)
			_kt_mix(lie_pose, smoothstep(0.25, 0.9, s))
			var a := (KP_FLAIL + key_bank) * KN
			var b := (lie_pose + key_bank) * KN
			var arms := smoothstep(0.5, 1.0, s)
			for i: int in range(K_WRIST_L, KN): _kt[i] = _kp[a + i].lerp(_kp[b + i], arms)
			lie = lie_from + (1.0 - lie_from) * pow(smoothstep(0.1, 1.0, s), 1.5)
			plant = 1.0 - smoothstep(0.25, 0.6, s)
			roll_to = KP_ROLL[lie_pose] * mirror * smoothstep(0.45, 1.0, s)
			roll = roll_to
		CL_LIE:
			lie = minf(1.0, lie + step * 4.0)
			settle_t += step
			_kt_set(lie_pose)
			roll_to = KP_ROLL[lie_pose] * mirror
			if st_state == "bound":
				# alive and not happy about it: breathing, and every few seconds a heave against the rope
				var breath := sin(clock * 2.1 + seed_a)
				_kt[K_CHEST_E].x += 0.035 * breath
				_kt[K_SPINE_E].x += 0.02 * breath
				var heave := _span(fposmod(clock * 0.21 + seed_a, 1.0), 0.0, 0.06, 0.2, 0.3)
				var kick := sin(clock * 10.0)
				_kt[K_FOOT_L] += Vector3(0, 0.07, 0.10) * heave * (0.5 + 0.5 * kick)
				_kt[K_FOOT_R] += Vector3(0, 0.09, 0.06) * heave * (0.5 - 0.5 * kick)
				_kt[K_CHEST_E].y += 0.16 * heave * sin(clock * 7.0)
				_kt[K_HEAD_E].x -= 0.35 * heave
				_kt[K_HEAD_E].y += 0.3 * heave * sin(clock * 5.0)
				roll_to += 0.16 * heave * sin(clock * 6.0) * mirror
			elif st_state == "stunned":
				# out cold, then groggy: the head lifts and drops, an arm drags under him
				var wake := 1.0 - smoothstep(1.0, 6.0, stun_left)
				_kt[K_CHEST_E].x -= 0.035 * (0.5 + 0.5 * sin(clock * 1.5 + seed_a))
				_kt_mix(KP_STIR, wake * (0.55 + 0.45 * sin(clock * 2.6)))
				_kt[K_HEAD_E].y += 0.5 * wake * sin(clock * 1.3)
				roll_to += 0.10 * wake * sin(clock * 1.9)
		CL_RISE:
			var s := clip_t / 0.9
			lie = lie_from * (1.0 - smoothstep(0.12, 0.8, s))
			_kt_set(KP_STIR)
			_kt_mix(KP_KNEES, smoothstep(0.0, 0.45, s))
			want = 1.0 - smoothstep(0.4, 0.95, s)
			if s >= 1.0: clip = CL_NONE
		CL_KNEEL:
			lie = 0.24 if snap else move_toward(lie, 0.24, step * 0.8)
			_kt_set(KP_SAG)
			_kt_mix(KP_KNEES, 0.6)
			# the head down, the shoulders drawn in, a slow breath
			_kt[K_HEAD_E].x += 0.35
			_kt[K_CHEST_E].x += 0.04 * sin(clock * 1.4 + seed_a)
			plant = 1.0
		CL_CARRIED:
			lie = 1.0
			_kt_set(KP_CARRIED)
			if grab_from != null and is_instance_valid(grab_from):
				# limp weight: everything that hangs swings with the bearer's step
				var stride: float = grab_from.phase
				var gait: float = grab_from.w_move
				var swing := sin(stride * TAU * 2.0) * gait
				var sway := sin(stride * TAU) * gait
				_kt[K_WRIST_L] += Vector3(0.03 * sway, -0.02 * swing, 0.06 * swing)
				_kt[K_WRIST_R] += Vector3(0.03 * sway, 0.02 * swing, 0.05 * swing)
				_kt[K_FOOT_L] += Vector3(0.02 * sway, 0.04 * swing, 0.0)
				_kt[K_FOOT_R] += Vector3(0.02 * sway, -0.03 * swing, 0.0)
				_kt[K_HEAD_E] += Vector3(0.08 * swing, 0.12 * sway, 0.0)
	key_w = want if snap else move_toward(key_w, want, step / (0.12 if want > key_w else 0.3))
	if clip != CL_FALL: roll = roll_to if snap else lerpf(roll, roll_to, 1.0 - exp(-step * 5.0))
	var kt := _ease(key_t)
	if kt >= 1.0:
		for i: int in range(KN): _k[i] = _kt[i]
	else:
		for i: int in range(KN): _k[i] = _k0[i].lerp(_kt[i], kt)

# ----------------------------------------------------------------------------------------------
# Pose
# ----------------------------------------------------------------------------------------------
## Fills _fz/_fy/_fp with one foot's forward offset, lift and pitch at cycle position pf (0..1).
func _foot_cycle(pf: float, beta: float, stride: float, lift: float, pk: float, shift: float, soft: float) -> void:
	var half := beta * stride * 0.5
	if pf < beta:
		# planted: slides back under the body at exactly travel speed, heel strike -> flat -> heel off
		var t := pf / beta
		_fz = half - pf * stride - shift
		_fp = (-0.30 * (1.0 - soft) * (1.0 - smoothstep(0.0, 0.2, t)) + 0.62 * smoothstep(0.58, 1.0, t)) * pk
		_fy = 0.0
	else:
		var s := (pf - beta) / (1.0 - beta)
		_fz = -half - shift + 2.0 * half * (s - sin(TAU * s) * 0.8 / TAU)
		_fp = (lerpf(0.62, 0.9, smoothstep(0.0, 0.2, s)) * (1.0 - smoothstep(0.2, 0.8, s)) - 0.30 * (1.0 - soft) * smoothstep(0.7, 1.0, s)) * pk
		_fy = lift * sin(PI * pow(s, 0.85))
	if _fp > 0.0:
		_fy += BALL * sin(_fp)
		_fz += BALL * (1.0 - cos(_fp))

func _ik(from: Vector3, target: Vector3, pole: Vector3, l1: float, l2: float) -> void:
	var to := target - from
	var dist := to.length()
	var dir := to / dist if dist > 0.0001 else Vector3.DOWN
	var d := clampf(dist, absf(l1 - l2) + 0.02, (l1 + l2) * 0.998)
	var perp := pole - dir * pole.dot(dir)
	if perp.length_squared() < 0.00001: perp = Vector3.FORWARD - dir * Vector3.FORWARD.dot(dir)
	perp = perp.normalized()
	var along := (l1 * l1 + d * d - l2 * l2) / (2.0 * d)
	_ik_mid = from + dir * along + perp * sqrt(maxf(l1 * l1 - along * along, 0.0))
	_ik_end = from + dir * d
	_ik_perp = perp

## Orientation for a limb segment whose bind direction is -Y, with its front (+Z) towards z_hint.
static func _limb(seg_dir: Vector3, z_hint: Vector3) -> Basis:
	var x := z_hint.cross(seg_dir)
	if x.length_squared() < 0.00001: x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, -seg_dir, x.cross(-seg_dir))

## Writes one bone; a body rolled about its spine has every bone turned with it.
func _bone(index: int, basis_m: Basis, origin_m: Vector3) -> void:
	if _rolled: skel.set_bone_pose(index, Transform3D(_roll_b * basis_m, _roll_b * origin_m))
	else: skel.set_bone_pose(index, Transform3D(basis_m, origin_m))

## A carried item's bone: rolls with the body like everything else that is attached to it.
func _item(index: int, xf: Transform3D) -> void:
	if _rolled: skel.set_bone_pose(index, Transform3D(_roll_b * xf.basis, _roll_b * xf.origin))
	else: skel.set_bone_pose(index, xf)

func _leg(thigh: int, hip: Vector3, ankle: Vector3, pole: Vector3, foot_b: Basis) -> void:
	_ik(hip, ankle, pole, L_THIGH, L_SHIN)
	if _rolled:
		_bone(thigh, _limb((_ik_mid - hip).normalized(), _ik_perp), hip)
		_bone(thigh + 1, _limb((_ik_end - _ik_mid).normalized(), _ik_perp), _ik_mid)
		_bone(thigh + 2, foot_b, _ik_end)
	else:
		skel.set_bone_pose(thigh, Transform3D(_limb((_ik_mid - hip).normalized(), _ik_perp), hip))
		skel.set_bone_pose(thigh + 1, Transform3D(_limb((_ik_end - _ik_mid).normalized(), _ik_perp), _ik_mid))
		skel.set_bone_pose(thigh + 2, Transform3D(foot_b, _ik_end))

func _arm(arm: int, shoulder: Vector3, wrist: Vector3, pole: Vector3, grip: Vector3, hold: float) -> void:
	_ik(shoulder, wrist, pole, L_ARM, L_FORE)
	var fore_dir := (_ik_end - _ik_mid).normalized()
	var fore := _limb(fore_dir, -_ik_perp)
	var reach := (_ik_end + fore_dir * 0.1).lerp(grip, hold) - _ik_end
	_hand_b = _limb(reach.normalized(), fore.z) if reach.length_squared() > 0.000001 else fore
	_hand_o = _ik_end
	if _rolled:
		_bone(arm, _limb((_ik_mid - shoulder).normalized(), -_ik_perp), shoulder)
		_bone(arm + 1, fore, _ik_mid)
		_bone(arm + 2, _hand_b, _ik_end)
	else:
		skel.set_bone_pose(arm, Transform3D(_limb((_ik_mid - shoulder).normalized(), -_ik_perp), shoulder))
		skel.set_bone_pose(arm + 1, Transform3D(fore, _ik_mid))
		skel.set_bone_pose(arm + 2, Transform3D(_hand_b, _ik_end))

## Free arm: wrist target in chest space from a shoulder swing angle and an elbow bend.
func _swing(side: float, swing: float, elbow: float, splay: float, tuck: float) -> Vector3:
	var upper := Vector3(side * (splay + arm_out), -cos(swing), sin(swing)).normalized()
	var fore := Vector3(-side * tuck * (1.0 - 2.0 * arm_out), -cos(swing + elbow), sin(swing + elbow)).normalized()
	return Vector3(side * shoulder_x, 0.205, 0.0) + upper * L_ARM + fore * L_FORE

## Root space to model space (worked out only in the frames that need it).
func _to_model() -> Transform3D:
	if not _rig_inv_ok:
		_rig_inv = _rig.affine_inverse()
		_rig_inv_ok = true
	return _rig_inv

## Where the Rig stands in root space: turned to face, tipped on to the ground as `lie` rises (the
## hips sinking from standing height to rest on the earth), nudged towards a partner.
func _rig_xf() -> Transform3D:
	var tip := Basis(Vector3.RIGHT, lie_sign * PI / 2.0 * _ease(lie))
	var side := sin(roll)
	var rest := lerpf(lie_front if lie_sign > 0.0 else lie_back, lie_side, side * side) - 0.07 * w_hidden + 0.03 * _span(settle_t, 0.0, 0.07, 0.07, 0.22)
	var hips_y := lerpf(JOINT[HIPS].y * height, rest, smoothstep(0.0, 1.0, lie))
	var turned := Basis(Vector3.UP, vis_yaw)
	var origin := Vector3(0, hips_y, 0) - tip * (JOINT[HIPS] * height)
	return Transform3D((turned * tip).scaled(Vector3.ONE * height), turned * origin + rig_off + lie_off * lie)

func _pose() -> void:
	var m := _ease(w_move)
	var sit := _ease(w_sit) if w_sit > 0.0 else 0.0
	var aboard := _ease(w_boat) if w_boat > 0.0 else 0.0
	var seat := maxf(sit, aboard)
	var rdy := _ease(w_ready) if w_ready > 0.0 else 0.0
	var aim := _ease(w_aim) if w_aim > 0.0 else 0.0
	var hid := _ease(w_hidden) if w_hidden > 0.0 else 0.0
	var edge := _ease(w_edge) if w_edge > 0.0 else 0.0
	var carry := _ease(w_carry) if w_carry > 0.0 else 0.0
	var td := _ease(w_td) if w_td > 0.0 else 0.0
	var at_ease := _ease(w_order) if w_order > 0.0 else 0.0
	var tp := maxf(throw_t, 0.0)
	var thr := smoothstep(0.0, 0.16, tp) * (1.0 - smoothstep(0.7, 1.0, tp)) if throw_t >= 0.0 else 0.0
	var hurt := _span(flinch_t, 0.0, 0.12, 0.35, 1.0) if flinch_t >= 0.0 else 0.0
	var jolt := _span(flinch_t, 0.0, 0.05, 0.1, 0.3) if flinch_t >= 0.0 else 0.0 # the blow itself, before he doubles over
	var kick := smoothstep(0.0, 0.03, recoil_t) * exp(-recoil_t * (9.0 if gun == GUN_RIFLE else 12.0)) if recoil_t >= 0.0 else 0.0
	# kneeling: tools, a body to lift or put down, a man to tie
	var stoop := w_pick * _span(pick_p, 0.0, 0.3, 0.42, 0.9) if w_pick > 0.0 else 0.0
	var lower := w_drop * smoothstep(0.0, 0.7, drop_p) if w_drop > 0.0 else 0.0
	var pin := 0.0
	if td > 0.0: pin = td * (1.0 if td_low else (0.0 if st_lethal else smoothstep(0.28, 0.6, td_p)))
	var act := maxf(maxf(_ease(w_act) if w_act > 0.0 else 0.0, stoop), maxf(pin, lower * 0.7))
	var civil := 1.0 if kind == "asset" else 0.0
	var c := maxf(maxf(_ease(w_crouch), act), hid * civil * (1.0 - m)) * (1.0 - 0.5 * thr)
	var u := smoothstep(1.35, 2.3, speed)
	var cyc := fposmod(phase, 1.0)
	var sn := sin(cyc * TAU)
	var cs := cos(cyc * TAU)
	var officer := 1.0 if guard_kind == "sergeant" else 0.0
	# a wound: hunched over it, favouring the left leg
	var limp := w_wound * m * (0.5 + 0.5 * cos((cyc - 0.3) * TAU))
	# --- paired actions pull the two figures together (the roots stay where the simulation has them)
	var off := Vector3.ZERO
	if td > 0.0 and pair_gap > 0.0:
		off = Basis(Vector3.UP, pair_yaw) * Vector3(0, 0, maxf(0.0, pair_gap - (0.52 if td_low else 0.36)) * (1.0 if td_low else 0.6) * td)
	elif w_hold > 0.0 and pair_gap > 0.0:
		off = Basis(Vector3.UP, pair_yaw) * Vector3(0, 0, -maxf(0.0, pair_gap - 0.36) * 0.4 * _ease(w_hold))
	rig_off = off
	# the common case is a man on his feet where the simulation has him
	if lie > 0.0 or off != Vector3.ZERO or lie_off != Vector3.ZERO: _rig = _rig_xf()
	else: _rig = Transform3D(Basis(Vector3.UP, vis_yaw).scaled(Vector3(height, height, height)), Vector3.ZERO)
	_rig_inv_ok = false
	_rolled = absf(roll) > 0.001 and w_carried < 1.0
	if _rolled: _roll_b = Basis(Vector3.UP, roll * (1.0 - w_carried))
	# --- gait numbers
	stride_len = lerpf(lerpf(lerpf(clampf(0.72 + 0.42 * speed, 0.9, 1.4), 0.82 + 0.36 * speed, u), 0.58 + 0.38 * speed, c), 1.02, carry)
	var beta := _gp(G_BETA, u, c) + 0.05 * carry
	var lift := _gp(G_LIFT, u, c)
	var shift := _gp(G_SHIFT, u, c)
	var pk := _gp(G_PITCH, u, c)
	var foot_x := _gp(G_FOOTX, u, c) + 0.03 * carry + stance_w
	# --- feet: ankle targets in model space
	_foot_cycle(cyc, beta, stride_len, lift, pk, shift, c)
	var foot_l := Vector3(foot_x, ANKLE + _fy, _fz)
	var pitch_l := _fp
	_foot_cycle(fposmod(cyc + 0.5, 1.0), beta, stride_len, lift, pk, shift, c)
	var foot_r := Vector3(-foot_x, ANKLE + _fy, _fz)
	var pitch_r := _fp
	# resting stances: stand, ready crouch, firing stance, at ease, kneel at work, sitting on the ground
	var rest_pr := lerpf(lerpf(lerpf(0.0, 0.62, c), 1.05, act), -0.12, seat)
	var rest_l := Vector3(0.10, ANKLE, 0.03).lerp(Vector3(0.125, ANKLE, 0.15), c).lerp(Vector3(0.11, ANKLE, 0.17), aim).lerp(Vector3(0.15, ANKLE, 0.01), at_ease).lerp(Vector3(0.125, ANKLE, 0.19), act).lerp(Vector3(0.11, ANKLE, 0.43), seat)
	var rest_r := Vector3(-0.10, ANKLE, -0.03).lerp(Vector3(-0.13, ANKLE, -0.17), c).lerp(Vector3(-0.13, ANKLE, -0.15), aim).lerp(Vector3(-0.14, ANKLE, -0.01), at_ease).lerp(Vector3(-0.12, ANKLE, -0.30), act).lerp(Vector3(-0.10, ANKLE, 0.40), seat)
	rest_r.y += BALL * sin(maxf(rest_pr, 0.0))
	rest_l.x += stance_w * (1.0 - seat)
	rest_r.x -= stance_w * (1.0 - seat)
	foot_l = rest_l.lerp(foot_l, m)
	foot_r = rest_r.lerp(foot_r, m)
	pitch_l = lerpf(-0.12 * seat, pitch_l, m)
	pitch_r = lerpf(rest_pr, pitch_r, m)
	# --- pelvis
	var idle_sway := sin(clock * 0.43 + seed_a) * (1.0 - m) * (1.0 - seat)
	var breath := sin(clock * 1.55 + seed_a * 2.0)
	var drop := lerpf(lerpf(0.012, 0.41, c), _gp(G_DROP, u, c), m) + 0.035 * rdy * (1.0 - c) + 0.03 * aim + 0.07 * act + 0.07 * hid * c + 0.02 * civil
	drop += (0.05 * carry + 0.02 * edge + 0.04 * w_wound) * (1.0 - c) + 0.06 * limp + 0.10 * hurt + 0.10 * hid * civil * (1.0 - m)
	var hips := Vector3((_gp(G_SWAY, u, c) * sway_k * (1.0 + 0.9 * carry) + 0.02 * w_wound) * sn * m + (0.028 + 0.03 * at_ease) * idle_sway,
		JOINT[HIPS].y - drop - _gp(G_BOB, u, c) * (1.0 + 1.2 * carry) * cos(cyc * 2.0 * TAU) * m + (0.003 * breath + 0.012 * officer * sin(clock * 1.1)) * (1.0 - m),
		lerpf(-0.09 * c, -0.03 * c, m))
	hips = hips.lerp(Vector3(0.0, 0.155, -0.10), seat)
	var lean := (lerpf(lerpf(0.0, 0.50, c), _gp(G_LEAN, u, c), m) + 0.12 * hid * c) * (1.0 - 0.55 * act) + 0.05 * aim + 0.10 * civil
	lean += 0.11 * carry + 0.06 * edge * (1.0 - aim) + 0.18 * w_wound * (1.0 - c) + 0.34 * hurt - 0.5 * jolt - 0.04 * officer + 0.35 * lower + 0.30 * hid * civil * (1.0 - m)
	lean += 0.10 * td * (1.0 - pin) + 0.28 * pin - 0.12 * kick * (1.0 if gun == GUN_REVOLVER else (0.8 if gun == GUN_RIFLE else 0.45))
	var pelvis_yaw := -_gp(G_PELV, u, c) * cs * m - 0.30 * aim
	var pelvis_roll := _gp(G_ROLL, u, c) * sway_k * (1.0 + carry) * sn * m + (0.04 + 0.05 * at_ease) * idle_sway + 0.11 * limp - 0.05 * carry
	# --- where the eyes go: guards sweep their arcs, operatives glance about, the informant frets
	var look := 0.0
	if enemy:
		var calm := 1.0 - maxf(rdy, w_tool)
		look = sin(clock * (0.62 + 0.11 * sin(seed_a)) + seed_a) * (0.62 - 0.3 * at_ease - 0.25 * officer * m) * calm
		# searching: long deliberate looks to either side; on edge: quick ones
		look += sin(clock * 1.7 + seed_a) * 0.55 * w_search + sin(clock * 3.1 + seed_a) * 0.22 * edge * (1.0 - aim) * (1.0 - w_search)
	elif civil > 0.0:
		look = sin(clock * 1.25) * 0.28 * (1.0 - sit) + sin(clock * 2.9) * 0.3 * m
	else:
		# standing: an easy glance about; crouched: a slow, deliberate sweep with the shoulders following
		look = (sin(clock * 0.37 + seed_a) * 0.24 + sin(clock * 0.83 + seed_a * 2.0) * (0.10 + 0.30 * c)) * (1.0 - m) * (1.0 - act) * (1.0 - w_gun) * (1.0 - td)
	var facing := 0.72 + 0.28 * maxf(aim, w_gaim) # a man taking aim squares his shoulders to the target
	var twist := (_gp(G_PELV, u, c) + _gp(G_TWIST, u, c)) * cs * m + 0.38 * look - 0.32 * aim + facing * turn
	twist += (0.45 * hurt + 0.3 * jolt + 0.10 * w_wound * (1.0 - m)) * (1.0 if key_bank == 0 else -1.0)
	var throw_lean := 0.0
	if thr > 0.0:
		twist += lerpf(-0.60, 0.55, smoothstep(0.12, 0.5, tp)) * thr
		throw_lean = 0.16 * smoothstep(0.1, 0.5, tp) * thr
	if td > 0.0 and st_lethal and not td_low:
		twist += lerpf(-0.35, 0.30, smoothstep(0.22, 0.42, td_p)) * td * (1.0 - smoothstep(0.8, 1.0, td_p))
	# keep the pelvis low enough that a planted leg never has to stretch (a little slack is fine)
	var hips_e := Vector3(lean * 0.30 - 0.28 * sit - 0.30 * aboard, pelvis_yaw, pelvis_roll)
	var hips_b := Basis.from_euler(hips_e)
	for side: int in range(2):
		var foot := foot_l if side == 0 else foot_r
		var joint := hips + hips_b * (JOINT[THIGH_L + side * 3] - JOINT[HIPS])
		var flat := Vector2(foot.x - joint.x, foot.z - joint.z).length_squared()
		var reach := (L_THIGH + L_SHIN) * 0.995
		hips.y = minf(hips.y, foot.y + sqrt(maxf(reach * reach - flat, 0.04)) + 0.03 - (joint.y - hips.y))
	var spine_e := Vector3(lean * 0.35 + 0.42 * sit + 0.30 * aboard, twist * 0.4, -pelvis_roll * 0.6 + 0.05 * carry)
	var chest_e := Vector3(lean * 0.35 + 0.40 * sit + 0.22 * aboard + throw_lean - 0.02 * breath - 0.03 * edge * breath, twist * 0.6, -pelvis_roll * 0.4 + 0.04 * carry)
	# --- key pose over the top (held, falling, lying, carried)
	var kw := _ease(key_w) if key_w > 0.0 else 0.0
	if kw > 0.0:
		hips = hips.lerp(_k[K_HIPS], kw)
		hips_e = hips_e.lerp(_k[K_HIPS_E], kw)
		spine_e = spine_e.lerp(_k[K_SPINE_E], kw)
		chest_e = chest_e.lerp(_k[K_CHEST_E], kw)
		hips_b = Basis.from_euler(hips_e)
	# a body settling after a fall: the trunk bounces once, the head nods after it
	var bounce := exp(-settle_t * 7.0) * sin(settle_t * 19.0) if clip == CL_LIE and settle_t < 0.8 else 0.0
	chest_e.x -= 0.09 * bounce
	var spine_b := hips_b * Basis.from_euler(spine_e)
	var chest_b := spine_b * Basis.from_euler(chest_e)
	var spine_o := hips + hips_b * (JOINT[SPINE] - JOINT[HIPS])
	var chest_o := spine_o + spine_b * (JOINT[CHEST] - JOINT[SPINE])
	chest_o.y += 0.006 * breath * (1.0 - kw)
	# head stays level and looks where the character is going
	var head_b := Basis.from_euler(Vector3(
		lean * 0.16 + 0.34 * sit + 0.26 * act + 0.14 * hid * c + 0.07 * aim + 0.08 * civil * (1.0 - seat) - 0.05 * rdy - 0.06 * officer + 0.2 * hurt + 0.10 * w_wound - 0.22 * w_tool * float(tool_kit == TOOL_GLASSES) - 0.5 * aim_pitch * maxf(aim, w_gaim),
		(pelvis_yaw + twist) * 0.3 + look * 0.62 + 0.10 * aim + 0.70 * turn + 0.8 * aboard * sin(clock * 0.45),
		-0.13 * aim + 0.03 * idle_sway - 0.10 * carry))
	if kw > 0.0:
		var hung := _k[K_HEAD_E]
		hung.x += 0.3 * bounce
		head_b = head_b.slerp(chest_b * Basis.from_euler(hung), kw)
	var head_o := chest_o + chest_b * (JOINT[HEAD] - JOINT[CHEST])
	if _rolled:
		_bone(HIPS, hips_b, hips)
		_bone(SPINE, spine_b, spine_o)
		_bone(CHEST, chest_b, chest_o)
		_bone(HEAD, head_b.scaled_local(Vector3.ONE * head_scale) if head_scale != 1.0 else head_b, head_o)
	else:
		skel.set_bone_pose(HIPS, Transform3D(hips_b, hips))
		skel.set_bone_pose(SPINE, Transform3D(spine_b, spine_o))
		skel.set_bone_pose(CHEST, Transform3D(chest_b, chest_o))
		skel.set_bone_pose(HEAD, Transform3D(head_b.scaled_local(Vector3.ONE * head_scale) if head_scale != 1.0 else head_b, head_o))
	# --- legs
	var knee_l := Vector3(0.10, 0.9 * seat, 1.0)
	var knee_r := Vector3(-0.10 - 0.25 * act, 0.9 * seat, 1.0)
	var foot_bl := Basis(Vector3.UP, 0.12) * Basis(Vector3.RIGHT, pitch_l)
	var foot_br := Basis(Vector3.UP, -0.12) * Basis(Vector3.RIGHT, pitch_r)
	if kw > 0.0:
		var key_l := hips + hips_b * _k[K_FOOT_L]
		var key_r := hips + hips_b * _k[K_FOOT_R]
		if plant > 0.0:
			# feet still on the ground where he stood while the body above them goes
			key_l = key_l.lerp(_to_model() * (Basis(Vector3.UP, vis_yaw) * Vector3(0.11, ANKLE, 0.04) * height + rig_off), plant)
			key_r = key_r.lerp(_to_model() * (Basis(Vector3.UP, vis_yaw) * Vector3(-0.11, ANKLE, -0.03) * height + rig_off), plant)
		foot_l = foot_l.lerp(key_l, kw)
		foot_r = foot_r.lerp(key_r, kw)
		knee_l = knee_l.lerp(hips_b * _k[K_KNEE_L], kw)
		knee_r = knee_r.lerp(hips_b * _k[K_KNEE_R], kw)
		var feet := _k[K_FEET]
		foot_bl = foot_bl.slerp(hips_b * Basis(Vector3.UP, feet.z) * Basis(Vector3.RIGHT, feet.x * (1.0 - plant)), kw)
		foot_br = foot_br.slerp(hips_b * Basis(Vector3.UP, -feet.z) * Basis(Vector3.RIGHT, feet.y * (1.0 - plant)), kw)
	_leg(THIGH_L, hips + hips_b * (JOINT[THIGH_L] - JOINT[HIPS]), foot_l, knee_l, foot_bl)
	var ankles := _ik_end
	_leg(THIGH_R, hips + hips_b * (JOINT[THIGH_R] - JOINT[HIPS]), foot_r, knee_r, foot_br)
	ankles = (ankles + _ik_end) * 0.5
	# --- arms, weapon, tools
	_chest = Transform3D(chest_b, chest_o)
	_hips_x = Transform3D(hips_b, hips)
	_wl = Vector3.ZERO
	_wr = Vector3.ZERO
	_pl = chest_b * Vector3(0.35, -0.25, -1.0)
	_pr = chest_b * Vector3(-0.35, -0.25, -1.0)
	_gl = Vector3.ZERO
	_gr = Vector3.ZERO
	_hl = 0.0
	_hr = 0.0
	if not enemy or kw > 0.0 or gun != GUN_RIFLE or w_order > 0.0 or w_slung > 0.0 or w_gdrop > 0.0:
		# free arms: swing with the stride (a rifleman with both hands on his weapon has none)
		var amp := _gp(G_SWING, u, c) * m * (1.0 - 0.6 * officer)
		var elbow := lerpf(lerpf(0.36, 1.10, c), _gp(G_ELBOW, u, c), m) + 0.55 * civil
		var fwd := 0.02 + 0.50 * c - 0.22 * u * m * (1.0 - c) + 0.10 * civil
		var tuck := 0.10 + 0.25 * c + 0.30 * civil
		var arm_l := -cs * amp
		_wl = _chest * _swing(1.0, fwd + arm_l + 0.12 * c, elbow + 0.25 * arm_l, 0.12, tuck)
		_wr = _chest * _swing(-1.0, fwd - arm_l - 0.10 * c, elbow - 0.25 * arm_l, 0.12, tuck)
	if enemy: _arms_guard(m, cyc, rdy, aim, at_ease, kick, breath, head_b, head_o)
	else: _arms_operative(m, sit, aboard, act, thr, tp, carry, td, stoop, lower, kick, hurt, civil)
	if kw > 0.0:
		_wl = _wl.lerp(_chest * _k[K_WRIST_L], kw)
		_wr = _wr.lerp(_chest * _k[K_WRIST_R], kw)
		_pl = _pl.lerp(chest_b * _k[K_ELBOW_L], kw)
		_pr = _pr.lerp(chest_b * _k[K_ELBOW_R], kw)
		_hl *= 1.0 - kw
		_hr *= 1.0 - kw
	_arm(ARM_L, _chest * (_joint_at(ARM_L, shoulder_x) - JOINT[CHEST]), _wl, _pl, _gl, _hl)
	var left_o := _hand_o
	_arm(ARM_R, _chest * (_joint_at(ARM_R, shoulder_x) - JOINT[CHEST]), _wr, _pr, _gr, _hr)
	if tool_kit == TOOL_KNIFE or tool_kit == TOOL_COSH:
		# the knife: sheathed across the back of the belt, or point-first from the right fist (the cosh: in the
		# coat pocket, or swung from the fist the same way)
		var blade := _hips_x * stow_tool
		if w_tool > 0.0: blade = blade.interpolate_with(Transform3D(_hand_b * Basis(Vector3.RIGHT, PI / 2.0), _hand_o + _hand_b * Vector3(0, -0.085, 0.015)), _ease(w_tool))
		_item(TOOL, blade)
	# --- anchors for partners and the selection marker, in root space
	var mid := (left_o + _hand_o) * 0.5
	if tool_kit == TOOL_ROPE and (w_tied > 0.0 or bonds_out):
		# the lashings appear as the knots are pulled tight
		bonds_out = w_tied > 0.0
		var tight := maxf(0.001, _ease(w_tied))
		_bone(TOOL, chest_b.scaled(Vector3.ONE * tight), mid + chest_b * Vector3(0, 0.035, 0))
		_bone(TOOL_B, hips_b.scaled(Vector3.ONE * tight), ankles + hips_b * Vector3(0, 0.05, 0))
	if _rolled:
		a_head = _rig * (_roll_b * head_o)
		a_chest = _rig * (_roll_b * chest_o)
		a_hands = _rig * (_roll_b * mid)
	else:
		a_head = _rig * head_o
		a_chest = _rig * chest_o
		a_hands = _rig * mid
	if carry > 0.0 or w_pick > 0.0 or w_drop > 0.0:
		# where a body rides: on top of the right shoulder
		carry_xf = Transform3D(Basis(Vector3.UP, vis_yaw + atan2(chest_b.z.x, chest_b.z.z)) * Basis(Vector3.RIGHT, 0.5 * lean + 0.5 * lower),
			_rig * (_chest * Vector3(-0.165, 0.375 - 0.03 * lower, -0.02)))
	_place(hips, seat, c)
	if flash_t >= 0.0 or flash != null: _show_flash()

## Puts the Rig, the contact shadow and the cover look where this frame's state says.
func _place(hips: Vector3, seat: float, c: float) -> void:
	if w_carried > 0.0:
		# over a shoulder (or on the way there / back): the Rig leaves its root and follows the bearer
		if (clip == CL_CARRIED or grab_ttl > 0) and grab_from != null and is_instance_valid(grab_from):
			var bearer: Transform3D = grab_from.carry_xf
			bearer.origin += grab_from.global_position
			var across := Basis(Vector3(-1, 0, 0), Vector3(0, -0.12, -1).normalized(), Vector3(0, -1, 0.12).normalized()).orthonormalized()
			var slack := 0.05 * sin(float(grab_from.phase) * TAU * 2.0) * float(grab_from.w_move)
			var basis_c := bearer.basis * Basis(Vector3.FORWARD, slack) * across
			carry_g = Transform3D(basis_c.scaled(Vector3.ONE * height), bearer.origin - basis_c * (JOINT[HIPS] * height))
		var home := Transform3D(Basis.IDENTITY, Vector3(position.x, st_elevation, position.z)) * _rig
		if not skel.top_level: skel.top_level = true
		skel.global_transform = home.interpolate_with(carry_g, _ease(w_carried))
	else:
		if skel.top_level: skel.top_level = false
		skel.transform = _rig
	var covered := w_hidden > 0.5 and lie > 0.5
	if baked:
		if covered != baked_covered:
			baked_covered = covered
			for i: int in range(body.mesh.get_surface_count()):
				body.set_surface_override_material(i, Figure.cover(body.mesh.surface_get_material(i)) if covered else null)
	else:
		var want_material := _cover_material if covered else _body_material
		if body.material_override != want_material: body.material_override = want_material
	var grounded := w_carried < 0.5 and not covered
	if blob.visible != grounded: blob.visible = grounded
	if not grounded: return
	# contact shadow: under the hips of a standing man, stretched under a lying one
	var flat := _ease(lie)
	var spread := 0.86 + 0.16 * c + 0.30 * seat
	blob.scale = Vector3(spread * (1.0 - 0.1 * flat), 1.0, spread * (1.0 + 0.25 * c + 0.3 * seat + 1.0 * flat))
	blob.rotation.y = vis_yaw
	var under := (Basis(Vector3.UP, vis_yaw) * Vector3(hips.x, 0.0, hips.z + 0.10 * c + 0.2 * seat) * height + rig_off).lerp((a_chest + _rig * hips) * 0.5, flat)
	blob.position = Vector3(under.x, 0.02, under.z)
	if ui_scale != 1.0: blob.scale *= Vector3(ui_scale, 1.0, ui_scale)

## The muzzle flash: one camera-facing quad at the muzzle for a few hundredths of a second.
func _show_flash() -> void:
	if flash_t < 0.0:
		if flash != null and flash.visible and (not flash_warming or Time.get_ticks_msec() > _flash_warm_until):
			flash.visible = false
			flash_warming = false
		return
	if flash == null: _make_flash()
	flash_warming = false
	flash.visible = true
	var prop: Transform3D = skel.get_bone_pose(PROP)
	var fade := 1.0 - flash_t / FLASH_TIME
	var size := (0.34 if two_hands else (0.62 if gun == GUN_RIFLE else 0.7)) * (0.55 + 0.45 * fade)
	var cam := get_viewport().get_camera_3d()
	var facing := cam.global_basis if cam != null else Basis.IDENTITY
	var at: Vector3 = skel.global_transform * (prop * (muzzle + Vector3(0, 0, 0.10)))
	# a model's own weapon (the art pack's): at its muzzle
	var tip: Variant = cutout.muzzle() if cutout != null and cutout.has_method("muzzle") else null
	if tip is Vector3: at = tip
	flash.global_transform = Transform3D((facing * Basis(Vector3.BACK, flash_roll)).scaled(Vector3.ONE * size), at)

func _make_flash() -> void:
	flash = MeshInstance3D.new()
	flash.name = "MuzzleFlash"
	flash.mesh = _flash_mesh
	flash.material_override = _flash_material
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flash)

## Guards: both hands on the rifle (port arms on patrol, levelled when uneasy, shouldered when sure,
## grounded at ease, slung for the lookout), the sergeant's hands behind his back until he draws.
func _arms_guard(m: float, cyc: float, rdy: float, aim: float, at_ease: float, kick: float, breath: float, head_b: Basis, head_o: Vector3) -> void:
	var chest_b := _chest.basis
	var gone := _ease(w_gdrop)
	if gun == GUN_RIFLE:
		var shoulder := Transform3D(Basis(Vector3.RIGHT, -aim_pitch * aim), Vector3(0, 0.2, 0)) * Transform3D(Basis.IDENTITY, Vector3(0, -0.2, 0))
		var prop := Transform3D(
			Basis(_rifle_port.basis.get_rotation_quaternion().slerp(_rifle_ready.basis.get_rotation_quaternion(), rdy).slerp(_rifle_aim.basis.get_rotation_quaternion(), aim)),
			_rifle_port.origin.lerp(_rifle_ready.origin, rdy).lerp(_rifle_aim.origin, aim))
		prop.origin.y += 0.008 * sin(cyc * 2.0 * TAU) * m - 0.004 * breath
		prop = shoulder * prop
		# the shot kicks it back and up; then he drops it from the shoulder to work the bolt
		var bolt := _span(recoil_t, 0.2, 0.34, 0.62, 0.85) if recoil_t >= 0.0 else 0.0
		if kick > 0.0 or bolt > 0.0:
			prop = prop * Transform3D(Basis(Vector3.RIGHT, -0.26 * kick + 0.20 * bolt) * Basis(Vector3.BACK, -0.35 * bolt), Vector3(0, -0.03 * bolt, -0.10 * kick))
		prop = _chest * prop
		var slung_w := _ease(w_slung)
		var free_r := maxf(slung_w, gone)
		var free_l := maxf(free_r, at_ease)
		if at_ease > 0.0: prop = prop.interpolate_with(_rifle_order, at_ease)
		if slung_w > 0.0: prop = prop.interpolate_with(_chest * _rifle_slung, slung_w)
		if gone > 0.0:
			# out of his hands: it lies where it fell, beside him (and does not roll over with him)
			var dropped := _to_model() * Transform3D(Basis(Vector3.UP, vis_yaw + (0.0 if key_bank == 0 else 2.4)), rig_off + lie_off * lie) * _rifle_ground
			if _rolled: prop = Transform3D(_roll_b * prop.basis, _roll_b * prop.origin)
			skel.set_bone_pose(PROP, prop.interpolate_with(dropped.orthonormalized(), gone * gone))
		else:
			_item(PROP, prop)
		var grip_z := 0.56 * at_ease
		var hand_r := prop * Vector3(-0.012 - 0.01 * at_ease, -0.05 + 0.03 * at_ease, -0.065 + grip_z)
		if bolt > 0.0:
			var stroke := sin(clampf((recoil_t - 0.3) / 0.4, 0.0, 1.0) * PI)
			hand_r = hand_r.lerp(prop * Vector3(-0.05, 0.05, 0.0 - 0.10 * stroke), bolt)
		_wr = _wr.lerp(hand_r, 1.0 - free_r)
		_wl = _wl.lerp(prop * Vector3(0.022, -0.068, 0.225), 1.0 - free_l)
		_gr = prop * Vector3(0.0, -0.005, grip_z)
		_gl = prop * Vector3(0.0, -0.012, 0.255)
		_hr = 1.0 - free_r
		_hl = 1.0 - free_l
		_pr = _pr.lerp(chest_b * Vector3(-1.0, -0.6 + 0.28 * aim + 0.25 * bolt, -0.45), 1.0 - free_r)
		_pl = _pl.lerp(chest_b * Vector3(0.7, -0.9, -0.2), 1.0 - free_l)
		if at_ease > 0.0:
			# at ease: left thumb hooked in the belt
			_wl = _wl.lerp(_chest * Vector3(0.15, -0.20, 0.10), at_ease * (1.0 - free_r))
			_pl = _pl.lerp(chest_b * Vector3(1.0, -0.2, -0.5), at_ease)
	else:
		# the sergeant: hands clasped in the small of his back until something makes him draw
		var calm := (1.0 - _ease(w_gun)) * (1.0 - gone)
		_wl = _wl.lerp(_chest * Vector3(0.035, -0.265, -0.145), calm)
		_wr = _wr.lerp(_chest * Vector3(-0.045, -0.28, -0.14), calm)
		_pl = _pl.lerp(chest_b * Vector3(1.0, -0.2, -0.5), calm)
		_pr = _pr.lerp(chest_b * Vector3(-1.0, -0.2, -0.5), calm)
		# stopped to inspect: the right fist comes round on to his hip
		var inspect := calm * (1.0 - m) * smoothstep(-0.2, 0.3, sin(clock * 0.6 + seed_a))
		_wr = _wr.lerp(_chest * Vector3(-0.215, -0.20, 0.035), inspect)
		_pr = _pr.lerp(chest_b * Vector3(-1.0, 0.1, -0.6), inspect)
		_sidearm(kick)
	if tool_kit == TOOL_GLASSES:
		# field glasses: hanging on his chest, or up at his eyes with both elbows out
		var glass := _chest * stow_tool
		var up := _ease(w_tool) * (1.0 - gone)
		if up > 0.0:
			glass = glass.interpolate_with(Transform3D(head_b, head_o + head_b * Vector3(0, 0.125, 0.155)), up)
			_wl = _wl.lerp(glass * Vector3(0.075, -0.035, -0.02), up)
			_wr = _wr.lerp(glass * Vector3(-0.075, -0.035, -0.02), up)
			_pl = _pl.lerp(chest_b * Vector3(1.0, -0.5, 0.1), up)
			_pr = _pr.lerp(chest_b * Vector3(-1.0, -0.5, 0.1), up)
			_gl = glass * Vector3(0.04, 0, 0.02)
			_gr = glass * Vector3(-0.04, 0, 0.02)
			_hl = maxf(_hl, up)
			_hr = maxf(_hr, up)
		_item(TOOL, glass)

## Pistol or revolver: holstered, low ready, levelled at the target (two hands for Wren, one for the
## others), kicking on the shot. Drives the right hand, and the left when it supports.
func _sidearm(kick: float) -> void:
	var holster := _hips_x * stow_prop
	var out := _ease(w_gun)
	if out <= 0.0:
		_item(PROP, holster)
		return
	var up := _ease(w_gaim)
	var chest_b := _chest.basis
	var level := Transform3D(Basis(Vector3.UP, atan2(chest_b.z.x, chest_b.z.z)) * Basis(Vector3.RIGHT, -aim_pitch), _chest.origin)
	var jump := kick * (0.75 if gun == GUN_REVOLVER else 0.4)
	var aimed := level * (_side_aim2 if two_hands else _side_aim1) * Transform3D(Basis(Vector3.RIGHT, -jump), Vector3(0, 0.05 * jump, -0.09 * jump))
	var held := (_chest * _side_ready).interpolate_with(aimed, up)
	var prop := holster.interpolate_with(held, smoothstep(0.2, 1.0, out))
	_item(PROP, prop)
	_wr = _wr.lerp(prop * Vector3(0.0, -0.045, -0.085), smoothstep(0.0, 0.7, out))
	_gr = prop * Vector3(0.0, 0.0, 0.02)
	_hr = out
	_pr = _pr.lerp(chest_b * Vector3(-0.8, -0.8, -0.2), out)
	if two_hands:
		_wl = _wl.lerp(prop * Vector3(0.05, -0.07, -0.05), out)
		_gl = prop * Vector3(0.012, -0.02, 0.01)
		_hl = out
		_pl = _pl.lerp(chest_b * Vector3(0.8, -0.8, -0.2), out)
	else:
		# the free arm tucked in out of the way
		_wl = _wl.lerp(_chest * Vector3(0.20, -0.16, 0.08), out * up)

## Operatives and the informant: everything their hands do.
func _arms_operative(m: float, sit: float, aboard: float, act: float, thr: float, tp: float, carry: float, td: float, stoop: float, lower: float, kick: float, hurt: float, civil: float) -> void:
	var chest_b := _chest.basis
	if civil > 0.0:
		# freed and waiting: hands wrung together at the belt; captive: arms wrapped round the knees;
		# in the boat: sitting up, forearms on his knees, looking about
		var wring := (1.0 - m) * (1.0 - maxf(sit, aboard))
		_wl = _wl.lerp(_chest * Vector3(0.075, -0.17 + 0.008 * sin(clock * 2.3), 0.15), wring).lerp(Vector3(0.085, 0.50, 0.36), sit).lerp(Vector3(0.15, 0.52, 0.34), aboard)
		_wr = _wr.lerp(_chest * Vector3(-0.075, -0.18, 0.155), wring).lerp(Vector3(-0.085, 0.48, 0.375), sit).lerp(Vector3(-0.14, 0.50, 0.36), aboard)
		_hl = maxf(wring, sit)
		_hr = _hl
		_gl = (_chest * Vector3(-0.01, -0.215, 0.215)).lerp(Vector3(-0.01, 0.46, 0.44), sit)
		_gr = (_chest * Vector3(0.01, -0.225, 0.20)).lerp(Vector3(0.01, 0.45, 0.425), sit)
		_pl = _pl.lerp(Vector3(0.7, -1.0, -0.3), sit)
		_pr = _pr.lerp(Vector3(-0.7, -1.0, -0.3), sit)
		# keeping down in a bush: one hand on the ground, the other shielding his head
		var duck := _ease(w_hidden) * (1.0 - m)
		_wl = _wl.lerp(Vector3(0.24, 0.10, 0.30), duck)
		_wr = _wr.lerp(_chest * Vector3(-0.10, 0.30, 0.20), duck)
		_hl *= 1.0 - duck
		_hr *= 1.0 - duck
		return
	if w_smoke > 0.0:
		# the right hand brings the cigarette to his mouth every few seconds; the left is in his jacket pocket
		var sm := _ease(w_smoke)
		var cyc := fposmod(clock * 0.24 + seed_a, 1.0)
		var drag := smoothstep(0.0, 0.12, cyc) * (1.0 - smoothstep(0.32, 0.46, cyc))
		_wr = _wr.lerp(_chest * Vector3(-0.05, lerpf(0.02, 0.27, drag), lerpf(0.21, 0.16, drag)), sm)
		_wl = _wl.lerp(_chest * Vector3(0.165, -0.27, 0.07), sm)
		_pr = _pr.lerp(_chest.basis * Vector3(-0.8, -0.6, -0.3), sm)
	# a wound: the left hand pressed to it
	var nurse := w_wound * (1.0 - maxf(maxf(carry, td), maxf(act, w_gun * float(two_hands))))
	if nurse > 0.0:
		_wl = _wl.lerp(_chest * Vector3(0.10, -0.15, 0.135), nurse)
		_pl = _pl.lerp(chest_b * Vector3(1.0, -0.4, -0.4), nurse)
	var cutters_out := false
	if act > 0.0 and w_act > 0.0:
		var work := _ease(w_act)
		match act_kind:
			"unlock":
				# kneeling at the lock: left hand steadies, right hand works the pick
				_wl = _wl.lerp(Vector3(0.06, 0.86 + 0.004 * sin(clock * 3.1), 0.42), work)
				_wr = _wr.lerp(Vector3(-0.05 + 0.012 * sin(clock * 9.0), 0.82 + 0.012 * cos(clock * 7.0), 0.41), work)
			"rescue":
				# helping the informant up
				_wl = _wl.lerp(Vector3(0.10, 0.62 + 0.05 * sin(clock * 4.0), 0.50), work)
				_wr = _wr.lerp(Vector3(-0.15, 0.80, 0.30), work)
			"plant":
				# setting a charge: reach out and down with it, press it home, then the fiddly bit with the fuse
				var reach := smoothstep(0.0, 0.3, act_p) * (1.0 - 0.35 * smoothstep(0.7, 0.9, act_p))
				var fiddle := smoothstep(0.55, 0.65, act_p) * (1.0 - smoothstep(0.92, 1.0, act_p))
				_wl = _wl.lerp(Vector3(0.12, lerpf(0.75, 0.30, reach), lerpf(0.35, 0.62, reach)), work)
				_wr = _wr.lerp(Vector3(-0.08 + 0.02 * sin(clock * 8.0) * fiddle, lerpf(0.75, 0.36, reach) + 0.03 * fiddle, lerpf(0.35, 0.58, reach)), work)
			"trap":
				# a peg pushed in on the left, the wire paid out across to the right, the second peg
				var across := smoothstep(0.34, 0.7, act_p)
				var tap := 0.035 * absf(sin(clock * 10.0))
				_wl = _wl.lerp(Vector3(0.26, 0.12 + tap * (1.0 - smoothstep(0.25, 0.35, act_p)), 0.40), work)
				_wr = _wr.lerp(Vector3(lerpf(0.16, -0.30, across), 0.13 + tap * smoothstep(0.72, 0.8, act_p) + 0.06 * sin(across * PI), 0.40), work)
			"trap_pickup":
				# pegs out, wire gathered in hand over hand, up to the pouch
				var gather := smoothstep(0.3, 0.75, act_p)
				var stow := smoothstep(0.78, 1.0, act_p)
				_wl = _wl.lerp(Vector3(0.24, 0.13, 0.40).lerp(Vector3(0.10, 0.5, 0.26), stow), work)
				_wr = _wr.lerp(Vector3(lerpf(-0.30, 0.10, gather) + 0.04 * sin(clock * 12.0) * gather * (1.0 - stow), 0.14 + 0.04 * absf(sin(clock * 12.0)) * gather, 0.40).lerp(Vector3(-0.10, 0.5, 0.26), stow), work)
			"cut", "sabotage":
				if act_kind == "sabotage" and tool_kit != TOOL_CUTTERS:
					# a main switch: both hands up on the lever, then a hard pull down
					var pull := smoothstep(0.45, 0.75, act_p)
					_wl = _wl.lerp(Vector3(0.06, lerpf(1.05, 0.62, pull), 0.42), work)
					_wr = _wr.lerp(Vector3(-0.06, lerpf(1.1, 0.66, pull), 0.40), work)
				else:
					cutters_out = true
					_use_cutters(work)
	if tool_kit == TOOL_CUTTERS and not cutters_out:
		var stowed := _chest * stow_tool
		_item(TOOL, stowed)
		_item(TOOL_B, stowed)
	if thr > 0.0:
		# quiet sidearm lob: hand drawn back by the hip -> flicked forward at waist height -> across the body
		var throw_hand := Vector3(-0.34, -0.20, -0.24).lerp(Vector3(-0.16, -0.10, 0.36), _ease(clampf((tp - 0.14) / 0.26, 0.0, 1.0))).lerp(Vector3(0.10, 0.02, 0.30), _ease(clampf((tp - 0.40) / 0.32, 0.0, 1.0)))
		_wr = _wr.lerp(_chest * throw_hand, thr)
		_wl = _wl.lerp(_chest * Vector3(0.20, -0.16, 0.26).lerp(Vector3(0.26, -0.22, -0.04), smoothstep(0.1, 0.6, tp)), thr)
		_pr = _pr.lerp(chest_b * Vector3(-1.0, -0.5, -0.5), thr)
	# --- a body: reach down for it, heave it over the right shoulder, steady it, let it slide off
	var loaded := maxf(carry, w_pick * smoothstep(0.38, 0.9, pick_p)) * (1.0 - 0.6 * lower)
	if stoop > 0.0 or loaded > 0.0 or lower > 0.0:
		var grab := Vector3(0.0, 0.25, 0.55)
		var other: Node3D = _mate(st_target) if w_pick > 0.0 else null
		if other != null: grab = _to_model() * (other.global_position - global_position + Vector3(other.a_chest)) * Vector3(1, 0, 1) + Vector3(0, 0.22, 0)
		var reach := w_pick * (1.0 - smoothstep(0.3, 0.55, pick_p))
		_wl = _wl.lerp(grab + Vector3(0.14, 0, 0), reach)
		_wr = _wr.lerp(grab + Vector3(-0.14, 0, 0), reach)
		var heft := 0.012 * sin(phase * TAU * 2.0) * m
		_wr = _wr.lerp(_chest * Vector3(-0.07, 0.07 + heft, 0.27), loaded)
		_wl = _wl.lerp(_chest * Vector3(-0.10, 0.33 + heft, 0.13), loaded * (1.0 - 0.55 * m))
		_pr = _pr.lerp(chest_b * Vector3(-1.0, -0.5, 0.1), loaded)
		_pl = _pl.lerp(chest_b * Vector3(0.9, -0.6, 0.2), loaded)
		# letting it go: both hands follow it down
		var release := w_drop * smoothstep(0.5, 1.0, drop_p) * (1.0 - carry)
		_wl = _wl.lerp(Vector3(0.14, 0.45, 0.42), release)
		_wr = _wr.lerp(Vector3(-0.14, 0.45, 0.42), release)
	if gun != GUN_NONE: _sidearm(kick)
	if td > 0.0: _arms_takedown(td)
	if hurt > 0.0:
		# hit: both arms snatched in
		_wl = _wl.lerp(_chest * Vector3(0.12, 0.02, 0.16), hurt * 0.7)
		_wr = _wr.lerp(_chest * Vector3(-0.14, -0.02, 0.15), hurt * 0.7 * (1.0 - _hr))

## Long-handled cutters in both fists: jaws to the wire, a slow open and a hard squeeze, three times.
## At the generator the same tool goes in after a lead: feel for it, one bite, then the left hand
## reaches in and rips the lead out.
func _use_cutters(work: float) -> void:
	var stowed := _chest * stow_tool
	var out := _ease(w_tool)
	var bite := 0.0
	var done := 0.0
	var pivot: Transform3D
	if act_kind == "cut":
		var beat := fposmod(act_p * 3.0, 1.0)
		bite = smoothstep(0.42, 0.62, beat) * (1.0 - smoothstep(0.86, 1.0, beat))
		pivot = Transform3D(Basis(Vector3.RIGHT, 0.12 - 0.06 * bite), _chest.origin + Vector3(0.0, -0.20 + 0.02 * bite, 0.62))
	else:
		var feel := sin(clock * 5.0) * (1.0 - smoothstep(0.3, 0.42, act_p))
		bite = 1.0 - _span(act_p, 0.26, 0.42, 0.5, 0.58)
		done = smoothstep(0.62, 0.78, act_p)
		pivot = Transform3D(Basis(Vector3.RIGHT, -0.12 + 0.6 * done), _chest.origin + Vector3(0.025 * feel, 0.02 + 0.015 * feel - 0.2 * done, 0.60 - 0.16 * done))
	var open := 0.34 * (1.0 - bite) + 0.03
	var half_a := pivot * Transform3D(Basis(Vector3.UP, -open), Vector3.ZERO)
	var half_b := pivot * Transform3D(Basis(Vector3.UP, open), Vector3.ZERO)
	skel.set_bone_pose(TOOL, stowed.interpolate_with(half_a, out))
	skel.set_bone_pose(TOOL_B, stowed.interpolate_with(half_b, out))
	var grasp := work * out
	var left := grasp * (1.0 - done)
	_wl = _wl.lerp(half_a * Vector3(0.05, -0.02, -0.50), left)
	_wr = _wr.lerp(half_b * Vector3(-0.05, -0.02, -0.50), grasp)
	_gl = half_a * Vector3(0.013, 0, -0.40)
	_gr = half_b * Vector3(-0.013, 0, -0.40)
	_hl = left
	_hr = grasp
	_pl = _pl.lerp(_chest.basis * Vector3(1.0, -0.5, -0.2), grasp)
	_pr = _pr.lerp(_chest.basis * Vector3(-1.0, -0.5, -0.2), grasp)
	if done > 0.0:
		var rip := smoothstep(0.84, 0.95, act_p)
		_wl = _wl.lerp((_chest.origin + Vector3(0.06, 0.04, 0.60)).lerp(_chest * Vector3(0.34, 0.10, 0.10), rip), work * done)

## Knife or rope: the hands go where the guard actually is (his head, back and wrists come from his model).
func _arms_takedown(td: float) -> void:
	var chest_b := _chest.basis
	var face := _chest * Vector3(0.0, 0.25, 0.40)
	var back := _chest * Vector3(0.0, -0.05, 0.36)
	var wrists := Vector3(0.0, 0.30, 0.55)
	var other := _mate(st_target)
	if other != null:
		var rel: Vector3 = other.global_position - global_position
		face = _to_model() * (rel + Vector3(other.a_head))
		back = _to_model() * (rel + Vector3(other.a_chest))
		wrists = _to_model() * (rel + Vector3(other.a_hands))
	var p := td_p
	if st_stun:
		# the left hand takes him by the collar, the right swings the cosh up over the shoulder and brings it down
		# on the back of his head; then both let him go down
		var raise := smoothstep(0.0, 0.32, p) * (1.0 - smoothstep(0.38, 0.48, p))
		var blow := smoothstep(0.36, 0.5, p)
		var done := smoothstep(0.75, 1.0, p)
		var crown := face + Vector3(0.0, 0.10, -0.06)
		_wl = _wl.lerp((back + Vector3(0.10, 0.16, -0.02)).lerp(_chest * Vector3(0.22, -0.2, 0.25), done), td)
		var up := _chest * Vector3(-0.26, 0.42, -0.04)
		var low := _chest * Vector3(-0.26, -0.20, 0.18)
		_wr = _wr.lerp(low.lerp(up, raise).lerp(crown, blow * (1.0 - done)).lerp(low, done), td)
		_pr = _pr.lerp(chest_b * Vector3(-1.0, 0.4 * raise - 0.3, -0.3), td)
		_pl = _pl.lerp(chest_b * Vector3(1.0, -0.3, -0.2), td)
	elif st_lethal:
		var strike := smoothstep(0.24, 0.40, p)
		var done := smoothstep(0.8, 1.0, p)
		if td_low:
			# one knee down beside him, a hand on his shoulder, one short thrust
			_wl = _wl.lerp(back + Vector3(0.10, 0.12, 0.05), td)
			_wr = _wr.lerp(Vector3(-0.26, 0.86, 0.10).lerp(back + Vector3(-0.05, 0.20, 0.0), strike).lerp(Vector3(-0.22, 0.6, 0.2), done), td)
		else:
			# left hand clamped over his mouth from behind, the right drives the knife in under the ribs
			_wl = _wl.lerp(face + Vector3(0.05, -0.06, 0.09), td * smoothstep(0.0, 0.2, p) * (1.0 - done))
			_pl = _pl.lerp(chest_b * Vector3(1.0, 0.3, -0.2), td)
			_wr = _wr.lerp((_chest * Vector3(-0.30, -0.22, -0.12)).lerp(back + Vector3(-0.07, -0.16, -0.14), strike).lerp(_chest * Vector3(-0.26, -0.25, 0.10), done), td)
			_pr = _pr.lerp(chest_b * Vector3(-1.0, -0.3, -0.6), td)
	else:
		var wind := clock * 11.0
		var tie_l := wrists + Vector3(0.05 + 0.045 * sin(wind), 0.07, 0.04 * cos(wind))
		var tie_r := wrists + Vector3(-0.05 - 0.045 * sin(wind), 0.08, -0.04 * cos(wind))
		if td_low:
			_wl = _wl.lerp(tie_l, td)
			_wr = _wr.lerp(tie_r, td)
		else:
			# the lock: right forearm across his throat, left hand hauling on it; then both hands on his
			# shoulders as he is put down; then the rope
			var lock := 1.0 - smoothstep(0.24, 0.4, p)
			var tie := smoothstep(0.56, 0.7, p)
			var press := (1.0 - lock) * (1.0 - tie)
			_wr = _wr.lerp((face + Vector3(0.11, -0.15, 0.06)) * lock + (back + Vector3(-0.13, 0.10, -0.04)) * press + tie_r * tie, td)
			_wl = _wl.lerp((face + Vector3(-0.03, -0.10, -0.02)) * lock + (back + Vector3(0.13, 0.10, -0.04)) * press + tie_l * tie, td)
			_pr = _pr.lerp(chest_b * Vector3(-1.0, 0.25 * lock - 0.3, -0.2), td)
			_pl = _pl.lerp(chest_b * Vector3(1.0, -0.3, -0.3), td)
