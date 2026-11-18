extends SceneTree

# Phase-2 guard for the ACTION VECTOR. Verifies the vector captures INTENT (not just
# position): each maneuver family derives its direction from the relevant motion, the
# magnitude scales with how hard the maneuver was, families differ from one another,
# and the world intent projects to the expected screen direction through a camera.
# Run:
# Godot --headless --path /Users/abdul/Desktop/Personal/flowstate/flowstate --script res://scripts/tests/_PanelActionVectorProbe.gd

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
	print("=== Panel Action Vector Probe (Phase 2) ===")

	var F := PanelGrammar.Family
	# A car facing -Z, up +Y, right +X, cruising forward at 30.
	var base := {pos = Vector3.ZERO, forward = Vector3(0, 0, -1), up = Vector3(0, 1, 0), right = Vector3(1, 0, 0), velocity = Vector3(0, 0, -30)}

	# DRIFT -> lateral (sideways), magnitude scales with slip.
	var drift := base.duplicate(); drift.velocity = Vector3(15, 0, -25)   # rightward slip
	var a_drift := _dir._compute_world_action(F.SLIDE, drift, {})
	_check("drift direction is lateral (sideways, not forward)",
		absf(a_drift.dir.dot(Vector3(1, 0, 0))) > 0.7 and absf(a_drift.dir.dot(Vector3(0, 0, -1))) < 0.4)
	var drift_hard := base.duplicate(); drift_hard.velocity = Vector3(28, 0, -8)
	_check("drift magnitude scales with how hard the slide is",
		_dir._compute_world_action(F.SLIDE, drift_hard, {}).magnitude > a_drift.magnitude)

	# JUMP -> up; magnitude scales with launch speed.
	var jump := base.duplicate(); jump.velocity = Vector3(0, 16, -20)
	var a_jump := _dir._compute_world_action(F.LAUNCH, jump, {})
	_check("jump direction is up", a_jump.dir.dot(Vector3(0, 1, 0)) > 0.9)
	var jump_hard := base.duplicate(); jump_hard.velocity = Vector3(0, 30, -20)
	_check("jump magnitude scales with launch speed",
		_dir._compute_world_action(F.LAUNCH, jump_hard, {}).magnitude > a_jump.magnitude)

	# LANDING -> down; magnitude from impact context.
	var a_land := _dir._compute_world_action(F.IMPACT, base, {"impact": 10.0})
	_check("landing direction is down", a_land.dir.dot(Vector3(0, -1, 0)) > 0.9)
	_check("landing magnitude scales with impact",
		_dir._compute_world_action(F.IMPACT, base, {"impact": 28.0}).magnitude > a_land.magnitude)

	# WALL -> follows the run; banking reference follows the (tilted) car up.
	var wall := base.duplicate(); wall.up = Vector3(0.6, 0.8, 0.0).normalized()
	var a_wall := _dir._compute_world_action(F.WALL, wall, {})
	_check("wall direction follows the run (forward)", a_wall.dir.dot(Vector3(0, 0, -1)) > 0.7)
	_check("wall banking follows the tilted car up", a_wall.roll_ref.dot(Vector3(0, 1, 0)) < 0.95)

	# NEAR-MISS -> toward the hazard.
	var a_danger := _dir._compute_world_action(F.DANGER, base, {"hazard_dir": Vector3(1, 0, 0)})
	_check("near-miss direction points at the hazard", a_danger.dir.dot(Vector3(1, 0, 0)) > 0.9)

	# BOOST -> travel direction.
	_check("boost direction follows travel", _dir._compute_world_action(F.THRUST, base, {}).dir.dot(Vector3(0, 0, -1)) > 0.9)

	# Different maneuvers => genuinely different directions (not just offsets).
	_check("families produce different action directions",
		a_jump.dir.distance_to(a_land.dir) > 1.0 and a_drift.dir.distance_to(a_jump.dir) > 0.7)

	# End-to-end: world intent projects to the expected SCREEN direction via a camera.
	var fakecar := Node3D.new(); root.get_child(0).add_child(fakecar); fakecar.global_position = Vector3.ZERO
	_dir._vehicle = fakecar
	var cam := Camera3D.new(); root.get_child(0).add_child(cam)
	cam.global_position = Vector3(0, 1.5, 8.0); cam.look_at(Vector3.ZERO, Vector3.UP); cam.current = true
	var av_up := _dir.project_action({dir = Vector3(0, 1, 0), roll_ref = Vector3(0, 1, 0), magnitude = 0.8})
	var av_down := _dir.project_action({dir = Vector3(0, -1, 0), roll_ref = Vector3(0, 1, 0), magnitude = 0.8})
	_check("world 'up' projects to screen-up (axis.y < 0)", av_up.axis.y < -0.3)
	_check("world 'down' projects to screen-down (axis.y > 0)", av_down.axis.y > 0.3)

	print("RESULT: %s" % ("PASS (all checks green)" if _fail == 0 else "FAIL (%d failed)" % _fail))
	return true


func _check(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("  [%s] %s" % ["OK" if cond else "XX", label])
