class_name BackingPrimitive
extends PanelPrimitive

# ============================================================================
#  BACKING — a HAND-MADE irregular burst behind the hero (Panel Director v2)
# ----------------------------------------------------------------------------
#  Procedural, asymmetric, uneven spikes with an inked edge and a brighter core —
#  illustrated rather than generated. Tinted to the accent hue (the accent lives
#  on the supporting graphics; the hero word stays white). Frozen per instance so
#  each burst is unique but stays in one visual language. Rides the master with a
#  brief flash on the impact slam.
# ============================================================================

const BASE_ALPHA := 0.92

var _color: Color = PanelTokens.CORE
var _ink: PackedVector2Array = PackedVector2Array()
var _fill: PackedVector2Array = PackedVector2Array()
var _core: PackedVector2Array = PackedVector2Array()


# config: { color, size }
func configure(config: Dictionary) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = config.get("size", Vector2(240, 240))
	_color = config.get("color", PanelTokens.CORE)
	_build_burst()
	queue_redraw()


func _build_burst() -> void:
	var c := size * 0.5
	var rmax := minf(size.x, size.y) * 0.5 - 4.0
	var spikes := randi_range(11, 16)
	var start := randf() * TAU
	var pts := PackedVector2Array()
	for i in spikes:
		var a1 := start + TAU * float(i) / float(spikes) + randf_range(-0.14, 0.14)
		pts.append(c + Vector2(cos(a1), sin(a1)) * rmax * randf_range(0.76, 1.0))   # uneven spike tip
		var a2 := start + TAU * (float(i) + 0.5) / float(spikes) + randf_range(-0.12, 0.12)
		pts.append(c + Vector2(cos(a2), sin(a2)) * rmax * randf_range(0.38, 0.6))   # irregular valley
	_ink = pts
	_fill = _scaled(pts, c, 0.92)
	_core = _scaled(pts, c, 0.64)


func _scaled(pts: PackedVector2Array, c: Vector2, f: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + (p - c) * f)
	return out


func _draw() -> void:
	draw_colored_polygon(_ink, PanelTokens.INK)     # black inked edge (dominant language)
	draw_colored_polygon(_fill, PanelTokens.CORE)   # WHITE body (dominant)
	draw_colored_polygon(_core, _color)             # accent core only — a sparing colour pop


func apply(state: MotionState, av: ActionVector) -> void:
	var flash := 1.0
	if state.phase == MotionTimeline.Phase.IMPACT:
		flash = 1.0 + 0.16 * (1.0 - state.phase_t)
	_apply_local(Vector2.ZERO, av.roll, BASE_ALPHA, flash)
