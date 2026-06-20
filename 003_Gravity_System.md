# Task 003 — Gravity System
## FLOWSTATE

---

## Goal

Implement the gravity system that allows the vehicle to attach to, traverse, and transition between surfaces of different orientations — floor, wall, and ceiling. This is the core technical differentiator of FLOWSTATE.

This task depends on Task 001 (movement must be working). Task 004 (wall riding) is built on top of this task.

---

## Goal Statement (Design)

A floor → wall → ceiling chain should feel fluid, skillful, and satisfying. The player should feel like they are bending the laws of physics — not fighting the game engine.

---

## Requirements

### Functional Requirements

- Vehicle detects the surface it is currently attached to via surface normal
- Vehicle's gravity direction aligns to the current surface normal
- Vehicle transitions between surfaces when contact is made at a compatible angle and speed
- Gravity direction change is smooth — not an instant snap
- Vehicle can drive on floors, walls (left and right), and ceilings
- Transition speed is configurable — defines how quickly gravity rotates to new surface
- If the vehicle contacts a new surface at too shallow an angle or too low a speed, attachment does not occur
- Vehicle enters an AIRBORNE state when no surface contact exists
- In AIRBORNE state, gravity is world-down (or a configurable fallback)
- Vehicle returns to surface attachment state when contact is re-established

### Attachment State Machine

```
GROUNDED
  ↓ leaves surface edge at speed
AIRBORNE
  ↓ contacts wall at valid angle+speed
WALL_LEFT or WALL_RIGHT
  ↓ reaches wall top / enters ceiling angle
INVERTED (ceiling)
  ↓ speed drops below threshold
AIRBORNE (falls off)
```

Every state transition must fire an event signal.

### Non-Functional Requirements

- GravitySystem is a standalone script — VehiclePhysics queries it, does not duplicate logic
- All attachment thresholds are exported for tuning
- System must not introduce physics jitter at surface edges
- Camera up-direction is updated by GravitySystem (connects to Task 002)

---

## Acceptance Criteria

| Criteria | How to Test |
|----------|-------------|
| Vehicle drives on walls without falling through | Drive at a wall at speed — vehicle sticks and drives up |
| Vehicle drives on ceiling when inverted | Transition floor → wall → ceiling — vehicle maintains grip |
| Gravity direction visually aligns to surface | Vehicle appears "grounded" to the surface, not rotated independently |
| Transition between surfaces is smooth | Cross floor-to-wall edge — gravity change takes a brief number of frames, not instant |
| Too-slow wall contact does not attach | Approach wall slowly — vehicle does not stick, slides or bounces off |
| Incorrect entry angle rejects attachment | Hit wall at very shallow angle — vehicle does not attach |
| Camera up-direction follows surface | Enter ceiling — camera inverts smoothly, scene remains readable |
| AIRBORNE state applies world-down gravity | Jump off a wall — vehicle falls toward world floor, not wall floor |
| All thresholds tunable in inspector | Open GravitySystem — attachment speed, angle tolerance, transition time all visible |

---

## Suggested File Structure

```
scripts/
└── vehicle/
    └── GravitySystem.gd
        # Owns: current gravity vector, current surface normal, attachment state enum
        # Emits: on_state_changed(new_state: AttachmentState)
        # Provides: get_gravity_vector(), get_surface_normal(), get_state()
        # Queries: surface contact via raycasts or collision signals

scenes/
└── tests/
    └── Test_GravityTransition.tscn
        # Ramp from floor to wall to ceiling
        # Vehicle + GravitySystem + DynamicCamera wired
        # Debug overlay: current state, current gravity direction, current speed
```

---

## AttachmentState Enum

```gdscript
enum AttachmentState {
    GROUNDED,
    WALL_LEFT,
    WALL_RIGHT,
    INVERTED,
    AIRBORNE
}
```

---

## Exported Tuning Parameters (minimum)

