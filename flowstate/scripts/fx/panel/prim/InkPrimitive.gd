class_name InkPrimitive
extends PanelPrimitive

# ============================================================================
#  INK — splatter / grit for a hand-made feel (grammar primitive)
# ----------------------------------------------------------------------------
#  A scatter of small accent-tinted dots behind the hero. Rides the master at a
#  low base opacity. Procedural placeholder. Knows nothing about siblings.
# ============================================================================

const BASE_ALPHA := 0.6

var _color: Color = PanelTokens.CORE
var _dots: Array = []   # frozen [pos: Vector2, radius: float]


# config: { color (Color), size (Vector2), count (int) }
func configure(config: Dictionary) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = config.get("size", Vector2(240, 240))
	# Dark ink (accent muddied toward black) — a shadow/ink layer behind the word for depth.
	_color = (config.get("color", PanelTokens.CORE) as Color).lerp(PanelTokens.INK, 0.55)
	var count: int = config.get("count", 10)
	_dots.clear()
	for i in count:
		var ang := randf() * TAU
		var rad := size.length() * 0.5 * randf_range(0.2, 0.6)
		var pos := size * 0.5 + Vector2(cos(ang), sin(ang)) * rad
		_dots.append([pos, randf_range(3.0, 9.0)])
	queue_redraw()


func apply(_state: MotionState, _av: ActionVector) -> void:
	_apply_local(Vector2.ZERO, 0.0, BASE_ALPHA, 1.0)


func _draw() -> void:
	for d in _dots:
		draw_circle(d[0], d[1], _color)
