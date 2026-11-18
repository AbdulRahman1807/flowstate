class_name KineticsPrimitive
extends PanelPrimitive

# ============================================================================
#  KINETICS — the ACTION LINE FIELD (Panel Director v2)
# ----------------------------------------------------------------------------
#  Not a rectangular patch of parallel lines. A procedurally generated FIELD of
#  expressive, tapered strokes that surrounds the composition, follows the Action
#  Vector (the whole field orients to the spine each frame), and wraps the car
#  (a centre exclusion gap). Strokes vary in length, spacing, thickness, taper,
#  and angle so it never reads as a repeated texture — it guides the eye, exaggerates
#  motion, glues the actors together, and feels hand-drawn.
#
#  ONE generator, many STYLES (chosen by the event family via style_for()):
#    SCRATCHES — short jittered strokes in a ring (drift)
#    STREAKS   — long flank strokes along the spine (boost / thrust / wall)
#    RAYS      — a forward cone radiating from the car (impact)
#    ARCS      — tangential strokes, a curved swirl (curved motion)
#    BURST     — a full radial explosion of rays (reward / tier-up)
# ============================================================================

enum FieldStyle { SCRATCHES, STREAKS, RAYS, ARCS, BURST }

var _color: Color = PanelTokens.CORE
var _quads: Array = []   # frozen tapered-stroke polygons


# config: { color, size, exclusion, style }
func configure(config: Dictionary) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = config.get("size", Vector2(620, 620))
	var base: Color = config.get("color", PanelTokens.CORE)
	_color = base.lerp(PanelTokens.CORE, 0.72)   # near-white action lines (accent used sparingly)
	_generate(config.get("style", FieldStyle.STREAKS), config.get("exclusion", 90.0))
	queue_redraw()


func apply(state: MotionState, av: ActionVector) -> void:
	# Orient the whole field to the spine; reveal in at impact, fade by settle.
	_apply_local(Vector2.ZERO, av.axis.angle(), _reveal(state) * 0.5, 1.0)


# --- procedural field generation (frozen once) ------------------------------
func _generate(style: int, r: float) -> void:
	_quads.clear()
	var c := size * 0.5
	var reach := minf(size.x, size.y) * 0.5 - 12.0
	var span := maxf(reach - r, 24.0)
	match style:
		FieldStyle.SCRATCHES: _gen_scratches(c, r, span)
		FieldStyle.STREAKS:   _gen_streaks(c, r, span, reach)
		FieldStyle.RAYS:      _gen_radial(c, r, span, 30, -1.3, 1.3)
		FieldStyle.ARCS:      _gen_arcs(c, r, span)
		FieldStyle.BURST:     _gen_radial(c, r, span, 48, 0.0, TAU)
		_:                    _gen_streaks(c, r, span, reach)


func _gen_scratches(c: Vector2, r: float, span: float) -> void:
	for i in 40:
		var pa := randf() * TAU
		var origin := c + Vector2(cos(pa), sin(pa)) * (r + randf() * span)
		var dir := Vector2.from_angle(randf_range(-0.4, 0.4))   # roughly along the spine, jittered
		var l := randf_range(16.0, 52.0)
		_add(origin - dir * l * 0.5, origin + dir * l * 0.5, randf_range(3.0, 6.0), randf_range(0.5, 1.4))


func _gen_streaks(c: Vector2, r: float, span: float, reach: float) -> void:
	for i in 24:
		var side := -1.0 if i % 2 == 0 else 1.0
		var off := side * (r + randf() * span)                  # flanks only — leave the car clear
		var dir := Vector2.from_angle(randf_range(-0.1, 0.1))
		var l := randf_range(130.0, 290.0)
		var mid := c + Vector2(randf_range(-reach * 0.3, reach * 0.3), off)
		_add(mid - dir * l * 0.5, mid + dir * l * 0.5, randf_range(2.0, 4.0), randf_range(0.4, 1.0))


func _gen_radial(c: Vector2, r: float, span: float, n: int, ang_lo: float, ang_hi: float) -> void:
	for i in n:
		var dir := Vector2.from_angle(randf_range(ang_lo, ang_hi))
		var l := randf_range(span * 0.4, span)
		_add(c + dir * r, c + dir * (r + l), randf_range(4.0, 8.0), 0.6)   # thick base -> thin tip


func _gen_arcs(c: Vector2, r: float, span: float) -> void:
	for i in 24:
		var ba := randf() * TAU
		var origin := c + Vector2(cos(ba), sin(ba)) * (r + randf() * span)
		var tang := Vector2.from_angle(ba + PI * 0.5)           # tangent -> a curved swirl read
		var l := randf_range(40.0, 100.0)
		_add(origin - tang * l * 0.5, origin + tang * l * 0.5, randf_range(2.5, 5.0), randf_range(0.6, 1.5))


# One tapered stroke = a quad from a (width wa) to b (width wb).
func _add(a: Vector2, b: Vector2, wa: float, wb: float) -> void:
	var d := b - a
	if d.length() < 0.5:
		return
	d = d.normalized()
	var perp := Vector2(-d.y, d.x)
	_quads.append(PackedVector2Array([
		a + perp * wa * 0.5, a - perp * wa * 0.5, b - perp * wb * 0.5, b + perp * wb * 0.5,
	]))


func _draw() -> void:
	for q in _quads:
		draw_colored_polygon(q, _color)


func _reveal(s: MotionState) -> float:
	match s.phase:
		MotionTimeline.Phase.ANTICIPATE:
			return s.phase_t
		MotionTimeline.Phase.IMPACT:
			return 1.0
		MotionTimeline.Phase.SETTLE:
			return maxf(0.0, 1.0 - s.phase_t * 1.4)
		_:
			return 0.0


# Family -> field style (semantic -> visual; the Composition passes this in).
static func style_for(family: PanelGrammar.Family) -> FieldStyle:
	match family:
		PanelGrammar.Family.SLIDE:  return FieldStyle.SCRATCHES
		PanelGrammar.Family.THRUST: return FieldStyle.STREAKS
		PanelGrammar.Family.LAUNCH: return FieldStyle.STREAKS
		PanelGrammar.Family.WALL:   return FieldStyle.STREAKS
		PanelGrammar.Family.IMPACT: return FieldStyle.RAYS
		PanelGrammar.Family.DANGER: return FieldStyle.SCRATCHES
		PanelGrammar.Family.REWARD: return FieldStyle.BURST
		PanelGrammar.Family.FAULT:  return FieldStyle.SCRATCHES
	return FieldStyle.STREAKS
