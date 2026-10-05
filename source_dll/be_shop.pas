unit be_shop;

{ [Shop] and [Supply] helpers: where an explosive armour-piercing round meets its first wall (the bullet's own
  flight: gravity, 1% drag a tick, as the server moves it), and the ground under a point (a supply crate's
  landing). }

{$mode objfpc}{$H+}

interface

{ the first bullet-solid wall on the flight of a bullet of Style made at X, Y with VX, VY: its tick (1 =
  the first move), the point HX, HY; -1 = no wall within MaxTicks }
function ShopApPredict(Style: LongInt; X, Y, VX, VY: Single; MaxTicks, Team: LongInt; out HX, HY: Single): LongInt;
{ the first floor a soldier stands on under X, Y within Down px with room over it: GY; False = none (a pit, the
  map's end). A point inside a wall climbs out of it first (at most 600 px), a floor under a roof lower than a
  soldier is passed by for the next one. }
function ShopGround(X, Y, Down: Single; out GY: Single): Boolean;

implementation

uses
  be_map, be_ballistic;

const
  STYLE_FLAME_SH = 5;

procedure Bisect(AX, AY, BX, BY: Single; Flags, Team: LongInt; out HX, HY: Single);
var
  Lo, Hi, Mid: Single;
  k: LongInt;
begin
  Lo := 0;
  Hi := 1;
  for k := 1 to 12 do
  begin
    Mid := (Lo + Hi) / 2;
    if MapRay(AX, AY, AX + (BX - AX) * Mid, AY + (BY - AY) * Mid, Flags, Team) then
      Hi := Mid
    else
      Lo := Mid;
  end;
  HX := AX + (BX - AX) * Hi;
  HY := AY + (BY - AY) * Hi;
end;

function ShopApPredict(Style: LongInt; X, Y, VX, VY: Single; MaxTicks, Team: LongInt; out HX, HY: Single): LongInt;
var
  PX, PY, NX, NY, G, SX, SY: Single;
  t: LongInt;
begin
  Result := -1;
  HX := X;
  HY := Y;
  if MaxTicks <= 0 then
    Exit;
  G := BulletGravity;
  if Style = STYLE_FLAME_SH then
    G := G - 0.15;
  PX := X;
  PY := Y;
  SX := VX;
  SY := VY;
  for t := 1 to MaxTicks do
  begin
    SY := SY + G;
    NX := PX + SX;
    NY := PY + SY;
    if MapRay(PX, PY, NX, NY, MR_BULLET, Team) then
    begin
      Bisect(PX, PY, NX, NY, MR_BULLET, Team, HX, HY);
      Result := t;
      Exit;
    end;
    PX := NX;
    PY := NY;
    SX := SX * 0.99;
    SY := SY * 0.99;
  end;
end;

function ShopGround(X, Y, Down: Single; out GY: Single): Boolean;
const
  { the room a crate and a soldier need over a floor }
  ROOM = 24;
var
  HX, HY, SY, EndY: Single;
  k, n: LongInt;
begin
  GY := Y;
  Result := False;
  if Down <= 0 then
    Exit;
  EndY := Y + Down;
  { inside a wall: up out of it }
  SY := Y;
  n := 0;
  while MapPointSolid(X, SY, MR_PLAYER, 0) and (n < 100) do
  begin
    SY := SY - 6;
    Inc(n);
  end;
  if MapPointSolid(X, SY, MR_PLAYER, 0) then
    Exit;
  for k := 1 to 4 do
  begin
    if SY >= EndY then
      Exit;
    if not MapRay(X, SY, X, EndY, MR_PLAYER, 0) then
      Exit;
    Bisect(X, SY, X, EndY, MR_PLAYER, 0, HX, HY);
    { room over the floor: done }
    if not MapRay(X, HY - 2, X, HY - ROOM, MR_PLAYER, 0) then
    begin
      GY := HY;
      Result := True;
      Exit;
    end;
    { a gap lower than a soldier: on under this floor }
    SY := HY + 2;
    n := 0;
    while MapPointSolid(X, SY, MR_PLAYER, 0) and (SY < EndY) and (n < 100) do
    begin
      SY := SY + 6;
      Inc(n);
    end;
  end;
end;

end.
