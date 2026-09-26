unit be_ballistic;

{$mode objfpc}{$H+}
{$Q-}{$R-}

interface

const
  WEAPONS = 17;
  STYLE_PLAIN = 1;
  STYLE_FRAGNADE = 2;
  STYLE_SHOTGUN = 3;
  STYLE_M79 = 4;
  STYLE_FLAME = 5;
  STYLE_PUNCH = 6;
  STYLE_ARROW = 7;
  STYLE_FLAMEARROW = 8;
  STYLE_CLUSTERNADE = 9;
  STYLE_CLUSTER = 10;
  STYLE_KNIFE = 11;
  STYLE_LAW = 12;
  STYLE_THROWNKNIFE = 13;
  FLAME_LIFE = 30;
  MAX_PATH = 256;
  MAX_SHOT = 16;
  MAX_INACCURACY = 0.5;
  SF_CROUCH = 1;
  SF_PRONE = 2;
  SF_AIRBORNE = 4;
  SF_RUNNING = 8;
  SF_JET = 16;
  SF_FLAG = 32;

type
  TWeaponStat = record
    Name: AnsiString;
    Damage, Speed, Spread, Inherit, MoveAcc, ModHead, ModChest, ModLegs: Single;
    Style, Interval, Ammo, Reload, StartUp, Bink: LongInt;
    Sound: AnsiString;
  end;

var
  Weapon: array[0..WEAPONS - 1] of TWeaponStat;
  BulletGravity: Single = 0.135;
  PathX, PathY: array[0..MAX_PATH - 1] of Single;
  PathCount: LongInt = 0;
  ShotX, ShotY, ShotVX, ShotVY: array[0..MAX_SHOT - 1] of Single;
  ShotCount: LongInt = 0;
  ShotPushX: Single = 0;
  ShotPushY: Single = 0;

procedure WeaponsDefault(Realistic: Boolean);
function WeaponsLoad(const Path: AnsiString; Realistic: Boolean): LongInt;
function ValidWeapon(W: LongInt): Boolean;
function ShotSpeed(W: LongInt): Single;
function ShotStyle(W: LongInt): LongInt;
function ShotDamage(W: LongInt): Single;
function BuildPath(W: LongInt; X, Y, VX, VY, AimX, AimY: Single; MaxTicks: LongInt; Spacing, MaxRange: Single): LongInt;
function BuildPathDir(W: LongInt; X, Y, DX, DY, VX, VY: Single; MaxTicks: LongInt; Spacing, MaxRange: Single): LongInt;
procedure Muzzle(X, Y, AimX, AimY: Single; Flags: LongInt; out OX, OY, DX, DY: Single);
function PathClip(CX, CY, HW, HH: Single): LongInt;
function Solve(W: LongInt; SX, SY, SVX, SVY, TX, TY, TVX, TVY, TGrav: Single; out DX, DY: Single;
  out Ticks: LongInt): Boolean;
function BuildShot(W: LongInt; SX, SY, SVX, SVY, DX, DY, Spread: Single; Seed, Flags: LongInt): LongInt;

implementation

uses
  Classes, SysUtils;

