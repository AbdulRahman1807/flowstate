# Task 016 — VFX Pass
## FLOWSTATE

---

## Goal

Apply the `04_Art_Direction` "moving graffiti mural" visual language on top of the substrate built in `013`–`015`. This task has four parts that build on each other:

- **A:** Wire `ComicPostFX` into the game scenes and enable `WallVFX` sparks
- **B:** Make `ComicPostFX` reactive to Flow multiplier and vehicle speed
- **C:** Add speed lines to the shader (the `04_Art_Direction` #1 speed feedback tool)
- **D:** Add comic onomatopoeia HUD feedback — trick names, bonuses, saves slamming onto screen

Parts A and B are not optional — they are what makes the game look like itself. Parts C and D are the "loud and poppy" layer on top.

**Depends on `013_Vehicle_Art.md` and `014_Track_Visual_Baseline.md` being done first.** Running ComicPostFX on a grey-box world before the dark substrate exists will produce wrong-looking results and mislead the tuning.

---

## Part A — ComicPostFX Wiring + WallVFX Enable

### ComicPostFX

`scenes/fx/ComicPostFX.tscn` is a complete, shelf-ready `CanvasLayer`. It has never been added to any playable scene. Add it as a direct child of:
- `Track_Circuit.tscn` (the main play scene)
- `Test_Playground.tscn` (the moveset validation bed)

No script changes. Just the scene instance. `ComicPostFX.gd`'s `_process()` already pushes all uniforms to the shader each frame — it works from the moment it's in the scene tree.

**After wiring, verify the static defaults look correct on the dark track before proceeding to Part B:**
- Halftone dots should appear in the shadow areas of the track (not on bright emissive edges)
- Ink outline should darken the edges of the vehicle and track geometry
- Chromatic aberration should be a subtle edge split, not a distracting smear

Adjust `master_mix`, `halftone_intensity`, and `outline_intensity` exports on the `ComicPostFX` node in the scene inspector if the static defaults feel too heavy or too light on the new dark environment.

### WallVFX

`WallVFX` is already in `Track_Circuit.tscn` (and `Test_Playground.tscn` via `PlaygroundBuilder`'s vehicle). It is set to `enabled = false` in the script default. Enable it:

In `Track_Circuit.tscn`, on the `WallVFX` node: set `enabled = true`.

The spark burst system (glow texture, hot-palette ramp, gravity arc) is fully built — it will immediately produce spark bursts on wall attach, wall jump, wall detach, near miss, ground jump, and landing events.

**Tune `burst_amount`, `spark_size`, and `burst_speed`** against the dark background — the sparks were designed for the `04` dark palette and should read well, but the exact values may need minor adjustment.

---

## Part B — ComicPostFXDriver.gd (Flow + Speed Reactivity)

New passive observer. `Node` child of the scene root (sibling of `ComicPostFX`). Reads `FlowSystem` and `VehiclePhysics` each frame, overrides `ComicPostFX`'s uniform values live.

This is what makes the game's visual intensity escalate with the player's skill — the core of the `04_Art_Direction` Flow escalation vision.

### Flow escalation table

| Flow multiplier | `halftone_intensity` | `halftone_scale` | `outline_intensity` | Feel |
|---|---|---|---|---|
| ×1.0 (base) | 0.18 | 140 | 0.50 | Subtle — clean |
| ×1.4 | 0.25 | 130 | 0.58 | Becoming visible |
| ×1.7 | 0.35 | 118 | 0.65 | Clearly comic |
| ×2.0 (max) | 0.50 | 105 | 0.75 | Fully saturated, ink-heavy |

Values lerp continuously — no step transitions. Lerp rate: `flow_lerp_speed = 3.0` per second (smooth, not instant).

### Speed reactivity (chromatic aberration)

`aberration_intensity` is driven by speed, not Flow — it communicates forward velocity, not style:

```gdscript
var speed_ratio := vehicle.get_speed() / vehicle.max_speed  # 0..1
var target_ca := lerp(aberration_idle, aberration_max, pow(speed_ratio, 2.0))
```

`pow(speed_ratio, 2.0)` keeps CA near-zero at mid-speed and ramps hard only near the top — so it feels like "I'm really flying" rather than a constant smear.

### Boost spike

When `vehicle.is_boost_active()` transitions to true, spike `aberration_intensity` to `aberration_boost_spike` over 0.05s, then let it decay back to the speed-mapped value over 0.4s. This is the camera-shake equivalent for a no-audio moment.

### Interface

```gdscript
class_name ComicPostFXDriver
extends Node

@export var fx_path: NodePath             # path to ComicPostFX node
@export var vehicle_path: NodePath
@export var flow_system_path: NodePath

# Flow ramp
@export var flow_lerp_speed: float = 3.0
@export var halftone_at_min_flow: float = 0.18
@export var halftone_at_max_flow: float = 0.50
@export var halftone_scale_at_min: float = 140.0
@export var halftone_scale_at_max: float = 105.0
@export var outline_at_min_flow: float = 0.50
@export var outline_at_max_flow: float = 0.75

# Speed / CA ramp
@export var aberration_idle: float = 0.08
@export var aberration_max: float = 0.45
@export var aberration_boost_spike: float = 0.85
@export var aberration_boost_decay: float = 0.4   # seconds to return to speed-mapped value

@export var enabled: bool = true
```

`ComicPostFXDriver` calls `fx.halftone_intensity = target`, `fx.outline_intensity = target`, etc. directly on the `ComicPostFX` node — overriding its own `@export` values at runtime. `ComicPostFX`'s inspector values become the "no-driver" fallback.

---

## Part C — Speed Lines (Shader Addition)

Add a fifth effect block to `comic_post_fx.gdshader`: a **radial streak pass** — UV-space rays radiating from screen centre outward, intensity zero at rest and scaling with a `speed_intensity` uniform.

### Why a shader effect not particles

Speed lines at screen-space are most correctly a full-screen UV effect — they radiate from the vanishing point (screen centre), respond to the full viewport, and cost less than a particle system at this scale. `ComicPostFX` is already a full-screen pass, so adding a fifth effect block is a zero-overhead extension of existing work.

### Shader additions to `comic_post_fx.gdshader`

New uniforms:
```glsl
uniform float speed_lines_intensity : hint_range(0.0, 1.0) = 0.0;  // 0 = off, driven by ComicPostFXDriver
uniform float speed_lines_count : hint_range(4.0, 64.0) = 24.0;    // number of streak directions
uniform float speed_lines_length : hint_range(0.0, 1.0) = 0.6;     // how far from centre streaks extend
uniform float speed_lines_width : hint_range(0.0, 0.5) = 0.04;     // angular width of each streak
uniform vec3  speed_lines_color : source_color = vec3(1.0, 1.0, 1.0);  // streak colour (white, blends additive)
```

Fragment shader block (after the halftone block, before master wet/dry):
```glsl
if (speed_lines_intensity > 0.0001) {
    vec2 from_center = uv - vec2(0.5);
    float dist = length(from_center);
    float angle = atan(from_center.y, from_center.x);

    // Discrete streak directions (like comic speed lines)
    float sector = TAU / speed_lines_count;
    float nearest_spoke = round(angle / sector) * sector;
    float angle_diff = abs(mod(angle - nearest_spoke + PI, TAU) - PI);

    // Streak: thin angular slice, fading with distance from centre, not beyond length
    float in_streak = step(angle_diff, speed_lines_width * 0.5);
    float streak_fade = smoothstep(0.0, 0.15, dist) *               // fade near centre
                        smoothstep(speed_lines_length, speed_lines_length * 0.6, dist); // fade at tip

    float streak = in_streak * streak_fade * speed_lines_intensity;
    col = mix(col, col + speed_lines_color * streak, streak);
}
```

`ComicPostFXDriver` drives `speed_lines_intensity = pow(speed_ratio, 1.5)` — zero at rest, building strongly near top speed. Result: at full speed the screen has faint white radial streaks like a comic speed panel; at rest the effect is completely invisible.

New `@export` in `ComicPostFX.gd`:
```gdscript
@export_group("Speed Lines")
@export var speed_lines_on: bool = true
@export_range(0.0, 1.0) var speed_lines_intensity: float = 0.0
@export_range(4.0, 64.0) var speed_lines_count: float = 24.0
@export_range(0.0, 1.0) var speed_lines_length: float = 0.6
@export_range(0.0, 0.5) var speed_lines_width: float = 0.04
@export var speed_lines_color: Color = Color(1, 1, 1)
```

---

## Part D — EventPopups.gd (Comic Onomatopoeia HUD Feedback)

New `EventPopups.gd`, `CanvasLayer` at layer **50** (above the 3D scene, below `ComicPostFX` at layer 100, above `PlayHUD` at layer 10). Spawns styled label pop-ups when key events fire.

This is the "loud, poppy, comic book" layer the current minimal HUD does not provide. `PlayHUD`'s top-bar (flow, score, timer) stays as-is — `EventPopups` is additive.

### Pop-up events

| Event | Signal | Text | Colour | Size |
|---|---|---|---|---|
| Wall save | `WallRiding.on_wall_save` | **SAVE!** | `COL_YELLOW` | 88px |
| Clean trick (≥360°) | `VehiclePhysics.trick_landed(deg≥360, true)` | **TRICK!** + `+Npts` sub-label | `COL_CYAN` | 72px |
| Clean trick (<360°) | `VehiclePhysics.trick_landed(deg<360, true)` | **TRICK** (no sub-label) | `COL_CYAN` | 56px |
| Botched trick | `VehiclePhysics.trick_landed(_, false)` | **BAILED** | `COL_WHITE`, 60% alpha | 40px |
| Wall jump | `WallRiding.on_wall_jump` | **WALL JUMP** | `COL_MAGENTA` | 52px |
| Near miss | `WallRiding.on_near_miss` | **NEAR MISS** | `COL_YELLOW` | 48px |
| Clean landing | `VehiclePhysics.clean_landing` | **CLEAN** | `COL_WHITE` | 40px |
| Loop entered | `GravitySystem.on_state_changed` → INVERTED | **LOOP!** | `COL_CYAN` | 56px |
| New personal best | `RunManager.on_run_finished` (was_last_run_best) | **★ NEW BEST ★** | `COL_YELLOW` | 96px, full-width |

Colours from `PlayHUD`'s existing constants: `COL_CYAN`, `COL_MAGENTA`, `COL_YELLOW`, `COL_WHITE`.

### Pop-up behaviour (the comic slam)

Each pop-up is a `Label` node spawned dynamically in `EventPopups`'s `CanvasLayer`:

1. **Spawn position:** Bottom-centre of screen, stacked upward from `y_anchor` (default: 72% down the screen height). Each new pop-up spawns at the top of the current stack. Max stack height: 4 items — oldest pops off when a 5th arrives.

2. **Entry animation (the "slam"):**
   - Frame 0: scale `1.5`, alpha `1.0`
   - Tween to scale `1.0` over `slam_duration` (0.08s) using `EASE_OUT` — fast, punchy, comic impact
   - Large thick outline (`font_outline_size = font_size / 4`) so text reads against any background

3. **Hold:** `hold_duration` (0.7s) at full opacity + scale 1.0

4. **Exit:** Tween alpha `1.0 → 0.0` and position `y - 20px` over `fade_duration` (0.25s). Remove node on completion.

5. **★ NEW BEST ★** is special: spawns centred on screen (not in the stack), larger, holds for 1.5s, no stacking.

### Interface

```gdscript
class_name EventPopups
extends CanvasLayer

@export var vehicle_path: NodePath
@export var wall_riding_path: NodePath
@export var run_manager_path: NodePath
@export var score_system_path: NodePath
@export var gravity_system_path: NodePath

@export var y_anchor: float = 0.70          # 0..1, fraction of screen height from top
@export var slam_duration: float = 0.08     # seconds for the scale-slam entry
@export var hold_duration: float = 0.70     # seconds at full opacity
@export var fade_duration: float = 0.25     # seconds to fade out
@export var stack_spacing: float = 10.0     # px between stacked items
@export var max_stack: int = 4              # oldest item removed when exceeded

@export var enabled: bool = true
```

### Font style

Same `_make_label()` pattern as `PlayHUD` — `Label.add_theme_font_size_override`, `add_theme_color_override`, and a thick `font_outline_size` (font_size / 4, minimum 8). No custom font asset needed for the scratch pass — the system font reads well at this size with the strong outline. A graffiti/bold font can drop in later.

---

## File Structure

```
flowstate/
├── scenes/
│   ├── Track_Circuit.tscn          # Add ComicPostFX instance, set WallVFX.enabled=true
│   └── tests/
│       └── Test_Playground.tscn    # Add ComicPostFX instance, set WallVFX.enabled=true
└── scripts/
    ├── fx/
    │   ├── ComicPostFX.gd          # Add speed_lines @export group
    │   └── ComicPostFXDriver.gd    # NEW reactive driver
    └── systems/
        └── EventPopups.gd          # NEW comic onomatopoeia layer
```

`shaders/comic_post_fx.gdshader` — add speed lines uniforms and fragment block (Part C).

---

## Implementation Order (within this task)

1. **Part A first** — wire and verify static defaults look correct
2. **Part B** — add reactivity, tune the Flow escalation curve
3. **Part C** — add speed lines, verify they disappear at rest and read at top speed
4. **Part D** — add EventPopups, trigger each event type to verify the slam animation

Do not proceed to the next part until the current part looks correct. ComicPostFX tuning is feel-based and should be done with the dev driving the circuit.

---

## Constants Reference

### ComicPostFX.gd (new speed lines group)
| Param | Default | Meaning |
|---|---|---|
| `speed_lines_on` | true | Toggle speed lines effect |
| `speed_lines_intensity` | 0.0 | Driver-controlled; 0 = invisible |
| `speed_lines_count` | 24.0 | Number of streak directions |
| `speed_lines_length` | 0.6 | Streak reach from screen centre |
| `speed_lines_width` | 0.04 | Angular width of each streak |

### ComicPostFXDriver.gd
| Param | Default | Meaning |
|---|---|---|
| `halftone_at_min_flow` | 0.18 | Halftone intensity at ×1.0 Flow |
| `halftone_at_max_flow` | 0.50 | Halftone intensity at ×2.0 Flow |
| `outline_at_min_flow` | 0.50 | Outline intensity at ×1.0 Flow |
| `outline_at_max_flow` | 0.75 | Outline intensity at ×2.0 Flow |
| `aberration_idle` | 0.08 | CA at rest |
| `aberration_max` | 0.45 | CA at top speed |
| `aberration_boost_spike` | 0.85 | CA spike on boost activation |
| `flow_lerp_speed` | 3.0 | How fast effect values track Flow changes |

### EventPopups.gd
| Param | Default | Meaning |
|---|---|---|
| `y_anchor` | 0.70 | Vertical position of pop-up stack |
| `slam_duration` | 0.08 | Entry slam animation duration |
| `hold_duration` | 0.70 | Time at full opacity |
| `fade_duration` | 0.25 | Exit fade duration |
| `max_stack` | 4 | Max simultaneous pop-ups |

---

## Acceptance Criteria

| Criteria | How to Test |
|---|---|
| Shader visible on dark track | Open Track_Circuit — halftone dots in shadows, ink outline on vehicle and track edges |
| Sparks on wall events | Attach to a wall — spark burst fires; wall jump — big launch pop |
| Flow escalation visible | Build to ×2.0 Flow — halftone becomes denser, outline thicker vs ×1.0 baseline |
| Speed drives CA | At max speed, subtle chromatic aberration at screen edge; at rest it disappears |
| Speed lines appear at top speed | Accelerate to max — faint radial streaks appear; at rest they are invisible |
| Boost spikes CA | Activate boost — brief screen-edge split spike, decays over 0.4s |
| SAVE! appears on wall save | Execute a wall save — "SAVE!" slams onto screen with yellow text |
| Trick name appears on clean trick | Land a clean trick — "TRICK!" or "TRICK! +Npts" appears cyan |
| Pop-ups stack without colliding | Chain two events quickly — both appear stacked, not overlapping |
| ★ NEW BEST ★ is full-screen | Beat your best run — large centred callout, not in the stack |
| No gameplay regressions | All probes pass unchanged |

---

## Status
Not started. Depends on: `013_Vehicle_Art.md` (Part A meaningless on a BoxMesh), `014_Track_Visual_Baseline.md` (shader tuning requires the dark substrate).
Blocks: M5 human tester exit condition — this is what makes runs shareable and replay moments feel earned.

## Future Considerations
*Not in this task.*
- Cel shader on the vehicle body (`vfx_sources`: Complete Cel Shader for Godot 4, MIT) — would be added as a spatial shader on the vehicle mesh, not a canvas_item pass
- Camera shake on boost (`002_Dynamic_Camera.md` explicitly deferred here)
- Dolly zoom at max Flow (`002_Dynamic_Camera.md` post-validation)
- Per-surface ComicPostFX colour tint (walls slightly warm, ceiling slightly cool) — purely aesthetic
- Music reactivity (post-validation)
