extends Node
class_name ScoreSystem

# ScoreSystem (M4 — 006_Scoring.md). Scene-level OBSERVER/COORDINATOR.
#   Score = Base Time Score x Flow Multiplier + Style Points  (02_GDD)
# implemented as CONTINUOUS accumulation so the HUD shows a live, climbing score:
#   each RUNNING frame  _score += base_rate * flow.get_multiplier() * delta
# plus flat style-event points on top.
#
# It is also the single place that translates gameplay events into the NEW flow
# triggers (gravity transfer / perfect landing / near miss / crash). FlowSystem
# stays a pure accumulator (06_Architecture) — it never subscribes to physics.
# The pre-existing flow triggers (high-speed in VehiclePhysics; wall-ride / wall-
# jump / ceiling-transition in WallRiding) keep driving flow where they already do,
# so this node must NOT also add flow for those (it would double-count).

signal on_score_changed(score: float)

@export var vehicle_path: NodePath = NodePath("../Vehicle")

# --- Score tuning ---
@export var base_rate: float = 100.0              # Time-score points per second at flow x1.0 (scaled by the flow multiplier)

# --- Style points (flat, per 006 table) ---
@export var perfect_landing_points: float = 250.0
@export var wall_ride_points_per_sec: float = 100.0
@export var drift_points_per_sec: float = 100.0   # Style points per second while drifting (flow for drift is already added by VehiclePhysics — do NOT also add flow here, per the no-double-count note above)
@export var gravity_transfer_points: float = 500.0
@export var near_miss_points: float = 150.0
@export var air_trick_points_per_360: float = 400.0   # Style on a CLEAN air-trick landing, per full 360° (flow owned by VehiclePhysics — no double-count)
@export var wall_save_points: float = 350.0           # Style on a wall save / ricochet (flow owned by WallRiding — no double-count)

# --- Flow amounts for the NEW triggers this node owns (the others live in their physics scripts) ---
@export var flow_on_perfect_landing: float = 0.8
@export var flow_on_gravity_transfer: float = 1.0
@export var flow_on_near_miss: float = 0.6

# --- Crash / near-stop flow penalty (Pillar 5: Failure Costs Momentum) ---
# Detected as fast -> near-zero, NOT a raw frame delta: the wall-attach 50->22 clamp and the
# steep-landing penalty both cause large one-frame drops that are NOT crashes, so they would
# false-trigger a delta check. A genuine smash-into-geometry leaves you near-stopped.
@export var crash_prev_speed_min: float = 20.0    # Must have been at least this fast last frame
@export var crash_now_speed_max: float = 6.0      # ...and near-stopped this frame
@export var crash_flow_penalty: float = 0.8
@export var crash_cooldown: float = 1.0           # No repeat crash penalty for this long (avoids farming while stopped)

@export var gravity_transfer_cooldown: float = 1.0  # Debounce INVERTED flicker near the dead-band

var _flow: FlowSystem
var _vehicle: VehiclePhysics
var _wall_riding: WallRiding
var _gravity: GravitySystem

var _score: float = 0.0
var _running: bool = false
var _style_breakdown: Dictionary = {}
var _max_flow_reached: float = 0.0
var _prev_speed: float = 0.0
var _crash_cd: float = 0.0
var _gt_cd: float = 0.0


func _ready() -> void:
	var vehicle := get_node_or_null(vehicle_path)
	if vehicle:
		_vehicle = vehicle as VehiclePhysics
		_flow = vehicle.get_node_or_null("FlowSystem") as FlowSystem
		_wall_riding = vehicle.get_node_or_null("WallRiding") as WallRiding
		_gravity = vehicle.get_node_or_null("GravitySystem") as GravitySystem

	if is_instance_valid(_vehicle):
		_vehicle.clean_landing.connect(_on_clean_landing)
		_vehicle.trick_landed.connect(_on_trick_landed)
	if is_instance_valid(_wall_riding):
		_wall_riding.on_near_miss.connect(_on_near_miss)
		_wall_riding.on_wall_save.connect(_on_wall_save)
	if is_instance_valid(_gravity):
		_gravity.on_state_changed.connect(_on_gravity_state_changed)


