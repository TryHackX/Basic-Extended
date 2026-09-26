unit be_world;

{$mode objfpc}{$H+}

interface

const
  BE_PLAYERS = 32;
  TEAM_SPEC = 5;
  LOS_HEIGHT = 12;
  LOS_RANGE = 1001;
  SHOW_ALL = 0;
  SHOW_SEENALL = 1;
  SHOW_SEEN = 2;
  SHOW_SEENALL_REAL = 3;
  SHOW_SEEN_REAL = 4;
  WF_ALIVE = 1;
  WF_HUMAN = 2;
  WI_STRIDE = 8;
  WF_STRIDE = 4;

type
  PLongArr = ^TLongArr;
  TLongArr = array[0..4095] of LongInt;
  PSingleArr = ^TSingleArr;
  TSingleArr = array[0..4095] of Single;

  TWPlayer = record
    Active, Alive, Human: Boolean;
    Team, Pct, Tag, Ping, AimX, AimY: LongInt;
    X, Y, VX, VY: Single;
    Name: AnsiString;
  end;

  TWFlag = record
    Active, InBase: Boolean;
    Team: LongInt;
    X, Y: Single;
  end;

var
  WP: array[1..BE_PLAYERS] of TWPlayer;
  WFlags: array[0..2] of TWFlag;
  WTick: LongInt = 0;
  WTeamGame: Boolean = False;
  WRealistic: Boolean = False;
  VisMine: array[1..BE_PLAYERS, 1..BE_PLAYERS] of Boolean;
  VisShow: array[1..BE_PLAYERS] of LongInt;
  VisRaysPerTick: LongInt = 24;
  VisRoundTicks: LongInt = 15;

procedure WorldLoad(Tick, Count: LongInt; I: PLongArr; F: PSingleArr);
procedure WorldBegin(Tick: LongInt);
procedure WorldPos(ID, Alive: LongInt; X, Y: Single);
procedure WorldAim(ID, AimX, AimY: LongInt);
procedure WorldVel(ID: LongInt; VX, VY: Single);
procedure WorldExtra(ID, Pct, Tag, Ping: LongInt);
procedure WorldEnd;
procedure WorldMeta(ID, Team, Human: LongInt);
procedure WorldFlag(Index, Team, State: LongInt; X, Y: Single);
procedure WorldName(ID: LongInt; const Name: AnsiString);
function ValidID(ID: LongInt): Boolean;
function Enemies(A, B: LongInt): Boolean;
function Shows(A, B, Show: LongInt): Boolean;
function NeedsLos(Show: LongInt): Boolean;
procedure VisSet(S, B: LongInt; Seen: Boolean);
procedure VisReset(ID: LongInt);
function VisNeeded: Boolean;
function VisNext(Tick: LongInt; out S, B: LongInt; out X1, Y1, X2, Y2: Single): Boolean;

implementation

var
  VisList: array[0..BE_PLAYERS - 1] of LongInt;
  VisCount: LongInt = 0;
  VisK: LongInt = 0;
  VisB: LongInt = 0;
  VisNextRound: LongInt = 0;
  VisTickSeen: LongInt = -1;
  VisRaysDone: LongInt = 0;

function ValidID(ID: LongInt): Boolean;
begin
  Result := (ID >= 1) and (ID <= BE_PLAYERS);
end;

procedure WorldLoad(Tick, Count: LongInt; I: PLongArr; F: PSingleArr);
var
  k, ID, Flags: LongInt;
  Seen: array[1..BE_PLAYERS] of Boolean;
begin
  WTick := Tick;
  for k := 1 to BE_PLAYERS do
    Seen[k] := False;
  if Count > BE_PLAYERS then
    Count := BE_PLAYERS;
  for k := 0 to Count - 1 do
  begin
    ID := I^[k * WI_STRIDE];
    if not ValidID(ID) then
      Continue;
    Seen[ID] := True;
    Flags := I^[k * WI_STRIDE + 1];
    with WP[ID] do
    begin
      Active := True;
      Alive := (Flags and WF_ALIVE) <> 0;
      Human := (Flags and WF_HUMAN) <> 0;
      Team := I^[k * WI_STRIDE + 2];
      Pct := I^[k * WI_STRIDE + 3];
      Tag := I^[k * WI_STRIDE + 4];
      Ping := I^[k * WI_STRIDE + 5];
      AimX := I^[k * WI_STRIDE + 6];
      AimY := I^[k * WI_STRIDE + 7];
      X := F^[k * WF_STRIDE];
      Y := F^[k * WF_STRIDE + 1];
      VX := F^[k * WF_STRIDE + 2];
      VY := F^[k * WF_STRIDE + 3];
    end;
  end;
  for k := 1 to BE_PLAYERS do
    if not Seen[k] then
    begin
      WP[k].Active := False;
      WP[k].Alive := False;
    end;