const
  IniNames: array[0..WEAPONS - 1] of AnsiString = ('USSOCOM', 'Desert Eagles', 'HK MP5', 'Ak-74', 'Steyr AUG',
    'Spas-12', 'Ruger 77', 'M79', 'Barret M82A1', 'FN Minimi', 'XM214 Minigun', 'Combat Knife', 'Chainsaw', 'M72 LAW',
    'Flamer', 'Rambo Bow', 'Flamed Arrows');
  Sounds: array[0..WEAPONS - 1] of AnsiString = ('colt1911-fire.wav', 'deserteagle-fire.wav', 'mp5-fire.wav',
    'ak74-fire.wav', 'steyraug-fire.wav', 'spas12-fire.wav', 'ruger77-fire.wav', 'm79-fire.wav', 'barretm82-fire.wav',
    'm249-fire.wav', 'minigun-fire.wav', 'throwgun.wav', 'chainsaw-r.wav', 'law.wav', 'flamer.wav', 'bow-fire.wav',
    'bow-fire.wav');
  NDamage: array[0..WEAPONS - 1] of Single = (1.49, 1.81, 1.01, 1.11, 0.71, 1.22, 2.49, 1550, 4.45, 0.85, 0.468,
    2150, 50, 1550, 19, 12, 8);
  NInterval: array[0..WEAPONS - 1] of LongInt = (10, 24, 6, 11, 7, 32, 39, 6, 225, 9, 3, 6, 2, 6, 6, 10, 10);
  NAmmo: array[0..WEAPONS - 1] of LongInt = (14, 7, 30, 40, 25, 7, 4, 1, 10, 50, 100, 1, 200, 1, 200, 1, 1);
  NReload: array[0..WEAPONS - 1] of LongInt = (60, 87, 105, 150, 125, 175, 84, 178, 70, 250, 480, 3, 110, 300, 5,
    25, 39);
  NSpeed: array[0..WEAPONS - 1] of Single = (18, 19, 18.9, 24, 26, 14, 33, 10.7, 55, 27, 29, 6, 8, 23, 10.5, 21, 18);
  NStyle: array[0..WEAPONS - 1] of LongInt = (1, 1, 1, 1, 1, 3, 1, 4, 1, 1, 1, 11, 11, 12, 5, 7, 8);
  NStartUp: array[0..WEAPONS - 1] of LongInt = (0, 0, 0, 0, 0, 0, 0, 0, 19, 0, 25, 0, 0, 13, 0, 0, 0);
  NSpread: array[0..WEAPONS - 1] of Single = (0, 0.15, 0.14, 0.09, 0.075, 0.8, 0, 0, 0, 0.064, 0.3, 0, 0, 0, 0, 0, 0);
  NInherit: array[0..WEAPONS - 1] of Single = (0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0, 0, 0.5, 0.5,
    0.5, 0.5);
  RDamage: array[0..WEAPONS - 1] of Single = (1.3, 1.66, 0.94, 1.08, 0.68, 1.2, 2.22, 1600, 4.95, 0.81, 0.43, 2250,
    21, 1500, 12, 12, 8);
  RInterval: array[0..WEAPONS - 1] of LongInt = (12, 27, 6, 11, 7, 35, 52, 6, 200, 10, 4, 6, 2, 30, 6, 10, 10);
  RAmmo: array[0..WEAPONS - 1] of LongInt = (12, 7, 30, 35, 30, 7, 4, 1, 10, 50, 100, 1, 200, 1, 200, 1, 1);
  RReload: array[0..WEAPONS - 1] of LongInt = (72, 106, 110, 158, 126, 175, 104, 173, 170, 261, 320, 3, 110, 495, 5,
    25, 39);
  RSpeed: array[0..WEAPONS - 1] of Single = (18, 19, 18.9, 24, 26, 13.2, 33, 11.4, 55, 27, 29, 6, 7.6, 23, 12.5, 21, 18);
  RStartUp: array[0..WEAPONS - 1] of LongInt = (0, 0, 0, 0, 0, 0, 0, 0, 16, 0, 33, 0, 0, 12, 0, 0, 0);
  RSpread: array[0..WEAPONS - 1] of Single = (0, 0.1, 0.03, 0, 0, 0.8, 0, 0, 0, 0, 0.1, 0, 0, 0, 0, 0, 0);
  NMoveAcc: array[0..WEAPONS - 1] of Single = (0, 0.009, 0, 0.011, 0, 0, 0.03, 0, 0.05, 0.013, 0.0625, 0, 0, 0, 0, 0,
    0);
  RMoveAcc: array[0..WEAPONS - 1] of Single = (0.02, 0.02, 0.01, 0.02, 0.01, 0.01, 0.03, 0.03, 0.07, 0.02, 0.01, 0.01,
    0.01, 0.01, 0.01, 0.01, 0.01);
  NBink: array[0..WEAPONS - 1] of LongInt = (0, 0, 0, -12, 0, 0, 0, 0, 65, 0, 0, 0, 0, 0, 0, 0, 0);
  RBink: array[0..WEAPONS - 1] of LongInt = (0, 0, -10, -10, -9, 0, 14, 45, 80, -8, -2, 0, 0, 0, 0, 0, 0);

