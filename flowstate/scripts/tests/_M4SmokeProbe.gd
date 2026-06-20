extends SceneTree

# M4 live smoke test: loads the REAL Track_Prototype and lets every system run
# together for ~2.5 s while "holding throttle". Verifies the integrated loop:
# auto-start fires, the car drives, the timer runs, and the score climbs — with
# no runtime errors. (Feel/full-run completion is the developer's drive-test.)
# Run: Godot --headless --script res://scripts/tests/_M4SmokeProbe.gd

var _fails := 0
var _frame := 0
var _scene: Node


func _initialize() -> void:
	_scene = load("res://scenes/Track_Prototype.tscn").instantiate()
	root.add_child(_scene)
	print("=== M4 Smoke Probe ===")


func _physics_process(_dt: float) -> bool:
	_frame += 1
	if _frame == 2:
		Input.action_press("accelerate", 1.0)   # hold throttle (stays pressed until released)
	if _frame < 160:
		return false

	Input.action_release("accelerate")

	var run := _scene.get_node_or_null("RunManager")
	var score := _scene.get_node_or_null("ScoreSystem")
	var vehicle := _scene.get_node_or_null("Vehicle")

	_check("run auto-started", run != null and run.get_state() == RunManager.RunState.RUNNING)
	_check("timer running", run != null and run.get_time() > 0.5)
	_check("score climbing", score != null and score.get_score() > 0.0)
	_check("vehicle drove forward", vehicle != null and vehicle.global_position.z < 5.0)
	if vehicle != null and score != null and run != null:
		print("  z=%.1f  speed=%.1f  score=%.0f  time=%.2f" % [
			vehicle.global_position.z, vehicle.get_speed(), score.get_score(), run.get_time()])

	print("=== %s (%d failure%s) ===" % ["PASS" if _fails == 0 else "FAIL", _fails, "" if _fails == 1 else "s"])
	return true


func _check(label: String, cond: bool) -> void:
	if not cond:
		_fails += 1
		print("  FAIL: %s" % label)
	else:
		print("  ok  : %s" % label)
