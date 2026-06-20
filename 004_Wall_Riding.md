# 004 — Wall Riding

**Version:** 2.0 — Button-Initiated Attachment  
**Status:** Active  
**Replaces:** Auto-Detection Architecture (v1.0)

---

## Design Philosophy

Wall riding in FLOWSTATE is an **intentional act**, not a physics outcome.

v1.0 treated wall contact as a passive trigger — the engine detected surface normals and auto-attached when angle and speed conditions were met. This required a two-gate filtering architecture (GravitySystem + WallRiding) and complex angle-of-approach constraints to prevent accidental attachments. Despite this, false positives were still possible at geometry edges and corners.

v2.0 removes auto-detection for walls entirely. The player presses a dedicated button to attach. If the button is pressed, it was intentional. This has three consequences:

- **False positives are impossible.** Clipping a wall at a bad angle is no longer a physics hazard.
- **Flow rewards become meaningful.** Every attachment is a deliberate decision — the flow system can reward that without needing to infer intent from physics data.
- **The detection architecture simplifies significantly.** The two-gate system, debounce frames, and approach angle filtering are replaced by a single scan-and-commit pass on button press.

Floor (GROUNDED) and ceiling (INVERTED) detection remain automatic. Ceilings are a natural consequence of wall riding — transitioning wall → ceiling is a skill chain, not a separate input decision. Walls are the only surface type that requires explicit player intent.

---

## Input

| Action Name | Default Binding | Type |
|---|---|---|
| `wall_attach` | Left Bumper / `Q` | Toggle (press-once) |

The action is a **toggle**:
- **First press (not on wall):** Scan for a candidate wall and attach if found.
- **Second press (while wall riding):** Detach. If speed and angle permit, execute a wall jump. Otherwise, execute a clean release.

Hold is not required. The player commits to the wall on first press and rides until they press again, lose speed, or exit the wall's surface.

---

## Wall Detection — WallSensor

Wall detection is handled by a dedicated `WallSensor` node. It runs **only when the player presses `wall_attach`**, not every frame.

### Algorithm

On button press, WallSensor casts a **horizontal fan of raycasts** around the vehicle's direction of travel:

1. Compute `vel_dir = velocity.normalized()`, projected onto the horizontal plane (`flat`)
2. Build a fan of `scan_ray_count` (= 9) rays sweeping `±scan_cone_angle` (= ±90°) around `flat`, rotated about world up. This covers walls directly to the left and right — the common case when riding *alongside* a wall — not just walls ahead.
3. For each ray hit, evaluate:
   - **Surface type gate:** `absf(hit_normal.dot(Vector3.UP)) <= 0.55` — discard floors and ceilings
   - **Approach gate:** `toward_wall = -vel_dir.dot(hit_normal)` must be in `[min_approach_dot, max_approach_dot]` (= **-0.25–0.99**). Allows driving parallel to a wall (`toward_wall ≈ 0`); rejects only walls being driven *away* from and near-perfect head-on slams.
   - **Range gate:** `hit_distance <= max_wall_range` (= **3.0 units**). Must be `<=` GravitySystem's `wall_stick_range` (= 3.5), or an attached wall is immediately out of sustain range and `force_airborne()` fires one frame after attach.
4. Score each passing candidate: `score = max(approach_dot, 0) * 0.4 + (1.0 - distance_norm) * 0.6`
5. Select the **highest-scoring candidate** and return its normal

Scoring favours the **closest** wall (60% weight) over approach directness (40%). When riding alongside a wall, `toward_wall ≈ 0` for every candidate, so proximity is what correctly picks the wall you are next to.

> **Design note (v2.1):** The original v2.0 spec used a narrow velocity-aligned cone (±45°) with an approach gate that required moving *into* the wall (`min_approach_dot = 0.05`). Playtesting showed this fails the primary use case — driving parallel to a wall and pressing the attach button — because the wall sits ~90° to the side, outside the cone, and a parallel approach scores `toward_wall ≈ 0` and is rejected by the gate. The horizontal fan + relaxed gate fixes this while keeping attachment skill-gated (must be near a wall, at speed, and press the button).

### Why Velocity Direction, Not Camera Direction

The cone is centred on velocity, not the camera look direction. At racing speeds the two are nearly identical in practice, but velocity-aligned scanning is more correct: it reflects where the vehicle is actually going, not where the player is looking. It also prevents scanning behind the vehicle when the camera leads a turn.

