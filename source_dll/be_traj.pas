unit be_traj;

{$mode objfpc}{$H+}

interface

const
  TJ_LAYER = 1;
  TJ_DOTS = 2;
  TJ_COLOR = 3;
  TJ_HIT_COLOR = 4;
  TJ_CURSOR_COLOR = 5;
  TJ_REFRESH = 6;
  TJ_DISPLAY = 7;
  TJ_TICKS = 8;
  TJ_CLIP = 9;
  TJF_SCALE = 1;
  TJF_CURSOR_SCALE = 2;
  TJF_MOVE = 3;
  TJF_SPACING = 4;
  TJF_RANGE = 5;
  TJF_MARGIN = 6;
  TJT_DOT = 1;
  TJT_CURSOR = 2;
  TJT_HIT = 3;

procedure TrajInt(Key, Value: LongInt);
procedure TrajFloat(Key: LongInt; Value: Single);
procedure TrajText(Key: LongInt; const Value: AnsiString);
function TrajPass(ID, Tick, Budget, Visible, Hit: LongInt; CursorX, CursorY: Single; Cursor: LongInt): LongInt;
function TrajHide(ID, Budget: LongInt): LongInt;
procedure TrajReset(ID: LongInt);
function TrajStep(ID, Tick, Budget, W, Flags, Team: LongInt; X, Y, VX, VY, AimX, AimY: Single;
  Cursor: LongInt): LongInt;
function TrajRecomputed: LongInt;

implementation

uses
  be_world, be_texts, be_font, be_ballistic, be_map;

const
  MAX_MARKS = 65;
  VIEW_HALF_W = 427;
  VIEW_HALF_H = 240;
  VIEW_REACH_X = 1000;
  VIEW_REACH_Y = 760;
  VIEW_CENTER = 0.505;
  VIEW_GROW = 0.17;

type
  TTrajMemo = record
    Valid, Hit: Boolean;
    Gen, MapGen, W, Flags, Team: LongInt;
    X, Y, VX, VY, AX, AY: Single;
    N: LongInt;
    MX, MY: array[0..MAX_MARKS - 1] of Single;
  end;

var
  Sent: array[1..BE_PLAYERS] of TTextSet;
  OwnBig, OwnWorld: TOwnMask;
  Layer: LongInt = 100;
  Dots: LongInt = 16;
  DotColor: LongInt = $FF3030;
  HitColor: LongInt = $33CC00;
  CursorColor: LongInt = $DCB201;
  Refresh: LongInt = 300;
  Display: LongInt = 600;
  DotScale: Single = 0.08;
  CursorScale: Single = 0.1;
  MoveEps: Single = 2;
  DotChar: AnsiString = '.';
  CursorChar: AnsiString = '+';
  HitChar: AnsiString = 'x';
  StepTicks: LongInt = 600;
  StepSpacing: Single = 24;
  StepRange: Single = 2400;
  ViewMargin: Single = 25;
  ClipView: Boolean = True;
  Gen: LongInt = 1;
  Recomputed: LongInt = 0;
  Memo: array[1..BE_PLAYERS] of TTrajMemo;

procedure BuildOwned;
var
  i: LongInt;
begin
  for i := 0 to 255 do
  begin
    OwnBig[i] := False;
    OwnWorld[i] := False;
  end;
  for i := Layer to Layer + Dots do
    if (i >= 0) and (i <= 255) then
      OwnWorld[i] := True;
end;

procedure TrajInt(Key, Value: LongInt);
begin
  case Key of
    TJ_LAYER: Layer := Value;
    TJ_DOTS: if (Value >= 1) and (Value <= 64) then Dots := Value;
    TJ_COLOR: DotColor := Value;
    TJ_HIT_COLOR: HitColor := Value;
    TJ_CURSOR_COLOR: CursorColor := Value;
    TJ_REFRESH: if Value > 0 then Refresh := Value;
    TJ_DISPLAY: if Value > 0 then Display := Value;
    TJ_TICKS: if (Value >= 10) and (Value <= 2000) then StepTicks := Value;
    TJ_CLIP: ClipView := Value <> 0;
  end;
  Inc(Gen);
  BuildOwned;
end;

procedure TrajFloat(Key: LongInt; Value: Single);
begin
  case Key of
    TJF_SCALE: DotScale := Value;
    TJF_CURSOR_SCALE: CursorScale := Value;
    TJF_MOVE: MoveEps := Value;
    TJF_SPACING: if Value >= 4 then StepSpacing := Value;
    TJF_RANGE: if Value >= 50 then StepRange := Value;
    TJF_MARGIN: if Value >= 0 then ViewMargin := Value;
  end;
  Inc(Gen);