end;

var
  SnapSeen: array[1..BE_PLAYERS] of Boolean;

procedure WorldBegin(Tick: LongInt);
var
  k: LongInt;
begin
  WTick := Tick;
  for k := 1 to BE_PLAYERS do
    SnapSeen[k] := False;
end;

procedure WorldPos(ID, Alive: LongInt; X, Y: Single);
begin
  if not ValidID(ID) then
    Exit;
  SnapSeen[ID] := True;
  WP[ID].Active := True;
  WP[ID].Alive := Alive <> 0;
  WP[ID].X := X;
  WP[ID].Y := Y;
  if Alive = 0 then
  begin
    WP[ID].VX := 0;
    WP[ID].VY := 0;
  end;
end;

procedure WorldAim(ID, AimX, AimY: LongInt);
begin
  if not ValidID(ID) then
    Exit;
  WP[ID].AimX := AimX;
  WP[ID].AimY := AimY;
end;

procedure WorldVel(ID: LongInt; VX, VY: Single);
begin
  if not ValidID(ID) then
    Exit;
  WP[ID].VX := VX;
  WP[ID].VY := VY;
end;

procedure WorldExtra(ID, Pct, Tag, Ping: LongInt);
begin
  if not ValidID(ID) then
    Exit;
  WP[ID].Pct := Pct;
  WP[ID].Tag := Tag;
  WP[ID].Ping := Ping;
end;

procedure WorldEnd;
var
  k: LongInt;
begin
  for k := 1 to BE_PLAYERS do
    if not SnapSeen[k] then
    begin
      WP[k].Active := False;
      WP[k].Alive := False;
    end;
end;

procedure WorldFlag(Index, Team, State: LongInt; X, Y: Single);
begin
  if (Index < 0) or (Index > 2) then
    Exit;
  WFlags[Index].Active := State > 0;
  WFlags[Index].InBase := State = 1;
  WFlags[Index].Team := Team;
  WFlags[Index].X := X;
  WFlags[Index].Y := Y;
end;

procedure WorldMeta(ID, Team, Human: LongInt);
begin
  if not ValidID(ID) then
    Exit;
  if Team > -100 then
    WP[ID].Team := Team;
  if Human >= 0 then
    WP[ID].Human := Human <> 0;
end;

procedure WorldName(ID: LongInt; const Name: AnsiString);
begin
  if ValidID(ID) then
    WP[ID].Name := Name;
end;

function Enemies(A, B: LongInt): Boolean;
begin
  Result := A <> B;
  if Result and WTeamGame then
    Result := WP[A].Team <> WP[B].Team;
end;

function NeedsLos(Show: LongInt): Boolean;
begin
  Result := (Show = SHOW_SEENALL_REAL) or (Show = SHOW_SEEN_REAL) or
    (WRealistic and ((Show = SHOW_SEENALL) or (Show = SHOW_SEEN)));
end;

function OnScreen(S, B: LongInt): Boolean;
var
  CX, CY: Single;
begin
  CX := WP[S].X + (WP[S].AimX - WP[S].X) * 0.5;
  CY := WP[S].Y - LOS_HEIGHT + (WP[S].AimY - WP[S].Y) * 0.5;
  Result := (Abs(WP[B].X - CX) <= 457) and (Abs(WP[B].Y - LOS_HEIGHT - CY) <= 270);
end;

function SeenBy(S, B: LongInt; Los: Boolean): Boolean;
begin
  if Los then
    Result := VisMine[S, B]
  else
    Result := OnScreen(S, B);
end;

function Shows(A, B, Show: LongInt): Boolean;
var
  s: LongInt;
  Los, Dead: Boolean;
