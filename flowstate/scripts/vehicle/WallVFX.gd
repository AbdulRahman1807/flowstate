class_name WallVFX
extends Node3D

# ============================================================================
#  WallVFX — movement impact VFX (M3 placeholder)
# ----------------------------------------------------------------------------
#  Passive observer (writes nothing, like DynamicCamera). Connects to WallRiding
#  and VehiclePhysics signals and throws bright additive SPARK BURSTS on impact
#  moments. Look target (04_Art_Direction + dev): comicy + realistic + graffiti —
#  hot white-cored sparks with saturated colour halos, NOT flat arcade pixels.
#  The "pixel" read came from flat solid-colour billboard squares; the fix is a
#  soft radial-glow texture (white-hot centre -> transparent edge), a white+colour
#  mix (uniform saturated colour is the cartoony part), and real spark motion
#  (fast, gravity arc, quick fade). Full inky/halftone comic pass is M5.
#
#  Events it pops on:
#    wall attach  -> sparks spray off the wall (along its normal)
#    wall ride    -> low, continuous edge sparks
#    wall jump    -> big launch pop
#    wall cancel  -> pop on detach (clean release / speed-loss / edge exit)
#    ground jump  -> pop  (VehiclePhysics.jumped)
#    land         -> pop scaled by impact  (VehiclePhysics.landed)
#    near miss    -> small flash
# ============================================================================

# 04_Art_Direction palette hues. White hot-cores are mixed in automatically.
@export var palette: PackedColorArray = PackedColorArray([
	Color(0.0, 1.0, 0.8),     # electric cyan
	Color(1.0, 0.176, 0.471), # hot magenta
	Color(0.91, 1.0, 0.0),    # acid yellow
])
@export var burst_amount: int = 22       # particles in an impact pop
@export var ride_amount: int = 16        # continuous edge-spark count while riding
@export var spark_lifetime: float = 0.38
@export var burst_speed: float = 13.0
@export var spark_size: float = 0.5
@export var spark_gravity: float = 14.0  # sparks arc down like real embers
@export var land_min_impact: float = 3.0 # below this, a landing is too soft to pop (spawn-settle, tiny steps)
@export var enabled: bool = false        # particle visuals OFF (rainbow-trail scrapped); comic look is the M5 shader/asset pass. Signal wiring + bursts_fired stay live.

var _burst: GPUParticles3D   # one-shot impact pops
var _ride: GPUParticles3D    # continuous trail while riding
var _vehicle: VehiclePhysics
var _wall_riding: WallRiding
var _just_jumped_off_wall: bool = false   # de-dupes the wall-jump (jump pop vs detach pop)
var bursts_fired: int = 0                 # observable for probes/debug

func _ready() -> void:
	_vehicle = get_parent() as VehiclePhysics
	_wall_riding = get_parent().get_node_or_null("WallRiding") as WallRiding
	if _wall_riding:
		_wall_riding.on_wall_attach.connect(_on_wall_attach)
		_wall_riding.on_wall_jump.connect(_on_wall_jump)
		_wall_riding.on_wall_detach.connect(_on_wall_detach)
		_wall_riding.on_near_miss.connect(_on_near_miss)
	if _vehicle:
		_vehicle.landed.connect(_on_land)
		_vehicle.jumped.connect(_on_ground_jump)

	_burst = _make_emitter(true, burst_amount, burst_speed)
	_ride = _make_emitter(false, ride_amount, burst_speed * 0.45)
	_ride.emitting = false
	add_child(_burst)
	add_child(_ride)

func _process(_dt: float) -> void:
	if _ride and _wall_riding:
		_ride.emitting = enabled and _wall_riding.is_wall_riding()

# --- event handlers ---

func _on_wall_attach(entry_speed: float, wall_normal: Vector3) -> void:
	_pop(wall_normal, clampf(entry_speed / 20.0, 0.7, 1.6))

func _on_wall_jump(_speed: float) -> void:
	_just_jumped_off_wall = true
	_pop(Vector3.UP, 1.9)   # big launch pop

