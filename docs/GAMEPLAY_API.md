# Hora Cero — gameplay API

Reference for everyone building on the rules: animator, HUD/controls, world/visuals, audio.
The rules live in `godot/scripts/simulation.gd` (one `RefCounted`, no nodes); a level is its data,
`godot/data/plaza.json` (the Plaza de Mayo) and `godot/data/riachuelo.json` (Riachuelo), each written by its layout
script (`tools/dev/plaza_layout.py`, `tools/dev/riachuelo_layout.py`: edit those, not the JSON).

A note on the examples. The rules engine was first written for an earlier, two-man level that is not part of this
repository: sections 2 to 13 describe the rules with that level's defaults and people as examples (two operatives,
Wren and Rook; a cell, an informant and a boat; five guards and a tower). The engine keeps those defaults, but
Hora Cero's levels set their own people, words and settings through their data: the keys of section 13, and the
levels themselves in sections 14d (Riachuelo) and 14e (the Plaza de Mayo).

Contents: 1 Conventions · 2 Mission flow · 3 Top-level state · 4 Operatives · 5 The informant · 6 Guards ·
7 Sight and detection · 8 Orders · 9 Action bar and interactables · 10 Rules in detail · 11 Events ·
12 Tuning table · 13 Level data · 14d Riachuelo · 14e The Plaza de Mayo · 18 Tests and tools · 19 Two languages ·
20 The launch screen and the questions

---

## 1. Conventions

- **Units.** The simulation is planar. Distances are "sim units": **32 units = 1 metre**. World position of a
  sim point `(x, y)` is `Vector3(x / 32, 0, y / 32)`. The map is 1280 × 800 units (40 × 25 m).
- **Angles** are radians in fields (`angle`) and degrees in mission data (`fov`, `post`, `scan`, route waits).
  0 = +x (east), π/2 = +y (south, towards the camera at the default yaw). Model yaw is `PI / 2 - angle`.
- **Time** is seconds of unpaused play (`sim.time`); the tactical pause stops the clock. `update(delta)` clamps
  `delta` to 0.06 s.
- **Determinism.** No random numbers anywhere. The same orders on the same ticks give the same mission; the
  scripted playthroughs step with `update(0.05)`.
- **Actors are plain Dictionaries** with String keys. Read any field; **write none** — change the game only
  through the methods in sections 2 and 8. After `restore()` / `load_checkpoint()` / `restart()` the actor
  dictionaries are *new objects*: never cache a reference across frames, look actors up again
  (`unit_by_id`, `guard_by_id`, or iterate `units` / `guards`).
- **Who calls what.** `three_d/main.gd` owns the `Simulation`, calls `update(dt)` once per frame and the flow
  methods. The HUD/controls call the order methods and the queries. `three_d/world.gd` drains `sim.events`
  once per frame and re-emits each entry through its signal `sim_event(event: Dictionary)` — connect to that
  rather than reading `sim.events` yourself (the list is emptied every frame).
- **Cost.** A quiet frame of `update` takes about 0.2 ms on a desktop core. One grid path search costs up to
  3.5 ms for a route across the whole map; patrols on their rounds never search, hunters search at most twice
  per `update` between them, a pursuing operative at most every 0.4 s, the informant at most every 0.35 s.
  A destination that cannot be reached at all (the locked yard, a roof) is refused without a search.

---

## 2. Mission flow

| Call | When | Effect |
|---|---|---|
| `Simulation.new(mission: Dictionary)` | once | Copies the mission data and calls `reset()`. |
| `reset()` | any time | Back to `phase = "briefing"`, paused, everything as authored. Clears the checkpoint. |
| `start()` | from briefing | `phase = "playing"`, **still paused** (command mode); stores the automatic "start" checkpoint. |
| `restart()` | any time | `reset()` then `start()`. |
| `toggle_pause()` | while playing | Tactical pause on/off. Orders given while paused start together on resume. |
| `update(delta: float)` | every frame | Advances the mission. Does nothing unless `phase == "playing"` and not `paused`. |
| `save_checkpoint() -> bool` | while playing | Manual checkpoint. Refused (false, reason in `message`) during an alarm or while any able guard's suspicion is above 0.15. |
| `can_save_checkpoint() -> bool` | any time | The same test without saving; use it to enable the button. |
| `has_checkpoint() -> bool` | any time | True from `start()` on. |
| `load_checkpoint() -> bool` | any time, also after `lost` | Restores the last checkpoint, sets `phase = "playing"`, `paused = true`, counts the load in `stats.checkpoints_loaded`. |
| `snapshot() -> Dictionary` / `restore(saved)` | any time | Deep copy of all mutable state / put it back exactly. `restore` empties `events`. |

`phase` is one of `"briefing"`, `"playing"`, `"won"`, `"lost"`. On `won` and `lost` the simulation pauses itself.
`lost_reason` then says who died and how, e.g. `"Rook was shot dead by a guard."`,
`"The informant was shot dead by a guard."`.

Automatic checkpoints: at `start()`, when the cell gate is unlocked (label `"gate"`) and when the informant is
freed (label `"informant"`). An automatic checkpoint that falls due during an alarm or while a guard is
suspicious is taken as soon as things are quiet again. `checkpoint` is
`{label: String, auto: bool, time: float, state: Dictionary}` (empty before `start()`).

---

## 3. Top-level state

| Field | Type | Meaning |
|---|---|---|
| `data` | Dictionary | The mission data (section 13). Read-only. |
| `phase`, `paused`, `time` | String, bool, float | See above. |
| `selected_id` | String | `"wren"` or `"rook"`. Orders act on the selected operative. |
| `units` | Array of Dictionary | The two operatives (section 4). |
| `guards` | Array of Dictionary | Every guard, living or not (section 6). **Grows** when reinforcements arrive and can shrink again on a checkpoint load: keep models and cones in step with it. |
| `prisoner` | Dictionary | The informant (section 5). |
| `door_open` | bool | Cell gate unlocked. While false the gate rectangle blocks movement and sight. |
| `fence_cut` | bool | The cuttable span of the wire has been cut (movement only; wire never blocks sight). |
| `radio_cut` | bool | Generator sabotaged: no reinforcements, shorter alarms. |
| `noise` | Array | Expanding rings to draw: `{x, y, radius, ttl, max_ttl, kind}`, kind `"pebble"` (radius 240, 2.4 s), `"shot"` (silenced pistol, radius 110, 1.2 s) or `"gunshot"` (revolver, radius 480 for the picture, 1.6 s). |
| `traps` | Array | Armed tripwires: `{id, x, y, by}`. A sprung or recovered trap leaves the list. |
| `alarm` | Dictionary | `{active: bool, time_left: float, duration: float, count: int, reason: String, x, y, radius: float, everyone: bool, reinforce_in: float, reinforce_pending: int}`. `x, y` is the last known position the hunters go to; `reason` is `"spotted"`, `"body"` or `"gunshot"`; `count` = alarms so far; `everyone` is true while an alarm that involved a gunshot is running. |
| `objectives` | Array | `{id, text, done, optional}` for `cell`, `informant`, `extract`, `radio` (optional). |
| `stats` | Dictionary | `{time, kills, binds, shots, alarms, bodies_found, distractions, checkpoints_loaded}`. `shots` counts operative rounds only. |
| `message` | String | The latest line for the notice strip (also carries the reason when an order is refused). |
| `lost_reason` | String | Set when `phase == "lost"`. |
| `events` | Array[Dictionary] | Section 11. Drained by the world each frame. |
| `checkpoint` | Dictionary | Section 2. |
| `par_time` | float | Seconds for the Swift badge (`parTime` in the data, 240). |
| `path_searches` | int | Profiling counter of grid searches; not part of the mission state. |

Lookups: `selected() -> Dictionary`, `unit_by_id(id) -> Dictionary`, `guard_by_id(id) -> Dictionary`
(each returns `{}` if unknown), `select(id)`, `max_suspicion() -> float` (highest suspicion of any able guard).

---

## 4. Operatives

`units[0]` is Wren (scout), `units[1]` is Rook (engineer).

| Field | Type | Meaning |
|---|---|---|
| `id`, `name`, `role`, `color` | String | `"wren"` / `"rook"`, display name, role, tint. |
| `x`, `y`, `angle` | float | Position (sim units) and facing (radians). |
| `stance` | String | `"sneak"` (crouched, the default) or `"walk"` (standing). Forced to `"walk"` while carrying. |
| `hp`, `alive` | int, bool | 100 at the start, 34 lost per hit. The mission is lost the moment anyone reaches 0. No healing. |
| `carrying` | String | Id of the guard on his shoulders, or `""`. |
| `ammo` | int | Rounds left (Wren 3, Rook 6). |
| `traps` | int | Tripwires in hand (Rook 1, Wren 0). `trap_kit` > 0 marks who can handle them. |
| `cooldown` | float | Seconds until the next pebble (Wren; 8 s after a throw). |
| `weapon_cooldown` | float | Seconds until the gun can be aimed again (pistol 0.8, revolver 1.0 after a shot). |
| `path` | Array of Vector2 | Way-points still to walk (draw the dashed route from this). |
| `order` | Dictionary | The current order, for previews: `{type, target?, x, y}`; `{}` when idle. `type` is one of `move`, `distract`, `takedown`, `shoot`, `pickup`, `drop`, `trap`, `trap_pickup`, `cut`, `sabotage`, `unlock`, `rescue`, `extract`. `target` is a guard id or trap id where it applies; `x, y` is where the order will be carried out (the target's position when it was given, the work spot, the pebble's landing point…). |
| `queued` | Dictionary | An order waiting behind a takedown in progress (same shape), else `{}`. |
| `action` | String | What the order is doing: `""` (nothing, or a plain move), otherwise the order type. |
| `acting` | bool | False while he is still walking to the job; true while the timed part runs (he stands still). |
| `action_time`, `action_total` | float | Progress of the timed part: draw the ring as `action_time / action_total` while `acting`. |
| `action_target` | Vector2 | Landing point of the last pebble. |
| `hidden` | bool | Crouched inside a bush rectangle (for the "in cover" look; a guard within 72 units can still see him). |
| `exposed` | bool | Counts as standing for detection right now: `stance == "walk"`, or carrying, or in the timed part of a takedown / pick-up / drop, or — Rook only — aiming the revolver or still recovering from its shot (`weapon_cooldown > 0`). |
| `pebble`, `tools` | bool | Kit flags: Wren throws pebbles; Rook has lock picks, wire cutters and the sabotage kit. |
| `melee` | Dictionary | `{label, time, lethal, time_stunned?}` — Wren `{"Knife", 0.5, true}`, Rook `{"Bind", 2.0, false, time_stunned 1.0}`. |
| `gun` | Dictionary | `{label, ammo, range, aim, recover, loud, noise?}` — Wren `{"Pistol", 3, 260, 0.5, 0.8, false, noise 110}`, Rook `{"Revolver", 6, 220, 0.5, 1.0, true}`. |

Speeds: walking 84 u/s (2.6 m/s), crouched 56 (1.75 m/s), carrying 50 (1.56 m/s). Body radius 9 units.

What to animate, by `action` (while `acting` unless noted):

| `action` | Timed part | Notes for the animator |
|---|---|---|
| `""` with a non-empty `path` | — | Moving. Crouch-walk or walk by `stance`; carry-walk when `carrying != ""`. |
| `takedown` | 0.5 s knife / 2.0 s bind (1.0 s on a stunned guard) | Starts within 30 units of the guard; the guard's `state` is `"held"` and his `held_by` is the operative for the whole time. Ends with event `takedown`. He is shown standing (`exposed`). |
| `shoot` | 0.5 s aim | He turns to the target while aiming; event `shot` when it fires. Rook stands up to aim and stays up for the 1.0 s recovery (`exposed`); Wren fires the muffled pistol from her crouch. |
| `pickup` | 0.7 s | Ends with event `pickup`; from then `carrying` is set and the body's position follows him. |
| `drop` | 0.3 s | Ends with event `drop {hidden}`. |
| `trap` | 1.5 s | Kneeling at his feet; event `trap_set`. |
| `trap_pickup` | 1.0 s | Event `trap_lifted`. |
| `cut` | 3.0 s | At the wire; event `fence_cut`. He stays crouched. |
| `sabotage` | 3.0 s | At the generator; event `radio_cut`. He stays crouched. |
| `unlock` | 1.4 s | At the lock spot; event `unlock`. He stays crouched. |
| `rescue` | 0.8 s | Within 34 units of the informant; event `rescued` (first time) or `escort` (taking over). |
| `extract` | none | Just the walk to his place on the landing stage. |
| pebble | instant | `action == "distract"` exists for a single tick only. Cue the throw from event `pebble` (or from `cooldown` jumping to 8, as the current animator does). |

