class_name VehicleController
extends Node

@export var jump_buffer_time: float = 0.12
@export var wall_attach_buffer_time: float = 0.1

@onready var vehicle_physics: VehiclePhysics = get_parent()

var _jump_buffer_timer: float = 0.0
var _wall_attach_buffer_timer: float = 0.0

# --- Replay (M5 — ghost replay) ---
# Recording: RunManager assigns a recorder; each live frame's intent is snapshotted into it.
# Playback (ghost): set_replay(data) makes this controller a GHOST that feeds the recorded
# intents to physics instead of reading Input. Inputs only — physics re-runs from the start state.
var replay_recorder: ReplayRecorder = null
var _replay_data: ReplayData = null
var _replay_cursor: int = 0
var _replay_finished: bool = false

signal replay_finished()


func set_replay(data: ReplayData) -> void:
	_replay_data = data
	_replay_cursor = 0
	_replay_finished = false


func is_replaying() -> bool:
	return _replay_data != null


func _physics_process(delta: float) -> void:
	if _replay_data != null:
		_process_replay()
		return

	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time
	if Input.is_action_just_pressed("wall_attach"):
		_wall_attach_buffer_timer = wall_attach_buffer_time

	_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)
	_wall_attach_buffer_timer = maxf(_wall_attach_buffer_timer - delta, 0.0)

	var intent := MovementIntent.new()
	intent.steer = Input.get_axis("steer_right", "steer_left")
	intent.accelerate = Input.get_action_strength("accelerate")
	intent.brake = Input.get_action_strength("brake")
	intent.jump = _jump_buffer_timer > 0.0
	intent.boost = Input.is_action_pressed("boost")
	intent.wall_attach = _wall_attach_buffer_timer > 0.0
	intent.air_trick = Input.is_action_pressed("air_trick")

	# Snapshot BEFORE apply_intent mutates the live intent (it clears wall_attach at step 9).
	if replay_recorder != null:
		replay_recorder.record_frame(intent)

	vehicle_physics.apply_intent(intent)


# Ghost: feed the next recorded intent to physics. The recorded intent already holds the RESOLVED
# values (e.g. buffered jump), so playback reproduces them frame-for-frame. Past the end the ghost
# coasts on a neutral intent and emits replay_finished once.
func _process_replay() -> void:
	if _replay_cursor < _replay_data.size():
		vehicle_physics.apply_intent(_replay_data.get_frame(_replay_cursor).clone())
		_replay_cursor += 1
	elif not _replay_finished:
		# End of the recording: stop the ghost dead — zero its velocity and STOP applying intents, so
		# it freezes where the run ended instead of coasting on a neutral intent forever.
		_replay_finished = true
		vehicle_physics.set_vehicle_velocity(Vector3.ZERO)
		replay_finished.emit()
	# Past the end (_replay_finished): no apply_intent → move_and_slide never runs → ghost is frozen.


func consume_jump() -> void:
	_jump_buffer_timer = 0.0


func consume_wall_attach() -> void:
	_wall_attach_buffer_timer = 0.0


func get_jump_buffer_timer() -> float:
	return _jump_buffer_timer
