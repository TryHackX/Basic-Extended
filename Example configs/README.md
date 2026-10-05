# Example configs

Ready `settings.ini` files for Basic-Extended 4.0, one folder per kind of server. Each one is the whole default
file (every key keeps its comment) with a few values changed for that server; every changed value has a
`; SET <folder>: <why>` line right above it, so a search for `; SET` lists what the set does.

The default file is the script's own `settings.ini` with every value at the code's default and nobody's data in it
(no Steam admins, no radar users, no server address): the `default` folder is exactly that.

| Folder | For | The server (`soldat.ini`) | What it switches on |
| :--- | :--- | :--- | :--- |
| `default` | any server | any | the basics: health display, regeneration, damage numbers, the radar for its users, the commands; the "hack" tools for admins |
| `ctf` | Capture the Flag (public) | `GameStyle=3` | a public circle and list radar of what the team sees and the flags; medic, assists, savior; the team-kill guard, spawn protection, pause, anti-spam, private messages |
| `inf` | Infiltration | `GameStyle=5` | as `ctf` |
| `htf` | Hold the Flag | `GameStyle=6` | as `ctf` |
| `tm` | Team Match | `GameStyle=2` | as `ctf` without flags |
| `dm` | Deathmatch | `GameStyle=0` | no radar for the players; multi kills and sprees told; spawn protection, anti-spam |
| `rscs` | Realistic + Survival + CTF | `GameStyle=3`, `Realistic_Mode=1`, `Survival_Mode=1` | the Battlefield mod whole: magazines (an empty gun stays in the hands, the survivor's kit carried into the next round), bleeding and the downed, classes, battle points, supply crates, mines and claymores, flash grenades, the Javelin, spotting, bounties, player reports; no grenade kits, no kill line |
| `rs` | Realistic + Survival, team match | `GameStyle=2`, `Realistic_Mode=1`, `Survival_Mode=1` | as `rscs` without flags |
| `rsa` | Realistic + Survival + Advance | as `rs` with the server's advance mode on | as `rs`, but no classes and no menu lock (the advance mode gives the weapons) |
| `rsdm` | Realistic + Survival deathmatch | `GameStyle=0`, `Realistic_Mode=1`, `Survival_Mode=1` | no radar for the players, damage numbers only for what the shooter can see, the TimeToKill countdown when two are left, hit flash, spawn protection, anti-spam |
| `shop` | an economy server | any team mode | every weapon is bought (`BuyOnly`: the menu is what a player owns) and kept across deaths, money every minute, supply crates; magazines, mines, flashes and Javelins from the shop |
| `tw` | Trench War | `GameStyle=2` or `3`, `Realistic_Mode=1` | limited ammunition, a mine and a claymore every life, cheaper stationary guns from the shop (two a player, two minutes), supply crates, bleeding, suppression; no radar for the players |
| `ttw` | Tactical Trench War | as `tw` | `tw` with classes (their mines instead of a mine every life), battle points, resupply at the base, the downed |
| `battlefield` | the Battlefield mod | `GameStyle=3` (or 2, 5, 6) | classes, battle points, resupply at the base, bleeding and the downed, spotting with marks over the enemies, bounties, mines, flashes, the Javelin, the shop for the extras |
| `insurgents` | insurgents against the coalition | `GameStyle=3` (or 2) | `battlefield` with Alpha in suicide vests and its own classes (`[Insurgents]`) |
| `hardcore` | hardcore | any team mode, `Realistic_Mode=1` | limited ammunition, bleeding, the downed; no radar, damage numbers, hit flash, kill line, trajectory or regeneration |
| `casual` | casual fun | any team mode | a public radar, medic, assists, savior, multi kills, sprees, first blood, fast regeneration; no limited ammunition, no bleeding |
| `clean` | clean / competitive | any | no radar, aimbot, trajectory or teleports; every "hack" tool off |
| `light` | the lightest | any | only the basics: no radar, damage numbers, suppression, aimbot, trajectory, teleports, no map walls read |

In all of them (but `clean`, where they are off):

- the "hack" tools (the aimbot, the trajectory, teleports and flying, speed, explosions, god, the stationary gun,
  infinite ammo, damage changes, `/give`, `/bonus`, `/sayas`, `/sayteam`, the admin radar) are for admins only, with
  `/` - the lines at the end of `[Permissions]`;
- every player may look up the anti-cheat: `/suspects`, `/acstats <player>`, `/acreview <player>` (also with `!`);
- the admins get the full radar (`[Radar] AdminsFull = 1`) in every set but `default`, `clean` and `light`.

The class balance, the bots' skills (`[Classes] BotSkills`), what the Recon's UAV and sensor show
(`[Classes] SkillSpots`), the damage limit of a life (`[Shop]` / `[Points] DamageLimit`), the memory reads
(`[General] MemoryReads`) and no earnings without an opponent (`[General] Opponents = any`: a bot counts) are the
defaults in every set.

## Use

1. Copy the `settings.ini` of the folder you want over `scripts/Basic-Extended/settings.ini` (next to `main.pas`).
2. Set the server's game mode as the table says (`soldat.ini` or the admin commands).
3. Put the Steam ids of the radar's full users in `[Radar] SteamIds` and the Steam admins in `[Admin] Steam-1`,
   `Steam-2` ... (players without Steam are admins through the server's own admin list); your server's address and
   style for `/info` in `[Info] Address` and `GameStyle`. The rules, the messages and the command lists are the
   default ones - every list is a set of numbered keys in its section (`Line-N`, `Message-N`, `Slot-N`, `Steam-N`,
   `Watch-N`).
4. `/reloadsettings` (or restart the server). Unknown keys and values out of range are reported in the server
   console; every set here loads without one.

Mixing: the sets differ only in the `; SET` lines, so a set is easy to take further - for example `ctf` plus
`[Classes] Enabled = 1` and `[Points] Enabled = 1` is a public CTF with the Battlefield classes.

Weapons mods: load them with the server's own `/loadwep <name>`; the library reads the same `configs/<name>.ini`
right after, so the trajectory, the aimbot, the anti-cheat and the ammunition use the new values.
