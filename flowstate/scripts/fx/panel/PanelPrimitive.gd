class_name PanelPrimitive
extends Control

# ============================================================================
#  PanelPrimitive — base class for every composable comic primitive
# ----------------------------------------------------------------------------
#  A primitive renders ITSELF and knows NOTHING about other primitives. It only
#  ever receives:
#    - its semantic config (configure(), once)
#    - a base placement within the composition (place_center(), once)
#    - the shared MotionState + ActionVector each frame (apply())
#  Its apply() adds only SECONDARY motion (offsets) on top of the master that the
#  Composition applies to the whole graphic. Primitives never reference siblings;
#  the Composition assembles them into a coherent graphic.
# ============================================================================

var _base_center: Vector2 = Vector2.ZERO   # frozen layout position (composition-local)


# Build content + set size from semantic config. Override.
func configure(_config: Dictionary) -> void:
	pass


# The Composition assigns the frozen base centre (composition-local). Called once.
func place_center(center: Vector2) -> void:
	_base_center = center
	pivot_offset = size * 0.5
	position = center - size * 0.5


# Per frame: derive secondary motion from the shared state (+ re-attach to the
# Action Vector). Override. Default rides the master with no secondary motion.
func apply(_state: MotionState, _av: ActionVector) -> void:
	_apply_local()


# Helper: place the primitive at its base centre + a secondary offset / rotation /
# alpha / scale (all LOCAL — they compose with the master the Composition applies).
func _apply_local(offset: Vector2 = Vector2.ZERO, rot: float = 0.0, alpha: float = 1.0, sc: float = 1.0) -> void:
	pivot_offset = size * 0.5
	position = _base_center + offset - size * 0.5
	rotation = rot
	modulate.a = alpha
	scale = Vector2(sc, sc)
