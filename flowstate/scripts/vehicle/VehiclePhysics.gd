class_name VehiclePhysics
extends CharacterBody3D

signal landed(impact_velocity: float)
signal jumped(jump_direction: Vector3)
signal clean_landing(impact_velocity: float)   # Perfect landing (angle ~parallel) — consumed by ScoreSystem for flow + style
signal drift_started
signal drift_ended
signal trick_landed(degrees: float, clean: bool)   # Air trick landed — total degrees rotated, clean = landed upright. Consumed by ScoreSystem for style.

@export var max_speed: float = 50.0   # Raised from 22 (which never actually held — see speed-cap fix). Tune live in inspector.
@export var wall_ride_speed_cap: float = 22.0   # Wall-ride velocity clamps to THIS, not max_speed: the jump-off preserves up-the-wall momentum, so it must stay bounded even when ground top speed is high.
@export var acceleration: float = 25.0
@export var brake_force: float = 30.0
@export var max_reverse_speed: float = 18.0   # ~36% of max_speed (08 target 35-40%). Reverse top speed; the cap clamps here.
@export var reverse_acceleration: float = 18.0
@export var reverse_engage_speed: float = 10.0
@export var drag: float = 0.08
@export var stop_speed_threshold: float = 1.0   # Grounded coasting below this (no throttle/brake) snaps to a true stop — drag is multiplicative so it only asymptotes toward 0; without this the car coasts forever at a minute speed

@export var steering_speed: float = 3.5
@export var high_speed_steering_dampen: float = 0.45

@export var jump_force: float = 12.0
@export var air_control_strength: float = 0.6
@export var gravity_force: float = 18.0

@export var boost_kick_speed: float = 15.0     # Instant forward velocity added on activation (~30% of max_speed) -> peak ~65
@export var boost_sustain_force: float = 6.0   # Gentle forward force during the decaying tail
@export var boost_decay_rate: float = 10.0     # How fast overspeed bleeds back to max_speed after boost (m/s²) — avoids hard snap
@export var boost_duration: float = 1.5
@export var boost_cooldown: float = 2.5

@export var landing_angle_penalty_curve: Curve
@export var clean_landing_max_dot: float = 0.25   # Landing angle below this (velocity ~parallel to surface) = a "perfect landing"
@export var clean_landing_min_impact: float = 3.0 # Min downward impact for a perfect landing to register (ignores tiny hops / spawn settle)

# Flow: high-speed driving is the GDD's primary flow trigger (02_GDD.md)
@export var flow_speed_threshold_ratio: float = 0.55   # Fraction of max_speed above which flow accumulates
@export var flow_per_second_at_speed: float = 0.6    # Flow gained per second while driving fast on the ground

# Drift: BRAKE-TO-DRIFT — hold brake while steering hard (above the thresholds below) to slide
# instead of slowing. No dedicated drift button; brake + a committed turn at speed initiates it.
# Preserves speed (brake scrub is suppressed while drifting), charges flow.
@export var drift_steer_mult: float = 1.4        # Extra steering authority while drifting
@export var drift_grip_rate: float = 3       # How fast velocity re-aligns toward facing during drift (higher = tighter; 0 = ice)
@export var drift_min_speed: float = 8.0         # Minimum forward speed required to enter drift
@export var drift_flow_per_second: float = 1.0   # Flow per second while actively drifting with steering input
@export var drift_brake_threshold: float = 0.5   # Brake input above this (with steer) initiates brake-to-drift
@export var drift_steer_threshold: float = 0.3   # |steer| above this (with brake) initiates brake-to-drift

