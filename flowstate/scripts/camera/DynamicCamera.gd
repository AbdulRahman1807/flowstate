class_name DynamicCamera
extends Camera3D

@export var vehicle_path: NodePath
@export var follow_distance: float = 8.0
@export var follow_height: float = 3.0
@export var fov_min: float = 75.0
@export var fov_max: float = 100.0
@export var fov_speed_range: Vector2 = Vector2(0.0, 40.0)
@export var fov_boost: float = 110.0
@export var boost_camera_pullback: float = 3.0
@export var fov_boost_engage: float = 6.0
@export var fov_boost_recovery: float = 3.0
@export var camera_lag: float = 0.15
@export var tilt_strength: float = 0.08
@export var tilt_smoothing: float = 6.0
@export var drift_travel_follow: float = 1.0   # While drifting, blend the follow direction toward travel (velocity) vs car facing. 0 = old facing-follow (camera veers with the yaw), 1 = fully behind travel (steady cam, car slides sideways in frame)
@export var landing_dip_strength: float = 0.4
@export var landing_dip_recovery: float = 8.0

var camera_up: Vector3 = Vector3.UP

var _vehicle: VehiclePhysics
var _current_tilt: float = 0.0
var _current_dip: float = 0.0
var _smoothed_back: Vector3 = Vector3.BACK
var _current_boost_fov_weight: float = 0.0

func _ready() -> void:
	top_level = true
	if not vehicle_path.is_empty():
		_vehicle = get_node_or_null(vehicle_path) as VehiclePhysics
		if _vehicle:
			_vehicle.landed.connect(_on_vehicle_landed)
			var back := _vehicle.global_transform.basis.z
			global_position = _vehicle.global_position + back * follow_distance + camera_up * follow_height
			
			var look_target := _vehicle.global_position + camera_up * (follow_height * 0.3)
			var look_dir := (look_target - global_position).normalized()
			if look_dir.length() > 0.01:
				var right := look_dir.cross(camera_up).normalized()
				var true_up := right.cross(look_dir).normalized()
				quaternion = Quaternion(Basis(right, true_up, -look_dir))

func _on_vehicle_landed(impact_velocity: float) -> void:
	_current_dip += landing_dip_strength * minf(impact_velocity / 10.0, 2.0)

func _physics_process(delta: float) -> void:
	if not _vehicle:
		return
		
	# 1. Update dip recovery
	_current_dip = lerpf(_current_dip, 0.0, landing_dip_recovery * delta)
	
	if _vehicle.gravity_system:
		camera_up = -_vehicle.gravity_system.get_gravity_vector().normalized()
		
	var speed := _vehicle.get_speed()
	
	# 2. FOV Mapping
	var boost_valid := _vehicle.is_boost_active() and speed > (fov_speed_range.x + 5.0)
	if boost_valid:
		_current_boost_fov_weight = lerpf(_current_boost_fov_weight, 1.0, fov_boost_engage * delta)
	else:
		_current_boost_fov_weight = lerpf(_current_boost_fov_weight, 0.0, fov_boost_recovery * delta)
		
	# FOV ramps from fov_speed_range.x up to the vehicle's max_speed, so the speed feedback always
	# scales to the current top speed — including while max_speed is being tuned live in the inspector.
	var fov_top_speed := maxf(_vehicle.max_speed, fov_speed_range.x + 1.0)
	var speed_ratio := clampf((speed - fov_speed_range.x) / (fov_top_speed - fov_speed_range.x), 0.0, 1.0)
	var curved_t := ease(speed_ratio, -2.0)
	var target_fov := lerpf(fov_min, fov_max, curved_t)
	fov = lerpf(target_fov, fov_boost, _current_boost_fov_weight)
	
	# 3. Position interpolation (lag, tightens at low speed)
	var active_follow_distance := follow_distance + (boost_camera_pullback * _current_boost_fov_weight)
	# Follow-back direction: normally behind the car's facing. While drifting the car yaws hard (the
	# facing rotates well past the slip angle), so chasing the facing makes the camera veer with the
	# slide. Anchor behind the DIRECTION OF TRAVEL instead (blended by drift_travel_follow) — the
	# camera stays steady on where you're heading and the car slides sideways in frame.
	# While DRIFTING (car yaws past its slip angle) or doing an AIR TRICK (basis tumbles), chasing
	# basis.z makes the camera lurch — anchor behind the DIRECTION OF TRAVEL instead. Tricks fully
	# commit to travel-follow; if the launch is near-vertical (little horizontal travel), hold the
	# last direction rather than chase the tumbling basis.
	if _vehicle.is_tricking():
		var tvel := _vehicle.velocity
		var tflat := tvel - camera_up * tvel.dot(camera_up)
		if tflat.length() > 1.0:
			_smoothed_back = _smoothed_back.lerp(-tflat.normalized(), delta * 3.0).normalized()
		# else: hold _smoothed_back steady — do not chase the tumbling basis
	else:
		var follow_back := _vehicle.global_transform.basis.z
		if drift_travel_follow > 0.0 and _vehicle.is_drifting():
			var vel := _vehicle.velocity
			var vel_flat := vel - camera_up * vel.dot(camera_up)   # travel direction in the camera's ground plane
			if vel_flat.length() > 1.0:
				follow_back = follow_back.lerp(-vel_flat.normalized(), drift_travel_follow).normalized()
		_smoothed_back = _smoothed_back.lerp(follow_back, delta * 3.0).normalized()
	var desired_pos := _vehicle.global_position + camera_up * (follow_height - _current_dip) + _smoothed_back * active_follow_distance
	var target_pos := _get_safe_camera_position(_vehicle.global_position, desired_pos)
	var effective_lag := lerpf(camera_lag * 0.3, camera_lag, speed_ratio)
	var smoothing := 1.0 / maxf(effective_lag, 0.001)
	global_position = global_position.lerp(target_pos, delta * smoothing)

	# 4. Tilt calculation
	var target_steer := _vehicle.get_steer_input()
	_current_tilt = lerpf(_current_tilt, target_steer * tilt_strength, delta * tilt_smoothing)
	
	# 5. Quaternion Rotation
	var look_target := _vehicle.global_position + camera_up * (follow_height * 0.3)
	var look_dir := (look_target - global_position).normalized()
	
	if look_dir.length() > 0.01:
		var right := look_dir.cross(camera_up)
		if right.length_squared() < 0.0001:
			# look_dir is (nearly) parallel to camera_up — cross collapses to zero, which would
			# NaN the basis. Fall back to the smoothed back-vector to derive a stable right axis.
			right = _smoothed_back.cross(camera_up)
			if right.length_squared() < 0.0001:
				right = Vector3.RIGHT
		right = right.normalized()
		var true_up := right.cross(look_dir).normalized()
		var desired_basis := Basis(right, true_up, -look_dir)
		
		# Apply local roll tilt
		desired_basis = desired_basis.rotated(look_dir, _current_tilt)
		
		var target_rotation := Quaternion(desired_basis)
		quaternion = quaternion.slerp(target_rotation, delta * tilt_smoothing)


func _get_safe_camera_position(vehicle_pos: Vector3, desired_pos: Vector3) -> Vector3:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		vehicle_pos, desired_pos, 0xFFFFFFFF, [_vehicle.get_rid()]
	)
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return desired_pos
	return result.position + result.normal * 0.3
