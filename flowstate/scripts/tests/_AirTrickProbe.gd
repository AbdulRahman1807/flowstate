extends SceneTree

# Verifies air tricks (010_Air_Tricks.md):
#   A. each input rotates the car around the expected axis
#   B. velocity magnitude is preserved through a trick
#   C. a full 360 accumulates
#   D. clean landing (upright) after >=min trick -> trick_landed(_, true) + "air_trick" style + Flow
#   E. botched landing (off-axis) -> trick_landed(_, false), NO style
#   F. no trick while grounded
# Run: Godot --headless --script res://scripts/tests/_AirTrickProbe.gd

var _v: CharacterBody3D
var _vc
var _gs
var _flow
var _score
var _ok := true

# trick_landed capture
var _last_degrees := -1.0
var _last_clean := false
var _fired := false

func _initialize() -> void:
	var world := Node3D.new(); root.add_child(world)
	var b := StaticBody3D.new(); b.position = Vector3(0, -0.5, 0)
	var s := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = Vector3(4000, 1, 4000); s.shape = bx
	b.add_child(s); world.add_child(b)

	_v = CharacterBody3D.new(); _v.set_script(load("res://scripts/vehicle/VehiclePhysics.gd")); _v.name = "Vehicle"
	var col := CollisionShape3D.new(); var cap := CapsuleShape3D.new(); cap.radius = 0.8; cap.height = 1.6; col.shape = cap
	_v.add_child(col)
	_vc = _child(_v, "VehicleController", Node, "res://scripts/vehicle/VehicleController.gd")
	_gs = _child(_v, "GravitySystem", Node3D, "res://scripts/vehicle/GravitySystem.gd")
	_child(_v, "WallRiding", Node, "res://scripts/vehicle/WallRiding.gd")
	_flow = _child(_v, "FlowSystem", Node, "res://scripts/systems/FlowSystem.gd")
	_child(_v, "WallSensor", Node, "res://scripts/vehicle/WallSensor.gd")
	world.add_child(_v)

	_score = Node.new(); _score.set_script(load("res://scripts/systems/ScoreSystem.gd")); _score.name = "ScoreSystem"
	world.add_child(_score)   # default vehicle_path "../Vehicle" resolves to world/Vehicle

	_v.trick_rate_ramp = 1000.0   # disable the ease-in ramp for deterministic degree-counting (the ramp is a feel layer, tested by driving)
	_v.trick_landed.connect(_on_trick)
	# Tests start the car high up (y=50) so it stays airborne for the whole rotation; landings are
	# triggered by teleporting onto the floor. Gravity stays ON (it drives up_direction), so the
	# velocity-preservation check looks at the HORIZONTAL component (gravity only adds vertical).
	print("=== Air Trick Probe (rate=%.0f, min=%.0f, clean_dot=%.2f) ===" % [
		_v.air_trick_rate, _v.air_trick_min_degrees, _v.air_trick_clean_dot])


