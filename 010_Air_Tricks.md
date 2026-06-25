# Task 010 — Air Tricks
## FLOWSTATE

---

## Goal

The "crazy moves" of the north-star clip: while airborne (off ramps, jumps, launches), the player performs predefined rotations — **barrel roll**, **flip**, **spin** — that preserve momentum, must be **landed clean**, and reward **Style + Flow**. This is M5 trick-flow verb #2 (after Drift, `009_Drift.md`; before the environmental save).

Run every decision through the pillars — especially **#1 Momentum Is Everything** (tricks never scrub speed), **#3 Easy to Learn, Hard to Master** (depth from landing-clean timing, not button count), **#4 Make Players Look Cool**.

---

## Control Scheme — Dedicated air-trick key (E / RB)

> **Decided after a feel pass (2026-06-21).** Originally shipped brake-as-modifier (reuse the idle-in-air brake, zero new binds). It failed in play: brake is pressed for other reasons, so it fired tricks unintentionally — tapping brake in the air spun the car. Replaced with a **dedicated `air_trick` key (E, gamepad RB)** that is only meaningful airborne — unambiguous, no misfires. (E was free since drift moved to brake-to-drift.) This is the one place M5 spends a new keybind, deliberately.

**While airborne (past `air_trick_min_airtime`), hold E:**
| Input combo | Trick | Rotation axis |
|-------------|-------|---------------|
| E + steer L/R | Barrel roll L/R | forward axis (`-basis.z`) |
| E + accelerate | Flip (forward) | right axis (`basis.x`) |
| E (no direction) | Spin | up axis (`basis.y`) |

Rotation is **player-driven and continuous** (rotates while E is held), so landing flat is a timing skill — not an auto-complete. This is the risk/reward that ties into the existing clean-landing system. Flips rotate slower than roll/spin (`air_trick_flip_rate` < `air_trick_rate`) — at the roll/spin speed they read as too fast.

> Which direction maps to which trick is still feel-tunable (e.g., if you habitually hold accelerate in the air, "spin" comes out as a flip).

---

## Requirements

### Functional
- While airborne + trick modifier, the car rotates around the selected axis at `air_trick_rate`.
- Rotation **accumulates** across the jump (track total degrees per axis).
- **Momentum preserved** — tricks never change velocity magnitude.
- On landing, reuse the existing landing-angle logic (`GravitySystem` contact + `clean_landing_max_dot`): landing flat after a trick = **clean** (reward); landing off-axis = **botched** (no trick bonus; optional small Flow penalty per Pillar 5 — failure costs momentum, not progress).
- Reward scales with rotation completed (e.g., per 360°) and is bigger for multi-trick combos.
- Style points credited to `ScoreSystem` (breakdown key `"air_trick"`); Flow charged once (owned by `VehiclePhysics`, like other physics-owned flow — no double-count in ScoreSystem).
- Air tricks only while `AIRBORNE`; disabled on any attached surface.

### Non-Functional
- All tuning values `@export` (rate, reward amounts, min-rotation-to-count, clean-land tolerance reuse).
- One dedicated air-only input action `air_trick` (E / RB). (Originally aimed for zero new binds via brake-as-modifier; that misfired in play — see Control Scheme.)
- Quaternion-based rotation (no euler/gimbal issues), consistent with the camera/gravity approach.
- Must not regress any existing system.

---

## Architecture (respect the boundaries in `06_Architecture.md` / CLAUDE.md)
- **`VehiclePhysics`** owns the airborne rotation (step 6 airborne branch) and tracks accumulated trick rotation for the current jump. On landing, emit a new signal `trick_landed(degrees: float, clean: bool)` (mirrors `clean_landing`). Charge trick **Flow** here.
- **`ScoreSystem`** consumes `trick_landed` → adds **Style** (breakdown `"air_trick"`). Does NOT add trick Flow (no double-count).
- **`DynamicCamera`** stays observer-only. (A trick-framing camera flourish, if any, is a later VFX/feel pass — not required for done.)
- **`GravitySystem`** is the source of truth for "airborne" and the landing contact normal — read it, don't duplicate it.

---

## Definition of Done — LOOP EXIT CONDITION (self-verifiable, no feel judgment)

The loop stops and reports when ALL of these hold:

1. **New probe `scripts/tests/_AirTrickProbe.gd` passes**, asserting:
   - a. Airborne + each trick input rotates the car around the expected axis (orientation changes measurably).
   - b. Velocity magnitude is preserved through a trick (≥ 99%).
   - c. A full 360° can be accumulated given sufficient airtime.
   - d. Landing flat after a ≥180° trick emits `trick_landed(_, true)` and adds a `"air_trick"` style entry + Flow gain.
   - e. Landing clearly off-axis after a trick emits `trick_landed(_, false)` and adds NO trick style.
   - f. No trick is possible while grounded/attached.