### What WallSensor Does Not Do

- It does not run every frame.
- It does not maintain state between presses.
- It does not interact with `move_and_slide()` collision results.
- It is not responsible for keeping the player on the wall — that is GravitySystem's job once attached.

---

## Attachment Sequence

On `wall_attach` button press, when not currently wall riding:

```
1. Speed gate         — current_speed >= wall_attach_min_speed (5.0). Reject silently if not.
2. State gate         — GravitySystem state must be AIRBORNE or GROUNDED. Reject if already INVERTED.
3. WallSensor scan    — find_best_wall(velocity, space_state). Reject if no candidate found.
4. Commit             — gravity_system.request_wall_attach(best_normal)
5. Velocity redirect  — redirect velocity **up-and-along** the wall, preserving speed magnitude. Blend the along-wall travel direction with the up-the-wall direction: `climb_dir = (along_dir + wall_up).normalized()`, then `velocity = climb_dir * speed`. This lifts the car onto the wall surface (a ground-level alongside approach has no upward component, so pure projection would wedge it at the wall base) while entry direction still shapes the climb angle
6. Signal             — emit on_wall_attach(wall_normal)
7. State              — _is_wall_riding = true
```

Step 5 (velocity redirect) previously happened reactively in `VehiclePhysics._on_state_changed`. It now happens proactively in `WallRiding._try_attach_to_wall()` at the moment of commitment, using the same `climb_dir` logic.

`gravity_system.request_wall_attach(normal)` is a new public method. It accepts a pre-validated wall normal (WallSensor has already confirmed it is a wall surface), classifies it as `WALL_LEFT` or `WALL_RIGHT` based on `normal.dot(global_transform.basis.x)`, and calls `_commit_surface_normal()` directly, bypassing all auto-detection logic.

---

## Sustained Wall Riding

Once attached, the wall riding physics are **identical to v1.0**. Nothing in GravitySystem's sustain logic changes:

**Gravity alignment** — `target_gravity = -current_surface_normal * airborne_gravity.length()` (magnitude always 18 m/s², direction into wall). Lerped at `gravity_transition_speed` (= 8.0) each frame for the **visual orientation**. The applied adhesion *force*, however, is always `-surface_normal * magnitude` (straight into the surface) while attached — it does not use the lerping vector. This decouples the smooth orientation lerp from the force, so the brief direction mismatch during lock-on never introduces a down-the-wall tangent component that would bleed momentum.

**Vehicle orientation** — `basis.y` rotated toward `gravity_up` each frame. Wall surface is treated as "floor" for `move_and_slide()` purposes.

**Velocity projection** — velocity perpendicular to wall surface is zeroed each frame to prevent clipping.

**Speed monitoring** — `eval_speed` (max over last 10 frames) is checked against `detach_speed_threshold` (= 4.0) each frame. If speed drops below this while in WALL or INVERTED state, `force_airborne()` is called. This is the only automatic detach trigger that remains.

**WallRiding update** — `apply_speed_decay(wall_speed_decay * delta)` (= 0.5 flat/s) is applied each frame while `_is_wall_riding` is true, in addition to GravitySystem's `wall_grip_decay` (= 0.15 multiplicative/s) and standard drag (= 0.08/s). Decay is applied to the forward axis only — lateral velocity (for wall steering) is preserved.

WallRiding's per-frame update runs via `update_wall(delta)`, called explicitly by `VehiclePhysics.apply_intent()` **after** the velocity rebuild — not from its own `_physics_process`. This guarantees the decay is not overwritten by the velocity rebuild and removes any dependency on scene-tree node order.

**Speed cap & boost lockout (jump-off consistency).** While in a WALL state, velocity is clamped to `wall_ride_speed_cap` (= 22, deliberately decoupled from ground `max_speed`) each frame, and boost is disabled (it only fires when GROUNDED or AIRBORNE). On a wall the vehicle's forward axis points up the surface, so boosting or carrying overspeed up a wall would fling the launch unpredictably high. Capping the ride speed and locking out boost keeps every wall jump-off bounded and repeatable.

---

## Detachment

Three detach paths exist:

### 1. Player Toggle (Second Button Press)

On `wall_attach` press while `_is_wall_riding` is true, `WallRiding.try_wall_detach()` is called:

