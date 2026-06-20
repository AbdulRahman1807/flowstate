# Task 002 — Dynamic Camera
## FLOWSTATE

---

## Goal

Implement a camera system that makes movement feel fast, readable, and cinematic. The camera is not a passive follower — it is an active participant in communicating speed and skill.

This task can be developed in parallel with Task 001. It requires a moving vehicle to test against, but does not depend on wall riding or gravity transitions.

---

## Requirements

### Functional Requirements

- Camera follows the vehicle from a third-person perspective
- Camera position has a configurable follow offset (height, distance behind vehicle)
- FOV expands as vehicle speed increases
- FOV contracts when vehicle decelerates
- Camera tilts slightly into turns (roll relative to steering direction)
- Camera has a configurable lag behind the vehicle — slightly behind at high speed, tight at low speed
- Camera responds to landing impact: brief downward dip, then recovery
- Camera must support arbitrary up-direction (required for wall riding and ceiling traversal in later tasks — build this now to avoid a rewrite)
- Camera smoothly interpolates all transitions — no snapping

### Non-Functional Requirements

- DynamicCamera script observes vehicle state only — no game logic
- All sensitivity values are exported for tuning
- Camera has no gimbal lock (use quaternion rotation, not euler angles)
- No camera clipping through track geometry (basic raycast check acceptable for prototype)
- 60fps at all times on M2 MacBook Air

---

## Acceptance Criteria

| Criteria | How to Test |
|----------|-------------|
| FOV visibly widens at top speed | Accelerate to max speed — field of view should noticeably expand |
| FOV contracts when braking | Hold brake from top speed — FOV narrows proportionally |
| Camera tilts into turns | Steer hard at speed — camera roll is visible and feels natural |
| Camera lag is perceptible at high speed | At top speed, make a sharp direction change — camera follows with a brief trail effect |
| Landing impact creates camera dip | Jump and land — camera briefly pushes down, then recovers smoothly |
| Camera up-direction can be overridden | (Test manually in editor) Set camera up to (0,-1,0) — camera renders correctly inverted |
| No snapping or jarring transitions | All camera movements are smooth interpolations — no single-frame jumps |
| All tuning parameters are editable in inspector | Open DynamicCamera in editor — FOV range, lag strength, tilt angle all visible |

---

## Suggested File Structure

```
scripts/
└── camera/
    └── DynamicCamera.gd
        # Observes: vehicle velocity, vehicle orientation, surface attachment state
        # Outputs: camera position, rotation, FOV
        # No game logic

scenes/
└── tests/
    └── Test_CameraResponse.tscn
        # Same flat test track from Task 001
        # Vehicle + DynamicCamera wired together
        # Debug overlay showing current FOV value and speed
```

---

## Exported Tuning Parameters (minimum)

```gdscript
@export var follow_distance: float = 8.0
@export var follow_height: float = 3.0
@export var fov_min: float = 75.0
@export var fov_max: float = 100.0
@export var fov_speed_range: Vector2 = Vector2(0.0, 40.0)  # min/max speed for FOV mapping
@export var camera_lag: float = 0.15           # seconds of positional lag
@export var tilt_strength: float = 0.08        # radians of tilt per unit of steer
@export var tilt_smoothing: float = 6.0
@export var landing_dip_strength: float = 0.4
@export var landing_dip_recovery: float = 8.0
```

---

## Implementation Notes

### Up-Direction Support

The camera's up vector must be driven by the GravitySystem (Task 003), not assumed to be world-up. Scaffold this now even though GravitySystem doesn't exist yet:

```gdscript
var camera_up: Vector3 = Vector3.UP  # Will be replaced by GravitySystem output in Task 003

func _update_orientation():
    # Use camera_up instead of Vector3.UP everywhere
    # This makes the Task 003 integration a one-line change
```

### FOV Mapping

Map vehicle speed to FOV using a curve rather than a linear ramp. Ease in at low speed, faster response at mid-speed, plateau at max:

```gdscript
func _get_target_fov(speed: float) -> float:
    var t = clamp(speed / max_speed, 0.0, 1.0)
    var curved_t = ease(t, -2.0)  # ease-in-out curve
    return lerp(fov_min, fov_max, curved_t)
```

### Quaternion Rotation

Avoid `look_at()` when the up-direction can change. Use quaternion slerp:

```gdscript
var target_rotation = Quaternion(desired_basis)
camera.quaternion = camera.quaternion.slerp(target_rotation, delta * smoothing)
```

---

## Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Euler angle gimbal lock on ceiling | High (if not addressed) | Use quaternions from the start — do not convert |
| Camera clipping through geometry | Medium | Basic sphere-cast between camera and vehicle |
| FOV change causes motion sickness in testing | Medium | Keep FOV range conservative (75–100), test early |
| Lag feels sluggish rather than stylish | Medium | Tune lag with a velocity-blended approach, not just position lerp |
| Camera tilt conflicts with gravity tilt in Task 003 | Medium | Keep steering tilt as a local offset on top of gravity-aligned orientation |

---

## Future Considerations

*Do not implement these in this task.*

- Task 003 will replace the hardcoded `camera_up = Vector3.UP` with GravitySystem output
- A cinematic replay camera mode may be added post-validation milestone
- Camera shake on boost activation is a VFX pass task, not a camera architecture task
- Dolly zoom (Hitchcock zoom) effect at max Flow could be explored as a feel enhancement after M5
