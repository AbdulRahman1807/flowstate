extends CanvasLayer
class_name PlayHUD

# PlayHUD (M4 — 008_HUD.md). Pure OBSERVER for the play scene: reads FlowSystem,
# ScoreSystem and RunManager via signals + getters, writes NOTHING to gameplay.
# Built procedurally (project convention) with high-contrast outlined text so it
# stays readable at speed and never obscures the track (04 hard rule).
#   - Flow multiplier  : large, top-center, ×N.N + a bar that fills with flow
#   - Score            : top-right
#   - Timer            : top-right (under score)
#   - End-of-run panel : shown on RunManager.on_run_finished

@export var flow_system_path: NodePath = NodePath("../Vehicle/FlowSystem")
@export var score_system_path: NodePath = NodePath("../ScoreSystem")
@export var run_manager_path: NodePath = NodePath("../RunManager")

@export var fade_delay: float = 1.5       # Seconds of no flow change before the flow display dims (04: fade when idle)
@export var idle_alpha: float = 0.35
@export var flow_bar_width: float = 340.0
@export var flow_bar_height: float = 20.0
@export var track_title: String = "FLOWSTATE — CIRCUIT"   # shown on the start/READY screen

@export_group("Flow Display Placement")
@export var show_flow_meter: bool = false                 # v2: the MomentumStack is the multiplier signal now — hide the old flow bar while tuning
@export var vehicle_path: NodePath = NodePath("../Vehicle")
@export var flow_follows_car: bool = true                  # float the multiplier near the car (comic HUD) vs fixed top-center
@export var flow_car_offset: Vector2 = Vector2(0, -130)    # screen offset of the flow display from the car (negative y = above)
@export var flow_follow_smooth: float = 12.0               # how snappily it tracks the car (lower = laggier)

# 04_Art_Direction palette
const COL_CYAN := Color(0.0, 1.0, 0.8)
const COL_MAGENTA := Color(1.0, 0.18, 0.47)
const COL_YELLOW := Color(0.91, 1.0, 0.0)
const COL_WHITE := Color(1, 1, 1)
const COL_OUTLINE := Color(0, 0, 0, 0.9)

var _flow: FlowSystem
var _score: ScoreSystem
var _run: RunManager
var _vehicle: Node3D

var _flow_box: VBoxContainer
var _flow_label: Label
var _flow_bar_bg: ColorRect
var _flow_bar_fill: ColorRect
var _score_label: Label
var _timer_label: Label
var _best_label: Label
var _start_panel: Control
var _summary: Control
var _summary_score: Label
var _summary_time: Label
var _summary_best: Label
var _summary_breakdown: Label

var _flow_idle_timer: float = 999.0
var _max_flow: float = 5.0


func _ready() -> void:
	layer = 10
	_flow = get_node_or_null(flow_system_path) as FlowSystem
	_score = get_node_or_null(score_system_path) as ScoreSystem
	_run = get_node_or_null(run_manager_path) as RunManager
	_vehicle = get_node_or_null(vehicle_path) as Node3D
	if is_instance_valid(_flow):
		_max_flow = _flow.max_flow

	_build_ui()
	if is_instance_valid(_flow_box):
		_flow_box.visible = show_flow_meter   # de-emphasise the old flow bar; MomentumStack is the reward signal

	if is_instance_valid(_flow):
		_flow.on_changed.connect(_on_flow_changed)
		_on_flow_changed(_flow.get_value())
	if is_instance_valid(_score):
		_score.on_score_changed.connect(_on_score_changed)
	if is_instance_valid(_run):
		_run.on_run_finished.connect(_on_run_finished)
		_run.on_run_started.connect(_on_run_started)


func _process(delta: float) -> void:
	# Timer ticks from the RunManager getter (per-frame read, no signal needed).
	if is_instance_valid(_run):
		_timer_label.text = _format_time(_run.get_time())

	# Flow display fades when idle, snaps bright on any change (handled in _on_flow_changed).
	_flow_idle_timer += delta
	if _flow_idle_timer > fade_delay:
		_flow_box.modulate.a = lerpf(_flow_box.modulate.a, idle_alpha, clampf(delta * 5.0, 0.0, 1.0))

	_update_flow_box_position(delta)


