extends SceneTree

# Guards CircuitBuilder._real_loop after the ASYMMETRIC back-cut (014 anti-scrape fix):
# the descending-back slabs are cut higher (loop_back_cut) so they don't hang over the approach
# lane, while the FRONT entry cut (loop_front_cut) is unchanged. This probe drives the REAL
# builder loop (not an inline copy) and asserts:
#   (1) a grounded car can drive the approach to the loop base WITHOUT scraping (no early speed
#       loss / no airborne-clip before the jump), and
#   (2) after jumping in it still inverts and rides over the top (loop is not broken by the cut).
# Run:
# Godot --headless --path /Users/abdul/Desktop/flowstate/flowstate --script res://scripts/tests/_LoopClearanceProbe.gd

const R := 13.0
const N := 56

var _v: CharacterBody3D
var _vc
var _gs
var _frame := 0
var _max_y := -999.0
var _did_invert := false
var _jumped := false
var _min_speed_pre_jump := 999.0


func _initialize() -> void:
	var world := Node3D.new(); root.add_child(world)
	# Flat floor: approach (+Z behind base) + run-through (-Z), top at y=0.
	_box(world, Vector3(60, 1, 240), Vector3(0, -0.5, -40))

	# The REAL builder loop at the origin (cursor facing -Z, base on the floor).
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
	print("=== Loop Clearance Probe (real _real_loop, asymmetric back-cut, R=%.0f) ===" % R)


func _physics_process(_dt: float) -> bool:
	_vc.set_physics_process(false)
	_frame += 1
	if _frame < 4:
		return false
	if _frame == 4:
		_v.set_vehicle_velocity(Vector3(0, 0, -34))

	var mi = load("res://scripts/vehicle/MovementIntent.gd").new()
	mi.accelerate = 1.0
	# Track the lowest speed while still on the approach (z > 2): a scrape on the descending-back
	# slabs would bleed speed here BEFORE the jump. With the back cut clear, speed stays high.
	if _v.global_position.z > 2.0 and not _jumped:
		_min_speed_pre_jump = minf(_min_speed_pre_jump, _v.velocity.length())
	# Jump onto the front above the cut once at the base.
	if not _jumped and int(_gs.get_state()) == 0 and _v.global_position.z <= 2.0:
		mi.jump = true
		_jumped = true
	_v.apply_intent(mi)
	_max_y = maxf(_max_y, _v.global_position.y)
	if int(_gs.get_state()) == 3:
		_did_invert = true

	if _frame >= 180:
		var clean_approach := _min_speed_pre_jump > 30.0   # 34 entry; a scrape would drop this well below
		print("=> min_speed_pre_jump=%.1f (entry 34)  max_y=%.1f (top=%.0f)  inverted=%s" % [
			_min_speed_pre_jump, _max_y, 2.0 * R, _did_invert])
		var ok: bool = clean_approach and _did_invert and _max_y > R * 1.6
		print("  ok " if clean_approach else "FAIL", ": approach not scraped (speed held)")
		print("  ok " if _did_invert else "FAIL", ": still inverts (loop not broken by the cut)")
		print("  ok " if _max_y > R * 1.6 else "FAIL", ": rode high over the top (max_y %.1f)" % _max_y)
		print("PASS" if ok else "FAILED")
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
