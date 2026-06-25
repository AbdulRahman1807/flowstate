# Movement Feel Targets
## FLOWSTATE — Pre-Prototype Stage

This document defines what "good" feels like before a single line of physics code is written. It exists so that tuning sessions have a concrete target, not a vibe. Every parameter in VehiclePhysics.gd should be tuned against this document.

---

## How To Use This Document

During tuning, read the feel target first. Drive the current build. Ask: does it match? If not, identify which parameter is responsible and adjust in one direction. Re-test. Do not change multiple parameters simultaneously — you will lose the thread.

When a section passes, mark it. When all sections pass, movement is ready for wall riding.

---

## Ground Movement

### Acceleration

**Target feel:** The vehicle should feel like it *wants* to go fast. Acceleration should be eager — not a gradual build, but a committed surge. A new player should feel the speed arrive before they expect it.

**Reference:** Rocket League kickoff acceleration. The vehicle is already moving by the time your brain registers you pressed the button.

**Failure modes:**
- Too slow: feels sluggish, like you're fighting friction
- Too fast: feels out of control, no time to read the track
- Non-linear without intention: feels inconsistent

**Quantitative targets:**
- 0 to 60% top speed: under 1.5 seconds
- 60% to 100% top speed: 1.5–3 seconds (top end takes effort)
- Top speed should feel genuinely fast — not "fast for a prototype"

---

### Steering

**Target feel:** Steering should feel like a direct extension of the left stick. No perceptible delay between input and direction change. At low speed, the vehicle should be highly maneuverable. At high speed, it should feel planted — requiring commitment to turns, but never fighting the player.

**Reference:** Trackmania's steering — immediate, readable, never fighting you — but slightly more forgiving.

**Failure modes:**
- Input lag: any gap between stick and response breaks immersion completely
- Oversteer at speed: the vehicle snaps past the intended line
- Understeer at all speeds: the vehicle feels like it's on rails in the wrong way — numb, not planted
- Oscillation: the vehicle wobbles when trying to hold a straight line

**Quantitative targets:**
- Full steer input response: same physics frame, no exceptions
- High-speed turning radius: tight enough to navigate a 4-lane-width curve at 80% top speed without braking
- Steering dampen at top speed: approximately 40–50% of low-speed steering authority

---

### Braking

**Target feel:** Braking should feel like controlled deceleration, not an emergency stop. The player should use it sparingly — it costs momentum. It should never feel abrupt. Releasing brake should immediately restore acceleration authority.

**Failure modes:**
- Instant stop: kills momentum, feels mechanical
- Too weak: players can't navigate tight sections at all
- Brake causes spin: should never destabilize the vehicle unexpectedly

**Note:** Braking is not a primary mechanic. If players are braking frequently, the track or top speed is wrong — not the brake.

---

### Reverse

**Target feel:** Reverse should feel like a utility gear, not a gameplay focus. Hold brake from standstill (or after slowing below the engage threshold) and the vehicle backs up with less authority than forward drive. Steering while reversing uses the same immediate yaw-and-align model as forward.

**Reference:** GTA V brake-to-reverse — hold S to stop, keep holding to back up.

**Failure modes:**
- Reverse engages at high forward speed: dangerous, unintended
- Reverse faster than forward: undermines the speed fantasy
- Reverse steering slides sideways: same ice-cube failure as forward

**Quantitative targets:**
- Reverse top speed: 35–40% of forward `max_speed` (forward `max_speed` raised to **50**, from 22 — the 22 cap never actually held; tuning live). `max_reverse_speed` set to **18** (~36% of max) to match this band after the cap raise; the dead "reverse braking" branch was removed so reverse actually reaches it.
- Reverse engage threshold: vehicle nearly stopped (default 2 units/s)
- W cancels reverse cleanly without a gear-shift pause

---

### Top Speed Feel

**Target feel:** Top speed should feel *fast enough to be exciting but slow enough to be readable*. The player should be able to see what's coming and react. Speed lines and camera FOV should make it feel even faster than it is.

**Reference:** GTA V stunt races at full acceleration — genuinely fast, but legible.

**Failure mode:** If a player at top speed cannot react to a feature they see 3 seconds ahead, top speed is too high for the current camera and FOV setup. Fix with camera and FOV first, then revisit top speed.

