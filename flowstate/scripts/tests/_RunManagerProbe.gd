extends SceneTree

# Verifies the M4 run lifecycle (007_Run_Lifecycle.md):
#   READY -> (start line) -> RUNNING -> (finish line) -> FINISHED,
#   timer runs while RUNNING, checkpoints record the respawn point, falling off
#   respawns at the last checkpoint at reduced speed WITHOUT ending the run, and
#   restart resets to a fresh run.
# Run: Godot --headless --script res://scripts/tests/_RunManagerProbe.gd

var _fails := 0
var _done := false
var _vehicle           # CharacterBody3D w/ VehiclePhysics (untyped for dynamic script access)
var _flow
var _score
var _run

var _start_area: Area3D
var _cp_area: Area3D
var _finish_area: Area3D

var _started := 0
var _finished := 0
var _finish_score := -1.0
var _finish_time := -1.0
var _cp_seen := -1
var _respawned := 0

const SPAWN := Vector3(0, 2, 0)
const CP_POS := Vector3(0, 3, -40)


func _initialize() -> void:
	var world := Node3D.new(); root.add_child(world)

	_vehicle = CharacterBody3D.new()
	_vehicle.set_script(load("res://scripts/vehicle/VehiclePhysics.gd"))
	_vehicle.name = "Vehicle"
	var col := CollisionShape3D.new(); var cap := CapsuleShape3D.new()
	cap.radius = 0.8; cap.height = 1.6; col.shape = cap; _vehicle.add_child(col)
	_child(_vehicle, "VehicleController", Node, "res://scripts/vehicle/VehicleController.gd")
	_child(_vehicle, "GravitySystem", Node3D, "res://scripts/vehicle/GravitySystem.gd")
	_child(_vehicle, "WallRiding", Node, "res://scripts/vehicle/WallRiding.gd")
	_flow = _child(_vehicle, "FlowSystem", Node, "res://scripts/systems/FlowSystem.gd")
	_child(_vehicle, "WallSensor", Node, "res://scripts/vehicle/WallSensor.gd")
	_vehicle.position = SPAWN
	world.add_child(_vehicle)

	_score = Node.new()
	_score.set_script(load("res://scripts/systems/ScoreSystem.gd"))
	_score.name = "ScoreSystem"
	_score.vehicle_path = NodePath("../Vehicle")
	world.add_child(_score)

	# Markers (groups + checkpoint meta index), like TrackBuilder builds.
	_start_area = _area(world, Vector3(14, 8, 1), Vector3(0, 3, -5), "start_line", -1)
	_cp_area = _area(world, Vector3(14, 8, 1), CP_POS, "checkpoints", 0)
	_finish_area = _area(world, Vector3(14, 8, 1), Vector3(0, 3, -80), "finish_line", -1)

	_run = Node.new()
	_run.set_script(load("res://scripts/systems/RunManager.gd"))
	_run.name = "RunManager"
	_run.vehicle_path = NodePath("../Vehicle")
	_run.score_system_path = NodePath("../ScoreSystem")
	world.add_child(_run)            # _ready captures start xform + defers marker wiring

	_run.on_run_started.connect(_sig_started)
	_run.on_run_finished.connect(_sig_finished)
	_run.on_checkpoint.connect(_sig_checkpoint)
	_run.on_respawn.connect(_sig_respawn)

	# Drive manually for determinism.
	_vehicle.get_node("VehicleController").set_physics_process(false)
	_flow.set_physics_process(false)
	_score.set_physics_process(false)
	_run.set_physics_process(false)

	print("=== RunManager Probe ===")


func _physics_process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	_run._wire_markers()             # node is in-tree now; deferred copy (from _ready) is guard-safe
	_run_tests()
	print("=== %s (%d failure%s) ===" % ["PASS" if _fails == 0 else "FAIL", _fails, "" if _fails == 1 else "s"])
	return true


func _run_tests() -> void:
	_check("initial READY", _run.get_state() == RunManager.RunState.READY)

	# --- start via the start line ---
	_start_area.body_entered.emit(_vehicle)
	_check("start -> RUNNING", _run.get_state() == RunManager.RunState.RUNNING)
	_check("on_run_started fired once", _started == 1)
	_check("score running after start", _score.is_running())

	# --- timer ticks while RUNNING ---
	for i in range(3):
		_run._physics_process(0.1)
	_check("timer advances", _run.get_time() > 0.25)

	# style point so the finish carries a real score
	_score.add_style(500.0, "test")

	# --- checkpoint records the respawn point ---
	_cp_area.body_entered.emit(_vehicle)
	_check("checkpoint index recorded", _run.get_checkpoint_index() == 0)
	_check("on_checkpoint fired", _cp_seen == 0)
	_check("checkpoint boosts flow", _flow.get_value() >= _run.checkpoint_flow_bonus - 0.01)

	# --- fall off the world -> respawn at checkpoint, run continues ---
	_flow.reset(); _flow.increase(3.0, "t")
	_vehicle.global_position = Vector3(0, -50, 0)        # below respawn_y_threshold
	_run._physics_process(0.1)
	_check("respawn fired", _respawned == 1)
	_check("respawn at checkpoint", _vehicle.global_position.distance_to(CP_POS) < 0.5)
	_check("respawn keeps RUNNING", _run.get_state() == RunManager.RunState.RUNNING)
	_check("respawn reduced speed", is_equal_approx(_vehicle.velocity.length(), _vehicle.max_speed * _run.respawn_speed_factor))
	_check("respawn flow penalty", _flow.get_value() < 3.0)

	# --- finish line ---
	var time_at_finish: float = _run.get_time()
	_finish_area.body_entered.emit(_vehicle)
	_check("finish -> FINISHED", _run.get_state() == RunManager.RunState.FINISHED)
	_check("on_run_finished fired", _finished == 1)
	_check("finish carries score", is_equal_approx(_finish_score, _score.get_score()) and _finish_score >= 500.0)
	_check("finish carries time", is_equal_approx(_finish_time, time_at_finish))
	_check("score stopped at finish", not _score.is_running())

	# --- restart -> fresh run ---
	_run._restart()
	_check("restart -> RUNNING", _run.get_state() == RunManager.RunState.RUNNING)
	_check("restart resets timer", _run.get_time() == 0.0)
	_check("restart resets checkpoint", _run.get_checkpoint_index() == -1)
	_check("restart back at spawn", _vehicle.global_position.distance_to(SPAWN) < 0.5)
	_check("restart re-armed score", _score.is_running() and _score.get_score() == 0.0)


# --- signal captures ---
func _sig_started() -> void: _started += 1
func _sig_finished(score: float, time: float) -> void:
	_finished += 1; _finish_score = score; _finish_time = time
func _sig_checkpoint(idx: int) -> void: _cp_seen = idx
func _sig_respawn() -> void: _respawned += 1


func _check(label: String, cond: bool) -> void:
	if not cond:
		_fails += 1
		print("  FAIL: %s" % label)
	else:
		print("  ok  : %s" % label)


func _area(world: Node, size: Vector3, pos: Vector3, group: String, idx: int) -> Area3D:
	var a := Area3D.new(); a.position = pos
	a.collision_layer = 0; a.collision_mask = 1
	var c := CollisionShape3D.new(); var b := BoxShape3D.new(); b.size = size; c.shape = b
	a.add_child(c)
	a.add_to_group(group)
	if idx >= 0:
		a.set_meta("checkpoint_index", idx)
	world.add_child(a)
	return a


func _child(parent: Node, n: String, base, path: String):
	var node = base.new(); node.set_script(load(path)); node.name = n
	parent.add_child(node); return node
