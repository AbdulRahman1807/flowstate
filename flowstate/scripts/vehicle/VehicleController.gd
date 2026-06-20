class_name VehicleController
extends Node

@export var jump_buffer_time: float = 0.12
@export var wall_attach_buffer_time: float = 0.1

@onready var vehicle_physics: VehiclePhysics = get_parent()

var _jump_buffer_timer: float = 0.0
var _wall_attach_buffer_timer: float = 0.0

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time
	if Input.is_action_just_pressed("wall_attach"):
		_wall_attach_buffer_timer = wall_attach_buffer_time

	_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)
	_wall_attach_buffer_timer = maxf(_wall_attach_buffer_timer - delta, 0.0)

	var intent := MovementIntent.new()
	intent.steer = Input.get_axis("steer_right", "steer_left")
	intent.accelerate = Input.get_action_strength("accelerate")
	intent.brake = Input.get_action_strength("brake")
	intent.jump = _jump_buffer_timer > 0.0
	intent.boost = Input.is_action_pressed("boost")
	intent.wall_attach = _wall_attach_buffer_timer > 0.0

	vehicle_physics.apply_intent(intent)


func consume_jump() -> void:
	_jump_buffer_timer = 0.0


func consume_wall_attach() -> void:
	_wall_attach_buffer_timer = 0.0


func get_jump_buffer_timer() -> float:
	return _jump_buffer_timer
