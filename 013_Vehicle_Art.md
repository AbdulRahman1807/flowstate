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

## As-Built (2026-06-25) — Toyota AE86

Dev supplied a **Toyota AE86 Sprinter Trueno** glTF (Sketchfab, `FoG Ryû`) — clean flat panels + hard lines, a strong fit for the cel/comic look (dev reference: a cel-shaded drifting-AE86 Sketchfab model, their own colours + graffiti on top). Moved into `flowstate/assets/meshes/ae86.glb` and imported (Godot extracted 32 PBR textures alongside it).

**Mesh facts (from headless inspection):**
- **Scale:** model is in **centimetres** (4.23 m car = 423 units) → instance scale **×0.01**.
- **Facing:** front (headlights) is at **+Z**; Godot forward is −Z → **rotate 180° about Y**.
- **Placement transform** (child of `Vehicle`, both scenes): `Transform3D(-0.01, 0, 0, 0, 0.01, 0, 0, 0, -0.01, 0, -1.5, 0)` (scale 0.01 + 180° Y, y −1.5). **Float fix (dev eyeball round 1):** the car first sat at y −0.8 and floated **0.706 m** above the deck — measured in-scene (`_ae86_fit` throwaway): the vehicle rests at origin y 1.5 while the deck is at y 0 (the collision capsule itself hovers ~0.7 — a pre-existing quirk the box hid). Dropped the visual to y −1.5 so the wheels meet the deck; collision/physics untouched.
- **Camera (dev: "too small"):** the car is realistically sized (4.23 m in a 12 m lane), so the fix is **framing, not scale** — pulled `DynamicCamera` `follow_distance` 8→6 and `follow_height` 3→2.4 so it reads bigger without widening the visual-vs-capsule overhang. Scale (`0.01`) and these camera knobs are all live for taste.
- **Structure** (useful for emissive targeting in stage 2 / cel shader in 016): `RootNode → Interior, SteeringWheel, CarBody, Headlights, FL/FR/RL/RR`. Body panels are split: `CarBody_Primary_0` (main paint), `CarBody_Secondary_0`, `CarBody_Trim1/2_0`, `CarBody_Windows_0`, `CarBody_LampCovers_0`, `CarBody_TailightFrame_0`, `CarBody_Reflector_0`, `CarBody_Trueno_0` (decal). Lights: `Headlights_*`. Wheels are **`VehicleWheel3D`** nodes (built for `VehicleBody3D`; harmless here — no runtime spam observed — but they won't spin since we drive a `CharacterBody3D`).

⚠️ **PERF:** ~**420k vertices / 37 meshes / 32 textures / 83 MB**. The ghost run `duplicate()`s the whole vehicle → ~840k verts on screen. It loads + the probes are green, but this is the top framerate risk on the M2 (PRD wants lightweight). **Recommend a decimated / texture-baked re-export** once the look is locked (016 puts a flat cel shader over the body, so most PBR detail is redundant). Not blocking.

### Done
- AE86 imported + instanced into `Track_Circuit.tscn` and `Test_Playground.tscn` (replaced the placeholder BoxMesh). Collision is still the capsule — visual only.
- Verified headless: both scenes load, `_CircuitSmokeProbe` / `_PlaygroundReplayProbe` PASS with **identical physics** (113.9 m, min-y 1.50); ghost duplication works with the heavier mesh.

### Dev eyeball round 2 (2026-06-25) — float varied by section + arrow collision
- **Submerging in some sections (fixed properly):** the static −1.5 offset floated on box decks but **submerged the car on ramps / ribbon arcs / loops**, because the collision capsule hovers above the surface by a *varying* amount per section. Replaced the fixed offset with **`VehicleVisuals.gd`** — a passive node (child of `Vehicle`) that each physics frame raycasts down the car's own −Y to the real surface and snaps the mesh's local Y so the wheels sit on it (flat / ramp / loop / wall all handled; airborne → wheels ease to `airborne_offset`). Writes only the mesh child's Y — physics untouched. Verified: holds −1.5 on the flat deck, no errors, adapts elsewhere. Knobs: `wheel_offset`, `snap_smoothing`, `airborne_offset`, `enabled`.
- **Car collided with the arrow chevrons (fixed):** `_arrows_along` built them with `_add_box` (StaticBody + collision). Now `_add_edge_box` (visual-only MeshInstance) — arrows are decoration, no collision. (All other CircuitBuilder/PlaygroundBuilder decorations were already visual-only.)

### Dev eyeball round 3 (2026-06-25) — landings snapped flat with no weight
Dev: falling/nosediving, the car snapped instantly flat on touchdown ("like nothing happened"). Chose **A2+B1+B2+B3**. Implemented as VISUAL-only (physics body still snaps flat so momentum is preserved — easing the physics orientation would point forward into the ground and `move_and_slide` would bleed speed):
- **A2 — landing pitch settle** (`VehicleVisuals`): physics snaps flat, but the mesh keeps the dive pitch (read from new `VehiclePhysics.get_last_landing_pitch()`, captured pre-snap) and eases to flat over ~0.3s, **pivoting about a point near the front** (`landing_pivot_forward`) so a nosedive lifts the rear down instead of burying the nose (no ground clip). Verified: continues at the dive angle, eases to level.
- **B1 — suspension squash:** on impact, compress the mesh vertically (scale Y, scaled by impact, eased back) around the wheels — weight, no physics bounce. Verified scale.y 0.01→0.0086→0.00999.
- **B2 — nose-dip:** a small extra nose-down on impact folded into the settle pitch (front suspension compress), eases out.
- **B3 — camera:** `DynamicCamera.landing_dip_strength` 0.4→0.65, recovery 8→6 so landings punch.

`VehicleVisuals` now OWNS the mesh's local transform (captures base scale + 180° yaw in `_ready`, recomposes each frame = ground-snap height + squash + pivot-pitch). Knobs: `landing_settle_recovery`, `landing_settle_max_deg`, `landing_pivot_forward`, `nose_dip_scale`, `squash_scale/max/recovery`, `land_min_impact`. No physics/probe regression (18/26, same 8 pre-existing).

### Pending (needs a dev eyeball — headless can't render)
- Confirm the car now sits planted across all sections (ramps, the two loops, wall runs) and the framing feels right; tweak `wheel_offset` / `snap_smoothing` on `VehicleVisuals`, the transform `0.01` (size), or the camera knobs as needed.
- Then the rest of `VehicleVisuals.gd`: **speed-reactive emissives** (underglow + headlight/taillight glow; the car's own PBR materials stay until 016's cel pass), and the cel shader (016).

## Status
**Stage 1 done (mesh in-scene, physics-clean); VehicleVisuals + cel shader pending a visual confirm.** Blocks: `016_VFX_Pass.md`. The Blender-MCP custom-vehicle path is moot for now — the AE86 is the vehicle.
