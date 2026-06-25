class_name VehicleVisuals
extends Node3D

# ============================================================================
#  VehicleVisuals (013) — keeps the car MESH planted, and gives landings weight.
# ----------------------------------------------------------------------------
#  Passive VISUAL helper. Owns the car-mesh child's local transform; writes NOTHING
#  to physics/velocity/state (observer discipline, like DynamicCamera / WallVFX).
#
#  It composes the mesh's local transform each frame from a captured base (scale +
#  180° yaw, read from the scene) plus three dynamic, purely-cosmetic layers:
#
#   1. GROUND-SNAP (always): the collision capsule hovers above the surface by a
#      varying amount, so we raycast down the car's -Y to the real surface and set
#      the mesh height onto it (flat / ramp / loop / wall; airborne → wheels tuck).
#   2. LANDING PITCH SETTLE (A2): the physics body snaps flat on touchdown (so
#      momentum is preserved), but the mesh keeps the dive pitch and EASES to flat
#      over ~0.3s — pivoting about a point near the FRONT so a nosedive lifts the
#      rear down rather than burying the nose. Includes a small extra nose-dip on
#      impact (B2, suspension compress at the front).
#   3. SQUASH (B1): on impact the body compresses vertically (scale Y), springing
#      back — weight without a physics bounce. Scales around the wheels (no clip).
#
#  All cosmetic; tricks/physics are untouched. Knobs are exported.
# ============================================================================

@export var vehicle_path: NodePath = NodePath("..")      ## the VehiclePhysics (parent)
@export var mesh_path: NodePath = NodePath("../AE86")     ## the car-mesh instance to drive
@export var enabled: bool = true

@export_group("Ground Snap")
@export var ray_length: float = 4.0          ## how far down the car's -Y to look for the surface
@export var wheel_offset: float = 0.0         ## fine-tune: + raises the car off the surface, - sinks it
@export var snap_smoothing: float = 18.0      ## lerp rate of the visual height (higher = snappier)
@export var airborne_offset: float = -0.8     ## mesh local Y when airborne (wheels tuck under the body)

@export_group("Landing Settle (A2 / B2)")
@export var landing_settle_recovery: float = 10.0  ## how fast the dive pitch eases to flat (per sec) — higher = quicker/subtler
@export var landing_settle_max_deg: float = 18.0   ## clamp on the visual landing pitch — kept low so even a steep dive settles gently
@export var landing_pivot_forward: float = 1.6     ## pitch pivots this far ahead of centre (m) so the nose doesn't bury
@export var nose_dip_scale: float = 0.003          ## extra nose-down (rad) per m/s of impact (subtle front compress)

@export_group("Suspension Squash (B1)")
@export var squash_scale: float = 0.004       ## vertical compress per m/s of impact (subtle)
@export var squash_max: float = 0.07          ## max compress (fraction of height)
@export var squash_recovery: float = 10.0     ## how fast it springs back (per sec)
@export var land_min_impact: float = 3.0      ## below this impact, no squash/dip (ignore spawn-settle / small hops)

var _vehicle: Node3D
var _mesh: Node3D
var _base_rot: Quaternion = Quaternion.IDENTITY
var _base_scale: Vector3 = Vector3.ONE
var _cur_y: float = -1.5
var _settle_pitch: float = 0.0   # current eased landing pitch (rad; negative = nose-down)
var _squash: float = 0.0         # current eased vertical compress (0..1)


func _ready() -> void:
	_vehicle = get_node_or_null(vehicle_path) as Node3D
	_mesh = get_node_or_null(mesh_path) as Node3D
	if _mesh:
		_cur_y = _mesh.position.y
		_base_rot = _mesh.transform.basis.get_rotation_quaternion()
		_base_scale = _mesh.transform.basis.get_scale()
	if is_instance_valid(_vehicle) and _vehicle.has_signal("landed"):
		_vehicle.landed.connect(_on_landed)


# Impact kicks off the squash (B1) and an extra nose-dip on top of the dive pitch (A2/B2).
func _on_landed(impact_velocity: float) -> void:
	if impact_velocity < land_min_impact:
		return
	var max_rad := deg_to_rad(landing_settle_max_deg)
	var dive := 0.0
	if is_instance_valid(_vehicle) and _vehicle.has_method("get_last_landing_pitch"):
		dive = _vehicle.get_last_landing_pitch()          # negative = nose-down dive
	# Continue the dive pitch (A2) + a small impact nose-dip (B2), both nose-down.
	_settle_pitch = clampf(dive - impact_velocity * nose_dip_scale, -max_rad, max_rad)
	_squash = clampf(impact_velocity * squash_scale, 0.0, squash_max)


func _physics_process(delta: float) -> void:
	if not enabled or not is_instance_valid(_vehicle) or not is_instance_valid(_mesh):
		return

	# 1. Ground-snap height ----------------------------------------------------
	var target_y := _cur_y
	var grounded := true
	if _vehicle.has_method("is_grounded"):
		grounded = _vehicle.is_grounded()
	if grounded:
		var b := _vehicle.global_transform.basis
		var origin := _vehicle.global_position
		var down := -b.y.normalized()
		var space := _vehicle.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(
			origin + b.y * 0.3, origin + down * ray_length, 0xFFFFFFFF, [_vehicle.get_rid()]
		)
		var hit := space.intersect_ray(q)
		if hit:
			target_y = -((hit.position - origin).dot(down)) + wheel_offset
	else:
		target_y = airborne_offset
	_cur_y = lerpf(_cur_y, target_y, clampf(delta * snap_smoothing, 0.0, 1.0))

	# 2. Ease the landing pitch + squash back to rest --------------------------
	_settle_pitch = lerpf(_settle_pitch, 0.0, clampf(delta * landing_settle_recovery, 0.0, 1.0))
	_squash = lerpf(_squash, 0.0, clampf(delta * squash_recovery, 0.0, 1.0))

	# 3. Compose the mesh transform: base (yaw+scale) + squash, then pitch about a
	#    forward pivot, dropped to the snapped height. All in the vehicle's local frame.
	var scale_y := _base_scale.y * (1.0 - _squash)
	var base_basis := Basis(_base_rot).scaled(Vector3(_base_scale.x, scale_y, _base_scale.z))
	var m0 := Transform3D(base_basis, Vector3(0.0, _cur_y, 0.0))
	if absf(_settle_pitch) > 0.0001:
		var rp := Basis(Vector3.RIGHT, _settle_pitch)            # pitch about the car's lateral axis
		var pivot := Vector3(0.0, _cur_y, -landing_pivot_forward) # near the front, at wheel height
		_mesh.transform = Transform3D(rp, pivot - rp * pivot) * m0
	else:
		_mesh.transform = m0
