extends SceneTree

# Panel Director v2 guard — the SPATIAL composition model. Verifies the car is the
# empty centre (exclusion radius), actors occupy distinct zones around it via the
# Action Vector spine (hero on the dominant side, praise counter-balancing), the
# composition is centred on the car, and the multiplier now lives in a separate
# PERSISTENT MomentumStack that accumulates + caps.
# Run:
# Godot --headless --path /Users/abdul/Desktop/Personal/flowstate/flowstate --script res://scripts/tests/_PanelSpatialProbe.gd

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
	print("=== Panel Spatial Probe (v2) ===")

	# A CLIMAX event composes a full multi-actor composition (incl. praise).
	var comp: Composition = _dir.compose(&"tier_up")
	var prims: Array = comp._primitives if comp != null else []
	_check("CLIMAX composes a multi-actor composition (>= 5 actors)", prims.size() >= 5)

	# The composition is CENTRED on the car (its empty centre), not offset beside it.
	var car := _dir.get_car_anchor()
	_check("composition is centred on the car", (comp.position + comp.size * 0.5).distance_to(car) < 5.0)

	# Car owns an empty exclusion radius: no MAJOR actor sits inside it (kinetics is
	# the centred bridge and is allowed at centre).
	var C := comp.size * 0.5
	var excl := _dir.exclusion_radius
	var clear := true
	for p in prims:
		if p is PanelLockup or p is BackingPrimitive:   # only the SOLID actors must clear the car
			if p._base_center.distance_to(C) < excl:
				clear = false
	_check("no major actor occupies the car's exclusion radius", clear)

	# The Action Vector is a SPINE: hero leads the dominant side, praise counter-balances.
	var spine: Vector2 = comp._spine
	var hero_side: float = (comp._lockup._base_center - C).dot(spine)
	var praise: PanelLockup = null
	for p in prims:
		if p is PanelLockup and p != comp._lockup:
			praise = p
	var praise_ok: bool = praise != null and (praise._base_center - C).dot(spine) < 0.0
	_check("hero occupies the dominant (spine) side", hero_side > 0.0)
	_check("praise counter-balances the opposite side", praise_ok)

	# Actors occupy DISTINCT zones (not all stacked at one point).
	var distinct := comp._lockup._base_center.distance_to(_find_flank(prims, C)) > excl
	_check("actors occupy distinct zones (not one point)", distinct)

	# MomentumStack: the multiplier is now a separate PERSISTENT, accumulating stack.
	_check("director owns a persistent MomentumStack", _dir._momentum != null)
	_dir.push_multiplier(2.0)
	_dir.push_multiplier(3.0)
	_dir.push_multiplier(4.0)
	_check("stack accumulates entries", _dir._momentum._entries.size() == 3)
	for v in [5.0, 6.0, 7.0, 8.0, 9.0]:
		_dir.push_multiplier(v)
	_check("stack caps the history (drops oldest)", _dir._momentum._entries.size() == MomentumStack.MAX)
	_check("newest entry is at the front", _dir._momentum._entries[0].text == "×9")

	print("RESULT: %s" % ("PASS (all checks green)" if _fail == 0 else "FAIL (%d failed)" % _fail))
	return true


func _find_flank(prims: Array, c: Vector2) -> Vector2:
	for p in prims:
		if p is EmanataPrimitive:
			return p._base_center
	return c


func _check(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("  [%s] %s" % ["OK" if cond else "XX", label])
