extends SceneTree

# M4 integration guard: loads the REAL Track_Prototype scene and verifies the
# procedurally-built run markers wired up correctly and the finish is reachable
# (sits over the flush recovery floor), plus that all M4 systems are present.
# Run: Godot --headless --script res://scripts/tests/_M4SceneProbe.gd

# Recovery floor spans z in [-3100, +100] (centre -1500, length 3200).
const FLOOR_Z_MIN := -3100.0
const FLOOR_Z_MAX := 100.0

var _fails := 0
var _done := false


func _initialize() -> void:
	var scene = load("res://scenes/Track_Prototype.tscn").instantiate()
	root.add_child(scene)
	print("=== M4 Scene Probe ===")


func _physics_process(_dt: float) -> bool:
	if _done:
		return true
	_done = true

	var starts := get_nodes_in_group_safe("start_line")
	var finishes := get_nodes_in_group_safe("finish_line")
	var checkpoints := get_nodes_in_group_safe("checkpoints")

	_check("start line present", starts.size() == 1)
	_check("finish line present", finishes.size() == 1)
	_check("5 checkpoints present", checkpoints.size() == 5)

	# Checkpoint indices 0..4 all present via meta.
	var idxs := {}
	for c in checkpoints:
		idxs[int(c.get_meta("checkpoint_index", -1))] = true
	var have_all := true
	for i in range(5):
		if not idxs.has(i):
			have_all = false
	_check("checkpoint indices 0..4", have_all)

	# Finish reachable: on the recovery floor footprint, down-track from spawn.
	if finishes.size() == 1:
		var fz: float = finishes[0].global_position.z
		print("  finish z = %.1f" % fz)
		_check("finish over recovery floor", fz > FLOOR_Z_MIN and fz < FLOOR_Z_MAX)
		_check("finish is down-track", fz < 0.0)

	# M4 systems wired into the scene.
	var scene := root.get_node_or_null("Track_Prototype")
	_check("RunManager in scene", scene != null and scene.get_node_or_null("RunManager") != null)
	_check("ScoreSystem in scene", scene != null and scene.get_node_or_null("ScoreSystem") != null)
	_check("PlayHUD in scene", scene != null and scene.get_node_or_null("PlayHUD") != null)
	_check("Vehicle in scene", scene != null and scene.get_node_or_null("Vehicle") != null)

	print("=== %s (%d failure%s) ===" % ["PASS" if _fails == 0 else "FAIL", _fails, "" if _fails == 1 else "s"])
	return true


func get_nodes_in_group_safe(g: String) -> Array:
	return get_nodes_in_group(g)


func _check(label: String, cond: bool) -> void:
	if not cond:
		_fails += 1
		print("  FAIL: %s" % label)
	else:
		print("  ok  : %s" % label)