var _warmup := 0
func _physics_process(_dt: float) -> bool:
	_vc.set_physics_process(false)
	# get_physics_process_delta_time() reads 0 on the very first physics tick, which would zero every
	# delta-scaled rotation. Let one tick pass so apply_intent's delta is real before running tests.
	_warmup += 1
	if _warmup < 2:
		return false

	# ---------- A. axis rotations ----------
	# Roll (brake+steer): rotates around forward axis -> forward preserved, up changes.
	_airborne(Vector3(0, 0, -10))
	_run(1.0, 1.0, 0.0, 15)
	var fwd: Vector3 = -_v.global_transform.basis.z
	var up: Vector3 = _v.global_transform.basis.y
	_check(fwd.dot(Vector3(0, 0, -1)) > 0.99, "A.roll: forward (roll axis) preserved")
	_check(up.dot(Vector3.UP) < 0.8, "A.roll: up rotated away")

	# Flip (brake+accel): rotates around right axis -> right preserved, forward changes.
	_airborne(Vector3(0, 0, -10))
	_run(1.0, 0.0, 1.0, 15)
	var right: Vector3 = _v.global_transform.basis.x
	fwd = -_v.global_transform.basis.z
	_check(right.dot(Vector3(1, 0, 0)) > 0.99, "A.flip: right (flip axis) preserved")
	_check(fwd.dot(Vector3(0, 0, -1)) < 0.8, "A.flip: forward rotated away")

	# Spin (brake only): rotates around up axis -> up preserved, forward changes.
	_airborne(Vector3(0, 0, -10))
	_run(1.0, 0.0, 0.0, 15)
	up = _v.global_transform.basis.y
	fwd = -_v.global_transform.basis.z
	_check(up.dot(Vector3.UP) > 0.99, "A.spin: up (spin axis) preserved")
	_check(fwd.dot(Vector3(0, 0, -1)) < 0.8, "A.spin: forward rotated away")

	# ---------- B. velocity preserved through FLIP & SPIN (their axes sweep forward through travel,
	# which exposed a clamp+rebuild that shrank momentum; roll alone never caught it). Horizontal
	# only — gravity adds vertical. ----------
	_airborne(Vector3(12, 0, 3))
	var hf0: float = Vector2(_v.velocity.x, _v.velocity.z).length()
	_run(1.0, 0.0, 1.0, 30)   # flip
	var hf1: float = Vector2(_v.velocity.x, _v.velocity.z).length()
	_check(absf(hf1 - hf0) / hf0 < 0.02, "B: horizontal speed preserved through FLIP (%.2f -> %.2f)" % [hf0, hf1])
	_airborne(Vector3(12, 0, 3))
	var hs0: float = Vector2(_v.velocity.x, _v.velocity.z).length()
	_run(1.0, 0.0, 0.0, 30)   # spin
	var hs1: float = Vector2(_v.velocity.x, _v.velocity.z).length()
	_check(absf(hs1 - hs0) / hs0 < 0.02, "B2: horizontal speed preserved through SPIN (%.2f -> %.2f)" % [hs0, hs1])

	# ---------- C. 360 accumulates ----------
	_airborne(Vector3(0, 0, -10))
	_v._trick_rotation_accum = 0.0
	_run(1.0, 1.0, 0.0, 61)
	_check(_v.get_trick_rotation() >= 360.0, "C: 360 accumulated (got %.0f)" % _v.get_trick_rotation())

	# ---------- D. clean landing (full 360 -> upright) ----------
	_score.start_run()
	var flow_before: float = (_flow as FlowSystem).get_value()
	_airborne(Vector3(0, 0, -10))
	_v._trick_rotation_accum = 0.0
	_run(1.0, 1.0, 0.0, 60)                       # 360 -> ends upright
	_fired = false
	_land()                                        # teleport onto floor + one frame
	var style_d: float = _score.get_style_breakdown().get("air_trick", 0.0)
	var flow_after: float = (_flow as FlowSystem).get_value()
	_check(_fired and _last_clean, "D: clean trick landed (degrees=%.0f clean=%s)" % [_last_degrees, _last_clean])
	_check(_last_degrees >= _v.air_trick_min_degrees, "D: degrees >= min")
	_check(style_d > 0.0, "D: 'air_trick' style awarded (%.0f)" % style_d)
	_check(flow_after > flow_before, "D: Flow gained (%.2f -> %.2f)" % [flow_before, flow_after])

	# ---------- E. botched landing (210 -> sideways) ----------
	var style_before_e: float = _score.get_style_breakdown().get("air_trick", 0.0)
	_airborne(Vector3(0, 0, -10))
	_v._trick_rotation_accum = 0.0
	_run(1.0, 1.0, 0.0, 35)                       # 210 -> sideways
	_fired = false
	_land()
	var style_after_e: float = _score.get_style_breakdown().get("air_trick", 0.0)
	_check(_fired and not _last_clean, "E: botched trick landed (degrees=%.0f clean=%s)" % [_last_degrees, _last_clean])
	_check(absf(style_after_e - style_before_e) < 0.001, "E: no style for botched trick (%.0f -> %.0f)" % [style_before_e, style_after_e])

	# ---------- F. no trick while grounded ----------
	# Already grounded from E's landing. Brake+steer on the ground is drift territory, never a trick.
	_v._trick_rotation_accum = 0.0
	_run(1.0, 1.0, 0.0, 5)
	_check(not _v.is_tricking(), "F: not tricking while grounded")
	_check(_v.get_trick_rotation() == 0.0, "F: no trick rotation accrued grounded")

	# ---------- G. heading after a FLIP past vertical: lands facing TRAVEL, not backward ----------
	# Travel is -Z. Flip (accel) ~180deg so the tumbled -basis.z would project BACKWARD (+Z); the
	# fix re-derives heading from the direction of travel, so it must land facing -Z.
	_airborne(Vector3(0, 0, -12))
	_v._trick_rotation_accum = 0.0
	_run(1.0, 0.0, 1.0, 45)                        # ~180deg flip (flip rate 240/s)
	_land_moving(Vector3(0, -2, -12))              # land keeping the -Z horizontal travel
	var gfwd: Vector3 = -_v.global_transform.basis.z
	_check(gfwd.dot(Vector3(0, 0, -1)) > 0.8, "G: lands facing travel after flip (fwd-dot-travel=%.2f)" % gfwd.dot(Vector3(0, 0, -1)))
	_check(_v.global_transform.basis.y.dot(Vector3.UP) > 0.9, "G: lands upright after flip (up-dot-UP=%.2f)" % _v.global_transform.basis.y.dot(Vector3.UP))

	# ---------- H. ROOF landing (incomplete 180 flip) is a CRASH — momentum bleeds ----------
	_airborne(Vector3(0, 0, -20))
	_v._trick_rotation_accum = 0.0
	_run(1.0, 0.0, 1.0, 45)                        # ~180deg flip -> inverted (on the roof) at touchdown
	_land_moving(Vector3(0, -2, -20))
	var h_crash: float = Vector2(_v.velocity.x, _v.velocity.z).length()
	_check(h_crash < 20.0 * 0.85, "H: roof landing crashed — horiz speed bled (20 -> %.1f)" % h_crash)

	# ---------- I. COMPLETED flip (360, wheels-down) keeps momentum — crash is orientation-gated ----------
	_airborne(Vector3(0, 0, -20))
	_v._trick_rotation_accum = 0.0
	_run(1.0, 0.0, 1.0, 90)                        # full 360 flip -> back on the wheels
	_land_moving(Vector3(0, -2, -20))
	var h_clean: float = Vector2(_v.velocity.x, _v.velocity.z).length()
	_check(h_clean > 20.0 * 0.9, "I: completed flip keeps momentum (20 -> %.1f)" % h_clean)

	# ---------- J. half-SPIN lands you REAR-FIRST = crash, but recovers facing forward ----------
	# Travel -Z. A 180deg spin leaves the front pointing +Z (backward) at touchdown -> crash. The car
	# has a fixed front, so this no longer "just works"; control recovers to face travel.
	_airborne(Vector3(0, 0, -20))
	_v._trick_rotation_accum = 0.0
	_run(1.0, 0.0, 0.0, 30)                        # ~180deg spin -> rear-first
	_land_moving(Vector3(0, -2, -20))
	var j_h: float = Vector2(_v.velocity.x, _v.velocity.z).length()
	var j_fwd: Vector3 = -_v.global_transform.basis.z
	_check(j_h < 20.0 * 0.85, "J: rear-first landing crashed (horiz 20 -> %.1f)" % j_h)
	_check(j_fwd.dot(Vector3(0, 0, -1)) > 0.8, "J: recovers facing travel (fwd-dot-travel=%.2f)" % j_fwd.dot(Vector3(0, 0, -1)))

	# ---------- K. full SPIN lands FRONT-FIRST = clean, momentum kept ----------
	_fired = false
	_airborne(Vector3(0, 0, -20))
	_v._trick_rotation_accum = 0.0
	_run(1.0, 0.0, 0.0, 60)                        # full 360 spin -> facing forward again
	_land_moving(Vector3(0, -2, -20))
	var k_h: float = Vector2(_v.velocity.x, _v.velocity.z).length()
	_check(k_h > 20.0 * 0.9, "K: full spin keeps momentum (20 -> %.1f)" % k_h)
	_check(_fired and _last_clean, "K: full spin landed clean (degrees=%.0f clean=%s)" % [_last_degrees, _last_clean])

	if _ok:
		print("PASS")
	else:
		print("FAILED")
	print("=== done ===")
	return true


