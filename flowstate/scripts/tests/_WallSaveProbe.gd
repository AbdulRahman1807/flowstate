extends SceneTree

# Verifies the wall SAVE / ricochet (verb #3, 011):
#   A. head-on-ish approach + save -> velocity deflects ALONG the wall (no longer into it), speed
#      magnitude preserved, on_wall_save fires, ScoreSystem "wall_save" style + Flow gained
#   B. speed below wall_save_min_speed -> no save
#   C. no wall in range -> no save
#   D. already wall-riding -> no save
#   E. integration: dead head-on + wall_attach through apply_intent (ride rejects >0.99) -> save fires
# Run: Godot --headless --path /Users/abdul/Desktop/flowstate/flowstate --script res://scripts/tests/_WallSaveProbe.gd

var _v: CharacterBody3D
var _vc
var _gs
var _wr
var _flow
var _score
var _ok := true
var _warmup := 0

# on_wall_save capture
var _fired := false
var _save_normal := Vector3.ZERO

func _initialize() -> void:
	var world := Node3D.new(); root.add_child(world)
	# floor
	var b := StaticBody3D.new(); b.position = Vector3(0, -0.5, 0)
	var s := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = Vector3(4000, 1, 4000); s.shape = bx
	b.add_child(s); world.add_child(b)
	# wall ahead (face toward +Z, normal (0,0,1)), tall+wide so angled rays hit it
	var w := StaticBody3D.new(); w.position = Vector3(0, 6, -3)
	var ws := CollisionShape3D.new(); var wbx := BoxShape3D.new(); wbx.size = Vector3(40, 12, 1); ws.shape = wbx
	w.add_child(ws); world.add_child(w)

	_v = CharacterBody3D.new(); _v.set_script(load("res://scripts/vehicle/VehiclePhysics.gd")); _v.name = "Vehicle"
	var col := CollisionShape3D.new(); var cap := CapsuleShape3D.new(); cap.radius = 0.8; cap.height = 1.6; col.shape = cap
	_v.add_child(col)
	_vc = _mk(_v, "VehicleController", Node, "res://scripts/vehicle/VehicleController.gd")
	_gs = _mk(_v, "GravitySystem", Node3D, "res://scripts/vehicle/GravitySystem.gd")
	_wr = _mk(_v, "WallRiding", Node, "res://scripts/vehicle/WallRiding.gd")
	_flow = _mk(_v, "FlowSystem", Node, "res://scripts/systems/FlowSystem.gd")
	_mk(_v, "WallSensor", Node, "res://scripts/vehicle/WallSensor.gd")
	world.add_child(_v)

	_score = Node.new(); _score.set_script(load("res://scripts/systems/ScoreSystem.gd")); _score.name = "ScoreSystem"
	world.add_child(_score)   # default vehicle_path "../Vehicle"

	_wr.on_wall_save.connect(_on_save)
	print("=== Wall Save Probe (min_speed=%.0f, min_approach=%.2f, range=%.1f) ===" % [
		_wr.wall_save_min_speed, _wr.wall_save_min_approach, _wr.wall_save_range])


