# 006 — Scoring: FlowSystem (full) + ScoreSystem

**Status:** Implemented (M4, 2026-06-19) — code + probe-verified, pending dev drive-test. **Refs:** 02_GDD (Flow + Score System), 03_Design_Pillars (Style Matters, Failure Costs Momentum). **Plan:** `M4_PLAN.md`.

> **Impl note:** the NEW flow triggers (gravity-transfer / perfect-landing / near-miss) and the crash flow-loss are driven by **ScoreSystem**, not by FlowSystem subscribing to physics — FlowSystem stays a pure accumulator (06_Architecture). Crash detection is **near-stop** (fast→~0), not raw frame-delta, so the wall-attach 50→22 clamp and steep-landing penalty don't false-trigger. Gravity transfer = entering INVERTED (debounced). Perfect landing = new `VehiclePhysics.clean_landing`. Verified by `_FlowScoreProbe.gd`.

## FlowSystem — promote stub → full
Already exists (`scripts/systems/FlowSystem.gd`): `increase(amount, reason)`, `decrease(amount, reason)`, `get_multiplier() → float`, signal `on_changed(value)`, passive `flow_decay_rate` decay, value `0..max_flow` (5).

**Wire ALL triggers (02_GDD §Flow):**
- **Increases** (✓ = already wired): high-speed grounded ✓ (VehiclePhysics), wall-ride/sec ✓, wall-jump ✓, ceiling transition ✓ (WallRiding). ADD: **gravity transfer** (GROUNDED↔INVERTED) via `GravitySystem.on_state_changed` (debounced); **perfect landing** (NEW — see below); near-miss ✓ (WallRiding).
- **Decreases (NEW):** crash into geometry, speed drop / near-stop, unintentional fall (on respawn). For prototype, detect crash + speed-drop in ScoreSystem/FlowSystem by watching a large frame-over-frame speed loss (no new physics signal needed); fall penalty comes from `RunManager.on_respawn`.

**Perfect-landing signal (NEW, small VehiclePhysics change):** `landed(impact)` currently carries no landing *quality*. Either extend to `landed(impact, retention)` or add a `clean_landing` signal emitted when the landing-angle penalty ≈ 0 (`landing_dot < ~0.25`). FlowSystem + ScoreSystem consume it. (The penalty math already exists in VehiclePhysics step 10.)

**Tune** increase/decrease magnitudes + decay so flow feels *earned* and *fairly lost* (Pillar 5). Keep `get_multiplier()` = `1.0 + value/max_flow` (1.0–2.0) initially; widen later if a max run should feel more amplified.

**Exports:** every trigger amount (per-second + per-event), `flow_decay_rate`, `max_flow`, multiplier scale.

## ScoreSystem (NEW node, scene-level)
`Score = Base Time Score × Flow Multiplier + Style Points` (02_GDD), implemented as **continuous accumulation** so the HUD shows a live, climbing score:
- Each RUNNING frame: `_score += base_rate * flow_system.get_multiplier() * delta`.
- Style events add flat points on top.

**Style points (exported values, 02_GDD):**
| Event | When | Source signal |
|---|---|---|
| Perfect Landing | clean landing | new `clean_landing` (above) |
| Wall Ride | per second riding | `WallRiding.is_wall_riding()` in `_process`, or accumulate from attach→detach |
| Gravity Transfer | per transfer | `GravitySystem.on_state_changed` → GROUNDED/INVERTED (debounce) |
| Near Miss | per event | `WallRiding.on_near_miss` |

**Interface:** `start_run()` (reset score + breakdown), `add_style(points, reason)`, `get_score() → float`, `get_style_breakdown() → Dictionary`, signal `on_score_changed(score)`. Reads `FlowSystem.get_multiplier()`. Connects to the style signals above. RunManager calls `start_run()` on run start and reads `get_score()` at finish.

**Exports:** `base_rate`, `perfect_landing_points`, `wall_ride_points_per_sec`, `gravity_transfer_points`, `near_miss_points`.

## Exit
A run accumulates a live score that visibly rises with speed + flow + style and where flow drops on crashes. Tuned so a *stylish* run clearly out-scores a clean-but-flat run (Pillar 2: Style Matters — "the coolest run is not always the fastest").
