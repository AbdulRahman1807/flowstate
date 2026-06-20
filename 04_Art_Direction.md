# Art Direction
## FLOWSTATE — Pre-Prototype Stage

---

## Visual Identity Statement

FLOWSTATE looks like a moving graffiti mural — loud, saturated, expressive, and kinetic. It draws from street art, motion graphics, and comic book aesthetics. It does not reference military, dark realism, or traditional motorsport. Every frame should feel like it was made by someone who cares deeply about style.

---

## Inspirations

| Source | What We Take From It |
|--------|---------------------|
| Street art / graffiti | Color language, expressive linework, energy |
| Motion graphics | Dynamic type, trail effects, kinetic composition |
| Comic books | Strong contrast, speed lines, impact framing |
| Trackmania | Track geometry language, speed readability |
| Tachyon Flow | Abstract environments, neon-on-dark palettes |

---

## Color Direction

The palette is saturated and high-contrast. Backgrounds are dark to let the vehicle and effects read clearly at speed.

**Prototype Target Palette:**

| Role | Description | Example Hex |
|------|-------------|-------------|
| Background / track base | Deep dark — almost black, with a tint | `#0D0D14` |
| Primary accent | Electric cyan or acid yellow — vehicle and key UI | `#00FFCC` or `#E8FF00` |
| Secondary accent | Hot magenta or orange — flow effects, boost | `#FF2D78` |
| Track surface | Dark concrete-grey with emissive edge lines | `#1A1A2E` |
| Speed effects | White core, colored bloom | `#FFFFFF` → accent fade |

The final palette is not locked at prototype stage. What is locked: **high saturation, dark background, strong contrast, and no muddy mid-tones.**

---

## Vehicle Design Direction

The vehicle is abstract. It reads clearly as a vehicle from a distance at speed. It is not a licensed car, a Formula 1 car, or a truck. It should feel like it belongs in this world.

**Key characteristics:**
- Silhouette is instantly readable
- Emissive elements (headlights, underbody, engine glow) respond to speed state
- No realistic materials — stylized, flat-shaded or toon-shaded preferred
- Boost effect: visible directional trail or flame
- At high Flow: subtle color shift or particle aura

---

## Speed Representation

Speed must be felt, not just seen on a speedometer.

### Methods (in priority order for prototype):

**1. Motion Blur / Speed Lines**
Radial blur from the center of screen outward. The faster the vehicle, the more aggressive the blur. Street art-style speed lines over the blur.

**2. Dynamic FOV**
FOV expands as speed increases. Subtle at low speed, significant at top speed. Snaps back quickly on deceleration. Range: approximately 75° idle → 100° max speed.

**3. Camera Lag**
Camera follows with a slight speed-dependent lag that creates a sensation of being pulled forward.

**4. Particle Trails**
Emissive particle trail from the vehicle. Scale with speed. Persist briefly.

**5. Screen Distortion (Stretch)**
At boost or peak speed: brief chromatic aberration or lens distortion on the edges. Use sparingly — 2–3 seconds maximum.

---

## Surface Feedback

Each surface type should have distinct visual language:

| Surface | Visual Cue |
|---------|-----------|
| Ground | Dust/spark particles on high-speed turns |
| Wall | Emissive edge sparks on contact and while riding |
| Ceiling | Inverted light bloom on vehicle underside |
| Transition | Brief flash / streak on gravity change |

---

## Flow State Visuals

As the Flow multiplier increases, the world should feel more intense:

- **Flow 1–2:** Normal
- **Flow 3:** Vehicle trail becomes more prominent
- **Flow 4:** Subtle edge glow on the vehicle, slight vignette intensification
- **Flow 5 (Max):** Screen edge glow, particle density increase, FOV slightly wider

This is a *gradual escalation*, not a binary mode switch.

---

## Track Visual Language

Tracks are movement sculptures. Visual design should support navigation at high speed.

**Key rules:**
- Surface edges must be clearly readable — use emissive edge lines
- Upcoming hazards / transitions must be predictable from a distance
- Color can be used to signal surface type (wall color vs floor color)
- No clutter inside the track line — all decoration is peripheral

**Anti-goals:**
- No photo-realistic concrete textures
- No generic racing game aesthetics (no sponsor logos, no barriers)
- No fog that obscures upcoming track geometry

---

## UI / HUD Philosophy

HUD is minimal. The world communicates speed and flow more than the HUD does.

**Prototype HUD elements:**
- Flow multiplier (large, in-world-feeling, top center or screen edge)
- Current score (small, top corner)
- Timer (small, top corner)
- Speedometer (optional — may be unnecessary if speed feels perceptible)

**HUD style:**
- No traditional racing game chrome
- Flat, high-contrast, graffiti-inflected typography
- HUD elements should fade when not actively changing

---

## Prototype Scope for Art

At prototype stage, art quality is explicitly secondary to movement quality. The following is acceptable:

- Placeholder geometry tracks (grey-boxed with emissive edges)
- Simple vehicle mesh (even a capsule/box with an emissive trail)
- Basic particle effects only
- No audio required

What is **not** acceptable even at prototype:
- Visual feedback that makes movement harder to read
- A camera that obscures the action
- No speed feedback at all (even placeholder effects must exist)

Additional Visual References

Borderlands 3

Key influences:

- Stylized action lines
- Ink-like motion accents
- Impact bursts
- Velocity exaggeration
- Graphic-novel energy

Important:
Do not replicate Borderlands' exact cel-shaded look.
Instead borrow its visual language for communicating speed and impact.
