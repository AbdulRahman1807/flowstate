extends Node3D

# ============================================================================
#  CircuitBuilder — a long, PROPER directional track for FLOWSTATE
# ----------------------------------------------------------------------------
#  A clear point-to-point course: START gate -> one channelled racing line ->
#  FINISH gate. Direction is never ambiguous because the whole lane is lined with
#  CONTINUOUS SIDE BARRIERS plus forward arrow chevrons — you follow the corridor.
#
#  Built with a moving "cursor" (Transform3D: travel = -basis.z, right = basis.x,
#  up = basis.y) advanced piece by piece, so straights, arcs, ramps, LOOPS, and
#  wall sections chain seamlessly at any heading. The recovery floor is sized to
#  the course bounds AFTER layout, so however far the line wanders it's covered.
#
#  Showcases the whole moveset across MANY sections: speed straights, sweeping
#  turns, launch humps (air tricks), drift chicanes, vertical LOOPS, wall-ride
#  walls, wall-to-wall HOP corridors, and wall-jump-across-GAP sections.
# ============================================================================

const LANE_W := 12.0
const DECK_T := 1.0
const BARRIER_T := 0.6
const BARRIER_H := 2.5
const SEG_LEN := 4.0

# --- Visual theming (014_Track_Visual_Baseline / 04_Art_Direction: dark world,
#     glowing cyan edge lines). Every colour is @export so the whole palette is
#     tunable live in the inspector. Defaults are dark + high-contrast — no muddy
#     mid-tones — with subtle hue separation so section TYPES stay distinguishable.
@export_group("Track Palette")
@export var col_deck: Color = Color(0.10, 0.10, 0.18)      ## track surface — dark, cool
@export var col_accent: Color = Color(0.10, 0.13, 0.22)    ## arcs / sweeping turns — slightly bluer
@export var col_ramp: Color = Color(0.15, 0.12, 0.10)      ## ramps / humps — slightly warm
@export var col_pad: Color = Color(0.09, 0.16, 0.16)       ## landing pads — slight teal (reads "safe")
@export var col_wall: Color = Color(0.22, 0.12, 0.30)      ## walls / barriers — saturated purple, clearly distinct from deck
@export var col_loop: Color = Color(0.16, 0.10, 0.21)      ## loops — distinct purple
@export var col_recovery: Color = Color(0.05, 0.05, 0.09)  ## recovery floor — darkest, recedes
@export_group("Edge Lines")
@export var col_edge: Color = Color(0.0, 1.0, 0.8)         ## emissive FLOOR edge-line colour (04 cyan)
@export var edge_emission_energy: float = 2.0              ## edge-line glow intensity
@export var edge_width: float = 0.4                        ## width of the glowing strip
@export var edge_margin: float = 0.35                      ## inset from the lane edge
@export var edge_lift: float = 0.06                        ## lift above the deck (avoids z-fighting)
@export var col_wall_edge: Color = Color(0.9, 0.05, 0.78)  ## emissive WALL-top colour — true magenta (high blue) so it doesn't read red
@export var wall_edge_emission_energy: float = 1.4         ## wall-top glow intensity
@export_group("Loop Clearance")
@export var loop_front_cut: float = 2.2   ## cut loop FRONT slabs below this height — the jump-in entry gap (unchanged)
@export var loop_back_cut: float = 4.5    ## cut loop BACK slabs below this — clears the descending-back off the approach lane (anti-scrape)
@export_group("Arrows")
@export var col_arrow: Color = Color(0.0, 1.0, 0.8)        ## forward chevron colour
@export var arrow_emission_energy: float = 1.4

# Surface materials — assigned in _build_materials() (called from _build, AFTER the
# @export palette is applied by the scene/inspector). Field initialisers can't read
# exports, so these stay declared-only here.
var _mat_deck: StandardMaterial3D
var _mat_accent: StandardMaterial3D
var _mat_ramp: StandardMaterial3D
var _mat_pad: StandardMaterial3D
var _mat_wall: StandardMaterial3D
var _mat_loop: StandardMaterial3D
var _mat_floor: StandardMaterial3D
var _mat_arrow: StandardMaterial3D
var _mat_edge: StandardMaterial3D
var _mat_wall_edge: StandardMaterial3D

