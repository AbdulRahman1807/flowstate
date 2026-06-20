extends SceneTree

# Verifies the landing-angle penalty (08_Movement_Feel_Targets.md) and that landing impact is
# reported to the camera (impact_velocity > 0 -> dip fires). A shallow landing keeps ~full
# horizontal speed; a normal flat jump loses a little; a steep dive loses a lot — per the angle
# curve. Before the fix, the penalty/impact read the post-rebuild (flattened) velocity, so impact
# was ~0 and steep landings were never penalized. Run:
#   Godot --headless --script res://scripts/tests/_GroundLandingProbe.gd

var _v: CharacterBody3D
var _gs
var _vc
var _impact := 0.0
var _approach_h := 0.0
var _was_air := true
var _did_jump := false
var _trial := 0
var _t := 0
var _need_setup := true

# label, start_pos, start_vel, is_jump
var _cases := [
	["SHALLOW land", Vector3(0, 4.0, 0), Vector3(0, -1, -22), false],
	["JUMP off flat", Vector3(0, 0.9, 0), Vector3(0, 0, -1), true],
	["STEEP dive", Vector3(0, 16.0, 0), Vector3(0, -19, -8), false],
]

func _initialize() -> void:
	var world := Node3D.new(); root.add_child(world)
	_box(world, Vector3(600, 1, 600), Vector3(0, -0.5, 0))   # floor top at y=0
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
	_v.landed.connect(func(iv: float): _impact = iv)
	print("=== Ground Landing Probe ===")

func _start() -> void:
	var c = _cases[_trial]
	_v.global_position = c[1]
	_v.velocity = c[2]
	_gs.force_airborne()
	_t = 0; _impact = 0.0; _approach_h = _h(c[2]); _was_air = true; _did_jump = false

func _h(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()

func _physics_process(_dt: float) -> bool:
	if _need_setup:
		_start(); _need_setup = false; return false
	var c = _cases[_trial]
	var is_jump: bool = c[3]
	var mi = load("res://scripts/vehicle/MovementIntent.gd").new()
	mi.accelerate = 1.0 if (is_jump and not _did_jump) else 0.0
	if is_jump and not _did_jump and _gs.get_state() != 4 and _t > 50:
		mi.jump = true; _did_jump = true
	_v.apply_intent(mi)
	_t += 1

	var air: bool = _gs.get_state() == 4
	if air:
		_approach_h = _h(_v.velocity)   # latest airborne horizontal = approach speed
	var ready: bool = (not is_jump) or _did_jump
	if _was_air and not air and ready:
		var landed_h := _h(_v.velocity)
		var ret := 100.0 * landed_h / maxf(_approach_h, 0.01)
		print("  %-13s approach_h=%5.1f  landed_h=%5.1f  retention=%3.0f%%  impact=%4.1f" % [c[0], _approach_h, landed_h, ret, _impact])
		_advance(); return _trial >= _cases.size()
	_was_air = air

	if _t > 300:
		print("  %-13s TIMEOUT (no landing)" % c[0]); _advance(); return _trial >= _cases.size()
	return false

func _advance() -> void:
	_trial += 1
	if _trial >= _cases.size():
		print("=== done ===")
	else:
		_start()

func _box(parent: Node, size: Vector3, pos: Vector3) -> void:
	var b := StaticBody3D.new(); b.position = pos
	var s := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = size; s.shape = bx
	b.add_child(s); parent.add_child(b)

func _child(parent: Node, n: String, base, path: String):
	var node = base.new(); node.set_script(load(path)); node.name = n
	parent.add_child(node); return node
