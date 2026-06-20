# 005 — Continuous Surface Following

**Status:** Phase 1 IMPLEMENTED & probe-verified (2026-06-19) · Phase 2 experimental (deferred, opt-in, not started)
**Depends on:** 003 (Gravity System), 004 (Wall Riding)
**Supersedes:** the floor/ceiling dead-band auto-detection in 003
**History:** v1 of this doc (full centrifugal sim) was rejected in design review — see §9. This is the revised two-phase design.

---

## 1. Problem (recap)

GravitySystem classifies the surface under the car as floor (`normal·UP > 0.55`) or ceiling (`< -0.55`) and discards the band between → any surface past ~57° tilt ejects the car (`force_airborne`). Loops, smooth wall→ceiling, steep banks, corkscrews are undrivable. Detach from non-floor surfaces is a flat speed cutoff that feels like artificial sticking.

## 2. Why two phases

The design review (§9) found that the "make it fully physical" approach (curvature-based centrifugal + tangent gravity + convex launch) is fragile (curvature from raycasts), fights the momentum pillar (tangent gravity bleeds speed), risks being too-sim for an arcade game, and bloats the most-iterated scripts. But the **goal** — drivable loops/ceilings with a speed-gated, non-arbitrary feel — is sound.

So:

- **Phase 1 (this milestone):** the simplest *robust* implementation that fixes dead-band, makes loops/ceilings drivable, resolves wall-riding ownership, and kills sticky jumps. No curvature math, no tangent gravity. Momentum-preserving (loops keep your speed). Legible.
- **Phase 2 (later, opt-in):** an experimental centrifugal-adhesion branch (radius-dependent detach, optional tangent gravity, convex launch) that plugs into Phase 1 through explicit seams (§7) behind a single flag — **without rewriting Phase 1.**

---

## 3. Design principles (from the review)