```gdscript
@export var min_attach_speed: float = 5.0          # Min speed for button wall attach (request_wall_attach)
@export var gravity_transition_speed: float = 8.0  # How fast gravity direction rotates to new surface
@export var wall_grip_decay: float = 0.15          # Speed lost per second while on a button wall (anti-grind)
@export var detach_speed_threshold: float = 4.0    # Absolute floor: tilted surfaces below this requirement hold freely
@export var wall_stick_range: float = 3.5          # Max distance to a button wall before detach (>= WallSensor.max_wall_range)
@export var airborne_gravity: Vector3 = Vector3(0, -18, 0)   # ~1.8g — Earth-like weighty fall

# Continuous surface following (005 Phase 1)
@export var attach_init_dot: float = 0.5           # Min |normal·UP| to AUTO-attach from air — walls stay button-only
@export var max_follow_rotation_deg: float = 20.0  # Max normal rotation/frame to keep following (smooth curve vs sharp wall)
@export var max_hold_speed: float = 14.0           # Speed to hold a full ceiling/loop-top
@export var hold_curve_exponent: float = 3.0       # Forgiving hold curve: required = max_hold_speed * tilt^exponent
@export var hold_speed_curve: Curve                # Optional override for tilt(0..1) -> 0..1 multiplier
@export var attach_cooldown_time: float = 0.18     # No auto-attach for this long after leaving a surface
```

---

## Implementation Notes

### Surface Detection (continuous following — 005 Phase 1)

**Superseded:** the original floor/ceiling classification with a ~57° dead-band is gone (it made loops, steep banks, and curved ceilings undrivable). GROUNDED/INVERTED are now reached by **continuous surface following** — see `005_Surface_Following.md`.

Each frame, find the surface *under the car* from the real `move_and_slide` contact normal (the contact most aligned with the car's up), with a single down-ray (`-basis.y`) as fallback. Follow that normal at **any tilt**. GROUNDED/INVERTED are just labels derived from `normal·UP`; they no longer gate attachment.

- **Attach from air** only when `abs(normal·UP) >= attach_init_dot` and not in `attach_cooldown` — so the car never auto-grabs a standalone vertical wall (those stay button-only). This is the ownership boundary with 004.
- **Sustain** while the normal rotates gradually (`<= max_follow_rotation_deg`/frame): smooth curves (loops, fillets) are followed; sharp flips (running into a wall) are rejected.
- **Detach** when the surface is lost, the normal flips sharply, or speed `< required_hold_speed(normal)` (tilt-scaled, forgiving `tilt^exponent`) — the legible "too slow on an overhang" rule. Floors/mild slopes hold at any speed.

`WALL_LEFT`/`WALL_RIGHT` remain reachable **only** via `request_wall_attach()` (button). Phase 2 (centrifugal adhesion) is opt-in and plugs into two seams without rewriting this — see 005.

### Gravity Transition

Do not snap gravity instantly. Lerp the gravity direction over `gravity_transition_speed` frames:

```gdscript
var target_gravity: Vector3 = -surface_normal * gravity_magnitude
current_gravity = current_gravity.lerp(target_gravity, delta * gravity_transition_speed)
```

The vehicle's orientation should follow the gravity direction, not the other way around.

### Preventing Jitter at Edges

The old per-frame normal debounce (`NORMAL_CONFIRM_FRAMES`) is **removed**. Continuous following gets stability from two places instead: (1) reading the resolved `move_and_slide` contact normal (already collision-resolved, not a raw single-ray), and (2) the `max_follow_rotation_deg` gate, which ignores per-frame normal jumps bigger than the threshold (sharp edges) while accepting the gradual rotation of a smooth curve. Speed for the detach check is smoothed via a short max-window so a one-frame dip doesn't drop the car.

---

## Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Physics jitter at surface edges | High | Normal debouncing (see above) |
| Gravity snap feels jarring | High | Lerp gravity direction, never instant-set |
| Speed destroyed on transition | High | Preserve velocity magnitude, only rotate direction |
| Vehicle "clips" through wall on first contact | Medium | Ensure collision shapes are correct before testing physics |
| Camera not keeping up with gravity changes | Medium | GravitySystem fires signal → Camera updates up-direction same frame |
| Ceiling attachment too hard to achieve | Medium | Generous angle tolerance — this is a game, not a simulation |

---

## Future Considerations

*Do not implement these in this task.*

- Task 004 (Wall Riding) adds the speed-decay and entry-angle-precision system on top of this task's attachment logic
- Future tracks may include curved surface transitions (e.g., quarter-pipes that smoothly connect floor to wall) — GravitySystem's normal-lerp approach supports this without changes
- "Gravity strips" (track elements that force a gravity change) would be implemented as triggers that override GravitySystem's detected normal — the interface already supports this
