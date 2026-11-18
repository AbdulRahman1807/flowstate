extends SceneTree

# Phase-1 guard for the Panel Director skeleton (architecture, not look): a semantic
# event -> recipe lookup -> Composition -> hero WORD, anchored near the car, and the
# Director stays generic (unknown events compose nothing). Placement DIRECTION is
# covered by _PanelActionVectorProbe (Phase 2).
# Run:
# Godot --headless --path /Users/abdul/Desktop/Personal/flowstate/flowstate --script res://scripts/tests/_PanelDirectorProbe.gd

var _director
var _done := false
var _fail := 0


func _initialize() -> void:
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)
	_director = PanelDirector.new()
	_director.name = "PanelDirector"
	world.add_child(_director)


func _physics_process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	print("=== Panel Director Probe (Phase 1 architecture) ===")

	_check("recipe library available + has 'drift'",
		_director._library != null and _director._library.has_recipe(&"drift"))

	var before: int = _director.get_child_count()
	var comp = _director.compose(&"drift")
	var made: bool = is_instance_valid(comp) and _director.get_child_count() == before + 1
	_check("known event -> Composition created", made)

	var word_ok := false
	if made:
		var recipe = _director._library.get_recipe(&"drift")
		word_ok = comp._lockup != null and comp._lockup._word_label != null and comp._lockup._word_label.text in recipe.words
	_check("composition has a hero WORD from the recipe pool", word_ok)

	var centred := false
	if made:
		centred = (comp.position + comp.size * 0.5).distance_to(_director.get_car_anchor()) < 50.0
	_check("composition is centred on the car (v2)", centred)

	_check("unknown event -> no composition (graceful)", _director.compose(&"no_such_event") == null)

	print("RESULT: %s" % ("PASS (all checks green)" if _fail == 0 else "FAIL (%d failed)" % _fail))
	return true


func _check(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("  [%s] %s" % ["OK" if cond else "XX", label])
