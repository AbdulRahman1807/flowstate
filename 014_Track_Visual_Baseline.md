# Task 014 — Track Visual Baseline
## FLOWSTATE

---

## Goal

Make the world look like `04_Art_Direction` before any post-processing shader is applied. Right now the game opens to a default sky, grey procedural geometry, and a white-background world. This task sets the substrate everything else builds on:

- Near-black `#0D0D14` background — so emissive elements pop and the `ComicPostFX` Sobel pass finds real contrast to ink
- Dark, tinted track and wall surfaces — floor, wall, and ceiling surfaces are visually distinct from each other but all dark
- **Emissive cyan edge lines on all track sections** — the primary navigational visual signal; makes the racing line unmistakable at speed
- Correct ambient lighting — very dim, directional, cool blue tint

This is a visual-only task. No physics, no gameplay, no signals.

---

## Environment

### Sky / Background

In `Track_Circuit.tscn`'s `WorldEnvironment` node, replace the `ProceduralSkyMaterial` with a flat colour:

```gdscript
environment.background_mode = Environment.BG_COLOR
environment.background_color = Color(0.05, 0.05, 0.08)   # #0D0D14 — near-black, cool blue tint
environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
environment.ambient_light_color = Color(0.04, 0.04, 0.08)
environment.ambient_light_energy = 0.3
```

Do the same for `Test_Playground.tscn` and any test scene that will be used for feel validation.

### Directional Light

Keep the existing `DirectionalLight3D` but dim it — the world should be lit, not bright:

```gdscript
light_energy = 0.6        # down from default 1.0
light_color = Color(0.8, 0.85, 1.0)   # cool white, not warm
shadow_enabled = true
```

---

## Track Materials

### CircuitBuilder.gd — Material Defaults

`CircuitBuilder` has eight distinct surface materials (`_mat_deck`, `_mat_accent`, `_mat_ramp`, `_mat_pad`, `_mat_wall`, `_mat_loop`, `_mat_floor`=recovery, `_mat_arrow`). One `@export` per material (a faithful superset of the original sketch — exposes every surface, no hardcoded colour) plus the edge-line group:

```gdscript
@export_group("Track Palette")
@export var col_deck: Color = Color(0.10, 0.10, 0.18)      # track surface — dark, cool
@export var col_accent: Color = Color(0.10, 0.13, 0.22)    # arcs / sweeping turns — slightly bluer
@export var col_ramp: Color = Color(0.15, 0.12, 0.10)      # ramps / humps — slightly warm
@export var col_pad: Color = Color(0.09, 0.16, 0.16)       # landing pads — slight teal (reads "safe")
@export var col_wall: Color = Color(0.14, 0.09, 0.17)      # walls / barriers — purple-grey, distinct
@export var col_loop: Color = Color(0.16, 0.10, 0.21)      # loops — distinct purple
@export var col_recovery: Color = Color(0.05, 0.05, 0.09)  # recovery floor — darkest, recedes
@export_group("Edge Lines")
@export var col_edge: Color = Color(0.0, 1.0, 0.8)         # electric cyan — edge lines
@export var edge_emission_energy: float = 2.0
@export var edge_width: float = 0.4
@export var edge_margin: float = 0.35
@export var edge_lift: float = 0.06
@export_group("Arrows")
@export var col_arrow: Color = Color(0.0, 1.0, 0.8)
@export var arrow_emission_energy: float = 1.4
```

Because field initialisers run before exports are applied, the `_mat_*` vars are declared-only and assigned in a `_build_materials()` called at the top of `_build()` (not at field-init). It uses the existing `_make_mat()` factory and the now-parameterised `_make_emissive(color, energy := 0.8)`.

### PlaygroundBuilder.gd — Material Defaults + Emissive Factory

`PlaygroundBuilder` had only `_mat(color)` with no emissive support. Add `_mat_emissive(color, energy)` (mirrors `CircuitBuilder._make_emissive()`, with `CULL_DISABLED` for the single-surface ribbons), the same declared-only `_mat_*` + `_build_materials()` deferral, and colour/edge exports for its six surfaces:

```gdscript
@export_group("Palette")
@export var col_floor: Color = Color(0.08, 0.09, 0.14)
@export var col_ramp: Color = Color(0.15, 0.12, 0.10)
@export var col_kicker: Color = Color(0.16, 0.13, 0.09)
@export var col_wall: Color = Color(0.10, 0.15, 0.18)
@export var col_loop: Color = Color(0.15, 0.10, 0.19)
@export var col_pillar: Color = Color(0.16, 0.09, 0.15)
@export_group("Edge Lines")
@export var col_edge: Color = Color(0.0, 1.0, 0.8)
@export var edge_emission_energy: float = 2.0
@export var edge_width: float = 0.4
@export var edge_lift: float = 0.06
```

