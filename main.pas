unit BasicExtended;

{ Basic-Extended 3.0 by TryHackX - the server basics of a Soldat 2.8.2 server (ScriptCore 3).

  One script instead of four: Basic 2.0.2 (player and admin commands, timers), Info (/info, tips,
  the cheating hint), DamageDisplay 1.6 (damage numbers) and BFRegeneration 0.0.3 (health on the
  screen, Battlefield 3 style regeneration, no medical kits). Every part has its own section in
  data/settings.ini and can be switched off there.

  How it keeps the server fast:
  - the settings are read into variables once (and by /reloadsettings), never inside a game event;
  - nothing goes to every player on every tick: the health text is sent only when the shown value
    changes, with a long display time; the damage numbers of one tick go out as one message;
  - work that concerns nobody is skipped: the bullets are looked at only while somebody waits for
    regeneration, and only up to the highest bullet slot in use;
  - commands are answered on the next tick and console lines go out a few per tick: writing to a
    player inside OnSpeak/OnCommand, or many lines to one player at once, can stop the server. }

interface

{ Basic-Extended's own library (source_dll): the players' store (data/players.bdb) and the log
  writer, both written to the disk by a thread of the library, never by the game. It is loaded from
  this script folder; if the folder is renamed, replace "scripts/Basic-Extended/" below (the path must
  not contain spaces). }
function BE_Init(DataDir: PChar; ApiVersion: Integer): Integer;
external {$IFDEF WIN32} 'BE_Init@scripts/Basic-Extended/basicext_dll.dll cdecl' {$ELSE} 'BE_Init@scripts/Basic-Extended/basicext_dll.so cdecl' {$ENDIF};

procedure BE_Shutdown();
external {$IFDEF WIN32} 'BE_Shutdown@scripts/Basic-Extended/basicext_dll.dll cdecl' {$ELSE} 'BE_Shutdown@scripts/Basic-Extended/basicext_dll.so cdecl' {$ENDIF};

function BE_Status(): PChar;
external {$IFDEF WIN32} 'BE_Status@scripts/Basic-Extended/basicext_dll.dll cdecl' {$ELSE} 'BE_Status@scripts/Basic-Extended/basicext_dll.so cdecl' {$ENDIF};

function BE_Pref_Count(Key: PChar): Integer;
external {$IFDEF WIN32} 'BE_Pref_Count@scripts/Basic-Extended/basicext_dll.dll cdecl' {$ELSE} 'BE_Pref_Count@scripts/Basic-Extended/basicext_dll.so cdecl' {$ENDIF};

function BE_Pref_Get(Key: PChar; Index: Integer): Integer;
external {$IFDEF WIN32} 'BE_Pref_Get@scripts/Basic-Extended/basicext_dll.dll cdecl' {$ELSE} 'BE_Pref_Get@scripts/Basic-Extended/basicext_dll.so cdecl' {$ENDIF};

procedure BE_Pref_Begin(Key: PChar);
external {$IFDEF WIN32} 'BE_Pref_Begin@scripts/Basic-Extended/basicext_dll.dll cdecl' {$ELSE} 'BE_Pref_Begin@scripts/Basic-Extended/basicext_dll.so cdecl' {$ENDIF};

procedure BE_Pref_Add(Value: Integer);
external {$IFDEF WIN32} 'BE_Pref_Add@scripts/Basic-Extended/basicext_dll.dll cdecl' {$ELSE} 'BE_Pref_Add@scripts/Basic-Extended/basicext_dll.so cdecl' {$ENDIF};

procedure BE_Pref_Commit();
external {$IFDEF WIN32} 'BE_Pref_Commit@scripts/Basic-Extended/basicext_dll.dll cdecl' {$ELSE} 'BE_Pref_Commit@scripts/Basic-Extended/basicext_dll.so cdecl' {$ENDIF};

procedure BE_Log(FileName, Line: PChar);
external {$IFDEF WIN32} 'BE_Log@scripts/Basic-Extended/basicext_dll.dll cdecl' {$ELSE} 'BE_Log@scripts/Basic-Extended/basicext_dll.so cdecl' {$ENDIF};

implementation

