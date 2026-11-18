extends SceneTree

# Guard for the ACTION LINE FIELD (evolved KineticsPrimitive). Verifies one
# procedural generator with per-family styles produces a VARIED field of strokes
# (not a uniform texture), that radial fields wrap the car's exclusion, that
# families map to distinct styles, and that it still derives its reveal from the
# shared MotionState.
# Run:
# Godot --headless --path /Users/abdul/Desktop/Personal/flowstate/flowstate --script res://scripts/tests/_PanelFieldProbe.gd

var _done := false
var _fail := 0


func _initialize() -> void:
	root.add_child(Node.new())


func _physics_process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	print("=== Action Line Field Probe ===")
	var parent := root.get_child(0)

	# Families map to distinct field styles (one system, many looks).
	var s_drift := KineticsPrimitive.style_for(PanelGrammar.Family.SLIDE)
	var s_boost := KineticsPrimitive.style_for(PanelGrammar.Family.THRUST)
	var s_impact := KineticsPrimitive.style_for(PanelGrammar.Family.IMPACT)
	var s_reward := KineticsPrimitive.style_for(PanelGrammar.Family.REWARD)
	_check("families map to distinct field styles",
		s_drift != s_impact and s_impact != s_reward and s_boost != s_impact)

	# An impact (RAYS) field generates MANY strokes.
	var f := KineticsPrimitive.new()
	parent.add_child(f)
	f.configure({"color": Color(0, 1, 0.8), "size": Vector2(600, 600), "exclusion": 90.0, "style": s_impact})
	_check("field generates many strokes", f._quads.size() >= 15)

	# Strokes VARY in length — not a uniform repeated texture.
	var lo := 1.0e9
	var hi := 0.0
	for q in f._quads:
		var l: float = q[0].distance_to(q[3])
		lo = minf(lo, l)
		hi = maxf(hi, l)
	_check("stroke lengths vary (not uniform)", hi - lo > 20.0)

	# The radial field wraps the car: strokes start outside the exclusion radius.
	var c := f.size * 0.5
	var min_start := 1.0e9
	for q in f._quads:
		var base: Vector2 = (q[0] + q[1]) * 0.5
		min_start = minf(min_start, base.distance_to(c))
	_check("radial field starts outside the car exclusion", min_start >= 80.0)

	# A different style also generates (streaks).
	var f2 := KineticsPrimitive.new()
	parent.add_child(f2)
	f2.configure({"color": Color(0, 1, 0.8), "size": Vector2(600, 600), "exclusion": 90.0, "style": s_boost})
	_check("a different style also generates a field", f2._quads.size() >= 8)

	# Still derives its reveal from the shared MotionState (impact > decay).
	var av := ActionVector.new(); av.axis = Vector2.RIGHT
	var imp := MotionState.new(); imp.phase = MotionTimeline.Phase.IMPACT; imp.phase_t = 0.5; imp.scale = 1.0; imp.alpha = 1.0
	var dec := MotionState.new(); dec.phase = MotionTimeline.Phase.DECAY; dec.phase_t = 0.9; dec.scale = 1.0; dec.alpha = 0.2
	f.apply(imp, av)
	var a_imp: float = f.modulate.a
	f.apply(dec, av)
	var a_dec: float = f.modulate.a
	_check("field reveals from the shared state (impact > decay)", a_imp > a_dec)

	print("RESULT: %s" % ("PASS (all checks green)" if _fail == 0 else "FAIL (%d failed)" % _fail))
	return true


func _check(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("  [%s] %s" % ["OK" if cond else "XX", label])