---

## 5. The informant

`prisoner` = `{id: "asset", name, x, y, angle, freed, aboard, follow_id, hidden, path, hp, alive}`.

- Before he is freed he sits in the cell and no guard takes notice of him.
- `freed`: after a `rescue` he follows `follow_id` (the rescuing operative) at 72 u/s, re-pathing at most
  every 0.35 s, and stops 25 units behind (he starts again once the gap exceeds 34). A second operative can
  take over the escort with another `rescue` order.
- **He cannot crouch.** On the move, or standing in the open, he counts as standing: every guard sees him in
  both zones of a cone.
- `hidden`: **standing still inside a bush rectangle he keeps down** and is exactly as hard to see as a
  crouched operative in a bush — not at all, unless a guard has him in his cone within 72 units. When his
  escort stops inside a bush he closes up to 12 units, so both fit. `hidden` is true only while his `path`
  is empty and he is inside a bush; show him kneeling (the character builder already blends a "hidden" pose
  from this field). The bushes are therefore the stepping stones of any quiet escort.
- `aboard`: the first time he is inside the extraction ring he gets into the boat: `aboard = true`,
  `follow_id = ""`, event `boarded`. From then on he is not a target, cannot be led away again and counts as
  "at the boat" for the win. (Show him sitting low in the boat.)
- He has 100 health like the operatives and can be shot during an alarm.

---

## 6. Guards

Every entry of `guards` has all of these fields:

| Field | Type | Meaning |
|---|---|---|
| `id` | String | `g1`…`g5`, `tower`, `sentry`, `sergeant`, reinforcements `r1`…`r3`. |
| `kind` | String | `"patrol"`, `"tower"`, `"sentry"`, `"sergeant"`, `"reinforcement"`. |
| `state` (`mode` is a copy, for old code) | String | See the state table below. |
| `x`, `y`, `angle` | float | Position and facing. He turns at a finite rate (3.2 rad/s, 5.5 when hunting), so a cone always sweeps. |
| `elevation` | float | Metres above the ground (tower sentry 2.6, everyone else 0). Purely for the visuals, except that `> 0` means "sees over everything but buildings, cannot be reached, stays where he falls". |
| `range`, `near` | float | Current length of the sight cone and of its near zone, in sim units. `range = base_range + 60` while he is on edge (below). |
| `fov`, `base_fov`, `base_range` | float | Current cone width in degrees, and the normal width and length. `fov = base_fov + 40` while he is on edge. |
| `suspicion` | float 0..1 | Detection meter. 1.0 = he has spotted someone. |
| `seen_id` | String | Who he is looking at this tick (`"wren"`, `"rook"`, `"asset"`) or `""`. |
| `spotted` | bool | Latched at suspicion 1.0, released when it drains below 0.5. |
| `body_alert` | float 0..1 | Fills while he looks at a body lying in the open. |
| `jumpy` | float | Seconds of edginess left after waking from a stun. |
| `route`, `route_index` | Array, int | Patrol way-points `[x, y]` or `[x, y, wait seconds, facing degrees]`; index of the point he is walking to. |
| `path` | Array of Vector2 | Way-points of the walk in progress. |
| `speed` | float | Walking speed (u/s). Hunting runs at 1.7 ×. |
| `has_post`, `post_x`, `post_y`, `post_angle` | — | A posted sentry's place and facing. |
| `has_return`, `return_x`, `return_y` | — | For a patrol drawn off by a noise: the spot on his round he will walk back to. |
| `has_scan`, `scan_from`, `scan_to`, `scan_speed`, `scan_pause`, `scan_dir`, `scan_wait` | — | The tower sentry's sweep (radians, rad/s, seconds). |
| `react` | float | Seconds of "what was that?" before he sets off (after a lure or an alarm). |
| `search_time`, `search_total` | float | Countdown while he looks around (states `search`, and the look-around part of `hunt`). |
| `goal` | Vector2 | Where he is investigating or hunting to. |
| `target_id` | String | Who he is aiming at (`""` if nobody). |
| `aim_time`, `aim_total` | float | Aim progress, 0 → 0.7 s. He fires when it is full and `fire_cooldown` is 0. |
| `fire_cooldown` | float | Seconds until his next shot (1.1 after each). |
| `fire_flash` | float | 0.14 s countdown set by each shot: muzzle flash. |
| `stun_time` | float | Seconds until a stunned guard wakes (20 → 0). |
| `held_by` | String | Operative taking him down (`state == "held"`). |
| `carried_by` | String | Operative carrying him, or `""`. While carried his `x, y` are the carrier's. |
| `hidden` | bool | A body nobody can find: lying in a bush, or the tower sentry in his cabin. |
| `found` | bool | A body that has already raised its alarm. |
| `static` | bool | Never moves (tower sentry). |
| `alarm_hold` | bool | Does not leave his post in an alarm; turns to face the trouble instead (gate sentry). |
| `lure_immune` | bool | Ignores pebbles (sergeant, tower sentry). The muffled pistol still draws the sergeant. |
| `melee_immune`, `trap_immune` | bool | Tower sentry. |
| `responder` | bool | A reinforcement during the alarm he was sent out for. |

### Guard states

| `state` | Meaning | Looks like |
|---|---|---|
| `patrol` | Walking his route; pauses at way-points that carry a wait, facing the given way. | Relaxed walk, rifle slung. |
| `post` | At his post, facing `post_angle` (the tower sentry sweeps between his two bearings). | Standing guard. |
| `investigate` | Heard a pebble or the muffled pistol: turns to it (`react` > 0), then walks to the spot (`goal`). | "?" — alert walk. |
| `search` | At the spot (or just woken from a stun): looks left and right for `search_total` seconds (3.2 s after a noise, 6 s after waking). | Peering about. |
| `return` | Walking back after a noise: a sentry to his post, a patrol to the spot on his round he left (`return_x, return_y`), from where he carries on as `patrol`. | Relaxed walk. |
| `alert` | An alarm is on but too far away to run to: carries on with patrol or post, on edge, will shoot. | Weapon ready, tense. |
| `hunt` | Called out by the alarm. In order: turning to the trouble (`react` > 0); running to `alarm.x, alarm.y` (`path` not empty, 1.7 × speed); aiming and firing (`target_id != ""`, see `aim_time`, `fire_flash`); looking around / walking a search ring (`path` empty or short hops). The tower sentry and the gate sentry stay put and face the trouble. | Weapon up, running; firing stance when `target_id != ""`. |
| `held` | Being knifed or tied up. Frozen, sees nothing. | Struggling in the operative's grip. |
| `stunned` | Tripped the wire; out for 20 s (`stun_time`). A body: can be carried, bound in 1 s, knifed. | Sprawled, dazed. |
| `bound` | Tied and gagged. Permanent. A body. | Lying trussed. |
| `dead` | Knifed or shot. A body. | Lying still. |

A guard is **on edge** in the states `hunt` and `alert`, and for `jumpy` seconds after waking from a stun: his
cone is 40° wider and 60 units longer (the fields `fov` and `range` change, so a cone drawn from them is
truthful), his meter fills twice as fast, and he is certain at once of anyone he sees standing.

Constants for these groups: `BODY_STATES = ["dead", "bound", "stunned"]` (can be carried, can be found),
`DOWN_STATES = BODY_STATES + ["held"]` (sees nothing, draws no cone).

---

## 7. Sight and detection

A guard notices a target (an operative, or the freed informant who is not yet aboard) when it is inside his
cone — within `range`, within `fov / 2` of `angle` — and the line of sight is clear:

| Where | Standing / walking / carrying / mid-takedown / the informant on his feet | Crouched (or the informant keeping still in a bush) |
|---|---|---|
| **Near zone** (distance ≤ `near`) | seen, meter fills in 0.5 s | seen, fills in 0.9 s — unless he is in a bush and more than 72 units away |
| **Far zone** (`near` < distance ≤ `range`) | seen, fills in 1.2 s (just outside the near zone) to 2.2 s (at the tip) | **not seen at all** |

- The meter drains to nothing in 2.0 s when he sees nobody. At 1.0 he has spotted the squad: event `spotted`,
  then the alarm (section 10.6). There is no instant failure any more.
- A guard on edge (section 6): the crouched times are halved, and a standing target is recognised in the
  same tick, in either zone.
- **Line of sight** is blocked by buildings, the compound walls, crates, sandbags, the truck and the closed
  cell gate. Water, the wire fence, the tree line, the tower's legs and bushes do not block it, nor does an
  obstacle marked `see_through` (a lamp post, a scaffold, a buffer stop: solid to walk into, but it hides
  nobody).
- **The tower sentry** (`elevation > 0`) is blocked only by obstacles of kind `"building"` (barracks, radio
  post, supply depot). He looks down into the cell compound.
- The same lines are used for shooting, in both directions.
- **Bodies**: a non-hidden, non-carried body anywhere in a cone (either zone) with clear sight fills
  `body_alert` in 1.0 s (0.5 s for a guard on edge) → event `body_found` → alarm at the body. Each body does
  this once.

Queries (all read-only, cheap enough to call per frame for a handful of points):

| Method | Returns |
|---|---|
| `line_of_sight(from: Vector2, to: Vector2) -> bool` | Ground-level sight between two points. |
| `sight_endpoint(from, to) -> Vector2` | Where a ground-level ray from `from` towards `to` stops. |
| `sight_clear_for(guard: Dictionary, to: Vector2) -> bool` | Sight from that guard (the tower sentry sees over walls). |
| `sight_endpoint_for(guard, to) -> Vector2` | Where that guard's ray stops. **Use this to draw his cone.** |
| `visibility(guard, target: Dictionary) -> int` | 0 not seen, 1 seen in the far zone, 2 seen in the near zone — for a real actor, stance and all. 0 for a guard who is down. |
| `zone_at(guard, point: Vector2, exposed: bool) -> int` | The same for a hypothetical person at `point`, standing (`exposed = true`) or crouched. 0 for a guard who is down. |
| `threats_at(point, exposed) -> Array[String]` | Ids of the guards who would see that person right now (command-mode preview of a destination). |
| `is_exposed(actor) -> bool` | Whether the actor counts as standing. |
| `in_bush(point) -> bool` | Inside a bush rectangle. |
| `is_blocked(point, margin = 9.0) -> bool` | Not walkable (obstacle, wire, tree line, water, map edge). |
| `find_path(from, to) -> Array` | Way-points (Vector2) or `[]`. A* on the 32-unit grid with string pulling; do not call it per frame. |
| `get_obstacles() -> Array`, `get_barriers() -> Array` | Solid scenery currently in force (the gate while closed) / movement-only barriers (wire minus the cut span, tower legs, tree line). |
| `position_of(actor) -> Vector2`, `rect_of(item) -> Rect2` | Static helpers. |

Drawing a cone truthfully: for each ray across `fov` around `angle`, end = `sight_endpoint_for(guard, origin +
dir * range)`; the near zone is the part of each ray within `near` of the origin (stronger tint: seen in any
stance), the rest is the far zone (paler: seen only standing). Skip guards whose `state` is in `DOWN_STATES`.
`world.gd` does exactly this already, crudely.

---

## 8. Orders

