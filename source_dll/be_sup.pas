unit be_sup;

{$mode objfpc}{$H+}

interface

uses
  be_world;

procedure SupConfig(Radius, RadiusBig: Single; ScanTicks: LongInt; TeamBullets, FriendlyFire, TeamGame: Boolean);
procedure SupPlayers(n: LongInt; I: PLongArr; F: PSingleArr);
function SupBullet(Owner, Style: LongInt; X, Y, VX, VY: Single): LongInt;
procedure TeamSet(ID, Team: LongInt);

implementation

var
  Teams: array[1..BE_PLAYERS] of LongInt;
  PCount: LongInt = 0;
  PID, PTeam: array[0..BE_PLAYERS - 1] of LongInt;
  PX, PY: array[0..BE_PLAYERS - 1] of Single;
  RSmall: Single = 50;
  RBig: Single = 130;
  Ticks: LongInt = 3;
  TeamHits, FF, Teamed: Boolean;

procedure SupConfig(Radius, RadiusBig: Single; ScanTicks: LongInt; TeamBullets, FriendlyFire, TeamGame: Boolean);
begin
  RSmall := Radius;
  RBig := RadiusBig;
  if ScanTicks < 1 then
    ScanTicks := 1;
  Ticks := ScanTicks;
  TeamHits := TeamBullets;
  FF := FriendlyFire;
  Teamed := TeamGame;
end;

procedure TeamSet(ID, Team: LongInt);
begin
  if ValidID(ID) then
    Teams[ID] := Team;
end;

procedure SupPlayers(n: LongInt; I: PLongArr; F: PSingleArr);
var
  k: LongInt;
begin
  if n < 0 then
    n := 0;
  if n > BE_PLAYERS then
    n := BE_PLAYERS;
  for k := 0 to n - 1 do
  begin
    PID[k] := I^[k * 2];
    PTeam[k] := I^[k * 2 + 1];
    PX[k] := F^[k * 2];
    PY[k] := F^[k * 2 + 1];
  end;
  PCount := n;
end;

function SupBullet(Owner, Style: LongInt; X, Y, VX, VY: Single): LongInt;
var
  k, OT: LongInt;
  R, R2, DX, DY, X0, X1, Y0, Y1, L2, T, CX, CY: Single;
begin
  Result := 0;
  if not ValidID(Owner) or (PCount = 0) then
    Exit;
  OT := Teams[Owner];
  R := RSmall;
  if (Style = 2) or (Style = 4) or (Style = 8) or (Style = 9) or (Style = 10) or (Style = 12) then
    R := RBig;
  R2 := R * R;
  DX := VX * Ticks;
  DY := VY * Ticks;
  if DX >= 0 then
  begin
    X0 := X - R;
    X1 := X + DX + R;
  end
  else
  begin
    X0 := X + DX - R;
    X1 := X + R;
  end;
  if DY >= 0 then
  begin
    Y0 := Y - R;
    Y1 := Y + DY + R;
  end
  else
  begin
    Y0 := Y + DY - R;
    Y1 := Y + R;
  end;
  L2 := DX * DX + DY * DY;
  for k := 0 to PCount - 1 do
  begin
    if PID[k] = Owner then
      Continue;
    if (PX[k] < X0) or (PX[k] > X1) or (PY[k] < Y0) or (PY[k] > Y1) then
      Continue;
    if Teamed and (PTeam[k] = OT) and not (FF and TeamHits) then
      Continue;
    T := 0;
    if L2 > 0.0001 then
    begin
      T := ((PX[k] - X) * DX + (PY[k] - Y) * DY) / L2;
      if T < 0 then
        T := 0;
      if T > 1 then
        T := 1;
    end;
    CX := X + T * DX - PX[k];
    CY := Y + T * DY - PY[k];
    if CX * CX + CY * CY <= R2 then
      Result := Result or LongInt(LongWord(1) shl (PID[k] - 1));
  end;
end;

end.
