# Task 009 — Drift
## FLOWSTATE

---

## Goal

Give the player a momentum-preserving slide: while turning hard at speed, the car breaks rear traction and slides at a slip angle, holding (not scrubbing) speed, charging Flow and Style, then snaps back to facing on release. Drift is the first M5 trick-flow verb — it delivers the *"drift off into the distance"* exit and lets you weave through tight geometry without losing speed.

This is a **deliberate, controllable** drift (not the "emerges naturally" stance the GDD originally took for M1 — see `02_GDD.md` Movement Systems › Drift).

---

## Control Scheme — Brake-to-Drift (DECIDED)

There is **no dedicated drift button.** Drift is initiated by holding **brake** while steering hard at forward speed:

```
drift active  ⇔  brake > drift_brake_threshold
              AND |steer| > drift_steer_threshold
              AND grounded AND not on a wall/ceiling
              AND velocity.dot(forward) >= drift_min_speed   (SIGNED forward speed)
```

Rationale (the keybind count was getting high — WASD + Space + Shift + Q + a drift key):
- Reuses inputs the player is already holding (brake + a committed turn). Universal racing muscle memory.
- Mirrors how reverse already works (`001_Movement_Prototype.md`: "same brake input — no separate key").
- Works identically on keyboard (S/↓ + A/D ←/→) and gamepad (left trigger + stick).

The old `drift` input action (E / RB) was **removed** from `project.godot`. `MovementIntent.drift` survives only as a programmatic/explicit override (used by probes); no input is wired to it.

---

## Requirements

### Functional
- Holding brake + hard steer at forward speed initiates a slide (slip angle builds toward a steady state).
- **Speed is preserved** while drifting — the brake's normal deceleration/reverse is *suppressed* during drift.
- Extra steering authority while drifting (`drift_steer_mult`) so the car can rotate into and hold the slide.
- Releasing the drift (release brake, or straighten below the steer threshold) **snaps velocity back to facing** at the current speed — no momentum lost.
- Drift charges **Flow** while active + steering.
- Drift accrues **Style** points while active (shown in the run's style breakdown).
- Drift is **forward-motion only** — it must never engage while reversing.
- Drift never engages while attached to a wall or ceiling.

### Non-Functional
- All tuning values are `@export` (see Constants Reference).
- No frame-snapping — slip builds and releases smoothly.
- Must not regress reverse, ground steering, wall riding, or the gravity/loop systems (see probe suite).

---

## Acceptance Criteria

| Criteria | How to Test |
|----------|-------------|
| Slip angle builds while drifting | `_DriftProbe.gd`: slip_angle > 5° after holding brake+steer at speed (grip-dependent: ~22° at grip 3.0, ~35° at grip 1.8) |
| Speed is preserved | `_DriftProbe.gd`: speed ≥ 60% of pre-drift speed (currently ~88%) |
| Flow charges during drift | `_DriftProbe.gd`: flow gained > 0.05 over the drift |
| Velocity snaps to facing on release | `_DriftProbe.gd`: alignment angle < 10° a few frames after release (currently ~0.4°) |
| Reverse + steer does NOT drift | `_ReverseProbe.gd` reaches −max_reverse_speed; backing up while turning builds clean reverse, never flips forward |
| Style credited for drift | `ScoreSystem` style breakdown contains a `"drift"` entry after drifting in a run |
| No new keybind | `project.godot` has no `drift` input action |

---

## Implementation Notes

### The Jolt re-alignment bypass (critical)
Jolt's `CharacterVirtual` runs an automatic physics step **between** frames that re-aligns `velocity` to the character's facing — which would erase the lateral drift before the next frame uses it. Workaround in `VehiclePhysics`:
- `_drift_vel_xz: Vector2` stores the intended world-space XZ velocity **after** the step-6 grip lerp.
- At the start of step 5 next frame, restore `velocity.x/z` from `_drift_vel_xz` (overriding Jolt's re-alignment).

### Per-frame flow (apply_intent)
- Step 6: rotate facing by `intent.steer * drift_steer_mult` (extra authority), then `velocity = velocity.lerp(forward * speed, drift_grip_rate * delta)` — partial grip toward the new facing (preserves magnitude), then save `_drift_vel_xz`.
- Step 4: brake deceleration/reverse is gated `if intent.brake > 0.0 and not _is_drifting` — this is what preserves momentum.
- Release (`was_drifting and not _is_drifting`): `velocity = forward * velocity.length()` — snap to facing at current speed.

### Signed forward-speed gate (do not "simplify")
The speed gate MUST use **`velocity.dot(forward)`** (signed forward speed), not `velocity.length()`. With unsigned length, holding brake+steer to reverse-and-turn tripped drift once reverse speed passed `drift_min_speed`, and the grip lerp flipped the backward velocity toward facing → reverse/forward oscillation.

### Signals & accessors
- `signal drift_started`, `signal drift_ended` (emitted on transition).
- `func is_drifting() -> bool` — read by `ScoreSystem` (style) and `DynamicCamera` (travel-follow).

### Camera
While `is_drifting()`, `DynamicCamera` blends the follow-behind direction toward the **direction of travel** (velocity) instead of the hard-yawing car facing (`drift_travel_follow`), so the camera stays steady on where you're heading and the car slides sideways in frame. (Camera is observer-only — `002_Dynamic_Camera.md`.)

### Scoring (no double-count)
- **Flow** is owned by `VehiclePhysics` (`drift_flow_per_second`). `ScoreSystem` must NOT also add drift flow (`06_Architecture` / ScoreSystem header: physics-owned flow triggers are not re-added here).
- **Style** is owned by `ScoreSystem` (`drift_points_per_sec`), accrued live while `is_drifting()`, mirroring wall-ride.

---

## Constants Reference (all `@export`)

### `VehiclePhysics.gd`
| Param | Default | Meaning |
|-------|---------|---------|
| `drift_steer_mult` | 1.4 | Extra steering authority while drifting |
| `drift_grip_rate` | 3.0 | How fast velocity re-aligns toward facing (higher = tighter/less slip; 0 = ice). Dev-tuned from 1.8. |
| `drift_min_speed` | 8.0 | Minimum **forward** speed to enter/sustain drift |
| `drift_flow_per_second` | 1.0 | Flow per second while drifting + steering |
| `drift_brake_threshold` | 0.5 | Brake input above this (with steer) initiates drift |
| `drift_steer_threshold` | 0.3 | `|steer|` above this (with brake) initiates drift |

### `ScoreSystem.gd`
| Param | Default | Meaning |
|-------|---------|---------|
| `drift_points_per_sec` | 100.0 | Style points per second while drifting |

### `DynamicCamera.gd`
| Param | Default | Meaning |
|-------|---------|---------|
| `drift_travel_follow` | 1.0 | Blend of follow-direction toward travel vs facing during drift (0 = facing, 1 = travel) |

---

## Test Assets
- `scenes/tests/Test_Drift.tscn` + `scripts/tests/DriftPlaygroundBuilder.gd` — 96×96 arena (perimeter walls, pillars, diagonal walls, ramps) for feel-testing.
- `scripts/tests/_DriftProbe.gd` — headless regression probe (speed preserved, slip angle, flow, snap-on-release).

---

## Status
Implemented and dev feel-confirmed (2026-06-20). Brake-to-drift, reverse oscillation fixed, camera travel-follow, Flow + Style wired. Probe suite green.

## Future Considerations
*Not in this task.*
- Drift-boost / charge-and-release payoff (Mario-Kart-style mini-turbo) could be explored after the other M5 verbs.
- Comic VFX for the slide is part of the parked `ComicPostFX` pass (M5 VFX), not here.