1. **Use the real contact, not a self-referential ray.** Detection reads `move_and_slide` contact normals (the surface the body is actually touching), with a down-ray only as a fallback. (Review: HIGH — `-basis.y` depends on the orientation it controls.)
2. **Detach must be legible.** A player must understand "I was going too slow." Phase 1 uses a speed threshold that scales with how inverted the surface is — readable and tunable. (Review: HIGH — invisible `v²κ` thresholds fail the "blame attribution" feel gate.)
3. **Clean ownership.** Continuous-follow owns the surface *under* the car; button wall-riding owns surfaces *beside* the car. The boundary is defined by geometry, not luck. (Review: HIGH — auto-riding curved wall bases undermines 004's intentional-only pillar.)
4. **Surfaces are sticky on purpose, never by accident.** An attach cooldown guarantees jumps/launches are never eaten by re-attach. (Review: HIGH — sticky jumps.)
5. **Don't touch the tuned ground game.** Flat-floor driving, jumps, and landings behave exactly as today. Phase 1 only changes what happens on *tilted* surfaces.
6. **Phase 2 is additive.** Everything Phase 2 needs is reachable through the seams in §7; turning the flag off restores Phase 1 exactly.

---

## 4. Phase 1 — specification

### 4.1 Detection (surface under the car)

Each frame, after `move_and_slide()`, find the surface the body is resting on:

1. Iterate `get_slide_collision_count()` and pick the contact whose normal is "most aligned with the car's up" (`normal·basis.y` largest) — that's the surface beneath the car (works at any orientation; on a loop side it's the wall, on a ceiling it's overhead).
2. **Fallback:** if there were no slide collisions this frame (e.g., snapped/hovering), cast a short ray along `-basis.y` (`ray_length`) and use its normal.
3. If neither finds a surface → no surface this frame.

`move_and_slide` already runs in VehiclePhysics; GravitySystem reads the resolved contacts via the vehicle. (Ordering note in §4.7.)

### 4.2 Attach (from AIRBORNE)

Attach only when **all** hold:
- A surface was found (4.1), and
- its normal is **floor-like or ceiling-like enough to *initiate*** on: `abs(normal·UP) >= attach_init_dot` (default 0.5). This is the **ownership rule** — you cannot auto-attach onto a near-vertical surface from the air; standalone vertical walls are button-only. And
- the **attach cooldown** (4.5) is not active.

On attach: commit the normal (debounced as today), set state label (4.4).

### 4.3 Sustain & detach (while attached, non-wall)

While GROUNDED/INVERTED, each frame:
- **Follow the contact normal continuously at ANY tilt** — provided it rotates *gradually*: only accept the new normal if `angle(new, current) <= max_follow_rotation_deg` per frame (default 20°). A loop rotates the normal ~1–2°/frame; a sharp floor→wall corner flips ~90° in a frame. So smooth curves (loops, fillets) are followed; **sharp walls are rejected** (you ran into a wall — continuous-follow does not grab it; button wall-riding or a stop handles it). This is the rest of the ownership rule and also rejects the lip-jitter the review flagged.
- **Detach (→ AIRBORNE) if any:**
  - the surface is lost (no contact / ray miss), or
  - the normal would jump more than `max_follow_rotation_deg` (sharp edge/wall), or
  - **speed `< required_hold_speed(normal)`** — the legible detach criterion (4.6), or
  - speed `< detach_speed_threshold` (absolute floor, existing).

### 4.4 States

| State | Reached by | Notes |
|-------|-----------|-------|
| GROUNDED | continuous-follow, `normal·UP >= -0.55` | flat floor, banks, **vertical loop sides** |
| INVERTED | continuous-follow, `normal·UP < -0.55` | loop tops, curved ceilings |
| WALL_LEFT / WALL_RIGHT | **button only** (`request_wall_attach`) | unchanged from 004 |
| AIRBORNE | no surface, detach, cooldown active | world gravity |

`_is_grounded = state != AIRBORNE` (unchanged), so driving/steering works on every attached surface.

### 4.5 Attach cooldown (kills sticky jumps)

A timer `_attach_cooldown` (default `0.18 s`). It is set whenever the car *leaves* a surface on purpose or by force:
- on jump (`VehiclePhysics` step 7),
- on wall-jump / wall detach (`WallRiding.try_wall_detach`),
- on any `force_airborne()`.

While `_attach_cooldown > 0`, continuous-follow will **not attach** (4.2). This guarantees a jump/launch clears the surface before re-attachment is possible — protects normal jumps, gap-jumps, and the directional wall-jump (004). Cooldown ticks down each frame.

### 4.6 The detach criterion — tilt-scaled hold-speed (Phase 1)

```
tilt = clamp((1.0 - normal·UP) * 0.5, 0.0, 1.0)   # floor 0 · vertical 0.5 · ceiling 1
required_hold_speed = max_hold_speed * hold_curve(tilt)
```

- `max_hold_speed` (default ~14): the speed needed to hold a full ceiling/loop-top.
- `hold_curve`: an exported `Curve` (fallback linear). Lets us make low tilts free and only demand speed as you go inverted.
- Floor (`tilt 0`) → `required = 0` → any speed, identical to today.
- Vertical (`tilt 0.5`) → ~half — you can ride a vertical loop side moderately.
- Inverted (`tilt 1`) → full — you need real speed to hold the top.

**Consequences (intended):** enter a loop fast enough and your (momentum-preserved) speed clears the rising threshold all the way around → you complete it and exit with ~entry speed. Too slow → you peel off where the rising threshold crosses your speed (partway up). Faster = makes loops; slower = falls off. Legible, and **momentum-preserving** (no tangent-gravity speed bleed) — which the pillars prize. Radius-independence is the known simplification (one global `max_hold_speed`); Phase 2 adds true radius dependence.

**This function is the primary Phase 2 seam** (§7).

### 4.7 Frame ordering & gravity

- Detection reads `move_and_slide` contacts, so the attach/detach evaluation must run **after** `move_and_slide` (end of `apply_intent`), updating state for next frame. `get_gravity_vector()` / state remain valid reads through the frame.
- Gravity stays as today: into-surface (`-normal * g`) when attached (H4-clean, no tangent), world-down when airborne. **Phase 1 does not add tangent gravity.**
- Wall states (WALL_LEFT/RIGHT) keep their existing sustain path (`_wall_still_present`) untouched; continuous-follow logic runs only for GROUNDED/INVERTED/AIRBORNE.

### 4.8 Exports (Phase 1)

```gdscript
# GravitySystem
@export var attach_init_dot: float = 0.5          # min |normal·UP| to AUTO-attach from air (ownership)
@export var max_follow_rotation_deg: float = 20.0 # max normal rotation/frame to keep following (curve vs corner)
@export var max_hold_speed: float = 14.0          # speed to hold a full ceiling/loop-top
@export var hold_speed_curve: Curve               # tilt(0..1) -> 0..1 multiplier (fallback: linear)
@export var attach_cooldown_time: float = 0.18    # no auto-attach for this long after leaving a surface
# Reused: ray_length (fallback ray), detach_speed_threshold (absolute floor), airborne_gravity
```

### 4.9 Phase 1 edge cases

- **Smooth convex crests don't launch** (the car hugs them; only *edges* launch via contact-loss). Acceptable for Phase 1 — the prototype track uses edge kickers. Smooth-crest launch is a Phase 2 concern (convex criterion). Documented, not a regression (today's behavior is the same).
- **Flat ceilings:** with one global `max_hold_speed`, a flat ceiling *is* technically holdable in Phase 1 if you exceed `max_hold_speed` (no curvature gate). This is fine/forgiving for Phase 1 (and lets designers do authored flat-ceiling runs); Phase 2's centrifugal model would make flat ceilings physically unholdable. Call this out so the difference is intentional, not a surprise.
- **Sharp corner into a wall:** rejected by `max_follow_rotation_deg` → car does not auto-ride; it collides/stops or the player button-rides. Correct ownership.