# Course bounds (XZ), tracked through the build so the recovery floor can cover it.
var _min_x := 1e9
var _max_x := -1e9
var _min_z := 1e9
var _max_z := -1e9


func _ready() -> void:
	_build()


func _build() -> void:
	_build_materials()
	var cur := Transform3D(Basis.IDENTITY, Vector3(0, 0, 22))
	_bound(cur.origin)

	cur = _straight(cur, 12.0, _mat_deck)              # lead-in deck under the spawn (vehicle at z=16)
	_add_start_line(cur)

	# 1. Long acceleration straight.
	cur = _straight(cur, 110.0, _mat_deck, true)
	cur = _checkpoint(cur, 0)

	# 2. Sweeping LEFT turn -> launch hump.
	cur = _arc(cur, 34.0, 80.0, -1, _mat_accent)
	cur = _straight(cur, 26.0, _mat_deck, true)
	cur = _hump(cur, 4.0)
	cur = _checkpoint(cur, 1)

	# 3. Sweeping RIGHT turn -> LOOP #1 (real 360 loop-de-loop, drive straight in).
	cur = _arc(cur, 30.0, 80.0, 1, _mat_accent)
	cur = _straight(cur, 34.0, _mat_deck, true)
	cur = _real_loop(cur, 13.0, 56)
	cur = _straight(cur, 24.0, _mat_deck, true)
	cur = _checkpoint(cur, 2)

	# 4. Drift chicane.
	cur = _arc(cur, 28.0, 60.0, -1, _mat_accent)
	cur = _drift_chicane(cur)
	cur = _checkpoint(cur, 3)

	# 5. Wall-ride straight (optional Q ride; lane still drivable through).
	cur = _straight(cur, 80.0, _mat_deck, true)
	_ride_wall(cur, 80.0)

	# 6. Turn -> wall-to-wall HOP corridor.
	cur = _arc(cur, 32.0, 85.0, 1, _mat_accent)
	cur = _wall_corridor(cur, 76.0)
	cur = _checkpoint(cur, 4)

	# 7. Straight + hump, then a turn into the first wall-jump GAP.
	cur = _straight(cur, 28.0, _mat_deck, true)
	cur = _hump(cur, 5.0)
	cur = _arc(cur, 34.0, 90.0, -1, _mat_accent)
	cur = _wall_jump_gap(cur, 46.0, 16.0, 52.0)
	cur = _checkpoint(cur, 5)

	# 8. LOOP #2 (bigger real 360 loop-de-loop).
	cur = _straight(cur, 38.0, _mat_deck, true)
	cur = _real_loop(cur, 16.0, 60)
	cur = _straight(cur, 24.0, _mat_deck, true)
	cur = _checkpoint(cur, 6)

	# 9. Turn -> second drift chicane -> second hop corridor.
	cur = _arc(cur, 30.0, 90.0, 1, _mat_accent)
	cur = _drift_chicane(cur)
	cur = _wall_corridor(cur, 70.0)
	cur = _checkpoint(cur, 7)

	# 10. Turn -> second wall-jump GAP.
	cur = _arc(cur, 28.0, 75.0, -1, _mat_accent)
	cur = _wall_jump_gap(cur, 42.0, 15.0, 52.0)
	cur = _checkpoint(cur, 8)

	# 11. Final flow: straight + hump + sweeping turn into the finish.
	cur = _straight(cur, 30.0, _mat_deck, true)
	cur = _hump(cur, 4.0)
	cur = _arc(cur, 32.0, 70.0, 1, _mat_accent)
	cur = _checkpoint(cur, 9)
	cur = _straight(cur, 56.0, _mat_deck, true)
	_add_finish_line(cur)
	_plaza(cur, 40.0)

	# Recovery floor sized to the whole course (built last, after bounds are known).
	_build_floor()


# ============================================================================
#  Composite sections
# ============================================================================

func _hump(cur: Transform3D, h: float) -> Transform3D:
	cur = _ramp(cur, 18.0, h, _mat_ramp)               # up
	cur = _straight(cur, 10.0, _mat_ramp)              # crest (fly off it fast)
	cur = _ramp(cur, 22.0, -h, _mat_ramp)              # back down
	return cur


