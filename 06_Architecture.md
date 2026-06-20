# Architecture
## FLOWSTATE — Pre-Prototype Stage

---

## Governing Principle

> The architecture must be as small as it needs to be, and no larger.

At pre-prototype stage, the only job of the architecture is to let the movement system be built, tested, and replaced quickly. No patterns, no abstractions, and no future-proofing until movement is proven fun.

---

## Project Structure

```
flowstate/
├── scenes/
│   ├── Main.tscn               # Entry point
│   ├── Vehicle.tscn            # The player vehicle
│   ├── Track_Prototype.tscn    # The one prototype track
│   └── UI/
│       └── HUD.tscn            # Minimal in-run HUD
│
├── scripts/
│   ├── vehicle/
│   │   ├── VehicleController.gd    # Input → movement translation
│   │   ├── VehiclePhysics.gd       # Custom physics layer
│   │   ├── GravitySystem.gd        # Surface attachment + gravity direction
│   │   └── WallRiding.gd           # Wall detection and adhesion
│   │
│   ├── camera/
│   │   └── DynamicCamera.gd        # FOV, lag, tilt, transition support
│   │
│   ├── systems/
│   │   ├── FlowSystem.gd           # Flow multiplier state
│   │   ├── ScoreSystem.gd          # Score tracking
│   │   └── ReplayRecorder.gd       # Input recording for ghost replay
│   │
│   └── ui/
│       └── HUDController.gd        # Connects HUD to game state
│
├── assets/
│   ├── meshes/                 # Vehicle and track geometry
│   ├── materials/              # Shaders and materials
│   └── vfx/                    # Particle systems
│
└── tests/                      # Manual test scenes for individual systems
    ├── Test_WallRiding.tscn
    ├── Test_GravityTransition.tscn
    └── Test_CameraResponse.tscn
```

---

## System Overview

### VehicleController

**Responsibility:** Translate player input into movement intent signals.

**Inputs:** Raw input (steer, accelerate, brake, jump, boost)

Brake input doubles as reverse intent. The controller passes brake strength as-is; `VehiclePhysics` applies forward braking, reverse braking, or reverse acceleration depending on signed forward speed.
**Outputs:** Movement intent struct passed to VehiclePhysics

Does not contain physics logic. Does not know about walls or gravity. It only knows what the player is asking for.

```
Input → [VehicleController] → MovementIntent → [VehiclePhysics]
```

---

### VehiclePhysics

**Responsibility:** Translate movement intent into actual velocity and position changes.

**Inputs:** MovementIntent, current surface normal, current gravity direction
**Outputs:** Applied velocity, position, orientation

This is the most critical and most likely to be iterated on. It must be replaceable without touching any other system. Keep its interface narrow.

---

### GravitySystem

**Responsibility:** Determine the vehicle's current gravity direction and surface attachment state.

**States:**
- `GROUNDED` — on a floor surface
- `WALL_LEFT` / `WALL_RIGHT` — on a wall
- `INVERTED` — on a ceiling
- `AIRBORNE` — no surface contact

**Outputs:** Current gravity vector, current surface normal, attachment state enum

Other systems query GravitySystem. They do not compute gravity themselves.

---

### WallRiding

**Responsibility:** Detect wall contact, determine if attachment conditions are met, and manage the wall ride lifecycle.

**Attachment conditions (tunable):**
- Minimum speed threshold
- Entry angle within acceptable range
- No active jump input at moment of contact

**Outputs:** Events — `OnWallAttach`, `OnWallDetach`, `OnWallExit`

WallRiding notifies GravitySystem of state changes. GravitySystem owns the gravity direction.

---

### DynamicCamera

**Responsibility:** Follow the vehicle in a way that makes movement feel fast and readable.

**Inputs:** Vehicle velocity, vehicle orientation, GravitySystem attachment state
**Outputs:** Camera position, rotation, FOV value

Must not contain any game logic. It observes and responds. It never drives behavior.

---

### FlowSystem

**Responsibility:** Track the current Flow value and emit change events.

**Interface:**
```
FlowSystem.increase(amount: float, reason: String)
FlowSystem.decrease(amount: float, reason: String)
FlowSystem.get_multiplier() → float
FlowSystem.on_changed → Signal(new_value: float)
```

Stateless relative to the rest of the game — FlowSystem does not know about physics or cameras.

---

### ScoreSystem

**Responsibility:** Accumulate score during a run.

**Inputs:** Flow multiplier (from FlowSystem), style events (from VehiclePhysics / WallRiding)
**Outputs:** Current score, end-of-run summary

Simple accumulator. No persistence at prototype stage.

---

### ReplayRecorder

**Responsibility:** Record player inputs frame-by-frame for ghost replay.

**Interface:**
```
ReplayRecorder.start_recording()
ReplayRecorder.record_frame(input: InputFrame)
ReplayRecorder.stop_recording() → ReplayData
ReplayRecorder.play_back(data: ReplayData)
```

Stores only inputs, not positions. Playback re-runs the physics from the same starting state.

---

## Communication Patterns

Systems communicate through:
1. **Direct method calls** for synchronous, single-frame data (e.g., camera reading vehicle speed)
2. **Signals / Events** for state changes that multiple systems care about (e.g., `FlowSystem.on_changed`)

No global event bus at prototype stage. If two systems need to communicate, one calls the other or subscribes to a signal. If that gets unwieldy, revisit.

---

## What This Architecture Does NOT Include

These are explicitly absent until movement is proven:

- Scene management / screen transitions
- Save/load system
- Settings system
- Audio manager
- Achievement / progression system
- Any network layer
- Any backend connection

Adding them before movement is validated adds risk and maintenance cost with zero benefit.

---

## Iteration Principle

When movement doesn't feel right:

1. Change parameters in VehiclePhysics first
2. If parameters aren't enough, rewrite VehiclePhysics
3. If the physics model is wrong, replace the whole physics layer

Because VehicleController and GravitySystem are separate, a full physics rewrite should not break the camera or the flow system. That is the only invariant this architecture must protect.
