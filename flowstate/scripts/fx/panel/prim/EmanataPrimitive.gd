class_name EmanataPrimitive
extends PanelPrimitive

# ============================================================================
#  EMANATA — comic punctuation marks (small stars/ticks) (grammar primitive)
# ----------------------------------------------------------------------------
#  A scatter of little impact marks that POP on the slam, hold, then fade in
#  decay. Procedural placeholder (small drawn stars). Knows nothing about siblings.
# ============================================================================

var _color: Color = PanelTokens.CORE
var _marks: Array = []   # frozen [pos: Vector2, radius: float]


# config: { color (Color), size (Vector2), count (int) }
func configure(config: Dictionary) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = config.get("size", Vector2(200, 200))
	_color = config.get("color", PanelTokens.CORE)
	var count: int = config.get("count", 5)
	_marks.clear()
	for i in count:
		var ang := randf() * TAU
		var rad := size.length() * 0.5 * randf_range(0.45, 0.62)
		var pos := size * 0.5 + Vector2(cos(ang), sin(ang)) * rad
		_marks.append([pos, randf_range(7.0, 13.0)])
	queue_redraw()


func apply(state: MotionState, _av: ActionVector) -> void:
	var r := _pop(state)   # x = scale, y = alpha
	_apply_local(Vector2.ZERO, 0.0, r.y, r.x)


func _draw() -> void:
	for m in _marks:
		_star(m[0], m[1])


# A small 4-point comic spark.
func _star(c: Vector2, r: float) -> void:
	draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), _color, 3.0)
	draw_line(c + Vector2(0, -r), c + Vector2(0, r), _color, 3.0)
	var d := r * 0.6
	draw_line(c + Vector2(-d, -d), c + Vector2(d, d), _color, 2.0)
	draw_line(c + Vector2(-d, d), c + Vector2(d, -d), _color, 2.0)


func _pop(s: MotionState) -> Vector2:
	match s.phase:
		MotionTimeline.Phase.ANTICIPATE:
			return Vector2(0.0, 0.0)
		MotionTimeline.Phase.IMPACT:
			var o := 1.0 - pow(1.0 - s.phase_t, 2.0)
			return Vector2(lerpf(0.4, 1.25, o), o)
		MotionTimeline.Phase.SETTLE:
			return Vector2(lerpf(1.25, 1.0, s.phase_t), 1.0)
		_:
			return Vector2(1.0, maxf(0.0, 1.0 - s.phase_t))