func _drift_chicane(cur: Transform3D) -> Transform3D:
	cur = _straight(cur, 16.0, _mat_deck, true)
	cur = _arc(cur, 16.0, 55.0, 1, _mat_accent)
	cur = _arc(cur, 16.0, 55.0, -1, _mat_accent)
	return cur


# A real 360° LOOP-DE-LOOP. The car drives in grounded, up the front, fully inverted over the top,
# and down — a pure vertical circle (which drives perfectly at speed: no bleed). The trick to ENTRY:
# a full loop's descending back hangs low across the approach and blocks a grounded car, so we OMIT
# those low back-bottom slabs (cut where the point is behind the entry AND low) — the car then drives
# straight in unobstructed. The rest of the circle is intact, so it's a genuine loop. `radius` sets
# the size; the loop returns the cursor advanced forward past it (a turn should follow to flow out).
func _real_loop(cur: Transform3D, radius: float, segments: int) -> Transform3D:
	var fwd := -cur.basis.z
	var up := cur.basis.y
	var right := cur.basis.x
	var base := cur.origin
	var centre := base + up * radius
	# Flat deck running through/under the loop: it catches you coming out the bottom of the circle, and
	# (since both bottoms are cut) lets you drive straight under if you don't jump in.
	var deck_len := radius * 2.0 + 16.0
	_add_box(Vector3(LANE_W, DECK_T, deck_len), base + fwd * (deck_len * 0.5) - up * (DECK_T * 0.5), cur.basis, _mat_deck)
	for i in range(segments):
		var ang := TAU * float(i) / float(segments)
		var p := centre - up * cos(ang) * radius + fwd * sin(ang) * radius
		# Cut the low bottoms so a grounded car can drive in/out. ASYMMETRIC: the FRONT keeps a low cut
		# (jump in onto it above the cut), but the descending BACK is cut HIGHER — its low slabs otherwise
		# hang over the approach lane at ~car-roof height and the car scrapes them before entering. The
		# car still rides the back down to loop_back_cut, then drops the rest to the under-deck.
		var height := (p - base).dot(up)
		var is_back := (p - base).dot(fwd) < 0.0
		if height < (loop_back_cut if is_back else loop_front_cut):
			continue
		var inward := (up * cos(ang) - fwd * sin(ang)).normalized()
		var tangent := (up * sin(ang) + fwd * cos(ang)).normalized()
		var basis := Basis(right, inward, -tangent)
		var seg_len := TAU * radius / float(segments) + 0.7
		_add_box(Vector3(LANE_W, 0.6, seg_len), p - inward * 0.3, basis, _mat_loop)
		# Glowing edge strips on the inner (driving) face — a cyan ring around the loop.
		for s: float in [-1.0, 1.0]:
			var ep := p + right * (s * (LANE_W * 0.5 - edge_margin)) + inward * edge_lift
			_add_edge_box(Vector3(edge_width, 0.05, seg_len), ep, basis)
	_bound(centre + fwd * radius)
	_bound(centre + up * radius)
	var nc := cur
	nc.origin += fwd * deck_len
	return nc


# A CLIMBING SPIRAL (helix): the car drives up a banked ramp that curves `turn_deg` while rising
# `rise`, then back down a matching curve — it goes up, spirals around, and comes out further along,
# so it clearly has an entry and an exit (unlike a flat circle). Drivable: the deck stays a gentle
# incline + curve (surface normal near-up), unlike a true inverting loop. Slabs are oriented to the
# local surface (forward = path direction, up = surface normal) for reliable contact normals.
func _spiral(cur: Transform3D, radius: float, rise: float, turn_deg: float, dir: int) -> Transform3D:
	# Up: climb + turn one way. Down: descend + turn back the OTHER way — net 0 heading change, an
	# S-shaped up-and-over that progresses forward and exits pointing the same way it entered.
	var c := cur
	c = _helix_arc(c, radius, rise, turn_deg, dir)        # climb, curving one way
	c = _helix_arc(c, radius, -rise, turn_deg, -dir)      # descend, curving back — net 0 heading, S-shaped, progresses forward
	return c


