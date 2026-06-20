# Task 001 — Movement Prototype
## FLOWSTATE

---

## Goal

Implement the core ground movement system: steering, acceleration, braking, reverse, jumping, and boosting. The vehicle must feel responsive and satisfying on flat and curved surfaces before any other system is built.

This task is the foundation of everything. Do not proceed to wall riding or gravity transitions until this task passes all acceptance criteria.

---

## Requirements

### Functional Requirements

- Vehicle moves forward with held accelerate input
- Vehicle steers left and right with proportional analogue input
- Steering response feels immediate — no lag between input and direction change
- Turning radius tightens at higher speeds to prevent overshoot
- Braking reduces forward speed without abrupt stops
- Holding brake below a speed threshold engages reverse gear (same `brake` input — no separate key)
- Reverse has a lower top speed than forward and uses the same steering model
- Vehicle maintains momentum on release of accelerate input (coasts via drag, does not stop instantly)
- Ground steering redirects velocity to the vehicle forward axis each physics frame (no lateral slide)
- Jump launches vehicle off the current surface with upward force relative to surface normal
- Jump arc allows for meaningful air time for routing
- Boost applies a burst of forward acceleration
- Boost has a cooldown or resource cost (design TBD, implement whichever is tunable)
- All inputs respond within one physics frame

### Non-Functional Requirements

- VehicleController and VehiclePhysics are separate scripts
- No wall riding or gravity logic in this task — surface is assumed flat
- All physics parameters are exposed as exported variables for in-editor tuning
- Runs at 60fps on MacBook Air M2 with no visible stutter

---

## Acceptance Criteria

| Criteria | How to Test |
|----------|-------------|
| Steering feels immediate | Tap steer input — direction changes on the same frame |
| High speed does not cause wild oversteer | Maintain top speed through a curve — vehicle stays on intended line |
| Jump launches upward relative to surface | Jump on flat ground — vehicle goes up, not sideways |
| Momentum is preserved through jump | Jump at top speed — speed during air should be close to pre-jump speed |
| Boost adds meaningful speed | Use boost at mid-speed — player perceives clear acceleration |
| Boost cannot be spammed indefinitely | Boost has a cooldown or resource — second immediate boost does not fire |
| Vehicle does not feel "floaty" | Land from a jump — vehicle contacts ground cleanly, no bounce |
| Vehicle does not feel "sticky" | Drive at speed and release accelerate — vehicle coasts, does not stop |
| Vehicle does not slide sideways when steering | Turn while moving — velocity follows facing direction, not the previous heading |
| A steers left, D steers right | Tap A — vehicle yaws left; tap D — vehicle yaws right |
| Reverse engages from standstill | Hold S until forward speed drops below threshold — vehicle accelerates backward |
| Reverse has a lower top speed | Hold S from standstill — speed plateaus below forward `max_speed` |
| W cancels reverse | Reverse, then hold W — vehicle slows, stops, and moves forward |
| Boost does not fire in reverse | Press boost while reversing — nothing happens |
| All parameters are tunable in editor | Open VehiclePhysics in inspector — steering, acceleration, jump force, boost values are all visible |

---

## Suggested File Structure

```
scripts/
└── vehicle/
    ├── VehicleController.gd
    │   # Reads input, builds MovementIntent struct
    │   # No physics logic here
    │
    ├── MovementIntent.gd
    │   # Plain data container for steer, accelerate, brake, jump, boost
    │
    └── VehiclePhysics.gd
        # Receives MovementIntent
        # Applies velocity, handles jump and boost state
        # All tuning vars exported

scenes/
└── tests/
    └── Test_GroundMovement.tscn
        # Flat surface with a few turns
        # Vehicle, camera placeholder, no HUD required
```

### MovementIntent Struct (suggested)

```gdscript
# MovementIntent.gd
class_name MovementIntent

var steer: float       # -1.0 to 1.0
var accelerate: float  # 0.0 to 1.0
var brake: float       # 0.0 to 1.0
var jump: bool
var boost: bool
```

---

## Input Mapping

