extends Node
class_name FlowSystem

# Flow accumulator (M4 — promoted from the M1 stub).
# PURE by design: it knows nothing about physics, cameras, or scoring. Other
# systems translate gameplay events into increase()/decrease() calls; this node
# only tracks the value, decays it passively, and maps it to a score multiplier.
# (06_Architecture: "FlowSystem — stateless accumulator, emits on_changed signal".)

signal on_changed(new_value: float)

@export var max_flow: float = 5.0
@export var flow_decay_rate: float = 0.15     # Flow lost per second passively (bleeds away if not maintained)
@export var max_multiplier: float = 2.5      # Score multiplier at full flow (1.0 .. this). 006 starts at 2.0; widen later for more amplification.

var _flow_value: float = 0.0
var _last_emitted: float = 0.0

const EMIT_EPSILON: float = 0.01  # Only fire on_changed when the value moves meaningfully

func _physics_process(delta: float) -> void:
	# Passive decay — flow bleeds away if not maintained.
	if _flow_value > 0.0:
		_flow_value = maxf(0.0, _flow_value - flow_decay_rate * delta)
		_emit_if_changed()

# Increase flow by amount, clamped to max. reason is for debugging/telemetry only.
func increase(amount: float, _reason: String = "") -> void:
	if amount <= 0.0:
		return
	_flow_value = minf(_flow_value + amount, max_flow)
	_emit_if_changed()

# Decrease flow by amount, clamped to 0. Used for crashes / falls (Pillar 5).
func decrease(amount: float, _reason: String = "") -> void:
	if amount <= 0.0:
		return
	_flow_value = maxf(_flow_value - amount, 0.0)
	_emit_if_changed()

# Hard reset to zero — called by RunManager on run start / restart.
func reset() -> void:
	_flow_value = 0.0
	_emit_if_changed()

# Raw flow value (0 .. max_flow). Used by ScoreSystem to track "max flow reached".
func get_value() -> float:
	return _flow_value

# Flow as a 0..1 fill ratio — used by the HUD flow bar.
func get_normalized() -> float:
	return _flow_value / max_flow if max_flow > 0.0 else 0.0

# Flow as a score multiplier: 1.0 at empty .. max_multiplier at full.
func get_multiplier() -> float:
	if max_flow <= 0.0:
		return 1.0
	return 1.0 + (_flow_value / max_flow) * (max_multiplier - 1.0)

func _emit_if_changed() -> void:
	if absf(_flow_value - _last_emitted) >= EMIT_EPSILON or (_flow_value == 0.0 and _last_emitted != 0.0):
		_last_emitted = _flow_value
		on_changed.emit(_flow_value)
