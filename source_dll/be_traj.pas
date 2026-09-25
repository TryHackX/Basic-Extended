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
  TJF_SCALE = 1;
  TJF_CURSOR_SCALE = 2;
  TJF_MOVE = 3;
  TJT_DOT = 1;
  TJT_CURSOR = 2;
  TJT_HIT = 3;

procedure TrajInt(Key, Value: LongInt);
procedure TrajFloat(Key: LongInt; Value: Single);
procedure TrajText(Key: LongInt; const Value: AnsiString);
function TrajPass(ID, Tick, Budget, Visible, Hit: LongInt; CursorX, CursorY: Single; Cursor: LongInt): LongInt;
function TrajHide(ID, Budget: LongInt): LongInt;
procedure TrajReset(ID: LongInt);

implementation

uses
  be_world, be_texts, be_font, be_ballistic;

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
  end;
  BuildOwned;
end;

procedure TrajFloat(Key: LongInt; Value: Single);
begin
  case Key of
    TJF_SCALE: DotScale := Value;
    TJF_CURSOR_SCALE: CursorScale := Value;
    TJF_MOVE: MoveEps := Value;
  end;
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
    SetForget(Sent[ID]);
end;

initialization
  BuildOwned;
end.
