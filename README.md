# Basic-Extended 3.2

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
   - [Steam ID Admin Rights & Moderation](#steam-id-admin-rights--moderation)
   - [Combat Extras & Class Mechanics](#combat-extras--class-mechanics)
7. [Configuration (`settings.ini`)](#configuration-settingsini)
8. [Building from Source](#building-from-source)
9. [Troubleshooting](#troubleshooting)

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
  |  reads the game state once (world snapshot), sends only the texts the library asks for
  v
basicext_dll.dll / .so (native code)
     Radar engine (list / labels / circle / arrows layout, exact glyph metrics of the game font)
     Text diff engine (per-player sent state, only changed texts go out, per-tick and per-second caps)
     Team vision scheduler (which ray casts the script has to do this tick)
     Teleport / flight controller (tap, hold, velocity inheritance, dead zone, smoothing)
     Ballistics (weapons.ini, bullet paths, lead solver, fire rate / magazine / reload, explosion patterns)
     TBEStore (BEDB binary storage, memory-mapped preference lookups)
     TBEWriter + Worker Thread (asynchronous logger, disk IO every 2s without holding server ticks)
```

### Why It Keeps the Server Fast:
- **Zero Disk Stalls on the Game Thread:** Preferences and player coordinates are kept in memory. The native library (`basicext_dll`) runs its own background worker that writes `players.bdb` and append-only text logs without delaying game physics ticks.
- **Library Module Pinning:** The DLL/SO pins itself in memory (`GET_MODULE_HANDLE_EX_FLAG_PIN` / `RTLD_NODELETE`), allowing seamless in-game `/recompile` reloading without crashing background threads.
- **Packet & Console Flooding Prevention:** Commands and system messages are queued and metered (`LinesPerTick`, `BroadcastLinesPerTick`, `TEXTS_PER_TICK`) to prevent client-side network choking and engine freezes.
- **Selective Processing:** Heavy collision checks (e.g. bullet suppression scans) operate exclusively when hurt players are waiting for regeneration and scan only active bullet IDs.
- **Math in Native Code:** PascalScript is slow (a single array operation costs about 2 microseconds), so every layout, distance, colour, ballistic and movement calculation runs in `basicext_dll`. The script only reads the game once per pass and sends the texts the library returns. The radar costs about 0.03 ms per user and tick.
- **Diffed Text Updates:** Every radar, trajectory and damage text is compared with what the player already has; unchanged texts are not sent again, small moves under a threshold are ignored, and each player gets at most `TextsPerTick` / `MaxTextsPerSecond` radar texts (an arrow always goes whole, the oldest first).

---

## Key Features

- **Dynamic Health HUD:** BigText on-screen display with smooth color interpolation (Green $\to$ Yellow $\to$ Red), low-health flashing, customizable layouts, and an **interactive in-game live editor** (`!hp edit`).
- **Battlefield 3-style Health Regeneration:** Health regenerates gradually after a delay, accelerating over time. Nearby enemy bullet passes apply **Suppression**, pausing regeneration.
- **Dynamic Damage Numbers:** WorldText numbers floating above hit targets (`sum`, `column`, or `hit` modes). Automatically hides damage numbers through walls when playing in Realistic Mode (Line of Sight checks).
- **Tactical Radar / ESP Overlay:** Four distinct operational modes: `list` (HUD text with the distance in meters, as the kill screen shows it), `labels` (overhead player tags), `circle` (circular mini-map), and `arrows` (small arrows of dots around your soldier). Features realistic raycast vision filters (`all`, `seen`, `seenall`).
- **Admin Tools:** click / hold teleport with velocity inheritance, smooth flight to the cursor, the bullet trajectory of any player, an aimbot that works with every weapon, and 14 kinds of explosions (`/bigexplode`, `/nuke`, rockets, arrows, knives, rain of bullets...).
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
| `!radar` | `[on\|off\|mode\|tick\|zoom\|show\|edit\|pos\|size\|reset]` | Configures tactical radar (if public). Modes: `list`, `circle`. |
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

### Admin Commands (`/` in game or Server Console)

| Command | Arguments | Description |
| :--- | :--- | :--- |
| `/admincommands` | *none* | Displays admin command documentation (`Admins_Commands.txt`). |
| `/steamadmin` | `[add\|del <player\|SteamID>]` | Lists or modifies authorized Steam admins (`Admins_Steam.txt`). |
| `/radar`, `/overlay` | `[mode\|tick\|zoom\|show\|pos\|size]` | Configures admin radar (includes `labels` and `arrows` modes). |
| `/tele`, `/tp` | *none* | Toggles click-to-teleport (jump to cursor on configured key). |
| `/teletomouse`, `/ttm` | `[inherit\|fixed]` | Tap the key = jump to the cursor and keep flying; hold it = teleport after teleport towards the cursor. `inherit`: the longer you hold, the faster you fly (up to `InheritMax`). |
| `/flytomouse`, `/ftm` | *none* | Toggles smooth flight toward the cursor while holding the key (faster when it is further, hovering when it is on you). |
| `/trajectory`, `/traj` | `[player\|off]` | Draws where the bullets of your (or a player's) weapon fly; green = where they hit. |
| `/aimbot` | `[on\|off\|cursor\|nearest]` | While the aimbot key (crouch) is held, your weapon fires at an enemy, leading moving targets. |
| `/god` | `[player]` | Toggles invulnerability (godmode). |
| `/heal` | `<player\|all>` | Restores health to 100%. |
| `/slap` | `<player> [damage]` | Slaps player upward, dealing optional damage. |
| `/freeze` | `<player>` | Freezes player at current position. |
| `/explode` | `<player\|all> [kind]` | Detonates an explosion at the target: `plain`, `big`, `nuke`, `law`, `m79`, `arrows`, `firearrows`, `bullets`, `spas`, `flame`, `cluster`, `nades`, `knives`, `rain`. |
| `/bigexplode`, `/boom`, `/nuke` | `<player\|all>` | A spectacular big explosion, or a nuke (rings of blasts and rockets from the sky). |
| `/bring`, `/goto` | `<player>` | Teleports player to you, or teleports you to player. |
| `/disarm`, `/give` | `<player> [0-16]` | Strips weapons or grants a specific primary weapon. |
| `/bonus` | `<player> <1-6>` | Grants bonus kits (1: Predator, 2: Berserker, 3: Vest, 4: Grenades, 5: Clusters, 6: Flamer). |
| `/banr` | `<id> <time> <reason>` | Timed player ban (e.g. `10m`, `2h`, `7d`, `1mon`, `1y`). |
| `/banipr`, `/banhwr` | `<time> <IP\|HWID> <reason>` | Manual timed IP or Hardware ID ban. |
| `/killall`, `/kickall`| *none* | Mass moderation commands (respects admin exemptions). |
| `/explodeall` | `[kind]` | Explodes every other living player. |
| `/randomize` | *none* | Shuffles server map list rotation. |
| `/reloadsettings`, `/be_reload` | *none* | Hot-reloads `settings.ini` and text data files without server restart. |
| `/be_status` | *none* | Displays live engine performance, memory database status, and throughput stats. |
| `/be_bench` | *none* | Benchmarks internal collision and object sweep performance (run on test servers). |
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
| `arrows` | Small arrows of `.` dots around your soldier, pointing to the nearest players; the colour tells the distance | Steam Admins |

Every mark is centred exactly with the metrics of the game font. The arrows are drawn where your soldier will be when they reach you (your ping and speed), and a dot is sent again only when it moved more than `ArrowMove` pixels.

**Radar editor (`!radar edit`):** the movement keys move the list or the circle (a tap = 1 pixel), reload / change weapon resize it in fine steps. The soldier is not pulled back every tick while a key is held any more (that flooded the server with position updates), and the marks keep their size while you resize, so the game does not have to build new letter sets.

**Vision Filtering:**
- `all`: Unrestricted tracking.
- `seen`: Displays only enemies visible to you or a living teammate (calculated via raycasting).
- `seenall`: Includes sightlines of dead teammates.

---

### Admin Tools: Teleport, Trajectory, Aimbot, Explosions

- **Teleport (`[Teleport]`):** the key is read every tick. `/tele` jumps to the cursor and stops. `/teletomouse`: a tap jumps and keeps the speed towards the cursor; holding the key longer than `HoldTicks` makes teleport after teleport towards the cursor with pushes in between. With `inherit` the speed grows the longer you hold (`InheritAccel` per second, `InheritGain` per jump, at most `InheritMax`). `/flytomouse` flies smoothly: the speed grows with the distance beyond `FlyDeadZone`, with the cursor on the soldier he hovers, and the direction is smoothed (`FlySmooth`) and corrected for gravity, so a cursor close to the soldier no longer makes him shake left and right.
- **Trajectory (`[Trajectory]`):** `/trajectory [player]` shows the flight of the bullets of the weapon in hand (speed, gravity and the speed of the soldier taken from the server's `weapons.ini`), with ray casts against the map; the dot where the bullets hit is green.
- **Aimbot (`[Aimbot]`):** while the key (crouch) is held, the weapon in hand fires at the enemy nearest to the cursor (or the nearest one). The shot leads a moving target, keeps the fire rate, magazine and reload of the weapon, is heard by the players nearby, and is fired as new bullets - the weapon itself is not fired nor changed, so every weapon works the same (not only the Barrett).
- **Explosions (`[Admin]`):** `/explode <player|all> [kind]`, `/bigexplode`, `/nuke`. The patterns are built in the library and spawned over several ticks (at most 48 bullets a tick). `ExplodePower` scales the damage.

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
- `[Radar]`: Steam IDs, public access switches, display modes, and radar update frequencies.
- `[Admin]`: Steam admin files, ban duration caps, command aliases, explosion commands and power.
- `[Teleport]`: Tap / hold behaviour, velocity inheritance, flight speed, dead zone and smoothing, wall collision prevention, and trigger keys.
- `[Trajectory]`, `[Aimbot]`: Commands, update rates, dots, target selection, range, spread, ammunition and sound.
- `[Weapons]`: Which `weapons.ini` the trajectory and the aimbot read (`auto` = the server's own).

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

`test.bat` (Windows) builds and runs the tests: the store, the library through its exports, and the engines (radar layout, text diff, teleport controller, ballistics, explosions). `main.pas` needs the library of the same release (`BE_API` 2).

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

---

## License

This project is licensed under the [MIT License](LICENSE).