func _helix_arc(cur: Transform3D, radius: float, rise: float, turn_deg: float, dir: int) -> Transform3D:
	var arclen := deg_to_rad(absf(turn_deg)) * radius
	var segs := maxi(4, int(ceil(arclen / SEG_LEN)))
	var seg_len := arclen / float(segs)
	var step := deg_to_rad(turn_deg / float(segs)) * float(dir)
	var rise_per := rise / float(segs)
	var c := cur
	var pts := PackedVector3Array()
	var rights: Array[Vector3] = []
	for i in range(segs + 1):
		pts.append(c.origin)
		rights.append(c.basis.x)
		if i < segs:
			c.origin += (-c.basis.z) * seg_len + Vector3.UP * rise_per
			c.basis = c.basis.rotated(Vector3.UP, step)
	for i in range(segs):
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var fwd := (p1 - p0).normalized()
		var right := rights[i]
		var up := right.cross(fwd).normalized()           # surface normal (near +y, tilted by the climb)
		if up.y < 0.0:
			up = -up
		var basis := Basis(right, up, -fwd)
		var seg_len2 := p0.distance_to(p1) + 0.8
		var mid := (p0 + p1) * 0.5
		_add_box(Vector3(LANE_W, DECK_T, seg_len2), mid - up * (DECK_T * 0.5), basis, _mat_loop)
		# Walls on BOTH edges so the car is held on the spiral through the turn.
		for s: float in [-1.0, 1.0]:
			_add_box(Vector3(0.6, 3.0, seg_len2), mid + right * (s * (LANE_W * 0.5 + 0.3)) + up * 1.5, basis, _mat_wall)
		_bound(p0)
	return c


# Two tall parallel walls flush at the lane edges: ride one (Q), wall-jump across to the other.
func _wall_corridor(cur: Transform3D, length: float) -> Transform3D:
	var fwd := -cur.basis.z
	var mid := cur.origin + fwd * (length * 0.5)
	_add_box(Vector3(LANE_W, DECK_T, length), mid - cur.basis.y * (DECK_T * 0.5), cur.basis, _mat_deck)
	var hw := LANE_W * 0.5
	for side: float in [-1.0, 1.0]:
		var wc := mid + cur.basis.x * (side * (hw + 0.5)) + cur.basis.y * 8.0
		_add_wall(Vector3(1.0, 16.0, length), wc, cur.basis)
	_arrows_along(cur, length)
	var nc := cur
	nc.origin += fwd * length
	_edge_lines_seg(cur, nc)
	_bound(nc.origin)
	return nc


# Ride the left wall, then wall-jump (Q) off it across an open GAP onto the landing pad. Miss = drop
# to the recovery floor and drive back on.
func _wall_jump_gap(cur: Transform3D, wall_len: float, gap: float, pad_len: float) -> Transform3D:
	var fwd := -cur.basis.z
	var hw := LANE_W * 0.5
	# Wall straight: deck + tall ride-wall on the LEFT, a normal barrier on the right.
	var mid := cur.origin + fwd * (wall_len * 0.5)
	_add_box(Vector3(LANE_W, DECK_T, wall_len), mid - cur.basis.y * (DECK_T * 0.5), cur.basis, _mat_deck)
	_add_wall(Vector3(1.0, 16.0, wall_len), mid - cur.basis.x * (hw + 0.5) + cur.basis.y * 8.0, cur.basis)
	_add_wall(Vector3(BARRIER_T, BARRIER_H, wall_len), mid + cur.basis.x * (hw + BARRIER_T * 0.5) + cur.basis.y * (BARRIER_H * 0.5), cur.basis)
	var wall_end := cur
	wall_end.origin += fwd * wall_len
	_edge_lines_seg(cur, wall_end)
	var c := cur
	c.origin += fwd * (wall_len + gap)                 # cross the gap (no deck)
	# Landing pad (teal) with barriers.
	var pmid := c.origin + fwd * (pad_len * 0.5)
	_add_box(Vector3(LANE_W, DECK_T, pad_len), pmid - c.basis.y * (DECK_T * 0.5), c.basis, _mat_pad)
	_side_barriers(c, pad_len, c.basis)
	var nc := c
	nc.origin += fwd * pad_len
	_edge_lines_seg(c, nc)
	_bound(nc.origin)
	return nc


# ============================================================================
#  Basic section builders (travel = -basis.z, right = basis.x, up = basis.y)
# ============================================================================

