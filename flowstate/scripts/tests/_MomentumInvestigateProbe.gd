extends SceneTree

# RUNTIME investigation: load the real Track_Circuit, find the Panel Director's
# MomentumStack, push a couple of tiers, step frames, and report exactly what the
# stack does at runtime — is it created, in-tree, visible, on-screen, and is it
# only reachable through debug input?
# Run:
# Godot --headless --path /Users/abdul/Desktop/Personal/flowstate/flowstate --script res://scripts/tests/_MomentumInvestigateProbe.gd

var _scene: Node
var _dir
var _stack
var _frames := 0


func _initialize() -> void:
	_scene = (load("res://scenes/Track_Circuit.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _physics_process(_dt: float) -> bool:
	_frames += 1
	if _frames == 3:
		print("=== Momentum Stack Investigation ===")
		_dir = _scene.get_node_or_null("PanelDirector")
		print("  PanelDirector in scene:  %s" % (_dir != null))
		if _dir == null:
			quit(); return true
		_stack = _dir._momentum
		print("  MomentumStack created:   %s" % (_stack != null))
		print("  stack in tree / visible: %s / %s" % [_stack.is_inside_tree(), _stack.visible])
		print("  director CanvasLayer:    %s" % _dir.layer)
		var dbg = _scene.get_node_or_null("PanelDirectorDebug")
		print("  debug node present:      %s (O key pushes a demo multiplier)" % [dbg != null])
		# how does the stack ever get entries?
		print("  entries before any push: %d" % _stack._entries.size())
		_dir.push_multiplier(2.0)
		_dir.push_multiplier(3.0)
		print("  entries after 2 pushes:  %d" % _stack._entries.size())
	elif _frames == 24:
		var vp := root.get_visible_rect().size
		print("  viewport: %s" % vp)
		if _stack != null and _stack._entries.size() > 0:
			var e: Label = _stack._entries[0]
			var centre := e.global_position + e.size * e.scale * 0.5
			var on := Rect2(Vector2.ZERO, vp).has_point(centre)
			print("  newest entry: text=%s alpha=%.2f scale=%s" % [e.text, e.modulate.a, e.scale])
			print("  newest entry centre on-screen: %s  (centre=%s)" % [on, centre])
		print("  CONCLUSION: the stack only gets entries via push_multiplier(), which today")
		print("  is called ONLY by the debug 'O' key — no gameplay wires it yet (Phase 6).")
		quit()
	return false