func _physics_process(_dt: float) -> bool:
	_vc.set_physics_process(false)
	_warmup += 1
	if _warmup < 2:
		return false

	_score.start_run()

	# ---------- A. head-on-ish save: deflect along the wall ----------
	_airborne_facing_wall(Vector3(4, 0, -12))    # mostly into the wall (-Z) + along (+X)
	var speed0: float = _v.velocity.length()
	var flow0: float = (_flow as FlowSystem).get_value()
	_fired = false
	var saved: bool = _wr._try_wall_save()
	var nv: Vector3 = _v.velocity
	var into_after: float = nv.dot(_save_normal) if _fired else 0.0
	var style_a: float = _score.get_style_breakdown().get("wall_save", 0.0)
	var flow1: float = (_flow as FlowSystem).get_value()
	_check(saved and _fired, "A: save fired")
	_check(into_after > -1.0, "A: no longer heading into wall (into=%.2f, was %.1f)" % [into_after, -12.0 * 0])  # into_after ~0
	_check(nv.x > 1.0, "A: deflected ALONG the wall (vel.x=%.2f)" % nv.x)
	_check(nv.length() >= speed0 * 0.9, "A: speed preserved (%.2f -> %.2f)" % [speed0, nv.length()])
	_check(nv.y <= _wr.wall_save_pop + 0.1, "A: not floaty — vertical is just the pop (vel.y=%.2f)" % nv.y)
	_check(style_a > 0.0, "A: 'wall_save' style awarded (%.0f)" % style_a)
	_check(flow1 > flow0, "A: Flow gained (%.2f -> %.2f)" % [flow0, flow1])

	# ---------- A2. dead head-on must NOT rocket the car straight up (the floaty bug) ----------
	_airborne_facing_wall(Vector3(0, 0, -14))    # straight into the wall, no along-direction
	var hs0: float = Vector2(_v.velocity.x, _v.velocity.z).length()
	_fired = false
	_wr._try_wall_save(0.0)
	var dv: Vector3 = _v.velocity
	_check(_fired, "A2: dead head-on save fired")
	_check(dv.y <= _wr.wall_save_pop + 0.1, "A2: NOT floaty — vertical is just the pop (vel.y=%.2f)" % dv.y)
	_check(Vector2(dv.x, dv.z).length() >= hs0 * 0.9, "A2: horizontal momentum preserved (%.1f -> %.1f)" % [hs0, Vector2(dv.x, dv.z).length()])

	# ---------- B. too slow -> no save ----------
	_airborne_facing_wall(Vector3(1, 0, -3))     # speed ~3.2 < wall_save_min_speed
	_fired = false
	var saved_b: bool = _wr._try_wall_save()
	_check(not saved_b and not _fired, "B: no save below min speed")

	# ---------- C. no wall in range -> no save ----------
	_gs.force_airborne()
	_v.global_transform = Transform3D(Basis(), Vector3(300, 5, 300))   # far from any wall
	_v.velocity = Vector3(0, 0, -12)
	_fired = false
	var saved_c: bool = _wr._try_wall_save()
	_check(not saved_c and not _fired, "C: no save with no wall in range")

	# ---------- D. already riding -> no save ----------
	_airborne_facing_wall(Vector3(4, 0, -12))
	_wr._is_wall_riding = true
	_fired = false
	var saved_d: bool = _wr._try_wall_save()
	_wr._is_wall_riding = false
	_check(not saved_d and not _fired, "D: no save while already wall-riding")

	# ---------- E. integration: dead head-on via apply_intent (ride rejects, save fires) ----------
	_airborne_facing_wall(Vector3(0, 0, -12))    # dead head-on (toward_wall ~1.0, ride rejects >0.99)
	_fired = false
	var mi = load("res://scripts/vehicle/MovementIntent.gd").new()
	mi.wall_attach = true
	_v.apply_intent(mi)
	_check(_fired, "E: dead head-on + wall button -> save fires through step 9")

	if _ok:
		print("PASS")
	else:
		print("FAILED")
	print("=== done ===")
	return true


# Put the car airborne just in front of the wall with the given velocity.
func _airborne_facing_wall(vel: Vector3) -> void:
	_gs.force_airborne()
	_gs._attach_cooldown = 0.0
	_v.global_transform = Transform3D(Basis(), Vector3(0, 3, 0))
	_v.velocity = vel
	_v._was_grounded_last_frame = false


func _on_save(_speed: float, normal: Vector3) -> void:
	_fired = true
	_save_normal = normal


func _check(cond: bool, msg: String) -> void:
	print("  %s : %s" % ["ok " if cond else "FAIL", msg])
	if not cond:
		_ok = false


func _mk(parent: Node, n: String, base, path: String):
	var node = base.new(); node.set_script(load(path)); node.name = n
	parent.add_child(node); return node
