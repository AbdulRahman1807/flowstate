extends Label

@export var vehicle_path: NodePath

var _vehicle_physics: VehiclePhysics
var _vehicle_controller: VehicleController


func _ready() -> void:
	var vehicle := get_node(vehicle_path) as VehiclePhysics
	_vehicle_physics = vehicle
	_vehicle_controller = vehicle.get_node("VehicleController") as VehicleController


func _process(_delta: float) -> void:
	if _vehicle_physics == null or _vehicle_controller == null:
		return

	var boost_state := "active" if _vehicle_physics.is_boost_active() else "inactive"
	var cooldown := _vehicle_physics.get_boost_cooldown_remaining()

	var gear := "Reverse" if _vehicle_physics.is_reversing() else "Forward"

	var attachment := "N/A"
	var gravity_vec := Vector3.ZERO
	if _vehicle_physics.gravity_system:
		var state_names = ["GROUNDED", "WALL_LEFT", "WALL_RIGHT", "INVERTED", "AIRBORNE"]
		attachment = state_names[_vehicle_physics.gravity_system.get_state()]
		gravity_vec = _vehicle_physics.gravity_system.get_gravity_vector()

	var wall_riding_text := "N/A"
	var wall_riding = _vehicle_physics.get_node_or_null("WallRiding")
	if wall_riding:
		wall_riding_text = "Active" if wall_riding._is_wall_riding else "Inactive"
		if wall_riding._is_wall_riding:
			wall_riding_text += " | Timer: %.2fs" % [wall_riding._wall_ride_timer]

	var flow_text := "N/A"
	var flow_system = _vehicle_physics.get_node_or_null("FlowSystem")
	if flow_system:
		flow_text = "Value: %.2f | Mult: %.2fx" % [flow_system._flow_value, flow_system.get_multiplier()]

	text = "Speed: %.1f (%s)\nGrounded: %s\nBoost: %s (cooldown: %.2fs)\nJump buffer: %.3fs\nAttachment: %s\nGravity: (%.1f, %.1f, %.1f)\nWallRiding: %s\nFlow: %s" % [
		_vehicle_physics.get_speed(),
		gear,
		_vehicle_physics.is_grounded(),
		boost_state,
		cooldown,
		_vehicle_controller.get_jump_buffer_timer(),
		attachment,
		gravity_vec.x, gravity_vec.y, gravity_vec.z,
		wall_riding_text,
		flow_text
	]