begin
  Result := True;
  if Show = SHOW_ALL then
    Exit;
  if WTeamGame and (WP[B].Team = WP[A].Team) then
    Exit;
  Los := NeedsLos(Show);
  Dead := (Show = SHOW_SEENALL) or (Show = SHOW_SEENALL_REAL);
  if SeenBy(A, B, Los) then
    Exit;
  if WTeamGame then
    for s := 1 to BE_PLAYERS do
      if (s <> A) and WP[s].Active and (WP[s].Team = WP[A].Team) then
        if Dead or WP[s].Alive then
          if SeenBy(s, B, Los) then
            Exit;
  Result := False;
end;

procedure VisSet(S, B: LongInt; Seen: Boolean);
begin
  if ValidID(S) and ValidID(B) then
    VisMine[S, B] := Seen;
end;

procedure VisReset(ID: LongInt);
var
  k: LongInt;
begin
  if not ValidID(ID) then
    Exit;
  for k := 1 to BE_PLAYERS do
  begin
    VisMine[ID, k] := False;
    VisMine[k, ID] := False;
  end;
end;

function VisNeeded: Boolean;
var
  k: LongInt;
begin
  Result := False;
  for k := 1 to BE_PLAYERS do
    if NeedsLos(VisShow[k]) then
    begin
      Result := True;
      Exit;
    end;
end;

function IsSpotter(S: LongInt): Boolean;
var
  a: LongInt;
begin
  Result := False;
  if not WP[S].Active then
    Exit;
  for a := 1 to BE_PLAYERS do
    if NeedsLos(VisShow[a]) and WP[a].Active then
      if (a = S) or (WTeamGame and (WP[a].Team = WP[S].Team)) then
      begin
        Result := True;
        Exit;
      end;
end;

procedure BuildList;
var
  i: LongInt;
begin
  VisCount := 0;
  for i := 1 to BE_PLAYERS do
    if IsSpotter(i) then
    begin
      VisList[VisCount] := i;
      Inc(VisCount);
    end;
end;

function PairRay(S, B: LongInt; out X1, Y1, X2, Y2: Single): Boolean;
var
  DX, DY: Single;
begin
  Result := False;
  X1 := 0;
  Y1 := 0;
  X2 := 0;
  Y2 := 0;
  if not WP[B].Alive then
    Exit;
  X1 := WP[S].X;
  Y1 := WP[S].Y - LOS_HEIGHT - 2;
  X2 := WP[B].X;
  Y2 := WP[B].Y - LOS_HEIGHT;
  DX := X2 - X1;
  DY := Y2 - Y1;
  if DX * DX + DY * DY > LOS_RANGE * LOS_RANGE then
    Exit;
  if WP[S].Alive then
    if DX * (WP[S].AimX - X1) + DY * (WP[S].AimY - Y1) <= 0 then
      Exit;
  Result := True;
end;

function VisNext(Tick: LongInt; out S, B: LongInt; out X1, Y1, X2, Y2: Single): Boolean;
var
  Guard, sp, bp: LongInt;
begin
  Result := False;
  S := 0;
  B := 0;
  X1 := 0;
  Y1 := 0;
  X2 := 0;
  Y2 := 0;
  if Tick <> VisTickSeen then
  begin
    VisTickSeen := Tick;
    VisRaysDone := 0;
  end;
  if VisRaysDone >= VisRaysPerTick then
    Exit;
  if VisCount = 0 then
  begin
    if Tick < VisNextRound then
      Exit;
    VisNextRound := Tick + VisRoundTicks;
    BuildList;
    VisK := 0;
    VisB := 0;
    if VisCount = 0 then
      Exit;
  end;
  Guard := 0;
  while Guard < VisRaysPerTick * 8 do
  begin
    Inc(Guard);
    Inc(VisB);
    if VisB > BE_PLAYERS then
    begin
      VisB := 1;
      Inc(VisK);
      if VisK >= VisCount then
      begin
        VisK := 0;
        VisB := 0;
        VisCount := 0;
        Exit;
      end;
    end;
    sp := VisList[VisK];
    bp := VisB;
    if sp = bp then
      Continue;
    VisMine[sp, bp] := False;
    if not WP[sp].Active or not WP[bp].Active then
      Continue;
    if WTeamGame and (WP[sp].Team = WP[bp].Team) then
      Continue;
    if not PairRay(sp, bp, X1, Y1, X2, Y2) then
      Continue;
    S := sp;
    B := bp;
    Inc(VisRaysDone);
    Result := True;
    Exit;
  end;
end;

end.
