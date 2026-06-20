class_name GravitySystem
extends Node3D

signal on_state_changed(new_state: AttachmentState)

enum AttachmentState {
	GROUNDED,
	WALL_LEFT,
	WALL_RIGHT,
	INVERTED,
	AIRBORNE
}

@export var min_attach_speed: float = 5.0          # Speed check inside request_wall_attach() (button walls)
@export var gravity_transition_speed: float = 8.0  # How fast gravity direction rotates to a new surface
@export var airborne_transition_speed: float = 30.0 # FASTER lerp used ONLY while AIRBORNE so leaving a wall/edge
													# snaps gravity to straight-down instead of floating on the
													# leftover into-wall vector (~0.13s vs ~0.5s). Still a lerp, not
													# a snap. Does NOT affect smooth surface-follow (loops/ceilings).
@export var wall_grip_decay: float = 0.15          # Speed lost per second while on a button wall (anti-grind)
@export var detach_speed_threshold: float = 4.0    # Absolute floor: tilted surfaces below this requirement hold freely
@export var airborne_gravity: Vector3 = Vector3(0, -18, 0)
@export var ray_length: float = 1.5
@export var wall_stick_range: float = 3.5          # Max distance to a button-wall before detach (>= WallSensor.max_wall_range)

# --- Continuous surface following (005 Phase 1) ---
@export var attach_init_dot: float = 0.5           # Min |normal·UP| to AUTO-attach from air — walls stay button-only (UNTUNED)
@export var max_follow_rotation_deg: float = 20.0  # Max surface-normal rotation/frame to keep following (smooth curve vs sharp wall)
@export var max_hold_speed: float = 14.0           # Speed to hold a full ceiling / loop-top (UNTUNED)
@export var hold_curve_exponent: float = 3.0       # Forgiving non-linear hold curve: required = max * tilt^exponent
@export var hold_speed_curve: Curve                # Optional override for tilt(0..1) -> 0..1 multiplier (else tilt^exponent)
@export var attach_cooldown_time: float = 0.18     # No auto-attach for this long after leaving a surface (kills sticky jumps)

const FLOOR_CEILING_DOT: float = 0.55              # |normal·UP| above this = floor/ceiling label; below = wall-like band

var _vehicle: CharacterBody3D
var _current_gravity: Vector3
var _current_state: AttachmentState = AttachmentState.AIRBORNE
var _current_surface_normal: Vector3 = Vector3.ZERO
var _attach_cooldown: float = 0.0
var _speed_history: Array[float] = []

func _ready() -> void:
	_vehicle = get_parent() as CharacterBody3D
	_current_gravity = airborne_gravity
	_current_state = AttachmentState.AIRBORNE


func get_gravity_vector() -> Vector3:
	return _current_gravity


# SEAM 2 — the full gravity to apply this frame. Phase 1: pure into-surface while attached
# (H4-clean, no tangent bleed), world gravity when airborne. Phase 2 composes tangent gravity
# here behind use_centrifugal_adhesion WITHOUT touching VehiclePhysics.
func get_applied_gravity() -> Vector3:
	if _current_state == AttachmentState.AIRBORNE or _current_surface_normal == Vector3.ZERO:
		return _current_gravity
	return -_current_surface_normal * airborne_gravity.length()


func get_surface_normal() -> Vector3:
	return _current_surface_normal


func get_state() -> AttachmentState:
	return _current_state


func force_airborne() -> void:
	_set_state(AttachmentState.AIRBORNE)
	_current_surface_normal = Vector3.ZERO
	_attach_cooldown = attach_cooldown_time   # single point: covers jump, wall-jump, surface loss, hold-loss


# Button wall attach (004) — pre-validated wall normal from WallSensor. Returns false if rejected.
func request_wall_attach(normal: Vector3) -> bool:
	var current_speed: float = _vehicle.velocity.length()
	if current_speed < min_attach_speed:
		return false
	_speed_history.clear()
	_commit_wall_normal(normal)
	return true


func update_system(delta: float) -> void:
	_attach_cooldown = maxf(_attach_cooldown - delta, 0.0)

	var on_wall := (_current_state == AttachmentState.WALL_LEFT or _current_state == AttachmentState.WALL_RIGHT)
	if on_wall:
		_update_wall()
	else:
		_update_follow(delta)

	# Gravity DIRECTION lerp (shared, used for orientation/camera) — never snaps.
	# AIRBORNE uses a faster transition so leaving a wall/edge engages straight-down gravity
	# promptly (kills the floaty arc + drift toward the old wall) instead of decaying the stale
	# into-wall vector over ~0.5s. Surface-following (loops/ceilings) keeps the smooth speed.
	var target_gravity: Vector3
	var transition_speed: float
	if _current_state == AttachmentState.AIRBORNE:
		target_gravity = airborne_gravity
		transition_speed = airborne_transition_speed
	else:
		target_gravity = -_current_surface_normal * airborne_gravity.length()
		transition_speed = gravity_transition_speed
	_current_gravity = _current_gravity.lerp(target_gravity, clampf(delta * transition_speed, 0.0, 1.0))


# --- Button wall riding sustain (004) — unchanged behavior, just isolated ---
func _update_wall() -> void:
	var space_state := _vehicle.get_world_3d().direct_space_state
	if not _wall_still_present(space_state):
		force_airborne()
		return
	_push_speed(_vehicle.velocity.length())
	if _eval_speed() < detach_speed_threshold:
		force_airborne()