var
  RandState: LongWord = 12345;

function Rnd: Single;
begin
  RandState := RandState * 1103515245 + 12345;
  Result := ((RandState shr 8) and $FFFF) / 65535;
end;

function ValidWeapon(W: LongInt): Boolean;
begin
  Result := (W >= 0) and (W < WEAPONS);
end;

procedure WeaponsDefault(Realistic: Boolean);
var
  i: LongInt;
begin
  for i := 0 to WEAPONS - 1 do
  begin
    Weapon[i].Name := IniNames[i];
    Weapon[i].Sound := Sounds[i];
    Weapon[i].Style := NStyle[i];
    Weapon[i].Inherit := NInherit[i];
    Weapon[i].ModHead := 1.1;
    Weapon[i].ModChest := 0.95;
    Weapon[i].ModLegs := 0.85;
    if Realistic then
    begin
      Weapon[i].Damage := RDamage[i];
      Weapon[i].Speed := RSpeed[i];
      Weapon[i].Spread := RSpread[i];
      Weapon[i].Interval := RInterval[i];
      Weapon[i].Ammo := RAmmo[i];
      Weapon[i].Reload := RReload[i];
      Weapon[i].StartUp := RStartUp[i];
      Weapon[i].MoveAcc := RMoveAcc[i];
      Weapon[i].Bink := RBink[i];
    end
    else
    begin
      Weapon[i].Damage := NDamage[i];
      Weapon[i].Speed := NSpeed[i];
      Weapon[i].Spread := NSpread[i];
      Weapon[i].Interval := NInterval[i];
      Weapon[i].Ammo := NAmmo[i];
      Weapon[i].Reload := NReload[i];
      Weapon[i].StartUp := NStartUp[i];
      Weapon[i].MoveAcc := NMoveAcc[i];
      Weapon[i].Bink := NBink[i];
    end;
  end;
end;

function ReadNum(const S: AnsiString; out V: Double): Boolean;
var
  Code: LongInt;
  T: AnsiString;
begin
  T := StringReplace(Trim(S), ',', '.', [rfReplaceAll]);
  Val(T, V, Code);
  Result := (Code = 0) and (T <> '');
end;

function WeaponsLoad(const Path: AnsiString; Realistic: Boolean): LongInt;
var
  L: TStringList;
  i, p, W, Found: LongInt;
  S, Sec, Key, Value, Version: AnsiString;
  V: Double;
  Old: Boolean;
  Keys: array[0..WEAPONS - 1] of TStringList;
