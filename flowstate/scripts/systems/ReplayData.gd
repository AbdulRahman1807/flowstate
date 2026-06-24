class_name ReplayData
extends RefCounted

# A recorded run: the per-physics-frame input stream + the start state to re-simulate from.
# INPUTS ONLY (CLAUDE.md decided-choice / 05_Technical_Requirements §Replay) — playback reruns
# the physics from start_transform/start_velocity, it never stores positions.

var frames: Array = []                                  # Array[MovementIntent], one per physics frame
var start_transform: Transform3D = Transform3D.IDENTITY
var start_velocity: Vector3 = Vector3.ZERO
var score: float = 0.0                                  # meta: score this run achieved (personal-best ghost)
var time: float = 0.0                                   # meta: run duration


func size() -> int:
	return frames.size()


func is_empty() -> bool:
	return frames.is_empty()


func get_frame(i: int) -> MovementIntent:
	if i < 0 or i >= frames.size():
		return null
	return frames[i]
