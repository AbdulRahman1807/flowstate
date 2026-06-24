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

# --- Ghost replay (M5) ---
@export var enable_ghost: bool = true                   # Spawn a ghost replaying your best run so far
@export var ghost_color: Color = Color(0.0, 1.0, 0.8)   # 04_Art_Direction cyan
@export var ghost_alpha: float = 0.35

var _vehicle: VehiclePhysics
var _flow: FlowSystem
var _gravity: GravitySystem
var _score: ScoreSystem

var _state: RunState = RunState.READY
var _time: float = 0.0
var _checkpoint_index: int = -1
var _start_xform: Transform3D = Transform3D.IDENTITY
var _respawn_xform: Transform3D = Transform3D.IDENTITY

# Replay / personal best (M5) — all in-memory (01_PRD: no persistence at prototype stage).
var _controller: VehicleController
var _recorder: ReplayRecorder
var _ghost: CharacterBody3D
var _best_replay: ReplayData
var _last_replay: ReplayData              # the run you just drove (ghost source when there's no finish line)
var _has_best: bool = false
var _best_score: float = 0.0
var _best_time: float = 0.0
var _last_run_was_best: bool = false


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
		# Wire the replay recorder into the player's controller (records inputs each frame).
		_controller = _vehicle.get_node_or_null("VehicleController") as VehicleController
		if is_instance_valid(_controller):
			_recorder = ReplayRecorder.new()
			_controller.replay_recorder = _recorder

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
	# Record this run (inputs only) from the current start state.
	if _recorder != null and is_instance_valid(_vehicle):
		_recorder.start_recording(_vehicle.global_transform, _vehicle.velocity)
	# Race a ghost: your best run if you've finished one, else your last run — so free-roam scenes
	# with no finish line (e.g. Test_Playground) still replay: drive, press R, race your last run.
	_spawn_ghost(_best_replay if _has_best else _last_replay)
	on_run_started.emit()


func _finish_run() -> void:
	_state = RunState.FINISHED
	if is_instance_valid(_score):
		_score.stop_run()
	var final_score := _score.get_score() if is_instance_valid(_score) else 0.0

	# Capture this run's recording and update the session personal best (in-memory only).
	_last_run_was_best = false
	if _recorder != null and _recorder.is_recording():
		var data := _recorder.stop_recording()
		data.score = final_score
		data.time = _time
		if not _has_best or final_score > _best_score:
			_has_best = true
			_best_score = final_score
			_best_time = _time
			_best_replay = data
			_last_run_was_best = true
	_free_ghost()
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
	# Save the run you just drove as the "last run" so its ghost races you next — this is what makes
	# replay work WITHOUT a finish line (free-roam scenes like the playground).
	if _recorder != null and _recorder.is_recording():
		var data := _recorder.stop_recording()
		if not data.is_empty():
			_last_replay = data
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


# --- Ghost replay (M5) ---
func _free_ghost() -> void:
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null


# Spawn a ghost that re-simulates the recording. It's a duplicate of the player vehicle whose
# controller replays the recorded inputs (inputs only, re-run from the recorded start state).
# Defensive: any failure here must NOT break the run loop — the ghost is a visual layer on top.
func _spawn_ghost(data: ReplayData) -> void:
	_free_ghost()
	if not enable_ghost or data == null or data.is_empty() or not is_instance_valid(_vehicle):
		return
	var parent := _vehicle.get_parent()
	if parent == null:
		return
	var ghost := _vehicle.duplicate() as CharacterBody3D
	if ghost == null:
		return
	ghost.name = "GhostVehicle"
	# Strip the camera (current=true would steal the view) and the VFX from the ghost.
	for child_name in ["Camera3D", "WallVFX"]:
		var c := ghost.get_node_or_null(child_name)
		if c != null:
			ghost.remove_child(c)
			c.free()
	# Collision: follow the same geometry (mask) but be invisible to the player and the run
	# Area3Ds — layer 0 means nothing collides into it, no ray hits it, no Area detects it.
	ghost.collision_layer = 0
	ghost.collision_mask = _vehicle.collision_mask
	# The ghost's controller replays the recording and does NOT record.
	var gc := ghost.get_node_or_null("VehicleController") as VehicleController
	if is_instance_valid(gc):
		gc.replay_recorder = null
		gc.set_replay(data)
	# Translucent ghost look.
	var mesh := ghost.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if is_instance_valid(mesh):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(ghost_color.r, ghost_color.g, ghost_color.b, ghost_alpha)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = ghost_color
		mat.emission_energy_multiplier = 0.6
		mesh.material_override = mat
	parent.add_child(ghost)
	ghost.global_transform = data.start_transform
	if ghost.has_method("set_vehicle_velocity"):
		ghost.set_vehicle_velocity(data.start_velocity)
	_ghost = ghost


# --- Getters (HUD reads these per-frame) ---
func get_time() -> float:
	return _time


func get_state() -> RunState:
	return _state


func get_checkpoint_index() -> int:
	return _checkpoint_index


func has_best() -> bool:
	return _has_best


func get_best_score() -> float:
	return _best_score


func get_best_time() -> float:
	return _best_time


func was_last_run_best() -> bool:
	return _last_run_was_best
