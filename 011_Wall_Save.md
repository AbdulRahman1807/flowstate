# Task 011 — Wall Save (Ricochet)
## FLOWSTATE

---

## Goal

Turn a near-crash into a momentum-preserving move. When the player is heading **into** a wall they can't ride and presses the wall button, instead of grinding to a stop the car **deflects off the wall and skims along it**, keeping its speed and popping back into the air. This is the third M5 trick-flow verb and the project's **north star — "the save"**: contact becomes an *opportunity*, not a punishment.

Pillar fit: **4 (Make Players Look Cool)** — a clutch wall ricochet is the highlight of a clip — and **5 (Failure Costs Momentum, Not Progress)** — a bad approach costs you nothing but a little control, and rewards a quick read with Flow + Style.

---

## Control Scheme — Same Wall Button (DECIDED)

There is **no dedicated save button.** The save reuses the existing wall button (`wall_attach` = Q / Left Bumper) and fires as a **fallback** when a normal wall-ride attach can't happen. The routing in `VehiclePhysics.apply_intent` (step 9) is:

```
on wall_attach pressed:
    if already wall-riding      -> try_wall_detach()      (jump / release)
    elif _try_attach_to_wall()  -> ride a glancing wall   (normal v2.0 attach)
    elif _try_wall_save(steer)  -> SAVE off an oncoming wall   ← verb #3
```

So pressing the wall button while skimming a glancing wall rides it (existing behaviour); pressing it while barrelling **head-on** into a wall (which the ride path rejects, approach > ~0.99) deflects you off it. One button, context-sensitive, no new keybind. Consistent with wall riding v2.0 — **button-initiated, never auto-detected** (`004_Wall_Riding.md`).

---

## Requirements

### Functional
- Pressing the wall button while heading into a non-ridable wall in range **deflects** the car off it, preserving speed magnitude, instead of crashing/stopping.
- The deflection **skims along the wall** (`wall_save_deflect = 1.0`); a dead head-on (no along-direction) falls back to a horizontal tangent along the wall, with `steer` picking the side.
- The launch is kept **horizontal** — the only vertical is a small `wall_save_pop` hop (converting speed into the up-the-wall tangent rocketed the car straight up and floaty; rejected).
- A save requires real speed (`wall_save_min_speed`) and a sufficiently **head-on** approach (`wall_save_min_approach`) to an oncoming wall within `wall_save_range`.
- A save charges **Flow** (`flow_on_wall_save`) and accrues a flat **Style** event (`wall_save_points`) — the save is the payoff moment.
- A save does **not** fire while already wall-riding, while INVERTED, or while in a WALL state.

### Non-Functional
- All tuning values are `@export` (see Constants Reference).
- Velocity **magnitude is preserved** through the deflection — only direction rotates (the surface-transition rule).
- No double-count: **Flow** is owned by `WallRiding`; **Style** is owned by `ScoreSystem` (`06_Architecture` rule for physics-owned flow triggers).
- Must not regress wall riding, attach, jump-off, or the gravity/loop systems (see probe suite).

---

## Acceptance Criteria

| Criteria | How to Test |
|----------|-------------|
| Save deflects along the wall, speed preserved | `_WallSaveProbe.gd` A: velocity deflects along the wall (`vel.x > 1`), `|v| ≥ 90%` of entry speed |
| Save is not floaty | `_WallSaveProbe.gd` A/A2: `vel.y ≤ wall_save_pop` (no straight-up rocket); dead head-on keeps horizontal momentum |
| Flow + Style awarded | `_WallSaveProbe.gd` A: `"wall_save"` in style breakdown, Flow increased |
| Too slow → no save | `_WallSaveProbe.gd` B: speed below `wall_save_min_speed` does not fire |
| No wall in range → no save | `_WallSaveProbe.gd` C: far from geometry does not fire |
| Already riding → no save | `_WallSaveProbe.gd` D: `_is_wall_riding` blocks the save |
| Fires through the real input path | `_WallSaveProbe.gd` E: dead head-on + `wall_attach` via `apply_intent` fires (ride rejects, save catches) |

