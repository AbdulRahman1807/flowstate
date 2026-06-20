extends SceneTree

# Proves the wall/edge-launch FLOAT fix (player feedback: "jumping off a ramp / wall edge is too
# floaty"). On detach, GravitySystem.force_airborne() leaves _current_gravity pointing INTO the wall
# (mostly sideways). The AIRBORNE gravity lerp must re-align that to straight-down PROMPTLY so the car
# gets pulled down instead of floating + drifting toward where the wall was.
#
# Two trials, identical launch (airborne, into-wall gravity, upward velocity, no geometry so the arc
# is free):
#   NEW : airborne_transition_speed = 30  (the fix)
#   OLD : airborne_transition_speed forced to gravity_transition_speed = 8 (pre-fix behavior)
# Asserts: (1) NEW re-aligns applied gravity to ~straight-down within a few frames,
#          (2) NEW apex is lower and airtime shorter than OLD (less float).
# Run: Godot --headless --script res://scripts/tests/_WallLaunchFloatProbe.gd

const ALIGN_DOT := 0.95          # applied-gravity dir vs Vector3.DOWN considered "straight down"
const MAX_ALIGN_FRAMES := 10     # NEW must reach ALIGN_DOT within this many frames
const START_Y := 200.0           # high up so nothing is hit during the measured arc
const UP_VEL := 8.0              # upward launch (like a wall jump-off carrying up-the-wall momentum)
const WALL_GRAV := Vector3(-17.7, -0.3, 0.0)  # leftover into-wall gravity (matches _WallStickProbe)

var _v: CharacterBody3D
var _gs
var _vc

var _trial := 0
var _need_setup := true
var _t := 0
# per-trial measurements
var _frames_to_align := -1
var _start_y := 0.0
var _peak_rise := 0.0            # max height gained above launch (apex)
var _air_frames_to_return := -1  # frames until the car falls back to launch height (airtime proxy)
var _rose := false
# results captured per trial: [label, frames_to_align, peak_rise, air_frames_to_return]
var _results := []

# [label, airborne_transition_speed]
var _cases := [
	["NEW(fast)", 30.0],
	["OLD(slow=8)", 8.0],
]

func _initialize() -> void:
	var world := Node3D.new(); root.add_child(world)
	# Intentionally NO geometry near the car — we measure a free airborne arc.

	_v = CharacterBody3D.new(); _v.set_script(load("res://scripts/vehicle/VehiclePhysics.gd")); _v.name = "Vehicle"
	var col := CollisionShape3D.new(); var cap := CapsuleShape3D.new(); cap.radius = 0.8; cap.height = 1.6; col.shape = cap
	_v.add_child(col)
	_vc = _child(_v, "VehicleController", Node, "res://scripts/vehicle/VehicleController.gd")
	_gs = _child(_v, "GravitySystem", Node3D, "res://scripts/vehicle/GravitySystem.gd")
	_child(_v, "WallRiding", Node, "res://scripts/vehicle/WallRiding.gd")
	_child(_v, "FlowSystem", Node, "res://scripts/systems/FlowSystem.gd")
	_child(_v, "WallSensor", Node, "res://scripts/vehicle/WallSensor.gd")
	world.add_child(_v)
	_vc.set_physics_process(false)   # we drive apply_intent ourselves (no double-step)
	print("=== Wall-Launch Float Probe (leave wall -> gravity must pull DOWN promptly) ===")

func _start_trial() -> void:
	var c = _cases[_trial]
	_gs.airborne_transition_speed = float(c[1])
	# Simulate the instant after detach: AIRBORNE, stale into-wall gravity, upward velocity.
	_v.global_position = Vector3(0, START_Y, 0)
	_v.velocity = Vector3(0, UP_VEL, 0)
	_gs.force_airborne()
	_gs._current_gravity = WALL_GRAV   # the leftover into-wall vector detach leaves behind
	_start_y = START_Y
	_t = 0
	_frames_to_align = -1
	_peak_rise = 0.0
	_air_frames_to_return = -1
	_rose = false