2. **Input:** the `air_trick` action (E / RB) is the only trick input — air-only, no ground-moveset impact. (Superseded the original "no new input action" goal after the brake-modifier feel pass.)
3. **Full existing probe suite stays green** (run every `scripts/tests/_*Probe.gd`; list any failures).
4. **All new tuning values are `@export`** (no candidate magic numbers).
5. **Docs updated**: this file's Status set to implemented; `02_GDD.md` gets an Air Tricks subsection; `CLAUDE.md` doc table + decided-choices note the verb; the `m5-trickflow-direction` memory updated.
6. **A first-pass feel is set** (sensible export defaults) but **FEEL IS NOT FINALIZED** — see below.

### Explicitly deferred to the dev's return (do NOT block the loop on these)
- Final **feel tuning** — rotation rate, which combos map to which trick, how forgiving the clean-land window is. These need a human driving (`Test_Drift.tscn` arena has ramps; reuse or extend it). The loop locks the *mechanic + probes + docs + first-pass defaults*, not the final feel.
- Comic VFX for tricks (parked `ComicPostFX`).

---

## Constants Reference (all `@export`, implemented)
### `VehiclePhysics.gd`
| Param | Default | Meaning |
|-------|---------|---------|
| `air_trick_rate` | 360.0 | deg/sec for roll & spin |
| `air_trick_flip_rate` | 240.0 | deg/sec for flips (slower — they read as too fast at the roll/spin rate) |
| `air_trick_min_degrees` | 180.0 | min accumulated rotation for a landing to count as a trick |
| `air_trick_clean_dot` | 0.8 | car-up · surface-normal at landing >= this = clean (landed upright / wheels-down) |
| `air_trick_facing_dot` | 0.5 | car-forward · travel at landing >= this = front-first; below = landed facing the wrong way (fixed front) = crash |
| `air_trick_input_threshold` | 0.3 | \|steer\| / accelerate above this selects roll / flip (else spin) |
| `air_trick_min_airtime` | 0.25 | **min continuous airtime before a trick can engage** — blocks accidental spins on tiny hops / brief airborne braking (added during impl; see Status) |
| `trick_flow_per_360` | 0.6 | Flow on a clean trick landing, per full 360° |
| `trick_crash_speed_penalty` | 0.6 | Fraction of speed lost landing on the roof after a trick (scales with how inverted; 0 disables) |
| `trick_crash_flow_penalty` | 1.0 | Flow lost on a full roof landing after a trick (scales with severity) |

### `ScoreSystem.gd`
| Param | Default | Meaning |
|-------|---------|---------|
| `air_trick_points_per_360` | 400.0 | Style on a CLEAN trick landing, per full 360° (flow owned by VehiclePhysics — no double-count) |

---

## Risks
| Risk | Mitigation |
|------|-----------|
| Trick rotation fights gravity orientation-align (VehiclePhysics step 2 snaps `basis.y` to gravity up) | While airborne mid-trick, suspend/relax the auto up-align so the player's rotation holds; re-align on landing approach. Verify in probe. |
| "Clean landing" too strict/loose → tricks never/always score | Reuse `clean_landing_max_dot`; expose a trick-specific tolerance if needed; probe both clean and botched cases. |
| Velocity drift from rotating the basis | Rotate orientation only; never rebuild velocity from the rotated basis airborne (preserve world-space velocity). Probe magnitude preservation. |
| Reintroducing a keybind | Hard requirement: grep `project.godot` for new actions in the done-check. |

---

## Status
Implemented 2026-06-21. Mechanic + probe (`scripts/tests/_AirTrickProbe.gd`, 16 checks) green; full existing suite (18 probes) green; no new keybind. **Feel is NOT finalized** — first-pass export defaults only; needs a human driving (`Test_Drift.tscn` arena has ramps to launch off — VehiclePhysics carries the mechanic so tricks work in any scene; ScoreSystem/style is wired in `Track_Prototype`).

