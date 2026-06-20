extends SceneTree

# Verifies brake/reverse: (A) holding brake from a stop builds reverse down to ~-max_reverse_speed
# (not stalled at the old ~10 from the dead middle branch), and (B) holding brake at high forward
# speed still decelerates (forward braking intact). Run:
#   Godot --headless --script res://scripts/tests/_ReverseProbe.gd

var _v: CharacterBody3D
var _gs
var _vc
var _t := 0
var _trial := 0
var _need_setup := true
# label, start_forward_speed
var _cases := [["reverse from stop", 0.0], ["brake from 40 fwd", 40.0]]

func _initialize() -> void:
	var world := Node3D.new(); root.add_child(world)
	var b := StaticBody3D.new(); b.position = Vector3(0, -0.5, 0)
	var s := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = Vector3(4000, 1, 4000); s.shape = bx
	b.add_child(s); world.add_child(b)
	_v = CharacterBody3D.new(); _v.set_script(load("res://scripts/vehicle/VehiclePhysics.gd")); _v.name = "Vehicle"
	var col := CollisionShape3D.new(); var cap := CapsuleShape3D.new(); cap.radius = 0.8; cap.height = 1.6; col.shape = cap
	_v.add_child(col)
	_vc = _child(_v, "VehicleController", Node, "res://scripts/vehicle/VehicleController.gd")
	_gs = _child(_v, "GravitySystem", Node3D, "res://scripts/vehicle/GravitySystem.gd")
	_child(_v, "WallRiding", Node, "res://scripts/vehicle/WallRiding.gd")
	_child(_v, "FlowSystem", Node, "res://scripts/systems/FlowSystem.gd")
	_child(_v, "WallSensor", Node, "res://scripts/vehicle/WallSensor.gd")
	world.add_child(_v)
	_vc.set_physics_process(false)
	print("=== Reverse Probe (max_reverse_speed=%.0f, reverse_engage=%.0f) ===" % [_v.max_reverse_speed, _v.reverse_engage_speed])

func _start() -> void:
	var c = _cases[_trial]
	_v.global_position = Vector3(0, 0.9, 0)
	_v.velocity = Vector3(0, 0, -float(c[1]))   # -Z is forward
	_gs.force_airborne()
	_t = 0

func _physics_process(_dt: float) -> bool:
	if _need_setup:
		_start(); _need_setup = false; return false
	var mi = load("res://scripts/vehicle/MovementIntent.gd").new()
	mi.brake = 1.0   # hold brake, no accelerate
	_v.apply_intent(mi)
	_t += 1
	if _t >= 180:
		var fwd: float = -_v.velocity.z   # +fwd / -reverse
		var c = _cases[_trial]
		print("  %-18s after 3s brake: signed_fwd_speed=%6.1f  reported=%.1f" % [c[0], fwd, _v.get_speed()])
		_trial += 1
		if _trial >= _cases.size():
			print("=== done ==="); return true
		_start(); return false
	return false

func _child(parent: Node, n: String, base, path: String):
	var node = base.new(); node.set_script(load(path)); node.name = n
	parent.add_child(node); return node
