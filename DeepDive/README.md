# Deep Dive (Roblox), Version 1

A submarine game. You build and upgrade a sub at your dock, dive into a dark
ocean, salvage treasure, fight sea monsters, and surface to cash in your haul.
If your sub sinks first, you lose the haul.

All the code is here. **The map, the subs, the monsters and every menu are
built by the scripts**, so you don't need to make any models by hand.

---

## Option A: open the ready-made place (easiest)

1. Download `DeepDive.rbxlx` from this folder.
2. In Roblox Studio: **File > Open from File** and pick `DeepDive.rbxlx`.
3. Do the **"Turn on saving"** step below, then press **Play**.

## Option B: paste the scripts yourself

1. In Roblox Studio, create a new place from the **Baseplate** template. The
   script removes the baseplate automatically.
2. In the **Explorer**, create these 7 scripts **with exactly these names**.
   For each one: right-click the parent, choose **Insert Object**, pick the
   type, rename it, then paste in the file's whole contents.

| # | Parent in Explorer                           | Type         | Name             | Paste this file                                |
|---|----------------------------------------------|--------------|------------------|------------------------------------------------|
| 1 | ReplicatedStorage                            | ModuleScript | `DeepDiveConfig` | `src/ReplicatedStorage/DeepDiveConfig.lua`     |
| 2 | ServerScriptService                          | ModuleScript | `WorldBuilder`   | `src/ServerScriptService/WorldBuilder.lua`     |
| 3 | ServerScriptService                          | ModuleScript | `SubBuilder`     | `src/ServerScriptService/SubBuilder.lua`       |
| 4 | ServerScriptService                          | ModuleScript | `PlayerData`     | `src/ServerScriptService/PlayerData.lua`       |
| 5 | ServerScriptService                          | ModuleScript | `Monsters`       | `src/ServerScriptService/Monsters.lua`         |
| 6 | ServerScriptService                          | **Script**   | `GameServer`     | `src/ServerScriptService/GameServer.lua`       |
| 7 | StarterPlayer > StarterPlayerScripts         | **LocalScript** | `GameClient`  | `src/StarterPlayerScripts/GameClient.lua`      |

ModuleScripts start with `return {}` already in them. Delete that first, then
paste.

## Turn on saving (both options)

1. Publish the place once: **File > Publish to Roblox**.
2. Open **Home > Game Settings > Security** and turn on **Enable Studio Access to
   API Services**.

Without this the game still runs, but progress won't save. The top-left panel
shows "Saving is OFF" when saving isn't working.

Recommended settings:
* **Game Settings > Places > Max Players: 8**. There are 8 berths, one per player.
* **Lighting > Technology: Future**. Headlights and glowing loot look much
  better with it. This setting can't be changed by a script.

---

## How to play

| Action                 | PC                     | Phone                  | Gamepad    |
|------------------------|------------------------|------------------------|------------|
| Board your sub         | walk up to it, press **E** | tap **Board Sub**  | X          |
| Forward / back / turn  | **W S A D**            | joystick               | left stick |
| Dive / rise            | **Q** / **E** (or Space) | **DOWN** / **UP**    | LB / RB    |
| Fire harpoon           | **left-click** (aim with the mouse) | **FIRE** (auto-aims) | RT |
| Sonar ping             | **F**                  | **SONAR**              | X          |
| Patch a leak           | hold **R**             | hold **PATCH**         | Y          |
| Repair kit / oxygen    | **1** / **2**          | buttons in the sub panel | -        |
| Leave the sub          | **LEAVE SUB** button (only at the surface) | same | -   |

The core loop:
1. Board your sub, which floats at your berth.
2. Dive. The deeper you go, the darker it gets.
3. Drive into glowing salvage on the sea floor to collect it.
4. Watch your **hull**, **air** and **cargo**. Monsters cause leaks, and leaks
   drain your hull.
