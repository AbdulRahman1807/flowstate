# Design Pillars
## FLOWSTATE

These five pillars are decision filters. When a design decision, feature proposal, or implementation choice is unclear, run it against every pillar. If it violates one, reconsider. If it violates two or more, cut it.

---

## Pillar 1 — Momentum Is Everything

Speed is the most valuable resource in FLOWSTATE. The entire game is built around the cycle of gaining it, protecting it, and expressing it.

**What this means in practice:**
- Every mechanic must support momentum preservation or reward momentum expression
- Controls must never introduce unnecessary friction or lag
- Physics must never randomly steal speed from the player
- UI and effects must communicate speed clearly at all times

**Test question:** *Does this mechanic help players gain or preserve momentum, or does it slow them down for a non-skill reason?*

---

## Pillar 2 — Style Matters

The coolest run is not always the fastest run. Players who take harder routes, chain more transitions, and execute with flair should be rewarded even if they don't post the best time.

**What this means in practice:**
- Scoring rewards style alongside time
- The Flow multiplier amplifies impressive sequences
- The camera and VFX should amplify style passively — the game should make players look better than they are
- Near-misses should be acknowledged and rewarded

**Test question:** *Does this system make impressive moments feel more rewarding, or does it flatten all outcomes?*

---

## Pillar 3 — Easy To Learn, Hard To Master

The controls are simple. The depth comes entirely from execution. A new player can get through the track. An expert player can turn the same track into a work of art.

**What this means in practice:**
- The control scheme must fit on one screen
- No hidden mechanics — everything the player needs to know is visible and predictable
- The skill ceiling comes from execution precision, not system complexity
- Tutorials and tooltips are not MVP concerns — the game teaches through feel

**Test question:** *Is this complexity coming from execution depth, or from system complexity? If the latter, simplify the system.*

---

## Pillar 4 — Make Players Look Cool

FLOWSTATE should naturally generate moments worth sharing. The game's camera, effects, and scoring systems should conspire to make every good run look cinematic.

**What this means in practice:**
- Dynamic camera responds to speed and transitions to frame the action well
- VFX scale with speed and skill (trails, particles, distortion)
- Replays automatically identify the best moments
- The visual language is loud and expressive — not subtle

**Test question:** *Would this moment look good in a clip? If not, why not — and can we fix that with camera or effects work?*

---

## Pillar 5 — Failure Costs Momentum, Not Progress

Mistakes are part of the learning process. FLOWSTATE punishes imprecision with score impact and momentum loss, not with time penalties, checkpoints, or run resets. Players should be able to recover from a mistake and still finish with a decent run.

**What this means in practice:**
- No health system
- No run-ending failure states (except falling entirely off the track, which respawns at last checkpoint)
- Crashes reduce Flow multiplier and bleed speed, but do not kill the run
- The restart option is always available but never forced

**Test question:** *Does this failure outcome make the player want to try again immediately, or does it make them put the controller down?*

---

## Applying the Pillars

Use this matrix during design reviews. A proposal should ideally support multiple pillars. A proposal that conflicts with any pillar needs strong justification.

| Proposal | P1 Momentum | P2 Style | P3 Learnable | P4 Look Cool | P5 Forgiving |
|----------|-------------|----------|--------------|--------------|--------------|
| Boost mechanic | ✅ Adds speed | ✅ Timing is stylish | ✅ Simple input | ✅ VFX potential | ✅ Optional use |
| Vehicle health system | ❌ Run-ending | — | ❌ Adds complexity | ❌ Breaks flow | ❌ Punishing |
| Speed gates | ⚠️ Can punish | ❌ Forces route | ❌ Hidden failure | ❌ Interrupts | ❌ Punishing |

Vehicle health and speed gates both fail the pillar test. They're cut.
