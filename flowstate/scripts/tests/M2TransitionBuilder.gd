extends Node3D

# ============================================================================
#  M2TransitionBuilder — the M2 verification surface
# ----------------------------------------------------------------------------
#  Builds a SMOOTH, seam-free floor -> wall -> ceiling half-loop (180 deg) so the
#  car can drive the floor, curve up through a vertical wall, and continue onto an
#  inverted ceiling run — the M2 gate (floor->wall->ceiling achievable + smooth,
#  camera readable throughout).
#
#  How it satisfies the physics (005 Phase 1 continuous surface-following):
#    * The transition is a CURVE, not a sharp corner. Following sustains only across
#      gradual normal rotation (<= max_follow_rotation_deg ~20 deg/frame); a smooth
#      circular arc rotates ~3 deg/frame at speed, so the car follows floor->wall->
#      ceiling automatically (no button wall-attach). Sharp 90 deg corners are the
#      DEFERRED Phase-2 case and are intentionally NOT used here.
#    * The whole curve is ONE ConcavePolygonShape3D ribbon (backface-collidable), so
#      there are no internal box seams for the capsule to catch on.
#    * The half-loop curls in -Z (the loop probe's parametrization), so the apex sits
#      over fresh ground and never overhangs the approach (the full-loop +sin curl is
#      the documented entry-overhang bug).
#
#  Carry enough speed in: the ceiling (fully inverted) needs tangential speed >=
#  GravitySystem.max_hold_speed (~14) to hold. Floor it on the run-up; feather to peel
#  off near the top and fall back to the recovery floor (failure costs momentum, not
#  progress) — itself a demonstration of the momentum pillar.
# ============================================================================

const LANE_W := 14.0
const R := 16.0             # half-loop radius -> ceiling at y = 2R = 32
const Z0 := -16.0           # z where the flat floor meets the half-loop (loop entry, bottom)
const APPROACH_NEAR := 24.0 # flat floor runs from here down to Z0
const CEILING_LEN := 44.0   # inverted run-out along the ceiling (in +Z)
const HALF_LOOP_SEGS := 40  # 180/40 = 4.5 deg facets — smooth + well within the follow limit
const CEILING_SEGS := 22

var _mat_floor := _mat(Color(0.16, 0.20, 0.28))
var _mat_loop := _mat(Color(0.45, 0.30, 0.55))
var _mat_ceiling := _mat(Color(0.28, 0.26, 0.42))
var _mat_safety := _mat(Color(0.10, 0.16, 0.24))

func _ready() -> void:
	_build()

func _build() -> void:
	# Recovery floor — fall off anywhere and land here, drive back on. Made long in +Z so the
	# launch off the END of the inverted ceiling (car exits moving +Z and arcs down ~z+110) lands
	# on it rather than into the void.
	_add_box(Vector3(170, 1, 380), Vector3(0, -0.65, 40.0), _mat_safety)

	# 1) Flat approach floor (thick box), surface at y=0, z = APPROACH_NEAR .. Z0.
	var approach_len := APPROACH_NEAR - Z0
	_add_box(Vector3(LANE_W, 1.0, approach_len), Vector3(0, -0.5, (APPROACH_NEAR + Z0) * 0.5), _mat_floor)

	# 2) ONE seamless ribbon: half-loop (floor->wall->ceiling) + flat ceiling run-out.
	var frames: Array[Transform3D] = []
	var centre := Vector3(0, R, Z0)                       # circle centre, directly above the entry
	for i in range(HALF_LOOP_SEGS + 1):
		var ang := PI * float(i) / float(HALF_LOOP_SEGS)  # 0 = floor, PI/2 = wall, PI = ceiling
		var origin := centre + Vector3(0, -cos(ang) * R, -sin(ang) * R)  # -sin => curl forward (-Z)
		frames.append(Transform3D(Basis(Vector3.RIGHT, ang), origin))
	# Flat inverted ceiling continuing +Z at y = 2R (the car exits the loop top moving +Z).
	var ceil_y := 2.0 * R
	for i in range(1, CEILING_SEGS + 1):
		var z := Z0 + CEILING_LEN * float(i) / float(CEILING_SEGS)
		frames.append(Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, ceil_y, z)))
	_ribbon(frames, LANE_W, _mat_loop)

	print("[M2] floor z%.0f..%.0f  ->  half-loop R%.0f (apex z%.0f, ceiling y=%.0f)  ->  ceiling +Z to z%.0f" % [
		APPROACH_NEAR, Z0, R, Z0 - R, ceil_y, Z0 + CEILING_LEN])


# --- primitives (same approach as TrackBuilder; kept local so this test is self-contained) ---

# One continuous surface from a list of frames (origin = centre-line point, basis.x = lane-right).
# Single StaticBody + ConcavePolygonShape3D trimesh — no per-segment boxes, so no internal seams.
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
	if mat != null:
		mi.material_override = mat
	body.add_child(mi)
	add_child(body)


func _add_box(size: Vector3, position: Vector3, mat: StandardMaterial3D) -> void:
	var body := StaticBody3D.new()
	body.position = position
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	if mat != null:
		mi.material_override = mat
	body.add_child(mi)
	add_child(body)


func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # ribbons are single-surface; show both sides
	return mat
