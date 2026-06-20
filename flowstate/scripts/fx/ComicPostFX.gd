class_name ComicPostFX
extends CanvasLayer

# ============================================================================
#  ComicPostFX — screen-space comic / Spider-Verse post-processing layer
# ----------------------------------------------------------------------------
#  Reusable, fully-tunable drop-in. A high-layer CanvasLayer holding one
#  full-rect ColorRect that runs comic_post_fx.gdshader over hint_screen_texture.
#  This script mirrors EVERY shader uniform as an @export (per the project's
#  "all tuning values are exported" ethos) and pushes them to the shader live,
#  so the dev tunes the whole look in the inspector while the scene runs.
#
#  Additive only: it reads the rendered frame and writes its own ColorRect.
#  It touches no physics, camera, or gameplay system.
#
#  READABILITY FIRST (04_Art_Direction: VFX must never make the track harder to
#  read). Defaults are deliberately subtle. The two effects most able to smother
#  the track — halftone dots and ink outline — default low/shadow-biased. To go
#  fully clean for a side-by-side, set master_mix = 0.0 (exact bypass) or toggle
#  the per-effect booleans below.
#
#  HOW TO TOGGLE EACH EFFECT:
#    - Per effect: untick its `*_on` bool (forces that effect's intensity to 0).
#    - Whole pass: untick `enabled`, or set `master_mix = 0.0`.
#  Both are live in the inspector at runtime.
# ============================================================================

const SHADER_PATH := "res://shaders/comic_post_fx.gdshader"

# --- master ----------------------------------------------------------------
@export var enabled: bool = true                     ## Master switch for the whole pass.
@export_range(0.0, 1.0) var master_mix: float = 1.0  ## Global wet/dry. 0.0 = exact raw-frame bypass.

@export_group("Posterize + Saturation")
@export var posterize_on: bool = true
@export_range(0.0, 1.0) var posterize_intensity: float = 0.6   ## Blend toward cel colour banding.
@export_range(2.0, 16.0) var posterize_levels: float = 6.0     ## Colour steps per channel (low = chunkier).
@export_range(0.0, 2.0) var saturation_boost: float = 0.35     ## Extra saturation, no muddy midtones.

@export_group("Halftone / Ben-Day Dots")
@export var halftone_on: bool = true
@export_range(0.0, 1.0) var halftone_intensity: float = 0.18   ## Dot strength. Kept low for readability.
@export_range(20.0, 400.0) var halftone_scale: float = 140.0   ## Dots across the screen (higher = finer).
@export_range(0.0, 1.5708) var halftone_angle: float = 0.4     ## Dot-grid rotation (radians).
@export var halftone_color: Color = Color(0.05, 0.05, 0.08)    ## Ink colour of the dots.
@export_range(0.0, 1.0) var halftone_shadow_bias: float = 0.7  ## 1.0 = dots only in shadows (keeps track clear).

@export_group("Ink Edge Outline")
@export var outline_on: bool = true
@export_range(0.0, 1.0) var outline_intensity: float = 0.5     ## How strongly ink darkens edges.
@export_range(0.5, 4.0) var outline_thickness: float = 1.2     ## Sobel sample spread, in pixels.
@export_range(0.0, 1.0) var outline_threshold: float = 0.18    ## Ignore edge response below this (denoise).
@export var outline_color: Color = Color(0.02, 0.02, 0.04)     ## Ink colour (near-black, cool tint).

@export_group("Chromatic Aberration")
@export var aberration_on: bool = true
@export_range(0.0, 1.0) var aberration_intensity: float = 0.25 ## Master strength of the RGB split.
@export_range(0.0, 8.0) var aberration_amount: float = 1.6     ## Max channel offset at screen edge, in pixels.
@export_range(0.5, 4.0) var aberration_edge_falloff: float = 2.0 ## >1 keeps centre clean, splits edges only.

var _rect: ColorRect
var _mat: ShaderMaterial

func _ready() -> void:
	# High layer so it composites on top of the 3D view but stays below debug HUD
	# layers if those are pushed higher. 100 per the FX layer convention.
	layer = 100

	_mat = ShaderMaterial.new()
	var shader := load(SHADER_PATH) as Shader
	if shader == null:
		push_error("ComicPostFX: could not load shader at %s" % SHADER_PATH)
		return
	_mat.shader = shader

	_rect = ColorRect.new()
	_rect.name = "ComicPostFXRect"
	# Full-rect: stretch to cover the whole viewport at any resolution.
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.material = _mat
	# The shader ignores the rect's own colour (it samples the screen), but the
	# rect must not eat input meant for gameplay / UI underneath it.
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color(0, 0, 0, 0)
	add_child(_rect)

	_push_all()

# Pushing every frame keeps inspector edits live while the scene runs. This is a
# handful of uniform writes — negligible cost, and it is what lets the dev tune.
func _process(_delta: float) -> void:
	_push_all()

func _push_all() -> void:
	if _mat == null:
		return

	visible = enabled
	if not enabled:
		return

	_mat.set_shader_parameter("master_mix", master_mix)

	# Per-effect bools gate intensity to 0 without disturbing the dev's tuned
	# values, so re-enabling restores the exact prior look.
	_mat.set_shader_parameter("posterize_intensity", posterize_intensity if posterize_on else 0.0)
	_mat.set_shader_parameter("posterize_levels", posterize_levels)
	_mat.set_shader_parameter("saturation_boost", saturation_boost if posterize_on else 0.0)

	_mat.set_shader_parameter("halftone_intensity", halftone_intensity if halftone_on else 0.0)
	_mat.set_shader_parameter("halftone_scale", halftone_scale)
	_mat.set_shader_parameter("halftone_angle", halftone_angle)
	_mat.set_shader_parameter("halftone_color", halftone_color)
	_mat.set_shader_parameter("halftone_shadow_bias", halftone_shadow_bias)

	_mat.set_shader_parameter("outline_intensity", outline_intensity if outline_on else 0.0)
	_mat.set_shader_parameter("outline_thickness", outline_thickness)
	_mat.set_shader_parameter("outline_threshold", outline_threshold)
	_mat.set_shader_parameter("outline_color", outline_color)

	_mat.set_shader_parameter("aberration_intensity", aberration_intensity if aberration_on else 0.0)
	_mat.set_shader_parameter("aberration_amount", aberration_amount)
	_mat.set_shader_parameter("aberration_edge_falloff", aberration_edge_falloff)
