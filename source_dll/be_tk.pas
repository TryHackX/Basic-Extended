unit be_tk;

{$mode objfpc}{$H+}
{$Q-}{$IFNDEF BE_CHECKS}{$R-}{$ENDIF}

{ [TeamKill]'s eyes on the shots. Every bullet the hook sees is copied into a queue (nothing else runs
  inside the server's CreateBullet) and looked at in the script's next tick: which soldier its line
  meets first - the body points of the skeletons as the server has them (be_sprite), the walls from the
  map (be_map). A team mate with no enemy near the line is an aimed shot at him, a team mate with an
  enemy near or behind him is crossfire, and an enemy or nobody is an ordinary shot. From the last shots
  of every shooter come the intent of a hit on a team mate (TkHit) and the spray events: SprayShots
  aimed shots at the same mate within SprayTicks, most of his shots, none of them crossfire. }

interface

uses
  be_hook;

const
  TK_EV_SPRAY = 1;
  { why a hit on a team mate looks the way it does }
  TR_UNKNOWN = 0;
  TR_AIMED = 1;
  TR_SPRAY = 2;
  TR_CROSSFIRE = 3;
  TR_SPLASH_ENEMY = 4;
  TR_SPLASH_ALONE = 5;
  TR_MELEE = 6;
  TR_STRAY = 7;
  { TkSet keys }
  TKC_ON = 1;
  TKC_LINE = 2;
  TKC_ENEMY = 3;
  TKC_RANGE = 4;
  TKC_SPRAY_SHOTS = 5;
  TKC_SPRAY_TICKS = 6;
  TKC_SPRAY_SHARE = 7;
  TKC_HIT_TICKS = 8;
  TKC_SPLASH = 9;

