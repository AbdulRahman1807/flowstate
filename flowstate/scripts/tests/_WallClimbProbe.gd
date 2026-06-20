extends SceneTree

# Headless probe for the vertical-wall-ride -> top-platform scenario.
# Builds: flush floor (y=0), a tall wall (y 0..18), a top platform (top y=17),
# spawns the vehicle at the base, attaches it to the wall at speed, and logs
# height + state each frame to confirm it CLIMBS and lands on the platform.
# Run: Godot --headless --script res://scripts/tests/_WallClimbProbe.gd

var _v: CharacterBody3D
var _gs
var _wr
var _frame := 0
var _max_y := -999.0
var _reached_platform := false

func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)

	_box(world, Vector3(200, 1, 200), Vector3(0, -0.65, -40))                 # flush floor, top y=-0.15
	_box(world, Vector3(1, 18, 60), Vector3(-3.0, 9.0, -30))                  # climb wall: inner face x=-2.5, y 0..18, z 0..-60
	# Top platform set BACK past the crest (near edge z=-24, no climb overhang),
	# at wall-top height (top y=18) so the car arcs up off the top and descends
	# back onto it. Long in -Z to catch the arc.
	_box(world, Vector3(18, 1, 50), Vector3(-1.0, 17.5, -49))                 # platform top y=18, z -24..-74

	_v = CharacterBody3D.new()
	_v.set_script(load("res://scripts/vehicle/VehiclePhysics.gd"))
	_v.name = "Vehicle"
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new(); cap.radius = 0.8; cap.height = 1.6
	col.shape = cap
	_v.add_child(col)
	_child(_v, "VehicleController", Node, "res://scripts/vehicle/VehicleController.gd")
	_gs = _child(_v, "GravitySystem", Node3D, "res://scripts/vehicle/GravitySystem.gd")
	_wr = _child(_v, "WallRiding", Node, "res://scripts/vehicle/WallRiding.gd")
	_child(_v, "FlowSystem", Node, "res://scripts/systems/FlowSystem.gd")
	_child(_v, "WallSensor", Node, "res://scripts/vehicle/WallSensor.gd")
	_v.position = Vector3(0, 0.3, -2)
	world.add_child(_v)

	print("=== Wall Climb Probe (expect Y to rise toward ~17 and land GROUNDED on platform) ===")

func _physics_process(_dt: float) -> bool:
	_frame += 1
	if _frame == 8:
		_v.velocity = Vector3(0, 0, -20)
		print("attach result = %s" % _wr._try_attach_to_wall())

	if _frame >= 8:
		_max_y = maxf(_max_y, _v.global_position.y)
		var names = ["GROUNDED", "WALL_LEFT", "WALL_RIGHT", "INVERTED", "AIRBORNE"]
		if _v.global_position.y >= 14.0 and _gs.get_state() == 0:
			_reached_platform = true
		if _frame % 8 == 0:
			print("f%3d  y=%5.1f  state=%-9s speed=%4.1f" % [_frame, _v.global_position.y, names[_gs.get_state()], _v.velocity.length()])

	if _frame > 260:
		print("=== max_y reached = %.1f | landed on platform (GROUNDED, y>=14) = %s ===" % [_max_y, _reached_platform])
		return true
	return false

func _box(parent: Node, size: Vector3, pos: Vector3) -> void:
	var b := StaticBody3D.new(); b.position = pos
	var s := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = size; s.shape = bx
	b.add_child(s); parent.add_child(b)

func _child(parent: Node, n: String, base, path: String):
	var node = base.new(); node.set_script(load(path)); node.name = n
	parent.add_child(node); return node
