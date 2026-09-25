unit be_fx;

{$mode objfpc}{$H+}
{$Q-}{$R-}

interface

const
  FX_PLAIN = 0;
  FX_BIG = 1;
  FX_NUKE = 2;
  FX_LAW = 3;
  FX_M79 = 4;
  FX_ARROWS = 5;
  FX_FIREARROWS = 6;
  FX_BULLETS = 7;
  FX_SPAS = 8;
  FX_FLAME = 9;
  FX_CLUSTER = 10;
  FX_NADES = 11;
  FX_KNIVES = 12;
  FX_RAIN = 13;
  FX_LAST = 13;
  MAX_FX = 256;

type
  TFxBullet = record
    DX, DY, VX, VY, HitM: Single;
    Style, Delay: LongInt;
  end;

var
  Fx: array[0..MAX_FX - 1] of TFxBullet;
  FxCount: LongInt = 0;

function FxBuild(Kind, Seed: LongInt; Power: Single): LongInt;

implementation

var
  Rs: LongWord = 1;

function Rnd: Single;
begin
  Rs := Rs * 1103515245 + 12345;
  Result := ((Rs shr 8) and $FFFF) / 65535;
end;

procedure Add(DX, DY, VX, VY, HitM: Single; Style, Delay: LongInt);
begin
  if FxCount >= MAX_FX then
    Exit;
  Fx[FxCount].DX := DX;
  Fx[FxCount].DY := DY;
  Fx[FxCount].VX := VX;
  Fx[FxCount].VY := VY;
  Fx[FxCount].HitM := HitM;
  Fx[FxCount].Style := Style;
  Fx[FxCount].Delay := Delay;
  Inc(FxCount);
end;

procedure Ring(N: LongInt; R, Speed, HitM: Single; Style, Delay: LongInt; Inward: Boolean; Phase, LiftY: Single);
var
  i: LongInt;
  A, CX, CY: Single;
begin
  for i := 0 to N - 1 do
  begin
    A := 2 * Pi * i / N + Phase;
    CX := Cos(A);
    CY := Sin(A);
    if Inward then
      Add(CX * R, CY * R - LiftY, -CX * Speed, -CY * Speed, HitM, Style, Delay)
    else
      Add(CX * R, CY * R - LiftY, CX * Speed, CY * Speed, HitM, Style, Delay);
  end;
end;

function FxBuild(Kind, Seed: LongInt; Power: Single): LongInt;
var
  i: LongInt;
  A, S: Single;
begin
  FxCount := 0;
  Rs := LongWord(Seed) * 2654435761 + 7;
  if Power <= 0 then
    Power := 1;
  case Kind of
    FX_PLAIN:
      Add(0, 0, 0, 0, 1000 * Power, 4, 0);
    FX_BIG:
      begin
        Add(0, -2, 0, 0, 1500 * Power, 4, 0);
        Ring(8, 40, 1.5, 1300 * Power, 4, 2, False, 0, 8);
        for i := 0 to 9 do
        begin
          A := -Pi / 2 + (Rnd - 0.5) * 2.2;
          S := 5 + Rnd * 4;
          Add(0, -14, Cos(A) * S, Sin(A) * S, 60 * Power, 10, 5);
        end;
        Ring(12, 12, 4, 19, 5, 7, False, 0.2, 12);
        Ring(8, 90, 1, 1300 * Power, 4, 11, False, Pi / 8, 8);
      end;
    FX_NUKE:
      begin
        Add(0, -2, 0, 0, 2000 * Power, 4, 0);
        Ring(8, 60, 0.5, 1500 * Power, 4, 6, False, 0, 10);
        Ring(12, 120, 0.5, 1500 * Power, 4, 14, False, Pi / 12, 10);
        Ring(16, 190, 0.5, 1500 * Power, 4, 24, False, 0, 10);
        for i := 0 to 5 do
          Add((i - 2.5) * 70, -420, 0, 12, 1550 * Power, 12, i * 5);
        for i := 0 to 15 do
        begin
          A := -Pi / 2 + (Rnd - 0.5) * 2.6;
          S := 6 + Rnd * 5;
          Add(0, -16, Cos(A) * S, Sin(A) * S, 60 * Power, 10, 8 + i mod 4);
        end;
        Ring(20, 16, 5, 19, 5, 18, False, 0, 14);
      end;
    FX_LAW:
      Ring(6, 260, 10, 1550 * Power, 12, 0, True, -Pi / 2, 10);
    FX_M79:
      for i := 0 to 4 do
        Add((Rnd - 0.5) * 120, -190, (Rnd - 0.5) * 1.5, 6, 1550 * Power, 4, i * 4);
    FX_ARROWS:
      Ring(16, 280, 12, 12 * Power, 7, 0, True, 0, 10);
    FX_FIREARROWS:
      Ring(12, 260, 11, 8 * Power, 8, 0, True, Pi / 12, 10);
    FX_BULLETS:
      Ring(24, 350, 16, 2.5 * Power, 1, 0, True, 0, 10);
    FX_SPAS:
      for i := 0 to 31 do
      begin
        A := Pi / 4 + (i div 8) * Pi / 2;
        Add(Cos(A) * 300 + (Rnd - 0.5) * 16, Sin(A) * 300 - 10 + (Rnd - 0.5) * 16,
          -Cos(A) * 13 + (Rnd - 0.5) * 1.6, -Sin(A) * 13 + (Rnd - 0.5) * 1.6, 1.8 * Power, 3, (i div 8) * 6);
      end;
    FX_FLAME:
      for i := 0 to 23 do
      begin
        A := 2 * Pi * i / 24;
        S := 3 + Rnd * 4;
        Add(0, -12, Cos(A) * S, Sin(A) * S - 1, 19 * Power, 5, i div 4);
      end;
    FX_CLUSTER:
      begin
        Add(0, -24, 0, 1, 1500 * Power, 9, 0);
        for i := 0 to 11 do
        begin
          A := -Pi / 2 + (Rnd - 0.5) * 3;
          S := 3 + Rnd * 5;
          Add(0, -20, Cos(A) * S, Sin(A) * S, 60 * Power, 10, 2 + i mod 3);
        end;
      end;
    FX_NADES:
      for i := 0 to 7 do
      begin
        A := -Pi / 2 + (i - 3.5) * 0.35;
        Add(0, -24, Cos(A) * 3, Sin(A) * 3, 1500 * Power, 2, i);
      end;
    FX_KNIVES:
      Ring(12, 240, 10, 2150 * Power, 13, 0, True, 0, 12);
    FX_RAIN:
      for i := 0 to 29 do
        Add((Rnd - 0.5) * 300, -420 - Rnd * 60, (Rnd - 0.5) * 1.5, 18, 2 * Power, 1, (i * 4) div 3);
  end;
  Result := FxCount;
end;

end.
