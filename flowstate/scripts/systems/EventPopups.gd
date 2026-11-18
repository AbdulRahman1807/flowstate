class_name EventPopups
extends CanvasLayer

# ============================================================================
#  EventPopups — comic onomatopoeia HUD feedback (016 Part D)
# ----------------------------------------------------------------------------
#  The "loud, poppy, comic book" layer. Passive observer: connects to gameplay
#  signals and SLAMS a styled comic SFX onto the screen near the car when
#  something cool happens. Writes nothing back to gameplay.
#
#  Each pop is: a random ONOMATOPOEIA word (from a per-event set) in a comic
#  FONT chosen by the event's feel, over a random tinted BURST shape, slammed in
#  at the car's screen position with a jaunty random tilt.
#
#  Font feel mapping (dev choice: per-event-type by feel):
#    comicy  (Bangers / KaBlam)        -> saves, loops, new-best  (the big beats)
#    bubbly  (LuckiestGuy / TitanOne)  -> tricks, clean landings  (playful)
#    sharp   (Anton / Bungee)          -> wall jumps, bails        (impact)
#    marker  (PermanentMarker)         -> near miss                (quick scrawl)
#
#  Layer 50: above the 3D scene + PlayHUD (10), below ComicPostFX (100) so the
#  post pass inks the text too.
# ============================================================================

const COL_CYAN := Color(0.0, 1.0, 0.8)
const COL_MAGENTA := Color(1.0, 0.18, 0.47)
const COL_YELLOW := Color(0.91, 1.0, 0.0)
const COL_WHITE := Color(1, 1, 1)
const COL_OUTLINE := Color(0, 0, 0, 0.9)

const FONT_DIR := "res://assets/fonts/"
const SFX_DIR := "res://assets/textures/sfx/"

@export var vehicle_path: NodePath
@export var wall_riding_path: NodePath
@export var run_manager_path: NodePath
@export var score_system_path: NodePath
@export var gravity_system_path: NodePath

@export_group("Onomatopoeia Word Sets")
@export var words_save: PackedStringArray = ["SKRRRT!", "CLUTCH!", "FWISH!", "SKREEE!", "NICE SAVE!"]
@export var words_wall_jump: PackedStringArray = ["SPRANG!", "BOING!", "KA-KICK!", "BWAMP!"]
@export var words_near_miss: PackedStringArray = ["WHOOSH!", "VWIP!", "SWISH!", "WHIFF!", "YIKES!"]
@export var words_clean: PackedStringArray = ["THUNK!", "STICK!", "STOMP!", "SOLID!"]
@export var words_trick_big: PackedStringArray = ["WHIRL!", "ZWOOSH!", "WOWZA!", "STYLIN'!", "RAAAD!"]
@export var words_trick_small: PackedStringArray = ["ZIP!", "TWIRL!", "SLICK!", "NICE!"]
@export var words_bail: PackedStringArray = ["WIPEOUT!", "OOF!", "WHUMP!", "BONK!", "CRUNCH!"]
@export var words_loop: PackedStringArray = ["WHEEE!", "VWOOOM!", "WHOA-OA!", "ZOOM!"]
@export var words_new_best: PackedStringArray = ["KAPOW!", "KABLAM!", "BOOM!", "RECORD!"]

@export_group("Comic Placement")
@export var car_offset: Vector2 = Vector2(0, -110)    ## base screen offset from the car (negative y = above it; higher so big pops clear the car)
@export var spread: Vector2 = Vector2(170, 90)        ## random ± offset around the base point (the scatter)
@export_range(0.0, 45.0) var max_tilt_deg: float = 9.0   ## small jaunty rotation each pop gets (calm — satisfying, not chaotic)
@export var size_scale: float = 2.0                   ## global multiplier on every pop's font size (much larger)
@export var burst_scale: float = 1.4                  ## burst size relative to the word (a halo/frame, not a screen-filler)
@export_range(0.0, 1.0) var burst_alpha: float = 0.8  ## burst opacity — a soft SAME-colour bloom behind the word (cohesive)
@export_range(0.1, 0.5) var outline_ratio: float = 0.3 ## word outline thickness as a fraction of font size (bold)
@export var shadow_enabled: bool = true               ## dark drop shadow behind the word (comic depth)
@export var shadow_offset_ratio: float = 0.06         ## drop-shadow offset as a fraction of font size
@export var shadow_color: Color = Color(0, 0, 0, 0.8) ## DARK drop shadow — depth without a clashing colour (keeps the 04 palette cohesive)
@export var slam_duration: float = 0.08
@export var hold_duration: float = 0.70
@export var fade_duration: float = 0.25
@export var rise_pixels: float = 22.0
@export var max_popups: int = 5
@export var enabled: bool = true