end;

procedure TrajText(Key: LongInt; const Value: AnsiString);
begin
  if Value = '' then
    Exit;
  case Key of
    TJT_DOT: DotChar := Value;
    TJT_CURSOR: CursorChar := Value;
    TJT_HIT: HitChar := Value;
  end;
end;

procedure Mark(L: LongInt; const Ch: AnsiString; C: LongInt; Sc, X, Y: Single; Group: LongInt);
var
  Em, CX, CY: Single;
begin
  Em := Sc * WORLD_EM;
  InkCenter(Ch, CX, CY);
  WantText(KIND_WORLD, L, Ch, X - CX * Em, Y - CY * Em, Sc, C, Display, MoveEps, Group);
end;

function TrajPass(ID, Tick, Budget, Visible, Hit: LongInt; CursorX, CursorY: Single; Cursor: LongInt): LongInt;
var
  i, k, n, Step: LongInt;
  More: Boolean;
begin
  Result := 0;
  if not ValidID(ID) then
    Exit;
  WantClear;
  if Visible > PathCount then
    Visible := PathCount;
  n := Visible - 1;
  if n > 0 then
  begin
    Step := 1;
    while (n + Step - 1) div Step > Dots do
      Inc(Step);
    i := 0;
    k := Step;
    while (k < n) and (i < Dots - 1) do
    begin
      Mark(Layer + i, DotChar, DotColor, DotScale, PathX[k], PathY[k], 1);
      Inc(i);
      Inc(k, Step);
    end;
    if Hit >= 0 then
      Mark(Layer + i, HitChar, HitColor, DotScale, PathX[n], PathY[n], 1)
    else
      Mark(Layer + i, DotChar, DotColor, DotScale, PathX[n], PathY[n], 1);
  end;
  if Cursor <> 0 then
    Mark(Layer + Dots, CursorChar, CursorColor, CursorScale, CursorX, CursorY, 0);
  Result := Diff(Sent[ID], OwnBig, OwnWorld, Tick, Refresh, Budget, More);
end;

function TrajHide(ID, Budget: LongInt): LongInt;
var
  More: Boolean;
begin
  Result := 0;
  if ValidID(ID) then
    Result := HideAll(Sent[ID], OwnBig, OwnWorld, Budget, More);
end;

procedure TrajReset(ID: LongInt);
begin
  if ValidID(ID) then
  begin
    SetForget(Sent[ID]);
    Memo[ID].Valid := False;
  end;
end;

function TrajRecomputed: LongInt;
begin
  Result := Recomputed;
  Recomputed := 0;
end;

function SameInput(const M: TTrajMemo; W, Flags, Team: LongInt; X, Y, VX, VY, AimX, AimY: Single): Boolean;
begin
  Result := M.Valid and (M.Gen = Gen) and (M.MapGen = MapGeneration) and (M.W = W) and (M.Flags = Flags) and
    (M.Team = Team) and (Abs(M.X - X) < 0.5) and (Abs(M.Y - Y) < 0.5) and (Abs(M.VX - VX) < 0.05) and
    (Abs(M.VY - VY) < 0.05) and (Abs(M.AX - AimX) < 0.5) and (Abs(M.AY - AimY) < 0.5);
end;

procedure ViewBox(X, Y, AimX, AimY: Single; out CX, CY, HW, HH: Single);
var
  DX, DY: Single;
begin
  DX := AimX - X;
  DY := AimY - Y;
  if (Abs(DX) <= VIEW_REACH_X) and (Abs(DY) <= VIEW_REACH_Y) then
  begin
    CX := X + VIEW_CENTER * DX;
    CY := Y + VIEW_CENTER * DY;
    HW := VIEW_HALF_W + ViewMargin + VIEW_GROW * Abs(DX);
    HH := VIEW_HALF_H + ViewMargin + VIEW_GROW * Abs(DY);
  end
  else
  begin
    CX := AimX;
    CY := AimY;
    HW := 2 * (VIEW_HALF_W + ViewMargin);
    HH := 2 * (VIEW_HALF_H + ViewMargin);
  end;
end;

function InBox(PX, PY, CX, CY, HW, HH: Single): Boolean; inline;
begin
  Result := (Abs(PX - CX) <= HW) and (Abs(PY - CY) <= HH);
end;

procedure HitPoint(AX, AY, BX, BY: Single; Team: LongInt; out HX, HY: Single);
var
  Lo, Hi, Mid: Single;
  k: LongInt;
