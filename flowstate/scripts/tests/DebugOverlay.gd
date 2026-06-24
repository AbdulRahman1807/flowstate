extends Label

@export var vehicle_path: NodePath
@export var score_path: NodePath   # optional — set in playground/track scenes to also show Score

var _vehicle_physics: VehiclePhysics
var _vehicle_controller: VehicleController
var _score                          # ScoreSystem (optional)
var _last_trick := "—"
var _last_trick_timer := 0.0
var _last_save := "—"
var _last_save_timer := 0.0


func _ready() -> void:
	var vehicle := get_node(vehicle_path) as VehiclePhysics
	_vehicle_physics = vehicle
	_vehicle_controller = vehicle.get_node("VehicleController") as VehicleController
	if not score_path.is_empty():
		_score = get_node_or_null(score_path)
	if _vehicle_physics:
		_vehicle_physics.trick_landed.connect(_on_trick_landed)
		var wr = _vehicle_physics.get_node_or_null("WallRiding")
		if wr:
			wr.on_wall_save.connect(_on_wall_save)


func _on_trick_landed(degrees: float, clean: bool) -> void:
	_last_trick = "%.0f° %s" % [degrees, "CLEAN" if clean else "botched"]
	_last_trick_timer = 3.0


func _on_wall_save(speed: float, _normal: Vector3) -> void:
	_last_save = "SAVE @ %.0f" % speed
	_last_save_timer = 3.0


func _process(delta: float) -> void:
	if _vehicle_physics == null or _vehicle_controller == null:
		return
	_last_trick_timer = maxf(_last_trick_timer - delta, 0.0)
	_last_save_timer = maxf(_last_save_timer - delta, 0.0)

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

	var drift_text := "yes" if _vehicle_physics.is_drifting() else "no"
	var trick_text := ("ROTATING %.0f deg" % _vehicle_physics.get_trick_rotation()) if _vehicle_physics.is_tricking() else "no"
	var last_trick_text := _last_trick if _last_trick_timer > 0.0 else "—"
	var last_save_text := _last_save if _last_save_timer > 0.0 else "—"
	var score_text := ""
	if _score:
		score_text = "\nScore: %.0f" % _score.get_score()

	text = "Speed: %.1f (%s)\nGrounded: %s\nBoost: %s (cooldown: %.2fs)\nJump buffer: %.3fs\nAttachment: %s\nGravity: (%.1f, %.1f, %.1f)\nWallRiding: %s\nFlow: %s\nDrift: %s\nAir trick: %s\nLast trick: %s\nLast save: %s%s" % [
		_vehicle_physics.get_speed(),
		gear,
		_vehicle_physics.is_grounded(),
		boost_state,
		cooldown,
		_vehicle_controller.get_jump_buffer_timer(),
		attachment,
		gravity_vec.x, gravity_vec.y, gravity_vec.z,
		wall_riding_text,
		flow_text,
		drift_text,
		trick_text,
		last_trick_text,
		last_save_text,
		score_text
	]
