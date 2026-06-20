extends Node3D

# ============================================================================
#  TrackBuilder — procedural stunt test track for FLOWSTATE
# ----------------------------------------------------------------------------
#  Builds one continuous, smooth, drivable course made of densely-tessellated
#  StaticBody3D segments. Every surface gets a BoxShape3D collider so the
#  vehicle's downward raycasts (ray_length 1.5) and move_and_slide() always
#  have something to stand on.
#
#  Physics envelope this geometry is sized to (see VehiclePhysics / GravitySystem):
#    * Vehicle spawns ~ (0, 2, 15) and drives toward -Z. The track therefore
#      starts under the spawn (z = +16) and runs out to large -Z.
#    * Custom gravity = 18 m/s^2, max_speed = 50, jump_force = 12.
#        A ~12 deg launch ramp at 50 m/s flies ~55 m (level launch-to-land),
#        ~5x the old 22 m/s envelope, so the section-3 ground jumps use ~28-30 u
#        gaps and long (44 u) pads to absorb the 40-50 m/s landing spread.
#        Wall jump-offs are capped to wall_ride_speed_cap (22), so the wall
#        sections stay bounded regardless of ground top speed.
#      -> every miss falls onto the flush recovery floor (y~0) and drives back on.
#    * Floor auto-detect requires surface normal within ~56 deg of world-up
#      (normal . UP > 0.55). All driving ramps/banks are kept <= ~30 deg.
#    * Wall riding needs a VERTICAL face within 3.0 u of the car. The lane is
#      14 u wide and the car drives down its centre, so ride-walls sit with
#      their inner face ~2.5 u from the centre line (inside the 3.0 u reach).
#
#  Layout is sequential along -Z; each section prints its own Z range below so
#  the developer knows where to drive to test each scenario.
# ============================================================================

const LANE_W := 14.0          # standard drivable lane width
const DECK_T := 1.0           # standard deck thickness
const SEG_LEN := 4.0          # tessellation length for curved/looped bands

# Reusable materials (kept as members so every segment of a section shares one).
var _mat_deck := _make_mat(Color(0.18, 0.20, 0.26))      # neutral road
var _mat_accent := _make_mat(Color(0.20, 0.45, 0.65))    # banks / special decks
var _mat_ramp := _make_mat(Color(0.65, 0.45, 0.18))      # launch ramps
var _mat_pad := _make_mat(Color(0.20, 0.55, 0.30))       # landing pads
var _mat_wall := _make_mat(Color(0.45, 0.22, 0.30))      # ride / canyon walls
var _mat_ceiling := _make_mat(Color(0.30, 0.25, 0.45))   # overhead surfaces
var _mat_loop := _make_mat(Color(0.55, 0.25, 0.55))      # loop ribbon
var _mat_floor := _make_mat(Color(0.10, 0.18, 0.28))     # safety floor


func _ready() -> void:
	_build_track()


