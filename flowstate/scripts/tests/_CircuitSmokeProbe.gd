extends SceneTree

# Smoke-tests the new Track_Circuit: it loads, has the run markers, auto-starts on throttle, the car
# drives the opening straight on solid deck (doesn't fall through), and crosses the first checkpoint.
# Drives the REAL input path via Input.action_press("accelerate"). Run:
# Godot --headless --path /Users/abdul/Desktop/flowstate/flowstate --script res://scripts/tests/_CircuitSmokeProbe.gd

var _scene: Node
var _rm
var _veh: Node3D
var _frame := 0
var _start_z := 0.0
var _min_y := 999.0
var _ok := true
var _checked_markers := false


func _initialize() -> void:
	_scene = (load("res://scenes/Track_Circuit.tscn") as PackedScene).instantiate()
	root.add_child(_scene)
	_rm = _scene.get_node("RunManager")
	_veh = _scene.get_node("Vehicle")
	_start_z = _veh.global_position.z
	Input.action_press("accelerate", 1.0)
	print("=== Circuit Smoke Probe ===")


func _physics_process(_dt: float) -> bool:
	_frame += 1
	if _frame < 4:
		return false

	if not _checked_markers:
		_checked_markers = true
		_check(get_nodes_in_group("start_line").size() == 1, "START gate present")
		_check(get_nodes_in_group("finish_line").size() == 1, "FINISH gate present")
		_check(get_nodes_in_group("checkpoints").size() >= 3, "checkpoints present (%d)" % get_nodes_in_group("checkpoints").size())

	_min_y = minf(_min_y, _veh.global_position.y)

	if _frame >= 220:        # ~3.6s of full throttle
		Input.action_release("accelerate")
		var travelled := _start_z - _veh.global_position.z
		_check(int(_rm.get_state()) == 1, "run auto-started (RUNNING) on throttle")
		_check(travelled > 50.0, "car drove the opening straight (travelled %.1f m)" % travelled)
		_check(_min_y > -3.0, "car stayed on solid deck — never fell through (min y %.2f)" % _min_y)
		_check(int(_rm.get_checkpoint_index()) >= 0, "crossed checkpoint 0 (index %d)" % int(_rm.get_checkpoint_index()))
		if _ok:
			print("PASS")
		else:
			print("FAILED")
		print("=== done ===")
		return true
	return false


func _check(cond: bool, msg: String) -> void:
	print("  %s : %s" % ["ok " if cond else "FAIL", msg])
	if not cond:
		_ok = false