func _physics_process(_dt: float) -> bool:
	if _need_setup:
		_start_trial(); _need_setup = false; return false

	var mi = load("res://scripts/vehicle/MovementIntent.gd").new()
	mi.accelerate = 0.0
	mi.steer = 0.0
	_v.apply_intent(mi)
	_t += 1

	# (1) How quickly does the APPLIED gravity re-align to straight-down?
	var g_dir: Vector3 = _gs.get_applied_gravity().normalized()
	var align_dot := g_dir.dot(Vector3.DOWN)
	if _frames_to_align < 0 and align_dot > ALIGN_DOT:
		_frames_to_align = _t

	# (2) Apex + airtime (float). Track rise above launch, then frames to fall back through it.
	var rise := _v.global_position.y - _start_y
	_peak_rise = maxf(_peak_rise, rise)
	if rise > 0.05:
		_rose = true
	if _rose and _air_frames_to_return < 0 and rise <= 0.0:
		_air_frames_to_return = _t

	if _t % 6 == 0:
		print("  %-11s f%2d  rise=%5.2f  g=(%6.2f,%7.2f,%6.2f)  dot(DOWN)=%.3f  spd=%4.1f" % [
			_cases[_trial][0], _t, rise,
			_gs.get_applied_gravity().x, _gs.get_applied_gravity().y, _gs.get_applied_gravity().z,
			align_dot, _v.velocity.length()])

	# End trial once it has come back down (or after a hard cap).
	if (_air_frames_to_return > 0) or _t >= 180:
		_results.append([_cases[_trial][0], _frames_to_align, _peak_rise, _air_frames_to_return])
		print("=> %-11s frames_to_align=%s  apex_rise=%.2f  airtime_frames(return)=%s" % [
			_cases[_trial][0],
			str(_frames_to_align) if _frames_to_align >= 0 else ">cap",
			_peak_rise,
			str(_air_frames_to_return) if _air_frames_to_return >= 0 else ">cap"])
		_trial += 1
		if _trial >= _cases.size():
			_finish()
			return true
		_start_trial()
	return false

func _finish() -> void:
	var new_r = _results[0]
	var old_r = _results[1]
	var align_ok: bool = new_r[1] >= 0 and new_r[1] <= MAX_ALIGN_FRAMES
	# NEW must align faster than OLD (OLD may never reach it within the cap -> treat as worse).
	var old_align: int = old_r[1] if old_r[1] >= 0 else 9999
	var faster_align: bool = new_r[1] >= 0 and new_r[1] < old_align
	# Less float: lower apex AND quicker return to launch height.
	var new_air: int = new_r[3] if new_r[3] >= 0 else 9999
	var old_air: int = old_r[3] if old_r[3] >= 0 else 9999
	var lower_apex: bool = new_r[2] < old_r[2]
	var shorter_air: bool = new_air < old_air
	var pass_all: bool = align_ok and faster_align and lower_apex and shorter_air
	print("---")
	print("ALIGN: NEW reached straight-down in %s frame(s) (<= %d) -> %s" % [str(new_r[1]), MAX_ALIGN_FRAMES, align_ok])
	print("ALIGN: NEW(%s) faster than OLD(%s) -> %s" % [str(new_r[1]), str(old_r[1]), faster_align])
	print("FLOAT: apex NEW=%.2f < OLD=%.2f -> %s" % [new_r[2], old_r[2], lower_apex])
	print("FLOAT: airtime NEW=%s < OLD=%s frames -> %s" % [str(new_r[3]), str(old_r[3]), shorter_air])
	print("=== %s ===" % ("PASS" if pass_all else "FAIL"))

func _child(parent: Node, n: String, base, path: String):
	var node = base.new(); node.set_script(load(path)); node.name = n
	parent.add_child(node); return node