| Action | Keyboard | Gamepad | Notes |
|--------|----------|---------|-------|
| `accelerate` | W | Right Trigger | Forward thrust |
| `brake` | S | Left Trigger | Brakes forward; engages reverse below `reverse_engage_speed` |
| `steer_left` | A | Left Stick Left (Axis 0−) | Negative steer axis |
| `steer_right` | D | Left Stick Right (Axis 0+) | Positive steer axis |
| `jump` | Space | Button 0 | Buffered jump |
| `boost` | Left Shift | Button 1 | Forward-only surge |

`VehicleController` reads steer via `Input.get_axis("steer_left", "steer_right")` and negates the result so that A produces left yaw and D produces right yaw in Godot's `-Z` forward convention.

---

## Ground Steering Physics

Steering rotates the vehicle on the Y axis, then **realigns horizontal velocity to the vehicle forward axis** (`-transform.basis.z`) while preserving speed magnitude. This eliminates the ice-cube slide where the body turns but momentum continues along the old heading.

- **Grounded:** velocity direction always matches facing after each steer step; speed is retained (coasting still works via `drag`)
- **Airborne:** velocity is not realigned — horizontal momentum is preserved through jumps (see acceptance criteria)
- **Braking:** opposes current travel direction (forward or reverse) before the steer/align step
- **Reverse alignment:** grounded velocity uses signed forward speed — negative values travel along `-forward`

---

## Reverse Gear

Reverse uses the existing `brake` action (S / Left Trigger). `VehicleController` passes brake strength unchanged; `VehiclePhysics` decides brake vs reverse based on signed forward speed.

| Signed Speed | Brake Held | Accelerate Held | Result |
|--------------|------------|-----------------|--------|
| > `reverse_engage_speed` | Yes | — | Forward braking |
| < `-reverse_engage_speed` | Yes | — | Reverse braking (slows backward motion) |
| −`reverse_engage_speed` … `reverse_engage_speed` | Yes | No | Reverse acceleration |
| Any | Yes | Yes | Accelerate wins — no reverse engagement |

- `get_speed()` returns absolute speed (forward or reverse)
- `is_reversing()` returns true when signed forward speed < −0.5
- Boost is disabled while reversing or when signed forward speed is negative

---

## Exported Tuning Parameters (minimum)

```gdscript
# VehiclePhysics
@export var max_speed: float = 22.0
@export var acceleration: float = 25.0
@export var brake_force: float = 30.0
@export var max_reverse_speed: float = 8.0      # ~36% of max_speed (08 feel target)
@export var reverse_acceleration: float = 18.0
@export var reverse_engage_speed: float = 10.0
@export var drag: float = 0.08
@export var steering_speed: float = 3.5
@export var high_speed_steering_dampen: float = 0.45
@export var jump_force: float = 12.0           # Scaled to gravity_force for ~1.3s air time
@export var air_control_strength: float = 0.6
@export var gravity_force: float = 18.0         # ~1.8g — Earth-like; must match GravitySystem.airborne_gravity magnitude
@export var boost_kick_speed: float = 8.0      # Instant forward velocity added on activation (~27% of max_speed)
@export var boost_sustain_force: float = 6.0   # Gentle forward force during the decaying tail
@export var boost_decay_rate: float = 10.0     # Overspeed bleed-off rate after boost ends (avoids hard snap)
@export var boost_duration: float = 1.5
@export var boost_cooldown: float = 2.5

# VehicleController
@export var jump_buffer_time: float = 0.12
```

---

## Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Default physics engine produces wrong feel | High | Custom velocity application, bypass engine defaults |
| Steering overshoot at high speed | Medium | Speed-dependent steering damping from the start |
| Lateral slide on turn (ice-cube feel) | High | Realign grounded velocity to forward axis after each steer rotation |
| Inverted steer input | Medium | Negate `Input.get_axis` result in VehicleController |
| Jump arc feels floaty or too short | Medium | Expose jump force and gravity scale separately |
| Boost too strong / too weak | Low | Cooldown + force both tunable, iterate fast |
| Physics inconsistency between frames | Low | Lock to physics tick, not render frame |

---

## Future Considerations

*These must not be implemented in this task. Noted here to avoid scope creep.*

- Wall contact detection will extend VehiclePhysics in Task 004
- Air control will be introduced when gravity transitions are built (Task 003)
- Boost resource management can evolve into a Flow-linked system later
- Boost VFX and camera effects are addressed in Tasks 002 and the VFX pass milestone
