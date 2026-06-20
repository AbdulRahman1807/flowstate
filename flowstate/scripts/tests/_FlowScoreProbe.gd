extends SceneTree

# Verifies the M4 scoring layer:
#   FlowSystem  — increase / decrease / clamp / reset / decay / multiplier mapping
#   ScoreSystem — start gating, continuous base x flow accumulation, style points +
#                 breakdown, the clean_landing / gravity-transfer / near-miss event
#                 paths (incl. debounce), and the near-stop crash flow penalty.
# Run: Godot --headless --script res://scripts/tests/_FlowScoreProbe.gd

var _fails := 0
var _done := false
var _flow            # vehicle's FlowSystem child
var _score           # ScoreSystem
var _vehicle           # CharacterBody3D w/ VehiclePhysics (untyped for dynamic access to script members/signals)
var _gs               # GravitySystem
var _wr               # WallRiding


func _initialize() -> void:
	var world := Node3D.new(); root.add_child(world)

	_vehicle = CharacterBody3D.new()
	_vehicle.set_script(load("res://scripts/vehicle/VehiclePhysics.gd"))
	_vehicle.name = "Vehicle"
	var col := CollisionShape3D.new(); var cap := CapsuleShape3D.new()
	cap.radius = 0.8; cap.height = 1.6; col.shape = cap; _vehicle.add_child(col)
	_child(_vehicle, "VehicleController", Node, "res://scripts/vehicle/VehicleController.gd")
	_gs = _child(_vehicle, "GravitySystem", Node3D, "res://scripts/vehicle/GravitySystem.gd")
	_wr = _child(_vehicle, "WallRiding", Node, "res://scripts/vehicle/WallRiding.gd")
	_flow = _child(_vehicle, "FlowSystem", Node, "res://scripts/systems/FlowSystem.gd")
	_child(_vehicle, "WallSensor", Node, "res://scripts/vehicle/WallSensor.gd")
	world.add_child(_vehicle)

	_score = Node.new()
	_score.set_script(load("res://scripts/systems/ScoreSystem.gd"))
	_score.name = "ScoreSystem"
	_score.vehicle_path = NodePath("../Vehicle")
	world.add_child(_score)   # _ready resolves refs + connects signals

	# Drive everything manually so assertions are deterministic.
	_vehicle.get_node("VehicleController").set_physics_process(false)
	_flow.set_physics_process(false)
	_score.set_physics_process(false)

	print("=== Flow + Score Probe ===")


func _physics_process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	_test_flow()
	_test_score()
	print("=== %s (%d failure%s) ===" % ["PASS" if _fails == 0 else "FAIL", _fails, "" if _fails == 1 else "s"])
	return true


func _test_flow() -> void:
	_flow.reset()
	_flow.increase(2.0, "t")
	_check("flow increase", is_equal_approx(_flow.get_value(), 2.0))
	var exp_mult_2: float = 1.0 + (2.0 / _flow.max_flow) * (_flow.max_multiplier - 1.0)
	_check("multiplier @flow 2.0", is_equal_approx(_flow.get_multiplier(), exp_mult_2))
	_check("normalized", is_equal_approx(_flow.get_normalized(), 0.4))
	_flow.increase(10.0, "t")
	_check("flow clamps to max", is_equal_approx(_flow.get_value(), 5.0))
	_check("multiplier @max", is_equal_approx(_flow.get_multiplier(), _flow.max_multiplier))
	_flow.decrease(1.0, "t")
	_check("flow decrease", is_equal_approx(_flow.get_value(), 4.0))
	_flow.reset()
	_check("flow reset", _flow.get_value() == 0.0 and is_equal_approx(_flow.get_multiplier(), 1.0))
	_flow.increase(1.0, "t")
	var after_decay: float = 1.0 - _flow.flow_decay_rate * 0.5
	_flow._physics_process(0.5)
	_check("flow passive decay", is_equal_approx(_flow.get_value(), after_decay))
	_flow.reset()


