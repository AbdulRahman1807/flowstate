extends SceneTree

# Proves 005 Phase 1: a FAST car completes a vertical loop (GROUNDED -> INVERTED -> GROUNDED),
# a SLOW car peels off partway up (goes AIRBORNE before completing).
# Run: Godot --headless --script res://scripts/tests/_LoopProbe.gd

const R := 16.0
const N := 48
const Z_C := -30.0          # loop bottom z

var _v: CharacterBody3D
var _gs
var _vc
var _trial := 0
var _t := 0
var _accel := 1.0
var _did_invert := false
var _did_airborne := false
var _attached_once := false
var _max_y := -999.0
# [initial_speed, accelerate, label]
var _cases := [[22.0, 1.0, "FAST"], [6.0, 0.0, "SLOW"]]

func _initialize() -> void:
	var world := Node3D.new(); root.add_child(world)
	# Catch floor far below so a detached car doesn't fall forever.
	_box(world, Vector3(200, 1, 200), Vector3(0, -12.0, Z_C))
	# Vertical loop: tangent slabs around a circle in the Y-Z plane; car drives the inside.
	# (No approach floor — the loop's descending front would overhang it; car starts at the bottom.)
	for i in range(N):
		var ang := TAU * float(i) / float(N)
		var p := Vector3(0, R - R * cos(ang), Z_C - R * sin(ang))
		var inward := Vector3(0, cos(ang), sin(ang))      # surface normal (toward centre / car)
		var fwd := Vector3(0, sin(ang), -cos(ang))        # travel tangent
		var basis := Basis(Vector3(1, 0, 0), inward, -fwd)
		var seg_len := TAU * R / float(N) + 0.6
		var centre := p - inward * 0.3                     # sink slab so its inward face sits at p
		_box_basis(world, Vector3(14, 0.6, seg_len), centre, basis)

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
	print("=== Loop Probe (R=%.0f) ===" % R)

var _need_setup := true

func _start_trial() -> void:
	var c = _cases[_trial]
	_accel = c[1]
	_v.global_position = Vector3(0, 0.9, Z_C)        # at the loop bottom, tangent = -Z
	_v.velocity = Vector3(0, 0, -float(c[0]))
	_gs.force_airborne()
	_t = 0
	_did_invert = false
	_did_airborne = false
	_attached_once = false
	_max_y = -999.0

func _physics_process(_dt: float) -> bool:
	if _need_setup:
		_start_trial()
		_need_setup = false
		return false
	var names = ["GROUNDED", "WALL_LEFT", "WALL_RIGHT", "INVERTED", "AIRBORNE"]
	var mi = load("res://scripts/vehicle/MovementIntent.gd").new()
	mi.accelerate = _accel
	mi.steer = 0.0
	_v.apply_intent(mi)

	_t += 1
	var st: int = _gs.get_state()
	_max_y = maxf(_max_y, _v.global_position.y)
	if st != 4:
		_attached_once = true
	if st == 3:
		_did_invert = true
	if _attached_once and st == 4 and not _did_invert:
		_did_airborne = true   # detached before reaching the top
	if _t % 24 == 0:
		print("  %s f%3d  y=%5.1f  z=%6.1f  state=%-9s spd=%4.1f" % [_cases[_trial][2], _t, _v.global_position.y, _v.global_position.z, names[st], _v.velocity.length()])

	if _t >= 360:
		var c = _cases[_trial]
		print("=> %s: max_y=%.1f  reached_top(INVERTED)=%s  detached_before_top=%s" % [c[2], _max_y, _did_invert, _did_airborne])
		_trial += 1
		if _trial >= _cases.size():
			print("=== done ===")
			return true
		_start_trial()
	return false

func _box(parent: Node, size: Vector3, pos: Vector3) -> void:
	var b := StaticBody3D.new(); b.position = pos
	var s := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = size; s.shape = bx
	b.add_child(s); parent.add_child(b)

func _box_basis(parent: Node, size: Vector3, pos: Vector3, basis: Basis) -> void:
	var b := StaticBody3D.new(); b.transform = Transform3D(basis.orthonormalized(), pos)
	var s := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = size; s.shape = bx
	b.add_child(s); parent.add_child(b)

func _child(parent: Node, n: String, base, path: String):
	var node = base.new(); node.set_script(load(path)); node.name = n
	parent.add_child(node); return node
