# Game Design Document
## FLOWSTATE — Pre-Prototype Stage

---

## Core Loop

```
Enter Track → Build Speed → Execute Chains → Preserve Flow → Finish → Review Score → Restart
```

The loop is tight. Restart cost is near-zero. The game only works if restarting feels like an opportunity, not a punishment.

---

## The Vehicle

The vehicle is not a car. It is a momentum-based movement character that happens to look like a vehicle.

Design constraints on vehicle behavior:
- Must feel instantly responsive to input
- Must never feel like it's fighting the player
- Speed loss must be clearly attributable to player error
- Physics must be learnable — the same input in the same situation produces the same result

### Vehicle Physics Properties (Target Feel)

| Property | Direction |
|----------|-----------|
| Steering response | Immediate, no lag |
| Turning radius | Tight enough for skilled routing, not a kart |
| Air control | Present, meaningful, not dominant |
| Gravity adhesion | Strong on surfaces, smooth on transitions |
| Collision behavior | Forgiving — scrapes do not kill momentum |

---

## Movement Systems

### Steering
- Analogue input preferred
- Tighter steering at high speed to avoid overshoot
- Drift is a deliberate, controllable mechanic (added in M5) — see Drift below and `009_Drift.md`

### Acceleration / Braking / Reverse
- Acceleration is continuous with a tunable top speed
- Braking reduces speed but should not be a primary mechanic
- Reverse is brake-to-engage: hold brake below a speed threshold to back up at a lower max speed
- The game is about going fast, not stopping — reverse exists for repositioning, not racing

### Drift
- **Brake-to-drift, no dedicated button:** hold brake while steering hard at forward speed to break traction and slide. (Full spec: `009_Drift.md`.)
- **Momentum-preserving:** drifting holds speed (the brake's scrub is suppressed while drifting) — it never punishes you for using it. The slide builds a slip angle; releasing snaps velocity back to facing at full speed.
- Drift charges **Flow** and accrues **Style** — it is a rewarded trick, not just a movement tool.
- Forward-motion only; never engages while reversing or wall/ceiling-attached.
- Skill expression: choosing when to commit, holding the line through tight geometry, and exiting clean into the next section.

### Jump
- Single jump from any attached surface
- Jump should give air time useful for route optimization
- Jump timing is a primary skill expression — launch angle affects next landing
- Jump from a wall should preserve the wall's velocity direction

### Air Tricks
- While airborne, the player can perform **barrel roll / flip / spin** (full spec: `010_Air_Tricks.md`).
- **Air-trick key (E / RB):** a dedicated, air-only button — E + steer = roll, E + accelerate = flip, E alone = spin. (Brake-as-modifier was tried first but misfired in the air — brake is pressed for other reasons.)
- **Momentum-preserving in the air:** tricks rotate orientation only; they never change velocity mid-flight. The risk is the *landing*.
- **Land it clean:** you must **complete the rotation** — come down on your **wheels** *and* **facing forward** (the car has a fixed front/rear) to earn **Style + Flow**. Landing on your **roof/side** or **rear-first** (a half-finished trick, e.g. a 180° flip or spin) is a **crash**: the car rights itself and recovers a forward heading so you keep going, but you bleed momentum + Flow scaled by how badly off you were (Pillar 5 — failure costs momentum, not progress).
- A minimum-airtime gate prevents accidental tricks on tiny hops.
- Skill expression: timing the rotation so you land flat, and stringing tricks into the run for Style.

### Boost
- Short burst of speed
- Resource-limited or cooldown-limited (to be determined during prototyping)
- Using boost well is a skill: timing it into a transition should feel powerful

### Wall Riding
- Vehicle attaches to walls on contact at speed
- Wall riding is maintained by speed — slow down and fall off
- Exit: player can jump off the wall or naturally exit at the wall's edge
- Entry angle affects exit angle — this is a core skill expression point

### Wall Save (Ricochet)
- **The "save" — the M5 north star:** heading *into* a wall you can't ride, press the wall button to **deflect off it instead of crashing** (full spec: `011_Wall_Save.md`).
- **Same wall button, no new input:** the save is a fallback on `wall_attach` — ride a glancing wall if you can, otherwise ricochet off an oncoming one.
- **Momentum-preserving:** the deflection skims along the wall keeping speed magnitude (only direction rotates), kept low/horizontal with just a small pop — it flows fast into the next move, never a floaty stop.
- Rewards **Flow + Style** — the save is the payoff moment (Pillars 4 *Make Players Look Cool* + 5 *Failure Costs Momentum, Not Progress*).
- Skill expression: reading a bad approach and turning a near-crash into your coolest move.

### Ceiling Traversal
- Ceiling attachment works the same as wall attachment
- Gravity inverts to maintain the vehicle on the ceiling surface
- Must support full steering while inverted

### Surface Transitions
- The gravity direction change on surface transitions must feel smooth, not jarring
- Transition should take a small but perceptible number of frames — not instant, not slow
- A bad transition (wrong angle, too slow) should cause the player to fall off, not crash
- Transitions are a major skill expression: a clean floor → wall → ceiling chain should feel incredible

---

## Flow System

Flow is a combo multiplier. It exists to reward players who maintain momentum chains.

### Flow Increases When:
- Moving at high speed
- Executing a wall ride
- Completing a surface transition
- Landing precisely (defined as: landing without significant speed loss)
- Near-miss events (close but no collision)

### Flow Decreases When:
- Speed drops significantly
- Crashing into geometry
- Coming to a near-stop
- Falling off a surface unintentionally

### Flow Implementation (Prototype)
- Single float value, 0.0 to 5.0
- Displayed as a visual bar or multiplier label
- Drives score multiplier only
- Does not gate access to anything

---

## Score System

Score is a combination of time and style. Neither dominates.

```
Score = (Base Time Score) × Flow Multiplier + Style Points
```

### Style Points (Prototype — Basic Version)
- Perfect Landing: flat bonus
- Wall Ride: bonus per second maintained
- Gravity Transfer: bonus per transfer
- Near Miss: bonus per event
- Drift: bonus per second maintained (M5 — `009_Drift.md`)
- Air Trick: flat bonus per clean landing (M5 — `010_Air_Tricks.md`)
- Wall Save: flat bonus per ricochet (M5 — `011_Wall_Save.md`)

Score is shown at end of run and on a local ghost leaderboard. No persistence required for prototype.

---

## Track Design (Prototype)

One track. Its purpose is to test every movement system.

### Required Track Sections
- Flat straight (baseline speed feel)
- Banked curve (steering feel)
- Jump gap (jump + landing feel)
- Wall section (wall riding)
- Ceiling section (ceiling traversal)
- Combined surface transition sequence (the centerpiece)
- Optional: split route with harder/faster path

### Track Philosophy
The track is not an obstacle course. It is a movement showcase. Every section should feel *designed to be ripped through*, not survived.

---

## Controls (Default Mapping — Gamepad)

| Action | Input |
|--------|-------|
| Steer | Left stick |
| Accelerate | Right trigger |
| Brake | Left trigger |
| Jump | A / Cross |
| Boost | B / Circle or Right Bumper |
| Camera reset | Right stick click |

Keyboard fallback required for development purposes.

---

## Failure States

FLOWSTATE does not have a traditional failure state. There is no death. There is no game over.

When the vehicle falls off the world: respawn at last checkpoint at reduced speed.
When the vehicle stalls: player retains control and can rebuild speed.

**The only real punishment for failure is momentum loss, and therefore score loss.**

Players should almost never feel the need to fully restart due to a mistake — only due to wanting a better score.