const
  VERSION = '3.1';
  { the library this main.pas was written for (source_dll/be_main.pas BE_API_VERSION) }
  BE_API = 1;
  TAG = '[Basic-Extended] ';
  TEAM_SPECTATOR = 5;
  MAX_BULLET_ID = 254;
  MAX_OBJECT_ID = 90;
  MAX_SPAWN_ID = 255;
  { kits: object styles and the spawn point styles they are created at }
  OBJECT_MEDKIT = 16;
  OBJECT_GRENADEKIT = 17;
  OBJECT_FIRST_BONUS = 18;  { flamer 18, predator 19, vest 20, berserker 21, cluster 22 }
  OBJECT_LAST_BONUS = 22;
  SPAWN_GRENADEKIT = 7;
  SPAWN_MEDKIT = 8;
  SPAWN_FIRST_BONUS = 9;    { cluster 9, vest 10, flamer 11, berserker 12, predator 13 }
  SPAWN_LAST_BONUS = 13;
  DEFAULT_HEALTH = 150;
  REALISTIC_HEALTH = 65;
  { the server hits a player with 4000 when it kills him itself; /brutalkill (3423) and the admin
    kill (3430) stay below }
  SERVER_HIT_DAMAGE = 3900;
  { a death this soon after an admin's /explode or /slap is not a suicide for [SelfKill] }
  ADMIN_HIT_TICKS = 180;
  { the admin's /pkill: a hit of this much from the player himself, no bullet }
  PKILL_DAMAGE = 3430;
  { BulletId of damage that is not a bullet: polygons, falls, /kill, the server's own kills }
  NO_BULLET = 255;
  PEND_SIZE = 64;
  PENDING_PER_TICK = 8;
  DN_PEND_SIZE = 256;
  { BigText/WorldText go out like console lines (one packet each): at most this many damage numbers
    and overlay texts to one player in one tick, the rest waits for the next ticks }
  TEXTS_PER_TICK = 8;
  { lines of one damage number column }
  DN_MAX_LINES = 5;
  { a map change announced this many ticks ago and never carried out (a pause during the countdown
    throws it away) does not stop the regeneration any longer }
  MAPCHANGE_TIMEOUT = 600;
  { a ban waits until the lines that tell the player about it are out }
  BAN_DELAY_TICKS = 20;
  STYLE_COUNT = 5;
  MAX_WORDS = 256;
  MAX_LINES = 20;
  MAX_BAR = 40;
  ERRORS_SHOWN = 20;
  NOT_A_NUMBER = -2147483647;
  { longest ban the ban lists can hold (minutes; 3600 ticks each in an Integer) }
  BAN_LIMIT = 596000;
  PERMANENT_BAN = -1000;
  { where a queued text came from }
  SRC_CHAT = 1;
  SRC_COMMAND = 2;
  SRC_CONSOLE = 3;
  { commands (ids of 40 and more are admin commands) }
  C_LIST = 1;
  C_RULES = 2;
  C_MAPLIST = 3;
  C_RATIO = 4;
  C_PING = 5;
  C_TRACK = 6;
  C_TIME = 7;
  C_WHOIS = 8;
  C_CALLADMIN = 9;
  C_JOIN = 10;
  C_SPEC = 11;
  C_ALPHA = 12;
  C_BRAVO = 13;
  C_CHARLIE = 14;
  C_DELTA = 15;
  C_HP = 16;
  C_DMG = 17;
  C_NEXTMAP = 18;
  C_LASTMAP = 19;
  C_CURMAP = 20;
  C_RADAR = 21;
  C_MEDIC = 23;
  C_INFO = 30;
  C_FIRST_ADMIN = 40;
  C_OVERLAY = 40;
  C_ADMINLIST = 41;
  C_IP = 42;
  C_HWID = 43;
  C_BAN = 44;
  C_BANHW = 45;
  C_BANIP = 46;
  C_KILLALL = 47;
  C_KICKALL = 48;
  C_EXPLODEALL = 49;
  C_RANDOMIZE = 50;
  C_RELOAD = 51;
  C_STATUS = 52;
  C_TEST = 53;
  C_BENCH = 54;
  C_STEAMADMIN = 55;
  C_TELE = 56;
  C_TELEMOUSE = 57;
  C_FLYMOUSE = 58;
  C_EXPLODE = 59;
  C_GOD = 60;
  C_HEAL = 61;
  C_SLAP = 62;
  C_FREEZE = 63;
  C_BRING = 64;
  C_GOTO = 65;
  C_DISARM = 66;
  C_GIVE = 67;
  C_BONUS = 68;
  { damage number modes }
  DM_SUM = 0;
  DM_COLUMN = 1;
  DM_HIT = 2;
  { radar modes: a steady list on the screen, labels over the players, a circle around the user }
  OVL_LIST = 0;
  OVL_LABELS = 1;
  OVL_CIRCLE = 2;
  OVL_ARROWS = 3;
  { which players the radar shows: all, those seen by the user or any team mate, those seen by the
    user or a living team mate }
  SHOW_ALL = 0;
  SHOW_SEENALL = 1;
  SHOW_SEEN = 2;
  { marks of special players: a flag carrier, a bow (Rambo bow, flamed arrows: weapons 15 and 16) }
  TAG_NONE = 0;
  TAG_FLAG = 1;
  TAG_BOW = 2;
  WEP_BOW = 15;
  WEP_BOW_FIRE = 16;
  WEP_NONE = 255;
  { arrows: dots of one arrow at most (shaft + head), layers of all arrows }
  ARROW_DOTS_MAX = 8;
  ARROW_LAYERS = 64;
  { the radar list stays on the screen for a minute and is sent again after 5 seconds without a
    change (texts are plain UDP packets in 2.8.2) }
  OVL_LIST_DISPLAY = 3600;
  OVL_LIST_REFRESH = 300;
  { labels and circle marks: sent for this long, taken away with ' ' when not wanted any more, and
    sent again after OVL_LIST_REFRESH ticks without a change }
  OVL_MARK_DISPLAY = 900;
  { A text fades over the last 77 ticks of its display time (the client's alpha is 3 * ticks left
    + 25). Sent this much longer and taken away with ' ' at the wanted time, it keeps its colour. }
  FADE_MARGIN = 80;
  { BigText letters are about BT_EM * Scale screen units high (480 units to the screen height; the
    1.8 client source: 28 pt font * 4.8); the circle radar centres its marks with it }
  BT_EM = 179;
  { the circle radar: ring dots at most; its layers are the ring dots, the user himself, one per
    player slot and the 8 hit marks }
  RING_MAX = 32;
  CIRCLE_LAYERS = 73;
  { what the editor edits }
  ED_HUD = 1;
  ED_RADAR = 2;
  { [Teleport] Key }
  TK_RELOAD = 0;
  TK_GRENADE = 1;
  TK_THROW = 2;
  TK_CHANGE = 3;
  { teleport modes of an admin: jump and stop, jump and keep flying, fly towards the cursor }
  TP_OFF = 0;
  TP_JUMP = 1;
  TP_MOMENTUM = 2;
  TP_FLY = 3;
  { width and height of a WorldText letter in map pixels per unit of Scale (measured on the 1.7.1
    client: "Admiral" at 0.02 is about 16 pixels wide) }
  WT_CHAR_WIDTH = 117;
  WT_LINE_HEIGHT = 233;
  { the fog of war of realistic mode (CheckSpriteLineOfSightVisibility in the game's Control.pas):
    a line from one upper body to the other (map pixels above Player.Y), and how far anybody sees }
  LOS_HEIGHT = 12;
  LOS_RANGE = 1001;
  { [DamageNumbers] LineOfSight }
  SIGHT_OFF = 0;
  SIGHT_AUTO = 1;
  SIGHT_ON = 2;
  { a player's own choice: 0 = the server default }
  PREF_DEFAULT = 0;
  PREF_ON = 1;
  PREF_OFF = 2;

var
  { ---------------- settings ---------------- }
  Cfg: TIniFile;
  CfgOk: Boolean;
  CfgKeys: TStringList;
  DataDir: string;

  LinesPerTick, BroadcastPerTick, MaxQueued: Integer;
  ColorGood, ColorBad: Longint;
  StartMessage: string;

  HudEnabled, HudDefaultOn, HudSave: Boolean;
  HudLayer, HudDefX, HudDefY, HudDefStyle, HudBarLen, HudDisplayTicks: Integer;
  HudEditorTicks, HudEditorStep: Integer;
  HudDefScale: Single;
  HudRegenMark: string;
  { low health: the text changes colour (and blinks) at LowPercent and below }
  HudLowPct, HudLowBlink: Integer;
  HudLowColor, HudLowColor2: Longint;
  HudStyleText: array[1..5] of string;
  HudHasPct, HudHasHp, HudHasMax, HudHasBar, HudHasRegen, HudHasVest: array[1..5] of Boolean;
  BarCache: array[0..40] of string;
  HudColorAt: array[0..100] of Longint;

  RegEnabled, RegBots, RegByDamage: Boolean;
  RegDelayTicks, RegStepTicks: Integer;
  RegStartRate, RegAccel, RegMaxRate, RegMaxPercent: Single;

  SupEnabled, SupTeamBullets: Boolean;
  SupRadius, SupRadiusBig: Single;
  SupDelayTicks, SupScanTicks: Integer;

  { kits removed: by object style (the kit) and by spawn point style (where it is created) }
  KitObj, KitSpawn: array[0..31] of Boolean;
  KitsAny: Boolean;
  KitSweepTicks: Integer;

  DmgEnabled, DmgDefaultOn, DmgTaken, DmgShowSelf, DmgPercent, DmgSharp: Boolean;
  DmgMode, DmgStackTicks, DmgDisplayTicks, DmgLayerFirst, DmgLayerLast, DmgSight: Integer;
  DmgScale, DmgOffsetX, DmgOffsetY: Single;
  DmgColorEnemy, DmgColorFriend, DmgColorSelf, DmgColorKill: Longint;
  DmgKillMark: string;

  OvlEnabled, OvlDefaultOn, OvlPublic, OvlPublicOn, OvlShowFar: Boolean;
  { who may use every radar mode: Steam ids in the S<number> form }
  OvlSteams: TStringList;
  OvlMode, OvlPublicMinTicks: Integer;
  OvlRange, OvlScale, OvlOffsetY, OvlListScale: Single;
  OvlUpdateTicks, OvlLayerFirst, OvlListLayer, OvlListX, OvlListY, OvlListMax, OvlListTicks: Integer;
  OvlListColor: Longint;
  OvlListTitle, OvlListLine: string;
  OvlCircleX, OvlCircleY, OvlCircleTicks, OvlCircleDots, OvlCircleLayer: Integer;
  OvlCircleR, OvlCircleScale: Single;
  OvlRingColor, OvlSelfColor, OvlEnemyColor, OvlFriendColor: Longint;
  OvlRingChar, OvlSelfChar, OvlEnemyChar, OvlFriendChar, OvlFarChar: string;
  OvlSizeRange, OvlArrowInner, OvlArrowOuter, OvlArrowHead, OvlArrowScale: Single;
  OvlShow, OvlPublicShow, OvlVisionRays, OvlVisionRound, OvlHitTicks, OvlArrowTicks, OvlArrowsMax, OvlArrowDots: Integer;
  OvlArrowLayer: Integer;
  OvlTags, OvlHitMarks: Boolean;
  OvlFlagChar, OvlBowChar, OvlHitChar, OvlArrowChar: string;
  OvlHitColor, OvlArrowNear, OvlArrowMid, OvlArrowFar: Longint;

  HfEnabled: Boolean;
  HfChar: string;
  HfScale, HfTicksPerPct: Single;
  HfX, HfY, HfLayer, HfMinTicks, HfMaxTicks: Integer;
  HfColor: Longint;

  TpEnabled, TpNoWalls: Boolean;
  TpKey, TpFlyEvery: Integer;
  TpMomBase, TpMomPerDist, TpMomKeep, TpMomMax, TpFlyBase, TpFlyPerDist, TpFlyMax: Single;

  AfEnabled, AfIgnoreAdmins: Boolean;
  AfSeconds, AfWarn, AfMinPlayers: Integer;
  AfText: string;

  { the extras of the older scripts }
  AsEnabled, McEnabled, FbEnabled, SvEnabled, SkEnabled, PhEnabled, TkEnabled, MdEnabled: Boolean;
  RsEnabled, LgEnabled, MdCall, PhGround, RsAdmins: Boolean;
  LgJoins, LgChat, LgCommands, LgAdmins, LgMaps, LgKills: Boolean;
  AsMinPct, AsPerPoint, AsPoints, AsLayer, AsTicks, AsX, AsY: Integer;
  McWindow, FbPoints, SvWindow, SvPoints: Integer;
  SkPoints, SkLayer, SkTicks, SkX, SkY: Integer;
  PhFactor, PhStyle, TkAlive, TkSeconds, TkLayer, TkX, TkY, MdCooldown, RsSlots: Integer;
  AsScale, SkScale, PhPower, TkScale, MdDist, MdRate, MdPointEvery: Single;
  AsColor, McColor, FbColor, SvColor, SkColor, PhColor, TkColor, MdColor: Longint;
  AsText, AsPointText, FbText, FbPointsText, SvText, SvSavedText, SkText, PhText, PhNoText: string;
  TkText, RsText, LgFolder: string;
  McText: array[2..10] of string;
  McMin, McMax: array[2..10] of Integer;
  RsList, LgWatch: TStringList;
  { admin commands }
  AdSlapDamage: Integer;
  AdKickSkipAdmins, AdKillSkipAdmins: Boolean;

  TgEnabled: Boolean;

  KiEnabled: Boolean;
  KiText: string;
  KiColor: Longint;

  ClColors, ClAuto: Boolean;
  ClColor: Longint;
  ClPad, ClExtraCount: Integer;
  { the command list: the file (Source = file) or built from the commands switched on (auto) }
  ClLines, ClAutoLines: TStringList;
  ClExtra: array[1..20] of string;
  RuColors, RuAfterMap: Boolean;
  RuColor: Longint;
  RuLines: TStringList;
  MiColor: Longint;
  MlColumns, MlPad: Integer;
  MlColor: Longint;
  RaPublic, PiPublic, PtPublic, TmPublic: Boolean;
  PtSeconds: Integer;
  TmFormat: string;
  WaTcp, WaInGame: Boolean;
  WaSeconds: Integer;
  CaCooldownTicks: Integer;
  TeMaxSpec: Integer;
  InAddress, InStyle: string;
  InHide: Boolean;
  InPad, InCount: Integer;
  InText: array[1..20] of string;
  InColor: array[1..20] of Longint;
  TiEnabled: Boolean;
  TiTicks: Integer;
  TiColor: Longint;
  TiAll, TiLeft: TStringList;
  WeEnabled, WeOnJoin: Boolean;
  WeTicks: Integer;
  WeText: string;
  WeColor: Longint;
  ChEnabled: Boolean;
  ChPattern: string;
  ChCount: Integer;
  ChText: array[1..20] of string;
  ChColor: Longint;
  SpEnabled: Boolean;
  SpTicks: Integer;
  SiEnabled, SiIgnoreAdmins: Boolean;
  SiMinPlayers, SiSeconds, SiBanMinutes: Integer;
  { admins by Steam id: the lines of data/Admins_Steam.txt, and its ids in the S<number> form }
  AdSteamRaw, AdSteams, AdListLines: TStringList;
  AdSteamFile: string;
  AdListColors, AdShorten: Boolean;
  AdMaxBan: Integer;
  MapsFile: string;
  MapsShuffle: Boolean;

  { chat (!word, ?word) and slash (/word) commands: the word and its command id }
  ChatWords, SlashWords: TStringList;
  ChatIds, SlashIds: array[0..255] of Integer;

  { ---------------- state ---------------- }
  { the script's player, bullet, object and spawn point objects never change: fetched once, each use
    saves a call (a property read costs about 1.6 microseconds) }
  PL: array[1..32] of TActivePlayer;
  BL: array[1..254] of TActiveMapBullet;
  OB: array[1..90] of TActiveMapObject;
  SP: array[1..255] of TActiveSpawnPoint;
  { each player's team as the team events told it (-1 = not on the server) }
  TeamOf: array[1..32] of Integer;
  { who is on the server (join and leave events) and the highest slot in use: the loops over the
    players stop there instead of going through all 32 slots }
  ActiveSlot: array[1..32] of Boolean;
  TopSlot: Integer;
  { the player's Steam id (S<number>) once Steam has confirmed it: at the join or by OnSteamAuth
    a moment later; '' for bots, players without Steam and until then }
  SteamId: array[1..32] of string;
  Started: Boolean;
  Realistic: Boolean;
  MaxHealth: Single;
  PrevMap: string;
  MapChanging, SpawnsCleared: Boolean;
  MapChangeTick: Integer;
  Errors: Integer;
  LastFlush: TDateTime;
  LastTickSeen: Integer;

  { console lines waiting: "colour<tab>text" per player, and for everybody }
  OutQ: array[1..32] of TStringList;
  OutAll: TStringList;
  OutPending: Integer;
  { /be_test: what the command answers is written to the server console as well }
  TestEcho: Boolean;
  { [Debug] BotsSeeTexts: bots get the health display and damage numbers too (the server does not
    send texts to bots, so this only exercises the code on a server without players) }
  DebugBots: Boolean;

  { chat lines and commands typed, run on the next tick }
  PendSlot, PendKind: array[0..63] of Integer;
  PendText: array[0..63] of string;
  PendHead, PendCount: Integer;
  { commands of admins arrive through OnCommand and OnAdminCommand; the second copy is skipped }
  SeenTick: array[1..32] of Integer;
  SeenText: array[1..32] of string;

  { the library runs (BE_Init answered BE_API): the players' choices are kept, the logger writes }
  BeOk: Boolean;
  { IPs this script put into remote.txt (data/granted_admins.txt), so a restart still knows them }
  GrantList: TStringList;
  PrefKey: array[1..32] of string;
  HudPOn, DmgPOn: array[1..32] of Integer;
  HudPX, HudPY, HudPStyle: array[1..32] of Integer;
  HudPScale: array[1..32] of Single;
  { the radar (on/off, mode + 1, update ticks, position, size) and the hit markers: 0 or -1 = the
    server default }
  RdPOn, RdPMode, RdPTicks, RdPX, RdPY, RdPShow: array[1..32] of Integer;
  RdPSize, RdPZoom: array[1..32] of Single;

  { health display }
  HudShown, HudDirty, HudForce: array[1..32] of Boolean;
  HudLast: array[1..32] of string;
  HudLastColor: array[1..32] of Longint;
  HudSentTick: array[1..32] of Integer;
  { 2.8.2 sends texts as plain UDP packets: a hide is sent a second time, and a shown text again
    every HudRefreshTicks, in case a packet was lost }
  HudHideAgain: array[1..32] of Boolean;
  HudRefreshTicks: Integer;
  { players whose health is at LowPercent or below (their text blinks) }
  HudLowOn: array[1..32] of Boolean;
  LowCount, DueBlink: Integer;
  { the admin rights this script gave (the IP it put into remote.txt), taken back when he leaves }
  GrantedIp: array[1..32] of string;
  HudAnyDirty: Boolean;

  { regeneration }
  Hurt, Regenerating: array[1..32] of Boolean;
  LastHit, LastSupp, RegenStart: array[1..32] of Integer;
  LastHealth: array[1..32] of Single;
  HurtCount: Integer;
  ScanTop: Integer;

  { the editor of the health display or the radar }
  EdOn, EdProne, EdMoved, EdNade: array[1..32] of Boolean;
  EdUntil, EdHold, EdKind, EdShowAt: array[1..32] of Integer;
  EdPinX, EdPinY, EdX, EdY, EdScale: array[1..32] of Single;
  EdCount: Integer;

  { damage numbers, per shooter and victim }
  DnSum, DnTickSum, DnX, DnY: array[1..32] of array[1..32] of Single;
  DnLast, DnLayer, DnLines: array[1..32] of array[1..32] of Integer;
  DnText: array[1..32] of array[1..32] of string;
  DnKill, DnPend, DnKillPend: array[1..32] of array[1..32] of Boolean;
  { The last hit on each player that is not settled yet: who fired it, the health before it and
    where it happened. What a hit really took is known only when the next hit on him comes or at the
    flush of the tick: scripts after this one may lower or cancel the damage (spawn protection), a
    vest takes a part, and a player cannot lose more than he has. }
  VicPend, VicLastShow, VicLastCount: array[1..32] of Boolean;
  VicLastS: array[1..32] of Integer;
  VicLastBefore, VicLastX, VicLastY: array[1..32] of Single;
  VicList: array[0..31] of Integer;
  VicCount: Integer;
  { texts sent to each player in the current tick }
  SentTick, SentCount: array[1..32] of Integer;
  { bans that wait for their lines (tick, minutes - 0 = kick -, reason) }
  BanAt, BanMin: array[1..32] of Integer;
  BanWhy: array[1..32] of string;
  BanPending: Integer;
  DnNext: array[1..32] of Integer;
  DnPendS, DnPendV: array[0..255] of Integer;
  DnPendCount: Integer;
  { damage a player did to each other player during the current fight (kill info): cleared when
    either of them respawns and when the other one starts to regenerate }
  Dealt: array[1..32] of array[1..32] of Single;
  { WorldText layers to take away with ' ' at a tick (sharp texts, 0 = nothing), and each player's
    earliest such tick }
  WtDue: array[1..32] of array[0..255] of Integer;
  WtNext: array[1..32] of Integer;
  { hits on each circle radar user: until when a direction is shown and who fired from there }
  HmUntil, HmShooter: array[1..32] of array[0..7] of Integer;
  HmActive: array[1..32] of Boolean;
  { the health each human victim lost in the current tick (percent), for the hit flash }
  HfPend: array[1..32] of Single;

  { radar: switched on, allowed every mode ([Radar] SteamIds), and a user now (on, allowed or the
    radar public, in the game) }
  OvlOn, OvlAllowed, OvlAdmin: array[1..32] of Boolean;
  { the next pass of each user, and a position, size or mode change to draw at once }
  RdDue: array[1..32] of Integer;
  RdRedraw: array[1..32] of Boolean;
  { the mode drawn last (-1 = nothing): a change takes the old marks away }
  RdDrawn: array[1..32] of Integer;
  { labels shown (user, player) }
  OvlLabelOn: array[1..32] of array[1..32] of Boolean;
  { circle marks shown (user, player): position, mark, colour, when sent }
  CbOn: array[1..32] of array[1..32] of Boolean;
  CbX, CbY, CbSent: array[1..32] of array[1..32] of Integer;
  CbColor: array[1..32] of array[1..32] of Longint;
  CbChar: array[1..32] of array[1..32] of string;
  { the ring of each user's circle: where and how big it was drawn, when }
  CrOn: array[1..32] of Boolean;
  CrX, CrY, CrR, CrDots, CrSent: array[1..32] of Integer;
  CrScale: array[1..32] of Single;
  { the hit marks of the circle shown, the arrow dots shown }
  ChOn: array[1..32] of array[0..7] of Boolean;
  ArOn: array[1..32] of array[0..63] of Boolean;
  { what each arrow dot was sent as (a dot is sent again only when it moved or changed) }
  ArX, ArY, ArSent: array[1..32] of array[0..63] of Integer;
  ArC: array[1..32] of array[0..63] of Longint;
  { flag carrier or bow of each living player (the pass that read them) }
  OvlPTag: array[1..32] of Integer;
  OvlLastTag: array[1..32] of array[1..32] of Integer;
  { team vision: VisMine[s][b] = s could see b when that pair was looked at last; the spotters of
    this round, where the round is; positions read once a tick for the rays }
  VisMine: array[1..32] of array[1..32] of Boolean;
  VisList: array[0..31] of Integer;
  VisCount, VisK, VisB, VisNextRound: Integer;
  VisNeeded: Boolean;
  VpTick, VpAimX, VpAimY: array[1..32] of Integer;
  VpX, VpY: array[1..32] of Single;
  VpAlive: array[1..32] of Boolean;
  { the slot each admin's overlay continues from when one pass was cut at TEXTS_PER_TICK }
  OvlNext: array[1..32] of Integer;
  OvlLastX, OvlLastY: array[1..32] of array[1..32] of Single;
  OvlLastPct, OvlLastTick: array[1..32] of array[1..32] of Integer;
  OvlCount: Integer;
  { the radar list each user sees now, and when it was sent }
  OvlListText: array[1..32] of string;
  OvlListSent: array[1..32] of Integer;
  { the living players as one radar pass read them }
  OvlPAlive: array[1..32] of Boolean;
  OvlPX, OvlPY: array[1..32] of Single;
  OvlPPct: array[1..32] of Integer;

  { timers }
  SpecLeft: array[1..32] of Integer;
  TrackLeft, TrackSum, TrackMax, TrackCount, TrackAsker: array[1..32] of Integer;
  CallLast: array[1..32] of Integer;
  WhoisLeft: Integer;
  TcpAdmins: TStringList;
  { teleport to the cursor: switched on by the admin, the key as last seen }
  TpOn, TpWas: array[1..32] of Boolean;
  TpMode, TpNext: array[1..32] of Integer;
  TpCount: Integer;
  { away from the keyboard: seconds alive without a key or a cursor move, the cursor last seen }
  AfIdle, AfAimX, AfAimY: array[1..32] of Integer;
  { godmode, frozen players (where) }
  GodOn, FrOn: array[1..32] of Boolean;
  FrX, FrY: array[1..32] of Single;
  FrCount: Integer;
  { extras: assists, kill combos, the last hit on a team mate (savior), a kill of the server itself
    (no suicide penalty), the medics of the teams, players waiting for their Steam id (reservation),
    watched players (logger) }
  AsCount, McCount, McLast, SvTarget, SvTick, ServerKill, AdminHit, RsWait: array[1..32] of Integer;
  FbDone: Boolean;
  TkLeft: Integer;
  MdOf, MdCool: array[0..4] of Integer;
  MdGiven: array[0..4] of Single;
  MdWants, LgWatched: array[1..32] of Boolean;
  LgWatchName: array[1..32] of string;
  DueRegen, DueScan, DueSecond, DuePoll, DueSweep, DueTip, DueWelcome, DuePing: Integer;

  { counters for /be_status }
  StatHud, StatDmg, StatOvl, StatHeals, StatKits, StatScans, StatBullets, StatSince, StatHid: Integer;
  StatRays, StatAfk: Integer;

{ ================================ text and number helpers ================================ }

procedure Log(Text: string);
begin
  WriteLn(TAG + Text);
end;

{ an error in one part of the tick is logged, and the other parts still run }
procedure StageError(Where: string);
begin
  Errors := Errors + 1;
  if Errors <= ERRORS_SHOWN then
    Log('error in ' + Where + ': ' + ExceptionToString(ExceptionType, ExceptionParam));
end;

function BoolText(B: Boolean): string;
begin
  if B then
    Result := 'on'
  else
    Result := 'off';
end;

function ParseBool(S: string; Def: Boolean; var Ok: Boolean): Boolean;
var
  L: string;
begin
  L := LowerCase(Trim(S));
  Ok := True;
  Result := Def;
  if (L = '1') or (L = 'true') or (L = 'yes') or (L = 'on') then
    Result := True
  else if (L = '0') or (L = 'false') or (L = 'no') or (L = 'off') then
    Result := False
  else
    Ok := False;
end;

{ a number with a dot or a comma, whatever the decimal separator of the server's system is }
function ParseFloat(S: string; var Ok: Boolean): Single;
var
  i, Len, Digit: Integer;
  Neg, Dot, Digits: Boolean;
  Value, Divisor: Extended;
begin
  Result := 0;
  Ok := False;
  S := Trim(S);
  Len := Length(S);
  if Len = 0 then
    Exit;
  i := 1;
  Neg := False;
  if S[1] = '-' then
  begin
    Neg := True;
    i := 2;
  end
  else if S[1] = '+' then
    i := 2;
  Value := 0;
  Divisor := 1;
  Dot := False;
  Digits := False;
  while i <= Len do
  begin
    Digit := Ord(S[i]) - 48;
    if (Digit >= 0) and (Digit <= 9) then
    begin
      Digits := True;
      Value := Value * 10 + Digit;
      if Dot then
        Divisor := Divisor * 10;
    end
    else if (S[i] = '.') or (S[i] = ',') then
    begin
      if Dot then
        Exit;
      Dot := True;
    end
    else
      Exit;
    i := i + 1;
  end;
  if not Digits then
    Exit;
  Result := Value / Divisor;
  if Neg then
    Result := -Result;
  Ok := True;
end;

{ a number with a dot, whatever the decimal separator of the server's system is }
function FloatStr(V: Extended; Decimals: Integer): string;
var
  i, Scale, All, Frac: Integer;
  Neg: Boolean;
  S: string;
begin
  Neg := V < 0;
  if Neg then
    V := -V;
  Scale := 1;
  for i := 1 to Decimals do
    Scale := Scale * 10;
  All := Round(V * Scale);
  Frac := All mod Scale;
  Result := IntToStr(All div Scale);
  if Decimals > 0 then
  begin
    S := IntToStr(Frac);
    while Length(S) < Decimals do
      S := '0' + S;
    Result := Result + '.' + S;
  end;
  if Neg then
    if All <> 0 then
      Result := '-' + Result;
end;

function ReplaceAll(S, Find, Repl: string): string;
var
  p, L: Integer;
begin
  Result := '';
  L := Length(Find);
  if L = 0 then
  begin
    Result := S;
    Exit;
  end;
  p := Pos(Find, S);
  while p > 0 do
  begin
    Result := Result + Copy(S, 1, p - 1) + Repl;
    Delete(S, 1, p + L - 1);
    p := Pos(Find, S);
  end;
  Result := Result + S;
end;

{ lines shorter than Width are filled with spaces: the client then draws the console line smaller }
function PadTo(S: string; Width: Integer): string;
begin
  Result := S;
  if Width <= 0 then
    Exit;
  while Length(Result) + 10 <= Width do
    Result := Result + '          ';
  while Length(Result) < Width do
    Result := Result + ' ';
end;

function FirstWord(S: string): string;
var
  p: Integer;
begin
  p := Pos(' ', S);
  if p = 0 then
    Result := S
  else
    Result := Copy(S, 1, p - 1);
end;

function AfterFirstWord(S: string): string;
var
  p: Integer;
begin
  p := Pos(' ', S);
  if p = 0 then
    Result := ''
  else
    Result := Trim(Copy(S, p + 1, Length(S)));
end;

function MixColor(A, B: Longint; T: Single): Longint;
var
  ar, ag, ab, br, bg, bb: Integer;
begin
  if T < 0 then
    T := 0;
  if T > 1 then
    T := 1;
  ar := (A shr 16) and 255;
  ag := (A shr 8) and 255;
  ab := A and 255;
  br := (B shr 16) and 255;
  bg := (B shr 8) and 255;
  bb := B and 255;
  Result := (Round(ar + (br - ar) * T) shl 16) or (Round(ag + (bg - ag) * T) shl 8) or
    Round(ab + (bb - ab) * T);
end;

{ names of Soldat's weapon numbers (what a bullet's GetOwnerWeaponId returns) }
function WeaponName(Num: Integer): string;
begin
  case Num of
    0: Result := 'USSOCOM';
    1: Result := 'Desert Eagles';
    2: Result := 'HK MP5';
    3: Result := 'Ak-74';
    4: Result := 'Steyr AUG';
    5: Result := 'Spas-12';
    6: Result := 'Ruger 77';
    7: Result := 'M79';
    8: Result := 'Barrett M82A1';
    9: Result := 'FN Minimi';
    10: Result := 'XM214 Minigun';
    11: Result := 'Combat Knife';
    12: Result := 'Chainsaw';
    13: Result := 'M72 LAW';
    14: Result := 'Flamer';
    15: Result := 'Rambo Bow';
    16: Result := 'Flamed Arrows';
    30: Result := 'Stationary gun';
    50: Result := 'Grenade';
    51: Result := 'Cluster grenade';
    52: Result := 'Cluster';
    53: Result := 'Thrown knife';
    255: Result := 'Hands';
  else
    Result := 'unknown';
  end;
end;

{ a slot number, the whole name, or a part of the name (the first player it fits) }
function FindPlayer(S: string): Integer;
var
  i, N: Integer;
  L: string;
begin
  Result := -1;
  S := Trim(S);
  if S = '' then
    Exit;
  N := StrToIntDef(S, 0);
  if (N >= 1) and (N <= 32) then
  begin
    if PL[N].Active then
      Result := N;
    Exit;
  end;
  L := LowerCase(S);
  for i := 1 to TopSlot do
    if PL[i].Active then
      if LowerCase(PL[i].Name) = L then
      begin
        Result := i;
        Exit;
      end;
  for i := 1 to TopSlot do
    if PL[i].Active then
      if Pos(L, LowerCase(PL[i].Name)) > 0 then
      begin
        Result := i;
        Exit;
      end;
end;

{ Teammatch, CTF, Infiltration and HTF have teams; DM, Pointmatch and Rambo do not }
function TeamGame(): Boolean;
var
  S: Integer;
begin
  S := Game.GameStyle;
  Result := (S = 2) or (S = 3) or (S = 5) or (S = 6);
end;

{ the team with fewer players; 0 in the modes without teams }
function SmallerTeam(): Integer;
var
  i, Best: Integer;
begin
  if not TeamGame() then
  begin
    Result := 0;
    Exit;
  end;
  Result := 1;
  Best := Game.Teams[1].Count;
  if Game.GameStyle = 2 then
  begin
    for i := 2 to 4 do
      if Game.Teams[i].Count < Best then
      begin
        Best := Game.Teams[i].Count;
        Result := i;
      end;
  end
  else if Game.Teams[2].Count < Best then
    Result := 2;
end;

{ The team a player may be in: deathmatch, pointmatch and rambomatch have no teams (0), CTF,
  infiltration and HTF only Alpha and Bravo, teammatch all four. The game's own menu offers only
  these; another team is a cheat or a console trick. }
function TeamForMode(Team: Integer): Integer;
var
  S: Integer;
begin
  Result := Team;
  if Team = TEAM_SPECTATOR then
    Exit;
  S := Game.GameStyle;
  if (S = 0) or (S = 1) or (S = 4) then
    Result := 0
  else if S = 2 then
  begin
    if (Team < 1) or (Team > 4) then
      Result := SmallerTeam();
  end
  else if (Team < 1) or (Team > 2) then
    Result := SmallerTeam();
end;

{ A Steam id as the settings may give it - S123456789, 123456789, 76561198083722517 (SteamID64),
  [U:1:123456789] or STEAM_0:1:61728394 - in the form of Player.SteamIDString (S and the account
  number); '' when it is not a Steam id }
function NormalizeSteam(S: string): string;
var
  T: string;
  V, Base: Int64;
  p, Y: Integer;
begin
  Result := '';
  T := UpperCase(Trim(S));
  if T = '' then
    Exit;
  Base := StrToInt64('76561197960265728');
  if Copy(T, 1, 6) = 'STEAM_' then
  begin
    { STEAM_X:Y:Z is the account Z * 2 + Y }
    Delete(T, 1, 6);
    p := Pos(':', T);
    if p = 0 then
      Exit;
    Delete(T, 1, p);
    p := Pos(':', T);
    if p = 0 then
      Exit;
    Y := StrToIntDef(Copy(T, 1, p - 1), -1);
    if (Y < 0) or (Y > 1) then
      Exit;
    V := StrToInt64Def(Copy(T, p + 1, Length(T)), -1);
    if V < 0 then
      Exit;
    V := V * 2 + Y;
    if V > 0 then
      Result := 'S' + IntToStr(V);
    Exit;
  end;
  if Copy(T, 1, 5) = '[U:1:' then
  begin
    T := Copy(T, 6, Length(T));
    if T <> '' then
      if T[Length(T)] = ']' then
        Delete(T, Length(T), 1);
  end
  else if T[1] = 'S' then
    Delete(T, 1, 1);
  V := StrToInt64Def(T, -1);
  if V >= Base then
    V := V - Base;
  if V > 0 then
    Result := 'S' + IntToStr(V);
end;

{ Soldat gives the Steam id only once Steam has confirmed it (S0 before that): an id read at the
  join or in OnSteamAuth is proven. Bots carry the server's own id and get none. }
function ReadSteam(ID: Integer): string;
begin
  Result := '';
  if PL[ID].Human then
    Result := NormalizeSteam(PL[ID].SteamIDString);
end;

{ a line of Admins_Steam.txt: the Steam id at its start; the rest of the line, empty lines and lines
  that start with #, // or ; are comments }
function SteamOfLine(Line: string): string;
var
  S: string;
begin
  Result := '';
  S := Trim(ReplaceAll(Line, #9, ' '));
  if S = '' then
    Exit;
  if (S[1] = '#') or (S[1] = ';') or (Copy(S, 1, 2) = '//') then
    Exit;
  Result := NormalizeSteam(FirstWord(S));
end;

procedure RecountTop();
var
  i: Integer;
begin
  TopSlot := 0;
  for i := 1 to 32 do
    if ActiveSlot[i] then
      TopSlot := i;
end;

function HealthPct(H: Single): Integer;
begin
  if H <= 0 then
    Result := 0
  else
    Result := Round(H * 100 / MaxHealth);
  if Result > 100 then
    Result := 100;
end;

{ True while the player may still get a damage number or an overlay text in this tick }
function TextRoom(ID, Tick: Integer): Boolean;
begin
  if SentTick[ID] <> Tick then
  begin
    SentTick[ID] := Tick;
    SentCount[ID] := 0;
  end;
  Result := SentCount[ID] < TEXTS_PER_TICK;
end;

procedure TextSent(ID: Integer);
begin
  SentCount[ID] := SentCount[ID] + 1;
end;

{ Tick + N, kept below the point where the server's tick counter starts again from 0 }
function After(Tick, N: Integer): Integer;
begin
  if Tick > 2147483000 - N then
    Result := 2147483000
  else
    Result := Tick + N;
end;

{ Every text size a client meets costs it a new set of letters (FreeType renders a glyph table for
  each size): sizes are rounded to steps of 0.001, so resizing does not make one table per step.
  (PascalScript divides two integers as integers - Round(S * 1000) / 1000 is 0 - so the steps are
  multiplied in.) }
function QScale(S: Single): Single;
begin
  if S < 0.1 then
    Result := Round(S * 1000) * 0.001
  else
    Result := Round(S * 200) * 0.005;
  if Result < 0.005 then
    Result := 0.005;
end;

{ ================================ console output ================================ }

procedure Say(ID: Integer; Text: string; Color: Longint);
begin
  if ID = 0 then
  begin
    WriteLn(Text);
    Exit;
  end;
  if (ID < 1) or (ID > 32) then
    Exit;
  if TestEcho then
    WriteLn(TAG + '[to ' + IntToStr(ID) + '] ' + Text);
  { nobody reads it on an empty slot (the queue of a slot is emptied when its player leaves) }
  if not ActiveSlot[ID] then
    Exit;
  if OutQ[ID].Count >= MaxQueued then
    Exit;
  OutQ[ID].Add(IntToStr(Color) + #9 + Text);
  OutPending := OutPending + 1;
end;

procedure SayAll(Text: string; Color: Longint);
begin
  { with [Debug] BotsSeeTexts the lines to everybody show in the server console too }
  if TestEcho or DebugBots then
    WriteLn(TAG + '[to all] ' + Text);
  if OutAll.Count >= MaxQueued then
    Exit;
  OutAll.Add(IntToStr(Color) + #9 + Text);
  OutPending := OutPending + 1;
end;

procedure SayTo(ID: Integer; ToAll: Boolean; Text: string; Color: Longint);
begin
  if ToAll then
    SayAll(Text, Color)
  else
    Say(ID, Text, Color);
end;

{ how many admins are in the game; each gets the text }
function SayAdmins(Text: string; Color: Longint): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 1 to TopSlot do
    if PL[i].Active then
      if PL[i].Human then
        if PL[i].IsAdmin then
        begin
          Say(i, Text, Color);
          Result := Result + 1;
        end;
end;

{ a ban (Minutes > 0) or a kick (0) a moment later, when the lines that tell the player about it
  are out; RunBans carries it out }
procedure ScheduleBan(ID, Minutes: Integer; Reason: string);
begin
  if BanAt[ID] = 0 then
    BanPending := BanPending + 1;
  BanAt[ID] := After(Game.TickCount, BAN_DELAY_TICKS);
  BanMin[ID] := Minutes;
  BanWhy[ID] := Reason;
end;

procedure RunBans(Tick: Integer);
var
  i: Integer;
begin
  for i := 1 to 32 do
    if BanAt[i] > 0 then
      if Tick >= BanAt[i] then
      begin
        BanAt[i] := 0;
        BanPending := BanPending - 1;
        if PL[i].Active then
        begin
          if BanMin[i] > 0 then
            PL[i].Ban(BanMin[i], BanWhy[i])
          else
            PL[i].Kick(TKickSilent);
        end;
      end;
  if BanPending < 0 then
    BanPending := 0;
end;

procedure FlushOutput();
var
  i, n, p: Integer;
  S: string;
  Q: TStringList;
begin
  n := 0;
  while OutAll.Count > 0 do
  begin
    if n >= BroadcastPerTick then
      Break;
    S := OutAll[0];
    OutAll.Delete(0);
    p := Pos(#9, S);
    Players.WriteConsole(Copy(S, p + 1, Length(S)), StrToIntDef(Copy(S, 1, p - 1), ColorGood));
    n := n + 1;
  end;
  OutPending := OutAll.Count;
  for i := 1 to TopSlot do
  begin
    Q := OutQ[i];
    if Q.Count > 0 then
    begin
      if not PL[i].Active then
        Q.Clear
      else
      begin
        n := 0;
        while Q.Count > 0 do
        begin
          if n >= LinesPerTick then
            Break;
          S := Q[0];
          Q.Delete(0);
          p := Pos(#9, S);
          PL[i].WriteConsole(Copy(S, p + 1, Length(S)), StrToIntDef(Copy(S, 1, p - 1), ColorGood));
          n := n + 1;
        end;
      end;
      OutPending := OutPending + Q.Count;
    end;
  end;
end;

{ ================================ settings ================================ }

function CfgStr(Section, Key, Def: string): string;
begin
  CfgKeys.Add(LowerCase(Section + '/' + Key));
  Result := Def;
  if CfgOk then
    Result := Cfg.ReadString(Section, Key, Def);
end;

procedure CfgWarn(Section, Key, Value, Msg: string);
begin
  Log('settings.ini: [' + Section + '] ' + Key + ' = ' + Value + ': ' + Msg);
end;

function CfgInt(Section, Key: string; Def, Lo, Hi: Integer): Integer;
var
  S: string;
  V: Integer;
begin
  Result := Def;
  S := Trim(CfgStr(Section, Key, ''));
  if S = '' then
    Exit;
  V := StrToIntDef(S, NOT_A_NUMBER);
  if V = NOT_A_NUMBER then
  begin
    CfgWarn(Section, Key, S, 'not a whole number, ' + IntToStr(Def) + ' used');
    Exit;
  end;
  if V < Lo then
  begin
    CfgWarn(Section, Key, S, 'below ' + IntToStr(Lo) + ', ' + IntToStr(Lo) + ' used');
    V := Lo;
  end;
  if V > Hi then
  begin
    CfgWarn(Section, Key, S, 'above ' + IntToStr(Hi) + ', ' + IntToStr(Hi) + ' used');
    V := Hi;
  end;
  Result := V;
end;

function CfgFloat(Section, Key: string; Def, Lo, Hi: Single): Single;
var
  S: string;
  V: Single;
  Ok: Boolean;
begin
  Result := Def;
  S := Trim(CfgStr(Section, Key, ''));
  if S = '' then
    Exit;
  V := ParseFloat(S, Ok);
  if not Ok then
  begin
    CfgWarn(Section, Key, S, 'not a number, ' + FloatStr(Def, 3) + ' used');
    Exit;
  end;
  if V < Lo then
  begin
    CfgWarn(Section, Key, S, 'below ' + FloatStr(Lo, 3) + ', ' + FloatStr(Lo, 3) + ' used');
    V := Lo;
  end;
  if V > Hi then
  begin
    CfgWarn(Section, Key, S, 'above ' + FloatStr(Hi, 3) + ', ' + FloatStr(Hi, 3) + ' used');
    V := Hi;
  end;
  Result := V;
end;

function CfgBool(Section, Key: string; Def: Boolean): Boolean;
var
  S: string;
  Ok: Boolean;
begin
  Result := Def;
  S := Trim(CfgStr(Section, Key, ''));
  if S = '' then
    Exit;
  Result := ParseBool(S, Def, Ok);
  if not Ok then
    CfgWarn(Section, Key, S, 'not a switch (1/0, yes/no, on/off), ' + BoolText(Def) + ' used');
end;

function CfgColor(Section, Key: string; Def: Longint): Longint;
var
  S: string;
  V: Integer;
begin
  Result := Def;
  S := Trim(CfgStr(Section, Key, ''));
  if S = '' then
    Exit;
  if S[1] = '#' then
    S := '$' + Copy(S, 2, Length(S));
  V := StrToIntDef(S, NOT_A_NUMBER);
  if V = NOT_A_NUMBER then
    CfgWarn(Section, Key, S, 'not a colour ($RRGGBB), the default used')
  else
    Result := V;
end;

{ a file of the data folder; an empty list when it is missing }
function LoadData(Name: string): TStringList;
var
  Path: string;
  Found: Boolean;
begin
  Found := False;
  Path := DataDir + Name;
  if Name <> '' then
    Found := File.Exists(Path);
  if Found then
    Result := File.CreateStringListFromFile(Path)
  else
  begin
    Result := File.CreateStringList();
    if Name <> '' then
      Log('file not found: ' + Path);
  end;
end;

{ "word|word|word" of a command; ! and / in front are ignored, ? stays (?nextmap) }
procedure AddWords(List: string; Id: Integer; Slash: Boolean);
var
  S, W: string;
  p: Integer;
begin
  S := LowerCase(List);
  while S <> '' do
  begin
    p := Pos('|', S);
    if p = 0 then
    begin
      W := Trim(S);
      S := '';
    end
    else
    begin
      W := Trim(Copy(S, 1, p - 1));
      Delete(S, 1, p);
    end;
    if W <> '' then
      if (W[1] = '!') or (W[1] = '/') then
        Delete(W, 1, 1);
    if W <> '' then
    begin
      if Slash then
      begin
        if SlashWords.IndexOf(W) >= 0 then
          Log('settings.ini: the command /' + W + ' is given twice, only the first one works')
        else if SlashWords.Count < MAX_WORDS then
        begin
          SlashIds[SlashWords.Count] := Id;
          SlashWords.Add(W);
        end;
      end
      else
      begin
        if ChatWords.IndexOf(W) >= 0 then
          Log('settings.ini: the command !' + W + ' is given twice, only the first one works')
        else if ChatWords.Count < MAX_WORDS then
        begin
          ChatIds[ChatWords.Count] := Id;
          ChatWords.Add(W);
        end;
      end;
    end;
  end;
end;

{ "text|$colour" lines of [Info]: the colour after the last | }
procedure SplitLine(S: string; Def: Longint; var Text: string; var Color: Longint);
var
  i, p: Integer;
begin
  Text := S;
  Color := Def;
  p := 0;
  for i := Length(S) downto 1 do
    if S[i] = '|' then
    begin
      p := i;
      Break;
    end;
  if p = 0 then
    Exit;
  if p < Length(S) then
    if S[p + 1] = '$' then
    begin
      Color := StrToIntDef(Trim(Copy(S, p + 1, Length(S))), Def);
      Text := Copy(S, 1, p - 1);
    end;
end;

{ the Steam ids of a setting ("id|id"; commas and spaces work too) in the S<number> form }
procedure LoadSteamWords(List: string; Dest: TStringList; Section, Key: string);
var
  S, W, N: string;
  p: Integer;
begin
  Dest.Clear;
  S := ReplaceAll(ReplaceAll(ReplaceAll(ReplaceAll(Trim(List), ',', '|'), ';', '|'), ' ', '|'), #9, '|');
  while S <> '' do
  begin
    p := Pos('|', S);
    if p = 0 then
    begin
      W := S;
      S := '';
    end
    else
    begin
      W := Copy(S, 1, p - 1);
      Delete(S, 1, p);
    end;
    W := Trim(W);
    if W <> '' then
    begin
      N := NormalizeSteam(W);
      if N = '' then
        CfgWarn(Section, Key, W, 'not a Steam id, left out')
      else if Dest.IndexOf(N) < 0 then
        Dest.Add(N);
    end;
  end;
end;

{ data/Admins_Steam.txt: one Steam id at the start of a line, in any form (S123456789,
  76561198083722517, STEAM_0:1:61728394, [U:1:123456789]); the rest of the line is a comment }
procedure LoadAdminSteams();
var
  i: Integer;
  N, L: string;
begin
  AdSteamRaw.Free;
  AdSteamRaw := LoadData(AdSteamFile);
  AdSteams.Clear;
  for i := 0 to AdSteamRaw.Count - 1 do
  begin
    L := Trim(AdSteamRaw[i]);
    N := SteamOfLine(L);
    if N <> '' then
    begin
      if AdSteams.IndexOf(N) < 0 then
        AdSteams.Add(N);
    end
    else if L <> '' then
      if (L[1] <> '#') and (L[1] <> ';') and (Copy(L, 1, 2) <> '//') then
        Log(AdSteamFile + ', line ' + IntToStr(i + 1) + ': not a Steam id at the start: ' + L);
  end;
end;

procedure SaveAdminSteams();
begin
  try
    AdSteamRaw.SaveToFile(DataDir + AdSteamFile);
  except
    Log('cannot write ' + DataDir + AdSteamFile);
  end;
end;

{ list, labels, circle or arrows (label and arrow too) -> OVL_*; -1 when it is none of them }
function RadarModeOf(S: string): Integer;
begin
  Result := -1;
  S := LowerCase(Trim(S));
  if S = 'list' then
    Result := OVL_LIST
  else if (S = 'labels') or (S = 'label') then
    Result := OVL_LABELS
  else if S = 'circle' then
    Result := OVL_CIRCLE
  else if (S = 'arrows') or (S = 'arrow') then
    Result := OVL_ARROWS;
end;

function RadarModeName(M: Integer): string;
begin
  Result := 'list';
  if M = OVL_LABELS then
    Result := 'labels'
  else if M = OVL_CIRCLE then
    Result := 'circle'
  else if M = OVL_ARROWS then
    Result := 'arrows';
end;

function ShowName(S: Integer): string;
begin
  Result := 'all';
  if S = SHOW_SEENALL then
    Result := 'seenall'
  else if S = SHOW_SEEN then
    Result := 'seen';
end;

function ShowOf(S: string): Integer;
begin
  Result := -1;
  S := LowerCase(Trim(S));
  if S = 'all' then
    Result := SHOW_ALL
  else if S = 'seenall' then
    Result := SHOW_SEENALL
  else if S = 'seen' then
    Result := SHOW_SEEN;
end;

{ a mark of the circle radar: the setting, or Def when it is empty }
function MarkChar(S, Def: string): string;
begin
  Result := Trim(S);
  if Result = '' then
    Result := Def;
end;

procedure PrepareHud();
var
  i, k: Integer;
  Full, Empty, S: string;
  CFull, CHalf, CLow: Longint;
begin
  for i := 1 to STYLE_COUNT do
  begin
    S := HudStyleText[i];
    HudHasPct[i] := Pos('{pct}', S) > 0;
    HudHasHp[i] := Pos('{hp}', S) > 0;
    HudHasMax[i] := Pos('{max}', S) > 0;
    HudHasBar[i] := Pos('{bar}', S) > 0;
    HudHasRegen[i] := Pos('{regen}', S) > 0;
    HudHasVest[i] := Pos('{vest}', S) > 0;
  end;
  Full := CfgStr('HealthHud', 'BarFull', '|');
  Empty := CfgStr('HealthHud', 'BarEmpty', '.');
  for i := 0 to HudBarLen do
  begin
    S := '';
    for k := 1 to HudBarLen do
      if k <= i then
        S := S + Full
      else
        S := S + Empty;
    BarCache[i] := S;
  end;
  CFull := CfgColor('HealthHud', 'ColorFull', $00FF00);
  CHalf := CfgColor('HealthHud', 'ColorHalf', $FFFF00);
  CLow := CfgColor('HealthHud', 'ColorLow', $FF0000);
  for i := 0 to 100 do
    if i >= 50 then
      HudColorAt[i] := MixColor(CHalf, CFull, (i - 50) * 0.02)
    else
      HudColorAt[i] := MixColor(CLow, CHalf, i * 0.02);
end;

procedure LoadSettings();
var
  i, k, n: Integer;
  S, Sec: string;
  Sections, Keys: TStringList;
  Found: Boolean;
begin
  CfgKeys.Clear;
  ChatWords.Clear;
  SlashWords.Clear;
  CfgOk := File.Exists(DataDir + 'settings.ini');
  if CfgOk then
    Cfg := File.CreateINI(DataDir + 'settings.ini')
  else
    Log('settings.ini not found in ' + DataDir + ', the defaults are used');

  LinesPerTick := CfgInt('General', 'LinesPerTick', 4, 1, 10);
  BroadcastPerTick := CfgInt('General', 'BroadcastLinesPerTick', 2, 1, 5);
  MaxQueued := CfgInt('General', 'MaxQueuedLines', 200, 20, 1000);
  ColorGood := CfgColor('General', 'ColorGood', $00BFFF);
  ColorBad := CfgColor('General', 'ColorBad', $FF0033);
  StartMessage := CfgStr('General', 'StartMessage', 'Basic-Extended v{version} loaded - successfully :)');

  { ---- health display ---- }
  HudEnabled := CfgBool('HealthHud', 'Enabled', True);
  HudLayer := CfgInt('HealthHud', 'Layer', 199, 0, 255);
  HudDefaultOn := CfgBool('HealthHud', 'DefaultOn', True);
  HudDefX := CfgInt('HealthHud', 'X', 20, 0, 854);
  HudDefY := CfgInt('HealthHud', 'Y', 384, 0, 480);
  HudDefScale := CfgFloat('HealthHud', 'Scale', 0.02, 0.005, 0.5);
  HudStyleText[1] := CfgStr('HealthHud', 'Style1', 'Health: {pct}% {regen}');
  HudStyleText[2] := CfgStr('HealthHud', 'Style2', 'HP {hp}/{max} {regen}');
  HudStyleText[3] := CfgStr('HealthHud', 'Style3', '{bar} {pct}% {regen}');
  HudStyleText[4] := CfgStr('HealthHud', 'Style4', '{pct}% {regen}');
  HudStyleText[5] := CfgStr('HealthHud', 'Style5', 'Health: {pct}% Vest: {vest}% {regen}');
  HudDefStyle := CfgInt('HealthHud', 'DefaultStyle', 1, 1, STYLE_COUNT);
  HudBarLen := CfgInt('HealthHud', 'BarLength', 10, 1, MAX_BAR);
  HudRegenMark := CfgStr('HealthHud', 'RegenMark', '+');
  HudDisplayTicks := CfgInt('HealthHud', 'DisplayTicks', 360000, 600, 3600000);
  HudRefreshTicks := CfgInt('HealthHud', 'RefreshSeconds', 5, 0, 3600) * 60;
  AddWords(CfgStr('HealthHud', 'Commands', 'hp|health'), C_HP, False);
  HudSave := CfgBool('HealthHud', 'SavePlayers', True);
  HudEditorTicks := CfgInt('HealthHud', 'EditorSeconds', 60, 5, 600) * 60;
  HudEditorStep := CfgInt('HealthHud', 'EditorStep', 1, 1, 20);
  HudLowPct := CfgInt('HealthHud', 'LowPercent', 25, 0, 99);
  HudLowColor := CfgColor('HealthHud', 'LowColor', $FF0000);
  HudLowColor2 := CfgColor('HealthHud', 'LowBlinkColor', $FFFFFF);
  HudLowBlink := CfgInt('HealthHud', 'LowBlinkTicks', 20, 0, 600);
  PrepareHud();

  { ---- regeneration ---- }
  RegEnabled := CfgBool('Regeneration', 'Enabled', True);
  RegDelayTicks := Round(CfgFloat('Regeneration', 'DelaySeconds', 5, 0, 120) * 60);
  RegStartRate := CfgFloat('Regeneration', 'StartRate', 3, 0.1, 100);
  RegAccel := CfgFloat('Regeneration', 'Acceleration', 12, 0, 1000);
  RegMaxRate := CfgFloat('Regeneration', 'MaxRate', 50, 0.1, 1000);
  RegMaxPercent := CfgFloat('Regeneration', 'MaxPercent', 100, 1, 100);
  RegStepTicks := CfgInt('Regeneration', 'StepTicks', 6, 1, 30);
  RegBots := CfgBool('Regeneration', 'Bots', True);
  S := LowerCase(Trim(CfgStr('Regeneration', 'Method', 'set')));
  RegByDamage := S = 'damage';
  if (S <> 'set') and (S <> 'damage') then
    CfgWarn('Regeneration', 'Method', S, 'set or damage, set used');

  SupEnabled := CfgBool('Suppression', 'Enabled', True);
  SupRadius := CfgFloat('Suppression', 'Radius', 50, 5, 1000);
  SupRadiusBig := CfgFloat('Suppression', 'ExplosiveRadius', 130, 5, 1000);
  SupDelayTicks := Round(CfgFloat('Suppression', 'DelaySeconds', 3, 0, 120) * 60);
  SupScanTicks := CfgInt('Suppression', 'ScanTicks', 4, 1, 30);
  SupTeamBullets := CfgBool('Suppression', 'TeamBullets', True);

  { ---- kits ---- }
  for i := 0 to 31 do
  begin
    KitObj[i] := False;
    KitSpawn[i] := False;
  end;
  if CfgBool('Kits', 'Medkits', True) then
  begin
    KitObj[OBJECT_MEDKIT] := True;
    KitSpawn[SPAWN_MEDKIT] := True;
  end;
  if CfgBool('Kits', 'GrenadeKits', False) then
  begin
    KitObj[OBJECT_GRENADEKIT] := True;
    KitSpawn[SPAWN_GRENADEKIT] := True;
  end;
  if CfgBool('Kits', 'BonusKits', False) then
  begin
    for i := OBJECT_FIRST_BONUS to OBJECT_LAST_BONUS do
      KitObj[i] := True;
    for i := SPAWN_FIRST_BONUS to SPAWN_LAST_BONUS do
      KitSpawn[i] := True;
  end;
  KitsAny := False;
  for i := 0 to 31 do
    if KitObj[i] then
      KitsAny := True;
  KitSweepTicks := CfgInt('Kits', 'SweepSeconds', 3, 1, 30) * 60;

  { ---- damage numbers ---- }
  DmgEnabled := CfgBool('DamageNumbers', 'Enabled', True);
  DmgDefaultOn := CfgBool('DamageNumbers', 'DefaultOn', True);
  AddWords(CfgStr('DamageNumbers', 'Commands', 'dmg|damage'), C_DMG, False);
  S := LowerCase(Trim(CfgStr('DamageNumbers', 'Mode', 'sum')));
  DmgMode := DM_SUM;
  if S = 'column' then
    DmgMode := DM_COLUMN
  else if S = 'hit' then
    DmgMode := DM_HIT
  else if S <> 'sum' then
    CfgWarn('DamageNumbers', 'Mode', S, 'sum, column or hit; sum used');
  S := LowerCase(Trim(CfgStr('DamageNumbers', 'Unit', 'percent')));
  DmgPercent := S <> 'hp';
  if (S <> 'percent') and (S <> 'hp') then
    CfgWarn('DamageNumbers', 'Unit', S, 'percent or hp; percent used');
  S := LowerCase(Trim(CfgStr('DamageNumbers', 'Amount', 'taken')));
  DmgTaken := S <> 'hit';
  if (S <> 'taken') and (S <> 'hit') then
    CfgWarn('DamageNumbers', 'Amount', S, 'taken or hit; taken used');
  S := LowerCase(Trim(CfgStr('DamageNumbers', 'LineOfSight', 'auto')));
  DmgSight := SIGHT_AUTO;
  if (S = 'on') or (S = '1') or (S = 'always') then
    DmgSight := SIGHT_ON
  else if (S = 'off') or (S = '0') or (S = 'never') then
    DmgSight := SIGHT_OFF
  else if S <> 'auto' then
    CfgWarn('DamageNumbers', 'LineOfSight', S, 'auto, on or off; auto used');
  DmgShowSelf := CfgBool('DamageNumbers', 'ShowSelf', True);
  DmgSharp := CfgBool('DamageNumbers', 'Sharp', True);
  DmgStackTicks := CfgInt('DamageNumbers', 'StackTicks', 45, 1, 600);
  DmgDisplayTicks := CfgInt('DamageNumbers', 'DisplayTicks', 90, 10, 600);
  DmgScale := CfgFloat('DamageNumbers', 'Scale', 0.0235, 0.005, 0.5);
  DmgOffsetX := CfgFloat('DamageNumbers', 'OffsetX', 0, -200, 200);
  DmgOffsetY := CfgFloat('DamageNumbers', 'OffsetY', 26, -200, 200);
  DmgLayerFirst := CfgInt('DamageNumbers', 'LayerFirst', 200, 1, 255);
  DmgLayerLast := CfgInt('DamageNumbers', 'LayerLast', 209, 1, 255);
  if DmgLayerLast < DmgLayerFirst then
    DmgLayerLast := DmgLayerFirst;
  DmgColorEnemy := CfgColor('DamageNumbers', 'ColorEnemy', $FF6060);
  DmgColorFriend := CfgColor('DamageNumbers', 'ColorFriend', $60FF60);
  DmgColorSelf := CfgColor('DamageNumbers', 'ColorSelf', $FFFF60);
  DmgColorKill := CfgColor('DamageNumbers', 'ColorKill', $FF2020);
  DmgKillMark := CfgStr('DamageNumbers', 'KillMark', 'X');

  { ---- radar ---- }
  OvlEnabled := CfgBool('Radar', 'Enabled', True);
  LoadSteamWords(CfgStr('Radar', 'SteamIds', ''), OvlSteams, 'Radar', 'SteamIds');
  OvlPublic := CfgBool('Radar', 'Public', False);
  OvlDefaultOn := CfgBool('Radar', 'DefaultOn', True);
  OvlPublicOn := CfgBool('Radar', 'PublicDefaultOn', False);
  AddWords(CfgStr('Radar', 'Commands', 'overlay|radar'), C_OVERLAY, True);
  AddWords(CfgStr('Radar', 'PlayerCommands', 'radar'), C_RADAR, False);
  if OvlEnabled then
    if OvlSteams.Count = 0 then
      if not OvlPublic then
        Log('settings.ini: [Radar] SteamIds is empty and Public = 0: nobody gets the radar');
  S := CfgStr('Radar', 'Mode', 'list');
  OvlMode := RadarModeOf(S);
  if OvlMode < 0 then
  begin
    CfgWarn('Radar', 'Mode', S, 'list, circle, labels or arrows; list used');
    OvlMode := OVL_LIST;
  end;
  OvlRange := CfgFloat('Radar', 'Range', 700, 50, 5000);
  OvlPublicMinTicks := CfgInt('Radar', 'PublicMinTicks', 10, 1, 600);
  OvlListX := CfgInt('Radar', 'ListX', 10, 0, 854);
  OvlListY := CfgInt('Radar', 'ListY', 150, 0, 480);
  OvlListScale := CfgFloat('Radar', 'ListScale', 0.018, 0.005, 0.5);
  OvlListMax := CfgInt('Radar', 'ListLines', 8, 1, 20);
  OvlListTicks := CfgInt('Radar', 'ListUpdateTicks', 15, 1, 600);
  OvlListLayer := CfgInt('Radar', 'ListLayer', 198, 0, 255);
  OvlListColor := CfgColor('Radar', 'ListColor', $E0E0E0);
  OvlListTitle := CfgStr('Radar', 'ListTitle', 'Radar');
  OvlListLine := CfgStr('Radar', 'ListLine', '{dir} {tag}{name} {pct}% {dist}');
  OvlCircleX := CfgInt('Radar', 'CircleX', 10, 0, 854);
  OvlCircleY := CfgInt('Radar', 'CircleY', 110, 0, 480);
  OvlCircleR := CfgFloat('Radar', 'CircleRadius', 50, 10, 240);
  OvlCircleScale := CfgFloat('Radar', 'CircleScale', 0.03, 0.005, 0.5);
  OvlCircleTicks := CfgInt('Radar', 'CircleUpdateTicks', 4, 1, 600);
  OvlCircleDots := CfgInt('Radar', 'CircleDots', 16, 0, RING_MAX);
  OvlCircleLayer := CfgInt('Radar', 'CircleLayerFirst', 110, 0, 255 - CIRCLE_LAYERS);
  OvlShowFar := CfgBool('Radar', 'ShowFar', True);
  OvlRingChar := MarkChar(CfgStr('Radar', 'RingChar', '.'), '.');
  OvlRingColor := CfgColor('Radar', 'RingColor', $808080);
  OvlSelfChar := MarkChar(CfgStr('Radar', 'SelfChar', '+'), '+');
  OvlSelfColor := CfgColor('Radar', 'SelfColor', $FFFFFF);
  OvlEnemyChar := MarkChar(CfgStr('Radar', 'EnemyChar', 'o'), 'o');
  OvlEnemyColor := CfgColor('Radar', 'EnemyColor', $FF4040);
  OvlFriendChar := MarkChar(CfgStr('Radar', 'FriendChar', 'o'), 'o');
  OvlFriendColor := CfgColor('Radar', 'FriendColor', $40FF40);
  OvlFarChar := MarkChar(CfgStr('Radar', 'FarChar', '.'), '.');
  OvlUpdateTicks := CfgInt('Radar', 'UpdateTicks', 6, 1, 600);
  OvlScale := CfgFloat('Radar', 'Scale', 0.02, 0.005, 0.5);
  OvlOffsetY := CfgFloat('Radar', 'OffsetY', 28, -200, 200);
  OvlLayerFirst := CfgInt('Radar', 'LayerFirst', 150, 0, 224);
  S := CfgStr('Radar', 'Show', 'all');
  OvlShow := ShowOf(S);
  if OvlShow < 0 then
  begin
    CfgWarn('Radar', 'Show', S, 'all, seenall or seen; all used');
    OvlShow := SHOW_ALL;
  end;
  S := CfgStr('Radar', 'PublicShow', 'seen');
  OvlPublicShow := ShowOf(S);
  if OvlPublicShow < 0 then
  begin
    CfgWarn('Radar', 'PublicShow', S, 'all, seenall or seen; seen used');
    OvlPublicShow := SHOW_SEEN;
  end;
  OvlVisionRays := CfgInt('Radar', 'VisionRaysPerTick', 24, 1, 200);
  OvlVisionRound := CfgInt('Radar', 'VisionRoundTicks', 15, 1, 600);
  OvlSizeRange := CfgFloat('Radar', 'SizeAffectsRange', 0.25, 0, 1);
  OvlTags := CfgBool('Radar', 'Tags', True);
  OvlFlagChar := MarkChar(CfgStr('Radar', 'FlagChar', 'F'), 'F');
  OvlBowChar := MarkChar(CfgStr('Radar', 'BowChar', 'R'), 'R');
  OvlHitMarks := CfgBool('Radar', 'HitMarks', True);
  OvlHitTicks := CfgInt('Radar', 'HitTicks', 45, 10, 600);
  OvlHitChar := MarkChar(CfgStr('Radar', 'HitChar', 'o'), 'o');
  OvlHitColor := CfgColor('Radar', 'HitColor', $FF0000);
  OvlArrowTicks := CfgInt('Radar', 'ArrowUpdateTicks', 4, 1, 600);
  OvlArrowsMax := CfgInt('Radar', 'ArrowsMax', 4, 1, 8);
  OvlArrowDots := CfgInt('Radar', 'ArrowDots', 3, 2, ARROW_DOTS_MAX - 2);
  OvlArrowInner := CfgFloat('Radar', 'ArrowInner', 26, 5, 300);
  OvlArrowOuter := CfgFloat('Radar', 'ArrowOuter', 60, 10, 400);
  if OvlArrowOuter < OvlArrowInner + 5 then
    OvlArrowOuter := OvlArrowInner + 5;
  OvlArrowHead := CfgFloat('Radar', 'ArrowHead', 8, 2, 60);
  OvlArrowScale := CfgFloat('Radar', 'ArrowScale', 0.03, 0.005, 0.5);
  OvlArrowChar := MarkChar(CfgStr('Radar', 'ArrowChar', 'o'), 'o');
  OvlArrowNear := CfgColor('Radar', 'ArrowColorNear', $FF2020);
  OvlArrowMid := CfgColor('Radar', 'ArrowColorMid', $FFFF20);
  OvlArrowFar := CfgColor('Radar', 'ArrowColorFar', $20FF20);
  OvlArrowLayer := CfgInt('Radar', 'ArrowLayerFirst', 210, 0, 256 - OvlArrowsMax * ARROW_DOTS_MAX);

  { ---- the hit flash ---- }
  HfEnabled := CfgBool('HitFlash', 'Enabled', False);
  HfChar := MarkChar(CfgStr('HitFlash', 'Char', 'O'), 'O');
  HfScale := CfgFloat('HitFlash', 'Scale', 75, 0.01, 500);
  HfX := CfgInt('HitFlash', 'X', -4100, -30000, 30000);
  HfY := CfgInt('HitFlash', 'Y', -4100, -30000, 30000);
  HfColor := CfgColor('HitFlash', 'Color', $FF0000);
  HfLayer := CfgInt('HitFlash', 'Layer', 197, 0, 255);
  HfTicksPerPct := CfgFloat('HitFlash', 'TicksPerPercent', 0.7, 0, 100);
  HfMinTicks := CfgInt('HitFlash', 'MinTicks', 10, 1, 600);
  HfMaxTicks := CfgInt('HitFlash', 'MaxTicks', 70, 1, 600);

  { ---- teleport ---- }
  TpEnabled := CfgBool('Teleport', 'Enabled', True);
  if TpEnabled then
  begin
    AddWords(CfgStr('Teleport', 'Commands', 'tele|tp'), C_TELE, True);
    AddWords(CfgStr('Teleport', 'MomentumCommands', 'teletomouse|ttm'), C_TELEMOUSE, True);
    AddWords(CfgStr('Teleport', 'FlyCommands', 'flytomouse|ftm'), C_FLYMOUSE, True);
  end
  else
  begin
    CfgStr('Teleport', 'Commands', '');
    CfgStr('Teleport', 'MomentumCommands', '');
    CfgStr('Teleport', 'FlyCommands', '');
  end;
  TpMomBase := CfgFloat('Teleport', 'MomentumBase', 2, 0, 11);
  TpMomPerDist := CfgFloat('Teleport', 'MomentumPerPixel', 0.008, 0, 1);
  TpMomKeep := CfgFloat('Teleport', 'MomentumKeep', 1, 0, 2);
  TpMomMax := CfgFloat('Teleport', 'MomentumMax', 11, 0, 11);
  TpFlyBase := CfgFloat('Teleport', 'FlyBase', 3, 0, 11);
  TpFlyPerDist := CfgFloat('Teleport', 'FlyPerPixel', 0.02, 0, 1);
  TpFlyMax := CfgFloat('Teleport', 'FlyMax', 11, 0, 11);
  TpFlyEvery := CfgInt('Teleport', 'FlyEveryTicks', 6, 1, 60);
  S := LowerCase(Trim(CfgStr('Teleport', 'Key', 'reload')));
  TpKey := TK_RELOAD;
  if S = 'grenade' then
    TpKey := TK_GRENADE
  else if S = 'throw' then
    TpKey := TK_THROW
  else if S = 'changeweapon' then
    TpKey := TK_CHANGE
  else if S <> 'reload' then
    CfgWarn('Teleport', 'Key', S, 'reload, grenade, throw or changeweapon; reload used');
  TpNoWalls := CfgBool('Teleport', 'NotIntoWalls', True);

  { ---- layers that would replace each other ---- }
  if OvlEnabled then
  begin
    if DmgEnabled then
      if (OvlLayerFirst + 31 >= DmgLayerFirst) and (OvlLayerFirst <= DmgLayerLast) then
        Log('settings.ini: the WorldText layers of [Radar] labels (' + IntToStr(OvlLayerFirst) + '-' +
          IntToStr(OvlLayerFirst + 31) + ') and [DamageNumbers] (' + IntToStr(DmgLayerFirst) + '-' +
          IntToStr(DmgLayerLast) + ') overlap');
    if (OvlLayerFirst + 31 >= OvlArrowLayer) and (OvlLayerFirst <= OvlArrowLayer + OvlArrowsMax * ARROW_DOTS_MAX - 1) then
      Log('settings.ini: the WorldText layers of [Radar] labels and arrows overlap');
    if DmgEnabled then
      if (OvlArrowLayer + OvlArrowsMax * ARROW_DOTS_MAX - 1 >= DmgLayerFirst) and (OvlArrowLayer <= DmgLayerLast) then
        Log('settings.ini: the WorldText layers of [Radar] arrows and [DamageNumbers] overlap');
    if (OvlListLayer = HudLayer) or ((OvlListLayer >= OvlCircleLayer) and (OvlListLayer < OvlCircleLayer + CIRCLE_LAYERS)) then
      Log('settings.ini: [Radar] ListLayer is used by the health display or the circle radar too');
    if (HudLayer >= OvlCircleLayer) and (HudLayer < OvlCircleLayer + CIRCLE_LAYERS) then
      Log('settings.ini: [HealthHud] Layer is one of the circle radar layers ([Radar] CircleLayerFirst)');
  end;

  TgEnabled := CfgBool('TeamGuard', 'Enabled', True);

  KiEnabled := CfgBool('KillInfo', 'Enabled', True);
  KiText := CfgStr('KillInfo', 'Text', 'Killed by {killer} ({weapon}), {pct}% health left. You hit him for {dealt}.');
  KiColor := CfgColor('KillInfo', 'Color', $FFA500);

  { ---- player commands ---- }
  if CfgBool('CommandList', 'Enabled', True) then
    AddWords(CfgStr('CommandList', 'Commands', 'cmd|command'), C_LIST, False)
  else
    CfgStr('CommandList', 'Commands', '');
  S := LowerCase(Trim(CfgStr('CommandList', 'Source', 'auto')));
  ClAuto := S <> 'file';
  if (S <> 'auto') and (S <> 'file') then
    CfgWarn('CommandList', 'Source', S, 'auto or file; auto used');
  ClExtraCount := 0;
  for i := 1 to MAX_LINES do
  begin
    S := CfgStr('CommandList', 'Extra' + IntToStr(i), '');
    if S <> '' then
    begin
      ClExtraCount := ClExtraCount + 1;
      ClExtra[ClExtraCount] := S;
    end;
  end;
  ClColors := CfgBool('CommandList', 'ColorsInFile', False);
  ClColor := CfgColor('CommandList', 'Color', $00BFFF);
  ClPad := CfgInt('CommandList', 'PadTo', 135, 0, 300);
  ClLines.Free;
  ClLines := LoadData(CfgStr('CommandList', 'File', 'Commands.txt'));

  if CfgBool('Rules', 'Enabled', True) then
    AddWords(CfgStr('Rules', 'Commands', 'rules|rul'), C_RULES, False)
  else
    CfgStr('Rules', 'Commands', '');
  RuColors := CfgBool('Rules', 'ColorsInFile', True);
  RuColor := CfgColor('Rules', 'Color', $00BFFF);
  RuAfterMap := CfgBool('Rules', 'ShowAfterMapChange', True);
  RuLines.Free;
  RuLines := LoadData(CfgStr('Rules', 'File', 'Rules.txt'));

  if CfgBool('MapInfo', 'Enabled', True) then
  begin
    AddWords(CfgStr('MapInfo', 'NextMap', '?nextmap'), C_NEXTMAP, False);
    AddWords(CfgStr('MapInfo', 'LastMap', '?lastmap'), C_LASTMAP, False);
    AddWords(CfgStr('MapInfo', 'CurrentMap', '?map'), C_CURMAP, False);
  end
  else
  begin
    CfgStr('MapInfo', 'NextMap', '');
    CfgStr('MapInfo', 'LastMap', '');
    CfgStr('MapInfo', 'CurrentMap', '');
  end;
  MiColor := CfgColor('MapInfo', 'Color', $00BFFF);

  if CfgBool('MapList', 'Enabled', True) then
    AddWords(CfgStr('MapList', 'Commands', 'maplist|listmaps'), C_MAPLIST, False)
  else
    CfgStr('MapList', 'Commands', '');
  MlColumns := CfgInt('MapList', 'Columns', 5, 1, 10);
  MlColor := CfgColor('MapList', 'Color', $00BFFF);
  MlPad := CfgInt('MapList', 'PadTo', 135, 0, 300);

  if CfgBool('Ratio', 'Enabled', True) then
    AddWords(CfgStr('Ratio', 'Commands', 'rate|ratio|kd|k/d|kdratio'), C_RATIO, False)
  else
    CfgStr('Ratio', 'Commands', '');
  RaPublic := CfgBool('Ratio', 'Public', True);

  if CfgBool('Ping', 'Enabled', True) then
    AddWords(CfgStr('Ping', 'Commands', 'ping'), C_PING, False)
  else
    CfgStr('Ping', 'Commands', '');
  PiPublic := CfgBool('Ping', 'Public', True);

  if CfgBool('PingTrack', 'Enabled', True) then
    AddWords(CfgStr('PingTrack', 'Commands', 'track|t|pingtrack|trackping'), C_TRACK, False)
  else
    CfgStr('PingTrack', 'Commands', '');
  PtSeconds := CfgInt('PingTrack', 'Seconds', 5, 1, 120);
  PtPublic := CfgBool('PingTrack', 'Public', True);

  if CfgBool('Time', 'Enabled', True) then
    AddWords(CfgStr('Time', 'Commands', 'time|date'), C_TIME, False)
  else
    CfgStr('Time', 'Commands', '');
  TmFormat := CfgStr('Time', 'Format', 'dd.mm.yyyy - h:nn:ss');
  TmPublic := CfgBool('Time', 'Public', True);

  if CfgBool('WhoIsAdmin', 'Enabled', True) then
    AddWords(CfgStr('WhoIsAdmin', 'Commands', 'whoisadmin|adminlist|adminsonline|onlineadmins|onlineadmin|adminonline|whois'),
      C_WHOIS, False)
  else
    CfgStr('WhoIsAdmin', 'Commands', '');
  WaTcp := CfgBool('WhoIsAdmin', 'CountTcp', True);
  WaInGame := CfgBool('WhoIsAdmin', 'CountInGame', True);
  WaSeconds := CfgInt('WhoIsAdmin', 'Seconds', 3, 1, 30);

  if CfgBool('CallAdmin', 'Enabled', True) then
    AddWords(CfgStr('CallAdmin', 'Commands', 'admin|calladmin'), C_CALLADMIN, False)
  else
    CfgStr('CallAdmin', 'Commands', '');
  CaCooldownTicks := CfgInt('CallAdmin', 'CooldownSeconds', 60, 0, 3600) * 60;

  if CfgBool('Teams', 'Enabled', True) then
  begin
    AddWords(CfgStr('Teams', 'JoinCommands', 'j|start|play'), C_JOIN, False);
    AddWords(CfgStr('Teams', 'SpectateCommands', 's|spec|5|specators|joins'), C_SPEC, False);
    AddWords(CfgStr('Teams', 'AlphaCommands', ''), C_ALPHA, False);
    AddWords(CfgStr('Teams', 'BravoCommands', ''), C_BRAVO, False);
    AddWords(CfgStr('Teams', 'CharlieCommands', ''), C_CHARLIE, False);
    AddWords(CfgStr('Teams', 'DeltaCommands', ''), C_DELTA, False);
  end
  else
  begin
    CfgStr('Teams', 'JoinCommands', '');
    CfgStr('Teams', 'SpectateCommands', '');
    CfgStr('Teams', 'AlphaCommands', '');
    CfgStr('Teams', 'BravoCommands', '');
    CfgStr('Teams', 'CharlieCommands', '');
    CfgStr('Teams', 'DeltaCommands', '');
  end;
  TeMaxSpec := CfgInt('Teams', 'MaxSpectators', 10, 0, 32);

  { ---- /info, tips, welcome, cheating hint ---- }
  if CfgBool('Info', 'Enabled', True) then
    AddWords(CfgStr('Info', 'Commands', 'info'), C_INFO, True)
  else
    CfgStr('Info', 'Commands', '');
  InAddress := CfgStr('Info', 'Address', '');
  InStyle := CfgStr('Info', 'GameStyle', '');
  InHide := CfgBool('Info', 'HideSoldatInfo', True);
  InPad := CfgInt('Info', 'PadTo', 135, 0, 300);
  InCount := 0;
  for i := 1 to MAX_LINES do
  begin
    S := CfgStr('Info', 'Line' + IntToStr(i), '');
    if S <> '' then
    begin
      InCount := InCount + 1;
      SplitLine(S, ColorGood, InText[InCount], InColor[InCount]);
    end;
  end;

  TiEnabled := CfgBool('Tips', 'Enabled', True);
  TiTicks := CfgInt('Tips', 'Seconds', 153, 10, 86400) * 60;
  TiColor := CfgColor('Tips', 'Color', $FF00FF);
  TiAll.Free;
  TiAll := LoadData(CfgStr('Tips', 'File', 'Messages.txt'));
  for i := TiAll.Count - 1 downto 0 do
    if Trim(TiAll[i]) = '' then
      TiAll.Delete(i);
  TiLeft.Clear;

  WeEnabled := CfgBool('Welcome', 'Enabled', False);
  WeTicks := CfgInt('Welcome', 'Minutes', 7, 0, 1440) * 3600;
  WeOnJoin := CfgBool('Welcome', 'OnJoin', False);
  WeText := CfgStr('Welcome', 'Text', 'Hello {player} on my server! Try /info command to learn something about the server and commands.');
  WeColor := CfgColor('Welcome', 'Color', $0099FF);

  ChEnabled := CfgBool('CheatHint', 'Enabled', True);
  ChPattern := LowerCase(CfgStr('CheatHint', 'Pattern', 'hax|heater|czit|eator|cheater|haxor|cziter|oszust|cheating|cheats|cheat'));
  if ChPattern = '' then
    ChEnabled := False;
  { a pattern that is not a valid regular expression would fail on every chat line }
  if ChEnabled then
    try
      Found := ExecRegExpr(ChPattern, 'test');
    except
      CfgWarn('CheatHint', 'Pattern', ChPattern, 'not a valid regular expression, the cheating hint is off');
      ChEnabled := False;
    end;
  ChColor := CfgColor('CheatHint', 'Color', $FF0000);
  ChCount := 0;
  for i := 1 to MAX_LINES do
  begin
    S := CfgStr('CheatHint', 'Line' + IntToStr(i), '');
    if S <> '' then
    begin
      ChCount := ChCount + 1;
      ChText[ChCount] := S;
    end;
  end;

  { ---- timers ---- }
  SpEnabled := CfgBool('ServerPing', 'Enabled', True);
  SpTicks := CfgInt('ServerPing', 'Minutes', 6, 1, 1440) * 3600;

  SiEnabled := CfgBool('SpecIdle', 'Enabled', True);
  SiMinPlayers := CfgInt('SpecIdle', 'MinPlayers', 15, 1, 32);
  SiSeconds := CfgInt('SpecIdle', 'Minutes', 10, 1, 1440) * 60;
  SiBanMinutes := CfgInt('SpecIdle', 'BanMinutes', 1, 0, 10080);
  SiIgnoreAdmins := CfgBool('SpecIdle', 'IgnoreAdmins', True);

  AfEnabled := CfgBool('Afk', 'Enabled', True);
  AfSeconds := CfgInt('Afk', 'Minutes', 3, 1, 120) * 60;
  AfWarn := CfgInt('Afk', 'WarnSeconds', 30, 0, 600);
  AfMinPlayers := CfgInt('Afk', 'MinPlayers', 4, 1, 32);
  AfIgnoreAdmins := CfgBool('Afk', 'IgnoreAdmins', True);
  AfText := CfgStr('Afk', 'Text', '{player} was moved to the spectators (away from the keyboard).');
  { ---- extras from the older scripts: all off unless switched on ---- }
  AsEnabled := CfgBool('Assists', 'Enabled', False);
  AsMinPct := CfgInt('Assists', 'MinPercent', 65, 1, 100);
  AsPerPoint := CfgInt('Assists', 'PerPoint', 3, 0, 100);
  AsPoints := CfgInt('Assists', 'Points', 1, 0, 100);
  AsText := CfgStr('Assists', 'Text', 'Assist on {victim} ({pct}%) - {count}/{need}');
  AsPointText := CfgStr('Assists', 'PointText', 'Assist on {victim} ({pct}%) - {need}/{need}, +{points} kill point!');
  AsColor := CfgColor('Assists', 'Color', $FF3232);
  AsLayer := CfgInt('Assists', 'Layer', 36, 0, 255);
  AsTicks := CfgInt('Assists', 'DisplayTicks', 240, 10, 3600);
  AsScale := CfgFloat('Assists', 'Scale', 0.07, 0.005, 1);
  AsX := CfgInt('Assists', 'X', 200, 0, 854);
  AsY := CfgInt('Assists', 'Y', 300, 0, 480);

  McEnabled := CfgBool('MultiKill', 'Enabled', False);
  McWindow := CfgInt('MultiKill', 'WindowSeconds', 3, 1, 60) * 60;
  McColor := CfgColor('MultiKill', 'Color', $CCCC00);
  for i := 2 to 10 do
  begin
    S := '';
    if i = 3 then
      S := 'Triple kill! {player} +{points} kills|2-3'
    else if i = 4 then
      S := 'Multi kill! {player} +{points} kills|3-5'
    else if i = 5 then
      S := 'Multi kill x2! {player} +{points} kills|4-6'
    else if i = 6 then
      S := 'Serial kill! {player} +{points} kills|5-7'
    else if i = 7 then
      S := 'Insane kill! {player} +{points} kills|6-8'
    else if i = 8 then
      S := 'Godlike kill! {player} +{points} kills|7-9'
    else if i = 9 then
      S := 'Masta kill! {player} +{points} kills|8-10';
    S := CfgStr('MultiKill', 'Combo' + IntToStr(i), S);
    McText[i] := '';
    McMin[i] := 0;
    McMax[i] := 0;
    k := 0;
    for n := Length(S) downto 1 do
      if k = 0 then
        if S[n] = '|' then
          k := n;
    if k > 0 then
    begin
      McText[i] := Copy(S, 1, k - 1);
      Sec := Trim(Copy(S, k + 1, Length(S)));
      n := Pos('-', Sec);
      if n > 0 then
      begin
        McMin[i] := StrToIntDef(Trim(Copy(Sec, 1, n - 1)), 0);
        McMax[i] := StrToIntDef(Trim(Copy(Sec, n + 1, Length(Sec))), McMin[i]);
      end
      else
      begin
        McMin[i] := StrToIntDef(Sec, 0);
        McMax[i] := McMin[i];
      end;
    end
    else
      McText[i] := S;
  end;

  FbEnabled := CfgBool('FirstBlood', 'Enabled', False);
  FbPoints := CfgInt('FirstBlood', 'Points', 10, -1000, 1000);
  FbText := CfgStr('FirstBlood', 'Text', 'FIRST BLOOD: {killer} killed {victim}');
  FbPointsText := CfgStr('FirstBlood', 'PointsText', '{points} points awarded!');
  FbColor := CfgColor('FirstBlood', 'Color', $00FF00);

  SvEnabled := CfgBool('Savior', 'Enabled', False);
  SvWindow := CfgInt('Savior', 'WindowSeconds', 2, 1, 30) * 60;
  SvPoints := CfgInt('Savior', 'Points', 1, 0, 100);
  SvText := CfgStr('Savior', 'Text', 'Savior ({saved}) +{points} kill!');
  SvSavedText := CfgStr('Savior', 'SavedText', 'You were rescued by {player}.');
  SvColor := CfgColor('Savior', 'Color', $66CC33);

  SkEnabled := CfgBool('SelfKill', 'Enabled', False);
  SkPoints := CfgInt('SelfKill', 'Points', 1, 0, 100);
  SkText := CfgStr('SelfKill', 'Text', 'Player {player} loses {points} point for suicide!');
  SkColor := CfgColor('SelfKill', 'Color', $CC3300);
  SkLayer := CfgInt('SelfKill', 'Layer', 37, 0, 255);
  SkTicks := CfgInt('SelfKill', 'DisplayTicks', 240, 10, 3600);
  SkScale := CfgFloat('SelfKill', 'Scale', 0.095, 0.005, 1);
  SkX := CfgInt('SelfKill', 'X', 64, 0, 854);
  SkY := CfgInt('SelfKill', 'Y', 375, 0, 480);

  PhEnabled := CfgBool('Posthumous', 'Enabled', False);
  PhFactor := CfgInt('Posthumous', 'ChanceFactor', 20, 1, 1000);
  PhGround := CfgBool('Posthumous', 'GroundOnly', False);
  PhPower := CfgFloat('Posthumous', 'Power', 100, 1, 1000);
  PhStyle := CfgInt('Posthumous', 'BulletStyle', 2, 1, 20);
  PhText := CfgStr('Posthumous', 'Text', 'You threw away a grenade just before your death.');
  PhNoText := CfgStr('Posthumous', 'NoText', '');
  PhColor := CfgColor('Posthumous', 'Color', $F8F35A);

  TkEnabled := CfgBool('TimeToKill', 'Enabled', False);
  TkAlive := CfgInt('TimeToKill', 'AlivePlayers', 2, 1, 32);
  TkSeconds := CfgInt('TimeToKill', 'Seconds', 30, 5, 3600);
  TkText := CfgStr('TimeToKill', 'Text', 'End in: {seconds}');
  TkColor := CfgColor('TimeToKill', 'Color', $00FF33);
  TkLayer := CfgInt('TimeToKill', 'Layer', 38, 0, 255);
  TkScale := CfgFloat('TimeToKill', 'Scale', 0.055, 0.005, 1);
  TkX := CfgInt('TimeToKill', 'X', 380, 0, 854);
  TkY := CfgInt('TimeToKill', 'Y', 10, 0, 480);

  MdEnabled := CfgBool('Medic', 'Enabled', False);
  if MdEnabled then
    AddWords(CfgStr('Medic', 'Commands', 'medic|med|medi|nurse'), C_MEDIC, False)
  else
    CfgStr('Medic', 'Commands', '');
  S := LowerCase(Trim(CfgStr('Medic', 'Mode', 'class')));
  MdCall := S = 'call';
  if (S <> 'class') and (S <> 'call') then
    CfgWarn('Medic', 'Mode', S, 'class or call; class used');
  MdDist := CfgFloat('Medic', 'Distance', 65, 10, 1000);
  MdRate := CfgFloat('Medic', 'HealPerSecond', 8, 0.5, 150);
  MdPointEvery := CfgFloat('Medic', 'PointEvery', 100, 0, 10000);
  MdCooldown := CfgInt('Medic', 'CooldownSeconds', 30, 0, 3600);
  MdColor := CfgColor('Medic', 'Color', $9F17F0);

  RsEnabled := CfgBool('Reservation', 'Enabled', False);
  RsSlots := CfgInt('Reservation', 'Slots', 2, 1, 31);
  RsAdmins := CfgBool('Reservation', 'AdminsToo', True);
  RsText := CfgStr('Reservation', 'Text', 'The server is full: the last {slots} slots are reserved.');
  RsList.Clear;
  Keys := LoadData(CfgStr('Reservation', 'File', 'Reserved.txt'));
  for i := 0 to Keys.Count - 1 do
  begin
    S := Trim(Keys[i]);
    if S <> '' then
      if (S[1] <> '#') and (S[1] <> ';') and (Copy(S, 1, 2) <> '//') then
      begin
        S := FirstWord(ReplaceAll(S, #9, ' '));
        Sec := NormalizeSteam(S);
        if Sec <> '' then
          RsList.Add(Sec)
        else
          RsList.Add(S);
      end;
  end;
  Keys.Free;

  LgEnabled := CfgBool('Logger', 'Enabled', False);
  LgFolder := Trim(CfgStr('Logger', 'Folder', 'logs/basic-extended/'));
  if LgFolder <> '' then
    if (Copy(LgFolder, Length(LgFolder), 1) <> '/') and (Copy(LgFolder, Length(LgFolder), 1) <> '\') then
      LgFolder := LgFolder + '/';
  LgJoins := CfgBool('Logger', 'Joins', True);
  LgChat := CfgBool('Logger', 'Chat', True);
  LgCommands := CfgBool('Logger', 'Commands', True);
  LgAdmins := CfgBool('Logger', 'Admins', True);
  LgMaps := CfgBool('Logger', 'Maps', True);
  LgKills := CfgBool('Logger', 'Kills', False);
  LgWatch.Clear;
  Keys := LoadData(CfgStr('Logger', 'WatchFile', 'Watched.txt'));
  for i := 0 to Keys.Count - 1 do
  begin
    S := Trim(Keys[i]);
    if S <> '' then
      if (S[1] <> '#') and (S[1] <> ';') and (Copy(S, 1, 2) <> '//') then
      begin
        Sec := NormalizeSteam(FirstWord(ReplaceAll(S, #9, ' ')));
        if Sec <> '' then
          LgWatch.Add(Sec)
        else
          LgWatch.Add(LowerCase(S));
      end;
  end;
  Keys.Free;
  Keys := nil;


  { ---- admin ---- }
  AdSteamFile := Trim(CfgStr('Admin', 'SteamFile', 'Admins_Steam.txt'));
  LoadAdminSteams();
  AddWords(CfgStr('Admin', 'SteamAdminCommands', 'steamadmin'), C_STEAMADMIN, True);
  AddWords(CfgStr('Admin', 'ListCommands', 'admincommands'), C_ADMINLIST, True);
  AdListLines.Free;
  AdListLines := LoadData(CfgStr('Admin', 'ListFile', 'Admins_Commands.txt'));
  AdListColors := CfgBool('Admin', 'ListColorsInFile', False);
  AddWords(CfgStr('Admin', 'IpCommands', 'ip'), C_IP, True);
  AddWords(CfgStr('Admin', 'HwidCommands', 'hwid'), C_HWID, True);
  AddWords(CfgStr('Admin', 'BanCommands', 'banr|banrange|bantime'), C_BAN, True);
  AddWords(CfgStr('Admin', 'BanHwidCommands', 'banhwr'), C_BANHW, True);
  AddWords(CfgStr('Admin', 'BanIpCommands', 'banipr'), C_BANIP, True);
  AdMaxBan := CfgInt('Admin', 'MaxBanMinutes', 129600, 0, BAN_LIMIT);
  AdShorten := CfgBool('Admin', 'ShortenLongBans', True);
  AddWords(CfgStr('Admin', 'KillAllCommands', 'killall'), C_KILLALL, True);
  AddWords(CfgStr('Admin', 'KickAllCommands', 'kickall'), C_KICKALL, True);
  AddWords(CfgStr('Admin', 'ExplodeAllCommands', 'explodeall'), C_EXPLODEALL, True);
  AdKillSkipAdmins := CfgBool('Admin', 'KillAllSkipsAdmins', False);
  AdKickSkipAdmins := CfgBool('Admin', 'KickAllSkipsAdmins', True);
  AddWords(CfgStr('Admin', 'ExplodeCommands', 'explode'), C_EXPLODE, True);
  AddWords(CfgStr('Admin', 'GodCommands', 'god'), C_GOD, True);
  AddWords(CfgStr('Admin', 'HealCommands', 'heal'), C_HEAL, True);
  AddWords(CfgStr('Admin', 'SlapCommands', 'slap'), C_SLAP, True);
  AdSlapDamage := CfgInt('Admin', 'SlapDamage', 15, 0, 150);
  AddWords(CfgStr('Admin', 'FreezeCommands', 'freeze'), C_FREEZE, True);
  AddWords(CfgStr('Admin', 'BringCommands', 'bring'), C_BRING, True);
  AddWords(CfgStr('Admin', 'GotoCommands', 'goto'), C_GOTO, True);
  AddWords(CfgStr('Admin', 'DisarmCommands', 'disarm'), C_DISARM, True);
  AddWords(CfgStr('Admin', 'GiveCommands', 'give'), C_GIVE, True);
  AddWords(CfgStr('Admin', 'BonusCommands', 'bonus'), C_BONUS, True);
  AddWords(CfgStr('Admin', 'RandomizeCommands', 'randomize'), C_RANDOMIZE, True);
  AddWords(CfgStr('Admin', 'ReloadCommands', 'reloadsettings|be_reload'), C_RELOAD, True);
  AddWords(CfgStr('Admin', 'StatusCommands', 'be_status'), C_STATUS, True);

  MapsFile := CfgStr('MapsList', 'File', 'mapslist.txt');
  MapsShuffle := CfgBool('MapsList', 'ShuffleOnStart', True);
  AddWords(CfgStr('Admin', 'TestCommands', 'be_test'), C_TEST, True);
  AddWords(CfgStr('Admin', 'BenchCommands', 'be_bench'), C_BENCH, True);
  DebugBots := CfgBool('Debug', 'BotsSeeTexts', False);

  { keys this script does not know: most likely a misspelt one }
  if CfgOk then
  begin
    Sections := File.CreateStringList();
    Keys := File.CreateStringList();
    Cfg.ReadSections(Sections);
    for i := 0 to Sections.Count - 1 do
    begin
      Sec := Sections[i];
      Keys.Clear;
      Cfg.ReadSection(Sec, Keys);
      for k := 0 to Keys.Count - 1 do
        if CfgKeys.IndexOf(LowerCase(Sec + '/' + Keys[k])) < 0 then
          Log('settings.ini: unknown key [' + Sec + '] ' + Keys[k]);
    end;
    Sections.Free;
    Keys.Free;
    Cfg.Free;
  end;
  CfgOk := False;
end;

{ ================================ player preferences ================================ }

{ a player is known by his Steam id (S<number>), without Steam by his computer (H + HWID, which can
  be faked, but it only keeps a text position); bots are not remembered }
function PrefKeyOf(ID: Integer): string;
var
  S: string;
begin
  Result := SteamId[ID];
  if Result <> '' then
    Exit;
  if not PL[ID].Human then
    Exit;
  S := Trim(PL[ID].HWID);
  if S <> '' then
    Result := 'H' + S;
end;

procedure PrefsClear(ID: Integer);
begin
  HudPOn[ID] := PREF_DEFAULT;
  DmgPOn[ID] := PREF_DEFAULT;
  HudPX[ID] := -1;
  HudPY[ID] := -1;
  HudPStyle[ID] := 0;
  HudPScale[ID] := 0;
  RdPOn[ID] := PREF_DEFAULT;
  RdPMode[ID] := 0;
  RdPTicks[ID] := 0;
  RdPX[ID] := -1;
  RdPY[ID] := -1;
  RdPSize[ID] := 0;
  RdPZoom[ID] := 0;
  RdPShow[ID] := 0;
end;

procedure PrefsSave(ID: Integer);
var
  AllDefault: Boolean;
begin
  if not HudSave then
    Exit;
  if not BeOk then
    Exit;
  if PrefKey[ID] = '' then
    Exit;
  AllDefault := (HudPOn[ID] = PREF_DEFAULT) and (DmgPOn[ID] = PREF_DEFAULT) and (HudPX[ID] < 0) and
    (HudPY[ID] < 0) and (HudPStyle[ID] = 0) and (HudPScale[ID] <= 0) and (RdPOn[ID] = PREF_DEFAULT) and
    (RdPMode[ID] = 0) and (RdPTicks[ID] = 0) and (RdPX[ID] < 0) and (RdPY[ID] < 0) and (RdPSize[ID] <= 0) and
    (RdPZoom[ID] <= 0) and (RdPShow[ID] = 0);
  { the values in the order of PrefsLoad; nothing at all removes the player from the store }
  BE_Pref_Begin(PChar(PrefKey[ID]));
  if not AllDefault then
  begin
    BE_Pref_Add(HudPOn[ID]);
    BE_Pref_Add(HudPX[ID]);
    BE_Pref_Add(HudPY[ID]);
    BE_Pref_Add(Round(HudPScale[ID] * 10000));
    BE_Pref_Add(HudPStyle[ID]);
    BE_Pref_Add(DmgPOn[ID]);
    BE_Pref_Add(RdPOn[ID]);
    BE_Pref_Add(RdPMode[ID]);
    BE_Pref_Add(RdPTicks[ID]);
    BE_Pref_Add(RdPX[ID]);
    BE_Pref_Add(RdPY[ID]);
    BE_Pref_Add(Round(RdPSize[ID] * 1000));
    BE_Pref_Add(0);
    BE_Pref_Add(Round(RdPZoom[ID] * 1000));
    BE_Pref_Add(RdPShow[ID]);
  end;
  BE_Pref_Commit();
end;

{ The values of a player in the store (data/players.bdb): hud, x, y, scale*10000, style, dmg, radar,
  radar mode+1, radar ticks, radar x, radar y, radar size*1000, 0 (was the hit markers), radar
  zoom*1000, radar show+1; 0 or -1 = the server default, older players have fewer. }
procedure PrefsLoad(ID: Integer);
var
  n, Cnt: Integer;
  S, Key: string;
  V: array[0..14] of Integer;
  Copied: Boolean;
begin
  PrefsClear(ID);
  PrefKey[ID] := PrefKeyOf(ID);
  if PrefKey[ID] = '' then
    Exit;
  if not BeOk then
    Exit;
  Key := PrefKey[ID];
  Cnt := BE_Pref_Count(PChar(Key));
  { known by his computer before this script knew Steam ids: those values are taken over for the
    Steam id }
  Copied := False;
  if Cnt = 0 then
    if SteamId[ID] <> '' then
    begin
      S := Trim(PL[ID].HWID);
      if S <> '' then
      begin
        Key := 'H' + S;
        Cnt := BE_Pref_Count(PChar(Key));
        Copied := Cnt > 0;
      end;
    end;
  if Cnt = 0 then
    Exit;
  for n := 0 to 14 do
    V[n] := 0;
  V[9] := -1;
  V[10] := -1;
  for n := 0 to 14 do
    if n < Cnt then
      V[n] := BE_Pref_Get(PChar(Key), n);
  if (V[0] >= 0) and (V[0] <= 2) then
    HudPOn[ID] := V[0];
  HudPX[ID] := V[1];
  HudPY[ID] := V[2];
  if V[3] > 0 then
    HudPScale[ID] := V[3] * 0.0001;
  if (V[4] >= 1) and (V[4] <= STYLE_COUNT) then
    HudPStyle[ID] := V[4];
  if (V[5] >= 0) and (V[5] <= 2) then
    DmgPOn[ID] := V[5];
  if (V[6] >= 0) and (V[6] <= 2) then
    RdPOn[ID] := V[6];
  if (V[7] >= 1) and (V[7] <= 4) then
    RdPMode[ID] := V[7];
  if (V[8] >= 1) and (V[8] <= 600) then
    RdPTicks[ID] := V[8];
  RdPX[ID] := V[9];
  RdPY[ID] := V[10];
  if V[11] > 0 then
    RdPSize[ID] := V[11] * 0.001;
  if (V[13] >= 100) and (V[13] <= 4000) then
    RdPZoom[ID] := V[13] * 0.001;
  if (V[14] >= 1) and (V[14] <= 3) then
    RdPShow[ID] := V[14];
  if Copied then
    PrefsSave(ID);
end;

{ Steam confirmed the player after his join: from now on his choices go by the Steam id. A line kept
  for that id wins; without one, what he has now (his computer's line) is kept for the id too. }
procedure PrefsAdopt(ID: Integer);
var
  Key: string;
begin
  Key := PrefKeyOf(ID);
  if Key = PrefKey[ID] then
    Exit;
  if not BeOk then
    Exit;
  if BE_Pref_Count(PChar(Key)) > 0 then
    PrefsLoad(ID)
  else
  begin
    PrefKey[ID] := Key;
    PrefsSave(ID);
  end;
end;

{ ================================ health display ================================ }

function HudIsOn(ID: Integer): Boolean;
begin
  if HudPOn[ID] = PREF_DEFAULT then
    Result := HudDefaultOn
  else
    Result := HudPOn[ID] = PREF_ON;
end;

function HudWanted(ID: Integer; P: TActivePlayer): Boolean;
begin
  Result := False;
  if not HudEnabled then
    Exit;
  if not HudIsOn(ID) then
    Exit;
  if not P.Human then
    if not DebugBots then
      Exit;
  if P.Team = TEAM_SPECTATOR then
    Exit;
  if not P.Alive then
    Exit;
  Result := True;
end;

{ players at low health are counted: their texts blink }
procedure HudLowSet(ID: Integer; Low: Boolean);
begin
  if Low = HudLowOn[ID] then
    Exit;
  HudLowOn[ID] := Low;
  if Low then
    LowCount := LowCount + 1
  else
    LowCount := LowCount - 1;
  if LowCount < 0 then
    LowCount := 0;
end;

{ ' ' for one tick: the old text disappears at once }
procedure HudHide(ID: Integer; P: TActivePlayer);
begin
  P.BigText(HudLayer, ' ', 1, ColorGood, 0.01, 0, 0);
  HudShown[ID] := False;
  HudLast[ID] := '';
  HudSentTick[ID] := Game.TickCount;
  HudHideAgain[ID] := True;
  StatHud := StatHud + 1;
end;

procedure HudDraw(ID: Integer; Force: Boolean);
var
  P: TActivePlayer;
  H: Single;
  Pct, S, X, Y: Integer;
  T: string;
  C: Longint;
  Sc: Single;
  Editing, Low: Boolean;
begin
  P := PL[ID];
  if not P.Active then
  begin
    HudShown[ID] := False;
    HudLowSet(ID, False);
    Exit;
  end;
  if not HudWanted(ID, P) then
  begin
    HudLowSet(ID, False);
    if HudShown[ID] then
      HudHide(ID, P);
    Exit;
  end;
  H := P.Health;
  Pct := HealthPct(H);
  S := HudPStyle[ID];
  if (S < 1) or (S > STYLE_COUNT) then
    S := HudDefStyle;
  T := HudStyleText[S];
  if HudHasPct[S] then
    T := ReplaceAll(T, '{pct}', IntToStr(Pct));
  if HudHasHp[S] then
    T := ReplaceAll(T, '{hp}', IntToStr(Round(H)));
  if HudHasMax[S] then
    T := ReplaceAll(T, '{max}', IntToStr(Round(MaxHealth)));
  if HudHasBar[S] then
    T := ReplaceAll(T, '{bar}', BarCache[Round(Pct * HudBarLen * 0.01)]);
  if HudHasVest[S] then
    T := ReplaceAll(T, '{vest}', IntToStr(Round(P.Vest)));
  if HudHasRegen[S] then
  begin
    if Regenerating[ID] then
      T := ReplaceAll(T, '{regen}', HudRegenMark)
    else
      T := ReplaceAll(T, '{regen}', '');
  end;
  C := HudColorAt[Pct];
  { low health: its own colour, blinking with the second one }
  Low := False;
  if HudLowPct > 0 then
    if Pct <= HudLowPct then
      Low := True;
  HudLowSet(ID, Low);
  if Low then
  begin
    C := HudLowColor;
    if HudLowBlink > 0 then
      if (Game.TickCount div HudLowBlink) mod 2 = 1 then
        C := HudLowColor2;
  end;
  Editing := EdOn[ID] and (EdKind[ID] = ED_HUD);
  if Editing then
  begin
    T := T + ' <edit>';
    C := $00FFFF;
    X := Round(EdX[ID]);
    Y := Round(EdY[ID]);
    Sc := EdScale[ID];
  end
  else
  begin
    X := HudPX[ID];
    if X < 0 then
      X := HudDefX;
    Y := HudPY[ID];
    if Y < 0 then
      Y := HudDefY;
    Sc := HudPScale[ID];
    if Sc <= 0 then
      Sc := HudDefScale;
  end;
  if not Force then
    if HudShown[ID] then
      if T = HudLast[ID] then
        if C = HudLastColor[ID] then
          Exit;
  P.BigText(HudLayer, T, HudDisplayTicks, C, QScale(Sc), X, Y);
  HudShown[ID] := True;
  HudHideAgain[ID] := False;
  HudLast[ID] := T;
  HudLastColor[ID] := C;
  HudSentTick[ID] := Game.TickCount;
  StatHud := StatHud + 1;
end;

procedure HudMark(ID: Integer; Force: Boolean);
begin
  HudDirty[ID] := True;
  if Force then
    HudForce[ID] := True;
  HudAnyDirty := True;
end;

procedure HudMarkAll(Force: Boolean);
var
  i: Integer;
begin
  for i := 1 to TopSlot do
    HudMark(i, Force);
end;

procedure HudFlush();
var
  i: Integer;
begin
  HudAnyDirty := False;
  for i := 1 to TopSlot do
    if HudDirty[i] then
    begin
      HudDirty[i] := False;
      HudDraw(i, HudForce[i]);
      HudForce[i] := False;
    end;
end;

{ the texts of players at low health change colour every LowBlinkTicks }
procedure LowBlinkTick(Tick: Integer);
var
  i: Integer;
begin
  if Tick < DueBlink then
    Exit;
  DueBlink := After(Tick, HudLowBlink);
  for i := 1 to TopSlot do
    if HudLowOn[i] then
      HudMark(i, False);
end;

{ every half second: health lost without a hit (hurt and lava polygons, other scripts) and texts
  that come near the end of their display time }
procedure HudPoll(Tick: Integer);
var
  i: Integer;
  P: TActivePlayer;
  H: Single;
begin
  for i := 1 to TopSlot do
  begin
    P := PL[i];
    if P.Active then
    begin
      if P.Alive then
      begin
        H := P.Health;
        if H < LastHealth[i] - 0.01 then
        begin
          LastHit[i] := Tick;
          Regenerating[i] := False;
        end;
        LastHealth[i] := H;
        if RegEnabled then
          if H < MaxHealth * RegMaxPercent / 100 - 0.01 then
            if not Hurt[i] then
              if P.Human or RegBots then
                Hurt[i] := True;
      end;
      if HudShown[i] then
      begin
        HudDirty[i] := True;
        HudAnyDirty := True;
        if HudRefreshTicks > 0 then
          if Tick - HudSentTick[i] >= HudRefreshTicks then
            HudForce[i] := True;
        if Tick - HudSentTick[i] > HudDisplayTicks div 2 then
          HudForce[i] := True;
      end
      else
      begin
        if HudHideAgain[i] then
          if Tick - HudSentTick[i] >= 30 then
          begin
            HudHideAgain[i] := False;
            P.BigText(HudLayer, ' ', 1, ColorGood, 0.01, 0, 0);
            StatHud := StatHud + 1;
          end;
        if HudEnabled then
          if P.Human or DebugBots then
            if P.Alive then
              HudMark(i, False);
      end;
    end;
  end;
end;

{ ================================ regeneration ================================ }

{ a new life, a new map or a new player: nothing waits, nothing regenerates }
procedure ResetLife(ID: Integer);
var
  j: Integer;
begin
  Hurt[ID] := False;
  Regenerating[ID] := False;
  LastHit[ID] := 0;
  LastSupp[ID] := 0;
  LastHealth[ID] := MaxHealth;
  { kill info counts the damage done during this life to the other player's current fight; a kill
    mark that waited for his number is not for his next life }
  for j := 1 to 32 do
  begin
    Dealt[ID][j] := 0;
    Dealt[j][ID] := 0;
    DnKillPend[j][ID] := False;
  end;
end;

{ Method = damage heals through Soldat's damage routine (other scripts see a heal), but a vest would
  keep three quarters of it and round small heals away: with a vest the health is set directly }
procedure ApplyHeal(ID: Integer; P: TActivePlayer; H, Amount: Single);
var
  Direct: Boolean;
begin
  Direct := True;
  if RegByDamage then
    if P.Vest <= 0 then
      Direct := False;
  if Direct then
    P.Health := H + Amount
  else
    P.Damage(ID, -Amount);
  LastHealth[ID] := P.Health;
  StatHeals := StatHeals + 1;
end;

procedure RegenPass(Tick: Integer);
var
  i, j: Integer;
  P: TActivePlayer;
  H, Cap, Rate, Add: Single;
  Wait: Boolean;
begin
  Cap := MaxHealth * RegMaxPercent / 100;
  HurtCount := 0;
  for i := 1 to TopSlot do
    if Hurt[i] then
    begin
      P := PL[i];
      if not P.Active then
      begin
        Hurt[i] := False;
        Regenerating[i] := False;
        Continue;
      end;
      if not P.Alive then
      begin
        Hurt[i] := False;
        Regenerating[i] := False;
        Continue;
      end;
      H := P.Health;
      { health lost since the last look without a hit: lava, hurt polygons, other scripts }
      if H < LastHealth[i] - 0.01 then
        LastHit[i] := Tick;
      LastHealth[i] := H;
      if H >= Cap - 0.01 then
      begin
        Hurt[i] := False;
        if Regenerating[i] then
        begin
          Regenerating[i] := False;
          HudMark(i, False);
        end;
        Continue;
      end;
      HurtCount := HurtCount + 1;
      Wait := Tick - LastHit[i] < RegDelayTicks;
      if SupEnabled then
        if Tick - LastSupp[i] < SupDelayTicks then
          Wait := True;
      if Wait then
      begin
        if Regenerating[i] then
        begin
          Regenerating[i] := False;
          HudMark(i, False);
        end;
        Continue;
      end;
      if not Regenerating[i] then
      begin
        Regenerating[i] := True;
        RegenStart[i] := Tick;
        { the fight is over: kill info counts the damage done to him from here on }
        for j := 1 to TopSlot do
          Dealt[j][i] := 0;
      end;
      Rate := RegStartRate + RegAccel * (Tick - RegenStart[i]) / 60;
      if Rate > RegMaxRate then
        Rate := RegMaxRate;
      Add := MaxHealth * Rate / 100 * RegStepTicks / 60;
      if H + Add > Cap then
        Add := Cap - H;
      if Add > 0 then
        ApplyHeal(i, P, H, Add);
      HudMark(i, False);
    end;
end;

{ Every enemy bullet is taken as the line it flies until the next look; a line that passes near a
  player who waits for regeneration delays it. Bullets take the lowest free slot, so the slots above
  the highest one in use (plus a margin for new ones) are empty and not looked at. }
procedure SuppressionScan(Tick: Integer);
var
  b, k, n, o, Top: Integer;
  Bul: TActiveMapBullet;
  List: array[1..32] of Integer;
  PX, PY: array[1..32] of Single;
  PTeam: array[1..32] of Integer;
  bx, by, dx, dy, x0, x1, y0, y1, R, R2, L2, t, cx, cy: Single;
  Style: Integer;
  Teams, FF, Enemy: Boolean;
  P: TActivePlayer;
begin
  { Hurt is set only for living players and cleared at a death or a leave; the teams come from the
    team events: only the positions are read }
  n := 0;
  for k := 1 to TopSlot do
    if Hurt[k] then
    begin
      P := PL[k];
      n := n + 1;
      List[n] := k;
      PX[n] := P.X;
      PY[n] := P.Y - 10;
      PTeam[n] := TeamOf[k];
    end;
  if n = 0 then
    Exit;
  StatScans := StatScans + 1;
  Teams := TeamGame();
  FF := Game.FriendlyFire;
  Top := 0;
  if ScanTop > MAX_BULLET_ID then
    ScanTop := MAX_BULLET_ID;
  for b := 1 to ScanTop do
  begin
    Bul := BL[b];
    if Bul.Active then
    begin
      Top := b;
      StatBullets := StatBullets + 1;
      o := Bul.Owner;
      if (o >= 1) and (o <= 32) then
      begin
        Style := Bul.Style;
        R := SupRadius;
        if (Style = 2) or (Style = 4) or (Style = 8) or (Style = 9) or (Style = 10) or (Style = 12) then
          R := SupRadiusBig;
        R2 := R * R;
        bx := Bul.X;
        by := Bul.Y;
        dx := Bul.VelX * SupScanTicks;
        dy := Bul.VelY * SupScanTicks;
        if dx >= 0 then
        begin
          x0 := bx - R;
          x1 := bx + dx + R;
        end
        else
        begin
          x0 := bx + dx - R;
          x1 := bx + R;
        end;
        if dy >= 0 then
        begin
          y0 := by - R;
          y1 := by + dy + R;
        end
        else
        begin
          y0 := by + dy - R;
          y1 := by + R;
        end;
        L2 := dx * dx + dy * dy;
        for k := 1 to n do
          if List[k] <> o then
            if PX[k] >= x0 then
              if PX[k] <= x1 then
                if PY[k] >= y0 then
                  if PY[k] <= y1 then
                  begin
                    Enemy := True;
                    if Teams then
                      if PTeam[k] = TeamOf[o] then
                        Enemy := FF and SupTeamBullets;
                    if Enemy then
                    begin
                      t := 0;
                      if L2 > 0.0001 then
                      begin
                        t := ((PX[k] - bx) * dx + (PY[k] - by) * dy) / L2;
                        if t < 0 then
                          t := 0;
                        if t > 1 then
                          t := 1;
                      end;
                      cx := bx + t * dx - PX[k];
                      cy := by + t * dy - PY[k];
                      if cx * cx + cy * cy <= R2 then
                        LastSupp[List[k]] := Tick;
                    end;
                  end;
      end;
    end;
  end;
  ScanTop := Top + 32;
end;

{ ================================ kits ================================ }

{ switch off the spawn points of the kits [Kits] removes: kits are placed only where one is active }
procedure KitSpawnsOff();
var
  i, k: Integer;
begin
  for i := 1 to MAX_SPAWN_ID do
    if SP[i].Active then
    begin
      k := SP[i].Style;
      if (k >= 0) and (k <= 31) then
        if KitSpawn[k] then
          SP[i].Active := False;
    end;
end;

{ a killed kit stays dead for the rest of the map }
procedure KitSweep();
var
  i, k: Integer;
begin
  for i := 1 to MAX_OBJECT_ID do
    if OB[i].Active then
    begin
      k := OB[i].Style;
      if (k >= 0) and (k <= 31) then
        if KitObj[k] then
        begin
          OB[i].Kill;
          StatKits := StatKits + 1;
        end;
    end;
end;

{ ================================ sharp texts ================================ }

{ The client fades a text out over its last 77 ticks. With [DamageNumbers] Sharp a damage number is
  sent for FADE_MARGIN ticks longer than it should stay and taken away with ' ' at the wanted tick
  (WtHideDue): it keeps its full colour until then. If that ' ' is lost on the way, the number fades
  out as before. }
function WtTicks(Ticks: Integer): Integer;
begin
  Result := Ticks;
  if DmgSharp then
    Result := Ticks + FADE_MARGIN;
end;

procedure WtSharp(ID, Layer, Tick, Ticks: Integer);
var
  Due: Integer;
begin
  if not DmgSharp then
    Exit;
  if (Layer < 0) or (Layer > 255) then
    Exit;
  Due := After(Tick, Ticks);
  WtDue[ID][Layer] := Due;
  if (WtNext[ID] = 0) or (Due < WtNext[ID]) then
    WtNext[ID] := Due;
end;

procedure WtHideDue(Tick: Integer);
var
  i, L, Next: Integer;
begin
  for i := 1 to TopSlot do
    if WtNext[i] > 0 then
      if Tick >= WtNext[i] then
      begin
        Next := 0;
        for L := DmgLayerFirst to DmgLayerLast do
          if WtDue[i][L] > 0 then
          begin
            if Tick >= WtDue[i][L] then
            begin
              WtDue[i][L] := 0;
              if PL[i].Active then
                PL[i].WorldText(L, ' ', 1, ColorGood, 0.01, 0, 0);
            end
            else if (Next = 0) or (WtDue[i][L] < Next) then
              Next := WtDue[i][L];
          end;
        WtNext[i] := Next;
      end;
end;

{ ================================ radar hit marks ================================ }

{ one of 8 directions: 0 right, then clockwise (Y grows downwards): 1 down-right, 2 down,
  3 down-left, 4 left, 5 up-left, 6 up, 7 up-right; 0.4142 = tan(22.5 degrees) }
function DirOf(DX, DY: Single): Integer;
var
  AX, AY: Single;
begin
  AX := Abs(DX);
  AY := Abs(DY);
  if AY <= 0.4142 * AX then
  begin
    if DX >= 0 then
      Result := 0
    else
      Result := 4;
  end
  else if AX <= 0.4142 * AY then
  begin
    if DY >= 0 then
      Result := 2
    else
      Result := 6;
  end
  else if DX >= 0 then
  begin
    if DY >= 0 then
      Result := 1
    else
      Result := 7;
  end
  else if DY >= 0 then
    Result := 3
  else
    Result := 5;
end;

{ V was hit from S. A user of the circle radar sees it as a red mark on the ring towards the
  shooter ([Radar] HitMarks), one per direction (the latest shooter from there), for HitTicks. }
procedure HitMarkAdd(V, S, Tick: Integer);
var
  D: Integer;
  DX, DY: Single;
begin
  if not OvlHitMarks then
    Exit;
  if not OvlAdmin[V] then
    Exit;
  if RdDrawn[V] <> OVL_CIRCLE then
    Exit;
  { the killing hit is settled after the death: nothing for a dead player }
  if not PL[V].Alive then
    Exit;
  DX := PL[S].X - PL[V].X;
  DY := PL[S].Y - PL[V].Y;
  if Abs(DX) + Abs(DY) < 1 then
    Exit;
  D := DirOf(DX, DY);
  HmUntil[V][D] := After(Tick, OvlHitTicks);
  HmShooter[V][D] := S;
  HmActive[V] := True;
  { the circle shows it on its next pass, at once }
  RdDue[V] := Tick;
end;

{ the marks end (death, respawn, a new map); the circle takes them away on its next pass }
procedure HitMarkClear(V: Integer);
var
  D: Integer;
begin
  if not HmActive[V] then
    Exit;
  for D := 0 to 7 do
    if HmUntil[V][D] > 0 then
      HmUntil[V][D] := 1;
end;

{ ================================ damage numbers ================================ }

function DmgIsOn(ID: Integer): Boolean;
begin
  if DmgPOn[ID] = PREF_DEFAULT then
    Result := DmgDefaultOn
  else
    Result := DmgPOn[ID] = PREF_ON;
end;

function DmgNumber(V: Single): string;
var
  N: Integer;
begin
  N := Round(V);
  if N < 1 then
    N := 1;
  Result := '-' + IntToStr(N);
  if DmgPercent then
    Result := Result + '%';
end;

procedure DmgAdd(S, V: Integer; Amount: Single; X, Y: Single);
begin
  if DnPend[S][V] then
  begin
    DnTickSum[S][V] := DnTickSum[S][V] + Amount;
    DnX[S][V] := X;
    DnY[S][V] := Y;
    Exit;
  end;
  if DnPendCount >= DN_PEND_SIZE then
    Exit;
  DnPend[S][V] := True;
  DnTickSum[S][V] := Amount;
  DnX[S][V] := X;
  DnY[S][V] := Y;
  DnPendS[DnPendCount] := S;
  DnPendV[DnPendCount] := V;
  DnPendCount := DnPendCount + 1;
end;

{ What the last hit on V really took (Taken): kill info counts it, and with Amount = taken it is the
  damage number. }
procedure DmgSettle(V: Integer; Taken: Single);
var
  S: Integer;
  Amount: Single;
begin
  if Taken <= 0.01 then
    Exit;
  S := VicLastS[V];
  if VicLastCount[V] then
    if S <> V then
    begin
      Dealt[S][V] := Dealt[S][V] + Taken;
      { the victim's circle radar shows where it came from, and his screen flashes red }
      if PL[V].Human or DebugBots then
      begin
        HitMarkAdd(V, S, Game.TickCount);
        if HfEnabled then
          HfPend[V] := HfPend[V] + Taken * 100 / MaxHealth;
      end;
    end;
  if VicLastShow[V] then
  begin
    Amount := Taken;
    if DmgPercent then
      Amount := Amount * 100 / MaxHealth;
    DmgAdd(S, V, Amount, VicLastX[V], VicLastY[V]);
  end;
end;

{ [DamageNumbers] LineOfSight: auto = in realistic mode only (the other modes show every player) }
function SightActive(): Boolean;
begin
  Result := False;
  if DmgSight = SIGHT_ON then
    Result := True
  else if DmgSight = SIGHT_AUTO then
    Result := Realistic;
end;

{ Could Viewer see Target now? The fog of war of realistic mode: team mates always, everybody for a
  dead player, the others only in front of the aim, up to LOS_RANGE away and with no wall between
  the upper bodies. A damage number over a player the shooter cannot see would show where he is. }
function CanSee(Viewer, Target: Integer): Boolean;
var
  P: TActivePlayer;
  VX, VY, TX, TY, AX, AY, DX, DY: Single;
begin
  Result := True;
  if Viewer = Target then
    Exit;
  P := PL[Viewer];
  if not P.Alive then
    Exit;
  if TeamGame() then
    if TeamOf[Viewer] = TeamOf[Target] then
      Exit;
  VX := P.X;
  VY := P.Y - LOS_HEIGHT - 2;
  TX := PL[Target].X;
  TY := PL[Target].Y - LOS_HEIGHT;
  DX := TX - VX;
  DY := TY - VY;
  AX := P.MouseAimX - VX;
  AY := P.MouseAimY - VY;
  Result := False;
  if DX * AX + DY * AY <= 0 then
    Exit;
  if DX * DX + DY * DY > LOS_RANGE * LOS_RANGE then
    Exit;
  Result := not Map.RayCast(VX, VY, TX, TY, False, False, False, False, 0);
end;

{ where a damage number is drawn: centred over the hit player (a letter is about WT_CHAR_WIDTH * Scale
  map pixels wide), OffsetY above his feet; a column grows upwards }
procedure DmgPlace(S, V: Integer; Width: Integer; var X, Y: Single);
begin
  X := DnX[S][V] - Width * DmgScale * WT_CHAR_WIDTH / 2 + DmgOffsetX;
  Y := DnY[S][V] - DmgOffsetY;
  if DmgMode = DM_COLUMN then
    Y := Y - (DnLines[S][V] - 1) * DmgScale * WT_LINE_HEIGHT;
end;

procedure DmgFlush(Tick: Integer);
var
  k, n, Cut, S, V, Layer, Width, FlashTicks: Integer;
  P: TActivePlayer;
  T, Line, Col: string;
  C: Longint;
  X, Y, H: Single;
  Fresh, Sight: Boolean;
  LS, LV: array[0..255] of Integer;
begin
  { first the last hit on every player hit since the last flush: it took what is gone now }
  n := VicCount;
  VicCount := 0;
  for k := 0 to n - 1 do
  begin
    V := VicList[k];
    VicPend[V] := False;
    { a player who left in the meantime lost nothing to the hit }
    if PL[V].Active then
    begin
      H := 0;
      if PL[V].Alive then
        H := PL[V].Health;
      if H < 0 then
        H := 0;
      DmgSettle(V, VicLastBefore[V] - H);
      { [HitFlash]: the longer, the more health it took (it fades out by itself) }
      if HfPend[V] > 0 then
      begin
        FlashTicks := Round(HfPend[V] * HfTicksPerPct);
        if FlashTicks < HfMinTicks then
          FlashTicks := HfMinTicks;
        if FlashTicks > HfMaxTicks then
          FlashTicks := HfMaxTicks;
        PL[V].BigText(HfLayer, HfChar, FlashTicks, HfColor, HfScale, HfX, HfY);
        HfPend[V] := 0;
      end;
    end;
  end;
  if DnPendCount = 0 then
    Exit;
  Sight := SightActive();
  { the list is taken over before anything is sent: an error while sending cannot leave it stuck }
  n := DnPendCount;
  for k := 0 to n - 1 do
  begin
    LS[k] := DnPendS[k];
    LV[k] := DnPendV[k];
    DnPend[LS[k]][LV[k]] := False;
  end;
  DnPendCount := 0;
  for k := 0 to n - 1 do
  begin
    S := LS[k];
    V := LV[k];
    P := PL[S];
    if not P.Active then
      Continue;
    { too many texts for this player in this tick: the number waits for the next tick }
    if not TextRoom(S, Tick) then
    begin
      DnPend[S][V] := True;
      DnPendS[DnPendCount] := S;
      DnPendV[DnPendCount] := V;
      DnPendCount := DnPendCount + 1;
      Continue;
    end;
    { a player the shooter cannot see gets no number (nor a kill mark) }
    if Sight then
      if S <> V then
        if not CanSee(S, V) then
        begin
          DnKillPend[S][V] := False;
          StatHid := StatHid + 1;
          Continue;
        end;
    Fresh := Tick - DnLast[S][V] > DmgStackTicks;
    if DnLayer[S][V] = 0 then
      Fresh := True;
    if DmgMode = DM_HIT then
      Fresh := True;
    if Fresh then
    begin
      Layer := DnNext[S];
      if (Layer < DmgLayerFirst) or (Layer > DmgLayerLast) then
        Layer := DmgLayerFirst;
      DnNext[S] := Layer + 1;
      DnLayer[S][V] := Layer;
      DnSum[S][V] := 0;
      DnLines[S][V] := 0;
      DnText[S][V] := '';
      DnKill[S][V] := False;
    end;
    { the killing hit is still waiting here when OnKill comes }
    if DnKillPend[S][V] then
    begin
      DnKill[S][V] := True;
      DnKillPend[S][V] := False;
    end;
    DnLast[S][V] := Tick;
    DnSum[S][V] := DnSum[S][V] + DnTickSum[S][V];
    Line := DmgNumber(DnTickSum[S][V]);
    if DmgMode = DM_COLUMN then
    begin
      Col := DnText[S][V];
      if DnLines[S][V] = 0 then
        Col := Line
      else
        Col := Col + #13#10 + Line;
      DnLines[S][V] := DnLines[S][V] + 1;
      if DnLines[S][V] > DN_MAX_LINES then
      begin
        Cut := Pos(#10, Col);
        if Cut > 0 then
          Delete(Col, 1, Cut);
        DnLines[S][V] := DnLines[S][V] - 1;
      end;
      DnText[S][V] := Col;
      T := Col;
      Width := Length(Line);
    end
    else
    begin
      if DmgMode = DM_SUM then
        T := DmgNumber(DnSum[S][V])
      else
        T := Line;
      Width := Length(T);
    end;
    if S = V then
      C := DmgColorSelf
    else if TeamOf[V] = TeamOf[S] then
    begin
      if TeamGame() then
        C := DmgColorFriend
      else
        C := DmgColorEnemy;
    end
    else
      C := DmgColorEnemy;
    if DnKill[S][V] then
    begin
      T := T + ' ' + DmgKillMark;
      Width := Width + 1 + Length(DmgKillMark);
      C := DmgColorKill;
    end;
    DmgPlace(S, V, Width, X, Y);
    P.WorldText(DnLayer[S][V], T, WtTicks(DmgDisplayTicks), C, DmgScale, X, Y);
    WtSharp(S, DnLayer[S][V], Tick, DmgDisplayTicks);
    TextSent(S);
    StatDmg := StatDmg + 1;
  end;
end;

{ the kill turns the victim's number of this shooter red, with the kill mark }
procedure DmgKill(S, V, Tick: Integer);
var
  T: string;
  X, Y: Single;
  Width: Integer;
  Waiting: Boolean;
begin
  { usually the killing hit is not settled yet: the flush of this tick adds the mark }
  Waiting := DnPend[S][V];
  if VicPend[V] then
    if VicLastS[V] = S then
      Waiting := True;
  if Waiting then
  begin
    DnKillPend[S][V] := True;
    Exit;
  end;
  if DnLayer[S][V] = 0 then
    Exit;
  if Tick - DnLast[S][V] > DmgStackTicks then
    Exit;
  if not TextRoom(S, Tick) then
    Exit;
  if SightActive() then
    if not CanSee(S, V) then
    begin
      StatHid := StatHid + 1;
      Exit;
    end;
  DnKill[S][V] := True;
  if DmgMode = DM_COLUMN then
  begin
    T := DnText[S][V];
    Width := 4;
  end
  else
  begin
    T := DmgNumber(DnSum[S][V]);
    Width := Length(T);
  end;
  Width := Width + 1 + Length(DmgKillMark);
  DmgPlace(S, V, Width, X, Y);
  PL[S].WorldText(DnLayer[S][V], T + ' ' + DmgKillMark, WtTicks(DmgDisplayTicks), DmgColorKill, DmgScale, X, Y);
  WtSharp(S, DnLayer[S][V], Tick, DmgDisplayTicks);
  TextSent(S);
  StatDmg := StatDmg + 1;
end;

{ ================================ radar ================================ }

{ who may use every mode: a Steam id of [Radar] SteamIds }
procedure OverlayAllow(ID: Integer);
begin
  OvlAllowed[ID] := False;
  if SteamId[ID] <> '' then
    OvlAllowed[ID] := OvlSteams.IndexOf(SteamId[ID]) >= 0;
  { [Debug] BotsSeeTexts: every bot runs the radar too }
  if DebugBots then
    if not PL[ID].Human then
      OvlAllowed[ID] := True;
end;

{ the radar at all: every mode for SteamIds, the list and the circle for everybody when it is public }
function RadarMay(ID: Integer): Boolean;
begin
  Result := OvlAllowed[ID] or OvlPublic;
end;

{ the player's own mode, else the server's; labels and arrows only for SteamIds }
function RadarMode(ID: Integer): Integer;
begin
  Result := OvlMode;
  if RdPMode[ID] >= 1 then
    Result := RdPMode[ID] - 1;
  if (Result = OVL_LABELS) or (Result = OVL_ARROWS) then
    if not OvlAllowed[ID] then
      Result := OVL_LIST;
end;

{ ticks between two passes: the player's own choice, else the mode's; public users not below
  PublicMinTicks }
function RadarTicks(ID: Integer): Integer;
var
  M: Integer;
begin
  M := RadarMode(ID);
  if M = OVL_LIST then
    Result := OvlListTicks
  else if M = OVL_CIRCLE then
    Result := OvlCircleTicks
  else if M = OVL_ARROWS then
    Result := OvlArrowTicks
  else
    Result := OvlUpdateTicks;
  if RdPTicks[ID] > 0 then
    Result := RdPTicks[ID];
  if not OvlAllowed[ID] then
    if Result < OvlPublicMinTicks then
      Result := OvlPublicMinTicks;
  if Result < 1 then
    Result := 1;
end;

function RadarEditing(ID: Integer): Boolean;
begin
  Result := EdOn[ID] and (EdKind[ID] = ED_RADAR);
end;

{ the size factor of the list and the circle (1 = the settings) }
function RadarSize(ID: Integer): Single;
begin
  if RadarEditing(ID) then
    Result := EdScale[ID]
  else
  begin
    Result := RdPSize[ID];
    if Result <= 0 then
      Result := 1;
  end;
end;

{ the zoom: more range, smaller marks (1 = the settings) }
function RadarZoom(ID: Integer): Single;
begin
  Result := RdPZoom[ID];
  if Result <= 0 then
    Result := 1;
end;

{ how far the radar reaches: Range, a little more for a bigger radar ([Radar] SizeAffectsRange),
  times the zoom }
function RadarRange(ID: Integer): Single;
begin
  Result := OvlRange * (1 + (RadarSize(ID) - 1) * OvlSizeRange) * RadarZoom(ID);
  if Result < 50 then
    Result := 50;
end;

{ where the mode is drawn by default: the top-left corner of the list or of the circle }
procedure RadarDefPos(Mode: Integer; var X, Y: Integer);
begin
  if Mode = OVL_CIRCLE then
  begin
    X := OvlCircleX;
    Y := OvlCircleY;
  end
  else
  begin
    X := OvlListX;
    Y := OvlListY;
  end;
end;

procedure RadarPos(ID, Mode: Integer; var X, Y: Integer);
begin
  if RadarEditing(ID) then
  begin
    X := Round(EdX[ID]);
    Y := Round(EdY[ID]);
    Exit;
  end;
  RadarDefPos(Mode, X, Y);
  if RdPX[ID] >= 0 then
    X := RdPX[ID];
  if RdPY[ID] >= 0 then
    Y := RdPY[ID];
end;

{ on or off: the player's own choice, else the default of his kind of user }
procedure RadarApplyOn(ID: Integer);
begin
  if RdPOn[ID] = PREF_ON then
    OvlOn[ID] := True
  else if RdPOn[ID] = PREF_OFF then
    OvlOn[ID] := False
  else if OvlAllowed[ID] then
    OvlOn[ID] := OvlDefaultOn
  else
    OvlOn[ID] := OvlPublicOn;
end;

{ which players the radar shows: all, those seen by the user or a team mate (seenall: dead team
  mates count), or those seen by the user or a living team mate (seen). A player of a public radar
  is not given less than PublicShow allows. }
function RadarShowOf(ID: Integer): Integer;
var
  Def: Integer;
begin
  if OvlAllowed[ID] then
    Def := OvlShow
  else
    Def := OvlPublicShow;
  Result := Def;
  if RdPShow[ID] >= 1 then
    Result := RdPShow[ID] - 1;
  if not OvlAllowed[ID] then
    if Result < OvlPublicShow then
      Result := OvlPublicShow;
end;

{ who sees the radar now, and whether any of them needs the team vision; worked out when one of
  these changes, not on every pass }
procedure OverlayRecount();
var
  i: Integer;
begin
  OvlCount := 0;
  VisNeeded := False;
  for i := 1 to 32 do
  begin
    OvlAdmin[i] := False;
    if OvlEnabled then
      if OvlOn[i] then
        if RadarMay(i) then
          if ActiveSlot[i] then
            if PL[i].Human or DebugBots then
              OvlAdmin[i] := True;
    if OvlAdmin[i] then
    begin
      OvlCount := OvlCount + 1;
      if RadarShowOf(i) <> SHOW_ALL then
        VisNeeded := True;
    end;
  end;
end;

{ the marks of one mode go away at once }
procedure RadarHideMode(ID, Mode: Integer);
var
  b, k: Integer;
  P: TActivePlayer;
begin
  P := PL[ID];
  if Mode = OVL_LIST then
  begin
    if OvlListText[ID] <> '' then
      if P.Active then
        P.BigText(OvlListLayer, ' ', 1, ColorGood, 0.01, 0, 0);
    OvlListText[ID] := '';
    OvlListSent[ID] := 0;
  end
  else if Mode = OVL_LABELS then
  begin
    for b := 1 to 32 do
      if OvlLabelOn[ID][b] then
      begin
        OvlLabelOn[ID][b] := False;
        if P.Active then
          P.WorldText(OvlLayerFirst + b - 1, ' ', 1, ColorGood, 0.01, 0, 0);
      end;
  end
  else if Mode = OVL_CIRCLE then
  begin
    if CrOn[ID] then
      if P.Active then
      begin
        for k := 0 to CrDots[ID] - 1 do
          P.BigText(OvlCircleLayer + k, ' ', 1, ColorGood, 0.01, 0, 0);
        P.BigText(OvlCircleLayer + RING_MAX, ' ', 1, ColorGood, 0.01, 0, 0);
      end;
    CrOn[ID] := False;
    CrDots[ID] := 0;
    for b := 1 to 32 do
      if CbOn[ID][b] then
      begin
        CbOn[ID][b] := False;
        if P.Active then
          P.BigText(OvlCircleLayer + RING_MAX + b, ' ', 1, ColorGood, 0.01, 0, 0);
      end;
    for k := 0 to 7 do
      if ChOn[ID][k] then
      begin
        ChOn[ID][k] := False;
        if P.Active then
          P.BigText(OvlCircleLayer + RING_MAX + 33 + k, ' ', 1, ColorGood, 0.01, 0, 0);
      end;
  end
  else if Mode = OVL_ARROWS then
  begin
    for k := 0 to ARROW_LAYERS - 1 do
      if ArOn[ID][k] then
      begin
        ArOn[ID][k] := False;
        if P.Active then
          P.WorldText(OvlArrowLayer + k, ' ', 1, ColorGood, 0.01, 0, 0);
      end;
  end;
end;

{ everything of the radar goes away (switched off, a new mode, a new layer after /reloadsettings) }
procedure OverlayHide(ID: Integer);
begin
  RadarHideMode(ID, RdDrawn[ID]);
  RdDrawn[ID] := -1;
end;

{ the living players, read once for all radar users of this tick; the flag and the bow only when
  [Radar] Tags is on (two more reads per player) }
procedure OverlaySnapshot();
var
  b, W: Integer;
  Q: TActivePlayer;
begin
  for b := 1 to TopSlot do
  begin
    OvlPAlive[b] := False;
    OvlPTag[b] := TAG_NONE;
    if ActiveSlot[b] then
    begin
      Q := PL[b];
      if Q.Alive then
      begin
        OvlPAlive[b] := True;
        OvlPX[b] := Q.X;
        OvlPY[b] := Q.Y;
        OvlPPct[b] := HealthPct(Q.Health);
        if OvlTags then
        begin
          if Q.Flagger then
            OvlPTag[b] := TAG_FLAG
          else
          begin
            W := Q.Primary.WType;
            if (W = WEP_BOW) or (W = WEP_BOW_FIRE) then
              OvlPTag[b] := TAG_BOW;
          end;
        end;
      end;
    end;
  end;
end;

function TagText(T: Integer): string;
begin
  Result := '';
  if T = TAG_FLAG then
    Result := OvlFlagChar
  else if T = TAG_BOW then
    Result := OvlBowChar;
end;

{ where another player is, seen from the radar user: < > left and right, ^ v above and below }
function RadarDir(DX, DY: Single): string;
begin
  Result := '';
  if DX < -40 then
    Result := '<'
  else if DX > 40 then
    Result := '>';
  if DY < -40 then
    Result := Result + '^'
  else if DY > 40 then
    Result := Result + 'v';
  if Result = '' then
    Result := 'o';
end;

{ the user's own position: where he stands, or lies dead }
procedure RadarCentre(A: Integer; var X, Y: Single);
begin
  if OvlPAlive[A] then
  begin
    X := OvlPX[A];
    Y := OvlPY[A];
  end
  else
  begin
    X := PL[A].X;
    Y := PL[A].Y;
  end;
end;

{ ---- team vision: who is seen by whom (radar Show = seen / seenall) ---- }

{ a player's position, life and cursor, read once a tick however many rays need them }
procedure VisionPos(i, Tick: Integer);
var
  P: TActivePlayer;
begin
  if VpTick[i] = Tick then
    Exit;
  VpTick[i] := Tick;
  P := PL[i];
  VpAlive[i] := False;
  if ActiveSlot[i] then
    if P.Alive then
    begin
      VpAlive[i] := True;
      VpX[i] := P.X;
      VpY[i] := P.Y;
      VpAimX[i] := P.MouseAimX;
      VpAimY[i] := P.MouseAimY;
    end;
  if not VpAlive[i] then
    if ActiveSlot[i] then
    begin
      VpX[i] := P.X;
      VpY[i] := P.Y;
    end;
end;

{ Could S see B by the rule of realistic mode (see CanSee): a living S only in front of his aim, a
  dead one from where he lies, in any direction; up to LOS_RANGE, no wall between the upper bodies. }
function SpotSee(S, B, Tick: Integer): Boolean;
var
  VX, VY, TX, TY, DX, DY: Single;
begin
  Result := False;
  VisionPos(S, Tick);
  VisionPos(B, Tick);
  if not VpAlive[B] then
    Exit;
  VX := VpX[S];
  VY := VpY[S] - LOS_HEIGHT - 2;
  TX := VpX[B];
  TY := VpY[B] - LOS_HEIGHT;
  DX := TX - VX;
  DY := TY - VY;
  if DX * DX + DY * DY > LOS_RANGE * LOS_RANGE then
    Exit;
  if VpAlive[S] then
    if DX * (VpAimX[S] - VX) + DY * (VpAimY[S] - VY) <= 0 then
      Exit;
  Result := not Map.RayCast(VX, VY, TX, TY, False, False, False, False, 0);
end;

{ is S a spotter somebody's radar needs: a radar user with a filter, or a team mate of one }
function VisSpotter(S: Integer): Boolean;
var
  a: Integer;
begin
  Result := False;
  for a := 1 to TopSlot do
    if OvlAdmin[a] then
      if RadarShowOf(a) <> SHOW_ALL then
      begin
        if a = S then
          Result := True
        else if TeamGame() then
          if TeamOf[a] = TeamOf[S] then
            Result := True;
        if Result then
          Exit;
      end;
end;

{ the spotters of this round: radar users with a filter and their team mates }
procedure VisionList();
var
  i: Integer;
begin
  VisCount := 0;
  for i := 1 to TopSlot do
    if ActiveSlot[i] then
      if VisSpotter(i) then
      begin
        VisList[VisCount] := i;
        VisCount := VisCount + 1;
      end;
end;

{ Every tick while a radar needs it: the next VisionRaysPerTick pairs (spotter, player) are looked
  at with Map.RayCast, round the table; with 16 against 16 it is all seen again every third of a
  second. The table keeps each answer until that pair comes again. }
procedure VisionTick(Tick: Integer);
var
  n, Guard, s, b: Integer;
  Teams: Boolean;
begin
  if VisCount = 0 then
  begin
    if Tick < VisNextRound then
      Exit;
    VisNextRound := After(Tick, OvlVisionRound);
    VisionList();
    VisK := 0;
    VisB := 0;
    if VisCount = 0 then
      Exit;
  end;
  Teams := TeamGame();
  n := 0;
  Guard := 0;
  while (n < OvlVisionRays) and (Guard < OvlVisionRays * 4) do
  begin
    Guard := Guard + 1;
    VisB := VisB + 1;
    if VisB > TopSlot then
    begin
      VisB := 1;
      VisK := VisK + 1;
      if VisK >= VisCount then
      begin
        { the table is round: the next one starts VisionRoundTicks after this one started (who is a
          spotter may have changed by then) }
        VisK := 0;
        VisB := 0;
        VisCount := 0;
        StatRays := StatRays + n;
        Exit;
      end;
    end;
    s := VisList[VisK];
    b := VisB;
    if s = b then
      Continue;
    VisMine[s][b] := False;
    if not ActiveSlot[s] then
      Continue;
    if not ActiveSlot[b] then
      Continue;
    if Teams then
      if TeamOf[s] = TeamOf[b] then
        Continue;
    VisMine[s][b] := SpotSee(s, b, Tick);
    n := n + 1;
  end;
  StatRays := StatRays + n;
end;

{ does A's radar show B now: team mates always, the others by A's filter }
function RadarShows(A, B: Integer): Boolean;
var
  Sh, s: Integer;
  Teams: Boolean;
begin
  Result := True;
  Sh := RadarShowOf(A);
  if Sh = SHOW_ALL then
    Exit;
  Teams := TeamGame();
  if Teams then
    if TeamOf[B] = TeamOf[A] then
      Exit;
  if VisMine[A][B] then
    Exit;
  if Teams then
    for s := 1 to TopSlot do
      if s <> A then
        if TeamOf[s] = TeamOf[A] then
          if VisMine[s][B] then
          begin
            if Sh = SHOW_SEENALL then
              Exit;
            if OvlPAlive[s] then
              Exit;
          end;
  Result := False;
end;

{ Mode = list: the nearest living players within reach, at most ListLines of them, in a steady
  text on the screen. The lines keep the slot order, so they stay in their places; the text is sent
  again only when it changes, moves or is about to run out. A spectator gets everybody alive,
  without distance. }
procedure OverlayList(A, Tick: Integer);
var
  b, k, Best, X0, Y0: Integer;
  Adm: TActivePlayer;
  ax, ay, DX, DY, R2, BestD, Sc: Single;
  Ref: Boolean;
  D2: array[1..32] of Single;
  Pick: array[1..32] of Boolean;
  T, L, Tg: string;
begin
  Adm := PL[A];
  Ref := TeamOf[A] <> TEAM_SPECTATOR;
  ax := 0;
  ay := 0;
  if Ref then
    RadarCentre(A, ax, ay);
  R2 := RadarRange(A);
  R2 := R2 * R2;
  for b := 1 to TopSlot do
  begin
    Pick[b] := False;
    D2[b] := -1;
    if b <> A then
      if OvlPAlive[b] then
        if RadarShows(A, b) then
        begin
          D2[b] := 0;
          if Ref then
          begin
            DX := OvlPX[b] - ax;
            DY := OvlPY[b] - ay;
            D2[b] := DX * DX + DY * DY;
            if D2[b] > R2 then
              D2[b] := -1;
          end;
        end;
  end;
  k := 0;
  while k < OvlListMax do
  begin
    Best := 0;
    BestD := 0;
    for b := 1 to TopSlot do
      if D2[b] >= 0 then
        if not Pick[b] then
          if (Best = 0) or (D2[b] < BestD) then
          begin
            Best := b;
            BestD := D2[b];
          end;
    if Best = 0 then
      Break;
    Pick[Best] := True;
    k := k + 1;
  end;
  T := OvlListTitle;
  if RadarEditing(A) then
    T := T + ' <edit>';
  for b := 1 to TopSlot do
    if Pick[b] then
    begin
      Tg := TagText(OvlPTag[b]);
      if Tg <> '' then
        Tg := Tg + ' ';
      L := ReplaceAll(OvlListLine, '{name}', PL[b].Name);
      L := ReplaceAll(L, '{pct}', IntToStr(OvlPPct[b]));
      L := ReplaceAll(L, '{tag}', Tg);
      if Ref then
      begin
        L := ReplaceAll(L, '{dist}', IntToStr(Round(Sqrt(D2[b]) / 10) * 10));
        L := ReplaceAll(L, '{dir}', RadarDir(OvlPX[b] - ax, OvlPY[b] - ay));
      end
      else
      begin
        L := ReplaceAll(L, '{dist}', '');
        L := ReplaceAll(L, '{dir}', '');
      end;
      L := Trim(L);
      if T = '' then
        T := L
      else
        T := T + #13#10 + L;
    end;
  if k = 0 then
  begin
    L := '(nobody within ' + IntToStr(Round(Sqrt(R2))) + ')';
    if T = '' then
      T := L
    else
      T := T + #13#10 + L;
  end;
  RadarPos(A, OVL_LIST, X0, Y0);
  Sc := QScale(OvlListScale * RadarSize(A));
  if not RdRedraw[A] then
    if T = OvlListText[A] then
      if Tick - OvlListSent[A] < OVL_LIST_REFRESH then
        Exit;
  Adm.BigText(OvlListLayer, T, OVL_LIST_DISPLAY, OvlListColor, Sc, X0, Y0);
  OvlListText[A] := T;
  OvlListSent[A] := Tick;
  StatOvl := StatOvl + 1;
end;

{ Mode = labels: one line "name health%" centred OffsetY above the feet of each living player near
  the user. A label is sent again when its player moved or his health changed (or before it runs
  out) and taken away with ' ' when he dies or leaves the range, so it keeps its full colour. At
  most TEXTS_PER_TICK texts at a time: a crowd is covered over a few passes. }
procedure OverlayLabels(A, Tick: Integer);
var
  b, k, Pct: Integer;
  Adm: TActivePlayer;
  ax, ay, bx, by, R2, X, Y: Single;
  T, Tg: string;
  Want: Boolean;
begin
  Adm := PL[A];
  RadarCentre(A, ax, ay);
  R2 := RadarRange(A);
  R2 := R2 * R2;
  b := OvlNext[A];
  k := 0;
  while k < TopSlot do
  begin
    if not TextRoom(A, Tick) then
      Break;
    k := k + 1;
    b := b + 1;
    if b > TopSlot then
      b := 1;
    Want := False;
    if b <> A then
      if OvlPAlive[b] then
      begin
        bx := OvlPX[b] - ax;
        by := OvlPY[b] - ay;
        if bx * bx + by * by <= R2 then
          Want := RadarShows(A, b);
      end;
    if Want then
    begin
      Pct := OvlPPct[b];
      if (not OvlLabelOn[A][b]) or (Abs(OvlPX[b] - OvlLastX[A][b]) > 2) or (Abs(OvlPY[b] - OvlLastY[A][b]) > 2) or
        (Pct <> OvlLastPct[A][b]) or (Tick - OvlLastTick[A][b] >= OVL_LIST_REFRESH) or
        (OvlPTag[b] <> OvlLastTag[A][b]) then
      begin
        T := PL[b].Name + ' ' + IntToStr(Pct) + '%';
        Tg := TagText(OvlPTag[b]);
        if Tg <> '' then
          T := T + ' [' + Tg + ']';
        X := OvlPX[b] - Length(T) * OvlScale * WT_CHAR_WIDTH / 2;
        Y := OvlPY[b] - OvlOffsetY;
        Adm.WorldText(OvlLayerFirst + b - 1, T, OVL_MARK_DISPLAY, HudColorAt[Pct], OvlScale, X, Y);
        TextSent(A);
        OvlLabelOn[A][b] := True;
        OvlLastX[A][b] := OvlPX[b];
        OvlLastY[A][b] := OvlPY[b];
        OvlLastPct[A][b] := Pct;
        OvlLastTag[A][b] := OvlPTag[b];
        OvlLastTick[A][b] := Tick;
        StatOvl := StatOvl + 1;
      end;
    end
    else if OvlLabelOn[A][b] then
    begin
      Adm.WorldText(OvlLayerFirst + b - 1, ' ', 1, ColorGood, 0.01, 0, 0);
      TextSent(A);
      OvlLabelOn[A][b] := False;
    end;
  end;
  OvlNext[A] := b;
end;

{ One mark of the circle radar, centred on (X, Y): BigText draws from the top-left corner of the
  letters, their middle is about 0.42 em per letter to the right and 0.66 em down. }
procedure CircleMark(ID, Layer: Integer; Ch: string; C: Longint; Sc, X, Y: Single);
var
  Em: Single;
begin
  Em := BT_EM * Sc;
  PL[ID].BigText(Layer, Ch, OVL_MARK_DISPLAY, C, Sc, Round(X - 0.42 * Em * Length(Ch)), Round(Y - 0.66 * Em));
  TextSent(ID);
  StatOvl := StatOvl + 1;
end;

{ Mode = circle: a ring of dots on the screen with the user in the middle; the players within reach
  are marks at their places (team mates in their colour, F for a flag carrier, R for a bow), those
  further away sit on the ring in their direction (ShowFar), hits on the user are red marks on the
  ring towards the shooter (HitMarks). A mark is sent again only when it moves or changes, and taken
  away with ' ' when not wanted. While the editor is open only the ring and the user are drawn. }
procedure OverlayCircle(A, Tick: Integer);
var
  b, k, X0, Y0, Dots, Px, Py, S: Integer;
  Adm: TActivePlayer;
  Sz, R, Sc, CX, CY, ax, ay, DX, DY, D, Ang, Rng: Single;
  Ch: string;
  C: Longint;
  Redraw, Want, Friend, Teams, Editing: Boolean;
begin
  Adm := PL[A];
  Sz := RadarSize(A);
  RadarPos(A, OVL_CIRCLE, X0, Y0);
  R := OvlCircleR * Sz;
  Sc := QScale(OvlCircleScale * Sz / Sqrt(RadarZoom(A)));
  CX := X0 + R;
  CY := Y0 + R;
  Dots := OvlCircleDots;
  Rng := RadarRange(A);
  Editing := RadarEditing(A);
  { the ring and the user himself: again when it moved, changed its size or is about to run out }
  Redraw := RdRedraw[A];
  if not CrOn[A] then
    Redraw := True;
  if (CrX[A] <> X0) or (CrY[A] <> Y0) or (CrR[A] <> Round(R * 10)) or (CrDots[A] <> Dots) or (CrScale[A] <> Sc) then
    Redraw := True;
  if Tick - CrSent[A] >= OVL_LIST_REFRESH then
    Redraw := True;
  if Redraw then
  begin
    for k := Dots to CrDots[A] - 1 do
      Adm.BigText(OvlCircleLayer + k, ' ', 1, ColorGood, 0.01, 0, 0);
    for k := 0 to Dots - 1 do
    begin
      Ang := 2 * Pi * k / Dots;
      CircleMark(A, OvlCircleLayer + k, OvlRingChar, OvlRingColor, Sc, CX + R * Cos(Ang), CY + R * Sin(Ang));
    end;
    CircleMark(A, OvlCircleLayer + RING_MAX, OvlSelfChar, OvlSelfColor, Sc, CX, CY);
    CrOn[A] := True;
    CrX[A] := X0;
    CrY[A] := Y0;
    CrR[A] := Round(R * 10);
    CrDots[A] := Dots;
    CrSent[A] := Tick;
    CrScale[A] := Sc;
  end;
  if Editing then
    Exit;
  RadarCentre(A, ax, ay);
  Teams := TeamGame();
  for b := 1 to TopSlot do
    if b <> A then
    begin
      Want := False;
      if OvlPAlive[b] then
        if RadarShows(A, b) then
        begin
          DX := OvlPX[b] - ax;
          DY := OvlPY[b] - ay;
          D := Sqrt(DX * DX + DY * DY);
          Friend := False;
          if Teams then
            if TeamOf[b] = TeamOf[A] then
              Friend := True;
          if Friend then
          begin
            Ch := OvlFriendChar;
            C := OvlFriendColor;
          end
          else
          begin
            Ch := OvlEnemyChar;
            C := OvlEnemyColor;
          end;
          if OvlPTag[b] <> TAG_NONE then
            Ch := TagText(OvlPTag[b]);
          if D <= Rng then
          begin
            Want := True;
            Px := Round(CX + DX / Rng * R);
            Py := Round(CY + DY / Rng * R);
          end
          else if OvlShowFar then
          begin
            Want := True;
            if OvlPTag[b] = TAG_NONE then
              Ch := OvlFarChar;
            Px := Round(CX + DX / D * R);
            Py := Round(CY + DY / D * R);
          end;
        end;
      if Want then
      begin
        if Redraw or (not CbOn[A][b]) or (CbX[A][b] <> Px) or (CbY[A][b] <> Py) or (CbColor[A][b] <> C) or
          (CbChar[A][b] <> Ch) or (Tick - CbSent[A][b] >= OVL_LIST_REFRESH) then
          if TextRoom(A, Tick) then
          begin
            CircleMark(A, OvlCircleLayer + RING_MAX + b, Ch, C, Sc, Px, Py);
            CbOn[A][b] := True;
            CbX[A][b] := Px;
            CbY[A][b] := Py;
            CbColor[A][b] := C;
            CbChar[A][b] := Ch;
            CbSent[A][b] := Tick;
          end;
      end
      else if CbOn[A][b] then
        if TextRoom(A, Tick) then
        begin
          Adm.BigText(OvlCircleLayer + RING_MAX + b, ' ', 1, ColorGood, 0.01, 0, 0);
          TextSent(A);
          CbOn[A][b] := False;
        end;
    end;
  { hits on the user: red marks on the ring, towards the shooter while they last }
  if HmActive[A] then
  begin
    HmActive[A] := False;
    for k := 0 to 7 do
      if HmUntil[A][k] > 0 then
      begin
        if Tick >= HmUntil[A][k] then
        begin
          HmUntil[A][k] := 0;
          if ChOn[A][k] then
          begin
            Adm.BigText(OvlCircleLayer + RING_MAX + 33 + k, ' ', 1, ColorGood, 0.01, 0, 0);
            ChOn[A][k] := False;
          end;
        end
        else
        begin
          HmActive[A] := True;
          S := HmShooter[A][k];
          DX := 0;
          DY := 0;
          if (S >= 1) and (S <= 32) then
            if ActiveSlot[S] then
            begin
              DX := PL[S].X - ax;
              DY := PL[S].Y - ay;
            end;
          D := Sqrt(DX * DX + DY * DY);
          if D < 1 then
          begin
            DX := Cos(k * Pi / 4);
            DY := Sin(k * Pi / 4);
            D := 1;
          end;
          CircleMark(A, OvlCircleLayer + RING_MAX + 33 + k, OvlHitChar, OvlHitColor, QScale(Sc * 1.4),
            CX + DX / D * R, CY + DY / D * R);
          ChOn[A][k] := True;
        end;
      end;
  end;
end;

{ one dot of an arrow: sent when it moved 2 pixels, changed colour or is about to run out (every
  WorldText is a packet of its own: the arrows are the dearest mode) }
procedure ArrowDot(A, Layer: Integer; Ch: string; C: Longint; X, Y: Single; Tick: Integer);
var
  Px, Py: Integer;
begin
  Px := Round(X);
  Py := Round(Y);
  if ArOn[A][Layer] then
    if Abs(ArX[A][Layer] - Px) < 2 then
      if Abs(ArY[A][Layer] - Py) < 2 then
        if ArC[A][Layer] = C then
          if Tick - ArSent[A][Layer] < OVL_LIST_REFRESH then
            Exit;
  PL[A].WorldText(OvlArrowLayer + Layer, Ch, OVL_MARK_DISPLAY, C, OvlArrowScale, Px, Py);
  ArOn[A][Layer] := True;
  ArX[A][Layer] := Px;
  ArY[A][Layer] := Py;
  ArC[A][Layer] := C;
  ArSent[A][Layer] := Tick;
  StatOvl := StatOvl + 1;
end;

{ Mode = arrows: arrows of dots around the user's own soldier (WorldText), each pointing at one of
  the nearest players within reach: the dots go from ArrowInner to ArrowOuter pixels, the colour tells
  the distance (ArrowColorNear - ArrowColorMid - ArrowColorFar) and grows brighter towards the tip,
  two dots make the head (the flag or bow letter sits on the tip). Drawn again on every pass, so they
  follow the user; the dots of an arrow not needed any more are taken away with ' '. }
procedure OverlayArrows(A, Tick: Integer);
var
  b, k, n, i, j, Best, Layer, Dots: Integer;
  Adm: TActivePlayer;
  ax, ay, cx, cy, DX, DY, D, Ux, Uy, R, Rng, BestD, T, X, Y, W, H: Single;
  C, CBase: Longint;
  Pick: array[1..32] of Boolean;
  D2: array[1..32] of Single;
  Used: array[0..63] of Boolean;
  Ch: string;
begin
  Adm := PL[A];
  RadarCentre(A, ax, ay);
  cx := ax;
  cy := ay - LOS_HEIGHT;
  Rng := RadarRange(A);
  Dots := OvlArrowDots;
  for k := 0 to ARROW_LAYERS - 1 do
    Used[k] := False;
  for b := 1 to TopSlot do
  begin
    Pick[b] := False;
    D2[b] := -1;
    if b <> A then
      if OvlPAlive[b] then
        if RadarShows(A, b) then
        begin
          DX := OvlPX[b] - ax;
          DY := OvlPY[b] - ay;
          D2[b] := DX * DX + DY * DY;
          if D2[b] > Rng * Rng then
            D2[b] := -1;
        end;
  end;
  n := 0;
  while n < OvlArrowsMax do
  begin
    Best := 0;
    BestD := 0;
    for b := 1 to TopSlot do
      if D2[b] >= 0 then
        if not Pick[b] then
          if (Best = 0) or (D2[b] < BestD) then
          begin
            Best := b;
            BestD := D2[b];
          end;
    if Best = 0 then
      Break;
    Pick[Best] := True;
    b := Best;
    D := Sqrt(D2[b]);
    DX := OvlPX[b] - ax;
    DY := OvlPY[b] - ay;
    if D < 1 then
    begin
      Ux := 1;
      Uy := 0;
    end
    else
    begin
      Ux := DX / D;
      Uy := DY / D;
    end;
    { the colour of the distance: near - mid - far }
    T := D / Rng;
    if T < 0.5 then
      CBase := MixColor(OvlArrowNear, OvlArrowMid, T * 2)
    else
      CBase := MixColor(OvlArrowMid, OvlArrowFar, (T - 0.5) * 2);
    W := OvlArrowScale * WT_CHAR_WIDTH / 2;
    H := OvlArrowScale * WT_LINE_HEIGHT / 2;
    { the shaft: dots from the inner to the outer radius, darker at the tail }
    for i := 0 to Dots - 1 do
    begin
      if Dots > 1 then
        R := OvlArrowInner + (OvlArrowOuter - OvlArrowInner) * i / (Dots - 1)
      else
        R := OvlArrowOuter;
      C := MixColor(MixColor(CBase, 0, 0.6), CBase, (i + 1) * 1.0 / Dots);
      Ch := OvlArrowChar;
      if i = Dots - 1 then
        if OvlPTag[b] <> TAG_NONE then
          Ch := TagText(OvlPTag[b]);
      Layer := n * ARROW_DOTS_MAX + i;
      X := cx + Ux * R - W * Length(Ch);
      Y := cy + Uy * R - H;
      ArrowDot(A, Layer, Ch, C, X, Y, Tick);
      Used[Layer] := True;
    end;
    { the head: two dots behind the tip, to both sides }
    for j := 0 to 1 do
    begin
      if j = 0 then
      begin
        X := cx + Ux * (OvlArrowOuter - OvlArrowHead) - Uy * OvlArrowHead * 0.8;
        Y := cy + Uy * (OvlArrowOuter - OvlArrowHead) + Ux * OvlArrowHead * 0.8;
      end
      else
      begin
        X := cx + Ux * (OvlArrowOuter - OvlArrowHead) + Uy * OvlArrowHead * 0.8;
        Y := cy + Uy * (OvlArrowOuter - OvlArrowHead) - Ux * OvlArrowHead * 0.8;
      end;
      Layer := n * ARROW_DOTS_MAX + Dots + j;
      ArrowDot(A, Layer, OvlArrowChar, CBase, X - W, Y - H, Tick);
      Used[Layer] := True;
    end;
    n := n + 1;
  end;
  for k := 0 to ARROW_LAYERS - 1 do
    if ArOn[A][k] then
      if not Used[k] then
      begin
        Adm.WorldText(OvlArrowLayer + k, ' ', 1, ColorGood, 0.01, 0, 0);
        ArOn[A][k] := False;
      end;
end;

{ every tick while somebody uses the radar: each user gets a pass when his own interval is up (or
  right after he moved it, resized it or changed the mode); a spectator gets the list }
procedure OverlayTick(Tick: Integer);
var
  i, M: Integer;
  Snap: Boolean;
begin
  Snap := False;
  for i := 1 to TopSlot do
    if OvlAdmin[i] then
      if (Tick >= RdDue[i]) or RdRedraw[i] then
      begin
        if not Snap then
        begin
          OverlaySnapshot();
          Snap := True;
        end;
        RdDue[i] := After(Tick, RadarTicks(i));
        M := RadarMode(i);
        if M <> OVL_LIST then
          if TeamOf[i] = TEAM_SPECTATOR then
            M := OVL_LIST;
        if M <> RdDrawn[i] then
        begin
          RadarHideMode(i, RdDrawn[i]);
          RdDrawn[i] := M;
          RdRedraw[i] := True;
        end;
        if M = OVL_LIST then
          OverlayList(i, Tick)
        else if M = OVL_CIRCLE then
          OverlayCircle(i, Tick)
        else if M = OVL_ARROWS then
          OverlayArrows(i, Tick)
        else
          OverlayLabels(i, Tick);
        RdRedraw[i] := False;
      end;
end;

{ ================================ the editor (health display, radar) ================================ }

{ what the editor shows while it is open: the health text, or the radar at the new place }
procedure EditorShow(ID: Integer);
begin
  if EdKind[ID] = ED_RADAR then
    RdRedraw[ID] := True
  else
    HudMark(ID, True);
end;

procedure EditorStop(ID: Integer; Save: Boolean);
var
  X, Y: Integer;
begin
  if not EdOn[ID] then
    Exit;
  EdOn[ID] := False;
  EdCount := EdCount - 1;
  if EdCount < 0 then
    EdCount := 0;
  if EdKind[ID] = ED_RADAR then
  begin
    if Save then
    begin
      RdPX[ID] := Round(EdX[ID]);
      RdPY[ID] := Round(EdY[ID]);
      RdPSize[ID] := EdScale[ID];
      RadarDefPos(RadarMode(ID), X, Y);
      if RdPX[ID] = X then
        if RdPY[ID] = Y then
        begin
          RdPX[ID] := -1;
          RdPY[ID] := -1;
        end;
      if Abs(RdPSize[ID] - 1) < 0.001 then
        RdPSize[ID] := 0;
      PrefsSave(ID);
      Say(ID, 'Radar saved: position ' + IntToStr(Round(EdX[ID])) + ' ' + IntToStr(Round(EdY[ID])) + ', size ' +
        FloatStr(EdScale[ID], 2) + '.', ColorGood);
    end
    else
      Say(ID, 'Radar editor closed without saving.', ColorGood);
    RdRedraw[ID] := True;
    Exit;
  end;
  if Save then
  begin
    HudPX[ID] := Round(EdX[ID]);
    HudPY[ID] := Round(EdY[ID]);
    HudPScale[ID] := EdScale[ID];
    if HudPX[ID] = HudDefX then
      if HudPY[ID] = HudDefY then
      begin
        HudPX[ID] := -1;
        HudPY[ID] := -1;
      end;
    if Abs(HudPScale[ID] - HudDefScale) < 0.0001 then
      HudPScale[ID] := 0;
    PrefsSave(ID);
    Say(ID, 'Health display saved: position ' + IntToStr(Round(EdX[ID])) + ' ' + IntToStr(Round(EdY[ID])) +
      ', size ' + FloatStr(EdScale[ID], 4) + '.', ColorGood);
  end
  else
    Say(ID, 'Health display editor closed without saving.', ColorGood);
  HudMark(ID, True);
end;

{ Kind = ED_HUD or ED_RADAR. The player stands still; the keys move and resize the text. }
procedure EditorStart(ID, Kind: Integer);
var
  P: TActivePlayer;
  X, Y: Integer;
  S: Single;
begin
  P := PL[ID];
  if not P.Alive then
  begin
    Say(ID, 'The editor works only while you are alive.', ColorBad);
    Exit;
  end;
  if EdOn[ID] then
  begin
    if EdKind[ID] = Kind then
      Exit;
    EditorStop(ID, True);
  end;
  if Kind = ED_RADAR then
  begin
    RadarPos(ID, RadarMode(ID), X, Y);
    S := RadarSize(ID);
  end;
  EdOn[ID] := True;
  EdKind[ID] := Kind;
  EdCount := EdCount + 1;
  EdUntil[ID] := Game.TickCount + HudEditorTicks;
  EdHold[ID] := 0;
  EdProne[ID] := P.IsProne;
  EdNade[ID] := P.KeyGrenade;
  EdMoved[ID] := False;
  EdPinX[ID] := P.X;
  EdPinY[ID] := P.Y;
  if Kind = ED_RADAR then
  begin
    EdX[ID] := X;
    EdY[ID] := Y;
    EdScale[ID] := S;
    if not OvlOn[ID] then
    begin
      RdPOn[ID] := PREF_ON;
      RadarApplyOn(ID);
      OverlayRecount();
    end;
    Say(ID, 'Radar editor: you stand still while it is open.', ColorGood);
  end
  else
  begin
    EdX[ID] := HudPX[ID];
    if EdX[ID] < 0 then
      EdX[ID] := HudDefX;
    EdY[ID] := HudPY[ID];
    if EdY[ID] < 0 then
      EdY[ID] := HudDefY;
    EdScale[ID] := HudPScale[ID];
    if EdScale[ID] <= 0 then
      EdScale[ID] := HudDefScale;
    if not HudIsOn(ID) then
      HudPOn[ID] := PREF_ON;
    Say(ID, 'Health display editor: you stand still while it is open.', ColorGood);
  end;
  Say(ID, 'Left / right, jump / crouch = move it (a tap = 1 pixel, hold = on and faster);', ColorGood);
  Say(ID, 'reload = bigger, change weapon = smaller.', ColorGood);
  Say(ID, 'Grenade (E) = save and close; lie down (X, prone) = close without saving. A hit or ' +
    IntToStr(HudEditorTicks div 60) + ' seconds save and close it.', ColorGood);
  EditorShow(ID);
end;

{ how many steps a key held for Hold ticks makes in this tick: a tap one step, then a pause of a
  third of a second, then one step every third tick, after a second one step a tick and after two
  seconds two }
function EditorSteps(Hold: Integer): Integer;
begin
  Result := 0;
  if Hold = 1 then
    Result := 1
  else if Hold > 120 then
    Result := 2
  else if Hold > 60 then
    Result := 1
  else if Hold > 20 then
    if Hold mod 3 = 0 then
      Result := 1;
end;

procedure EditorTick(Tick: Integer);
var
  i, Steps, ShowTicks: Integer;
  P: TActivePlayer;
  L, R, U, D, Big, Small, Prone, Nade, Any: Boolean;
  Step, Lo, Hi, SizeStep: Single;
begin
  for i := 1 to TopSlot do
    if EdOn[i] then
    begin
      P := PL[i];
      if not P.Active then
      begin
        EdOn[i] := False;
        EdCount := EdCount - 1;
        Continue;
      end;
      if not P.Alive then
      begin
        EditorStop(i, False);
        Continue;
      end;
      if Tick > EdUntil[i] then
      begin
        EditorStop(i, True);
        Continue;
      end;
      { the keys come with the player's movement packets (every 4-5 ticks); prone is not a key
        the server sees, so going prone is read from the stance }
      L := P.KeyLeft;
      R := P.KeyRight;
      U := P.KeyUp;
      D := P.KeyCrouch;
      Big := P.KeyReload;
      Small := P.KeyChangeWeap;
      Prone := P.IsProne;
      Nade := P.KeyGrenade;
      if Nade then
        if not EdNade[i] then
        begin
          EditorStop(i, True);
          Continue;
        end;
      EdNade[i] := Nade;
      if Prone then
        if not EdProne[i] then
        begin
          EditorStop(i, False);
          Continue;
        end;
      EdProne[i] := Prone;
      if EdKind[i] = ED_RADAR then
      begin
        Lo := 0.3;
        Hi := 4;
        SizeStep := 1.05;
        ShowTicks := 6;
      end
      else
      begin
        Lo := 0.005;
        Hi := 0.5;
        SizeStep := 1.04;
        ShowTicks := 3;
      end;
      Any := L or R or U or D or Big or Small;
      if Any then
      begin
        EdHold[i] := EdHold[i] + 1;
        Steps := EditorSteps(EdHold[i]);
        if Steps > 0 then
          if L or R or U or D then
          begin
            Step := HudEditorStep * Steps;
            if L then
              EdX[i] := EdX[i] - Step;
            if R then
              EdX[i] := EdX[i] + Step;
            if U then
              EdY[i] := EdY[i] - Step;
            if D then
              EdY[i] := EdY[i] + Step;
            if EdX[i] < 0 then
              EdX[i] := 0;
            if EdX[i] > 850 then
              EdX[i] := 850;
            if EdY[i] < 0 then
              EdY[i] := 0;
            if EdY[i] > 475 then
              EdY[i] := 475;
            EdMoved[i] := True;
          end;
        { the size: one step a press, then one every 8 ticks while held. Every size the client
          meets costs it a new set of letters; a fast stream of sizes stalled the game. }
        if Big or Small then
          if (EdHold[i] = 1) or ((EdHold[i] > 20) and (EdHold[i] mod 8 = 0)) then
          begin
            if Big then
              EdScale[i] := EdScale[i] * SizeStep;
            if Small then
              EdScale[i] := EdScale[i] / SizeStep;
            if EdScale[i] < Lo then
              EdScale[i] := Lo;
            if EdScale[i] > Hi then
              EdScale[i] := Hi;
            EdMoved[i] := True;
          end;
        { drawn at most every ShowTicks; the last step is drawn on release }
        if EdMoved[i] then
          if Tick >= EdShowAt[i] then
          begin
            EdMoved[i] := False;
            EdShowAt[i] := Tick + ShowTicks;
            EditorShow(i);
          end;
      end
      else
      begin
        EdHold[i] := 0;
        if EdMoved[i] then
        begin
          EdMoved[i] := False;
          EditorShow(i);
        end;
      end;
      { the player stands still: put back when the movement keys moved him (every Move goes to every
        player, so not more often than every second tick) }
      if Tick mod 2 = 0 then
        if (Abs(P.X - EdPinX[i]) > 2) or (Abs(P.Y - EdPinY[i]) > 2) then
        begin
          P.Move(EdPinX[i], EdPinY[i]);
          P.SetVelocity(0, 0);
        end;
    end;
end;

{ ================================ admins by Steam id ================================ }

procedure SaveGrants();
begin
  try
    GrantList.SaveToFile(DataDir + 'granted_admins.txt');
  except
    Log('cannot write ' + DataDir + 'granted_admins.txt');
  end;
end;

{ Admins_Steam.txt: the player is an admin for this visit once Steam has confirmed his account (an
  HWID can be faked, a Steam account cannot). Soldat keeps admins by IP, and setting IsAdmin makes
  the server write the IP into remote.txt (taking it away removes it from there). So the script takes
  back only an IP it put there itself, and only when no other player it made admin uses that IP; an
  admin by remote.txt, 127.0.0.1 or a TCP login is left alone. }
procedure GrantSteamAdmin(ID: Integer);
var
  P: TActivePlayer;
  Ip: string;
begin
  if GrantedIp[ID] <> '' then
    Exit;
  if SteamId[ID] = '' then
    Exit;
  if AdSteams.IndexOf(SteamId[ID]) < 0 then
    Exit;
  P := PL[ID];
  Ip := P.IP;
  if Ip = '' then
    Exit;
  if P.IsAdmin then
  begin
    { already an admin: ours only when an earlier run of the script put the IP there }
    if GrantList.IndexOf(Ip) >= 0 then
      GrantedIp[ID] := Ip;
    Exit;
  end;
  P.IsAdmin := True;
  GrantedIp[ID] := Ip;
  if GrantList.IndexOf(Ip) < 0 then
  begin
    GrantList.Add(Ip);
    SaveGrants();
  end;
  Log(P.Name + ' is an admin for this visit (' + AdSteamFile + ': ' + SteamId[ID] + ').');
  Say(ID, 'You are an admin on this server (Steam account ' + SteamId[ID] + ').', ColorGood);
end;

procedure RevokeGrant(ID: Integer);
var
  i, k: Integer;
  Ip: string;
begin
  Ip := GrantedIp[ID];
  GrantedIp[ID] := '';
  if Ip = '' then
    Exit;
  for i := 1 to 32 do
    if GrantedIp[i] = Ip then
      Exit;
  PL[ID].IsAdmin := False;
  k := GrantList.IndexOf(Ip);
  if k >= 0 then
  begin
    GrantList.Delete(k);
    SaveGrants();
  end;
end;

{ An IP this script once made admin (the server stopped while that admin played, or his IP changed)
  and now used by a player it did not make admin: the rights are taken back, or whoever gets that
  address later would be an admin. A Steam admin who comes back gets them again when Steam confirms
  him. }
procedure DropStaleGrant(ID: Integer);
var
  i, k: Integer;
  Ip: string;
begin
  if GrantedIp[ID] <> '' then
    Exit;
  Ip := PL[ID].IP;
  if Ip = '' then
    Exit;
  k := GrantList.IndexOf(Ip);
  if k < 0 then
    Exit;
  for i := 1 to 32 do
    if GrantedIp[i] = Ip then
      Exit;
  PL[ID].IsAdmin := False;
  GrantList.Delete(k);
  SaveGrants();
  Log('the admin rights of ' + Ip + ' (given for ' + AdSteamFile + ' earlier) were taken back: ' + PL[ID].Name +
    ' joined from it');
end;

{ after /reloadsettings or /steamadmin: players now on the list become admins, players taken off it
  lose what this script gave them }
procedure RecheckSteamAdmins();
var
  i: Integer;
begin
  for i := 1 to TopSlot do
    if ActiveSlot[i] then
      if SteamId[i] <> '' then
      begin
        if AdSteams.IndexOf(SteamId[i]) >= 0 then
          GrantSteamAdmin(i)
        else if GrantedIp[i] <> '' then
        begin
          RevokeGrant(i);
          Log(PL[i].Name + ' is not in ' + AdSteamFile + ' any more: the admin rights this script gave were taken back.');
        end;
      end;
end;

{ ================================ extras (from the owner's older scripts) ================================ }

{ a text of [Assists], [MultiKill] ...: the tokens replaced (count and seconds are the same number) }
function ExText(S, Player, Other: string; Points, Pct, Count, Need: Integer): string;
begin
  Result := ReplaceAll(S, '{player}', Player);
  Result := ReplaceAll(Result, '{killer}', Player);
  Result := ReplaceAll(Result, '{victim}', Other);
  Result := ReplaceAll(Result, '{saved}', Other);
  Result := ReplaceAll(Result, '{points}', IntToStr(Points));
  Result := ReplaceAll(Result, '{pct}', IntToStr(Pct));
  Result := ReplaceAll(Result, '{count}', IntToStr(Count));
  Result := ReplaceAll(Result, '{seconds}', IntToStr(Count));
  Result := ReplaceAll(Result, '{need}', IntToStr(Need));
end;

{ kill points for a player (the scoreboard), never below 0 }
procedure AddPoints(ID, N: Integer);
var
  K: Integer;
begin
  if N = 0 then
    Exit;
  K := PL[ID].Kills + N;
  if K < 0 then
    K := 0;
  PL[ID].Kills := K;
end;

{ two players on opposite sides (every other player in the modes without teams) }
function Enemies(A, B: Integer): Boolean;
begin
  Result := A <> B;
  if Result then
    if TeamGame() then
      Result := TeamOf[A] <> TeamOf[B];
end;

{ [Assists]: whoever did at least MinPercent of the victim's health in his last fight (since his
  respawn or his last regeneration) gets an assist; PerPoint assists make Points kill points }
procedure AssistKill(K, V: Integer);
var
  s, Pct: Integer;
  T: string;
begin
  for s := 1 to TopSlot do
    if ActiveSlot[s] then
      if s <> V then
        if s <> K then
          if Enemies(s, V) then
          begin
            Pct := Round(Dealt[s][V] * 100 / MaxHealth);
            if Pct > 100 then
              Pct := 100;
            if Pct >= AsMinPct then
            begin
              AsCount[s] := AsCount[s] + 1;
              if (AsPerPoint > 0) and (AsCount[s] >= AsPerPoint) then
              begin
                AsCount[s] := 0;
                AddPoints(s, AsPoints);
                T := ExText(AsPointText, PL[s].Name, PL[V].Name, AsPoints, Pct, AsPerPoint, AsPerPoint);
              end
              else
                T := ExText(AsText, PL[s].Name, PL[V].Name, AsPoints, Pct, AsCount[s], AsPerPoint);
              if PL[s].Human then
                PL[s].BigText(AsLayer, T, AsTicks, AsColor, AsScale, AsX, AsY);
            end;
          end;
end;

{ [MultiKill]: kills of one player no more than WindowSeconds apart; the Nth of them brings the
  line ComboN (text|min-max points) }
procedure MultiKill(K, Tick: Integer);
var
  n, Pts: Integer;
begin
  if Tick - McLast[K] > McWindow then
    McCount[K] := 0;
  McLast[K] := Tick;
  McCount[K] := McCount[K] + 1;
  n := McCount[K];
  if (n < 2) or (n > 10) then
    Exit;
  if McText[n] = '' then
    Exit;
  Pts := McMin[n];
  if McMax[n] > McMin[n] then
    Pts := Random(McMin[n], McMax[n] + 1);
  AddPoints(K, Pts);
  SayAll(ExText(McText[n], PL[K].Name, '', Pts, 0, n, 0), McColor);
end;

{ [FirstBlood]: the first kill of the map }
procedure FirstBloodKill(K, V: Integer);
begin
  if FbDone then
    Exit;
  FbDone := True;
  AddPoints(K, FbPoints);
  SayAll(ExText(FbText, PL[K].Name, PL[V].Name, FbPoints, 0, 0, 0), FbColor);
  if FbPoints <> 0 then
    Say(K, ExText(FbPointsText, PL[K].Name, PL[V].Name, FbPoints, 0, 0, 0), FbColor);
end;

{ [Savior]: the victim had hit a team mate of the killer within WindowSeconds - that team mate was
  rescued }
procedure SaviorKill(K, V, Tick: Integer);
var
  Saved: Integer;
begin
  Saved := SvTarget[V];
  SvTarget[V] := 0;
  if (Saved < 1) or (Saved > 32) then
    Exit;
  if Tick - SvTick[V] > SvWindow then
    Exit;
  if Saved = K then
    Exit;
  if not ActiveSlot[Saved] then
    Exit;
  if not PL[Saved].Alive then
    Exit;
  if not TeamGame() then
    Exit;
  if TeamOf[Saved] <> TeamOf[K] then
    Exit;
  AddPoints(K, SvPoints);
  Say(Saved, ExText(SvSavedText, PL[K].Name, PL[Saved].Name, SvPoints, 0, 0, 0), SvColor);
  Say(K, ExText(SvText, PL[K].Name, PL[Saved].Name, SvPoints, 0, 0, 0), SvColor);
end;

{ [SelfKill]: a suicide costs Points kill points (not the kills of the server itself) }
procedure SelfKillPenalty(V: Integer);
begin
  if PL[V].Kills <= 0 then
    Exit;
  AddPoints(V, -SkPoints);
  Players.BigText(SkLayer, ExText(SkText, PL[V].Name, '', SkPoints, 0, 0, 0), SkTicks, SkColor, SkScale, SkX, SkY);
end;

{ [Posthumous]: the victim drops a live grenade where he died, with a chance of one in
  ChanceFactor - his kills (a good player more often); his own grenade, so its kills are his }
procedure PosthumousKill(V: Integer);
var
  Cd: Integer;
  P: TActivePlayer;
begin
  P := PL[V];
  if PhGround then
    if not P.OnGround then
      Exit;
  Cd := PhFactor - P.Kills;
  if Cd < 1 then
    Cd := 1;
  if Random(0, Cd) <> 0 then
  begin
    if PhNoText <> '' then
      Say(V, PhNoText, PhColor);
    Exit;
  end;
  Map.CreateBullet(P.X, P.Y - 30, 0, 0, PhPower, PhStyle, P);
  if PhText <> '' then
    Say(V, PhText, PhColor);
end;

{ [TimeToKill], once a second: when exactly AlivePlayers are alive a countdown starts; at 0 they all
  die (the server's own kill: no suicide penalty) }
procedure TimeToKillSecond(Tick: Integer);
var
  i, n: Integer;
begin
  n := 0;
  for i := 1 to TopSlot do
    if ActiveSlot[i] then
      if TeamOf[i] <> TEAM_SPECTATOR then
        if PL[i].Alive then
          n := n + 1;
  if n <> TkAlive then
  begin
    if TkLeft > 0 then
      Players.BigText(TkLayer, ' ', 1, ColorGood, 0.01, 0, 0);
    TkLeft := 0;
    Exit;
  end;
  if TkLeft = 0 then
    TkLeft := TkSeconds + 1;
  TkLeft := TkLeft - 1;
  if TkLeft > 0 then
  begin
    Players.BigText(TkLayer, ExText(TkText, '', '', 0, 0, TkLeft, 0), 120, TkColor, TkScale, TkX, TkY);
    Exit;
  end;
  Players.BigText(TkLayer, ' ', 1, ColorGood, 0.01, 0, 0);
  for i := 1 to TopSlot do
    if ActiveSlot[i] then
      if TeamOf[i] <> TEAM_SPECTATOR then
        if PL[i].Alive then
        begin
          ServerKill[i] := Tick;
          PL[i].Damage(i, 4000);
        end;
end;

{ [Medic], once a second. Mode = class: the medic of a team (!medic takes the job) heals the hurt
  team mates within Distance and gets a kill point for every PointEvery health he gave. Mode = call:
  a hurt player (or one next to a hurt team mate) calls the medic with !medic; he heals himself and
  those around him while anybody there is hurt, then the team waits CooldownSeconds. }
procedure MedicSecond();
var
  t, m, j: Integer;
  P, Q: TActivePlayer;
  Mx, My, H, Add, Cap, DX, DY: Single;
  Healed: Boolean;
begin
  Cap := MaxHealth;
  for t := 0 to 4 do
  begin
    if MdCool[t] > 0 then
    begin
      MdCool[t] := MdCool[t] - 1;
      if MdCool[t] = 0 then
        for j := 1 to TopSlot do
          if MdWants[j] then
            if TeamOf[j] = t then
            begin
              MdWants[j] := False;
              Say(j, 'The medic is there again (!medic).', MdColor);
            end;
    end;
    m := MdOf[t];
    if m < 1 then
      Continue;
    P := PL[m];
    if (not ActiveSlot[m]) or (TeamOf[m] <> t) then
    begin
      MdOf[t] := 0;
      Continue;
    end;
    if not P.Alive then
      Continue;
    Mx := P.X;
    My := P.Y;
    Healed := False;
    for j := 1 to TopSlot do
      if ActiveSlot[j] then
        if TeamOf[j] = t then
        begin
          Q := PL[j];
          if Q.Alive then
          begin
            DX := Q.X - Mx;
            DY := Q.Y - My;
          end;
          if Q.Alive then
            if DX * DX + DY * DY <= MdDist * MdDist then
            begin
              H := Q.Health;
              if H < Cap - 0.01 then
              begin
                Add := MdRate;
                if H + Add > Cap then
                  Add := Cap - H;
                Q.Health := H + Add;
                LastHealth[j] := H + Add;
                HudMark(j, False);
                Healed := True;
                if not MdCall then
                  if j <> m then
                  begin
                    MdGiven[t] := MdGiven[t] + Add;
                    if MdPointEvery > 0 then
                      if MdGiven[t] >= MdPointEvery then
                      begin
                        MdGiven[t] := 0;
                        AddPoints(m, 1);
                        Say(m, 'You got 1 point for healing.', MdColor);
                      end;
                  end;
              end;
            end;
        end;
    { a called medic leaves when nobody near him is hurt }
    if MdCall then
      if not Healed then
        MdOf[t] := 0;
  end;
end;

{ !medic }
procedure CmdMedic(ID: Integer);
var
  t, j: Integer;
  Hurt2: Boolean;
  X, Y, DX, DY: Single;
begin
  if not MdEnabled then
  begin
    Say(ID, 'There is no medic on this server.', ColorBad);
    Exit;
  end;
  t := TeamOf[ID];
  if (t < 0) or (t > 4) then
  begin
    Say(ID, 'Join a team first.', ColorBad);
    Exit;
  end;
  if not MdCall then
  begin
    if MdOf[t] = ID then
    begin
      MdOf[t] := 0;
      Say(ID, 'You are not the medic of your team any more.', MdColor);
      for j := 1 to TopSlot do
        if j <> ID then
          if ActiveSlot[j] then
            if TeamOf[j] = t then
              Say(j, 'Your team has no medic: !medic takes the job.', MdColor);
    end
    else if MdOf[t] = 0 then
    begin
      MdOf[t] := ID;
      MdGiven[t] := 0;
      Say(ID, 'You are the medic of your team: you heal the team mates near you and get points for it.', MdColor);
    end
    else
      Say(ID, 'The medic of your team is ' + PL[MdOf[t]].Name + '.', MdColor);
    Exit;
  end;
  { call mode }
  if MdOf[t] > 0 then
  begin
    Say(ID, 'The medic is healing at ' + PL[MdOf[t]].Name + ' now.', MdColor);
    Exit;
  end;
  if MdCool[t] > 0 then
  begin
    MdWants[ID] := True;
    Say(ID, 'The medic gathers supplies: wait ' + IntToStr(MdCool[t]) + ' seconds.', MdColor);
    Exit;
  end;
  Hurt2 := False;
  if PL[ID].Alive then
  begin
    X := PL[ID].X;
    Y := PL[ID].Y;
    for j := 1 to TopSlot do
      if ActiveSlot[j] then
        if TeamOf[j] = t then
          if PL[j].Alive then
            if PL[j].Health < MaxHealth - 0.01 then
            begin
              DX := PL[j].X - X;
              DY := PL[j].Y - Y;
              if DX * DX + DY * DY <= MdDist * MdDist then
                Hurt2 := True;
            end;
  end;
  if not Hurt2 then
  begin
    Say(ID, 'Nobody near you is hurt.', ColorBad);
    Exit;
  end;
  MdOf[t] := ID;
  MdCool[t] := MdCooldown;
  Say(ID, 'The medic is coming: he heals you and your team mates near you.', MdColor);
end;

{ [Reservation]: the last Slots slots are kept for the players of File (Steam ids or IPs; with
  AdminsToo those of Admins_Steam.txt too). Somebody else who takes one of them is kicked - once
  his Steam id is known (at the join or up to 8 seconds later). }
function ResReserved(ID: Integer): Boolean;
begin
  Result := False;
  if SteamId[ID] <> '' then
  begin
    if RsList.IndexOf(SteamId[ID]) >= 0 then
      Result := True;
    if RsAdmins then
      if AdSteams.IndexOf(SteamId[ID]) >= 0 then
        Result := True;
  end;
  if RsList.IndexOf(PL[ID].IP) >= 0 then
    Result := True;
end;

procedure ResCheck(ID: Integer; Final: Boolean);
begin
  RsWait[ID] := 0;
  if not RsEnabled then
    Exit;
  if not PL[ID].Human then
    Exit;
  if Game.NumPlayers <= Game.MaxPlayers - RsSlots then
    Exit;
  if ResReserved(ID) then
    Exit;
  { the Steam id may still come }
  if SteamId[ID] = '' then
    if not Final then
    begin
      RsWait[ID] := After(Game.TickCount, 480);
      Exit;
    end;
  Say(ID, ReplaceAll(RsText, '{slots}', IntToStr(RsSlots)), ColorBad);
  Log(PL[ID].Name + ' kicked: a reserved slot ([Reservation])');
  ScheduleBan(ID, 0, '');
end;

procedure ResSecond(Tick: Integer);
var
  i: Integer;
begin
  for i := 1 to TopSlot do
    if RsWait[i] > 0 then
      if Tick >= RsWait[i] then
        if ActiveSlot[i] then
          ResCheck(i, True)
        else
          RsWait[i] := 0;
end;

{ ================================ logger ================================ }

{ [Logger]: one file a day in Folder (yyyy-mm-dd.txt), written by the library's thread; a watched
  player (Steam id, IP or name in WatchFile) also gets his own file in Folder/watched. A password
  typed after /adminlog is never written. }
procedure LogLine(ID: Integer; Text: string);
var
  T, F: string;
begin
  if not LgEnabled then
    Exit;
  if not BeOk then
    Exit;
  T := FormatDateTime('hh:nn:ss', Now) + '  ' + Text;
  F := LgFolder + FormatDateTime('yyyy-mm-dd', Now) + '.txt';
  BE_Log(PChar(F), PChar(T));
  if (ID >= 1) and (ID <= 32) then
    if LgWatched[ID] then
    begin
      F := LgFolder + 'watched/' + LgWatchName[ID] + '.txt';
      T := FormatDateTime('yyyy-mm-dd ', Now) + T;
      BE_Log(PChar(F), PChar(T));
    end;
end;

{ a file name out of a player name: letters, digits, - and _ stay }
function SafeName(S: string): string;
var
  i: Integer;
  C: string;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    C := Copy(S, i, 1);
    if ((C >= 'a') and (C <= 'z')) or ((C >= 'A') and (C <= 'Z')) or ((C >= '0') and (C <= '9')) or (C = '-') or
      (C = '_') then
      Result := Result + C
    else
      Result := Result + '_';
  end;
  if Result = '' then
    Result := 'player';
end;

{ is the player watched (WatchFile): by Steam id, IP or name }
procedure LogWatchCheck(ID: Integer);
begin
  LgWatched[ID] := False;
  if not LgEnabled then
    Exit;
  if not PL[ID].Human then
    Exit;
  if SteamId[ID] <> '' then
    if LgWatch.IndexOf(SteamId[ID]) >= 0 then
      LgWatched[ID] := True;
  if LgWatch.IndexOf(PL[ID].IP) >= 0 then
    LgWatched[ID] := True;
  if LgWatch.IndexOf(LowerCase(PL[ID].Name)) >= 0 then
    LgWatched[ID] := True;
  if SteamId[ID] <> '' then
    LgWatchName[ID] := SteamId[ID]
  else
    LgWatchName[ID] := SafeName(PL[ID].Name);
end;

{ a command as the log shows it: the password of /adminlog is left out }
function LogCommand(Text: string): string;
var
  W: string;
begin
  Result := Trim(Text);
  W := LowerCase(FirstWord(Result));
  if (W = '/adminlog') or (W = 'adminlog') or (W = '/password') or (W = '/pass') then
    Result := FirstWord(Result) + ' ***';
end;

function TeamName(T: Integer): string;
begin
  case T of
    0: Result := 'the game';
    1: Result := 'Alpha';
    2: Result := 'Bravo';
    3: Result := 'Charlie';
    4: Result := 'Delta';
    5: Result := 'the spectators';
  else
    Result := 'team ' + IntToStr(T);
  end;
end;

{ ================================ commands ================================ }

procedure ShowList(ID: Integer; List: TStringList; Colors: Boolean; Color: Longint; Pad: Integer; ToAll: Boolean);
var
  i, p: Integer;
  S: string;
  C: Longint;
begin
  for i := 0 to List.Count - 1 do
  begin
    S := List[i];
    C := Color;
    if Colors then
    begin
      p := Pos(#9, S);
      if p > 0 then
      begin
        C := StrToIntDef(Trim(Copy(S, 1, p - 1)), Color);
        S := Copy(S, p + 1, Length(S));
      end;
    end;
    SayTo(ID, ToAll, PadTo(S, Pad), C);
  end;
end;

function TargetOf(ID: Integer; Args: string): Integer;
begin
  if Trim(Args) = '' then
    Result := ID
  else
    Result := FindPlayer(Args);
end;

procedure CmdRatio(ID: Integer; Args: string);
var
  T, K, D: Integer;
  P: TActivePlayer;
  R: Single;
begin
  T := TargetOf(ID, Args);
  if T < 1 then
  begin
    Say(ID, 'Player not found (' + Args + ')', ColorBad);
    Exit;
  end;
  P := PL[T];
  if P.Team = TEAM_SPECTATOR then
  begin
    SayTo(ID, RaPublic, P.Name + ' - is spectating', ColorBad);
    Exit;
  end;
  K := P.Kills;
  D := P.Deaths;
  if D = 0 then
    SayTo(ID, RaPublic, P.Name + ' - K/D is incalculable (' + IntToStr(K) + '/0) with ' + IntToStr(P.Flags) + ' caps.',
      ColorBad)
  else
  begin
    R := K;
    R := R / D;
    SayTo(ID, RaPublic, P.Name + ' - K/D is ' + FloatStr(R, 2) + ' (' + IntToStr(K) + '/' + IntToStr(D) + ') with ' +
      IntToStr(P.Flags) + ' caps.', ColorGood);
  end;
end;

procedure CmdPing(ID: Integer; Args: string);
var
  T: Integer;
begin
  T := TargetOf(ID, Args);
  if T < 1 then
  begin
    Say(ID, 'Player not found (' + Args + ')', ColorBad);
    Exit;
  end;
  SayTo(ID, PiPublic, PL[T].Name + '''s ping: ' + IntToStr(PL[T].Ping), ColorGood);
end;

procedure CmdTrack(ID: Integer; Args: string);
var
  T, Ping: Integer;
begin
  T := TargetOf(ID, Args);
  if T < 1 then
  begin
    Say(ID, 'Player not found (' + Args + ')', ColorBad);
    Exit;
  end;
  if TrackLeft[T] > 0 then
  begin
    Say(ID, PL[T].Name + ' is already tracking.', ColorBad);
    Exit;
  end;
  Ping := PL[T].Ping;
  TrackLeft[T] := PtSeconds;
  TrackSum[T] := Ping;
  TrackMax[T] := Ping;
  TrackCount[T] := 1;
  TrackAsker[T] := ID;
  Say(ID, 'Tracking ' + PL[T].Name + ' ...', ColorGood);
end;

procedure CmdWhois(ID: Integer);
begin
  if WhoisLeft > 0 then
  begin
    SayAll('Already counting connected admins - please wait...', ColorBad);
    Exit;
  end;
  SayAll('Counting connected admins...', ColorGood);
  SayAll(' ', ColorGood);
  SayAll(' ', ColorGood);
  TcpAdmins.Clear;
  WhoisLeft := WaSeconds;
  { TCP admin programs answer this console line with "[x] name" (OnTCPMessage) }
  if WaTcp then
    WriteLn('/clientlist (127.0.0.1)');
end;

procedure WhoisReport();
var
  i: Integer;
  Names: TStringList;
begin
  if WaTcp then
  begin
    if TcpAdmins.Count = 0 then
      SayAll('There''s no TCP admin connected.', ColorBad)
    else
    begin
      if TcpAdmins.Count = 1 then
        SayAll('There''s 1 TCP admin connected:', ColorGood)
      else
        SayAll('There''re ' + IntToStr(TcpAdmins.Count) + ' TCP admins connected:', ColorGood);
      for i := 0 to TcpAdmins.Count - 1 do
        SayAll(TcpAdmins[i], ColorGood);
    end;
    TcpAdmins.Clear;
  end;
  if WaInGame then
  begin
    Names := File.CreateStringList();
    for i := 1 to TopSlot do
      if PL[i].Active then
        if PL[i].IsAdmin then
          Names.Add(PL[i].Name);
    if Names.Count = 0 then
      SayAll('There''s no In-Game admin connected.', ColorBad)
    else
    begin
      if Names.Count = 1 then
        SayAll('There''s 1 In-Game admin connected:', ColorGood)
      else
        SayAll('There''re ' + IntToStr(Names.Count) + ' In-Game admins connected:', ColorGood);
      for i := 0 to Names.Count - 1 do
        SayAll(Names[i], ColorGood);
    end;
    Names.Free;
  end;
end;

procedure CmdCallAdmin(ID: Integer; Args: string);
var
  Tick: Integer;
  S: string;
begin
  Tick := Game.TickCount;
  if CallLast[ID] <> 0 then
    if Tick - CallLast[ID] < CaCooldownTicks then
    begin
      Say(ID, 'You called the admins a moment ago - please wait.', ColorBad);
      Exit;
    end;
  CallLast[ID] := Tick;
  S := PL[ID].Name + ' (id ' + IntToStr(ID) + ') calls an admin';
  if Args <> '' then
    S := S + ': ' + Args
  else
    S := S + '.';
  WriteLn(TAG + S);
  if SayAdmins(S, ColorBad) > 0 then
    Say(ID, 'The admins in the game have been told.', ColorGood)
  else
    Say(ID, 'No admin is in the game now; the message went to the server console.', ColorGood);
end;

procedure CmdJoin(ID: Integer; Team: Integer);
var
  P: TActivePlayer;
begin
  P := PL[ID];
  if Team < 0 then
  begin
    if P.Team <> TEAM_SPECTATOR then
    begin
      Say(ID, 'You''re already in the game.', ColorBad);
      Exit;
    end;
    Team := SmallerTeam();
  end
  else if P.Team = Team then
  begin
    Say(ID, 'You''re already in this team.', ColorBad);
    Exit;
  end;
  P.ChangeTeam(Team, TJoinSilent);
  Say(ID, 'You joined the game.', ColorGood);
end;

procedure CmdSpec(ID: Integer);
var
  P: TActivePlayer;
begin
  P := PL[ID];
  if P.Team = TEAM_SPECTATOR then
  begin
    Say(ID, 'You''re already on the observer team.', ColorBad);
    Exit;
  end;
  if TeMaxSpec > 0 then
    if Game.Spectators >= TeMaxSpec then
    begin
      Say(ID, 'Spectators are full!', ColorBad);
      Exit;
    end;
  P.ChangeTeam(TEAM_SPECTATOR, TJoinSilent);
  Say(ID, 'You joined the observer team.', ColorGood);
end;

procedure CmdMapList(ID: Integer);
var
  i, n, W, Cols: Integer;
  Line, Name: string;
  L: TMapsList;
begin
  L := Game.MapsList;
  n := L.MapsCount;
  if n = 0 then
  begin
    Say(ID, 'The maps list is empty.', ColorBad);
    Exit;
  end;
  W := 0;
  for i := 0 to n - 1 do
    if Length(L.Map[i]) > W then
      W := Length(L.Map[i]);
  W := W + 3;
  Cols := MlColumns;
  while (Cols > 1) and (Cols * W > 100) do
    Cols := Cols - 1;
  Say(ID, 'Maps list (' + IntToStr(n) + '):', MlColor);
  Line := '';
  for i := 0 to n - 1 do
  begin
    Name := L.Map[i];
    if i < n - 1 then
      while Length(Name) < W do
        Name := Name + ' ';
    Line := Line + Name;
    if (i + 1) mod Cols = 0 then
    begin
      Say(ID, PadTo(Line, MlPad), MlColor);
      Line := '';
    end;
  end;
  if Line <> '' then
    Say(ID, PadTo(Line, MlPad), MlColor);
end;

procedure CmdInfo(ID: Integer);
var
  i, Left: Integer;
  S: string;
begin
  Left := Game.TimeLeft;
  if Left < 0 then
    Left := 0;
  for i := 1 to InCount do
  begin
    S := InText[i];
    if Pos('{', S) > 0 then
    begin
      S := ReplaceAll(S, '{server}', Game.ServerName);
      S := ReplaceAll(S, '{version}', Game.ServerVersion);
      S := ReplaceAll(S, '{address}', InAddress);
      S := ReplaceAll(S, '{port}', IntToStr(Game.ServerPort));
      S := ReplaceAll(S, '{style}', InStyle);
      S := ReplaceAll(S, '{prevmap}', PrevMap);
      S := ReplaceAll(S, '{map}', Game.CurrentMap);
      S := ReplaceAll(S, '{nextmap}', Game.NextMap);
      S := ReplaceAll(S, '{ff}', iif(Game.FriendlyFire, 'True', 'False'));
      S := ReplaceAll(S, '{realistic}', iif(Game.Realistic, 'True', 'False'));
      S := ReplaceAll(S, '{survival}', iif(Game.Survival, 'True', 'False'));
      S := ReplaceAll(S, '{advance}', iif(Game.Advance, 'True', 'False'));
      S := ReplaceAll(S, '{timelimit}', IntToStr(Game.TimeLimit div 3600) + 'm');
      S := ReplaceAll(S, '{timeleft}', IntToStr(Left div 60) + 'min ' + IntToStr(Left mod 60) + 's');
    end;
    if S = '' then
      S := ' ';
    Say(ID, PadTo(S, InPad), InColor[i]);
  end;
end;

{ number + m, h, d, mon or y -> minutes; -1 when it cannot be read }
function BanMinutes(S: string): Integer;
var
  Mult, N: Integer;
  Num: string;
begin
  Result := -1;
  S := LowerCase(Trim(S));
  Mult := 0;
  Num := '';
  if Length(S) > 3 then
    if Copy(S, Length(S) - 2, 3) = 'mon' then
    begin
      Mult := 43200;
      Num := Copy(S, 1, Length(S) - 3);
    end;
  if Mult = 0 then
    if Length(S) > 1 then
    begin
      Num := Copy(S, 1, Length(S) - 1);
      case Copy(S, Length(S), 1) of
        'm': Mult := 1;
        'h': Mult := 60;
        'd': Mult := 1440;
        'y': Mult := 525600;
      end;
    end;
  if Mult = 0 then
    Exit;
  N := StrToIntDef(Num, -1);
  if N < 1 then
    Exit;
  if N > BAN_LIMIT div Mult then
    Result := BAN_LIMIT + 1
  else
    Result := N * Mult;
end;

{ the limit of [Admin] MaxBanMinutes: shortened or refused }
function CheckBanTime(ID: Integer; Minutes: Integer): Integer;
begin
  Result := Minutes;
  if AdMaxBan > 0 then
    if Minutes > AdMaxBan then
    begin
      if AdShorten then
      begin
        Result := AdMaxBan;
        Say(ID, 'The ban time is too long. We set it to ' + IntToStr(AdMaxBan) + ' minutes.', ColorBad);
      end
      else
      begin
        Result := -1;
        Say(ID, 'The ban time is too long. The operation was aborted!', ColorBad);
      end;
    end;
  if Result > BAN_LIMIT then
    Result := BAN_LIMIT;
end;

function AdminName(ID: Integer): string;
begin
  if ID = 0 then
    Result := 'Server'
  else
    Result := PL[ID].Name;
end;

procedure CmdBan(ID: Integer; Args: string);
var
  T, Minutes, i: Integer;
  S, Reason: string;
begin
  S := Args;
  T := StrToIntDef(FirstWord(S), 0);
  S := AfterFirstWord(S);
  Minutes := BanMinutes(FirstWord(S));
  Reason := AfterFirstWord(S);
  if (T < 1) or (T > 32) or (Minutes < 1) then
  begin
    Say(ID, 'Use correctly: /banr <Player_ID> <Ban_Time> <Reason>', ColorBad);
    Say(ID, 'Ban time format, example: 262800m or 4380h or 182d or 6mon or 1y', ColorBad);
    Exit;
  end;
  if not PL[T].Active then
  begin
    Say(ID, 'There is no such player on the server.', ColorBad);
    Exit;
  end;
  if Reason = '' then
  begin
    Say(ID, 'You probably didn''t give a reason.', ColorBad);
    Exit;
  end;
  Minutes := CheckBanTime(ID, Minutes);
  if Minutes < 1 then
    Exit;
  SayAll('Player ' + PL[T].Name + ' has been banned for ' + IntToStr(Minutes) + ' minutes! By: ' + AdminName(ID),
    ColorGood);
  SayAll('Reason is: ' + Reason, ColorGood);
  WriteLn(TAG + 'Player ' + PL[T].Name + ' has been banned for ' + IntToStr(Minutes) + ' minutes! By: ' +
    AdminName(ID) + ', reason: ' + Reason);
  { six empty lines push the ban message into the middle of the victim's console; the ban follows
    when they are out }
  for i := 1 to 6 do
    Say(T, ' ', ColorGood);
  for i := 1 to 3 do
    Say(T, 'You`ve been banned as "' + Reason + '", on: ' + IntToStr(Minutes) + ' minutes! By: ' +
      AdminName(ID), ColorBad);
  ScheduleBan(T, Minutes, Reason);
end;

{ /banhwr <time> <hwid> <reason> and /banipr <time> <ip> <reason> }
procedure CmdBanList(ID: Integer; Args: string; Hw: Boolean);
var
  Minutes, i: Integer;
  S, Target, Reason: string;
  Ok: Boolean;
begin
  S := Args;
  Minutes := BanMinutes(FirstWord(S));
  S := AfterFirstWord(S);
  Target := FirstWord(S);
  Reason := AfterFirstWord(S);
  if Hw then
    Ok := ExecRegExpr('^[A-Fa-f0-9]{11}$', Target)
  else
    Ok := ExecRegExpr('^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$', Target);
  if (Minutes < 1) or (not Ok) or (Reason = '') then
  begin
    if Hw then
      Say(ID, 'Bad command parameters. Try: /banhwr <Time number + m|h|d|y|mon> <HWID> <reason>.', ColorBad)
    else
      Say(ID, 'Bad command parameters. Try: /banipr <Time number + m|h|d|y|mon> <IP> <Reason>.', ColorBad);
    Exit;
  end;
  Minutes := CheckBanTime(ID, Minutes);
  if Minutes < 1 then
    Exit;
  { the ban lists count in ticks: 3600 a minute }
  if Hw then
    Game.BanLists.AddHWBan(UpperCase(Target), Reason, Minutes * 3600)
  else
    Game.BanLists.AddIPBan(Target, Reason, Minutes * 3600);
  for i := 1 to 6 do
    SayAll(' ', ColorGood);
  if Hw then
    SayAll('HWID ' + Target + ' banned as "' + Reason + '", on: ' + IntToStr(Minutes) + ' minutes! By: ' + AdminName(ID),
      ColorBad)
  else
    SayAll('IP ' + Target + ' banned as "' + Reason + '", on: ' + IntToStr(Minutes) + ' minutes! By: ' + AdminName(ID),
      ColorBad);
  WriteLn(TAG + iif(Hw, 'HWID ', 'IP ') + Target + ' banned for ' + IntToStr(Minutes) + ' minutes by ' + AdminName(ID) +
    ': ' + Reason);
end;

{ /steamadmin - the list; /steamadmin add|del <player or Steam id>. Only the server console, a TCP
  admin or a Steam admin may use it: an admin by remote.txt cannot make himself a Steam admin. }
procedure CmdSteamAdmin(ID: Integer; Args: string; Console: Boolean);
var
  W, Rest, N, Name: string;
  T, i, Found: Integer;
begin
  if not Console then
    if AdSteams.IndexOf(SteamId[ID]) < 0 then
    begin
      Say(ID, 'Only a Steam admin (' + AdSteamFile + ') or the server console can change the Steam admins.',
        ColorBad);
      Exit;
    end;
  W := LowerCase(FirstWord(Args));
  Rest := AfterFirstWord(Args);
  if (W = 'add') or (W = 'del') or (W = 'remove') then
  begin
    if Rest = '' then
    begin
      Say(ID, 'Use: /steamadmin add|del <player or Steam id>', ColorBad);
      Exit;
    end;
    Name := '';
    T := FindPlayer(Rest);
    if T >= 1 then
    begin
      N := SteamId[T];
      Name := PL[T].Name;
      if N = '' then
      begin
        Say(ID, Name + ' has no Steam account confirmed by Steam.', ColorBad);
        Exit;
      end;
    end
    else
    begin
      N := NormalizeSteam(Rest);
      if N = '' then
      begin
        Say(ID, 'Neither a player on the server nor a Steam id: ' + Rest, ColorBad);
        Exit;
      end;
    end;
    if W = 'add' then
    begin
      if AdSteams.IndexOf(N) >= 0 then
      begin
        Say(ID, N + ' is a Steam admin already.', ColorBad);
        Exit;
      end;
      if Name <> '' then
        AdSteamRaw.Add(N + ' // ' + Name)
      else
        AdSteamRaw.Add(N);
      AdSteams.Add(N);
      SaveAdminSteams();
      Say(ID, N + ' added to ' + AdSteamFile + '.', ColorGood);
      Log(Trim(N + ' ' + Name) + ' added to ' + AdSteamFile + ' by ' + AdminName(ID) + '.');
    end
    else
    begin
      Found := 0;
      for i := AdSteamRaw.Count - 1 downto 0 do
        if SteamOfLine(AdSteamRaw[i]) = N then
        begin
          AdSteamRaw.Delete(i);
          Found := Found + 1;
        end;
      i := AdSteams.IndexOf(N);
      if i >= 0 then
        AdSteams.Delete(i);
      if Found = 0 then
      begin
        Say(ID, N + ' is not in ' + AdSteamFile + '.', ColorBad);
        Exit;
      end;
      SaveAdminSteams();
      Say(ID, N + ' removed from ' + AdSteamFile + '.', ColorGood);
      Log(Trim(N + ' ' + Name) + ' removed from ' + AdSteamFile + ' by ' + AdminName(ID) + '.');
    end;
    RecheckSteamAdmins();
    Exit;
  end;
  if AdSteams.Count = 0 then
    Say(ID, 'There are no Steam admins (' + AdSteamFile + ').', ColorBad)
  else
  begin
    Say(ID, 'Steam admins (' + AdSteamFile + '):', ColorGood);
    for i := 0 to AdSteamRaw.Count - 1 do
      if SteamOfLine(AdSteamRaw[i]) <> '' then
        Say(ID, Trim(AdSteamRaw[i]), ColorGood);
  end;
  Say(ID, 'Change it: /steamadmin add|del <player or Steam id>', ColorGood);
end;

procedure ShuffleMapsList();
var
  L: TStringList;
  i, j: Integer;
  S: string;
begin
  if not File.Exists(MapsFile) then
  begin
    Log('maps list not found: ' + MapsFile);
    Exit;
  end;
  L := File.CreateStringListFromFile(MapsFile);
  for i := L.Count - 1 downto 0 do
    if Trim(L[i]) = '' then
      L.Delete(i);
  for i := L.Count - 1 downto 1 do
  begin
    j := Random(0, i + 1);
    S := L[i];
    L[i] := L[j];
    L[j] := S;
  end;
  try
    L.SaveToFile(MapsFile);
    Game.LoadList(MapsFile);
  except
    Log('cannot write ' + MapsFile);
  end;
  L.Free;
end;

procedure CmdStatus(ID: Integer);
var
  Secs, i, k, Kits, Spawns, Shown, Pairs, Seen: Integer;
  Lib: string;
begin
  Secs := (Game.TickCount - StatSince) div 60;
  if Secs < 1 then
    Secs := 1;
  Kits := 0;
  for i := 1 to MAX_OBJECT_ID do
    if OB[i].Active then
    begin
      k := OB[i].Style;
      if (k >= 0) and (k <= 31) then
        if KitObj[k] then
          Kits := Kits + 1;
    end;
  Spawns := 0;
  for i := 1 to MAX_SPAWN_ID do
    if SP[i].Active then
    begin
      k := SP[i].Style;
      if (k >= 0) and (k <= 31) then
        if KitSpawn[k] then
          Spawns := Spawns + 1;
    end;
  Shown := 0;
  for i := 1 to TopSlot do
    if HudShown[i] then
      Shown := Shown + 1;
  Say(ID, 'Basic-Extended ' + VERSION + ' - in the last ' + IntToStr(Secs) + ' s:', ColorGood);
  Say(ID, 'health texts ' + IntToStr(StatHud) + ' (shown to ' + IntToStr(Shown) + ' players now), damage numbers ' +
    IntToStr(StatDmg) + ', overlay texts ' + IntToStr(StatOvl) + ', heals ' + IntToStr(StatHeals), ColorGood);
  Say(ID, 'bullet scans ' + IntToStr(StatScans) + ' (bullets looked at ' + IntToStr(StatBullets) +
    '), players waiting for regeneration ' + IntToStr(HurtCount), ColorGood);
  Say(ID, 'kits removed ' + IntToStr(StatKits) + ', removable kits on the map ' + IntToStr(Kits) +
    ', their spawn points still active ' + IntToStr(Spawns), ColorGood);
  Say(ID, 'highest player slot ' + IntToStr(TopSlot) + ', radar users ' + IntToStr(OvlCount) + ', Steam admins ' +
    IntToStr(AdSteams.Count) + ', line of sight ' + BoolText(SightActive()) + ' (numbers not shown: ' +
    IntToStr(StatHid) + ')', ColorGood);
  { how many living players could see each other now by realistic mode's rule }
  Pairs := 0;
  Seen := 0;
  for i := 1 to TopSlot do
    if PL[i].Active then
      if PL[i].Alive then
        for k := 1 to TopSlot do
          if k <> i then
            if PL[k].Active then
              if PL[k].Alive then
              begin
                Pairs := Pairs + 1;
                if CanSee(i, k) then
                  Seen := Seen + 1;
              end;
  Say(ID, 'living players who could see each other now (realistic rule): ' + IntToStr(Seen) + ' of ' +
    IntToStr(Pairs) + ' pairs', ColorGood);
  if BeOk then
  begin
    Lib := BE_Status();
    Say(ID, 'library: ' + Lib, ColorGood);
  end
  else
    Say(ID, 'library: not running (the players'' choices are not kept, the logger does not write)', ColorBad);
  Say(ID, 'vision rays ' + IntToStr(StatRays) + ', players moved to the spectators (AFK) ' + IntToStr(StatAfk) +
    ', teleport on for ' + IntToStr(TpCount) + ', low health now ' + IntToStr(LowCount), ColorGood);
  StatHud := 0;
  StatDmg := 0;
  StatOvl := 0;
  StatHeals := 0;
  StatScans := 0;
  StatBullets := 0;
  StatKits := 0;
  StatHid := 0;
  StatRays := 0;
  StatAfk := 0;
  StatSince := Game.TickCount;
end;

{ /be_bench: how long the heavier parts take on this machine (each is run 1000 times in one tick,
  so the server stands still for a moment - not for a full server) }
procedure CmdBench(ID: Integer);
var
  i, k, Tick, Waiting, Top: Integer;
  T0: TDateTime;
  Ms: Extended;
  H: Single;
  SaveHurt: array[1..32] of Boolean;
  SaveSupp: array[1..32] of Integer;
begin
  Tick := Game.TickCount;
  Waiting := 0;
  for k := 1 to 32 do
  begin
    SaveHurt[k] := Hurt[k];
    SaveSupp[k] := LastSupp[k];
    Hurt[k] := False;
    if PL[k].Active then
      if PL[k].Alive then
      begin
        Hurt[k] := True;
        Waiting := Waiting + 1;
      end;
  end;
  Top := ScanTop;
  T0 := Now();
  for i := 1 to 1000 do
    SuppressionScan(Tick);
  Ms := (Now() - T0) * 86400000;
  for k := 1 to 32 do
  begin
    Hurt[k] := SaveHurt[k];
    LastSupp[k] := SaveSupp[k];
  end;
  ScanTop := Top;
  Say(ID, 'bullet scan, ' + IntToStr(Waiting) + ' players waiting, slots up to ' + IntToStr(Top) + ': ' +
    FloatStr(Ms, 1) + ' us per scan', ColorGood);
  T0 := Now();
  for i := 1 to 1000 do
    KitSweep();
  Ms := (Now() - T0) * 86400000;
  Say(ID, 'kit sweep (90 objects): ' + FloatStr(Ms, 1) + ' us per sweep', ColorGood);
  T0 := Now();
  for i := 1 to 1000 do
    for k := 1 to 32 do
      H := PL[k].Health;
  Ms := (Now() - T0) * 86400000;
  Say(ID, 'reading PL[i].Health: ' + FloatStr(Ms / 32, 3) + ' us per read', ColorGood);
end;

{ [CommandList] Source = auto: the player commands switched on in this script (the first word of
  each) in columns, then the Extra lines (the help commands of the other scripts). Built when the
  settings are read. }
procedure BuildCommandList();
var
  Id, k, i, W, Cols: Integer;
  Words: TStringList;
  S, Line, Cell, T: string;
  C: Longint;
begin
  ClAutoLines.Clear;
  Words := File.CreateStringList();
  for Id := 1 to C_FIRST_ADMIN - 1 do
  begin
    if Id = C_RADAR then
      if not (OvlEnabled and OvlPublic) then
        Continue;
    S := '';
    for k := 0 to ChatWords.Count - 1 do
      if S = '' then
        if ChatIds[k] = Id then
        begin
          S := ChatWords[k];
          if S[1] <> '?' then
            S := '!' + S;
        end;
    for k := 0 to SlashWords.Count - 1 do
      if S = '' then
        if SlashIds[k] = Id then
          S := '/' + SlashWords[k];
    if S <> '' then
      Words.Add(S);
  end;
  W := 0;
  for i := 0 to Words.Count - 1 do
    if Length(Words[i]) > W then
      W := Length(Words[i]);
  W := W + 3;
  Cols := 72 div W;
  if Cols < 1 then
    Cols := 1;
  if Cols > 8 then
    Cols := 8;
  ClAutoLines.Add(IntToStr(ClColor) + #9 + 'Commands:');
  Line := '';
  for i := 0 to Words.Count - 1 do
  begin
    Cell := Words[i];
    if (i + 1) mod Cols <> 0 then
      if i < Words.Count - 1 then
        while Length(Cell) < W do
          Cell := Cell + ' ';
    Line := Line + Cell;
    if (i + 1) mod Cols = 0 then
    begin
      ClAutoLines.Add(IntToStr(ClColor) + #9 + Line);
      Line := '';
    end;
  end;
  if Line <> '' then
    ClAutoLines.Add(IntToStr(ClColor) + #9 + Line);
  for i := 1 to ClExtraCount do
  begin
    SplitLine(ClExtra[i], ClColor, T, C);
    ClAutoLines.Add(IntToStr(C) + #9 + T);
  end;
  Words.Free;
end;

procedure LoadAll();
begin
  LoadSettings();
  BuildCommandList();
  if RegEnabled then
    if not HudEnabled then
      Log('regeneration runs without the health display');
end;

procedure CmdHp(ID: Integer; Args: string);
var
  W, Rest: string;
  N: Integer;
  V: Single;
  Ok: Boolean;
begin
  W := LowerCase(FirstWord(Args));
  Rest := AfterFirstWord(Args);
  if not HudEnabled then
  begin
    Say(ID, 'The health display is switched off on this server.', ColorBad);
    Exit;
  end;
  if W = '' then
  begin
    if HudIsOn(ID) then
      HudPOn[ID] := PREF_OFF
    else
      HudPOn[ID] := PREF_ON;
    if HudIsOn(ID) = HudDefaultOn then
      HudPOn[ID] := PREF_DEFAULT;
    Say(ID, 'Health display ' + BoolText(HudIsOn(ID)) + '. More: !hp help', ColorGood);
  end
  else if (W = 'on') or (W = 'off') then
  begin
    if W = 'on' then
      HudPOn[ID] := PREF_ON
    else
      HudPOn[ID] := PREF_OFF;
    if HudIsOn(ID) = HudDefaultOn then
      HudPOn[ID] := PREF_DEFAULT;
    Say(ID, 'Health display ' + BoolText(HudIsOn(ID)) + '.', ColorGood);
  end
  else if W = 'edit' then
  begin
    EditorStart(ID, ED_HUD);
    Exit;
  end
  else if (W = 'done') or (W = 'save') then
  begin
    if EdOn[ID] then
      EditorStop(ID, True)
    else
      Say(ID, 'The editor is not open (!hp edit).', ColorBad);
    Exit;
  end
  else if W = 'reset' then
  begin
    EditorStop(ID, False);
    HudPOn[ID] := PREF_DEFAULT;
    HudPX[ID] := -1;
    HudPY[ID] := -1;
    HudPScale[ID] := 0;
    HudPStyle[ID] := 0;
    Say(ID, 'Health display: the server settings again.', ColorGood);
  end
  else if W = 'style' then
  begin
    N := StrToIntDef(Rest, 0);
    if (N < 1) or (N > STYLE_COUNT) then
    begin
      Say(ID, 'Styles 1-' + IntToStr(STYLE_COUNT) + ':', ColorGood);
      for N := 1 to STYLE_COUNT do
        Say(ID, IntToStr(N) + ': ' + HudStyleText[N], ColorGood);
      Exit;
    end;
    HudPStyle[ID] := N;
    if HudPStyle[ID] = HudDefStyle then
      HudPStyle[ID] := 0;
    if not HudIsOn(ID) then
      HudPOn[ID] := PREF_ON;
    Say(ID, 'Health display style ' + IntToStr(N) + '.', ColorGood);
  end
  else if W = 'size' then
  begin
    V := ParseFloat(Rest, Ok);
    if not Ok then
    begin
      Say(ID, 'Use: !hp size <0.005-0.5> (the server default is ' + FloatStr(HudDefScale, 4) + ')', ColorBad);
      Exit;
    end;
    if V < 0.005 then
      V := 0.005;
    if V > 0.5 then
      V := 0.5;
    HudPScale[ID] := V;
    Say(ID, 'Health display size ' + FloatStr(V, 4) + '.', ColorGood);
  end
  else if (W = 'pos') or (W = 'position') then
  begin
    N := StrToIntDef(FirstWord(Rest), -1);
    V := StrToIntDef(AfterFirstWord(Rest), -1);
    if (N < 0) or (V < 0) or (N > 854) or (V > 480) then
    begin
      Say(ID, 'Use: !hp pos <x 0-854> <y 0-480> (keep x below 600 to be seen on every screen)', ColorBad);
      Exit;
    end;
    HudPX[ID] := N;
    HudPY[ID] := Round(V);
    Say(ID, 'Health display position ' + IntToStr(N) + ' ' + IntToStr(Round(V)) + '.', ColorGood);
  end
  else
  begin
    Say(ID, '!hp - health display on/off; !hp on|off; !hp style <1-' + IntToStr(STYLE_COUNT) + '>; !hp size <n>;',
      ColorGood);
    Say(ID, '!hp pos <x> <y>; !hp edit - move it with the keys; !hp reset - the server settings', ColorGood);
    Exit;
  end;
  PrefsSave(ID);
  HudMark(ID, True);
end;

procedure CmdDmg(ID: Integer);
begin
  if not DmgEnabled then
  begin
    Say(ID, 'Damage numbers are switched off on this server.', ColorBad);
    Exit;
  end;
  if DmgIsOn(ID) then
    DmgPOn[ID] := PREF_OFF
  else
    DmgPOn[ID] := PREF_ON;
  if DmgIsOn(ID) = DmgDefaultOn then
    DmgPOn[ID] := PREF_DEFAULT;
  PrefsSave(ID);
  Say(ID, 'Damage numbers ' + BoolText(DmgIsOn(ID)) + '.', ColorGood);
end;

{ !radar (players, when the radar is public) and /radar or /overlay (SteamIds users and admins):
  on/off, mode, tick, zoom, show, edit, done, pos, size, reset, help. Cmd is the word shown in the
  answers. }
procedure CmdRadar(ID: Integer; Args, Cmd: string);
var
  W, Rest, Modes: string;
  N, M, X, Y: Integer;
  V: Single;
  Ok, NewOn, DefOn: Boolean;
begin
  if not OvlEnabled then
  begin
    Say(ID, 'The radar is switched off on this server.', ColorBad);
    Exit;
  end;
  if not RadarMay(ID) then
  begin
    if Cmd = '!radar' then
      Say(ID, 'The radar is not public on this server.', ColorBad)
    else
      Say(ID, 'The radar is only for the Steam ids in [Radar] SteamIds (or for everybody with Public = 1).',
        ColorBad);
    Exit;
  end;
  W := LowerCase(FirstWord(Args));
  Rest := AfterFirstWord(Args);
  { shortcuts: !radar circle = !radar mode circle, !radar scale = !radar size }
  if RadarModeOf(W) >= 0 then
  begin
    Rest := W;
    W := 'mode';
  end
  else if W = 'scale' then
    W := 'size';
  Modes := 'list, circle';
  if OvlAllowed[ID] then
    Modes := Modes + ', labels, arrows';
  if (W = '') or (W = 'on') or (W = 'off') then
  begin
    if W = '' then
      NewOn := not OvlOn[ID]
    else
      NewOn := W = 'on';
    DefOn := OvlPublicOn;
    if OvlAllowed[ID] then
      DefOn := OvlDefaultOn;
    if NewOn = DefOn then
      RdPOn[ID] := PREF_DEFAULT
    else if NewOn then
      RdPOn[ID] := PREF_ON
    else
      RdPOn[ID] := PREF_OFF;
    RadarApplyOn(ID);
    if not OvlOn[ID] then
    begin
      if RadarEditing(ID) then
        EditorStop(ID, False);
      OverlayHide(ID);
    end;
    RdRedraw[ID] := True;
    OverlayRecount();
    PrefsSave(ID);
    Say(ID, 'Radar ' + BoolText(OvlOn[ID]) + ' (' + RadarModeName(RadarMode(ID)) + '). More: ' + Cmd + ' help',
      ColorGood);
  end
  else if W = 'mode' then
  begin
    M := RadarModeOf(Rest);
    if M < 0 then
    begin
      Say(ID, 'Radar mode now: ' + RadarModeName(RadarMode(ID)) + '. Use: ' + Cmd + ' mode ' + ReplaceAll(Modes, ', ', '|'),
        ColorGood);
      Exit;
    end;
    if (M = OVL_LABELS) or (M = OVL_ARROWS) then
      if not OvlAllowed[ID] then
      begin
        Say(ID, 'The labels and the arrows are only for the radar admins; you have ' + Modes + '.', ColorBad);
        Exit;
      end;
    if RadarEditing(ID) then
      EditorStop(ID, True);
    if M = OvlMode then
      RdPMode[ID] := 0
    else
      RdPMode[ID] := M + 1;
    RdRedraw[ID] := True;
    PrefsSave(ID);
    Say(ID, 'Radar mode ' + RadarModeName(M) + '.', ColorGood);
    if not OvlOn[ID] then
      Say(ID, 'The radar is off: ' + Cmd + ' switches it on.', ColorGood);
  end
  else if (W = 'tick') or (W = 'ticks') then
  begin
    N := StrToIntDef(Rest, -1);
    if N < 0 then
    begin
      Say(ID, 'The radar is updated every ' + IntToStr(RadarTicks(ID)) + ' ticks (60 = 1 second). Use: ' + Cmd +
        ' tick <n>, 0 = the server setting.', ColorGood);
      Exit;
    end;
    if N > 600 then
      N := 600;
    if N > 0 then
      if not OvlAllowed[ID] then
        if N < OvlPublicMinTicks then
        begin
          N := OvlPublicMinTicks;
          Say(ID, 'Not faster than every ' + IntToStr(N) + ' ticks on this server.', ColorBad);
        end;
    RdPTicks[ID] := N;
    RdDue[ID] := Game.TickCount;
    PrefsSave(ID);
    Say(ID, 'The radar is updated every ' + IntToStr(RadarTicks(ID)) + ' ticks.', ColorGood);
  end
  else if W = 'zoom' then
  begin
    V := ParseFloat(Rest, Ok);
    if not Ok then
    begin
      Say(ID, 'The radar reaches ' + IntToStr(Round(RadarRange(ID))) + ' pixels (zoom ' + FloatStr(RadarZoom(ID), 2) +
        '). Use: ' + Cmd + ' zoom <0.5-4> - more reaches further, the circle marks get smaller.', ColorGood);
      Exit;
    end;
    if V < 0.5 then
      V := 0.5;
    if V > 4 then
      V := 4;
    RdPZoom[ID] := V;
    if Abs(V - 1) < 0.001 then
      RdPZoom[ID] := 0;
    RdRedraw[ID] := True;
    PrefsSave(ID);
    Say(ID, 'Radar zoom ' + FloatStr(V, 2) + ': it reaches ' + IntToStr(Round(RadarRange(ID))) + ' pixels.', ColorGood);
  end
  else if W = 'show' then
  begin
    M := ShowOf(Rest);
    if M < 0 then
    begin
      Say(ID, 'The radar shows: ' + ShowName(RadarShowOf(ID)) + '. Use: ' + Cmd + ' show all|seenall|seen - seen = the' +
        ' players you or a living team mate can see, seenall = dead team mates count too.', ColorGood);
      Exit;
    end;
    if not OvlAllowed[ID] then
      if M < OvlPublicShow then
      begin
        Say(ID, 'On this server the radar shows at most: ' + ShowName(OvlPublicShow) + '.', ColorBad);
        Exit;
      end;
    RdPShow[ID] := M + 1;
    if OvlAllowed[ID] then
    begin
      if M = OvlShow then
        RdPShow[ID] := 0;
    end
    else if M = OvlPublicShow then
      RdPShow[ID] := 0;
    RdRedraw[ID] := True;
    OverlayRecount();
    PrefsSave(ID);
    Say(ID, 'The radar shows: ' + ShowName(RadarShowOf(ID)) + '.', ColorGood);
  end
  else if W = 'edit' then
  begin
    if (RadarMode(ID) = OVL_LABELS) or (RadarMode(ID) = OVL_ARROWS) then
      Say(ID, 'The editor moves the list and the circle; the labels and the arrows stay by the players.', ColorBad)
    else if TeamOf[ID] = TEAM_SPECTATOR then
      Say(ID, 'The editor works only while you play.', ColorBad)
    else
      EditorStart(ID, ED_RADAR);
  end
  else if (W = 'done') or (W = 'save') then
  begin
    if RadarEditing(ID) then
      EditorStop(ID, True)
    else
      Say(ID, 'The radar editor is not open (' + Cmd + ' edit).', ColorBad);
  end
  else if (W = 'pos') or (W = 'position') then
  begin
    X := StrToIntDef(FirstWord(Rest), -1);
    Y := StrToIntDef(AfterFirstWord(Rest), -1);
    if (X < 0) or (Y < 0) or (X > 854) or (Y > 480) then
    begin
      Say(ID, 'Use: ' + Cmd + ' pos <x 0-854> <y 0-480> (the top-left corner; keep x below 600 to be seen on every screen)',
        ColorBad);
      Exit;
    end;
    RdPX[ID] := X;
    RdPY[ID] := Y;
    RdRedraw[ID] := True;
    PrefsSave(ID);
    Say(ID, 'Radar position ' + IntToStr(X) + ' ' + IntToStr(Y) + '.', ColorGood);
  end
  else if W = 'size' then
  begin
    V := ParseFloat(Rest, Ok);
    if not Ok then
    begin
      Say(ID, 'Use: ' + Cmd + ' size <0.3-4> (1 = the server setting)', ColorBad);
      Exit;
    end;
    if V < 0.3 then
      V := 0.3;
    if V > 4 then
      V := 4;
    RdPSize[ID] := V;
    if Abs(V - 1) < 0.001 then
      RdPSize[ID] := 0;
    RdRedraw[ID] := True;
    PrefsSave(ID);
    Say(ID, 'Radar size ' + FloatStr(V, 2) + '.', ColorGood);
  end
  else if W = 'reset' then
  begin
    if RadarEditing(ID) then
      EditorStop(ID, False);
    RdPMode[ID] := 0;
    RdPTicks[ID] := 0;
    RdPX[ID] := -1;
    RdPY[ID] := -1;
    RdPSize[ID] := 0;
    RdPZoom[ID] := 0;
    RdPShow[ID] := 0;
    RdRedraw[ID] := True;
    OverlayRecount();
    PrefsSave(ID);
    Say(ID, 'Radar: the server settings again.', ColorGood);
  end
  else
  begin
    Say(ID, Cmd + ' - on/off; ' + Cmd + ' mode ' + ReplaceAll(Modes, ', ', '|') + ' (or just ' + Cmd + ' circle); ' +
      Cmd + ' reset', ColorGood);
    Say(ID, Cmd + ' tick <n> - update every n ticks (60 = 1 s); ' + Cmd + ' edit - move and resize it with the keys',
      ColorGood);
    Say(ID, Cmd + ' pos <x> <y>; ' + Cmd + ' size <n>; ' + Cmd + ' zoom <n> - reach further (smaller circle marks)',
      ColorGood);
    Say(ID, Cmd + ' show all|seenall|seen - only the players you or your team can see', ColorGood);
  end;
end;

{ /tele, /teletomouse, /flytomouse: with the key of [Teleport] Key the admin jumps to his cursor and
  stops, jumps and keeps flying in that direction, or flies towards the cursor while he holds the key.
  The game sends the cursor with the key press, so the jump goes where the cursor is at that moment.
  The same command again switches it off; another one switches to its mode. }
procedure CmdTele(ID: Integer; Console: Boolean; Mode: Integer);
var
  K, Name: string;
begin
  if Console then
  begin
    Say(ID, 'The teleport is for admins in the game.', ColorBad);
    Exit;
  end;
  if TpOn[ID] and (TpMode[ID] = Mode) then
  begin
    TpOn[ID] := False;
    TpMode[ID] := TP_OFF;
    TpCount := TpCount - 1;
    if TpCount < 0 then
      TpCount := 0;
    Say(ID, 'Teleport off.', ColorGood);
    Exit;
  end;
  if not TpOn[ID] then
    TpCount := TpCount + 1;
  TpOn[ID] := True;
  TpMode[ID] := Mode;
  TpWas[ID] := True;
  K := 'reload';
  if TpKey = TK_GRENADE then
    K := 'grenade'
  else if TpKey = TK_THROW then
    K := 'throw weapon'
  else if TpKey = TK_CHANGE then
    K := 'change weapon';
  if Mode = TP_MOMENTUM then
    Name := 'you jump to your cursor and keep flying that way (faster for a longer jump)'
  else if Mode = TP_FLY then
    Name := 'you fly towards your cursor while you hold it (faster when it is further)'
  else
    Name := 'you jump to your cursor and stop there';
  Say(ID, 'Teleport on: press ' + K + ' and ' + Name + '. The same command switches it off.', ColorGood);
end;

{ ---- admin commands on one player ---- }

{ the player an admin command names: a slot or a name (the first word); nobody named = the admin
  himself when SelfOk }
function AdminTarget(ID: Integer; Args: string; SelfOk: Boolean): Integer;
var
  W: string;
begin
  Result := -1;
  W := FirstWord(Trim(Args));
  if W = '' then
  begin
    if SelfOk then
      if ID >= 1 then
        Result := ID;
    if Result < 0 then
      Say(ID, 'Name a player (id or name).', ColorBad);
    Exit;
  end;
  Result := FindPlayer(W);
  if Result < 1 then
    Say(ID, 'Player not found (' + W + ')', ColorBad);
end;

{ /explode <player|all> }
procedure CmdExplode(ID: Integer; Args: string);
var
  T, i: Integer;
begin
  if LowerCase(Trim(Args)) = 'all' then
  begin
    for i := 1 to TopSlot do
      if i <> ID then
        if PL[i].Active then
          if PL[i].Alive then
          begin
            AdminHit[i] := Game.TickCount;
            Map.CreateBullet(PL[i].X, PL[i].Y, 0, 0, 1000, 4, PL[i]);
          end;
    Exit;
  end;
  T := AdminTarget(ID, Args, False);
  if T < 1 then
    Exit;
  if not PL[T].Alive then
  begin
    Say(ID, PL[T].Name + ' is dead.', ColorBad);
    Exit;
  end;
  AdminHit[T] := Game.TickCount;
  Map.CreateBullet(PL[T].X, PL[T].Y, 0, 0, 1000, 4, PL[T]);
  Say(ID, PL[T].Name + ' exploded.', ColorGood);
end;

{ /god [player]: no damage for him until it is switched off (or he leaves) }
procedure CmdGod(ID: Integer; Args: string);
var
  T: Integer;
begin
  T := AdminTarget(ID, Args, True);
  if T < 1 then
    Exit;
  GodOn[T] := not GodOn[T];
  if T = ID then
    Say(ID, 'Godmode ' + BoolText(GodOn[T]) + '.', ColorGood)
  else
  begin
    Say(ID, 'Godmode of ' + PL[T].Name + ' ' + BoolText(GodOn[T]) + '.', ColorGood);
    Say(T, AdminName(ID) + ' switched your godmode ' + BoolText(GodOn[T]) + '.', ColorGood);
  end;
  Log('godmode of ' + PL[T].Name + ' ' + BoolText(GodOn[T]) + ' by ' + AdminName(ID));
end;

{ /heal <player|all>: full health }
procedure CmdHeal(ID: Integer; Args: string);
var
  T, i: Integer;
begin
  if LowerCase(Trim(Args)) = 'all' then
  begin
    for i := 1 to TopSlot do
      if PL[i].Active then
        if PL[i].Alive then
        begin
          PL[i].Health := MaxHealth;
          LastHealth[i] := MaxHealth;
          HudMark(i, False);
        end;
    Say(ID, 'Everybody healed.', ColorGood);
    Exit;
  end;
  T := AdminTarget(ID, Args, True);
  if T < 1 then
    Exit;
  if not PL[T].Alive then
  begin
    Say(ID, PL[T].Name + ' is dead.', ColorBad);
    Exit;
  end;
  PL[T].Health := MaxHealth;
  LastHealth[T] := MaxHealth;
  HudMark(T, False);
  Say(ID, PL[T].Name + ' healed.', ColorGood);
end;

{ /slap <player> [damage]: a hit and a jump }
procedure CmdSlap(ID: Integer; Args: string);
var
  T, N: Integer;
begin
  T := AdminTarget(ID, Args, False);
  if T < 1 then
    Exit;
  if not PL[T].Alive then
  begin
    Say(ID, PL[T].Name + ' is dead.', ColorBad);
    Exit;
  end;
  N := StrToIntDef(AfterFirstWord(Args), AdSlapDamage);
  if N < 0 then
    N := 0;
  AdminHit[T] := Game.TickCount;
  if N > 0 then
    PL[T].Damage(T, N);
  PL[T].SetVelocity(Random(-40, 41) * 0.1, -6);
  Say(T, AdminName(ID) + ' slapped you.', ColorBad);
  Say(ID, PL[T].Name + ' slapped (' + IntToStr(N) + ').', ColorGood);
end;

{ /freeze <player>: he stands where he is until it is switched off (or he dies or leaves) }
procedure CmdFreeze(ID: Integer; Args: string);
var
  T: Integer;
begin
  T := AdminTarget(ID, Args, False);
  if T < 1 then
    Exit;
  FrOn[T] := not FrOn[T];
  if FrOn[T] then
  begin
    FrX[T] := PL[T].X;
    FrY[T] := PL[T].Y;
    FrCount := FrCount + 1;
  end
  else
    FrCount := FrCount - 1;
  if FrCount < 0 then
    FrCount := 0;
  Say(ID, PL[T].Name + iif(FrOn[T], ' frozen.', ' free again.'), ColorGood);
  Say(T, iif(FrOn[T], 'An admin froze you.', 'You can move again.'), ColorBad);
end;

{ /bring <player>: he comes to the admin; /goto <player>: the admin goes to him }
procedure CmdBring(ID: Integer; Args: string; Bring: Boolean);
var
  T: Integer;
begin
  T := AdminTarget(ID, Args, False);
  if T < 1 then
    Exit;
  if T = ID then
    Exit;
  if not PL[T].Alive then
  begin
    Say(ID, PL[T].Name + ' is dead.', ColorBad);
    Exit;
  end;
  if not PL[ID].Alive then
  begin
    Say(ID, 'You are dead.', ColorBad);
    Exit;
  end;
  if Bring then
  begin
    PL[T].Move(PL[ID].X, PL[ID].Y - 10);
    PL[T].SetVelocity(0, 0);
    if FrOn[T] then
    begin
      FrX[T] := PL[ID].X;
      FrY[T] := PL[ID].Y - 10;
    end;
    Say(ID, PL[T].Name + ' brought to you.', ColorGood);
  end
  else
  begin
    PL[ID].Move(PL[T].X, PL[T].Y - 10);
    PL[ID].SetVelocity(0, 0);
    Say(ID, 'You went to ' + PL[T].Name + '.', ColorGood);
  end;
end;

{ /disarm <player>: no weapons; /give <player> <weapon 0-16> as the primary weapon }
procedure CmdWeapon(ID: Integer; Args: string; Disarm: Boolean);
var
  T, W: Integer;
  A, B: TNewWeapon;
begin
  T := AdminTarget(ID, Args, False);
  if T < 1 then
    Exit;
  if not PL[T].Alive then
  begin
    Say(ID, PL[T].Name + ' is dead.', ColorBad);
    Exit;
  end;
  W := WEP_NONE;
  if not Disarm then
  begin
    W := StrToIntDef(AfterFirstWord(Args), -1);
    if (W < 0) or (W > 16) then
    begin
      Say(ID, 'Use: /give <player> <weapon 0-16> (0 USSOCOM, 1 Desert Eagles, 2 MP5, 3 Ak-74, 4 Steyr AUG,' +
        ' 5 Spas-12, 6 Ruger, 7 M79, 8 Barrett, 9 Minimi, 10 Minigun, 11 knife, 12 chainsaw, 13 LAW, 14 flamer,' +
        ' 15 bow, 16 flamed arrows)', ColorBad);
      Exit;
    end;
  end;
  A := TNewWeapon.Create;
  A.WType := W;
  if Disarm then
  begin
    B := TNewWeapon.Create;
    B.WType := WEP_NONE;
    PL[T].ForceWeapon(A, B);
    B.Free;
    Say(ID, PL[T].Name + ' disarmed.', ColorGood);
  end
  else
  begin
    PL[T].ForceWeapon(A, PL[T].Secondary);
    Say(ID, PL[T].Name + ' got ' + WeaponName(W) + '.', ColorGood);
  end;
  A.Free;
end;

{ /bonus <player> <1-6>: predator, berserker, vest, grenades, clusters, flame god }
procedure CmdBonus(ID: Integer; Args: string);
var
  T, N: Integer;
begin
  T := AdminTarget(ID, Args, True);
  if T < 1 then
    Exit;
  N := StrToIntDef(AfterFirstWord(Args), 0);
  if (N < 1) or (N > 6) then
  begin
    Say(ID, 'Use: /bonus <player> <1 predator, 2 berserker, 3 vest, 4 grenades, 5 clusters, 6 flame god>', ColorBad);
    Exit;
  end;
  if not PL[T].Alive then
  begin
    Say(ID, PL[T].Name + ' is dead.', ColorBad);
    Exit;
  end;
  PL[T].GiveBonus(N);
  HudMark(T, False);
  Say(ID, PL[T].Name + ' got the bonus.', ColorGood);
end;

{ every second tick while somebody is frozen: put back where he was frozen }
procedure FreezeTick(Tick: Integer);
var
  i: Integer;
  P: TActivePlayer;
begin
  if Tick mod 2 <> 0 then
    Exit;
  for i := 1 to TopSlot do
    if FrOn[i] then
    begin
      P := PL[i];
      if not P.Active then
      begin
        FrOn[i] := False;
        FrCount := FrCount - 1;
        Continue;
      end;
      if not P.Alive then
        Continue;
      if (Abs(P.X - FrX[i]) > 2) or (Abs(P.Y - FrY[i]) > 2) then
      begin
        P.Move(FrX[i], FrY[i]);
        P.SetVelocity(0, 0);
      end;
    end;
  if FrCount < 0 then
    FrCount := 0;
end;

procedure RunCommand(ID, Cmd: Integer; Args: string; Console: Boolean);
var
  i, T, Top, OldLayer: Integer;
begin
  { player commands need a player }
  if Console then
    if Cmd < C_FIRST_ADMIN then
      Exit;
  case Cmd of
    C_LIST:
      if ClAuto then
        ShowList(ID, ClAutoLines, True, ClColor, ClPad, False)
      else if ClLines.Count = 0 then
        Say(ID, 'There are no commands to display', ColorBad)
      else
        ShowList(ID, ClLines, ClColors, ClColor, ClPad, False);
    C_RULES:
      if RuLines.Count = 0 then
        Say(ID, 'No rules to display.', ColorBad)
      else
        ShowList(ID, RuLines, RuColors, RuColor, 0, False);
    C_MAPLIST: CmdMapList(ID);
    C_RATIO: CmdRatio(ID, Args);
    C_PING: CmdPing(ID, Args);
    C_TRACK: CmdTrack(ID, Args);
    C_TIME: SayTo(ID, TmPublic, 'Time on the server - ' + FormatDateTime(TmFormat, Now()), ColorGood);
    C_WHOIS: CmdWhois(ID);
    C_CALLADMIN: CmdCallAdmin(ID, Args);
    C_JOIN: CmdJoin(ID, -1);
    C_SPEC: CmdSpec(ID);
    C_ALPHA: CmdJoin(ID, 1);
    C_BRAVO: CmdJoin(ID, 2);
    C_CHARLIE: CmdJoin(ID, 3);
    C_DELTA: CmdJoin(ID, 4);
    C_HP: CmdHp(ID, Args);
    C_DMG: CmdDmg(ID);
    C_NEXTMAP: Say(ID, 'Nextmap is: ' + Game.NextMap, MiColor);
    C_LASTMAP: Say(ID, 'Lastmap is: ' + PrevMap, MiColor);
    C_CURMAP: Say(ID, 'Current map is: ' + Game.CurrentMap, MiColor);
    C_INFO: CmdInfo(ID);
    C_OVERLAY:
      if Console then
        Say(ID, 'The radar is for players in the game.', ColorBad)
      else
        CmdRadar(ID, Args, '/radar');
    C_RADAR: CmdRadar(ID, Args, '!radar');
    C_TELE: CmdTele(ID, Console, TP_JUMP);
    C_MEDIC: CmdMedic(ID);
    C_EXPLODE: CmdExplode(ID, Args);
    C_GOD: CmdGod(ID, Args);
    C_HEAL: CmdHeal(ID, Args);
    C_SLAP: CmdSlap(ID, Args);
    C_FREEZE: CmdFreeze(ID, Args);
    C_BRING: CmdBring(ID, Args, True);
    C_GOTO: CmdBring(ID, Args, False);
    C_DISARM: CmdWeapon(ID, Args, True);
    C_GIVE: CmdWeapon(ID, Args, False);
    C_BONUS: CmdBonus(ID, Args);
    C_TELEMOUSE: CmdTele(ID, Console, TP_MOMENTUM);
    C_FLYMOUSE: CmdTele(ID, Console, TP_FLY);
    C_ADMINLIST:
      if AdListLines.Count = 0 then
        Say(ID, 'There are no admin commands to display', ColorBad)
      else
        ShowList(ID, AdListLines, AdListColors, ColorGood, ClPad, False);
    C_IP, C_HWID:
      begin
        T := TargetOf(ID, Args);
        if T < 1 then
          Say(ID, 'Player not found (' + Args + ')', ColorBad)
        else if Cmd = C_IP then
          Say(ID, PL[T].Name + ' IP: ' + PL[T].IP, ColorGood)
        else
          Say(ID, PL[T].Name + ' HWID: ' + PL[T].HWID, ColorGood);
      end;
    C_BAN: CmdBan(ID, Args);
    C_BANHW: CmdBanList(ID, Args, True);
    C_BANIP: CmdBanList(ID, Args, False);
    C_KILLALL:
      begin
        Top := TopSlot;
        for i := 1 to Top do
          if i <> ID then
            if PL[i].Active then
              if PL[i].Alive then
                if not (AdKillSkipAdmins and PL[i].IsAdmin) then
                begin
                  ServerKill[i] := Game.TickCount;
                  PL[i].Damage(i, 4000);
                end;
      end;
    C_KICKALL:
      begin
        { a kick runs the leave event at once, and that lowers TopSlot }
        Top := TopSlot;
        for i := 1 to Top do
          if i <> ID then
            if PL[i].Active then
              if not (AdKickSkipAdmins and PL[i].IsAdmin) then
                PL[i].Kick(TKickSilent);
      end;
    C_EXPLODEALL:
      for i := 1 to TopSlot do
        if i <> ID then
          if PL[i].Active then
            if PL[i].Alive then
            begin
              AdminHit[i] := Game.TickCount;
              Map.CreateBullet(PL[i].X, PL[i].Y, 0, 0, 1000, 4, PL[i]);
            end;
    C_RANDOMIZE:
      begin
        ShuffleMapsList();
        Say(ID, 'Mapslist has been randomized.', ColorGood);
      end;
    C_RELOAD:
      begin
        OldLayer := HudLayer;
        { the radar marks go and come back on the next pass (their layers or places may change) }
        for i := 1 to TopSlot do
          OverlayHide(i);
        LoadAll();
        { a text on the old layer would stay for its whole display time }
        if OldLayer <> HudLayer then
          for i := 1 to TopSlot do
            if HudShown[i] then
              if PL[i].Active then
                PL[i].BigText(OldLayer, ' ', 1, ColorGood, 0.01, 0, 0);
        if not RegEnabled then
          for i := 1 to TopSlot do
          begin
            Regenerating[i] := False;
            Hurt[i] := False;
          end;
        for i := 1 to TopSlot do
        begin
          OverlayAllow(i);
          RadarApplyOn(i);
          RdRedraw[i] := True;
          HitMarkClear(i);
          if not TpEnabled then
            TpOn[i] := False;
        end;
        if not TpEnabled then
          TpCount := 0;
        OverlayRecount();
        RecheckSteamAdmins();
        HudMarkAll(True);
        if KitsAny then
        begin
          KitSpawnsOff();
          KitSweep();
        end;
        { like Basic 2.0.2: the maps list file is read again }
        if File.Exists(MapsFile) then
          Game.LoadList(MapsFile);
        Say(ID, 'Settings loaded successfully!', ColorGood);
      end;
    C_STATUS: CmdStatus(ID);
    C_BENCH: CmdBench(ID);
    C_STEAMADMIN: CmdSteamAdmin(ID, Args, Console);
  end;
end;

procedure CheatHint(ID: Integer);
var
  i: Integer;
begin
  for i := 1 to ChCount do
    Say(ID, ChText[i], ChColor);
end;

{ a chat line: !word and ?word commands, and the cheating hint }
procedure RunChat(ID: Integer; Text: string);
var
  S, L, W: string;
  k: Integer;
begin
  S := Trim(Text);
  if Length(S) > 1 then
    if S[1] = '^' then
      Delete(S, 1, 1);
  L := LowerCase(S);
  if ChEnabled then
    if ExecRegExpr(ChPattern, L) then
      CheatHint(ID);
  if Length(L) < 2 then
    Exit;
  if (L[1] <> '!') and (L[1] <> '?') then
    Exit;
  W := FirstWord(L);
  if W[1] = '!' then
    Delete(W, 1, 1);
  k := ChatWords.IndexOf(W);
  if k < 0 then
    Exit;
  RunCommand(ID, ChatIds[k], AfterFirstWord(S), False);
end;

function SlashCommandId(Text: string): Integer;
var
  S: string;
  k: Integer;
begin
  Result := 0;
  S := Trim(Text);
  if Length(S) < 2 then
    Exit;
  if S[1] = '/' then
    Delete(S, 1, 1);
  k := SlashWords.IndexOf(LowerCase(FirstWord(S)));
  if k >= 0 then
    Result := SlashIds[k];
end;

{ /be_test <slot> <text>: runs a chat line or a command of this script as if that player had typed
  it; the answers are written to the server console too (a testing aid for admins) }
procedure RunTest(ID: Integer; Args: string);
var
  Slot, Cmd: Integer;
  Text, S: string;
begin
  Slot := StrToIntDef(FirstWord(Args), 0);
  Text := AfterFirstWord(Args);
  if (Slot < 1) or (Slot > 32) or (Text = '') then
  begin
    Say(ID, 'Use: /be_test <player id> <chat line or /command>', ColorBad);
    Exit;
  end;
  if not PL[Slot].Active then
  begin
    Say(ID, 'There is no such player on the server.', ColorBad);
    Exit;
  end;
  TestEcho := True;
  if Text[1] = '/' then
  begin
    Cmd := SlashCommandId(Text);
    if Cmd = 0 then
      Say(ID, 'Not a command of this script: ' + Text, ColorBad)
    else if (Cmd >= C_FIRST_ADMIN) and (not PL[Slot].IsAdmin) then
      Say(ID, 'That player is not an admin.', ColorBad)
    else if Cmd <> C_TEST then
    begin
      S := Trim(Text);
      Delete(S, 1, 1);
      RunCommand(Slot, Cmd, AfterFirstWord(S), False);
    end;
  end
  else
    RunChat(Slot, Text);
  TestEcho := False;
end;

procedure RunSlash(ID: Integer; Text: string; Console: Boolean);
var
  S: string;
  Cmd: Integer;
begin
  Cmd := SlashCommandId(Text);
  if Cmd = 0 then
    Exit;
  { admin commands need an admin; the radar is also for [Radar] SteamIds and, when public, everybody }
  if Cmd >= C_FIRST_ADMIN then
    if not Console then
      if not PL[ID].IsAdmin then
        if not ((Cmd = C_OVERLAY) and (OvlAllowed[ID] or OvlPublic)) then
          Exit;
  { the testing aids act as other players or stop the server for a moment: only from the server
    console or a TCP admin }
  if (Cmd = C_TEST) or (Cmd = C_BENCH) then
    if not Console then
    begin
      Say(ID, 'This command works only from the server console or a TCP admin connection.', ColorBad);
      Exit;
    end;
  S := Trim(Text);
  if S[1] = '/' then
    Delete(S, 1, 1);
  if Cmd = C_TEST then
    RunTest(ID, AfterFirstWord(S))
  else
    RunCommand(ID, Cmd, AfterFirstWord(S), Console);
end;

procedure QueueText(Slot, Kind: Integer; Text: string);
var
  k: Integer;
begin
  if PendCount >= PEND_SIZE then
    Exit;
  k := (PendHead + PendCount) mod PEND_SIZE;
  PendSlot[k] := Slot;
  PendKind[k] := Kind;
  PendText[k] := Text;
  PendCount := PendCount + 1;
end;

procedure RunPending();
var
  n, Slot, Kind: Integer;
  Text: string;
begin
  n := 0;
  while PendCount > 0 do
  begin
    if n >= PENDING_PER_TICK then
      Break;
    Slot := PendSlot[PendHead];
    Kind := PendKind[PendHead];
    Text := PendText[PendHead];
    PendHead := (PendHead + 1) mod PEND_SIZE;
    PendCount := PendCount - 1;
    n := n + 1;
    if Kind = SRC_CONSOLE then
      RunSlash(0, Text, True)
    else if PL[Slot].Active then
    begin
      if Kind = SRC_CHAT then
        RunChat(Slot, Text)
      else
        RunSlash(Slot, Text, False);
    end;
  end;
end;

{ ================================ timers ================================ }

{ /tele: on the key press the admin jumps to his cursor (the game sends the cursor with the key), not
  into a wall ([Teleport] NotIntoWalls) }
procedure TeleportTick(Tick: Integer);
var
  i: Integer;
  P: TActivePlayer;
  K, Blocked, Go: Boolean;
  X, Y, PX, PY, DX, DY, D, Sp, VX, VY: Single;
begin
  for i := 1 to TopSlot do
    if TpOn[i] then
    begin
      P := PL[i];
      if not P.Active then
      begin
        TpOn[i] := False;
        TpMode[i] := TP_OFF;
        TpCount := TpCount - 1;
        Continue;
      end;
      if TpKey = TK_GRENADE then
        K := P.KeyGrenade
      else if TpKey = TK_THROW then
        K := P.KeyThrow
      else if TpKey = TK_CHANGE then
        K := P.KeyChangeWeap
      else
        K := P.KeyReload;
      { a jump on the press; the flight also every FlyEveryTicks while the key is held }
      Go := False;
      if K then
      begin
        if not TpWas[i] then
          Go := True
        else if TpMode[i] = TP_FLY then
          if Tick >= TpNext[i] then
            Go := True;
      end;
      TpWas[i] := K;
      if Go then
        if P.Alive then
        begin
          if not P.IsAdmin then
          begin
            TpOn[i] := False;
            TpMode[i] := TP_OFF;
            TpCount := TpCount - 1;
            Say(i, 'Teleport off: you are not an admin any more.', ColorBad);
            Continue;
          end;
          X := P.MouseAimX;
          Y := P.MouseAimY;
          PX := P.X;
          PY := P.Y;
          DX := X - PX;
          DY := Y - PY;
          D := Sqrt(DX * DX + DY * DY);
          if TpMode[i] = TP_FLY then
          begin
            { no jump: a push towards the cursor, stronger when it is further }
            TpNext[i] := After(Tick, TpFlyEvery);
            if D >= 1 then
            begin
              Sp := TpFlyBase + D * TpFlyPerDist;
              if Sp > TpFlyMax then
                Sp := TpFlyMax;
              P.SetVelocity(DX / D * Sp, DY / D * Sp);
            end;
          end
          else
          begin
            Blocked := False;
            if TpNoWalls then
              Blocked := Map.RayCast(X, Y - 10, X + 1, Y - 9, True, False, False, False, TeamOf[i]);
            if Blocked then
              Say(i, 'Your cursor is inside a wall.', ColorBad)
            else if TpMode[i] = TP_MOMENTUM then
            begin
              { the speed he had, and more for a longer jump, all in the direction of the jump }
              VX := P.VelX;
              VY := P.VelY;
              Sp := Sqrt(VX * VX + VY * VY) * TpMomKeep + TpMomBase + D * TpMomPerDist;
              if Sp > TpMomMax then
                Sp := TpMomMax;
              P.Move(X, Y);
              if D >= 1 then
                P.SetVelocity(DX / D * Sp, DY / D * Sp);
            end
            else
            begin
              P.Move(X, Y);
              P.SetVelocity(0, 0);
            end;
          end;
        end;
    end;
  if TpCount < 0 then
    TpCount := 0;
end;

{ [Afk]: a player in a team who is alive and presses no key nor moves the cursor for Minutes goes to
  the spectators (then [SpecIdle] may kick him); the time while he is dead does not count }
procedure AfkSecond();
var
  i: Integer;
  P: TActivePlayer;
  Act: Boolean;
  AX, AY: Integer;
begin
  if Game.NumPlayers < AfMinPlayers then
    Exit;
  for i := 1 to TopSlot do
    if ActiveSlot[i] then
    begin
      P := PL[i];
      if not P.Human then
        Continue;
      if TeamOf[i] = TEAM_SPECTATOR then
      begin
        AfIdle[i] := 0;
        Continue;
      end;
      if not P.Alive then
        Continue;
      Act := P.KeyLeft or P.KeyRight or P.KeyUp or P.KeyCrouch or P.KeyJetpack or P.KeyShoot or P.KeyGrenade or
        P.KeyChangeWeap or P.KeyThrow or P.KeyReload or P.KeyProne or P.KeyFlagThrow;
      AX := P.MouseAimX;
      AY := P.MouseAimY;
      if (Abs(AX - AfAimX[i]) > 3) or (Abs(AY - AfAimY[i]) > 3) then
        Act := True;
      AfAimX[i] := AX;
      AfAimY[i] := AY;
      if Act then
        AfIdle[i] := 0
      else
      begin
        AfIdle[i] := AfIdle[i] + 1;
        if AfWarn > 0 then
          if AfIdle[i] = AfSeconds - AfWarn then
            Say(i, 'Are you there? In ' + IntToStr(AfWarn) + ' seconds you go to the spectators (away from the keyboard).',
              ColorBad);
        if AfIdle[i] >= AfSeconds then
        begin
          AfIdle[i] := 0;
          if AfIgnoreAdmins then
            if P.IsAdmin then
              Continue;
          SayAll(ReplaceAll(AfText, '{player}', P.Name), ColorBad);
          P.ChangeTeam(TEAM_SPECTATOR, TJoinSilent);
          StatAfk := StatAfk + 1;
        end;
      end;
    end;
end;

procedure SecondTick(Tick: Integer);
var
  i, n, Sum, Humans, Ping: Integer;
  P: TActivePlayer;
  S: string;
begin
  { a map change that was announced and never came (a pause during the countdown) }
  if MapChanging then
    if Tick - MapChangeTick > MAPCHANGE_TIMEOUT then
    begin
      MapChanging := False;
      SpawnsCleared := False;
    end;
  if AfEnabled then
    AfkSecond();
  if TkEnabled then
    TimeToKillSecond(Tick);
  if MdEnabled then
    MedicSecond();
  if RsEnabled then
    ResSecond(Tick);
  { who is admin: TCP admins answer during these seconds }
  if WhoisLeft > 0 then
  begin
    WhoisLeft := WhoisLeft - 1;
    if WhoisLeft = 0 then
      WhoisReport();
  end;

  for i := 1 to TopSlot do
    if TrackLeft[i] > 0 then
    begin
      P := PL[i];
      if not P.Active then
        TrackLeft[i] := 0
      else
      begin
        Ping := P.Ping;
        TrackSum[i] := TrackSum[i] + Ping;
        TrackCount[i] := TrackCount[i] + 1;
        if Ping > TrackMax[i] then
          TrackMax[i] := Ping;
        TrackLeft[i] := TrackLeft[i] - 1;
        if TrackLeft[i] = 0 then
          SayTo(TrackAsker[i], PtPublic, 'Tracking result for ' + P.Name + ': Average Ping: ' +
            IntToStr(Round(TrackSum[i] * 1.0 / TrackCount[i])) + ', Max Ping: ' + IntToStr(TrackMax[i]), ColorGood);
      end;
    end;

  { spectators who only take a slot }
  if SiEnabled then
    if Game.NumPlayers >= SiMinPlayers then
      for i := 1 to TopSlot do
        if SpecLeft[i] > 0 then
        begin
          P := PL[i];
          if not P.Active then
            SpecLeft[i] := 0
          else if P.Team <> TEAM_SPECTATOR then
            SpecLeft[i] := 0
          else if SiIgnoreAdmins and P.IsAdmin then
            SpecLeft[i] := 0
          else
          begin
            SpecLeft[i] := SpecLeft[i] - 1;
            if (SpecLeft[i] mod 60 = 0) and (SpecLeft[i] >= 60) then
            begin
              Say(i, 'You cannot idle as spectator forever!', ColorGood);
              Say(i, 'Time left: ' + IntToStr(SpecLeft[i] div 60) + iif(SpecLeft[i] = 60, ' minute', ' minutes'),
                ColorGood);
            end
            else if SpecLeft[i] = 15 then
            begin
              Say(i, '--- FINAL WARNING ---', ColorGood);
              Say(i, 'Time left: 15 seconds', ColorGood);
            end
            else if SpecLeft[i] = 0 then
            begin
              if SiBanMinutes > 0 then
              begin
                SayAll(P.Name + ' has been kicked for occupying', ColorBad);
                SayAll('a slot (banned for ' + IntToStr(SiBanMinutes) + iif(SiBanMinutes = 1, ' minute', ' minutes') +
                  ').', ColorBad);
                ScheduleBan(i, SiBanMinutes, 'Spec idle kick');
              end
              else
              begin
                SayAll(P.Name + ' has been kicked for occupying a slot.', ColorBad);
                ScheduleBan(i, 0, '');
              end;
            end;
          end;
        end;

  if SpEnabled then
    if Tick >= DuePing then
    begin
      DuePing := After(Tick, SpTicks);
      Sum := 0;
      Humans := 0;
      for i := 1 to TopSlot do
        if PL[i].Active then
          if PL[i].Human then
          begin
            Sum := Sum + PL[i].Ping;
            Humans := Humans + 1;
          end;
      if Humans > 0 then
        SayAll('Recent average server ping is: ' + IntToStr(Round(Sum * 1.0 / Humans)) + 'ms.', ColorGood);
    end;

  if TiEnabled then
    if Tick >= DueTip then
    begin
      DueTip := After(Tick, TiTicks);
      if TiLeft.Count = 0 then
        TiLeft.AddStrings(TiAll);
      if TiLeft.Count > 0 then
      begin
        n := Random(0, TiLeft.Count);
        SayAll(TiLeft[n], TiColor);
        TiLeft.Delete(n);
      end;
    end;

  if WeEnabled then
    if WeTicks > 0 then
      if Tick >= DueWelcome then
      begin
        DueWelcome := After(Tick, WeTicks);
        for i := 1 to TopSlot do
          if PL[i].Active then
            if PL[i].Human then
            begin
              S := ReplaceAll(WeText, '{player}', PL[i].Name);
              Say(i, S, WeColor);
            end;
      end;
end;

{ ================================ events ================================ }

{ the server's tick counter starts again from 0 after about 414 days: every time stamp starts again }
procedure ClockWrapped(Tick: Integer);
var
  i, j: Integer;
begin
  DueRegen := Tick;
  DueScan := Tick;
  DueSecond := Tick;
  DuePoll := Tick;
  DueSweep := Tick;
  DueTip := After(Tick, TiTicks);
  DueWelcome := After(Tick, WeTicks);
  DuePing := After(Tick, SpTicks);
  StatSince := Tick;
  for i := 1 to 32 do
  begin
    LastHit[i] := 0;
    LastSupp[i] := 0;
    RegenStart[i] := Tick;
    HudSentTick[i] := 0;
    OvlListSent[i] := 0;
    CallLast[i] := 0;
    SeenTick[i] := -1;
    EdUntil[i] := Tick + HudEditorTicks;
    RdDue[i] := Tick;
    VpTick[i] := -1;
    CrSent[i] := 0;
    WtNext[i] := 0;
    for j := 0 to 7 do
      if HmUntil[i][j] > 0 then
        HmUntil[i][j] := Tick;
    for j := 0 to 255 do
      WtDue[i][j] := 0;
    for j := 1 to 32 do
    begin
      DnLast[i][j] := 0;
      OvlLastTick[i][j] := 0;
      CbSent[i][j] := 0;
    end;
  end;
end;

procedure OnTick(Ticks: Integer);
var
  Tick: Integer;
  T: TDateTime;
begin
  Tick := Game.TickCount;
  if Tick < LastTickSeen then
    ClockWrapped(Tick);
  LastTickSeen := Tick;
  { every part on its own: an error in one of them is logged and the others still run }
  if PendCount > 0 then
    try
      RunPending();
    except
      StageError('commands');
    end;
  if (DnPendCount > 0) or (VicCount > 0) then
    try
      DmgFlush(Tick);
    except
      StageError('damage numbers');
    end;
  if EdCount > 0 then
    try
      EditorTick(Tick);
    except
      StageError('editor');
    end;
  if Tick >= DueRegen then
  begin
    DueRegen := After(Tick, RegStepTicks);
    if RegEnabled then
      if not MapChanging then
        if not Game.Paused then
          try
            RegenPass(Tick);
          except
            StageError('regeneration');
          end;
  end;
  if Tick >= DueScan then
  begin
    DueScan := After(Tick, SupScanTicks);
    if RegEnabled then
      if SupEnabled then
        if HurtCount > 0 then
          if not MapChanging then
            try
              SuppressionScan(Tick);
            except
              StageError('bullet scan');
            end;
  end;
  if OvlCount > 0 then
    try
      OverlayTick(Tick);
    except
      StageError('radar');
    end;
  if VisNeeded then
    if OvlCount > 0 then
      try
        VisionTick(Tick);
      except
        StageError('radar vision');
      end;
  if DmgSharp then
    try
      WtHideDue(Tick);
    except
      StageError('sharp texts');
    end;
  if LowCount > 0 then
    if HudLowBlink > 0 then
      try
        LowBlinkTick(Tick);
      except
        StageError('low health');
      end;
  if TpCount > 0 then
    try
      TeleportTick(Tick);
    except
      StageError('teleport');
    end;
  if FrCount > 0 then
    try
      FreezeTick(Tick);
    except
      StageError('freeze');
    end;
  if Tick >= DuePoll then
  begin
    DuePoll := After(Tick, 30);
    try
      HudPoll(Tick);
    except
      StageError('health poll');
    end;
  end;
  if KitsAny then
    if Tick >= DueSweep then
    begin
      DueSweep := After(Tick, KitSweepTicks);
      try
        KitSweep();
      except
        StageError('kits');
      end;
    end;
  if Tick >= DueSecond then
  begin
    DueSecond := After(Tick, 60);
    try
      SecondTick(Tick);
    except
      StageError('timers');
    end;
  end;
  if BanPending > 0 then
    try
      RunBans(Tick);
    except
      StageError('bans');
    end;
  if HudAnyDirty then
    try
      HudFlush();
    except
      StageError('health display');
    end;
  { after a stall the server runs the missed ticks back to back: the console lines still go out
    a few at a time, at least 8 ms apart }
  if OutPending > 0 then
  begin
    T := Now();
    if (T < LastFlush) or ((T - LastFlush) * 86400000 >= 8) then
    begin
      LastFlush := T;
      try
        FlushOutput();
      except
        StageError('console output');
      end;
    end;
  end;
end;

procedure OnSpeakEv(Player: TActivePlayer; Text: string);
var
  S: string;
  Wanted: Boolean;
begin
  S := Trim(Text);
  if Length(S) > 1 then
    if S[1] = '^' then
      Delete(S, 1, 1);
  if LgEnabled then
    if LgChat then
      LogLine(Player.ID, Player.Name + ': ' + Text);
  Wanted := False;
  if Length(S) > 1 then
    if (S[1] = '!') or (S[1] = '?') then
      Wanted := True;
  if not Wanted then
    if ChEnabled then
      Wanted := ExecRegExpr(ChPattern, LowerCase(S));
  if Wanted then
    QueueText(Player.ID, SRC_CHAT, Text);
end;

{ a command typed by a player: run on the next tick. True keeps the server from running it itself
  (Soldat's own /info when [Info] HideSoldatInfo = 1). }
function OnCommandEv(Player: TActivePlayer; Command: string): Boolean;
var
  ID, Cmd: Integer;
begin
  Result := False;
  if LgEnabled then
    if LgCommands then
      LogLine(Player.ID, Player.Name + ' command: ' + LogCommand(Command));
  Cmd := SlashCommandId(Command);
  if Cmd = 0 then
    Exit;
  ID := Player.ID;
  if (SeenTick[ID] = Game.TickCount) and (SeenText[ID] = Command) then
    Exit;
  SeenTick[ID] := Game.TickCount;
  SeenText[ID] := Command;
  QueueText(ID, SRC_COMMAND, Command);
  if Cmd = C_INFO then
    Result := InHide;
end;

{ Player = nil: the server console or a TCP admin. An admin in the game sends the same command
  through OnCommand as well; the second copy is skipped. }
function OnAdminCommandEv(Player: TActivePlayer; Command: string): Boolean;
var
  ID, Cmd: Integer;
begin
  Result := False;
  if LgEnabled then
    if LgAdmins then
      if Player = nil then
        LogLine(0, 'console/TCP admin: ' + LogCommand(Command));
  Cmd := SlashCommandId(Command);
  if Cmd < C_FIRST_ADMIN then
    Exit;
  if Player = nil then
  begin
    QueueText(0, SRC_CONSOLE, Command);
    Exit;
  end;
  ID := Player.ID;
  if (SeenTick[ID] = Game.TickCount) and (SeenText[ID] = Command) then
    Exit;
  SeenTick[ID] := Game.TickCount;
  SeenText[ID] := Command;
  QueueText(ID, SRC_COMMAND, Command);
end;

function OnDamageEv(Shooter, Victim: TActivePlayer; Damage: Single; BulletId: Byte): Single;
var
  S, V, Tick: Integer;
  H, Shown: Single;
  Show, Count: Boolean;
begin
  Result := Damage;
  if Damage <= 0 then
    Exit;
  V := Victim.ID;
  S := Shooter.ID;
  Tick := Game.TickCount;
  { /god: no damage at all (the server's own kills still go through) }
  if GodOn[V] then
    if Damage <= SERVER_HIT_DAMAGE then
    begin
      Result := 0;
      Exit;
    end;
  if Damage > SERVER_HIT_DAMAGE then
    ServerKill[V] := Tick;
  if S = V then
    if BulletId = NO_BULLET then
      if Abs(Damage - PKILL_DAMAGE) < 0.5 then
        ServerKill[V] := Tick;
  { [Savior]: whom this player attacked last }
  if SvEnabled then
    if S <> V then
      if Enemies(S, V) then
      begin
        SvTarget[S] := V;
        SvTick[S] := Tick;
      end;
  { regeneration waits again, the health display shows the new value on the next tick }
  LastHit[V] := Tick;
  if Regenerating[V] then
    Regenerating[V] := False;
  if RegEnabled then
    if Victim.Human or RegBots then
      Hurt[V] := True;
  HudMark(V, False);
  if EdOn[V] then
    EditorStop(V, True);
  { damage numbers: only for a human shooter who wants them; own falls, polygons and /kill have no
    bullet and are not shown; the server's own kills count nowhere }
  Show := DmgEnabled;
  if Show then
    if not Shooter.Human then
      if not DebugBots then
        Show := False;
  if Show then
    if not DmgIsOn(S) then
      Show := False;
  if Show then
    if S = V then
      if (not DmgShowSelf) or (BulletId = NO_BULLET) then
        Show := False;
  Count := True;
  if Damage > SERVER_HIT_DAMAGE then
  begin
    Show := False;
    Count := False;
  end;
  H := Victim.Health;
  if H < 0 then
    H := 0;
  { the hit before this one on the same player took what is gone since then }
  if VicPend[V] then
    DmgSettle(V, VicLastBefore[V] - H)
  else if VicCount < 32 then
  begin
    VicPend[V] := True;
    VicList[VicCount] := V;
    VicCount := VicCount + 1;
  end;
  VicLastS[V] := S;
  VicLastBefore[V] := H;
  VicLastCount[V] := Count;
  VicLastShow[V] := False;
  if Show then
  begin
    VicLastX[V] := Victim.X;
    VicLastY[V] := Victim.Y;
    if DmgTaken then
      VicLastShow[V] := True
    else
    begin
      { Amount = hit: the damage the hit carried, as Soldat gave it to this script }
      Shown := Damage;
      if DmgPercent then
        Shown := Shown * 100 / MaxHealth;
      DmgAdd(S, V, Shown, VicLastX[V], VicLastY[V]);
    end;
  end;
end;

procedure OnKillEv(Killer, Victim: TActivePlayer; BulletId: Byte);
var
  K, V, Tick, W: Integer;
  S, Wep: string;
  Dealt2: Single;
begin
  K := Killer.ID;
  V := Victim.ID;
  Tick := Game.TickCount;
  Hurt[V] := False;
  Regenerating[V] := False;
  HudMark(V, False);
  if EdOn[V] then
    EditorStop(V, False);
  if DmgEnabled then
    if K <> V then
      if Killer.Human or DebugBots then
        if DmgIsOn(K) then
          DmgKill(K, V, Tick);

  if KiEnabled then
    if K <> V then
      if Victim.Human then
      begin
        Wep := 'unknown';
        if (BulletId >= 1) and (BulletId <= MAX_BULLET_ID) then
          if BL[BulletId].Owner = K then
          begin
            W := BL[BulletId].GetOwnerWeaponId;
            Wep := WeaponName(W);
          end;
        if Wep = 'unknown' then
          Wep := Killer.Primary.Name;
        { the damage he did to the killer in the killer's current fight (reset when the killer
          respawns or starts to regenerate), never more than a full health }
        Dealt2 := Dealt[V][K];
        if Dealt2 > MaxHealth then
          Dealt2 := MaxHealth;
        S := KiText;
        S := ReplaceAll(S, '{killer}', Killer.Name);
        S := ReplaceAll(S, '{weapon}', Wep);
        S := ReplaceAll(S, '{pct}', IntToStr(HealthPct(Killer.Health)));
        S := ReplaceAll(S, '{hp}', IntToStr(Round(Killer.Health)));
        if DmgPercent then
          S := ReplaceAll(S, '{dealt}', IntToStr(Round(Dealt2 * 100 / MaxHealth)) + '%')
        else
          S := ReplaceAll(S, '{dealt}', IntToStr(Round(Dealt2)));
        Say(V, S, KiColor);
      end;

  HitMarkClear(V);

  if K <> V then
  begin
    if Enemies(K, V) then
    begin
      if FbEnabled then
        FirstBloodKill(K, V);
      if McEnabled then
        MultiKill(K, Tick);
      if SvEnabled then
        SaviorKill(K, V, Tick);
    end;
    if AsEnabled then
      AssistKill(K, V);
    if PhEnabled then
      PosthumousKill(V);
  end
  else if SkEnabled then
    if ServerKill[V] <> Tick then
      if Tick - AdminHit[V] > ADMIN_HIT_TICKS then
        SelfKillPenalty(V);
  McCount[V] := 0;
  if LgEnabled then
    if LgKills then
      LogLine(K, Killer.Name + ' killed ' + Victim.Name);
end;

procedure OnRespawnEv(Player: TActivePlayer);
var
  ID: Integer;
begin
  ID := Player.ID;
  { during a map change the new map is loaded and its kits come right after the respawns: with the
    medkit spawn points switched off no kit is created at all. A respawn during the countdown (still
    the old map) must not use this up. A restart of the same map is left to OnAfterMapEv. }
  if MapChanging then
    if KitsAny then
      if not SpawnsCleared then
        if Game.CurrentMap <> PrevMap then
        begin
          SpawnsCleared := True;
          KitSpawnsOff();
        end;
  ResetLife(ID);
  if EdOn[ID] then
    EditorStop(ID, False);
  HitMarkClear(ID);
  HudMark(ID, True);
end;

procedure OnKitEv(Player: TActivePlayer; Kit: TActiveMapObject);
var
  k: Integer;
begin
  if KitsAny then
    if Kit.Active then
    begin
      k := Kit.Style;
      if (k >= 0) and (k <= 31) then
        if KitObj[k] then
        begin
          Kit.Kill;
          StatKits := StatKits + 1;
        end;
    end;
  HudMark(Player.ID, False);
end;

procedure SetupPlayer(ID: Integer);
var
  i: Integer;
begin
  SteamId[ID] := ReadSteam(ID);
  PrefsLoad(ID);
  ResetLife(ID);
  TeamOf[ID] := PL[ID].Team;
  SpecLeft[ID] := 0;
  AfIdle[ID] := 0;
  GodOn[ID] := False;
  if FrOn[ID] then
    FrCount := FrCount - 1;
  FrOn[ID] := False;
  AsCount[ID] := 0;
  McCount[ID] := 0;
  McLast[ID] := 0;
  SvTarget[ID] := 0;
  ServerKill[ID] := -1;
  AdminHit[ID] := -1000000;
  RsWait[ID] := 0;
  MdWants[ID] := False;
  LgWatched[ID] := False;
  TpOn[ID] := False;
  TpWas[ID] := True;
  HudLowSet(ID, False);
  HmActive[ID] := False;
  EdShowAt[ID] := 0;
  WtNext[ID] := 0;
  RdDue[ID] := 0;
  RdRedraw[ID] := True;
  RdDrawn[ID] := -1;
  CrOn[ID] := False;
  CrDots[ID] := 0;
  EdKind[ID] := ED_HUD;
  TrackLeft[ID] := 0;
  CallLast[ID] := 0;
  if EdOn[ID] then
    EdCount := EdCount - 1;
  EdOn[ID] := False;
  HudShown[ID] := False;
  HudHideAgain[ID] := False;
  HudLast[ID] := '';
  OverlayAllow(ID);
  RadarApplyOn(ID);
  OvlNext[ID] := 0;
  OvlListText[ID] := '';
  OvlListSent[ID] := 0;
  { a hit on the slot's last player that is not settled yet takes nothing from this one }
  VicLastBefore[ID] := 0;
  OutQ[ID].Clear;
  DnNext[ID] := DmgLayerFirst;
  for i := 1 to 32 do
  begin
    DnLayer[ID][i] := 0;
    DnLayer[i][ID] := 0;
    DnKillPend[ID][i] := False;
    DnKillPend[i][ID] := False;
    Dealt[i][ID] := 0;
    OvlLastTick[ID][i] := 0;
    OvlLastTick[i][ID] := 0;
    OvlLabelOn[ID][i] := False;
    CbOn[ID][i] := False;
  end;
  for i := 0 to 7 do
  begin
    HmUntil[ID][i] := 0;
    ChOn[ID][i] := False;
  end;
  for i := 0 to ARROW_LAYERS - 1 do
    ArOn[ID][i] := False;
  for i := 1 to 32 do
  begin
    VisMine[ID][i] := False;
    VisMine[i][ID] := False;
    OvlLastTag[ID][i] := 0;
  end;
  VpTick[ID] := -1;
  for i := DmgLayerFirst to DmgLayerLast do
    WtDue[ID][i] := 0;
end;

procedure OnJoinGameEv(Player: TActivePlayer; Team: TTeam);
var
  ID: Integer;
begin
  ID := Player.ID;
  ActiveSlot[ID] := True;
  if ID > TopSlot then
    TopSlot := ID;
  SetupPlayer(ID);
  if Player.Human then
  begin
    { a Steam id given at the join is confirmed already; otherwise OnSteamAuth brings it }
    GrantSteamAdmin(ID);
    DropStaleGrant(ID);
    if WeEnabled then
      if WeOnJoin then
        Say(ID, ReplaceAll(WeText, '{player}', Player.Name), WeColor);
    LogWatchCheck(ID);
    if LgEnabled then
      if LgJoins then
        LogLine(ID, Player.Name + ' joined (IP ' + Player.IP + ', Steam ' + iif(SteamId[ID] = '', 'not yet', SteamId[ID]) +
          ', HWID ' + Player.HWID + ')');
    if RsEnabled then
      ResCheck(ID, False);
  end;
  OverlayRecount();
  HudMark(ID, True);
end;

procedure OnLeaveGameEv(Player: TActivePlayer; Kicked: Boolean);
var
  ID, i: Integer;
begin
  ID := Player.ID;
  if LgEnabled then
    if LgJoins then
      LogLine(ID, Player.Name + iif(Kicked, ' was kicked', ' left'));
  for i := 0 to 4 do
    if MdOf[i] = ID then
      MdOf[i] := 0;
  GodOn[ID] := False;
  if FrOn[ID] then
  begin
    FrOn[ID] := False;
    FrCount := FrCount - 1;
  end;
  RsWait[ID] := 0;
  { left before a ban he was told about: the ban lists get his address and computer }
  if BanAt[ID] > 0 then
  begin
    BanAt[ID] := 0;
    BanPending := BanPending - 1;
    if BanMin[ID] > 0 then
    begin
      Game.BanLists.AddIPBan(Player.IP, BanWhy[ID], BanMin[ID] * 3600);
      if Player.HWID <> '' then
        Game.BanLists.AddHWBan(Player.HWID, BanWhy[ID], BanMin[ID] * 3600);
    end;
  end;
  if EdOn[ID] then
  begin
    EdOn[ID] := False;
    EdCount := EdCount - 1;
  end;
  { a ping measurement he asked for has nobody to report to }
  for i := 1 to TopSlot do
    if TrackAsker[i] = ID then
      TrackLeft[i] := 0;
  SpecLeft[ID] := 0;
  TrackLeft[ID] := 0;
  Hurt[ID] := False;
  Regenerating[ID] := False;
  HudShown[ID] := False;
  HudDirty[ID] := False;
  HudLowSet(ID, False);
  HmActive[ID] := False;
  if TpOn[ID] then
  begin
    TpOn[ID] := False;
    TpCount := TpCount - 1;
  end;
  OvlOn[ID] := False;
  OvlAllowed[ID] := False;
  OvlListText[ID] := '';
  RdDrawn[ID] := -1;
  CrOn[ID] := False;
  { his mark and label go from the radars of the others at once (the passes may not reach his slot
    any more) }
  for i := 1 to TopSlot do
  begin
    if CbOn[i][ID] then
    begin
      CbOn[i][ID] := False;
      if PL[i].Active then
        PL[i].BigText(OvlCircleLayer + RING_MAX + ID, ' ', 1, ColorGood, 0.01, 0, 0);
    end;
    if OvlLabelOn[i][ID] then
    begin
      OvlLabelOn[i][ID] := False;
      if PL[i].Active then
        PL[i].WorldText(OvlLayerFirst + ID - 1, ' ', 1, ColorGood, 0.01, 0, 0);
    end;
    CbOn[ID][i] := False;
    OvlLabelOn[ID][i] := False;
  end;
  OutQ[ID].Clear;
  PrefKey[ID] := '';
  TeamOf[ID] := -1;
  RevokeGrant(ID);
  SteamId[ID] := '';
  ActiveSlot[ID] := False;
  RecountTop();
  OverlayRecount();
end;

{ Steam confirmed a player after his join: his admin rights, the radar and his saved choices follow
  his Steam id from now on }
procedure SteamReady(ID: Integer);
var
  S: string;
begin
  S := ReadSteam(ID);
  if S = '' then
    Exit;
  if S = SteamId[ID] then
    Exit;
  SteamId[ID] := S;
  PrefsAdopt(ID);
  HudMark(ID, True);
  GrantSteamAdmin(ID);
  OverlayAllow(ID);
  RadarApplyOn(ID);
  RdRedraw[ID] := True;
  OverlayRecount();
  LogWatchCheck(ID);
  if LgEnabled then
    if LgJoins then
      LogLine(ID, PL[ID].Name + ' Steam confirmed: ' + S);
  if RsWait[ID] > 0 then
    ResCheck(ID, True);
end;

{ Steam's answer for a player (AuthState 0 = his account is confirmed). It may come before the join;
  then the join reads the id itself. }
function OnSteamAuthEv(ID: Byte; AuthState: Byte): Byte;
var
  Slot: Integer;
begin
  Result := AuthState;
  Slot := ID;
  if (Slot < 1) or (Slot > 32) then
    Exit;
  if AuthState <> 0 then
    Exit;
  if not ActiveSlot[Slot] then
    Exit;
  try
    SteamReady(Slot);
  except
    StageError('Steam login');
  end;
end;

procedure OnJoinTeamEv(Player: TActivePlayer; Team: TTeam);
var
  ID, Want: Integer;
begin
  ID := Player.ID;
  { [TeamGuard]: a team the game mode does not have (a cheat or a console trick) - the player is put
    into one it has (the game runs this event again for that team) }
  if TgEnabled then
    if Team.ID <> TEAM_SPECTATOR then
    begin
      Want := TeamForMode(Team.ID);
      if Want <> Team.ID then
      begin
        Log(Player.Name + ' joined team ' + IntToStr(Team.ID) + ', which this game mode does not have: moved to team ' +
          IntToStr(Want) + '.');
        Say(ID, 'This game mode has no such team: you were moved.', ColorBad);
        Player.Team := Want;
      end;
    end;
  { read back: the guard or another script may have moved the player again }
  TeamOf[ID] := Player.Team;
  SpecLeft[ID] := 0;
  AfIdle[ID] := 0;
  RdRedraw[ID] := True;
  if LgEnabled then
    if LgJoins then
      LogLine(ID, Player.Name + ' joined ' + TeamName(TeamOf[ID]));
  if Team.ID = TEAM_SPECTATOR then
  begin
    Hurt[ID] := False;
    Regenerating[ID] := False;
    if SiEnabled then
      if Player.Human then
        if Game.NumPlayers >= SiMinPlayers then
          if not (SiIgnoreAdmins and Player.IsAdmin) then
          begin
            SpecLeft[ID] := SiSeconds;
            Say(ID, 'Remember, you cannot idle as spectator forever!', ColorGood);
            Say(ID, 'If you won''t leave or join any team,', ColorGood);
            Say(ID, 'you will be kicked per ' + IntToStr(SiSeconds div 60) + iif(SiSeconds = 60, ' minute.', ' minutes.'),
              ColorGood);
          end;
  end;
  HudMark(ID, True);
end;

procedure OnBeforeMapEv(NewMap: string);
var
  i: Integer;
begin
  PrevMap := Game.CurrentMap;
  MapChanging := True;
  MapChangeTick := Game.TickCount;
  SpawnsCleared := False;
  for i := 1 to TopSlot do
  begin
    Hurt[i] := False;
    Regenerating[i] := False;
  end;
end;

procedure OnAfterMapEv(NewMap: string);
var
  i, j: Integer;
begin
  MapChanging := False;
  { realistic mode may have been switched for this map }
  Realistic := Game.Realistic;
  if Realistic then
    MaxHealth := REALISTIC_HEALTH
  else
    MaxHealth := DEFAULT_HEALTH;
  if KitsAny then
  begin
    KitSpawnsOff();
    KitSweep();
  end;
  SpawnsCleared := False;
  ScanTop := MAX_BULLET_ID;
  VicCount := 0;
  for i := 1 to 32 do
  begin
    VicPend[i] := False;
    ResetLife(i);
    for j := 1 to 32 do
      DnLayer[i][j] := 0;
    HitMarkClear(i);
    RdRedraw[i] := True;
  end;
  if RuAfterMap then
    if RuLines.Count > 0 then
      ShowList(0, RuLines, RuColors, RuColor, 0, True);
  HudMarkAll(True);
  { extras: a new first blood, no medics, no combos }
  FbDone := False;
  TkLeft := 0;
  for i := 0 to 4 do
  begin
    MdOf[i] := 0;
    MdCool[i] := 0;
    MdGiven[i] := 0;
  end;
  for i := 1 to 32 do
  begin
    McCount[i] := 0;
    SvTarget[i] := 0;
    MdWants[i] := False;
  end;
  if LgEnabled then
    if LgMaps then
      LogLine(0, 'map ' + NewMap);
end;

procedure OnTcpEv(Ip: string; Port: Word; Text: string);
begin
  if WhoisLeft > 0 then
    if WaTcp then
      if Length(Text) >= 3 then
        if Copy(Text, 1, 1) = '[' then
          if Copy(Text, 3, 1) = ']' then
            TcpAdmins.Add(Text);
end;

function OnErrorEv(ErrorCode: TErrorType; Message, UnitName, FunctionName: string; Row, Col: Cardinal): Boolean;
begin
  Result := True;
  Errors := Errors + 1;
  if Errors <= ERRORS_SHOWN then
    Log('script error in ' + FunctionName + ' (' + UnitName + ' ' + IntToStr(Row) + ':' + IntToStr(Col) + '): ' +
      Message);
end;

{ ================================ start ================================ }

procedure Startup();
var
  i: Integer;
  Dir: string;
begin
  Started := False;
  Errors := 0;
  Dir := Script.Dir;
  if Dir <> '' then
    if (Copy(Dir, Length(Dir), 1) <> '/') and (Copy(Dir, Length(Dir), 1) <> '\') then
      Dir := Dir + '/';
  DataDir := Dir + 'data/';
  for i := 1 to 32 do
    PL[i] := Players[i];
  for i := 1 to MAX_BULLET_ID do
    BL[i] := Map.Bullets[i];
  for i := 1 to MAX_OBJECT_ID do
    OB[i] := Map.Objects[i];
  for i := 1 to MAX_SPAWN_ID do
    SP[i] := Map.Spawns[i];
  for i := 1 to 32 do
  begin
    ActiveSlot[i] := PL[i].Active;
    RdDrawn[i] := -1;
    EdKind[i] := ED_HUD;
  end;
  RecountTop();
  CfgKeys := File.CreateStringList();
  ChatWords := File.CreateStringList();
  SlashWords := File.CreateStringList();
  ClLines := File.CreateStringList();
  ClAutoLines := File.CreateStringList();
  OvlSteams := File.CreateStringList();
  AdSteams := File.CreateStringList();
  AdSteamRaw := File.CreateStringList();
  RsList := File.CreateStringList();
  LgWatch := File.CreateStringList();
  RuLines := File.CreateStringList();
  TiAll := File.CreateStringList();
  TiLeft := File.CreateStringList();
  AdListLines := File.CreateStringList();
  TcpAdmins := File.CreateStringList();
  OutAll := File.CreateStringList();
  for i := 1 to 32 do
    OutQ[i] := File.CreateStringList();
  { the library: the players' store (it takes over an older data/players.txt once) and the logger }
  BeOk := False;
  i := BE_Init(PChar(DataDir), BE_API);
  if i = BE_API then
    BeOk := True
  else if i < 0 then
    Log('basicext_dll comes from another release (API ' + IntToStr(-i) + ', main.pas needs ' + IntToStr(BE_API) +
      '): the players'' choices are not kept, the logger does not write')
  else
    Log('basicext_dll could not start: the players'' choices are not kept, the logger does not write');
  if File.Exists(DataDir + 'granted_admins.txt') then
    GrantList := File.CreateStringListFromFile(DataDir + 'granted_admins.txt')
  else
    GrantList := File.CreateStringList();
  for i := GrantList.Count - 1 downto 0 do
    if Trim(GrantList[i]) = '' then
      GrantList.Delete(i);

  Script.OnUnhandledException := @OnErrorEv;
  LoadAll();
  Realistic := Game.Realistic;
  if Realistic then
    MaxHealth := REALISTIC_HEALTH
  else
    MaxHealth := DEFAULT_HEALTH;
  PrevMap := Game.CurrentMap;
  MapChanging := False;
  SpawnsCleared := False;
  ScanTop := MAX_BULLET_ID;
  PendHead := 0;
  PendCount := 0;
  DnPendCount := 0;
  VicCount := 0;
  OutPending := 0;
  EdCount := 0;
  HurtCount := 0;
  WhoisLeft := 0;
  LastFlush := 0;
  StatSince := Game.TickCount;
  LastTickSeen := Game.TickCount;
  DueTip := After(Game.TickCount, TiTicks);
  DueWelcome := After(Game.TickCount, WeTicks);
  DuePing := After(Game.TickCount, SpTicks);

  { the script may be loaded in the middle of a map }
  for i := 1 to 32 do
  begin
    SeenTick[i] := -1;
    GrantedIp[i] := '';
    if PL[i].Active then
    begin
      SetupPlayer(i);
      GrantSteamAdmin(i);
    end
    else
    begin
      PrefsClear(i);
      SteamId[i] := '';
      TeamOf[i] := -1;
    end;
  end;
  for i := 1 to 32 do
    if PL[i].Active then
      if PL[i].Human then
        DropStaleGrant(i);
  for i := 0 to GrantList.Count - 1 do
    Log('remote.txt holds ' + GrantList[i] + ', made admin for ' + AdSteamFile + ' earlier; it is taken out when ' +
      'that player leaves, or when somebody else joins from that address');
  if KitsAny then
  begin
    KitSpawnsOff();
    KitSweep();
  end;
  if MapsShuffle then
    ShuffleMapsList();

  Game.OnJoin := @OnJoinGameEv;
  Game.OnLeave := @OnLeaveGameEv;
  Game.OnAdminCommand := @OnAdminCommandEv;
  Game.OnTCPMessage := @OnTcpEv;
  Game.OnSteamAuth := @OnSteamAuthEv;
  Map.OnBeforeMapChange := @OnBeforeMapEv;
  Map.OnAfterMapChange := @OnAfterMapEv;
  for i := 0 to 5 do
    Game.Teams[i].OnJoin := @OnJoinTeamEv;
  for i := 1 to 32 do
  begin
    PL[i].OnSpeak := @OnSpeakEv;
    PL[i].OnCommand := @OnCommandEv;
    PL[i].OnDamage := @OnDamageEv;
    PL[i].OnKill := @OnKillEv;
    PL[i].OnAfterRespawn := @OnRespawnEv;
    PL[i].OnKitPickup := @OnKitEv;
  end;
  OverlayRecount();
  HudMarkAll(True);
  Game.TickThreshold := 1;
  Game.OnClockTick := @OnTick;
  Started := True;
  { like Basic 2.0.2: the players see that the script is running again after a recompile }
  if StartMessage <> '' then
    SayAll(ReplaceAll(StartMessage, '{version}', VERSION), $FFAA00);
  Log(VERSION + ' started (' + IntToStr(ChatWords.Count + SlashWords.Count) + ' command words, health ' +
    IntToStr(Round(MaxHealth)) + ').');
end;

{ the script is unloaded (/recompile, or an error it could not handle): the health texts go away and
  the admin rights it gave are taken back }
procedure CleanUp();
var
  i: Integer;
begin
  if not Started then
    Exit;
  Started := False;
  try
    for i := 1 to 32 do
      if PL[i].Active then
      begin
        if HudShown[i] then
          PL[i].BigText(HudLayer, ' ', 1, ColorGood, 0.01, 0, 0);
        OverlayHide(i);
        RevokeGrant(i);
      end;
  except
  end;
  { the library writes what is pending and stops its thread }
  if BeOk then
  begin
    BeOk := False;
    BE_Shutdown();
  end;
end;

initialization
begin
  Startup();
end;

finalization
begin
  CleanUp();
end;

end.