begin
  Result := 0;
  WeaponsDefault(Realistic);
  if (Path = '') or not FileExists(Path) then
    Exit;
  L := TStringList.Create;
  for i := 0 to WEAPONS - 1 do
    Keys[i] := TStringList.Create;
  try
    try
      L.LoadFromFile(Path);
    except
      Exit;
    end;
    Sec := '';
    Version := '';
    W := -1;
    for i := 0 to L.Count - 1 do
    begin
      S := Trim(L[i]);
      if (S = '') or (S[1] = ';') or (S[1] = '#') then
        Continue;
      if S[1] = '[' then
      begin
        p := Pos(']', S);
        if p = 0 then
          p := Length(S) + 1;
        Sec := Trim(Copy(S, 2, p - 2));
        W := -1;
        for p := 0 to WEAPONS - 1 do
          if CompareText(IniNames[p], Sec) = 0 then
            W := p;
        if (W < 0) and (CompareText(Sec, 'Barrett M82A1') = 0) then
          W := 8;
        Continue;
      end;
      p := Pos('=', S);
      if p < 2 then
        Continue;
      Key := Trim(Copy(S, 1, p - 1));
      Value := Trim(Copy(S, p + 1, Length(S)));
      p := Pos(';', Value);
      if p > 0 then
        Value := Trim(Copy(Value, 1, p - 1));
      if (CompareText(Sec, 'Info') = 0) and (CompareText(Key, 'Version') = 0) then
        Version := Value;
      if W >= 0 then
        Keys[W].Values[LowerCase(Key)] := Value;
    end;
    Old := False;
    if Version <> '' then
      Old := CompareText(Copy(Version, 1, 5), '1.7.1') < 0
    else if ReadNum(Keys[1].Values['speed'], V) then
      Old := V > 100;
    Found := 0;
    for W := 0 to WEAPONS - 1 do
    begin
      if Keys[W].Count = 0 then
        Continue;
      Inc(Found);
      if ReadNum(Keys[W].Values['damage'], V) then
        if Old then
          Weapon[W].Damage := V / 100
        else
          Weapon[W].Damage := V;
      if ReadNum(Keys[W].Values['speed'], V) then
        if Old then
          Weapon[W].Speed := V / 10
        else
          Weapon[W].Speed := V;
      if ReadNum(Keys[W].Values['bulletspread'], V) then
        if Old then
          Weapon[W].Spread := V / 100
        else
          Weapon[W].Spread := V;
      if ReadNum(Keys[W].Values['inheritedvelocity'], V) then
        if Old then
          Weapon[W].Inherit := V / 100
        else
          Weapon[W].Inherit := V;
      if ReadNum(Keys[W].Values['fireinterval'], V) then
        Weapon[W].Interval := Round(V);
      if ReadNum(Keys[W].Values['ammo'], V) then
        Weapon[W].Ammo := Round(V);
      if ReadNum(Keys[W].Values['reloadtime'], V) then
        Weapon[W].Reload := Round(V);
      if ReadNum(Keys[W].Values['bulletstyle'], V) then
        Weapon[W].Style := Round(V);
      if ReadNum(Keys[W].Values['startuptime'], V) then
        Weapon[W].StartUp := Round(V);
      if ReadNum(Keys[W].Values['movementacc'], V) then
        if Old and (V >= 1) then
          Weapon[W].MoveAcc := V / 1000
        else
          Weapon[W].MoveAcc := V;
      if ReadNum(Keys[W].Values['bink'], V) then
        Weapon[W].Bink := Round(V);
      if ReadNum(Keys[W].Values['modifierhead'], V) then
        Weapon[W].ModHead := V;
      if ReadNum(Keys[W].Values['modifierchest'], V) then
        Weapon[W].ModChest := V;
      if ReadNum(Keys[W].Values['modifierlegs'], V) then
        Weapon[W].ModLegs := V;
    end;
    Result := Found;
  finally
    for i := 0 to WEAPONS - 1 do
      Keys[i].Free;
    L.Free;
  end;
end;

function ShotStyle(W: LongInt): LongInt;
begin
  Result := STYLE_PLAIN;
  if not ValidWeapon(W) then
    Exit;
  Result := Weapon[W].Style;
  if (Result = STYLE_KNIFE) or (Result = STYLE_PUNCH) then
    Result := STYLE_THROWNKNIFE;
end;

function ShotSpeed(W: LongInt): Single;
begin
  Result := 18;
  if not ValidWeapon(W) then
    Exit;
  Result := Weapon[W].Speed;
  if (Weapon[W].Style = STYLE_KNIFE) or (Weapon[W].Style = STYLE_PUNCH) then
    Result := Weapon[11].Speed * 1.5;
  if Result < 1 then
    Result := 1;
end;

function ShotDamage(W: LongInt): Single;
begin
  Result := 1;
  if not ValidWeapon(W) then
    Exit;
  Result := Weapon[W].Damage;
  if (Weapon[W].Style = STYLE_KNIFE) or (Weapon[W].Style = STYLE_PUNCH) then
    Result := Weapon[11].Damage;
end;

function StyleLift(Style: LongInt): Single;
begin
  Result := 0;
  if Style = STYLE_FLAME then
    Result := 0.15;
end;

