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
| `010_Air_Tricks.md` | Air tricks spec (M5 trick-flow verb #2) — roll/flip/spin, implemented + probe-green, dev feel-confirmed |
| `011_Wall_Save.md` | Wall save / ricochet spec (M5 trick-flow verb #3, the "save" north star) — implemented + probe-green, dev feel-confirmed |
| `012_Replay_Ghost.md` | Ghost replay + session personal best spec (M5 MVP-validation tail) — implemented + probe-green (deterministic, inputs-only) |
| `013_Vehicle_Art.md` | Vehicle visual design — mesh sourcing (Blender MCP / CC0 / primitives), materials, `VehicleVisuals.gd` speed-reactive emissives |
| `014_Track_Visual_Baseline.md` | Dark environment + emissive cyan edge lines — substrate for VFX pass; CircuitBuilder/PlaygroundBuilder material overhaul |
| `015_Audio_Scratch.md` | Scratch audio system — `VehicleAudio.gd`, synthesised tones via AudioStreamGenerator, all signal hookpoints |
| `016_VFX_Pass.md` | Full VFX pass — ComicPostFX wiring, `ComicPostFXDriver` Flow/speed reactivity, speed lines shader, `EventPopups` comic onomatopoeia HUD |

---

## Running the Project

This is a **Godot 4.6** project located in the `flowstate/` subdirectory. Open it in the Godot editor:

```
godot --editor flowstate/project.godot
```

**`scenes/Track_Circuit.tscn` (M5) is the main scene + the proper directional course** — a long (~1.4k units, 10 checkpoints) clearly-channelled start→finish track (continuous side barriers + forward arrow chevrons so the racing line is unmistakable). Built by `CircuitBuilder.gd` with a cursor (a `Transform3D` advanced piece by piece, so everything chains at any heading); sections: speed straights, sweeping turns, launch humps (air), drift chicanes, two real 360° **LOOPS** (`_real_loop` — jump into the circle to ride it fully inverted at speed, then drive out; the pure vertical circle drives perfectly, and the low front/back slabs that would block the entry are CUT so you launch in and roll out under the cut front — no re-loop), wall-ride walls, wall-to-wall **HOP corridors**, and wall-jump-across-**GAP** sections, ending in a finish plaza. Recovery floor is sized to the course bounds after layout. Wired with the full run loop (`RunManager`/`ScoreSystem`/`PlayHUD`), a START/READY screen, an end-of-run summary, and ghost replay + personal best. (`scenes/Track_Prototype.tscn` is the older M4 track.) Individual system test scenes live in `scenes/tests/`:

- `Test_GroundMovement.tscn` — flat track for movement/steering validation
- `Test_GravityTransition.tscn` — **M2 verification:** a smooth floor→wall→ceiling half-loop (built procedurally by `M2TransitionBuilder.gd`, single seamless ribbon, 005 Phase-1 continuous-follow — drive in fast and it carries you up the wall and onto the inverted ceiling). Recovery floor below. Verified by `_M2Probe.gd`.
- `Test_CameraResponse.tscn` — camera behaviour with debug overlay
- `Test_WallRiding.tscn` — wall riding and detachment
- `Test_Drift.tscn` — 96×96 drift arena (perimeter walls, pillars, ramps) for drift + air-trick feel
- `Test_Playground.tscn` — **big free-roam moveset bed:** effectively-infinite floor + ramp garden, quarter-pipe kicker, wall-ride wall, wall-hop corridor, floor→wall→ceiling half-loop, pillar slalom (built by `PlaygroundBuilder.gd`). Debug overlay shows drift / air-trick / last-trick / flow. Use this to exercise the whole moveset. **Has a `RunManager` (M5):** auto-starts on throttle; **R** teleports you to spawn and races the **ghost of your last run** (free-roam ghost — no finish line needed; `012_Replay_Ghost.md`).

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

**The grounded car comes to a TRUE stop.** Drag is multiplicative (`signed_forward_speed *= 1 - drag*delta`), so it only *asymptotes* toward zero — the car would coast forever at a minute speed. `stop_speed_threshold` (1.0 m/s) snaps a sub-threshold coast to zero when grounded with no throttle/brake and not drifting. (Gated to coasting only, so it never blocks brake-to-reverse passing through 0.) A replaying ghost likewise stops dead at the end of its recording.

**Drift is brake-to-drift — no dedicated drift key.** Holding `brake` while steering hard (`brake > drift_brake_threshold` and `|steer| > drift_steer_threshold`) at speed initiates a slide instead of slowing; the old `drift` input action (E / RB) was removed from `project.godot`. While `_is_drifting`, the brake's deceleration/reverse is suppressed so the drift preserves momentum (Pillar 1) — brake only slows/reverses when NOT drifting (steer below threshold). Do not re-add a separate drift button. (`MovementIntent.drift` remains only as a programmatic/explicit override; no input is wired to it.) Full spec: `009_Drift.md`.

**Air tricks use a dedicated air-only key (`air_trick` = E / RB).** While AIRBORNE (and past `air_trick_min_airtime`): E+steer = barrel roll, E+accelerate = flip, E alone = spin. (Brake-as-modifier was tried first and removed — brake is pressed for other reasons, so it misfired tricks in the air.) Rotation is **orientation-only** — never rebuild velocity from the rotated basis (momentum preserved). The gravity up-align (VehiclePhysics step 2) is **suspended while a trick rotates**, else it snaps the car upright every frame. Flips use a slower `air_trick_flip_rate`. Clean landing = car upright vs surface at touchdown (`air_trick_clean_dot`) → `trick_landed(degrees, clean)` → Flow (VehiclePhysics) + Style (ScoreSystem, no double-count). `GravitySystem._detect_surface_normal()` has a **world-down ray fallback** so a tumbling car still lands. Full spec: `010_Air_Tricks.md`.

**Wall save / ricochet reuses the wall button — no dedicated save key (verb #3, "the save").** Pressing `wall_attach` (Q / LB) is routed in `VehiclePhysics` step 9: detach if riding, else ride a glancing wall (`_try_attach_to_wall`), **else `_try_wall_save(steer)`** off an oncoming wall you'd have crashed into. The save **deflects/skims along the wall preserving speed magnitude**, kept HORIZONTAL with only a small `wall_save_pop` up (converting speed into the up-the-wall tangent rocketed the car straight up — rejected). Button-initiated only (never auto-detected — respects wall riding v2.0). Detection is a dedicated `WallSensor.find_wall_for_save()` (oncoming wall, `wall_save_min_approach`, `wall_save_range`) decoupled from the sustain range (a save doesn't attach). Reward: Flow (`flow_on_wall_save`, owned by WallRiding) + flat Style (`wall_save_points`, ScoreSystem, no double-count) → `on_wall_save`. Full spec: `011_Wall_Save.md`.

**Replay records inputs only**, not positions. Playback reruns physics from the same starting state. **Implemented (M5):** `ReplayRecorder` / `ReplayData` capture the per-frame `MovementIntent`; the ghost is a runtime `duplicate()` of the vehicle whose `VehicleController` replays the stream (`set_replay`) — deterministic (probe end-drift 0.0), `collision_layer = 0` so it follows the track but is invisible to the player / run Area3Ds, camera + VFX stripped. `RunManager` keeps a **session** personal best (in-memory — no persistence, per `01_PRD`) and spawns a ghost each run (best run if you've finished one, else your last run — so free-roam scenes with no finish line still replay); `PlayHUD` shows BEST / NEW BEST. A ghost **stops dead** at the end of its recording (velocity zeroed, no further intents → frozen where the run ended), never coasting on. Full spec: `012_Replay_Ghost.md`.

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

**Now on M5 — reframed.** M4 proved the scoring *loop* works, but the core *execution* wasn't fun yet (dev: "track too simple AND moveset too simple"), so M5 is: **deepen the moveset + environment until stylish trick-flow is pullable → then validate → then the comic VFX.** North star = **"the save"** (turn a near-crash into your coolest move). Full plan + session pickup point: the `m5_trickflow_direction` memory.

**Moveset deepening DONE + dev feel-confirmed (2026-06-23).** All three trick-flow verbs are implemented and probe-green — **drift** (verb #1, `009`), **air tricks** roll/flip/spin (verb #2, `010`), **wall save / ricochet** (verb #3, `011`, the "save" north star) — plus the `Test_Playground` moveset bed. 19 probes green. Dev drive-tested the moveset and confirmed it **feels good** (the reframed-M5 "is stylish trick-flow pullable/fun?" check is dev-satisfied).

**M5 validation loop now BUILT (2026-06-23).** Ghost replay + session personal best are implemented + probe-green (`012_Replay_Ghost.md`): deterministic inputs-only replay, race-your-best-run ghost, BEST / ★ NEW BEST ★ on the HUD. Camera landing-impact (DynamicCamera dip) and style events (ScoreSystem) were already done. So **every implementable M5 build task is complete — 21 probes green.** The ONLY remaining M5 items are not code I can close: **(1) the VFX pass — deliberately dev-parked and reframe-sequenced LAST** (comic `ComicPostFX` + disabled `WallVFX`; see `vfx_sources`) — the dev's timing call; and **(2) the human exit gate** — `07_Roadmap` requires an EXTERNAL tester (not the dev) to voluntarily restart + a replay moment that genuinely excites. Build side of M5 = done; what's left is a playtest + the VFX go/no-go.

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
