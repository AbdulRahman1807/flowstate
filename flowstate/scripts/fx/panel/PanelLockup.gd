class_name PanelLockup
extends PanelPrimitive

# ============================================================================
#  PanelLockup — the hero WORD (+ optional VALUE) with physical presence
# ----------------------------------------------------------------------------
#  A composable primitive hosting the hero lettering. It carries a dark drop
#  SHADOW behind the word for depth, so the word reads as an inked graphic sitting
#  ON the composition rather than text floating in space. WHITE fill + thick black
#  ink is the hero-typography convention (the accent hue lives on the supporting
#  graphics). value may be "" (the v2 hero is word-only).
# ============================================================================

const HERO_SIZE := 132
const VALUE_RATIO := 0.62
const SUFFIX_GAP := 14.0
const OUTLINE_RATIO := 0.26
const SHADOW_OFFSET := Vector2(7.0, 9.0)

var _word_label: Label
var _value_label: Label
var _shadow_label: Label


# config: { word, value, lockup, font, color }
func configure(config: Dictionary) -> void:
	build(
		config.get("word", ""),
		config.get("value", ""),
		config.get("lockup", PanelGrammar.Lockup.SUFFIX),
		config.get("font", null),
		config.get("color", PanelTokens.CORE))


func apply(_state: MotionState, av: ActionVector) -> void:
	_apply_local(Vector2.ZERO, av.roll, 1.0, 1.0)   # bank to the car; ride the master


func build(word: String, value: String, mode: PanelGrammar.Lockup, font: Font = null, color: Color = PanelTokens.CORE) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f: Font = font if font != null else _fallback_font()
	var value_size := int(round(HERO_SIZE * VALUE_RATIO))
	var w := _text_size(word, f, HERO_SIZE)

	# Drop shadow (behind the word) for physical presence.
	_shadow_label = _make_label(word, f, HERO_SIZE, Color(0, 0, 0, 0.55), false)
	_shadow_label.size = w
	add_child(_shadow_label)

	_word_label = _make_label(word, f, HERO_SIZE, color, true)
	_word_label.size = w
	add_child(_word_label)

	if value == "":
		_word_label.position = Vector2.ZERO
		_shadow_label.position = SHADOW_OFFSET
		size = w
		pivot_offset = size * 0.5
		return

	_value_label = _make_label(value, f, value_size, color, true)
	add_child(_value_label)
	var v := _text_size(value, f, value_size)
	_value_label.size = v

	var total := Vector2.ZERO
	match mode:
		PanelGrammar.Lockup.STACKED:
			total = Vector2(maxf(w.x, v.x), w.y + v.y * 0.72)
			_word_label.position = Vector2((total.x - w.x) * 0.5, 0.0)
			_value_label.position = Vector2((total.x - v.x) * 0.5, w.y * 0.92)
		PanelGrammar.Lockup.BADGE:
			total = Vector2(w.x + v.x * 0.45, w.y + v.y * 0.35)
			_word_label.position = Vector2(0.0, v.y * 0.35)
			_value_label.position = Vector2(w.x - v.x * 0.5, 0.0)
			_value_label.pivot_offset = v * 0.5
			_value_label.rotation = deg_to_rad(8.0)
		_:
			total = Vector2(w.x + SUFFIX_GAP + v.x, maxf(w.y, v.y))
			_word_label.position = Vector2(0.0, (total.y - w.y) * 0.5)
			_value_label.position = Vector2(w.x + SUFFIX_GAP, total.y - v.y)

	_shadow_label.position = _word_label.position + SHADOW_OFFSET
	size = total
	pivot_offset = size * 0.5


func _make_label(text: String, font: Font, font_size: int, color: Color, outline: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if outline:
		l.add_theme_constant_override("outline_size", maxi(10, int(font_size * OUTLINE_RATIO)))
		l.add_theme_color_override("font_outline_color", PanelTokens.INK)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _text_size(text: String, font: Font, font_size: int) -> Vector2:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size) + Vector2(0.0, font_size * 0.3)


func _fallback_font() -> Font:
	var f := load("res://assets/fonts/Bangers.ttf") as Font
	return f if f != null else ThemeDB.fallback_font