procedure Muzzle(X, Y, AimX, AimY: Single; Flags: LongInt; out OX, OY, DX, DY: Single);
var
  Dir, SX, SY, BX, BY, D, HX, HY: Single;
begin
  if AimX >= X then
    Dir := 1
  else
    Dir := -1;
  if (Flags and SF_PRONE) <> 0 then
  begin
    SX := 2.5;
    SY := -1.6;
  end
  else if (Flags and SF_CROUCH) <> 0 then
  begin
    SX := -2.1;
    SY := -5.9;
  end
  else
  begin
    SX := -1.7;
    SY := -11.4;
  end;
  SX := X + Dir * SX;
  SY := Y + SY;
  BX := AimX - SX;
  BY := AimY - SY;
  D := Sqrt(BX * BX + BY * BY);
  if D < 0.001 then
  begin
    BX := Dir;
    BY := 0;
    D := 1;
  end;
  HX := SX + 7 * BX / D;
  HY := SY + 7 * BY / D;
  BX := AimX - HX;
  BY := AimY - HY;
  D := Sqrt(BX * BX + BY * BY);
  if D < 0.001 then
  begin
    DX := Dir;
    DY := 0;
  end
  else
  begin
    DX := BX / D;
    DY := BY / D;
  end;
  OX := HX - 4 * DX;
  OY := HY - 4 * DY - 2;
end;

function BuildPathDir(W: LongInt; X, Y, DX, DY, VX, VY: Single; MaxTicks: LongInt; Spacing, MaxRange: Single): LongInt;
var
  Sp, BX, BY, BVX, BVY, G, Walk, NextAt, SegL, F: Single;
  t: LongInt;
begin
  PathCount := 0;
  Result := 0;
  if not ValidWeapon(W) then
    Exit;
  if Spacing < 2 then
    Spacing := 2;
  Sp := ShotSpeed(W);
  BVX := DX * Sp + VX * Weapon[W].Inherit;
  BVY := DY * Sp + VY * Weapon[W].Inherit;
  BX := X;
  BY := Y;
  G := BulletGravity - StyleLift(Weapon[W].Style);
  if Weapon[W].Style = STYLE_FLAME then
    if MaxTicks > FLAME_LIFE then
      MaxTicks := FLAME_LIFE;
  PathX[0] := BX;
  PathY[0] := BY;
  PathCount := 1;
  Walk := 0;
  NextAt := Spacing;
  for t := 1 to MaxTicks do
  begin
    BVY := BVY + G;
    SegL := Sqrt(BVX * BVX + BVY * BVY);
    while (SegL > 0.0001) and (Walk + SegL >= NextAt) and (PathCount < MAX_PATH) do
    begin
      F := (NextAt - Walk) / SegL;
      PathX[PathCount] := BX + BVX * F;
      PathY[PathCount] := BY + BVY * F;
      Inc(PathCount);
      NextAt := NextAt + Spacing;
    end;
    Walk := Walk + SegL;
    BX := BX + BVX;
    BY := BY + BVY;
    BVX := BVX * 0.99;
    BVY := BVY * 0.99;
    if (PathCount >= MAX_PATH) or (Walk >= MaxRange) then
      Break;
  end;
  Result := PathCount;
end;

function BuildPath(W: LongInt; X, Y, VX, VY, AimX, AimY: Single; MaxTicks: LongInt; Spacing, MaxRange: Single): LongInt;
var
  DX, DY, D: Single;
begin
  PathCount := 0;
  Result := 0;
  if not ValidWeapon(W) then
    Exit;
  DX := AimX - X;
  DY := AimY - Y;
  D := Sqrt(DX * DX + DY * DY);
  if D < 0.001 then
  begin
    DX := 1;
    DY := 0;
    D := 1;
  end;
  Result := BuildPathDir(W, X, Y, DX / D, DY / D, VX, VY, MaxTicks, Spacing, MaxRange);
end;

function PathClip(CX, CY, HW, HH: Single): LongInt;
var
  i: LongInt;
  Inside: Boolean;
