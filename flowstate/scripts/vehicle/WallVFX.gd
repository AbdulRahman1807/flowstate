class_name WallVFX
extends Node3D

# ============================================================================
#  WallVFX — contact-accurate movement VFX
# ----------------------------------------------------------------------------
#  Passive observer (writes nothing, like DynamicCamera). Sparks are emitted at
#  the REAL contact point and fly in a TIGHT cone along the friction direction
#  that created them — never a 360° puff from the car's centre. Sources:
#
#    scrape (continuous) — body sliding along a wall: sparks at the wall contact
#                          point, sprayed backward along the slide + off the wall.
#                          Driven by VehiclePhysics.get_scrape_contact().
#    wall ride (cont.)   — button-attached riding: sparks at the wheels, backward.
#    landing (burst)     — hard touchdown: sparks from under the car, low along
#                          the travel direction.
#    wall attach / jump  — sparks at the car base off the wall / launch.
#    drift smoke         — soft alpha puffs off the rear while drifting.
#
#  Clean takeoffs (ground jump) and near-misses make NO sparks — there is no
#  metal-on-surface contact, so a spark there would be wrong (and the takeoff
#  flash read like a double-jump). bursts_fired still counts impact events even
#  when visuals are disabled, so the signal wiring stays probe-verifiable.
# ============================================================================

# --- impact sparks (white-hot streaks, monochrome) -------------------------
@export var spark_color: Color = Color(0.55, 0.95, 1.0) ## single neon tint in the white-hot sparks (no rainbow)
@export var burst_amount: int = 16        ## particles in an impact pop
@export var ride_amount: int = 12         ## continuous wall-ride spark density
@export var scrape_amount: int = 24       ## continuous wall-scrape spark density
@export var spark_lifetime: float = 0.28
@export var burst_speed: float = 18.0
@export var spark_length: float = 0.7     ## long axis of the spark streak (stretched along its velocity)
@export var spark_thickness: float = 0.09 ## short axis — a thin glowing head tapering to a fine tail
@export var spark_gravity: float = 22.0   ## sparks arc down fast like real embers
@export_range(0.0, 90.0) var spark_spread: float = 22.0  ## tight cone for impact sparks (degrees)
@export_range(0.0, 90.0) var scrape_spread: float = 30.0 ## slightly wider fan for grinding sparks (degrees)
@export var scrape_out_bias: float = 0.45 ## how much scrape sparks spray OUT off the wall vs straight back
@export var base_offset: float = 0.9      ## distance below the car origin to the tyres / ground contact

# --- drift smoke (soft, alpha-blended; the reference's signature) ----------
@export var smoke_enabled: bool = true
@export var smoke_color: Color = Color(0.7, 0.8, 0.95)  ## cool near-white; push toward a hue for neon vapour
@export var smoke_amount: int = 28
@export var smoke_lifetime: float = 0.9
@export var smoke_size: float = 1.6
@export_range(0.0, 1.0) var smoke_opacity: float = 0.32 ## peak alpha of a puff (low = smoke, not fog)
@export var smoke_rise: float = 1.2                     ## upward drift speed of the smoke

@export var land_min_impact: float = 3.0 ## below this, a landing is too soft to spark (spawn-settle, tiny steps)
@export var enabled: bool = false        ## master switch for spark + smoke visuals (set true in the play scenes)

var _burst: GPUParticles3D    # one-shot impact pops
var _ride: GPUParticles3D     # continuous sparks while button-wall-riding
var _scrape: GPUParticles3D   # continuous sparks while scraping a wall
var _smoke: GPUParticles3D    # continuous drift smoke
var _vehicle: VehiclePhysics
var _wall_riding: WallRiding
var _is_drifting: bool = false
var _last_wall_normal: Vector3 = Vector3.UP
var _just_jumped_off_wall: bool = false   # de-dupes the wall-jump (jump pop vs detach pop)
var bursts_fired: int = 0                 # observable for probes/debug

func _ready() -> void:
	_vehicle = get_parent() as VehiclePhysics
	_wall_riding = get_parent().get_node_or_null("WallRiding") as WallRiding
	if _wall_riding:
		_wall_riding.on_wall_attach.connect(_on_wall_attach)
		_wall_riding.on_wall_jump.connect(_on_wall_jump)
		_wall_riding.on_wall_detach.connect(_on_wall_detach)
		# on_near_miss deliberately NOT consumed — a near miss has no contact, so no spark.
	if _vehicle:
		_vehicle.landed.connect(_on_land)
		_vehicle.drift_started.connect(_on_drift_started)
		_vehicle.drift_ended.connect(_on_drift_ended)
		# 'jumped' deliberately NOT consumed — a clean takeoff makes no sparks.

	_burst = _make_spark_emitter(true, burst_amount, spark_spread)
	_ride = _make_spark_emitter(false, ride_amount, spark_spread)
	_ride.position = Vector3(0.0, -base_offset, 0.0)   # at the wheels (car-local)
	_scrape = _make_spark_emitter(false, scrape_amount, scrape_spread)
	add_child(_burst)
	add_child(_ride)
	add_child(_scrape)

	_smoke = _make_smoke()
	_smoke.position = Vector3(0.0, -base_offset, 0.3)  # near the rear wheels / ground (car-local)
	add_child(_smoke)

