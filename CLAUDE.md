# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Documentation Is the Source of Truth

All `.md` files in the project root are authoritative design and architecture documents. **The code must not deviate from them without explicit approval from the developer.** Before implementing anything, verify it is consistent with the relevant spec doc. If a decision conflicts with a document, surface the conflict and ask — do not resolve it silently.

| Doc | Authority |
|-----|-----------|
| `01_PRD.md` | What gets built and what is explicitly out of scope |
| `02_GDD.md` | Mechanics, systems, flow/score rules |
| `03_Design_Pillars.md` | Decision filter — run every proposal through all five pillars |
| `04_Art_Direction.md` | Visual identity and speed feedback approach |
| `05_Technical_Requirements.md` | Engine, performance targets, physics requirements |
| `06_Architecture.md` | System responsibilities and interface contracts |
| `07_Roadmap.md` | Milestone gates — nothing downstream gets built until the gate before it passes |
| `08_Movement_Feel_Targets.md` | Quantitative tuning targets for all movement parameters |
| `001_Movement_Prototype.md` | Full spec for ground movement implementation |
| `002_Dynamic_Camera.md` | Full spec for DynamicCamera implementation |
| `003_Gravity_System.md` | Full spec for GravitySystem implementation |
| `004_Wall_Riding.md` | Full spec for wall riding (v2.0, button-initiated) |
| `005_Surface_Following.md` | Continuous surface following (Phase 1 implemented; Phase 2 centrifugal opt-in) |
| `009_Drift.md` | Brake-to-drift spec (M5 trick-flow verb #1) — implemented, dev feel-confirmed |

---

## Running the Project

This is a **Godot 4.6** project located in the `flowstate/` subdirectory. Open it in the Godot editor:

```
godot --editor flowstate/project.godot
```

The main scene is `scenes/Track_Prototype.tscn`. Individual system test scenes live in `scenes/tests/`:

- `Test_GroundMovement.tscn` — flat track for movement/steering validation
- `Test_GravityTransition.tscn` — **M2 verification:** a smooth floor→wall→ceiling half-loop (built procedurally by `M2TransitionBuilder.gd`, single seamless ribbon, 005 Phase-1 continuous-follow — drive in fast and it carries you up the wall and onto the inverted ceiling). Recovery floor below. Verified by `_M2Probe.gd`.
- `Test_CameraResponse.tscn` — camera behaviour with debug overlay
- `Test_WallRiding.tscn` — wall riding and detachment

**Physics engine:** Jolt Physics (set in `project.godot`). Default world gravity is `0.0` — gravity is fully managed by `GravitySystem.gd`.

---

## Architecture

### System Responsibilities (strict — do not cross these boundaries)

```
Input → [VehicleController] → MovementIntent → [VehiclePhysics]
                                                      ↑
                                 [GravitySystem]  owns gravity vector, surface normal, attachment state
                                 [WallRiding]     notifies GravitySystem via request_wall_attach()
                                 [WallSensor]     scan-on-demand only, no per-frame state
                                 [DynamicCamera]  reads vehicle + GravitySystem, writes nothing
                                 [FlowSystem]     stateless accumulator, emits on_changed signal
```

**VehicleController** — reads raw input, builds `MovementIntent`. No physics logic. No knowledge of walls or gravity.

**VehiclePhysics** — applies velocity and position changes from `MovementIntent` + current gravity/surface from `GravitySystem`. Most-iterated script. Keep its interface narrow so it can be rewritten without touching other systems.

**GravitySystem** — owns `AttachmentState` (`GROUNDED`, `WALL_LEFT`, `WALL_RIGHT`, `INVERTED`, `AIRBORNE`), the current gravity vector, and the current surface normal. **Continuously follows the surface *under* the car** (from the `move_and_slide` contact normal, down-ray fallback) at any tilt — this is how `GROUNDED`/`INVERTED` are reached, including loops and curved ceilings (see `005_Surface_Following.md`). It auto-attaches from air only on floor/ceiling-ish surfaces (`attach_init_dot`) and sustains only across gradual normal rotation, so sharp standalone walls are *not* auto-grabbed. `WALL_LEFT`/`WALL_RIGHT` are reachable only via `request_wall_attach(normal)` (button) — never via auto-detection. Detach from tilted/inverted surfaces is a forgiving tilt-scaled hold-speed (Phase 1); centrifugal adhesion is opt-in Phase 2. Emits `on_state_changed` on every transition. Exposes `get_applied_gravity()` (Seam 2) so VehiclePhysics applies one gravity vector regardless of phase.

**WallRiding (v2.0)** — attachment is **button-initiated** (`wall_attach` = Q / Left Bumper), not automatic. On first press: calls `WallSensor.find_best_wall()`, then `gravity_system.request_wall_attach(normal)`. On second press: `try_wall_detach()` — wall jump if `speed >= 8.0`, clean release otherwise. The only automatic detach trigger is speed dropping below `detach_speed_threshold` (4.0 m/s).

**WallSensor** — runs only on button press. Casts a cone of 8 rays (±45° around velocity direction), scores candidates by `approach_dot * 0.7 + (1.0 - distance_norm) * 0.3`, returns the best hit within 4.0 units. Maintains no per-frame state.

**DynamicCamera** — observes vehicle velocity/orientation and `GravitySystem` state. Must use quaternion slerp (not euler angles / `look_at()`) to support arbitrary up-direction without gimbal lock. `camera_up` is driven by `GravitySystem` output.

**FlowSystem** — interface: `increase(amount, reason)`, `decrease(amount, reason)`, `get_multiplier() → float`, signal `on_changed(new_value)`. Knows nothing about physics or cameras.

**WallVFX** — passive observer (writes nothing, like DynamicCamera). The general movement-impact VFX consumer (name is historical). Connects to `WallRiding` (`on_wall_attach` / `on_wall_jump` / `on_wall_detach` / `on_near_miss`) **and** `VehiclePhysics` (`landed` / `jumped`), and throws additive soft-glow spark bursts — white-hot core → `04_Art_Direction` palette halo (cyan/magenta/acid-yellow), gravity arc — for wall attach/ride/jump/cancel, ground jump, and land. Wall-jump is de-duped against its detach; soft landings below `land_min_impact` don't pop. Placeholder (M3); full inky/halftone comic pass is M5. Wired into `Test_WallRiding` + `Track_Prototype`.

### Communication Rules

- **Synchronous per-frame data:** direct method calls (e.g. camera reads vehicle speed)
- **State changes:** signals (`FlowSystem.on_changed`, `GravitySystem.on_state_changed`, `WallRiding.on_wall_attach / on_wall_detach / on_wall_jump`)
- **No global event bus at prototype stage**

---

## Key Decided Implementation Choices

These are not up for re-evaluation without flagging it first.

**Wall riding is v2.0 (button-initiated).** The old auto-commit path in GravitySystem that watched slide collisions was removed. See `004_Wall_Riding.md` §"Removed from v1.0" for the full list of removed patterns — do not reintroduce them.

**Jolt Physics, world gravity disabled.** `3d/default_gravity=0.0` in `project.godot`. All gravity is applied manually in `VehiclePhysics` using the vector from `GravitySystem`. Do not re-enable engine gravity.

**Custom physics layer over `CharacterBody3D` + `move_and_slide()`.** Standard `RigidBody3D` is not used. Surface transition requirements cannot be met with default rigid body behaviour.

**Gravity lerps, never snaps.** `current_gravity = current_gravity.lerp(target_gravity, delta * gravity_transition_speed)`. An instant gravity change is never acceptable.

**Velocity magnitude is preserved through surface transitions.** Speed is never destroyed by a state change — only direction rotates.

**Ground steering realigns velocity to facing.** After each steer rotation, horizontal velocity direction snaps to vehicle forward (`-transform.basis.z`) while preserving speed magnitude. Realignment is grounded-only; airborne velocity is not realigned.

**Boost is disabled while reversing** (`signed_forward_speed < -0.5`) **and while attached to a wall or ceiling** (only fires when GROUNDED or AIRBORNE) — boosting on a wall flings the launch unpredictably high.

**Wall-ride speed is capped to `wall_ride_speed_cap` (= 22), not `max_speed`.** While in a WALL state, velocity is clamped each frame so a fast or boosted entry can't fling the jump-off. This cap is deliberately decoupled from ground `max_speed`: the jump-off preserves up-the-wall momentum, so it must stay bounded even when ground top speed is high (raising `max_speed` to 50 re-broke the floaty jump-off until this was decoupled). Keeps wall jump-offs consistent.

**Drift is brake-to-drift — no dedicated drift key.** Holding `brake` while steering hard (`brake > drift_brake_threshold` and `|steer| > drift_steer_threshold`) at speed initiates a slide instead of slowing; the old `drift` input action (E / RB) was removed from `project.godot`. While `_is_drifting`, the brake's deceleration/reverse is suppressed so the drift preserves momentum (Pillar 1) — brake only slows/reverses when NOT drifting (steer below threshold). Do not re-add a separate drift button. (`MovementIntent.drift` remains only as a programmatic/explicit override; no input is wired to it.) Full spec: `009_Drift.md`.

**Replay records inputs only**, not positions. Playback reruns physics from the same starting state.

---

## All Physics Parameters Must Be Exported

Every tuning value must be an `@export var`. No hardcoded constants that are candidates for adjustment. Minimum exported sets are defined in each task doc — refer to `001_Movement_Prototype.md`, `002_Dynamic_Camera.md`, `003_Gravity_System.md`, and `004_Wall_Riding.md` §"Constants Reference".

---

## Design Pillars (Decision Filter)

Run every proposal through these. Two or more failures = cut it.

1. **Momentum Is Everything** — does this help players gain/preserve momentum, or slow them for a non-skill reason?
2. **Style Matters** — does this make impressive moments more rewarding, or flatten outcomes?
3. **Easy to Learn, Hard to Master** — is complexity from execution depth, or system complexity?
4. **Make Players Look Cool** — would this moment look good in a clip?
5. **Failure Costs Momentum, Not Progress** — does this failure make the player try again, or put the controller down?

---

## Current Milestone

```
[ M0 Foundation ] → [ M1 Ground ] → [ M2 Gravity ] → [ M3 Walls ] → [ M4 Full Run ] → [ M5 Validated ]
                                                                          ↑
                                                              M0–M4 done — now on M5
```

M0–M4 are done. **M4 closed 2026-06-19** — Flow + Score + RunManager + HUD + first track built and dev-validated (incl. the end-of-run screen); wall jump-off feel fixed (sideways + float) and the flow economy rebalanced; import clean, 16/16 probes green. (Plan was `M4_PLAN.md`; task specs `006_Scoring.md`, `007_Run_Lifecycle.md`, `008_HUD.md`.)

**Now on M5 — reframed.** M4 proved the scoring *loop* works, but the core *execution* isn't fun yet (dev: "track too simple AND moveset too simple"), so M5 is: **deepen the moveset + environment until stylish trick-flow is pullable → then validate → then the comic VFX.** North star = **"the save"** (turn a near-crash into your coolest move). **Starting with DRIFT, feel-first.** Full plan + session pickup point: the `m5_trickflow_direction` memory. (Comic VFX `ComicPostFX` stays parked; see `vfx_sources`.)

---

## Explicitly Out of Scope (Prototype Stage)

Do not design for, reference in code, or add scaffolding for:

- Scene management / screen transitions
- Save/load or settings systems
- Audio manager
- Achievement / progression systems
- Any network layer or backend
- Multiple vehicles, vehicle stats, or upgrades
- Track editor or procedural generation
- Global leaderboards or cloud saves
- Mobile platform support
