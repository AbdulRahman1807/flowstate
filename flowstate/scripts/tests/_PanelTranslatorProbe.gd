extends SceneTree

# Phase-6 guard for the gameplay->compositor bridge. Verifies the PanelEventTranslator
# turns gameplay signals into the RIGHT semantic events (drift->drift vocabulary, etc.),
# gates tiny landings, fires boost once on activation, dedups within a cooldown, lets a
# trick/crash verdict CLAIM its landing (one composition per touchdown), maps the wall
# verbs, converts continuous Flow into discrete tier_up moments feeding the MomentumStack,
# and fires new_best only on an actual personal best — compositor untouched throughout.
# Run:
# Godot --headless --path /Users/abdul/Desktop/Personal/flowstate/flowstate --script res://scripts/tests/_PanelTranslatorProbe.gd

class StubVehicle extends Node:
	signal drift_started
	signal jumped(direction: Vector3)
	signal landed(impact_velocity: float)
	signal trick_landed(degrees: float, clean: bool)
	var boosting := false
	func is_boost_active() -> bool:
		return boosting

class StubWallRiding extends Node:
	signal on_wall_attach(entry_speed: float, wall_normal: Vector3)
	signal on_wall_jump(speed_at_jump: float)
	signal on_near_miss()
	signal on_wall_save(speed: float, wall_normal: Vector3)

class StubFlow extends Node:
	signal on_changed(new_value: float)
	var mult := 1.0
	func get_multiplier() -> float:
		return mult

class StubRunManager extends Node:
	signal on_run_finished(score: float, time: float)
	var best := false
	func was_last_run_best() -> bool:
		return best

var _dir: PanelDirector
var _veh: StubVehicle
var _wall: StubWallRiding
var _flow: StubFlow
var _rm: StubRunManager
var _tr: PanelEventTranslator
var _done := false
var _fail := 0


func _initialize() -> void:
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)
	_dir = PanelDirector.new(); _dir.name = "PanelDirector"; world.add_child(_dir)
	_veh = StubVehicle.new(); _veh.name = "Vehicle"; world.add_child(_veh)
	_wall = StubWallRiding.new(); _wall.name = "WallRiding"; world.add_child(_wall)
	_flow = StubFlow.new(); _flow.name = "FlowSystem"; world.add_child(_flow)
	_rm = StubRunManager.new(); _rm.name = "RunManager"; world.add_child(_rm)
	_tr = PanelEventTranslator.new(); _tr.name = "Translator"; world.add_child(_tr)
	_tr.init(_veh, _dir)
	_tr.init_wall_riding(_wall)
	_tr.init_flow(_flow)
	_tr.init_run_manager(_rm)