All order methods act on the **selected** operative, return `true` if the order was accepted and `false`
otherwise (with the reason in `message`; the operative's current order is then left alone). They are accepted
only while `phase == "playing"`, paused or not. A new order replaces the current one — except during the timed
part of a takedown, which cannot be abandoned: the new order is stored in `queued` and starts when it ends.
Each operative holds one order; give both of them orders during a pause and they start on the same tick.

An operative carrying a body accepts only `move`, `drop` and `extract`.

| Method | Who | What happens |
|---|---|---|
| `move_to(point: Vector2)` | both | Walk there. A point he cannot stand on or reach (a roof, the water, past the wire or the edge of the map) is walked back along the line toward him to the last spot he can reach, and he goes there ("as close as he can get"). Refused only when that spot is where he already stands. |
| `toggle_stance()` | both | Crouch ↔ stand, at once (not an order; not while carrying). |
| `distract(point: Vector2)` | Wren | Pebble to a point within 240 units, on open ground, cooldown 8 s. Aimed farther it lands on the 240 ring; aimed at something solid or off the map it lands at the last open spot along the throw. Thrown at once (on resume if paused); she stops to throw. Guards within 240 units of where it lands — except the sergeant and the tower sentry, and not during an alarm — go and look. |
| `order_takedown(guard_id: String)` | both | Go after the guard, re-pathing as he moves (at most every 0.4 s), and take him down within 30 units: Wren's knife 0.5 s (dead), Rook's bind 2.0 s (bound; 1.0 s if he is stunned). Refused for the tower sentry and for guards already dead or bound. |
| `order_shoot(guard_id: String)` | both | Aim 0.5 s and fire, if within range (pistol 260, revolver 220) with a clear line; otherwise he first walks towards the target until he has the shot. Refused with no ammunition, and — when there is nowhere to walk to (the tower) — when out of range or without a line. |
| `order_pickup(guard_id: String)` | both | Walk to a dead, bound or stunned guard and lift him (0.7 s, within 26 units). Not the tower sentry, and not a body hidden in a bush (hidden stays hidden; it is not listed in `interactables()` either). |
| `drop_body()` | both | Put the body down here (0.3 s). |
| `order_drop(point: Vector2)` | both | Carry it to `point`, then put it down — into a bush to hide it. |
| `place_trap()` | Rook | Set the tripwire at his feet (1.5 s). |
| `order_trap_pickup(trap_id := "")` | Rook | Recover an unsprung tripwire (1.0 s); with no id, the nearest. |
| `order_cut_fence()` | Rook | Go to the cuttable span (whichever side is nearer by path) and cut it (3.0 s). |
| `order_sabotage()` | Rook | Go to the generator and kill it (3.0 s). |
| `order_unlock()` | Rook | Go to the lock spot in front of the cell gate and pick it (1.4 s). |
| `order_rescue()` | both | Once the gate is open: go to the informant and free him (0.8 s), or take over the escort. |
| `order_extract()` | both | Walk to his own place on the landing stage. |
| `cancel_order()` | both | Drop the current order and stop (a takedown in progress is finished first; its queued order is dropped). |
| `interact()` | both | Old context button: unlock (Rook only) → rescue → extract, whichever is next. |
| `perform(action_id: String, target = null)` | both | One entry point for the HUD: `action_id` is an `id` from `available_actions()` or an `order` from `interactables()`; `target` is a guard id / trap id (String), a point (Vector2) or nothing. Also accepts `"move"` (Vector2), `"stance"`, `"cancel"`, `"interact"`. |

---

## 9. Action bar and interactables

### `available_actions(unit_id := "") -> Array[Dictionary]`

The bar of one operative (the selected one by default), in display order. Every entry has:

`{id, label, kind, enabled, reason, count, cooldown, cooldown_total, range, context, active}`

- `kind`: `"instant"` (tap the button, `perform(id)`), `"target_guard"` (pick a guard, `perform(id, guard_id)`),
  `"target_point"` (pick a point, `perform(id, Vector2)`), `"context"` (normally triggered by tapping the world
  thing — see `interactables()` — but `perform(id)` works too).
- `enabled` / `reason`: `reason` is `""` exactly when enabled, otherwise a short sentence to show.
- `count`: rounds or tripwires left, −1 where it does not apply.
- `cooldown`, `cooldown_total`: seconds left and full length (pebble 8 s; gun recovery).
- `range`: sim units for `shoot` and `distract` (draw the range ring), else 0.
- `active`: this is the operative's current order.

| Operative | Entries |
|---|---|
| Wren | `stance` ("Stand"/"Crouch": what the tap will do), `takedown` ("Knife"), `shoot` ("Pistol", count 3), `distract` ("Pebble"), `pickup` ("Carry") or — while carrying — `drop` ("Drop body"), `rescue` ("Rescue"/"Escort"), `extract` ("To the boat") |
| Rook | `stance`, `takedown` ("Bind"), `shoot` ("Revolver", count 6), `trap` ("Tripwire", count 1) or — when it is laid — `trap_pickup` ("Recover trap"), `pickup` / `drop`, `unlock`, `cut` ("Cut wire"), `sabotage`, `rescue`, `extract` |

A phone bar can show the non-context entries as buttons and keep one context button, or none: every context
action is also an interactable.

### `interactables() -> Array[Dictionary]`

World things the selected operative can be sent to right now:

`{id, type, label, x, y, radius, order, target, enabled, reason}` → call `perform(order, target)`.

| `type` | Listed while | Position, tap radius | `order`, `target` |
|---|---|---|---|
| `gate` | gate locked | centre of the gate (1088, 560), 40 | `unlock`, null (Rook only: disabled with a reason for Wren) |
| `informant` | gate open, he is not aboard and not already following this operative | his position, 26 | `rescue`, null |
| `fence` | wire not cut | centre of the cuttable span (990.5, 86.5), 44 | `cut`, null (Rook) |
| `radio` | generator running | (840, 134), 30 | `sabotage`, null (Rook) |
| `trap` | a tripwire is laid | its position, 22 | `trap_pickup`, trap id (Rook) |
| `body` | per dead / bound / stunned guard on the ground | his position, 24 | `pickup`, guard id |
| `bush` | the operative is carrying | centre of each bush, half its smaller side | `drop`, the centre (Vector2): carries the body in and hides it |
| `extraction` | the informant is free | the ring's centre and radius | `extract`, null |

Living guards are not listed: tapping one maps to `takedown` or `shoot` as the HUD decides.

---

## 10. Rules in detail

### 10.1 Takedowns
- The operative runs the guard down (he is faster crouched than a guard walks) and the timed part starts as
  soon as he is within 30 units with nothing solid between. From that tick the guard is `held`.
- **Come from outside his cone.** A guard who has his attacker in his cone at the moment he is grabbed gets a
  shout off: event `spotted` and an alarm, whatever his suspicion was. The takedown still completes. (Crouched
  in the far zone you are invisible, but the last 30 units are always the near zone.)
- **During an alarm that shout is a shot.** A guard who is already on `hunt` or `alert` and has his attacker
  in his cone fires as he is seized: 34 health, events `spotted`, `guard_shot {hit: true}`, `hurt`. The
  takedown then completes — unless that bullet was the attacker's last, in which case the mission is lost
  and the guard is not even held. From behind or the side it costs nothing: one operative can hold a
  hunter's attention while the other takes him.
- During the timed part the operative counts as standing, so other guards can see it in their far zones.
- Works on hunting and stunned guards too. Not on the tower sentry.
- `stats.kills` / `stats.binds` count the results; event `takedown {by, target, lethal}`.

### 10.2 Bodies
- Dead, bound and stunned guards lie where they fell (inside a bush: hidden at once).
- Carrying: 50 u/s, standing, no other abilities. A body put down inside a bush rectangle is `hidden` for
  good; anywhere else it can be found (section 7).
- A stunned guard who is found is woken (event `woke {found_by}`) and joins the alarm. One who wakes while
  being carried breaks free.
- The tower sentry's body stays in the cabin, hidden.

### 10.3 Guns
- **Pistol** (Wren, 3 rounds): kills. Guards within 110 units **of Wren** — the sergeant included, the tower
  sentry not — go and investigate where she fired from (event `heard`). No alarm. She can fire it crouched
  without giving herself away.
- **Revolver** (Rook, 6 rounds): kills, and raises the alarm at once, heard everywhere (`alarm.everyone`).
  **It gives him away**: he counts as standing while he aims and until he has recovered from the shot
  (1.0 s), so every guard on edge who has him in his cone knows him at once and starts to aim. Fired from a
  crouch at a single guard it wins the duel (0.5 s against 0.7 s); a second guard in view gets his shot in
  before Rook can fire again.
- A shot hits if, when it goes off, the target is within range + 20 and the line is clear.
- Both can hit the tower sentry from anywhere with a line to him that crosses no building.

### 10.4 Pebble
- Lands where aimed; every free, mobile guard within 240 units of the landing point who is not `lure_immune`
  turns (0.3 s, staggered 0.12 s apiece), walks there, searches 3.2 s and goes back: a sentry to his post, a
  patrol **to the spot on his round where he was when he heard it**, and on from there. (A second noise while
  he is out does not change that spot.) His round is simply delayed by the excursion.
- Guards in `hunt` or `alert` ignore it.

### 10.5 Rook's tools
- **Lock**: 1.4 s at the lock spot `(door.interactX, door.interactY)`; opens movement and sight through the gate.
- **Wire**: the fence blocks movement along its whole length; the cut removes the one cuttable span.
- **Tripwire**: sprung by the first able guard who comes within 18 units of it (not the tower sentry):
  `stunned` for 20 s, event `trap_sprung`. If nobody deals with him he wakes, searches on edge for 6 s
  (no alarm by itself) and resumes. The wire is used up when sprung.
- **Generator**: `radio_cut = true`, objective `radio` done; from then on alarms last 12 s instead of 20 and
  bring no reinforcements (men already on their way are called off too).

### 10.6 Alarm
- **Starts** when a guard's meter reaches 1.0 or he is grabbed from the front (`reason "spotted"`), when a
  body is found (`"body"`), or when the revolver fires (`"gunshot"`) while at least one guard is still on his feet
  (with every guard down nobody is left to hear the shot). Events `alarm_start {reason, x, y, count}`.
- **Who comes.** Guards within `alarm.radius` (400 units, 12.5 m) of the trouble hunt; after a gunshot
  everybody hunts; reinforcements always hunt. Guards farther away go on `alert` and keep to their duty; an
  alert guard joins the hunt if the last known position moves within 400 units of him — which it does when he
  sees someone himself.
- **Last known position** `alarm.x, alarm.y`: follows the target while any guard has him confirmed in sight;
  otherwise stays where he was last seen. Hunters run there (each to his own spot a little apart), look around
  for 3 s, then walk a ring of 120 units around it.
- **Shooting.** A guard on `hunt` who has someone confirmed in sight (meter at 1.0) stops, aims 0.7 s and
  fires, then every 1.1 s. A shot hits if the line is clear and the target within his range + 20 when it goes
  off; each hit is 34 health (events `guard_shot {hit}`, `hurt`). After 0.4 s of aiming he is committed: if
  he loses sight of the target in the next 0.4 s he fires anyway, and hits unless something solid has come
  between them. Dropping to a crouch in his far zone within those first 0.4 s saves the bullet; later it
  costs one and no more.
- **What that means for the player.** Standing, walking, carrying and the informant on his feet are shot at
  0.7 s after an alerted guard sees them, at up to 250 units (patrols). Crouched you are still invisible in
  far zones, and seen in near zones in half the usual time. So: drop, break the line, and move away from the
  last known position; or fight from a crouch, one guard at a time.
- **Clock.** `alarm.time_left` is held at `alarm.duration` while anyone is confirmed in sight and runs down
  otherwise. At 0: event `alarm_end`, everyone goes back to his round or post.
- **Reinforcements.** 4 s into the first alarm two guards (`r1`, `r2`) come out of the barracks door and hunt;
  a later alarm brings one more (`r3`); never more than three. Afterwards they walk their own rounds for the
  rest of the mission. Event `reinforcements {ids, x, y}`.
- No checkpoints during an alarm.

### 10.7 Winning, losing, badges
- **Win**: gate unlocked, informant freed and aboard (or standing in the ring), both operatives inside the
  extraction ring (66 units around (240, 704)). Event `won`.
- **Lose**: an operative or the informant reaches 0 health. Events `death`, `lost`.
- `result_badges() -> Array[Dictionary]`: five entries `{id, label, text, earned}` —
  `ghost` (no alarm: `stats.alarms == 0`), `clean_hands` (`stats.kills == 0`), `not_a_shot`
  (`stats.shots == 0`), `saboteur` (`radio_cut`), `swift` (`time <= par_time`, 4:00).
  `badge_earned(id) -> bool` looks one up. Meaningful once `phase == "won"`. All five can be earned in one
  run (the clean-hands solution does).

---

## 11. Events

`events` is an `Array[Dictionary]`; every entry has `type: String` and `time: float` (mission seconds).
At most 256 are kept if nobody drains the list. `restore()` clears it.

| `type` | Payload | When |
|---|---|---|
| `checkpoint` | `action` (`"save"` / `"load"`), `label`, `auto` | A checkpoint is stored or loaded. |
| `pebble` | `by`, `x`, `y` | Wren's pebble lands (it is instant). |
| `heard` | `guards` (Array of ids), `x`, `y`, `noise` (`"pebble"` / `"shot"`) | Guards set off to investigate a noise. Not emitted if nobody heard. |
| `takedown` | `by`, `target`, `lethal` | A knife kill or a bind is complete. |
| `shot` | `by`, `x`, `y`, `tx`, `ty`, `loud`, `hit_id` (`""` on a miss) | An operative fires. |
| `pickup` | `by`, `body` | A body is lifted. |
| `drop` | `by`, `body`, `hidden` | A body is put down; `hidden` if in a bush. |
| `trap_set` | `by`, `trap`, `x`, `y` | Tripwire armed. |
| `trap_lifted` | `by`, `trap` | Tripwire recovered. |
| `trap_sprung` | `guard`, `trap`, `x`, `y` | A guard trips it. |
| `woke` | `guard`, `found_by` (`""` if on his own) | A stunned guard comes round. |
| `fence_cut` | `by` | The wire parts. |
| `radio_cut` | `by` | The generator dies. |
| `unlock` | `by` | The cell gate opens. |
| `rescued` | `by` | The informant is freed. |
| `escort` | `by` | Another operative takes over the escort. |
| `boarded` | `id` (`"asset"`) | The informant gets into the boat. |
| `spotted` | `guard`, `target` | A guard's meter reaches 1.0 (or he is grabbed from the front). Fires again for the same guard only after he has lost the target for a while. |
| `body_found` | `guard`, `body`, `x`, `y` | A guard recognises a body. |
| `alarm_start` | `reason`, `x`, `y`, `count` | The alarm goes up. |
| `alarm_end` | — | It dies down. |
| `reinforcements` | `ids`, `x`, `y` (the barracks door) | Extra guards appear in `guards`. |
| `guard_shot` | `by`, `target`, `hit`, `x`, `y`, `tx`, `ty` | A guard fires (also the shot of a guard seized from the front during an alarm). |
| `hurt` | `id`, `hp`, `by` | A shot lands on an operative or the informant. |
| `death` | `id`, `by` | He is killed. |
| `planted` | `by`, `site`, `kind` (`"limpet"` / `"charge"`), `objective`, `left` (of that objective), `x`, `y` | A charge is set (missions with `charges`). |
| `chat` / `chat_end` | `by`, `guard` (and `x`, `y`, `left`) | A local stops a guard for a smoke / the smoke is over. |
| `cover_blown` | `id` | A guard has marked a local: his cover is gone for good. |
| `uniform` | `by`, `guard`, `x`, `y` | An operative has put on the uniform of a guard who is down. |
| `objective` | `id` | Setting a charge completed an objective (the last limpet, the last charge). |
| `rigged` | `by`, `passage`, `x`, `y` (the anchor) | A rope is fixed: the passage is open to everyone. |
| `talk` / `calmed` | `by`, `guard` (and `x`, `y`) | An operative reaches a civilian and starts talking / the civilian is talked round (state `calm`). |
| `tracks` | `guard`, `by` (whose prints), `x`, `y` (where the trail leads), `first` | A guard has found footprints in the snow and follows them. |
| `fuse_lit` | `seconds`, `x`, `y` | The last charge of the fuse's objective is set: the fuses burn. |
| `blast` | `x`, `y` | The fuses have burned down and the charges go off. |
| `won` | `time` | Mission complete. |
| `lost` | `reason` | Mission failed. |

Not events (poll the state instead): stance changes, an order being given, a guard's suspicion rising
(`suspicion`, `seen_id`), a guard starting to aim (`target_id`, `aim_time`), the alarm clock
(`alarm.time_left`), the informant ducking into cover (`prisoner.hidden`), a lured guard turning for home
(`state == "return"`).

---

## 12. Tuning table

Constants in `simulation.gd` (sim units, seconds):

| Constant | Value | |
|---|---|---|
| `WALK_SPEED` / `SNEAK_SPEED` / `CARRY_SPEED` / `PRISONER_SPEED` | 84 / 56 / 50 / 72 | u/s |
| `FOLLOW_DISTANCE` / `FOLLOW_DISTANCE_COVER` / `FOLLOW_SLACK` / `FOLLOW_REPATH` | 25 / 12 / 9 / 0.35 | the informant behind his escort: in the open / when the escort is in a bush / extra gap before he moves again / seconds between his path searches |
| `BODY_RADIUS` | 9 | collision radius of everyone |
| `GUARD_TURN_RATE` / `HUNT_TURN_RATE` | 3.2 / 5.5 | rad/s |
| `FILL_NEAR_STAND` / `FILL_NEAR_CROUCH` | 0.5 / 0.9 | s to full suspicion in the near zone |
| `FILL_FAR_MIN` … `FILL_FAR_MAX` | 1.2 … 2.2 | s, far zone, from its inner edge to the tip |
| `SUSPICION_DRAIN` | 2.0 | s from full to empty |
| `BUSH_REVEAL` | 72 | a bush hides a croucher beyond this |
| `BODY_ALERT_TIME` | 1.0 | s of looking at a body |
| `ALERT_FOV_BONUS` / `ALERT_RANGE_BONUS` / `ALERT_FILL_SCALE` | 40° / 60 / 2× | guards on edge (and instant recognition of standing targets) |
| `MELEE_RANGE` | 30 | |
| `PICKUP_RANGE` / `PICKUP_TIME` / `DROP_TIME` | 26 / 0.7 / 0.3 | |
| `UNLOCK_TIME` / `RESCUE_TIME` / `RESCUE_RANGE` | 1.4 / 0.8 / 34 | |
| `CUT_TIME` / `SABOTAGE_TIME` | 3.0 / 3.0 | overridable in the data |
| `DISTRACT_RANGE` / `DISTRACT_RADIUS` / `DISTRACT_COOLDOWN` | 240 / 240 / 8 | throw range, hearing radius, cooldown |
| `SEARCH_TIME` | 3.2 | after walking to a noise |
| `TRAP_SET_TIME` / `TRAP_LIFT_TIME` / `TRAP_RADIUS` | 1.5 / 1.0 / 18 | |
| `STUN_TIME` / `WAKE_SEARCH_TIME` | 20 / 6 | |
| `ALARM_TIME` / `ALARM_TIME_RADIO_CUT` / `ALARM_RADIUS` | 20 / 12 / 400 | overridable in the data |
| `HUNT_SPEED_SCALE` | 1.7 | |
| `HUNT_LOOK_TIME` / `HUNT_SEARCH_RADIUS` | 3.0 / 120 | |
| `HUNT_REPATH_TIME` / `HUNT_SEARCHES_PER_UPDATE` / `PURSUIT_REPATH` | 0.6 / 2 / 0.4 | minimum seconds between path searches of one hunter / hunters allowed to search in one update / minimum seconds for a pursuing operative |
| `GUARD_AIM_TIME` / `GUARD_FIRE_INTERVAL` / `GUARD_DAMAGE` | 0.7 / 1.1 / 34 | |
| `AIM_COMMIT` / `AIM_GRACE` | 0.4 / 0.4 | |
| `SHOT_SLACK` | 20 | extra reach of a shot already aimed |
| `MAX_HEALTH` | 100 | |
| `CHECKPOINT_SUSPICION` | 0.15 | manual saves refused above this |

In the level data: operative kits (`melee`, `gun`, `traps`), each guard's `speed`, `range`, `near`, `fov`,
routes and waits, the tower's `scan`, `fence.time`, `radio.time`, `alarm {duration, durationRadioCut, radius}`,
`reinforcements {delay, first, later, cap, guard, spawn, routes}`, `parTime`.

Cone sizes in this level (on edge: + 60 range, + 40°):

| Guard | `range` | `near` | `fov` | speed |
|---|---|---|---|---|
| patrols g1–g5, reinforcements | 190 (5.9 m) | 96 (3.0 m) | 66° (g2, g4: 70°; g5: 68°) | 32–37 (36 for reinforcements) |
| gate sentry | 220 (6.9 m) | 110 (3.4 m) | 70° | 34 |
| sergeant | 230 (7.2 m) | 130 (4.1 m) | 80° | 40 |
| tower sentry | 400 (12.5 m) | 150 (4.7 m) | 28°, sweeping 9°/s | — |

---

## 13. Level data (`godot/data/*.json`)

Unchanged keys: `id`, `title`, `subtitle`, `width`, `height`, `cellSize`, `waterBoundary`, `extraction {x, y,
radius}`, `prisoner {id, name, x, y}`, `door {id, x, y, w, h, interactX, interactY}`, `obstacles` (kinds
`water`, `building`, `wall`, `crates`, `sandbags`, `truck`), `bushes`. **No map geometry was moved and no bush
was added.**

New or extended:

- `parTime`: 240.
- `units[]`: plus `pebble`, `tools`, `traps`, `melee {label, time, lethal, time_stunned?}`,
  `gun {label, ammo, range, aim, recover, loud, noise?}`.
- `guards[]`: `id`, `kind`, `route` (points `[x, y]` or `[x, y, wait_seconds, facing_degrees]`; a guard walks
  them in order and loops), `speed`, `range`, `near`, `fov`; for posted men `post [x, y, facing_degrees]`;
  optional `scan {from, to, speed (deg/s), pause}`, `elevation` (m), and the flags `static`, `alarm_hold`,
  `lure_immune`, `melee_immune`, `trap_immune`. Missing values default to: kind `patrol`, speed 34,
  range 190, near `min(80, 0.45 × range)`, fov 66.
- `barriers[]`: rectangles that stop feet but not eyes: `{id, kind, x, y, w, h, cuttable?}`. Kinds here:
  `fence` (three pieces; the middle one, `fence-span`, is `cuttable`), `tower` (the legs of the watchtower),
  `trees` (the tree line along the northern edge).
- `fence {span, interact: [[x, y], [x, y]], time}`: the cuttable barrier's id and the two spots (outside and
  inside) Rook can cut from.
