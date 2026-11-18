class_name PanelRecipe
extends Resource

# ============================================================================
#  PanelRecipe — purely SEMANTIC description of one gameplay event
# ----------------------------------------------------------------------------
#  A recipe says WHAT happened, never HOW it looks. No screen offsets, placement,
#  timings, easing curves, layout, or rendering behaviour ever live here — those
#  belong to the Panel Director (interpretation) and the Composition (rendering).
#  The Director reads recipes generically, so adding an event = adding a recipe.
#
#  Fields are all semantic gameplay meaning. They are consumed by the grammar:
#    family   -> how the Action Vector is derived (Phase 2)
#    category -> tokens / hue / voice (later)
#    tier     -> emphasis hierarchy (later)
#    backing  -> burst-shape meaning (later)
#    words    -> hero word pool
# ============================================================================

@export var event_id: StringName = &""
@export var family: PanelGrammar.Family = PanelGrammar.Family.SLIDE        ## the KIND of maneuver (drives the Action Vector)
@export var category: PanelGrammar.Category = PanelGrammar.Category.STYLE  ## emotional class (maps to tokens later)
@export var default_tier: PanelGrammar.Tier = PanelGrammar.Tier.BEAT       ## semantic emphasis / importance
@export var default_backing: PanelGrammar.BackingFamily = PanelGrammar.BackingFamily.STAR  ## which burst-shape meaning fits
@export var allowed_lockups: PackedInt32Array = PackedInt32Array()         ## which lockup styles fit (values are PanelGrammar.Lockup); empty -> suffix
@export var words: PackedStringArray = []                                  ## hero WORD pool


func pick_word() -> String:
	if words.is_empty():
		return String(event_id).to_upper()
	return words[randi() % words.size()]
