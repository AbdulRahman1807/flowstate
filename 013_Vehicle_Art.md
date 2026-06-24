# Task 013 — Vehicle Visual Design
## FLOWSTATE

---

## Goal

Replace the placeholder `BoxMesh` vehicle with a visually expressive stylised racer that reads correctly on the dark track, communicates speed state through emissive elements, and holds up under the `ComicPostFX` shader pass. The vehicle is the thing the player watches for every second of every run — it must look like it belongs in the world.

Design target (`04_Art_Direction`): abstract but instantly readable as a vehicle at speed; emissive elements respond to speed state; flat/toon-shaded rather than realistic; no licensed car references. Think aggressive low-body racing shell with large aerodynamic fins — geometric, not organic.

---

## Mesh Sourcing (pick one path)

### Path A — Blender MCP (recommended for the final vehicle)

Connect Claude Code to a running Blender instance via the `blender-mcp` addon. I script the vehicle geometry in Python/bpy — extrudes, bevels, modifiers, parametric proportions tuned to this game's camera distance and speed. Produces a purpose-built mesh with correct silhouette, hard-surface detail, and fin geometry that catches the ink outline well. Setup is a one-time session (~30 min) then a dedicated geometry session.

**Works best for:** the sleek futuristic aesthetic the game calls for. I'm strongest at procedural/geometric hard-surface — which is exactly right here (sharp fins, bevelled body panels, intake vents, emissive strips).

**Setup:** Install Blender + `blender-mcp` addon → run MCP server → add to Claude Code MCP settings. Separate session from this task.

### Path B — CC0 Asset Import (fastest path to unblock everything else)

