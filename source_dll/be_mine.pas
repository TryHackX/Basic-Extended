unit be_mine;

{$mode objfpc}{$H+}
{$Q-}{$IFNDEF BE_CHECKS}{$R-}{$ENDIF}

{ [Mines]: the players' landmines and claymores. The script plants them (MnPlant) and makes their
  blasts (only it can make bullets); here they are looked after in every tick of the script:

  - armed ArmTicks after planting, gone after LifeTicks (0 = never);
  - a landmine goes off under an enemy: a point of his legs or body within TrigR px of it sideways and
    at most TrigH px above it (a soldier jumping or jetting over it passes, one crawling over it not);
  - a claymore goes off when an enemy's leg (or a lying body) crosses its tripwire - along the ground,
    WireH px high, from the claymore up to WireLen px ahead or the first wall - or with Fuse = cone when
    any point of him is in its front cone (ConeRange px, with nothing between); touching it (TouchR)
    sets it off from any side;
  - an enemy crouching or lying within SpotR px of a landmine he can see finds it: from then on he (and
    with SpotShare his team) sees its mark;
  - an enemy staying low within DefR px of one he sees takes it apart in DefTicks; the owner picks his
    own up the same way in PickTicks;
  - an enemy bullet the hook saw passing through a claymore (a landmine with ShootLand) sets it off;
  - with Corpses a dead soldier's body (an enemy's, or anybody's) that comes onto an armed landmine, onto
    a claymore or across its tripwire sets it off - a body lying there already when it was armed does
    not (a body is there from the death until the next life; its skeleton is the server's ragdoll).

  The soldiers are their skeletons as the server has them (be_sprite); for a player whose record is not
  known the script tells where he stands (MnPos). Each viewer gets the marks of the mines he may see,
  the nearest first, in the WorldText layers of the pool (be_texts: only what changed is sent); a layer
  keeps its mine while he still sees it. A new claymore's owner sees the edges of its cone for a moment
  (the preview, on layers of its own). A mine that goes while somebody works on it tells him
  (MNE_WORK_STOP). }

interface

uses
  be_hook;

const
  MN_LAND = 1;
  MN_CLAY = 2;
  { the events: Kind, Id (the mine), P (a player), Q }
  MNE_ARMED = 1;
  MNE_TRIGGER = 2;
  MNE_EXPIRE = 3;
  MNE_SHOT = 4;
  MNE_SPOTTED = 5;
  MNE_WORK = 6;
  MNE_WORK_STOP = 7;
  MNE_DEFUSED = 8;
  MNE_PICKED = 9;
  { MnSet keys }
  MNC_ON = 1;
  MNC_ARM = 2;
  MNC_LIFE = 3;
  MNC_TRIG_R = 4;
  MNC_TRIG_H = 5;
  MNC_FUSE = 6;
  MNC_WIRE_LEN = 7;
  MNC_WIRE_H = 8;
  MNC_CONE_ANGLE = 9;
  MNC_CONE_RANGE = 10;
  MNC_TOUCH = 11;
  MNC_SPOT = 12;
  MNC_SPOT_SHARE = 13;
  MNC_DEFUSE_R = 14;
  MNC_DEFUSE_T = 15;
  MNC_PICK_T = 16;
  MNC_SHOOT_LAND = 17;
  MNC_SHOOT_CLAY = 18;
  MNC_HIT_R = 19;
  MNC_SEEN_LAND = 20;
  MNC_SEEN_CLAY = 21;
  MNC_REAL = 22;
  MNC_MARK_SCALE = 23;
  MNC_WIRE_SCALE = 24;
  MNC_LAYER = 25;
  MNC_LAYERS = 26;
  MNC_PREVIEW = 27;
  MNC_PREVIEW_RANGE = 28;
  MNC_SPREAD = 29;
  MNC_MAX_TILT = 30;
  MNC_REFRESH = 31;
  MNC_SPECTATORS = 32;
  MNC_SIGHT = 33;
  MNC_PREV_LAYER = 34;
  MNC_PREV_EDGE = 35;
  MNC_PREV_ARC = 36;
  MNC_PREV_SCALE = 37;
  MNC_CORPSES = 38;
  { how the enemies see a mine every enemy may see: through walls, with nothing between their eyes and it
    only in realistic mode, always so }
  SIGHT_ALWAYS = 0;
  SIGHT_REALISTIC = 1;
  SIGHT_EYES = 2;
  { MnSetInt keys: the colours ($AARRGGBB) }
  MNI_OWN = 1;
  MNI_TEAM = 2;
  MNI_ENEMY = 3;
  MNI_ARMING = 4;
  MNI_WIRE = 5;
  MNI_PREVIEW = 6;
  { MnText keys }
  MNT_MINE = 1;
  MNT_CLAY_R = 2;
  MNT_CLAY_L = 3;
  MNT_WIRE = 4;
  MNT_PREVIEW = 5;
  { the fuses of a claymore }
  FUSE_WIRE = 1;
  FUSE_CONE = 2;
  { which dead soldiers' bodies set mines off: none, the enemies' (as the living), everybody's }
  CORPSE_OFF = 0;
  CORPSE_ENEMY = 1;
  CORPSE_ALL = 2;

procedure MnSet(Key: LongInt; Value: Single);
procedure MnSetInt(Key, Value: LongInt);
procedure MnText(Key: LongInt; const S: AnsiString);
{ the team (0 none, 1-4, 5 spectators) and whether he lives, from the script's events (BE_TkPlayer); a
  death leaves his body until the next life }
procedure MnPlayer(ID, NewTeam, IsAlive: LongInt);
{ a player (not a bot): only players pick their own mines up (a bot crouches near them by chance) }
procedure MnHuman(ID, Human: LongInt);
{ where a soldier the library does not know stands (his feet) and whether he crouches or lies }
procedure MnPos(ID: LongInt; X, Y: Single; Low: LongInt);
{ the slots (bit ID - 1) the script should tell about with MnPos (seen in the last MnTick) }
function MnWants: LongWord;
{ whether he holds crouch or lies now (the script reads the keys of the soldiers near a mine, MnNear) }
procedure MnLow(ID, Low: LongInt);
{ the soldiers near a mine (bit ID - 1), seen in the last MnTick: the script tells MnLow about them }
function MnNear: LongWord;
{ a mine of Owner at his feet (X, Y); a claymore looks from his upper body towards AimX, AimY (tilted
  at most MaxTilt from level). The number of the mine (1 ..), 0 = no room }
function MnPlant(Kind, Owner, Team: LongInt; X, Y, AimX, AimY: Single; Tick: LongInt): LongInt;
procedure MnRemove(Id: LongInt);
function MnRemoveOwner(Owner: LongInt): LongInt;
procedure MnClear;
function MnGet(Id: LongInt; out Kind, Owner, Team: LongInt; out X, Y, FX, FY: Single): Boolean;
{ how far under mine Id the ground stops bullets (a floor only the players stand on lets them through):
  -1 = not within 12 px - a blast in the ground would not go off there }
function MnGround(Id: LongInt): Single;
{ the mines of Owner (0 = everybody's) of Kind (0 = both) }
function MnCount(Owner, Kind: LongInt): LongInt;
{ the nearest mine to X, Y (0 = none) and how far }
function MnNearest(X, Y: Single; out D: Single): LongInt;
{ a mine detector: every enemy mine within R px of X, Y that V has not found is found by him (with SpotShare his
  team too; MNE_SPOTTED with Q = 1); the number found now }
function MnDetect(V: LongInt; X, Y, R: Single): LongInt;
{ the other mines within R of mine Id go off at AtTick }
procedure MnChain(Id: LongInt; R: Single; AtTick: LongInt);
{ from the hook (inside the server's CreateBullet): a copy of the shot, nothing more }
procedure MnQueueShot(const E: TShotEvent);
function MnTick(Tick: LongInt): LongInt;
function MnNext(out Kind, Id, P, Q: LongInt): Boolean;
{ the marks for Viewer standing at X, Y: the ops to send (be_texts), More = 1 when some are left for the
  next call }
function MnDraw(Viewer, Tick, Budget: LongInt; X, Y: Single; out More: LongInt): LongInt;
function MnHide(Viewer, Budget: LongInt): LongInt;
procedure MnForget(Viewer: LongInt);
{ the game was paused Delta ticks: every tick kept moves on by them (no mine arms or expires during a pause) }
procedure MnShift(Delta: LongInt);
{ changes with every planted, gone, armed or found mine (the script draws again then) }
function MnVersion: LongInt;
function MnInfo: AnsiString;

var
  { a point of a soldier's body (be_sprite's SpritePoint; a test sets its own and MnBridge False - the
    eyes then are the neck) }
  MnPoint: function(ID, K: LongInt; out X, Y: Single): Boolean = nil;
  MnBridge: Boolean = True;

implementation

uses
  SysUtils, Math, be_map, be_sprite, be_texts, be_font, be_ballistic;

const
  MAX_ID = 32;
  MAX_MINES = 64;
  QUEUE = 256;
  EVENTS = 128;
  MAX_POOL = 48;
  MAX_PREV = 32;
  { a soldier whose neck is less than this over his lower foot crouches (8 px) or lies (4 px); standing it
    is 16, running 13-16 (measured on the server) }
  LOW_NECK = 12.5;
  { how far a soldier's points lie from his upper body (the quick look first) }
  BODY_REACH = 40;
  { the realistic mode's sight (the game's) }
  SIGHT_RANGE = 1001;
  { what a viewer is sent: this far around him }
  VIEW_X = 1100;
  VIEW_Y = 800;
  { the points of a soldier low enough to step on a landmine or to lie on it }
  LOWPTS: array[0..8] of LongInt = (1, 2, 17, 18, 3, 4, 5, 6, 7);
  { the points of a dead soldier's body that press a landmine lying on it }
  CORPSEPTS: array[0..11] of LongInt = (1, 2, 17, 18, 3, 4, 5, 6, 7, 8, 9, 12);
  { the parts of the legs (and a lying body) that can cross a tripwire }
  LEG_A: array[0..7] of LongInt = (5, 4, 6, 3, 1, 2, 7, 7);
  LEG_B: array[0..7] of LongInt = (4, 1, 3, 2, 17, 18, 5, 6);
  { the points that touch a claymore or stand in its cone }
  BODY: array[0..7] of LongInt = (1, 2, 3, 4, 5, 6, 7, 12);

type
  TMine = record
    Live, Armed, Going: Boolean;
    Kind, Owner, Team, Uid: LongInt;
    X, Y, FX, FY: Single;
    { the tripwire from WX0 to WX1 at height WY (WX0 = WX1: none) }
    WX0, WX1, WY: Single;
    { how far under it bullets meet the ground (-1 = not near) }
    BGround: Single;
    PlantTick, ArmTick, EndTick, ChainAt: LongInt;
    { a bullet will reach it at ShotAt (fired by ShotBy): 0 = none }
    ShotAt, ShotBy: LongInt;
    { the enemies who found it (bit ID - 1) and their teams (bit team) }
    SeenBy: LongWord;
    SeenTeams: LongInt;
    { who takes it apart (or picks it up), since when, how long it takes }
    Worker, WorkStart, WorkNeed: LongInt;
    { the bodies on it in the last tick (bit ID - 1) }
    BodyIn: LongWord;
  end;

  TEvent = record
    Kind, Id, P, Q: LongInt;
  end;

  TShotCopy = record
    Owner, Tick, Style: LongInt;
    X, Y, VX, VY: Single;
  end;

  TView = record
    Sent: TTextSet;
    { layer k of the pool shows mine LMine (its uid LUid), part LPart: 0 the mark, 1 the wire }
    LMine, LUid, LPart: array[0..MAX_POOL - 1] of LongInt;
  end;

var
  MnOn: Boolean = False;
  ArmTicks: LongInt = 120;
  LifeTicks: LongInt = 0;
  TrigR: Single = 16;
  TrigH: Single = 8;
  Fuse: LongInt = FUSE_WIRE;
  WireLen: Single = 160;
  WireH: Single = 5;
  WireTol: Single = 4;
  ConeCos: Single = 0.866;
  ConeRange: Single = 180;
  TouchR: Single = 14;
  SpotR: Single = 70;
  SpotShare: Boolean = True;
  DefR: Single = 40;
  DefTicks: LongInt = 180;
  PickTicks: LongInt = 90;
  ShootLand: Boolean = False;
  ShootClay: Boolean = True;
  HitR: Single = 7;
  SeenLand: LongInt = 1;
  SeenClay: LongInt = 2;
  RealSight: Boolean = False;
  SpecSee: Boolean = True;
  Corpses: LongInt = CORPSE_OFF;
  MarkScale: Single = 0.06;
  WireScale: Single = 0.05;
  Layer0: LongInt = 133;
  Layers: LongInt = 16;
  PrevTicks: LongInt = 150;
  PrevRange: Single = 200;
  { the preview's dots: PrevEdge on each edge of the cone, PrevArc on its far arc, on the layers from
    PrevLayer0 }
  PrevLayer0: LongInt = 185;
  PrevEdge: LongInt = 6;
  PrevArc: LongInt = 3;
  PrevScale: Single = 0.07;
  SightRule: LongInt = SIGHT_EYES;
  Spread: Single = 0.349;
  MaxTilt: Single = 0.524;
  Refresh: LongInt = 120;
  ColOwn: LongInt = $FFFF60;
  ColTeam: LongInt = $60FF60;
  ColEnemy: LongInt = $FF4040;
  ColArming: LongInt = $A0A0A0;
  ColWire: LongInt = $70FF3030;
  ColPrev: LongInt = $FFFF60;
  TxMine: AnsiString = 'o';
  TxClayR: AnsiString = '|)';
  TxClayL: AnsiString = '(|';
  TxWire: AnsiString = '-';
  TxPrev: AnsiString = '.';
  Mines: array[1..MAX_MINES] of TMine;
  Live: LongInt = 0;
  NextUid: LongInt = 1;
  Ver: LongInt = 1;
  PTeam: array[1..MAX_ID] of LongInt;
  PAlive, PHuman: array[1..MAX_ID] of Boolean;
  { his body lies on the map (from his death until the next life) }
  PBody: array[1..MAX_ID] of Boolean;
  FallX, FallY: array[1..MAX_ID] of Single;
  FallLow: array[1..MAX_ID] of Boolean;
  { his crouch or prone key as the script read it, for which tick (Gen counts the ticks); the soldiers near
    a mine }
  LowKey: array[1..MAX_ID] of Boolean;
  LowGen: array[1..MAX_ID] of LongInt;
  Gen: LongInt = 0;
  NearMask: LongWord = 0;
  FallTick: array[1..MAX_ID] of LongInt;
  { this tick: where each soldier's upper body is (the quick look), whether it is known }
  BX, BY: array[1..MAX_ID] of Single;
  BOk: array[1..MAX_ID] of Boolean;
  Working: array[1..MAX_ID] of LongInt;
  Wanted: LongWord = 0;
  CurTick: LongInt = 0;
  Q: array[0..QUEUE - 1] of TShotCopy;
  QHead: LongInt = 0;
  QTail: LongInt = 0;
  Ev: array[0..EVENTS - 1] of TEvent;
  EvHead: LongInt = 0;
  EvTail: LongInt = 0;
  Views: array[1..MAX_ID] of TView;
  OwnBig, OwnWorld: TOwnMask;
  CntPlanted: LongInt = 0;
  CntTrig: LongInt = 0;
  CntShot: LongInt = 0;
  CntSpot: LongInt = 0;
  CntDefused: LongInt = 0;
  CntPicked: LongInt = 0;
  CntExpired: LongInt = 0;
  CntFed: LongInt = 0;
  CntDropped: LongInt = 0;
  CntBody: LongInt = 0;

function Valid(ID: LongInt): Boolean;
begin
  Result := (ID >= 1) and (ID <= MAX_ID);
end;

function IdOk(Id: LongInt): Boolean;
begin
  Result := (Id >= 1) and (Id <= MAX_MINES);
  if Result then
    Result := Mines[Id].Live;
end;

function Bit(ID: LongInt): LongWord;
begin
  Result := LongWord(1) shl (ID - 1);
end;

function FMin(A, B: Single): Single;
begin
  if A < B then
    Result := A
  else
    Result := B;
end;

function FMax(A, B: Single): Single;
begin
  if A > B then
    Result := A
  else
    Result := B;
end;

{ the preview's dots (both edges and the arc), at most MAX_PREV and within the 256 layers }
function PreviewCount: LongInt;
begin
  Result := 2 * PrevEdge + PrevArc;
  if Result > MAX_PREV then
    Result := MAX_PREV;
  if PrevLayer0 + Result > 256 then
    Result := 256 - PrevLayer0;
  if Result < 0 then
    Result := 0;
end;

procedure SetPool;
var
  i: LongInt;
begin
  for i := 0 to 255 do
  begin
    OwnBig[i] := False;
    OwnWorld[i] := ((i >= Layer0) and (i < Layer0 + Layers)) or
      ((i >= PrevLayer0) and (i < PrevLayer0 + PreviewCount));
  end;
end;

procedure MnSet(Key: LongInt; Value: Single);
begin
  case Key of
    MNC_ON: MnOn := Value <> 0;
    MNC_ARM: if Value >= 0 then ArmTicks := Round(Value);
    MNC_LIFE: if Value >= 0 then LifeTicks := Round(Value);
    MNC_TRIG_R: if Value > 0 then TrigR := Value;
    MNC_TRIG_H: if Value > 0 then TrigH := Value;
    MNC_FUSE: if (Value = FUSE_WIRE) or (Value = FUSE_CONE) then Fuse := Round(Value);
    MNC_WIRE_LEN: if Value >= 0 then WireLen := Value;
    MNC_WIRE_H: if Value >= 0 then WireH := Value;
    MNC_CONE_ANGLE: if (Value > 0) and (Value < 90) then ConeCos := Cos(Value * Pi / 180);
    MNC_CONE_RANGE: if Value > 0 then ConeRange := Value;
    MNC_TOUCH: if Value >= 0 then TouchR := Value;
    MNC_SPOT: if Value >= 0 then SpotR := Value;
    MNC_SPOT_SHARE: SpotShare := Value <> 0;
    MNC_DEFUSE_R: if Value > 0 then DefR := Value;
    MNC_DEFUSE_T: if Value >= 0 then DefTicks := Round(Value);
    MNC_PICK_T: if Value >= 0 then PickTicks := Round(Value);
    MNC_SHOOT_LAND: ShootLand := Value <> 0;
    MNC_SHOOT_CLAY: ShootClay := Value <> 0;
    MNC_HIT_R: if Value > 0 then HitR := Value;
    MNC_SEEN_LAND: if (Value >= 0) and (Value <= 2) then SeenLand := Round(Value);
    MNC_SEEN_CLAY: if (Value >= 0) and (Value <= 2) then SeenClay := Round(Value);
    MNC_REAL: RealSight := Value <> 0;
    MNC_MARK_SCALE: if Value > 0 then MarkScale := QScale(Value);
    MNC_WIRE_SCALE: if Value > 0 then WireScale := QScale(Value);
    MNC_LAYER:
      if (Value >= 0) and (Value <= 255) then
      begin
        Layer0 := Round(Value);
        if Layer0 + Layers > 256 then
          Layers := 256 - Layer0;
        SetPool;
      end;
    MNC_LAYERS:
      if (Value >= 1) and (Value <= MAX_POOL) then
      begin
        Layers := Round(Value);
        if Layer0 + Layers > 256 then
          Layers := 256 - Layer0;
        SetPool;
      end;
    MNC_PREVIEW: if Value >= 0 then PrevTicks := Round(Value);
    MNC_PREVIEW_RANGE: if Value > 0 then PrevRange := Value;
    MNC_SPREAD: if (Value >= 0) and (Value <= 90) then Spread := Value * Pi / 180;
    MNC_MAX_TILT: if (Value >= 0) and (Value <= 90) then MaxTilt := Value * Pi / 180;
    MNC_REFRESH: if Value >= 10 then Refresh := Round(Value);
    MNC_SPECTATORS: SpecSee := Value <> 0;
    MNC_SIGHT: if (Value >= SIGHT_ALWAYS) and (Value <= SIGHT_EYES) then SightRule := Round(Value);
    MNC_PREV_LAYER:
      if (Value >= 0) and (Value <= 255) then
      begin
        PrevLayer0 := Round(Value);
        SetPool;
      end;
    MNC_PREV_EDGE:
      if (Value >= 0) and (Value <= MAX_PREV div 2) then
      begin
        PrevEdge := Round(Value);
        SetPool;
      end;
    MNC_PREV_ARC:
      if (Value >= 0) and (Value <= MAX_PREV) then
      begin
        PrevArc := Round(Value);
        SetPool;
      end;
    MNC_PREV_SCALE: if Value > 0 then PrevScale := QScale(Value);
    MNC_CORPSES: if (Value >= CORPSE_OFF) and (Value <= CORPSE_ALL) then Corpses := Round(Value);
  end;
end;

procedure MnSetInt(Key, Value: LongInt);
begin
  case Key of
    MNI_OWN: ColOwn := Value;
    MNI_TEAM: ColTeam := Value;
    MNI_ENEMY: ColEnemy := Value;
    MNI_ARMING: ColArming := Value;
    MNI_WIRE: ColWire := Value;
    MNI_PREVIEW: ColPrev := Value;
  end;
end;

procedure MnText(Key: LongInt; const S: AnsiString);
begin
  case Key of
    MNT_MINE: TxMine := S;
    MNT_CLAY_R: TxClayR := S;
    MNT_CLAY_L: TxClayL := S;
    MNT_WIRE: TxWire := S;
    MNT_PREVIEW: TxPrev := S;
  end;
end;

procedure MnPlayer(ID, NewTeam, IsAlive: LongInt);
begin
  if not Valid(ID) then
    Exit;
  if IsAlive <> 0 then
    PBody[ID] := False
  else if PAlive[ID] then
    PBody[ID] := True;
  if (NewTeam < 0) or (NewTeam > 4) then
    PBody[ID] := False;
  PTeam[ID] := NewTeam;
  PAlive[ID] := IsAlive <> 0;
  if not PAlive[ID] then
    FallTick[ID] := 0;
end;

procedure MnHuman(ID, Human: LongInt);
begin
  if Valid(ID) then
    PHuman[ID] := Human <> 0;
end;

procedure MnPos(ID: LongInt; X, Y: Single; Low: LongInt);
begin
  if not Valid(ID) then
    Exit;
  FallX[ID] := X;
  FallY[ID] := Y;
  FallLow[ID] := Low <> 0;
  LowKey[ID] := Low <> 0;
  LowGen[ID] := Gen + 1;
  FallTick[ID] := CurTick;
  if FallTick[ID] = 0 then
    FallTick[ID] := 1;
  Inc(CntFed);
end;

function MnWants: LongWord;
begin
  Result := Wanted;
end;

procedure MnLow(ID, Low: LongInt);
begin
  if not Valid(ID) then
    Exit;
  LowKey[ID] := Low <> 0;
  LowGen[ID] := Gen + 1;
end;

function MnNear: LongWord;
begin
  Result := NearMask;
end;

function MnVersion: LongInt;
begin
  Result := Ver;
end;

{ how high over his feet a point of a soldier the script told about is (standing / low) }
function FallUp(K: LongInt; Low: Boolean): Single;
begin
  case K of
    1, 2, 17, 18: Result := 0;
    3, 4: if Low then Result := 3 else Result := 6;
    5, 6: if Low then Result := 4 else Result := 11;
    7: if Low then Result := 4 else Result := 12;
    9, 12: if Low then Result := 7 else Result := 17;
  else
    if Low then
      Result := 4
    else
      Result := 9;
  end;
end;

function Pt(ID, K: LongInt; out X, Y: Single): Boolean;
begin
  Result := False;
  X := 0;
  Y := 0;
  if Assigned(MnPoint) then
    Result := MnPoint(ID, K, X, Y);
  if Result then
    Exit;
  if FallTick[ID] = 0 then
    Exit;
  if CurTick - FallTick[ID] > 3 then
    Exit;
  X := FallX[ID];
  Y := FallY[ID] - FallUp(K, FallLow[ID]);
  Result := True;
end;

{ crouching or lying: he holds crouch or lies (the keys the script read for this tick or the last) and,
  when his skeleton is known, his neck is low over his feet (the crouch key held in a jump is not it) }
function IsLow(ID: LongInt): Boolean;
var
  NX, NY, AX, AY, CX, CY: Single;
begin
  Result := False;
  if (LowGen[ID] <> Gen) and (LowGen[ID] <> Gen - 1) then
    Exit;
  if not LowKey[ID] then
    Exit;
  Result := True;
  if Assigned(MnPoint) then
    if MnPoint(ID, 9, NX, NY) then
      if MnPoint(ID, 1, AX, AY) then
        if MnPoint(ID, 2, CX, CY) then
          Result := FMax(AY, CY) - NY < LOW_NECK;
end;

function Eyes(ID: LongInt; out X, Y: Single): Boolean;
begin
  Result := False;
  if MnBridge then
    Result := SpriteEyes(ID, X, Y);
  if not Result then
    Result := Pt(ID, 9, X, Y);
end;

{ may ID set off, find, take apart or shoot mine M: somebody of another team (in the modes without teams
  everybody but the owner) }
function Hostile(const M: TMine; ID: LongInt): Boolean;
begin
  Result := False;
  if not Valid(ID) then
    Exit;
  if ID = M.Owner then
    Exit;
  if (PTeam[ID] < 0) or (PTeam[ID] > 4) then
    Exit;
  if M.Team = 0 then
    Result := True
  else
    Result := PTeam[ID] <> M.Team;
end;

function SeenLevel(const M: TMine): LongInt;
begin
  if M.Kind = MN_CLAY then
    Result := SeenClay
  else
    Result := SeenLand;
end;

{ has V found it (or his team) }
function Found(const M: TMine; V: LongInt): Boolean;
begin
  Result := (M.SeenBy and Bit(V)) <> 0;
  if not Result then
    if (PTeam[V] >= 0) and (PTeam[V] <= 4) then
      Result := (M.SeenTeams and (1 shl PTeam[V])) <> 0;
end;

{ nothing between V's eyes and the mine (the game's rule for grenades in realistic mode) }
function EyesReach(const M: TMine; V: LongInt): Boolean;
var
  EX, EY: Single;
begin
  Result := True;
  if not PAlive[V] then
    Exit;
  if not Eyes(V, EX, EY) then
    Exit;
  if (Abs(EX - M.X) > SIGHT_RANGE) or (Abs(EY - M.Y) > SIGHT_RANGE) then
  begin
    Result := False;
    Exit;
  end;
  if MapReady then
    Result := not MapRay(EX, EY, M.X, M.Y - 4, 0, 0);
end;

{ may V see mine M now: its owner, his team (unless only the owner sees it), an enemy who found it or
  every enemy (by SightRule: with his eyes on it - not through walls - in every mode or only in realistic
  mode, or always), the spectators }
function Sees(const M: TMine; V: LongInt): Boolean;
var
  L: LongInt;
begin
  Result := False;
  if not Valid(V) then
    Exit;
  if V = M.Owner then
  begin
    Result := True;
    Exit;
  end;
  L := SeenLevel(M);
  if PTeam[V] = 5 then
  begin
    Result := SpecSee;
    Exit;
  end;
  if (M.Team <> 0) and (PTeam[V] = M.Team) then
  begin
    Result := L >= 1;
    Exit;
  end;
  if Found(M, V) then
  begin
    Result := True;
    Exit;
  end;
  if L >= 2 then
  begin
    Result := True;
    if (SightRule = SIGHT_EYES) or ((SightRule = SIGHT_REALISTIC) and RealSight) then
      Result := EyesReach(M, V);
  end;
end;

{ how far from A along the unit vector D (at most Len) the way is free of walls (Flags of MapRay) }
function FreeLen(AX, AY, DX, DY, Len: Single; Flags: LongInt): Single;
var
  Lo, Hi, Mid: Single;
  k: LongInt;
begin
  Result := Len;
  if not MapReady then
    Exit;
  if not MapRay(AX, AY, AX + DX * Len, AY + DY * Len, Flags, 0) then
    Exit;
  Lo := 0;
  Hi := Len;
  for k := 1 to 10 do
  begin
    Mid := (Lo + Hi) / 2;
    if MapRay(AX, AY, AX + DX * Mid, AY + DY * Mid, Flags, 0) then
      Hi := Mid
    else
      Lo := Mid;
  end;
  Result := Lo;
end;

procedure Push(Kind, Id, P, Q: LongInt);
var
  k: LongInt;
begin
  Ev[EvHead].Kind := Kind;
  Ev[EvHead].Id := Id;
  Ev[EvHead].P := P;
  Ev[EvHead].Q := Q;
  k := (EvHead + 1) mod EVENTS;
  if k = EvTail then
    EvTail := (EvTail + 1) mod EVENTS;
  EvHead := k;
end;

function MnPlant(Kind, Owner, Team: LongInt; X, Y, AimX, AimY: Single; Tick: LongInt): LongInt;
var
  i, Slot: LongInt;
  D, AX, AY, S, T, L: Single;
begin
  Result := 0;
  if (Kind <> MN_LAND) and (Kind <> MN_CLAY) then
    Exit;
  if not Valid(Owner) then
    Exit;
  Slot := 0;
  for i := 1 to MAX_MINES do
    if not Mines[i].Live then
    begin
      Slot := i;
      Break;
    end;
  if Slot = 0 then
    Exit;
  { the ground under his feet }
  D := FreeLen(X, Y - 6, 0, 1, 26, MR_PLAYER);
  if D < 26 then
    Y := Y - 6 + D;
  Mines[Slot].Live := True;
  Mines[Slot].Armed := False;
  Mines[Slot].Going := False;
  Mines[Slot].Kind := Kind;
  Mines[Slot].Owner := Owner;
  Mines[Slot].Team := Team;
  Mines[Slot].Uid := NextUid;
  Inc(NextUid);
  Mines[Slot].X := X;
  Mines[Slot].Y := Y;
  Mines[Slot].BGround := -1;
  if MapReady then
  begin
    D := FreeLen(X, Y - 4, 0, 1, 16, MR_BULLET);
    if D < 16 then
    begin
      Mines[Slot].BGround := D - 4;
      if Mines[Slot].BGround < 0 then
        Mines[Slot].BGround := 0;
    end;
  end;
  Mines[Slot].FX := 1;
  Mines[Slot].FY := 0;
  Mines[Slot].WX0 := X;
  Mines[Slot].WX1 := X;
  Mines[Slot].WY := Y - WireH;
  Mines[Slot].PlantTick := Tick;
  Mines[Slot].ArmTick := Tick + ArmTicks;
  if LifeTicks > 0 then
    Mines[Slot].EndTick := Tick + LifeTicks
  else
    Mines[Slot].EndTick := 0;
  Mines[Slot].ChainAt := 0;
  Mines[Slot].ShotAt := 0;
  Mines[Slot].ShotBy := 0;
  Mines[Slot].SeenBy := 0;
  Mines[Slot].SeenTeams := 0;
  Mines[Slot].Worker := 0;
  Mines[Slot].WorkStart := 0;
  Mines[Slot].WorkNeed := 0;
  Mines[Slot].BodyIn := 0;
  if Kind = MN_CLAY then
  begin
    { it looks where he looked, level or tilted up to MaxTilt }
    AX := AimX - X;
    AY := AimY - (Y - 12);
    S := 1;
    if AX < 0 then
      S := -1;
    if Abs(AX) < 1 then
      AX := S;
    T := ArcTan(AY / Abs(AX));
    if T > MaxTilt then
      T := MaxTilt;
    if T < -MaxTilt then
      T := -MaxTilt;
    Mines[Slot].FX := S * Cos(T);
    Mines[Slot].FY := Sin(T);
    { the tripwire runs along the ground ahead of it, knee high, to the first wall }
    L := 0;
    if Fuse = FUSE_WIRE then
      L := FreeLen(X + S * 6, Y - WireH, S, 0, WireLen, MR_PLAYER);
    Mines[Slot].WX0 := X + S * 6;
    Mines[Slot].WX1 := X + S * (6 + L);
    if L < 4 then
      Mines[Slot].WX1 := Mines[Slot].WX0;
  end;
  Inc(Live);
  Inc(Ver);
  Inc(CntPlanted);
  Result := Slot;
end;

procedure MnRemove(Id: LongInt);
var
  w: LongInt;
begin
  if not IdOk(Id) then
    Exit;
  w := Mines[Id].Worker;
  if Valid(w) then
  begin
    if Working[w] = Id then
      Working[w] := 0;
    Push(MNE_WORK_STOP, Id, w, 0);
  end;
  Mines[Id].Live := False;
  Mines[Id].Going := False;
  Mines[Id].Worker := 0;
  Dec(Live);
  if Live < 0 then
    Live := 0;
  Inc(Ver);
end;

function MnRemoveOwner(Owner: LongInt): LongInt;
var
  i: LongInt;
begin
  Result := 0;
  for i := 1 to MAX_MINES do
    if Mines[i].Live then
      if Mines[i].Owner = Owner then
      begin
        MnRemove(i);
        Inc(Result);
      end;
end;

procedure MnClear;
var
  i: LongInt;
begin
  for i := 1 to MAX_MINES do
  begin
    Mines[i].Live := False;
    Mines[i].Going := False;
    Mines[i].Worker := 0;
  end;
  for i := 1 to MAX_ID do
    Working[i] := 0;
  Live := 0;
  QTail := QHead;
  EvTail := EvHead;
  Inc(Ver);
end;

function MnGet(Id: LongInt; out Kind, Owner, Team: LongInt; out X, Y, FX, FY: Single): Boolean;
begin
  Result := IdOk(Id);
  Kind := 0;
  Owner := 0;
  Team := 0;
  X := 0;
  Y := 0;
  FX := 1;
  FY := 0;
  if not Result then
    Exit;
  Kind := Mines[Id].Kind;
  Owner := Mines[Id].Owner;
  Team := Mines[Id].Team;
  X := Mines[Id].X;
  Y := Mines[Id].Y;
  FX := Mines[Id].FX;
  FY := Mines[Id].FY;
end;

function MnGround(Id: LongInt): Single;
begin
  Result := -1;
  if IdOk(Id) then
    Result := Mines[Id].BGround;
end;

function MnCount(Owner, Kind: LongInt): LongInt;
var
  i: LongInt;
begin
  Result := 0;
  for i := 1 to MAX_MINES do
    if Mines[i].Live then
      if (Owner = 0) or (Mines[i].Owner = Owner) then
        if (Kind = 0) or (Mines[i].Kind = Kind) then
          Inc(Result);
end;

function MnDetect(V: LongInt; X, Y, R: Single): LongInt;
var
  i: LongInt;
begin
  Result := 0;
  if not Valid(V) then
    Exit;
  if R <= 0 then
    Exit;
  for i := 1 to MAX_MINES do
    if Mines[i].Live then
      if Hostile(Mines[i], V) then
        if not Found(Mines[i], V) then
          if Sqr(Mines[i].X - X) + Sqr(Mines[i].Y - Y) <= Sqr(R) then
          begin
            Mines[i].SeenBy := Mines[i].SeenBy or Bit(V);
            if SpotShare then
              if (PTeam[V] >= 1) and (PTeam[V] <= 4) then
                Mines[i].SeenTeams := Mines[i].SeenTeams or (1 shl PTeam[V]);
            Inc(Ver);
            Inc(CntSpot);
            Push(MNE_SPOTTED, i, V, 1);
            Inc(Result);
          end;
end;

function MnNearest(X, Y: Single; out D: Single): LongInt;
var
  i: LongInt;
  E: Single;
begin
  Result := 0;
  D := 1E9;
  for i := 1 to MAX_MINES do
    if Mines[i].Live then
    begin
      E := Sqrt(Sqr(Mines[i].X - X) + Sqr(Mines[i].Y - Y));
      if E < D then
      begin
        D := E;
        Result := i;
      end;
    end;
end;

procedure MnChain(Id: LongInt; R: Single; AtTick: LongInt);
var
  i: LongInt;
  X, Y: Single;
begin
  if not IdOk(Id) then
    Exit;
  if R <= 0 then
    Exit;
  X := Mines[Id].X;
  Y := Mines[Id].Y;
  for i := 1 to MAX_MINES do
    if i <> Id then
      if Mines[i].Live then
        if not Mines[i].Going then
          if Sqr(Mines[i].X - X) + Sqr(Mines[i].Y - Y) <= Sqr(R) then
            if (Mines[i].ChainAt = 0) or (Mines[i].ChainAt > AtTick) then
              Mines[i].ChainAt := AtTick;
end;

procedure MnQueueShot(const E: TShotEvent);
var
  n: LongInt;
begin
  if not MnOn then
    Exit;
  if Live <= 0 then
    Exit;
  if not (ShootClay or ShootLand) then
    Exit;
  if not Valid(E.Owner) then
    Exit;
  { the bullets that fly straight enough for a line (plain, shotgun, flame, arrows, a thrown knife, the
    stationary gun) }
  if not ((E.Style = 1) or (E.Style = 3) or (E.Style = 5) or (E.Style = 7) or (E.Style = 8) or (E.Style = 13) or
    (E.Style = 14)) then
    Exit;
  Q[QHead].Owner := E.Owner;
  Q[QHead].Tick := E.Tick;
  Q[QHead].Style := E.Style;
  Q[QHead].X := E.X;
  Q[QHead].Y := E.Y;
  Q[QHead].VX := E.VX;
  Q[QHead].VY := E.VY;
  n := (QHead + 1) mod QUEUE;
  if n = QTail then
  begin
    QTail := (QTail + 1) mod QUEUE;
    Inc(CntDropped);
  end;
  QHead := n;
end;

function FiniteS(V: Single): Boolean;
begin
  Result := (PLongWord(@V)^ and $7F800000) <> $7F800000;
end;

{ where a mine is hit by bullets: its middle }
procedure Middle(const M: TMine; out X, Y: Single);
begin
  X := M.X;
  if M.Kind = MN_CLAY then
    Y := M.Y - 5
  else
    Y := M.Y - 2;
end;

{ a mine a bullet reaches goes off: the bullet is followed tick by tick as the game flies it (it falls and slows
  down), and the mine goes off when the bullet gets there - not at the shot (an enemy's bullet, before a wall) }
procedure LookShot(const C: TShotCopy);
var
  i, Best, Stp, BestAt, Cands: LongInt;
  L, DX, DY, WX, WY, T, CX, CY, G, PX, PY, BVX, BVY, NX, NY, SX, SY, SL, U, BestU, Drop, Sp: Single;
  Cand: array[1..MAX_MINES] of Boolean;
  MX, MY: array[1..MAX_MINES] of Single;
begin
  if not (FiniteS(C.X) and FiniteS(C.Y) and FiniteS(C.VX) and FiniteS(C.VY)) then
    Exit;
  L := Sqrt(C.VX * C.VX + C.VY * C.VY);
  if L < 0.01 then
    Exit;
  DX := C.VX / L;
  DY := C.VY / L;
  { the mines near the bullet's way (under its first line by as much as it can fall): only for them is the
    flight followed }
  Cands := 0;
  for i := 1 to MAX_MINES do
  begin
    Cand[i] := False;
    if Mines[i].Live then
      if not Mines[i].Going then
        if Mines[i].ShotAt = 0 then
        begin
          if Mines[i].Kind = MN_CLAY then
          begin
            if not ShootClay then
              Continue;
          end
          else if not ShootLand then
            Continue;
          if not Hostile(Mines[i], C.Owner) then
            Continue;
          Middle(Mines[i], CX, CY);
          WX := CX - C.X;
          WY := CY - C.Y;
          T := WX * DX + WY * DY;
          if (T < 0) or (T > 1250) then
            Continue;
          Sp := T / L * 1.4;
          Drop := 0.5 * BulletGravity * Sp * Sp + HitR;
          if Abs(WX * DY - WY * DX) > Drop then
            Continue;
          Cand[i] := True;
          MX[i] := CX;
          MY[i] := CY;
          Inc(Cands);
        end;
  end;
  if Cands = 0 then
    Exit;
  G := BulletGravity;
  if C.Style = STYLE_FLAME then
    G := G - 0.15;
  PX := C.X;
  PY := C.Y;
  BVX := C.VX;
  BVY := C.VY;
  Best := 0;
  BestAt := 0;
  for Stp := 1 to 70 do
  begin
    BVY := BVY + G;
    NX := PX + BVX;
    NY := PY + BVY;
    SX := NX - PX;
    SY := NY - PY;
    SL := SX * SX + SY * SY;
    BestU := 2;
    for i := 1 to MAX_MINES do
      if Cand[i] then
      begin
        WX := MX[i] - PX;
        WY := MY[i] - PY;
        if SL < 0.0001 then
          U := 0
        else
          U := (WX * SX + WY * SY) / SL;
        if U < 0 then
          U := 0;
        if U > 1 then
          U := 1;
        CX := PX + U * SX - MX[i];
        CY := PY + U * SY - MY[i];
        if CX * CX + CY * CY <= HitR * HitR then
          if U < BestU then
          begin
            { a wall on the way to the point of the closest pass stops the bullet first }
            if MapReady then
              if MapRay(PX, PY, PX + U * SX, PY + U * SY, MR_BULLET, 0) then
                Continue;
            BestU := U;
            Best := i;
          end;
      end;
    if Best <> 0 then
    begin
      BestAt := Stp;
      Break;
    end;
    if MapReady then
      if MapRay(PX, PY, NX, NY, MR_BULLET, 0) then
        Exit;
    PX := NX;
    PY := NY;
    BVX := BVX * 0.99;
    BVY := BVY * 0.99;
  end;
  if Best = 0 then
    Exit;
  Mines[Best].ShotBy := C.Owner;
  Mines[Best].ShotAt := C.Tick + BestAt - 1;
  if Mines[Best].ShotAt < 1 then
    Mines[Best].ShotAt := 1;
  if Mines[Best].ShotAt <= CurTick then
  begin
    Mines[Best].Going := True;
    Inc(CntShot);
    Push(MNE_SHOT, Best, C.Owner, 0);
  end;
end;

{ a landmine: a point of his legs or body within TrigR sideways and at most TrigH over it }
function LandHit(const M: TMine; ID: LongInt): Boolean;
var
  k: LongInt;
  X, Y: Single;
begin
  Result := False;
  for k := 0 to High(LOWPTS) do
    if Pt(ID, LOWPTS[k], X, Y) then
      if Abs(X - M.X) <= TrigR then
        if (Y >= M.Y - TrigH) and (Y <= M.Y + 4) then
        begin
          Result := True;
          Exit;
        end;
end;

{ a claymore: a point of him within TouchR of it }
function TouchHit(const M: TMine; ID: LongInt): Boolean;
var
  k: LongInt;
  X, Y, CX, CY: Single;
begin
  Result := False;
  if TouchR <= 0 then
    Exit;
  CX := M.X;
  CY := M.Y - 5;
  for k := 0 to High(BODY) do
    if Pt(ID, BODY[k], X, Y) then
      if Sqr(X - CX) + Sqr(Y - CY) <= Sqr(TouchR) then
      begin
        Result := True;
        Exit;
      end;
end;

{ a claymore's tripwire: a part of his legs (or of his lying body) crosses its height over it }
function WireHit(const M: TMine; ID: LongInt): Boolean;
var
  k: LongInt;
  AX, AY, CX, CY, T, XL, XR, WL, WR: Single;
begin
  Result := False;
  if Abs(M.WX1 - M.WX0) < 1 then
    Exit;
  WL := FMin(M.WX0, M.WX1);
  WR := FMax(M.WX0, M.WX1);
  for k := 0 to High(LEG_A) do
    if Pt(ID, LEG_A[k], AX, AY) then
      if Pt(ID, LEG_B[k], CX, CY) then
      begin
        if M.WY < FMin(AY, CY) - WireTol then
          Continue;
        if M.WY > FMax(AY, CY) + WireTol then
          Continue;
        if Abs(CY - AY) < 1 then
        begin
          XL := FMin(AX, CX);
          XR := FMax(AX, CX);
        end
        else
        begin
          T := (M.WY - AY) / (CY - AY);
          if T < 0 then
            T := 0;
          if T > 1 then
            T := 1;
          XL := AX + (CX - AX) * T;
          XR := XL;
        end;
        if (XR >= WL) and (XL <= WR) then
        begin
          Result := True;
          Exit;
        end;
      end;
end;

{ a claymore with Fuse = cone: a point of him in its front cone with nothing between }
function ConeHit(const M: TMine; ID: LongInt): Boolean;
var
  k: LongInt;
  X, Y, CX, CY, DX, DY, D: Single;
begin
  Result := False;
  CX := M.X;
  CY := M.Y - 6;
  for k := 0 to High(BODY) do
    if Pt(ID, BODY[k], X, Y) then
    begin
      DX := X - CX;
      DY := Y - CY;
      D := Sqrt(DX * DX + DY * DY);
      if (D < 1) or (D > ConeRange) then
        Continue;
      if (DX * M.FX + DY * M.FY) / D < ConeCos then
        Continue;
      if MapReady then
        if MapRay(CX, CY, X, Y, 0, 0) then
          Continue;
      Result := True;
      Exit;
    end;
end;

{ a dead soldier's body on a landmine: a point of it within TrigR px of it sideways and at most TrigH
  px above it }
function BodyLandHit(const M: TMine; ID: LongInt): Boolean;
var
  k: LongInt;
  X, Y: Single;
begin
  Result := False;
  for k := 0 to High(CORPSEPTS) do
    if MnPoint(ID, CORPSEPTS[k], X, Y) then
      if Abs(X - M.X) <= TrigR then
        if (Y >= M.Y - TrigH) and (Y <= M.Y + 4) then
        begin
          Result := True;
          Exit;
        end;
end;

{ the bodies (bit ID - 1) on mine i now (Corpses: the enemies' or everybody's): on a landmine, on a
  claymore or across its tripwire (a claymore's cone looks for the living only); their skeletons need
  the memory bridge }
function BodiesOn(i: LongInt): LongWord;
var
  v: LongInt;
  X, Y, Reach: Single;
begin
  Result := 0;
  if not Assigned(MnPoint) then
    Exit;
  if Mines[i].Kind = MN_LAND then
    Reach := TrigR + BODY_REACH
  else
    Reach := FMax(TouchR, Abs(Mines[i].WX1 - Mines[i].X)) + BODY_REACH;
  for v := 1 to MAX_ID do
    if PBody[v] then
      if (Corpses = CORPSE_ALL) or Hostile(Mines[i], v) then
        if MnPoint(v, 7, X, Y) then
          if (Abs(X - Mines[i].X) <= Reach) and (Abs(Y - Mines[i].Y) <= Reach) then
          begin
            if Mines[i].Kind = MN_LAND then
            begin
              if BodyLandHit(Mines[i], v) then
                Result := Result or Bit(v);
            end
            else if TouchHit(Mines[i], v) then
              Result := Result or Bit(v)
            else if Fuse = FUSE_WIRE then
              if WireHit(Mines[i], v) then
                Result := Result or Bit(v);
          end;
end;

{ an enemy low near a landmine he does not know yet, with his eyes on it, finds it }
procedure LookSpot(i: LongInt);
var
  v: LongInt;
  X, Y, EX, EY: Single;
begin
  for v := 1 to MAX_ID do
    if PAlive[v] then
      if BOk[v] then
        if Hostile(Mines[i], v) then
          if not Found(Mines[i], v) then
            if Sqr(BX[v] - Mines[i].X) + Sqr(BY[v] - Mines[i].Y) <= Sqr(SpotR + 12) then
              if IsLow(v) then
                if Pt(v, 7, X, Y) then
                  if Sqr(X - Mines[i].X) + Sqr(Y - Mines[i].Y) <= Sqr(SpotR) then
                  begin
                    if MapReady then
                      if Eyes(v, EX, EY) then
                        if MapRay(EX, EY, Mines[i].X, Mines[i].Y - 3, 0, 0) then
                          Continue;
                    Mines[i].SeenBy := Mines[i].SeenBy or Bit(v);
                    if SpotShare then
                      if (PTeam[v] >= 1) and (PTeam[v] <= 4) then
                        Mines[i].SeenTeams := Mines[i].SeenTeams or (1 shl PTeam[v]);
                    Inc(Ver);
                    Inc(CntSpot);
                    Push(MNE_SPOTTED, i, v, 0);
                  end;
end;

{ may V work on mine i now: low, his upper body within DefR of it; the owner picks it up, an enemy who
  sees it takes it apart }
function CanWork(i, V: LongInt): Boolean;
var
  X, Y: Single;
begin
  Result := False;
  if not Valid(V) then
    Exit;
  if not PAlive[V] then
    Exit;
  if V = Mines[i].Owner then
  begin
    if PickTicks <= 0 then
      Exit;
    if not PHuman[V] then
      Exit;
    if not Mines[i].Armed then
      Exit;
  end
  else
  begin
    if DefTicks <= 0 then
      Exit;
    if not Hostile(Mines[i], V) then
      Exit;
    if not Sees(Mines[i], V) then
      Exit;
  end;
  if not Pt(V, 7, X, Y) then
    Exit;
  if Sqr(X - Mines[i].X) + Sqr(Y - (Mines[i].Y - 4)) > Sqr(DefR) then
    Exit;
  Result := IsLow(V);
end;

procedure LookWork(i, Tick: LongInt);
var
  v, w: LongInt;
begin
  w := Mines[i].Worker;
  if w <> 0 then
  begin
    if not CanWork(i, w) then
    begin
      Mines[i].Worker := 0;
      if Valid(w) then
        if Working[w] = i then
          Working[w] := 0;
      Push(MNE_WORK_STOP, i, w, 0);
      Exit;
    end;
    if Tick - Mines[i].WorkStart >= Mines[i].WorkNeed then
    begin
      Mines[i].Going := True;
      Mines[i].Worker := 0;
      if Working[w] = i then
        Working[w] := 0;
      if w = Mines[i].Owner then
      begin
        Inc(CntPicked);
        Push(MNE_PICKED, i, w, 0);
      end
      else
      begin
        Inc(CntDefused);
        Push(MNE_DEFUSED, i, w, 0);
      end;
    end;
    Exit;
  end;
  for v := 1 to MAX_ID do
    if PAlive[v] then
      if BOk[v] then
        if Working[v] = 0 then
          if Sqr(BX[v] - Mines[i].X) + Sqr(BY[v] - Mines[i].Y) <= Sqr(DefR + 12) then
            if CanWork(i, v) then
            begin
              Mines[i].Worker := v;
              Mines[i].WorkStart := Tick;
              if v = Mines[i].Owner then
                Mines[i].WorkNeed := PickTicks
              else
                Mines[i].WorkNeed := DefTicks;
              Working[v] := i;
              Push(MNE_WORK, i, v, Mines[i].WorkNeed);
              Exit;
            end;
end;

function MnTick(Tick: LongInt): LongInt;
var
  i, v, Bodies: LongInt;
  Hit, Known: Boolean;
  Reach, NearR: Single;
  NewIn, Fresh: LongWord;
begin
  Result := 0;
  CurTick := Tick;
  Inc(Gen);
  try
    { the bodies lying on the map (Corpses) }
    Bodies := 0;
    if Corpses <> CORPSE_OFF then
      if Live > 0 then
        for v := 1 to MAX_ID do
          if PBody[v] then
            Inc(Bodies);
    { every soldier's upper body once (the quick look); the ones the library does not know are asked for }
    Wanted := 0;
    for v := 1 to MAX_ID do
    begin
      BOk[v] := False;
      if PAlive[v] then
        if (PTeam[v] >= 0) and (PTeam[v] <= 4) then
        begin
          Known := False;
          if Assigned(MnPoint) then
            Known := MnPoint(v, 7, BX[v], BY[v]);
          if Known then
            BOk[v] := True
          else
          begin
            Wanted := Wanted or Bit(v);
            BOk[v] := Pt(v, 7, BX[v], BY[v]);
          end;
        end;
      if not PAlive[v] then
        Working[v] := 0;
    end;
    { the soldiers near a mine: the script reads their crouch and prone keys for the next tick }
    NearMask := 0;
    if Live > 0 then
    begin
      NearR := FMax(SpotR, DefR) + 30;
      for v := 1 to MAX_ID do
        if BOk[v] then
          for i := 1 to MAX_MINES do
            if Mines[i].Live then
              if (Abs(BX[v] - Mines[i].X) <= NearR) and (Abs(BY[v] - Mines[i].Y) <= NearR) then
              begin
                NearMask := NearMask or Bit(v);
                Break;
              end;
    end;
    while QTail <> QHead do
    begin
      if MnOn then
        if Live > 0 then
          LookShot(Q[QTail]);
      QTail := (QTail + 1) mod QUEUE;
    end;
    if MnOn then
      for i := 1 to MAX_MINES do
        if Mines[i].Live then
          if not Mines[i].Going then
          begin
            if not Mines[i].Armed then
              if Tick >= Mines[i].ArmTick then
              begin
                Mines[i].Armed := True;
                Inc(Ver);
                Push(MNE_ARMED, i, Mines[i].Owner, 0);
              end;
            if Mines[i].EndTick > 0 then
              if Tick >= Mines[i].EndTick then
              begin
                Mines[i].Going := True;
                Inc(CntExpired);
                Push(MNE_EXPIRE, i, Mines[i].Owner, 0);
                Continue;
              end;
            if Mines[i].ChainAt > 0 then
              if Tick >= Mines[i].ChainAt then
              begin
                Mines[i].Going := True;
                Push(MNE_TRIGGER, i, 0, 1);
                Continue;
              end;
            { the bullet that was followed has arrived }
            if Mines[i].ShotAt > 0 then
              if Tick >= Mines[i].ShotAt then
              begin
                Mines[i].Going := True;
                Inc(CntShot);
                Push(MNE_SHOT, i, Mines[i].ShotBy, 0);
                Continue;
              end;
            if Mines[i].Armed then
            begin
              { how far from it a soldier's upper body may be for him to set it off }
              if Mines[i].Kind = MN_LAND then
                Reach := TrigR + BODY_REACH
              else
              begin
                Reach := TouchR;
                if Fuse = FUSE_CONE then
                  Reach := FMax(Reach, ConeRange)
                else
                  Reach := FMax(Reach, Abs(Mines[i].WX1 - Mines[i].X));
                Reach := Reach + BODY_REACH;
              end;
              for v := 1 to MAX_ID do
                if BOk[v] then
                  if Abs(BX[v] - Mines[i].X) <= Reach then
                    if Abs(BY[v] - Mines[i].Y) <= Reach then
                      if Hostile(Mines[i], v) then
                      begin
                        if Mines[i].Kind = MN_LAND then
                          Hit := LandHit(Mines[i], v)
                        else
                        begin
                          Hit := TouchHit(Mines[i], v);
                          if not Hit then
                          begin
                            if Fuse = FUSE_CONE then
                              Hit := ConeHit(Mines[i], v)
                            else
                              Hit := WireHit(Mines[i], v);
                          end;
                        end;
                        if Hit then
                        begin
                          Mines[i].Going := True;
                          Inc(CntTrig);
                          Push(MNE_TRIGGER, i, v, 0);
                          Break;
                        end;
                      end;
            end;
            if Mines[i].Going then
              Continue;
            { a body that came onto it since the last tick sets it off (Q = 2); one lying there already
              when it was armed does not }
            if Bodies > 0 then
            begin
              NewIn := BodiesOn(i);
              Fresh := NewIn and not Mines[i].BodyIn;
              Mines[i].BodyIn := NewIn;
              if Mines[i].Armed then
                if Fresh <> 0 then
                begin
                  v := 1;
                  while (Fresh and Bit(v)) = 0 do
                    Inc(v);
                  Mines[i].Going := True;
                  Inc(CntBody);
                  Push(MNE_TRIGGER, i, v, 2);
                  Continue;
                end;
            end
            else
              Mines[i].BodyIn := 0;
            if SpotR > 0 then
              if (Mines[i].Kind = MN_LAND) or (SeenClay < 2) then
                LookSpot(i);
            LookWork(i, Tick);
          end;
  except
  end;
  Result := (EvHead - EvTail + EVENTS) mod EVENTS;
end;

function MnNext(out Kind, Id, P, Q: LongInt): Boolean;
begin
  Result := EvTail <> EvHead;
  Kind := 0;
  Id := 0;
  P := 0;
  Q := 0;
  if not Result then
    Exit;
  Kind := Ev[EvTail].Kind;
  Id := Ev[EvTail].Id;
  P := Ev[EvTail].P;
  Q := Ev[EvTail].Q;
  EvTail := (EvTail + 1) mod EVENTS;
end;

{ ---------------- the marks ---------------- }

{ a text placed so that its ink's middle lies on X, Y }
procedure InkAt(const T: AnsiString; Sc, X, Y: Single; out TX, TY: Single);
var
  CX, CY: Single;
begin
  InkCenter(T, CX, CY);
  TX := X - CX * Sc * WORLD_EM;
  TY := Y - CY * Sc * WORLD_EM;
end;

function MarkText(const M: TMine): AnsiString;
begin
  if M.Kind = MN_LAND then
    Result := TxMine
  else if M.FX >= 0 then
    Result := TxClayR
  else
    Result := TxClayL;
end;

function MarkColor(const M: TMine; V: LongInt): LongInt;
begin
  if (V = M.Owner) or ((M.Team <> 0) and (PTeam[V] = M.Team)) then
  begin
    if not M.Armed then
      Result := ColArming
    else if V = M.Owner then
      Result := ColOwn
    else
      Result := ColTeam;
  end
  else
    Result := ColEnemy;
end;

{ the mark of a mine: its ink standing on the ground at it }
procedure MarkPlace(const M: TMine; const T: AnsiString; out TX, TY: Single);
var
  L, Tp, R, B, Em: Single;
begin
  InkBox(T, L, Tp, R, B);
  Em := MarkScale * WORLD_EM;
  TX := M.X - (L + R) / 2 * Em;
  { the bottom of the ink 1 px over the ground }
  TY := M.Y - 1 - B * Em;
end;

{ the tripwire: dashes from its start to its end, their ink on its height }
function WireText(const M: TMine; out TX, TY: Single): AnsiString;
var
  Unit_, Len, L, Tp, R, B, Em: Single;
  n, k: LongInt;
begin
  Result := '';
  TX := 0;
  TY := 0;
  if TxWire = '' then
    Exit;
  Len := Abs(M.WX1 - M.WX0);
  if Len < 4 then
    Exit;
  Em := WireScale * WORLD_EM;
  Unit_ := TextAdvance(TxWire + ' ') * Em;
  if Unit_ < 1 then
    Exit;
  n := Trunc(Len / Unit_);
  if n < 1 then
    n := 1;
  if n > 80 then
    n := 80;
  for k := 1 to n do
  begin
    Result := Result + TxWire;
    if k < n then
      Result := Result + ' ';
  end;
  InkBox(Result, L, Tp, R, B);
  if M.WX1 >= M.WX0 then
    TX := M.WX0 - L * Em
  else
    TX := M.WX0 - R * Em;
  TY := M.WY - (Tp + B) / 2 * Em;
end;

{ dot j (0 .. PreviewCount - 1) of a new claymore's preview: PrevEdge along each edge of its cone, then
  PrevArc on the far arc between them; False when a wall stops the shells before it }
function PreviewDot(const M: TMine; j: LongInt; out TX, TY: Single): Boolean;
var
  A, A0, D, CX, CY, PX, PY: Single;
begin
  Result := False;
  TX := 0;
  TY := 0;
  if TxPrev = '' then
    Exit;
  A0 := ArcTan2(M.FY, M.FX);
  if j < PrevEdge then
  begin
    A := A0 - Spread;
    D := PrevRange * (j + 1) / PrevEdge;
  end
  else if j < 2 * PrevEdge then
  begin
    A := A0 + Spread;
    D := PrevRange * (j - PrevEdge + 1) / PrevEdge;
  end
  else
  begin
    A := A0 - Spread + 2 * Spread * (j - 2 * PrevEdge + 1) / (PrevArc + 1);
    D := PrevRange;
  end;
  CX := M.X + M.FX * 5;
  CY := M.Y - 6 + M.FY * 5;
  PX := CX + Cos(A) * D;
  PY := CY + Sin(A) * D;
  if MapReady then
    if MapRay(CX, CY, PX, PY, MR_BULLET, 0) then
      Exit;
  InkAt(TxPrev, PrevScale, PX, PY, TX, TY);
  Result := True;
end;

function MnDraw(Viewer, Tick, Budget: LongInt; X, Y: Single; out More: LongInt): LongInt;
var
  Cand: array[0..MAX_MINES - 1] of LongInt;
  Dist: array[0..MAX_MINES - 1] of Single;
  WMine, WUid, WPart: array[0..MAX_POOL - 1] of LongInt;
  WPlaced: array[0..MAX_POOL - 1] of Boolean;
  Keep: array[0..MAX_POOL - 1] of Boolean;
  n, i, j, k, c, Part, Nw, Prev, Pool: LongInt;
  d, TX, TY: Single;
  T: AnsiString;
  MoreB, Found_: Boolean;
begin
  Result := 0;
  More := 0;
  if not Valid(Viewer) then
    Exit;
  try
    WantClear;
    Pool := Layers;
    if Pool > MAX_POOL then
      Pool := MAX_POOL;
    Nw := 0;
    { the preview of his newest claymore (drawn after the marks) }
    Prev := 0;
    if PrevTicks > 0 then
      for i := 1 to MAX_MINES do
        if Mines[i].Live then
          if not Mines[i].Going then
            if Mines[i].Kind = MN_CLAY then
              if Mines[i].Owner = Viewer then
                if Tick - Mines[i].PlantTick < PrevTicks then
                  if (Prev = 0) or (Mines[i].PlantTick > Mines[Prev].PlantTick) then
                    Prev := i;
    { the mines he may see around him, the nearest first }
    n := 0;
    if MnOn then
      for i := 1 to MAX_MINES do
        if Mines[i].Live then
          if not Mines[i].Going then
            if (Abs(Mines[i].X - X) <= VIEW_X) and (Abs(Mines[i].Y - Y) <= VIEW_Y) then
              if Sees(Mines[i], Viewer) then
              begin
                Cand[n] := i;
                Dist[n] := Sqr(Mines[i].X - X) + Sqr(Mines[i].Y - Y);
                Inc(n);
              end;
    for i := 1 to n - 1 do
    begin
      c := Cand[i];
      d := Dist[i];
      j := i - 1;
      while (j >= 0) and (Dist[j] > d) do
      begin
        Cand[j + 1] := Cand[j];
        Dist[j + 1] := Dist[j];
        Dec(j);
      end;
      Cand[j + 1] := c;
      Dist[j + 1] := d;
    end;
    for k := 0 to n - 1 do
    begin
      i := Cand[k];
      if Nw >= Pool then
        Break;
      WMine[Nw] := i;
      WUid[Nw] := Mines[i].Uid;
      WPart[Nw] := 0;
      Inc(Nw);
      if Mines[i].Kind = MN_CLAY then
        if Fuse = FUSE_WIRE then
          if Abs(Mines[i].WX1 - Mines[i].WX0) >= 4 then
            if Nw < Pool then
            begin
              WMine[Nw] := i;
              WUid[Nw] := Mines[i].Uid;
              WPart[Nw] := 1;
              Inc(Nw);
            end;
    end;
    { a layer keeps what it shows while that is still wanted; the rest go to free layers }
    for j := 0 to Nw - 1 do
      WPlaced[j] := False;
    for k := 0 to Pool - 1 do
    begin
      Keep[k] := False;
      if Views[Viewer].LMine[k] <> 0 then
        for j := 0 to Nw - 1 do
          if not WPlaced[j] then
            if (WMine[j] = Views[Viewer].LMine[k]) and (WUid[j] = Views[Viewer].LUid[k]) and
              (WPart[j] = Views[Viewer].LPart[k]) then
            begin
              Keep[k] := True;
              WPlaced[j] := True;
              Break;
            end;
      if not Keep[k] then
        Views[Viewer].LMine[k] := 0;
    end;
    for j := 0 to Nw - 1 do
      if not WPlaced[j] then
      begin
        Found_ := False;
        for k := 0 to Pool - 1 do
          if Views[Viewer].LMine[k] = 0 then
          begin
            Views[Viewer].LMine[k] := WMine[j];
            Views[Viewer].LUid[k] := WUid[j];
            Views[Viewer].LPart[k] := WPart[j];
            Found_ := True;
            Break;
          end;
        if not Found_ then
          Break;
      end;
    { the wanted texts of the layers }
    for k := 0 to Pool - 1 do
    begin
      i := Views[Viewer].LMine[k];
      if i = 0 then
        Continue;
      Part := Views[Viewer].LPart[k];
      if Part = 0 then
      begin
        T := MarkText(Mines[i]);
        MarkPlace(Mines[i], T, TX, TY);
        WantText(KIND_WORLD, Layer0 + k, T, TX, TY, MarkScale, MarkColor(Mines[i], Viewer), Refresh + 120, 0.5);
      end
      else if Part = 1 then
      begin
        T := WireText(Mines[i], TX, TY);
        if T <> '' then
          WantText(KIND_WORLD, Layer0 + k, T, TX, TY, WireScale, ColWire, Refresh + 120, 0.5);
      end;
    end;
    { the preview on its own layers }
    if Prev > 0 then
      for j := 0 to PreviewCount - 1 do
        if PreviewDot(Mines[Prev], j, TX, TY) then
          WantText(KIND_WORLD, PrevLayer0 + j, TxPrev, TX, TY, PrevScale, ColPrev, PrevTicks + 30, 0.5);
    Result := Diff(Views[Viewer].Sent, OwnBig, OwnWorld, Tick, Refresh, Budget, MoreB);
    if MoreB then
      More := 1;
  except
    Result := 0;
    More := 0;
  end;
end;

function MnHide(Viewer, Budget: LongInt): LongInt;
var
  k: LongInt;
  MoreB: Boolean;
begin
  Result := 0;
  if not Valid(Viewer) then
    Exit;
  try
    for k := 0 to MAX_POOL - 1 do
      Views[Viewer].LMine[k] := 0;
    Result := HideAll(Views[Viewer].Sent, OwnBig, OwnWorld, Budget, MoreB);
  except
    Result := 0;
  end;
end;

procedure MnShift(Delta: LongInt);
var
  k: LongInt;
begin
  if Delta <= 0 then
    Exit;
  for k := 1 to MAX_MINES do
    if Mines[k].Live then
    begin
      if Mines[k].PlantTick > 0 then
        Inc(Mines[k].PlantTick, Delta);
      if Mines[k].ArmTick > 0 then
        Inc(Mines[k].ArmTick, Delta);
      if Mines[k].EndTick > 0 then
        Inc(Mines[k].EndTick, Delta);
      if Mines[k].ChainAt > 0 then
        Inc(Mines[k].ChainAt, Delta);
      if Mines[k].ShotAt > 0 then
        Inc(Mines[k].ShotAt, Delta);
      if Mines[k].WorkStart > 0 then
        Inc(Mines[k].WorkStart, Delta);
    end;
  for k := 1 to MAX_ID do
    if FallTick[k] > 1 then
      Inc(FallTick[k], Delta);
  if CurTick > 0 then
    Inc(CurTick, Delta);
end;

procedure MnForget(Viewer: LongInt);
var
  k: LongInt;
begin
  if not Valid(Viewer) then
    Exit;
  SetForget(Views[Viewer].Sent);
  for k := 0 to MAX_POOL - 1 do
    Views[Viewer].LMine[k] := 0;
  Working[Viewer] := 0;
  FallTick[Viewer] := 0;
  LowKey[Viewer] := False;
  LowGen[Viewer] := 0;
  PBody[Viewer] := False;
end;

function MnInfo: AnsiString;
var
  L, C: LongInt;
begin
  L := MnCount(0, MN_LAND);
  C := MnCount(0, MN_CLAY);
  Result := 'on the map ' + IntToStr(L) + ' mines, ' + IntToStr(C) + ' claymores; planted ' + IntToStr(CntPlanted) +
    ', set off ' + IntToStr(CntTrig) + ', by bodies ' + IntToStr(CntBody) + ', shot ' + IntToStr(CntShot) + ', found ' +
    IntToStr(CntSpot) + ', defused ' +
    IntToStr(CntDefused) + ', picked up ' + IntToStr(CntPicked) + ', ran out ' + IntToStr(CntExpired) +
    '; soldiers told by the script ' + IntToStr(CntFed);
  if CntDropped > 0 then
    Result := Result + ', shots dropped ' + IntToStr(CntDropped);
end;

initialization
  MnPoint := @SpritePoint;
  SetPool;
end.
