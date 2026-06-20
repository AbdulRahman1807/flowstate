# Roadmap
## FLOWSTATE — Pre-Prototype Stage

---

## Philosophy

The roadmap is sequenced by validation risk. The riskiest assumptions — does movement feel good? does wall riding work? — are tested first. Nothing downstream gets built until the thing before it is validated.

There is no timeline. This is a sequence of gates.

---

## Gate Model

Each milestone has an exit condition. You do not proceed until the condition is met. "Good enough" is not a valid exit condition.

---

## Milestone 0 — Foundation
**Goal:** Project is set up and a vehicle can move on a flat surface.

Tasks:
- Engine selected and project initialized
- Basic vehicle mesh (placeholder acceptable) in scene
- VehicleController reads input
- VehiclePhysics applies movement to vehicle on flat ground
- Vehicle steers, accelerates, brakes, and reverses

**Exit Condition:** Vehicle moves responsively on flat ground with no unexpected behavior. Input feels immediate.

---

## Milestone 1 — Ground Movement Validation
**Goal:** Ground movement alone feels genuinely satisfying.

Tasks:
- Tune acceleration curve
- Tune turning feel at speed
- Jump implemented and tuned
- Boost implemented and tuned
- Dynamic camera operational (FOV, lag, tilt)
- Basic test environment (flat track with a few turns)

**Exit Condition:** You drive around the flat track and want to do it again. Not because you're testing — because it feels good.

⚠️ **Do not proceed until this gate is met.** Building wall riding on top of bad ground movement wastes time.

---

## Milestone 2 — Gravity System
**Goal:** Vehicle can attach to and traverse walls and ceilings.

Tasks:
- GravitySystem operational
- Surface normal detection reliable
- Wall attachment / detachment lifecycle working
- Ceiling traversal working
- Camera handles arbitrary up-direction
- Gravity transition implemented (floor → wall → ceiling)

**Exit Condition:** Floor → wall → ceiling transition is achievable and feels smooth, not janky. Camera remains readable throughout.

---

## Milestone 3 — Wall Riding
**Goal:** Wall riding is a satisfying, learnable skill.

Tasks:
- Wall entry angle detection
- Speed-dependent wall adhesion (fall off if too slow)
- Wall exit: jump off, natural edge exit, speed bleed exit
- Skill expression visible: entry angle affects exit angle
- VFX placeholder: spark on wall contact
- WallRiding events connected to FlowSystem

**Exit Condition:** A wall section can be driven, and the experience of riding it feels distinct from ground driving. A skilled entry vs clumsy entry produces clearly different results.

---

## Milestone 4 — Flow + Score + First Track
**Goal:** A complete run with scoring is playable.

Tasks:
- FlowSystem fully operational and tuned
- ScoreSystem computing score per run
- Full prototype track built (all surface types included)
- HUD showing Flow multiplier, score, and timer
- Respawn on track exit
- End-of-run summary screen

**Exit Condition:** A full run produces a score. The player can see their Flow multiplier responding to their skill. They restart.

---

## Milestone 5 — MVP Validation
**Goal:** The game's core promise is validated.

Tasks:
- Ghost replay operational
- Local personal best stored
- VFX pass: speed lines, particle trails, boost effect
- Camera impact response on landing
- Rough style point events (perfect landing, near miss)

**Exit Condition:** At least one external tester (not the developer) restarts the track multiple times voluntarily. At least one replay moment produces genuine surprise or excitement.

---

## Post-Validation (Future — Do Not Design For)

After Milestone 5 is validated, the following become possible next steps — but none of them should influence the current architecture:

- Audio and music
- Additional tracks
- Ghost leaderboards
- Visual polish pass
- PC / additional platform builds

Nothing in this list should be referenced in any code, scene, or design document at the current stage.

---

## Current Position

```
[ M0 Foundation ] → [ M1 Ground ] → [ M2 Gravity ] → [ M3 Walls ] → [ M4 Full Run ] → [ M5 Validated ]
       ↑
   You are here
```
