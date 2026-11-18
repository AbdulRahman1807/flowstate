extends SceneTree

# Verifies ghost replay (M5) is DETERMINISTIC and inputs-only:
#   A. Recorder round-trip: N frames recorded -> ReplayData has N frames, start state stored,
#      a known frame's fields survive the clone.
#   B. Determinism: replaying the SAME recorded intents on an identical fresh vehicle from the
#      same start reproduces the trajectory (ghost end ~= player end), and it actually MOVED
#      (end is far from start, so we're not trivially matching two parked cars).
#
# Method: one player vehicle is driven through a scripted intent stream (recording each frame),
# then a second identical vehicle replays the recording. Both collide only with the floor (not
# each other) so the parked player can't deflect the ghost at the end of its run.
# Delta is 0 on the first physics tick, so both phases run only AFTER a short warm-up (constant
# delta) — otherwise frame-0 would integrate differently between record and replay.
# Run: Godot --headless --path /Users/abdul/Desktop/Personal/flowstate/flowstate --script res://scripts/tests/_ReplayProbe.gd

const N := 90
const WARMUP := 3

var _player: CharacterBody3D
var _player_vc
var _ghost: CharacterBody3D
var _ghost_vc
var _recorder
var _data
var _start := Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0))
var _player_end := Vector3.ZERO
var _ok := true
var _frame := 0
var _phase := 0          # 0 = recording, 1 = replaying, 2 = done


func _initialize() -> void:
	var world := Node3D.new(); root.add_child(world)
	# Floor on layer 1.
	var b := StaticBody3D.new(); b.position = Vector3(0, -0.5, 0); b.collision_layer = 1
	var s := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = Vector3(2000, 1, 2000); s.shape = bx
	b.add_child(s); world.add_child(b)

	_player = _mk_vehicle(world, "Player", 1 << 1)   # layer 2, collides with floor only
	_ghost = _mk_vehicle(world, "Ghost", 1 << 2)     # layer 4, collides with floor only
	_player_vc = _player.get_node("VehicleController")
	_ghost_vc = _ghost.get_node("VehicleController")
	_player.global_transform = _start
	_ghost.global_transform = _start

	_recorder = load("res://scripts/systems/ReplayRecorder.gd").new()
	_recorder.start_recording(_start, Vector3.ZERO)

	print("=== Replay Probe (N=%d frames) ===" % N)


func _mk_vehicle(world: Node3D, vname: String, layer: int) -> CharacterBody3D:
	var v := CharacterBody3D.new()
	v.set_script(load("res://scripts/vehicle/VehiclePhysics.gd"))
	v.name = vname
	v.collision_layer = layer
	v.collision_mask = 1                  # collide with the floor only, never the other car
	var col := CollisionShape3D.new(); var cap := CapsuleShape3D.new()
	cap.radius = 0.8; cap.height = 1.6; col.shape = cap
	v.add_child(col)
	_mk(v, "VehicleController", Node, "res://scripts/vehicle/VehicleController.gd")
	_mk(v, "GravitySystem", Node3D, "res://scripts/vehicle/GravitySystem.gd")
	_mk(v, "WallRiding", Node, "res://scripts/vehicle/WallRiding.gd")
	_mk(v, "FlowSystem", Node, "res://scripts/systems/FlowSystem.gd")
	_mk(v, "WallSensor", Node, "res://scripts/vehicle/WallSensor.gd")
	world.add_child(v)
	return v


# A scripted, deterministic input stream: accelerate, weave, jump once.
func _scripted_intent(i: int) -> MovementIntent:
	var intent := MovementIntent.new()
	intent.accelerate = 1.0
	intent.steer = sin(float(i) * 0.12) * 0.6
	intent.jump = (i == 20)
	return intent


func _physics_process(_dt: float) -> bool:
	# Never let either controller read live Input (headless): drive physics manually.
	_player_vc.set_physics_process(false)
	_ghost_vc.set_physics_process(false)

	_frame += 1
	if _frame <= WARMUP:
		return false

	var i := _frame - WARMUP - 1

	if _phase == 0:
		# --- Phase A: drive + record the player ---
		var intent := _scripted_intent(i)
		_recorder.record_frame(intent)
		_player.apply_intent(intent)
		if i == N - 1:
			_player_end = _player.global_transform.origin
			_data = _recorder.stop_recording()
			_phase = 1
		return false

	if _phase == 1:
		# --- Phase B: replay the recording on the identical ghost ---
		var j := i - N
		var frame = _data.get_frame(j)
		if frame != null:
			_ghost.apply_intent(frame.clone())
		if j == N - 1:
			_finish()
			return true

	return false


func _finish() -> void:
	var ghost_end := _ghost.global_transform.origin

	# A. Recorder round-trip
	_check(_data != null and _data.size() == N, "A: recorded %d frames (expected %d)" % [_data.size() if _data else -1, N])
	_check(_data.start_transform.origin.distance_to(_start.origin) < 0.001, "A: start transform stored")
	var f20 = _data.get_frame(20)
	_check(f20 != null and f20.jump == true, "A: frame 20 jump survived the clone")
	var f0 = _data.get_frame(0)
	_check(f0 != null and is_equal_approx(f0.accelerate, 1.0), "A: frame 0 accelerate survived the clone")

	# B. Determinism + actually moved
	var moved := _player_end.distance_to(_start.origin)
	var drift := ghost_end.distance_to(_player_end)
	_check(moved > 5.0, "B: player actually drove (moved %.2f from start)" % moved)
	_check(drift < 0.5, "B: ghost reproduced the run (end drift %.4f < 0.5)" % drift)

	print("  player_end=(%.2f,%.2f,%.2f)  ghost_end=(%.2f,%.2f,%.2f)" % [
		_player_end.x, _player_end.y, _player_end.z, ghost_end.x, ghost_end.y, ghost_end.z])
	if _ok:
		print("PASS")
	else:
		print("FAILED")
	print("=== done ===")


func _check(cond: bool, msg: String) -> void:
	print("  %s : %s" % ["ok " if cond else "FAIL", msg])
	if not cond:
		_ok = false


func _mk(parent: Node, n: String, base, path: String):
	var node = base.new(); node.set_script(load(path)); node.name = n
	parent.add_child(node); return node