# --- Run lifecycle (called by RunManager) ---
func start_run() -> void:
	_score = 0.0
	_style_breakdown.clear()
	_max_flow_reached = 0.0
	_crash_cd = 0.0
	_gt_cd = 0.0
	_prev_speed = _vehicle.get_speed() if is_instance_valid(_vehicle) else 0.0
	_running = true
	on_score_changed.emit(_score)


func stop_run() -> void:
	_running = false


func _physics_process(delta: float) -> void:
	if not _running:
		return

	if is_instance_valid(_flow):
		_max_flow_reached = maxf(_max_flow_reached, _flow.get_value())
		# Continuous time-score, amplified by current flow.
		_score += base_rate * _flow.get_multiplier() * delta

	# Wall-ride style points accrue live while riding (flow for it is already added by WallRiding).
	if is_instance_valid(_wall_riding) and _wall_riding.is_wall_riding():
		_add_style_internal(wall_ride_points_per_sec * delta, "wall_ride")

	# Drift style points accrue live while drifting (flow for it is already added by VehiclePhysics).
	if is_instance_valid(_vehicle) and _vehicle.is_drifting():
		_add_style_internal(drift_points_per_sec * delta, "drift")

	# Crash / near-stop -> flow penalty.
	_crash_cd = maxf(_crash_cd - delta, 0.0)
	_gt_cd = maxf(_gt_cd - delta, 0.0)
	if is_instance_valid(_vehicle):
		var cur := _vehicle.get_speed()
		if _crash_cd <= 0.0 and _prev_speed > crash_prev_speed_min and cur < crash_now_speed_max:
			if is_instance_valid(_flow):
				_flow.decrease(crash_flow_penalty, "crash")
			_crash_cd = crash_cooldown
		_prev_speed = cur

	on_score_changed.emit(_score)


# --- Style API ---
func add_style(points: float, reason: String) -> void:
	if not _running:
		return
	_add_style_internal(points, reason)
	on_score_changed.emit(_score)


# Internal add WITHOUT emitting (the per-frame accumulator emits once at the end of the frame).
func _add_style_internal(points: float, reason: String) -> void:
	if points == 0.0:
		return
	_score += points
	_style_breakdown[reason] = _style_breakdown.get(reason, 0.0) + points


# --- Event handlers (only count while a run is RUNNING) ---
func _on_clean_landing(_impact: float) -> void:
	if not _running:
		return
	_add_style_internal(perfect_landing_points, "perfect_landing")
	if is_instance_valid(_flow):
		_flow.increase(flow_on_perfect_landing, "perfect_landing")
	on_score_changed.emit(_score)


# Air trick landed (VehiclePhysics owns the trick Flow; this only adds Style). Botched (off-axis)
# landings score nothing — Pillar 5: failure costs the reward opportunity, not progress.
func _on_trick_landed(degrees: float, clean: bool) -> void:
	if not _running or not clean:
		return
	_add_style_internal(air_trick_points_per_360 * (degrees / 360.0), "air_trick")
	on_score_changed.emit(_score)


func _on_near_miss() -> void:
	if not _running:
		return
	_add_style_internal(near_miss_points, "near_miss")
	if is_instance_valid(_flow):
		_flow.increase(flow_on_near_miss, "near_miss")
	on_score_changed.emit(_score)


# Wall save / ricochet (verb #3). WallRiding owns the Flow; this only adds Style.
func _on_wall_save(_speed: float, _normal: Vector3) -> void:
	if not _running:
		return
	_add_style_internal(wall_save_points, "wall_save")
	on_score_changed.emit(_score)


# Gravity transfer = reaching INVERTED (a successful flip onto a ceiling / over a loop top).
# Debounced so dead-band flicker can't farm points.
func _on_gravity_state_changed(new_state: GravitySystem.AttachmentState) -> void:
	if not _running:
		return
	if new_state != GravitySystem.AttachmentState.INVERTED:
		return
	if _gt_cd > 0.0:
		return
	_gt_cd = gravity_transfer_cooldown
	_add_style_internal(gravity_transfer_points, "gravity_transfer")
	if is_instance_valid(_flow):
		_flow.increase(flow_on_gravity_transfer, "gravity_transfer")
	on_score_changed.emit(_score)


# --- Getters ---
func get_score() -> float:
	return _score


func get_style_breakdown() -> Dictionary:
	return _style_breakdown.duplicate()


func get_max_flow_reached() -> float:
	return _max_flow_reached


func is_running() -> bool:
	return _running
