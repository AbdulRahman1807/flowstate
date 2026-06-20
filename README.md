# FLOWSTATE

> A third-person momentum racing game about maintaining flow through gravity-defying environments.

---

## Current Status

**Stage:** Pre-Prototype
**Priority:** Movement system validation
**Engine:** (TBD — Unity or Godot 4 recommended)
**Platform:** MacBook Air M2 / Desktop target

The project lives or dies on how movement *feels*. Nothing else matters until that question is answered.

---

## Core Fantasy

> "I just pulled off something that looked impossible."

---

## Documentation Index

| File | Purpose |
|------|---------|
| `01_PRD.md` | Product Requirements — what we're building and why |
| `02_GDD.md` | Game Design Document — mechanics and systems |
| `03_Design_Pillars.md` | The five pillars every decision gets measured against |
| `04_Art_Direction.md` | Visual identity, style, and atmosphere |
| `05_Technical_Requirements.md` | Engine, platform, and performance constraints |
| `06_Architecture.md` | Code structure and system organization |
| `07_Roadmap.md` | Milestones and sequencing |

## Task Index

| Task | Description |
|------|-------------|
| `001_Movement_Prototype.md` | Core steering, acceleration, brake, reverse, jump, boost |
| `Tasks/002_Dynamic_Camera.md` | Speed-responsive camera with surface transition support |
| `Tasks/003_Gravity_System.md` | Surface attachment and gravity direction changes |
| `Tasks/004_Wall_Riding.md` | Wall entry, traversal, and exit |

---

## MVP Scope

One vehicle. One track. These systems, nothing more:

- Steering + Acceleration + Brake + Reverse
- Jump
- Boost
- Wall Riding
- Gravity / Surface Transitions
- Basic Flow Multiplier
- Basic Score Tracking
- Dynamic Camera
- Early Stylized VFX

**Everything else is explicitly out of scope until movement is proven fun.**

---

## Development Principles

- Validate before building
- Modular and replaceable over clever and coupled
- Fast iteration over clean architecture
- If it doesn't serve movement quality, cut it