func _on_wall_detach(_ride_duration: float, _exit_speed: float, _reason: String) -> void:
	# Every wall exit pops — but skip the one that immediately follows a wall jump (already popped).
	if _just_jumped_off_wall:
		_just_jumped_off_wall = false
		return
	_pop(Vector3.UP, 1.0)

func _on_near_miss() -> void:
	_pop(Vector3.UP, 0.7)

func _on_land(impact_velocity: float) -> void:
	if impact_velocity < land_min_impact:
		return   # too soft to register (spawn-settle, small step-downs)
	_pop(Vector3.UP, clampf(impact_velocity / 12.0, 0.6, 1.8))

func _on_ground_jump(jump_direction: Vector3) -> void:
	_pop(jump_direction, 1.1)

func _pop(dir: Vector3, scale: float) -> void:
	if not _burst or not _vehicle:
		return
	bursts_fired += 1   # count the event even when visuals are off (keeps signal wiring verifiable)
	if not enabled:
		return           # rainbow-trail visuals scrapped; comic look is the M5 shader/asset pass
	_burst.global_position = _vehicle.global_position
	var pm := _burst.process_material as ParticleProcessMaterial
	pm.direction = dir.normalized() if dir.length() > 0.01 else Vector3.UP
	_burst.amount = maxi(6, int(round(burst_amount * scale)))
	_burst.restart()


# --- emitter construction (procedural; no .tres to author) ---

func _make_emitter(one_shot: bool, amount: int, speed: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.local_coords = false                       # world space => sparks fly free / trail
	p.one_shot = one_shot
	p.explosiveness = 1.0 if one_shot else 0.0   # 1.0 = whole pop in one frame (comic punch)
	p.amount = maxi(amount, 1)
	p.lifetime = spark_lifetime
	p.emitting = false
	p.draw_pass_1 = _spark_mesh(one_shot)
	p.process_material = _spark_process(speed)
	return p

func _spark_mesh(one_shot: bool) -> Mesh:
	var q := QuadMesh.new()
	var s := spark_size if one_shot else spark_size * 0.7
	q.size = Vector2(s, s)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD              # additive => glows on the dark bg
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _glow_texture()                       # soft round glow, NOT a hard square
	m.vertex_color_use_as_albedo = true                      # per-particle palette/white tint
	m.albedo_color = Color(1, 1, 1, 1)
	q.material = m
	return q

func _spark_process(speed: float) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.direction = Vector3.UP
	pm.spread = 75.0
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -spark_gravity, 0)               # embers fall away (realistic)
	pm.damping_min = 3.0
	pm.damping_max = 9.0
	pm.scale_min = 0.5
	pm.scale_max = 1.5
	pm.color_initial_ramp = _hot_palette_ramp()              # white hot-cores + saturated hues
	pm.color_ramp = _fade_ramp()                             # hold bright, then fade out
	return pm

# Soft round glow: white-hot centre fading to a transparent edge. This is what turns the flat
# coloured squares into glowing sparks.
func _glow_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.22, 0.55, 1.0])
	g.colors = PackedColorArray([
		Color(1, 1, 1, 1.0),     # white-hot core
		Color(1, 1, 1, 0.8),
		Color(1, 1, 1, 0.22),
		Color(1, 1, 1, 0.0),     # soft falloff
	])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 72
	t.height = 72
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t

# Per-particle colour: white interleaved with the palette hues so roughly half the sparks read as
# white-hot and the rest carry graffiti colour — avoids the uniform-saturated "cartoony" look.
func _hot_palette_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	var white := Color(1, 1, 1, 1)
	var stops: Array[Color] = [white]
	for hue in palette:
		stops.append(hue)
		stops.append(white)
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	var n := stops.size()
	for i in range(n):
		offsets.append(float(i) / float(maxi(n - 1, 1)))
		colors.append(stops[i])
	g.offsets = offsets
	g.colors = colors
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex

func _fade_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex
