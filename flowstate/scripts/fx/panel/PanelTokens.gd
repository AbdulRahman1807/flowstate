class_name PanelTokens
extends RefCounted

# ============================================================================
#  PanelTokens — the visual identity tokens (grammar §1 / §8)
# ----------------------------------------------------------------------------
#  Maps SEMANTICS to appearance: a category -> its accent hue, a maneuver family
#  -> its type voice, a backing family -> its burst texture. The Composition reads
#  these to dress its primitives, so the look stays cohesive and on-palette.
#  (04_Art_Direction: dark bg + cyan/magenta/acid-yellow + white core.)
# ============================================================================

const CORE := Color(1, 1, 1)
const INK := Color(0, 0, 0, 0.9)

const _ACCENT := {
	PanelGrammar.Category.STYLE:   Color(0.0, 1.0, 0.8),    # cyan
	PanelGrammar.Category.IMPACT:  Color(1.0, 0.18, 0.47),  # magenta
	PanelGrammar.Category.REWARD:  Color(0.91, 1.0, 0.0),   # acid yellow
	PanelGrammar.Category.DANGER:  Color(0.91, 1.0, 0.0),   # acid yellow
	PanelGrammar.Category.HEAT:    Color(1.0, 0.48, 0.0),   # orange
	PanelGrammar.Category.FAILURE: Color(0.5, 0.5, 0.56),   # grey ink
}

const _VOICE := {
	PanelGrammar.Family.SLIDE:  "LuckiestGuy.ttf",
	PanelGrammar.Family.LAUNCH: "Bungee.ttf",
	PanelGrammar.Family.IMPACT: "Anton.ttf",
	PanelGrammar.Family.WALL:   "LuckiestGuy.ttf",
	PanelGrammar.Family.DANGER: "PermanentMarker.ttf",
	PanelGrammar.Family.THRUST: "Bungee.ttf",
	PanelGrammar.Family.REWARD: "Bangers.ttf",
	PanelGrammar.Family.FAULT:  "Anton.ttf",
}

const _BACKING := {
	PanelGrammar.BackingFamily.STAR:   "burst_star.png",
	PanelGrammar.BackingFamily.SPLAT:  "burst_splat.png",
	PanelGrammar.BackingFamily.SPEED:  "burst_speed.png",
	PanelGrammar.BackingFamily.JAGGED: "burst_jagged.png",
	PanelGrammar.BackingFamily.ZAP:    "burst_zap.png",
}


static func accent(category: PanelGrammar.Category) -> Color:
	return _ACCENT.get(category, CORE)


static func voice(family: PanelGrammar.Family) -> Font:
	var file: String = _VOICE.get(family, "Bangers.ttf")
	var f := load("res://assets/fonts/" + file) as Font
	return f if f != null else ThemeDB.fallback_font


static func backing_texture(backing: PanelGrammar.BackingFamily) -> Texture2D:
	var file: String = _BACKING.get(backing, "burst_star.png")
	return load("res://assets/textures/sfx/" + file) as Texture2D
