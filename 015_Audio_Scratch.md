# Task 015 — Scratch Audio
## FLOWSTATE

---

## Goal

Make the game not silent. A tester playing a completely silent game is being asked to imagine 50% of the feel — that directly hurts the M5 exit condition ("I cannot believe I did that" is much harder to feel without sound).

This is a **scratch pass** — not final audio. The goal is functional, clearly distinct sounds for every meaningful event, implemented with zero external audio asset files using Godot's `AudioStreamGenerator`. Real sounds drop in later by swapping the stream source; the architecture and signal wiring is identical.

The wall save, boost, drift, trick land, and wall jump need to feel like *events* — distinct sounds that signal "something cool happened." The engine hum needs to communicate speed state continuously.

`04_Art_Direction` deferred audio as not required for movement validation. Movement is now validated — that rationale is expired.

---

## Architecture

New `VehicleAudio.gd` — `Node` child of `Vehicle`. Same passive observer pattern as `WallVFX.gd`: connects to signals in `_ready()`, reads getters each frame for continuous streams. **No writes to gameplay state.**

### Node structure (built procedurally in `_ready()`)

```
VehicleAudio (Node)
├── EngineStream   (AudioStreamPlayer3D)   # continuous engine hum
├── DriftStream    (AudioStreamPlayer3D)   # continuous tire squeal (on/off)
└── EventBus       (AudioStreamPlayer3D)   # one-shot events (polyphonic via separate players)
    ├── JumpPlayer       (AudioStreamPlayer3D)
    ├── LandPlayer       (AudioStreamPlayer3D)
    ├── WallPlayer       (AudioStreamPlayer3D)
    ├── BoostPlayer      (AudioStreamPlayer3D)
    ├── SavePlayer       (AudioStreamPlayer3D)
    └── TrickPlayer      (AudioStreamPlayer3D)
```

All nodes built in code — no `.tscn` authoring required.

---

## Continuous Streams

### Engine Hum

Driven from `_physics_process(delta)` using `get_speed()`.

```gdscript
var speed_ratio := _vehicle.get_speed() / _vehicle.max_speed   # 0..1
EngineStream.pitch_scale = lerp(engine_pitch_idle, engine_pitch_max, speed_ratio)
EngineStream.volume_db = lerp(engine_vol_idle_db, engine_vol_max_db, speed_ratio)
```

**Scratch sound:** `AudioStreamGenerator` producing a continuous sawtooth/square tone at ~80 Hz, low-pass filtered, with harmonics. Pitch sweep covers roughly a 2.5-octave range from idle to top speed. The pitch should be the primary speed feedback signal.

**Boost modifier:** When `is_boost_active()`, add +0.25 to `pitch_scale` over 0.1s, return to speed-mapped pitch when boost ends.

### Drift Squeal

Activated by `drift_started` / `drift_ended` signals. On `drift_started`, fade in `DriftStream` over `drift_fade_in` (0.08s). On `drift_ended`, fade out over `drift_fade_out` (0.15s).

**Scratch sound:** `AudioStreamGenerator` producing a mid-frequency (600–1200 Hz) sawtooth with slight flutter. Pitch scales gently with `get_speed()` — a fast drift squeals higher than a slow one.

```gdscript
DriftStream.pitch_scale = lerp(0.8, 1.3, speed_ratio)
```

---

## One-Shot Events

Each event uses a dedicated `AudioStreamPlayer3D` so they don't interrupt each other. The engine/drift streams are never interrupted by events.

| Event | Signal | Player | Character | Volume Scaling |
|---|---|---|---|---|
| Jump | `VehiclePhysics.jumped` | `JumpPlayer` | Short upward whoosh (100–400 Hz sweep up, 0.12s) | Fixed |
| Land | `VehiclePhysics.landed(impact)` | `LandPlayer` | Low thud + brief sub rumble | `impact_velocity / 15.0` clamped 0.3–1.5 |
| Clean landing | `VehiclePhysics.clean_landing` | `LandPlayer` (layered) | High bright chime on top of thud (reward feel) | Fixed |
| Boost activate | `is_boost_active()` rising edge | `BoostPlayer` | Punchy forward surge — sharp attack, quick decay (0.3s), high-energy | Fixed |
| Wall attach | `WallRiding.on_wall_attach(speed, normal)` | `WallPlayer` | Short spark impact (white noise burst, 0.1s) | `entry_speed / 20.0` clamped 0.5–1.5 |
| Wall jump | `WallRiding.on_wall_jump(speed)` | `WallPlayer` | Big elastic launch pop — low thud + high streak | `speed / 20.0` |
| Wall save | `WallRiding.on_wall_save(speed, normal)` | `SavePlayer` | **Largest sound event** — hard impact + metallic ricochet streak + tail whoosh. Must be clearly distinguishable from wall attach. | `speed / 20.0` |
| Wall detach (passive) | `WallRiding.on_wall_detach` (reason ≠ "player_toggle") | `WallPlayer` | Soft release click | Fixed, quiet |
| Trick land (clean) | `VehiclePhysics.trick_landed(deg, true)` | `TrickPlayer` | Satisfying reward hit — mid-frequency impact + brief ascending tone. Scale pitch with `degrees/360` — a full 720° sounds bigger than 180°. | `deg / 360.0` clamped 0.7–1.8 |
| Trick land (botched) | `VehiclePhysics.trick_landed(deg, false)` | `TrickPlayer` | Dull thud only — no reward tone | Fixed, quiet |
| Gravity invert (loop entry) | `GravitySystem.on_state_changed` → INVERTED | `WallPlayer` | Brief low "whomp" — signals the world flipping | Fixed |