func _build_track() -> void:
	# ── Flush recovery floor ─────────────────────────────────────────────
	# Top sits at y = -0.15 — just under the base driving level (y = 0) — so the
	# whole course is effectively at ground level. Drift off any base section and
	# you are on this floor at the same height: just drive back on. Every stunt
	# (ramps, walls, platforms, loop) rises FROM this floor, so missing one drops
	# you onto it, never into an unrecoverable pit. Wide + long enough to cover
	# the entire course and its sideways sweeps.
	_add_box(Vector3(420, 1, 3200), Vector3(0, -0.65, -1500), Vector3.ZERO, _mat_floor)

	var z := 16.0

	# ── SECTION 1: Launch / acceleration straight (y=0) ──  z +16 .. -120
	# Long flat run so the car reaches max_speed (22) before anything happens.
	_straight(Vector3(0, 0, z), 136.0, LANE_W, _mat_deck)
	z -= 136.0
	_add_start_line(5.0)                                                 # START gate just ahead of spawn (z=10)

	# ── SECTION 2: Smooth banked S-curve (y=0) ──  z -120 .. -260
	# Two flat-plan arcs banking <= 22 deg into the turn. Built from short tangent
	# segments so the road reads as one smooth ribbon.
	var e := _banked_arc(Vector3(0, 0, z), 70.0, 22.0, -1, 20.0)         # bank left
	e = _banked_arc(e, 70.0, 22.0, +1, 20.0)                             # bank right
	z = e.z
	_add_checkpoint(z, 0)                                                # CP0 — before the gap jumps

	# ── SECTION 3: Gap jumps — rise, jump, then RETURN to base ───────────
	# Re-sized for max_speed=50: a ~12 deg ramp at 50 m/s flies ~55 m, so gaps are
	# ~28-30 u and pads are long (44 u) to absorb the 40-50 m/s landing spread. A
	# miss drops only a few u onto the flush recovery floor (drive back on).
	_straight(Vector3(0, 0, z), 28.0, LANE_W, _mat_deck); z -= 28.0      # run-up (already ~50 from S1)
	_ramp(Vector3(0, 0, z), 16.0, LANE_W, 3.5, _mat_ramp); z -= 16.0     # launch ramp to y=3.5 (~12.3 deg)
	z -= 28.0                                                            # gap (lands deep on the long pad at 50)
	_straight(Vector3(0, 3.5, z), 44.0, LANE_W, _mat_pad); z -= 44.0     # pad #1 (long catch)
	_ramp(Vector3(0, 3.5, z), 14.0, LANE_W, 3.0, _mat_ramp); z -= 14.0   # launch ramp to y=6.5
	z -= 30.0                                                            # bigger gap
	_straight(Vector3(0, 6.5, z), 44.0, LANE_W, _mat_pad); z -= 44.0     # pad #2 (long catch)
	_ramp(Vector3(0, 6.5, z), 48.0, LANE_W, -6.5, _mat_ramp); z -= 48.0  # descend back to y=0 (~7.7 deg)

	# ── SECTION 4: Wall-ride straight — wall on LEFT (y=0) ───────────────
	# Long deck, tall wall flush at the left edge (inner face x=-2.5, inside the
	# 3.0 u attach reach). Drive fast, press Q to ride it.
	z -= 6.0
	_straight(Vector3(0, 0, z), 70.0, LANE_W, _mat_deck)
	_add_box(Vector3(1, 18, 70), Vector3(-3.0, 9.0, z - 35.0), Vector3.ZERO, _mat_wall)
	z -= 70.0

	# ── SECTION 5: Wall-ride straight — wall on RIGHT (variety, y=0) ─────
	z -= 6.0
	_straight(Vector3(0, 0, z), 60.0, LANE_W, _mat_deck)
	_add_box(Vector3(1, 18, 60), Vector3(+3.0, 9.0, z - 30.0), Vector3.ZERO, _mat_wall)
	z -= 60.0
	_add_checkpoint(z, 1)                                                # CP1 — before the vertical wall climb

	# ── SECTION 6: VERTICAL wall ride -> TOP PLATFORM (y=0 -> y=18) ──────
	# Drive in fast, attach to the tall left wall and ride UP it; gravity pins
	# you to the face while the climb redirect carries you up-and-forward. At the
	# wall top you auto-detach (edge_exit, velocity preserved) and arc onto a big
	# top platform. A long descent ramp returns to base. Generous platform so the
	# landing is forgiving.
	_straight(Vector3(0, 0, z), 24.0, LANE_W, _mat_deck); z -= 24.0      # approach
	var climb_z := z
	_straight(Vector3(0, 0, climb_z), 46.0, LANE_W, _mat_deck)          # base under climb wall
	_add_box(Vector3(1, 18, 46), Vector3(-3.0, 9.0, climb_z - 23.0), Vector3.ZERO, _mat_wall)   # climb wall y0..18
	# Top platform at wall-top height (top y=18). Near edge is set BACK to climb_z-22
	# (past where the car crests) so it never overhangs the climb; the car launches off
	# the top and arcs back down onto it. Verified by _WallClimbProbe.
	_add_box(Vector3(18, 1, 50), Vector3(-1.0, 17.5, climb_z - 47.0), Vector3.ZERO, _mat_pad)
	_ramp(Vector3(-1.0, 18.0, climb_z - 72.0), 32.0, LANE_W, -18.0, _mat_ramp)                  # platform -> base (~29 deg)
	z = climb_z - 72.0 - 32.0

	# ── SECTION 7: Wall-to-wall (wall-jump corridor, y=0) ───────────────
	# Two parallel walls. Attach to one, wall-jump (Q, speed >= 8) across to the
	# other. Walls are tall so you catch the far wall at whatever height you reach.
	z -= 6.0
	var corr_z := z
	_straight(Vector3(0, 0, z), 80.0, LANE_W, _mat_deck)
	_add_box(Vector3(1, 24, 80), Vector3(-5.0, 12.0, corr_z - 40.0), Vector3.ZERO, _mat_wall)   # left, inner -4.5
	_add_box(Vector3(1, 24, 80), Vector3(+5.0, 12.0, corr_z - 40.0), Vector3.ZERO, _mat_wall)   # right, inner +4.5
	z -= 80.0
	_add_checkpoint(z, 2)                                                # CP2 — before the wall-jump-across-gap

	# ── SECTION 8: Wall ride -> wall-jump across a GAP to a platform ─────
	# Ride the left wall, then wall-jump (Q) off it across an open gap onto the
	# catch pad. Miss = drop to the flush floor and retry.
	z -= 6.0
	_straight(Vector3(0, 0, z), 40.0, LANE_W, _mat_deck)
	_add_box(Vector3(1, 16, 40), Vector3(-3.0, 8.0, z - 20.0), Vector3.ZERO, _mat_wall)
	z -= 40.0
	z -= 12.0                                                            # gap to clear with a wall-jump (capped ~20 m/s)
	_straight(Vector3(0, 0, z), 44.0, LANE_W, _mat_pad)                 # catch pad (extended; a fast no-wall overshoot still lands)
	z -= 44.0

	# ── SECTION 9: Ceiling test (y=0) ──  (needs pending gravity work)
	# Floor + parallel ceiling 16 u overhead joined by a left wall (square tube).
	z -= 6.0
	var ceil_z := z
	_straight(Vector3(0, 0, z), 60.0, LANE_W, _mat_deck)
	_add_box(Vector3(LANE_W, 1, 60), Vector3(0, 16.0, ceil_z - 30.0), Vector3.ZERO, _mat_ceiling)
	_add_box(Vector3(1, 16, 60), Vector3(-7.0, 8.0, ceil_z - 30.0), Vector3.ZERO, _mat_wall)
	z -= 60.0
	_add_checkpoint(z, 3)                                                # CP3 — before the loop

	# ── SECTION 10: Smooth vertical LOOP (y=0) ──  (needs pending gravity work)
	z -= 6.0
	_straight(Vector3(0, 0, z), 24.0, LANE_W, _mat_deck); z -= 24.0      # loop run-in
	var loop_entry_z := z - 2.0
	_vertical_loop(Vector3(0, 0, loop_entry_z), 14.0, 60)
	_straight(Vector3(0, 0, loop_entry_z - 4.0), 24.0, LANE_W, _mat_deck)  # loop run-out
	z = loop_entry_z - 28.0

	# ── SECTION 11: Quarter-pipe + corkscrew (y=0) ──  (needs pending gravity work)
	_straight(Vector3(0, 0, z), 20.0, LANE_W, _mat_deck); z -= 20.0      # approach
	_quarter_pipe(Vector3(0, 0, z), 12.0, LANE_W, 18); z -= 14.0         # concave kicker
	_straight(Vector3(0, 0, z), 16.0, LANE_W, _mat_deck); z -= 16.0      # settle
	_corkscrew(Vector3(0, 0, z), 8.0, 60.0, 180.0, 48); z -= 60.0        # half-twist tube
	_add_checkpoint(z, 4)                                                # CP4 — before the finish plaza

	# ── SECTION 12: Large flat finish plaza (y=0) ───────────────────────
	_straight(Vector3(0, 0, z), 60.0, 60.0, _mat_pad)                    # 60 u wide
	_add_box(Vector3(60, 6, 1), Vector3(0, 3.0, z - 60.0), Vector3.ZERO, _mat_accent)  # finish wall
	_add_finish_line(z - 2.0, 60.0)                                     # FINISH gate at the plaza entrance


