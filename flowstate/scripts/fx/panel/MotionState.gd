class_name MotionState
extends RefCounted

# ============================================================================
#  MotionState — the shared per-frame output of a Composition's single timeline
# ----------------------------------------------------------------------------
#  ONE conductor: the Composition computes this each frame from its MotionTimeline
#  and every primitive derives its transform/opacity from THIS shared state,
#  adding only secondary offsets (lag/wobble) on top. Primitives never run their
#  own independent timelines.
# ============================================================================

var phase: int = 0              # MotionTimeline.Phase
var phase_t: float = 0.0        # 0..1 within the current phase
var life_t: float = 0.0         # 0..1 over the whole life
var scale: float = 1.0          # master uniform scale
var squash: float = 0.0         # >0 = wide/short, <0 = tall/narrow (applied to x vs y)
var alpha: float = 1.0          # master opacity
var drift: Vector2 = Vector2.ZERO   # master position offset (grows during decay)
var spin: float = 0.0           # master rotation offset, radians (decay)
var finished: bool = false      # decay complete -> the composition frees itself
