class_name PanelGrammar
extends RefCounted

# ============================================================================
#  PanelGrammar — the semantic vocabulary of the Comic Compositor
# ----------------------------------------------------------------------------
#  These enums describe MEANING (what a maneuver IS), never appearance. Recipes
#  use only this vocabulary; the Panel Director maps it to the visual grammar
#  (action vector, tokens, layout, motion). Keeping the vocabulary here — apart
#  from both recipes and rendering — is what stops rendering logic leaking into
#  recipes over time.
# ============================================================================

# The KIND of maneuver — drives how the Action Vector is derived from car state.
enum Family { SLIDE, LAUNCH, IMPACT, WALL, DANGER, THRUST, REWARD, FAULT }

# Emotional class — maps to tokens (accent hue, type voice) in a later phase.
enum Category { STYLE, IMPACT, REWARD, DANGER, HEAT, FAILURE }

# Semantic emphasis (importance) — maps to the hierarchy (scale/primitives/duration).
enum Tier { WHISPER, BEAT, HERO, CLIMAX }

# Word + multiplier merge styles (Phase 3).
enum Lockup { SUFFIX, STACKED, BADGE }

# Which burst-shape MEANING fits the event (Phase 5 picks the actual texture).
enum BackingFamily { STAR, SPLAT, SPEED, JAGGED, ZAP }