func _straight(cur: Transform3D, length: float, mat: StandardMaterial3D, arrows: bool = false) -> Transform3D:
	var fwd := -cur.basis.z
	var mid := cur.origin + fwd * (length * 0.5)
	_add_box(Vector3(LANE_W, DECK_T, length), mid - cur.basis.y * (DECK_T * 0.5), cur.basis, mat)
	_side_barriers(cur, length, cur.basis)
	if arrows:
		_arrows_along(cur, length)
	var nc := cur
	nc.origin += fwd * length
	_edge_lines_seg(cur, nc)
	_bound(nc.origin)
	return nc


func _ramp(cur: Transform3D, length: float, rise: float, mat: StandardMaterial3D) -> Transform3D:
	var fwd := -cur.basis.z
	var slope := atan2(rise, length)
	var deck_len := sqrt(length * length + rise * rise)
	var deck_basis := cur.basis.rotated(cur.basis.x.normalized(), slope)
	var mid := cur.origin + fwd * (length * 0.5) + cur.basis.y * (rise * 0.5)
	_add_box(Vector3(LANE_W, DECK_T, deck_len), mid - deck_basis.y * (DECK_T * 0.5), deck_basis, mat)
	var hw := LANE_W * 0.5
	for side: float in [-1.0, 1.0]:
		var bc: Vector3 = mid + cur.basis.x * (side * (hw + BARRIER_T * 0.5)) + deck_basis.y * (BARRIER_H * 0.5)
		_add_wall(Vector3(BARRIER_T, BARRIER_H, deck_len), bc, deck_basis)
	var nc := cur
	nc.origin += fwd * length + cur.basis.y * rise
	_edge_lines_seg(Transform3D(deck_basis, cur.origin), Transform3D(deck_basis, nc.origin))
	_bound(nc.origin)
	return nc


func _arc(cur: Transform3D, radius: float, sweep_deg: float, dir: int, mat: StandardMaterial3D) -> Transform3D:
	var arclen := deg_to_rad(absf(sweep_deg)) * radius
	var segs := maxi(2, int(ceil(arclen / SEG_LEN)))
	var seg_len := arclen / segs
	var step := deg_to_rad(sweep_deg / float(segs)) * float(dir)
	var c := cur
	var frames: Array[Transform3D] = []
	for i in range(segs + 1):
		frames.append(c)
		_bound(c.origin)
		if i < segs:
			c.origin += (-c.basis.z) * seg_len
			c.basis = c.basis.rotated(c.basis.y.normalized(), step)
	_ribbon(frames, LANE_W, mat)
	_edge_lines_frames(frames)
	_wall_ribbon(frames, -1.0)
	_wall_ribbon(frames, 1.0)
	_wall_top_strip(frames, -1.0)
	_wall_top_strip(frames, 1.0)
	return c


func _side_barriers(cur: Transform3D, length: float, basis: Basis) -> void:
	var fwd := -basis.z
	var hw := LANE_W * 0.5
	var mid := cur.origin + fwd * (length * 0.5)
	for side: float in [-1.0, 1.0]:
		var bc: Vector3 = mid + basis.x * (side * (hw + BARRIER_T * 0.5)) + basis.y * (BARRIER_H * 0.5)
		_add_wall(Vector3(BARRIER_T, BARRIER_H, length), bc, basis)


func _arrows_along(cur: Transform3D, length: float) -> void:
	var fwd := -cur.basis.z
	var n := maxi(1, int(length / 24.0))
	for i in range(n):
		var t := (float(i) + 0.5) * (length / float(n))
		var p := cur.origin + fwd * t + cur.basis.y * 0.06
		for side: float in [-1.0, 1.0]:
			var b := cur.basis.rotated(cur.basis.y.normalized(), deg_to_rad(35.0 * side))
			_add_box(Vector3(0.4, 0.12, 3.2), p + cur.basis.x * (side * 0.9), b, _mat_arrow)


func _ride_wall(end_cur: Transform3D, length: float) -> void:
	var back := end_cur.basis.z
	var mid := end_cur.origin + back * (length * 0.5)
	var inner := LANE_W * 0.5 - 0.5
	var wc := mid - end_cur.basis.x * (inner + 0.5) + end_cur.basis.y * 7.0
	_add_wall(Vector3(1.0, 14.0, length), wc, end_cur.basis)


