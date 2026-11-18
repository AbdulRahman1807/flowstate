class_name PanelRecipeLibrary
extends Resource

# ============================================================================
#  PanelRecipeLibrary — the set of (semantic) recipes the Director can compose
# ----------------------------------------------------------------------------
#  A data asset: assign a hand-authored .tres, or fall back to default(). Lookup
#  is by event_id so the Director stays generic. Recipe DATA lives here; adding
#  an event = adding a recipe, never editing the Director.
# ============================================================================

@export var recipes: Array[PanelRecipe] = []

var _by_id: Dictionary = {}


func _index() -> void:
	_by_id.clear()
	for r in recipes:
		if r != null and r.event_id != &"":
			_by_id[r.event_id] = r


func get_recipe(event_id: StringName) -> PanelRecipe:
	if _by_id.is_empty() and not recipes.is_empty():
		_index()
	return _by_id.get(event_id, null)


func has_recipe(event_id: StringName) -> bool:
	return get_recipe(event_id) != null


# Bootstrap recipes (placeholder words) with their SEMANTIC mapping (grammar §8),
# including which lockup styles fit each event. The Director turns these into visuals.
static func default() -> PanelRecipeLibrary:
	var F := PanelGrammar.Family
	var C := PanelGrammar.Category
	var T := PanelGrammar.Tier
	var B := PanelGrammar.BackingFamily
	var L := PanelGrammar.Lockup
	var lib := PanelRecipeLibrary.new()
	lib.recipes = [
		_mk("drift",     F.SLIDE,  C.STYLE,   T.BEAT,   B.SPEED,  [L.SUFFIX],            ["SKRRT!", "SCRAPE!", "SLIDE!", "SKID!"]),
		_mk("jump",      F.LAUNCH, C.IMPACT,  T.HERO,   B.JAGGED, [L.SUFFIX, L.STACKED], ["LAUNCH!", "HOP!", "LIFTOFF!", "UP!"]),
		_mk("landing",   F.IMPACT, C.IMPACT,  T.HERO,   B.STAR,   [L.STACKED, L.BADGE],  ["SLAM!", "THUD!", "STICK!", "STOMP!"]),
		_mk("boost",     F.THRUST, C.HEAT,    T.BEAT,   B.SPEED,  [L.SUFFIX],            ["WHOOSH!", "ZOOM!", "SURGE!", "BOOST!"]),
		_mk("wall_ride", F.WALL,   C.STYLE,   T.HERO,   B.SPEED,  [L.SUFFIX, L.STACKED], ["GRIND!", "SCRAPE!", "RIDE!", "SHRED!"]),
		_mk("near_miss", F.DANGER, C.DANGER,  T.BEAT,   B.SPEED,  [L.SUFFIX],            ["WHOOSH!", "CLOSE!", "WHIFF!", "PHEW!"]),
		_mk("tier_up",   F.REWARD, C.REWARD,  T.CLIMAX, B.STAR,   [L.BADGE, L.STACKED],  ["FLOW!", "RISE!", "HYPE!", "LEVEL!"]),
		_mk("crash",     F.FAULT,  C.FAILURE, T.HERO,   B.JAGGED, [L.SUFFIX],            ["WIPEOUT!", "OOF!", "CRUNCH!", "BAIL!"]),
		_mk("wall_save", F.WALL,   C.REWARD,  T.CLIMAX, B.STAR,   [L.BADGE, L.STACKED],  ["CLUTCH!", "SAVE!", "SKRRT!", "NICE!"]),
		_mk("trick",     F.REWARD, C.STYLE,   T.HERO,   B.STAR,   [L.STACKED, L.BADGE],  ["SICK!", "STYLE!", "CLEAN!", "SLICK!"]),
		_mk("new_best",  F.REWARD, C.REWARD,  T.CLIMAX, B.STAR,   [L.BADGE],             ["NEW BEST!", "RECORD!", "LEGEND!", "PEAK!"]),
	]
	lib._index()
	return lib


static func _mk(id: String, fam: PanelGrammar.Family, cat: PanelGrammar.Category, tier: PanelGrammar.Tier, backing: PanelGrammar.BackingFamily, allowed: Array, word_list: Array) -> PanelRecipe:
	var r := PanelRecipe.new()
	r.event_id = StringName(id)
	r.family = fam
	r.category = cat
	r.default_tier = tier
	r.default_backing = backing
	r.allowed_lockups = PackedInt32Array(allowed)
	r.words = PackedStringArray(word_list)
	return r