# Float the flow multiplier near the car's screen position (comic HUD). Falls back to
# top-centre if following is off or the car can't be projected (no camera / behind it).
func _update_flow_box_position(delta: float) -> void:
	if not show_flow_meter:
		return
	var vp := get_viewport().get_visible_rect().size
	var box_w := flow_bar_width
	var box_h := _flow_box.size.y
	var center: Vector2
	var cam := get_viewport().get_camera_3d()
	if flow_follows_car and cam != null and is_instance_valid(_vehicle) and not cam.is_position_behind(_vehicle.global_position):
		center = cam.unproject_position(_vehicle.global_position) + flow_car_offset
	else:
		center = Vector2(vp.x * 0.5, 18.0 + box_h * 0.5)   # fixed top-centre fallback
	var target := center - Vector2(box_w * 0.5, box_h * 0.5)
	if _flow_box.position == Vector2.ZERO:
		_flow_box.position = target   # snap on the first frame (avoid lerping from the origin)
	else:
		_flow_box.position = _flow_box.position.lerp(target, clampf(delta * flow_follow_smooth, 0.0, 1.0))


# ----------------------------------------------------------------------------
#  Signal handlers
# ----------------------------------------------------------------------------
func _on_flow_changed(value: float) -> void:
	var ratio := value / _max_flow if _max_flow > 0.0 else 0.0
	ratio = clampf(ratio, 0.0, 1.0)
	var mult := _flow.get_multiplier() if is_instance_valid(_flow) else 1.0
	_flow_label.text = "×%.1f" % mult
	_flow_bar_fill.size = Vector2(flow_bar_width * ratio, flow_bar_height)
	var col := _flow_color(ratio)
	_flow_bar_fill.color = col
	_flow_label.add_theme_color_override("font_color", col.lerp(COL_WHITE, 0.4))
	# Snap bright on change.
	_flow_box.modulate.a = 1.0
	_flow_idle_timer = 0.0


func _on_score_changed(score: float) -> void:
	_score_label.text = "%d" % int(round(score))


func _on_run_started() -> void:
	_summary.visible = false
	if is_instance_valid(_start_panel):
		_start_panel.visible = false


func _on_run_finished(score: float, time: float) -> void:
	_summary_score.text = "%d" % int(round(score))
	_summary_time.text = "TIME   " + _format_time(time)
	_summary_breakdown.text = _build_breakdown_text()
	# Personal best (session). NEW BEST! if this run beat it, otherwise show the standing best.
	if is_instance_valid(_run) and _run.has_best():
		_best_label.text = "BEST  %d" % int(round(_run.get_best_score()))
		if _run.was_last_run_best():
			_summary_best.text = "★ NEW BEST ★"
			_summary_best.add_theme_color_override("font_color", COL_YELLOW)
		else:
			_summary_best.text = "BEST   %d" % int(round(_run.get_best_score()))
			_summary_best.add_theme_color_override("font_color", COL_WHITE)
	else:
		_summary_best.text = ""
	_summary.visible = true


# ----------------------------------------------------------------------------
#  Helpers
# ----------------------------------------------------------------------------
func _flow_color(ratio: float) -> Color:
	# cyan -> magenta -> acid-yellow as flow escalates (style ramps with skill).
	if ratio < 0.5:
		return COL_CYAN.lerp(COL_MAGENTA, ratio / 0.5)
	return COL_MAGENTA.lerp(COL_YELLOW, (ratio - 0.5) / 0.5)


func _format_time(t: float) -> String:
	var minutes := int(t) / 60
	var seconds := t - float(minutes * 60)
	return "%d:%05.2f" % [minutes, seconds]


func _build_breakdown_text() -> String:
	var lines := PackedStringArray()
	var max_flow_reached := _score.get_max_flow_reached() if is_instance_valid(_score) else 0.0
	lines.append("MAX FLOW   %.1f / %.0f" % [max_flow_reached, _max_flow])
	if is_instance_valid(_score):
		var bd := _score.get_style_breakdown()
		var keys := bd.keys()
		keys.sort()
		for k in keys:
			lines.append("%-16s +%d" % [_pretty(k), int(round(bd[k]))])
	return "\n".join(lines)


func _pretty(key: String) -> String:
	return key.capitalize()


