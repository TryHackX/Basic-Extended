unit be_body;

{$mode objfpc}{$H+}
{$Q-}{$IFNDEF BE_CHECKS}{$R-}{$ENDIF}

{ [Bleeding] and [Downed]: what the hits do to a soldier's body over time, looked after in every tick of the
  script (BdTick):

  - a hit may open a wound (BdHit): the chance grows with the damage (a share of the maximum health) and with
    the place it hit - the head and neck, the torso, the legs, found on the skeleton the way the server finds
    it (BdHitPart); a blast opens several (shrapnel), a blade cuts deeper, fire and fists open none. A graze
    stops by itself, a heavy wound bleeds until it is bandaged, an arterial one bleeds fast;
  - the blood (100 at spawn) runs out at the sum of the open wounds' rates and comes back slowly when none
    bleeds; below WeakBlood he loses health (BDE_DRAIN), below ShockBlood he may fall into shock (frozen, a
    black screen: BDE_SHOCK), at DeathBlood he bleeds out: at once (BDE_BLED - the script puts him down or kills
    him as the one who opened his worst wound), or with OutMode 1 his health drains faster and faster while a
    wound bleeds (BDE_FADING once, then BDE_DRAIN twice a second; the script kills him when it is gone);
  - staying low and still with an open wound bandages it (by itself, or asked for with BdWant): 1-4 s by the
    wound's kind, the bandage (100 at spawn) used up in percent by the kind; a first-aid kit closes every
    wound and gives blood back (and gets a downed soldier up with SelfRevive); falling freely without a key
    held (BdAir, with BDC_AIR) counts as low and still for bandaging; a medic (BdMedic) with no wound of his own
    to bandage bandages his wounded mates within his reach with his own bandage (BDE_TREAT, BDE_TREATED); a part
    his vest covers (BdCover, for the next hit) opens no wound;
  - a downed soldier (BdDown, the script's [Downed]) lies until DownTicks run out (BDE_DOWN_END) or a team mate
    stays low next to him for ReviveTicks (BDE_REVIVED); when nobody of his team who could help is left
    (LastStand), his time ends at once.

  The script tells the lives and deaths (BdPlayer, from BE_TkPlayer), whether a soldier is a player
  (BdHuman) and where a soldier stands whose record the library does not know (BdWants, BdPos). The soldiers
  are their skeletons and stances as the server has them (be_sprite); only where the stance is not known
  the script tells the crouch and prone keys of the soldiers the library asks about (BdNear, BdLow). Shots
  come from the hook (BdShot): a shot stops his bandaging, and the shots and grenades of a soldier who is
  down or in shock are taken out as the server makes them (BdMuted). }

interface

uses
  be_hook;

const
  MAX_WOUNDS = 8;
  { the kinds of wounds }
  WK_GRAZE = 1;
  WK_HEAVY = 2;
  WK_ARTERY = 3;
  { the places (the server's body parts: 12 the head, 10 the torso, 3 the legs; 0 = a blast, spread) }
  WP_HEAD = 12;
  WP_TORSO = 10;
  WP_LEGS = 3;
  WP_BLAST = 0;
  { the work of a soldier }
  BW_NONE = 0;
  BW_BANDAGE = 1;
  BW_KIT = 2;
  BW_REVIVE = 3;
  { how a wound closed }
  BC_CLOTTED = 1;
  BC_BANDAGE = 2;
  BC_KIT = 3;
  BC_HEALED = 4;
  { the events: Kind, ID (a soldier), P, Q }
  BDE_WOUND = 1;
  BDE_CLOSED = 2;
  BDE_WORK = 3;
  BDE_WORK_STOP = 4;
  BDE_BANDAGED = 5;
  BDE_KIT = 6;
  BDE_DRAIN = 7;
  BDE_SHOCK = 8;
  BDE_SHOCK_END = 9;
  BDE_BLED = 10;
  BDE_DOWN_END = 11;
  BDE_REVIVED = 12;
  BDE_HUD = 13;
  BDE_NO_BANDAGE = 14;
  { he bleeds out (OutMode 1): his health drains fast from now on }
  BDE_FADING = 15;
  { a medic (ID) starts bandaging a mate (P), his wound's kind Q; done: BDE_TREATED (ID the medic, P the mate, Q the
    kind) }
  BDE_TREAT = 16;
  BDE_TREATED = 17;
  { why a downed soldier's time ended (BDE_DOWN_END Q) }
  DE_TIME = 0;
  DE_GAVE_UP = 1;
  DE_ALONE = 2;
  DE_BLED = 3;
  { BdSet keys }
  BDC_ON = 1;
  BDC_DOWN = 2;
  BDC_CRIT = 3;
  BDC_CRIT_DMG = 4;
  BDC_HEAD = 5;
  BDC_TORSO = 6;
  BDC_LEGS = 7;
  BDC_ART_SHARE = 8;
  BDC_HEAVY_SHARE = 9;
  BDC_RATE1 = 10;
  BDC_RATE2 = 11;
  BDC_RATE3 = 12;
  BDC_CLOT1 = 13;
  BDC_CLOT2 = 14;
  BDC_CLOT3 = 15;
  BDC_BLAST = 16;
  BDC_WEAK = 18;
  BDC_SHOCK = 19;
  BDC_DEATH = 20;
  BDC_DRAIN = 21;
  BDC_SHOCK_EVERY = 22;
  BDC_SHOCK_CHANCE = 23;
  BDC_SHOCK_TICKS = 24;
  BDC_REGEN = 25;
  BDC_REGEN_DELAY = 26;
  BDC_BANDAGE = 27;
  BDC_BAND_T1 = 28;
  BDC_BAND_T2 = 29;
  BDC_BAND_T3 = 30;
  BDC_BAND_C1 = 31;
  BDC_BAND_C2 = 32;
  BDC_BAND_C3 = 33;
  BDC_BAND_LOW = 34;
  BDC_BAND_AUTO = 35;
  BDC_AUTO_DELAY = 36;
  BDC_KITS = 37;
  BDC_KIT_TICKS = 38;
  BDC_KIT_BLOOD = 39;
  BDC_DOWN_TICKS = 40;
  BDC_REVIVE_R = 41;
  BDC_REVIVE_TICKS = 42;
  BDC_REVIVE_LOW = 43;
  BDC_SELF_REVIVE = 44;
  BDC_BOTS_REVIVE = 45;
  BDC_DOWN_BLEED = 46;
  BDC_STILL = 47;
  BDC_BOTS = 48;
  BDC_BOT_BANDAGE = 49;
  BDC_LAST_STAND = 50;
  BDC_TEAMS = 51;
  BDC_KIT_LOW = 52;
  BDC_MELEE = 53;
  { a light wound stops after a random time between Clot1Min and Clot1 ticks (1 = on) }
  BDC_CLOT_RANDOM = 54;
  BDC_CLOT1_MIN = 55;
  { the health a hit's share is measured against (0 = the server's maximum health): the same odds in both modes }
  BDC_REF_HP = 56;
  { at most this many open wounds of each kind (a graze, a heavy one, an arterial one; 0 = no limit): a hit that
    would open one more of a full kind opens none }
  BDC_MAX1 = 57;
  BDC_MAX2 = 58;
  BDC_MAX3 = 59;
  { at DeathBlood: 0 = he bleeds out at once, 1 = his health drains, OutDrain percent of the maximum health a second
    more and OutGrow more for every point of blood under DeathBlood, while a wound bleeds }
  BDC_OUT_MODE = 60;
  BDC_OUT_DRAIN = 61;
  BDC_OUT_GROW = 62;
  { falling freely without a key held (BdAir) counts as low and still for bandaging (1 = on) }
  BDC_AIR = 63;
  { the parts a vest covers (BdCover) }
  COVER_HEAD = 1;
  COVER_TORSO = 2;
  COVER_LEGS = 4;

procedure BdSet(Key: LongInt; Value: Single);
{ the team (0 none, 1-4, 5 spectators) and whether he lives (BE_TkPlayer) }
procedure BdPlayer(ID, NewTeam, IsAlive: LongInt);
procedure BdHuman(ID, Human: LongInt);
{ a new life: full blood, no wounds, a full bandage, Kits first-aid kits }
procedure BdSpawn(ID, Tick: LongInt);
{ a new player in the slot, a map start: his life is forgotten (his team, whether he lives and whether he is a
  player stay as BdPlayer and BdHuman told them); the wounds he gave others no longer name him }
procedure BdForget(ID: LongInt);
{ everything of a slot (the library's start) }
procedure BdReset(ID: LongInt);
{ his bandage (percent) and first-aid kits: set (Add = 0: kept from the last round) or given (Add = 1: a
  bounty's reward, a supply) }
procedure BdSupplies(ID: LongInt; Band: Single; Kits, Add: LongInt);
{ where a soldier the library does not know stands (his feet) and whether he crouches or lies }
procedure BdPos(ID: LongInt; X, Y: Single; Low: LongInt);
{ the slots (bit ID - 1) the script should tell about with BdPos }
function BdWants: LongWord;
{ whether he holds crouch or lies now (the soldiers of BdNear) }
procedure BdLow(ID, Low: LongInt);
{ the soldiers whose crouch and prone keys the library needs for the next tick (bit ID - 1) }
function BdNear: LongWord;
{ which of the server's body parts bullet (X, Y, going VX, VY; bullet style Style) hit soldier V: WP_HEAD,
  WP_TORSO, WP_LEGS (0 = not known) }
function BdHitPart(V, Style: LongInt; X, Y, VX, VY: Single): LongInt;
{ a hit on V by By's weapon W (bullet style Style) of Damage, his maximum health MaxHP, at Part: the kind of
  the wound it opened (0 = none) }
function BdHit(V, By, W, Style: LongInt; Damage, MaxHP: Single; Part, Tick: LongInt): LongInt;
{ he asks for work: BW_BANDAGE or BW_KIT (0 = he no longer wants it); the result: 1 it can start (when he
  stays still), 0 there is nothing to do, -1 no bandage left for his wound, -2 no kit }
function BdWant(ID, What: LongInt): LongInt;
{ healed from outside: How = BC_KIT (a health kit: every wound closed, blood back), BC_HEALED (a medic, a
  healing polygon: the grazes close, Blood percent back) }
procedure BdHeal(ID, How: LongInt; Blood: Single);
{ he is down (the script's [Downed]) since Tick, put down by By with W }
procedure BdDown(ID, By, W, Tick: LongInt);
procedure BdGiveUp(ID: LongInt);
{ a shot of the hook: it stops his bandaging }
procedure BdShot(const E: TShotEvent);
{ his bullets are taken out as they are made: he is down or in shock (integers only: called inside the
  server's CreateBullet) }
function BdMuted(ID: LongInt): Boolean;
function BdTick(Tick: LongInt): LongInt;
function BdNext(out Kind, ID, P, Q: LongInt): Boolean;
{ his state for the texts: blood percent, the worst open wound's kind (0 none), open wounds, bandage percent,
  kits; work (BW_*) and its share done (0-100); 1 down, 2 in shock }
procedure BdGet(ID: LongInt; out Blood: Single; out Worst, Wounds: LongInt; out Band: Single; out Kits, Work,
  Pct, State: LongInt);
{ the soldier he works on (a revive: the downed mate), 0 = none; the soldier who helps him up, 0 = none }
function BdWorkOn(ID: LongInt): LongInt;
function BdHelper(ID: LongInt): LongInt;
{ the one who opened his worst wound and his weapon (a bleeding out's kill), 0 = nobody known }
function BdCulprit(ID: LongInt; out W: LongInt): LongInt;
{ the ticks left while down (0 = not down) }
function BdDownLeft(ID, Tick: LongInt): LongInt;
{ his open wounds by place for the blood line: per place (byte 0 the head, 1 the torso, 2 the legs, 3 none) bits 0-3
  the wounds there, bits 4-5 the worst kind, bit 6 shrapnel among them; Rate = the blood he loses a second in
  hundredths of a percent; Left = the seconds until he bleeds out at that rate (-1 = not bleeding) }
function BdPlaces(ID: LongInt; out Rate, Left: LongInt): LongInt;
{ round 26: the texts of the blood line's wound list - 0 a place's part (its tokens: place, kind, many), 1 the
  many (its token: count), 2-5 the places (head, torso, legs, shrapnel), 6-8 the kinds (light, heavy, arterial) }
procedure BdHudText(Kind: LongInt; const Text: AnsiString);
{ his open wounds as the blood line's list ('' = none): one part per place, joined by ', ' }
function BdWoundList(ID: LongInt): AnsiString;
{ a transfusion: Blood percent more within Ticks (0 = at once), never over 100 }
procedure BdTransfuse(ID: LongInt; Blood: Single; Ticks: LongInt);
{ his class's perks: his bandaging BandF times faster; the downed he helps up ReviveF times faster, from ReviveR px
  (0 = the setting's) }
procedure BdPerk(ID: LongInt; BandF, ReviveF, ReviveR: Single);
{ he falls freely without a key held this tick (the script tells it every tick for the soldiers who bleed) }
procedure BdAir(ID, Free: LongInt);
{ a medic: with no wound of his own to bandage he bandages the wounded mates within R px (0 = not a medic) }
procedure BdMedic(ID: LongInt; R: Single);
{ the parts his vest covers for the next hit (COVER_* bits): no wound opens there }
procedure BdCover(ID, Mask: LongInt);
{ the game was paused Delta ticks: every tick kept moves on by them (nothing runs out during a pause) }
procedure BdShift(Delta: LongInt);
function BdInfo: AnsiString;

var
  { a point of a soldier's body (be_sprite's SpritePoint) and his stance (SpriteStance: 1 standing, 2
    crouching, 4 lying, 0 not known); a test sets its own }
  BdPoint: function(ID, K: LongInt; out X, Y: Single): Boolean = nil;
  BdStance: function(ID: LongInt): LongInt = nil;

implementation

uses
  SysUtils, be_sprite, be_util;

const
  MAX_ID = 32;
  EVENTS = 256;
  { a soldier whose neck is less than this over his lower foot crouches or lies (be_mine's measure) }
  LOW_NECK = 12.5;
  { the server's hit circles: the body parts in the order it tries them, their radius, 2 px to the left }
  PART_R = 7;
  HITPARTS: array[0..6] of LongInt = (12, 11, 10, 6, 5, 4, 3);
  { the ticks a soldier's upper body is followed for "still" }
  STILL_SPAN = 8;
  { a shot this recent stops the bandaging }
  SHOT_TICKS = 20;

type
  TWound = record
    Kind, Part: LongInt;
    { a blast's shrapnel (Part: where it struck) }
    Blast: Boolean;
    { blood percent a tick }
    Rate: Single;
    { the tick it stops by itself (0 = never) }
    Stop: LongInt;
    By, W, Tick: LongInt;
    { the ticks of bandaging it already had (kept when the work stopped) }
    Done: LongInt;
  end;

  TBody = record
    Alive, Human, Low: Boolean;
    Team, LowGen: LongInt;
    { the upper body now and STILL_SPAN ticks ago (a ring of places) }
    PX, PY: array[0..STILL_SPAN - 1] of Single;
    PN: LongInt;
    FallX, FallY: Single;
    FallTick: LongInt;
    FallLow: Boolean;
    Blood: Single;
    Wounds: array[0..MAX_WOUNDS - 1] of TWound;
    WN: LongInt;
    Band: Single;
    Kits: LongInt;
    Work, WorkOn, WorkStart, WorkNeed, Want: LongInt;
    { since when he is ready for his work (low and still), 0 = not }
    ReadySince: LongInt;
    ShockUntil, NextShock: LongInt;
    Dying: Boolean;
    Down: Boolean;
    DownEnd, DownBy, DownW, Helper: LongInt;
    DownAt: LongInt;
    LastShot, LastClosed, LastWound, NextDrain: LongInt;
    { what his text showed last }
    HudBlood, HudWorst, HudWN, HudBand, HudKits, HudPlaces: LongInt;
    { a transfusion: the blood still to come and a tick's share }
    TransLeft, TransStep: Single;
    { his class's perks }
    BandF, ReviveF, ReviveR2: Single;
    { falling freely without a key (the tick the script told it), a medic's reach, the parts covered for the next
      hit, the medic bandaging him, his health draining fast (bleeding out with OutMode 1) }
    Air: Boolean;
    AirGen: LongInt;
    MedicR: Single;
    Cover, TreatBy: LongInt;
    OutOn: Boolean;
    { who opened his last wound in this life, and with what (a death by low blood after the wounds closed) }
    LastBy, LastW: LongInt;
  end;

  TEvent = record
    Kind, ID, P, Q: LongInt;
  end;

var
  BdOn: Boolean = False;
  DownOn: Boolean = False;
  Crit: Single = 60;
  CritDmg: Single = 25;
  FHead: Single = 1.3;
  FTorso: Single = 1;
  FLegs: Single = 1.2;
  ArtShare: Single = 12;
  HeavyShare: Single = 45;
  Rates: array[1..3] of Single = (0.3, 1, 3);
  Clots: array[1..3] of LongInt = (1500, 0, 0);
  ClotRandom: Boolean = True;
  Clot1Min: LongInt = 480;
  BlastMax: LongInt = 3;
  WeakB: Single = 75;
  ShockB: Single = 55;
  DeathB: Single = 40;
  Drain: Single = 1;
  ShockEvery: LongInt = 300;
  ShockChance: Single = 35;
  ShockTicks: LongInt = 180;
  Regen: Single = 0.25;
  RegenDelay: LongInt = 600;
  BandFull: Single = 100;
  BandT: array[1..3] of LongInt = (60, 150, 240);
  BandC: array[1..3] of Single = (10, 25, 40);
  BandLow: Boolean = True;
  BandAuto: Boolean = True;
  AutoDelay: LongInt = 30;
  KitsLife: LongInt = 1;
  KitTicks: LongInt = 300;
  KitBlood: Single = 25;
  KitLow: Boolean = False;
  DownTicks: LongInt = 1200;
  ReviveR: Single = 30;
  ReviveTicks: LongInt = 240;
  ReviveLow: Boolean = True;
  SelfRevive: Boolean = True;
  BotsRevive: Boolean = True;
  DownBleed: Boolean = True;
  StillPx: Single = 0.6;
  BotsBleed: Boolean = True;
  BotBandage: LongInt = 600;
  LastStand: Boolean = True;
  Teams: Boolean = True;
  Melee: Single = 2;
  RefHP: Single = 0;
  KindMax: array[1..3] of LongInt = (0, 0, 0);
  OutMode: LongInt = 0;
  OutDrain: Single = 5;
  OutGrow: Single = 1;
  AirOn: Boolean = False;
  CntTreated: LongInt = 0;
  B: array[1..MAX_ID] of TBody;
  Ev: array[0..EVENTS - 1] of TEvent;
  EvHead: LongInt = 0;
  EvTail: LongInt = 0;
  CurTick: LongInt = 0;
  Gen: LongInt = 0;
  Wanted: LongWord = 0;
  NearMask: LongWord = 0;
  CntWounds: LongInt = 0;
  CntBandaged: LongInt = 0;
  CntKits: LongInt = 0;
  CntShocks: LongInt = 0;
  CntBled: LongInt = 0;
  CntDowned: LongInt = 0;
  CntRevived: LongInt = 0;
  CntParts: array[0..3] of LongInt;

function Valid(ID: LongInt): Boolean;
begin
  Result := (ID >= 1) and (ID <= MAX_ID);
end;

function Bit(ID: LongInt): LongWord;
begin
  Result := LongWord(1) shl (ID - 1);
end;

function FMax(A, C: Single): Single;
begin
  if A > C then
    Result := A
  else
    Result := C;
end;

procedure Push(Kind, ID, P, Q: LongInt);
var
  k: LongInt;
begin
  Ev[EvHead].Kind := Kind;
  Ev[EvHead].ID := ID;
  Ev[EvHead].P := P;
  Ev[EvHead].Q := Q;
  k := (EvHead + 1) mod EVENTS;
  if k = EvTail then
    EvTail := (EvTail + 1) mod EVENTS;
  EvHead := k;
end;

procedure BdSet(Key: LongInt; Value: Single);
begin
  case Key of
    BDC_ON: BdOn := Value <> 0;
    BDC_DOWN: DownOn := Value <> 0;
    BDC_CRIT: if (Value >= 0) and (Value <= 100) then Crit := Value;
    BDC_CRIT_DMG: if (Value > 0) and (Value <= 100) then CritDmg := Value;
    BDC_HEAD: if Value >= 0 then FHead := Value;
    BDC_TORSO: if Value >= 0 then FTorso := Value;
    BDC_LEGS: if Value >= 0 then FLegs := Value;
    BDC_ART_SHARE: if (Value >= 0) and (Value <= 100) then ArtShare := Value;
    BDC_HEAVY_SHARE: if (Value >= 0) and (Value <= 100) then HeavyShare := Value;
    BDC_RATE1: if Value >= 0 then Rates[1] := Value;
    BDC_RATE2: if Value >= 0 then Rates[2] := Value;
    BDC_RATE3: if Value >= 0 then Rates[3] := Value;
    BDC_CLOT1: if Value >= 0 then Clots[1] := Round(Value);
    BDC_CLOT2: if Value >= 0 then Clots[2] := Round(Value);
    BDC_CLOT3: if Value >= 0 then Clots[3] := Round(Value);
    BDC_BLAST: if (Value >= 0) and (Value <= MAX_WOUNDS) then BlastMax := Round(Value);
    BDC_WEAK: if (Value >= 0) and (Value <= 100) then WeakB := Value;
    BDC_SHOCK: if (Value >= 0) and (Value <= 100) then ShockB := Value;
    BDC_DEATH: if (Value >= 0) and (Value <= 100) then DeathB := Value;
    BDC_DRAIN: if Value >= 0 then Drain := Value;
    BDC_SHOCK_EVERY: if Value >= 1 then ShockEvery := Round(Value);
    BDC_SHOCK_CHANCE: if (Value >= 0) and (Value <= 100) then ShockChance := Value;
    BDC_SHOCK_TICKS: if Value >= 0 then ShockTicks := Round(Value);
    BDC_REGEN: if Value >= 0 then Regen := Value;
    BDC_REGEN_DELAY: if Value >= 0 then RegenDelay := Round(Value);
    BDC_BANDAGE: if Value >= 0 then BandFull := Value;
    BDC_BAND_T1: if Value >= 1 then BandT[1] := Round(Value);
    BDC_BAND_T2: if Value >= 1 then BandT[2] := Round(Value);
    BDC_BAND_T3: if Value >= 1 then BandT[3] := Round(Value);
    BDC_BAND_C1: if Value >= 0 then BandC[1] := Value;
    BDC_BAND_C2: if Value >= 0 then BandC[2] := Value;
    BDC_BAND_C3: if Value >= 0 then BandC[3] := Value;
    BDC_BAND_LOW: BandLow := Value <> 0;
    BDC_BAND_AUTO: BandAuto := Value <> 0;
    BDC_AUTO_DELAY: if Value >= 0 then AutoDelay := Round(Value);
    BDC_KITS: if Value >= 0 then KitsLife := Round(Value);
    BDC_KIT_TICKS: if Value >= 1 then KitTicks := Round(Value);
    BDC_KIT_BLOOD: if Value >= 0 then KitBlood := Value;
    BDC_DOWN_TICKS: if Value >= 1 then DownTicks := Round(Value);
    BDC_REVIVE_R: if Value > 0 then ReviveR := Value;
    BDC_REVIVE_TICKS: if Value >= 1 then ReviveTicks := Round(Value);
    BDC_REVIVE_LOW: ReviveLow := Value <> 0;
    BDC_SELF_REVIVE: SelfRevive := Value <> 0;
    BDC_BOTS_REVIVE: BotsRevive := Value <> 0;
    BDC_DOWN_BLEED: DownBleed := Value <> 0;
    BDC_STILL: if Value >= 0 then StillPx := Value;
    BDC_BOTS: BotsBleed := Value <> 0;
    BDC_BOT_BANDAGE: if Value >= 0 then BotBandage := Round(Value);
    BDC_LAST_STAND: LastStand := Value <> 0;
    BDC_TEAMS: Teams := Value <> 0;
    BDC_KIT_LOW: KitLow := Value <> 0;
    BDC_MELEE: if Value >= 0 then Melee := Value;
    BDC_CLOT_RANDOM: ClotRandom := Value <> 0;
    BDC_CLOT1_MIN: if Value >= 0 then Clot1Min := Round(Value);
    BDC_REF_HP: if Value >= 0 then RefHP := Value;
    BDC_MAX1: if (Value >= 0) and (Value <= MAX_WOUNDS) then KindMax[1] := Round(Value);
    BDC_MAX2: if (Value >= 0) and (Value <= MAX_WOUNDS) then KindMax[2] := Round(Value);
    BDC_MAX3: if (Value >= 0) and (Value <= MAX_WOUNDS) then KindMax[3] := Round(Value);
    BDC_OUT_MODE: if (Value >= 0) and (Value <= 1) then OutMode := Round(Value);
    BDC_OUT_DRAIN: if Value >= 0 then OutDrain := Value;
    BDC_OUT_GROW: if Value >= 0 then OutGrow := Value;
    BDC_AIR: AirOn := Value <> 0;
  end;
end;

{ ---------------- the soldiers ---------------- }

procedure ClearWork(ID: LongInt);
var
  P: LongInt;
begin
  { his patient may bandage himself again, and another medic may treat him }
  if B[ID].Work = BW_BANDAGE then
  begin
    P := B[ID].WorkOn;
    if (P >= 1) and (P <= MAX_ID) then
      if B[P].TreatBy = ID then
        B[P].TreatBy := 0;
  end;
  B[ID].Work := BW_NONE;
  B[ID].WorkOn := 0;
  B[ID].WorkStart := 0;
  B[ID].WorkNeed := 0;
  B[ID].ReadySince := 0;
end;

procedure ClearLife(ID: LongInt);
var
  k: LongInt;
begin
  B[ID].Blood := 100;
  B[ID].WN := 0;
  B[ID].Band := BandFull;
  B[ID].Kits := KitsLife;
  ClearWork(ID);
  B[ID].Want := BW_NONE;
  B[ID].ShockUntil := 0;
  B[ID].NextShock := 0;
  B[ID].Dying := False;
  B[ID].Down := False;
  B[ID].DownEnd := 0;
  B[ID].DownBy := 0;
  B[ID].DownW := -1;
  B[ID].Helper := 0;
  B[ID].LastShot := -1000000;
  B[ID].LastClosed := -1000000;
  B[ID].LastWound := -1000000;
  B[ID].NextDrain := 0;
  B[ID].PN := 0;
  B[ID].HudBlood := 100;
  B[ID].HudWorst := 0;
  B[ID].HudWN := 0;
  B[ID].HudBand := Round(BandFull);
  B[ID].HudKits := KitsLife;
  B[ID].HudPlaces := 0;
  B[ID].TransLeft := 0;
  B[ID].TransStep := 0;
  B[ID].Air := False;
  B[ID].AirGen := 0;
  B[ID].Cover := 0;
  B[ID].TreatBy := 0;
  B[ID].OutOn := False;
  B[ID].LastBy := 0;
  B[ID].LastW := -1;
  for k := 1 to MAX_ID do
  begin
    if B[k].WorkOn = ID then
    begin
      { a medic bandaging him stops (a helper of a downed one is told by FreeHelpers) }
      if B[k].Work = BW_BANDAGE then
        Push(BDE_WORK_STOP, k, BW_BANDAGE, 0);
      ClearWork(k);
    end;
    if B[k].TreatBy = ID then
      B[k].TreatBy := 0;
  end;
end;

{ the helpers of downed D stop (he is up, dead or gave up) }
procedure FreeHelpers(D: LongInt);
var
  k: LongInt;
begin
  for k := 1 to MAX_ID do
    if (B[k].Work = BW_REVIVE) and (B[k].WorkOn = D) then
    begin
      Push(BDE_WORK_STOP, k, BW_REVIVE, 0);
      ClearWork(k);
    end;
  B[D].Helper := 0;
end;

{ the events of his not handed over yet that mean nothing once he is dead (a wound of the killing hit, his line,
  the drain, a shock) }
procedure CancelEvents(ID: LongInt);
var
  k: LongInt;
begin
  k := EvTail;
  while k <> EvHead do
  begin
    if Ev[k].ID = ID then
      if (Ev[k].Kind = BDE_WOUND) or (Ev[k].Kind = BDE_HUD) or (Ev[k].Kind = BDE_DRAIN) or (Ev[k].Kind = BDE_SHOCK) then
        Ev[k].Kind := 0;
    k := (k + 1) mod EVENTS;
  end;
end;

procedure BdPlayer(ID, NewTeam, IsAlive: LongInt);
begin
  if not Valid(ID) then
    Exit;
  B[ID].Team := NewTeam;
  if IsAlive = 0 then
  begin
    if B[ID].Alive then
    begin
      { his wounds end with his life; whoever helped him stops }
      B[ID].Alive := False;
      B[ID].WN := 0;
      B[ID].Down := False;
      B[ID].ShockUntil := 0;
      B[ID].TransLeft := 0;
      ClearWork(ID);
      B[ID].Want := BW_NONE;
      FreeHelpers(ID);
      CancelEvents(ID);
    end;
    B[ID].FallTick := 0;
  end
  else
    B[ID].Alive := True;
end;

procedure BdHuman(ID, Human: LongInt);
begin
  if Valid(ID) then
    B[ID].Human := Human <> 0;
end;

procedure BdSpawn(ID, Tick: LongInt);
begin
  if not Valid(ID) then
    Exit;
  CurTick := Tick;
  ClearLife(ID);
  B[ID].Alive := True;
  B[ID].NextDrain := Tick + 60;
end;

procedure BdForget(ID: LongInt);
var
  v, k: LongInt;
begin
  if not Valid(ID) then
    Exit;
  ClearLife(ID);
  B[ID].Low := False;
  B[ID].LowGen := 0;
  B[ID].FallTick := 0;
  B[ID].BandF := 1;
  B[ID].ReviveF := 1;
  B[ID].ReviveR2 := 0;
  B[ID].MedicR := 0;
  { a bleeding out later must not credit whoever takes this slot }
  for v := 1 to MAX_ID do
  begin
    for k := 0 to B[v].WN - 1 do
      if B[v].Wounds[k].By = ID then
        B[v].Wounds[k].By := 0;
    if B[v].DownBy = ID then
      B[v].DownBy := 0;
    if B[v].LastBy = ID then
      B[v].LastBy := 0;
  end;
end;

procedure BdReset(ID: LongInt);
begin
  if not Valid(ID) then
    Exit;
  BdForget(ID);
  B[ID].Alive := False;
  B[ID].Human := False;
  B[ID].Team := 0;
end;

procedure BdSupplies(ID: LongInt; Band: Single; Kits, Add: LongInt);
begin
  if not Valid(ID) then
    Exit;
  if Add <> 0 then
  begin
    B[ID].Band := B[ID].Band + Band;
    B[ID].Kits := B[ID].Kits + Kits;
  end
  else
  begin
    B[ID].Band := Band;
    B[ID].Kits := Kits;
  end;
  if B[ID].Band < 0 then
    B[ID].Band := 0;
  if B[ID].Band > 1000 then
    B[ID].Band := 1000;
  if B[ID].Kits < 0 then
    B[ID].Kits := 0;
end;

procedure BdPos(ID: LongInt; X, Y: Single; Low: LongInt);
begin
  if not Valid(ID) then
    Exit;
  B[ID].FallX := X;
  B[ID].FallY := Y;
  B[ID].FallLow := Low <> 0;
  B[ID].Low := Low <> 0;
  B[ID].LowGen := Gen + 1;
  B[ID].FallTick := CurTick;
  if B[ID].FallTick = 0 then
    B[ID].FallTick := 1;
end;

function BdWants: LongWord;
begin
  Result := Wanted;
end;

procedure BdLow(ID, Low: LongInt);
begin
  if not Valid(ID) then
    Exit;
  B[ID].Low := Low <> 0;
  B[ID].LowGen := Gen + 1;
end;

function BdNear: LongWord;
begin
  Result := NearMask;
end;

{ a point of his body: the skeleton, else what the script told (his feet, a point up to 12 px over them) }
function Pt(ID, K: LongInt; out X, Y: Single): Boolean;
begin
  Result := False;
  X := 0;
  Y := 0;
  if Assigned(BdPoint) then
    Result := BdPoint(ID, K, X, Y);
  if Result then
    Exit;
  if B[ID].FallTick = 0 then
    Exit;
  if CurTick - B[ID].FallTick > 3 then
    Exit;
  X := B[ID].FallX;
  Y := B[ID].FallY;
  case K of
    1, 2, 3, 4, 17, 18: Y := Y - 3;
    9, 12: if B[ID].FallLow then Y := Y - 8 else Y := Y - 17;
  else
    if B[ID].FallLow then
      Y := Y - 4
    else
      Y := Y - 10;
  end;
  Result := True;
end;

{ the server knows his stance }
function StanceKnown(ID: LongInt): Boolean;
begin
  Result := False;
  if Assigned(BdStance) then
    Result := BdStance(ID) > 0;
end;

{ crouching or lying: the stance the server has, else the key the script read (this tick or the last) and,
  with a skeleton, a low body }
function IsLow(ID: LongInt): Boolean;
var
  NX, NY, AX, AY, CX, CY: Single;
  S: LongInt;
begin
  Result := False;
  if Assigned(BdStance) then
  begin
    S := BdStance(ID);
    if S > 0 then
    begin
      Result := (S = 2) or (S = 4);
      Exit;
    end;
  end;
  if (B[ID].LowGen <> Gen) and (B[ID].LowGen <> Gen - 1) then
    Exit;
  if not B[ID].Low then
    Exit;
  Result := True;
  if Assigned(BdPoint) then
    if BdPoint(ID, 9, NX, NY) then
      if BdPoint(ID, 1, AX, AY) then
        if BdPoint(ID, 2, CX, CY) then
          Result := FMax(AY, CY) - NY < LOW_NECK;
end;

{ still: his upper body moved less than StillPx a tick over the last STILL_SPAN ticks }
function IsStill(ID: LongInt): Boolean;
var
  a, c: LongInt;
begin
  Result := False;
  if B[ID].PN < STILL_SPAN then
    Exit;
  a := (B[ID].PN - 1) mod STILL_SPAN;
  c := B[ID].PN mod STILL_SPAN;
  Result := Sqr(B[ID].PX[a] - B[ID].PX[c]) + Sqr(B[ID].PY[a] - B[ID].PY[c]) <=
    Sqr(StillPx * (STILL_SPAN - 1));
end;

function BdHitPart(V, Style: LongInt; X, Y, VX, VY: Single): LongInt;
var
  k, Part, Near: LongInt;
  CX, CY, Off, FX, FY, A, Bq, C, Disc, T, Best, D, NearD: Single;
begin
  Result := 0;
  if not Valid(V) then
    Exit;
  if not Assigned(BdPoint) then
    Exit;
  { the server's circles lie 2 px left of the parts (not for a fist or a blade); an arrow is left a step
    before the place it hit }
  Off := 2;
  if (Style = 6) or (Style = 11) then
    Off := 0;
  if Style = 7 then
  begin
    X := X + VX;
    Y := Y + VY;
  end;
  { the server leaves a bullet on the edge of the circle it hit: that circle, when one edge is that near }
  Near := 0;
  NearD := 1E9;
  for k := 0 to High(HITPARTS) do
    if BdPoint(V, HITPARTS[k], CX, CY) then
    begin
      D := Abs(Sqrt(Sqr(X - (CX - Off)) + Sqr(Y - CY)) - PART_R);
      if D < NearD then
      begin
        NearD := D;
        Near := HITPARTS[k];
      end;
    end;
  Part := 0;
  if NearD <= 0.75 then
    Part := Near
  else
  begin
    { a bullet that started inside circles hit the first of them in the server's order }
    for k := 0 to High(HITPARTS) do
      if Part = 0 then
        if BdPoint(V, HITPARTS[k], CX, CY) then
          if Sqr(X - (CX - Off)) + Sqr(Y - CY) <= Sqr(PART_R) then
            Part := HITPARTS[k];
  end;
  if Part = 0 then
  begin
    { else the first circle the bullet's line of this tick enters (a step back to a step ahead) }
    Best := 1E9;
    A := VX * 2 * VX * 2 + VY * 2 * VY * 2;
    if A > 0.0001 then
      for k := 0 to High(HITPARTS) do
        if BdPoint(V, HITPARTS[k], CX, CY) then
        begin
          FX := X - VX - (CX - Off);
          FY := Y - VY - CY;
          Bq := 2 * (FX * VX * 2 + FY * VY * 2);
          C := FX * FX + FY * FY - Sqr(PART_R + 0.5);
          Disc := Bq * Bq - 4 * A * C;
          if Disc < 0 then
            Continue;
          T := (-Bq - Sqrt(Disc)) / (2 * A);
          if T < 0 then
            if C <= 0 then
              T := 0;
          if (T >= 0) and (T <= 1) then
            if T < Best then
            begin
              Best := T;
              Part := HITPARTS[k];
            end;
        end;
    if Part = 0 then
      Part := Near;
  end;
  { the server's parts: 12 the head, 5, 6, 10, 11 the torso, 3, 4 the legs }
  case Part of
    12: Result := WP_HEAD;
    5, 6, 10, 11: Result := WP_TORSO;
    3, 4: Result := WP_LEGS;
  else
    Result := 0;
  end;
end;

{ ---------------- wounds ---------------- }

function WorstIndex(ID: LongInt): LongInt;
var
  k: LongInt;
begin
  Result := -1;
  for k := 0 to B[ID].WN - 1 do
    if Result < 0 then
      Result := k
    else if B[ID].Wounds[k].Rate > B[ID].Wounds[Result].Rate then
      Result := k;
end;

procedure RemoveWound(ID, k, How: LongInt);
var
  j, Kind: LongInt;
begin
  if (k < 0) or (k >= B[ID].WN) then
    Exit;
  Kind := B[ID].Wounds[k].Kind;
  for j := k to B[ID].WN - 2 do
    B[ID].Wounds[j] := B[ID].Wounds[j + 1];
  Dec(B[ID].WN);
  B[ID].LastClosed := CurTick;
  Push(BDE_CLOSED, ID, Kind, How);
end;

{ a new wound (False: none - its kind is full, or no room for a wound that bad) }
function AddWound(V, Kind, Part, By, W, Tick: LongInt; Blast: Boolean): Boolean;
var
  k, Weak, n: LongInt;
begin
  Result := False;
  if (Kind >= 1) and (Kind <= 3) then
    if KindMax[Kind] > 0 then
    begin
      n := 0;
      for k := 0 to B[V].WN - 1 do
        if B[V].Wounds[k].Kind = Kind then
          Inc(n);
      if n >= KindMax[Kind] then
        Exit;
    end;
  if B[V].WN >= MAX_WOUNDS then
  begin
    { no room: the new one replaces the weakest when it is worse }
    Weak := 0;
    for k := 1 to B[V].WN - 1 do
      if B[V].Wounds[k].Rate < B[V].Wounds[Weak].Rate then
        Weak := k;
    if B[V].Wounds[Weak].Rate >= Rates[Kind] / 60 then
      Exit;
    k := Weak;
  end
  else
  begin
    k := B[V].WN;
    Inc(B[V].WN);
  end;
  B[V].Wounds[k].Kind := Kind;
  B[V].Wounds[k].Part := Part;
  B[V].Wounds[k].Blast := Blast;
  B[V].Wounds[k].Done := 0;
  B[V].Wounds[k].Rate := Rates[Kind] / 60;
  if Clots[Kind] > 0 then
  begin
    B[V].Wounds[k].Stop := Tick + Clots[Kind];
    { a light wound: some stop sooner than others }
    if Kind = WK_GRAZE then
      if ClotRandom then
        if Clot1Min < Clots[Kind] then
          B[V].Wounds[k].Stop := Tick + Clot1Min + Random(Clots[Kind] - Clot1Min + 1);
  end
  else
    B[V].Wounds[k].Stop := 0;
  B[V].Wounds[k].By := By;
  B[V].Wounds[k].W := W;
  B[V].Wounds[k].Tick := Tick;
  B[V].LastWound := Tick;
  if By > 0 then
  begin
    B[V].LastBy := By;
    B[V].LastW := W;
  end;
  Inc(CntWounds);
  if Blast then
    Push(BDE_WOUND, V, Kind, WP_BLAST)
  else
    Push(BDE_WOUND, V, Kind, Part);
  Result := True;
end;

{ his open wounds by place: per place (byte 0 the head, 1 the torso, 2 the legs, 3 none) bits 0-3 the count, bits
  4-5 the worst kind, bit 6 shrapnel among them }
function PlacesCode(ID: LongInt): LongInt;
var
  k, P: LongInt;
  C, Kd, Bl: array[0..3] of LongInt;
begin
  for P := 0 to 3 do
  begin
    C[P] := 0;
    Kd[P] := 0;
    Bl[P] := 0;
  end;
  for k := 0 to B[ID].WN - 1 do
  begin
    case B[ID].Wounds[k].Part of
      WP_HEAD: P := 0;
      WP_TORSO: P := 1;
      WP_LEGS: P := 2;
    else
      P := 3;
    end;
    if C[P] < 15 then
      Inc(C[P]);
    if B[ID].Wounds[k].Kind > Kd[P] then
      Kd[P] := B[ID].Wounds[k].Kind;
    if B[ID].Wounds[k].Blast then
      Bl[P] := 1;
  end;
  Result := 0;
  for P := 0 to 3 do
    Result := Result or ((C[P] or (Kd[P] shl 4) or (Bl[P] shl 6)) shl (P * 8));
end;

{ the kind of a new wound at Part (a share Share of the maximum health taken): an artery (the neck, the
  thigh) more often at the head and the legs, a heavy wound more often with a big hit or a blade }
function RollKind(Part: LongInt; Share, Blade: Single): LongInt;
var
  A, H, R: Single;
begin
  A := ArtShare;
  if Part = WP_HEAD then
    A := A * 1.5
  else if Part = WP_LEGS then
    A := A * 1.3
  else if Part = WP_TORSO then
    A := A * 0.7;
  A := A * Blade;
  H := HeavyShare * (0.6 + Share) * Blade;
  if A > 100 then
    A := 100;
  if A + H > 100 then
    H := 100 - A;
  R := Random(10000) / 100;
  if R < A then
    Result := WK_ARTERY
  else if R < A + H then
    Result := WK_HEAVY
  else
    Result := WK_GRAZE;
end;

{ a part his vest covers (Cov: COVER_* bits) }
function Covered(Part, Cov: LongInt): Boolean;
begin
  Result := ((Part = WP_HEAD) and ((Cov and COVER_HEAD) <> 0)) or ((Part = WP_TORSO) and ((Cov and COVER_TORSO) <> 0))
    or ((Part = WP_LEGS) and ((Cov and COVER_LEGS) <> 0));
end;

function BdHit(V, By, W, Style: LongInt; Damage, MaxHP: Single; Part, Tick: LongInt): LongInt;
var
  Share, Chance, F, Blade: Single;
  n, k, P, Kind, Cov: LongInt;
begin
  Result := 0;
  CurTick := Tick;
  if not BdOn then
    Exit;
  if not Valid(V) then
    Exit;
  { what his vest covers counts for this hit only }
  Cov := B[V].Cover;
  B[V].Cover := 0;
  if not B[V].Alive then
    Exit;
  if not (B[V].Human or BotsBleed) then
    Exit;
  if (Damage <= 0) or (MaxHP <= 0) then
    Exit;
  { fire and fists open no wound }
  if (Style = 5) or (Style = 6) or (Style = 8) then
    Exit;
  if RefHP > 0 then
    Share := Damage / RefHP
  else
    Share := Damage / MaxHP;
  if Share > 1 then
    Share := 1;
  Blade := 1;
  if (Style = 11) or (Style = 13) then
    Blade := Melee;
  { a blast (grenade, M79, clusters, LAW): up to BlastMax shrapnel wounds, spread over the body }
  if (Style = 2) or (Style = 4) or (Style = 9) or (Style = 10) or (Style = 12) then
  begin
    n := 1 + Round((BlastMax - 1) * Share * 2);
    if n > BlastMax then
      n := BlastMax;
    for k := 1 to n do
    begin
      Chance := Crit * Share * 100 / CritDmg;
      if Random(100) < Chance then
      begin
        case Random(10) of
          0: P := WP_HEAD;
          1, 2, 3, 4: P := WP_LEGS;
        else
          P := WP_TORSO;
        end;
        Kind := RollKind(P, Share, 1);
        if AddWound(V, Kind, P, By, W, Tick, True) then
          if Kind > Result then
            Result := Kind;
      end;
    end;
    if Result > 0 then
      Inc(CntParts[0]);
    Exit;
  end;
  if Part = WP_HEAD then
    F := FHead
  else if Part = WP_LEGS then
    F := FLegs
  else
    F := FTorso;
  Chance := Crit * F * Blade * Share * 100 / CritDmg;
  if Random(10000) >= Round(Chance * 100) then
    Exit;
  if Part = 0 then
    Part := WP_TORSO;
  if Covered(Part, Cov) then
    Exit;
  Kind := RollKind(Part, Share, Blade);
  if not AddWound(V, Kind, Part, By, W, Tick, False) then
    Exit;
  Result := Kind;
  if Part = WP_HEAD then
    Inc(CntParts[1])
  else if Part = WP_LEGS then
    Inc(CntParts[3])
  else
    Inc(CntParts[2]);
end;

{ the wound the bandage can close now: the worst one his bandage covers (-1 = none; Short = there are
  wounds but too little bandage) }
function BandTarget(ID: LongInt; out Short: Boolean): LongInt;
var
  k: LongInt;
begin
  Result := -1;
  Short := False;
  for k := 0 to B[ID].WN - 1 do
    if B[ID].Band + 0.001 >= BandC[B[ID].Wounds[k].Kind] then
    begin
      if Result < 0 then
        Result := k
      else if B[ID].Wounds[k].Rate > B[ID].Wounds[Result].Rate then
        Result := k;
    end
    else
      Short := True;
end;

{ the wound of P a bandage of Band can close now: his worst one it covers (-1 = none) }
function BandTargetFor(P: LongInt; Band: Single): LongInt;
var
  k: LongInt;
begin
  Result := -1;
  for k := 0 to B[P].WN - 1 do
    if Band + 0.001 >= BandC[B[P].Wounds[k].Kind] then
      if (Result < 0) or (B[P].Wounds[k].Rate > B[P].Wounds[Result].Rate) then
        Result := k;
end;

function FindPatient(M: LongInt): LongInt; forward;

function BdWant(ID, What: LongInt): LongInt;
var
  Short: Boolean;
begin
  Result := 0;
  if not Valid(ID) then
    Exit;
  if not B[ID].Alive then
    Exit;
  if What = BW_BANDAGE then
  begin
    if BandTarget(ID, Short) >= 0 then
      Result := 1
    else if Short then
      Result := -1
    { a medic with no wound of his own: a wounded mate near him (also without AutoBandage) }
    else if B[ID].MedicR > 0 then
      if not B[ID].Down then
        if FindPatient(ID) > 0 then
          Result := 1;
  end
  else if What = BW_KIT then
  begin
    if B[ID].Kits <= 0 then
      Result := -2
    else if (B[ID].WN > 0) or (B[ID].Blood < 100) or B[ID].Down then
      Result := 1;
  end;
  if Result = 1 then
    B[ID].Want := What
  else if What = BW_NONE then
    B[ID].Want := BW_NONE;
end;

procedure BdHeal(ID, How: LongInt; Blood: Single);
var
  k: LongInt;
begin
  if not Valid(ID) then
    Exit;
  if not B[ID].Alive then
    Exit;
  if How = BC_KIT then
  begin
    while B[ID].WN > 0 do
      RemoveWound(ID, B[ID].WN - 1, BC_KIT);
  end
  else
  begin
    k := 0;
    while k < B[ID].WN do
      if B[ID].Wounds[k].Kind = WK_GRAZE then
        RemoveWound(ID, k, BC_HEALED)
      else
        Inc(k);
  end;
  B[ID].Blood := B[ID].Blood + Blood;
  if B[ID].Blood > 100 then
    B[ID].Blood := 100;
  if B[ID].Blood > DeathB then
    B[ID].Dying := False;
end;

procedure BdDown(ID, By, W, Tick: LongInt);
var
  k: LongInt;
begin
  if not Valid(ID) then
    Exit;
  CurTick := Tick;
  B[ID].Down := True;
  B[ID].DownAt := Tick;
  B[ID].DownEnd := Tick + DownTicks;
  B[ID].DownBy := By;
  B[ID].DownW := W;
  B[ID].Helper := 0;
  if B[ID].ShockUntil > 0 then
    Push(BDE_SHOCK_END, ID, 0, 0);
  B[ID].ShockUntil := 0;
  if B[ID].Work <> BW_NONE then
    Push(BDE_WORK_STOP, ID, B[ID].Work, 0);
  ClearWork(ID);
  { with a kit of his own he gets himself up by staying low (crouch) for KitTicks }
  B[ID].Want := BW_NONE;
  if SelfRevive then
    if B[ID].Kits > 0 then
      B[ID].Want := BW_KIT;
  for k := 1 to MAX_ID do
    if B[k].WorkOn = ID then
    begin
      Push(BDE_WORK_STOP, k, B[k].Work, 0);
      ClearWork(k);
    end;
  Inc(CntDowned);
end;

procedure BdGiveUp(ID: LongInt);
begin
  if not Valid(ID) then
    Exit;
  if not B[ID].Down then
    Exit;
  B[ID].DownEnd := 0;
  Push(BDE_DOWN_END, ID, DE_GAVE_UP, 0);
  B[ID].Down := False;
  FreeHelpers(ID);
end;

procedure BdShot(const E: TShotEvent);
begin
  if E.Script then
    Exit;
  if Valid(E.Owner) then
    B[E.Owner].LastShot := E.Tick;
end;

function BdMuted(ID: LongInt): Boolean;
begin
  Result := False;
  if (ID >= 1) and (ID <= MAX_ID) then
    if B[ID].Alive then
      Result := B[ID].Down or (B[ID].ShockUntil > CurTick);
end;

{ ---------------- the tick ---------------- }

{ he may do his own work now: alive, not down (a kit is the exception), not in shock, still, low when it
  must be, no shot lately; falling freely without a key held is low and still for bandaging (AirOn) }
function CanWork(ID, What: LongInt): Boolean;
var
  Free: Boolean;
begin
  Result := False;
  if not B[ID].Alive then
    Exit;
  if B[ID].ShockUntil > CurTick then
    Exit;
  if B[ID].Down then
    if not ((What = BW_KIT) and SelfRevive) then
      Exit;
  if CurTick - B[ID].LastShot < SHOT_TICKS then
    Exit;
  Free := False;
  if What = BW_BANDAGE then
    if AirOn then
      if B[ID].Air then
        if (B[ID].AirGen = Gen) or (B[ID].AirGen = Gen - 1) then
          Free := True;
  if not B[ID].Down then
    if not Free then
      if not IsStill(ID) then
        Exit;
  if What = BW_BANDAGE then
  begin
    if BandLow then
      if not Free then
        if not IsLow(ID) then
          Exit;
  end
  else if What = BW_KIT then
  begin
    if KitLow or B[ID].Down then
      if not IsLow(ID) then
        Exit;
  end;
  Result := True;
end;

procedure StartWork(ID, What, OnID, Need: LongInt);
begin
  B[ID].Work := What;
  B[ID].WorkOn := OnID;
  B[ID].WorkStart := CurTick;
  B[ID].WorkNeed := Need;
  Push(BDE_WORK, ID, What, Need);
end;

procedure StopWork(ID: LongInt);
var
  k, P: LongInt;
  Short: Boolean;
begin
  if B[ID].Work = BW_NONE then
    Exit;
  { a bandage put on halfway stays: the work goes on from there (his own, or a mate's a medic began) }
  if B[ID].Work = BW_BANDAGE then
  begin
    P := B[ID].WorkOn;
    if Valid(P) then
    begin
      k := BandTargetFor(P, B[ID].Band);
      if k >= 0 then
        B[P].Wounds[k].Done := B[P].Wounds[k].Done + Round((CurTick - B[ID].WorkStart) * FMax(B[ID].BandF, 0.1));
      if B[P].TreatBy = ID then
        B[P].TreatBy := 0;
    end
    else
    begin
      k := BandTarget(ID, Short);
      if k >= 0 then
        B[ID].Wounds[k].Done := B[ID].Wounds[k].Done + Round((CurTick - B[ID].WorkStart) * FMax(B[ID].BandF, 0.1));
    end;
  end;
  Push(BDE_WORK_STOP, ID, B[ID].Work, 0);
  if B[ID].Work = BW_REVIVE then
    if Valid(B[ID].WorkOn) then
      if B[B[ID].WorkOn].Helper = ID then
        B[B[ID].WorkOn].Helper := 0;
  ClearWork(ID);
end;

procedure FinishBandage(ID: LongInt);
var
  k, Kind, Ready: LongInt;
  Short: Boolean;
begin
  k := BandTarget(ID, Short);
  Ready := B[ID].ReadySince;
  ClearWork(ID);
  { the wounds are bandaged one after the other without a new wait }
  B[ID].ReadySince := Ready;
  if k < 0 then
    Exit;
  Kind := B[ID].Wounds[k].Kind;
  B[ID].Band := B[ID].Band - BandC[Kind];
  if B[ID].Band < 0 then
    B[ID].Band := 0;
  RemoveWound(ID, k, BC_BANDAGE);
  Inc(CntBandaged);
  Push(BDE_BANDAGED, ID, Kind, Round(BandC[Kind] * 10));
  if B[ID].WN = 0 then
    B[ID].Want := BW_NONE;
end;

{ a medic's bandage on the worst wound of his mate it covers }
procedure FinishTreat(ID: LongInt);
var
  P, k, Kind, Ready: LongInt;
begin
  P := B[ID].WorkOn;
  Ready := B[ID].ReadySince;
  ClearWork(ID);
  B[ID].ReadySince := Ready;
  if not Valid(P) then
    Exit;
  if B[P].TreatBy = ID then
    B[P].TreatBy := 0;
  k := BandTargetFor(P, B[ID].Band);
  if k < 0 then
    Exit;
  Kind := B[P].Wounds[k].Kind;
  B[ID].Band := B[ID].Band - BandC[Kind];
  if B[ID].Band < 0 then
    B[ID].Band := 0;
  RemoveWound(P, k, BC_BANDAGE);
  Inc(CntBandaged);
  Inc(CntTreated);
  Push(BDE_TREATED, ID, P, Kind);
end;

{ may medic M bandage mate P now: alive, not down (getting him up is another work), of his team, within his reach,
  not bandaging himself nor bandaged by another medic, with a wound M's bandage covers }
function CanTreat(M, P: LongInt): Boolean;
var
  X1, Y1, X2, Y2: Single;
begin
  Result := False;
  if (P = M) or not Valid(P) then
    Exit;
  if B[M].MedicR <= 0 then
    Exit;
  if not B[P].Alive then
    Exit;
  if B[P].Down then
    Exit;
  if B[P].WN = 0 then
    Exit;
  if not Teams then
    Exit;
  if (B[M].Team < 1) or (B[M].Team > 4) or (B[P].Team <> B[M].Team) then
    Exit;
  if (B[P].Work = BW_BANDAGE) or (B[P].Work = BW_KIT) then
    Exit;
  if (B[P].TreatBy <> 0) and (B[P].TreatBy <> M) then
    Exit;
  if not Pt(M, 7, X1, Y1) then
    Exit;
  if not Pt(P, 7, X2, Y2) then
    Exit;
  if Sqr(X1 - X2) + Sqr(Y1 - Y2) > Sqr(B[M].MedicR) then
    Exit;
  Result := BandTargetFor(P, B[M].Band) >= 0;
end;

{ the mate a medic bandages next: the one with the worst wound his bandage covers (0 = none) }
function FindPatient(M: LongInt): LongInt;
var
  P, k: LongInt;
  Best: Single;
begin
  Result := 0;
  Best := -1;
  for P := 1 to MAX_ID do
    if CanTreat(M, P) then
    begin
      k := BandTargetFor(P, B[M].Band);
      if k >= 0 then
        if B[P].Wounds[k].Rate > Best then
        begin
          Best := B[P].Wounds[k].Rate;
          Result := P;
        end;
    end;
end;

procedure FinishKit(ID: LongInt);
var
  Up: LongInt;
begin
  ClearWork(ID);
  B[ID].Want := BW_NONE;
  if B[ID].Kits <= 0 then
    Exit;
  Dec(B[ID].Kits);
  while B[ID].WN > 0 do
    RemoveWound(ID, B[ID].WN - 1, BC_KIT);
  B[ID].Blood := B[ID].Blood + KitBlood;
  if B[ID].Blood > 100 then
    B[ID].Blood := 100;
  B[ID].Dying := False;
  Up := 0;
  if B[ID].Down then
    if SelfRevive then
    begin
      Up := 1;
      B[ID].Down := False;
      Inc(CntRevived);
    end;
  Inc(CntKits);
  Push(BDE_KIT, ID, 0, Up);
  if Up = 1 then
  begin
    FreeHelpers(ID);
    Push(BDE_REVIVED, ID, ID, 0);
  end;
end;

{ his work: bandaging (by itself when BandAuto, or asked for) and the kit; a medic with nothing of his own to
  bandage bandages his mates }
procedure LookWork(ID: LongInt);
var
  What, Need, k, P: LongInt;
  Short: Boolean;
begin
  if B[ID].Work = BW_REVIVE then
    Exit;
  if B[ID].Work <> BW_NONE then
  begin
    if not CanWork(ID, B[ID].Work) then
    begin
      StopWork(ID);
      Exit;
    end;
    { a mate's wound: he stays within reach and still has it }
    if B[ID].Work = BW_BANDAGE then
      if B[ID].WorkOn > 0 then
        if not CanTreat(ID, B[ID].WorkOn) then
        begin
          StopWork(ID);
          Exit;
        end;
    if CurTick - B[ID].WorkStart >= B[ID].WorkNeed then
    begin
      if B[ID].Work = BW_KIT then
        FinishKit(ID)
      else if B[ID].WorkOn > 0 then
        FinishTreat(ID)
      else
        FinishBandage(ID);
    end;
    Exit;
  end;
  { what he could start: his kit, his own wounds first, then (a medic) a mate's }
  What := BW_NONE;
  P := 0;
  if B[ID].Want = BW_KIT then
    What := BW_KIT
  else if B[ID].WN > 0 then
  begin
    if (B[ID].Want = BW_BANDAGE) or BandAuto then
      if not B[ID].Down then
        if B[ID].TreatBy = 0 then
          What := BW_BANDAGE;
    { a wound of his own his bandage cannot cover: a medic goes on to his mates }
    if What = BW_BANDAGE then
      if B[ID].MedicR > 0 then
        if B[ID].Want <> BW_BANDAGE then
          if BandTarget(ID, Short) < 0 then
            What := BW_NONE;
  end;
  { a medic with nothing of his own: a mate's wound - by itself (AutoBandage) or when he asks (!bandage) }
  if What = BW_NONE then
    if B[ID].MedicR > 0 then
      if BandAuto or (B[ID].Want = BW_BANDAGE) then
        if not B[ID].Down then
        begin
          P := FindPatient(ID);
          if P > 0 then
            What := BW_BANDAGE;
        end;
  if What = BW_NONE then
  begin
    B[ID].ReadySince := 0;
    { a medic's request with nobody left to bandage ends }
    if B[ID].WN = 0 then
      if B[ID].Want = BW_BANDAGE then
        B[ID].Want := BW_NONE;
    Exit;
  end;
  if not CanWork(ID, What) then
  begin
    B[ID].ReadySince := 0;
    Exit;
  end;
  if B[ID].ReadySince = 0 then
    B[ID].ReadySince := CurTick;
  { asked for: at once; by itself: after AutoDelay ticks low and still }
  if B[ID].Want <> What then
    if CurTick - B[ID].ReadySince < AutoDelay then
      Exit;
  if What = BW_KIT then
  begin
    if B[ID].Kits <= 0 then
    begin
      B[ID].Want := BW_NONE;
      Exit;
    end;
    StartWork(ID, BW_KIT, 0, KitTicks);
  end
  else if P > 0 then
  begin
    k := BandTargetFor(P, B[ID].Band);
    if k < 0 then
      Exit;
    Need := BandT[B[P].Wounds[k].Kind] - B[P].Wounds[k].Done;
    if B[ID].BandF > 0 then
      Need := Round(Need / B[ID].BandF);
    if Need < 1 then
      Need := 1;
    B[P].TreatBy := ID;
    StartWork(ID, BW_BANDAGE, P, Need);
    Push(BDE_TREAT, ID, P, B[P].Wounds[k].Kind);
  end
  else
  begin
    k := BandTarget(ID, Short);
    if k < 0 then
    begin
      if Short then
        if B[ID].Want = BW_BANDAGE then
          Push(BDE_NO_BANDAGE, ID, 0, 0);
      B[ID].Want := BW_NONE;
      Exit;
    end;
    Need := BandT[B[ID].Wounds[k].Kind] - B[ID].Wounds[k].Done;
    if B[ID].BandF > 0 then
      Need := Round(Need / B[ID].BandF);
    if Need < 1 then
      Need := 1;
    StartWork(ID, BW_BANDAGE, 0, Need);
  end;
end;

{ may H help downed D up: alive, not down, of his team, near, low (a bot only near with BotsRevive) }
function CanHelp(H, D: LongInt): Boolean;
var
  X1, Y1, X2, Y2: Single;
begin
  Result := False;
  if H = D then
    Exit;
  if not B[H].Alive then
    Exit;
  if B[H].Down then
    Exit;
  if B[H].ShockUntil > CurTick then
    Exit;
  if not Teams then
    Exit;
  if (B[H].Team < 1) or (B[H].Team > 4) then
    Exit;
  if B[H].Team <> B[D].Team then
    Exit;
  if not Pt(H, 7, X1, Y1) then
    Exit;
  if not Pt(D, 7, X2, Y2) then
    Exit;
  if Sqr(X1 - X2) + Sqr(Y1 - Y2) > Sqr(FMax(ReviveR, B[H].ReviveR2)) then
    Exit;
  if B[H].Human then
  begin
    if ReviveLow then
      if not IsLow(H) then
        Exit;
  end
  else if not BotsRevive then
    Exit;
  Result := True;
end;

{ a downed soldier: his time, a mate helping him up }
procedure LookDown(D: LongInt);
var
  h: LongInt;
begin
  { a downed bot with a kit of its own (SelfRevive) uses it BotBandage ticks later: it cannot crouch }
  if not B[D].Human then
    if SelfRevive then
      if BotBandage > 0 then
        if B[D].Kits > 0 then
          if B[D].Helper = 0 then
            if CurTick - B[D].DownAt >= BotBandage then
            begin
              FinishKit(D);
              Exit;
            end;
  h := B[D].Helper;
  if h <> 0 then
  begin
    if (B[h].Work <> BW_REVIVE) or (B[h].WorkOn <> D) or not CanHelp(h, D) then
    begin
      if B[h].Work = BW_REVIVE then
        StopWork(h);
      B[D].Helper := 0;
      h := 0;
    end
    else
    begin
      { his time waits while he is helped }
      B[D].DownEnd := B[D].DownEnd + 1;
      if CurTick - B[h].WorkStart >= B[h].WorkNeed then
      begin
        ClearWork(h);
        B[D].Helper := 0;
        B[D].Down := False;
        B[D].Dying := False;
        { his own kit waited for this (SelfRevive): it is not used now }
        B[D].Want := BW_NONE;
        if B[D].Work = BW_KIT then
          StopWork(D);
        FreeHelpers(D);
        { the mate who gets him up stops his bleeding too }
        while B[D].WN > 0 do
          RemoveWound(D, B[D].WN - 1, BC_BANDAGE);
        if B[D].Blood <= DeathB then
          B[D].Blood := DeathB + 5;
        Inc(CntRevived);
        Push(BDE_REVIVED, D, h, 0);
        Exit;
      end;
    end;
  end;
  if h = 0 then
    for h := 1 to MAX_ID do
      if B[h].Work = BW_NONE then
        if CanHelp(h, D) then
        begin
          B[D].Helper := h;
          if B[h].ReviveF > 0 then
            StartWork(h, BW_REVIVE, D, Round(ReviveTicks / B[h].ReviveF))
          else
            StartWork(h, BW_REVIVE, D, ReviveTicks);
          Break;
        end;
  if B[D].Helper = 0 then
    if CurTick >= B[D].DownEnd then
    begin
      B[D].Down := False;
      Push(BDE_DOWN_END, D, DE_TIME, 0);
    end;
end;

{ nobody of his team is left who could help (LastStand): the downed of that team end }
procedure LookAlone;
var
  v, k: LongInt;
  Up: array[0..5] of LongInt;
  AnyDown: Boolean;
begin
  AnyDown := False;
  for k := 0 to 5 do
    Up[k] := 0;
  for v := 1 to MAX_ID do
    if B[v].Alive then
      if (B[v].Team >= 0) and (B[v].Team <= 5) then
      begin
        if B[v].Down then
          AnyDown := True
        else
          Inc(Up[B[v].Team]);
      end;
  if not AnyDown then
    Exit;
  for v := 1 to MAX_ID do
    if B[v].Alive then
      if B[v].Down then
        if B[v].Helper = 0 then
          if (B[v].Team >= 0) and (B[v].Team <= 4) then
          begin
            { a team with nobody up; without teams (0): at most one other soldier up, and no kit of his own }
            if ((B[v].Team >= 1) and Teams and (Up[B[v].Team] = 0)) or
              (((B[v].Team = 0) or not Teams) and (Up[0] + Up[1] + Up[2] + Up[3] + Up[4] <= 1)) then
              if not (SelfRevive and (B[v].Kits > 0)) then
              begin
                B[v].Down := False;
                FreeHelpers(v);
                Push(BDE_DOWN_END, v, DE_ALONE, 0);
              end;
          end;
end;

function BdTick(Tick: LongInt): LongInt;
var
  v, k, a, Culprit, W: LongInt;
  X, Y, Sum, Depth, Chance, Amount, NearR, X2, Y2: Single;
begin
  Result := 0;
  CurTick := Tick;
  Inc(Gen);
  try
    Wanted := 0;
    NearMask := 0;
    if not (BdOn or DownOn) then
    begin
      Result := (EvHead - EvTail + EVENTS) mod EVENTS;
      Exit;
    end;
    { the upper bodies (still or not), the soldiers the library does not know }
    for v := 1 to MAX_ID do
      if B[v].Alive then
        if (B[v].Team >= 0) and (B[v].Team <= 4) then
        begin
          if Pt(v, 7, X, Y) then
          begin
            a := B[v].PN mod STILL_SPAN;
            B[v].PX[a] := X;
            B[v].PY[a] := Y;
            Inc(B[v].PN);
          end
          else
            Wanted := Wanted or Bit(v);
        end;
    for v := 1 to MAX_ID do
    begin
      if not B[v].Alive then
        Continue;
      { the blood }
      if B[v].WN > 0 then
      begin
        if B[v].Down and not DownBleed then
        else
        begin
          Sum := 0;
          k := 0;
          while k < B[v].WN do
          begin
            if (B[v].Wounds[k].Stop > 0) and (Tick >= B[v].Wounds[k].Stop) then
            begin
              RemoveWound(v, k, BC_CLOTTED);
              Continue;
            end;
            Sum := Sum + B[v].Wounds[k].Rate;
            Inc(k);
          end;
          B[v].Blood := B[v].Blood - Sum;
          if B[v].Blood < 0 then
            B[v].Blood := 0;
        end;
        { a bot bandages itself after a while (it cannot be told to stay low) }
        if not B[v].Human then
          if BotBandage > 0 then
            if B[v].WN > 0 then
              if Tick - B[v].LastWound >= BotBandage then
                if B[v].Work = BW_NONE then
                  if not B[v].Down then
                  begin
                    B[v].ReadySince := Tick;
                    FinishBandage(v);
                  end;
      end
      else if B[v].Blood < 100 then
        if Tick - B[v].LastClosed >= RegenDelay then
          if Tick - B[v].LastWound >= RegenDelay then
          begin
            B[v].Blood := B[v].Blood + Regen / 60;
            if B[v].Blood > 100 then
              B[v].Blood := 100;
            if B[v].Blood > DeathB then
              if not B[v].OutOn then
                B[v].Dying := False;
          end;
      { a transfusion (a blood bag) }
      if B[v].TransLeft > 0 then
      begin
        Amount := B[v].TransStep;
        if Amount > B[v].TransLeft then
          Amount := B[v].TransLeft;
        B[v].TransLeft := B[v].TransLeft - Amount;
        B[v].Blood := B[v].Blood + Amount;
        if B[v].Blood >= 100 then
        begin
          B[v].Blood := 100;
          B[v].TransLeft := 0;
        end;
        if B[v].Blood > DeathB then
          B[v].Dying := False;
      end;
      { too little blood: he bleeds out - at once, or (OutMode 1, not down) his health drains faster and faster while
        a wound bleeds (Dying: down later, his time does not end at once) }
      if BdOn then
        if B[v].Blood <= DeathB then
        begin
          if (OutMode = 1) and not B[v].Down then
          begin
            if (B[v].WN > 0) and not B[v].OutOn then
            begin
              B[v].OutOn := True;
              B[v].Dying := True;
              B[v].NextDrain := Tick;
              Inc(CntBled);
              Push(BDE_FADING, v, 0, 0);
            end;
          end
          else if not B[v].Dying then
          begin
            B[v].Dying := True;
            Culprit := BdCulprit(v, W);
            Inc(CntBled);
            FreeHelpers(v);
            if B[v].Down then
            begin
              B[v].Down := False;
              Push(BDE_DOWN_END, v, DE_BLED, 0);
            end
            else
              Push(BDE_BLED, v, Culprit, W);
            Continue;
          end;
        end;
      if B[v].OutOn then
        if (B[v].WN = 0) or (B[v].Blood > DeathB) or B[v].Down then
          B[v].OutOn := False;
      { shock }
      if B[v].ShockUntil > 0 then
        if Tick >= B[v].ShockUntil then
        begin
          B[v].ShockUntil := 0;
          Push(BDE_SHOCK_END, v, 0, 0);
        end;
      if BdOn then
        if B[v].ShockUntil = 0 then
          if not B[v].Down then
            if B[v].Blood < ShockB then
              if ShockTicks > 0 then
                if Tick >= B[v].NextShock then
                begin
                  B[v].NextShock := Tick + ShockEvery;
                  Depth := (ShockB - B[v].Blood) / FMax(ShockB - DeathB, 1);
                  if Depth > 1 then
                    Depth := 1;
                  Chance := ShockChance * (0.25 + 0.75 * Depth);
                  if Random(10000) < Round(Chance * 100) then
                  begin
                    B[v].ShockUntil := Tick + ShockTicks;
                    { the next one not before ShockEvery after this one ends: no chain of shocks }
                    B[v].NextShock := B[v].ShockUntil + ShockEvery;
                    if B[v].Work <> BW_NONE then
                      StopWork(v);
                    Inc(CntShocks);
                    Push(BDE_SHOCK, v, ShockTicks, 0);
                  end;
                end;
      { low blood takes health, once a second (bleeding out: twice a second, more and more) }
      if BdOn then
        if Tick >= B[v].NextDrain then
        begin
          if B[v].OutOn then
            B[v].NextDrain := Tick + 30
          else
            B[v].NextDrain := Tick + 60;
          if (B[v].Blood < WeakB) or B[v].OutOn then
            if not B[v].Down then
            begin
              Amount := 0;
              if Drain > 0 then
              begin
                Depth := (WeakB - B[v].Blood) / FMax(WeakB - DeathB, 1);
                if Depth > 1 then
                  Depth := 1;
                if Depth < 0 then
                  Depth := 0;
                Amount := Drain * Depth;
              end;
              if B[v].OutOn then
                Amount := (Amount + OutDrain + OutGrow * (DeathB - B[v].Blood)) / 2;
              if Amount > 0 then
                Push(BDE_DRAIN, v, Round(Amount * 100), 0);
            end;
        end;
      { his work }
      if BdOn or (DownOn and SelfRevive) then
        LookWork(v);
      if B[v].Down then
        LookDown(v);
      { the text }
      k := PlacesCode(v);
      if (Round(B[v].Blood) <> B[v].HudBlood) or (B[v].WN <> B[v].HudWN) or (Round(B[v].Band) <> B[v].HudBand) or
        (B[v].Kits <> B[v].HudKits) or (k <> B[v].HudPlaces) then
      begin
        B[v].HudBlood := Round(B[v].Blood);
        B[v].HudWN := B[v].WN;
        B[v].HudBand := Round(B[v].Band);
        B[v].HudKits := B[v].Kits;
        B[v].HudPlaces := k;
        Push(BDE_HUD, v, 0, 0);
      end;
    end;
    if DownOn then
      if LastStand then
        LookAlone;
    { the keys the library wants for the next tick: those who bleed or want work, the downed, the mates near
      a downed one }
    NearR := ReviveR + 30;
    for v := 1 to MAX_ID do
      if B[v].Alive then
      begin
        if (B[v].WN > 0) or (B[v].Want <> BW_NONE) or (B[v].Work <> BW_NONE) or B[v].Down then
          if not StanceKnown(v) then
            NearMask := NearMask or Bit(v);
        if B[v].Down then
          if Pt(v, 7, X, Y) then
            for k := 1 to MAX_ID do
              if k <> v then
                if B[k].Alive then
                  if B[k].Team = B[v].Team then
                    if not StanceKnown(k) then
                      if Pt(k, 7, X2, Y2) then
                        if (Abs(X2 - X) <= NearR) and (Abs(Y2 - Y) <= NearR) then
                          NearMask := NearMask or Bit(k);
      end;
  except
  end;
  Result := (EvHead - EvTail + EVENTS) mod EVENTS;
end;

function BdNext(out Kind, ID, P, Q: LongInt): Boolean;
begin
  Result := EvTail <> EvHead;
  Kind := 0;
  ID := 0;
  P := 0;
  Q := 0;
  if not Result then
    Exit;
  Kind := Ev[EvTail].Kind;
  ID := Ev[EvTail].ID;
  P := Ev[EvTail].P;
  Q := Ev[EvTail].Q;
  EvTail := (EvTail + 1) mod EVENTS;
end;

procedure BdGet(ID: LongInt; out Blood: Single; out Worst, Wounds: LongInt; out Band: Single; out Kits, Work,
  Pct, State: LongInt);
var
  k: LongInt;
begin
  Blood := 100;
  Worst := 0;
  Wounds := 0;
  Band := 0;
  Kits := 0;
  Work := 0;
  Pct := 0;
  State := 0;
  if not Valid(ID) then
    Exit;
  Blood := B[ID].Blood;
  k := WorstIndex(ID);
  if k >= 0 then
    Worst := B[ID].Wounds[k].Kind;
  Wounds := B[ID].WN;
  Band := B[ID].Band;
  Kits := B[ID].Kits;
  Work := B[ID].Work;
  if (Work <> BW_NONE) and (B[ID].WorkNeed > 0) then
  begin
    Pct := (CurTick - B[ID].WorkStart) * 100 div B[ID].WorkNeed;
    if Pct > 99 then
      Pct := 99;
    if Pct < 0 then
      Pct := 0;
  end;
  if B[ID].Down then
    State := 1
  else if B[ID].ShockUntil > CurTick then
    State := 2;
end;

function BdWorkOn(ID: LongInt): LongInt;
begin
  Result := 0;
  if Valid(ID) then
    Result := B[ID].WorkOn;
end;

function BdHelper(ID: LongInt): LongInt;
begin
  Result := 0;
  if Valid(ID) then
    Result := B[ID].Helper;
end;

function BdCulprit(ID: LongInt; out W: LongInt): LongInt;
var
  k: LongInt;
begin
  Result := 0;
  W := -1;
  if not Valid(ID) then
    Exit;
  k := WorstIndex(ID);
  if k >= 0 then
  begin
    Result := B[ID].Wounds[k].By;
    W := B[ID].Wounds[k].W;
  end
  else if B[ID].Down then
  begin
    Result := B[ID].DownBy;
    W := B[ID].DownW;
  end
  else if B[ID].LastBy > 0 then
  begin
    Result := B[ID].LastBy;
    W := B[ID].LastW;
  end;
end;

function BdDownLeft(ID, Tick: LongInt): LongInt;
begin
  Result := 0;
  if Valid(ID) then
    if B[ID].Down then
    begin
      Result := B[ID].DownEnd - Tick;
      if Result < 1 then
        Result := 1;
    end;
end;

var
  HudTexts: array[0..8] of AnsiString = ('{place} {kind}{many}', 'x{count}', 'head', 'torso', 'leg', 'shrapnel',
    'light', 'heavy', 'arterial');

procedure BdHudText(Kind: LongInt; const Text: AnsiString);
begin
  if (Kind >= 0) and (Kind <= 8) then
    HudTexts[Kind] := Text;
end;

function BdWoundList(ID: LongInt): AnsiString;
var
  Code, P, C, Kd: LongInt;
  Nm, KN, Many: AnsiString;
begin
  Result := '';
  if not Valid(ID) then
    Exit;
  if B[ID].WN <= 0 then
    Exit;
  Code := PlacesCode(ID);
  for P := 0 to 3 do
  begin
    C := (Code shr (P * 8)) and 15;
    if C > 0 then
    begin
      Kd := (Code shr (P * 8 + 4)) and 3;
      Nm := HudTexts[2 + P];
      if Kd = 3 then
        KN := HudTexts[8]
      else if Kd = 2 then
        KN := HudTexts[7]
      else
        KN := HudTexts[6];
      Many := '';
      if C > 1 then
        Many := ' ' + Fill(HudTexts[1], '{count}'#1 + IntToStr(C));
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + Fill(HudTexts[0], '{place}'#1 + Nm + #1'{kind}'#1 + KN + #1'{count}'#1 + IntToStr(C) +
        #1'{many}'#1 + Many);
    end;
  end;
end;

function BdPlaces(ID: LongInt; out Rate, Left: LongInt): LongInt;
var
  k: LongInt;
  Sum: Single;
begin
  Result := 0;
  Rate := 0;
  Left := -1;
  if not Valid(ID) then
    Exit;
  if not B[ID].Alive then
    Exit;
  Result := PlacesCode(ID);
  Sum := 0;
  if not (B[ID].Down and not DownBleed) then
    for k := 0 to B[ID].WN - 1 do
      Sum := Sum + B[ID].Wounds[k].Rate;
  Rate := Round(Sum * 60 * 100);
  if Sum > 0 then
  begin
    Left := Round((B[ID].Blood - DeathB) / Sum / 60);
    if Left < 0 then
      Left := 0;
  end;
end;

procedure BdTransfuse(ID: LongInt; Blood: Single; Ticks: LongInt);
begin
  if not Valid(ID) then
    Exit;
  if not B[ID].Alive then
    Exit;
  if Blood <= 0 then
    Exit;
  if Ticks < 1 then
    Ticks := 1;
  B[ID].TransLeft := B[ID].TransLeft + Blood;
  B[ID].TransStep := B[ID].TransLeft / Ticks;
end;

procedure BdPerk(ID: LongInt; BandF, ReviveF, ReviveR: Single);
begin
  if not Valid(ID) then
    Exit;
  if BandF > 0 then
    B[ID].BandF := BandF
  else
    B[ID].BandF := 1;
  if ReviveF > 0 then
    B[ID].ReviveF := ReviveF
  else
    B[ID].ReviveF := 1;
  if ReviveR > 0 then
    B[ID].ReviveR2 := ReviveR
  else
    B[ID].ReviveR2 := 0;
end;

procedure BdAir(ID, Free: LongInt);
begin
  if not Valid(ID) then
    Exit;
  B[ID].Air := Free <> 0;
  B[ID].AirGen := Gen + 1;
end;

procedure BdMedic(ID: LongInt; R: Single);
begin
  if not Valid(ID) then
    Exit;
  if R > 0 then
    B[ID].MedicR := R
  else
    B[ID].MedicR := 0;
end;

procedure BdCover(ID, Mask: LongInt);
begin
  if Valid(ID) then
    B[ID].Cover := Mask;
end;

procedure ShiftTick(var T: LongInt; Delta: LongInt);
begin
  if T > 0 then
    Inc(T, Delta);
end;

procedure BdShift(Delta: LongInt);
var
  i, k: LongInt;
begin
  if Delta <= 0 then
    Exit;
  for i := 1 to MAX_ID do
  begin
    ShiftTick(B[i].FallTick, Delta);
    for k := 0 to B[i].WN - 1 do
    begin
      ShiftTick(B[i].Wounds[k].Stop, Delta);
      ShiftTick(B[i].Wounds[k].Tick, Delta);
    end;
    ShiftTick(B[i].WorkStart, Delta);
    ShiftTick(B[i].ReadySince, Delta);
    ShiftTick(B[i].ShockUntil, Delta);
    ShiftTick(B[i].NextShock, Delta);
    ShiftTick(B[i].DownEnd, Delta);
    ShiftTick(B[i].DownAt, Delta);
    ShiftTick(B[i].LastShot, Delta);
    ShiftTick(B[i].LastClosed, Delta);
    ShiftTick(B[i].LastWound, Delta);
    ShiftTick(B[i].NextDrain, Delta);
  end;
  ShiftTick(CurTick, Delta);
end;

function BdInfo: AnsiString;
var
  v, n, d: LongInt;
begin
  n := 0;
  d := 0;
  for v := 1 to MAX_ID do
    if B[v].Alive then
    begin
      if B[v].WN > 0 then
        Inc(n);
      if B[v].Down then
        Inc(d);
    end;
  Result := 'bleeding now ' + IntToStr(n) + ', down now ' + IntToStr(d) + '; wounds ' + IntToStr(CntWounds) +
    ' (head ' + IntToStr(CntParts[1]) + ', torso ' + IntToStr(CntParts[2]) + ', legs ' + IntToStr(CntParts[3]) +
    ', blasts ' + IntToStr(CntParts[0]) + '), bandaged ' + IntToStr(CntBandaged) + ' (by a medic ' +
    IntToStr(CntTreated) + '), kits used ' + IntToStr(CntKits) +
    ', shocks ' + IntToStr(CntShocks) + ', bled out ' + IntToStr(CntBled) + ', downed ' + IntToStr(CntDowned) +
    ', revived ' + IntToStr(CntRevived);
end;

initialization
  BdPoint := @SpritePoint;
  BdStance := @SpriteStance;
  Randomize;
end.
