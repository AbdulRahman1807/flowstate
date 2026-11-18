class_name ComicPostFXDriver
extends Node

# ============================================================================
#  ComicPostFXDriver — Flow + speed reactivity for ComicPostFX (016 Part B)
# ----------------------------------------------------------------------------
#  Passive observer (writes nothing to gameplay, like DynamicCamera / WallVFX).
#  Each frame it reads FlowSystem + VehiclePhysics and OVERRIDES ComicPostFX's
#  uniform-mirroring @export values live, so the comic look ESCALATES with the
#  player's skill instead of sitting at a static intensity. This is the core of
#  04_Art_Direction's "the world gets louder as you get better" vision.
#
#    Flow  -> halftone density/scale + ink outline   (style: how cool you are)
#    Speed -> chromatic aberration + speed lines      (velocity: how fast you fly)
#    Boost -> a brief CA spike that decays back        (the no-audio "punch")
#
#  ComicPostFX's own inspector values become the "no-driver" fallback — set
#  `enabled = false` here (or remove the node) and ComicPostFX renders its
#  static defaults. Everything is @export per the project's tuning ethos; the
#  Flow escalation curve and speed/CA mapping are meant to be dev-driven.
# ============================================================================

@export var fx_path: NodePath            ## ComicPostFX node
@export var vehicle_path: NodePath       ## VehiclePhysics (speed + boost)
@export var flow_system_path: NodePath   ## FlowSystem (style escalation)

@export_group("Flow Ramp")
@export var flow_lerp_speed: float = 3.0          ## how fast effects track Flow changes (per second, smooth)
@export var halftone_at_min_flow: float = 0.10    ## halftone intensity at base Flow (subtle)
@export var halftone_at_max_flow: float = 0.22    ## halftone intensity at max Flow (still an accent; dots are off by default anyway)
@export var halftone_scale_at_min: float = 160.0  ## dot scale at base Flow (higher = finer)
@export var halftone_scale_at_max: float = 200.0  ## dot scale at max Flow — FINER, not chunkier: big dots read clumsy, so Flow escalation = denser+finer dots, never bigger ones
@export var outline_at_min_flow: float = 0.55     ## ink outline strength at base Flow (bold)
@export var outline_at_max_flow: float = 0.82     ## ink outline strength at max Flow (strong comic linework, not overbearing)

@export_group("Speed / Chromatic Aberration")
@export var aberration_idle: float = 0.08          ## CA at rest
@export var aberration_max: float = 0.4            ## CA at top speed (subtle — 04 says use aberration sparingly; readability stays)
@export_range(1.0, 4.0) var aberration_speed_exp: float = 2.0  ## pow curve — keeps CA low until near top speed
@export var aberration_boost_spike: float = 0.85   ## CA snaps to this on boost activation
@export var aberration_boost_decay: float = 0.4    ## seconds to ease the spike back to the speed-mapped value

@export_group("Speed Lines")
@export var speed_lines_at_top: float = 0.65       ## peak speed_lines_intensity (present but calm — readability over spectacle)
@export_range(1.0, 4.0) var speed_lines_exp: float = 1.6  ## pow curve — invisible at rest, building near top speed

@export var enabled: bool = true

var _fx: ComicPostFX
var _vehicle: VehiclePhysics
var _flow: FlowSystem

# Smoothed live values (lerped toward their Flow/speed targets so nothing snaps).
var _halftone: float = 0.18
var _halftone_scale: float = 140.0
var _outline: float = 0.5
var _ca: float = 0.08
var _was_boosting: bool = false


func _ready() -> void:
	_fx = get_node_or_null(fx_path) as ComicPostFX
	_vehicle = get_node_or_null(vehicle_path) as VehiclePhysics
	_flow = get_node_or_null(flow_system_path) as FlowSystem
	if _fx == null:
		push_warning("ComicPostFXDriver: no ComicPostFX at fx_path — driver inert.")
	# Seed the smoothed values from the fx's static defaults so frame 0 doesn't jump.
	if _fx:
		_halftone = _fx.halftone_intensity
		_halftone_scale = _fx.halftone_scale
		_outline = _fx.outline_intensity
	_ca = aberration_idle


func _process(delta: float) -> void:
	if not enabled or _fx == null:
		return

	# --- Flow escalation: halftone + outline grow inkier as Flow climbs ------
	var flow_t := 0.0
	if _flow and _flow.max_flow > 0.0:
		flow_t = clampf(_flow.get_value() / _flow.max_flow, 0.0, 1.0)
	var k := clampf(delta * flow_lerp_speed, 0.0, 1.0)
	_halftone = lerpf(_halftone, lerpf(halftone_at_min_flow, halftone_at_max_flow, flow_t), k)
	_halftone_scale = lerpf(_halftone_scale, lerpf(halftone_scale_at_min, halftone_scale_at_max, flow_t), k)
	_outline = lerpf(_outline, lerpf(outline_at_min_flow, outline_at_max_flow, flow_t), k)

	# --- Speed: chromatic aberration tracks raw velocity, not style ----------
	var speed_ratio := 0.0
	if _vehicle and _vehicle.max_speed > 0.0:
		speed_ratio = clampf(_vehicle.get_speed() / _vehicle.max_speed, 0.0, 1.0)
	var target_ca := lerpf(aberration_idle, aberration_max, pow(speed_ratio, aberration_speed_exp))

	# Boost spike: snap CA up on activation, then ease back toward the speed-mapped
	# value over aberration_boost_decay seconds (the camera-shake equivalent for a
	# no-audio moment). Normal CA also eases at this rate, which keeps it smooth.
	var boosting := _vehicle.is_boost_active() if _vehicle else false
	if boosting and not _was_boosting:
		_ca = aberration_boost_spike
	_was_boosting = boosting
	var ease := clampf(delta / maxf(aberration_boost_decay, 0.001), 0.0, 1.0)
	_ca = lerpf(_ca, target_ca, ease)

	# --- Speed lines: same speed signal, sharper curve, capped peak ----------
	var speed_lines := pow(speed_ratio, speed_lines_exp) * speed_lines_at_top

	# --- Push overrides onto ComicPostFX (its @exports are the fallback) ------
	_fx.halftone_intensity = _halftone
	_fx.halftone_scale = _halftone_scale
	_fx.outline_intensity = _outline
	_fx.aberration_intensity = _ca
	_fx.speed_lines_intensity = speed_lines
