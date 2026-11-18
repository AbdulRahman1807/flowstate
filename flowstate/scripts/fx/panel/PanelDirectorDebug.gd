extends Node

# ============================================================================
#  PanelDirectorDebug — DETERMINISTIC verification scaffolding (not gameplay wiring)
# ----------------------------------------------------------------------------
#  Number keys 1..9 trigger a SPECIFIC event so one composition can be evaluated
#  repeatedly (1 drift · 2 jump · 3 landing · 4 boost · 5 wall_ride · 6 near_miss
#  · 7 tier_up · 8 crash · 9 wall_save). O pushes a multiplier tier. There is NO
#  random event generation — the compositor should never feel random. auto_stack
#  keeps the persistent stack populated so it can be judged; turn it off for full
#  manual control. Removed once real gameplay events drive the Director (Phase 6).
# ============================================================================

@export var director_path: NodePath
@export var auto_stack: bool = true        # keep pushing multiplier tiers so the stack stays visible
@export var stack_interval: float = 2.4

const EVENTS: Array[StringName] = [
	&"drift", &"jump", &"landing", &"boost", &"wall_ride", &"near_miss", &"tier_up", &"crash", &"wall_save",
]
const KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]

var _director: PanelDirector
var _mult := 1.0
var _t := 0.0


func _ready() -> void:
	_director = get_node_or_null(director_path) as PanelDirector


func _process(dt: float) -> void:
	if not auto_stack or _director == null:
		return
	_t += dt
	if _t >= stack_interval:
		_t = 0.0
		_mult += 1.0
		if _mult > 6.0:
			_mult = 2.0
		_director.push_multiplier(_mult)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo) or _director == null:
		return
	var kc: int = event.keycode
	for i in KEYS.size():
		if kc == KEYS[i]:
			_director.compose(EVENTS[i])   # deterministic, one composition at a time
			return
	if kc == KEY_O:
		_mult += 1.0
		_director.push_multiplier(_mult)