# Air tricks (010): while AIRBORNE, hold the air-trick key (E / RB) + a direction to rotate —
# barrel roll (steer), flip (accelerate), spin (no direction). E is air-only, so it never misfires
# the way brake did. Rotation is orientation-only (momentum preserved, Pillar 1); land upright to score.
@export var air_trick_rate: float = 360.0          # deg/sec for roll & spin
@export var air_trick_flip_rate: float = 240.0     # deg/sec for flips (slower — they read as too fast at the roll/spin rate)
@export var air_trick_min_degrees: float = 180.0   # min accumulated rotation for a landing to count as a trick
@export var air_trick_clean_dot: float = 0.8       # car-up · surface-normal at landing >= this = clean (landed upright / wheels-down)
@export var air_trick_facing_dot: float = 0.5      # car-forward · travel at landing >= this = front-first; below = landed facing the wrong way (the car has a fixed front) = a crash
@export var air_trick_input_threshold: float = 0.3 # |steer| / accelerate above this selects roll / flip (else spin)
@export var trick_flow_per_360: float = 0.6        # Flow on a clean trick landing, per full 360°
@export var air_trick_min_airtime: float = 0.25    # Min continuous airtime before a trick can engage — blocks accidental spins on tiny hops / brief airborne moments while braking
# Botched-orientation landing after a trick = landing on the roof/side = a CRASH (it's a car). The
# car still auto-rights (Pillar 5: costs momentum, not progress), but bleeds speed + flow scaled by
# how far from upright it came down. Only evaluated when a trick happened (else slope landings would
# false-trigger). 0 disables.
@export var trick_crash_speed_penalty: float = 0.6 # Fraction of speed lost on a full roof landing (scales with how inverted)
@export var trick_crash_flow_penalty: float = 1.0  # Flow lost on a full roof landing (scales with how inverted)

var _is_grounded: bool = false
var _boost_active: bool = false
var _boost_timer: float = 0.0
var _boost_cooldown_timer: float = 0.0
var _current_speed: float = 0.0
var _signed_forward_speed: float = 0.0
var _last_steer: float = 0.0
var _was_grounded_last_frame: bool = false
var _is_drifting: bool = false
var _drift_vel_xz: Vector2 = Vector2.ZERO  # Jolt auto-realigns velocity to facing between frames; this stores intended drift direction
var _trick_active: bool = false            # an air trick is rotating this frame
var _trick_rotation_accum: float = 0.0     # degrees rotated since leaving the ground (reset on landing)
var _airborne_time: float = 0.0            # continuous seconds airborne — gates air-trick engagement

@onready var _vehicle_controller: VehicleController = $VehicleController
@onready var gravity_system: GravitySystem = $GravitySystem
@onready var _wall_riding: WallRiding = get_node_or_null("WallRiding")
@onready var _flow_system: FlowSystem = get_node_or_null("FlowSystem")

func _ready() -> void:
	up_direction = Vector3.UP
	floor_snap_length = 0.3