begin
  Result := PathCount;
  if (HW <= 0) or (HH <= 0) then
    Exit;
  Inside := False;
  for i := 0 to PathCount - 1 do
    if (Abs(PathX[i] - CX) <= HW) and (Abs(PathY[i] - CY) <= HH) then
      Inside := True
    else if Inside then
    begin
      PathCount := i + 1;
      Result := PathCount;
      Exit;
    end;
  if not Inside then
  begin
    if PathCount > 1 then
      PathCount := 1;
    Result := PathCount;
  end;
end;

procedure Simulate(W: LongInt; SX, SY, BVX, BVY, TX, TY, TVX, TVY, TGrav: Single; MaxT: LongInt;
  out BestT: LongInt; out EX, EY: Single);
var
  t: LongInt;
  BX, BY, PX, PY, PVX, PVY, G, RX0, RY0, RX1, RY1, SX1, SY1, S, L2, DX, DY, D2, Best: Single;
begin
  BX := SX;
  BY := SY;
  PX := TX;
  PY := TY;
  PVX := TVX;
  PVY := TVY;
  G := BulletGravity - StyleLift(Weapon[W].Style);
  Best := 1E30;
  BestT := 0;
  EX := TX - SX;
  EY := TY - SY;
  RX0 := PX - BX;
  RY0 := PY - BY;
  for t := 1 to MaxT do
  begin
    BVY := BVY + G;
    BX := BX + BVX;
    BY := BY + BVY;
    BVX := BVX * 0.99;
    BVY := BVY * 0.99;
    PVY := PVY + TGrav;
    PX := PX + PVX;
    PY := PY + PVY;
    if TGrav <> 0 then
    begin
      PVX := PVX * 0.99;
      PVY := PVY * 0.99;
    end;
    RX1 := PX - BX;
    RY1 := PY - BY;
    SX1 := RX1 - RX0;
    SY1 := RY1 - RY0;
    L2 := SX1 * SX1 + SY1 * SY1;
    S := 1;
    if L2 > 0.000001 then
    begin
      S := -(RX0 * SX1 + RY0 * SY1) / L2;
      if S < 0 then
        S := 0;
      if S > 1 then
        S := 1;
    end;
    DX := RX0 + SX1 * S;
    DY := RY0 + SY1 * S;
    D2 := DX * DX + DY * DY;
    if D2 < Best then
    begin
      Best := D2;
      BestT := t;
      EX := DX;
      EY := DY;
    end
    else if D2 > Best * 4 + 10000 then
      Break;
    RX0 := RX1;
    RY0 := RY1;
  end;
end;

function Solve(W: LongInt; SX, SY, SVX, SVY, TX, TY, TVX, TVY, TGrav: Single; out DX, DY: Single;
  out Ticks: LongInt): Boolean;
var
  AX, AY, L, Sp, EX, EY, Inh: Single;
  i, BT, MaxT: LongInt;
begin
  Result := False;
  DX := 1;
  DY := 0;
  Ticks := 0;
  EX := 0;
  EY := 0;
  if not ValidWeapon(W) then
    Exit;
  Sp := ShotSpeed(W);
  Inh := Weapon[W].Inherit;
  AX := TX - SX;
  AY := TY - SY;
  L := Sqrt(AX * AX + AY * AY);
  if L < 0.001 then
    Exit;
  MaxT := Round(L / Sp * 3) + 30;
  if MaxT > 400 then
    MaxT := 400;
  if Weapon[W].Style = STYLE_FLAME then
    MaxT := FLAME_LIFE;
  for i := 1 to 32 do
  begin
    L := Sqrt(AX * AX + AY * AY);
    if L < 0.001 then
      Break;
    DX := AX / L;
    DY := AY / L;
    Simulate(W, SX, SY, DX * Sp + SVX * Inh, DY * Sp + SVY * Inh, TX, TY, TVX, TVY, TGrav, MaxT, BT, EX, EY);
    Ticks := BT;
    if EX * EX + EY * EY < 1 then
    begin
      Result := True;
      Exit;
    end;
    AX := AX + EX;
    AY := AY + EY;
  end;
  Result := EX * EX + EY * EY < 9;