# ============================================================================
#  Section helpers
# ============================================================================

# Flat deck running along -Z. start = top-near corner reference (deck TOP is at
# start.y; the box is sunk so its surface sits exactly at start.y). Returns the
# end-point on the deck surface (x, y, z_far) for chaining.
func _straight(start: Vector3, length: float, width: float, mat: StandardMaterial3D) -> Vector3:
	var centre := Vector3(start.x, start.y - DECK_T * 0.5, start.z - length * 0.5)
	_add_box(Vector3(width, DECK_T, length), centre, Vector3.ZERO, mat)
	return Vector3(start.x, start.y, start.z - length)


# Straight ramp rising by `rise` over `length` (constant slope). Surface starts
# at start.y and ends at start.y + rise. Tilt = atan(rise/length) — keep small.
# Returns the surface end-point (raised).
func _ramp(start: Vector3, length: float, width: float, rise: float, mat: StandardMaterial3D) -> Vector3:
	var slope := atan2(rise, length)                       # radians, about X
	var run := Vector3(0, rise * 0.5, -length * 0.5)        # midpoint offset along the ramp
	var centre := Vector3(start.x, start.y, start.z) + run
	centre.y -= cos(slope) * DECK_T * 0.5                   # sink the deck under its surface
	_add_box(Vector3(width, DECK_T, sqrt(length * length + rise * rise)),
			centre, Vector3(rad_to_deg(slope), 0, 0), mat)
	return Vector3(start.x, start.y + rise, start.z - length)