var _vehicle: VehiclePhysics
var _wall_riding: WallRiding
var _run_manager
var _score
var _gravity

# Fonts (loaded once), by feel.
var _f_bangers: Font
var _f_kablam: Font
var _f_luckiest: Font
var _f_titan: Font
var _f_anton: Font
var _f_bungee: Font
var _f_marker: Font
var _bursts: Array[Texture2D] = []

var _active: Array[Control] = []


func _ready() -> void:
	layer = 50

	_f_bangers = _load_font("Bangers.ttf")
	_f_kablam = _load_font("KaBlam.ttf")
	_f_luckiest = _load_font("LuckiestGuy.ttf")
	_f_titan = _load_font("TitanOne.ttf")
	_f_anton = _load_font("Anton.ttf")
	_f_bungee = _load_font("Bungee.ttf")
	_f_marker = _load_font("PermanentMarker.ttf")
	for n in ["burst_star", "burst_splat", "burst_speed", "burst_jagged", "burst_zap"]:
		var t := load(SFX_DIR + n + ".png") as Texture2D
		if t:
			_bursts.append(t)

	_vehicle = get_node_or_null(vehicle_path) as VehiclePhysics
	_wall_riding = get_node_or_null(wall_riding_path) as WallRiding
	_run_manager = get_node_or_null(run_manager_path)
	_score = get_node_or_null(score_system_path)
	_gravity = get_node_or_null(gravity_system_path)

	if _wall_riding:
		_wall_riding.on_wall_save.connect(_on_wall_save)
		_wall_riding.on_wall_jump.connect(_on_wall_jump)
		_wall_riding.on_near_miss.connect(_on_near_miss)
	if _vehicle:
		_vehicle.trick_landed.connect(_on_trick_landed)
		_vehicle.clean_landing.connect(_on_clean_landing)
	if _gravity:
		_gravity.on_state_changed.connect(_on_gravity_state_changed)
	if _run_manager and _run_manager.has_signal("on_run_finished"):
		_run_manager.on_run_finished.connect(_on_run_finished)


# --- event handlers (font/colour/size chosen by feel) ----------------------

func _on_wall_save(_speed: float, _normal: Vector3) -> void:
	_spawn(words_save, _f_bangers, COL_YELLOW, 88)          # comicy / hero beat

func _on_wall_jump(_speed: float) -> void:
	_spawn(words_wall_jump, _f_bungee, COL_MAGENTA, 60)     # sharp / blocky kick

func _on_near_miss() -> void:
	_spawn(words_near_miss, _f_marker, COL_YELLOW, 52)      # marker scrawl

func _on_clean_landing(_impact: float) -> void:
	_spawn(words_clean, _f_titan, COL_WHITE, 48)            # bubbly / satisfying

func _on_trick_landed(degrees: float, clean: bool) -> void:
	if not clean:
		_spawn(words_bail, _f_anton, Color(1, 1, 1, 0.7), 52)   # sharp / crash
		return
	if degrees >= 360.0:
		var pts := int(round(_air_trick_points_per_360() * (degrees / 360.0)))
		_spawn(words_trick_big, _f_luckiest, COL_CYAN, 76, "  +%d" % pts)
	else:
		_spawn(words_trick_small, _f_luckiest, COL_CYAN, 56)

func _on_gravity_state_changed(new_state) -> void:
	if new_state == GravitySystem.AttachmentState.INVERTED:
		_spawn(words_loop, _f_kablam, COL_CYAN, 60)         # comicy

func _on_run_finished(_score_value: float, _time: float) -> void:
	if _run_manager and _run_manager.has_method("was_last_run_best") and _run_manager.was_last_run_best():
		_spawn_center(words_new_best, _f_bangers, COL_YELLOW, 100, 1.5)


# --- spawn / lifecycle -----------------------------------------------------