---

## Jump

### Launch

**Target feel:** The jump should feel deliberate and powerful. It should reward timing — jumping at the lip of a ramp should extend the arc meaningfully versus jumping flat. The vehicle should feel like it's been launched, not popped.

**Reference:** CS:GO bhop — the jump is a tool, not an afterthought.

**Failure modes:**
- Floaty: too much hang time, vehicle drifts
- Too snappy: vehicle pops up and drops immediately, no arc
- Jump height independent of speed: kills jump-as-skill-tool entirely

**Quantitative targets:**
- Jump from flat at top speed: vehicle should clear a 3-unit-wide gap with room to spare
- Jump height from flat: approximately 2–3 vehicle lengths of vertical clearance
- Air time from flat ground: 0.8–1.4 seconds

---

### Air Control

**Target feel:** The vehicle should be steerable in the air, but not as much as on the ground. Air control exists so players can adjust for landing precision — not so players can fully reorient mid-air.

**Failure modes:**
- No air control: players cannot course-correct, landings feel random
- Full air control: kills the sense of commitment, trivializes routing

**Quantitative targets:**
- Air steering authority: approximately 55–65% of ground steering (revised from 30–40% — wall-to-wall transitions require meaningful mid-arc redirection, not just landing adjustment)
- Air steering should not affect forward speed

### Airborne Pitch (2026-06-25)

**Target feel:** A real car (and the AE86 in particular) noses up as it launches and noses down as it falls — it pivots to follow its trajectory rather than staying a perfectly level plank in the air. This is a *visual/orientation* behaviour; it must not bleed momentum.

**Implementation (`VehiclePhysics` step 2, exported):** while airborne with no trick in progress and past `air_pitch_min_airtime` (0.2 s, so brief surface bumps on banked spirals/loops are excluded and keep surface-following intact), the car's nose slerps (`air_pitch_rate` 6/s) toward the velocity direction — pitch from `atan2(velocity.y, horizontal)`, clamped to `air_pitch_max_deg` (55°) so a near-vertical launch doesn't point it straight up. Heading (yaw) and zero-roll are preserved; air steering still works on top. Orientation-only — step 3 reprojects velocity onto the new basis, so speed is untouched. Tricks (held E) bypass it entirely; below the airtime gate the car keeps the prior level-to-gravity-up behaviour.

**Failure modes:**
- Pitches on tiny surface bumps → jitter / breaks surface re-attach (fixed via the airtime gate)
- Pitch couples into velocity → momentum bleed (avoided: orientation-only)
- Over-pitch on near-vertical launches → car points straight up (clamped)

---

### Landing

**Target feel:** Landing should feel like a *decision completed*. A clean landing — flat, on the intended surface — should produce no speed penalty. A rough landing — steep angle, edge clip — should produce an audible (eventually) and visual response and a speed penalty proportional to how bad it was.

**Reference:** Trackmania's landing system — clean landings are completely smooth, bad landings are punishing but readable.

**Failure modes:**
- All landings feel the same: removes landing precision as a skill
- Clean landings still lose speed: punishes players who did nothing wrong
- Landing physics feel bouncy: kills momentum, looks wrong

**Quantitative targets:**
- Clean landing speed retention: 95–100% of approach speed
- 30° off-angle landing speed retention: 80–90%
- 60° off-angle landing speed retention: 50–70%
- Landing bounce: should not exist. Vehicle contacts surface and stays.

---

## Boost

### Activation

**Target feel:** Boost should feel like a significant event — not a subtle nudge. The player should feel the surge, see it, and briefly hear it (when audio exists). Boost is a reward for correct positioning and timing.

**Reference:** Rocket League boost — committed, powerful, clearly communicated.

**Failure modes:**
- Boost feels like "a bit more gas": not a distinct mechanic, just faster acceleration
- Boost is too strong: breaks track design, skips over crafted sections
- No feedback on boost activation: player doesn't know it fired

**Quantitative targets:**
- Boost speed delta: 20–30% top speed increase instantaneously, decaying over ~1.5 seconds
- Boost cooldown: 2–3 seconds (fast enough to use tactically, slow enough to be a decision)

### Boost Into a Surface Transition