- If `current_speed >= wall_jump_min_speed` (= 8.0): **wall jump** — a **directional** launch shaped by the inputs held at the moment of the jump (see "Directional Wall Jump" below). Call `gravity_system.force_airborne()`. `current_speed` for the threshold gate is `velocity.length()` (total), not forward-only.
- If speed below threshold: **clean release** — call `gravity_system.force_airborne()` only. Velocity preserved as-is.

The wall jump threshold distinguishes an intentional launch from a low-speed scrape-off. Players below threshold get a clean release without the perpendicular force, avoiding a jarring snap when speed has already bled out.

#### Directional Wall Jump (v2.1)

The held steer / accelerate / brake at the instant of the jump shape the launch — this is the primary skill-expression point of the detach. `try_wall_detach(steer, accelerate, brake)` receives these from `VehiclePhysics.apply_intent()`. The jump velocity is:

```
jump_vel = (perp + up + forward) * brake_scale
perp    = wall_normal   * wall_jump_force * perp_scale
up      = Vector3.UP    * wall_jump_up_force
forward = forward_axis  * (forward_speed * wall_jump_forward_preserve + wall_jump_forward_push * accelerate)
```

- **Steer** sets `perp_scale`. `side = -1` for `WALL_LEFT`, `+1` for `WALL_RIGHT`, so `steer_away = steer * side` is `+1` when steering **away** from the wall, `-1` when steering **into** it. `perp_scale = lerp(wall_jump_perp_min, wall_jump_perp_max, (steer_away + 1) / 2)`. Away → maximum push off the wall; into → minimal push (you barely peel off); neutral → mid.
- **Accelerate (W)** adds `wall_jump_forward_push` along the facing axis — hold for more forward travel off the wall.
- **Brake (S)** scales the whole launch by `lerp(1.0, wall_jump_brake_min, brake)` — hold to drop off slow.
- `forward` is isolated to the facing axis (`forward_axis = -basis.z`) so gravity-accumulated vertical velocity is **not** carried into the jump; only `wall_jump_up_force` sets baseline height.

Concrete example, **left wall** (D = away, A = into): **D** launches far off the wall; **A** barely peels you off; **W** carries you forward along it; **S** drops you off slowed. Neutral gives a moderate default pop-off.

### 2. Speed Loss (Automatic)

GravitySystem's `eval_speed < detach_speed_threshold` (= 4.0) triggers `force_airborne()`. This is the natural end of a wall ride that wasn't intentionally exited. WallRiding observes the state change, emits `on_wall_detach` with reason `"speed_loss"`, and resets `_is_wall_riding`.

### 3. Surface Loss (Automatic)

While in WALL state, GravitySystem casts a ray toward the committed surface normal (`-_current_surface_normal`) over `wall_stick_range` (= 3.5) every frame. If it no longer hits a wall-ish surface (vehicle reached the edge or end of the wall segment), `force_airborne()` is called. WallRiding observes and emits `on_wall_detach` with reason `"edge_exit"`.

**Critical range invariant:** this sustain ray casts toward the *known* wall normal, independent of vehicle orientation — unlike the floor/ceiling auto-detect rays which fire along the vehicle's basis axes at `ray_length` (= 1.5). The earlier implementation reused those short axis rays to confirm walls, so any wall attached beyond ~1.7 units was force-detached the frame after attach (the wall state lasted one frame; gravity never flipped). `wall_stick_range` must be `>=` `WallSensor.max_wall_range`.

### Ceiling Transition (Special Case)

If GravitySystem transitions from WALL to INVERTED (vehicle rode up and onto a ceiling), WallRiding emits `on_wall_detach` with reason `"ceiling_transition"` and awards `flow_on_clean_transition` (= 0.5) bonus. `_is_wall_riding` resets — the ceiling ride is managed by GravitySystem as INVERTED state, not by WallRiding. The player may re-initiate wall riding from the ceiling by pressing `wall_attach` again if a suitable wall is in range.

---

## Speed Bleed While Wall Riding

Three stacked decay sources, unchanged from v1.0:

| Source | Rate | Type | Location |
|---|---|---|---|
| Standard drag | 0.08 × speed / s | Multiplicative | `VehiclePhysics.gd` |
| `wall_grip_decay` | 0.15 × speed / s | Multiplicative | `VehiclePhysics.gd` |
| `wall_speed_decay` | 0.5 units / s | Subtractive (flat) | `WallRiding.gd` via `apply_speed_decay()` |