---

## Implementation Notes

### Detection (`WallSensor.find_wall_for_save`)
A dedicated scan, separate from `find_best_wall` (which finds *glancing* ridable walls). `find_wall_for_save(origin, velocity, space, exclude, min_approach = 0.6, scan_range = 4.0)` returns the normal of an **oncoming** wall — one the velocity is heading *into* by at least `min_approach` — within `scan_range`, else `Vector3.ZERO`. The range is decoupled from `max_wall_range`/`wall_stick_range` because a save does not *sustain* an attachment, so it isn't bound by the sustain-range invariant.

### Deflection (`WallRiding._try_wall_save`)
- `into = velocity · normal`; `along = velocity − normal·into`; `reflected = velocity − 2·normal·into`.
- `dir = reflected.lerp(along, wall_save_deflect)` — at `1.0` this is a pure along-wall skim; lower values mix in a pinball reflection.
- Flatten to horizontal (`dir.y = 0`); if degenerate (dead head-on), use a horizontal tangent `normal × UP`, `steer` choosing the side.
- `velocity = dir.normalized() * speed + UP * wall_save_pop`, then `gravity_system.force_airborne()`.

### Scoring (no double-count)
- **Flow:** `WallRiding` calls `flow_system.increase(flow_on_wall_save, "wall_save")`.
- **Style:** `ScoreSystem._on_wall_save` adds `wall_save_points` as a flat `"wall_save"` event. `ScoreSystem` must NOT also add save Flow.

### Signal
- `signal on_wall_save(speed: float, wall_normal: Vector3)` — consumed by `ScoreSystem` (Style) and available to VFX.

---

## Constants Reference (all `@export`)

### `WallRiding.gd`
| Param | Default | Meaning |
|-------|---------|---------|
| `wall_save_min_speed` | 8.0 | Minimum speed to save (else it's just a stop) |
| `wall_save_min_approach` | 0.6 | How head-on the wall must be to count as a save (velocity·normal) |
| `wall_save_range` | 4.0 | Save scan range (not bound by `wall_stick_range` — no sustain) |
| `wall_save_deflect` | 1.0 | 0 = pinball reflect; 1 = skim along the wall |
| `wall_save_pop` | 4.0 | Small up impulse on a save (the only vertical in the launch) |
| `flow_on_wall_save` | 1.5 | Flow reward for a save |

### `ScoreSystem.gd`
| Param | Default | Meaning |
|-------|---------|---------|
| `wall_save_points` | 350.0 | Flat Style on a wall save (Flow owned by `WallRiding`) |

### `WallSensor.gd`
| Param | Default | Meaning |
|-------|---------|---------|
| `find_wall_for_save(... min_approach, scan_range)` | 0.6 / 4.0 | Per-call save-scan args (defaults mirror the `WallRiding` exports) |

---

## Test Assets
- `scripts/tests/_WallSaveProbe.gd` — headless regression probe (A deflect/speed/not-floaty/style/flow, A2 dead head-on, B too slow, C no wall, D already riding, E full `apply_intent` path).
- Feel-tested in `scenes/tests/Test_Playground.tscn` (dense geometry) and `Test_Drift.tscn`.

---

## Status
Implemented and probe-green; moveset drive-test dev-confirmed feels good (2026-06-23). Button-routed fallback, along-wall skim, not-floaty horizontal launch, Flow + Style wired.

## Future Considerations
*Not in this task.*
- A bigger reward / slow-mo beat on a high-speed save could amplify the "the save" highlight moment.
- An air-redirect / push-off (recover a bad trajectory off a nearby surface mid-air) was sketched alongside the save as part of the same north-star; not built. Decide by feel if the wall save alone delivers the moment.
- Comic VFX for the ricochet is part of the parked `ComicPostFX` pass (M5 VFX), not here.