- `radio {x, y, time}`: where Rook stands to sabotage the generator.
- `alarm {duration, durationRadioCut, radius}`.
- `reinforcements {spawn: [[x, y]…], delay, first, later, cap, guard {speed, range, near, fov}, routes: [route…]}`:
  reinforcement *n* appears at `spawn[n]` and afterwards walks `routes[n]`.
- `objectives[]`: `{id, text, optional?}`.

### Keys a level may use: kits, charges and more (first written for the engine's harbour level)

Every one is optional.

- `progressKey`, `theme` (in Hora Cero `"boca"` or `"plaza"`: world.gd builds no other), `worldName`, `camera {min, max,
  start, zoom, zoomMax}` (metres).
- Without `door` and `prisoner` there is nobody to rescue: `has_prisoner` is false and the extraction opens
  once every charge is set (`ready_to_leave()`).
- `charges[]`: `{id, objective, by: [unit ids], kind, label, x, y (where to stand), tx, ty (where the charge
  goes), time, radius, order, done ("{left}" is replaced), finished, refuse}`. Order `plant` (target: a site id,
  or "" for the nearest one this operative carries). Queries: `charge_sites()`, `charge_site(id)`,
  `can_plant(unit, site)`, `sites_left(objective)`, `objective_progress(objective) -> [done, total]`;
  state `planted {site id: unit id}` (in snapshots and checkpoints).
