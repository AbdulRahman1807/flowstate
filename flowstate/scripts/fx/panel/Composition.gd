class_name Composition
extends Control

# ============================================================================
#  Composition — a bold, LAYERED comic composition around the car (v2 + visual)
# ----------------------------------------------------------------------------
#  Centred on the car (empty exclusion radius), it arranges layered actors into
#  the surrounding space along the Action Vector spine, boldly. Visual-direction
#  pass: bigger hero, hand-made backing, frame-wide action-line field, WHITE hero
#  typography over the accent supporting graphics, and real depth stacking behind
#  the word (field -> burst -> ink -> shadow -> word). The multiplier is elsewhere
#  (the persistent MomentumStack). Architecture unchanged: immutable + one conductor.
# ============================================================================

const LAYOUT_SPAN := 900.0
const HERO_GAP := 40.0
const BACKING_SCALE := 2.3          # the burst frames the word generously
const INK_SCALE := 1.7
const KINETICS_SPAN := 1800.0       # frame-wide motion field
const EMANATA_SPAN := 760.0         # marks ring the negative space around the car
const PRAISE_GAP := 110.0

const PRAISE := {
	PanelGrammar.Category.STYLE: ["CLEAN!", "SMOOTH!", "SLICK!", "STYLISH!"],
	PanelGrammar.Category.IMPACT: ["SOLID!", "PERFECT!", "SICK!"],
	PanelGrammar.Category.REWARD: ["PERFECT!", "FLAWLESS!", "HYPE!"],
	PanelGrammar.Category.DANGER: ["PHEW!", "CLOSE!", "CLUTCH!"],
	PanelGrammar.Category.HEAT: ["BLAZING!", "ON FIRE!", "HOT!"],
	PanelGrammar.Category.FAILURE: ["OOF!", "TOUGH!", "RESET!"],
}

var _av_provider: Callable
var _exclusion: float = 95.0
var _spine: Vector2 = Vector2.RIGHT

# --- frozen decision ---
var _word_text: String
var _tier: PanelGrammar.Tier = PanelGrammar.Tier.BEAT
var _family: PanelGrammar.Family = PanelGrammar.Family.SLIDE
var _backing: PanelGrammar.BackingFamily = PanelGrammar.BackingFamily.STAR
var _category: PanelGrammar.Category = PanelGrammar.Category.STYLE
var _lockup_mode: PanelGrammar.Lockup = PanelGrammar.Lockup.SUFFIX
var _color: Color = PanelTokens.CORE     # the accent hue (for supporting graphics)
var _font: Font
var _lockup: PanelLockup
var _primitives: Array[PanelPrimitive] = []

# --- motion (one conductor) ---
var _timeline: MotionTimeline
var _motion_state: MotionState
var _last_center: Vector2 = Vector2.ZERO


func setup(recipe: PanelRecipe, context: Dictionary, av_provider: Callable, exclusion: float) -> void:
	_av_provider = av_provider
	_exclusion = exclusion
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_decide(recipe, context)
	var av0: ActionVector = _av_provider.call() if _av_provider.is_valid() else null
	if av0 != null and av0.axis.length() > 0.1:
		_spine = av0.axis
	_build()
	_timeline = MotionTimeline.new()
	_timeline.configure(_tier)
	_motion_state = _timeline.state()
	_apply(_motion_state)


func _decide(recipe: PanelRecipe, _context: Dictionary) -> void:
	_word_text = recipe.pick_word()
	_tier = recipe.default_tier
	_family = recipe.family
	_backing = recipe.default_backing
	_category = recipe.category
	_color = PanelTokens.accent(_category)   # accent -> supporting graphics (hero stays white)
	_font = PanelTokens.voice(recipe.family)
	_lockup_mode = _pick_lockup(recipe.allowed_lockups)


