class_name PlaygroundBuilder
extends Node3D

# ============================================================================
#  PlaygroundBuilder — a big, free-roam test track for the whole moveset.
# ----------------------------------------------------------------------------
#  Spawn at the origin (forward = -Z). An effectively-infinite flat floor lets you
#  drive anywhere; sections are spread around the origin and colour-coded:
#
#    -Z (forward) ...... RAMP GARDEN: three ramps (small/med/big) for jumps + air tricks
#    far -Z ............ QUARTER-PIPE KICKER: curved lip for near-vertical big air
#    +X (right) ........ WALL-RIDE WALL: long tall wall — drive alongside, press Q to ride
#    +X back ........... WALL-HOP CORRIDOR: two parallel walls — Q to ride, Q to hop across
#    -X (left) ......... HALF-LOOP: floor->wall->ceiling curve -> inverted run (surface follow,
#                        gravity transfer); fall off and the infinite floor catches you
#    +Z (back) ......... PILLAR SLALOM: weave through pillars (drift + near-miss)
#
#  All geometry is StaticBody3D. Curved surfaces (kicker, loop) are single
#  backface-collidable ConcavePolygonShape3D ribbons (same technique as M2TransitionBuilder),
#  so the car follows them seamlessly with no internal box seams.
# ============================================================================

@export var floor_size: float = 4000.0   # effectively-infinite floor

const QP_SEGS := 20          # quarter-pipe facets (90/20 = 4.5deg — smooth, within follow limit)
const LOOP_R := 16.0         # half-loop radius -> ceiling at y = 2R = 32
const LOOP_Z0 := -16.0       # local z where floor meets the loop (entry)
const LOOP_CEIL_LEN := 44.0  # inverted ceiling run-out
const LOOP_SEGS := 40
const LOOP_CEIL_SEGS := 22

# --- Visual theming (014_Track_Visual_Baseline) — dark surfaces + emissive cyan
#     accents, matching Track_Circuit. All @export so the palette is tunable live.
@export_group("Palette")
@export var col_floor: Color = Color(0.08, 0.09, 0.14)
@export var col_ramp: Color = Color(0.15, 0.12, 0.10)
@export var col_kicker: Color = Color(0.16, 0.13, 0.09)
@export var col_wall: Color = Color(0.10, 0.15, 0.18)
@export var col_loop: Color = Color(0.15, 0.10, 0.19)
@export var col_pillar: Color = Color(0.16, 0.09, 0.15)
@export_group("Edge Lines")
@export var col_edge: Color = Color(0.0, 1.0, 0.8)
@export var edge_emission_energy: float = 2.0
@export var edge_width: float = 0.4
@export var edge_lift: float = 0.06

# Materials — assigned in _build_materials() (after exports are applied).
var _mat_floor: StandardMaterial3D
var _mat_ramp: StandardMaterial3D
var _mat_kicker: StandardMaterial3D
var _mat_wall: StandardMaterial3D
var _mat_loop: StandardMaterial3D
var _mat_pillar: StandardMaterial3D
var _mat_edge: StandardMaterial3D


func _ready() -> void:
	_build()


func _build() -> void:
	_build_materials()
	# Effectively-infinite floor, top at y=0.
	_box(Vector3(floor_size, 1.0, floor_size), Vector3(0, -0.5, 0), _mat_floor)

	_ramp_garden()
	_quarter_pipe_kicker()
	_wall_ride_wall()
	_wall_hop_corridor()
	_half_loop()
	_pillar_slalom()

	print("[Playground] built — ramps(-Z), kicker(far -Z), wall(+X), wall-hop(+X back), half-loop(-X), pillars(+Z)")


# --- Sections -------------------------------------------------------------

# Three ramps of increasing pitch along -Z (drive forward into them). Approach the low (+Z) edge;
# launch off the high (-Z) edge. y is set so the low edge sits ~on the floor.
func _ramp_garden() -> void:
	_ramp(Vector3(16, 1, 16), -30.0, deg_to_rad(12))
	_ramp(Vector3(16, 1, 18), -62.0, deg_to_rad(20))
	_ramp(Vector3(18, 1, 22), -98.0, deg_to_rad(28))