procedure TkSet(Key: LongInt; Value: Single);
{ the team (1-4 play, 0 none, 5 spectators) and whether he lives, from the script's events }
procedure TkPlayer(ID, NewTeam, IsAlive: LongInt);
{ from the hook (inside the server's CreateBullet): a copy of the shot, nothing more }
procedure TkQueueShot(const E: TShotEvent);
{ the script's tick: the queued shots are looked at; the result is the number of events waiting }
function TkTick: LongInt;
function TkNext(out Kind, S, T, N, Reason: LongInt): Boolean;
{ how much a hit of S on his team mate V (a bullet of Style) looks meant: 0-100, and why (TR_*) }
function TkHit(S, V, Style, Tick: LongInt; out Reason: LongInt): LongInt;
{ S's shots of the last hit window: at T (aimed), crossfire at T, at enemies, all }
function TkShots(S, T, Tick: LongInt; out AtT, Cross, AtEnemy, All: LongInt): Boolean;
procedure TkForget(ID: LongInt);
function TkInfo: AnsiString;

var
  { a point of a soldier's body (be_sprite's SpritePoint; a test sets its own) }
  TkPoint: function(ID, K: LongInt; out X, Y: Single): Boolean = nil;

implementation

uses
  SysUtils, be_map, be_sprite;

const
  MAX_ID = 32;
  QUEUE = 512;
  RING = 48;
  EVENTS = 32;
  { the classes of a shot }
  SC_NONE = 0;
  SC_ENEMY = 1;
  SC_AIMED = 2;
  SC_CROSS = 3;
  SC_WALL = 4;
  { the body points the game hits bullets against (Bullets.pas BodyPartsPriority) }
  PARTS: array[0..6] of LongInt = (12, 11, 10, 6, 5, 4, 3);

type
  TShotCopy = record
    Tick, Owner, Style: LongInt;
    X, Y, VX, VY: LongWord;
  end;

  TRing = record
    Head: LongInt;
    Tick: array[0..RING - 1] of LongInt;
    Cls, Tgt: array[0..RING - 1] of Byte;
  end;

  TEvent = record
    Kind, S, T, N, Reason: LongInt;
  end;

var
  TkOn: Boolean = False;
  LineR: Single = 10;
  EnemyR: Single = 45;
  Range: Single = 900;
  SprayShots: LongInt = 5;
  SprayTicks: LongInt = 90;
  SprayShare: Single = 0.6;
  HitTicks: LongInt = 90;
  SplashR: Single = 150;
  Team: array[1..MAX_ID] of LongInt;
  Alive: array[1..MAX_ID] of Boolean;
  Q: array[0..QUEUE - 1] of TShotCopy;
  QHead: LongInt = 0;
  QTail: LongInt = 0;
  Rings: array[1..MAX_ID] of TRing;
  { the last spray event of a shooter (at whom, when), so one spray is told once a window }
  SprayTgt, SprayAt: array[1..MAX_ID] of LongInt;
  Ev: array[0..EVENTS - 1] of TEvent;
  EvHead: LongInt = 0;
  EvTail: LongInt = 0;
  CntShots: LongInt = 0;
  CntAimed: LongInt = 0;
  CntCross: LongInt = 0;
  CntSprays: LongInt = 0;
  CntDropped: LongInt = 0;

function Finite(Bits: LongWord): Boolean;
begin
  Result := (Bits and $7F800000) <> $7F800000;
end;

function Valid(ID: LongInt): Boolean;
begin
  Result := (ID >= 1) and (ID <= MAX_ID);
end;

function Playing(ID: LongInt): Boolean;
begin
  Result := Valid(ID) and Alive[ID] and (Team[ID] >= 1) and (Team[ID] <= 4);
end;

procedure TkSet(Key: LongInt; Value: Single);
begin
  case Key of
    TKC_ON: TkOn := Value <> 0;
    TKC_LINE: if Value > 0 then LineR := Value;
    TKC_ENEMY: if Value >= 0 then EnemyR := Value;
    TKC_RANGE: if Value > 0 then Range := Value;
    TKC_SPRAY_SHOTS: if Value >= 1 then SprayShots := Round(Value);
    TKC_SPRAY_TICKS: if Value >= 1 then SprayTicks := Round(Value);
    TKC_SPRAY_SHARE: if (Value >= 0) and (Value <= 1) then SprayShare := Value;
    TKC_HIT_TICKS: if Value >= 1 then HitTicks := Round(Value);
    TKC_SPLASH: if Value >= 0 then SplashR := Value;
  end;
end;

procedure TkPlayer(ID, NewTeam, IsAlive: LongInt);
begin
  if not Valid(ID) then
    Exit;
  Team[ID] := NewTeam;
  Alive[ID] := IsAlive <> 0;
end;

{ the bullets that fly straight enough for a line: plain, shotgun, flame, arrows, LAW, a thrown knife,
  the stationary gun }
function Straight(Style: LongInt): Boolean;
begin
  Result := (Style = 1) or (Style = 3) or (Style = 5) or (Style = 7) or (Style = 8) or (Style = 12) or
    (Style = 13) or (Style = 14);
end;

procedure TkQueueShot(const E: TShotEvent);
var
  n: LongInt;
begin
  if not TkOn then
    Exit;
  if not Valid(E.Owner) then
    Exit;
  if not Straight(E.Style) then
    Exit;
  Q[QHead].Tick := E.Tick;
  Q[QHead].Owner := E.Owner;
  Q[QHead].Style := E.Style;
  Q[QHead].X := PLongWord(@E.X)^;
  Q[QHead].Y := PLongWord(@E.Y)^;
  Q[QHead].VX := PLongWord(@E.VX)^;
  Q[QHead].VY := PLongWord(@E.VY)^;
  n := (QHead + 1) mod QUEUE;
  if n = QTail then
  begin
    QTail := (QTail + 1) mod QUEUE;
    Inc(CntDropped);
  end;
  QHead := n;
end;

procedure Push(Kind, S, T, N, Reason: LongInt);
var
  k: LongInt;
begin
  Ev[EvHead].Kind := Kind;
  Ev[EvHead].S := S;
  Ev[EvHead].T := T;
  Ev[EvHead].N := N;
  Ev[EvHead].Reason := Reason;
  k := (EvHead + 1) mod EVENTS;
  if k = EvTail then
    EvTail := (EvTail + 1) mod EVENTS;
  EvHead := k;
end;

procedure Remember(S, Tick, Cls, Tgt: LongInt);
var
  h: LongInt;
begin
  h := Rings[S].Head;
  Rings[S].Tick[h] := Tick;
  Rings[S].Cls[h] := Cls;
  Rings[S].Tgt[h] := Tgt;
  Rings[S].Head := (h + 1) mod RING;
end;

{ the shots of S since Since: aimed at T, crossfire at T, at enemies, all (nobody and walls too) }
procedure Count(S, T, Since: LongInt; out AtT, Cross, AtEnemy, All: LongInt);
var
  k: LongInt;
begin
  AtT := 0;
  Cross := 0;
  AtEnemy := 0;
  All := 0;
  for k := 0 to RING - 1 do
    if Rings[S].Tick[k] > 0 then
      if Rings[S].Tick[k] >= Since then
      begin
        Inc(All);
        case Rings[S].Cls[k] of
          SC_ENEMY: Inc(AtEnemy);
          SC_AIMED:
            if Rings[S].Tgt[k] = T then
              Inc(AtT);
          SC_CROSS:
            if Rings[S].Tgt[k] = T then
              Inc(Cross);
        end;
      end;
end;

{ how near the line from P along the unit vector D a soldier's body comes (Dist) and how far along it
  (Along); False when no body point lies ahead within Range }
function OnLine(ID: LongInt; PX, PY, DX, DY: Single; out Dist, Along: Single): Boolean;
var
  k: LongInt;
  X, Y, WX, WY, T, C: Single;
begin
  Result := False;
  Dist := 1E9;
  Along := 0;
  if not Assigned(TkPoint) then
    Exit;
  for k := 0 to High(PARTS) do
    if TkPoint(ID, PARTS[k], X, Y) then
    begin
      WX := X - PX;
      WY := Y - PY;
      T := WX * DX + WY * DY;
      if (T < 8) or (T > Range) then
        Continue;
      C := Abs(WX * DY - WY * DX);
      if C < Dist then
      begin
        Dist := C;
        Along := T;
        Result := True;
      end;
    end;
end;

procedure Look(const C: TShotCopy);
var
  S, j, First, Cls: LongInt;
  PX, PY, VX, VY, L, DX, DY, D, A, FirstA, TX, TY: Single;
  Near: Boolean;
  AtT, Cross, AtEnemy, All: LongInt;
begin
  S := C.Owner;
  if not ((Team[S] >= 1) and (Team[S] <= 4)) then
    Exit;
  if not (Finite(C.X) and Finite(C.Y) and Finite(C.VX) and Finite(C.VY)) then
    Exit;
  PX := PSingle(@C.X)^;
  PY := PSingle(@C.Y)^;
  VX := PSingle(@C.VX)^;
  VY := PSingle(@C.VY)^;
  L := Sqrt(VX * VX + VY * VY);
  if L < 0.01 then
    Exit;
  DX := VX / L;
  DY := VY / L;
  { a shotgun's pellets come in one tick: one shot of the tick is enough }
  if C.Style = 3 then
    if Rings[S].Tick[(Rings[S].Head + RING - 1) mod RING] = C.Tick then
      Exit;
  Inc(CntShots);
  First := 0;
  FirstA := 1E9;
  Near := False;
  for j := 1 to MAX_ID do
    if (j <> S) and Playing(j) then
      if OnLine(j, PX, PY, DX, DY, D, A) then
      begin
        if Team[j] <> Team[S] then
          if D <= EnemyR then
            Near := True;
        if D <= LineR then
          if A < FirstA then
          begin
            FirstA := A;
            First := j;
          end;
      end;
  Cls := SC_NONE;
  if First > 0 then
  begin
    if Team[First] <> Team[S] then
      Cls := SC_ENEMY
    else
    begin
      Cls := SC_AIMED;
      if Near then
        Cls := SC_CROSS;
      { a wall before him stops the bullet }
      if MapReady then
        if TkPoint(First, 7, TX, TY) then
          if MapRay(PX, PY, TX, TY, MR_BULLET, 0) then
            Cls := SC_WALL;
    end;
  end;
  if Cls = SC_AIMED then
    Inc(CntAimed)
  else if Cls = SC_CROSS then
    Inc(CntCross);
  Remember(S, C.Tick, Cls, First);
  if Cls <> SC_AIMED then
    Exit;
  { a spray: enough aimed shots at the same mate within the window, most of his shots, no crossfire }
  Count(S, First, C.Tick - SprayTicks, AtT, Cross, AtEnemy, All);
  if AtT < SprayShots then
    Exit;
  if Cross > 0 then
    Exit;
  if AtT < SprayShare * All then
    Exit;
  if (SprayTgt[S] = First) and (C.Tick - SprayAt[S] < SprayTicks) then
    Exit;
  SprayTgt[S] := First;
  SprayAt[S] := C.Tick;
  Inc(CntSprays);
  Push(TK_EV_SPRAY, S, First, AtT, TR_SPRAY);
end;

function TkTick: LongInt;
begin
  try
    while QTail <> QHead do
    begin
      if TkOn then
        Look(Q[QTail]);
      QTail := (QTail + 1) mod QUEUE;
    end;
  except
    QTail := QHead;
  end;
  Result := (EvHead - EvTail + EVENTS) mod EVENTS;
end;

function TkNext(out Kind, S, T, N, Reason: LongInt): Boolean;
begin
  Result := EvTail <> EvHead;
  Kind := 0;
  S := 0;
  T := 0;
  N := 0;
  Reason := 0;
  if not Result then
    Exit;
  Kind := Ev[EvTail].Kind;
  S := Ev[EvTail].S;
  T := Ev[EvTail].T;
  N := Ev[EvTail].N;
  Reason := Ev[EvTail].Reason;
  EvTail := (EvTail + 1) mod EVENTS;
end;

{ how far from its centre a blast hurts (the game's explosion radii): the frag grenade 85 px, the M79 and the LAW
  64 px, a cluster grenade's bursts 35 px }
function BlastReach(Style: LongInt): Single;
begin
  case Style of
    2: Result := 85;
    4, 12: Result := 64;
    9, 10: Result := 35;
  else
    Result := 0;
  end;
end;

{ an enemy of V within SplashR of the blast that reached him: the blast's centre is not known here, it lies within
  Reach of V, so an enemy within SplashR of the centre is within SplashR + Reach of V (BE2-02: the enemy on the far side
  of the blast counts too) }
function EnemyNear(V: LongInt; Reach: Single): Boolean;
var
  j: LongInt;
  X, Y, EX, EY: Single;
begin
  Result := False;
  if not Assigned(TkPoint) then
    Exit;
  if not TkPoint(V, 7, X, Y) then
    Exit;
  for j := 1 to MAX_ID do
    if (j <> V) and Playing(j) and (Team[j] <> Team[V]) then
      if TkPoint(j, 7, EX, EY) then
        if Sqr(EX - X) + Sqr(EY - Y) <= Sqr(SplashR + Reach) then
        begin
          Result := True;
          Exit;
        end;
end;

function TkHit(S, V, Style, Tick: LongInt; out Reason: LongInt): LongInt;
var
  AtT, Cross, AtEnemy, All: LongInt;
begin
  Reason := TR_UNKNOWN;
  Result := 50;
  try
    if not (Valid(S) and Valid(V)) then
      Exit;
    { a knife in the hand or a punch: nobody does that by chance }
    if (Style = 6) or (Style = 11) then
    begin
      Reason := TR_MELEE;
      Result := 100;
      Exit;
    end;
    { grenades, M79, cluster: an accident when enemies are near him }
    if (Style = 2) or (Style = 4) or (Style = 9) or (Style = 10) then
    begin
      if EnemyNear(V, BlastReach(Style)) then
      begin
        Reason := TR_SPLASH_ENEMY;
        Result := 10;
      end
      else
      begin
        Reason := TR_SPLASH_ALONE;
        Result := 60;
      end;
      Exit;
    end;
    if not TkOn then
      Exit;
    if (SprayTgt[S] = V) and (Tick - SprayAt[S] <= 2 * SprayTicks) then
    begin
      Reason := TR_SPRAY;
      Result := 100;
      Exit;
    end;
    Count(S, V, Tick - HitTicks, AtT, Cross, AtEnemy, All);
    if AtT + Cross = 0 then
    begin
      { no shot of his went at him: he ran into the fire, a ricochet - or a LAW's blast }
      if (Style = 12) and not EnemyNear(V, BlastReach(Style)) then
      begin
        Reason := TR_SPLASH_ALONE;
        Result := 60;
        Exit;
      end;
      Reason := TR_STRAY;
      Result := 20;
      Exit;
    end;
    if Cross >= AtT then
    begin
      Reason := TR_CROSSFIRE;
      Result := 20;
      Exit;
    end;
    Result := Round(100 * AtT / (AtT + Cross + AtEnemy));
    if AtEnemy = 0 then
      if AtT = 1 then
        Result := 90;
    Reason := TR_AIMED;
    if Result < 50 then
      Reason := TR_CROSSFIRE;
  except
    Reason := TR_UNKNOWN;
    Result := 50;
  end;
end;

function TkShots(S, T, Tick: LongInt; out AtT, Cross, AtEnemy, All: LongInt): Boolean;
begin
  AtT := 0;
  Cross := 0;
  AtEnemy := 0;
  All := 0;
  Result := Valid(S) and Valid(T);
  if Result then
    Count(S, T, Tick - HitTicks, AtT, Cross, AtEnemy, All);
end;

procedure TkForget(ID: LongInt);
var
  k: LongInt;
begin
  if not Valid(ID) then
    Exit;
  Rings[ID].Head := 0;
  for k := 0 to RING - 1 do
    Rings[ID].Tick[k] := 0;
  SprayTgt[ID] := 0;
  SprayAt[ID] := 0;
  for k := 1 to MAX_ID do
    if SprayTgt[k] = ID then
      SprayTgt[k] := 0;
end;

function TkInfo: AnsiString;
begin
  Result := 'team kill eyes: shots looked at ' + IntToStr(CntShots) + ', aimed at team mates ' + IntToStr(CntAimed) +
    ', crossfire ' + IntToStr(CntCross) + ', sprays ' + IntToStr(CntSprays);
  if CntDropped > 0 then
    Result := Result + ', not looked at (queue full) ' + IntToStr(CntDropped);
end;

initialization
  TkPoint := @SpritePoint;
end.