Download [Kenney Vehicle Kit](https://kenney.nl/assets/vehicle-kit) (CC0, `.glb`). It includes a clean stylised low-body racing car that reads well at speed. Import into `flowstate/assets/meshes/vehicle_kenney.glb`, swap the BoxMesh reference in `Track_Circuit.tscn` and all test scenes.

**Works best for:** unblocking track visual baseline, audio, and VFX work immediately while the Blender vehicle is pending. Replace when Path A is done.

### Path C — Godot Primitives (zero external tools)

Construct a multi-part vehicle in `VehicleVisuals.gd`'s `_ready()` using `BoxMesh` + `CylinderMesh`:
- Main body: `BoxMesh(2.0, 0.6, 3.2)`, slightly tapered using `top_size`
- Rear fins: two thin `BoxMesh(0.08, 0.8, 0.9)` mounted at rear corners
- Underbody glow strip: `BoxMesh(1.2, 0.06, 2.8)` flush under the body
- Wheel cylinders: four `CylinderMesh(r=0.35, h=0.25)` at corners

Silhouette is blockier than A or B but the emissive behaviour and material system is identical.

---

## Visual Requirements

Regardless of which path produces the mesh, the vehicle in-game must satisfy:

| Requirement | Detail |
|---|---|
| Silhouette reads at speed | From 8 units behind (camera distance), the vehicle's outline is unambiguous — not a featureless blob |
| Low aggressive profile | Centre of mass visual sits low; fins or spoiler at rear |
| No realistic details | No door handles, mirrors, exhaust pipes, or branded elements |
| Works inverted | Silhouette must read when the camera is upside-down (ceiling traversal) |
| Dark base material | Body albedo in the `#1A1A2E` – `#0D0D14` range, unshaded, so the emissives pop against it |

---

## Materials

Three material types on the vehicle. All `StandardMaterial3D`, `SHADING_MODE_UNSHADED`.

### Body Material
```gdscript
albedo_color = Color(0.08, 0.08, 0.14)   # near-black with a cool blue tint
shading_mode = SHADING_MODE_UNSHADED
cull_mode = CULL_BACK
```

### Emissive Strip Material (undercarriage + fin edges)
```gdscript
albedo_color = Color(0.0, 0.0, 0.0)
emission_enabled = true
emission = Color(0.0, 1.0, 0.8)          # electric cyan (04 palette)
emission_energy_multiplier = 1.2          # base glow (driven up at speed by VehicleVisuals)
shading_mode = SHADING_MODE_UNSHADED
```

### Boost Trail Material (rear-facing quad, visible only while boosting)
```gdscript
albedo_color = Color(0.0, 0.0, 0.0, 0.0)
emission_enabled = true
emission = Color(1.0, 0.18, 0.47)        # hot magenta (04 palette)
emission_energy_multiplier = 2.0
transparency = TRANSPARENCY_ALPHA
shading_mode = SHADING_MODE_UNSHADED
blend_mode = BLEND_MODE_ADD
```

---

## VehicleVisuals.gd

New passive observer script. Node type: `Node3D`, child of `Vehicle`.

**Responsibility:** Read `VehiclePhysics` getters each frame and push `emission_energy_multiplier` overrides to the emissive materials. No writes to gameplay. Same pattern as `WallVFX.gd`.

### What it drives

| Element | At rest | At top speed | Boost active |
|---|---|---|---|
| Undercarriage emissive | `1.2` | `2.8` | `3.5` |
| Engine glow (rear panel) | `0.4` | `1.8` | `2.5` |
| Boost trail mesh | `visible = false` | `visible = false` | `visible = true` |
| Boost trail energy | — | — | `2.0 + sin(time * 8) * 0.4` (pulse) |

### Interface

```gdscript
class_name VehicleVisuals
extends Node3D

@export var vehicle_path: NodePath
@export var glow_idle: float = 1.2
@export var glow_max: float = 2.8
@export var glow_boost: float = 3.5
@export var engine_glow_idle: float = 0.4
@export var engine_glow_max: float = 1.8
@export var engine_glow_boost: float = 2.5
@export var boost_pulse_rate: float = 8.0      # Hz of the boost trail pulse
@export var enabled: bool = true

var _vehicle: VehiclePhysics
var _emissive_mats: Array[StandardMaterial3D]  # filled in _ready from child MeshInstances
var _boost_trail: MeshInstance3D
```

In `_physics_process(delta)`:
1. Read `speed_ratio = _vehicle.get_speed() / _vehicle.max_speed`
2. Lerp each emissive material's `emission_energy_multiplier` toward the target value (lerp rate ~8.0/s — smooth, not instant)
3. If `_vehicle.is_boost_active()`: lerp toward `glow_boost`, set `_boost_trail.visible = true`, apply pulse
4. Else: lerp toward `lerp(glow_idle, glow_max, speed_ratio)`, set `_boost_trail.visible = false`

---

## File Structure

```
flowstate/
├── assets/
│   └── meshes/
│       └── vehicle_kenney.glb     # or the Blender-exported .glb (Path A)
├── scripts/
│   └── vehicle/
│       └── VehicleVisuals.gd      # NEW passive observer
```

`VehicleVisuals` is added as a child of the Vehicle node in every scene that has a vehicle (`Track_Circuit`, `Test_Playground`, all test scenes).

---

## Constants Reference (all `@export`)

| Param | Default | Meaning |
|---|---|---|
| `glow_idle` | 1.2 | Emissive energy at rest |
| `glow_max` | 2.8 | Emissive energy at top speed |
| `glow_boost` | 3.5 | Emissive energy while boosting |
| `engine_glow_idle` | 0.4 | Engine panel energy at rest |
| `engine_glow_max` | 1.8 | Engine panel energy at top speed |
| `engine_glow_boost` | 2.5 | Engine panel energy while boosting |
| `boost_pulse_rate` | 8.0 | Boost trail oscillation rate (Hz) |

---

## Acceptance Criteria

| Criteria | How to Test |
|---|---|
| Vehicle reads as a vehicle at speed | Open Track_Circuit, drive at top speed — silhouette is clearly a racer, not a box |
| Emissive undercarriage visible on dark track | At rest, the cyan undercarriage glow is visible against the dark surface |
| Glow brightens at speed | Accelerate from 0 to max — emissive energy visibly increases |
| Boost trail appears | Activate boost — magenta trail pops on and pulses, disappears on cooldown |
| Works inverted | Drive a loop — vehicle reads correctly upside-down |
| No gameplay impact | No change to any probe output; `VehicleVisuals` has no writes to physics state |

---

## Status
Not started. Depends on: none (can be done in parallel with 014).
Blocks: `016_VFX_Pass.md` (ComicPostFX outline pass looks wrong on a BoxMesh).

## Mesh Sourcing Decision
Use Path B (Kenney CC0 import) to unblock everything immediately. Schedule a dedicated Blender MCP session to build the final vehicle when the rest of the visual layer is working. Swap the mesh then — `VehicleVisuals.gd` and the material system are identical regardless of mesh source.
