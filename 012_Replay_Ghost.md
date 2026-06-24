# Task 012 — Ghost Replay + Personal Best
## FLOWSTATE

---

## Goal

Let the player race a **ghost of their best run** and review what they pulled off — the payoff the PRD's vision and success-metric #3 hang on (*"a replay makes them say 'I cannot believe I actually did that'"*). The replay is **inputs only**: it records the per-physics-frame `MovementIntent` stream and re-simulates it, never storing positions (`05_Technical_Requirements.md` §Replay, `06_Architecture.md` `ReplayRecorder`, CLAUDE.md decided-choice). A **session personal best** (in-memory — the prototype has no persistence, `01_PRD.md` constraint) gives the player a target to beat.

This is the M5 "MVP Validation" tail that makes the validation loop runnable: **Build Speed → Execute Chains → Finish → Review Score → beat your Ghost/PB → Restart.**

---

## Scope

**In:**
- Record the player's input stream per physics frame during a run.
- Re-simulate that input on a translucent **ghost vehicle** alongside the next run (race-your-best-run).
- Track the session **personal best** score + its replay; show BEST / ★ NEW BEST ★ on the HUD.

**Out (unchanged non-goals):** persistence to disk, replay *sharing*, ghost *leaderboards*, a cinematic replay-camera mode (`01_PRD.md` Non-Goals, `07_Roadmap.md` Post-Validation, `002_Dynamic_Camera.md:143`). All deliberately deferred past validation.

---

## How It Works

### Recording (inputs only)
`VehicleController` builds a `MovementIntent` each frame. When `RunManager` has assigned it a `ReplayRecorder`, the controller snapshots that intent into the recorder **before** `apply_intent` mutates it (step 9 clears `wall_attach`). `MovementIntent.clone()` makes the snapshot immutable.

### Playback (the ghost)
A ghost is a runtime `duplicate()` of the player vehicle whose `VehicleController` is put in **replay mode** (`set_replay(ReplayData)`): instead of reading `Input`, it feeds the recorded intents to `apply_intent` frame-for-frame. Because it re-runs the same physics from the same start state at a fixed tick, the trajectory reproduces **deterministically** (probe: end-drift `0.0000`). The ghost:
- has its `Camera3D` (the `current` view camera) and `WallVFX` stripped,
- is set to `collision_layer = 0` / `collision_mask = player's` — it follows the **same track geometry** but is invisible to the player, to raycasts, and to the run Area3Ds (so it can't deflect the player or trip start/finish/checkpoints),
- gets a translucent emissive (`ghost_color` / `ghost_alpha`) material,
- coasts on a neutral intent past the end of the recording (emits `replay_finished`).

### Personal best (session) + which ghost you race
On finish, `RunManager` stops the recording, tags it with the run's score/time, and if it beats the stored best, keeps it as `_best_replay`. **Which ghost spawns next run:** your **best** run if you've finished one, **else your last run** (`_last_replay`, captured on restart). The last-run fallback is what lets free-roam scenes with **no finish line** (e.g. `Test_Playground`) replay at all — drive, press **R**, race the run you just drove. All in-memory.

---

## Architecture

| Piece | Role |
|-------|------|
| `ReplayData.gd` (`RefCounted`) | The recording: `frames: Array[MovementIntent]` + `start_transform` + `start_velocity` + meta `score`/`time`. Inputs only. |
| `ReplayRecorder.gd` (`RefCounted`) | `start_recording(xform, vel)` / `record_frame(intent)` / `stop_recording() -> ReplayData`. Owned by `RunManager`. |
| `VehicleController` | Records live intents (when a recorder is set); or, as a ghost, replays a `ReplayData` instead of reading `Input`. New: `replay_recorder`, `set_replay()`, `is_replaying()`, `replay_finished`. |
| `RunManager` | Wires the recorder into the player controller; records each run; keeps the session best; spawns/frees the ghost. New: `_spawn_ghost()`, `has_best()`, `get_best_score()`, `was_last_run_best()`. |
| `PlayHUD` | Observer-only: shows `BEST n` (top-right) and `★ NEW BEST ★` / standing best on the summary. |

Boundaries respected: `RunManager` still only writes the vehicle on respawn/restart + (now) spawns a sibling ghost; `PlayHUD` writes nothing to gameplay; `FlowSystem`/`ScoreSystem` are untouched (the ghost has no scene-level listeners, so it never scores).

---

## Determinism & Known Limits
- Re-simulation is deterministic given identical start state + inputs + fixed physics tick (verified end-drift `0.0000`).
- A recorded run that included a **respawn** (fell off, teleported) won't reproduce past that point — the teleport isn't in the input stream. Best runs (the ones that become the ghost) generally don't fall; documented as a prototype limit.
- Ghost spawning is **defensive**: any failure is swallowed so it can never break the run loop (the ghost is a layer on top).

---

## Constants Reference (all `@export`)

### `RunManager.gd`
| Param | Default | Meaning |
|-------|---------|---------|
| `enable_ghost` | true | Spawn the best-run ghost on each run |
| `ghost_color` | cyan `(0,1,0.8)` | Ghost tint (04 palette) |
| `ghost_alpha` | 0.35 | Ghost translucency |

---

## Test Assets
- `scripts/tests/_ReplayProbe.gd` — determinism + recorder round-trip: drives a scripted run, records it, replays it on an identical vehicle, asserts the end matches (drift `< 0.5`, actual `0.0`) and the recording survived the clone.
- `scripts/tests/_GhostSpawnProbe.gd` — real `Track_Prototype`: forces begin → finish → restart and asserts a correctly-configured `GhostVehicle` spawns (replaying, camera/VFX stripped, `collision_layer = 0`) and simulates without error.
- `scripts/tests/_PlaygroundReplayProbe.gd` — real `Test_Playground` (no finish line): restarting captures + races the ghost of your last run (the free-roam path).

---

## Status
Implemented + probe-green (2026-06-23). Ghost replay deterministic, session personal best + HUD wired. Closes the M5 "Ghost replay operational" + "Local personal best stored" tasks (`07_Roadmap.md`).

## Future Considerations
*Not in this task.* Persisted best/replay, ghost leaderboards, replay sharing, and a cinematic replay-camera are all post-validation (deferred). The comic VFX over a replay is the parked `ComicPostFX` pass.
