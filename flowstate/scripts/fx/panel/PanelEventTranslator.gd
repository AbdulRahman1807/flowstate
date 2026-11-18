class_name PanelEventTranslator
extends Node

# ============================================================================
#  PanelEventTranslator — the semantic translation layer (Phase 6)
# ----------------------------------------------------------------------------
#  The ONLY bridge between gameplay and the comic compositor. It listens to
#  gameplay signals and translates them into SEMANTIC event ids that it hands
#  to the Panel Director. Gameplay never composes graphics and never knows
#  about words / fonts / bursts / recipes; the Director only ever receives event
#  ids. The compositor stays fully data-driven.
#
#  6A wired core movement (drift/jump/landing/boost). 6B adds the rest:
#  wall ride / wall jump / near miss / wall save (WallRiding), air-trick
#  landings — clean -> "trick", botched -> "crash" (VehiclePhysics), discrete
#  Flow tiers -> "tier_up" + the MomentumStack, and "new_best" (RunManager).
# ============================================================================

@export var vehicle_path: NodePath
@export var director_path: NodePath
@export var wall_riding_path: NodePath
@export var flow_system_path: NodePath
@export var run_manager_path: NodePath
@export var landing_min_impact: float = 5.0   # ignore tiny suspension corrections / spawn settle
@export var event_cooldown: float = 0.25       # per-event anti-spam / dedup

var _vehicle: Node
var _director: PanelDirector
var _flow: Node
var _was_boosting := false
var _last_emit: Dictionary = {}   # event_id -> time (s)

# A landing is held for one frame so a trick/crash judgment (emitted right after
# `landed` in the same physics step) can claim the moment — one composition per
# landing, and the trick verdict wins over the generic slam.
var _pending_landing: float = -1.0
var _landing_claimed := false

# Discrete Flow tier (floor of the raw 0..max_flow value). Crossing UP a tier is
# a composable reward moment + feeds the persistent MomentumStack.
var _flow_tier: int = 0


func _ready() -> void:
	var v := get_node_or_null(vehicle_path)
	var d := get_node_or_null(director_path) as PanelDirector
	if v != null and d != null:
		init(v, d)
	var wr := get_node_or_null(wall_riding_path)
	if wr != null:
		init_wall_riding(wr)
	var fl := get_node_or_null(flow_system_path)
	if fl != null:
		init_flow(fl)
	var rm := get_node_or_null(run_manager_path)
	if rm != null:
		init_run_manager(rm)


# Wire the gameplay signals -> semantic handlers. (Direct injection for tests.)
func init(vehicle: Node, director: PanelDirector) -> void:
	_vehicle = vehicle
	_director = director
	if _vehicle.has_signal("drift_started"):
		_vehicle.drift_started.connect(_on_drift)
	if _vehicle.has_signal("jumped"):
		_vehicle.jumped.connect(_on_jump)
	if _vehicle.has_signal("landed"):
		_vehicle.landed.connect(_on_land)
	if _vehicle.has_signal("trick_landed"):
		_vehicle.trick_landed.connect(_on_trick_landed)


func init_wall_riding(wall_riding: Node) -> void:
	if wall_riding.has_signal("on_wall_attach"):
		wall_riding.on_wall_attach.connect(_on_wall_attach)
	if wall_riding.has_signal("on_wall_jump"):
		wall_riding.on_wall_jump.connect(_on_wall_jump)
	if wall_riding.has_signal("on_near_miss"):
		wall_riding.on_near_miss.connect(_on_near_miss)
	if wall_riding.has_signal("on_wall_save"):
		wall_riding.on_wall_save.connect(_on_wall_save)


func init_flow(flow: Node) -> void:
	_flow = flow
	if _flow.has_signal("on_changed"):
		_flow.on_changed.connect(_on_flow_changed)


func init_run_manager(run_manager: Node) -> void:
	if run_manager.has_signal("on_run_finished"):
		run_manager.on_run_finished.connect(_on_run_finished.bind(run_manager))


func _process(_dt: float) -> void:
	# Release a landing held from the previous physics step — unless a trick or
	# crash composition already claimed that touchdown.
	if _pending_landing >= 0.0:
		if not _landing_claimed:
			_emit(&"landing", {"impact": _pending_landing})
		_pending_landing = -1.0
		_landing_claimed = false
	# Boost has no signal — detect the false->true activation transition (fires once).
	if _vehicle == null or not _vehicle.has_method("is_boost_active"):
		return
	var boosting: bool = _vehicle.is_boost_active()
	if boosting and not _was_boosting:
		_emit(&"boost")
	_was_boosting = boosting


func _on_drift() -> void:
	_emit(&"drift")


func _on_jump(_direction: Vector3) -> void:
	_emit(&"jump")


func _on_land(impact_velocity: float) -> void:
	if impact_velocity >= landing_min_impact:   # only meaningful airtime, not tiny corrections
		_pending_landing = impact_velocity
		_landing_claimed = false


func _on_trick_landed(degrees: float, clean: bool) -> void:
	_landing_claimed = true   # the trick verdict IS this landing's composition
	if clean:
		_emit(&"trick", {"degrees": degrees})
	else:
		_emit(&"crash", {"degrees": degrees})


func _on_wall_attach(_entry_speed: float, _wall_normal: Vector3) -> void:
	_emit(&"wall_ride")


func _on_wall_jump(_speed_at_jump: float) -> void:
	_emit(&"jump")


func _on_near_miss() -> void:
	_emit(&"near_miss")


func _on_wall_save(_speed: float, _wall_normal: Vector3) -> void:
	_emit(&"wall_save")


# Continuous Flow -> discrete tiers. Crossing UP a tier composes "tier_up" and
# pushes the current score multiplier onto the persistent MomentumStack; dropping
# just lowers the baseline silently (losing flow is punishment enough).
func _on_flow_changed(new_value: float) -> void:
	var tier := int(floorf(new_value))
	if tier > _flow_tier:
		_flow_tier = tier
		_emit(&"tier_up", {"tier": tier})
		if _director != null and _flow != null and _flow.has_method("get_multiplier"):
			_director.push_multiplier(_flow.get_multiplier())
	elif tier < _flow_tier:
		_flow_tier = tier


func _on_run_finished(_score: float, _time: float, run_manager: Node) -> void:
	if run_manager.has_method("was_last_run_best") and run_manager.was_last_run_best():
		_emit(&"new_best")


# Translate + dispatch a semantic event (cooldown-guarded), then let the Director compose.
func _emit(event_id: StringName, context: Dictionary = {}) -> void:
	var now := float(Time.get_ticks_msec()) / 1000.0
	if float(_last_emit.get(event_id, -999.0)) + event_cooldown > now:
		return
	_last_emit[event_id] = now
	if _director != null:
		_director.compose(event_id, context)