At entry speed 30 m/s, speed reaches `detach_speed_threshold` (= 4.0) in approximately **7–8 seconds** under default values. Wall riding is a skill tax, not a punishment — the decay is tuned to match prototype wall section lengths of 4–8 seconds.

---

## Corners and Wall Edges

**Wall-to-wall corners:** WallSensor is only invoked on button press, so rapid normal oscillation at corners is not a concern. If the player presses while in a corner, WallSensor scores both candidate normals and selects the one the player is most approaching. The result is deterministic from a single scan.

**Wall top edges (wall → open air):** Surface loss detach applies (see §Detachment path 3). The vehicle arcs off the edge with preserved velocity.

**Wall → ceiling transitions:** GravitySystem auto-detects the ceiling once the vehicle's raycasts reach the ceiling surface, transitions to INVERTED, and the ceiling-transition detach path fires in WallRiding. This chain (wall → ceiling) is the primary intended use of momentum carry-through and is rewarded with flow bonus.

**Wall → ground transitions:** GravitySystem auto-detects the floor and transitions to GROUNDED. WallRiding observes the non-wall state, emits `on_wall_detach` with reason `"edge_exit"`, and resets. The standard angle-based landing penalty applies (see `08_Movement_Feel_Targets.md` — penalty scales with approach angle on the surviving horizontal speed).

---

## Momentum Preservation on Exit

**Clean release / speed-loss detach:** Velocity is preserved verbatim. No exit penalty, no direction override. The vehicle carries whatever speed and direction it had at the moment of detach. Gravity lerps from wall-normal direction back to `airborne_gravity (0, -18, 0)` over ~0.3–0.5 seconds.

**Wall jump:** the launch is **directional** (see §"Directional Wall Jump"). Baseline values are a 10 m/s perpendicular outward impulse (`wall_jump_force`, scaled 0.3×–1.8× by steer), a 4 m/s world-up impulse (`wall_jump_up_force`), and 60% of the along-facing forward speed (`wall_jump_forward_preserve`, isolated to `-basis.z` so gravity-accumulated vertical is excluded). Holding accelerate adds forward; holding brake scales the whole launch down. (Tuned down from 24/14/0.8 → 14/8/0.8 → 10/4/0.6 for a controlled pop-off, then made directional for skill expression.) The result is a steerable outward-and-upward arc with meaningful speed retention and enough airtime for wall-to-wall transitions.

**Ceiling transition:** No speed penalty. Velocity direction is not modified by GravitySystem during state transition — `move_and_slide()` carries the velocity through the surface change.

---

## Flow Integration

Wall riding contributes to the flow system at three points:

| Event | Flow Delta | Condition |
|---|---|---|
| Per-second riding | `flow_per_second` | While `_is_wall_riding` is true |
| Wall jump | `flow_on_wall_jump` | `try_wall_detach()` executes jump path |
| Ceiling transition | `+0.5` (fixed) | `on_wall_detach` reason = `"ceiling_transition"` |

Because every attachment is now button-initiated, **all flow rewards reflect deliberate decisions**. The per-second reward accumulates only while the player is actively committed to the wall. There is no flow reward for accidentally touching a wall surface, because accidental attachment is no longer possible.

Future: wall → ceiling → wall chain detection could award a compounding bonus at each transition link.

---

## Re-Entry and Cooldown

**No cooldown timer is implemented.** Because attachment is button-gated, the player physically controls re-entry rate. A player who repeatedly presses the button while no valid wall is in range simply gets silence from WallSensor — no state change occurs.

If a wall jump was just executed, the vehicle is moving away from the surface. WallSensor's `toward_wall` check (`-vel_dir.dot(normal) >= min_approach_dot`) will fail for that wall until the vehicle has arced and re-approached, which provides natural re-entry spacing without a timer.

---

## Removed from v1.0

The following are **no longer present in the codebase** following the v2.0 refactor:

- Slide collision auto-commit in `GravitySystem` (lines 100–112 in v1.0)
- Raycast-based WALL_LEFT / WALL_RIGHT classification in the auto-detect loop
- `NORMAL_CONFIRM_FRAMES` debounce for wall normals
- `min_attach_angle` gate in GravitySystem transition logic
- WallRiding observer pattern (polling `gravity_system.get_state()` every frame)
- `_rejection_cooldown` / `REJECTION_COOLDOWN_TIME` (were already removed in a prior cleanup)

