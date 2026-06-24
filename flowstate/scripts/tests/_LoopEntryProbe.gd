extends SceneTree

# Can a GROUNDED car drive seamlessly into a loop if we CUT the descending-back slabs that hang low
# over the approach (the blocker)? The car drives in flat, up the front, over, around — the rest of
# the circle is intact, only the low back-bottom (which blocks entry) is omitted. Then we see where
# it exits so a catch deck can be placed. Run:
# Godot --headless --path /Users/abdul/Desktop/flowstate/flowstate --script res://scripts/tests/_LoopEntryProbe.gd

const R := 14.0
const N := 56
const LANE := 12.0

var _v: CharacterBody3D
var _vc
var _gs
var _frame := 0
var _max_y := -999.0
var _did_invert := false
var _jumped := false


func _initialize() -> void:
	var world := Node3D.new(); root.add_child(world)
	_box(world, Vector3(60, 1, 220), Vector3(0, -0.5, -30))            # flat floor everywhere
	_build_loop_cut(world, Vector3(0, 0, 0), R, N)                     # loop, back-bottom cut

	_v = CharacterBody3D.new(); _v.set_script(load("res://scripts/vehicle/VehiclePhysics.gd")); _v.name = "Vehicle"
	var col := CollisionShape3D.new(); var cap := CapsuleShape3D.new(); cap.radius = 0.8; cap.height = 1.6; col.shape = cap
	_v.add_child(col)
	_vc = _mk(_v, "VehicleController", Node, "res://scripts/vehicle/VehicleController.gd")
	_gs = _mk(_v, "GravitySystem", Node3D, "res://scripts/vehicle/GravitySystem.gd")
	_mk(_v, "WallRiding", Node, "res://scripts/vehicle/WallRiding.gd")
	_mk(_v, "FlowSystem", Node, "res://scripts/systems/FlowSystem.gd")
	_mk(_v, "WallSensor", Node, "res://scripts/vehicle/WallSensor.gd")
	world.add_child(_v)
	_v.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 34))
	print("=== Loop Entry Probe (back-bottom cut, grounded drive-in, R=%.0f) ===" % R)


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


# Pure loop minus the descending-back slabs that hang low over the approach (p.z>1 and p.y<3.0).
func _build_loop_cut(world: Node3D, base: Vector3, radius: float, segments: int) -> void:
	var centre := base + Vector3(0, radius, 0)
	for i in range(segments):
		var ang := TAU * float(i) / float(segments)
		var p := centre + Vector3(0, -cos(ang) * radius, -sin(ang) * radius)
		if p.y < 2.2:
			continue                                                   # cut BOTH bottoms: jump in onto the front, drive out under the cut front
		var inward := Vector3(0, cos(ang), sin(ang))
		var fwd := Vector3(0, sin(ang), -cos(ang))
		var basis := Basis(Vector3(1, 0, 0), inward, -fwd)
		var seg_len := TAU * radius / float(segments) + 0.6
		_box_basis(world, Vector3(LANE, 0.6, seg_len), p - inward * 0.3, basis)


func _box_basis(world: Node3D, size: Vector3, pos: Vector3, basis: Basis) -> void:
	var b := StaticBody3D.new(); b.transform = Transform3D(basis.orthonormalized(), pos)
	var s := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = size; s.shape = bx
	b.add_child(s); world.add_child(b)


func _box(world: Node3D, size: Vector3, pos: Vector3) -> void:
	var b := StaticBody3D.new(); b.position = pos
	var s := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = size; s.shape = bx
	b.add_child(s); world.add_child(b)


func _mk(parent: Node, n: String, base, path: String):
	var node = base.new(); node.set_script(load(path)); node.name = n
	parent.add_child(node); return node
