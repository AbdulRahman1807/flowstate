extends SceneTree

# Phase-4 guard for the MOTION GRAMMAR. Verifies the shared timing language: the
# four phases progress in order, the impact SLAMS (scale overshoot), opacity snaps
# in and holds, settle eases back to rest, decay ages out (fade + drift), the
# timeline finishes, tier changes duration, and the Composition drives the WHOLE
# composition from that one timeline (the single conductor) without rebuilding.
# Run:
# Godot --headless --path /Users/abdul/Desktop/Personal/flowstate/flowstate --script res://scripts/tests/_PanelMotionProbe.gd

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
	print("=== Panel Motion Probe (Phase 4) ===")
	var P := MotionTimeline.Phase

	var tl := MotionTimeline.new()
	tl.configure(PanelGrammar.Tier.HERO)
	var total := tl.duration()

	# Phases progress in order over the life.
	_check("starts in ANTICIPATE", _sample(tl, total * 0.03).phase == P.ANTICIPATE)
	_check("mid-life is SETTLE", _sample(tl, total * 0.45).phase == P.SETTLE)
	_check("late-life is DECAY", _sample(tl, total * 0.95).phase == P.DECAY)

	# The slam: impact overshoots past the rest scale.
	var peak := 0.0
	for i in range(40):
		peak = maxf(peak, _sample(tl, total * float(i) / 39.0).scale)
	_check("impact slams (scale overshoots > 1.1)", peak > 1.1)

	# Opacity: near-invisible at the start, full through settle.
	_check("anticipate starts near-invisible", _sample(tl, total * 0.01).alpha < 0.3)
	_check("holds full opacity through settle", absf(_sample(tl, total * 0.5).alpha - 1.0) < 0.05)

	# Settle eases back toward rest scale.
	_check("settle returns toward rest scale (~1.0)", absf(_sample(tl, total * 0.6).scale - 1.0) < 0.2)

	# Decay ages out: fades and drifts up.
	var d := _sample(tl, total * 0.97)
	_check("decay fades out", d.alpha < 0.3)
	_check("decay drifts up (ages out)", d.drift.y < 0.0)

	# Finishes at total duration.
	_check("finishes at the total duration", _sample(tl, total * 1.02).finished)

	# Emphasis tier changes the duration (climax lasts longer than beat).
	var beat := MotionTimeline.new(); beat.configure(PanelGrammar.Tier.BEAT)
	var climax := MotionTimeline.new(); climax.configure(PanelGrammar.Tier.CLIMAX)
	_check("climax lasts longer than beat", climax.duration() > beat.duration())

	# The single conductor: the Composition drives the whole composition from one
	# timeline, animating the master transform without rebuilding structure.
	var comp: Composition = _dir.compose(&"jump", {"multiplier": 3.0})
	_check("composition owns one timeline", comp != null and comp._timeline != null)
	var children_before: int = comp._lockup.get_child_count()
	comp._process(0.16)   # advance into the impact slam
	_check("master motion drives the whole composition (impact scale != rest)", comp.scale != Vector2.ONE)
	comp._process(0.20)
	_check("structure stays immutable through motion", comp._lockup.get_child_count() == children_before)

	print("RESULT: %s" % ("PASS (all checks green)" if _fail == 0 else "FAIL (%d failed)" % _fail))
	return true


func _sample(tl: MotionTimeline, t: float) -> MotionState:
	tl._elapsed = t
	return tl.state()


func _check(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("  [%s] %s" % ["OK" if cond else "XX", label])
