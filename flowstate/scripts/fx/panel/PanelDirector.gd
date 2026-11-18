class_name PanelDirector
extends CanvasLayer

# ============================================================================
#  PanelDirector — the FLOWSTATE Comic Compositor (reusable engine subsystem)
# ----------------------------------------------------------------------------
#  Gameplay emits a SEMANTIC EVENT; the Director looks up its (semantic) recipe
#  and assembles a Composition around the car per the visual grammar. It is the
#  ONLY place that translates semantics -> visuals. It is generic: it never names
#  an event — adding an event = adding a recipe.
#
#  PHASE 2 adds the ACTION VECTOR: each composition is placed/oriented by a vector
#  derived from the car's real motion (slip, vertical velocity, impact, banking),
#  scaled by the maneuver's intensity — so it captures intent, not just position.
# ============================================================================

@export var vehicle_path: NodePath
@export var recipe_library: PanelRecipeLibrary            ## assign a .tres, else default() is used
@export var ref_speed: float = 30.0                       ## speed mapping to full action magnitude (intent normaliser)
@export var probe_length: float = 2.0                     ## world units used to project a 3D direction to screen
@export var exclusion_radius: float = 95.0                ## the car's empty centre — no major primitive inside (v2)
@export var layer_index: int = 50

var _vehicle: Node3D
var _library: PanelRecipeLibrary
var _momentum: MomentumStack
var _field: EnvironmentalField


func _ready() -> void:
	layer = layer_index
	_vehicle = get_node_or_null(vehicle_path) as Node3D
	_library = recipe_library if recipe_library != null else PanelRecipeLibrary.default()
	# Environmental motion field — the car's WORLD-speed (a separate persistent system,
	# on its own lower CanvasLayer so it streams BEHIND the comic compositions).
	var env_layer := CanvasLayer.new()
	env_layer.layer = layer_index - 5
	add_child(env_layer)
	_field = EnvironmentalField.new()
	_field.init(_vehicle, Callable(self, "get_car_anchor"))
	env_layer.add_child(_field)

	_momentum = MomentumStack.new()                       # persistent combo memory (v2)
	_momentum.init(Callable(self, "get_car_anchor"))
	add_child(_momentum)


# --- public API: the ONLY thing gameplay calls -------------------------------
func compose(event_id: StringName, context: Dictionary = {}) -> Composition:
	var recipe := _library.get_recipe(event_id)
	if recipe == null:
		return null
	# Capture the maneuver's intent in world space NOW (frozen); the Composition
	# re-projects it to the current screen each frame (origin tracks the car).
	var world_action := _compute_world_action(recipe.family, _read_car_state(), context)
	var comp := Composition.new()
	add_child(comp)
	comp.setup(recipe, context, Callable(self, "project_action").bind(world_action), exclusion_radius)
	return comp


# v2: the multiplier is a PERSISTENT stack, pushed independently of ephemeral events.
func push_multiplier(value: float) -> void:
	if _momentum != null:
		_momentum.push(value)