# Called by VehicleController every physics frame.
func apply_intent(intent: MovementIntent) -> void:
	var delta := get_physics_process_delta_time()
	_last_steer = intent.steer
	var incoming_velocity := velocity  # pre-update velocity; landing impact/angle read from this
	var incoming_basis_y := global_transform.basis.y  # car-up BEFORE this frame's gravity re-align — air-trick landing reads this
	var incoming_forward := -global_transform.basis.z  # car-FORWARD before re-align — air-trick landing reads facing (front-first vs rear-first) from this


	# 1. Update Gravity System
	if gravity_system:
		gravity_system.update_system(delta)
		_is_grounded = gravity_system.get_state() != GravitySystem.AttachmentState.AIRBORNE
	else:
		_is_grounded = is_on_floor()

	# Air-trick state — AIRBORNE only; brake = modifier, direction picks the axis (reuses idle
	# airborne inputs, no new keybind). Computed before step 2 so the gravity up-align can be
	# suspended while a trick rotates (otherwise it snaps the car upright every frame, killing it).
	if _is_grounded:
		_airborne_time = 0.0
	else:
		_airborne_time += delta
	var _trick_axis := Vector3.ZERO
	var _trick_dir := 1.0
	var _trick_rate := air_trick_rate
	_trick_active = false
	if not _is_grounded and _airborne_time >= air_trick_min_airtime and intent.air_trick:
		if absf(intent.steer) > air_trick_input_threshold:
			_trick_axis = Vector3.FORWARD          # barrel roll around the forward axis
			_trick_dir = signf(intent.steer)
		elif intent.accelerate > air_trick_input_threshold:
			_trick_axis = Vector3.RIGHT            # flip around the lateral axis
			_trick_rate = air_trick_flip_rate      # flips rotate slower (feel)
		else:
			_trick_axis = Vector3.UP               # spin around the up axis
		_trick_active = true

	# 2. Align vehicle orientation to gravity
	var gravity_vec := Vector3(0, -gravity_force, 0)
	var gravity_up := Vector3.UP
	
	if gravity_system:
		gravity_vec = gravity_system.get_gravity_vector()
		gravity_up = -gravity_vec.normalized()
		
		var current_up := global_transform.basis.y
		# Suspend the up-align while a trick is rotating so the player's rotation holds. It resumes the
		# moment the trick ends / the car lands. On a grounded TRICK RECOVERY (just landed from a trick)
		# we fully re-seat the car: upright AND facing its DIRECTION OF TRAVEL — so a tumbled (flip) or
		# spun-around (spin) car recovers to a drivable forward heading. The car has a fixed front, so
		# landing inverted/backward is judged a CRASH in step 10 (momentum cost), but control recovers
		# (Pillar 5). This grounded recovery also covers SPINS, where up is unchanged so the plain
		# up-align below would skip and leave the car stuck facing backward (janky reverse). Surface-
		# following (loops) never accrues trick rotation, so it keeps the -basis.z heading exactly as before.
		var ground_recover := _is_grounded and _trick_rotation_accum > 0.0
		if not _trick_active and (ground_recover or not current_up.is_equal_approx(gravity_up)):
			var forward_ref := -global_transform.basis.z
			if ground_recover:
				var travel := velocity - gravity_up * velocity.dot(gravity_up)
				if travel.length() > 1.0:
					forward_ref = travel.normalized()
			var right_ref := forward_ref.cross(gravity_up)
			if right_ref.length_squared() < 0.001:
				right_ref = global_transform.basis.x
			right_ref = right_ref.normalized()
			var true_forward := gravity_up.cross(right_ref).normalized()
			global_transform.basis = Basis(right_ref, gravity_up, -true_forward)
			
	up_direction = gravity_up
	var forward := -transform.basis.z

	# Determine drift state — brake-to-drift: braking while steering hard at speed slides instead of
	# slowing. intent.drift (programmatic/explicit) also forces it. Grounded, off-wall, above min speed.
	var was_drifting := _is_drifting
	var _drift_on_wall := false
	if gravity_system:
		var _dcs := gravity_system.get_state()
		_drift_on_wall = (_dcs == GravitySystem.AttachmentState.WALL_LEFT
				or _dcs == GravitySystem.AttachmentState.WALL_RIGHT)
	var _drift_input := intent.drift or (intent.brake > drift_brake_threshold and absf(intent.steer) > drift_steer_threshold)
	# Gate on SIGNED forward speed (velocity.dot(forward)), not unsigned velocity.length(): with
	# brake-to-drift, holding brake+steer to reverse-and-turn would trip drift once reverse speed
	# passed drift_min_speed, and the step-6 grip lerp flipped the backward velocity toward facing
	# -> reverse/forward oscillation. Drift is a forward-motion move only.
	_is_drifting = _drift_input and _is_grounded and not _drift_on_wall and velocity.dot(forward) >= drift_min_speed
	if _is_drifting and not was_drifting:
		_drift_vel_xz = Vector2(velocity.x, velocity.z)  # Capture world-space direction at drift entry
		drift_started.emit()
	elif not _is_drifting and was_drifting:
		_drift_vel_xz = Vector2.ZERO
		drift_ended.emit()

	if gravity_system:
		var current_state := gravity_system.get_state()
		var on_wall := (current_state == GravitySystem.AttachmentState.WALL_LEFT or
						current_state == GravitySystem.AttachmentState.WALL_RIGHT)

		if on_wall:
			# Project velocity onto wall plane to prevent move_and_slide()
			# from destroying momentum while orientation lerp is still in progress
			var wall_normal := gravity_system.get_surface_normal()
			velocity = velocity - wall_normal * velocity.dot(wall_normal)
			
			var projected_forward := forward - wall_normal * forward.dot(wall_normal)
			if projected_forward.length_squared() > 0.001:
				forward = projected_forward.normalized()
			else:
				# Degenerate case: vehicle is head-on to wall
				# forward is parallel to wall normal — projection collapses to zero
				# Use world up projected onto wall plane as the climb direction instead
				var world_up := Vector3.UP
				var up_on_wall := world_up - wall_normal * world_up.dot(wall_normal)
				if up_on_wall.length_squared() > 0.001:
					forward = up_on_wall.normalized()
				else:
					forward = global_transform.basis.x  # absolute last resort

	# 3. Velocity projections
	var signed_forward_speed := velocity.dot(forward)
	var local_right_vel := velocity.dot(transform.basis.x)
	var local_up_vel := velocity.dot(transform.basis.y)

	# 4. Acceleration, braking, reverse, and drag
	if _is_grounded:
		# Accelerate only up to max_speed and never overshoot it. Without this guard, throttle
		# (acceleration = 25/s) outruns the soft overspeed decay below (boost_decay_rate = 10/s),
		# so holding W climbs past the cap indefinitely (drag-limited ~150+). The decay still
		# handles bleeding off genuine boost overspeed; it is not the normal speed ceiling.
		if intent.accelerate > 0.0 and signed_forward_speed < max_speed:
			signed_forward_speed = minf(signed_forward_speed + acceleration * intent.accelerate * delta, max_speed)

		if intent.brake > 0.0 and not _is_drifting:
			# While drifting, brake is the drift trigger — not a decelerator. Suppressing the scrub
			# here is what lets brake-to-drift preserve momentum (Pillar 1).
			if signed_forward_speed > reverse_engage_speed:
				# Forward braking (above the reverse-engage threshold)
				signed_forward_speed -= brake_force * intent.brake * delta
				signed_forward_speed = maxf(signed_forward_speed, 0.0)
			elif intent.accelerate == 0.0:
				# Brake-to-reverse: at/below the engage threshold, holding brake decelerates through
				# zero and builds reverse down to -max_reverse_speed (the cap clamps it). The old
				# "reverse braking" middle branch was dead (cap < engage) and stalled reverse at the
				# engage speed; removing it lets reverse actually reach max_reverse_speed. W cancels.
				signed_forward_speed -= reverse_acceleration * intent.brake * delta

	if absf(signed_forward_speed) > 0.0:
		var drag_factor := maxf(1.0 - drag * delta, 0.0)
		signed_forward_speed *= drag_factor

	# Stiction: drag is multiplicative so it only ASYMPTOTES toward zero — the car would coast forever
	# at a minute speed and never truly stop. When grounded and purely coasting (no throttle, no brake,
	# not drifting), snap a sub-threshold crawl to a real stop.
	if _is_grounded and not _is_drifting and intent.accelerate == 0.0 and intent.brake == 0.0 and absf(signed_forward_speed) < stop_speed_threshold:
		signed_forward_speed = 0.0

	if gravity_system and _is_grounded and gravity_system.get_state() != GravitySystem.AttachmentState.GROUNDED:
		signed_forward_speed *= maxf(0.0, 1.0 - gravity_system.wall_grip_decay * delta)

	if not _boost_active:
		if signed_forward_speed > max_speed:
			# Decay overspeed (from a boost kick) smoothly toward max_speed instead of snapping
			signed_forward_speed = maxf(max_speed, signed_forward_speed - boost_decay_rate * delta)
		elif signed_forward_speed < -max_reverse_speed:
			signed_forward_speed = -max_reverse_speed

	# 5. Rebuild velocity vector
	if _is_grounded:
		if gravity_system and (
			gravity_system.get_state() == GravitySystem.AttachmentState.WALL_LEFT
			or gravity_system.get_state() == GravitySystem.AttachmentState.WALL_RIGHT
		):
			var lateral := velocity - forward * velocity.dot(forward)
			velocity = forward * signed_forward_speed + lateral
		elif _is_drifting:
			# Jolt's CharacterVirtual auto-runs a physics step between frames that re-aligns
			# velocity to the car's facing, defeating lateral drift. Restore from _drift_vel_xz
			# (saved after step 6 last frame) to get back the intended world-space drift direction.
			velocity.x = _drift_vel_xz.x
			velocity.z = _drift_vel_xz.y
			var spd := velocity.length()
			if spd > max_speed:
				velocity = velocity * (max_speed / spd)
		elif was_drifting:
			# Drift release: snap velocity to current facing at full current speed.
			signed_forward_speed = velocity.length()
			velocity = forward * signed_forward_speed
		else:
			velocity = forward * signed_forward_speed
	else:
		# Air trick: leave world-space velocity untouched (orientation-only). Rebuilding from the
		# tumbling basis + the clamped signed_forward_speed shrinks velocity whenever forward
		# anti-aligns with travel (flips/spins) — that corrupted momentum and spiked the FOV.
		if not _trick_active:
			velocity = forward * signed_forward_speed + transform.basis.y * local_up_vel + transform.basis.x * local_right_vel

	# 6. Steering
	if _is_grounded:
		var speed_ratio := clampf(absf(signed_forward_speed) / max_speed, 0.0, 1.0) if max_speed > 0.0 else 0.0
		var low_speed_dampen := clampf(speed_ratio * 3.0, 0.0, 1.0)
		var high_speed_dampen := lerpf(1.0, high_speed_steering_dampen, speed_ratio)
		var dampen_factor := low_speed_dampen * high_speed_dampen
		var reverse_factor := -1.0 if signed_forward_speed < 0.0 else 1.0
		var steer_mult := drift_steer_mult if _is_drifting else 1.0
		rotate_object_local(Vector3.UP, intent.steer * reverse_factor * steering_speed * steer_mult * dampen_factor * delta)

		forward = -transform.basis.z
		if gravity_system and (
			gravity_system.get_state() == GravitySystem.AttachmentState.WALL_LEFT
			or gravity_system.get_state() == GravitySystem.AttachmentState.WALL_RIGHT
		):
			var lateral := velocity - forward * velocity.dot(forward)
			velocity = forward * signed_forward_speed + lateral
		elif _is_drifting:
			# Partial grip — velocity gradually aligns toward new facing without hard-snapping.
			# drift_grip_rate controls how slidey (low) vs controlled (high) the drift feels.
			var spd := velocity.length()
			if spd > 0.001:
				velocity = velocity.lerp(forward * spd, drift_grip_rate * delta)
			# Save XZ after grip lerp — restored next frame in step 5 to override Jolt's auto re-alignment
			_drift_vel_xz = Vector2(velocity.x, velocity.z)
		else:
			velocity = forward * signed_forward_speed
	elif _trick_active:
		# Air trick: rotate ORIENTATION ONLY around the trick axis. Do NOT rebuild velocity from the
		# rotated basis — the car spins/flips but keeps flying the same way (momentum preserved, Pillar 1).
		rotate_object_local(_trick_axis, _trick_dir * deg_to_rad(_trick_rate) * delta)
		_trick_rotation_accum += _trick_rate * delta
	elif intent.steer != 0.0:
		var speed_ratio := clampf(absf(signed_forward_speed) / max_speed, 0.0, 1.0) if max_speed > 0.0 else 0.0
		var dampen_factor := lerpf(1.0, high_speed_steering_dampen, speed_ratio)
		rotate_object_local(
			Vector3.UP,
			intent.steer * steering_speed * dampen_factor * air_control_strength * delta
		)
		forward = -transform.basis.z
		velocity = forward * signed_forward_speed + transform.basis.y * local_up_vel + transform.basis.x * local_right_vel

	# 7. Jump
	if intent.jump and _is_grounded:
		velocity += transform.basis.y * jump_force
		jumped.emit(transform.basis.y)
		if gravity_system:
			gravity_system.force_airborne()
		_is_grounded = false
		intent.jump = false
		_vehicle_controller.consume_jump()

	# 8. Boost — only on the ground or in the air. While attached to a wall/ceiling the
	# forward axis points up the surface, so boosting there flings the launch unpredictably
	# high; disabling it keeps wall jump-offs consistent.
	var boost_allowed := true
	if gravity_system:
		var bstate := gravity_system.get_state()
		boost_allowed = (bstate == GravitySystem.AttachmentState.GROUNDED
				or bstate == GravitySystem.AttachmentState.AIRBORNE)

	if intent.boost and boost_allowed and _boost_cooldown_timer <= 0.0 and not _boost_active and signed_forward_speed >= 0.0:
		_boost_active = true
		_boost_timer = boost_duration
		_boost_cooldown_timer = boost_cooldown
		# Instant burst — the surge arrives on this frame, not gradually
		velocity += forward * boost_kick_speed

	if _boost_active:
		# Gentle sustain that fades over the duration, holding the burst rather than building it.
		# Only thrusts when boost is allowed (ground/air) — on a wall the timer still runs out but
		# no force is applied, so a boost can't sustain a wall climb.
		if boost_allowed:
			var boost_ratio := _boost_timer / boost_duration if boost_duration > 0.0 else 0.0
			velocity += forward * boost_sustain_force * boost_ratio * delta
		_boost_timer -= delta
		if _boost_timer <= 0.0:
			_boost_active = false

	_boost_cooldown_timer = maxf(_boost_cooldown_timer - delta, 0.0)

	# 8.5. Sustained wall-riding update — explicit call guarantees it runs after velocity rebuild
	if _wall_riding:
		_wall_riding.update_wall(delta)

	# 8.6. Cap speed while wall-riding so a fast or boosted entry can't fling the launch off the
	# wall. Uses wall_ride_speed_cap, NOT max_speed: the jump-off preserves forward momentum that
	# points up the wall during a climb, so it must stay bounded even when ground max_speed is high.
	if gravity_system:
		var wstate := gravity_system.get_state()
		if (wstate == GravitySystem.AttachmentState.WALL_LEFT
				or wstate == GravitySystem.AttachmentState.WALL_RIGHT):
			var sp := velocity.length()
			if sp > wall_ride_speed_cap:
				velocity = velocity * (wall_ride_speed_cap / sp)

	# 9. Wall attach / detach / save
	if intent.wall_attach:
		if _wall_riding and _wall_riding.is_wall_riding():
			_wall_riding.try_wall_detach(intent.steer, intent.accelerate, intent.brake)
			_vehicle_controller.consume_wall_attach()
		elif _wall_riding:
			# Ride a glancing wall; if none, try a SAVE — deflect off a wall you're heading into.
			if _wall_riding._try_attach_to_wall():
				_vehicle_controller.consume_wall_attach()
			elif _wall_riding._try_wall_save(intent.steer):
				_vehicle_controller.consume_wall_attach()
		intent.wall_attach = false

	if _trick_active:
		# The forward axis tumbles mid-trick, so its projection is meaningless. Use HORIZONTAL travel
		# speed (perpendicular to gravity), NOT velocity.length(): the full magnitude grows with the
		# fall, which made get_speed() spike and the camera FOV lurch during tricks. Horizontal travel
		# speed is ~constant (momentum is preserved), so the FOV stays calm.
		var trick_horiz := velocity - gravity_up * velocity.dot(gravity_up)
		_signed_forward_speed = trick_horiz.length()
		_current_speed = _signed_forward_speed
	else:
		_signed_forward_speed = velocity.dot(forward)
		_current_speed = absf(_signed_forward_speed)

	# Speed-based flow accumulation (GDD primary trigger) — grounded high-speed driving feeds flow
	if _is_grounded and is_instance_valid(_flow_system) and max_speed > 0.0:
		if _current_speed >= max_speed * flow_speed_threshold_ratio:
			_flow_system.increase(flow_per_second_at_speed * delta, "high_speed")

	# Drift flow — reward active drifting with steering input
	if _is_drifting and absf(intent.steer) > 0.1 and is_instance_valid(_flow_system):
		_flow_system.increase(drift_flow_per_second * delta, "drift")

	# 10. Landing impact detection — read from the incoming (pre-rebuild) velocity, since the
	# grounded velocity rebuild above has already flattened this frame's fall component. Reading
	# the post-rebuild velocity here gave impact_velocity ~0 (camera dip never fired) and a
	# landing_dot ~0 (steep landings were never penalized — every landing felt identical).
	if not _was_grounded_last_frame and _is_grounded:
		var impact_velocity := absf(incoming_velocity.dot(gravity_up))
		landed.emit(impact_velocity)

		var surface_normal := gravity_up
		var is_wall := false
		if gravity_system:
			surface_normal = gravity_system.get_surface_normal()
			var state := gravity_system.get_state()
			is_wall = (state == GravitySystem.AttachmentState.WALL_LEFT or state == GravitySystem.AttachmentState.WALL_RIGHT)

		# Approach angle: velocity parallel to the surface (clean) -> ~0; a steep dive -> ~1.
		# Penalty scales the surviving horizontal travel speed only — the fall component is
		# already gone, so a clean fast landing keeps its momentum (08_Movement_Feel_Targets.md).
		if not is_wall and incoming_velocity.length() > 0.0 and surface_normal != Vector3.ZERO:
			var landing_dot := absf(incoming_velocity.normalized().dot(surface_normal))
			# Perfect landing: came down clean (velocity ~parallel to the surface) from a real drop.
			if landing_dot < clean_landing_max_dot and impact_velocity >= clean_landing_min_impact:
				clean_landing.emit(impact_velocity)
			if landing_dot > 0.2:
				var penalty_factor: float
				if landing_angle_penalty_curve:
					penalty_factor = landing_angle_penalty_curve.sample(landing_dot)
				else:
					# Tuned to 08: clean ~100%, 30deg-off ~85%, 60deg-off ~55%, straight-down ~40%.
					penalty_factor = landing_dot * landing_dot * 0.6
				velocity *= (1.0 - penalty_factor)
				_current_speed = velocity.length()

		# Air-trick landing. A trick rotates orientation freely, so the car comes down on its WHEELS (clean) or its
		# ROOF/side (a crash) — it's a car, inverted landings aren't a free reset. Only evaluated when
		# a trick happened (else an upright landing on a slope would false-trigger). orient_dot: 1 =
		# wheels-down, 0 = on its side, <0 = on the roof.
		if _trick_rotation_accum > 0.0 and not is_wall and surface_normal != Vector3.ZERO:
			var orient_dot := incoming_basis_y.dot(surface_normal)        # 1 wheels-down, <0 roof
			# Facing: was the car's REAL front (pre-recovery) pointing along travel? The car has a
			# fixed front — a half-spin that lands you rear-first is NOT a clean drive-away.
			var facing_dot := 1.0                                         # 1 front-first, <0 rear-first
			var travel_flat := incoming_velocity - surface_normal * incoming_velocity.dot(surface_normal)
			if travel_flat.length() > 1.0:
				facing_dot = incoming_forward.dot(travel_flat.normalized())
			# Clean needs BOTH wheels-down and front-first (and a full enough rotation).
			if orient_dot >= air_trick_clean_dot and facing_dot >= air_trick_facing_dot and _trick_rotation_accum >= air_trick_min_degrees:
				trick_landed.emit(_trick_rotation_accum, true)
				if is_instance_valid(_flow_system):
					_flow_system.increase(trick_flow_per_360 * (_trick_rotation_accum / 360.0), "air_trick")
			else:
				# Landed on the roof/side OR facing the wrong way = CRASH: bleed momentum + Flow by the
				# WORSE of the two errors. step-2 still recovers a drivable forward heading so you keep
				# going (Pillar 5: failure costs momentum, not progress). No trick reward.
				var orient_sev := clampf((air_trick_clean_dot - orient_dot) / (air_trick_clean_dot + 1.0), 0.0, 1.0)
				var facing_sev := clampf((air_trick_facing_dot - facing_dot) / (air_trick_facing_dot + 1.0), 0.0, 1.0)
				var severity := maxf(orient_sev, facing_sev)
				if severity > 0.0:
					velocity *= (1.0 - trick_crash_speed_penalty * severity)
					_current_speed = velocity.length()
					if is_instance_valid(_flow_system):
						_flow_system.decrease(trick_crash_flow_penalty * severity, "bad_landing")
				if _trick_rotation_accum >= air_trick_min_degrees:
					trick_landed.emit(_trick_rotation_accum, false)
		_trick_rotation_accum = 0.0

	# 11. move_and_slide()
	move_and_slide()

	# 12. Gravity accumulation — after move_and_slide so this frame's landing impact_velocity is
	# not inflated. GravitySystem composes the applied gravity (Seam 2): pure into-surface while
	# attached (H4-clean), world gravity airborne. VehiclePhysics just applies it, so Phase 2's
	# tangent gravity needs no change here.
	if gravity_system:
		velocity += gravity_system.get_applied_gravity() * delta
	else:
		velocity += gravity_vec * delta

	_was_grounded_last_frame = _is_grounded