GravitySystem's auto-detect loop now classifies GROUNDED and INVERTED only. WALL_LEFT and WALL_RIGHT are reachable exclusively via `request_wall_attach()`.

---

## Not Yet Implemented

- **Cooldown timer** — not needed; button gating provides natural spacing
- **Curved surface transitions / quarter-pipes** — GravitySystem's gravity lerp supports them in theory; no curved geometry in current test track
- **Wall bounce** — intentional off-wall redirect on button press at steep angle; noted as future consideration
- **Wall → ceiling → wall chain bonus** — FlowSystem hooks exist; reward logic not yet written
- **Visual feedback** — `WallVFX.gd` (placeholder, M3) consumes all four wall signals (`on_wall_attach` / `on_wall_jump` / `on_wall_detach` / `on_near_miss`) plus `VehiclePhysics.landed` / `jumped`, and throws additive soft-glow spark bursts in the `04_Art_Direction` comic/graffiti palette (wall surface-feedback language). Wall-jump is de-duped vs its detach. The full inky/halftone pass is M5.
- **Input buffer** — *implemented*: `VehicleController.wall_attach_buffer_time` (= 0.1s) buffers the press and retries the attach scan until a wall is in range or the window expires; `consume_wall_attach()` clears it on a successful attach/detach so a single press never double-toggles

---

## Constants Reference

| Constant | Value | Owner | Purpose |
|---|---|---|---|
| `wall_attach_min_speed` | 5.0 | WallRiding | Minimum speed to initiate attachment on button press |
| `wall_jump_min_speed` | 8.0 | WallRiding | Minimum speed for toggle-off to execute wall jump vs clean release |
| `wall_jump_force` | 10.0 | WallRiding | Base perpendicular outward impulse on wall jump (scaled by `perp_scale`) |
| `wall_jump_up_force` | 4.0 | WallRiding | World-up impulse on wall jump — baseline arc height |
| `wall_jump_forward_preserve` | 0.6 | WallRiding | Fraction of along-facing forward speed preserved on wall jump |
| `wall_jump_perp_min` | 0.3 | WallRiding | Perp scale when steering INTO the wall (barely off) |
| `wall_jump_perp_max` | 1.8 | WallRiding | Perp scale when steering AWAY from the wall (far off) |
| `wall_jump_forward_push` | 8.0 | WallRiding | Extra forward velocity when holding accelerate (W) at jump |
| `wall_jump_brake_min` | 0.4 | WallRiding | Launch velocity scale when fully braking (S) at jump |
| `wall_speed_decay` | 0.5 | WallRiding | Flat speed subtraction per second while riding |
| `wall_detach_speed` | 5.0 | WallRiding | Speed tag for detach reason classification |
| `wall_ride_speed_cap` | 22.0 | VehiclePhysics | Wall-ride velocity clamp — bounds the jump-off independent of ground `max_speed` |
| `wall_grip_decay` | 0.15 | GravitySystem | Multiplicative speed loss per second on any wall/ceiling state |
| `detach_speed_threshold` | 4.0 | GravitySystem | Absolute floor — `force_airborne()` if `eval_speed` drops below |
| `min_attach_speed` | 5.0 | GravitySystem | Speed check inside `request_wall_attach()` |
| `airborne_gravity` | (0, -18, 0) | GravitySystem | Base gravity magnitude (~1.8g, Earth-like); direction is rotated per surface |
| `gravity_transition_speed` | 8.0 | GravitySystem | Lerp rate for gravity direction changes |
| `scan_ray_count` | 9 | WallSensor | Number of rays in the detection fan |
| `scan_cone_angle` | 90° | WallSensor | Half-width of the horizontal fan around travel direction (±90° = full sideways coverage) |
| `max_wall_range` | 3.0 | WallSensor | Maximum raycast distance for wall candidates (must be <= `wall_stick_range`) |
| `wall_stick_range` | 3.5 | GravitySystem | Max distance to wall surface before a wall ride auto-detaches (sustain ray toward surface normal) |
| `min_approach_dot` | -0.25 | WallSensor | Minimum `toward_wall` value — allows parallel/alongside approaches, rejects walls being driven away from |
| `max_approach_dot` | 0.99 | WallSensor | Maximum `toward_wall` value — rejects near-perfect head-on slams |