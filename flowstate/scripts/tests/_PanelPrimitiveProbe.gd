extends SceneTree

# Phase-5 guard for the PRIMITIVE SYSTEM. Verifies the modular contract: the tier
# selects a set of PanelPrimitives, they're dressed with semantic tokens, each one
# works standalone (no sibling awareness), every primitive derives its motion from
# the SINGLE shared timeline, and the structure stays immutable through motion.
# Run:
# Godot --headless --path /Users/abdul/Desktop/Personal/flowstate/flowstate --script res://scripts/tests/_PanelPrimitiveProbe.gd

var _dir: PanelDirector
var _done := false
var _fail := 0


func _initialize() -> void:
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)
	_dir = PanelDirector.new()
	_dir.name = "PanelDirector"
	world.add_child(_dir)


func _physics_process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	print("=== Panel Primitive Probe (Phase 5) ===")

	# HERO-tier event -> full primitive set, all PanelPrimitive.
	var comp: Composition = _dir.compose(&"jump", {"multiplier": 4.0})
	var prims: Array = comp._primitives if comp != null else []
	_check("HERO tier assembles 4 primitives (field is now environmental)", prims.size() == 4)
	var all_prim := true
	for p in prims:
		if not (p is PanelPrimitive):
			all_prim = false
	_check("every element is a PanelPrimitive", all_prim)

	var hb := false; var hi := false; var hh := false; var he := false
	for p in prims:
		if p is BackingPrimitive: hb = true
		elif p is InkPrimitive: hi = true
		elif p is PanelLockup: hh = true
		elif p is EmanataPrimitive: he = true
	_check("set includes backing/ink/hero/emanata", hb and hi and hh and he)

	# Colour hierarchy: WHITE hero typography; the accent lives on the supporting graphics.
	var magenta := PanelTokens.accent(PanelGrammar.Category.IMPACT)
	_check("hero typography is white", comp._lockup._word_label.get_theme_color(&"font_color") == PanelTokens.CORE)
	var backing: BackingPrimitive = null
	for p in comp._primitives:
		if p is BackingPrimitive:
			backing = p
	_check("supporting backing carries the accent hue", backing != null and backing._color == magenta)

	# Tier drives the primitive count (a BEAT composes fewer than a HERO).
	var beat: Composition = _dir.compose(&"drift", {"multiplier": 2.0})
	_check("lower tier composes fewer primitives", beat._primitives.size() < prims.size())

	# Modularity: a primitive works ALONE (no siblings, no composition).
	var solo := KineticsPrimitive.new()
	root.get_child(0).add_child(solo)
	solo.configure({"color": magenta, "size": Vector2(200, 140)})
	solo.place_center(Vector2(100, 100))
	var av := ActionVector.new(); av.axis = Vector2.RIGHT; av.roll = 0.2
	var st := MotionState.new(); st.phase = MotionTimeline.Phase.IMPACT; st.phase_t = 0.5
	solo.apply(st, av)
	_check("a primitive renders standalone (no siblings needed)", is_instance_valid(solo))

	# One conductor: a primitive derives from the shared timeline (emanata pops at impact, fades by decay).
	var em: EmanataPrimitive = null
	for p in comp._primitives:
		if p is EmanataPrimitive:
			em = p
	var tl := MotionTimeline.new(); tl.configure(PanelGrammar.Tier.HERO)
	var total := tl.duration()
	comp._apply(_at(tl, total * 0.16))
	var a_impact: float = em.modulate.a
	comp._apply(_at(tl, total * 0.96))
	var a_decay: float = em.modulate.a
	_check("primitives derive from the shared state (impact > decay)", a_impact > a_decay)

	# Immutability: structure unchanged through motion.
	var n: int = comp._primitives.size()
	for i in range(8):
		comp._apply(_at(tl, total * float(i) / 8.0))
	_check("structure stays immutable through motion", comp._primitives.size() == n and comp.get_child_count() == n)

	print("RESULT: %s" % ("PASS (all checks green)" if _fail == 0 else "FAIL (%d failed)" % _fail))
	return true


func _at(tl: MotionTimeline, t: float) -> MotionState:
	tl._elapsed = t
	return tl.state()


func _check(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("  [%s] %s" % ["OK" if cond else "XX", label])
