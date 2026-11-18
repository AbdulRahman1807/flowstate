extends SceneTree

# Headless guard for EventPopups (016 Part D). Verifies the comic-SFX assets load
# and the spawn path builds a pop without error: the 7 feel fonts + 5 burst
# textures resolve, and calling each event handler creates a tinted-burst + worded
# label Control (exercises get_string_size with the real fonts + the TextureRect).
# Built in _initialize, tested in the first _physics_process (tree live, _ready ran).
# Run:
# Godot --headless --path /Users/abdul/Desktop/Personal/flowstate/flowstate --script res://scripts/tests/_EventPopupProbe.gd

var _ep
var _done := false


func _initialize() -> void:
	var world := Node.new()
	world.name = "World"
	root.add_child(world)
	_ep = EventPopups.new()
	_ep.name = "EventPopups"
	world.add_child(_ep)   # _ready loads fonts + bursts (deferred until the tree is live)


func _physics_process(_delta: float) -> bool:
	if _done:
		return true
	_done = true

	print("=== EventPopups Probe ===")
	var fonts_ok: bool = (_ep._f_bangers != null and _ep._f_kablam != null and _ep._f_luckiest != null
		and _ep._f_titan != null and _ep._f_anton != null and _ep._f_bungee != null and _ep._f_marker != null)
	print("  [%s] all 7 fonts loaded" % ("OK" if fonts_ok else "XX"))
	var bursts_ok: bool = _ep._bursts.size() == 5
	print("  [%s] bursts loaded: %d / 5" % ["OK" if bursts_ok else "XX", _ep._bursts.size()])

	# Fire each spawn path; count the pop Controls created.
	var before: int = _ep.get_child_count()
	_ep._on_clean_landing(10.0)
	_ep._on_wall_save(20.0, Vector3.UP)
	_ep._on_near_miss()
	_ep._on_trick_landed(720.0, true)    # big clean trick (+pts)
	_ep._on_trick_landed(180.0, false)   # bail
	_ep._on_wall_jump(15.0)
	var made: int = _ep.get_child_count() - before
	var spawned_ok: bool = made >= 5
	print("  [%s] pops created from handlers: %d" % ["OK" if spawned_ok else "XX", made])

	var ok: bool = fonts_ok and bursts_ok and spawned_ok
	print("RESULT: %s" % ("PASS (all checks green)" if ok else "FAIL"))
	return true
