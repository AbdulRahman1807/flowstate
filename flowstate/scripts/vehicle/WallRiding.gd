class_name WallRiding
extends Node

@onready var gravity_system: GravitySystem = get_parent().get_node_or_null("GravitySystem")
@onready var vehicle_physics: VehiclePhysics = get_parent()
@onready var flow_system: FlowSystem = get_parent().get_node_or_null("FlowSystem")
@onready var wall_sensor: WallSensor = get_parent().get_node_or_null("WallSensor")

@export var wall_attach_min_speed: float = 5.0
@export var wall_jump_min_speed: float = 8.0
@export var wall_jump_force: float = 10.0
@export var wall_jump_up_force: float = 6.0
@export var wall_jump_forward_preserve: float = 0.85
# Directional jump-off: held inputs at the moment of jump shape the launch.
# Baseline (neutral steer) is deliberately small so leaving the wall flows UP + FORWARD off the
# surface with only enough perpendicular push to clear it — NOT a big sideways fling. Steering
# AWAY (perp_max) still gives a strong directional push-off; steering INTO (perp_min) barely peels.
@export var wall_jump_perp_min: float = 0.1       # perp push when steering INTO the wall (barely off)
@export var wall_jump_perp_max: float = 0.9       # perp push when steering AWAY from the wall (far off)
@export var wall_jump_forward_push: float = 8.0   # extra forward velocity added when holding accelerate (W)
@export var wall_jump_brake_min: float = 0.4      # launch velocity scale when fully braking (S)
@export var wall_speed_decay: float = 0.5
@export var wall_detach_speed: float = 5.0
@export var flow_per_second_on_wall: float = 0.6
@export var flow_on_wall_jump: float = 1.0
@export var flow_on_ceiling_transition: float = 1.0
@export var near_miss_speed_threshold: float = 6.0

signal on_wall_attach(entry_speed: float, wall_normal: Vector3)
signal on_wall_detach(ride_duration: float, exit_speed: float, reason: String)
signal on_wall_jump(speed_at_jump: float)
signal on_near_miss()

var _is_wall_riding: bool = false
var _wall_ride_timer: float = 0.0
var _near_miss_triggered: bool = false
var _last_fail_log_ms: int = 0

func _ready() -> void:
	if gravity_system:
		gravity_system.on_state_changed.connect(_on_gravity_state_changed)

# Throttles attach-failure logs so the input buffer's per-frame retries don't spam the console.
func _log_fail(msg: String) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_fail_log_ms > 400:
		_last_fail_log_ms = now
		print(msg)

func _try_attach_to_wall() -> bool:
	if not is_instance_valid(gravity_system) or not is_instance_valid(vehicle_physics):
		_log_fail("[Wall] FAIL: node refs invalid")
		return false

	var current_speed := vehicle_physics.velocity.length()
	if current_speed < wall_attach_min_speed:
		_log_fail("[Wall] FAIL: speed %.1f < min %.1f" % [current_speed, wall_attach_min_speed])
		return false

	var state := gravity_system.get_state()
	if state == GravitySystem.AttachmentState.INVERTED:
		_log_fail("[Wall] FAIL: state is INVERTED")
		return false
	if state == GravitySystem.AttachmentState.WALL_LEFT or state == GravitySystem.AttachmentState.WALL_RIGHT:
		_log_fail("[Wall] FAIL: already on wall")
		return false

	var wall_normal := Vector3.ZERO
	if is_instance_valid(wall_sensor):
		var space_state := vehicle_physics.get_world_3d().direct_space_state
		wall_normal = wall_sensor.find_best_wall(
			vehicle_physics.global_position,
			vehicle_physics.velocity,
			space_state,
			[vehicle_physics.get_rid()]
		)

	if wall_normal == Vector3.ZERO:
		_log_fail("[Wall] FAIL: no wall in range (speed=%.1f range=%.1f)" % [current_speed, wall_sensor.max_wall_range if is_instance_valid(wall_sensor) else -1.0])
		return false

	if not gravity_system.request_wall_attach(wall_normal):
		_log_fail("[Wall] FAIL: gravity rejected attach (speed below min_attach_speed)")
		return false

	# Redirect velocity up-and-along the wall so the car climbs ONTO the surface instead of
	# wedging at the wall base. A ground-level alongside approach has no upward component, so
	# pure projection would just grind the car into the wall corner. We blend the along-wall
	# travel direction with the up-the-wall direction (preserving speed magnitude), so entry
	# direction still shapes the climb while guaranteeing the car gets up onto the wall.
	var wall_up := (Vector3.UP - wall_normal * Vector3.UP.dot(wall_normal)).normalized()
	var along := vehicle_physics.velocity - wall_normal * vehicle_physics.velocity.dot(wall_normal)
	var along_dir := along.normalized() if along.length_squared() > 0.01 else wall_up
	var climb_dir := (along_dir + wall_up).normalized()
	if climb_dir.length_squared() < 0.01:
		climb_dir = wall_up
	vehicle_physics.velocity = climb_dir * current_speed

	_is_wall_riding = true
	_wall_ride_timer = 0.0
	_near_miss_triggered = false

	print("[Wall] ATTACHED: normal=(%.2f,%.2f,%.2f) speed=%.1f" % [wall_normal.x, wall_normal.y, wall_normal.z, current_speed])
	emit_signal("on_wall_attach", current_speed, wall_normal)
	return true