func _test_score() -> void:
	# --- start gating ---
	_score.start_run()
	_check("start: score 0", _score.get_score() == 0.0)
	_check("start: running", _score.is_running())
	_check("start: breakdown empty", _score.get_style_breakdown().is_empty())

	# --- continuous base x flow accumulation ---
	_flow.reset()
	_flow.increase(2.5, "t")
	var mult: float = _flow.get_multiplier()
	var expected_accum: float = _score.base_rate * mult * 0.5   # 5 frames x 0.1s, flow held constant
	for i in range(5):
		_score._physics_process(0.1)
	_check("time-score accumulates", is_equal_approx(_score.get_score(), expected_accum))
	_check("max flow tracked", is_equal_approx(_score.get_max_flow_reached(), 2.5))

	# --- explicit style ---
	var before: float = _score.get_score()
	_score.add_style(123.0, "test_event")
	_check("add_style adds points", is_equal_approx(_score.get_score(), before + 123.0))
	_check("add_style breakdown", is_equal_approx(_score.get_style_breakdown().get("test_event", 0.0), 123.0))

	# --- clean_landing signal path (style + flow) ---
	_flow.reset()
	_emit_clean_landing(10.0)
	_check("clean_landing -> style", is_equal_approx(_score.get_style_breakdown().get("perfect_landing", 0.0), _score.perfect_landing_points))
	_check("clean_landing -> flow", is_equal_approx(_flow.get_value(), _score.flow_on_perfect_landing))

	# --- gravity transfer (INVERTED) + debounce ---
	_flow.reset()
	_gs.on_state_changed.emit(GravitySystem.AttachmentState.INVERTED)
	var gt_after_first: float = _score.get_style_breakdown().get("gravity_transfer", 0.0)
	_check("gravity transfer -> style", is_equal_approx(gt_after_first, _score.gravity_transfer_points))
	_gs.on_state_changed.emit(GravitySystem.AttachmentState.INVERTED)   # debounced: no extra points
	_check("gravity transfer debounced", is_equal_approx(_score.get_style_breakdown().get("gravity_transfer", 0.0), gt_after_first))
	_gs.on_state_changed.emit(GravitySystem.AttachmentState.GROUNDED)   # non-inverted: ignored
	_check("gravity grounded ignored", is_equal_approx(_score.get_style_breakdown().get("gravity_transfer", 0.0), gt_after_first))

	# --- near miss ---
	_wr.on_near_miss.emit()
	_check("near miss -> style", is_equal_approx(_score.get_style_breakdown().get("near_miss", 0.0), _score.near_miss_points))

	# --- crash / near-stop flow penalty ---
	_flow.reset(); _flow.increase(4.0, "t")
	_vehicle._current_speed = 30.0
	_score._physics_process(0.016)        # prev <- 30 (no crash yet)
	_vehicle._current_speed = 2.0
	var flow_before_crash: float = _flow.get_value()
	_score._physics_process(0.016)        # fast -> near-stop -> penalty
	_check("crash drops flow", _flow.get_value() < flow_before_crash - 0.5)

	# --- stop gating ---
	_score.stop_run()
	var frozen: float = _score.get_score()
	_score.add_style(999.0, "should_not_count")
	_score._physics_process(0.5)
	_check("stop: no style after", not _score.get_style_breakdown().has("should_not_count"))
	_check("stop: no accrual after", is_equal_approx(_score.get_score(), frozen))


# clean_landing is a VehiclePhysics signal; emit it on the vehicle to exercise the connection.
func _emit_clean_landing(impact: float) -> void:
	_vehicle.clean_landing.emit(impact)


func _check(label: String, cond: bool) -> void:
	if not cond:
		_fails += 1
		print("  FAIL: %s" % label)
	else:
		print("  ok  : %s" % label)


func _child(parent: Node, n: String, base, path: String):
	var node = base.new(); node.set_script(load(path)); node.name = n
	parent.add_child(node); return node