---

## Scratch Sound Generation

All sounds are generated via `AudioStreamGenerator` at runtime — no `.wav`, `.ogg`, or `.mp3` files required for the scratch pass.

### Generator approach

Each `AudioStreamPlayer3D` is assigned a generator that fills its buffer in `_process()` with synthesised waveforms:

```gdscript
func _fill_buffer(player: AudioStreamPlayer3D, duration: float, wave_fn: Callable) -> void:
    var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
    var frames := int(duration * AudioServer.get_mix_rate())
    for i in range(frames):
        var t := float(i) / AudioServer.get_mix_rate()
        playback.push_frame(Vector2(wave_fn.call(t), wave_fn.call(t)))
```

**Primitive waveforms used:**
- `sine(freq, t)` — `sin(TAU * freq * t)`
- `sawtooth(freq, t)` — `fmod(freq * t, 1.0) * 2.0 - 1.0`
- `noise_burst(t, decay)` — `randf_range(-1, 1) * exp(-decay * t)`
- `sweep(f0, f1, duration, t)` — sine at frequency `lerp(f0, f1, t/duration)`

Complex events (wall save, boost) combine two or three of these with different envelopes.

### Replacement path

To replace a scratch sound with a real audio file: assign an `AudioStreamOggVorbis` or `AudioStreamWAV` to the player instead of the generator. The signal wiring and volume/pitch logic is unchanged.

---

## `VehicleAudio.gd` Interface

```gdscript
class_name VehicleAudio
extends Node

@export var vehicle_path: NodePath
@export var wall_riding_path: NodePath

# Engine
@export var engine_pitch_idle: float = 0.6
@export var engine_pitch_max: float = 1.8
@export var engine_vol_idle_db: float = -12.0
@export var engine_vol_max_db: float = -4.0
@export var boost_pitch_add: float = 0.25

# Drift
@export var drift_fade_in: float = 0.08
@export var drift_fade_out: float = 0.15

# Master
@export var master_volume_db: float = 0.0
@export var enabled: bool = true
```

---

## Constants Reference

| Param | Default | Meaning |
|---|---|---|
| `engine_pitch_idle` | 0.6 | Engine pitch at 0 speed |
| `engine_pitch_max` | 1.8 | Engine pitch at max speed |
| `engine_vol_idle_db` | -12.0 | Engine volume at rest (dB) |
| `engine_vol_max_db` | -4.0 | Engine volume at top speed (dB) |
| `boost_pitch_add` | 0.25 | Pitch delta added while boost active |
| `drift_fade_in` | 0.08 | Seconds for drift squeal to reach full volume |
| `drift_fade_out` | 0.15 | Seconds for drift squeal to fade out |

---

## File Structure

```
flowstate/
└── scripts/
    └── vehicle/
        └── VehicleAudio.gd     # NEW passive observer
```

`VehicleAudio` added as child of Vehicle node in `Track_Circuit.tscn` and `Test_Playground.tscn`. Optionally add to test scenes for feel validation.

---

## Acceptance Criteria

| Criteria | How to Test |
|---|---|
| Engine pitch responds to speed | Accelerate from 0 to max — pitch rises continuously |
| Drift squeal appears on drift | Brake+steer at speed — squeal fades in; release — fades out |
| Boost has a distinct sound | Activate boost — clearly different from engine, punchy |
| Wall save is the loudest event | Hit a wall with Q at speed — unmistakably the biggest sound in the game |
| Wall jump sounds like a launch | Jump off wall — elastic pop distinctly different from ground jump |
| Trick land (clean) has a reward tone | Land a clean 360 — satisfying chime layered on top of the impact |
| Trick land (botched) is quiet | Land a botched trick — dull thud only, no reward |
| No gameplay regressions | All probes pass unchanged — `VehicleAudio` writes nothing to physics |
| Sounds don't overlap destructively | Multiple simultaneous events (land + wall attach) don't cancel each other |

---

## Status
Not started. Depends on: none.
Blocks: M5 human tester exit condition — a silent game significantly reduces the chance of a genuine "I cannot believe I did that" emotional response.

## Future Considerations
*Not in this task.*
- Replace `AudioStreamGenerator` scratch sounds with real audio files (engine recording, tire squeal, impact SFX) — drop-in swap, no architecture changes
- Music/soundtrack (post-validation, `07_Roadmap` Post-Validation list)
- Spatial audio tuning (reverb based on surface type — wall vs open air)
- Flow-reactive audio mix (music intensity tracks Flow multiplier)
