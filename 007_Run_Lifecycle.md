# 007 — Run Lifecycle (RunManager)

**Status:** Implemented (M4, 2026-06-19) — code + probe-verified, pending dev drive-test. **Refs:** 02_GDD (Core Loop, Failure States), 07_Roadmap M4, 03_Design_Pillars (Failure Costs Momentum, Not Progress). **Plan:** `M4_PLAN.md`.

> **Impl note:** markers are built procedurally in `TrackBuilder` (groups `start_line`/`finish_line`/`checkpoints`, checkpoint order via a `checkpoint_index` meta); RunManager collects them by group (deferred so build order doesn't matter) and filters `body_entered` for the vehicle. Off-world detection uses the **y-threshold** path (`global_position.y < respawn_y_threshold`); no separate KillZone Area3D (the spec's "or"). Respawn forward speed = `max_speed * respawn_speed_factor`. Verified by `_RunManagerProbe.gd`.

## RunManager (NEW node, scene-level)
Owns the run state machine, the timer, and respawn/restart. Reads the vehicle transform; writes it **only** on respawn/restart. Pure coordinator — no physics changes.

**States:** `READY → RUNNING → FINISHED`.
- **Start:** vehicle crosses the **start line** (Area3D) — or auto-start on first throttle input. → RUNNING; start timer; `ScoreSystem.start_run()`; reset FlowSystem; `emit on_run_started`.
- **Finish:** vehicle crosses the **finish line** (Area3D). → FINISHED; stop timer; `emit on_run_finished(get_score(), time)` (HUD shows the summary).
- **Timer:** elapsed run seconds — feeds the HUD and (optionally) a completion bonus.

**Checkpoints:** ordered checkpoint Area3Ds (group `checkpoints`); entering one records `last_checkpoint`; `emit on_checkpoint(index)`.

**Respawn on track exit (02_GDD Failure States):** detect falling off the world — `vehicle.global_position.y < respawn_y_threshold` (below the recovery floor) **or** an off-track KillZone Area3D. → move the vehicle to `last_checkpoint` (or start) at **reduced speed** (`respawn_speed_factor`), zero the airborne velocity, `FlowSystem.decrease(...)` (penalty). **Not** a run reset — the timer keeps running. `emit on_respawn`.

**Restart:** input action `restart` (bind R / gamepad Start) → reset vehicle to start, timer = 0, reset FlowSystem + ScoreSystem → RUNNING. Always available, never forced (Pillar 5: restart feels like an opportunity).

**Replay note:** replay records inputs only (CLAUDE.md decided choice). Ghost/replay playback is **M5**, not built here — restart just resets live state.

**Interface / signals:** `on_run_started`, `on_run_finished(score, time)`, `on_checkpoint(index)`, `on_respawn`. Reads `ScoreSystem.get_score()`.

**Exports:** `respawn_y_threshold`, `respawn_speed_factor` (e.g. 0.4), start/finish/checkpoint node paths (or auto-collect checkpoints from the `checkpoints` group), `auto_start` (bool).

## Track elements (built in §Track of `M4_PLAN.md`)
Start line, finish line, and 3–5 checkpoints as Area3Ds along the track. RunManager connects to each `body_entered` and filters for the vehicle.

## Exit
A full pass start→finish transitions READY→RUNNING→FINISHED and fires `on_run_finished` with a score + time. Falling off respawns at the last checkpoint at reduced speed **without ending the run**. Restart resets cleanly to a fresh run.
