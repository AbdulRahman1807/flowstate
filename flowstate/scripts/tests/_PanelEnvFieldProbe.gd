extends SceneTree

# Guard for the ENVIRONMENTAL Action Line Field — the car's world-speed effect,
# independent of the comic compositions. Verifies it generates a field, is driven
# by SPEED (near-invisible at rest, intensifying with speed), is larger than the
# viewport (reaches/exceeds the edges), and is centred on the car.
# Run:
# Godot --headless --path /Users/abdul/Desktop/Personal/flowstate/flowstate --script res://scripts/tests/_PanelEnvFieldProbe.gd

class StubVehicle extends Node:
	var speed := 0.0
	func get_speed() -> float:
		return speed

var _field: EnvironmentalField
var _veh: StubVehicle
var _done := false
var _fail := 0


func _initialize() -> void:
	var world := Node.new()
	root.add_child(world)
	_veh = StubVehicle.new()
	world.add_child(_veh)
	_field = EnvironmentalField.new()
	world.add_child(_field)
	_field.init(_veh, Callable(self, "_anchor"))


func _anchor() -> Vector2:
	return Vector2(400.0, 300.0)


func _physics_process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	print("=== Environmental Field Probe ===")
	var vp := root.get_visible_rect().size

	_check("field generates a stroke field", _field._strokes.size() >= 40)

	_veh.speed = 0.0
	for i in 30:
		_field._process(0.05)
	var a_rest: float = _field._alpha
	_check("near-invisible at rest", a_rest < 0.08)

	_veh.speed = 60.0
	for i in 30:
		_field._process(0.05)
	var a_fast: float = _field._alpha
	_check("intensity driven by SPEED (fast >> rest)", a_fast > a_rest + 0.15)

	_check("field is larger than the viewport (reaches the edges)", _field.size.x > vp.x and _field.size.y > vp.y)

	var centre := _field.position + _field.size * 0.5
	_check("field is centred on the car", centre.distance_to(_anchor()) < 2.0)

	print("RESULT: %s" % ("PASS (all checks green)" if _fail == 0 else "FAIL (%d failed)" % _fail))
	return true


func _check(label: String, cond: bool) -> void:
	if not cond:
		_fail += 1
	print("  [%s] %s" % ["OK" if cond else "XX", label])
