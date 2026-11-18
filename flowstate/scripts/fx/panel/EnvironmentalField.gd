class_name EnvironmentalField
extends Control

# ============================================================================
#  EnvironmentalField — the ACTION LINE FIELD as a camera-scale WORLD effect
# ----------------------------------------------------------------------------
#  This is the car's motion through the WORLD, NOT the motion of any comic word.
#  It is a separate PERSISTENT system (like the MomentumStack) — independent of
#  the ephemeral compositions. It:
#    - is centred on the car and sized well BEYOND the viewport (reaches the
#      edges, originates off-screen),
#    - wraps the car with an exclusion gap,
#    - streams OUTWARD (the world rushing past),
#    - and its intensity is driven by the car's actual SPEED — so it communicates
#      world-speed even when no comic words are on screen.
#  It renders BEHIND the comic compositions (its own lower CanvasLayer) and fades
#  out at low speed, so it never fights the racing line.
# ============================================================================

@export var exclusion: float = 130.0
@export var max_alpha: float = 0.28        # atmosphere, not the hero — supports gameplay, never dominates
@export var idle_speed: float = 6.0        # below this the field is fully OFF (car effectively stationary)
@export var speed_ref: float = 44.0        # speed mapping to full field intensity
@export var stroke_count: int = 44
@export var wrap_span: float = 950.0       # how far a stroke streams before recycling inward

var _vehicle: Node
var _anchor_provider: Callable
var _strokes: Array = []   # [angle, length, w0, w1, phase]
var _alpha: float = 0.0
var _flow: float = 0.0


func init(vehicle: Node, anchor_provider: Callable) -> void:
	_vehicle = vehicle
	_anchor_provider = anchor_provider
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_regen()


func _regen() -> void:
	_strokes.clear()
	for i in stroke_count:
		_strokes.append([
			randf() * TAU,                    # direction from the car
			randf_range(240.0, 1150.0),       # length — long, reaching past the edges
			randf_range(2.0, 6.0),            # base width
			randf_range(0.4, 1.4),            # tip width
			randf(),                          # per-stroke phase offset (varied streaming)
		])


func _process(dt: float) -> void:
	var vp := get_viewport_rect().size
	size = vp * 2.4                          # larger than screen -> reaches + originates off-screen
	var anchor := vp * 0.5
	if _anchor_provider.is_valid():
		anchor = _anchor_provider.call()
	position = anchor - size * 0.5           # centred on the car

	var speed := 0.0
	if is_instance_valid(_vehicle) and _vehicle.has_method("get_speed"):
		speed = _vehicle.get_speed()
	# Deadzone below idle_speed -> the field goes fully invisible when nearly stationary.
	var ratio := clampf((speed - idle_speed) / maxf(speed_ref - idle_speed, 1.0), 0.0, 1.0)
	_alpha = lerpf(_alpha, ratio * max_alpha, clampf(dt * 5.0, 0.0, 1.0))
	_flow += dt * (60.0 + ratio * 560.0)     # outward stream speed scales with car speed
	queue_redraw()


func _draw() -> void:
	if _alpha < 0.01:
		return
	var c := size * 0.5
	var reach := size.length() * 0.5
	for s in _strokes:
		var dir := Vector2.from_angle(s[0])
		var travel := fmod(_flow + s[4] * wrap_span, wrap_span)   # streams outward, recycles inward
		var r0: float = exclusion + travel
		if r0 > reach:
			continue
		var r1: float = minf(r0 + s[1], reach)
		# fade in from the car, ease out near the edge
		var life := clampf(travel / 90.0, 0.0, 1.0) * (1.0 - clampf((r0 - exclusion) / (reach - exclusion), 0.0, 1.0) * 0.35)
		_stroke(c + dir * r0, c + dir * r1, s[2], s[3], life)


func _stroke(a: Vector2, b: Vector2, wa: float, wb: float, life: float) -> void:
	var d := b - a
	if d.length() < 1.0:
		return
	d = d.normalized()
	var perp := Vector2(-d.y, d.x)
	var col := Color(1.0, 1.0, 1.0, _alpha * life)   # white speed lines
	draw_colored_polygon(PackedVector2Array([
		a + perp * wa * 0.5, a - perp * wa * 0.5, b - perp * wb * 0.5, b + perp * wb * 0.5,
	]), col)