### 4.10 Phase 1 test plan

- `_LoopProbe.gd` (new): vertical loop ribbon; fast entry → full traversal, exit ≈ entry speed; slow entry → detach partway up. Assert state sequence GROUNDED→INVERTED→GROUNDED for the fast case.
- `_WallStickProbe` / `_WallClimbProbe` / `_WallJumpDirProbe` — must be unchanged (wall riding intact).
- New `_JumpStickProbe` (or extend climb probe): jump straight up off a floor → must reach airborne and not be re-grabbed within the cooldown.
- Headless parse + scene load clean.

---

## 5. Phase 2 — experimental centrifugal adhesion (deferred)

Enabled by a single flag; **off by default**; adds behavior only.

```gdscript
@export var use_centrifugal_adhesion: bool = false
```

What it adds, all behind the flag:

1. **Radius-dependent detach.** Replace `required_hold_speed(normal)` (the §7 seam) with the centrifugal test: stay while `a_c >= off_pull` (concave) where `a_c = v²·κ`, `off_pull = -g·(normal·UP)`, `κ` from curvature estimation. Gives "tighter loops need more speed."
2. **Convex launch.** Add the missing half: on convex surfaces detach (launch) when `a_c > g_into_surface` — real air off smooth crests.
3. **Curvature estimation.** Compute `κ` from the **rotation of the contact normal over distance actually travelled** (EMA-smoothed) — motion-history based, mesh-independent — *not* geometric raycast probes (the review's top rewrite risk). Lives entirely in the Phase 2 branch.
4. **Tangent gravity (optional sub-flag).** Compose tangent gravity into `get_gravity_vector()` (§7 seam #2) for energy-conservation feel. Gated separately (`use_tangent_gravity`) because of its momentum-pillar tension; validate in playtest before defaulting on.
5. **Detach feedback hook.** Emit an "about-to-lose-grip" signal so loss is fair/legible.

Phase 2 risks (carried from review): curvature reliability on tight/3D curves, tangent gravity vs momentum pillar, knife-edge near threshold, tuning-knob count, sim-vs-arcade fit. These are why it's opt-in and playtest-gated.

---

## 6. What is explicitly NOT changing

- Button wall-riding (004) — detection, attach, directional jump, sustain: untouched.
- Flat-floor driving, jump, landing — identical.
- VehicleController, WallSensor, FlowSystem, DynamicCamera — no changes (camera already follows `get_gravity_vector()`).

---

## 7. The seams (how Phase 2 plugs in without rewriting Phase 1)

Phase 1 must be built with exactly these two extension points so Phase 2 is purely additive:

**Seam 1 — the detach predicate.** One function owns the "should I still be attached?" decision:

```gdscript
# Phase 1 body: tilt-scaled hold-speed (4.6)
# Phase 2 body (when use_centrifugal_adhesion): centrifugal a_c vs off_pull (+ convex launch)
func _surface_holds(normal: Vector3, tangential_speed: float, delta: float) -> bool
```

All detach logic calls this; swapping its body (guarded by the flag) is the only change to the detach path. Phase 1 ignores `delta`; Phase 2 uses it for curvature/EMA.

**Seam 2 — gravity composition.** GravitySystem owns the full applied gravity vector; VehiclePhysics applies whatever `get_gravity_vector()` returns when attached (no per-axis logic in VehiclePhysics beyond "apply it"):

```gdscript
# Phase 1: returns into-surface gravity only (-normal * g), H4-clean
# Phase 2: returns into-surface + tangent (when use_tangent_gravity)
func get_gravity_vector() -> Vector3
```

This means Phase 2's tangent gravity needs **zero** VehiclePhysics changes. (Phase 1 includes the small VehiclePhysics step-12 change to "apply the provided attached-gravity vector" instead of recomputing `-surf_n*|g|` inline — designed once, stable across phases.)

Curvature state, the convex branch, the tangent sub-flag, and the feedback signal all live inside these two functions / behind `use_centrifugal_adhesion`. Nothing in detection, ownership, cooldown, or states changes between phases.

---

## 8. Doc updates when Phase 1 lands

- `003_Gravity_System.md`: replace the floor/ceiling dead-band description with continuous-follow; add the Phase-1 exports; note INVERTED is now reached via continuous-follow, not the old gated path.
- `CLAUDE.md`: add 005 to the doc table; note continuous-follow owns under-car surfaces, button wall-riding owns beside-car surfaces.
- `004_Wall_Riding.md`: one line clarifying the ownership boundary (sharp walls = button; smooth curves = auto-follow).
- `08_Movement_Feel_Targets.md`: add a loop feel target (entry speed to complete a radius-R loop; exit ≈ entry under Phase 1).

---

## 9. Review resolutions (traceability)

| Review finding (sev) | Resolution in this design |
|---|---|
| Self-referential `-basis.y` detection (HIGH) | Phase 1 reads `move_and_slide` contact normals; ray is fallback (§4.1) |
| Sticky jumps / re-attach eats launches (HIGH) | Attach cooldown (§4.5) |
| Convex launch missing (HIGH) | Phase 1 = edge-launch only (documented §4.9); convex launch is Phase 2 (§5.2) |
| Curvature from raycasts fragile (HIGH) | Phase 1 has no curvature; Phase 2 uses motion-history EMA, not geometric probes (§5.3) |
| Detach legibility / fairness (HIGH) | Phase 1 tilt-scaled speed is readable; Phase 2 adds feedback hook (§5.5) |
| Wall-riding ownership conflict (HIGH) | `attach_init_dot` + `max_follow_rotation_deg`: sharp walls = button, smooth curves = auto (§4.2, §4.3) |
| Tangent gravity vs momentum pillar (MED-HIGH) | Cut from Phase 1; Phase 2 sub-flag, playtest-gated (§5.4) |
| Complexity in VehiclePhysics (MED-HIGH) | Gravity composition centralized in GravitySystem (Seam 2); VehiclePhysics stays thin |
| Determinism/replay (MED) | All new state is sim-side and reset on respawn/airborne; Phase 1 adds no float-history (cooldown is a simple timer) |

## 10. Open decisions

1. `max_hold_speed` default (14?) and the `hold_speed_curve` shape (how free are vertical sides vs ceilings?).
2. `attach_init_dot` = 0.5 (≈60° from vertical) the right ownership cutoff between "auto" and "button" surfaces?
3. Phase 1 flat-ceiling forgiveness (§4.9) — keep it (designer-friendly) or tighten later in Phase 2?
