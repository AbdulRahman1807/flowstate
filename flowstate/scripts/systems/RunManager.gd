extends Node
class_name RunManager

# RunManager (M4 — 007_Run_Lifecycle.md). Scene-level COORDINATOR.
# Owns the run state machine, the timer, and respawn/restart. Reads the vehicle
# transform; writes it ONLY on respawn/restart. No physics logic of its own.
#
#   READY --(start line / first throttle)--> RUNNING --(finish line)--> FINISHED
#
# Falling off the world respawns at the last checkpoint at reduced speed WITHOUT
# ending the run (Pillar 5: Failure Costs Momentum, Not Progress). Restart is
# always available and resets to a fresh run.

signal on_run_started()
signal on_run_finished(score: float, time: float)
signal on_checkpoint(index: int)
signal on_respawn()

enum RunState { READY, RUNNING, FINISHED }

@export var vehicle_path: NodePath = NodePath("../Vehicle")
@export var score_system_path: NodePath = NodePath("../ScoreSystem")

@export var auto_start: bool = true                 # Start on first throttle, in addition to crossing the start line
@export var respawn_y_threshold: float = -10.0      # Below the recovery floor (top y=-0.15) = fell off the world
@export var respawn_speed_factor: float = 0.4       # Respawn forward speed as a fraction of max_speed (keeps some momentum)
@export var respawn_flow_penalty: float = 1.0       # Flow lost on a fall

@export var start_line_group: String = "start_line"
@export var finish_line_group: String = "finish_line"
@export var checkpoint_group: String = "checkpoints"
@export var checkpoint_flow_bonus: float = 1.5      # Flow granted each time you cross a NEW checkpoint (the "blue slabs" pop your flow)

var _vehicle: VehiclePhysics
var _flow: FlowSystem
var _gravity: GravitySystem
var _score: ScoreSystem

var _state: RunState = RunState.READY
var _time: float = 0.0
var _checkpoint_index: int = -1
var _start_xform: Transform3D = Transform3D.IDENTITY
var _respawn_xform: Transform3D = Transform3D.IDENTITY


func _ready() -> void:
	var vehicle := get_node_or_null(vehicle_path)
	if vehicle:
		_vehicle = vehicle as VehiclePhysics
		_flow = vehicle.get_node_or_null("FlowSystem") as FlowSystem
		_gravity = vehicle.get_node_or_null("GravitySystem") as GravitySystem
	_score = get_node_or_null(score_system_path) as ScoreSystem

	if is_instance_valid(_vehicle):
		_start_xform = _vehicle.global_transform
		_respawn_xform = _start_xform

	# Markers are built by TrackBuilder during ITS _ready; collect them after the
	# current frame so scene-tree order doesn't matter.
	call_deferred("_wire_markers")


func _wire_markers() -> void:
	# Idempotent: guards against any double-wire (deferred re-entry, scene reload).
	for a in get_tree().get_nodes_in_group(start_line_group):
		if a is Area3D and not a.body_entered.is_connected(_on_start_entered):
			a.body_entered.connect(_on_start_entered)
	for a in get_tree().get_nodes_in_group(finish_line_group):
		if a is Area3D and not a.body_entered.is_connected(_on_finish_entered):
			a.body_entered.connect(_on_finish_entered)
	for a in get_tree().get_nodes_in_group(checkpoint_group):
		if a is Area3D:
			var idx := int(a.get_meta("checkpoint_index", 0))
			var cb := _on_checkpoint_entered.bind(idx, a)
			if not a.body_entered.is_connected(cb):
				a.body_entered.connect(cb)


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		_restart()
		return

	if _state == RunState.RUNNING:
		_time += delta
		if is_instance_valid(_vehicle) and _vehicle.global_position.y < respawn_y_threshold:
			_respawn()

	if _state == RunState.READY and auto_start and Input.is_action_pressed("accelerate"):
		_begin_run()


# --- Marker callbacks (filter for the vehicle; static track geometry overlapping a
# trigger also fires body_entered, so the identity check matters) ---
func _on_start_entered(body: Node) -> void:
	if _state == RunState.READY and body == _vehicle:
		_begin_run()


func _on_finish_entered(body: Node) -> void:
	if _state == RunState.RUNNING and body == _vehicle:
		_finish_run()


func _on_checkpoint_entered(body: Node, index: int, area: Area3D) -> void:
	if _state != RunState.RUNNING or body != _vehicle:
		return
	if index > _checkpoint_index:                       # forward progress only — don't move it backward
		_checkpoint_index = index
		_respawn_xform = _upright_facing_neg_z(area.global_position)
		if is_instance_valid(_flow):
			_flow.increase(checkpoint_flow_bonus, "checkpoint")   # crossing a checkpoint pops your flow
		on_checkpoint.emit(index)


# --- State transitions ---
func _begin_run() -> void:
	_state = RunState.RUNNING
	_time = 0.0
	if is_instance_valid(_flow):
		_flow.reset()
	if is_instance_valid(_score):
		_score.start_run()
	on_run_started.emit()


func _finish_run() -> void:
	_state = RunState.FINISHED
	if is_instance_valid(_score):
		_score.stop_run()
	var final_score := _score.get_score() if is_instance_valid(_score) else 0.0
	on_run_finished.emit(final_score, _time)


func _respawn() -> void:
	if not is_instance_valid(_vehicle):
		return
	_vehicle.global_transform = _respawn_xform
	var forward := -_respawn_xform.basis.z
	var speed: float = _vehicle.max_speed * respawn_speed_factor
	_vehicle.set_vehicle_velocity(forward * speed)
	if is_instance_valid(_gravity):
		_gravity.force_airborne()
	if is_instance_valid(_flow):
		_flow.decrease(respawn_flow_penalty, "fall")
	on_respawn.emit()


func _restart() -> void:
	if is_instance_valid(_vehicle):
		_vehicle.global_transform = _start_xform
		_vehicle.set_vehicle_velocity(Vector3.ZERO)
		if is_instance_valid(_gravity):
			_gravity.force_airborne()
	_checkpoint_index = -1
	_respawn_xform = _start_xform
	_begin_run()


func _upright_facing_neg_z(pos: Vector3) -> Transform3D:
	# Identity basis already faces -Z (forward = -basis.z) with +Y up.
	return Transform3D(Basis.IDENTITY, pos)


# --- Getters (HUD reads these per-frame) ---
func get_time() -> float:
	return _time


func get_state() -> RunState:
	return _state


func get_checkpoint_index() -> int:
	return _checkpoint_index
