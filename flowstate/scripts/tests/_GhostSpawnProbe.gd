extends SceneTree

# Validates the ghost spawns correctly in the REAL Track_Prototype scene (the runtime duplicate():
# camera/VFX stripped, collision neutralised, controller replaying) and simulates without error.
# Drives the RunManager state machine directly: begin -> record a few frames -> finish (captures a
# best) -> restart (spawns the ghost of that best). Run:
# Godot --headless --path /Users/abdul/Desktop/Personal/flowstate/flowstate --script res://scripts/tests/_GhostSpawnProbe.gd

var _scene: Node
var _rm
var _frame := 0
var _phase := 0
var _ok := true


func _initialize() -> void:
	_scene = (load("res://scenes/Track_Prototype.tscn") as PackedScene).instantiate()
	root.add_child(_scene)
	_rm = _scene.get_node("RunManager")
	print("=== Ghost Spawn Probe (real Track_Prototype) ===")


func _physics_process(_dt: float) -> bool:
	_frame += 1
	if _frame < 5:
		return false            # let RunManager._ready + deferred marker wiring settle

	match _phase:
		0:
			_rm._begin_run()
			_check(int(_rm.get_state()) == 1, "run RUNNING after begin")
			_phase = 1
		1, 2, 3, 4, 5, 6, 7, 8:
			_phase += 1            # ~8 frames: the player controller records (neutral) input frames
		9:
			_rm._finish_run()
			_check(_rm.has_best(), "has_best after first finish")
			_check(_rm.was_last_run_best(), "first finish is a NEW best")
			_phase = 10
		10:
			_rm._restart()
			var ghost := _scene.get_node_or_null("GhostVehicle")
			_check(ghost != null, "GhostVehicle spawned on restart")
			if ghost != null:
				var gc = ghost.get_node_or_null("VehicleController")
				_check(gc != null and gc.is_replaying(), "ghost controller is replaying")
				_check(ghost.get_node_or_null("Camera3D") == null, "ghost Camera3D stripped (no view steal)")
				_check(ghost.get_node_or_null("WallVFX") == null, "ghost WallVFX stripped")
				_check(int(ghost.collision_layer) == 0, "ghost collision_layer = 0 (invisible to player + Areas)")
			_phase = 11
		11, 12:
			_phase += 1            # let the ghost simulate a couple frames (crash check)
		13:
			var ghost := _scene.get_node_or_null("GhostVehicle")
			_check(ghost != null and is_instance_valid(ghost), "ghost still alive after simulating frames")
			_finish()
			return true
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
