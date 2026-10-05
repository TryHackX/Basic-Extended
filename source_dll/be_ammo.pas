unit be_ammo;

{ Limited ammunition ([Ammo]): a reserve of rounds per weapon, or spare magazines, worked out from the
  magazine count the game reports.

  Soldat keeps the magazine in the game client: the client fires, reloads and sends its count to the
  server about every 7 ticks (every 4 on a LAN). In between, the server simulates the soldier and its
  copy can show counts the client never had: an empty magazine full for a moment (the server's own
  reload), a shot the client did not fire, 0 right after a script gave a partial magazine (2.8.2 takes
  that number for the magazine size and resets the weapon). So a new count is believed only when it
  has held for CONFIRM ticks: every sample since then stayed on the same side of the old count.

  A reload is the count coming back from 0. The rounds it loads come out of the reserve (pool) or are
  the fullest spare magazine; when there is less than the game loaded, the script sets the magazine to
  what is really there. A human client takes such a partial magazine; a bot's weapon only reloads full
  (the server resets a partial one), so a bot just loses the weapon when nothing is left.

  A magazine emptied at once is a reload with rounds left: the magazine taken out goes back into the
  pouch. How many rounds it still had is the lowest count reported before the 0, less the shots seen
  after that report: the hook in the server's CreateBullet reports every bullet as it is made
  (AmmoShot), because a shot and the reload can happen in the same tick and the count never shows the
  shot then (holding the reload key and firing). The magazine shown is the count known less the shots
  seen after it, so it drops with every shot at once.

  The Spas-12 loads shell by shell and always takes its shells from the reserve; weapons with one
  round (M79, LAW, bows) and the chainsaw (fuel in millilitres, used while held and faster while
  sawing) have no magazines either. The knife is not counted.

  A weapon on the ground is a map object. Soldat lets a soldier pick one up only with empty hands,
  just like a weapon chosen in the menu after a respawn, so the script tells which record a dropped
  weapon's object belongs to (the hook in CreateThing reports the object the game made for the
  soldier), and which record's object vanished when a weapon came into empty hands; with none, the
  weapon is a fresh one (the menu, a weapon of the map). With DeadMagazines = body a dead soldier's
  weapon keeps only its magazine and his spare magazines stay with his body, looted there. }

{$mode objfpc}{$H+}
{$Q-}{$IFNDEF BE_CHECKS}{$R-}{$ENDIF}

interface

const
  AMA_NONE = 0;
  AMA_SET = 1;
  AMA_DROP = 2;
  AMA_HUD = 3;
  AMF_HUMAN = 1;
  AMF_RELOAD = 2;
  AMF_SHOOT = 4;
  AMF_FREE = 8;
  { round 26: AmmoPass - the script looks at this soldier itself this tick (a weapon change, a record not readable) }
  AMA_FULL = 9;
  { AmmoRepackEvent }
  AMR_NONE = 0;
  AMR_STARTED = 1;
  AMR_STEP = 2;
  AMR_DONE = 3;
  AMR_SHOT = 4;
  AMR_STOPPED = 5;
  { AmmoSetText }
  AMT_NO_SPARE = 0;

procedure AmmoConfig(Enabled, MagMode, EmptyDrop, PickupFullSet, TrackGround, SawIdleTicks, SawAttackTicks,
  SawAttackDrain: LongInt; LootRadius: Single);
procedure AmmoOptions(OneRound, KeepInterrupted, SortMags, RepackStartTicks, RepackStepTicks: LongInt);
procedure AmmoSetText(Kind: LongInt; const S: AnsiString);
procedure AmmoSetReserve(W, Rounds: LongInt);
{ [Ammo] SurvivalCarry: his ammunition now (every pouch; the magazines in his gun and in a secondary he has
  used go back into their pouches) is kept for his next life - AmmoRespawn brings it back, and each kept
  weapon is loaded from its own pouch (the fullest magazine) the first time it comes into his hands.
  AmmoCarryConfirm: it stays, and what his death left on the ground at the saved tick is taken away (it came
  over with him); AmmoCarryDrop: it goes (a death in the round, a new map) }
procedure AmmoCarrySave(ID, Tick: LongInt);
procedure AmmoCarryConfirm(ID: LongInt);
procedure AmmoCarryDrop(ID: LongInt);
function AmmoCarryKept(ID: LongInt): LongInt;
{ the rounds he has for weapon W (the gun, the secondary, the pouch); -1 = not used this life }
function AmmoLeftOf(ID, W, Tick: LongInt): LongInt;
{ while he is down his weapons are away: nothing he reports is looked at (On = 0: again, the count held a
  moment - the script gives the same weapon and magazine back) }
