extends SceneTree

# Verifies the CLIMBING SPIRAL (CircuitBuilder._helix_arc) is drivable: a car driven into it climbs
# real height and keeps moving — it does NOT stall at the bottom the way a true inverting loop does
# (a full inverting loop-de-loop is not drivable from a ground approach with the current physics; see
# the project memory note). Guards the "loops are drivable climbing spirals" decision.
# Run: Godot --headless --path /Users/abdul/Desktop/Personal/flowstate/flowstate --script res://scripts/tests/_SpiralLoopProbe.gd

const RADIUS := 28.0
const RISE := 16.0
const TURN := 360.0
const DIR := -1
const LANE := 12.0

var _v: CharacterBody3D
var _vc
var _frame := 0
var _max_y := -999.0
var _ok := true


func _initialize() -> void:
	var world := Node3D.new(); root.add_child(world)
	_box(world, Vector3(500, 1, 500), Vector3(0, -3.5, -60))
	_box(world, Vector3(LANE, 1, 30), Vector3(0, -0.5, 15))
	_build_helix(world, Transform3D(Basis.IDENTITY, Vector3.ZERO), RADIUS, RISE, TURN, DIR)

	_v = CharacterBody3D.new(); _v.set_script(load("res://scripts/vehicle/VehiclePhysics.gd")); _v.name = "Vehicle"
	var col := CollisionShape3D.new(); var cap := CapsuleShape3D.new(); cap.radius = 0.8; cap.height = 1.6; col.shape = cap
	_v.add_child(col)
	_vc = _mk(_v, "VehicleController", Node, "res://scripts/vehicle/VehicleController.gd")
	_mk(_v, "GravitySystem", Node3D, "res://scripts/vehicle/GravitySystem.gd")
	_mk(_v, "WallRiding", Node, "res://scripts/vehicle/WallRiding.gd")
	_mk(_v, "FlowSystem", Node, "res://scripts/systems/FlowSystem.gd")
	_mk(_v, "WallSensor", Node, "res://scripts/vehicle/WallSensor.gd")
	world.add_child(_v)
	_v.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 24))
	print("=== Climbing Spiral Probe (R=%.0f rise=%.0f) ===" % [RADIUS, RISE])


func _physics_process(_dt: float) -> bool:
	_vc.set_physics_process(false)
	_frame += 1
	if _frame < 4:
		return false
	if _frame == 4:
		_v.set_vehicle_velocity(Vector3(0, 0, -30))

	var mi = load("res://scripts/vehicle/MovementIntent.gd").new()
	mi.accelerate = 1.0
	mi.steer = (0.6 * float(DIR)) if _v.global_position.z < 0.5 else 0.0
	_v.apply_intent(mi)
	_max_y = maxf(_max_y, _v.global_position.y)

	if _frame >= 220:
		_check(_max_y > 6.0, "car CLIMBED the spiral (max y %.1f) — did not stall at the bottom" % _max_y)
		if _ok:
			print("PASS")
		else:
			print("FAILED")
		print("=== done ===")
		return true
	return false


# Mirrors CircuitBuilder._helix_arc (deck + both-side walls).
func _build_helix(world: Node3D, cur: Transform3D, radius: float, rise: float, turn_deg: float, dir: int) -> void:
	var arclen := deg_to_rad(absf(turn_deg)) * radius
	var segs := maxi(4, int(ceil(arclen / 4.0)))
	var seg_len := arclen / float(segs)
	var step := deg_to_rad(turn_deg / float(segs)) * float(dir)
	var rise_per := rise / float(segs)
	var c := cur
	var pts := PackedVector3Array()
	var rights: Array[Vector3] = []
	for i in range(segs + 1):
		pts.append(c.origin)
		rights.append(c.basis.x)
		if i < segs:
			c.origin += (-c.basis.z) * seg_len + Vector3.UP * rise_per
			c.basis = c.basis.rotated(Vector3.UP, step)
	for i in range(segs):
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var fwd := (p1 - p0).normalized()
		var right := rights[i]
		var up := right.cross(fwd).normalized()
		if up.y < 0.0:
			up = -up
		var basis := Basis(right, up, -fwd)
		var seg_len2 := p0.distance_to(p1) + 0.8
		var mid := (p0 + p1) * 0.5
		_box_basis(world, Vector3(LANE, 1.0, seg_len2), mid - up * 0.5, basis)
		for s: float in [-1.0, 1.0]:
			_box_basis(world, Vector3(0.6, 3.0, seg_len2), mid + right * (s * (LANE * 0.5 + 0.3)) + up * 1.5, basis)


func _box_basis(world: Node3D, size: Vector3, pos: Vector3, basis: Basis) -> void:
	var b := StaticBody3D.new(); b.transform = Transform3D(basis.orthonormalized(), pos)
	var s := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = size; s.shape = bx
	b.add_child(s); world.add_child(b)


func _box(world: Node3D, size: Vector3, pos: Vector3) -> void:
	var b := StaticBody3D.new(); b.position = pos
	var s := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = size; s.shape = bx
	b.add_child(s); world.add_child(b)


func _check(cond: bool, msg: String) -> void:
	print("  %s : %s" % ["ok " if cond else "FAIL", msg])
	if not cond:
		_ok = false


func _mk(parent: Node, n: String, base, path: String):
	var node = base.new(); node.set_script(load(path)); node.name = n
	parent.add_child(node); return node
