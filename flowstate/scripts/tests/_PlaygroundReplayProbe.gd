extends SceneTree

# Validates the FREE-ROAM replay path on the real Test_Playground scene: it has no finish line,
# so the ghost must come from your LAST run captured on restart (RunManager._restart) — drive,
# press R, race the ghost of the run you just drove. Asserts a RunManager is wired into the
# playground and that restarting (without a finish) spawns a replaying ghost.
# Run: Godot --headless --path /Users/abdul/Desktop/Personal/flowstate/flowstate --script res://scripts/tests/_PlaygroundReplayProbe.gd

var _scene: Node
var _rm
var _frame := 0
var _phase := 0
var _ok := true


func _initialize() -> void:
	_scene = (load("res://scenes/tests/Test_Playground.tscn") as PackedScene).instantiate()
	root.add_child(_scene)
	_rm = _scene.get_node_or_null("RunManager")
	print("=== Playground Replay Probe (free-roam, no finish line) ===")


func _physics_process(_dt: float) -> bool:
	_frame += 1
	if _frame < 5:
		return false

	match _phase:
		0:
			_check(_rm != null, "RunManager wired into Test_Playground")
			if _rm == null:
				_finish(); return true
			_rm._begin_run()
			_check(int(_rm.get_state()) == 1, "run RUNNING after begin")
			_phase = 1
		1, 2, 3, 4, 5, 6, 7, 8:
			_phase += 1            # player controller records (neutral) input frames
		9:
			# Restart WITHOUT a finish -> captures the just-driven run and races its ghost.
			_rm._restart()
			var ghost := _scene.get_node_or_null("GhostVehicle")
			_check(ghost != null, "ghost spawned on restart (no finish line needed)")
			if ghost != null:
				var gc = ghost.get_node_or_null("VehicleController")
				_check(gc != null and gc.is_replaying(), "ghost is replaying your last run")
			_phase = 10
		10, 11:
			_phase += 1            # let the ghost simulate (crash check)
		12:
			var ghost := _scene.get_node_or_null("GhostVehicle")
			_check(ghost != null and is_instance_valid(ghost), "ghost still alive after simulating")
			_finish(); return true
	return false


func _finish() -> void:
	if _ok:
		print("PASS")
	else:
		print("FAILED")
	print("=== done ===")


func _check(cond: bool, msg: String) -> void:
	print("  %s : %s" % ["ok " if cond else "FAIL", msg])
	if not cond:
		_ok = false
