class_name MovementIntent

var steer: float = 0.0       # -1.0 (left) to 1.0 (right)
var accelerate: float = 0.0  # 0.0 to 1.0
var brake: float = 0.0       # 0.0 to 1.0
var jump: bool = false
var boost: bool = false
var wall_attach: bool = false
var drift: bool = false  # Explicit/programmatic drift override; players trigger drift via brake+steer (brake-to-drift)
var air_trick: bool = false  # Air-trick modifier (E / RB) — only meaningful while airborne


# Immutable snapshot for replay recording. apply_intent() MUTATES the intent (e.g. clears
# wall_attach at step 9), so the recorder must store a COPY taken before apply, not the live ref.
func clone() -> MovementIntent:
	var c := MovementIntent.new()
	c.steer = steer
	c.accelerate = accelerate
	c.brake = brake
	c.jump = jump
	c.boost = boost
	c.wall_attach = wall_attach
	c.drift = drift
	c.air_trick = air_trick
	return c
