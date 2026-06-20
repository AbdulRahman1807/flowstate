# Task 010 — Air Tricks
## FLOWSTATE

---

## Goal

The "crazy moves" of the north-star clip: while airborne (off ramps, jumps, launches), the player performs predefined rotations — **barrel roll**, **flip**, **spin** — that preserve momentum, must be **landed clean**, and reward **Style + Flow**. This is M5 trick-flow verb #2 (after Drift, `009_Drift.md`; before the environmental save).

Run every decision through the pillars — especially **#1 Momentum Is Everything** (tricks never scrub speed), **#3 Easy to Learn, Hard to Master** (depth from landing-clean timing, not button count), **#4 Make Players Look Cool**.

---

## Control Scheme — Reuse Airborne Inputs (NO new keybind)

The keybind budget is full (WASD + Space + Shift + Q). Air tricks must add **zero** new binds by repurposing inputs that are idle in the air:
- **Brake** does nothing airborne (no ground) → use it as the **trick modifier**.
- **Accelerate** does nothing airborne → free.
- **Steer** airborne currently does gentle air-yaw (air control) — keep that when the modifier is NOT held.

**While airborne + brake held (trick modifier):**
| Input combo | Trick | Rotation axis |
|-------------|-------|---------------|
| brake + steer L/R | Barrel roll L/R | forward axis (`-basis.z`) |
| brake + accelerate | Flip (forward) | right axis (`basis.x`) |
| brake only (no dir) | Spin | up axis (`basis.y`) |

Rotation is **player-driven and continuous** (rotates while held at `air_trick_rate`), so landing flat is a timing skill — not an auto-complete. This is the risk/reward that ties into the existing clean-landing system.

> This mapping is the **starting design to validate by feel** — the axes/combos are exported/structured so they can be reassigned during the dev's feel pass. Do not treat the specific combos as locked.

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
- No new input action in `project.godot`.
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
2. **`project.godot` has no new input action** (grep clean).
3. **Full existing probe suite stays green** (run every `scripts/tests/_*Probe.gd`; list any failures).
4. **All new tuning values are `@export`** (no candidate magic numbers).
5. **Docs updated**: this file's Status set to implemented; `02_GDD.md` gets an Air Tricks subsection; `CLAUDE.md` doc table + decided-choices note the verb; the `m5-trickflow-direction` memory updated.
6. **A first-pass feel is set** (sensible export defaults) but **FEEL IS NOT FINALIZED** — see below.

### Explicitly deferred to the dev's return (do NOT block the loop on these)
- Final **feel tuning** — rotation rate, which combos map to which trick, how forgiving the clean-land window is. These need a human driving (`Test_Drift.tscn` arena has ramps; reuse or extend it). The loop locks the *mechanic + probes + docs + first-pass defaults*, not the final feel.
- Comic VFX for tricks (parked `ComicPostFX`).

---

## Suggested Exports (starting values — tune by feel later)
```gdscript
# VehiclePhysics.gd
@export var air_trick_rate: float = 360.0          # deg/sec of trick rotation while held
@export var air_trick_min_degrees: float = 180.0   # min accumulated rotation for a landing to count as a trick
@export var trick_flow_per_360: float = 0.6        # Flow on a clean trick landing, per full rotation
# ScoreSystem.gd
@export var air_trick_points_per_360: float = 400.0 # Style on a clean trick landing, per full rotation
```

---

## Risks
| Risk | Mitigation |
|------|-----------|
| Trick rotation fights gravity orientation-align (VehiclePhysics step 2 snaps `basis.y` to gravity up) | While airborne mid-trick, suspend/relax the auto up-align so the player's rotation holds; re-align on landing approach. Verify in probe. |
| "Clean landing" too strict/loose → tricks never/always score | Reuse `clean_landing_max_dot`; expose a trick-specific tolerance if needed; probe both clean and botched cases. |
| Velocity drift from rotating the basis | Rotate orientation only; never rebuild velocity from the rotated basis airborne (preserve world-space velocity). Probe magnitude preservation. |
| Reintroducing a keybind | Hard requirement: grep `project.godot` for new actions in the done-check. |