procedure AmmoPause(ID, On, Tick: LongInt);
{ a fresh set of spare magazines for weapon W (a bounty's reward; later the supply crates) }
procedure AmmoRefill(ID, W: LongInt);
{ [Shop]: N spare magazines of W (in pool mode a magazine's worth of rounds each), as many as ExtraMagazines'
  limit lets; the number added }
function AmmoAddMags(ID, W, N: LongInt): LongInt;
{ a class's loadout: N spare magazines over the fresh set with every weapon he takes up from now on (a magazine's
  worth of rounds for a weapon without magazines), and N over ExtraMagazines for the shop's and the crates' ones;
  0 = none }
procedure AmmoPlayerExtra(ID, N: LongInt);
{ [Shop]: a fresh set of spare magazines when the pouch holds less than one; 1 = filled, 0 = it had as much }
function AmmoTopUp(ID, W: LongInt): LongInt;
{ [Ammo] ExtraMagazines: the most spare magazines of a weapon a soldier carries = a fresh weapon's plus
  Extra (-1 = up to the pouch's 12); looting and picking up a dead soldier's weapon stop there }
procedure AmmoLimit(Extra: LongInt);
procedure AmmoRespawn(ID, Tick: LongInt);
procedure AmmoShot(ID, W, Tick: LongInt);
{ a weapon object the game made for a soldier (the CreateThing hook): its map object style and slot }
procedure AmmoDropped(ID, ObjStyle, Slot, Tick: LongInt);
{ 1 = a dead soldier's spare magazines stay with his body (looted there), his weapon keeps only its
  magazine; 0 = they lie with his weapon }
procedure AmmoSetBodyMode(Body: LongInt);
{ where a dead soldier's body is now (the game moves it) }
procedure AmmoBodyMove(ID: LongInt; X, Y: Single);
{ a team change or leaving the game: the weapon stays on the ground with the spare magazines }
function AmmoLeftBehind(ID, Tick: LongInt; X, Y: Single): LongInt;
function AmmoObserve(ID, Tick, W, A, SW, SA, Flags: LongInt; X, Y: Single; out Value: LongInt): LongInt;
procedure AmmoForced(ID, Tick, W, Value: LongInt);
{ Rounds taken out of weapon W in the hands go back into the pool at its next reload (a guided rocket
  fired from a loaded launcher: the tube reloads, the reserve stays) }
procedure AmmoKeep(ID, W, Rounds: LongInt);
function AmmoClip(ID, Tick, A: LongInt): LongInt;
function AmmoShown(ID, Tick, W, A: LongInt): LongInt;
function AmmoDeath(ID, Tick: LongInt; X, Y: Single): LongInt;
function AmmoSelectMag(ID, W, Index: LongInt): LongInt;
function AmmoReloadNow(ID, Tick, Clip: LongInt): LongInt;
function AmmoMagCount(ID, W: LongInt): LongInt;
function AmmoMagRounds(ID, W, Index: LongInt): LongInt;
function AmmoLoose(ID, W: LongInt): LongInt;
function AmmoUsesMags(W: LongInt): LongInt;
function AmmoFormatHud(ID, W, Clip: LongInt): AnsiString;
function AmmoLevel(ID, W, Clip: LongInt): LongInt;
function AmmoRepack(ID, Tick: LongInt): LongInt;
function AmmoRepacking(ID: LongInt): LongInt;
function AmmoRepackEvent(ID: LongInt): LongInt;
function AmmoCanLoot(ID, W: LongInt; X, Y: Single): LongInt;
function AmmoLoot(ID, W: LongInt; X, Y: Single; Repack: LongInt): LongInt;
procedure AmmoGroundClear;
procedure AmmoPickFrom(ID, Tick, Index: LongInt);
function AmmoGroundNext(W, From: LongInt): LongInt;
function AmmoGroundSlot(Index: LongInt): LongInt;
function AmmoGroundKind(Index: LongInt): LongInt;
{ the ticks a record lies on the ground (since its weapon was dropped); -1 = no record }
function AmmoGroundAge(Index, Tick: LongInt): LongInt;
function AmmoGroundDist(Index: LongInt; X, Y: Single): LongInt;
function AmmoGroundHasSlot(Slot: LongInt): LongInt;
function AmmoGroundAttach(ID, W, Slot, Corpse, Tick: LongInt): LongInt;
procedure AmmoGroundMove(Index: LongInt; X, Y: Single);
procedure AmmoGroundMissing(Index, Tick: LongInt);
function AmmoStatus: AnsiString;
{ round 26: the weapon in his hands the script saw last (main.pas AmLastW: -1 a new life) }
procedure AmmoLastW(ID, W: LongInt);
{ round 26: the ammunition of every soldier of Mask in one call, read from the soldiers' records (be_sprite): the
  soldiers whose weapon is the one the script saw last are followed here as AmmoObserve does it; the others (a
  change, a record not readable) come back as AMA_FULL for the script's own look. Human, Free, Repack: the soldiers
  with AMF_HUMAN, AMF_FREE, and the ones repacking (their fire key counts). The count of the soldiers with
  something to do (AmmoPassOp) }
function AmmoPass(Tick: LongInt; Mask, Human, Free, Repack: LongWord): LongInt;
procedure AmmoPassOp(k: LongInt; out ID, Act, Value: LongInt);

implementation

uses
  SysUtils, be_world, be_ballistic, be_sprite;

const
  AM_W = 17;
  W_SPAS = 5;
  W_KNIFE = 11;
  W_SAW = 12;
  W_NONE = 255;
  MAX_MAGS = 12;
  MAX_GROUND = 128;
  { a new count is believed after this many ticks (a client report comes every 7) }
  CONFIRM = 8;
  { a count set by the script needs this long to reach the client and come back in its report }
  HOLD = 24;
  { after a weapon change the server and the client agree again within this }
  CHANGE_HOLD = 12;
  BUF = 16;
  { the soldier's last shots (ticks with new bullets of the weapon in the hands) }
  SHOT_BUF = 16;
  { weapons on the ground are forgotten after this (the game removes them earlier) }
  GROUND_TICKS = 5400;
  { a weapon object missing this long is gone for good (not picked up by a player the script follows) }
  MISSING_TICKS = 20;
  { a record gets its object only this soon after the weapon was dropped }
  ATTACH_TICKS = 120;
  { the reload key seen this recently: a count falling to 0 is a reload, not shots }
  RELOAD_KEY_TICKS = 30;
  HUD_TICKS = 6;
  SAW_HUD_TICKS = 30;
  { a weapon just taken away can come back for a moment: the client's reports sent before it got the
    change still carry it (up to twice the ping) }
  DROP_GUARD = 60;

type
  TPouch = record
    Used: Boolean;
    { the pool of rounds; with magazines, the loose rounds (the pouch was full) }
    Reserve: LongInt;
    MagN: LongInt;
    Mags: array[0..MAX_MAGS - 1] of LongInt;
    Sel: LongInt;
  end;

  TAmPlayer = record
    Pouch: array[0..AM_W - 1] of TPouch;
    W, SW, SA: LongInt;
    C, CTick: LongInt;
    Discard: LongInt;
    ReloadKeyTick: LongInt;
    HoldUntil, HoldVal: LongInt;
    PickFrom, PickTick: LongInt;
    N: LongInt;
    ST, SV: array[0..BUF - 1] of LongInt;
    SawIdleAt, SawAttackAt, SawHudAt: LongInt;
    HudDirty: Boolean;
    HudAt: LongInt;
    DropW, DropTick: LongInt;
    { the lowest count above 0 reported since the believed count last changed, and when }
    MinNZ, MinNZTick: LongInt;
    ShotW, ShotN: LongInt;
    ShotT: array[0..SHOT_BUF - 1] of LongInt;
    { EmptyDrop = 0: nothing left to load; the magazine is set to 0 again before the game's reload
      could fill it }
    Dry: Boolean;
    DryAt: LongInt;
    { /repack: 0 = no, 1 = waiting for the start, 2 = running; the weapon; the next step; the event
      for the script }
    RpState, RpW, RpNext, RpEvent: LongInt;
    { the magazine shown: DispV at tick DispT, less the shots after it; the last value shown }
    DispV, DispT, LastShown: LongInt;
    { the pouches that came over from the last round (their gun is loaded from them); nothing looked at
      while he is down }
    Carry: array[0..AM_W - 1] of Boolean;
    Paused: Boolean;
    { a class's spare magazines over the fresh set (AmmoPlayerExtra) }
    Extra: LongInt;
    { the weapon he put away with Q and the rounds it really has (its magazine cannot fill while it is away;
      -1 = none) }
    HW, HC: LongInt;
  end;

  TCarry = record
    Saved: Boolean;
    Tick: LongInt;
    Pouch: array[0..AM_W - 1] of TPouch;
  end;

  TGround = record
    { Corpse: a dead soldier's (his spare magazines are in it); Body: the spare magazines at his body,
      not a weapon }
    Active, Corpse, Body: Boolean;
    W, Clip, Reserve, MagN: LongInt;
    Mags: array[0..MAX_MAGS - 1] of LongInt;
    X, Y: Single;
    Tick, Owner: LongInt;
    { the map object of the weapon (0 = not known), and since when it is missing }
    Slot, MissingSince: LongInt;
  end;

var
  Pl: array[1..BE_PLAYERS] of TAmPlayer;
  Ground: array[0..MAX_GROUND - 1] of TGround;
  ResMax: array[0..AM_W - 1] of LongInt;
  CfgOn: Boolean = False;
  CfgMag: Boolean = True;
  CfgEmptyDrop: Boolean = True;
  CfgFullSet: Boolean = False;
  CfgGround: Boolean = True;
  CfgSawIdle: LongInt = 20;
  CfgSawAttack: LongInt = 3;
  CfgSawDrain: LongInt = 1;
  CfgLootRadius: Single = 45;
  CfgOneRound: Boolean = False;
  CfgKeep: Boolean = False;
  CfgSort: Boolean = True;
  CfgRpStart: LongInt = 60;
  CfgRpStep: LongInt = 60;
  TxtNoSpare: AnsiString = 'empty';
  CfgBody: Boolean = False;
  CfgExtra: LongInt = -1;
  { the last tick the script reported (AmmoObserve): the age of the records on the ground }
  AmTick: LongInt = 0;
  Kept: array[1..BE_PLAYERS] of TCarry;
  { the weapon object the game made last for each soldier (the CreateThing hook), for a record made
    right after it }
  ObjW, ObjSlot, ObjTick: array[1..BE_PLAYERS] of LongInt;
  StSets: LongInt = 0;
  StDrops: LongInt = 0;
  StReloads: LongInt = 0;
  StTaken: LongInt = 0;
  StShots: LongInt = 0;
  StRepacks: LongInt = 0;
  StProven: LongInt = 0;

function Counted(W: LongInt): Boolean;
begin
  Result := (W >= 0) and (W < AM_W) and (W <> W_KNIFE);
end;

function Cap(W: LongInt): LongInt;
begin
  Result := 1;
  if ValidWeapon(W) then
    Result := Weapon[W].Ammo;
  if Result < 1 then
    Result := 1;
end;

function UsesMags(W: LongInt): Boolean;
begin
  Result := CfgMag and (W <> W_SPAS) and (W <> W_SAW) and (W <> W_KNIFE) and (Cap(W) >= 2);
end;

procedure ClearPouch(var P: TPouch);
var
  k: LongInt;
begin
  P.Used := False;
  P.Reserve := 0;
  P.MagN := 0;
  P.Sel := -1;
  for k := 0 to MAX_MAGS - 1 do
    P.Mags[k] := 0;
end;

function Sorted(const P: TPouch): Boolean;
var
  k: LongInt;
begin
  Result := True;
  for k := 1 to P.MagN - 1 do
    if P.Mags[k] > P.Mags[k - 1] then
    begin
      Result := False;
      Exit;
    end;
end;

{ the fullest first; a magazine chosen with /mag stays chosen }
procedure SortPouch(var P: TPouch);
var
  i, j, v, SelRounds: LongInt;
begin
  SelRounds := -1;
  if (P.Sel >= 0) and (P.Sel < P.MagN) then
    SelRounds := P.Mags[P.Sel];
  for i := 1 to P.MagN - 1 do
  begin
    v := P.Mags[i];
    j := i - 1;
    while (j >= 0) and (P.Mags[j] < v) do
    begin
      P.Mags[j + 1] := P.Mags[j];
      Dec(j);
    end;
    P.Mags[j + 1] := v;
  end;
  if SelRounds >= 0 then
    for i := 0 to P.MagN - 1 do
      if P.Mags[i] = SelRounds then
      begin
        P.Sel := i;
        Break;
      end;
end;

{ magazines a fresh reserve of R rounds makes: whole ones, rounded (160 rounds of an AK with 35-round
  magazines: 5), at least one }
function FreshMags(W, R: LongInt): LongInt;
var
  C: LongInt;
begin
  C := Cap(W);
  Result := (R + C div 2) div C;
  if (Result = 0) and (R > 0) then
    Result := 1;
  if Result > MAX_MAGS then
    Result := MAX_MAGS;
end;

{ the most spare magazines of W a soldier carries (ExtraMagazines over a fresh weapon's; the pouch: 12) }
function MagLimit(W: LongInt): LongInt;
begin
  Result := MAX_MAGS;
  if CfgExtra < 0 then
    Exit;
  Result := FreshMags(W, ResMax[W]) + CfgExtra;
  if Result > MAX_MAGS then
    Result := MAX_MAGS;
  if Result < 1 then
    Result := 1;
end;

{ the most spare rounds of a weapon without magazines: its reserve and ExtraMagazines magazines' worth }
function SpareLimit(W: LongInt): LongInt;
begin
  Result := ResMax[W];
  if CfgExtra > 0 then
    Result := Result + CfgExtra * Cap(W);
end;

{ a fresh weapon: the reserve; in magazine mode as full magazines only, the reserve rounded to whole
  magazines }
procedure Fill(var P: TPouch; W: LongInt);
var
  C, k: LongInt;
begin
  ClearPouch(P);
  P.Used := True;
  if UsesMags(W) then
  begin
    C := Cap(W);
    P.MagN := FreshMags(W, ResMax[W]);
    for k := 0 to P.MagN - 1 do
      P.Mags[k] := C;
  end
  else
    P.Reserve := ResMax[W];
end;

procedure Touch(ID, W: LongInt);
var
  k, C: LongInt;
begin
  if Counted(W) then
    if not Pl[ID].Pouch[W].Used then
    begin
      Fill(Pl[ID].Pouch[W], W);
      { a class's spare magazines over the fresh set }
      if Pl[ID].Extra > 0 then
        if W <> W_SAW then
        begin
          C := Cap(W);
          if UsesMags(W) then
          begin
            for k := 1 to Pl[ID].Extra do
              if Pl[ID].Pouch[W].MagN < MAX_MAGS then
              begin
                Pl[ID].Pouch[W].Mags[Pl[ID].Pouch[W].MagN] := C;
                Inc(Pl[ID].Pouch[W].MagN);
              end;
          end
          else
            Pl[ID].Pouch[W].Reserve := Pl[ID].Pouch[W].Reserve + Pl[ID].Extra * C;
        end;
    end;
end;

{ rounds that could still be loaded into the weapon (with magazines: also the loose rounds) }
function Left(ID, W: LongInt): LongInt;
var
  k: LongInt;
begin
  Result := 0;
  if not Counted(W) then
    Exit;
  Result := Pl[ID].Pouch[W].Reserve;
  if UsesMags(W) then
    for k := 0 to Pl[ID].Pouch[W].MagN - 1 do
      Result := Result + Pl[ID].Pouch[W].Mags[k];
end;

{ a magazine goes into the pouch; with the pouch full its rounds stay loose (repacked later) }
procedure AddMag(var P: TPouch; Rounds: LongInt);
begin
  if Rounds <= 0 then
    Exit;
  if P.MagN < MAX_MAGS then
  begin
    P.Mags[P.MagN] := Rounds;
    Inc(P.MagN);
    if CfgSort then
      SortPouch(P);
  end
  else
    P.Reserve := P.Reserve + Rounds;
end;

{ rounds taken out of the weapon go back: a magazine, or into the pool }
procedure PutBack(ID, W, Rounds: LongInt);
begin
  if (Rounds <= 0) or not Counted(W) then
    Exit;
  Pl[ID].Pouch[W].Used := True;
  if UsesMags(W) then
    AddMag(Pl[ID].Pouch[W], Rounds)
  else
    Pl[ID].Pouch[W].Reserve := Pl[ID].Pouch[W].Reserve + Rounds;
end;

{ the magazine to load: the one chosen with /mag, else the fullest; -1 when there is none }
function TakeMag(var P: TPouch): LongInt;
var
  k, Best: LongInt;
begin
  Result := -1;
  if P.MagN <= 0 then
    Exit;
  Best := P.Sel;
  if (Best < 0) or (Best >= P.MagN) then
  begin
    Best := 0;
    for k := 1 to P.MagN - 1 do
      if P.Mags[k] > P.Mags[Best] then
        Best := k;
  end;
  P.Sel := -1;
  Result := P.Mags[Best];
  for k := Best to P.MagN - 2 do
    P.Mags[k] := P.Mags[k + 1];
  P.Mags[P.MagN - 1] := 0;
  Dec(P.MagN);
  if Result <= 0 then
    Result := TakeMag(P);
end;

procedure DropFirst(var P: TAmPlayer);
var
  k: LongInt;
begin
  for k := 1 to P.N - 1 do
  begin
    P.ST[k - 1] := P.ST[k];
    P.SV[k - 1] := P.SV[k];
  end;
  if P.N > 0 then
    Dec(P.N);
end;

procedure Push(var P: TAmPlayer; Tick, V: LongInt);
begin
  if P.N >= BUF then
    DropFirst(P);
  P.ST[P.N] := Tick;
  P.SV[P.N] := V;
  Inc(P.N);
end;

procedure Dirty(ID: LongInt);
begin
  Pl[ID].HudDirty := True;
end;

{ the magazine shown is V at tick T (the shots after T come off it) }
procedure ShowFrom(var P: TAmPlayer; V, T: LongInt);
begin
  P.DispV := V;
  P.DispT := T;
end;

{ the believed count changed: the lowest report starts again from it }
procedure MinFrom(var P: TAmPlayer; V, Tick: LongInt);
begin
  P.MinNZ := 0;
  if V > 0 then
    P.MinNZ := V;
  P.MinNZTick := Tick;
end;

{ shots seen after T1 up to T2 }
function ShotsIn(const P: TAmPlayer; T1, T2: LongInt): LongInt;
var
  k: LongInt;
begin
  Result := 0;
  if P.ShotW <> P.W then
    Exit;
  for k := 0 to P.ShotN - 1 do
    if (P.ShotT[k] > T1) and (P.ShotT[k] <= T2) then
      Inc(Result);
end;

{ the tick of the first shot after T (-1 = none) }
function FirstShotAfter(const P: TAmPlayer; T: LongInt): LongInt;
var
  k: LongInt;
begin
  Result := -1;
  if P.ShotW <> P.W then
    Exit;
  for k := 0 to P.ShotN - 1 do
    if P.ShotT[k] > T then
      if (Result < 0) or (P.ShotT[k] < Result) then
        Result := P.ShotT[k];
end;

{ the rounds the magazine held when it went to 0 at tick Z: the lowest count reported before Z (also
  reports not believed yet), less the shots seen after that report; T0 = the tick of that report }
function RoundsBefore(ID, Z: LongInt; out T0: LongInt): LongInt;
var
  P: ^TAmPlayer;
  k: LongInt;
begin
  P := @Pl[ID];
  Result := P^.C;
  T0 := P^.CTick;
  if (P^.MinNZ > 0) and (P^.MinNZ < Result) then
  begin
    Result := P^.MinNZ;
    T0 := P^.MinNZTick;
  end;
  for k := 0 to P^.N - 1 do
    if P^.ST[k] < Z then
      if (P^.SV[k] > 0) and (P^.SV[k] < Result) then
      begin
        Result := P^.SV[k];
        T0 := P^.ST[k];
      end;
  Result := Result - ShotsIn(P^, T0, Z);
  if Result < 0 then
    Result := 0;
end;

{ a reload with R rounds left keeps them (a single round only with ReloadOneRound = 1) }
function KeepRounds(R: LongInt): LongInt;
begin
  Result := R;
  if (R = 1) and not CfgOneRound then
    Result := 0;
  if R < 1 then
    Result := 0;
end;

{ the magazine taken out for a reload that has not ended: its rounds (0 = none). A reload whose 0 was
  not believed yet counts too when the reload key was seen. }
function Interrupted(ID, Tick: LongInt): LongInt;
var
  P: ^TAmPlayer;
  k, Z, T0: LongInt;
begin
  P := @Pl[ID];
  Result := P^.Discard;
  if Result > 0 then
    Exit;
  if P^.C <= 0 then
    Exit;
  if P^.N = 0 then
    Exit;
  if P^.SV[P^.N - 1] <> 0 then
    Exit;
  if Tick - P^.ReloadKeyTick > RELOAD_KEY_TICKS then
    Exit;
  if P^.W = W_SPAS then
    Exit;
  Z := P^.ST[P^.N - 1];
  for k := P^.N - 1 downto 0 do
    if P^.SV[k] = 0 then
      Z := P^.ST[k]
    else
      Break;
  Result := KeepRounds(RoundsBefore(ID, Z, T0));
end;

{ ---------------- ground ---------------- }

function GroundSlot: LongInt;
var
  i, Oldest: LongInt;
begin
  Oldest := 0;
  for i := 0 to MAX_GROUND - 1 do
  begin
    if not Ground[i].Active then
    begin
      Result := i;
      Exit;
    end;
    if Ground[i].Tick < Ground[Oldest].Tick then
      Oldest := i;
  end;
  Result := Oldest;
end;

procedure GroundAddAs(ID, Tick, W, Clip: LongInt; X, Y: Single; Corpse, Body: Boolean);
var
  g, k: LongInt;
begin
  if not CfgGround then
    Exit;
  if not Counted(W) then
    Exit;
  g := GroundSlot;
  Ground[g].Active := True;
  Ground[g].Corpse := Corpse;
  Ground[g].Body := Body;
  Ground[g].W := W;
  Ground[g].Clip := Clip;
  Ground[g].X := X;
  Ground[g].Y := Y;
  Ground[g].Tick := Tick;
  Ground[g].Owner := ID;
  Ground[g].Slot := 0;
  Ground[g].MissingSince := 0;
  Ground[g].Reserve := 0;
  Ground[g].MagN := 0;
  for k := 0 to MAX_MAGS - 1 do
    Ground[g].Mags[k] := 0;
  if Corpse then
    if Pl[ID].Pouch[W].Used then
    begin
      Ground[g].Reserve := Pl[ID].Pouch[W].Reserve;
      Ground[g].MagN := Pl[ID].Pouch[W].MagN;
      for k := 0 to MAX_MAGS - 1 do
        Ground[g].Mags[k] := Pl[ID].Pouch[W].Mags[k];
      ClearPouch(Pl[ID].Pouch[W]);
      Pl[ID].Pouch[W].Used := True;
    end;
  { the chainsaw's fuel is in its tank: it goes with the saw also when the saw is thrown away }
  if not Corpse and (W = W_SAW) then
    if Pl[ID].Pouch[W].Used then
    begin
      Ground[g].Reserve := Pl[ID].Pouch[W].Reserve;
      Pl[ID].Pouch[W].Reserve := 0;
    end;
  { the weapon's object, when the hook saw the game make it for this soldier just now }
  if not Body then
    if (ObjW[ID] = W) and (ObjSlot[ID] > 0) and (Tick - ObjTick[ID] <= 2) then
    begin
      Ground[g].Slot := ObjSlot[ID];
      ObjSlot[ID] := 0;
    end;
end;

procedure GroundAdd(ID, Tick, W, Clip: LongInt; X, Y: Single; Corpse: Boolean);
begin
  GroundAddAs(ID, Tick, W, Clip, X, Y, Corpse, False);
end;

{ the nearest record of kind W with a dead soldier's spare magazines within Radius (a live one, not too
  old); -1 = none }
function GroundNear(Tick, W: LongInt; X, Y, Radius: Single): LongInt;
var
  i: LongInt;
  D, Best: Single;
begin
  Result := -1;
  Best := Radius * Radius;
  for i := 0 to MAX_GROUND - 1 do
    if Ground[i].Active then
      if (Ground[i].W = W) and Ground[i].Corpse then
      begin
        if Tick - Ground[i].Tick > GROUND_TICKS then
        begin
          Ground[i].Active := False;
          Continue;
        end;
        D := Sqr(Ground[i].X - X) + Sqr(Ground[i].Y - Y);
        if D <= Best then
        begin
          Best := D;
          Result := i;
        end;
      end;
end;

{ a weapon came into the hands: from the ground when the script found the record whose object vanished
  (AmmoPickFrom this tick) - it brings the rounds in it (the game gives them) and, from a dead
  soldier, his spare magazines (when the own pouch of that kind is empty, or always with
  PickupFullSet); a chainsaw brings the fuel in its tank. Otherwise a fresh weapon with a full reserve
  the first time in a life. }
procedure PickUp(ID, Tick, W: LongInt);
var
  g, k: LongInt;
  P: ^TPouch;
begin
  if not Counted(W) then
    Exit;
  P := @Pl[ID].Pouch[W];
  g := -1;
  if Pl[ID].PickTick = Tick then
    g := Pl[ID].PickFrom;
  Pl[ID].PickFrom := -1;
  Pl[ID].PickTick := -1;
  if (g >= 0) and (g < MAX_GROUND) then
    if not Ground[g].Active or (Ground[g].W <> W) then
      g := -1;
  if (g < 0) or (g >= MAX_GROUND) or not CfgGround then
  begin
    Touch(ID, W);
    Exit;
  end;
  if not P^.Used then
  begin
    ClearPouch(P^);
    P^.Used := True;
  end;
  if W = W_SAW then
    { the fuel in the saw's tank }
    P^.Reserve := Ground[g].Reserve
  else if Ground[g].Corpse then
    if (Left(ID, W) = 0) or CfgFullSet then
    begin
      if CfgExtra < 0 then
      begin
        P^.Reserve := P^.Reserve + Ground[g].Reserve;
        for k := 0 to Ground[g].MagN - 1 do
          AddMag(P^, Ground[g].Mags[k]);
      end
      else if UsesMags(W) then
      begin
        { no more than ExtraMagazines allows (the fullest first); loose rounds up to a magazine }
        for k := 0 to Ground[g].MagN - 1 do
          if P^.MagN < MagLimit(W) then
            AddMag(P^, Ground[g].Mags[k]);
        if P^.Reserve < Cap(W) then
        begin
          P^.Reserve := P^.Reserve + Ground[g].Reserve;
          if P^.Reserve > Cap(W) then
            P^.Reserve := Cap(W);
        end;
      end
      else
      begin
        P^.Reserve := P^.Reserve + Ground[g].Reserve;
        if P^.Reserve > SpareLimit(W) then
          P^.Reserve := SpareLimit(W);
      end;
    end;
  Ground[g].Active := False;
end;

{ ---------------- the magazine count ---------------- }

function SetTo(ID, Tick, V: LongInt; out Value: LongInt): LongInt;
begin
  if V < 0 then
    V := 0;
  Value := V;
  Pl[ID].C := V;
  Pl[ID].CTick := Tick;
  Pl[ID].HoldUntil := Tick + HOLD;
  Pl[ID].HoldVal := V;
  Pl[ID].N := 0;
  MinFrom(Pl[ID], V, Tick);
  { the client has the count only a moment later: shots before that were not from it }
  ShowFrom(Pl[ID], V, Tick + HOLD);
  Inc(StSets);
  Dirty(ID);
  Result := AMA_SET;
end;

{ how often an empty weapon of a human is set to 0 again with EmptyDrop = 0: well before the game's
  reload could fill it (the Spas-12 loads a shell about every 24 ticks) }
function DryTicks(W: LongInt): LongInt;
begin
  Result := 30;
  if W = W_SPAS then
    Result := 15
  else if ValidWeapon(W) then
    if Weapon[W].Reload > 0 then
      Result := Weapon[W].Reload div 2;
  if Result < 15 then
    Result := 15;
end;

{ nothing left to load: the weapon goes (EmptyDrop, and always for a bot: the server reloads a bot's
  weapon at once and full), or a human's magazine is kept at 0 }
function Empty(ID, Tick, Flags: LongInt; out Value: LongInt): LongInt;
begin
  Value := 0;
  Dirty(ID);
  if CfgEmptyDrop or ((Flags and AMF_HUMAN) = 0) or (Pl[ID].W = W_SAW) then
  begin
    Pl[ID].DropW := Pl[ID].W;
    Pl[ID].DropTick := Tick;
    Pl[ID].W := W_NONE;
    Pl[ID].C := 0;
    Pl[ID].N := 0;
    Pl[ID].HoldUntil := Tick + CHANGE_HOLD;
    Pl[ID].HoldVal := 0;
    ShowFrom(Pl[ID], 0, Tick);
    Pl[ID].Dry := False;
    Pl[ID].RpState := 0;
    Inc(StDrops);
    Result := AMA_DROP;
    Exit;
  end;
  Pl[ID].Dry := True;
  Pl[ID].DryAt := Tick + DryTicks(Pl[ID].W);
  Result := SetTo(ID, Tick, 0, Value);
end;

{ a count V (reported at SampleTick) is believed: shots, a reload emptying the magazine, or a reload
  done }
function Apply(ID, Tick, SampleTick, V, Flags: LongInt; out Value: LongInt): LongInt;
var
  P: ^TAmPlayer;
  W, Old, Iv, MaxShots, Take, Target, Latest, R, T0: LongInt;
begin
  Value := 0;
  P := @Pl[ID];
  W := P^.W;
  Old := P^.C;
  Result := AMA_NONE;
  Dirty(ID);
  if V < Old then
  begin
    { a magazine emptied at once is a reload: its rounds are not lost (tactical reload) }
    if (V = 0) and (W <> W_SPAS) then
    begin
      R := RoundsBefore(ID, SampleTick, T0);
      Iv := 1;
      if ValidWeapon(W) then
        Iv := Weapon[W].Interval;
      if Iv < 1 then
        Iv := 1;
      MaxShots := (SampleTick - T0) div Iv + 1;
      if (R > MaxShots) or (Tick - P^.ReloadKeyTick <= RELOAD_KEY_TICKS) then
        P^.Discard := KeepRounds(R);
    end;
    P^.C := V;
    P^.CTick := SampleTick;
    MinFrom(P^, V, SampleTick);
    ShowFrom(P^, V, SampleTick);
    if V = 0 then
      if Left(ID, W) + P^.Discard <= 0 then
        Result := Empty(ID, Tick, Flags, Value);
    Exit;
  end;
  { more rounds: shells of the Spas-12, or a reload from 0 }
  Latest := V;
  if P^.N > 0 then
    Latest := P^.SV[P^.N - 1];
  if W = W_SPAS then
  begin
    Take := V - Old;
    if Take > P^.Pouch[W].Reserve then
      Take := P^.Pouch[W].Reserve;
    P^.Pouch[W].Reserve := P^.Pouch[W].Reserve - Take;
    StTaken := StTaken + Take;
    Target := Old + Take;
    P^.C := V;
    P^.CTick := SampleTick;
    MinFrom(P^, V, SampleTick);
    ShowFrom(P^, V, SampleTick);
    if Target < V then
    begin
      if Target <= 0 then
        Result := Empty(ID, Tick, Flags, Value)
      else if (Flags and AMF_HUMAN) <> 0 then
        Result := SetTo(ID, Tick, Target - (V - Latest), Value);
    end;
    Exit;
  end;
  if Old > 0 then
  begin
    { not a reload: a script gave the rounds }
    P^.C := V;
    P^.CTick := SampleTick;
    MinFrom(P^, V, SampleTick);
    ShowFrom(P^, V, SampleTick);
    Exit;
  end;
  Inc(StReloads);
  if UsesMags(W) then
  begin
    AddMag(P^.Pouch[W], P^.Discard);
    P^.Discard := 0;
    Target := TakeMag(P^.Pouch[W]);
    if Target < 0 then
    begin
      { no magazine left: the loose rounds fill one }
      Target := V;
      if Target > P^.Pouch[W].Reserve then
        Target := P^.Pouch[W].Reserve;
      P^.Pouch[W].Reserve := P^.Pouch[W].Reserve - Target;
    end;
  end
  else
  begin
    P^.Pouch[W].Reserve := P^.Pouch[W].Reserve + P^.Discard;
    P^.Discard := 0;
    Take := V;
    if Take > P^.Pouch[W].Reserve then
      Take := P^.Pouch[W].Reserve;
    P^.Pouch[W].Reserve := P^.Pouch[W].Reserve - Take;
    Target := Take;
  end;
  StTaken := StTaken + Target;
  P^.C := V;
  P^.CTick := SampleTick;
  MinFrom(P^, V, SampleTick);
  ShowFrom(P^, V, SampleTick);
  if Target >= V then
    Exit;
  if Target <= 0 then
  begin
    Result := Empty(ID, Tick, Flags, Value);
    Exit;
  end;
  { a bot's weapon only reloads full: it keeps the full magazine this time }
  if (Flags and AMF_HUMAN) <> 0 then
    Result := SetTo(ID, Tick, Target - (V - Latest), Value);
end;

{ a shot while the magazine is believed empty: the client finished a reload the reports never showed -
  with the reload key and the fire key held it fires the moment the magazine is in and the key takes it
  out again, so every report says 0. The magazine is loaded now (the fullest spare one, or the rounds of
  the pool); the shots since come off it, and the next 0 takes it out again with what is left. A
  partial magazine is set for a human (the game loaded a full one); nothing to load: empty. }
function ProvenReload(ID, Tick, Flags: LongInt; out Value: LongInt): LongInt;
var
  P: ^TAmPlayer;
  W, V, Target, Take, T1, n: LongInt;
begin
  Result := AMA_NONE;
  Value := 0;
  P := @Pl[ID];
  W := P^.W;
  T1 := FirstShotAfter(P^, P^.DispT);
  if T1 < 0 then
    Exit;
  T1 := T1 - 1;
  n := ShotsIn(P^, T1, Tick);
  V := Cap(W);
  Inc(StReloads);
  Inc(StProven);
  if UsesMags(W) then
  begin
    AddMag(P^.Pouch[W], P^.Discard);
    P^.Discard := 0;
    Target := TakeMag(P^.Pouch[W]);
    if Target < 0 then
    begin
      Target := V;
      if Target > P^.Pouch[W].Reserve then
        Target := P^.Pouch[W].Reserve;
      P^.Pouch[W].Reserve := P^.Pouch[W].Reserve - Target;
    end;
  end
  else
  begin
    P^.Pouch[W].Reserve := P^.Pouch[W].Reserve + P^.Discard;
    P^.Discard := 0;
    Take := V;
    if Take > P^.Pouch[W].Reserve then
      Take := P^.Pouch[W].Reserve;
    P^.Pouch[W].Reserve := P^.Pouch[W].Reserve - Take;
    Target := Take;
  end;
  StTaken := StTaken + Target;
  Dirty(ID);
  { the reports before it showed the empty magazine of the last reload }
  P^.N := 0;
  if Target <= 0 then
  begin
    Result := Empty(ID, Tick, Flags, Value);
    Exit;
  end;
  P^.Dry := False;
  { a bot's weapon only reloads full: it keeps the full magazine this time }
  if (Target < V) and ((Flags and AMF_HUMAN) = 0) then
    Target := V;
  P^.C := Target;
  P^.CTick := T1;
  MinFrom(P^, Target, T1);
  ShowFrom(P^, Target, T1);
  if Target < V then
    Result := SetTo(ID, Tick, Target - n, Value);
end;

function SawTick(ID, Tick, Flags: LongInt; out Value: LongInt): LongInt;
var
  P: ^TAmPlayer;
  F: ^TPouch;
  Used: Boolean;
begin
  Result := AMA_NONE;
  Value := 0;
  P := @Pl[ID];
  F := @P^.Pouch[W_SAW];
  Used := False;
  if Tick >= P^.SawIdleAt then
  begin
    P^.SawIdleAt := Tick + CfgSawIdle;
    Dec(F^.Reserve);
    Used := True;
  end;
  if (Flags and AMF_SHOOT) <> 0 then
    if Tick >= P^.SawAttackAt then
    begin
      P^.SawAttackAt := Tick + CfgSawAttack;
      F^.Reserve := F^.Reserve - CfgSawDrain;
      Used := True;
    end;
  if F^.Reserve <= 0 then
  begin
    F^.Reserve := 0;
    Result := Empty(ID, Tick, Flags, Value);
    Exit;
  end;
  if Used then
    if Tick >= P^.SawHudAt then
    begin
      P^.SawHudAt := Tick + SAW_HUD_TICKS;
      Result := AMA_HUD;
    end;
end;

{ ---------------- /repack ---------------- }

{ partial magazines to put together (the loose rounds count as one), or with SortMagazines = 0 an
  order to put right }
function NeedRepack(const P: TPouch; C: LongInt): Boolean;
var
  k, Partial: LongInt;
begin
  Partial := 0;
  for k := 0 to P.MagN - 1 do
    if (P.Mags[k] > 0) and (P.Mags[k] < C) then
      Inc(Partial);
  if P.Reserve > 0 then
    Inc(Partial);
  Result := Partial >= 2;
  if (P.Reserve > 0) and (P.MagN < MAX_MAGS) then
    Result := True;
  if not CfgSort then
    if not Sorted(P) then
      Result := True;
end;

{ one magazine: the fullest one that is not full takes the loose rounds and then the rounds of the
  emptiest ones (an emptied magazine is gone); with all full, the loose rounds make a new one }
procedure RepackStep(var P: TPouch; C: LongInt);
var
  a, b, k, Need, Take: LongInt;
begin
  SortPouch(P);
  a := -1;
  for k := 0 to P.MagN - 1 do
    if P.Mags[k] < C then
    begin
      a := k;
      Break;
    end;
  if a < 0 then
  begin
    if (P.Reserve > 0) and (P.MagN < MAX_MAGS) then
    begin
      Take := C;
      if Take > P.Reserve then
        Take := P.Reserve;
      P.Mags[P.MagN] := Take;
      Inc(P.MagN);
      P.Reserve := P.Reserve - Take;
    end;
    SortPouch(P);
    Exit;
  end;
  Need := C - P.Mags[a];
  Take := Need;
  if Take > P.Reserve then
    Take := P.Reserve;
  P.Mags[a] := P.Mags[a] + Take;
  P.Reserve := P.Reserve - Take;
  Need := Need - Take;
  b := P.MagN - 1;
  while (Need > 0) and (b > a) do
  begin
    Take := Need;
    if Take > P.Mags[b] then
      Take := P.Mags[b];
    P.Mags[a] := P.Mags[a] + Take;
    P.Mags[b] := P.Mags[b] - Take;
    Need := Need - Take;
    Dec(b);
  end;
  { emptied magazines are gone }
  k := 0;
  while k < P.MagN do
    if P.Mags[k] <= 0 then
    begin
      for b := k to P.MagN - 2 do
        P.Mags[b] := P.Mags[b + 1];
      P.Mags[P.MagN - 1] := 0;
      Dec(P.MagN);
    end
    else
      Inc(k);
  P.Sel := -1;
  SortPouch(P);
end;

procedure RepackTick(ID, Tick, W, Flags: LongInt);
var
  P: ^TAmPlayer;
begin
  P := @Pl[ID];
  if W <> P^.RpW then
  begin
    P^.RpState := 0;
    P^.RpEvent := AMR_STOPPED;
    Exit;
  end;
  if (Flags and AMF_SHOOT) <> 0 then
  begin
    P^.RpState := 0;
    P^.RpEvent := AMR_SHOT;
    Exit;
  end;
  if (Flags and AMF_RELOAD) <> 0 then
  begin
    P^.RpState := 0;
    P^.RpEvent := AMR_STOPPED;
    Exit;
  end;
  if Tick < P^.RpNext then
    Exit;
  P^.RpNext := Tick + CfgRpStep;
  if P^.RpState = 1 then
  begin
    P^.RpState := 2;
    P^.RpEvent := AMR_STARTED;
    Exit;
  end;
  RepackStep(P^.Pouch[W], Cap(W));
  Dirty(ID);
  if NeedRepack(P^.Pouch[W], Cap(W)) then
    P^.RpEvent := AMR_STEP
  else
  begin
    P^.RpState := 0;
    P^.RpEvent := AMR_DONE;
    Inc(StRepacks);
  end;
end;

{ the weapon in the hands changed: a swap with the secondary (the key Q) keeps both, anything else
  leaves the old weapon on the ground (with its magazine; the spare magazines stay with the soldier).
  A reload cut short by the change: its magazine is lost, or goes back into the pouch
  (InterruptedReload = 1). An empty weapon with nothing to load goes at once, before the game
  reloads it. }
{ the reload (or the Spas-12's shells) the game finished while no report has held long enough to be believed
  (CONFIRM): its rounds come out of the pouch now, because the weapon leaves the hands (Q, a throw) - else the
  magazine would come back full and unpaid }
procedure SettleReload(ID: LongInt);
var
  P: ^TAmPlayer;
  W, V, Target: LongInt;
begin
  P := @Pl[ID];
  W := P^.W;
  if (not Counted(W)) or (W = W_SAW) then
    Exit;
  if P^.N <= 0 then
    Exit;
  V := P^.SV[P^.N - 1];
  if V <= P^.C then
    Exit;
  if W = W_SPAS then
  begin
    Target := V - P^.C;
    if Target > P^.Pouch[W].Reserve then
      Target := P^.Pouch[W].Reserve;
    P^.Pouch[W].Reserve := P^.Pouch[W].Reserve - Target;
    StTaken := StTaken + Target;
    Target := P^.C + Target;
  end
  else
  begin
    { rounds that came while the magazine was not empty: a script gave them, nothing to pay }
    if P^.C > 0 then
      Exit;
    Inc(StReloads);
    if UsesMags(W) then
    begin
      AddMag(P^.Pouch[W], P^.Discard);
      P^.Discard := 0;
      Target := TakeMag(P^.Pouch[W]);
      if Target < 0 then
      begin
        Target := V;
        if Target > P^.Pouch[W].Reserve then
          Target := P^.Pouch[W].Reserve;
        P^.Pouch[W].Reserve := P^.Pouch[W].Reserve - Target;
      end;
    end
    else
    begin
      P^.Pouch[W].Reserve := P^.Pouch[W].Reserve + P^.Discard;
      P^.Discard := 0;
      Target := V;
      if Target > P^.Pouch[W].Reserve then
        Target := P^.Pouch[W].Reserve;
      P^.Pouch[W].Reserve := P^.Pouch[W].Reserve - Target;
    end;
    StTaken := StTaken + Target;
    if Target > V then
      Target := V;
  end;
  P^.C := Target;
  P^.CTick := P^.ST[P^.N - 1];
  P^.N := 0;
end;

function Change(ID, Tick, W, A, SW, SA, Flags: LongInt; X, Y: Single; out Value: LongInt): LongInt;
var
  P: ^TAmPlayer;
  Old, OldC, Out, K, FixTo, BackC: LongInt;
  Back: Boolean;
begin
  P := @Pl[ID];
  Old := P^.W;
  FixTo := -1;
  SettleReload(ID);
  { the weapon he put away comes back into the hands }
  Back := (P^.HW >= 0) and (W = P^.HW) and (SW = Old);
  BackC := P^.HC;
  OldC := P^.C - ShotsIn(P^, P^.CTick, Tick + 1);
  if OldC < 0 then
    OldC := 0;
  Out := 0;
  if Counted(Old) then
    Out := Interrupted(ID, Tick);
  if Out > 0 then
  begin
    OldC := 0;
    if CfgKeep then
      PutBack(ID, Old, Out);
  end;
  if P^.RpState > 0 then
  begin
    P^.RpState := 0;
    P^.RpEvent := AMR_STOPPED;
  end;
  if (SW >= 0) and Counted(Old) and (W = P^.SW) and (SW = Old) then
  begin
    P^.SW := Old;
    P^.SA := OldC;
    P^.HW := Old;
    P^.HC := OldC;
  end
  else
  begin
    if Counted(Old) then
      if not ((SW >= 0) and (SW = Old)) then
        GroundAdd(ID, Tick, Old, OldC, X, Y, False);
    PickUp(ID, Tick, W);
    if SW >= 0 then
    begin
      P^.SW := SW;
      P^.SA := SA;
    end;
  end;
  { a weapon put away cannot gain rounds: what the game shows above what it had was never paid for (a human's
    game; a bot's count is the server's own) }
  if Back then
  begin
    if (Flags and AMF_HUMAN) <> 0 then
      if Counted(W) and (W <> W_SAW) then
        if A > BackC then
        begin
          FixTo := BackC;
          A := BackC;
        end;
    if not ((SW >= 0) and Counted(Old) and (W = P^.SW) and (SW = Old)) then
      P^.HW := -1;
  end;
  P^.W := W;
  P^.C := A;
  P^.CTick := Tick;
  P^.N := 0;
  P^.Discard := 0;
  P^.HoldUntil := Tick + CHANGE_HOLD;
  P^.HoldVal := A;
  P^.Dry := False;
  P^.ShotW := W;
  P^.ShotN := 0;
  MinFrom(P^, A, Tick);
  ShowFrom(P^, A, Tick);
  Dirty(ID);
  Value := 0;
  Result := AMA_HUD;
  if FixTo >= 0 then
    Result := SetTo(ID, Tick, FixTo, Value);
  { a weapon that came over from the last round: the game gave it a fresh magazine, he loads his own - the
    fullest of its pouch }
  if Counted(W) and (W <> W_SAW) then
    if P^.Carry[W] then
    begin
      P^.Carry[W] := False;
      if UsesMags(W) then
      begin
        K := TakeMag(P^.Pouch[W]);
        if K < 0 then
          K := 0;
      end
      else
      begin
        K := P^.Pouch[W].Reserve;
        if K > Cap(W) then
          K := Cap(W);
        P^.Pouch[W].Reserve := P^.Pouch[W].Reserve - K;
      end;
      if K <> A then
      begin
        Result := SetTo(ID, Tick, K, Value);
        A := K;
      end;
    end;
  { an empty weapon with nothing to load (picked up empty): it goes, or it is kept at 0 before the
    game can reload it }
  if (A = 0) and Counted(W) and (W <> W_SAW) then
    if Left(ID, W) <= 0 then
      Result := Empty(ID, Tick, Flags, Value);
end;

{ ---------------- the interface ---------------- }

procedure AmmoConfig(Enabled, MagMode, EmptyDrop, PickupFullSet, TrackGround, SawIdleTicks, SawAttackTicks,
  SawAttackDrain: LongInt; LootRadius: Single);
begin
  CfgOn := Enabled <> 0;
  CfgMag := MagMode <> 0;
  CfgEmptyDrop := EmptyDrop <> 0;
  CfgFullSet := PickupFullSet <> 0;
  CfgGround := TrackGround <> 0;
  if SawIdleTicks < 1 then
    SawIdleTicks := 1;
  if SawAttackTicks < 1 then
    SawAttackTicks := 1;
  if SawAttackDrain < 0 then
    SawAttackDrain := 0;
  CfgSawIdle := SawIdleTicks;
  CfgSawAttack := SawAttackTicks;
  CfgSawDrain := SawAttackDrain;
  if LootRadius < 5 then
    LootRadius := 5;
  CfgLootRadius := LootRadius;
end;

procedure AmmoOptions(OneRound, KeepInterrupted, SortMags, RepackStartTicks, RepackStepTicks: LongInt);
begin
  CfgOneRound := OneRound <> 0;
  CfgKeep := KeepInterrupted <> 0;
  CfgSort := SortMags <> 0;
  if RepackStartTicks < 0 then
    RepackStartTicks := 0;
  if RepackStepTicks < 1 then
    RepackStepTicks := 1;
  CfgRpStart := RepackStartTicks;
  CfgRpStep := RepackStepTicks;
end;

procedure AmmoSetText(Kind: LongInt; const S: AnsiString);
begin
  if Kind = AMT_NO_SPARE then
    TxtNoSpare := S;
end;

procedure AmmoSetReserve(W, Rounds: LongInt);
begin
  if (W >= 0) and (W < AM_W) then
  begin
    if Rounds < 0 then
      Rounds := 0;
    ResMax[W] := Rounds;
  end;
end;

procedure AmmoLimit(Extra: LongInt);
begin
  if Extra < -1 then
    Extra := -1;
  if Extra > MAX_MAGS then
    Extra := MAX_MAGS;
  CfgExtra := Extra;
end;

procedure AmmoRespawn(ID, Tick: LongInt);
var
  w: LongInt;
begin
  if not ValidID(ID) then
    Exit;
  for w := 0 to MAX_GROUND - 1 do
    if Ground[w].Active then
      if Ground[w].Body then
        if Ground[w].Owner = ID then
          Ground[w].Active := False;
  ObjSlot[ID] := 0;
  for w := 0 to AM_W - 1 do
    ClearPouch(Pl[ID].Pouch[w]);
  Pl[ID].W := W_NONE;
  Pl[ID].SW := -1;
  Pl[ID].SA := 0;
  Pl[ID].HW := -1;
  Pl[ID].HC := 0;
  Pl[ID].C := 0;
  Pl[ID].CTick := Tick;
  Pl[ID].Discard := 0;
  Pl[ID].ReloadKeyTick := -1000000;
  Pl[ID].HoldUntil := 0;
  Pl[ID].HoldVal := 0;
  Pl[ID].PickFrom := -1;
  Pl[ID].PickTick := -1;
  Pl[ID].N := 0;
  Pl[ID].SawIdleAt := 0;
  Pl[ID].SawAttackAt := 0;
  Pl[ID].SawHudAt := 0;
  Pl[ID].HudDirty := True;
  Pl[ID].HudAt := 0;
  Pl[ID].DropW := -1;
  Pl[ID].DropTick := 0;
  Pl[ID].MinNZ := 0;
  Pl[ID].MinNZTick := Tick;
  Pl[ID].ShotW := W_NONE;
  Pl[ID].ShotN := 0;
  Pl[ID].Dry := False;
  Pl[ID].DryAt := 0;
  Pl[ID].RpState := 0;
  Pl[ID].RpW := -1;
  Pl[ID].RpNext := 0;
  Pl[ID].RpEvent := AMR_NONE;
  ShowFrom(Pl[ID], 0, Tick);
  Pl[ID].LastShown := -1;
  Pl[ID].Paused := False;
  { the ammunition kept from the last round }
  for w := 0 to AM_W - 1 do
    Pl[ID].Carry[w] := False;
  if Kept[ID].Saved then
  begin
    Kept[ID].Saved := False;
    for w := 0 to AM_W - 1 do
    begin
      Pl[ID].Pouch[w] := Kept[ID].Pouch[w];
      Pl[ID].Carry[w] := Kept[ID].Pouch[w].Used and (w <> W_SAW);
    end;
  end;
end;

{ rounds put into a pouch of the kept state }
procedure CarryPut(var P: TPouch; W, Rounds: LongInt);
begin
  if (Rounds <= 0) or not Counted(W) then
    Exit;
  P.Used := True;
  if UsesMags(W) then
    AddMag(P, Rounds)
  else
    P.Reserve := P.Reserve + Rounds;
end;

procedure AmmoCarrySave(ID, Tick: LongInt);
var
  P: ^TAmPlayer;
  W, C, k: LongInt;
begin
  if not CfgOn or not ValidID(ID) then
    Exit;
  P := @Pl[ID];
  for k := 0 to AM_W - 1 do
    Kept[ID].Pouch[k] := P^.Pouch[k];
  W := P^.W;
  if Counted(W) and (W <> W_SAW) then
  begin
    C := P^.C - ShotsIn(P^, P^.CTick, Tick + 1);
    Kept[ID].Pouch[W].Used := True;
    CarryPut(Kept[ID].Pouch[W], W, C);
  end;
  if Counted(P^.SW) and (P^.SW <> W) and (P^.SW <> W_SAW) then
    if P^.Pouch[P^.SW].Used then
      CarryPut(Kept[ID].Pouch[P^.SW], P^.SW, P^.SA);
  Kept[ID].Saved := True;
  Kept[ID].Tick := Tick;
end;

procedure AmmoCarryConfirm(ID: LongInt);
var
  g: LongInt;
begin
  if not ValidID(ID) then
    Exit;
  if not Kept[ID].Saved then
    Exit;
  for g := 0 to MAX_GROUND - 1 do
    if Ground[g].Active then
      if Ground[g].Owner = ID then
        if Abs(Ground[g].Tick - Kept[ID].Tick) <= 2 then
          Ground[g].Active := False;
end;

procedure AmmoCarryDrop(ID: LongInt);
begin
  if ValidID(ID) then
    Kept[ID].Saved := False;
end;

function AmmoCarryKept(ID: LongInt): LongInt;
begin
  Result := 0;
  if ValidID(ID) then
    if Kept[ID].Saved then
      Result := 1;
end;

function AmmoLeftOf(ID, W, Tick: LongInt): LongInt;
var
  P: ^TAmPlayer;
  C: LongInt;
begin
  Result := -1;
  if not CfgOn or not ValidID(ID) or not Counted(W) then
    Exit;
  P := @Pl[ID];
  if not P^.Pouch[W].Used then
    if W <> P^.W then
      Exit;
  Result := Left(ID, W);
  if W = P^.W then
  begin
    C := P^.C - ShotsIn(P^, P^.CTick, Tick + 1);
    if C > 0 then
      Result := Result + C;
  end
  else if W = P^.SW then
    if P^.SA > 0 then
      Result := Result + P^.SA;
end;

{ the pouch of W up to a fresh set and his class's extra magazines: full magazines (or rounds of the pool) are
  added, nothing he has is taken away (a bounty's reward, a resupply); True = something was added }
function TopUpPouch(ID, W: LongInt): Boolean;
var
  P: ^TPouch;
  C, Want, Have, k: LongInt;
begin
  Result := False;
  P := @Pl[ID].Pouch[W];
  C := Cap(W);
  if C < 1 then
    C := 1;
  if UsesMags(W) then
  begin
    Want := (FreshMags(W, ResMax[W]) + Pl[ID].Extra) * C;
    Have := P^.Reserve;
    for k := 0 to P^.MagN - 1 do
      Have := Have + P^.Mags[k];
    while (Have < Want) and (P^.MagN < MAX_MAGS) do
    begin
      AddMag(P^, C);
      Have := Have + C;
      Result := True;
    end;
  end
  else
  begin
    Want := ResMax[W] + Pl[ID].Extra * C;
    if P^.Reserve < Want then
    begin
      P^.Reserve := Want;
      Result := True;
    end;
  end;
  P^.Used := True;
end;

procedure AmmoRefill(ID, W: LongInt);
begin
  if not CfgOn or not ValidID(ID) or not Counted(W) or (W = W_SAW) then
    Exit;
  Touch(ID, W);
  if TopUpPouch(ID, W) then
    Dirty(ID);
end;

procedure AmmoPlayerExtra(ID, N: LongInt);
begin
  if not ValidID(ID) then
    Exit;
  if N < 0 then
    N := 0;
  if N > MAX_MAGS then
    N := MAX_MAGS;
  Pl[ID].Extra := N;
end;

function AmmoAddMags(ID, W, N: LongInt): LongInt;
var
  C, k, Room, Lim: LongInt;
begin
  Result := 0;
  if not CfgOn or not ValidID(ID) or not Counted(W) or (W = W_SAW) or (N <= 0) then
    Exit;
  Touch(ID, W);
  C := Cap(W);
  if UsesMags(W) then
  begin
    { a class's extra magazines on top of ExtraMagazines }
    Lim := MagLimit(W);
    if CfgExtra >= 0 then
      Lim := Lim + Pl[ID].Extra;
    if Lim > MAX_MAGS then
      Lim := MAX_MAGS;
    Room := Lim - Pl[ID].Pouch[W].MagN;
    if Room > N then
      Room := N;
    for k := 1 to Room do
    begin
      AddMag(Pl[ID].Pouch[W], C);
      Inc(Result);
    end;
  end
  else
    for k := 1 to N do
      if Pl[ID].Pouch[W].Reserve + C <= SpareLimit(W) + Pl[ID].Extra * C then
      begin
        Pl[ID].Pouch[W].Reserve := Pl[ID].Pouch[W].Reserve + C;
        Inc(Result);
      end;
  if Result > 0 then
    Dirty(ID);
end;

function AmmoTopUp(ID, W: LongInt): LongInt;
begin
  Result := 0;
  if not CfgOn or not ValidID(ID) or not Counted(W) or (W = W_SAW) then
    Exit;
  Touch(ID, W);
  if TopUpPouch(ID, W) then
  begin
    Dirty(ID);
    Result := 1;
  end;
end;

procedure AmmoPause(ID, On, Tick: LongInt);
begin
  if not ValidID(ID) then
    Exit;
  if On <> 0 then
    Pl[ID].Paused := True
  else if Pl[ID].Paused then
  begin
    Pl[ID].Paused := False;
    Pl[ID].HoldUntil := Tick + HOLD;
    Pl[ID].HoldVal := Pl[ID].C;
    Pl[ID].DropW := -1;
  end;
end;

{ a bullet of the soldier's weapon was made (the hook in CreateBullet); several in one tick are one
  shot (the Spas-12's pellets) }
procedure AmmoShot(ID, W, Tick: LongInt);
var
  P: ^TAmPlayer;
  k: LongInt;
begin
  if not CfgOn or not ValidID(ID) then
    Exit;
  P := @Pl[ID];
  if W <> P^.W then
    Exit;
  if P^.ShotW <> W then
  begin
    P^.ShotW := W;
    P^.ShotN := 0;
  end;
  if P^.ShotN > 0 then
    if P^.ShotT[P^.ShotN - 1] = Tick then
      Exit;
  if P^.ShotN >= SHOT_BUF then
  begin
    for k := 1 to SHOT_BUF - 1 do
      P^.ShotT[k - 1] := P^.ShotT[k];
    P^.ShotN := SHOT_BUF - 1;
  end;
  P^.ShotT[P^.ShotN] := Tick;
  Inc(P^.ShotN);
  Inc(StShots);
  Dirty(ID);
end;

{ the object styles of the dropped weapons: 4..14 the guns 0..10, 15 a bow, 25 the chainsaw, 26 the LAW }
function WeaponOfObject(S: LongInt): LongInt;
begin
  Result := -1;
  if (S >= 4) and (S <= 14) then
    Result := S - 4
  else if S = 25 then
    Result := W_SAW
  else if S = 26 then
    Result := 13
  else if S = 15 then
    Result := 15;
end;

procedure AmmoDropped(ID, ObjStyle, Slot, Tick: LongInt);
var
  W, i, Best: LongInt;
begin
  if not ValidID(ID) then
    Exit;
  W := WeaponOfObject(ObjStyle);
  if W < 0 then
    Exit;
  { a bow object stands for both bows }
  if (W = 15) and (Pl[ID].W = 16) then
    W := 16;
  { the record made just before the object (a death, a kick: the script hears of it first) gets it }
  Best := -1;
  for i := 0 to MAX_GROUND - 1 do
    if Ground[i].Active then
      if (Ground[i].Owner = ID) and (Ground[i].W = W) and (Ground[i].Slot = 0) and not Ground[i].Body then
        if (Tick - Ground[i].Tick >= 0) and (Tick - Ground[i].Tick <= 2) then
          if (Best < 0) or (Ground[i].Tick > Ground[Best].Tick) then
            Best := i;
  if Best >= 0 then
  begin
    Ground[Best].Slot := Slot;
    Ground[Best].MissingSince := 0;
    ObjSlot[ID] := 0;
    Exit;
  end;
  { else the record comes a moment later (a throw is seen in the next tick) }
  ObjW[ID] := W;
  ObjSlot[ID] := Slot;
  ObjTick[ID] := Tick;
end;

procedure AmmoSetBodyMode(Body: LongInt);
begin
  CfgBody := Body <> 0;
end;

procedure AmmoBodyMove(ID: LongInt; X, Y: Single);
var
  i: LongInt;
begin
  for i := 0 to MAX_GROUND - 1 do
    if Ground[i].Active then
      if Ground[i].Body then
        if Ground[i].Owner = ID then
        begin
          Ground[i].X := X;
          Ground[i].Y := Y;
        end;
end;

{ the magazine shown: the count known less the shots the hook saw after it; 0 while the client
  reloads (the count went to 0 with the reload key held) }
function ShownValue(ID, Tick, W, A: LongInt): LongInt;
var
  P: ^TAmPlayer;
begin
  P := @Pl[ID];
  if Tick < P^.HoldUntil then
    Result := P^.HoldVal
  else
    Result := P^.C;
  if W <> W_SAW then
    if P^.DispT <= Tick then
      Result := P^.DispV - ShotsIn(P^, P^.DispT, Tick);
  if (A = 0) and (W <> W_SPAS) and (W <> W_SAW) then
    if Tick - P^.ReloadKeyTick <= RELOAD_KEY_TICKS then
      Result := 0;
  if Result < 0 then
    Result := 0;
end;

function AmmoObserve(ID, Tick, W, A, SW, SA, Flags: LongInt; X, Y: Single; out Value: LongInt): LongInt;
var
  P: ^TAmPlayer;
  k, V, VT, R: LongInt;
  Same: Boolean;
begin
  Result := AMA_NONE;
  Value := 0;
  if not CfgOn or not ValidID(ID) then
    Exit;
  AmTick := Tick;
  P := @Pl[ID];
  if P^.Paused then
    Exit;
  if (Flags and AMF_RELOAD) <> 0 then
    P^.ReloadKeyTick := Tick;
  if W <> P^.W then
    if W = P^.DropW then
      if Tick - P^.DropTick < DROP_GUARD then
        Exit;
  if W <> P^.W then
  begin
    { 2.8.2 may report 255 for a tick: the change waits for a real count }
    if W <> W_SAW then
      if Counted(W) then
        if (A < 0) or (A > Cap(W)) then
          Exit;
    Result := Change(ID, Tick, W, A, SW, SA, Flags, X, Y, Value);
    P^.HudDirty := False;
    P^.HudAt := Tick + HUD_TICKS;
    Exit;
  end;
  if SW >= 0 then
  begin
    P^.SW := SW;
    P^.SA := SA;
  end;
  { the weapon put away is not his second one any more (thrown, given, a new life) }
  if P^.HW >= 0 then
    if SW >= 0 then
      if SW <> P^.HW then
        P^.HW := -1;
  if not Counted(W) then
    Exit;
  Touch(ID, W);
  if P^.RpState > 0 then
    RepackTick(ID, Tick, W, Flags);
  if (Flags and AMF_FREE) <> 0 then
  begin
    { infinite ammo: the count is followed, nothing is used (the chainsaw's fuel neither) }
    if W <> W_SAW then
    begin
      P^.C := A;
      P^.CTick := Tick;
      P^.N := 0;
      P^.Discard := 0;
      P^.Dry := False;
      MinFrom(P^, A, Tick);
      ShowFrom(P^, A, Tick);
    end;
    Exit;
  end;
  if W = W_SAW then
  begin
    Result := SawTick(ID, Tick, Flags, Value);
    Exit;
  end;
  { a shot from a magazine believed empty proves a reload (see ProvenReload); shots the client fired
    before it got a count set by the script are not counted (DispT is after them) }
  if (P^.C = 0) and (P^.DispV = 0) and (W <> W_SPAS) then
    if P^.DispT <= Tick then
      if ShotsIn(P^, P^.DispT, Tick) > 0 then
      begin
        R := ProvenReload(ID, Tick, Flags, Value);
        if (R = AMA_SET) or (R = AMA_DROP) then
        begin
          Result := R;
          P^.HudDirty := False;
          P^.HudAt := Tick + HUD_TICKS;
          Exit;
        end;
        if P^.W <> W then
          Exit;
      end;
  { 2.8.2 may report 255 for a tick; a count above the magazine size is not a count }
  if (A < 0) or (A > Cap(W)) then
    Exit;
  { EmptyDrop = 0: nothing to load, the magazine stays at 0 (set again now and then, and at once when
    a report shows rounds after the last setting reached the client) }
  if P^.Dry then
  begin
    if Left(ID, W) + P^.Discard > 0 then
      P^.Dry := False
    else
    begin
      if (Tick >= P^.DryAt) or ((A > 0) and (Tick >= P^.HoldUntil)) then
      begin
        P^.DryAt := Tick + DryTicks(W);
        Result := SetTo(ID, Tick, 0, Value);
        P^.HudDirty := False;
        P^.HudAt := Tick + HUD_TICKS;
      end;
      Exit;
    end;
  end;
  if Tick < P^.HoldUntil then
  begin
    { the reports sent before the client got the count still show the old one. The count itself: the
      client has it (the shots before it were not from this magazine). A 0 with the reload key held:
      the client reloads that magazine. Fewer rounds, and at least as many shots seen since the
      setting: the client fired from it. }
    if A = P^.HoldVal then
    begin
      P^.CTick := Tick;
      MinFrom(P^, A, Tick);
      ShowFrom(P^, A, Tick);
    end
    else if (A = 0) and (Tick - P^.ReloadKeyTick <= 3) and (W <> W_SPAS) then
      ShowFrom(P^, 0, Tick)
    else if (A > 0) and (A < P^.HoldVal) and (P^.HoldVal - A <= ShotsIn(P^, P^.CTick, Tick)) then
      ShowFrom(P^, A, Tick)
    else
      Exit;
    P^.HoldUntil := Tick;
  end;
  Push(P^, Tick, A);
  while (P^.N > 1) and (Tick - P^.ST[0] >= CONFIRM) do
  begin
    V := P^.SV[0];
    VT := P^.ST[0];
    DropFirst(P^);
    if (V > 0) and ((P^.MinNZ <= 0) or (V < P^.MinNZ)) then
    begin
      P^.MinNZ := V;
      P^.MinNZTick := VT;
    end;
    if V = P^.C then
      Continue;
    Same := True;
    for k := 0 to P^.N - 1 do
      if V < P^.C then
      begin
        if P^.SV[k] >= P^.C then
          Same := False;
      end
      else if P^.SV[k] <= P^.C then
        Same := False;
    if not Same then
      Continue;
    R := Apply(ID, Tick, VT, V, Flags, Value);
    if (R = AMA_SET) or (R = AMA_DROP) then
    begin
      Result := R;
      P^.HudDirty := False;
      P^.HudAt := Tick + HUD_TICKS;
      Exit;
    end;
    if P^.W <> W then
      Exit;
  end;
  { the client keeps reporting the believed count well after the last shot: that is what it has (a
    shot counted twice, a bullet that came in before an older report) }
  if P^.W = W then
    if (Tick >= P^.HoldUntil) and (A = P^.C) and (W <> W_SAW) then
      if (P^.ShotN = 0) or (P^.ShotT[P^.ShotN - 1] < Tick - 10) then
        if P^.DispV - ShotsIn(P^, P^.DispT, Tick) <> A then
          ShowFrom(P^, A, Tick);
  if not P^.HudDirty then
    if P^.W = W then
      if ShownValue(ID, Tick, W, A) <> P^.LastShown then
      begin
        P^.HudDirty := True;
        P^.LastShown := ShownValue(ID, Tick, W, A);
      end;
  if P^.HudDirty then
    if Tick >= P^.HudAt then
    begin
      P^.HudDirty := False;
      P^.HudAt := Tick + HUD_TICKS;
      Result := AMA_HUD;
    end;
end;

procedure AmmoKeep(ID, W, Rounds: LongInt);
begin
  if not ValidID(ID) then
    Exit;
  if (Rounds <= 0) or not Counted(W) then
    Exit;
  if W <> Pl[ID].W then
    Exit;
  Pl[ID].Discard := Pl[ID].Discard + Rounds;
  Dirty(ID);
end;

procedure AmmoForced(ID, Tick, W, Value: LongInt);
begin
  if not ValidID(ID) then
    Exit;
  if W <> Pl[ID].W then
    Exit;
  if Value < 0 then
    Value := 0;
  Pl[ID].C := Value;
  Pl[ID].CTick := Tick;
  Pl[ID].HoldUntil := Tick + HOLD;
  Pl[ID].HoldVal := Value;
  Pl[ID].N := 0;
  MinFrom(Pl[ID], Value, Tick);
  ShowFrom(Pl[ID], Value, Tick + HOLD);
  Dirty(ID);
end;

function AmmoClip(ID, Tick, A: LongInt): LongInt;
begin
  Result := A;
  if not ValidID(ID) then
    Exit;
  if Tick < Pl[ID].HoldUntil then
    Result := Pl[ID].HoldVal;
end;

{ the magazine to show (the health line, !ammo): the believed count, so the server's short guesses
  (a full magazine for a moment during a reload) never appear; A while another weapon is followed }
function AmmoShown(ID, Tick, W, A: LongInt): LongInt;
begin
  Result := A;
  if not CfgOn or not ValidID(ID) then
    Exit;
  if W <> Pl[ID].W then
    Exit;
  Result := ShownValue(ID, Tick, W, A);
  Pl[ID].LastShown := Result;
end;

{ the weapon in the hands stays on the ground: with the spare magazines of its kind, or (Body) with
  its magazine only, all the spare magazines staying with the body }
function LeaveWeapon(ID, Tick: LongInt; X, Y: Single; Body: Boolean): LongInt;
var
  W, C, Out, k: LongInt;
begin
  Result := -1;
  if not CfgOn or not ValidID(ID) then
    Exit;
  W := Pl[ID].W;
  if Counted(W) then
    if CfgGround then
    begin
      C := Pl[ID].C - ShotsIn(Pl[ID], Pl[ID].CTick, Tick + 1);
      if C < 0 then
        C := 0;
      Out := Interrupted(ID, Tick);
      if Out > 0 then
      begin
        C := 0;
        if CfgKeep then
          PutBack(ID, W, Out);
      end;
      GroundAdd(ID, Tick, W, C, X, Y, not Body);
      Result := W;
    end;
  if Body then
    if CfgGround then
      for k := 0 to AM_W - 1 do
        if Counted(k) and (k <> W_SAW) then
          if Pl[ID].Pouch[k].Used then
            if (Pl[ID].Pouch[k].MagN > 0) or (Pl[ID].Pouch[k].Reserve > 0) then
              GroundAddAs(ID, Tick, k, 0, X, Y, True, True);
  Pl[ID].W := W_NONE;
  Pl[ID].N := 0;
  Pl[ID].Discard := 0;
  Pl[ID].Dry := False;
  Pl[ID].RpState := 0;
end;

function AmmoDeath(ID, Tick: LongInt; X, Y: Single): LongInt;
begin
  Result := LeaveWeapon(ID, Tick, X, Y, CfgBody);
end;

function AmmoLeftBehind(ID, Tick: LongInt; X, Y: Single): LongInt;
begin
  Result := LeaveWeapon(ID, Tick, X, Y, False);
end;

function AmmoSelectMag(ID, W, Index: LongInt): LongInt;
begin
  Result := 0;
  if not ValidID(ID) or not Counted(W) then
    Exit;
  if (Index >= 0) and (Index < Pl[ID].Pouch[W].MagN) then
  begin
    Pl[ID].Pouch[W].Sel := Index;
    Result := 1;
  end;
end;

{ /mag: reload now; the magazine in the weapon goes back into the pouch. 1 = the script sets the
  magazine to 0 (the game then reloads) }
function AmmoReloadNow(ID, Tick, Clip: LongInt): LongInt;
var
  V: LongInt;
begin
  Result := 0;
  if not CfgOn or not ValidID(ID) then
    Exit;
  if not Counted(Pl[ID].W) or (Pl[ID].W = W_SPAS) or (Pl[ID].W = W_SAW) then
    Exit;
  if Clip <= 0 then
    Exit;
  Pl[ID].Discard := Clip;
  SetTo(ID, Tick, 0, V);
  Result := 1;
end;

function AmmoMagCount(ID, W: LongInt): LongInt;
begin
  Result := 0;
  if ValidID(ID) and Counted(W) then
    if UsesMags(W) then
      Result := Pl[ID].Pouch[W].MagN;
end;

function AmmoMagRounds(ID, W, Index: LongInt): LongInt;
begin
  Result := 0;
  if ValidID(ID) and Counted(W) then
    if (Index >= 0) and (Index < Pl[ID].Pouch[W].MagN) then
      Result := Pl[ID].Pouch[W].Mags[Index];
end;

function AmmoLoose(ID, W: LongInt): LongInt;
begin
  Result := 0;
  if ValidID(ID) and Counted(W) then
    Result := Pl[ID].Pouch[W].Reserve;
end;

function AmmoUsesMags(W: LongInt): LongInt;
begin
  Result := 0;
  if UsesMags(W) then
    Result := 1;
end;

{ the chainsaw's fuel: litres from 1 l up, millilitres below }
function FuelText(Ml: LongInt): AnsiString;
var
  Cl: LongInt;
begin
  if Ml < 0 then
    Ml := 0;
  if Ml < 1000 then
  begin
    Result := IntToStr(Ml) + ' ml';
    Exit;
  end;
  Cl := Ml div 10;
  Result := IntToStr(Cl div 100) + '.';
  if Cl mod 100 < 10 then
    Result := Result + '0';
  Result := Result + IntToStr(Cl mod 100) + ' l';
end;

function AmmoFormatHud(ID, W, Clip: LongInt): AnsiString;
var
  k: LongInt;
begin
  Result := '';
  if not CfgOn or not ValidID(ID) or not Counted(W) then
    Exit;
  if W = W_SAW then
  begin
    Result := ' | Fuel: ' + FuelText(Pl[ID].Pouch[W].Reserve);
    Exit;
  end;
  if Clip < 0 then
    Clip := 0;
  if UsesMags(W) then
  begin
    Result := ' | Ammo: ' + IntToStr(Clip) + ' [';
    if Pl[ID].Pouch[W].MagN = 0 then
      Result := Result + TxtNoSpare;
    for k := 0 to Pl[ID].Pouch[W].MagN - 1 do
    begin
      if k > 0 then
        Result := Result + ', ';
      Result := Result + IntToStr(Pl[ID].Pouch[W].Mags[k]);
    end;
    Result := Result + ']';
    if Pl[ID].Pouch[W].Reserve > 0 then
      Result := Result + ' +' + IntToStr(Pl[ID].Pouch[W].Reserve);
  end
  else
    Result := ' | Ammo: ' + IntToStr(Clip) + '/' + IntToStr(Pl[ID].Pouch[W].Reserve);
end;

{ what is left of a full load, in percent (the magazine and the spare rounds against a fresh weapon's;
  the chainsaw: the fuel); 0 = nothing at all }
function AmmoLevel(ID, W, Clip: LongInt): LongInt;
var
  Total, Full: LongInt;
begin
  Result := 100;
  if not CfgOn or not ValidID(ID) or not Counted(W) then
    Exit;
  if Clip < 0 then
    Clip := 0;
  if W = W_SAW then
  begin
    Total := Pl[ID].Pouch[W].Reserve;
    Full := ResMax[W];
  end
  else
  begin
    Total := Clip + Left(ID, W) + Pl[ID].Discard;
    Full := Cap(W);
    if UsesMags(W) then
      Full := Full + Cap(W) * FreshMags(W, ResMax[W])
    else
      Full := Full + ResMax[W];
  end;
  if Total <= 0 then
  begin
    Result := 0;
    Exit;
  end;
  if Full <= 0 then
    Exit;
  Result := Total * 100 div Full;
  if Result < 1 then
    Result := 1;
  if Result > 100 then
    Result := 100;
end;

{ /repack: 1 = it begins after RepackStart ticks without shooting, 0 = nothing to put together,
  -1 = the weapon has no magazines, -2 = no weapon in the hands }
function AmmoRepack(ID, Tick: LongInt): LongInt;
var
  P: ^TAmPlayer;
  W: LongInt;
begin
  Result := -2;
  if not CfgOn or not ValidID(ID) then
    Exit;
  P := @Pl[ID];
  W := P^.W;
  if not Counted(W) then
    Exit;
  Result := -1;
  if not UsesMags(W) then
    Exit;
  Result := 0;
  if not NeedRepack(P^.Pouch[W], Cap(W)) then
    Exit;
  P^.RpState := 1;
  P^.RpW := W;
  P^.RpNext := Tick + CfgRpStart;
  P^.RpEvent := AMR_NONE;
  Result := 1;
end;

function AmmoRepacking(ID: LongInt): LongInt;
begin
  Result := 0;
  if ValidID(ID) then
    Result := Pl[ID].RpState;
end;

function AmmoRepackEvent(ID: LongInt): LongInt;
begin
  Result := AMR_NONE;
  if not ValidID(ID) then
    Exit;
  Result := Pl[ID].RpEvent;
  Pl[ID].RpEvent := AMR_NONE;
end;

{ looting a dead soldier's weapon of the same kind lying under a crouching soldier: 1 = there is
  something to take }
function AmmoCanLoot(ID, W: LongInt; X, Y: Single): LongInt;
var
  g, k, C: LongInt;
begin
  Result := 0;
  if not CfgOn or not ValidID(ID) or not Counted(W) or (W = W_SAW) then
    Exit;
  g := GroundNear(AmTick, W, X, Y, CfgLootRadius);
  if g < 0 then
    Exit;
  if not Ground[g].Corpse then
    Exit;
  C := Cap(W);
  if UsesMags(W) then
  begin
    if (Ground[g].MagN > 0) and (Pl[ID].Pouch[W].MagN < MagLimit(W)) then
      Result := 1
    else if (Ground[g].Reserve > 0) and (Pl[ID].Pouch[W].MagN < MagLimit(W)) then
      Result := 1
    else if (Ground[g].MagN > 0) or (Ground[g].Reserve > 0) then
      for k := 0 to Pl[ID].Pouch[W].MagN - 1 do
        if Pl[ID].Pouch[W].Mags[k] < C then
        begin
          Result := 1;
          Break;
        end;
  end
  else if (Ground[g].Reserve > 0) and (Pl[ID].Pouch[W].Reserve < SpareLimit(W)) then
    Result := 1;
end;

{ Repack = 0: take a spare magazine (or the reserve, at most up to a full one); Repack = 1: top up
  the own partial magazines with the rounds lying there. The rounds taken; -1 = the pouch is full }
function AmmoLoot(ID, W: LongInt; X, Y: Single; Repack: LongInt): LongInt;
var
  g, k, i, C, Missing, Taken: LongInt;
  P: ^TPouch;
begin
  Result := 0;
  if not CfgOn or not ValidID(ID) or not Counted(W) or (W = W_SAW) then
    Exit;
  g := GroundNear(AmTick, W, X, Y, CfgLootRadius);
  if g < 0 then
    Exit;
  if not Ground[g].Corpse then
    Exit;
  P := @Pl[ID].Pouch[W];
  if not P^.Used then
  begin
    ClearPouch(P^);
    P^.Used := True;
  end;
  C := Cap(W);
  if UsesMags(W) then
  begin
    if Repack = 0 then
    begin
      { D15: only loose rounds there - a magazine of them when his own are full and he has room, else his partial
        magazines are topped up (Repack = 1) }
      if Ground[g].MagN <= 0 then
      begin
        if Ground[g].Reserve <= 0 then
          Exit;
        for k := 0 to P^.MagN - 1 do
          if P^.Mags[k] < C then
          begin
            Result := -1;
            Exit;
          end;
        if P^.MagN >= MagLimit(W) then
        begin
          Result := -1;
          Exit;
        end;
        Taken := Ground[g].Reserve;
        if Taken > C then
          Taken := C;
        Ground[g].Reserve := Ground[g].Reserve - Taken;
        AddMag(P^, Taken);
        if CfgSort then
          SortPouch(P^);
        Result := Taken;
        if Ground[g].Reserve <= 0 then
          Ground[g].Active := False;
        Dirty(ID);
        Exit;
      end;
      if P^.MagN >= MagLimit(W) then
      begin
        Result := -1;
        Exit;
      end;
      Result := Ground[g].Mags[0];
      for k := 0 to Ground[g].MagN - 2 do
        Ground[g].Mags[k] := Ground[g].Mags[k + 1];
      Ground[g].Mags[Ground[g].MagN - 1] := 0;
      Dec(Ground[g].MagN);
      AddMag(P^, Result);
    end
    else
    begin
      Taken := 0;
      for k := 0 to P^.MagN - 1 do
      begin
        Missing := C - P^.Mags[k];
        while (Missing > 0) and (Ground[g].Reserve > 0) do
        begin
          Dec(Ground[g].Reserve);
          Inc(P^.Mags[k]);
          Dec(Missing);
          Inc(Taken);
        end;
        while (Missing > 0) and (Ground[g].MagN > 0) do
        begin
          i := Ground[g].MagN - 1;
          if Ground[g].Mags[i] > 0 then
          begin
            Dec(Ground[g].Mags[i]);
            Inc(P^.Mags[k]);
            Dec(Missing);
            Inc(Taken);
          end;
          if Ground[g].Mags[i] <= 0 then
            Dec(Ground[g].MagN);
        end;
      end;
      if CfgSort then
        SortPouch(P^);
      Result := Taken;
    end;
  end
  else
  begin
    Taken := Ground[g].Reserve;
    if P^.Reserve + Taken > SpareLimit(W) then
      Taken := SpareLimit(W) - P^.Reserve;
    if Taken <= 0 then
    begin
      Result := -1;
      Exit;
    end;
    P^.Reserve := P^.Reserve + Taken;
    Ground[g].Reserve := Ground[g].Reserve - Taken;
    Result := Taken;
  end;
  if (Ground[g].MagN <= 0) and (Ground[g].Reserve <= 0) then
    Ground[g].Active := False;
  Dirty(ID);
end;

procedure AmmoGroundClear;
var
  i: LongInt;
begin
  for i := 0 to MAX_GROUND - 1 do
    Ground[i].Active := False;
end;

procedure AmmoPickFrom(ID, Tick, Index: LongInt);
begin
  if not ValidID(ID) then
    Exit;
  Pl[ID].PickFrom := Index;
  Pl[ID].PickTick := Tick;
end;

function AmmoGroundNext(W, From: LongInt): LongInt;
var
  i: LongInt;
begin
  Result := -1;
  if From < 0 then
    From := 0;
  for i := From to MAX_GROUND - 1 do
    if Ground[i].Active and not Ground[i].Body then
    begin
      if Ground[i].Slot = 0 then
        if not Ground[i].Corpse then
          if AmTick - Ground[i].Tick > 300 then
          begin
            Ground[i].Active := False;
            Continue;
          end;
      if (W < 0) or (Ground[i].W = W) then
      begin
        Result := i;
        Exit;
      end;
    end;
end;

function AmmoGroundSlot(Index: LongInt): LongInt;
begin
  Result := 0;
  if (Index >= 0) and (Index < MAX_GROUND) then
    if Ground[Index].Active then
      Result := Ground[Index].Slot;
end;

function AmmoGroundKind(Index: LongInt): LongInt;
begin
  Result := -1;
  if (Index >= 0) and (Index < MAX_GROUND) then
    if Ground[Index].Active then
      Result := Ground[Index].W;
end;

function AmmoGroundAge(Index, Tick: LongInt): LongInt;
begin
  Result := -1;
  if (Index >= 0) and (Index < MAX_GROUND) then
    if Ground[Index].Active then
      Result := Tick - Ground[Index].Tick;
end;

function AmmoGroundDist(Index: LongInt; X, Y: Single): LongInt;
begin
  Result := 1000000;
  if (Index >= 0) and (Index < MAX_GROUND) then
    if Ground[Index].Active then
      Result := Round(Sqrt(Sqr(Ground[Index].X - X) + Sqr(Ground[Index].Y - Y)));
end;

function AmmoGroundHasSlot(Slot: LongInt): LongInt;
var
  i: LongInt;
begin
  Result := 0;
  if Slot <= 0 then
    Exit;
  for i := 0 to MAX_GROUND - 1 do
    if Ground[i].Active then
      if Ground[i].Slot = Slot then
      begin
        Result := 1;
        Exit;
      end;
end;

{ the newest record of this soldier's weapon of kind W (dropped alive, or with his body) without an
  object gets the object Slot; 1 = attached }
function AmmoGroundAttach(ID, W, Slot, Corpse, Tick: LongInt): LongInt;
var
  i, Best: LongInt;
begin
  Result := 0;
  if Slot <= 0 then
    Exit;
  Best := -1;
  for i := 0 to MAX_GROUND - 1 do
    if Ground[i].Active then
      if (Ground[i].Owner = ID) and (Ground[i].W = W) and (Ground[i].Slot = 0) and not Ground[i].Body and
        ((Ground[i].Corpse = (Corpse <> 0)) or CfgBody) and (Tick - Ground[i].Tick <= ATTACH_TICKS) then
        if (Best < 0) or (Ground[i].Tick > Ground[Best].Tick) then
          Best := i;
  if Best < 0 then
    Exit;
  Ground[Best].Slot := Slot;
  Ground[Best].MissingSince := 0;
  Result := 1;
end;

procedure AmmoGroundMove(Index: LongInt; X, Y: Single);
begin
  if (Index >= 0) and (Index < MAX_GROUND) then
    if Ground[Index].Active then
    begin
      Ground[Index].X := X;
      Ground[Index].Y := Y;
      Ground[Index].MissingSince := 0;
    end;
end;

{ the record's object is not on the map: gone for good after MISSING_TICKS (a pickup is resolved
  before that) }
procedure AmmoGroundMissing(Index, Tick: LongInt);
begin
  if (Index >= 0) and (Index < MAX_GROUND) then
    if Ground[Index].Active then
    begin
      if Ground[Index].MissingSince = 0 then
        Ground[Index].MissingSince := Tick
      else if Tick - Ground[Index].MissingSince >= MISSING_TICKS then
        Ground[Index].Active := False;
    end;
end;

var
  LastW: array[1..BE_PLAYERS] of LongInt;
  PassID, PassAct, PassVal: array[0..BE_PLAYERS - 1] of LongInt;
  PassN: LongInt = 0;

procedure AmmoLastW(ID, W: LongInt);
begin
  if ValidID(ID) then
    LastW[ID] := W;
end;

procedure PassAdd(ID, Act, Value: LongInt);
begin
  if PassN >= BE_PLAYERS then
    Exit;
  PassID[PassN] := ID;
  PassAct[PassN] := Act;
  PassVal[PassN] := Value;
  Inc(PassN);
end;

function AmmoPass(Tick: LongInt; Mask, Human, Free, Repack: LongWord): LongInt;
var
  ID, W, A, Fl, Act, V: LongInt;
  Alive, Fire, Reload: Boolean;
  Bit: LongWord;
begin
  PassN := 0;
  Result := 0;
  for ID := 1 to BE_PLAYERS do
  begin
    Bit := LongWord(1) shl (ID - 1);
    if (Mask and Bit) = 0 then
      Continue;
    if not SpriteRead(ID, Alive, W, A, Fire, Reload) then
    begin
      PassAdd(ID, AMA_FULL, 0);
      Continue;
    end;
    { the dead: the script moves their bodies' magazines now and then }
    if not Alive then
      Continue;
    if W <> LastW[ID] then
    begin
      PassAdd(ID, AMA_FULL, 0);
      Continue;
    end;
    Fl := 0;
    if (Human and Bit) <> 0 then
      Fl := Fl or AMF_HUMAN;
    if (W >= 0) and (W <= 16) then
    begin
      if Reload then
        Fl := Fl or AMF_RELOAD;
      if (W = W_SAW) or ((Repack and Bit) <> 0) then
        if Fire then
          Fl := Fl or AMF_SHOOT;
    end;
    if (Free and Bit) <> 0 then
      Fl := Fl or AMF_FREE;
    V := 0;
    Act := AmmoObserve(ID, Tick, W, A, -1, -1, Fl, 0, 0, V);
    if Act <> AMA_NONE then
      PassAdd(ID, Act, V);
  end;
  Result := PassN;
end;

procedure AmmoPassOp(k: LongInt; out ID, Act, Value: LongInt);
begin
  ID := 0;
  Act := AMA_NONE;
  Value := 0;
  if (k < 0) or (k >= PassN) then
    Exit;
  ID := PassID[k];
  Act := PassAct[k];
  Value := PassVal[k];
end;

function AmmoStatus: AnsiString;
var
  i, n, b: LongInt;
begin
  n := 0;
  b := 0;
  for i := 0 to MAX_GROUND - 1 do
    if Ground[i].Active then
      if Ground[i].Body then
        Inc(b)
      else
        Inc(n);
  Result := 'ammo: reloads ' + IntToStr(StReloads) + ', rounds loaded ' + IntToStr(StTaken) + ', magazines set ' +
    IntToStr(StSets) + ', weapons taken ' + IntToStr(StDrops) + ', shots seen ' + IntToStr(StShots) + ', repacks ' +
    IntToStr(StRepacks) + ', reloads seen only by a shot ' + IntToStr(StProven) + ', on the ground ' + IntToStr(n) +
    ', with bodies ' + IntToStr(b);
end;

procedure InitLastW;
var
  i: LongInt;
begin
  for i := 1 to BE_PLAYERS do
    LastW[i] := -1;
end;

initialization
  InitLastW;

end.
