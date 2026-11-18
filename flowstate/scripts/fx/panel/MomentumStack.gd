class_name MomentumStack
extends Control

# ============================================================================
#  MomentumStack — the PERSISTENT momentum / combo memory (Panel Director v2)
# ----------------------------------------------------------------------------
#  The primary reward signal. Motion language is a COMIC STAMP, not UI easing:
#    instant appearance -> heavy scale overshoot (SLAM) -> tiny elastic settle,
#    and the moment a new multiplier lands it PUNCHES every previous entry back
#    into history (they recoil smaller/dimmer at once — never a motionless idle).
#  The newest DOMINATES (largest, brightest, strongest outline+shadow); older
#  entries shrink, desaturate, drift, and overlap like layers of printed comic
#  graphics accumulating on the page. Persistent + car-anchored + on-screen.
#  Architecture unchanged: same Control, same init()/push()/_entries contract.
# ============================================================================

const MAX := 5
const SPACING := 60.0          # tight -> new entries OVERLAP the previous like stacked prints
const DEMOTE_LERP := 24.0      # position/dim snap FAST (a shove, not a float)
const STAMP_TIME := 0.15       # newest: SLAM in -> overshoot -> settle
const STAMP_SCALE := 2.0       # heavy overshoot on arrival
const PUNCH_TIME := 0.16       # existing entries recoil this fast when shoved back
const LIFETIME := 5.0
const FADE := 0.5

const HERO_SIZE := 152         # oversized — one of the largest persistent elements on screen
const OUTLINE := 34
const SHADOW_OFF := 7          # drop shadow -> lifts the newest off the page
const MIN_SCALE := 0.30        # oldest shrinks hard
const MIN_ALPHA := 0.14
const MIN_DIM := 0.55          # oldest desaturates/recedes toward the background

@export var zone_offset: Vector2 = Vector2(170.0, -150.0)   # stable screen offset from the car
@export var stack_dir: Vector2 = Vector2(0.35, -1.0)        # direction older entries drift

var _anchor_provider: Callable
var _font: Font
var _entries: Array[Label] = []   # newest first


func init(anchor_provider: Callable) -> void:
	_anchor_provider = anchor_provider
	_font = load("res://assets/fonts/Bangers.ttf") as Font
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func push(value: float) -> void:
	var l := _make_label("×" + _fmt(value))
	add_child(l)                                          # last child -> drawn ON TOP of history
	l.reset_size()
	l.pivot_offset = l.size * 0.5
	l.rotation_degrees = randf_range(-4.0, 4.0)           # hand-stamped print tilt (kept)
	l.modulate = Color(1, 1, 1, 1)                        # INSTANT appearance (no fade-in), full brightness
	l.position = _base() - l.size * 0.5                   # snap to the newest slot (no drift-from-origin)
	l.set_meta("born", _now())
	# The SLAM: oversized -> overshoot below rest -> tiny elastic settle.
	l.scale = Vector2(STAMP_SCALE, STAMP_SCALE)
	_stamp_scale(l, Vector2.ONE, STAMP_TIME)
	_entries.push_front(l)

	# A new stamp PUNCHES the whole stack back into history at once.
	for i in _entries.size():
		if i == 0:
			continue
		var s := _rank_scale(i)
		_stamp_scale(_entries[i], Vector2(s, s), PUNCH_TIME)   # visible recoil, not a slow lerp

	while _entries.size() > MAX:
		_retire(_entries.pop_back())


func _process(dt: float) -> void:
	var base := _base()
	var dir := stack_dir.normalized()
	var vp := get_viewport_rect().size
	var k := clampf(dt * DEMOTE_LERP, 0.0, 1.0)

	for i in range(_entries.size() - 1, -1, -1):
		var l := _entries[i]
		if not is_instance_valid(l):
			_entries.remove_at(i)
			continue

		var tgt_scale := _rank_scale(i)                   # newest full-size; older shrink hard
		var dim := lerpf(1.0, MIN_DIM, _rank_t(i))        # older recede toward the background
		var tgt_alpha := lerpf(1.0, MIN_ALPHA, _rank_t(i))

		# aging: even without a new push, an entry fades out after its lifetime.
		var age := _now() - float(l.get_meta("born", _now()))
		if age > LIFETIME:
			tgt_alpha *= clampf(1.0 - (age - LIFETIME) / FADE, 0.0, 1.0)
			if age > LIFETIME + FADE:
				_entries.remove_at(i)
				l.queue_free()
				continue

		var tgt_centre := base + dir * (float(i) * SPACING)
		tgt_centre.x = clampf(tgt_centre.x, 120.0, maxf(120.0, vp.x - 120.0))
		tgt_centre.y = clampf(tgt_centre.y, 120.0, maxf(120.0, vp.y - 120.0))
		l.pivot_offset = l.size * 0.5
		l.position = l.position.lerp(tgt_centre - l.size * 0.5, k)   # shoved into history (fast)
		l.modulate = l.modulate.lerp(Color(dim, dim, dim, tgt_alpha), k)
		# scale is owned by the stamp/punch tween during its window; otherwise settle.
		if _now() >= float(l.get_meta("stamp_until", 0.0)):
			l.scale = l.scale.lerp(Vector2(tgt_scale, tgt_scale), k)


# --- helpers -----------------------------------------------------------------

func _rank_t(i: int) -> float:
	return clampf(float(i) / float(maxi(MAX - 1, 1)), 0.0, 1.0)


func _rank_scale(i: int) -> float:
	return lerpf(1.0, MIN_SCALE, _rank_t(i))


# A single hard "stamp" tween on scale (overshoot + settle). Kills any prior one so
# a rapid combo re-punches cleanly instead of two tweens fighting.
func _stamp_scale(l: Label, target: Vector2, dur: float) -> void:
	if l.has_meta("tw"):
		var prev = l.get_meta("tw")
		if prev is Tween and prev.is_valid():
			prev.kill()
	l.set_meta("stamp_until", _now() + dur)
	var tw := create_tween()
	tw.tween_property(l, "scale", target, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	l.set_meta("tw", tw)


func _base() -> Vector2:
	if _anchor_provider.is_valid():
		return _anchor_provider.call() + zone_offset
	return zone_offset


func _retire(l: Label) -> void:
	if is_instance_valid(l):
		var prev = l.get_meta("tw", null)
		if prev is Tween and prev.is_valid():
			prev.kill()
		var tw := create_tween()
		tw.tween_property(l, "modulate:a", 0.0, FADE)
		tw.tween_callback(l.queue_free)


func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	var f: Font = _font if _font != null else ThemeDB.fallback_font
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", HERO_SIZE)   # the PRIMARY reward signal
	l.add_theme_color_override("font_color", PanelTokens.accent(PanelGrammar.Category.REWARD))
	l.add_theme_constant_override("outline_size", OUTLINE)
	l.add_theme_color_override("font_outline_color", PanelTokens.INK)
	# drop shadow: lifts the newest off the page (fades with modulate, so newest is strongest).
	l.add_theme_color_override("font_shadow_color", PanelTokens.INK)
	l.add_theme_constant_override("shadow_offset_x", SHADOW_OFF)
	l.add_theme_constant_override("shadow_offset_y", SHADOW_OFF)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _fmt(v: float) -> String:
	if absf(v - roundf(v)) < 0.05:
		return "%d" % int(roundf(v))
	return "%.1f" % v


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
