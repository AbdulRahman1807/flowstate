extends SceneTree

# Verifies directional wall jump-off on a LEFT wall (normal +X, so D=away, A=into).
# For each held-input case it re-attaches, jumps, and logs the launch velocity.
# Expected: D -> big +X (far right); A -> small +X (barely off); W -> bigger -Z (forward);
# S -> reduced magnitude.
# Run: Godot --headless --script res://scripts/tests/_WallJumpDirProbe.gd

var _v: CharacterBody3D
var _gs
var _wr
var _trial := 0
var _phase := 0
var _t := 0
# [steer, accel, brake, label]
var _cases := [[-1.0, 0.0, 0.0, "D (away) "], [1.0, 0.0, 0.0, "A (into) "], [0.0, 1.0, 0.0, "W (fwd)  "], [0.0, 0.0, 1.0, "S (brake)"]]

func _initialize() -> void:
	var world := Node3D.new(); root.add_child(world)
	_box(world, Vector3(200, 1, 200), Vector3(0, -0.65, -40))     # flush floor
	_box(world, Vector3(1, 18, 60), Vector3(-3.0, 9.0, -30))      # LEFT wall, normal +X

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
	print("=== Wall Jump Direction Probe (LEFT wall: D=away, A=into) ===")

func _physics_process(_dt: float) -> bool:
	match _phase:
		0:
			if _trial >= _cases.size():
				print("=== done ===")
				return true
			_v.global_position = Vector3(0, 0.3, -2)
			_v.velocity = Vector3(0, 0, -20)
			_phase = 1; _t = 0
		1:
			_t += 1
			if _t >= 2:
				_wr._try_attach_to_wall()
				_phase = 2; _t = 0
		2:
			_t += 1
			if _t >= 5:
				var c = _cases[_trial]
				var st_ok: int = _gs.get_state()
				_wr.try_wall_detach(c[0], c[1], c[2])
				var v: Vector3 = _v.velocity
				print("%s  vel=(%5.1f,%5.1f,%5.1f)  |v|=%5.1f   (attached=%s)" % [c[3], v.x, v.y, v.z, v.length(), st_ok == 1])
				_trial += 1; _phase = 0
	return false

func _box(parent: Node, size: Vector3, pos: Vector3) -> void:
	var b := StaticBody3D.new(); b.position = pos
	var s := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = size; s.shape = bx
	b.add_child(s); parent.add_child(b)

func _child(parent: Node, n: String, base, path: String):
	var node = base.new(); node.set_script(load(path)); node.name = n
	parent.add_child(node); return node