begin
  Lo := 0;
  Hi := 1;
  for k := 1 to 7 do
  begin
    Mid := (Lo + Hi) / 2;
    if MapRay(AX, AY, AX + (BX - AX) * Mid, AY + (BY - AY) * Mid, MR_BULLET, Team) then
      Hi := Mid
    else
      Lo := Mid;
  end;
  HX := AX + (BX - AX) * Hi;
  HY := AY + (BY - AY) * Hi;
end;

procedure Compute(var M: TTrajMemo; W, Flags, Team: LongInt; X, Y, VX, VY, AimX, AimY: Single);
var
  OX, OY, DX, DY, CX, CY, HW, HH, HX, HY: Single;
  n, k, First, Last, S, Step, Count, i: LongInt;
  Hit, HitSeen: Boolean;
begin
  Inc(Recomputed);
  M.Valid := True;
  M.Gen := Gen;
  M.MapGen := MapGeneration;
  M.W := W;
  M.Flags := Flags;
  M.Team := Team;
  M.X := X;
  M.Y := Y;
  M.VX := VX;
  M.VY := VY;
  M.AX := AimX;
  M.AY := AimY;
  M.N := 0;
  M.Hit := False;
  if not ValidWeapon(W) then
    Exit;
  Muzzle(X, Y, AimX, AimY, Flags, OX, OY, DX, DY);
  n := BuildPathDir(W, OX, OY, DX, DY, VX, VY, StepTicks, StepSpacing, StepRange);
  if n < 2 then
    Exit;
  if ClipView then
    ViewBox(X, Y, AimX, AimY, CX, CY, HW, HH)
  else
  begin
    CX := X;
    CY := Y;
    HW := 1E9;
    HH := 1E9;
  end;
  First := -1;
  Last := -1;
  Hit := False;
  HitSeen := False;
  HX := 0;
  HY := 0;
  if InBox(PathX[0], PathY[0], CX, CY, HW, HH) then
  begin
    First := 0;
    Last := 0;
  end;
  for k := 1 to n - 1 do
  begin
    if MapRay(PathX[k - 1], PathY[k - 1], PathX[k], PathY[k], MR_BULLET, Team) then
    begin
      Hit := True;
      HitPoint(PathX[k - 1], PathY[k - 1], PathX[k], PathY[k], Team, HX, HY);
      if InBox(HX, HY, CX, CY, HW, HH) then
      begin
        HitSeen := True;
        if First < 0 then
          First := k;
        Last := k;
      end;
      Break;
    end;
    if InBox(PathX[k], PathY[k], CX, CY, HW, HH) then
    begin
      if First < 0 then
        First := k;
      Last := k;
    end
    else if First >= 0 then
      Break;
  end;
  if (First < 0) or (Last < 1) then
    Exit;
  S := First;
  if S < 1 then
    S := 1;
  if S > Last then
    S := Last;
  Count := Last - S + 1;
  Step := 1;
  while (Count + Step - 1) div Step > Dots do
    Inc(Step);
  i := 0;
  k := S;
  while (k < Last) and (i < Dots - 1) and (i < MAX_MARKS - 1) do
  begin
    M.MX[i] := PathX[k];
    M.MY[i] := PathY[k];
    Inc(i);
    Inc(k, Step);
  end;
  if Hit and HitSeen then
  begin
    M.MX[i] := HX;
    M.MY[i] := HY;
    M.Hit := True;
  end
  else
  begin
    M.MX[i] := PathX[Last];
    M.MY[i] := PathY[Last];
  end;
  M.N := i + 1;
end;

function TrajStep(ID, Tick, Budget, W, Flags, Team: LongInt; X, Y, VX, VY, AimX, AimY: Single;
  Cursor: LongInt): LongInt;
var
  i: LongInt;
  More: Boolean;
begin
  Result := -1;
  if not MapReady then
    Exit;
  Result := 0;
  if not ValidID(ID) then
    Exit;
  if not SameInput(Memo[ID], W, Flags, Team, X, Y, VX, VY, AimX, AimY) then
    Compute(Memo[ID], W, Flags, Team, X, Y, VX, VY, AimX, AimY);
  WantClear;
  for i := 0 to Memo[ID].N - 1 do
    if Memo[ID].Hit and (i = Memo[ID].N - 1) then
      Mark(Layer + i, HitChar, HitColor, DotScale, Memo[ID].MX[i], Memo[ID].MY[i], 1)
    else
      Mark(Layer + i, DotChar, DotColor, DotScale, Memo[ID].MX[i], Memo[ID].MY[i], 1);
  if Cursor <> 0 then
    Mark(Layer + Dots, CursorChar, CursorColor, CursorScale, AimX, AimY, 0);
  Result := Diff(Sent[ID], OwnBig, OwnWorld, Tick, Refresh, Budget, More);
end;

initialization
  BuildOwned;
end.
