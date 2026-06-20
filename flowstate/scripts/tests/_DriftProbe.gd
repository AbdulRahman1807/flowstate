extends SceneTree

# Verifies drift mechanics: speed preserved while sliding, slip angle exists,
# flow charges during steer+drift, velocity snaps to facing on release. Run:
#   Godot --headless --script res://scripts/tests/_DriftProbe.gd

var _v: CharacterBody3D
var _gs
var _vc
var _fs
var _t := 0
var _phase := 0   # 0=wind_up  1=drift  2=release

var _pre_drift_speed := 0.0
var _flow_before_drift := 0.0
var _ok := true

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
	_fs = _child(_v, "FlowSystem", Node, "res://scripts/systems/FlowSystem.gd")
	_child(_v, "WallSensor", Node, "res://scripts/vehicle/WallSensor.gd")
	world.add_child(_v)
	_vc.set_physics_process(false)
	_v.global_position = Vector3(0, 0.9, 0)
	_v.velocity = Vector3.ZERO
	print("=== Drift Probe (min_speed=%.0f, grip=%.1f, steer_mult=%.1f) ===" % [
		_v.drift_min_speed, _v.drift_grip_rate, _v.drift_steer_mult])

func _physics_process(_dt: float) -> bool:
	_vc.set_physics_process(false)  # SceneTree fires before Node; re-suppress each frame since _initialize() disable doesn't hold
	_t += 1
	var mi = load("res://scripts/vehicle/MovementIntent.gd").new()

	if _phase == 0:
		# Wind up to well above drift_min_speed
		mi.accelerate = 1.0
		_v.apply_intent(mi)
		if _t >= 240:
			_pre_drift_speed = _v.velocity.length()
			_flow_before_drift = (_fs as FlowSystem).get_value()
			print("  wind-up: speed=%.1f (need >= drift_min_speed=%.1f)" % [_pre_drift_speed, _v.drift_min_speed])
			if _pre_drift_speed < _v.drift_min_speed:
				push_error("FAIL: could not reach drift_min_speed before drifting")
				_ok = false
			_phase = 1; _t = 0

	elif _phase == 1:
		# Brake-to-drift: hold brake + half steer for 60 frames (~1s). Brake is the drift TRIGGER
		# here, not a decelerator — so this also verifies braking doesn't scrub speed mid-drift.
		# At high speed + drift_steer_mult, car rotates ~62° total; steady-state slip ~35°.
		# Using half steer avoids a full spin (which would wrap slip back toward 0°).
		mi.brake = 1.0
		mi.steer = 0.5
		_v.apply_intent(mi)
		if _t >= 60:
			var spd := _v.velocity.length()
			var fwd := -_v.global_transform.basis.z
			var vel_dir := _v.velocity.normalized() if spd > 0.1 else fwd
			var drift_dot := clampf(fwd.dot(vel_dir), -1.0, 1.0)
			var slip_angle := rad_to_deg(acos(drift_dot))
			var flow_gained: float = (_fs as FlowSystem).get_value() - _flow_before_drift

			print("  after drift 1s (half steer):")
			print("    speed=%.1f  (pre=%.1f, ratio=%.0f%%)" % [spd, _pre_drift_speed, spd / _pre_drift_speed * 100.0])
			print("    slip_angle=%.1f deg  (grip-dependent: ~35 at grip=1.8, ~22 at grip=3.0)" % slip_angle)
			print("    flow_gained=%.2f" % flow_gained)

			# Speed should be broadly preserved (drift doesn't scrub momentum)
			if spd < _pre_drift_speed * 0.6:
				push_error("FAIL: speed scrubbed too much (%.1f < %.1f * 0.6)" % [spd, _pre_drift_speed])
				_ok = false

			# Velocity should differ from facing — we're actually sliding
			if slip_angle < 5.0:
				push_error("FAIL: no slip angle — drift not creating lateral (%.1f deg)" % slip_angle)
				_ok = false

			# Flow should have charged during active steer+drift
			if flow_gained < 0.05:
				push_error("FAIL: no flow charged during drift (gained=%.2f)" % flow_gained)
				_ok = false

			_phase = 2; _t = 0

	elif _phase == 2:
		# Release drift (brake off, straighten) — accelerate ahead for 5 frames, then measure alignment
		mi.accelerate = 0.5
		mi.steer = 0.0
		_v.apply_intent(mi)
		if _t >= 5:
			var fwd := -_v.global_transform.basis.z
			var vel_dir := _v.velocity.normalized() if _v.velocity.length() > 0.1 else fwd
			var align_dot := clampf(fwd.dot(vel_dir), -1.0, 1.0)
			var align_angle := rad_to_deg(acos(align_dot))

			print("  after release (5 frames):")
			print("    align_angle=%.2f deg (should be ~0 — snap on release)" % align_angle)

			# Snap-on-release should re-align velocity to facing immediately
			if align_angle > 10.0:
				push_error("FAIL: velocity not realigned after drift release (%.1f deg > 10 deg)" % align_angle)
				_ok = false

			if _ok:
				print("PASS")
			print("=== done ===")
			return true

	return false

func _child(parent: Node, n: String, base, path: String):
	var node = base.new(); node.set_script(load(path)); node.name = n
	parent.add_child(node); return node