Implementation notes / decisions made during the build:
- **`air_trick_min_airtime` (0.25s) gate added** (not in the original spec). Without it, any brief airborne moment while holding brake (e.g., the reverse probe's spawn-settle, or a tiny hop) triggered a spin — `brake-only airborne = spin`. The gate blocks micro-tricks and fixed a reverse regression. It's also a good feel default (no accidental tricks on bumps).
- **Clean = orientation at landing** (`incoming_basis_y · surface_normal >= air_trick_clean_dot`), measured before the gravity up-align re-snaps the car. Robust botched landings rely on the GravitySystem world-down fallback (below).
- **GravitySystem got a world-down ray fallback** in `_detect_surface_normal()` so a tumbling/upside-down car still detects the ground and lands (clean or botched). Additive — only reached when tilted-airborne; all gravity/loop/wall probes stay green.
- **Velocity is preserved for ALL trick axes** via a step-5 guard (feel pass). The step-5 airborne rebuild is identity only while forward stays aligned with travel (roll). For flips/spins the forward axis sweeps through the travel direction, so `signed_forward_speed` hit the reverse clamp (−18) and the rebuild *shrank* momentum (and spiked the FOV). Fix: skip the step-5 velocity rebuild entirely while `_trick_active` — orientation-only, velocity untouched except gravity. Probe checks B/B2 guard flip & spin preservation.
- **Camera calmed during tricks** (feel pass, scoped to `is_tricking()`): FOV is driven by HORIZONTAL travel speed while tricking (not `velocity.length()`, which inflates with the fall and made the FOV lurch), and the follow anchors behind the flight path (travel direction) instead of chasing the tumbling basis. The car tumbles in-frame; the camera stays steady.
- **Input went brake → dedicated E** after the first feel pass: brake-as-modifier misfired (tapping brake in the air spun the car). E is air-only and unambiguous. **Flips also got their own slower rate** (`air_trick_flip_rate` 240 vs roll/spin 360) — they read as too fast at the shared rate.
- **Landing heading after a FLIP fixed (2026-06-24).** The step-2 gravity up-align rebuilt the car's heading from `-basis.z`; after a flip past vertical that axis projects *backward* horizontally, so the car landed **facing backward** (world-space momentum was preserved, but the facing read reversed and the grounded rebuild then fought it). Fix: when re-aligning *after a trick* (`_trick_rotation_accum > 0`), derive the heading from the **direction of travel** (horizontal velocity) instead of `-basis.z`, so the car lands facing where it's moving. Gated on trick rotation, so smooth surface-following (loops, which never accrue trick rotation) is unchanged. Guarded by `_AirTrickProbe` case **G** (flip ~180° + land moving → forward·travel = 1.00, upright).
- **Orientation smoothing round (2026-06-25).** Removed the air snaps: releasing a trick mid-air used to INSTANTLY level the car using `-basis.z`, which is vertical at ~90° → collapsed to a **backward-facing snap**. Now, while airborne after a release (`_trick_rotation_accum > 0`), step 2 **slerps** toward {upright, heading = direction of travel, nose on the velocity arc} at `air_recover_rate` — smooth, never backward. Trick rotation also **ramps in** (`trick_rate_ramp`) and resets on axis change, so **spin↔flip transitions cross-fade** instead of snapping the rotation plane. Grounded facing stays instant (the velocity-realign would scrub speed if eased mid-rotation — momentum constraint); after the air recovery you land already aligned, so the common case no longer snaps on landing. (Held-trick-into-ground landings still snap the yaw instantly — a visual-only ease is the deferred follow-up if needed.)
- **Botched landing is now a CRASH — fixed front/rear (2026-06-24).** It's a car: landing on the roof/side OR facing the wrong way after a trick is not a free reset. A clean landing now requires **both** wheels-down (`incoming_basis_y · surface_normal >= air_trick_clean_dot`) **and** front-first (`incoming_forward · travel >= air_trick_facing_dot`), plus `>= air_trick_min_degrees` — i.e. you must **complete the rotation** (a 180° flip lands on the roof; a 180° spin lands rear-first; both crash; a full 360° of either lands clean). Otherwise it **bleeds momentum + Flow scaled by the WORSE of the two errors** (`trick_crash_speed_penalty` 0.6 / `trick_crash_flow_penalty` 1.0; severity 0 at the clean thresholds → 1.0 fully inverted/backward). Recovery (step 2): the car rights AND re-faces its **direction of travel** so control recovers to a drivable forward heading (Pillar 5 — failure costs momentum, not progress, doesn't strand you in reverse). This grounded recovery also covers **spins** (up unchanged, so the plain up-align used to skip them and leave the car stuck backward). Only evaluated when a trick happened, so upright slope landings don't false-trigger. Guarded by `_AirTrickProbe` **H** (180° flip → roof → 20→8), **I** (360° flip → 20→20 clean), **J** (180° spin → rear-first → 20→8, recovers forward), **K** (360° spin → 20→20 clean).

## Feel-tuning checklist (for the dev's pass)
- Drive `Test_Drift.tscn`: get airborne off a ramp, hold **E** + steer (roll) / accelerate (flip) / nothing (spin).
- Tune `air_trick_rate` (roll/spin speed), `air_trick_flip_rate` (flip speed — lowered after flips felt too fast), `air_trick_clean_dot` (upright-landing forgiveness), `air_trick_min_airtime`, and the reward amounts.
- Decide whether `E (no direction) = spin` stays or remaps; if you habitually hold accelerate in the air it comes out as a flip.
- Consider a camera stabilization / trick-framing pass if the tumble is disorienting.