func _process(_dt: float) -> void:
	if not _vehicle:
		return
	# Continuous wall-RIDE sparks (button-attached riding) — at the wheels, sprayed backward.
	if _ride and _wall_riding:
		var riding := _wall_riding.is_wall_riding()
		_ride.emitting = enabled and riding
		if riding and _vehicle.velocity.length() > 0.5:
			(_ride.process_material as ParticleProcessMaterial).direction = -_vehicle.velocity.normalized()
	# Continuous wall-SCRAPE sparks at the real contact point, fired along the slide.
	if _scrape:
		var s := _vehicle.get_scrape_contact()
		var active: bool = enabled and bool(s["active"])
		_scrape.emitting = active
		if active:
			_scrape.global_position = s["point"]
			var n: Vector3 = s["normal"]
			var tangent: Vector3 = s["tangent"]
			var spd: float = s["speed"]
			var pm := _scrape.process_material as ParticleProcessMaterial
			pm.direction = (-tangent + n * scrape_out_bias).normalized()  # back along the slide + off the wall
			pm.initial_velocity_min = spd * 0.35
			pm.initial_velocity_max = spd * 0.8 + 4.0
	# Drift smoke.
	if _smoke:
		_smoke.emitting = enabled and smoke_enabled and _is_drifting

# --- event handlers ---

func _on_wall_attach(entry_speed: float, wall_normal: Vector3) -> void:
	_last_wall_normal = wall_normal
	_emit_burst(_base_point(), wall_normal, clampf(entry_speed / 20.0, 0.7, 1.4))

func _on_wall_jump(_speed: float) -> void:
	_just_jumped_off_wall = true
	_emit_burst(_base_point(), (_last_wall_normal + _vehicle.global_transform.basis.y).normalized(), 1.6)

func _on_wall_detach(_ride_duration: float, _exit_speed: float, _reason: String) -> void:
	# Every wall exit pops — but skip the one that immediately follows a wall jump (already popped).
	if _just_jumped_off_wall:
		_just_jumped_off_wall = false
		return
	_emit_burst(_base_point(), _vehicle.global_transform.basis.y, 0.8)

func _on_land(impact_velocity: float) -> void:
	if impact_velocity < land_min_impact:
		return   # too soft to register (spawn-settle, small step-downs)
	var up := _vehicle.global_transform.basis.y
	var travel := _vehicle.velocity - up * _vehicle.velocity.dot(up)   # horizontal-ish component
	var dir: Vector3
	if travel.length() > 0.5:
		dir = (travel.normalized() - up * 0.25).normalized()   # spray forward, hugging the ground
	else:
		dir = -up                                              # straight-down landing -> splash down/out
	_emit_burst(_base_point(), dir, clampf(impact_velocity / 12.0, 0.6, 1.8))

func _on_drift_started() -> void:
	_is_drifting = true

func _on_drift_ended() -> void:
	_is_drifting = false

# Contact point under the car (tyres), in world space.
func _base_point() -> Vector3:
	return _vehicle.global_position - _vehicle.global_transform.basis.y * base_offset

func _emit_burst(origin: Vector3, dir: Vector3, scale: float) -> void:
	if not _burst or not _vehicle:
		return
	bursts_fired += 1   # count the event even when visuals are off (keeps signal wiring verifiable)
	if not enabled:
		return
	_burst.global_position = origin
	var pm := _burst.process_material as ParticleProcessMaterial
	pm.direction = dir.normalized() if dir.length() > 0.01 else Vector3.UP
	_burst.amount = maxi(6, int(round(burst_amount * scale)))
	_burst.restart()


# --- spark emitter construction (procedural; no .tres to author) ---