# --- Continuous surface following (005 Phase 1) ---
func _update_follow(delta: float) -> void:
	var normal := _detect_surface_normal()

	if normal == Vector3.ZERO:
		if _current_state != AttachmentState.AIRBORNE:
			force_airborne()
		return

	if _current_state == AttachmentState.AIRBORNE:
		# Ownership: auto-attach only onto floor/ceiling-ish surfaces, and never during the
		# post-detach cooldown. Standalone vertical walls remain button-only.
		if _attach_cooldown <= 0.0 and absf(normal.dot(Vector3.UP)) >= attach_init_dot:
			_speed_history.clear()
			_commit_follow_normal(normal)
		return

	# Sustaining GROUNDED / INVERTED.
	# Reject sudden normal flips (sharp walls / edges); smooth curves rotate gradually.
	var rot_deg := rad_to_deg(acos(clampf(normal.dot(_current_surface_normal), -1.0, 1.0)))
	if rot_deg > max_follow_rotation_deg:
		force_airborne()
		return

	_push_speed(_tangential_speed(normal))
	if not _surface_holds(normal, _eval_speed(), delta):
		force_airborne()
		return

	_commit_follow_normal(normal)


# SEAM 1 — "does this surface still hold the car?" Phase 1: tilt-scaled hold-speed.
# Phase 2 swaps this body (centrifugal a_c vs off_pull, + convex launch) behind a flag.
func _surface_holds(normal: Vector3, tangential_speed: float, _delta: float) -> bool:
	var required := _required_hold_speed(normal)
	if required < detach_speed_threshold:
		return true   # gentle enough to rest on (floors, mild slopes, ~vertical) — holds at any speed
	return tangential_speed >= required


func _required_hold_speed(normal: Vector3) -> float:
	var tilt := clampf((1.0 - normal.dot(Vector3.UP)) * 0.5, 0.0, 1.0)  # floor 0 · vertical .5 · ceiling 1
	var m: float
	if hold_speed_curve:
		m = hold_speed_curve.sample(tilt)
	else:
		m = pow(tilt, hold_curve_exponent)   # forgiving: ~0 until the surface starts to invert
	return max_hold_speed * m


# The surface under the car: prefer the real move_and_slide contact (most aligned with the car's
# up), fall back to a short down-ray. Independent of the orientation it controls (no -basis.y
# self-reference for the primary source).
func _detect_surface_normal() -> Vector3:
	var car_up := _vehicle.global_transform.basis.y
	var best := Vector3.ZERO
	var best_dot := 0.0
	for i in _vehicle.get_slide_collision_count():
		var c := _vehicle.get_slide_collision(i)
		var n := c.get_normal()
		var d := n.dot(car_up)
		if d > best_dot:
			best_dot = d
			best = n
	if best != Vector3.ZERO:
		return best
	# Fallback: cast straight "down" under the car.
	var space_state := _vehicle.get_world_3d().direct_space_state
	var from := _vehicle.global_position
	var to := from - car_up * (ray_length + 0.2)
	var query := PhysicsRayQueryParameters3D.create(from, to, _vehicle.collision_mask, [_vehicle.get_rid()])
	var result := space_state.intersect_ray(query)
	if not result.is_empty():
		return result.normal
	return Vector3.ZERO


func _tangential_speed(normal: Vector3) -> float:
	var v := _vehicle.velocity
	return (v - normal * v.dot(normal)).length()


func _push_speed(s: float) -> void:
	_speed_history.push_front(s)
	if _speed_history.size() > 10:
		_speed_history.pop_back()


func _eval_speed() -> float:
	var m := 0.0
	for s in _speed_history:
		m = maxf(m, s)
	return m


# Wall presence (button walls) — cast toward the committed wall normal over wall_stick_range.
func _wall_still_present(space_state: PhysicsDirectSpaceState3D) -> bool:
	if _current_surface_normal == Vector3.ZERO:
		return false
	var from := _vehicle.global_position
	var to := from - _current_surface_normal * wall_stick_range
	var query := PhysicsRayQueryParameters3D.create(from, to, _vehicle.collision_mask, [_vehicle.get_rid()])
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return false
	return absf(result.normal.dot(Vector3.UP)) <= FLOOR_CEILING_DOT


# Continuous-follow commit: GROUNDED / INVERTED only — never WALL (those are button-initiated).
func _commit_follow_normal(normal: Vector3) -> void:
	_current_surface_normal = normal
	if normal.dot(Vector3.UP) < -FLOOR_CEILING_DOT:
		_set_state(AttachmentState.INVERTED)
	else:
		_set_state(AttachmentState.GROUNDED)


# Button-wall commit (004): classifies WALL_LEFT / WALL_RIGHT from a pre-validated wall normal.
func _commit_wall_normal(normal: Vector3) -> void:
	_current_surface_normal = normal
	var up_dot := normal.dot(Vector3.UP)
	if up_dot > FLOOR_CEILING_DOT:
		_set_state(AttachmentState.GROUNDED)
	elif up_dot < -FLOOR_CEILING_DOT:
		_set_state(AttachmentState.INVERTED)
	else:
		var right_dot := normal.dot(_vehicle.global_transform.basis.x)
		if right_dot > 0.0:
			_set_state(AttachmentState.WALL_LEFT)
		else:
			_set_state(AttachmentState.WALL_RIGHT)


func _set_state(new_state: AttachmentState) -> void:
	if _current_state != new_state:
		_current_state = new_state
		on_state_changed.emit(new_state)