5. **Surface** to bank the haul as coins. If you sink, you keep only 10%.
6. Spend coins at the **Shop**: hull, engine, lights, cargo, plating and
   harpoon upgrades, supplies, and paint.

## What's in Version 1

* **Zones:** Sunlit Reef (0–200 m) and Twilight Drop (200–600 m), with a
  sealed door to the Midnight Trench at the bottom as a teaser for later
  updates.
* **Hulls:** Tin Can (2 seats, rated to 210 m), Steel (4 seats, rated to
  620 m) and Titanium. Abyssal Alloy is listed as "coming soon".
* **Upgrades:** engine (5 stars), lights (Lamp, Floodlight, Sonar Beam), cargo
  (5 sizes), hull plating (3 tiers), harpoon turret (3 tiers).
* **Monsters:**
  * Biter fish ram the hull.
  * Jellyfish swarms latch on, drain health and slow you down.
  * Eel packs ram hard and drag you off course.
  * Monsters get stronger the deeper you go, and solo subs take less damage.
* **Hazards:** leaks (patch them), oxygen timer, and crush damage when you go
  deeper than your hull is rated for.
* **Crew (2–4 players):**
  * The **Crew** button lets you invite players, or open your sub to anyone.
    Friends can always board.
  * Stations: Helm drives, Turret shoots, Sonar has faster and bigger pings,
    Repair patches leaks fast.
  * Each extra crew member adds +15% loot.
  * Solo players get an auto-repair kit instead.
* **Hooks:**
  * Distress-signal wrecks with rare loot appear every few minutes.
  * Expedition lore logs are found inside those wrecks.
  * Daily chest with a login streak.
  * "Deepest Dives" leaderboard at the dock, shared across all servers.
* **Saving:** DataStore with retries, autosave every 2.5 minutes, and saves on
  leave and on shutdown. If loading fails, that session is never saved, so a
  bad load can't wipe anyone's progress.
* **Robux (optional):** coin packs, a 2x loot boost, emergency surface and a
  VIP pass. They stay hidden until you create them on the Creator Dashboard
  and put their IDs in `Config.Monetization`. Every gameplay item can also be
  earned by playing.

## Where to change things

Everything you'd want to balance is in **`DeepDiveConfig`**: prices, hull HP,
dive depths, engine speeds, cargo slots, monster health and damage, loot
values, spawn counts, the daily chest, lore text, sounds and Robux IDs. Change
a number there and it updates everywhere.

| Script | What it does |
|---|---|
| `DeepDiveConfig` | All the numbers and settings (server and client both read it) |
| `WorldBuilder` | Builds the terrain sea floor, dock, berths, shop hut, leaderboard and decorations |
| `SubBuilder` | Builds a sub out of parts (size depends on hull tier) |
| `PlayerData` | Saving and loading |
| `Monsters` | Monster models, AI, spawning and despawning |
| `GameServer` | Rules: boarding, crew, damage, loot, surfacing, shop, Robux |
| `GameClient` | HUD, menus, controls, darkness and fog, effects |

The server owns all coins, loot, damage and purchases. The client only sends
requests.

## Testing checklist

1. Press **Play**. You spawn on the dock, the tutorial box appears and a daily
   chest pops up.
2. Walk to the berth with your name on the sign and press **E** to board.
3. Dive with **Q**. The depth gauge counts up and it gets darker and bluer.
4. Collect a few glowing items. The cargo counter goes up.
5. Rise with **E**. The "HAUL BANKED!" popup appears and your coins go up.
6. Buy the Harpoon Mk I in the Shop, dive again and shoot a biter fish.
7. Try going below 210 m in the Tin Can. The hull should start crushing.
8. Multiplayer: **Test > Clients and Servers > 2 players**, then invite the
   other player from the Crew menu.

If something breaks, open **View > Output** and copy the red error text.

## Rebuilding the place file

After editing anything in `src/`, run `python3 tools/build_place.py` to
regenerate `DeepDive.rbxlx`.