- `radio`: plus `by` (who may do it; default whoever has `tools`), `label`, `thing`, `icon`, the messages
  `refuse`, `already`, `unreachable`, `order`, `done`, `deadReason`, `badge`, and `sound` (the cue played).
- `guards[].powered {range, near, fov}`: what is left of this guard's sight once the power is cut (the
  searchlight crew); the guard gets `dark = true`. `guards[].look`: which baked figure dresses him
  (`sailor0..2`, `bootsmann`, `ot0..1`; the HUD names him SAILOR, BOATSWAIN or OT GUARD after it). Riachuelo's
  people: `guardia0..2` (the Guardia de Emergencia: greatcoat, peaked cap, G.E. armband, carbine and baton),
  `guardia_sgt` (the sergeant: cape, whistle, pistol; a guard of kind `sergeant` gets it from any `guardia` look),
  `informer` (no gun, his evening paper under his arm), `vecino0..5` and `vecina0..3` (the barrio's men and women, no
  gun; `vecino3..5` and `vecina2..3` are the first figures in other colours). `prisoner.look` `pasajero`: the passenger
  in his borrowed overcoat and spectacles.
- Any unit, guard (civilians too) or the `prisoner`: `look` `"art:<slot>"` dresses him in the art pack's drawing or
  model for that slot (`godot/art_pack/manifest.json`, docs/ART_PACK.md): a paper cut-out on the figure's own rig
  (operative.gd, cutout.gd; a rigged person's model moved on its own skeleton, rig_person.gd; a one-piece creature's
  moved whole, creature_body.gd), or the neutral stand-in with its LICENSED ART PENDING plate while the slot has no file. A
  `look` that is a path to a PNG (`"art_pack/x/y.png"`, `"res://..."`) or a `.glb`/`.gltf` model does the same without a
  slot. `look_height` (metres) sets that actor's height (else the slot's `height_m`). Nothing in the rules changes.
- `ink: true` (top level): the operation is always drawn in comic ink (scripts/three_d/ink.gd); `preview {ink: true}`:
  only in that operation's preview build. Otherwise the player's choice (Settings, the progress file's
  `settings/ink`), off by default; the export feature `comic_ink` or `HORACERO_INK=1` (tools; `0` forces it off) too.
- `units[].stance` (`"walk"` / `"sneak"`): how he starts. `units[].portrait`: his cell in the photo atlas
  (`assets/operatives.webp`, 384 px cells left to right: 0 Wren, 1 Rook, 2 Merle, 3 Rype, 4 Hornero, 5 Lechuza,
  6 Benteveo, 7 Biguá); without it, his place in the squad.
- Hornero (`id` `hornero`, Operation Riachuelo, the tram motorman): his figure is `hornero` (operative.gd dresses
  any unit with that id). He carries the tram's controller handle as a cosh (give him `melee {stun, ...}`: it is
  drawn from his right coat pocket for the stun) and the tram's hand bell at his left hip (no rule of its own yet).
- Lechuza, Benteveo and Biguá (`id` `lechuza`, `benteveo`, `bigua`): figures of their own, like Hornero's (no
  `units[].look`). Lechuza carries his folding ladder on his right shoulder and the lineman's tool belt (pliers, the
  sector key, a coil of cord; he binds with no tool to draw). Benteveo has the bag of the late edition across him (no
  weapon). Biguá has a coil of rope over his right shoulder and a sheath knife on the front of his right hip, drawn for
  a lethal takedown (`melee {lethal: true}`).
- `units[].cover {label, zones: [[x, y, w, h], ...], inside, blown}`: a local in his own clothes. Walking
  upright, carrying nothing and doing nothing but his own work, outside the `zones`, he is `covered`: guards
  look straight through him, during an alarm too. Inside a zone he is seen like anyone else. Once a guard
  marks him (`spotted` with him as the target) `blown = true` for the rest of the mission (event
  `cover_blown`). Queries: `covered(unit)`, `covered_at(unit, point)`, `restricted_zones(unit) -> Array[Rect2]`.
- `uniforms {time, action, label, officers, close, order, done, blown, standing, taken}`: any operative can take
  the uniform of a guard who is down (dead, bound or stunned, on the ground, not carried, not already
  stripped): order `uniform`, target the guard's id (`order_uniform(guard_id)`), `time` seconds beside him.
  The guard is left `stripped` (his figure lies in shirt sleeves); the operative gets `disguise {id, kind,
  look}` (whose uniform; the renderer dresses him in that guard's figure, his own weapons and ways kept) and a
  `cover {label, uniform: true, zones: [], blown}`, stands up, and is unmarked again (`blown = false`). From
  then on the `cover` rules hold for him like for a local, everywhere, with one difference: a uniform does not
  fool an officer (a guard whose `kind` or `look` is in `officers`: the sergeant, the boatswain) nor any guard
  within `close` units (`UNIFORM_CLOSE`, 56): for them he is seen like anyone else (`sees_through(guard,
  unit)`). Interactables of type `uniform` (order `uniform`) list the guards whose uniform can be taken; the
  HUD's context slot offers it before carrying the body. Event `uniform` {`by`, `guard`, `x`, `y`}. Missions
  without `uniforms` refuse the order.
- Obstacles carry an optional `see_through` (bool, default false): in the way, but no cover from sight. The
  harbour's smaller things are obstacles too, each built where its footprint is: `silo`, `scaffold` (`out`:
  how far it stands off the pier), `skip`, `formwork` (`lean`: -1 when the pier is to the east), `post` (lamp
  posts at `harbour.lampX`, the site floodlight's pole) and `buffer` (the buffer stop at a siding's west end,
  `harbour.bufferX`; none where cargo under a tarp covers the end). Every walking guard's round must be open
  ground with a way from each point to the next (`tests/cockle_rules.gd` checks it): a point inside something
  solid would stop him there for good.
- `harbour.uboats[] {id, x, z, yaw, length, beam, afloat, scenery?, lamp?}` (metres): the U-boats of the
  3D harbour, a node each in `harbour.uboats` so the closing scene can sink them. Those up on keel blocks are
  also obstacles of kind `uboat`. `charges[].boat` names the U-boat a charge goes on, `charges[].prop`
  ("limpet") the look of the charge if not its `kind`'s.
- `units[].chat {count, time, label, order, start, done, broken, empty, high, edgy, restricted}`: he can stop
  a guard for a smoke (order `chat`, target a guard id; `order_chat(guard_id)`). He walks up (within
  `CHAT_RANGE`), the guard turns to him and stands in state `chat` for `time` seconds, watching only him, then
  goes back to his duty; walking off ends it early. Refused for a guard up high (elevated), behind the wire
  (inside one of his zones), during an alarm, with a body, or with no cigarettes left (`smokes`). Events
  `chat` {`by`, `guard`, `x`, `y`, `left`} and `chat_end` {`guard`, `by`}.
- `units[].melee.stun` (seconds): a cosh, not a knife or a rope. The guard is knocked out (state `stunned`,
  `stun_time` = stun) instead of killed or bound, comes round on his own and goes looking (`woke`), and counts
  in `stats.knockouts`. The takedown event carries `stun: true`.
- `units[].throw {label, count, range, radius, cooldown, noise, icon, kit, done, none, empty}`: a thrown
  distraction of his own (Merle's two wine bottles) in place of Wren's pebbles; `throws` counts what is left
  (-1: no end of them). The `pebble` event carries `noise` ("bottle"). Query: `throw_spec(unit)`.
- `units[].exit {x, y, radius, label, type, order}`: he leaves his own way (the dock gate) instead of by the
  boat, and he does not hold the boat up: the mission is won once everyone else is at the boat with every
  charge set, wherever he is. If he was not at his exit by then he slips away home (`unit.home`, event
  `slipped_home {id}`).
- Messages: `briefingMessage`, `startMessage`, `winMessage`, `extractMessage`, `reinforcements.message`,
  `alarm.gunshotMessage`; `extraction.label`, `extraction.icon`.
- `copy {title, briefing, debrief, wonTitle, hints, coachOrder, hintsWhen, objectiveHow, checkpoints, orderNames, ...}`:
  the HUD's words for this operation; `history[] {title, body, foot}`: the pages after the debrief.
- `tracks` (rails for the recon map), `harbour {...}` (the 3D builders' layout), `finale {}` (a closing scene
  after the win), `ambience {water, hum, electric, windDb, waterRects, falloff, every, calls[]}` (sound).

---

### Keys a level may use: snow, tracks, ropes and floodlights (first written for the engine's snow level)

Every one is optional.

- `passages[] {id, kind, label, x, y, w, h, anchor [x, y], closed, by, time, quiet, noise, sound, slow, radius, depth,
  checkpoint, verb, icon, kit, order, orderQuiet, done, doneQuiet, refuse, already, unreachable}`: a way through that is
  shut until somebody opens it: a gorge to rope down, a window to break, a grille to unscrew, a door to pick. Until
  then each is an obstacle of kind `closed` (default `gorge`: it blocks walking, not sight; `wall` blocks both).
  Order `rig` (target: the passage id; `order_rig(id)`), for the operatives in `by` (empty: anyone), `time` seconds
  at the `anchor`; `quiet {unit: time}` gives those operatives a slower, silent way (`orderQuiet`, `doneQuiet`),
  everyone else's makes a `noise` of that radius (`sound`, e.g. glass) that draws guards. Opened, it is open ground
  for everyone, walked at `slow` of the usual speed (`climbing(actor)`); state `rigged {passage id: unit id}`, a
  checkpoint unless `checkpoint` is false, event `rigged {kind, quiet}`. The HUD shows `verb` and `icon` on the
  action and lists `kit` in the briefing (`""`: nothing to carry). Queries: `passages()`, `passage_by_id(id)`,
  `passage_anchor(p)`, `can_rig(unit, p)`. Interactables of type `rope` (order `rig`).
- `snow {tracks, ttl, spacing, see, follow, hops, packed: [[x, y, w, h]], indoors: [[x, y, w, h]], seen}`: fresh snow
  (not `packed`, not `indoors`, not a rope) takes a footprint every `spacing` units walked (skis leave a ski track);
  prints last `ttl` seconds (`live_tracks()`). A guard on his round who sees a print within `see` (his full range on
  floodlit ground), in his cone and in clear sight, walks to the newest print of the same man within `follow` of it,
  and then looks for more, at most `hops` times (event `tracks`; `message` = `seen` the first time). Queries:
  `on_snow(point)`, `fresh_snow(point)`.
- `floodlit: [[x, y, w, h]]`: under a floodlight a crouched man in a guard's far zone is seen all the same, a
  snowsuit hides nobody, and prints are seen right across the cone (`floodlit(point)`).
- `units[].skis {speed, label, kit}`: upright, empty-handed, on snow and not on a rope he runs at `speed` times his
  walk (`skiing(unit)`). `units[].camo {label, kit}`: crouched, empty-handed and keeping still on snow out of the
  floodlights, a guard sees him only from `CAMO_REVEAL` (36) or closer (`camouflaged(unit)`).
- `guards[].civilian` (the night watchman): no gun; seeing a stranger he raises the alarm and keeps out of the way.
  Knives and guns refuse him (`spare`, "%s" the operative); a bind or a cosh are allowed. `units[].talk {label,
  time, kit, order, start, done, soldier, already, nobody}`: order `talk` (target: the civilian's id;
  `order_talk(id)`): he walks up within `TALK_RANGE`, talks for `time` seconds, and the civilian sits it out in state
  `calm` (`CALM_STATES`): he sees nothing, nobody finds him, and a takedown on him is refused (`calmRefuse`). Events
  `talk`, `calmed`. Interactables of type `civilian` (order `talk`).
- `fuse {objective, time, at, lure, radius, jumpy, danger: [[x, y, w, h]], lit, done, caught, search}`: setting the
  objective's last charge (with no `objective`: the last of all the required ones) lights the fuses (`fuse_left`,
  event `fuse_lit`); when they burn down (`blasted`, event `blast`) everyone inside `danger` is lost, guards within
  `radius` of `at` come to look at `lure` (where they can get to: outside a sealed building), and every guard is on
  edge for `jumpy` seconds. No alarm: they take it for a mine set off by the snow. `search {spawn: [[x, y]], guard,
  routes}`: men turn out at the blast, one per spawn point, ids `s1`, `s2`..., kind `search`, each walking his route
  (event `search {ids, x, y}`); they follow tracks like anyone.