func _spawn(words: PackedStringArray, font: Font, color: Color, font_size: int, suffix: String = "") -> void:
	if not enabled or words.is_empty():
		return
	while _active.size() >= max_popups:
		_begin_exit(_active.pop_front())

	var text := words[randi() % words.size()] + suffix
	var pop := _make_pop(text, font, color, font_size)
	var bsize: Vector2 = pop.get_meta("popsize")
	var base := _car_screen_pos() + car_offset
	var scatter := Vector2(randf_range(-spread.x, spread.x), randf_range(-spread.y, spread.y))
	pop.position = base + scatter - bsize * 0.5
	pop.rotation_degrees = randf_range(-max_tilt_deg, max_tilt_deg)
	add_child(pop)
	_active.append(pop)

	pop.scale = Vector2(1.9, 1.9)
	var tw := create_tween()
	tw.tween_property(pop, "scale", Vector2.ONE, slam_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_interval(hold_duration)
	tw.tween_callback(func() -> void:
		_active.erase(pop)
		_begin_exit(pop))


func _spawn_center(words: PackedStringArray, font: Font, color: Color, font_size: int, hold: float) -> void:
	if not enabled or words.is_empty():
		return
	var text := words[randi() % words.size()]
	var pop := _make_pop(text, font, color, font_size)
	var bsize: Vector2 = pop.get_meta("popsize")
	var vp := get_viewport().get_visible_rect().size
	pop.position = vp * Vector2(0.5, 0.4) - bsize * 0.5
	add_child(pop)

	pop.scale = Vector2(2.2, 2.2)
	var tw := create_tween()
	tw.tween_property(pop, "scale", Vector2.ONE, slam_duration * 1.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_interval(hold)
	tw.tween_property(pop, "modulate:a", 0.0, fade_duration * 1.5)
	tw.tween_callback(func() -> void:
		if is_instance_valid(pop):
			pop.queue_free())


# Build a pop: a random tinted burst behind the worded label, grouped under one
# Control sized to the burst (so scale/rotation pivot about its centre).
func _make_pop(text: String, font: Font, color: Color, font_size_in: int) -> Control:
	var font_size := int(round(font_size_in * size_scale))
	var f := font if font != null else ThemeDB.fallback_font
	var tsize := _text_size(text, f, font_size)
	var side := maxf(tsize.x, tsize.y) * burst_scale
	var bsize := Vector2(side, side)
	var label_pos := (bsize - tsize) * 0.5

	var pop := Control.new()
	pop.size = bsize
	pop.pivot_offset = bsize * 0.5
	pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pop.set_meta("popsize", bsize)

	# Burst behind = a soft SAME-colour bloom (the pop is one cohesive hue — 04 palette).
	if not _bursts.is_empty():
		var burst := TextureRect.new()
		burst.texture = _bursts[randi() % _bursts.size()]
		burst.modulate = Color(color.r, color.g, color.b, burst_alpha)
		burst.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		burst.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		burst.size = bsize
		burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pop.add_child(burst)

	# Dark drop shadow (comic depth + legibility), no clashing colour.
	if shadow_enabled:
		var shadow := _label(text, f, font_size, shadow_color, false)
		shadow.size = tsize
		shadow.position = label_pos + Vector2(font_size, font_size) * shadow_offset_ratio
		pop.add_child(shadow)

	# The word itself, in the event's colour, thick dark outline for legibility.
	var label := _label(text, f, font_size, color, true)
	label.size = tsize
	label.position = label_pos
	pop.add_child(label)
	return pop


func _label(text: String, font: Font, font_size: int, color: Color, outline: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if outline:
		l.add_theme_constant_override("outline_size", maxi(8, int(font_size * outline_ratio)))
		l.add_theme_color_override("font_outline_color", COL_OUTLINE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _begin_exit(pop: Control) -> void:
	if not is_instance_valid(pop) or bool(pop.get_meta("dying", false)):
		return
	pop.set_meta("dying", true)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(pop, "modulate:a", 0.0, fade_duration)
	tw.tween_property(pop, "position:y", pop.position.y - rise_pixels, fade_duration)
	tw.chain().tween_callback(func() -> void:
		if is_instance_valid(pop):
			pop.queue_free())


# Project the car to screen so pops appear at the action. Falls back to lower-centre.
func _car_screen_pos() -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_3d()
	if cam and is_instance_valid(_vehicle) and not cam.is_position_behind(_vehicle.global_position):
		return cam.unproject_position(_vehicle.global_position)
	return vp * Vector2(0.5, 0.6)


func _text_size(text: String, font: Font, font_size: int) -> Vector2:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size) + Vector2(0.0, float(font_size) * 0.35)


func _load_font(file_name: String) -> Font:
	var f := load(FONT_DIR + file_name) as Font
	if f == null:
		push_warning("EventPopups: font not found: %s — falling back to default." % file_name)
	return f


func _air_trick_points_per_360() -> float:
	if _score:
		var v = _score.get("air_trick_points_per_360")
		if v != null:
			return float(v)
	return 400.0
