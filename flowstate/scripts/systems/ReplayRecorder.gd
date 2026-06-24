class_name ReplayRecorder
extends RefCounted

# ReplayRecorder (06_Architecture). Records the player's MovementIntent frame-by-frame so a run
# can be re-simulated as a ghost. RefCounted (owned by RunManager) — not a Node; it just buffers.
#
#   start_recording(start_xform, start_vel)  -> begin a fresh recording at the run's start state
#   record_frame(intent)                     -> append a snapshot (called by VehicleController each frame)
#   stop_recording()                         -> ReplayData (the finished recording)
#
# Playback is driven by VehicleController.set_replay(ReplayData) (the input source), not here —
# the recorder only produces the data.

var _recording: bool = false
var _frames: Array = []
var _start_transform: Transform3D = Transform3D.IDENTITY
var _start_velocity: Vector3 = Vector3.ZERO


func start_recording(start_transform: Transform3D, start_velocity: Vector3 = Vector3.ZERO) -> void:
	_frames = []
	_start_transform = start_transform
	_start_velocity = start_velocity
	_recording = true


# Snapshots the intent (clone) — apply_intent() mutates the live intent (clears wall_attach etc.),
# so we must copy at record time, not hold the reference.
func record_frame(intent: MovementIntent) -> void:
	if not _recording or intent == null:
		return
	_frames.append(intent.clone())


func stop_recording() -> ReplayData:
	_recording = false
	var data := ReplayData.new()
	data.frames = _frames.duplicate()
	data.start_transform = _start_transform
	data.start_velocity = _start_velocity
	return data


func is_recording() -> bool:
	return _recording


func frame_count() -> int:
	return _frames.size()
