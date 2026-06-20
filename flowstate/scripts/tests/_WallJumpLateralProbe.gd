extends SceneTree

# Verifies the wall jump-off FLOWS — low sideways momentum AND low vertical "hover".
# Player feedback: (1) "too much sideways momentum ... no exaggerated sideways" and later
# (2) "jumping off from a side wall is still way too floaty ... having the car hover and
# gradually fall for 5 seconds is a major turn off".
#
# The launch must carry the player's momentum into the HORIZONTAL travel direction with only a
# small off-wall push (sideways) and a small intentional hop (vertical) — not a skyward fling.
#
# Phase A: realistic attach (drive at a LEFT wall, attach via the real path) + neutral jump.
# Phase B: the CRITICAL case — a car CLIMBING the wall (facing tilted up the wall, big upward
#          velocity) jumps off; the launch must be mostly HORIZONTAL (vertical ~= up_force only).
# Run: Godot --headless --script res://scripts/tests/_WallJumpLateralProbe.gd

const LATERAL_RATIO_MAX := 0.45

var _v: CharacterBody3D
var _gs
var _wr
var _phase := 0
var _t := 0
var _fails := 0

func _initialize() -> void:
	var world := Node3D.new(); root.add_child(world)
	_box(world, Vector3(200, 1, 200), Vector3(0, -0.65, -40))     # flush floor
	_box(world, Vector3(1, 18, 60), Vector3(-3.0, 9.0, -30))      # LEFT wall, normal +X

	_v = CharacterBody3D.new(); _v.set_script(load("res://scripts/vehicle/VehiclePhysics.gd")); _v.name = "Vehicle"
	var col := CollisionShape3D.new(); var cap := CapsuleShape3D.new(); cap.radius = 0.8; cap.height = 1.6; col.shape = cap
	_v.add_child(col)
	var vc = _child(_v, "VehicleController", Node, "res://scripts/vehicle/VehicleController.gd")
	_gs = _child(_v, "GravitySystem", Node3D, "res://scripts/vehicle/GravitySystem.gd")
	_wr = _child(_v, "WallRiding", Node, "res://scripts/vehicle/WallRiding.gd")
	_child(_v, "FlowSystem", Node, "res://scripts/systems/FlowSystem.gd")
	_child(_v, "WallSensor", Node, "res://scripts/vehicle/WallSensor.gd")
	_v.position = Vector3(0, 0.3, -2)
	world.add_child(_v)
	vc.set_physics_process(false)   # we drive apply_intent / detach ourselves
	print("=== Wall Jump Lateral+Float Probe ===")

func _physics_process(_dt: float) -> bool:
	match _phase:
		0:
			_v.global_position = Vector3(0, 0.3, -2)
			_v.velocity = Vector3(0, 0, -20)
			_gs.force_airborne()
			_phase = 1; _t = 0
		1:
			_t += 1
			if _t >= 2:
				_wr._try_attach_to_wall()
				_phase = 2; _t = 0
		2:
			_t += 1
			if _t >= 5:
				_assert_jump("A: realistic attach, neutral jump")
				_phase = 3; _t = 0
		3:
			# Phase B: simulate a car CLIMBING the wall — facing tilted UP the wall, big upward
			# velocity. This is the case the float fix targets (steering up the wall tilts forward).
			var up_axis := Vector3(1, 0, 0)                       # wall normal (up while attached)
			var fwd := Vector3(0.0, 0.7, -0.7).normalized()      # facing up-and-along the wall
			var right := fwd.cross(up_axis).normalized()
			var true_fwd := up_axis.cross(right).normalized()
			var basis := Basis(right, up_axis, -true_fwd).orthonormalized()
			_v.global_transform = Transform3D(basis, Vector3(-1.5, 6, -10))
			_v.velocity = true_fwd * 20.0                        # climbing up-the-wall at 20 m/s
			_gs.request_wall_attach(Vector3(1, 0, 0))            # WALL state, normal +X
			_wr._is_wall_riding = true
			var pre_up: float = _v.velocity.y
			_assert_jump("B: climbing jump-off (pre vy=%.1f)" % pre_up, pre_up)
			print("=== %s (%d failure%s) ===" % ["PASS" if _fails == 0 else "FAIL", _fails, "" if _fails == 1 else "s"])
			return true
	return false

func _assert_jump(label: String, pre_up: float = 0.0) -> void:
	var wall_normal: Vector3 = _gs.get_surface_normal()
	_wr.try_wall_detach(0.0, 0.0, 0.0)                           # NEUTRAL steer
	var v: Vector3 = _v.velocity
	var total: float = v.length()
	var lateral: float = absf(v.dot(wall_normal))               # off-wall (sideways)
	var horizontal: float = Vector2(v.x, v.z).length()          # ground-plane speed
	var vertical: float = absf(v.y)                             # the "hover" component
	var ratio: float = lateral / total if total > 0.001 else 0.0
	var up_force: float = _wr.wall_jump_up_force

	print("  [%s] vel=(%5.1f,%5.1f,%5.1f) |v|=%5.1f  lateral=%.1f horiz=%.1f vert=%.1f (up_force=%.1f)" % [
		label, v.x, v.y, v.z, total, lateral, horizontal, vertical, up_force])

	_check("%s: low sideways (lateral/total %.2f < %.2f)" % [label, ratio, LATERAL_RATIO_MAX], ratio < LATERAL_RATIO_MAX)
	_check("%s: not floaty (vertical %.1f <= up_force+3)" % [label, vertical], vertical <= up_force + 3.0)
	_check("%s: flows horizontal (horiz %.1f > vert %.1f)" % [label, horizontal, vertical], horizontal > vertical)
	_check("%s: speed preserved (|v| %.1f > 8)" % [label, total], total > 8.0)
	if pre_up > 0.0:
		_check("%s: scenario was climbing (pre vy %.1f > 8)" % [label, pre_up], pre_up > 8.0)

func _check(label: String, cond: bool) -> void:
	if not cond:
		_fails += 1
		print("  FAIL: %s" % label)
	else:
		print("  ok  : %s" % label)

func _box(parent: Node, size: Vector3, pos: Vector3) -> void:
	var b := StaticBody3D.new(); b.position = pos
	var s := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = size; s.shape = bx
	b.add_child(s); parent.add_child(b)

func _child(parent: Node, n: String, base, path: String):
	var node = base.new(); node.set_script(load(path)); node.name = n
	parent.add_child(node); return node
