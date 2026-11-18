extends SceneTree

# Headless guard for ComicPostFXDriver (016 Part B). Builds a real vehicle subtree
# + FlowSystem + ComicPostFX + the driver, then drives Flow / speed / boost by hand
# and asserts the driver pushes the right uniform overrides onto ComicPostFX:
#   - Flow ramps halftone (intensity + scale) and ink outline between min/max
#   - speed maps chromatic aberration idle->max, and speed lines off->on
#   - a boost activation spikes CA above the speed-mapped max
#   - enabled = false makes the driver inert (no writes)
#
# Nodes are built in _initialize() but TESTED in the first _physics_process() tick:
# during _initialize() the tree isn't live yet, so add_child defers tree-entry and
# the driver's _ready (which resolves its NodePaths) hasn't run. Paths are relative
# (no get_path, which would fail pre-tree).
# Run:
# Godot --headless --path /Users/abdul/Desktop/Personal/flowstate/flowstate --script res://scripts/tests/_ComicFXDriverProbe.gd

var _fx
var _drv
var _veh
var _flow
var _fail := 0
var _done := false


func _initialize() -> void:
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)

	# --- real vehicle subtree (frozen — we set _current_speed / _boost_active directly) ---
	_veh = CharacterBody3D.new()
	_veh.set_script(load("res://scripts/vehicle/VehiclePhysics.gd"))
	_veh.name = "Vehicle"
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new(); cap.radius = 0.92; cap.height = 3.0; col.shape = cap
	_veh.add_child(col)
	_mk(_veh, "VehicleController", Node, "res://scripts/vehicle/VehicleController.gd")
	_mk(_veh, "GravitySystem", Node3D, "res://scripts/vehicle/GravitySystem.gd")
	_mk(_veh, "WallRiding", Node, "res://scripts/vehicle/WallRiding.gd")
	_flow = _mk(_veh, "FlowSystem", Node, "res://scripts/systems/FlowSystem.gd")
	_mk(_veh, "WallSensor", Node, "res://scripts/vehicle/WallSensor.gd")
	world.add_child(_veh)

	# --- ComicPostFX + driver (relative paths; resolved in driver._ready once in-tree) ---
	_fx = ComicPostFX.new()
	_fx.name = "ComicPostFX"
	world.add_child(_fx)

	_drv = Node.new()
	_drv.set_script(load("res://scripts/fx/ComicPostFXDriver.gd"))
	_drv.name = "Driver"
	_drv.fx_path = NodePath("../ComicPostFX")
	_drv.vehicle_path = NodePath("../Vehicle")
	_drv.flow_system_path = NodePath("../Vehicle/FlowSystem")
	world.add_child(_drv)


func _physics_process(_delta: float) -> bool:
	if _done:
		return true
	_done = true

	# Freeze the engine's own ticking so only our manual pumps drive the systems.
	_veh.set_physics_process(false)
	_veh.set_process(false)
	_fx.set_process(false)
	_drv.set_process(false)
	_veh.max_speed = 50.0
	_veh._current_speed = 0.0
	_veh._boost_active = false

	print("=== ComicPostFXDriver Probe ===")

	# 1) Flow at 0 -> halftone/scale/outline settle to the min-flow anchors.
	_pump(50)
	_check("halftone @min flow", _fx.halftone_intensity, _drv.halftone_at_min_flow)
	_check("halftone_scale @min flow", _fx.halftone_scale, _drv.halftone_scale_at_min)
	_check("outline @min flow", _fx.outline_intensity, _drv.outline_at_min_flow)

	# 2) Flow at max -> ramps to the max-flow anchors.
	_flow.increase(_flow.max_flow, "probe")
	_pump(50)
	_check("halftone @max flow", _fx.halftone_intensity, _drv.halftone_at_max_flow)
	_check("halftone_scale @max flow", _fx.halftone_scale, _drv.halftone_scale_at_max)
	_check("outline @max flow", _fx.outline_intensity, _drv.outline_at_max_flow)

	# 3) Speed at max -> CA near aberration_max, speed lines on.
	_veh._current_speed = _veh.max_speed
	_pump(50)
	_check("CA @top speed", _fx.aberration_intensity, _drv.aberration_max, 0.03)
	_assert("speed lines on @top speed", _fx.speed_lines_intensity > 0.1)

	# 4) Speed at 0 -> CA back to idle, speed lines off.
	_veh._current_speed = 0.0
	_pump(50)
	_check("CA @rest", _fx.aberration_intensity, _drv.aberration_idle, 0.03)
	_assert("speed lines off @rest", _fx.speed_lines_intensity < 0.001)

	# 5) Boost activation spikes CA above the speed-mapped max (speed still 0).
	_veh._boost_active = true
	_drv._process(0.1)   # one frame after the false->true transition
	_assert("boost spikes CA above max", _fx.aberration_intensity > _drv.aberration_max)

	# 6) enabled = false -> driver writes nothing.
	_veh._boost_active = false
	_drv.enabled = false
	_fx.halftone_intensity = 0.999
	_pump(5)
	_assert("disabled driver is inert", is_equal_approx(_fx.halftone_intensity, 0.999))

	if _fail == 0:
		print("RESULT: PASS (all checks green)")
	else:
		print("RESULT: FAIL (%d checks failed)" % _fail)
	return true


func _pump(n: int) -> void:
	for i in range(n):
		_drv._process(0.1)


func _check(label: String, got: float, want: float, tol: float = 0.01) -> void:
	var ok := absf(got - want) <= tol
	if not ok:
		_fail += 1
	print("  [%s] %s: got %.4f want %.4f (tol %.3f)" % ["OK" if ok else "XX", label, got, want, tol])


func _assert(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("  [%s] %s" % ["OK" if cond else "XX", label])


func _mk(parent: Node, n: String, type, path: String) -> Node:
	var node = type.new()
	node.name = n
	node.set_script(load(path))
	parent.add_child(node)
	return node