**Target feel:** Using boost just before entering a wall or ceiling transition should feel spectacular. The speed increase should carry through the transition and feel like it paid off.

This is a design intention, not a tuning target yet. Note it here so the boost force vector is preserved through gravity transitions (Task 003) rather than being cancelled.

---

## Wall Riding

### Entry

**Target feel:** Entering a wall should feel like "locking on." There should be a perceptible moment where the vehicle commits to the wall surface. Too casual an entry — too slow, too parallel — should fail silently (no explosion, no penalty, just no attachment). A committed entry at speed should feel crisp.

**Failure modes:**
- Entry feels accidental: player doesn't know they're on the wall
- Entry too forgiving: any touch sticks, removes skill
- Entry too strict: players can't reliably attach even when trying correctly

**Quantitative targets:**
- Minimum attach speed: ~25% of top speed
- Valid entry angle: approximately 20°–70° from perpendicular to wall
- Attachment should be confirmed within 2 physics frames of valid contact

---

### During

**Target feel:** Riding a wall should feel precarious but controlled. The vehicle should feel like it is *working* to stay attached. Speed decay should be perceptible but not brutal — the player should feel it as a cost, not a death sentence.

**Failure modes:**
- Wall feels identical to ground: removes the wall's distinct identity
- Speed decay too fast: walls become unusable at any length
- Speed decay too slow: walls become free speed highways

**Quantitative targets:**
- Speed decay on wall: 3–6 units/second (tuned to track wall section length)
- Steering on wall: same authority as ground — walls are navigable

---

### Exit

**Target feel:** Exiting a wall — by jumping, by reaching an edge, or by losing speed — should feel like a resolution. A jump exit should feel like a launch. An edge exit should feel like the wall *released* the vehicle, not dropped it.

**Failure modes:**
- Jump off wall feels weak: missed skill reward
- Edge exit causes jitter or bounce: breaks flow
- Speed loss on edge exit: punishes correct traversal

---

## Gravity Transitions

### Floor → Wall

**Target feel:** The transition should feel like the world rotated around the player, not like the player was repositioned. The instant before and after the transition, the camera and vehicle orientation should be consistent enough that the player never loses their sense of direction.

**Reference:** Tachyon Flow's surface transitions — seamless, world-bending, surprising in the best way the first time.

**Failure modes:**
- Snap: gravity changes instantly. Never acceptable.
- Camera loses up: player becomes disoriented. Transition must be readable.
- Speed cancelled: the entire point of the transition is to carry momentum through it.

**Quantitative targets:**
- Gravity rotation time: 6–10 physics frames to full alignment
- Speed retention through transition: 90–100% of approach speed
- Camera orientation lag behind gravity: 1–3 frames (follows gravity, not instant)

---

### Wall → Ceiling

**Target feel:** This is the signature moment of FLOWSTATE. Floor → wall → ceiling is the "impossible thing" from the core fantasy. It should feel earned and extraordinary. The vehicle going inverted should not feel like a physics accident — it should feel like a deliberate act of mastery.

**Failure modes:**
- Transition feels identical to floor → wall: undercuts the spectacle
- Ceiling adhesion feels weak or uncertain: player doesn't trust it
- Camera goes wrong: the one case where a camera issue actually breaks the game

**Qualitative gate:** A developer who has driven the prototype 50 times should still feel something when they hit a clean floor → wall → ceiling chain. If it feels routine, the transitions need more weight.

---

## Overall Feel Gates

These are go/no-go checks before exiting Milestone 1. A tester who has never played the prototype runs these checks cold:

| Check | Pass Condition |
|-------|---------------|
| Pick up and play | Tester is moving at speed within 15 seconds without instruction |
| Speed legibility | Tester correctly estimates "I'm going fast" vs "I'm going slow" without a speedometer |
| Jump intuition | Tester uses jump to cross a gap correctly on the second or third attempt |
| Restart impulse | After one full run, tester restarts voluntarily |
| Blame attribution | When tester loses speed, they attribute it to their own mistake, not the game |

The last one is the most important. If a player loses momentum and blames the physics, the physics are wrong.


Speed Visualization

The player should feel acceleration visually.

Methods:

- Speed streaks
- Motion accents
- Dynamic FOV
- Velocity trails
- Impact bursts
- Environmental distortion

Visual feedback should scale with momentum.