func _make_spark_emitter(one_shot: bool, amount: int, spread: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.local_coords = false                       # world space => sparks fly free / trail
	# Stretch each spark along its OWN velocity (while still facing the camera) so they render as
	# sharp lines, not round blobs — the way real metal sparks streak.
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	p.one_shot = one_shot
	p.explosiveness = 1.0 if one_shot else 0.0   # 1.0 = whole pop in one frame (comic punch)
	p.amount = maxi(amount, 1)
	p.lifetime = spark_lifetime
	p.emitting = false
	p.draw_pass_1 = _spark_mesh(one_shot)
	p.process_material = _spark_process(spread)
	return p

func _spark_mesh(one_shot: bool) -> Mesh:
	var q := QuadMesh.new()
	var k := 1.0 if one_shot else 0.7
	# Long, thin quad. Its local +Y is the long axis; transform_align points that Y along the spark's
	# velocity, so the quad stretches into a streak (thickness = local X, length = local Y).
	q.size = Vector2(spark_thickness * k, spark_length * k)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD              # additive => glows on the dark bg
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED      # node-level transform_align does the billboarding
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _streak_texture()                     # sharp tapered LINE, not a round blob
	m.vertex_color_use_as_albedo = true                      # per-particle white/neon tint
	m.albedo_color = Color(1, 1, 1, 1)
	q.material = m
	return q

func _spark_process(spread: float) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT  # from a precise contact point
	pm.direction = Vector3.UP                                # overridden per emit / per frame
	pm.spread = spread                                       # tight => sparks stay true to the friction dir
	pm.initial_velocity_min = burst_speed * 0.4
	pm.initial_velocity_max = burst_speed
	pm.gravity = Vector3(0, -spark_gravity, 0)               # embers fall away fast (no lingering trail)
	pm.damping_min = 3.0
	pm.damping_max = 9.0
	pm.scale_min = 0.3                                       # wide length variance => not uniform needles
	pm.scale_max = 1.8
	pm.color_initial_ramp = _spark_ramp()                    # white hot-cores + one neon tint (no rainbow)
	pm.color_ramp = _fade_ramp()                             # hold bright, then fade out
	return pm

# Spark "tadpole": a bright glowing HEAD (the leading +Y end, which transform_align points along
# velocity) tapering into a thin fading TAIL — like a real ember with a motion-blur trail, not a
# uniform double-ended needle.
func _streak_texture() -> ImageTexture:
	var w := 16
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		var v := float(y) / float(h - 1)               # 0 = tail, 1 = head (head leads along velocity)
		var d := 1.0 - v                               # 0 at head, 1 at tail
		var bright := exp(-d * 3.0)                    # bright glowing head, exponentially fading tail
		var half_w := lerpf(0.55, 0.06, clampf(d * 1.3, 0.0, 1.0))   # rounded head, thin tail
		for x in range(w):
			var du := absf(float(x) / float(w - 1) - 0.5) * 2.0      # 0 centre .. 1 edge
			var across := smoothstep(half_w, half_w * 0.35, du)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, bright * across))
	return ImageTexture.create_from_image(img)

# Per-particle spark colour: white-hot core easing through ONE neon tint and back to white. Reads as
# real sparks, not the old cyan/magenta/yellow "rainbow" that looked like an arcade kids' game.
func _spark_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), spark_color, Color(1, 1, 1, 1)])
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex

# Brightness over life: flickers as it flies (real sparks twinkle), then dies out — not a steady line.
func _fade_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.45, 0.7, 1.0])
	g.colors = PackedColorArray([
		Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.6), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.0),
	])
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex

# Soft round glow: white-hot centre fading to a transparent edge. Used by the smoke puffs.
func _glow_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.22, 0.55, 1.0])
	g.colors = PackedColorArray([
		Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.22), Color(1, 1, 1, 0.0),
	])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 72
	t.height = 72
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


# --- drift smoke (soft alpha puffs; continuous while drifting) ---

func _make_smoke() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.local_coords = false                       # puffs stay in world space => trail behind the drift
	p.one_shot = false
	p.amount = maxi(smoke_amount, 1)
	p.lifetime = smoke_lifetime
	p.emitting = false
	p.draw_pass_1 = _smoke_mesh()
	p.process_material = _smoke_process()
	return p

func _smoke_mesh() -> Mesh:
	var q := QuadMesh.new()
	q.size = Vector2(smoke_size, smoke_size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX             # alpha smoke (additive would glow like vapour)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _glow_texture()                       # soft round puff
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1, 1, 1, 1)
	q.material = m
	return q

func _smoke_process() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.6, 0.1, 0.6)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 40.0
	pm.initial_velocity_min = smoke_rise * 0.5
	pm.initial_velocity_max = smoke_rise
	pm.gravity = Vector3(0, 0.4, 0)                          # gentle rise
	pm.damping_min = 1.0
	pm.damping_max = 2.5
	pm.scale_min = 0.8
	pm.scale_max = 1.5
	pm.color = Color(smoke_color.r, smoke_color.g, smoke_color.b, smoke_opacity)
	pm.color_ramp = _smoke_fade_ramp()
	return pm

# Smoke alpha lifecycle: fade in fast, hold, fade out (multiplies the base smoke_opacity).
func _smoke_fade_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0)])
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex
