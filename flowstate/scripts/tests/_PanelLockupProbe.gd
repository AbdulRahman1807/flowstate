extends SceneTree

# Lockup COMPONENT guard. The multiplier moved out of the composition into the
# MomentumStack (v2), so this tests PanelLockup directly as a reusable word(+value)
# actor: word+value fuse into one graphic (shared font, one subtree, hierarchy),
# word-only builds, and all three modes build.
# Run:
# Godot --headless --path /Users/abdul/Desktop/Personal/flowstate/flowstate --script res://scripts/tests/_PanelLockupProbe.gd

var _done := false
var _fail := 0


func _initialize() -> void:
	root.add_child(Node.new())   # a tree parent for the lockups


func _physics_process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	print("=== Panel Lockup Probe (component) ===")
	var parent := root.get_child(0)

	var lk := PanelLockup.new()
	parent.add_child(lk)
	lk.build("SKRRT", "×4", PanelGrammar.Lockup.SUFFIX)
	_check("word + value both present", lk._word_label != null and lk._value_label != null)
	_check("value reads as a multiplier (×N)", lk._value_label != null and lk._value_label.text.begins_with("×"))
	_check("value lives inside the lockup subtree (one graphic)", lk._value_label != null and lk._value_label.get_parent() == lk)
	_check("word + value share the same font", lk._word_label.get_theme_font(&"font") == lk._value_label.get_theme_font(&"font"))
	_check("value is a step below the hero word (hierarchy)",
		lk._value_label.get_theme_font_size(&"font_size") < lk._word_label.get_theme_font_size(&"font_size"))

	var wo := PanelLockup.new()
	parent.add_child(wo)
	wo.build("CLEAN", "", PanelGrammar.Lockup.SUFFIX)
	_check("word-only build (no value element)", wo._value_label == null)

	var modes_ok := true
	for m in [PanelGrammar.Lockup.SUFFIX, PanelGrammar.Lockup.STACKED, PanelGrammar.Lockup.BADGE]:
		var t := PanelLockup.new()
		parent.add_child(t)
		t.build("WHAM", "×5", m)
		if t._word_label == null or t._value_label == null or t.size.x <= 0.0:
			modes_ok = false
	_check("all three lockup modes (suffix/stacked/badge) build", modes_ok)

	print("RESULT: %s" % ("PASS (all checks green)" if _fail == 0 else "FAIL (%d failed)" % _fail))
	return true


func _check(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("  [%s] %s" % ["OK" if cond else "XX", label])