# steer / accel / brake are the player's held inputs at the moment of jump (-1..1, 0..1, 0..1).
# They shape the launch direction — see the directional-jump exports.
func try_wall_detach(steer: float = 0.0, accel: float = 0.0, brake: float = 0.0) -> bool:
	if not _is_wall_riding:
		return false
	if not is_instance_valid(gravity_system) or not is_instance_valid(vehicle_physics):
		return false

	_is_wall_riding = false  # set early so _on_gravity_state_changed guard fires when force_airborne() emits
	var current_speed := vehicle_physics.velocity.length()

	if current_speed >= wall_jump_min_speed:
		var wall_normal := gravity_system.get_surface_normal()
		var current_velocity := vehicle_physics.velocity

		# Forward launch = the HORIZONTAL travel direction, NOT the up-the-wall facing. While
		# climbing a side wall the car's facing (-basis.z) tilts steeply UPWARD (steering up the
		# wall rotates forward toward +Y), so preserving momentum along that axis fires the car
		# nearly straight up — that is the floaty hover that kills flow. Projecting the facing onto
		# the horizontal plane preserves the momentum MAGNITUDE but redirects it into the travel
		# direction (only direction rotates, per the surface-transition rule), so the jump-off flows
		# fast and LOW into the next trick. The ONLY vertical in the launch is the up_force hop.
		var fwd_axis := -vehicle_physics.global_transform.basis.z
		var fwd_speed := current_velocity.dot(fwd_axis)
		var fwd_horiz := fwd_axis - Vector3.UP * fwd_axis.dot(Vector3.UP)
		if fwd_horiz.length_squared() < 0.01:
			# Facing ~straight up/down (rare): fall back to the horizontal velocity direction.
			var vel_horiz := current_velocity - Vector3.UP * current_velocity.dot(Vector3.UP)
			fwd_horiz = vel_horiz if vel_horiz.length_squared() > 0.01 else fwd_axis
		fwd_horiz = fwd_horiz.normalized()

		# Directional jump-off. `side` flips the steer meaning by wall side so that, in both
		# cases, steering AWAY from the wall maximises the push-off and steering INTO it
		# minimises it. (WALL_LEFT: D=away; WALL_RIGHT: A=away.)
		var side := -1.0 if gravity_system.get_state() == GravitySystem.AttachmentState.WALL_LEFT else 1.0
		var steer_away := clampf(steer * side, -1.0, 1.0)                         # +1 away, -1 into wall
		var perp_scale := lerpf(wall_jump_perp_min, wall_jump_perp_max, (steer_away + 1.0) * 0.5)

		var perp := wall_normal * wall_jump_force * perp_scale                    # off-wall push (A/D)
		var up := Vector3.UP * wall_jump_up_force                                 # the ONLY vertical in the launch
		var forward := fwd_horiz * (maxf(fwd_speed, 0.0) * wall_jump_forward_preserve + wall_jump_forward_push * clampf(accel, 0.0, 1.0))  # horizontal; W adds forward

		# Brake (S) bleeds the whole launch down.
		var jump_vel := (perp + up + forward) * lerpf(1.0, wall_jump_brake_min, clampf(brake, 0.0, 1.0))
		vehicle_physics.velocity = jump_vel
		gravity_system.force_airborne()

		if is_instance_valid(flow_system):
			flow_system.increase(flow_on_wall_jump, "wall_jump")

		emit_signal("on_wall_jump", jump_vel.length())
	else:
		gravity_system.force_airborne()

	emit_signal("on_wall_detach", _wall_ride_timer, current_speed, "player_toggle")
	_is_wall_riding = false
	_wall_ride_timer = 0.0
	return true

func _on_gravity_state_changed(new_state: GravitySystem.AttachmentState) -> void:
	if not _is_wall_riding:
		return

	var on_wall := (new_state == GravitySystem.AttachmentState.WALL_LEFT or
					new_state == GravitySystem.AttachmentState.WALL_RIGHT)
	if on_wall:
		return

	var current_speed := vehicle_physics.get_speed() if is_instance_valid(vehicle_physics) else 0.0
	var reason := "edge_exit"

	if new_state == GravitySystem.AttachmentState.INVERTED:
		reason = "ceiling_transition"
		if is_instance_valid(flow_system):
			flow_system.increase(flow_on_ceiling_transition, "ceiling_transition")
	elif current_speed < (gravity_system.detach_speed_threshold if is_instance_valid(gravity_system) else wall_detach_speed):
		reason = "speed_loss"

	emit_signal("on_wall_detach", _wall_ride_timer, current_speed, reason)
	_is_wall_riding = false
	_wall_ride_timer = 0.0

# Called explicitly by VehiclePhysics.apply_intent each frame — NOT _physics_process.
# Guarantees this runs after the velocity rebuild so apply_speed_decay is not overwritten,
# removing the scene-tree-order dependency that made wall drag non-deterministic.
func update_wall(delta: float) -> void:
	if not _is_wall_riding:
		return
	if not is_instance_valid(vehicle_physics):
		return

	_wall_ride_timer += delta

	vehicle_physics.apply_speed_decay(wall_speed_decay * delta)

	if is_instance_valid(flow_system):
		flow_system.increase(flow_per_second_on_wall * delta, "wall_ride")

	var current_speed := vehicle_physics.get_speed()
	if current_speed < near_miss_speed_threshold and current_speed >= wall_detach_speed:
		if not _near_miss_triggered:
			emit_signal("on_near_miss")
			_near_miss_triggered = true
	elif current_speed >= near_miss_speed_threshold:
		_near_miss_triggered = false

func is_wall_riding() -> bool:
	return _is_wall_riding

func get_wall_ride_timer() -> float:
	return _wall_ride_timer