# Banked, curving arc in the X-Z plane. The plan-view path turns by `total_deg`
# total; `dir` = -1 turns toward -X (left), +1 toward +X (right). Each tangent
# segment's deck is rolled by `bank_deg` (about its local forward axis) so the
# road leans into the turn. Built from short segments for a smooth ribbon.
# Returns the surface end-point on the deck.
func _banked_arc(start: Vector3, length: float, bank_deg: float, dir: int, total_deg: float) -> Vector3:
	var seg_count := int(ceil(length / SEG_LEN))
	var seg_len := length / seg_count
	var step_deg := (total_deg / seg_count) * dir
	var heading := 0.0                                     # 0 = facing -Z
	var pos := Vector3(start.x, start.y, start.z)
	var frames: Array[Transform3D] = []
	for i in range(seg_count + 1):
		var fwd := Vector3(sin(deg_to_rad(heading)) * dir * -1.0, 0, -cos(deg_to_rad(heading))).normalized()
		# yaw to follow the path, then roll to bank into the turn
		var basis := Basis(Vector3.UP, deg_to_rad(heading * dir * -1.0))
		basis = basis.rotated(fwd, deg_to_rad(-bank_deg * dir))
		frames.append(Transform3D(basis, pos))
		if i < seg_count:
			pos += fwd * seg_len
			heading += step_deg
	_ribbon(frames, LANE_W, _mat_accent)
	return Vector3(pos.x, start.y, pos.z)


# Smooth vertical loop in the Y-Z plane. A continuous ribbon of `segments` short
# flat bands placed around a circle of `radius`, each rotated tangent to the
# circle so the band's surface always faces the loop interior. The loop's bottom
# sits on the run deck (centre.y = base.y + radius). The drive enters from +Z.
func _vertical_loop(base: Vector3, radius: float, segments: int) -> void:
	var centre := Vector3(base.x, base.y + radius, base.z)
	var frames: Array[Transform3D] = []
	for i in range(segments + 1):                          # +1 closes the ring flush
		var ang := TAU * float(i) / float(segments)        # 0 at bottom, sweeps up the +Z face
		var offset := Vector3(0, -cos(ang) * radius, sin(ang) * radius)
		var basis := Basis(Vector3.RIGHT, ang)             # tangent rotation wraps the tube interior
		frames.append(Transform3D(basis, centre + offset))
	_ribbon(frames, LANE_W, _mat_loop)


# Concave quarter-pipe: a smooth ramp that curves from a flat deck up to a near-
# vertical wall over a 90 deg sweep, built from short tangent bands. `radius` is
# the pipe radius; the band surfaces face up-and-inward so a fast car can ride up
# the transition. Drive enters from +Z at base.y. (Geometry only — the upper end
# exceeds the floor-detect angle by design, like a real quarter-pipe lip.)
func _quarter_pipe(base: Vector3, radius: float, width: float, segments: int) -> void:
	# Circle centre is up and forward of the entry so the arc starts flat.
	var centre := Vector3(base.x, base.y + radius, base.z)
	var frames: Array[Transform3D] = []
	for i in range(segments + 1):
		var ang := (PI * 0.5) * float(i) / float(segments)   # 0 = flat bottom .. PI/2 = vertical
		var offset := Vector3(0, -cos(ang) * radius, -sin(ang) * radius)
		var basis := Basis(Vector3.RIGHT, -ang)              # tilt forward into the curve
		frames.append(Transform3D(basis, centre + offset))
	_ribbon(frames, width, _mat_accent)