func _ramp(size: Vector3, z: float, pitch: float) -> void:
	# +pitch around X raises the -Z end; place y so the low (+Z) end's top is ~floor level.
	var y := (size.z * 0.5) * sin(pitch) - 0.4
	_box_rot(size, Vector3(0, y, z), Vector3(pitch, 0, 0), _mat_ramp)
	# Glowing lip across the high (-Z) launch edge — marks the take-off point.
	var rbasis := Basis.from_euler(Vector3(pitch, 0, 0))
	var lip_pos := Vector3(0, y, z) + rbasis * Vector3(0, size.y * 0.5 + edge_lift, -size.z * 0.5)
	_add_edge_box(Vector3(size.x, 0.1, edge_width), lip_pos, rbasis)


# Curved lip that flings you near-vertically for big air / multi-tricks. Approach from +Z (-Z drive).
func _quarter_pipe_kicker() -> void:
	_ribbon(_qp_frames(Vector3(0, 0, -135), 12.0, 1.0), 16.0, _mat_kicker)


# Long, tall wall on the right. Drive alongside it (~x=43) and press Q to wall-ride.
func _wall_ride_wall() -> void:
	_box(Vector3(2, 12, 70), Vector3(45, 6, 0), _mat_wall)
	_add_edge_box(Vector3(2.0, 0.12, 70.0), Vector3(45, 12.0 + edge_lift, 0), Basis.IDENTITY)


# Two parallel walls ~6m apart: ride one (Q), wall-jump (Q) across to the other, repeat.
func _wall_hop_corridor() -> void:
	_box(Vector3(2, 12, 50), Vector3(42, 6, 70), _mat_wall)
	_box(Vector3(2, 12, 50), Vector3(48, 6, 70), _mat_wall)
	_add_edge_box(Vector3(2.0, 0.12, 50.0), Vector3(42, 12.0 + edge_lift, 70), Basis.IDENTITY)
	_add_edge_box(Vector3(2.0, 0.12, 50.0), Vector3(48, 12.0 + edge_lift, 70), Basis.IDENTITY)


# Floor -> wall -> ceiling half-loop + inverted run-out, on the left (x=-55). Drive in fast from
# +Z; carry >= ~14 m/s tangential to hold the ceiling. Fall off -> the infinite floor catches you.
func _half_loop() -> void:
	var off := Vector3(-55, 0, 0)
	var frames: Array[Transform3D] = []
	var centre := off + Vector3(0, LOOP_R, LOOP_Z0)
	for i in range(LOOP_SEGS + 1):
		var ang := PI * float(i) / float(LOOP_SEGS)            # 0 floor -> PI/2 wall -> PI ceiling
		var origin := centre + Vector3(0, -cos(ang) * LOOP_R, -sin(ang) * LOOP_R)
		frames.append(Transform3D(Basis(Vector3.RIGHT, ang), origin))
	var ceil_y := 2.0 * LOOP_R
	for i in range(1, LOOP_CEIL_SEGS + 1):
		var z := LOOP_Z0 + LOOP_CEIL_LEN * float(i) / float(LOOP_CEIL_SEGS)
		frames.append(Transform3D(Basis(Vector3.RIGHT, PI), off + Vector3(0, ceil_y, z)))
	_ribbon(frames, 14.0, _mat_loop)
	_ribbon_edges(frames, 14.0)


# Pillars to weave through at speed (drift lines, near-misses). Behind spawn (+Z), left of the
# wall-hop corridor.
func _pillar_slalom() -> void:
	for pos: Vector3 in [
		Vector3(12, 2.5, 45), Vector3(-14, 2.5, 55), Vector3(6, 2.5, 70),
		Vector3(-18, 2.5, 82), Vector3(16, 2.5, 95), Vector3(-4, 2.5, 108),
		Vector3(-22, 2.5, 120), Vector3(10, 2.5, 122),
	]:
		_box(Vector3(4, 5, 4), pos, _mat_pillar)
		_add_edge_box(Vector3(4.0, 0.12, 4.0), pos + Vector3(0, 2.5 + edge_lift, 0), Basis.IDENTITY)


