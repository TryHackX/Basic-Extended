unit be_gun;

{$mode objfpc}{$H+}

interface

const
  TM_CURSOR = 0;
  TM_NEAREST = 1;

function GunTick(ID, Tick, W, Trigger, Infinite: LongInt): LongInt;
procedure GunFired(ID, Tick: LongInt);
procedure GunReset(ID: LongInt);
function GunAmmo(ID: LongInt): LongInt;
function GunTargets(Shooter, Mode: LongInt; MaxDist, MaxAngle: Single): LongInt;
function GunTarget(Index: LongInt): LongInt;

implementation

uses
  be_world, be_ballistic;

type
  TGunner = record
    W, Ammo, NextShot, ReloadEnd, StartUpEnd: LongInt;
    Holding, Ready: Boolean;
  end;

var
  Gunners: array[1..BE_PLAYERS] of TGunner;
  Cand: array[0..BE_PLAYERS - 1] of LongInt;
  CandCount: LongInt = 0;

procedure GunReset(ID: LongInt);
begin
  if ValidID(ID) then
    FillChar(Gunners[ID], SizeOf(TGunner), 0);
end;

function GunAmmo(ID: LongInt): LongInt;
begin
  Result := 0;
  if ValidID(ID) then
    Result := Gunners[ID].Ammo;
end;

function GunTick(ID, Tick, W, Trigger, Infinite: LongInt): LongInt;
var
  G: ^TGunner;
begin
  Result := 0;
  if not ValidID(ID) or not ValidWeapon(W) then
    Exit;
  G := @Gunners[ID];
  if (not G^.Ready) or (G^.W <> W) then
  begin
    G^.Ready := True;
    G^.W := W;
    G^.Ammo := Weapon[W].Ammo;
    if G^.Ammo < 1 then
      G^.Ammo := 1;
    G^.ReloadEnd := 0;
    G^.NextShot := Tick;
    G^.Holding := False;
  end;
  if Trigger = 0 then
  begin
    G^.Holding := False;
    Exit;
  end;
  if not G^.Holding then
  begin
    G^.Holding := True;
    G^.StartUpEnd := Tick + Weapon[W].StartUp;
  end;
  if Tick < G^.ReloadEnd then
    Exit;
  if (G^.Ammo <= 0) and (Infinite = 0) then
  begin
    G^.Ammo := Weapon[W].Ammo;
    if G^.Ammo < 1 then
      G^.Ammo := 1;
    G^.ReloadEnd := Tick + Weapon[W].Reload;
    Result := 2;
    Exit;
  end;
  if (Tick >= G^.StartUpEnd) and (Tick >= G^.NextShot) then
    Result := 1;
end;

procedure GunFired(ID, Tick: LongInt);
var
  G: ^TGunner;
  I: LongInt;
begin
  if not ValidID(ID) then
    Exit;
  G := @Gunners[ID];
  if not ValidWeapon(G^.W) then
    Exit;
  I := Weapon[G^.W].Interval;
  if I < 1 then
    I := 1;
  G^.NextShot := Tick + I;
  Dec(G^.Ammo);
end;

function GunTargets(Shooter, Mode: LongInt; MaxDist, MaxAngle: Single): LongInt;
var
  b, i, j, t: LongInt;
  SX, SY, AX, AY, AL, DX, DY, D, Cs, MinCos: Single;
  Key: array[0..BE_PLAYERS - 1] of Single;
  kv: Single;
begin
  CandCount := 0;
  Result := 0;
  if not ValidID(Shooter) or not WP[Shooter].Alive then
    Exit;
  SX := WP[Shooter].X;
  SY := WP[Shooter].Y;
  AX := WP[Shooter].AimX - SX;
  AY := WP[Shooter].AimY - SY;
  AL := Sqrt(AX * AX + AY * AY);
  MinCos := Cos(MaxAngle * Pi / 180);
  for b := 1 to BE_PLAYERS do
  begin
    if (b = Shooter) or not WP[b].Alive or (WP[b].Team = TEAM_SPEC) then
      Continue;
    if not Enemies(Shooter, b) then
      Continue;
    DX := WP[b].X - SX;
    DY := WP[b].Y - SY;
    D := Sqrt(DX * DX + DY * DY);
    if D > MaxDist then
      Continue;
    Cs := 1;
    if (AL > 0.5) and (D > 0.5) then
      Cs := (DX * AX + DY * AY) / (D * AL);
    if (Mode = TM_CURSOR) and (MaxAngle < 180) and (Cs < MinCos) then
      Continue;
    if Mode = TM_CURSOR then
      kv := (1 - Cs) * 1000 + D * 0.05
    else
      kv := D;
    Cand[CandCount] := b;
    Key[CandCount] := kv;
    Inc(CandCount);
  end;
  for i := 1 to CandCount - 1 do
  begin
    t := Cand[i];
    kv := Key[i];
    j := i - 1;
    while (j >= 0) and (Key[j] > kv) do
    begin
      Cand[j + 1] := Cand[j];
      Key[j + 1] := Key[j];
      Dec(j);
    end;
    Cand[j + 1] := t;
    Key[j + 1] := kv;
  end;
  Result := CandCount;
end;

function GunTarget(Index: LongInt): LongInt;
begin
  Result := 0;
  if (Index >= 0) and (Index < CandCount) then
    Result := Cand[Index];
end;

end.