func _plaza(cur: Transform3D, depth: float) -> void:
	var fwd := -cur.basis.z
	var center := cur.origin + fwd * (depth * 0.5)
	_add_box(Vector3(40, DECK_T, depth), center - cur.basis.y * (DECK_T * 0.5), cur.basis, _mat_accent)
	_add_wall(Vector3(40, 6, 1), cur.origin + fwd * depth + cur.basis.y * 3.0, cur.basis)
	_bound(cur.origin + fwd * depth)


# ============================================================================
#  Bounds + recovery floor
# ============================================================================

func _bound(p: Vector3) -> void:
	_min_x = minf(_min_x, p.x)
	_max_x = maxf(_max_x, p.x)
	_min_z = minf(_min_z, p.z)
	_max_z = maxf(_max_z, p.z)


func _build_floor() -> void:
	var cx := (_min_x + _max_x) * 0.5
	var cz := (_min_z + _max_z) * 0.5
	var sx := (_max_x - _min_x) + 260.0     # generous margin for lane width, arc bulge, landing spread
	var sz := (_max_z - _min_z) + 260.0
	_add_box(Vector3(sx, 1.0, sz), Vector3(cx, -0.65, cz), Basis.IDENTITY, _mat_floor)


# ============================================================================
#  Primitives
# ============================================================================