func _build() -> void:
	size = Vector2(LAYOUT_SPAN, LAYOUT_SPAN)
	pivot_offset = size * 0.5
	var c := size * 0.5

	# Hero word (WHITE, no value) — configured first for its size.
	_lockup = PanelLockup.new()
	_lockup.configure({"word": _word_text, "value": "", "font": _font, "color": PanelTokens.CORE, "lockup": _lockup_mode})
	var hero_reach := _exclusion + _lockup.size.length() * 0.5 + HERO_GAP
	var hero_pos := c + _spine * hero_reach
	var perp := Vector2(-_spine.y, _spine.x)

	var full := _tier == PanelGrammar.Tier.HERO or _tier == PanelGrammar.Tier.CLIMAX
	# Actors DISTRIBUTED around the car (not stacked overhead): hero + burst on the
	# dominant side, ink on a flank, emanata ringing all around, praise on the counter side.
	# z-order (back -> front): field, burst, ink, HERO word, emanata, praise.
	# NOTE: the action-line field is now the persistent EnvironmentalField (the car's
	# world-speed), NOT a composition primitive — the popup lives INSIDE that field.
	var specs: Array = []
	if full:
		specs.append(["backing", hero_pos])                   # hand-made burst behind the word
		specs.append(["ink", c + perp * (_exclusion + 90.0)]) # ink on a flank (distribute around the car)
	specs.append(["hero", hero_pos])                          # white word + shadow
	if _tier != PanelGrammar.Tier.WHISPER:
		specs.append(["emanata", c])                 # accent marks ringing the negative space
	if _tier == PanelGrammar.Tier.CLIMAX:
		specs.append(["praise", c - _spine * (_exclusion + PRAISE_GAP)])

	for s in specs:
		var p := _make_primitive(s[0])
		if p != null:
			add_child(p)
			p.place_center(s[1])
			_primitives.append(p)


func _make_primitive(tag: String) -> PanelPrimitive:
	match tag:
		"hero":
			return _lockup
		"backing":
			var b := BackingPrimitive.new()
			b.configure({"color": _color, "size": _lockup.size * BACKING_SCALE})
			return b
		"ink":
			var i := InkPrimitive.new()
			i.configure({"color": _color, "size": _lockup.size * INK_SCALE})
			return i
		"kinetics":
			var k := KineticsPrimitive.new()
			k.configure({"color": _color, "size": Vector2(KINETICS_SPAN, KINETICS_SPAN), "exclusion": _exclusion, "style": KineticsPrimitive.style_for(_family)})
			return k
		"emanata":
			var e := EmanataPrimitive.new()
			e.configure({"color": _color, "size": Vector2(EMANATA_SPAN, EMANATA_SPAN)})
			return e
		"praise":
			var pool: Array = PRAISE.get(_category, ["NICE!"])
			var pr := PanelLockup.new()
			pr.configure({"word": pool[randi() % pool.size()], "value": "", "font": _font, "color": _color, "lockup": PanelGrammar.Lockup.SUFFIX})
			return pr
	return null


func _process(dt: float) -> void:
	_timeline.advance(dt)
	_motion_state = _timeline.state()
	if _motion_state.finished:
		queue_free()
		return
	_apply(_motion_state)


func _apply(st: MotionState) -> void:
	var center := _last_center
	var av: ActionVector = null
	if _av_provider.is_valid():
		av = _av_provider.call()
		if av != null:
			center = av.origin   # centred on the car (its empty centre)
			_last_center = center
	pivot_offset = size * 0.5
	scale = Vector2(st.scale * (1.0 + st.squash), st.scale / (1.0 + st.squash))
	modulate.a = st.alpha
	rotation = st.spin
	position = center + st.drift - size * 0.5
	if av != null:
		for p in _primitives:
			p.apply(st, av)


func get_motion_state() -> MotionState:
	return _motion_state


func _pick_lockup(allowed: PackedInt32Array) -> PanelGrammar.Lockup:
	if allowed.is_empty():
		return PanelGrammar.Lockup.SUFFIX
	return allowed[randi() % allowed.size()] as PanelGrammar.Lockup
