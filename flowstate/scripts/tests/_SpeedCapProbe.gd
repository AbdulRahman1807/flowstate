extends SceneTree

# Reproduces the speed-cap bug: holding accelerate on flat ground should settle at max_speed (22),
# but speed climbs far past it. Run:
#   Godot --headless --script res://scripts/tests/_SpeedCapProbe.gd

var _v: CharacterBody3D
var _gs
var _vc
var _t := 0

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
	_v.global_position = Vector3(0, 0.9, 0)
	_v.velocity = Vector3.ZERO
	print("=== Speed Cap Probe (max_speed=%.0f, NO boost, full throttle) ===" % _v.max_speed)

func _physics_process(_dt: float) -> bool:
	var mi = load("res://scripts/vehicle/MovementIntent.gd").new()
	mi.accelerate = 1.0   # hold W, never boost
	_v.apply_intent(mi)
	_t += 1
	if _t % 120 == 0:
		print("  t=%4.1fs  reported_speed=%6.1f  (cap=%.0f)" % [_t / 60.0, _v.get_speed(), _v.max_speed])
	if _t >= 720:
		var over: bool = _v.get_speed() > _v.max_speed + 1.0
		print("=> final reported_speed=%.1f  exceeds_cap=%s" % [_v.get_speed(), over])
		print("=== done ===")
		return true
	return false

func _child(parent: Node, n: String, base, path: String):
	var node = base.new(); node.set_script(load(path)); node.name = n
	parent.add_child(node); return node