# Read-only access to current speed — used by DynamicCamera in Task 002.
func get_speed() -> float:
	return _current_speed


# Read-only access to grounded state — used by camera landing dip in Task 002.
func is_grounded() -> bool:
	return _is_grounded


func is_boost_active() -> bool:
	return _boost_active


func get_boost_cooldown_remaining() -> float:
	return _boost_cooldown_timer


# Read-only access to reverse state — used by debug overlay and camera.
func is_reversing() -> bool:
	return _signed_forward_speed < -0.5


# Reduces current speed by a flat amount — used by WallRiding for wall drag
func apply_speed_decay(amount: float) -> void:
	var forward := -transform.basis.z
	var current := velocity.dot(forward)
	var reduced := maxf(current - amount, 0.0)
	var lateral_comp := velocity.dot(transform.basis.x)
	var surface_normal_comp := velocity.dot(transform.basis.y)
	velocity = forward * reduced + transform.basis.x * lateral_comp + transform.basis.y * surface_normal_comp

func get_steer_input() -> float:
	return _last_steer

func is_drifting() -> bool:
	return _is_drifting

func is_tricking() -> bool:
	return _trick_active

func get_trick_rotation() -> float:
	return _trick_rotation_accum

# Direct velocity override — used by wall jump
func set_vehicle_velocity(new_velocity: Vector3) -> void:
	velocity = new_velocity

# Returns current velocity vector — used by WallRiding
func get_vehicle_velocity() -> Vector3:
	return velocity
