# Tidewild — an original creature-collecting MMO for Roblox

Tidewild is a multiplayer creature-collector RPG for Roblox. It has visible overworld spawns,
battles that happen right where you meet a creature, catching by sneaking up and throwing an Orb,
and a social plaza where you can greet, battle and trade with other players.

Every creature, move, type, name and model in this project is original.
**No assets, code or data from any Nintendo / Game Freak / The Pokémon Company game are included,
and none should be added.** Ripped models or game files would get the experience taken down on
Roblox (DMCA) and put your account at risk. To make it look better, add your own or properly
licensed models (see *Custom models* below).

## Features

| System | What it does |
| --- | --- |
| **Visible spawns** (`SpawnService`) | Creatures spawn in biome zones (Meadow, Beach, Forest, Highland) near players and wander, chase, flee or watch you depending on their temperament. Shiny odds are 1/512. |
| **Overworld battles** (`BattleService`, `BattleEngine`) | Press **E** near a creature, or let an aggressive one run into you. Your lead creature hops out beside you and the turn-based battle plays out in the world, with no screen transition. Includes type matchups, STAB, crits, stat stages, XP, move learning and evolution. |
| **Sneak catching** | Press **Q** to throw an Orb at the targeted creature. Throwing from behind, while it hasn't noticed you, gives a ×1.75 catch bonus. A failed throw either starts a battle or makes it run away. |
| **Followers** | Every player's lead creature follows them around. Each client draws these itself from player attributes, so the server does no work for them. |
| **Plaza** (`PlazaService`, `PlazaUI`) | Preset greetings (**G**) show as chat bubbles and earn Plaza Coins for meeting new people. Click or tap another player to invite them to a **battle** (levels evened out to 50, nobody's party gets hurt) or a **trade** (both players confirm, and the server checks and saves it immediately). Plaza rank, a top-socialite announcement, benches, a heal fountain and supply stands. |
| **Chat** | Roblox's built-in TextChatService, which Roblox filters. |
| **Saving** (`DataService`) | Party, box, items, money, Plaza Coins and dex, saved to a DataStore with autosave and a save when the server shuts down. |
| **Movement** | Hold **Shift** to sprint at 32 speed with a wider field of view. Sprinting scares skittish creatures. Mobile and gamepad buttons are included. |
| **Starter world** (`WorldBuilder`) | Builds an island with terrain, a plaza hub, a forest and snowy highlands on first run, so the game is playable straight away. |

### Performance design
* Wild creatures exist **only as data on the server**, updated 5 times a second. Each client gets a
  small snapshot of only the creatures within 220 studs, then builds, smooths and animates the
  models itself. The server never sends moving parts over the network.
* Clients skip animating models that are far from the camera.
* Workspace `StreamingEnabled` is on, and Lighting uses `Future`.

## Getting it into Roblox Studio

### Option A — Rojo (recommended)
1. Install [Rojo](https://rojo.space) (CLI and the Studio plugin).
2. In this folder run `rojo serve`, open a new Baseplate in Studio, and click **Connect** in the Rojo plugin.
   Or build a place file: `rojo build -o Tidewild.rbxlx`, then open it in Studio.
3. Delete the default `Baseplate` part. The island is generated when the game runs.
4. Turn on **Game Settings → Security → Enable Studio Access to API Services** so saves work while testing.
5. Press **Play**. To test trading and PvP, use **Test → Clients and Servers** with 2 players.

### Option B — manual copy
Create the same layout by hand:
* `ReplicatedStorage/Shared` (Folder) ← every file in `src/shared` as a **ModuleScript**
* `ServerScriptService/Server` (**Script**, contents of `src/server/init.server.luau`), with a child
  Folder `Services` containing `src/server/Services/*` as ModuleScripts
* `StarterPlayer/StarterPlayerScripts/Client` (**LocalScript**, contents of `src/client/init.client.luau`),
  with children `WorldRenderer` and `Controls` (ModuleScripts) and a Folder `UI` holding `src/client/UI/*`

## Project layout
```
src/
  shared/      Config, Types, Moves, Creatures, CreatureFactory, BattleEngine, CreatureModel, Net
  server/      init.server.luau + Services/{WorldBuilder, DataService, SpawnService, BattleService, PlazaService}
  client/      init.client.luau, WorldRenderer, Controls, UI/{Theme, HUD, BattleUI, PlazaUI}
```

## Extending
* **New creature:** add an entry to `src/shared/Creatures.luau` and put it in a biome spawn table.
* **New move:** add it to `src/shared/Moves.luau`. Effects: `stat`, `heal`, `drain`, `recoil`, `priority`.
* **Custom models:** make a `Model` named after the species id (e.g. `Cindervix`) inside a
  `ReplicatedStorage/CreatureModels` folder. `CreatureModel.build` uses it in place of the
  generated placeholder. Put the pivot at the model's feet, facing −Z.
* **Your own map:** build a `Workspace/World` folder in Studio. Give it a `Plaza` folder containing a
  `PlazaSpawn` SpawnLocation and ProximityPrompts named `HealPrompt`, `OrbPrompt` and `PotionPrompt`, and a
  `SpawnZones` folder of invisible Parts with the attributes `Biome`, `MinLevel`, `MaxLevel` and `MaxSpawns`.
  The world generator is skipped when this folder exists.
* **Tuning:** everything is in `src/shared/Config.luau`.

## Controls
| Action | Keyboard | Gamepad | Touch |
| --- | --- | --- | --- |
| Sprint | Shift | L3 | Run button |
| Battle target | E | X | Battle button |
| Throw Orb | Q | R2 | Orb button |
| Greetings | G | — | Greet button |
| Player menu | Click a player | — | Tap a player |
