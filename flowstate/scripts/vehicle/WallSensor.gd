class_name WallSensor
extends Node

@export var scan_ray_count: int = 9
@export var scan_cone_angle: float = 90.0   # Half-width of the horizontal fan around travel direction (±90° = full sideways coverage)
@export var max_wall_range: float = 3.0   # Must be <= GravitySystem.wall_stick_range, or attached walls cannot be sustained
@export var min_approach_dot: float = -0.25  # Allow driving parallel/alongside a wall (toward_wall ≈ 0); only reject clearly moving away
@export var max_approach_dot: float = 0.99
@export var collision_mask: int = 0xFFFFFFFF

func find_best_wall(origin: Vector3, velocity: Vector3, space_state: PhysicsDirectSpaceState3D, exclude: Array[RID] = []) -> Vector3:
	if velocity.length_squared() < 0.001:
		return Vector3.ZERO

	var vel_dir := velocity.normalized()
	var rays := _generate_cone_rays(vel_dir)
	var best_normal := Vector3.ZERO
	var best_score := -INF

	for ray_dir in rays:
		var from := origin
		var to := origin + ray_dir * max_wall_range
		var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask)
		query.exclude = exclude
		var result := space_state.intersect_ray(query)

		if result.is_empty():
			continue

		var hit_normal: Vector3 = result.normal
		var hit_distance: float = origin.distance_to(result.position)

		# Surface type gate: wall only (not floor or ceiling)
		if absf(hit_normal.dot(Vector3.UP)) > 0.55:
			continue

		var toward_wall := -vel_dir.dot(hit_normal)

		# Approach gate: allow parallel/alongside approaches, reject only walls being driven away from
		# and near-perfect head-on slams.
		if toward_wall < min_approach_dot or toward_wall > max_approach_dot:
			continue

		# Range gate (bounds check — redundant given ray length but explicit)
		if hit_distance > max_wall_range:
			continue

		# Score candidate: favour proximity (60%) over approach (40%). When riding alongside,
		# toward_wall ≈ 0 for all candidates, so proximity is what picks the wall you are next to.
		var distance_norm := hit_distance / max_wall_range
		var score := maxf(toward_wall, 0.0) * 0.4 + (1.0 - distance_norm) * 0.6

		if score > best_score:
			best_score = score
			best_normal = hit_normal

	return best_normal


func _generate_cone_rays(center: Vector3) -> Array[Vector3]:
	var rays: Array[Vector3] = []

	# Horizontal fan around the direction of travel. Prototype walls are vertical and are
	# typically beside the vehicle when you want to ride them — a narrow velocity-aligned cone
	# misses any wall you are driving parallel to. Sweeping ±scan_cone_angle (default ±90°)
	# in the horizontal plane catches walls directly to the left and right.
	var up_ref := Vector3.UP
	var flat := center - up_ref * center.dot(up_ref)
	if flat.length_squared() < 0.001:
		flat = center  # velocity nearly vertical — fall back to raw direction
	flat = flat.normalized()

	var half_angle_rad := deg_to_rad(scan_cone_angle)
	var count := maxi(scan_ray_count, 2)
	for i in range(count):
		var t := -1.0 + 2.0 * float(i) / float(count - 1)  # -1 .. +1 across the fan
		var ray := flat.rotated(up_ref, t * half_angle_rad)
		rays.append(ray.normalized())

	return rays