# ----------------------------------------------------------------------------
#  UI construction
# ----------------------------------------------------------------------------
func _make_label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", maxi(4, font_size / 6))
	l.add_theme_color_override("font_outline_color", COL_OUTLINE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_ui() -> void:
	# --- Flow display: top-center ---
	_flow_box = VBoxContainer.new()
	# Positioned manually every frame so it can float near the car — see _update_flow_box_position().
	_flow_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_flow_box.add_theme_constant_override("separation", 4)
	_flow_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flow_box)

	_flow_label = _make_label("×1.0", 48, COL_CYAN)
	_flow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flow_label.custom_minimum_size = Vector2(flow_bar_width, 0)
	_flow_box.add_child(_flow_label)

	var bar_holder := Control.new()
	bar_holder.custom_minimum_size = Vector2(flow_bar_width, flow_bar_height)
	bar_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flow_box.add_child(bar_holder)

	_flow_bar_bg = ColorRect.new()
	_flow_bar_bg.color = Color(0, 0, 0, 0.5)
	_flow_bar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flow_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_holder.add_child(_flow_bar_bg)

	_flow_bar_fill = ColorRect.new()
	_flow_bar_fill.color = COL_CYAN
	_flow_bar_fill.position = Vector2.ZERO
	_flow_bar_fill.size = Vector2(0, flow_bar_height)
	_flow_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_holder.add_child(_flow_bar_fill)

	# --- Score + timer: top-right ---
	var tr := VBoxContainer.new()
	tr.anchor_left = 1.0
	tr.anchor_right = 1.0
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tr.offset_right = -20.0
	tr.offset_top = 18.0
	tr.alignment = BoxContainer.ALIGNMENT_END
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)

	_score_label = _make_label("0", 34, COL_WHITE)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr.add_child(_score_label)

	_timer_label = _make_label("0:00.00", 22, COL_CYAN)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr.add_child(_timer_label)

	# Personal best (session) — appears once a run has been completed.
	_best_label = _make_label("", 20, COL_YELLOW)
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr.add_child(_best_label)

	# --- End-of-run summary panel (hidden during play) ---
	_summary = Control.new()
	_summary.set_anchors_preset(Control.PRESET_FULL_RECT)
	_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summary.visible = false
	add_child(_summary)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summary.add_child(dim)

	var panel := VBoxContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_theme_constant_override("separation", 10)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summary.add_child(panel)

	var title := _make_label("RUN COMPLETE", 40, COL_YELLOW)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	_summary_score = _make_label("0", 72, COL_WHITE)
	_summary_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_summary_score)

	_summary_time = _make_label("TIME   0:00.00", 26, COL_CYAN)
	_summary_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_summary_time)

	_summary_best = _make_label("", 28, COL_YELLOW)
	_summary_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_summary_best)

	_summary_breakdown = _make_label("", 22, COL_WHITE)
	_summary_breakdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_summary_breakdown)

	var prompt := _make_label("Press  R  to restart", 24, COL_MAGENTA)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(prompt)

	# --- Start / READY screen (shown until the first run begins) ---
	_start_panel = Control.new()
	_start_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_start_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_start_panel)

	var sdim := ColorRect.new()
	sdim.color = Color(0, 0, 0, 0.62)
	sdim.set_anchors_preset(Control.PRESET_FULL_RECT)
	sdim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_panel.add_child(sdim)

	var spanel := VBoxContainer.new()
	spanel.anchor_left = 0.5
	spanel.anchor_top = 0.5
	spanel.anchor_right = 0.5
	spanel.anchor_bottom = 0.5
	spanel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	spanel.grow_vertical = Control.GROW_DIRECTION_BOTH
	spanel.alignment = BoxContainer.ALIGNMENT_CENTER
	spanel.add_theme_constant_override("separation", 12)
	spanel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_panel.add_child(spanel)

	var stitle := _make_label(track_title, 46, COL_CYAN)
	stitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spanel.add_child(stitle)

	var sgo := _make_label("▶  ACCELERATE TO START", 30, COL_YELLOW)
	sgo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spanel.add_child(sgo)

	var shint := _make_label("WASD drive  ·  Space jump  ·  Q wall  ·  E air-trick  ·  brake+turn drift  ·  R restart", 18, COL_WHITE)
	shint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spanel.add_child(shint)