func _physics_process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	print("=== Panel Event Translator Probe (Phase 6) ===")

	# --- 6A core movement -----------------------------------------------------
	# Drift -> a DRIFT composition (correct vocabulary — the whole point).
	_veh.drift_started.emit()
	_check("drift signal -> drift composition (drift vocabulary)", _tr._last_emit.has(&"drift") and _last_word_in(&"drift"))

	# Jump.
	_veh.jumped.emit(Vector3.UP)
	_check("jump signal -> jump event", _tr._last_emit.has(&"jump"))

	# Landing: tiny impact ignored; meaningful impact fires (held one frame first).
	_veh.landed.emit(2.0)
	_tr._process(0.0)
	_check("tiny landing ignored (below threshold)", not _tr._last_emit.has(&"landing"))
	_veh.landed.emit(12.0)
	_check("landing held for the trick verdict (not emitted same-frame)", not _tr._last_emit.has(&"landing"))
	_tr._process(0.0)
	_check("meaningful landing -> landing event (next frame)", _tr._last_emit.has(&"landing"))

	# Boost: fires once on the activation transition, not while held.
	_veh.boosting = true
	_tr._process(0.0)
	_check("boost activation -> boost event", _tr._last_emit.has(&"boost"))
	var t_boost: float = _tr._last_emit[&"boost"]
	_tr._process(0.0)
	_check("boost does not re-fire while held", _tr._last_emit[&"boost"] == t_boost)

	# Dedup: a duplicate within the cooldown is suppressed (no frame spam).
	var t_drift: float = _tr._last_emit[&"drift"]
	_veh.drift_started.emit()
	_check("duplicate within cooldown suppressed", _tr._last_emit[&"drift"] == t_drift)

	# --- 6B ---------------------------------------------------------------------
	_tr.event_cooldown = 0.0   # timing checks done — the rest verifies routing

	# A clean trick claims its landing: ONE composition (trick), no generic slam.
	var t_landing: float = _tr._last_emit[&"landing"]
	_veh.landed.emit(15.0)
	_veh.trick_landed.emit(360.0, true)
	_tr._process(0.0)
	_check("clean trick -> trick event (trick vocabulary)", _tr._last_emit.has(&"trick") and _last_word_in(&"trick"))
	_check("trick claims the landing (no double composition)", _tr._last_emit[&"landing"] == t_landing)

	# A botched trick -> crash (and still claims the landing).
	_veh.landed.emit(15.0)
	_veh.trick_landed.emit(180.0, false)
	_tr._process(0.0)
	_check("botched trick -> crash event", _tr._last_emit.has(&"crash"))
	_check("crash claims the landing too", _tr._last_emit[&"landing"] == t_landing)

	# Wall verbs.
	_wall.on_wall_attach.emit(20.0, Vector3.RIGHT)
	_check("wall attach -> wall_ride event", _tr._last_emit.has(&"wall_ride"))
	var t_jump: float = _tr._last_emit[&"jump"]
	_wall.on_wall_jump.emit(15.0)
	_check("wall jump -> jump event", _tr._last_emit[&"jump"] != t_jump)
	_wall.on_near_miss.emit()
	_check("near miss -> near_miss event", _tr._last_emit.has(&"near_miss"))
	_wall.on_wall_save.emit(25.0, Vector3.RIGHT)
	_check("wall save -> wall_save event", _tr._last_emit.has(&"wall_save"))

	# Flow -> discrete tiers: crossing UP composes tier_up + pushes the multiplier
	# onto the MomentumStack; dropping is silent; re-crossing fires again.
	_flow.mult = 1.4
	_flow.on_changed.emit(1.2)
	_check("flow crossing tier 1 -> tier_up event", _tr._last_emit.has(&"tier_up"))
	_check("tier_up pushes the multiplier onto the MomentumStack", _dir._momentum._entries.size() == 1)
	var t_tier: float = _tr._last_emit[&"tier_up"]
	_flow.on_changed.emit(1.8)
	_check("flow rising within a tier is silent", _tr._last_emit[&"tier_up"] == t_tier and _dir._momentum._entries.size() == 1)
	_flow.on_changed.emit(0.4)
	_check("flow dropping a tier is silent", _tr._last_emit[&"tier_up"] == t_tier)
	_flow.on_changed.emit(2.3)
	_check("re-crossing (now tier 2) fires tier_up again + pushes", _tr._last_emit[&"tier_up"] != t_tier and _dir._momentum._entries.size() == 2)

	# New best: only when the finished run actually set the session PB.
	_rm.best = false
	_rm.on_run_finished.emit(100.0, 60.0)
	_check("ordinary finish -> no new_best", not _tr._last_emit.has(&"new_best"))
	_rm.best = true
	_rm.on_run_finished.emit(200.0, 55.0)
	_check("PB finish -> new_best event", _tr._last_emit.has(&"new_best") and _last_word_in(&"new_best"))

	print("RESULT: %s" % ("PASS (all checks green)" if _fail == 0 else "FAIL (%d failed)" % _fail))
	return true


func _last_word_in(event_id: StringName) -> bool:
	var last: Composition = null
	for ch in _dir.get_children():
		if ch is Composition:
			last = ch
	if last == null:
		return false
	var recipe := _dir._library.get_recipe(event_id)
	return recipe != null and last._word_text in recipe.words


func _check(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("  [%s] %s" % ["OK" if cond else "XX", label])