# --- Primitives -----------------------------------------------------------

# Quarter-pipe frames: 0 (floor) -> 90deg (vertical lip). curl=+1 curls toward -Z (approach -Z);
# curl=-1 curls toward +Z. origin = centre-line point, basis.x = lane-right.
func _qp_frames(offset: Vector3, radius: float, curl: float) -> Array[Transform3D]:
	var frames: Array[Transform3D] = []
	var centre := offset + Vector3(0, radius, 0)
	for i in range(QP_SEGS + 1):
		var ang := (PI * 0.5) * float(i) / float(QP_SEGS)
		var origin := centre + Vector3(0, -cos(ang) * radius, -curl * sin(ang) * radius)
		frames.append(Transform3D(Basis(Vector3.RIGHT, curl * ang), origin))
	return frames


# One continuous surface from a list of frames — single StaticBody + ConcavePolygonShape3D trimesh
# (backface-collidable), so curves have no internal seams. (Same as M2TransitionBuilder._ribbon.)
func _ribbon(frames: Array[Transform3D], width: float, mat: StandardMaterial3D) -> void:
	if frames.size() < 2:
		return
	var hw := width * 0.5
	var faces := PackedVector3Array()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(frames.size() - 1):
		var a := frames[i]
		var b := frames[i + 1]
		var a_l := a.origin - a.basis.x * hw
		var a_r := a.origin + a.basis.x * hw
		var b_l := b.origin - b.basis.x * hw
		var b_r := b.origin + b.basis.x * hw
		for tri in [[a_l, a_r, b_r], [a_l, b_r, b_l]]:
			for p: Vector3 in tri:
				st.add_vertex(p)
				faces.append(p)
	st.generate_normals()

	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	col.shape = shape
	body.add_child(col)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)


func _box(size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
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
	mi.material_override = mat
	sb.add_child(mi)
	add_child(sb)


func _box_rot(size: Vector3, pos: Vector3, rot: Vector3, mat: StandardMaterial3D) -> void:
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
	mi.material_override = mat
	sb.add_child(mi)
	add_child(sb)


func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # ribbons are single-surface; show both sides
	return mat


func _mat_emissive(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _build_materials() -> void:
	_mat_floor = _mat(col_floor)
	_mat_ramp = _mat(col_ramp)
	_mat_kicker = _mat(col_kicker)
	_mat_wall = _mat(col_wall)
	_mat_loop = _mat(col_loop)
	_mat_pillar = _mat(col_pillar)
	_mat_edge = _mat_emissive(col_edge, edge_emission_energy)


# --- Emissive accents (014) — visual only, no collision -------------------

# A thin glowing box (used for ramp launch lips, wall tops, pillar caps).
func _add_edge_box(size: Vector3, position: Vector3, basis: Basis) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat_edge
	mi.transform = Transform3D(basis.orthonormalized(), position)
	add_child(mi)


# Glowing strips down both lane edges of a ribbon surface (the half-loop).
func _ribbon_edges(frames: Array[Transform3D], width: float) -> void:
	if frames.size() < 2:
		return
	var hw := width * 0.5
	for side: float in [-1.0, 1.0]:
		var off := (hw - edge_width * 0.5) * side
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(frames.size() - 1):
			var a := frames[i]
			var b := frames[i + 1]
			var a_in := a.origin + a.basis.x * (off - edge_width * 0.5) + a.basis.y * edge_lift
			var a_out := a.origin + a.basis.x * (off + edge_width * 0.5) + a.basis.y * edge_lift
			var b_in := b.origin + b.basis.x * (off - edge_width * 0.5) + b.basis.y * edge_lift
			var b_out := b.origin + b.basis.x * (off + edge_width * 0.5) + b.basis.y * edge_lift
			for tri in [[a_in, a_out, b_out], [a_in, b_out, b_in]]:
				for p: Vector3 in tri:
					st.add_vertex(p)
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _mat_edge
		add_child(mi)
