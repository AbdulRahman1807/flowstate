extends SceneTree

# Headless probe: build a vehicle next to a wall, attach, and log GravitySystem state each
# frame to verify the wall ride is SUSTAINED (not killed one frame after attach).
# Run: Godot --headless --script res://scripts/tests/_WallStickProbe.gd

var _vehicle: CharacterBody3D
var _gs
var _wr
var _frame := 0
var _attached := false

func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)

	# Floor under the car
	_add_static_box(world, Vector3(40, 1, 40), Vector3(0, -1, 0))
	# Wall to the LEFT: +x face at x = -2.0, so 2.0 units from a car at x = 0 (within range)
	_add_static_box(world, Vector3(1, 20, 40), Vector3(-2.5, 8, 0))

	_vehicle = CharacterBody3D.new()
	_vehicle.set_script(load("res://scripts/vehicle/VehiclePhysics.gd"))
	_vehicle.name = "Vehicle"

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.8
	cap.height = 1.6
	col.shape = cap
	_vehicle.add_child(col)

	_add_child_with_script(_vehicle, "VehicleController", Node, "res://scripts/vehicle/VehicleController.gd")
	_gs = _add_child_with_script(_vehicle, "GravitySystem", Node3D, "res://scripts/vehicle/GravitySystem.gd")
	_wr = _add_child_with_script(_vehicle, "WallRiding", Node, "res://scripts/vehicle/WallRiding.gd")
	_add_child_with_script(_vehicle, "FlowSystem", Node, "res://scripts/systems/FlowSystem.gd")
	_add_child_with_script(_vehicle, "WallSensor", Node, "res://scripts/vehicle/WallSensor.gd")

	_vehicle.position = Vector3(0, 0.3, 0)
	world.add_child(_vehicle)

	print("=== Wall Stick Probe ===")

func _physics_process(_delta: float) -> bool:
	_frame += 1

	# Let physics settle, then attach at frame 8 by driving forward and calling the real attach path.
	if _frame == 8:
		_vehicle.velocity = Vector3(0, 0, -20)
		var ok: bool = _wr._try_attach_to_wall()
		_attached = true
		print("frame %d: attach result = %s" % [_frame, ok])

	if _attached and _frame >= 8 and _frame <= 40:
		var state_names = ["GROUNDED", "WALL_LEFT", "WALL_RIGHT", "INVERTED", "AIRBORNE"]
		var g = _gs.get_gravity_vector()
		print("frame %2d: state=%-10s gravity=(%5.1f,%5.1f,%5.1f) riding=%s speed=%.1f" % [
			_frame, state_names[_gs.get_state()], g.x, g.y, g.z, _wr.is_wall_riding(), _vehicle.velocity.length()
		])

	if _frame > 42:
		print("=== done ===")
		return true
	return false

func _add_static_box(parent: Node, size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)

func _add_child_with_script(parent: Node, n: String, base_type, script_path: String):
	var node = base_type.new()
	node.set_script(load(script_path))
	node.name = n
	parent.add_child(node)
	return node