- `units[].cover.seenBy: [guard ids]`: the guards who know the local by face and see straight through his cover
  (the sergeant at Vemork knows the night shift).
- `roofs: [[x, y, w, h]]`: a building made of separate walls still has a roof: an elevated guard (a tower, the
  searchlight) sees neither into it nor through it.
- `guards[].skis`: a patrol on skis (the 3D world gives him skis; his `speed` says how fast).
- A guard of kind `searchlight` (`static`, `elevation`): the beam sweeps its `scan`; inside its `fov` a man is seen
  crouched or not out to `near`, and only buildings and `roofs` cast a shadow. It cannot be lured, reached or
  trapped (`lure_immune`, `melee_immune`, `trap_immune`).
- `charges[].kind` `"evidence"`: a thing left on purpose (the submachine gun), set by anyone (`by: []`), for an
  optional objective.
- `units[].melee {icon, kit}`: the takedown's icon and the word for it in the briefing kit.
- `ambience {humAt: [[x, z]], radioIsPower}`: where the hum comes from (metres; else the radio), and `false` when
  the mission's radio is only a telephone line: cutting it stops neither the hum nor the siren.

---

### Keys Riachuelo uses (`godot/data/riachuelo.json`, written by `tools/dev/riachuelo_layout.py`)

Every one is optional.

- `floodlit` entries may carry a fifth element `"powered"`: `[x, y, w, h, "powered"]` is a lamp fed from the mission's
  board (its `radio`), dark once the board is cut (`floodlit(point)` then ignores it). Plain entries stay lit.