# --- Action Vector, part 1: semantics + car state -> WORLD-space intent -------
# Pure (takes a state dict, no node reads) so it is deterministic and testable
# without a camera. THIS is where a maneuver's intent is captured: direction from
# the relevant motion, magnitude from how hard it was performed.
func _compute_world_action(family: PanelGrammar.Family, s: Dictionary, context: Dictionary) -> Dictionary:
	var world_up := Vector3.UP
	var fwd: Vector3 = s.forward
	var car_up: Vector3 = s.up
	var vel: Vector3 = s.velocity
	var speed := vel.length()
	var dir := world_up
	var roll_ref := car_up
	var mag := 0.5

	match family:
		PanelGrammar.Family.SLIDE:
			# Drift: the sideways slip (velocity minus its forward + vertical parts).
			var lateral := vel - fwd * vel.dot(fwd)
			lateral -= car_up * lateral.dot(car_up)
			dir = lateral.normalized() if lateral.length() > 0.1 else s.right
			roll_ref = car_up
			mag = clampf(lateral.length() / ref_speed, 0.0, 1.5)   # how hard the slide is
		PanelGrammar.Family.LAUNCH:
			dir = world_up
			roll_ref = car_up
			mag = clampf(maxf(vel.y, 0.0) / ref_speed, 0.0, 1.5)   # how hard the launch is
		PanelGrammar.Family.IMPACT:
			dir = -world_up
			roll_ref = car_up
			var impact: float = float(context.get("impact", absf(minf(vel.y, 0.0))))
			mag = clampf(impact / ref_speed, 0.0, 1.5)             # how hard the landing is
		PanelGrammar.Family.WALL:
			dir = fwd                                              # the run direction
			roll_ref = car_up                                     # banks to the wall via the tilted up
			mag = clampf(speed / ref_speed, 0.0, 1.5)
		PanelGrammar.Family.DANGER:
			dir = (context["hazard_dir"] as Vector3).normalized() if context.has("hazard_dir") else s.right
			roll_ref = car_up
			mag = clampf(speed / ref_speed, 0.0, 1.2)
		PanelGrammar.Family.THRUST:
			dir = vel.normalized() if speed > 0.5 else fwd
			roll_ref = car_up
			mag = clampf(speed / ref_speed, 0.3, 1.5)
		PanelGrammar.Family.REWARD:
			dir = world_up
			roll_ref = world_up                                   # flat, HUD-ish reward
			mag = clampf(float(context.get("tier", 1)) / 5.0, 0.4, 1.5)
		PanelGrammar.Family.FAULT:
			dir = -world_up
			roll_ref = world_up
			mag = 0.7
		_:
			dir = world_up; roll_ref = car_up; mag = 0.5

	if dir.length() < 0.001:
		dir = world_up
	return {dir = dir.normalized(), roll_ref = roll_ref.normalized(), magnitude = mag}


func _read_car_state() -> Dictionary:
	if not is_instance_valid(_vehicle):
		return {pos = Vector3.ZERO, forward = Vector3.FORWARD, up = Vector3.UP, right = Vector3.RIGHT, velocity = Vector3.ZERO}
	var t := _vehicle.global_transform
	var vel := Vector3.ZERO
	if _vehicle is CharacterBody3D:
		vel = (_vehicle as CharacterBody3D).velocity
	return {pos = t.origin, forward = -t.basis.z, up = t.basis.y, right = t.basis.x, velocity = vel}


# --- Action Vector, part 2: project the frozen intent to the current screen ---
func project_action(world_action: Dictionary) -> ActionVector:
	var av := ActionVector.new()
	av.magnitude = world_action.magnitude
	var vp := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_3d()
	if cam == null or not is_instance_valid(_vehicle) or cam.is_position_behind(_vehicle.global_position):
		av.origin = vp * 0.5      # fallback: centre, axis up (no camera / off-screen)
		return av
	var pos: Vector3 = _vehicle.global_position
	av.origin = cam.unproject_position(pos)
	av.axis = _screen_dir(cam, pos, world_action.dir)
	av.roll = _screen_roll(cam, pos, world_action.roll_ref)
	return av


func get_car_anchor() -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_3d()
	if cam and is_instance_valid(_vehicle) and not cam.is_position_behind(_vehicle.global_position):
		return cam.unproject_position(_vehicle.global_position)
	return vp * 0.5


# Screen-space direction of a world-space vector at `pos` (as the camera sees it).
func _screen_dir(cam: Camera3D, pos: Vector3, world_dir: Vector3) -> Vector2:
	var d := cam.unproject_position(pos + world_dir * probe_length) - cam.unproject_position(pos)
	return d.normalized() if d.length() > 0.001 else Vector2.UP


# Screen banking: the angle between the car's projected up and screen-up.
func _screen_roll(cam: Camera3D, pos: Vector3, roll_ref: Vector3) -> float:
	var d := cam.unproject_position(pos + roll_ref * probe_length) - cam.unproject_position(pos)
	if d.length() < 0.001:
		return 0.0
	return d.angle() - Vector2.UP.angle()
