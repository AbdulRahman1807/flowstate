extends SceneTree

# Guards CircuitBuilder._real_loop at the size of LOOP #2 (R=16) with the REAL vehicle collision shape
# (fore-aft capsule). Companion to _LoopClearanceProbe, which guards LOOP #1 (R=13) the same way — so
# between them BOTH real loop sizes are covered with the real shape. Drives a grounded car into the
# real builder loop, jumps in onto the front, and asserts it still inverts and rides high over the top
# (the long collision nose doesn't catch on the way in / fail to establish inversion). Run:
# Godot --headless --path /Users/abdul/Desktop/flowstate/flowstate --script res://scripts/tests/_LoopEntryProbe.gd

const R := 16.0
const N := 60

var _v: CharacterBody3D
var _vc
var _gs
var _frame := 0
var _max_y := -999.0
var _did_invert := false
var _jumped := false


func _initialize() -> void:
	var world := Node3D.new(); root.add_child(world)
	_box(world, Vector3(60, 1, 240), Vector3(0, -0.5, -40))            # flat floor everywhere

	# The REAL builder loop at LOOP #2's size (R=16), origin, cursor facing -Z.
	var cb := Node3D.new()
	cb.set_script(load("res://scripts/tests/CircuitBuilder.gd"))
	world.add_child(cb)
	cb._build_materials()
	cb._real_loop(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)), R, N)

	_v = CharacterBody3D.new(); _v.set_script(load("res://scripts/vehicle/VehiclePhysics.gd")); _v.name = "Vehicle"
	var col := CollisionShape3D.new(); var cap := CapsuleShape3D.new(); cap.radius = 0.92; cap.height = 3.0; col.shape = cap
	col.transform = Transform3D(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0), Vector3.ZERO)   # real shape: capsule laid along Z (fore-aft) so the nose/tail are covered
	_v.add_child(col)
	_vc = _mk(_v, "VehicleController", Node, "res://scripts/vehicle/VehicleController.gd")
	_gs = _mk(_v, "GravitySystem", Node3D, "res://scripts/vehicle/GravitySystem.gd")
	_mk(_v, "WallRiding", Node, "res://scripts/vehicle/WallRiding.gd")
	_mk(_v, "FlowSystem", Node, "res://scripts/systems/FlowSystem.gd")
	_mk(_v, "WallSensor", Node, "res://scripts/vehicle/WallSensor.gd")
	world.add_child(_v)
	_v.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 34))
	print("=== Loop Entry Probe (REAL _real_loop, loop #2 size, grounded drive-in, R=%.0f) ===" % R)


func _physics_process(_dt: float) -> bool:
	_vc.set_physics_process(false)
	_frame += 1
	if _frame < 4:
		return false
	if _frame == 4:
		_v.set_vehicle_velocity(Vector3(0, 0, -34))

	var mi = load("res://scripts/vehicle/MovementIntent.gd").new()
	mi.accelerate = 1.0
	# Jump onto the front (both bottoms cut) so the exit can drive out UNDER the cut front — no re-loop.
	if not _jumped and int(_gs.get_state()) == 0 and _v.global_position.z <= 2.0:
		mi.jump = true
		_jumped = true
	_v.apply_intent(mi)
	_max_y = maxf(_max_y, _v.global_position.y)
	if int(_gs.get_state()) == 3:
		_did_invert = true

	if _frame % 8 == 0:
		var names = ["GROUNDED", "WALL_L", "WALL_R", "INVERTED", "AIRBORNE"]
		var p := _v.global_position
		print("  f%3d y=%5.1f z=%6.1f spd=%5.1f st=%s" % [_frame, p.y, p.z, _v.velocity.length(), names[int(_gs.get_state())]])

	if _frame >= 180:
		print("=> max_y=%.1f (top=%.0f)  inverted=%s  final z=%.1f y=%.1f spd=%.1f" % [
			_max_y, 2.0 * R, _did_invert, _v.global_position.z, _v.global_position.y, _v.velocity.length()])
		print("PASS" if (_did_invert and _max_y > R * 1.6) else "FAILED")
		print("=== done ===")
		return true
	return false


func _box(world: Node3D, size: Vector3, pos: Vector3) -> void:
	var b := StaticBody3D.new(); b.position = pos
	var s := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = size; s.shape = bx
	b.add_child(s); world.add_child(b)


func _mk(parent: Node, n: String, base, path: String):
	var node = base.new(); node.set_script(load(path)); node.name = n
	parent.add_child(node); return node