# Put the car airborne, high up, identity orientation, with the given velocity.
func _airborne(vel: Vector3) -> void:
	_gs.force_airborne()
	_gs._attach_cooldown = 0.0
	_v.global_transform = Transform3D(Basis(), Vector3(0, 50, 0))
	_v.velocity = vel
	_v._was_grounded_last_frame = false
	_v._airborne_time = 10.0   # pretend we've been airborne a while so the airtime gate is satisfied


# Run n physics frames of apply_intent. First arg is the air-trick modifier (E), then steer/accel.
func _run(trick: float, steer: float, accelerate: float, n: int) -> void:
	for i in n:
		var mi = load("res://scripts/vehicle/MovementIntent.gd").new()
		mi.air_trick = trick > 0.5; mi.steer = steer; mi.accelerate = accelerate
		_v.apply_intent(mi)


# Teleport the car onto the floor and run one frame so it lands (triggers the landing eval).
func _land() -> void:
	_gs._attach_cooldown = 0.0
	_v.global_position = Vector3(0, 0.9, 0)
	_v.velocity = Vector3(0, -2, 0)
	var mi = load("res://scripts/vehicle/MovementIntent.gd").new()
	_v.apply_intent(mi)


# Land while KEEPING a horizontal travel component (so the post-trick heading re-derivation runs).
func _land_moving(vel: Vector3) -> void:
	_gs._attach_cooldown = 0.0
	_v.global_position = Vector3(0, 0.9, 0)
	_v.velocity = vel
	var mi = load("res://scripts/vehicle/MovementIntent.gd").new()
	_v.apply_intent(mi)


func _on_trick(degrees: float, clean: bool) -> void:
	_last_degrees = degrees; _last_clean = clean; _fired = true


func _check(cond: bool, msg: String) -> void:
	print("  %s : %s" % ["ok " if cond else "FAIL", msg])
	if not cond:
		_ok = false


func _child(parent: Node, n: String, base, path: String):
	var node = base.new(); node.set_script(load(path)); node.name = n
	parent.add_child(node); return node
