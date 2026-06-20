extends SceneTree

# Guards the wall-jump-off bound after max_speed was raised to 50. Entering a wall at high speed
# must NOT produce a bigger launch: wall-ride velocity clamps to wall_ride_speed_cap (22), so the
# jump-off is the same bounded launch whether you entered at 20 or 50. Without the decoupling
# (cap tied to max_speed=50) the 50-entry launch is ~1.7x bigger and floaty. Run:
#   Godot --headless --script res://scripts/tests/_WallJumpCapProbe.gd

var _v: CharacterBody3D
var _gs
var _wr
var _phase := 0
var _t := 0
var _trial := 0
var _ride_speed_seen := 0.0
var _results := {}
var _cases := [20.0, 50.0]   # entry speeds

func _initialize() -> void:
	var world := Node3D.new(); root.add_child(world)
	_box(world, Vector3(200, 1, 200), Vector3(0, -0.65, -40))
	_box(world, Vector3(1, 18, 60), Vector3(-3.0, 9.0, -30))   # LEFT wall, normal +X
	_v = CharacterBody3D.new(); _v.set_script(load("res://scripts/vehicle/VehiclePhysics.gd")); _v.name = "Vehicle"
	var col := CollisionShape3D.new(); var cap := CapsuleShape3D.new(); cap.radius = 0.8; cap.height = 1.6; col.shape = cap
	_v.add_child(col)
	_child(_v, "VehicleController", Node, "res://scripts/vehicle/VehicleController.gd")
	_gs = _child(_v, "GravitySystem", Node3D, "res://scripts/vehicle/GravitySystem.gd")
	_wr = _child(_v, "WallRiding", Node, "res://scripts/vehicle/WallRiding.gd")
	_child(_v, "FlowSystem", Node, "res://scripts/systems/FlowSystem.gd")
	_child(_v, "WallSensor", Node, "res://scripts/vehicle/WallSensor.gd")
	_v.position = Vector3(0, 0.3, -2)
	world.add_child(_v)
	print("=== Wall Jump Cap Probe (max_speed=%.0f, wall_ride_speed_cap=%.0f) ===" % [_v.max_speed, _v.wall_ride_speed_cap])

func _physics_process(_dt: float) -> bool:
	match _phase:
		0:
			if _trial >= _cases.size():
				_verdict()
				return true
			_v.global_position = Vector3(0, 0.3, -2)
			_v.velocity = Vector3(0, 0, -_cases[_trial])
			_gs.force_airborne()
			_ride_speed_seen = 0.0
			_phase = 1; _t = 0
		1:
			_t += 1
			if _t >= 2:
				_wr._try_attach_to_wall()
				_phase = 2; _t = 0
		2:
			_t += 1
			_ride_speed_seen = maxf(_ride_speed_seen, _v.velocity.length())
			if _t >= 8:
				_wr.try_wall_detach(0.0, 0.0, 0.0)   # neutral jump-off
				_results[_cases[_trial]] = [_ride_speed_seen, _v.velocity.length()]
				print("  entry=%4.1f  peak_ride_speed=%5.1f  jumpoff|v|=%5.1f" % [_cases[_trial], _ride_speed_seen, _v.velocity.length()])
				_trial += 1; _phase = 0
	return false

func _verdict() -> void:
	var slow = _results[20.0]
	var fast = _results[50.0]
	# Fast entry must be clamped on the wall, and its jump-off must be ~the same bounded launch.
	var ride_clamped: bool = fast[0] <= _v.wall_ride_speed_cap + 2.0
	var jumpoff_bounded: bool = absf(fast[1] - slow[1]) <= 3.0
	print("=> ride_clamped(50->~22)=%s  jumpoff_bounded(50≈20)=%s  PASS=%s" % [ride_clamped, jumpoff_bounded, ride_clamped and jumpoff_bounded])
	print("=== done ===")

func _box(parent: Node, size: Vector3, pos: Vector3) -> void:
	var b := StaticBody3D.new(); b.position = pos
	var s := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = size; s.shape = bx
	b.add_child(s); parent.add_child(b)

func _child(parent: Node, n: String, base, path: String):
	var node = base.new(); node.set_script(load(path)); node.name = n
	parent.add_child(node); return node