func _add_box(size: Vector3, position: Vector3, basis: Basis, mat: StandardMaterial3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.transform = Transform3D(basis.orthonormalized(), position)
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
	return body


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
	_commit_surface(st, faces, mat)


func _wall_ribbon(frames: Array[Transform3D], side: float) -> void:
	if frames.size() < 2:
		return
	var hw := LANE_W * 0.5
	var faces := PackedVector3Array()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(frames.size() - 1):
		var a := frames[i]
		var b := frames[i + 1]
		var a_b := a.origin + a.basis.x * (side * hw)
		var a_t := a_b + a.basis.y * BARRIER_H
		var b_b := b.origin + b.basis.x * (side * hw)
		var b_t := b_b + b.basis.y * BARRIER_H
		for tri in [[a_b, a_t, b_t], [a_b, b_t, b_b]]:
			for p: Vector3 in tri:
				st.add_vertex(p)
				faces.append(p)
	st.generate_normals()
	_commit_surface(st, faces, _mat_wall)


func _commit_surface(st: SurfaceTool, faces: PackedVector3Array, mat: StandardMaterial3D) -> void:
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


func _make_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


# ============================================================================
#  Emissive edge lines (014) — glowing cyan strips along the lane edges.
#  Visual ONLY: a MeshInstance3D with no StaticBody/collision, lifted slightly
#  above the deck. They make the racing line unmistakable and give the M5
#  ComicPostFX Sobel pass bright edges to ink. They never touch the car.
# ============================================================================

# Two-frame convenience for straight/ramp/deck sections.
func _edge_lines_seg(a: Transform3D, b: Transform3D) -> void:
	var frames: Array[Transform3D] = [a, b]
	_edge_lines_frames(frames)


# Glowing strip down each lane edge, following the given path frames (so it curves
# with arcs and tilts with ramps automatically).
func _edge_lines_frames(frames: Array[Transform3D]) -> void:
	if frames.size() < 2:
		return
	_edge_ribbon(frames, -1.0)
	_edge_ribbon(frames, 1.0)


func _edge_ribbon(frames: Array[Transform3D], side: float) -> void:
	var off := (LANE_W * 0.5 - edge_margin) * side
	var sw := edge_width
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(frames.size() - 1):
		var a := frames[i]
		var b := frames[i + 1]
		var a_in := a.origin + a.basis.x * (off - sw * 0.5) + a.basis.y * edge_lift
		var a_out := a.origin + a.basis.x * (off + sw * 0.5) + a.basis.y * edge_lift
		var b_in := b.origin + b.basis.x * (off - sw * 0.5) + b.basis.y * edge_lift
		var b_out := b.origin + b.basis.x * (off + sw * 0.5) + b.basis.y * edge_lift
		for tri in [[a_in, a_out, b_out], [a_in, b_out, b_in]]:
			for p: Vector3 in tri:
				st.add_vertex(p)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat_edge
	add_child(mi)


# Single thin emissive strip oriented to an arbitrary basis (used for loop segments
# and wall tops). Visual only. Defaults to the cyan floor-edge material.
func _add_edge_box(size: Vector3, position: Vector3, basis: Basis, mat: StandardMaterial3D = null) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat if mat != null else _mat_edge
	mi.transform = Transform3D(basis.orthonormalized(), position)
	add_child(mi)


# Builds a wall box (_mat_wall) PLUS a magenta glow strip along its top edge, so EVERY
# straight/ramp/ride/corridor/gap wall reads consistently. position = wall CENTRE; size.y
# = wall height; basis.y = up. (Curved arc walls use _wall_top_strip instead.)
func _add_wall(size: Vector3, position: Vector3, basis: Basis) -> void:
	_add_box(size, position, basis, _mat_wall)
	var top := position + basis.y * (size.y * 0.5 + edge_lift)
	_add_edge_box(Vector3(size.x + 0.1, 0.14, size.z), top, basis, _mat_wall_edge)


# Magenta glow strip along the TOP of an arc's side wall, following the wall frames.
# Makes curved walls read as walls (distinct from the cyan floor lines). Visual only.
func _wall_top_strip(frames: Array[Transform3D], side: float) -> void:
	if frames.size() < 2:
		return
	var hw := LANE_W * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(frames.size() - 1):
		var a := frames[i]
		var b := frames[i + 1]
		var a_o := a.origin + a.basis.x * (side * hw) + a.basis.y * BARRIER_H
		var a_i := a_o - a.basis.x * (side * edge_width)
		var b_o := b.origin + b.basis.x * (side * hw) + b.basis.y * BARRIER_H
		var b_i := b_o - b.basis.x * (side * edge_width)
		for tri in [[a_o, a_i, b_i], [a_o, b_i, b_o]]:
			for p: Vector3 in tri:
				st.add_vertex(p)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat_wall_edge
	add_child(mi)


func _make_emissive(color: Color, energy: float = 0.8) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # edge strips are single-sided ribbons — must show from above
	return mat


func _build_materials() -> void:
	_mat_deck = _make_mat(col_deck)
	_mat_accent = _make_mat(col_accent)
	_mat_ramp = _make_mat(col_ramp)
	_mat_pad = _make_mat(col_pad)
	_mat_wall = _make_mat(col_wall)
	_mat_loop = _make_mat(col_loop)
	_mat_floor = _make_mat(col_recovery)
	_mat_arrow = _make_emissive(col_arrow, arrow_emission_energy)
	_mat_edge = _make_emissive(col_edge, edge_emission_energy)
	_mat_wall_edge = _make_emissive(col_wall_edge, wall_edge_emission_energy)


# ============================================================================
#  Run markers (groups read by RunManager)
# ============================================================================

const START_GROUP := "start_line"
const FINISH_GROUP := "finish_line"
const CHECKPOINT_GROUP := "checkpoints"

var _mat_start := _make_trigger_mat(Color(0.20, 1.00, 0.40))
var _mat_finish := _make_trigger_mat(Color(1.00, 0.85, 0.10))
var _mat_checkpoint := _make_trigger_mat(Color(0.00, 1.00, 0.80))


func _add_start_line(cur: Transform3D) -> void:
	_trigger(cur, Vector3(LANE_W, 8.0, 1.0), START_GROUP, -1, _mat_start)


func _add_finish_line(cur: Transform3D) -> void:
	_trigger(cur, Vector3(LANE_W, 8.0, 1.0), FINISH_GROUP, -1, _mat_finish)


func _checkpoint(cur: Transform3D, index: int) -> Transform3D:
	_trigger(cur, Vector3(LANE_W, 8.0, 1.0), CHECKPOINT_GROUP, index, _mat_checkpoint)
	return cur


func _trigger(cur: Transform3D, size: Vector3, group: String, index: int, mat: StandardMaterial3D) -> void:
	var area := Area3D.new()
	area.transform = Transform3D(cur.basis.orthonormalized(), cur.origin + cur.basis.y * (size.y * 0.5))
	area.collision_layer = 0
	area.collision_mask = 1
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