end;

function BuildShot(W: LongInt; SX, SY, SVX, SVY, DX, DY, Spread: Single; Seed, Flags: LongInt): LongInt;
var
  i, n: LongInt;
  Sp, Inh, BX, BY, L, SpreadW, Inacc, MaxDev: Single;
  Pellets: Boolean;
begin
  ShotCount := 0;
  ShotPushX := 0;
  ShotPushY := 0;
  Result := 0;
  if not ValidWeapon(W) then
    Exit;
  RandState := LongWord(Seed) * 2654435761 + 1;
  if Spread < 0 then
    Spread := 0;
  Sp := ShotSpeed(W);
  Inh := Weapon[W].Inherit;
  L := Sqrt(DX * DX + DY * DY);
  if L < 0.0001 then
    Exit;
  DX := DX / L;
  DY := DY / L;
  Pellets := (Weapon[W].Style = STYLE_SHOTGUN) or (W = 1);
  Inacc := 0;
  if (Flags and SF_RUNNING) <> 0 then
    Inacc := Weapon[W].MoveAcc * 7
  else if (Flags and SF_AIRBORNE) <> 0 then
    Inacc := Weapon[W].MoveAcc * 3;
  if not Pellets then
    if Weapon[W].Spread > 0 then
    begin
      if (Flags and SF_PRONE) <> 0 then
        Inacc := Inacc + Weapon[W].Spread / 1.625
      else if (Flags and SF_CROUCH) <> 0 then
        Inacc := Inacc + Weapon[W].Spread / 1.3
      else
        Inacc := Inacc + Weapon[W].Spread;
    end;
  Inacc := Inacc * 0.25 * Spread;
  if Inacc > MAX_INACCURACY then
    Inacc := MAX_INACCURACY;
  if Inacc > 0 then
  begin
    MaxDev := MAX_INACCURACY * Sin(Inacc / MAX_INACCURACY * Pi / 2);
    DX := DX + (Rnd * 2 - 1) * MaxDev;
    DY := DY + (Rnd * 2 - 1) * MaxDev;
    L := Sqrt(DX * DX + DY * DY);
    if L > 0.0001 then
    begin
      DX := DX / L;
      DY := DY / L;
    end;
  end;
  BX := DX * Sp + SVX * Inh;
  BY := DY * Sp + SVY * Inh;
  if Weapon[W].Style = STYLE_SHOTGUN then
  begin
    ShotPushX := -BX * 0.0412;
    ShotPushY := -BY * 0.041;
  end
  else if W = 10 then
  begin
    if (Flags and SF_JET) <> 0 then
    begin
      ShotPushX := BX * 0.0012;
      ShotPushY := BY * 0.0009;
    end
    else
    begin
      ShotPushX := BX * 0.0082;
      ShotPushY := BY * 0.0078;
    end;
    if (Flags and SF_FLAG) <> 0 then
    begin
      ShotPushX := ShotPushX * 0.5;
      ShotPushY := ShotPushY * 0.7;
    end;
    ShotPushX := -ShotPushX * 0.6;
    ShotPushY := -ShotPushY;
  end;
  n := 1;
  SpreadW := 0;
  if Weapon[W].Style = STYLE_SHOTGUN then
  begin
    n := 6;
    SpreadW := Weapon[W].Spread * Spread;
  end
  else if W = 1 then
  begin
    n := 2;
    SpreadW := Weapon[W].Spread * Spread;
  end;
  for i := 0 to n - 1 do
  begin
    ShotX[i] := SX;
    ShotY[i] := SY;
    if (W = 1) and (i = 1) then
    begin
      ShotX[i] := SX - DY * 3;
      ShotY[i] := SY + DX * 3;
    end;
    ShotVX[i] := BX + (Rnd * 2 - 1) * SpreadW;
    ShotVY[i] := BY + (Rnd * 2 - 1) * SpreadW;
  end;
  ShotCount := n;
  Result := n;
end;

initialization
  WeaponsDefault(False);
end.
