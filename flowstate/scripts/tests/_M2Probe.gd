extends SceneTree

# Verifies the M2 floor->wall->ceiling showcase (M2TransitionBuilder): a car driven forward from
# the spawn follows the smooth half-loop GROUNDED -> up the wall -> INVERTED on the ceiling, and
# holds inverted (does not peel off). Run:
#   Godot --headless --script res://scripts/tests/_M2Probe.gd

var _v: CharacterBody3D
var _gs
var _vc
var _t := 0
var _reached_inverted := false
var _inverted_frames := 0
var _max_y := -999.0
var _landed_after_inverted := false
var _settled := false                       # true once it first rests on the approach floor
var _peeled_off_climb := false              # went airborne mid floor->wall->ceiling climb

func _initialize() -> void:
	var world := Node3D.new(); root.add_child(world)
	var builder := Node3D.new()
	builder.set_script(load("res://scripts/tests/M2TransitionBuilder.gd"))
	world.add_child(builder)   # builds the geometry in _ready

	_v = CharacterBody3D.new(); _v.set_script(load("res://scripts/vehicle/VehiclePhysics.gd")); _v.name = "Vehicle"
	var col := CollisionShape3D.new(); var cap := CapsuleShape3D.new(); cap.radius = 0.8; cap.height = 1.6; col.shape = cap
	_v.add_child(col)
	_vc = _child(_v, "VehicleController", Node, "res://scripts/vehicle/VehicleController.gd")
	_gs = _child(_v, "GravitySystem", Node3D, "res://scripts/vehicle/GravitySystem.gd")
	_child(_v, "WallRiding", Node, "res://scripts/vehicle/WallRiding.gd")
	_child(_v, "FlowSystem", Node, "res://scripts/systems/FlowSystem.gd")
	_child(_v, "WallSensor", Node, "res://scripts/vehicle/WallSensor.gd")
	_v.global_position = Vector3(0, 2, 16)
	world.add_child(_v)
	_vc.set_physics_process(false)
	print("=== M2 Probe (drive floor -> wall -> ceiling) ===")

func _physics_process(_dt: float) -> bool:
	var mi = load("res://scripts/vehicle/MovementIntent.gd").new()
	mi.accelerate = 1.0
	mi.steer = 0.0
	_v.apply_intent(mi)
	_t += 1

	var st: int = _gs.get_state()   # 0 GROUNDED,1 WL,2 WR,3 INVERTED,4 AIRBORNE
	_max_y = maxf(_max_y, _v.global_position.y)
	if st == 0:
		_settled = true   # rested on the approach floor (ignore the initial spawn-drop airborne)
	if st == 3:
		_reached_inverted = true
		_inverted_frames += 1
	# Peeling off the curve = going airborne AFTER settling but BEFORE reaching the ceiling.
	if _settled and not _reached_inverted and st == 4:
		_peeled_off_climb = true
	# Recovered after the inverted run: grounded again on the recovery floor.
	if _reached_inverted and st == 0 and _v.global_position.y < 5.0:
		_landed_after_inverted = true

	var names = ["GROUNDED", "WALL_L", "WALL_R", "INVERTED", "AIRBORNE"]
	if _t % 20 == 0:
		print("  f%3d  pos=(%.0f,%5.1f,%6.1f)  state=%-9s spd=%4.1f" % [_t, _v.global_position.x, _v.global_position.y, _v.global_position.z, names[st], _v.velocity.length()])

	if _t >= 300:
		var gate_ok: bool = _reached_inverted and _inverted_frames >= 20 and not _peeled_off_climb
		print("=> reached_inverted=%s  inverted_frames=%d  max_y=%.1f (ceiling=32)  followed_cleanly=%s" % [
			_reached_inverted, _inverted_frames, _max_y, not _peeled_off_climb])
		print("=> GATE(floor->wall->ceiling smooth)=%s   EXIT(lands on recovery floor)=%s" % [gate_ok, _landed_after_inverted])
		print("=== done ===")
		return true
	return false

func _child(parent: Node, n: String, base, path: String):
	var node = base.new(); node.set_script(load(path)); node.name = n
	parent.add_child(node); return node
