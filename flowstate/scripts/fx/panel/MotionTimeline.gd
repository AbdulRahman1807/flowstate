class_name MotionTimeline
extends RefCounted

# ============================================================================
#  MotionTimeline — the shared MOTION GRAMMAR clock (grammar §6)
# ----------------------------------------------------------------------------
#  One per Composition; the Composition advances it and applies its MotionState
#  to all primitives — the single conductor. Four phases:
#
#    ANTICIPATE -> IMPACT -> SETTLE -> DECAY
#
#  The feel is a printed comic graphic FORCEFULLY STAMPED on (a fast impact with
#  scale overshoot + squash→stretch, snapping to full opacity) that then SETTLES
#  elastically and naturally AGES OUT (decay: shrink, fade, drift, slight rotate).
#  Total duration + phase split scale with the semantic emphasis tier.
#
#  This is timing, not appearance — the tuning lives here (the timing engine),
#  owned by the Composition.
# ============================================================================

enum Phase { ANTICIPATE, IMPACT, SETTLE, DECAY }

const IMPACT_SCALE := 1.35     # scale overshoot at the slam
const DECAY_DRIFT := 26.0      # px the panel drifts (up) as it ages out
const DECAY_SPIN_DEG := 6.0    # slight rotation as it ages out

var _elapsed := 0.0
var _total := 0.7
var _bounds: PackedFloat32Array = PackedFloat32Array([0.07, 0.154, 0.434, 0.7])


# Total duration + phase proportions (anticipate/impact/settle/decay) per tier.
func configure(tier: PanelGrammar.Tier) -> void:
	var total := 0.7
	var props := PackedFloat32Array([0.10, 0.12, 0.40, 0.38])
	match tier:
		PanelGrammar.Tier.WHISPER:
			total = 0.35
			props = PackedFloat32Array([0.0, 0.15, 0.40, 0.45])   # no anticipate — instant tick
		PanelGrammar.Tier.BEAT:
			total = 0.70
			props = PackedFloat32Array([0.10, 0.12, 0.40, 0.38])
		PanelGrammar.Tier.HERO:
			total = 1.00
			props = PackedFloat32Array([0.10, 0.12, 0.40, 0.38])
		PanelGrammar.Tier.CLIMAX:
			total = 1.45
			props = PackedFloat32Array([0.12, 0.12, 0.44, 0.32])
	_total = total
	_bounds = PackedFloat32Array()
	var c := 0.0
	for p in props:
		c += p * total
		_bounds.append(c)


func advance(dt: float) -> void:
	_elapsed += dt

func duration() -> float:
	return _total

func is_finished() -> bool:
	return _elapsed >= _total


func state() -> MotionState:
	var st := MotionState.new()
	var e := clampf(_elapsed, 0.0, _total)
	st.life_t = e / _total if _total > 0.0 else 1.0

	var phase := int(Phase.DECAY)
	var pt := 1.0
	var lo := 0.0
	for i in range(4):
		var hi: float = _bounds[i]
		if e <= hi or i == 3:
			phase = i
			pt = (e - lo) / (hi - lo) if (hi - lo) > 0.0001 else 1.0
			break
		lo = hi
	st.phase = phase
	st.phase_t = clampf(pt, 0.0, 1.0)

	match phase:
		Phase.ANTICIPATE:                                   # quick wind-up: appear small + dim
			st.scale = lerpf(0.45, 0.70, _out(st.phase_t))
			st.alpha = lerpf(0.0, 0.55, st.phase_t)
			st.squash = lerpf(0.0, 0.10, st.phase_t)
		Phase.IMPACT:                                       # SLAM: overshoot scale, snap to full, squash->stretch
			st.scale = lerpf(0.70, IMPACT_SCALE, _out(st.phase_t))
			st.alpha = lerpf(0.55, 1.0, _out(minf(st.phase_t * 1.6, 1.0)))
			st.squash = lerpf(0.30, -0.12, _out(st.phase_t))
		Phase.SETTLE:                                       # elastic back to rest + tiny wobble
			st.scale = lerpf(IMPACT_SCALE, 1.0, _out_back(st.phase_t))
			st.alpha = 1.0
			st.squash = lerpf(-0.12, 0.0, _out(st.phase_t)) + _wobble(st.phase_t)
		Phase.DECAY:                                        # age out: shrink, fade, drift up, rotate
			st.scale = lerpf(1.0, 0.82, _in(st.phase_t))
			st.alpha = lerpf(1.0, 0.0, _in(clampf(st.phase_t * 1.1, 0.0, 1.0)))
			st.drift = Vector2(0.0, -1.0) * (DECAY_DRIFT * _in(st.phase_t))
			st.spin = deg_to_rad(DECAY_SPIN_DEG) * _in(st.phase_t)
			st.squash = 0.0

	st.finished = _elapsed >= _total
	return st


# --- easing (the rhythm's curves) -------------------------------------------
func _out(t: float) -> float:        # decelerate
	return 1.0 - pow(1.0 - t, 2.0)

func _in(t: float) -> float:         # accelerate
	return t * t

func _out_back(t: float) -> float:   # overshoot then settle (elastic-ish)
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)

func _wobble(t: float) -> float:     # small decaying wobble during settle
	return sin(t * PI * 3.0) * 0.05 * (1.0 - t)
