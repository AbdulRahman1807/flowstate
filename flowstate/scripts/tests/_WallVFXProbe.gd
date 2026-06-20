extends SceneTree

# Verifies WallVFX consumes every movement-impact signal and the burst path runs error-free:
#   wall attach -> +1, wall jump -> +1 (de-duped: the detach that follows a jump must NOT add a
#   second pop), ground jump (VehiclePhysics.jumped) -> +1, land (VehiclePhysics.landed) -> +1.
# Run: Godot --headless --script res://scripts/tests/_WallVFXProbe.gd

var _v: CharacterBody3D
var _gs
var _wr
var _vfx
var _t := 0
var _attach_ok := false

func _initialize() -> void:
	var world := Node3D.new(); root.add_child(world)
	_box(world, Vector3(200, 1, 200), Vector3(0, -0.65, -40))   # floor
	_box(world, Vector3(1, 18, 60), Vector3(-3.0, 9.0, -30))    # LEFT wall, normal +X

	_v = CharacterBody3D.new(); _v.set_script(load("res://scripts/vehicle/VehiclePhysics.gd")); _v.name = "Vehicle"
	var col := CollisionShape3D.new(); var cap := CapsuleShape3D.new(); cap.radius = 0.8; cap.height = 1.6; col.shape = cap
	_v.add_child(col)
	_child(_v, "VehicleController", Node, "res://scripts/vehicle/VehicleController.gd")
	_gs = _child(_v, "GravitySystem", Node3D, "res://scripts/vehicle/GravitySystem.gd")
	_wr = _child(_v, "WallRiding", Node, "res://scripts/vehicle/WallRiding.gd")
	_child(_v, "FlowSystem", Node, "res://scripts/systems/FlowSystem.gd")
	_child(_v, "WallSensor", Node, "res://scripts/vehicle/WallSensor.gd")
	_vfx = _child(_v, "WallVFX", Node3D, "res://scripts/vehicle/WallVFX.gd")
	_v.position = Vector3(0, 0.3, -2)
	world.add_child(_v)
	print("=== WallVFX Probe ===")

func _physics_process(_dt: float) -> bool:
	_t += 1
	if _t == 2:
		_v.global_position = Vector3(0, 0.3, -2)
		_v.velocity = Vector3(0, 0, -20)
	elif _t == 4:
		_attach_ok = _wr._try_attach_to_wall()
		print("  attach=%s  bursts=%d (expect 1)" % [_attach_ok, _vfx.bursts_fired])
	elif _t == 12:
		_wr.try_wall_detach(0.0, 1.0, 0.0)   # wall jump (W) -> on_wall_jump + on_wall_detach
		print("  wall-jump  bursts=%d (expect 2 — detach de-duped)" % _vfx.bursts_fired)
	elif _t == 16:
		_v.jumped.emit(Vector3.UP)            # ground jump
		print("  ground-jump  bursts=%d (expect 3)" % _vfx.bursts_fired)
	elif _t == 18:
		_v.landed.emit(10.0)                  # land
		print("  land  bursts=%d (expect 4)" % _vfx.bursts_fired)
	elif _t >= 22:
		var ok: bool = _attach_ok and _vfx.bursts_fired == 4
		print("=> bursts_fired=%d  (attach+walljump+groundjump+land, jump de-duped)  PASS=%s" % [_vfx.bursts_fired, ok])
		print("=== done ===")
		return true
	return false

func _box(parent: Node, size: Vector3, pos: Vector3) -> void:
	var b := StaticBody3D.new(); b.position = pos
	var s := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = size; s.shape = bx
	b.add_child(s); parent.add_child(b)

func _child(parent: Node, n: String, base, path: String):
	var node = base.new(); node.set_script(load(path)); node.name = n
	parent.add_child(node); return node
