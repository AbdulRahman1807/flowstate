class_name DriftPlaygroundBuilder
extends Node3D

# Procedural drift playground — call _build() from _ready() or a parent scene.
# Produces a 96x96 arena with perimeter walls, scattered pillars, and two ramps.
# All geometry is StaticBody3D children of this node.

@export var arena_half: float = 48.0
@export var wall_height: float = 8.0
@export var pillar_size: Vector3 = Vector3(4, 5, 4)

func _ready() -> void:
	_build()

func _build() -> void:
	# Main floor
	_box(Vector3(arena_half * 2, 1.0, arena_half * 2), Vector3(0, -0.5, 0))

	# Recovery floor — catches falls off the arena
	_box(Vector3(arena_half * 2 + 60, 1.0, arena_half * 2 + 60), Vector3(0, -18.0, 0))

	# Perimeter walls — tall enough for wall riding (use Q next to them)
	var aw := arena_half + 0.5
	_box(Vector3(arena_half * 2 + 2, wall_height, 2.0), Vector3(0, wall_height * 0.5, aw))   # North
	_box(Vector3(arena_half * 2 + 2, wall_height, 2.0), Vector3(0, wall_height * 0.5, -aw))  # South
	_box(Vector3(2.0, wall_height, arena_half * 2 + 2), Vector3(aw, wall_height * 0.5, 0))   # East
	_box(Vector3(2.0, wall_height, arena_half * 2 + 2), Vector3(-aw, wall_height * 0.5, 0))  # West

	# Interior pillars — weave through these while drifting
	for pos: Vector3 in [
		Vector3(22,  2.5,  12),
		Vector3(-22, 2.5,  12),
		Vector3(0,   2.5, -22),
		Vector3(32,  2.5, -8),
		Vector3(-32, 2.5, -8),
		Vector3(0,   2.5,  32),
		Vector3(14,  2.5, -36),
		Vector3(-14, 2.5, -36),
	]:
		_box(pillar_size, pos)

	# Two short diagonal walls — force direction changes
	_box_rot(Vector3(2.0, 5.0, 18.0), Vector3(20, 2.5, -14), Vector3(0, deg_to_rad(35), 0))
	_box_rot(Vector3(2.0, 5.0, 18.0), Vector3(-20, 2.5, -14), Vector3(0, deg_to_rad(-35), 0))

	# Ramp pair — gently tilted (10°) so fast entries get a bit of air
	_box_rot(Vector3(12.0, 0.8, 18.0), Vector3(-14, 0.8, 22), Vector3(deg_to_rad(10), 0, 0))
	_box_rot(Vector3(12.0, 0.8, 18.0), Vector3(14, 0.8, 22), Vector3(deg_to_rad(10), 0, 0))


func _box(size: Vector3, pos: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	sb.add_child(col)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	sb.add_child(mi)
	add_child(sb)


func _box_rot(size: Vector3, pos: Vector3, rot: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.position = pos
	sb.rotation = rot
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	sb.add_child(col)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	sb.add_child(mi)
	add_child(sb)
