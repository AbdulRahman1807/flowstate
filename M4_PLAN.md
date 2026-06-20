# M4 — Flow + Score + First Track — Implementation Plan

**Status:** Planned 2026-06-19. Execute next session.
**Goal (07_Roadmap):** A complete run with scoring is playable.
**Exit:** A full run produces a score; the player sees the Flow multiplier responding to skill; they restart.

## Why this is the milestone (not VFX)
M4 is the first time FLOWSTATE is a *loop* you can validate: Build Speed → Execute Chains → Preserve Flow → Finish → **Review Score** → Restart (02_GDD). It answers the riskiest open question — *is chasing a Flow-score actually fun?* The comic VFX was correctly deferred to M5 (see Carry-over).

## New / changed systems
| System | State | Doc |
|---|---|---|
| FlowSystem | promote stub → full (all triggers + tuning) | `006_Scoring.md` |
| ScoreSystem | NEW (`score = base × flow + style`) | `006_Scoring.md` |
| RunManager | NEW (run lifecycle: start/finish/timer/checkpoints/respawn/restart) | `007_Run_Lifecycle.md` |
| HUD + end-of-run summary | NEW | `008_HUD.md` |
| Track (M4) | add start/finish/checkpoint Area3Ds + retune for max_speed=50 | this doc §Track |

## Architecture (extends 06_Architecture)
- Every NEW system is an **observer/coordinator** — reads existing signals, never touches physics.
- Signals available to consume: `VehiclePhysics.landed(impact)` / `jumped(dir)`, `WallRiding.on_wall_attach` / `on_wall_detach(reason)` / `on_wall_jump` / `on_near_miss`, `GravitySystem.on_state_changed(state)`, `FlowSystem.on_changed(value)`.
- NEW signals: `RunManager.on_run_started` / `on_run_finished(score,time)` / `on_checkpoint(i)` / `on_respawn`; `ScoreSystem.on_score_changed(score)`.
- Events → signals; per-frame reads → direct getters (HUD reads flow/score/time). No global event bus (prototype rule holds).

## Sequencing (next session, in order)
1. **Track markers + RunManager (`007`)** — start/finish/checkpoint Area3Ds, run state machine, timer, respawn-on-fall, restart. (Creates a "run" to score.)
2. **Scoring (`006`)** — finish wiring FlowSystem triggers + tune; ScoreSystem accumulates (base × flow + style). Needs the run timer from 007.
3. **HUD + summary (`008`)** — display flow/score/timer; end-of-run panel on `on_run_finished`.
4. **Track retune (§Track)** — widen jump gaps / re-space for 50; place start/finish/checkpoints; confirm all surface types.
5. **Integrate + tune** — drive a full run, confirm the M4 gate.

## Track (M4) work
TrackBuilder.gd exists (12 sections) but was sized for max_speed=22 → at 50, jumps fly ~2× farther.
- **Retune:** widen jump gaps (sections 3, 8), lengthen landing pads, re-space sections. Keep all surface types (flat / banked / jump / wall L+R / vertical climb / ceiling / loop / quarter-pipe — loop+ceiling rely on 005 surface-following, drivable).
- **Add:** a **start line** (Area3D at spawn), a **finish line** (Area3D, section 12), and 3–5 ordered **checkpoint** Area3Ds (group `checkpoints`). RunManager connects to their `body_entered`.
- Keep the flush recovery floor (fall = land + drive back on; respawn only for true off-world via the KillZone / y-threshold).

## Key decisions (resolved — don't re-litigate)
- **Score formula (02_GDD):** `Score = Base Time Score × Flow Multiplier + Style Points`, implemented as **continuous accumulation**: each RUNNING frame `score += base_rate × flow.get_multiplier() × delta` (rewards sustained fast/high-flow driving) + flat style-event points. Final score at finish. (Live score → readable HUD.)
- **Flow:** value 0–5 in FlowSystem, passive decay; multiplier mapping tuned in 006 (start `1.0 + value/5` = 1.0–2.0, may widen to ~3×).
- **Respawn (02_GDD):** fall off world → respawn at last checkpoint at **reduced speed** + a Flow penalty. NOT a run reset; timer keeps running. Restart is always available, never forced (Pillar 5).
- **Replay/ghost = M5** (CLAUDE.md: replay records inputs only — out of M4 scope).
- **HUD (04):** minimal, flat, high-contrast, graffiti-inflected, fades when idle. Prototype = simple labels + a flow bar.

## Exit criteria (M4 gate)
Drive the track start→finish → a score is produced; the Flow multiplier visibly responds to skill (chains raise it, crashes drop it); the end-of-run summary shows score/time; restart works and feels like an opportunity, not a punishment. A tester restarts voluntarily.

## Carry-over / parked
- **WallVFX rainbow-trail particles DISABLED** (`enabled=false`); signal hooks + `bursts_fired` stay live for M5.
- **Wall-attach decel flag (M3):** entering a wall at 50 hard-clamps to `wall_ride_speed_cap=22` → revisit (soften the clamp, or raise the cap) during M4 polish or M5.
- **Comic VFX = parked M5 spike:** `ComicPostFX` (`shaders/comic_post_fx.gdshader`, `scripts/fx/ComicPostFX.gd`, `scenes/fx/ComicPostFX.tscn`) — tunable, wired into `Test_WallRiding`. M5 look targets: thick neo-brutalist comic-panel borders, action/sketch lines, BAM/POW onomatopoeia (asset-based). Sources: `vfx_sources` memory.

## Out of scope (M4 — defer to M5+)
Ghost replay, personal-best persistence, audio, the full comic VFX pass.