# Corkscrew: a flat lane that spirals about the -Z travel axis, twisting by
# `twist_deg` total over `length`. Built from short bands each rolled a little
# more than the last so the surface reads as one continuous helical ribbon.
# (Geometry only; sustained corkscrew driving depends on pending gravity work.)
func _corkscrew(base: Vector3, _radius: float, length: float, twist_deg: float, segments: int) -> void:
	var frames: Array[Transform3D] = []
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var roll := deg_to_rad(twist_deg * t)
		var seg_z := base.z - length * t
		var basis := Basis(Vector3.FORWARD, roll)            # roll about the travel axis
		frames.append(Transform3D(basis, Vector3(base.x, base.y, seg_z)))
	_ribbon(frames, LANE_W, _mat_loop)


# ============================================================================
#  Primitives
# ============================================================================

# Axis-aligned / euler-rotated box with collision + mesh. Kept compatible with
# the original helper's signature (size, position, rotation_degrees, [material]).
func _add_box(size: Vector3, position: Vector3, rotation_degrees: Vector3, mat: StandardMaterial3D = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	body.rotation_degrees = rotation_degrees
	_attach_box_visuals(body, size, mat)
	add_child(body)
	return body


# Box placed with an explicit Basis (for arbitrary tangent orientations the
# euler form can't express cleanly). Position is the body origin = box centre.
func _add_box_basis(size: Vector3, position: Vector3, basis: Basis, mat: StandardMaterial3D = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.transform = Transform3D(basis.orthonormalized(), position)
	_attach_box_visuals(body, size, mat)
	add_child(body)
	return body


# Adds the collider + mesh (+ optional material) for a box body.
func _attach_box_visuals(body: StaticBody3D, size: Vector3, mat: StandardMaterial3D) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)

	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh
	if mat != null:
		mesh_instance.material_override = mat
	body.add_child(mesh_instance)


# Builds ONE continuous surface from a list of frames (Transform3D: origin = centre-line
# point, basis.x = lane-right). Adjacent frames are joined into a quad strip, so the whole
# curved section is a single StaticBody with a single ConcavePolygonShape3D (trimesh) — no
# per-segment boxes, therefore no internal edges/seams for the car to catch on. This is the
# fix for the "smooth sections are made of rectangles" snagging.
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
	shape.backface_collision = true                # collidable from either side (loop interior etc.)
	col.shape = shape
	body.add_child(col)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	if mat != null:
		mi.material_override = mat
	body.add_child(mi)
	add_child(body)


func _make_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # ribbons are single-surface; show both sides
	return mat


# ============================================================================
#  Run markers (M4 — 007_Run_Lifecycle.md)
# ----------------------------------------------------------------------------
#  Start / finish / checkpoint Area3D triggers, built procedurally WITH the
#  track so their positions track the geometry. RunManager finds them by group
#  and connects to body_entered. Each is a translucent emissive gate so the
#  driver can see it without it obscuring the track (04 readability rule).
# ============================================================================

const START_GROUP := "start_line"
const FINISH_GROUP := "finish_line"
const CHECKPOINT_GROUP := "checkpoints"

var _mat_start := _make_trigger_mat(Color(0.20, 1.00, 0.40))      # green
var _mat_finish := _make_trigger_mat(Color(1.00, 0.85, 0.10))     # gold
var _mat_checkpoint := _make_trigger_mat(Color(0.00, 1.00, 0.80)) # cyan


func _add_start_line(z: float) -> void:
	_add_trigger(Vector3(LANE_W, 8.0, 1.0), Vector3(0, 3.0, z), START_GROUP, -1, _mat_start)


func _add_finish_line(z: float, width: float) -> void:
	_add_trigger(Vector3(width, 8.0, 1.0), Vector3(0, 3.0, z), FINISH_GROUP, -1, _mat_finish)


func _add_checkpoint(z: float, index: int) -> void:
	_add_trigger(Vector3(LANE_W, 8.0, 1.0), Vector3(0, 3.0, z), CHECKPOINT_GROUP, index, _mat_checkpoint)


func _add_trigger(size: Vector3, position: Vector3, group: String, index: int, mat: StandardMaterial3D) -> Area3D:
	var area := Area3D.new()
	area.position = position
	area.collision_layer = 0      # the trigger only senses; nothing needs to detect it
	area.collision_mask = 1       # detect the vehicle (collision_layer 1)
	area.monitoring = true
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	area.add_child(col)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	area.add_child(mi)
	area.add_to_group(group)
	if index >= 0:
		area.set_meta("checkpoint_index", index)
	add_child(area)
	return area


func _make_trigger_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.22)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
