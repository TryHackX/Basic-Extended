# Basic-Extended 3.5

The complete server essentials, Battlefield 3-style health regeneration, dynamic damage numbers, tactical radar, and administration suite for **Soldat Dedicated Server 2.8.2 (Soldat 1.7.1)** running **ScriptCore 3**.

Author: **Dominik (TryHackX)** — MIT License. Designed for high-performance servers, running natively alongside [ZitroStats](https://github.com/TryHackX/ZitroStats-Core) and [AntiFake-Extended](https://github.com/TryHackX/AntiFake-Extended).

---

## Contents

1. [Overview & Architecture](#overview--architecture)
2. [Key Features](#key-features)
3. [Directory Structure](#directory-structure)
4. [Installation](#installation)
5. [Commands Reference](#commands-reference)
6. [Modules & Mechanics](#modules--mechanics)
   - [Health HUD & In-Game Editor](#health-hud--in-game-editor)
   - [BF3 Health Regeneration & Suppression](#bf3-health-regeneration--suppression)
   - [Damage Numbers & Hit Flash](#damage-numbers--hit-flash)
   - [Tactical Radar & Overlays](#tactical-radar--overlays)
   - [Admin Tools: Teleport, Trajectory, Aimbot, Explosions](#admin-tools-teleport-trajectory-aimbot-explosions)
   - [Anti-Cheat Statistics](#anti-cheat-statistics)
   - [Command Permissions](#command-permissions)
   - [Map Geometry in the Library](#map-geometry-in-the-library)
   - [Steam ID Admin Rights & Moderation](#steam-id-admin-rights--moderation)
   - [Combat Extras & Class Mechanics](#combat-extras--class-mechanics)
7. [Configuration (`settings.ini`)](#configuration-settingsini)
8. [Building from Source](#building-from-source)
9. [Troubleshooting](#troubleshooting)
10. [Roadmap](ROADMAP.md)

---

## Overview & Architecture

**Basic-Extended** unites and replaces four legacy server scripts into a single, high-performance PascalScript + native Cdecl library architecture:
- **Basic 2.0.2** (commands, timers, admin utilities, map rotation)
- **Info** (`/info`, map statistics, anti-cheat reporting hints, tips)
- **DamageDisplay 1.6** (floating damage numbers, hit feedback)
- **BFRegeneration 0.0.3** (Battlefield 3 health regeneration, suppression, kit suppression)

```text
Soldat Dedicated Server (Game Thread)
  |  events: OnDamage, OnKill, OnTick, OnCommand, OnSpeak, OnSteamAuth
  v
main.pas (ScriptCore 3 bridge)
  |  reads the game state once per pass (one call per player into the library), sends only the
  |  texts the library asks for, does what only the game can do (move, bullets, objects)
  v
basicext_dll.dll / .so (native code)
     Map geometry (the .pms polygons and sectors, ray casts exactly like the server's)
     Radar engine (list / labels / circle / ring layout, exact glyph metrics of the game font)
     Text diff engine (per-player sent state, only changed texts go out, per-tick and per-second caps)
     Team vision (what the players see: the screen, or ray casts through the walls)
     Teleport / flight controller (tap, hold steering with camera-lag compensation, dead zone)
     Ballistics (weapons.ini, muzzle position, bullet paths clipped to the view, lead solver,
                 fire rate / magazine / reload, the game's inaccuracy model, explosion patterns)
     Anti-cheat statistics (start-up, fire interval, jumps, bink, movement accuracy, head hits)
     Suppression (swept bullet tests against the hurt players)
     Text helpers (message templates, HUD text and bar, numbers, colours, log lines, weapon names)
     TBEStore (BEDB binary storage, memory-mapped preference lookups)
     TBEWriter + Worker Thread (asynchronous logger, disk IO every 2s without holding server ticks)
```

### Why It Keeps the Server Fast:
- **Zero Disk Stalls on the Game Thread:** Preferences and player coordinates are kept in memory. The native library (`basicext_dll`) runs its own background worker that writes `players.bdb` and append-only text logs without delaying game physics ticks.
- **Library Module Pinning:** The DLL/SO pins itself in memory (`GET_MODULE_HANDLE_EX_FLAG_PIN` / `RTLD_NODELETE`), allowing seamless in-game `/recompile` reloading without crashing background threads.
- **Packet & Console Flooding Prevention:** Commands and system messages are queued and metered (`LinesPerTick`, `BroadcastLinesPerTick`, `TEXTS_PER_TICK`) to prevent client-side network choking and engine freezes.
- **Selective Processing:** Heavy collision checks (e.g. bullet suppression scans) operate exclusively when hurt players are waiting for regeneration and scan only active bullet IDs.
- **Math in Native Code:** PascalScript is slow (an array element or a property costs about a microsecond, as much as a call into the library), so every layout, distance, colour, ballistic, ray cast and movement calculation runs in `basicext_dll`. The script reads each player once per pass and hands the values over with one call; the library reads the map itself and answers ray casts in about a microsecond. `/be_bench` measures these costs on the running server.
- **Diffed Text Updates:** Every radar, trajectory and damage text is compared with what the player already has; unchanged texts are not sent again, small moves under a threshold are ignored, and each player gets at most `TextsPerTick` / `MaxTextsPerSecond` radar texts.

---

## Key Features

- **Dynamic Health HUD:** BigText on-screen display with smooth color interpolation (Green $\to$ Yellow $\to$ Red), low-health flashing, customizable layouts, and an **interactive in-game live editor** (`!hp edit`).
- **Battlefield 3-style Health Regeneration:** Health regenerates gradually after a delay, accelerating over time. Nearby enemy bullet passes apply **Suppression**, pausing regeneration.
- **Dynamic Damage Numbers:** WorldText numbers floating above hit targets (`sum`, `column`, or `hit` modes). Automatically hides damage numbers through walls when playing in Realistic Mode (Line of Sight checks).
- **Tactical Radar / ESP Overlay:** Four modes: `list` (HUD text with the distance in meters, as the kill screen shows it, each line coloured by team, health or distance), `labels` (overhead player tags), `circle` (circular mini-map with an optional outline of the walls around you; each player may scale the marks and the edge dots), and `ring` (a dot on a ring around your soldier for each nearby player: the size is the distance, `F` marks a flag carrier). Dropped flags are shown in every mode. Vision filters (`all`, `seen`, `seenall`, and `seenreal` / `seenallreal` with ray casts through the walls - in realistic mode `seen` casts rays too), team mates on or off, every mode keeps its own place, size, zoom, update rate and reach, and each group (full users / everybody) has its own modes, default, filter and speed limit.
- **Admin Tools:** click / hold teleport that steers after the cursor, smooth flight to the cursor (optionally above the game's speed limit with short jumps), the bullet trajectory of any player (following a Barrett bullet the camera follows) or only their cursor, seen by you, that player, both or everybody, an aimbot that uses the weapon's real magazine, reload and inaccuracy (cursor, radius or nearest target, extra shots after a kill, LAW rules, colliders, Spas-12 and Minigun recoil), a speed booster (everywhere, on the ground, or the ground and a stronger jump), chat and team chat lines as another player, the library follows the server's `/loadwep`, 14 kinds of explosions, and commands that take `all`, teams or names: give weapons with ammo, bonuses, stationary guns, infinite ammo, damage and vest changes.
- **Anti-Cheat Statistics:** Barrett start-up time, fire rate, magazine and reload speed, teleports, speed, hits under bink and while moving - per game and for all games of a computer (by the hardware id, so players without Steam too); `/suspects`, `/acstats` (a table of every check) and `/acreview` for every player by default, so anybody can check a suspect; a log of every finding and an optional vote kick.
- **Command Permissions (`[Permissions]`):** every command can be for everybody, the admins, the console only or nobody, typed with `/`, `!` or both.
- **Example configs (`Example configs/`):** ready `settings.ini` files for CTF, Infiltration, Hold the Flag, Team Match, Deathmatch, a survival + realistic deathmatch on RSCS maps and a clean competitive server: the "hack" tools only for admins (or off), the anti-cheat for everybody.
- **Killing Sprees (`[Spree]`):** the old sprees are back, switched off by default (ZitroStats has its own).
- **Steam ID Authentication:** Assigns admin permissions verified directly against Steam Web tickets (`Admins_Steam.txt`), eliminating HWID spoofing vulnerabilities.
- **Modular Combat Extras:** Optional assists, multikill announcements, first blood rewards, savior bonuses, suicide penalties, posthumous martyrdom grenade drops, and medic classes.

---

## Directory Structure

```text
soldatserver/
|-- logs/basic-extended/             created automatically for daily logs
|   `-- watched/                     individual logs for watched players
`-- scripts/
    `-- Basic-Extended/
        |-- main.pas                 ScriptCore 3 script
        |-- basicext_dll.dll         32-bit Windows native library
        |-- basicext_dll.so          32-bit Linux native library
        |-- README.md
        |-- Example configs/         ready settings.ini files (ctf, inf, htf, tm, dm, rscs, clean)
        |-- data/
        |   |-- settings.ini         master configuration
        |   |-- players.bdb          binary player preferences database
        |   |-- Admins_Steam.txt     list of authorized Steam IDs
        |   |-- Admins_Commands.txt  help file for /admincommands
        |   |-- Commands.txt         player command list (if Source = file)
        |   |-- Rules.txt            server rules displayed on join/map change
        |   |-- Messages.txt         rotating periodic tips/announcements
        |   |-- Reserved.txt         Steam IDs / IPs for slot reservation
        |   `-- Watched.txt          targets tracked by the logger
        `-- source_dll/              Free Pascal source for basicext_dll
```

---

## Installation

1. Copy the `Basic-Extended` folder into your server's `scripts/` directory:
   ```text
   soldatserver/scripts/Basic-Extended/
   ```
   *(Ensure the path does not contain spaces).*
2. Ensure `scripts/scripts.ini` contains the script entry:
   ```ini
   [Scripts]
   Basic-Extended
   ```
3. Verify that native libraries can be loaded:
   - In `server.ini`, under `[ScriptCore3]`: `AllowDlls=1`
4. On Linux, ensure `basicext_dll.so` has execution permissions, or compile it from `source_dll/` (see [Building from Source](#building-from-source)).
5. Start or recompile your server (`/recompile`).

---

## Commands Reference

### Player Commands (Chat `!` or `?`)

| Command | Arguments | Description |
| :--- | :--- | :--- |
| `!cmd`, `!command` | *none* | Displays available server commands and extra script links. |
| `!rules`, `!rul` | *none* | Displays server rules. |
| `!hp`, `!health` | `[on\|off\|style\|size\|pos\|edit\|reset]` | Toggles or configures the health display. `!hp edit` opens the visual editor. |
| `!dmg`, `!damage` | *none* | Toggles floating damage numbers over targets. |
| `!radar` | `[on\|off\|mode\|tick\|zoom\|show\|team\|outline\|marks\|edge\|edit\|pos\|size\|reset]` | Configures the tactical radar (if public). The modes of the player's group (`[Radar] PublicModes`). Place, size, zoom and rate are kept for each mode. |
| `!rate`, `!ratio`, `!kd` | `[player]` | Displays kill/death ratio and flag capture statistics. |
| `!ping` | `[player]` | Checks ping of self or another player. |
| `!track`, `!t` | `[player]` | Tracks ping of a player over several seconds and reports average/max. |
| `!time`, `!date` | *none* | Displays current server date and time. |
| `!whois`, `!whoisadmin` | *none* | Lists connected In-Game and TCP server admins. |
| `!admin`, `!calladmin` | `[message]` | Calls connected admins or sends an alert to the server console. |
| `!medic`, `!med` | *none* | Enlists as team medic (class mode) or requests medical extraction (call mode). |
| `!j`, `!start`, `!play` | *none* | Joins the active game (auto-balances to smaller team). |
| `!s`, `!spec` | *none* | Moves player to spectator team. |
| `!maplist`, `!listmaps`| *none* | Lists all maps in server rotation. |
| `?map`, `?nextmap`, `?lastmap` | *none* | Displays current, upcoming, and previous map names. |
| `!suspects`, `/suspects` | `[all]` | Anti-cheat: the players of this game by suspicion (`all`: everybody), with the suspicion over all games of their computer. |
| `!acstats`, `/acstats` | `<player>` | A table of every anti-cheat check: this game and all games of that computer. |
| `!acreview`, `/acreview` | `<player>` | The last things the anti-cheat noticed, newest first. |

### Admin Commands (`/` in game or Server Console)

| Command | Arguments | Description |
| :--- | :--- | :--- |
| `/admincommands` | *none* | Displays admin command documentation (`Admins_Commands.txt`). |
| `/steamadmin` | `[add\|del <player\|SteamID>]` | Lists or modifies authorized Steam admins (`Admins_Steam.txt`). |
| `/radar`, `/overlay` | `[mode\|tick\|zoom\|show\|team\|outline\|marks\|edge\|edit\|pos\|size]` | Configures the radar of full users (`FullModes`, all four modes by default). |
| `/tele`, `/tp` | *none* | Toggles click-to-teleport (jump to cursor on configured key). |
| `/teletomouse`, `/ttm` | `[inherit\|fixed]` | Tap the key = jump to the cursor and keep flying; hold it = fly where the cursor points (turning round too), jumping towards it. `inherit`: the longer you hold, the faster you fly (up to `InheritMax`). |
| `/flytomouse`, `/ftm` | *none* | Toggles flight toward the cursor while holding the key (faster when it is further, hovering when it is on you; up to the game's speed limit, `FlyHops = 1` for more with short jumps). |
| `/trajectory`, `/traj` | `[player [cursor] [me\|self\|selfme\|public]\|off]` | Draws where the bullets of your (or a player's) weapon fly, only the part on screen; green = where they hit; ahead of a Barrett bullet the camera follows. `cursor`: only that player's cursor. Who sees it: `me` (only you, the default), `self` (only that player), `selfme` (both), `public` (everybody). |
| `/aimbot`, `/aim` | `[on\|off\|cursor\|nearest\|radius [px\|edit\|save\|cancel]\|acc <0-100>\|extra <min-max>\|law <game\|ground\|anywhere>\|colliders on\|off]` | While the aimbot key (crouch) is held, your weapon fires at an enemy, leading moving targets. `radius`: only enemies within that many pixels of the cursor (`radius edit` draws the circle for you); `acc` = share of the weapon's own inaccuracy; `extra` = random shots more after the target is gone. |
| `/speed`, `/speedhack` | `<player> [1.1-5\|off] [all\|ground\|jump]` | Runs and flies faster; `ground`: only on the ground, `jump`: the ground and a stronger jump off it. |
| `/sayas`, `/sayteam` | `<player> <text>` | A chat (or team chat) line as that player; the admin is written to the server console. |
| `/loadwep` (server) | `<name>` | The server's own command; the library reads the same `configs/<name>.ini` right after, so the trajectory, the aimbot and the anti-cheat use it. |
| `/slay` | `<player>` | Kills at once. |
| `/god`, `/heal`, `/slap`, `/freeze` | `<player> [...]` | Godmode, full health, a slap (optional damage), freeze (again = free). |
| `/explode` | `<player> [kind]` | Detonates an explosion at the target: `plain`, `big`, `nuke`, `law`, `m79`, `arrows`, `firearrows`, `bullets`, `spas`, `flame`, `cluster`, `nades`, `knives`, `rain`. |
| `/bigexplode`, `/boom`, `/nuke` | `<player>` | A spectacular big explosion, or a nuke (rings of blasts and rockets from the sky). |
| `/bring`, `/goto` | `<player>` | Teleports players to you, or you to a player. |
| `/disarm` | `<player>` | Takes the weapons. |
| `/give` | `[near] <player> [ammo] <weapon>` | Gives a weapon with that many rounds (`/give all 30 ak`); `near` drops it next to them. A bow outside Rambo is refused (the server bans for it). |
| `/bonus` | `[near] <player> <kind>` | Gives a bonus at once: `predator`, `berserker`, `vest`, `nades`, `clusters`, `flame`, `medkit` (1-7); `near` drops the kit next to them. |
| `/statgun`, `/removestatgun` | `[player]`, `[all]` | Places a stationary gun next to you (or a player); removes the nearest one (or all). |
| `/infammo` | `<player>` | Infinite ammo on/off (a thrown knife comes back). |
| `/dmgfix`, `/dmgtaken` | `<player> <+n%\|-n%\|n%\|xN\|off>` | Changes the damage the player deals / takes (`/dmgfix 1 +2%`, `/dmgtaken bravo -10%`). |
| `/vest` | `<player> [0-100]` | Sets body armour. |
| `/acclear` | `<player\|all> [all]` | Forgets the anti-cheat numbers (`all`: all games too); `/acclear all all` forgets everybody and the whole history. |
| `/banr` | `<id> <time> <reason>` | Timed player ban (e.g. `10m`, `2h`, `7d`, `1mon`, `1y`). |
| `/banipr`, `/banhwr` | `<time> <IP\|HWID> <reason>` | Manual timed IP or Hardware ID ban. |
| `/killall`, `/kickall`| *none* | Mass moderation commands (respects admin exemptions). |
| `/explodeall` | `[kind]` | Explodes every other living player. |
| `/randomize` | *none* | Shuffles server map list rotation. |
| `/reloadsettings`, `/be_reload` | *none* | Hot-reloads `settings.ini` and text data files without server restart. |
| `/be_status` | *none* | Displays live engine performance, memory database status, and throughput stats. |
| `/be_bench` | *none* | Measures the bullet scan, the kit sweep, a property read, the player snapshot and a library call (run on test servers). |
| `/be_test` | `<slot> <command>` | Emulates player commands for testing. |

---

## Modules & Mechanics

### Health HUD & In-Game Editor

The Health HUD displays real-time vitals using a high-layer BigText element (`Layer = 199`). It smoothly transitions through colors based on remaining life:
$$\text{Full (Green)} \longrightarrow \text{Half (Yellow)} \longrightarrow \text{Low (Red)}$$

When health falls to or below `LowPercent` (default: 25%), the HUD flashes to alert the player.

**Interactive Visual Editor (`!hp edit`):**
- **Movement Keys (Left / Right / Jump / Crouch):** Moves HUD pixel by pixel. Holding increases speed.
- **Reload Key:** Increases font scale.
- **Change Weapon Key:** Decreases font scale.
- **Grenade Key (E) or `!hp done`:** Saves position and exits.
- **Prone Key (X):** Discards changes and exits.

---

### BF3 Health Regeneration & Suppression

1. **Healing Curve:** After taking damage, regeneration pauses for `DelaySeconds` (5s). Healing starts at `StartRate` (%/s) and accelerates by `Acceleration` (%/s²) until reaching `MaxRate` (50%/s).
2. **Suppression:** Bullets passing within `Radius` pixels (50px for small arms, 130px for explosives) reset the delay timer by `DelaySeconds` (3s), suppressing health regeneration even if the shot misses.
3. **Kit Suppression:** Medkits and grenade crates can be stripped from `.pms` maps automatically on map load (`Medkits = 1`, `GrenadeKits = 1`), preserving tactical reliance on regeneration.

---

### Damage Numbers & Hit Flash

- **Floating Indicators:** When inflicting damage, WorldText numbers float above the victim, visible exclusively to the attacker.
- **Modes:**
  - `sum`: Accumulates consecutive hits into a growing number.
  - `column`: Displays up to 5 individual hits stacked vertically.
  - `hit`: Renders an independent number per impact.
- **Line-of-Sight Protection:** In Realistic Mode, damage numbers are suppressed if the target is behind cover or outside visibility, preventing players from locating enemies through fog-of-war.
- **Hit Flash (`[HitFlash]`):** Optional screen-wide red vignette pulse scaled to the amount of damage received.

---

### Tactical Radar & Overlays

Designed for administrative spectating, competitive tournaments, or public tactical servers:

| Mode | Visual Representation | Target Audience |
| :--- | :--- | :--- |
| `list` | Static on-screen text panel with direction, health and the distance in meters (`{m}`, pixels / 14 like the kill screen) | Admins / Public |
| `circle` | Circular mini-map HUD showing relative angles and ranges | Admins / Public |
| `labels` | Name and health tags centred over the soldiers (health coloured) | Steam Admins |
| `ring` | A dot on a ring around your soldier for each nearby player; the dot's size tells the distance, `F` a flag carrier; colours by team, distance or health | Steam Admins |

Every mark is centred exactly with the metrics of the game font. The ring is drawn where your soldier will be when the texts reach you (your ping and speed). `!radar team off` hides the team mates; every mode keeps its own position, size, zoom and update rate. The letters of the ring keep one size (`RingLetterScale`) however close the player is.

**Radar editor (`!radar edit`):** the movement keys move the list or the circle (a tap = 1 pixel), reload / change weapon resize it in fine steps; the labels (their letters) and the ring (its dots) are resized the same way.

**A smooth circle:** with `CircleMovePixels = 0` a mark is sent every time it moves a screen pixel. A bigger circle (`!radar size`) moves its marks in finer steps; `!radar marks <n>` keeps the marks small in it and `!radar edge <n>` (`CircleEdgeScale`, for example 1.2 = 20% bigger) sizes the ring's dots and the players beyond reach. The soldier is not pulled back every tick while a key is held any more (that flooded the server with position updates), and the marks keep their size while you resize, so the game does not have to build new letter sets.

**Who gets which mode (`[Radar]`):** full users are the Steam ids of `SteamIds` (and the admins with `AdminsFull = 1`); with `Public = 1` everybody else gets `PublicModes` too. Each group has its start mode (`Mode` / `PublicMode`), on or off at the start, filter (`Show` / `PublicShow`, the public may not choose to see more) and the fastest update (`FullMinTicks` / `PublicMinTicks`). For example a circle for everybody showing only the enemies the team can see, and every mode with everybody for the admins. Each mode may have its own reach (`ListRange`, `LabelsRange`, `CircleRange`, `RingRange`).

**Flags and the map:** a dropped flag (out of its base, not carried) is a line of the list, a mark on the circle and the ring, a label over it; a carried flag is not drawn again over its carrier, whose own mark says `F`. `!radar outline on` casts `OutlineDots` rays from you in every direction and puts a dot in the circle where each one meets a wall - the shape of the room or cave you are in (made again only when you moved).

**Vision Filtering:**
- `all`: everybody within reach.
- `seen`: only the enemies on the screen of you or a living team mate (the part of the map the game shows around the camera); in realistic mode, where the walls hide the players, only those in the line of sight (ray casts).
- `seenall`: the same, with the dead team mates too.
- `seenreal`, `seenallreal`: always the line of sight (ray casts through the walls), also outside realistic mode.

---

### Admin Tools: Teleport, Trajectory, Aimbot, Explosions

- **Teleport (`[Teleport]`):** the key is read every tick. `/tele` jumps to the cursor and stops. `/teletomouse`: a tap jumps and keeps the speed towards the cursor; holding the key longer than `HoldTicks` flies where the cursor points - move the mouse to the other side and you turn round - with jumps towards it at most every `HopTicks` (and not before your ping has passed). The game's camera lags behind after every jump, so for a moment the cursor seems to be behind you; the controller leaves that out. With `inherit` the speed grows the longer you hold (`InheritAccel` per second, `InheritGain` per jump, at most `InheritMax`). `/flytomouse` flies smoothly: the speed grows with the distance beyond `FlyDeadZone` (8 px) up to `FlyMax`. The game keeps a soldier's speed at 11 px a tick on each axis (15.5 diagonally), so by default (`FlyMax` = `FlyVelocityMax` = 15.5) it flies at that limit without any jumps; `FlyHops = 1` makes up what a higher `FlyMax` (up to 60) asks with short jumps along the way (`FlyHopTicks`, `FlyHopMaxPixels`) - faster, but the soldier visibly jumps. With the cursor on the soldier you hover. Jumps never end in a wall (`NotIntoWalls`).
- **Trajectory (`[Trajectory]`):** `/trajectory [player]` shows the flight of the bullets of the weapon in hand (speed, gravity and the speed of the soldier taken from the server's `weapons.ini`), from the gun's real muzzle (standing, crouching or prone), with ray casts against the map; the dot where the bullets hit is green. It is worked out again only when the position, speed, cursor, weapon or stance changed, and only the part the player can see is drawn (the screen around the camera, which the game keeps between the soldier and the cursor - further out with a Barrett zoom). Soldat sends the cursor to the server only after the mouse moved about 30 pixels, so a far M79 shot can land a little off the drawn path. When the watched player fires a Barrett while crouching or prone (the game's camera then follows the bullet), the dots are drawn ahead of the flying bullet and disappear behind it. `/trajectory <player> cursor` shows only that player's cursor. Who sees it: `/trajectory <player> [cursor] me|self|selfme|public` - only you (the default; the watched player never knows), only that player (his own dots), both of you, or everybody.
- **Aimbot (`[Aimbot]`):** while the key (crouch) is held, the weapon in hand fires at the enemy nearest to the line of the cursor, only at enemies within a circle around the cursor (`radius`, never jumping to somebody far away; `/aimbot radius edit` draws the circle for you until you save it), or at the nearest one. The shot leads a moving target, keeps the fire rate, start-up and reload of the weapon, takes a round of its real magazine (the game reloads it; `/infammo` or `InfiniteAmmo` = no), a thrown knife leaves the hand with the game's throw sound, and a Spas-12 or Minigun shot pushes the shooter back as in the game (`Recoil`). `/aimbot acc <0-100>` adds that share of the weapon's own inaccuracy (standing, crouching, prone, running and jumping as in the game). After the target dies it fires a few more shots the same way (`ExtraShots`, a random number in a range), so it does not stop at once. While you fire yourself it waits, so the magazine count of the server and of your game stay the same. The LAW fires as in the game (on the ground, crouching or prone) unless `/aimbot law ground|anywhere`. Colliders (the red circles that stop bullets) block the aim like walls (`Colliders`). With `Key = fire` the weapon's own bullets do no damage while the aimbot is on. The server does not let a script turn a player's cursor or press keys for a human (only for bots), so the soldier's arm does not follow the target.
- **Speed, chat, weapons (`[Admin]`):** `/speed <player> [factor] [all|ground|jump]` pushes running and jets up to that factor (`ground`: only running on the ground; `jump`: the ground and the jump off it, `SpeedJumpShare` of the boost, nothing in the air); `/sayas` and `/sayteam` write a chat or team chat line as another player in the game's own format and colours; after the server's `/loadwep <name>` the library reads `configs/<name>.ini` too.
- **Explosions (`[Admin]`):** `/explode <player> [kind]`, `/bigexplode`, `/nuke`. The patterns are built in the library and spawned over several ticks (at most 48 bullets a tick, and never into the last 32 free bullet slots of the game). `ExplodePower` scales the damage.

---

### Anti-Cheat Statistics

Numbers worked out in the library from what the server sees (`[AntiCheat]`). By default every player may look them up (`/suspects`, `/acstats`, `/acreview`, with `/` or `!`), so anybody can check a suspect; `/acclear` is for admins.

| Measure | How |
| :--- | :--- |
| Start-up | The time from the fire key (it reaches the server with the movement packets) to the Barrett / LAW bullet. The Barrett needs 19 ticks; a cheat without start-up fires at once. A lost packet can make one honest shot look short, so the share matters. |
| Fire rate | Two bullets of a weapon with a long interval (Barrett, Ruger, Spas...) closer than `FireIntervalShare` of it. |
| Ammo | The magazine emptied faster than the fire interval allows, or full again sooner than the reload time (weapons given by the script and picked up are left out). |
| Teleports | A living player who moved further than 11 px a tick on each axis allows between two looks (with lag allowance); moves by the script are left out. |
| Speed | More than `SpeedPixels` a tick on average over a second. |
| Hits under bink | Barrett hits fired soon after the shooter was hit while holding it (the game spreads those bullets widely). |
| Hits while moving | Hits by weapons with movement inaccuracy fired while running, jumping or flying. |

Head hits are not counted: in Soldat they are easy to get just by being above a player. The fire time of every hit is worked out from the bullet's position and speed, so only hits are seen (the server tells nothing about misses). `/suspects` lists the suspicious players of this game (`all`: everybody) with one short line each and the suspicion over all games of that computer (`Kruger (3): 45% - start-up 3/5 too fast, teleports 2 (310 px)  | 20% in 7 games`), `/acstats <player>` a coloured table - every check in this game next to all games of that computer (kept in `players.bdb` by the hardware id, so players without Steam too) - and `/acreview <player>` the last things noticed with how long ago. `/acclear all all` forgets everybody and the whole history. Findings go to `data/anticheat.log` with ping, computer id and address, and admins in the game are told once a player's suspicion reaches `TellFromScore`. With `VoteKick = 1` a vote to kick starts (with the reason and a line to everybody) when the suspicion reaches `VoteFromScore` with at least `VoteMinFindings` findings - never over another vote and never for an admin; nobody is kicked by the script itself.

---

### Command Permissions

`[Permissions]` in `settings.ini` sets who may use a command and how it is typed: `<command> = <who> [<how>]` with who = `all`, `admins`, `console` or `off`, and how = `/`, `!` or `both`. For example `aimbot = admins both` also allows `!aim` in the chat, `trajectory = console` keeps it to the server console, `ratio = off` frees its words. By default `suspects`, `acstats` and `acreview` are for everybody with `/` and `!`. The names of all commands are listed in the file; `Example configs/` shows complete sets.

---

### Map Geometry in the Library

At every map change the library reads `maps/<map>.pms` (`[MapGeometry] MapFolder`) and casts rays exactly like the server (sectors, polygon types, team polygons), only faster: it skips polygons already tested and those whose bounding box the ray misses. The radar's `seen` filter, the trajectory, the aimbot's line of sight, the realistic fog of war of the damage numbers and the teleport's wall check use it; when the map cannot be read, the script casts the rays with `Map.RayCast` as before. `/be_status` shows the polygon count and compares rays between the players with the server's own.

---

### Steam ID Admin Rights & Moderation

- **Spoof-Proof Identity:** Unlike IP- or HWID-based admin lists, Steam accounts are verified cryptographically via `OnSteamAuth`.
- **Automatic Assignment:** Verified Steam IDs listed in `data/Admins_Steam.txt` receive admin privileges immediately upon join.
- **Clean Leave Cleanup:** Temporary IP permissions granted through Soldat's `remote.txt` are revoked automatically upon disconnect, keeping your server secure.

---

### Combat Extras & Class Mechanics

- **Assists (`[Assists]`):** Players dealing $\ge 65\%$ damage to an enemy who is subsequently killed receive assist credit and bonus points.
- **MultiKill Combos (`[MultiKill]`):** Streak banners (`Triple kill!`, `Godlike!`) for multi-kills achieved within a 3-second window.
- **Martyrdom (`[Posthumous]`):** Dying players have a skill-scaled chance to drop a live grenade upon death.
- **Medic Mechanic (`[Medic]`):** Allows players to act as field medics, radiating area-of-effect healing to nearby teammates.
- **TimeToKill (`[TimeToKill]`):** Prevents infinite standoffs in Survival mode by triggering an end-of-round sudden death countdown when few players remain.

---

## Configuration (`settings.ini`)

The settings file is located at `scripts/Basic-Extended/data/settings.ini`. It supports in-game hot reloading via `/reloadsettings`.

Key sections include:
- `[General]`: Output line rates, broadcast throttling, and startup banners.
- `[HealthHud]`: HUD layers, default positions, styles, and low-health blink intervals.
- `[Regeneration]` & `[Suppression]`: Regeneration curves, delay intervals, and suppression radii.
- `[Kits]`: Toggle map removal of medkits, grenade kits, and bonus crates.
- `[DamageNumbers]`: Modes, colors, and line-of-sight filters.
- `[Radar]`: who gets which modes (Steam IDs, admins, everybody), filters, reach and update rate of each mode, list colours, flags, the circle's marks and edge dots, the ring's letters and the map outline.
- `[Admin]`: Steam admin files, ban duration caps, command aliases, explosion commands and power, `/speed` (mode, jump share), `/sayas`, `/sayteam`, `/slay`.
- `[Teleport]`: Tap / hold behaviour, velocity inheritance, flight speed, dead zone and smoothing, wall collision prevention, and trigger keys.
- `[Trajectory]`, `[Aimbot]`: Commands, update rates, dots, view clipping, following a bullet, target selection (cursor, radius, nearest), range, spread, extra shots, LAW rule, colliders, recoil, ammunition and sound.
- `[Weapons]`: Which `weapons.ini` the trajectory and the aimbot read (`auto` = the server's own; a `/loadwep` is followed).
- `[AntiCheat]`: Commands, thresholds, the log file, when admins are told, the optional vote kick and the colours of the lines.
- `[Permissions]`: who may use each command and whether it is typed with `/`, `!` or both.
- `[MapGeometry]`: Where the map files are and how many vision rays the library casts a tick.
- `[Spree]`: Killing sprees (off by default).

Ready files for several kinds of servers are in `Example configs/` (see its `README.md`).

---

## Building from Source

Requirements: **Free Pascal Compiler 3.2+ for i386** (Soldat server is 32-bit).

### Windows

Run `build.bat` inside `source_dll/`:
```bat
cd scripts\Basic-Extended\source_dll
build.bat            :: builds basicext_dll.dll
build.bat debug      :: builds debug binary with overflow/range checks
```

### Linux (Ubuntu / Debian x86_64)

Install the 32-bit compilation toolchain and FPC i386:
```bash
sudo apt-get install binutils libc6-dev-i386
wget https://downloads.sourceforge.net/project/freepascal/Linux/3.2.2/fpc-3.2.2.i386-linux.tar
tar xf fpc-3.2.2.i386-linux.tar && cd fpc-3.2.2.i386-linux && sudo ./install.sh
```

Build the shared library:
```bash
cd scripts/Basic-Extended/source_dll
sh build.sh          # builds basicext_dll.so
sh build.sh debug    # debug build
```

Compiled libraries are automatically placed in `scripts/Basic-Extended/`.

`test.bat` (Windows) builds and runs the tests: the store, the library through its exports, and the engines (radar layout, text diff, teleport controller, ballistics, explosions). `main.pas` needs the library of the same release (`BE_API` 5).

---

## Troubleshooting

| Issue | Cause & Solution |
| :--- | :--- |
| `Invalid External` or library fails to load | Ensure the folder name has **no spaces** (`Basic-Extended`, not `Basic Extended`). |
| Library error: `API mismatch` | `main.pas` and `basicext_dll` are from different releases. Update both together. |
| Changes to `main.pas` do not take effect | Delete `main.psb` (compiled byte-code cache) in the script directory and restart. |
| Health HUD or Damage Numbers not appearing | Check if layer numbers collide with other scripts (`[HealthHud] Layer = 199`). Verify `AllowDlls = 1` in `server.ini`. |
| Damage numbers show through walls | Set `[DamageNumbers] LineOfSight = auto` or `on`. Ensure map polygons are compiled correctly. |
| Steam admins not recognized | Ensure the client runs an authentic Steam copy and `Admins_Steam.txt` contains valid Steam IDs (e.g. `S123456789` or `76561198...`). |
| Server freezes on high player count | Decrease `LinesPerTick` in `[General]`. Ensure `basicext_dll` is running (check `/be_status`). |
| `/be_status` says `map not loaded` | The library could not read `maps/<map>.pms` (another folder: `[MapGeometry] MapFolder`). Everything still works, the script casts the rays itself. |
| An aimbot kill shows the Desert Eagles in the kill list and in ZitroStats | The server names the weapon of a bullet made by a script after its bullet style: for the rifles and pistols (the plain bullet) that is the first such weapon, the Desert Eagles. ScriptCore cannot give a script bullet another weapon; only a write into the server's memory could (see the roadmap). |
| A player (admin too) banned for a day, "Not allowed weapon" | The server's own anti-cheat: a bow outside Rambo mode, a weapon switched off on the server, or a flamer while `sv_bonus_flamer` is 1. `/give` refuses the bow; see `[Admin] GiveFlamer`. |

---

## License

This project is licensed under the [MIT License](LICENSE).