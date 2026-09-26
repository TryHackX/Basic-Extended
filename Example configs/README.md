# Example configs

Ready `settings.ini` files for Basic-Extended 3.5. Each one is the full default file with a few
values changed for one kind of server, so every key keeps its comment.

| Folder | For | What differs from the default |
| :--- | :--- | :--- |
| `ctf` | Capture the Flag | public circle radar (list too) with the enemies the team can see and the dropped flags; medic, assists, savior |
| `inf` | Infiltration | like `ctf` |
| `htf` | Hold the Flag | like `ctf`; the radar shows the yellow flag when it is dropped |
| `tm` | Team Match | team radar without flags; medic, assists, savior |
| `dm` | Deathmatch | no radar for the players, multi kills shown, no team features |
| `rscs-dm-survival-realistic` | deathmatch on RSCS maps, survival + realistic | no radar for the players, damage numbers only for what the shooter can see, the TimeToKill countdown when two are left, hit flash |
| `clean` | clean / competitive | no radar, aimbot, trajectory or teleport, every "hack" admin tool off |

In all of them:

- every player may look up the anti-cheat: `/suspects`, `/acstats <player>`, `/acreview <player>`
  (also `!suspects` ... in the chat); `/acclear` stays for admins;
- the "hack" tools (radar with everybody, aimbot, trajectory, teleports, flying, speed, explosions,
  god, statgun, infinite ammo, damage changes, `/give`, `/bonus`, `/sayas`, `/sayteam`) are only for
  admins, with `/` - see the end of `[Permissions]`; in `clean` they are off, and the admins keep only
  moderation (kick, ban, freeze, bring, goto, slay, map commands ...);
- the admins get the full radar (`AdminsFull = 1`, every mode, `Show = all`) except in `clean`.

## Use

1. Copy the `settings.ini` of the folder you want over `scripts/Basic-Extended/data/settings.ini`.
2. Put the Steam ids of the radar's full users in `[Radar] SteamIds`; the Steam admins stay in
   `data/Admins_Steam.txt` (players without Steam are admins through the server's own admin list).
3. `/reloadsettings` (or restart the server). Unknown keys and values out of range are reported in the
   server console.

Weapons mods: load them with the server's own `/loadwep <name>`; the library reads the same
`configs/<name>.ini` right after, so the trajectory, the aimbot and the anti-cheat use the new values.