The playground is a free-roam bed with discrete features (not one continuous lane), so emissive accents go on the **landmarks**: the half-loop's two ribbon edges (`_ribbon_edges`), each ramp's launch lip, the wall-ride / wall-hop wall tops, and a cap on every slalom pillar — so features read against the dark floor.

---

## Emissive Edge Lines

This is the most important visual element: thin emissive strips running along the left and right edges of every track section. They make the racing line unmistakable at speed and give the `ComicPostFX` Sobel pass strong, bright edges to ink.

### Approach

`CircuitBuilder._ribbon(cursor, width, length, mat)` already builds a ribbon mesh for the track surface using two triangle strips. Add a paired helper `_edge_ribbons(cursor, width, length)` that extrudes two thin quads (one per edge) alongside the main ribbon using the emissive edge material.

Each edge quad:
- Width: `0.15` units (narrow strip at each edge)
- Positioned at `+width/2` and `-width/2` in the cursor's local X, offset outward by `0.05` so they sit on top of the surface edge without z-fighting
- Uses `_make_emissive(col_edge)` with `emission_energy_multiplier = edge_emission_energy`
- Same length/curve as the parent ribbon section

Call `_edge_ribbons()` immediately after every `_ribbon()` call in the section builders (`_straight`, `_turn`, `_loop`, `_wall_ride`, etc.). This means edge lines automatically appear on every section type, including loops and the full circuit.

### For BoxMesh sections

`CircuitBuilder._add_box()` builds flat box sections (straights and hump/ramp sections). Add thin `BoxMesh` edge strips along the left and right long edges of each box:
- Size: `(0.15, 0.08, length)` matching the section length
- Offset: `±(width/2 + 0.075)` in local X, `+height/2 + 0.04` in local Y (sits on top)
- Same emissive material

---

## Wall Visual Distinction

Walls and barriers should be visually distinct from the floor — players need to read them as "wall" not "floor extension". Two changes:

1. **Wall material colour:** use `col_wall` (slightly warm purple-grey) on side barriers and wall-ride sections, distinct from `col_floor` (cool grey). CircuitBuilder already passes separate materials to `_wall_ribbon()` — use the new `_mat_wall` there.

2. **Wall edge lines:** Apply the same emissive edge strip logic to the top edge of wall sections (the edge the player would run along). This signals "the rideable top" visually. Use `col_edge` at `emission_energy_multiplier = 1.2` (slightly dimmer than floor edges, so floor navigation takes priority).

---

## Loop Visual Treatment

The `_real_loop` sections in `CircuitBuilder` use a vertical circle ribbon. The emissive edge lines on a loop produce a full glowing circle which is a strong visual landmark. No special treatment needed — `_edge_ribbons()` handles it automatically. Verify that the edge lines are visible from the entry approach (should be glowing rings visible through the loop opening before entry).

---

## Recovery Floor

The recovery floor (the large flat platform below the course) should be the darkest material (`col_barrier`) with no emissive edge lines. It is a safety net, not a track section — visually it should recede.

---

## File Structure

No new files. Changes are in:

```
flowstate/
└── scripts/
    └── tests/
        ├── CircuitBuilder.gd       # @export colours, _edge_ribbons(), dark material defaults
        └── PlaygroundBuilder.gd    # @export colours, _mat_emissive() factory, dark material defaults
```

Scene changes: `WorldEnvironment` properties in `Track_Circuit.tscn` and `Test_Playground.tscn`.

---

## Constants Reference (all `@export` on the builder scripts)

### CircuitBuilder.gd
| Param | Default | Meaning |
|---|---|---|
| `col_deck` | `Color(0.10, 0.10, 0.18)` | Track surface colour |
| `col_accent` | `Color(0.10, 0.13, 0.22)` | Arc / sweeping-turn surface |
| `col_ramp` | `Color(0.15, 0.12, 0.10)` | Ramp / hump surface |
| `col_pad` | `Color(0.09, 0.16, 0.16)` | Landing pad (slight teal) |
| `col_wall` | `Color(0.14, 0.09, 0.17)` | Wall / barrier surface |
| `col_loop` | `Color(0.16, 0.10, 0.21)` | Loop surface |
| `col_recovery` | `Color(0.05, 0.05, 0.09)` | Recovery floor (darkest) |
| `col_edge` / `col_arrow` | `Color(0.0, 1.0, 0.8)` | Emissive cyan (FLOOR edges / chevrons) |
| `col_wall_edge` | `Color(1.0, 0.18, 0.47)` | Emissive **magenta** wall-top accent — reads distinct from cyan floor (04 "wall colour vs floor colour") |
| `edge_emission_energy` / `wall_edge_emission_energy` | `2.0` / `1.6` | Floor-edge / wall-top glow intensity |
| `arrow_emission_energy` | `1.4` | Chevron glow intensity |
| `edge_width` / `edge_margin` / `edge_lift` | `0.4` / `0.35` / `0.06` | Edge strip width, inset from lane edge, lift above deck |

