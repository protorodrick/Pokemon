# Particle Orb — Roblox port of the three.js scene

A port of `original/index.html` (the interactive particle system with a central RGB orb and ring) to Roblox.

## Run it (one click)
1. Download [`build/ParticleOrb.rbxlx`](build/ParticleOrb.rbxlx) and double-click it. Roblox Studio opens.
2. Press **Play** (F5).

Or paste all of [`build/ParticleOrb_Installer.luau`](build/ParticleOrb_Installer.luau) into Studio's **View → Command Bar**, press Enter, then press Play.

## Controls
| Action | Key | Touch |
| --- | --- | --- |
| Fly on/off | F | Fly button |
| Rise / sink while flying | Space or E / Ctrl or Q | ▲ / ▼ buttons |
| Original camera (fixed view from z = 300, FOV 75) | V | Original View button |

## How it maps to the original
| three.js | Roblox |
| --- | --- |
| `SphereGeometry(30, 32, 32)` + `wireframe: true` | Same vertex and index layout, rebuilt in `Geometry.luau` and drawn as a `WireframeHandleAdornment` |
| `TorusGeometry(45, 1.5, 16, 100)` wireframe | Same, in the XY plane |
| 1000 `Points`, `size: 2`, random in a 500³ cube | 1000 small Neon parts, moved every frame with `BulkMoveTo` |
| `particleSystem.rotation.y = t * 0.05` | Same formula |
| Orb `rotation.x/y += 0.01`, ring `+= 0.005 / 0.01` per frame | Same rates, scaled by frame time so they match 60 fps on any device |
| `setHSL(t * 0.1 % 1, 1, 0.5)` | `Color3.fromHSV(t * 0.1 % 1, 1, 1)`, which is the same colour |
| Per-particle colour `(x/500 + 0.5 + sin(t + i*0.1)*0.5) % 1` | Same formula. JavaScript's `%` is matched with `math.fmod`, and negative values are clamped to 0 like WebGL does |
| `camera.position.z = 300`, FOV 75 | Players spawn on a glass platform at that spot. **V** switches to that exact fixed camera |
| `THREE.Clock`, `Math.random()` | Shared server clock and seeded random, so every player sees the same scene at the same moment |

Differences you can't avoid in Roblox:
- The background is Roblox's darkest night sky rather than pure black.
- Particles are small cubes rather than flat squares that always face the camera.
- If `WireframeHandleAdornment` isn't available, the wireframes are drawn with lower-detail neon lines instead.
