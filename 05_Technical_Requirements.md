# Technical Requirements
## FLOWSTATE — Pre-Prototype Stage

---

## Development Environment

| Property | Value |
|----------|-------|
| Primary machine | MacBook Air M2, 8GB RAM |
| OS | macOS (arm64) |
| Target platform | Desktop (macOS primary, Windows secondary) |
| Development paradigm | Solo developer, AI-assisted |

---

## Engine Recommendation

### Recommended: Godot 4

**Rationale:**
- Free, open source, no royalties
- Native arm64 build for M2 — excellent performance on target hardware
- Built-in physics engine suitable for custom vehicle behavior
- GDScript or C# — both are AI-agent-friendly
- Lightweight project footprint — important with 8GB RAM
- No account system, no cloud dependency
- Active community and extensive documentation

**Alternative: Unity (URP)**
- Larger ecosystem
- More third-party vehicle physics assets
- Higher memory overhead
- Requires account and license management
- Acceptable if the developer has existing Unity proficiency

**Recommendation: Choose based on developer experience. If starting fresh, use Godot 4.**

---

## Performance Targets

| Metric | Target |
|--------|--------|
| Frame rate | 60fps locked on M2 MacBook Air |
| Physics tick rate | 60hz minimum (120hz preferred for smooth surface transitions) |
| Input latency | <1 frame at 60fps |
| Load time (prototype track) | <5 seconds |
| Memory usage | <2GB RAM total |
| Build size | <500MB |

---

## Physics Requirements

The vehicle physics system must satisfy the following:

- **Custom gravity direction** — gravity must be directable (not always world-down)
- **Surface normal detection** — vehicle must detect and align to surface normals
- **Velocity preservation across gravity transitions** — speed must not be destroyed by surface changes
- **No physics-engine jitter on surface edges** — transitions must not produce bounce artifacts
- **Deterministic enough for ghost replay** — same inputs must produce consistent results

Standard ragdoll or rigid body physics are insufficient. A custom physics layer is required on top of whatever the engine provides.

---

## Input Requirements

| Input Method | Required |
|--------------|---------|
| Gamepad (XInput / DInput) | Required — primary input |
| Keyboard | Required — development fallback |
| Mouse | Not required for prototype |

Input must be:
- Polled every physics frame, not every render frame
- Remappable in final product (not required for prototype)

---

## Camera Requirements

- Camera must support arbitrary up-direction (for ceiling traversal)
- Camera lag and FOV adjustment must be configurable via exposed parameters
- No gimbal lock on surface transitions
- Smooth interpolation between all states

---

## Replay Requirements (Prototype)

For prototype, replay is defined as: **recording inputs and replaying them deterministically.**

- Record: player inputs per physics frame + timestamp
- Playback: reapply inputs to a ghost vehicle running alongside or after the player
- Storage: in-memory only, no file system persistence required at prototype stage

---

## Out of Scope — Technical

These systems must not be designed for or referenced in prototype architecture:

| System | Status |
|--------|--------|
| Backend / server | Out of scope |
| Account / auth system | Out of scope |
| Cloud saves | Out of scope |
| Online leaderboards | Out of scope |
| Real-time networking | Out of scope |
| DLC / asset streaming | Out of scope |
| Anti-cheat | Out of scope |
| Analytics | Out of scope |
| Crash reporting | Out of scope |

---

## Code Quality Standards (Prototype)

These standards exist to support AI-assisted development and fast iteration:

- All systems are contained in clearly named files with single responsibilities
- No singletons except for core systems (GameManager, FlowSystem)
- No premature optimization — write clear code first
- Every public method has a one-line comment
- No framework abstractions before the system exists and works
- Prototype code is allowed to be messy — **it must not be coupled**

Coupling is the primary risk. A bad physics implementation should be replaceable without touching the camera system.
