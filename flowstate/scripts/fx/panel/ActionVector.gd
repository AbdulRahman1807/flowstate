class_name ActionVector
extends RefCounted

# ============================================================================
#  ActionVector — the spatial backbone of a composition (grammar §3)
# ----------------------------------------------------------------------------
#  The car-anchored, screen-space encoding of a maneuver. Every primitive lays
#  out relative to this, so compositions feel attached to the action rather than
#  pinned to fixed offsets. It carries:
#    origin    — the car's screen anchor (the composition's origin; Law 1)
#    axis      — the screen DIRECTION of the maneuver's intent (normalized)
#    roll      — the car's banking on screen (so the panel tilts with the car)
#    magnitude — the captured INTENSITY of the maneuver (0..~1.5)
#
#  The Director computes a frozen WORLD-space intent at compose() time, then
#  re-projects it to this screen-space ActionVector each frame — so the intent is
#  fixed (the moment it happened) while its on-screen form stays camera-correct.
# ============================================================================

var origin: Vector2 = Vector2.ZERO
var axis: Vector2 = Vector2.UP
var roll: float = 0.0
var magnitude: float = 0.0

# A point at `distance` along the action axis (where the action is heading).
func point(distance: float) -> Vector2:
	return origin + axis * distance

# The screen-perpendicular of the axis (the "wing" direction for later layout).
func perpendicular() -> Vector2:
	return Vector2(-axis.y, axis.x)