> **Render note:** edge strips are single-sided ribbons, so `_make_emissive()` sets `CULL_DISABLED` — without it the strips backface-cull and show nothing from above (the original "no racing lines" bug). Floor edges = cyan, wall tops = magenta, so the two never read as the same line.

### PlaygroundBuilder.gd
| Param | Default | Meaning |
|---|---|---|
| `col_floor` | `Color(0.08, 0.09, 0.14)` | Infinite floor |
| `col_ramp` / `col_kicker` | `Color(0.15, 0.12, 0.10)` / `Color(0.16, 0.13, 0.09)` | Ramp / quarter-pipe |
| `col_wall` / `col_loop` / `col_pillar` | dark cool / purple / magenta-dark | Walls / half-loop / pillars |
| `col_edge` | `Color(0.0, 1.0, 0.8)` | Emissive cyan accents |
| `edge_emission_energy` / `edge_width` / `edge_lift` | `2.0` / `0.4` / `0.06` | Accent glow / strip width / lift |

### Environment (both scenes, in the `.tscn`)
| Property | Value |
|---|---|
| `background_mode` | `1` (BG_COLOR) |
| `background_color` | `Color(0.05, 0.05, 0.08)` |
| `ambient_light_source` / `_color` / `_energy` | `2` (COLOR) / `Color(0.04,0.04,0.08)` / `0.3` |
| DirectionalLight `light_color` / `light_energy` | `Color(0.8,0.85,1)` / `0.6` |

---

## Acceptance Criteria

| Criteria | How to Test |
|---|---|
| World is near-black | Open Track_Circuit — background is dark, no default sky visible |
| Track surface is dark grey | Floor reads as dark, distinct from the black background |
| Walls read distinct from floor | Wall sections are slightly different colour than floor sections |
| Emissive edge lines present | Every track section (straights, turns, loops, wall sections) has glowing cyan edges |
| Loop rings visible pre-entry | Approaching a loop, two glowing circles are visible ahead |
| Recovery floor recedes | The safety floor is darker than the track with no edge lines |
| No ComicPostFX needed | The visual baseline looks correct with `ComicPostFX.enabled = false` |
| No physics regressions | All existing probes pass unchanged — track geometry is identical, only materials changed |

---

## Status
**Implemented (2026-06-24).** Dark flat-colour environment + dim cool light in `Track_Circuit.tscn` and `Test_Playground.tscn`; dark palette + emissive cyan edge lines in `CircuitBuilder.gd` (straights, ramps, arcs, loop rings, wall-corridor / wall-jump decks) and emissive landmark accents in `PlaygroundBuilder.gd` (half-loop edges, ramp lips, wall tops, pillar caps). Edge meshes are visual-only (no collision) so the car is untouched.

**Dev-test round 1 fixes (2026-06-24):**
1. *"No racing lines"* — `_make_emissive()` wasn't double-sided, so the single-sided floor strips backface-culled to nothing from above. Fixed with `CULL_DISABLED`.
2. *"Walls hard to make out / accent too red / missing on some walls"* — `col_wall` saturated/brightened to read distinct from the deck; the magenta wall-top accent retuned to a truer magenta (`Color(0.9,0.05,0.78)`, high blue so it doesn't clip red); and all wall types now route through a single `_add_wall()` (box + top strip) so straights, ramps, ride-walls, corridor/gap walls, and the plaza wall are all accented consistently (arcs use `_wall_top_strip`). Directional light nudged 0.6 → 0.85.
3. *"Loops scrape / kill momentum"* (pre-existing loop geometry, surfaced during this test) — `_real_loop` now uses an **asymmetric cut**: front keeps `loop_front_cut` (2.2, jump-in entry) but the descending **back** is cut at `loop_back_cut` (4.5) so its low slabs no longer hang over the approach lane at car-roof height. Verified by the new `_LoopClearanceProbe` (approach speed held at 34 = no scrape; still inverts; rides to 25.2 of 26).

Verified headless (Godot 4.6.3): `_CircuitSmokeProbe`, `_PlaygroundReplayProbe`, `_LoopEntryProbe`, and the new `_LoopClearanceProbe` all PASS, with **identical car travel + min-y to baseline** → no physics regression. Changes are isolated to the builder/scene files + the new probe; the pre-existing observational probes (`_SpeedCapProbe` etc.) don't reference them and are unaffected.

Depends on: none. Blocks: `016_VFX_Pass.md` (ComicPostFX Sobel pass needs bright emissive edges to ink; posterize/halftone need the dark base to read). Visual confirmation (the actual look) is a dev eyeball pass — headless can't render.