- `passages[].crew: [unit ids]`: a passage only they may use (Biguá's boat). Rigged, it is open ground for its crew and
  for the prisoner while one of them escorts him; for everyone else it stays what it was (`closed`, e.g. `water`). The
  simulation keeps two walking grids (everyone's and the crew's) and plans each walker's routes on his own
  (`_walk_as`); `passage_open_to(passage, actor)` says whether it is open to someone. `get_obstacles()` keeps listing a
  rigged crew passage as closed.
- `guards[].calm: true` on a civilian: he starts in state `calm` (a neighbour out to watch the snow): no cone, nobody's
  target (takedowns refused with `calmRefuse`), never found, through checkpoints too.
- `guards[].title`: the HUD's name for him (PATROLMAN, NEIGHBOUR, INFORMER) in place of one from his kind or look.
- `door {label, icon, order, done, refuse, already, locked}`: the cell door's words (the café cellar: "Cellar door", "Hornero
  has the keys...") and its picture on the marker and the plate (`cellar`; default `key`); `prisoner {icon, tag, word,
  safe, free, takeOver, order, follows, following, already, boarded}`: the one
  being got out, in the mission's words (PASSENGER, "passenger", "across"; `order` is "%s will %s..." with `free` or
  `takeOver`; `icon` his marker and the RESCUE plate's picture, `hand`; default `rescue`). Missing keys fall back to
  Breakwater's informant. A mission with a `prisoner` and no `door` has nothing to
  unlock: he can be freed at once.
- `units[].cover.icon`: his clothes in the briefing kit (`motorcap`, `flatcap`; default `walk`). `radio.kit {icon,
  text}`: what the one who puts it out carries for it, listed in his briefing kit (Lechuza's `lampkey`, "the lamp
  board's key"); the board itself is `radio.icon` (`lampboard`).
- `units[].cover.zones` is still where cover does not hold; a cover that holds only in a few places (Hornero on the
  tram lines, Benteveo in the crowds) is written as the rest of the map (`outside()` in the layout script).
- `theme` `"boca"` picks the La Boca builders, laid out from `bocaWorld` (metres): `boca_ground.gd` (extends
  `harbour_ground.gd`: snowy cobbles from a layout mask, the cutting, quay walls and water from the data's water
  rectangles, river mist; Vemork's footprints and snowfall by way of a `snow_ground.gd` child) and `boca.gd` (extends
  `harbour.gd` without its ships, bunker, quay or yard: houses on every building rectangle, the courtyard, the café
  and its cellar door (`gate`), the bridges, the ladder, the tram, the quay, Biguá's boat, the transporter bridge and
  its gondola, the launch's searchlight, the cart, the lamps). Only the lamps marked `powered` die with the board;
  the launch's searchlight has its own dynamo. `ground_height()` puts a man down the ladder into the cutting and the
  boat's crew (and the passenger behind them) on the water.
- In `scripts/missions.gd`, `LEVELS` lists the game's levels in the order they are played; each opens when the one
  before it is won (`Missions.unlocked()`; `HORACERO_UNLOCK=1` opens them all for testing).
- No `fence`: the wire cutters' order is refused ("There is no wire to cut here.") instead of failing.
- The briefing's kit and the tag over a local in his own words: `units[].toolsKit` (what `tools` is called, in place of
  "lock picks, wire cutters": Hornero's keys), `units[].cover.kit` (his clothes, in place of "dock clothes": a
  motorman's cap and coat) and `units[].cover.tag` (the tag over him while his cover holds, in place of DOCKER).

## 14d. The level — Operation Riachuelo

La Boca, Buenos Aires, a snowy winter night in 1958 (an original story), 240 × 150 m: the game's second level, played
by the squad of four neighbours. North to south: the tenements with the squad's courtyard (the start), a street, a sunken
railway cutting (a footbridge in the west, a lit road bridge in the east; Lechuza's ladder by the courtyard), a street
along it, four blocks cut by three streets running down to the river, a cross street and an alley; Café La Bruma on the
Vuelta de Rocha with the passenger in its cellar (the `door`), a square full of snow-watchers in front; the riverside
avenue with the tram rails and a standing tram; the quay, lit from one lamp board on a column at the foot of the tram
street; the boat shed in the west, the transporter bridge's machine house and gondola landing in the east; the
Riachuelo with a river launch moored in it, its searchlight sweeping the boat's water (never its far half) and the
quay; the far bank with the lane where friends wait (the extraction).

- Hornero (the leader, a tram motorman): `tools` (the cellar door, the gondola), the tram's controller handle as a
  cosh, a bell rung to draw guards (`throw`, noise `bell`), and a motorman's `cover` on the tram lines (the avenue and the
  tram street); the sergeant knows him.
- Lechuza (the power company's night lineman): the lamp board (`radio`, his alone, opened with his sector key), his
  folding ladder down the cutting (a `passage`), binds with electrician's cord.
- Benteveo (the canillita, 16): one more of the crowd on the square, in the café and in front of the tenements
  (`cover`; the informer and the sergeant know him), bundles of La Última, the invented evening paper, thrown to draw
  guards while he shouts its last edition, the Sexta (`throw`, `papers`).
- Biguá (the botero): his rowboat, the Santa Lucía, from the shed's slip, straight across (a `crew` passage: his and the passenger's
  only), a knife (lethal, as in the other operations).

Twenty-six on the street: patrolmen of a fictional Guardia de Emergencia (looks `guardia0..2`) on the north street, at
the footbridge and the road bridge, along the cutting, at the top of the west street, down the tram street and the
cross street, the east street, the alley, the square, the avenue and the quay, a man posted on the gondola's landing
and one walking round the machine house (the lamps light the last three: `powered`), the sergeant going round the
middle, and the launch's searchlight; an informer among the snow-watchers on the square (a civilian who shouts); ten
calm neighbours. Reinforcements turn out of the Guardia's post. Fresh snow in the courtyard, the side streets, the
alley, the quay and the far bank takes footprints; the busy streets, the rails, the square and the gondola's landing are
trodden slush. Par 9:00.

The scripted run (`tests/riachuelo_playthrough.gd`): the squad waits for the sergeant to pass, Lechuza sets the ladder
and all four cross the cutting. Lechuza and Benteveo wait in the scrub on the far lip until the tram street's patrolman
turns off along the cross street, follow him down, and Lechuza puts the quay's lamps out; they wait in a doorway by the
landing. Hornero and Biguá follow the alley's patrolman down the alley and Biguá's knife takes him by the café's back
door (hidden in a doorway). Hornero opens the cellar and goes on upright along the tram lines to the dark landing,
where he works the gondola a few steps behind the posted man; three ride across. Biguá takes the passenger up the
alley, along the cross street and down the west street to the boats by the shed and rows him over when the launch's
beam has swung away. It wins unseen in about 5:53 with Ghost, Not a shot, Saboteur and Swift (one man killed). Every
line it put in the notice strip is then read in Spanish (`locale/es.json`): each has its Rioplatense form.
The second level of Hora Cero, opened by winning the Plaza de Mayo.

### Keys the Plaza de Mayo uses (`godot/data/plaza.json`, written by `tools/dev/plaza_layout.py`)

Every one is optional. Together they make a
**rescue**: no guards and no way out, a deadly snow instead, and people to bring under cover. `rescue_on` is true when
the data has `snowfall`.

- `snowfall {schedule, bury, rate {unit, person}, recover, grace {unit, person}, need, heavy, lull, panic,
  panicExposure, warn, lead, follow, speed, run, helpTime, guideTime, canvasTime, helped, title, messages}`: the snow.
  `schedule` is `[[seconds, strength], ...]`, linear between its points (`snow_intensity(t)`); at `bury` seconds the
  snow buries the square (`square_buried`): whoever is still out in it is lost. Out in the snow, cold (`exposure`,
  0..1) builds at `strength / rate.unit` (operatives) or `strength / rate.person` (people) a second; under cover it
  goes at `1 / recover` a second. At 1 one falls: an operative (`unit.fallen`) has `grace.unit` seconds for a mate to
  help him up (`help`: on his feet again with `helped` of cold), a person `grace.person` for Biguá to carry them in
  (carried, their time stands still); then the snow covers them (`unit.buried`, not `alive`; a person's state
  `lost`). `heavy` and `lull` are the strengths at which `snow_level()` says `wave` and `lull`; in a wave at or above
  `panic`, a person following who has taken `panicExposure` of cold may break and run. `need` is how many must be
  under cover to win; `lead` how many an operative leads at once unless his own `units[].lead` says otherwise;
  `follow` the gap between followers (units), `speed` and `run` people's walking and running speeds; `helpTime`,
  `guideTime`, `canvasTime` the orders' work. `messages` are the notice lines (`fell`, `fellUnit`, `buried`,
  `buriedUnit`, `savedCount` "Under cover: %d of %d.", `panicked`, `dark`, `lostAll`, `tooFew`, `lostTooMany`, `wave`,
  `lullNow`, and the orders' refusals), in the mission's words; the code has English fallbacks for each.
- `people [{id, x, y, facing, group, look, exposure?, panic? {at, flee}}]`: the square's people, kept on the guards'
  list as civilians of kind `person` (`person: true`; no cone, nobody's target, never alarmed) so the world and the
  HUD draw them with the figures their `look` names. States (`PERSON_STATES`): `crowd` (standing), `follow` (led by an
  operative: `follow_id`, `rank` in the chain), `coming` (making for a shelter by himself, called there), `panic`
  (running blindly, `panic.flee` at `panic.at` seconds, or broken in a wave), `safe` (under cover: `shelter`), `fallen`
  (down in the snow, carried like a body: in `BODY_STATES`), `lost`. Queries: `people()`, `person_by_id(id)`,
  `followers_of(unit_id)`, `lead_of(unit)`, `rescue_counts() -> {saved, lost, out, fallen, total, need}`.
- `shelters [{id, label, kind, x, y, w, h, inside, dark?, vehicle?}]`: where the snow cannot reach (the Catedral's
  portico, the Cabildo's arcade, three subte stairs, the Banco's porch, the tram, the colectivo). One with `vehicle`
  moves with it. One with `dark` (a passage's id) is shunned by people until that passage is rigged (Lechuza's lights);
  the squad may still shelter in it. Queries: `shelters()`, `shelter_by_id(id)`, `shelter_rect(s)`,
  `shelter_open(s)`, `shelter_at(point, for_people)`, `shelter_inside(s)`.
- `vehicles [{id, label, kind, x, y, w, h, stops?, speed?, by?, time?, icon, verb, order, done, moving, refuse}]`: a
  vehicle with `stops` (x positions in units) is driven by the units in `by` to its next stop (`drive`), carrying
  everyone in its rectangle; one without stays put (the colectivo). `vehicles` (state `{x, y, stop, to, dir,
  driver}`), `vehicle_spec(id)`, `vehicle_rect(id)`, `vehicle_at(point)`.
- `canvases [{id, label, kind, x, y, time, holds, order, take}]`: a cloth (the café's awning, the kiosk's tarpaulin,
  the cart's cover) taken once (`canvases_taken`) and held over the operative and the first `holds` behind him for one
  crossing: no cold for them while it lasts (`time` seconds out of cover at most), spent once he is under cover again.
- `units[].call {label, mode, radius, count, cooldown, noise, icon, from?, done, none, empty, away}`: the call (an
  instant action, `call`): `follow` (Benteveo's voice: everyone near falls in behind him, as many as he can lead) or
  `come` (Hornero's bell, rung from the vehicle `from`: everyone near makes for it). `units[].lead` (how many he can
  lead), `units[].carries: true` (he may lift the fallen: Biguá, Juan Salvo).
- `units[].suit: true`: sealed against the snow (Juan Salvo): no cold at all, wave or no wave; knocked down, he gets up
  again by himself after `snowfall.suitUp` seconds (8); the buried square still takes him if he is out in it.
- `units[].arrive {at, to, text, notYet, checkpoint}`: one who comes later in the night. Until `at` seconds he is
  `away`: off in play where his data puts him (the edge of the map), not selectable, refusing every order (`notYet`),
  taking no cold, nobody's prey, not holding up the end; then `_arrive()`: event `arrival`, the `text` in the notice, a
  move order on to `to`, a checkpoint under his id when `checkpoint` is true. The HUD shows his photo dark with ON HIS
  WAY; the recon map leaves him out; `plaza_creatures.gd` hides his figure and marks where he will come in.
- `units[].gun {icon, kit, prompt, promptNone, sound}`: a gun's own picture and briefing words, the armed prompt's line
  (with marked targets, with none), and the noise kind its shot leaves (Juan Salvo's rifle: `rifle`).
- `creatures {look, title, speed, charge, flee, sense, reach, radius, pause, hits, away, linger, think, spare, roam,
  hear {noise kind: units}, arrivals [{id, at, from, to, text}], arrive, back, strike, strikeUnit, driven, killed,
  missed, unarmed, noTarget, shootLabel, drawnBy {noise kind: text}}`: the cascarudos. Kept on the guards' list as
  kind `creature` (`creature: true`), dressed from `look` (the art pack's slot), named `title` in the HUD's tags.
  States (`CREATURE_STATES`, all in `DOWN_STATES` but `dead`: no cone, no perception, no alarm): `waiting` (off the map
  until `at`), `prowl` (roaming at `speed` toward the nearest one out in the open anywhere, or wandering `roam` with
  nobody out), `stalk` (going at `charge` for the nearest out in the open within `sense`), `drawn` (to a noise heard
  within `hear[kind]`: the bell, a shout, a shot; it stays about `linger` seconds), `stay` (`pause` seconds over the
  one it knocked down), `driven` (hit: off at `flee` the way it came), `away` (off the map `away` seconds, then back
  in), `dead` (the `hits`-th hit). Whoever it reaches (`reach`, nothing solid between) falls: a person `fallen`, one of
  the squad `fallen` (he is left alone `spare` seconds once up). Nobody under cover or in a vehicle is prey. It walks
  its own ground (`_creature_path`: everything solid, every shelter and every vehicle grown by `radius`;
  `creature_ground_open(point)`), and never walks into a vehicle under way. A shot at it (`shoot`, `target_guard`;
  persons are refused as civilians) drives it off or kills it, and the bang (`gun.noise` far, kind `gun.sound`) draws
  the others. `creatures_about()` lists those in the square; `interactables()` lists each for one with a gun (type
  `creature`, order `shoot`). Events: `creature {again}`, `struck {by, id, unit}`, `drawn {ids, noise}`,
  `creature_hit {hits}`, `creature_gone`, `creature_dead`, `arrival`; stats `struck`, `creatures_killed`.
- `passages[].objective`: rigging the passage completes that objective (the arcade's lights, the service gate).
- `medals [{id, label, text, art, rule}]` in place of the five badges: `rule` `everyone` (nobody lost, out or down at
  the end), `squad` (none of the four lost), `time` (within `parTime`; `%d:%02d` in the text). `art` is a medal of
  `ActionSlot.BADGES`, else a glyph stamped in a ring.
- Orders: `order_guide(person_id)` (`guide`, a `target_guard` action: he walks to the person and leads them in, and
  with them whoever of their group stands near and is not led yet), `order_call()`, `order_drive(id)`,
  `order_canvas(id)`, `order_help(unit_id)`; `perform()` takes `guide`, `call`, `drive`, `canvas`, `help`. Biguá lifts
  a fallen person with `pickup` and sets them down under cover (`safe`). `available_actions()` lists `guide` (count:
  his followers), `call` (cooldown, calls left), `drive` and `canvas` (context); `interactables()` lists the people
  (`person`), a fallen mate (`fallen`), the cloths (`canvas`), the drivable vehicle (its `kind`), and the passages.
- Events: `guided`, `call`, `saved`, `fallen {unit}`, `buried {unit}`, `panic`, `helped`, `canvas`, `canvas_spent`,
  `drive`, `arrived`, `snowfall {level, strength}` (on a change of `snow_level()`), `square_buried`. Losing: the whole squad
  lost (`lostAll`; one still on his way counts as there), too many lost to reach `need` (`lostTooMany`), or the burial with too few under cover (`tooFew`).
  Winning: everyone in (people and the squad under cover, nobody out or down) with at least `need` saved, or the
  burial with `need` saved. `snow_intensity(t)`, `snow_level(t)`, `next_wave()` (seconds, 0 in a wave, -1 if none),
  `bury_time()`, `bury_left()`.
- `theme` `"plaza"` picks the plaza builders, laid out from `plazaWorld` (metres): `plaza_ground.gd` (extends
  `boca_ground.gd`: the carriageways, walks, lawns and kerbs from layout masks, the subte's stairs left open, the snow
  laid by `laid(snow_cover())` as it falls, the footprints from Vemork's ground, its own snowfall as thick as the
  rules' snow) and `plaza.gd` (extends `boca.gd`: the landmarks from the Plaza de Mayo kit, see 14e). `ground_height()`
  takes a man down the subte's stairs (the kit's 24 steps, `plazaWorld.stairDepth` 4.2 m) and up on the tram's floor,
  the colectivo's, the Catedral's stylobate (`stylobate`, 1.6 m) and its eight steps, the Banco's five steps to its
  porch and the arcade's floor. `plazaWorld.benches` (`[x, z, facing°]`) and `parked` (`[x, z, heading°, kind]`:
  `sedan`, `saloon`, `taxi`, `truck`) place the kit's benches and cars where the layout's `bench` and `car` obstacles
  are. The atmosphere is La Boca's night; the light comes high from the north-north-west, and on the square the
  figures throw no shadow from it (their soft one at their feet only: `world.gd`, for the draw calls).
- `camera.title.yaw` (degrees, 45 unless given): the launch screen's view looks this way along the title stretch.

## 14e. The level — Plaza de Mayo

Buenos Aires, 1958, the night the snow begins (a prologue after the comic by Oesterheld and Solano López that began in
Hora Cero Semanal in 1957, whose rights holders cleared its characters and creatures): the game's first level, the four
neighbours of Riachuelo and Juan Salvo, 280 × 166 m. A snow that kills when it settles on
you, and from the first minute the cascarudos. The square (200 × 96 m) with Rivadavia and its tram tracks along the north, Hipólito Yrigoyen
along the south, Bolívar west and Balcarce east; the Catedral in the north-west corner behind its portico, the Banco de
la Nación in the north-east, the Casa Rosada across the east side, the ministries along the south, the Cabildo and its
arcade on the west with the Avenida de Mayo leaving between it and the Palacio Municipal; in the square the Pirámide
behind its railing, eight palms round it, the Belgrano before the Casa Rosada, the flagpole, eighteen lamps, twelve
benches; two subte stairs on the avenue's pavements and a locked service stair by the square's south-west corner;
cars of the time parked at the kerbs (official cars before the Casa Rosada, taxis on Bolívar, cars and a soda truck on
Yrigoyen).

Twenty-six people in groups about the square watch the first snow; three of them panic at set times and run off into
it (two of them to the Casa Rosada's shut gates). The snow comes in waves you see coming (the readout: WAVE IN 12), with lulls between, until it
buries the square at 8:00. Hornero brings the tram along Rivadavia from stop to stop and rings its bell (people near
make for it); Benteveo's shout gathers everyone near behind him and he leads eight; Lechuza mends the Cabildo's arcade
lights (people will not go into its dark) and unlocks the service gate; Biguá carries in whoever falls. Each of them
can take a cloth (the café's awning, the kiosk's tarpaulin, the cart's cover) for one crossing. Juan Salvo comes in
off Avenida de Mayo at 0:30 in his insulating suit: no cold, so he is the one to cross the open square in a wave and
carry in the fallen, one at a time; he leads two; his rifle has six rounds. Three cascarudos come up the avenues
(Rivadavia from the east at 0:15, Hipólito Yrigoyen from the east at 1:15, Avenida de Mayo at 2:40), go for whoever is
out in the open and knock them down; noise draws them (Hornero's bell from 80 m, a shout from 16, a shot from 120); a
hit drives one off for 35 s, three kill it. Their figures and Juan Salvo's are the art pack's licensed models
(`juan_salvo`, `cascarudo`: a cascarudo 4 m long, so the rules' `creatures.radius` is 56 (1.75 m, half its width) and
`reach` 2.8 m, from its middle to just past its head). Medals: Nobody left out, The whole squad, Swift
(under 5:30). Par 5:30.

The scripted run (`tests/plaza_playthrough.gd`, its header tells it in full): in the first light snow Benteveo shouts
the group by the Catedral into its portico, Hornero takes the tram from stop to stop ringing its bell for the groups
under the palms and by the flagpole without waiting at the first stop (they run after the tram), and at the bank's stop
the bell draws the first cascarudo away from the flagpole to the tram while the two in its reach get in ahead of it;
Lechuza mends the arcade's lights, opens the service gate and brings the group by the Cabildo down the service stair,
and Biguá brings the groups by the Belgrano and the Casa Rosada to the colectivo. Juan Salvo walks along the north of
the square toward the tram and drives the first cascarudo off with his rifle as it comes at him; through the first
wave, which the squad waits out under cover, he crosses to the Casa Rosada's gates and drives off the second as it goes
for the two who have run there in a panic, and in the lull he leads them to the colectivo, while Benteveo leads the six
by the Pirámide to the tram and Lechuza the two in the south to the service stair, ahead of the third cascarudo. All 26
under cover and the squad too in about 3:24, nobody fallen or knocked down, two of the six rounds fired, all three
medals.
`plaza_creatures.gd` (made by `plaza.gd`) shows who of them is in the square and inks their marks on the ground: a red
ring round each cascarudo, its senses' reach, a line to the one it goes for or to the noise that draws it, the edge
where one is about to come in, and where Juan Salvo will; and it lays the night on their models (cutout.gd weather(): the
snow settling on Juan's hood and shoulders and on the cascarudos' backs with the rules' snow cover, both wetter as the
night goes on). Knocked down, Juan Salvo gets no snow mound (his suit keeps it off; he gets up by himself).

The 3D scene (`scripts/three_d/plaza.gd`) builds the square from the Plaza de Mayo kit (`plaza_kit.gd`, with
`plaza_kit_buildings.gd`, `plaza_kit_props.gd` and `plaza_kit_vehicles.gd`) on the layout's footprints, and the layout
follows the kit: `plaza_layout.py` fits the rules' rectangles to what the kit's builders put where, so the walk mesh,
the cover and the pictures agree. The Catedral (`plazaWorld.catedral`, its front the foot of its steps on Rivadavia's
pavement): twelve columns 0.04 of its front in from either end and 5 m back (`columnX`, `columnsZ`), the stylobate
1.6 m up from 3.6 m back, the portico's floor to the wall with the doors 11 m back. The Cabildo (`cabildo`, facing
east): five arches of 5.2 m in a front 0.8 m thick (`pier-*` between them), its arcade 3.4 m deep to the house
(`arcade`), closed by walls 0.4 m thick. The Banco: its porch set back 4 m between the middle five of eleven bays
(`bancoPorch`), four great columns before it, five steps up. The Casa Rosada: the wings 2.4 m and the pavilions 1.2 m
behind Tamburini's block, the pedestals of its columns on the pavement, the arch (`rosadaArch`) shut. The Pirámide's
railing (6.4 m), the Belgrano's granite step (7.4 × 4.2 m, looking west), the flagpole's base, the kiosk, the
colectivo (the kit's 7.6 × 2.24 m), the subte's stairs (24 steps, 4.2 m down from just inside the head).

`_landmarks()` (the Casa Rosada floodlit with the flag over its attic, the Cabildo, the Catedral, the Banco, the two
ministries, the Pirámide, the Belgrano, the flagpole and its flag, the kiosk, the three stairs), `_municipal()` (the kit
has no Palacio Municipal: its Avenida de Mayo fronts round the block, the domed turret on the corner), `_city()` (the
kit's avenue fronts along every street edge round the square and west of it), `_furniture()` (the palms, the lamps of
the square, the benches; the city's lamps), `_traffic()` (the parked cars, the rules' colectivo, a second tram and
colectivo beyond the map) and `_cafe_front()`. The rules' tram is the kit's on a kit of its own (`tram_kit`), fitted to
the rules' 14 m, so that its light on the snow and its headlamp go with it. Its own builders only for what the kit has
not: `_tram_line()`, `_service_gate()`, `_cart(rect)`, `_cafe_awning(pos)` and the cloths, `_cabildo_lights()` (the
arcade's darkness and fuse box: the kit's five lanterns are taken out of the Cabildo's detail, `_split_lanterns()`, and
stay dark until the passage is rigged), the drifts and the mounds. Real lights only where the kit asks for them and the
game needs them (`_kit_lights()`: the eighteen lamps of the square, the arcade's lanterns, the subte's passages, the
kiosk, the Casa Rosada's arch); the square's lamps stutter now and then, more in a wave, their halos with them (each
lamp's instances of the kit's halo multimesh). The buildings fade when somebody stands behind them (body and detail;
in comic ink they go altogether). In the game's opening view (the start, 140 × 70, zoom 34) a frame is about 390 draw
calls and 1.2 M primitives (Compatibility renderer).

The snow builds up with the rules' clock: `PlazaGround.snow_cover(sim)` (0..1, the schedule summed) over the dusting
that lay already (`PlazaGround.DUSTING`, 0.3: `laid()`) whitens the ground (`shaders/plaza_ground.gdshader`, `cover`),
raises the snow on everything built (`snow_amount` of the kit's shaders and of the surface and La Boca's walls shaders;
the kit's ledges, roofs and cars hold theirs as geometry), the drifts against the walls and the kerbs' snow; the flags
fly harder in a wave; a mound grows over anyone fallen and covers anyone lost (their figure hidden); people and the
squad kneel when they fall (`operative.gd`, `CL_KNEEL`).

## 18. Tests and tools

From the repository root (`tools/run_tests.sh` runs them all, importing first; set `GODOT` to the Godot 4.7 binary):

```
godot --headless --path godot --script res://tests/plaza_rules.gd           # the plaza's rules one by one: snow, cold, leading, calls, tram, cloths, every order
godot --headless --path godot --script res://tests/plaza_playthrough.gd     # everyone under cover, all three medals, read in Spanish too
godot --headless --path godot --script res://tests/plaza_scene.gd           # the square in 3D: the kit on the rules' footprints, lamps, snow, tram, mounds, gate
godot --headless --path godot --script res://tests/riachuelo_rules.gd       # Riachuelo's rules one by one, the grid, every order of every operative
godot --headless --path godot --script res://tests/riachuelo_playthrough.gd # the crossing: ladder, lamps, cellar, gondola and boat
godot --headless --path godot --script res://tests/riachuelo_scene.gd       # La Boca in 3D: lamps, ladder, cellar door, gondola, boat
godot --headless --path godot --script res://tests/world_visuals.gd         # the world layer's bookkeeping in Riachuelo: models, cones, previews
godot --headless --path godot --script res://tests/hud_actions.gd           # the phone controls end to end, then the plaza's
godot --headless --path godot --script res://tests/icons.gd                 # every picture either level can ask for
godot --headless --path godot --script res://tests/art_pack.gd              # the art pack, cut-outs, models, stand-ins, comic ink
godot --headless --path godot --script res://tests/voice_lines.gd           # the voices, their files and their timing
godot --headless --path godot --script res://tests/audio_events.gd          # the sounds: files, events, the tram's bell, the rifle
godot --headless --path godot --script res://tests/lang_es.gd               # the game in Spanish (section 19)
godot --headless --path godot --script res://tests/launch_screen.gd         # the launch screen and the questions (section 20)
```

The licensed art (Juan Salvo, the cascarudo, the vehicles) is in the repository with its makers' permission, under its
own terms (NOTICE): the suites check the models themselves, and the neutral stand-ins and the kit's own vehicles in a
build without them (README.md).

- `tests/playthrough_kit.gd` — the script player: `order / do / go / walk / follow / until / wait`, and
  `scan(span, step, plan)`, which replays a plan from the current moment after 0, step, 2 × step … seconds
  and reports which start times get through (how wide a timing window is). Use it when retuning.
- `tools/dev/plaza_shots.gd` photographs the square (setups "", "hero", "lit", "rescue", "late", "buried"; flags
  "persp" for a lens instead of the game's orthographic camera, "perf" and "census" for what a frame draws; see its
  header); `tools/dev/riachuelo_shots.gd` photographs La Boca (setups "", "cafe", "crossing"); `collision_map.gd
  riachuelo` with `collision_overlay.py` lays the rules' solids over a picture from straight above;
  `stealth_planner.gd` finds unseen routes through the patrols; `mission_map.gd` draws a layout;
  `ui_shots.gd` photographs the dossier pages and the game at one window size; `icon_shots.gd` every icon a level
  can show.

Add `-d` to any of them to see GDScript warnings.

## 19. Two languages

The whole game is in Spanish (Rioplatense, as Buenos Aires spoke it in 1958) and English. English is the source:
every text in the code and in the level data is written in English and is its own key; `godot/locale/es.json` maps
it to Spanish (`strings`), and lists the names and words that stay the same in both (`keep`: Hornero, Cabildo,
PLAN…). `godot/scripts/lang.gd` does the rest:

- **Choosing.** ES and EN on the launch screen itself, and the language row in SETTINGS. The choice is kept in the
  progress file (`settings/language`); the first time, the game starts in Spanish (`Missions.start_lang()`,
  `Lang.starting()`). Switching reloads the scene. `HORACERO_LANG=es` forces Spanish (tests, tools; runs started
  with `--script` are in English otherwise).
- **Level data** is translated once as it loads (`Lang.translate_data`): every text field, never ids or codes
  (`DATA_IDS`) and never the world's signage (`DATA_SKIP`). The simulation then builds its messages from Spanish
  names and labels.
- **The screen** goes through Godot's TranslationServer: Labels and Buttons translate themselves, the painted
  panels and plates call `tr()`. World signs (`Label3D`) are set never to translate.
- **Lookup** takes a text as the game made it: an exact key; the same in capitals (plates); with its first
  letter lowered; a template filled in (`"%s closes in: %s."`, matched back and rebuilt in Spanish, its pieces
  translated in turn, a name's article lowered inside a sentence: "al pasajero"); or several sentences run together,
  the longest known run first. What it cannot place is shown as it is.
- **Stamps** on the dossier have Spanish versions (`assets/ui/stamp_*_es.png`, from `tools/gen_ui_textures.py`).
- **Voices** come from `assets/audio/voice/<language>/`, falling back to English (`docs/VOICE_LINES.md`).

Adding or changing a text: write it in English as usual, then run `python3 tools/i18n_extract.py` from the
repository root; it lists the texts of the code and the data that have no Spanish yet (`--check` exits non-zero
if any). Add them to `es.json`, keeping every placeholder (`%s`, `%d`, `%.1f`, `{left}`) in the same order. The
Spanish is Rioplatense: `vos` to the player and among the squad (tocá, agachate, movete), `ustedes` for several,
never vosotros or tú; `tests/lang_es.gd` checks every entry for it.

## 20. The launch screen and the questions

**The launch screen** (`scripts/three_d/front.gd`) opens the game: the current level's scene behind it, the camera
drifting along a stretch of it (data `camera.title`: `from`, `to`, `zoom`), the guards walking their rounds
(`Simulation.idle()`: patrols and posts only, nothing noticed, the clock still), no cones or marks. Under the name,
HORA CERO, a brass PREVIEW stamp (ADELANTO in Spanish) and the game's line, INVASIÓN BUENOS AIRES (`Missions.GAME`,
the one place it is written). The menu: CONTINUE (PLAY before anything is on file) to the current level's briefing,
SETTINGS (language, text size, sound, voices, comic ink, the art credits), HOW TO PLAY (the HUD's page over the
scene), and TELL US WHAT YOU THINK when the answers have somewhere to go (below). ES and EN sit top right. The
pages are full screen on dossier paper; upright, the column is set at a phone's width and drawn larger. The
briefing's other button is MENU; the pause menu's is MAIN MENU (two taps: the run is left). Android's Back and Esc
go a page back, and from the menu leave the game. Runs started with `--script` skip the launch screen unless
`Front.force = 1` or `HORACERO_TITLE=1`.

**The levels** (`scripts/missions.gd`): the Plaza de Mayo, then Riachuelo, the second opened by winning the first
(NEXT OPERATION after the plaza's real story). When the Godot editor runs the game (Run Project, a debug build with
the editor's debugger attached) both are open (`Missions.dev_unlocked()`); exported games, tests and tools keep the
lock. `HORACERO_UNLOCK=1` or `0` forces it either way in a debug build; `HORACERO_MISSION=riachuelo` starts straight
on a level.

**The questions** (`scripts/feedback.gd`): did you enjoy it (1 to 5), would you play more levels like these, what
confused you or what you would change, an email to hear when more comes; every answer optional. They are offered
(on the menu, in the pause menu over the paused level, and after the last level's real story, once, until answered
after a win) only when a feedback address is configured: the project setting `hora_cero/feedback/url`, empty in this
repository, or a web build's `--feedback-url` (`tools/web_site_build.py`, which writes it into that build's page
only). Without one nothing is asked and nothing is sent anywhere. With one, the answers wait in the progress file
(section `feedback`) until the address takes them, and go as one JSON object:
`{game, device, won, level, platform, lang, build, rating, would_play_more, comment, email}` (`Feedback.body()`;
`device` is a random id made once on the device, so answering again can replace the earlier answers). Optional
request headers: `hora_cero/feedback/headers`, or `--feedback-header` for a web build. Tests are offline: `Feedback.online`
is false under `--script` unless `HORACERO_FEEDBACK_ONLINE=1`.

Phones play in either orientation (`display/window/handheld/orientation` = sensor); every screen has an
upright and a landscape layout and re-lays itself out when the phone turns.
