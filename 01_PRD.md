# Product Requirements Document
## FLOWSTATE — Pre-Prototype Stage

---

## Problem Statement

Momentum-based movement games have an incredibly high skill ceiling and produce some of gaming's most satisfying moments, but nearly all of them are either first-person shooters (CS:GO surf/bhop), traditional racing games with rigid physics, or unreachable AAA productions. FLOWSTATE fills the gap: a third-person vehicle game where movement *is* the game, and the vehicle behaves more like a parkour character than a car.

---

## Product Vision

A game where players feel physically capable of the impossible. Where a run produces moments they didn't think they could pull off. Where a replay makes them say "I cannot believe I actually did that."

---

## Target Audience

**Primary:** Players who love mastery-driven movement games. Fans of Trackmania, CS surf maps, Rocket League freestyle, and GTA stunt content.

**Secondary:** Speedrunners, time-attack players, and clip culture participants who value style over progression.

**Not targeted:** Players who want vehicle RPG progression, story, or realistic simulation.

---

## MVP Requirements

### Must Have (Prototype Stage)

| Requirement | Rationale |
|-------------|-----------|
| Ground movement feels responsive and predictable | Core feel. Nothing else matters if this fails. |
| Jumping preserves and can increase momentum | Required for skill expression |
| Wall riding with correct physics | Core differentiator |
| Ceiling traversal | Core differentiator |
| Surface-to-surface gravity transitions | Core differentiator |
| Boost mechanic | Momentum acceleration layer |
| Dynamic FOV and camera tilt | Speed must *feel* fast |
| Flow multiplier (basic) | Reward loop foundation |
| Score feedback | Player needs feedback to iterate |
| One functional test track | Movement needs a context to be tested in |

### Must Not Have (Prototype Stage)

- Vehicle stats, upgrades, or unlocks
- Multiple vehicles
- Multiplayer of any kind
- Account system or cloud services
- Track editor
- Procedural generation
- Story or campaign
- Audio (nice to have, not required for movement validation)
- Polished UI

---

## Success Metrics (Prototype)

The prototype succeeds when all of the following are true:

1. A player restarts the same track repeatedly because movement feels satisfying — not out of obligation.
2. A player completes a run and wants to immediately improve it.
3. A replay moment makes the player think "I cannot believe I landed that."
4. Wall-to-ceiling transitions feel fluid, not janky.
5. The vehicle *never* feels like it's fighting the player.

These are qualitative, not quantitative. One tester achieving all five is sufficient to proceed to Alpha.

---

## Non-Goals (Explicitly Deferred)

These are acknowledged future directions that must not influence prototype architecture:

- Global leaderboards
- Real-time multiplayer
- Replay sharing infrastructure
- Community-created tracks
- Mobile platform support
- Cosmetic systems

---

## Constraints

| Constraint | Impact |
|------------|--------|
| Solo developer | Architecture must be simple enough for one person to hold in their head |
| MacBook Air M2, 8GB RAM | Lightweight engine build, no heavy physics middleware |
| AI-assisted development | Code must be modular and clearly commented for agent handoff |
| Pre-prototype stage | No persistent data, no external services, no backend |
