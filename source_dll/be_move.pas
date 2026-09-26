unit be_move;

{$mode objfpc}{$H+}

interface

const
  TP_OFF = 0;
  TP_JUMP = 1;
  TP_MOMENTUM = 2;
  TP_FLY = 3;
  VAR_FIXED = 0;
  VAR_INHERIT = 1;
  MA_MOVE = 1;
  MA_VELOCITY = 2;
  MA_TAP = 4;
  MA_BLOCKED = 8;
  MO_NO_WALLS = 1;

  MF_MOM_BASE = 1;
  MF_MOM_PER_PIXEL = 2;
  MF_MOM_KEEP = 3;
  MF_MOM_MAX = 4;
  MF_HOLD_TICKS = 5;
  MF_HOP_TICKS = 6;
  MF_HOP_MIN = 7;
  MF_GAIN = 8;
  MF_VMAX = 9;
  MF_PUSH_TICKS = 10;
  MF_FLY_BASE = 11;
  MF_FLY_PER_PIXEL = 12;
  MF_FLY_MAX = 13;
  MF_FLY_EVERY = 14;
  MF_FLY_DEAD = 15;
  MF_FLY_SMOOTH = 16;
  MF_GRAVITY = 17;
  MF_ACCEL = 19;
  MF_STEER = 20;
  MF_HOP_MAX = 21;
  MF_FLY_HOP_TICKS = 22;
  MF_FLY_HOP_MAX = 23;
  MF_FLY_VEL_MAX = 24;

procedure MoveSet(Key: LongInt; Value: Single);
function MoveStep(ID, Tick, Mode, Variant, Key, Alive, Ping, Team, Opts: LongInt; X, Y, VX, VY: Single;
  AimX, AimY: LongInt; out OX, OY, OVX, OVY: Single): LongInt;
procedure MoveBlocked(ID, Tick: LongInt);
procedure MoveReset(ID: LongInt);

implementation

uses
  be_world, be_map;

const
  HOP_SLOTS = 6;
  CAM_KEEP = 0.86;
  VEL_LAG = 6.143;
  AXIS_MAX = 11;

type
  THop = record
    T: LongInt;
    DX, DY: Single;
  end;

  TMover = record
    Mode, Variant: LongInt;
    KeyWas, Continuous, Started: Boolean;
    Hold, LastHop, NextPush, NextFly, HopNext: LongInt;
    DirX, DirY, Speed, CmdX, CmdY, PredX, PredY, Owed: Single;
    PredTick: LongInt;
    Hops: array[0..HOP_SLOTS - 1] of THop;
  end;

var
  Movers: array[1..BE_PLAYERS] of TMover;
  MomBase: Single = 2;
  MomPerPixel: Single = 0.008;
  MomKeep: Single = 1;
  MomMax: Single = 11;
  HoldTicks: Single = 15;
  HopTicks: Single = 6;
  HopMin: Single = 24;
  Gain: Single = 0.6;
  Vmax: Single = 9;
  PushTicks: Single = 3;
  FlyBase: Single = 1.5;
  FlyPerPixel: Single = 0.04;
  FlyMax: Single = 11;
  FlyEvery: Single = 2;
  FlyDead: Single = 8;
  FlySmooth: Single = 0.5;
  Gravity: Single = 0.06;
  Accel: Single = 4;
  Steer: Single = 0.3;
  HopMax: Single = 600;
  FlyHopTicks: Single = 4;
  FlyHopMax: Single = 160;
  FlyVelMax: Single = 11;

procedure MoveSet(Key: LongInt; Value: Single);
begin
  case Key of
    MF_MOM_BASE: MomBase := Value;
    MF_MOM_PER_PIXEL: MomPerPixel := Value;
    MF_MOM_KEEP: MomKeep := Value;
    MF_MOM_MAX: MomMax := Value;
    MF_HOLD_TICKS: HoldTicks := Value;
    MF_HOP_TICKS: HopTicks := Value;
    MF_HOP_MIN: HopMin := Value;
    MF_GAIN: Gain := Value;
    MF_VMAX: Vmax := Value;
    MF_PUSH_TICKS: PushTicks := Value;
    MF_FLY_BASE: FlyBase := Value;
    MF_FLY_PER_PIXEL: FlyPerPixel := Value;
    MF_FLY_MAX: FlyMax := Value;
    MF_FLY_EVERY: FlyEvery := Value;
    MF_FLY_DEAD: FlyDead := Value;
    MF_FLY_SMOOTH: FlySmooth := Value;
    MF_GRAVITY: Gravity := Value;
    MF_ACCEL: Accel := Value;
    MF_STEER: Steer := Value;
    MF_HOP_MAX: HopMax := Value;
    MF_FLY_HOP_TICKS: FlyHopTicks := Value;
    MF_FLY_HOP_MAX: FlyHopMax := Value;
    MF_FLY_VEL_MAX: FlyVelMax := Value;
  end;
end;

procedure MoveReset(ID: LongInt);
begin
  if not ValidID(ID) then
    Exit;
  FillChar(Movers[ID], SizeOf(TMover), 0);
  Movers[ID].KeyWas := True;
end;

procedure MoveBlocked(ID, Tick: LongInt);
begin
  if not ValidID(ID) then
    Exit;
  Movers[ID].LastHop := Tick;
end;

function Clamp(V, Lo, Hi: Single): Single;
begin
  Result := V;
  if Result < Lo then
    Result := Lo;
  if Result > Hi then
    Result := Hi;
end;

procedure LimitSpeed(var X, Y: Single; Max: Single);
var
  L: Single;
begin
  L := Sqrt(X * X + Y * Y);
  if (L > Max) and (L > 0.0001) then
  begin
    X := X / L * Max;
    Y := Y / L * Max;
  end;
end;

procedure ClampAxes(var X, Y: Single);
begin
  X := Clamp(X, -AXIS_MAX, AXIS_MAX);
  Y := Clamp(Y, -AXIS_MAX, AXIS_MAX);
end;

procedure AddHop(var M: TMover; Tick: LongInt; DX, DY: Single);
begin
  M.Hops[M.HopNext].T := Tick;
  M.Hops[M.HopNext].DX := DX;
  M.Hops[M.HopNext].DY := DY;
  M.HopNext := (M.HopNext + 1) mod HOP_SLOTS;
end;

procedure HopLag(const M: TMover; Tick, Lag: LongInt; out LX, LY: Single);
var
  k, n: LongInt;
  F: Single;
begin
  LX := 0;
  LY := 0;
  for k := 0 to HOP_SLOTS - 1 do
    if M.Hops[k].T <> 0 then
    begin
      n := Tick - M.Hops[k].T - Lag;
      if (n >= 0) and (n < 60) then
      begin
        F := Exp(n * Ln(CAM_KEEP));
        LX := LX + M.Hops[k].DX * F;
        LY := LY + M.Hops[k].DY * F;
      end;
    end;
end;

function Solid(X, Y: Single; Team, Opts: LongInt): Boolean;
begin
  Result := ((Opts and MO_NO_WALLS) <> 0) and MapReady and MapPointSolid(X, Y - 10, MR_PLAYER, Team);
end;

function MoveStep(ID, Tick, Mode, Variant, Key, Alive, Ping, Team, Opts: LongInt; X, Y, VX, VY: Single;
  AimX, AimY: LongInt; out OX, OY, OVX, OVY: Single): LongInt;
var
  M: ^TMover;
  Down, Press: Boolean;
  DX, DY, D, Sp, TX, TY, NX, NY, L, Comp, LX, LY, HX, HY, IX, IY: Single;
  Lag: LongInt;
begin
  Result := 0;
  OX := 0;
  OY := 0;
  OVX := 0;
  OVY := 0;
  if not ValidID(ID) then
    Exit;
  M := @Movers[ID];
  if (not M^.Started) or (M^.Mode <> Mode) or (M^.Variant <> Variant) then
  begin
    FillChar(M^, SizeOf(TMover), 0);
    M^.Started := True;
    M^.Mode := Mode;
    M^.Variant := Variant;
    M^.KeyWas := True;
  end;
  Down := Key <> 0;
  Press := Down and not M^.KeyWas;
  M^.KeyWas := Down;
  if Down then
    Inc(M^.Hold)
  else
  begin
    M^.Hold := 0;
    M^.Continuous := False;
  end;
  if Alive = 0 then
    Exit;
  Lag := Round(Clamp(Ping, 0, 1000) * 0.06);
  case Mode of
    TP_JUMP:
      if Press then
      begin
        OX := AimX;
        OY := AimY;
        if Solid(OX, OY, Team, Opts) then
        begin
          Result := MA_BLOCKED or MA_TAP;
          Exit;
        end;
        Result := MA_MOVE or MA_VELOCITY or MA_TAP;
      end;
    TP_MOMENTUM:
      begin
        if Press then
        begin
          DX := AimX - X;
          DY := AimY - Y;
          D := Sqrt(DX * DX + DY * DY);
          OX := AimX;
          OY := AimY;
          if Solid(OX, OY, Team, Opts) then
          begin
            M^.LastHop := Tick;
            Result := MA_BLOCKED or MA_TAP;
            Exit;
          end;
          Sp := Sqrt(VX * VX + VY * VY) * MomKeep + MomBase + D * MomPerPixel;
          if Sp > MomMax then
            Sp := MomMax;
          Result := MA_MOVE or MA_TAP;
          if D >= 1 then
          begin
            M^.DirX := DX / D;
            M^.DirY := DY / D;
            OVX := M^.DirX * Sp;
            OVY := M^.DirY * Sp;
            ClampAxes(OVX, OVY);
            Result := Result or MA_VELOCITY;
          end
          else
          begin
            M^.DirX := 0;
            M^.DirY := 0;
          end;
          AddHop(M^, Tick, DX, DY);
          M^.Speed := Sp;
          M^.CmdX := OVX;
          M^.CmdY := OVY;
          M^.LastHop := Tick;
          M^.NextPush := Tick + Round(PushTicks);
          Exit;
        end;
        if not Down or (M^.Hold < HoldTicks) then
          Exit;
        M^.Continuous := True;
        HopLag(M^, Tick, Lag, LX, LY);
        HX := AimX - X + LX;
        HY := AimY - Y + LY;
        IX := HX + VEL_LAG * VX;
        IY := HY + VEL_LAG * VY;
        D := Sqrt(IX * IX + IY * IY);
        if D >= HopMin then
        begin
          NX := IX / D;
          NY := IY / D;
          if ((M^.DirX = 0) and (M^.DirY = 0)) or (NX * M^.DirX + NY * M^.DirY < -0.2) then
          begin
            M^.DirX := NX;
            M^.DirY := NY;
          end
          else
          begin
            TX := M^.DirX + (NX - M^.DirX) * Clamp(Steer, 0.01, 1);
            TY := M^.DirY + (NY - M^.DirY) * Clamp(Steer, 0.01, 1);
            L := Sqrt(TX * TX + TY * TY);
            if L > 0.0001 then
            begin
              M^.DirX := TX / L;
              M^.DirY := TY / L;
            end;
          end;
        end;
        if (M^.DirX = 0) and (M^.DirY = 0) then
          Exit;
        if Variant = VAR_INHERIT then
        begin
          M^.Speed := M^.Speed + Accel / 60;
          if M^.Speed > Vmax then
            M^.Speed := Vmax;
        end
        else
        begin
          M^.Speed := MomBase + D * MomPerPixel;
          if M^.Speed > MomMax then
            M^.Speed := MomMax;
        end;
        D := Sqrt(HX * HX + HY * HY);
        if (Tick - M^.LastHop >= HopTicks) and (Tick - M^.LastHop >= Lag + 2) and (D >= HopMin) and
          (HX * M^.DirX + HY * M^.DirY > 0) then
        begin
          if D > HopMax then
          begin
            HX := HX / D * HopMax;
            HY := HY / D * HopMax;
          end;
          OX := X + HX;
          OY := Y + HY;
          if Solid(OX, OY, Team, Opts) then
          begin
            M^.LastHop := Tick;
            Result := MA_BLOCKED;
          end
          else
          begin
            if Variant = VAR_INHERIT then
            begin
              M^.Speed := M^.Speed + Gain;
              if M^.Speed > Vmax then
                M^.Speed := Vmax;
            end;
            OVX := M^.DirX * M^.Speed;
            OVY := M^.DirY * M^.Speed;
            ClampAxes(OVX, OVY);
            M^.CmdX := OVX;
            M^.CmdY := OVY;
            AddHop(M^, Tick, HX, HY);
            M^.LastHop := Tick;
            M^.NextPush := Tick + Round(PushTicks);
            Result := MA_MOVE or MA_VELOCITY;
            Exit;
          end;
        end;
        if Tick >= M^.NextPush then
        begin
          M^.NextPush := Tick + Round(PushTicks);
          Comp := Gravity * (PushTicks + 1) / 2;
          OVX := M^.DirX * M^.Speed;
          OVY := M^.DirY * M^.Speed - Comp;
          ClampAxes(OVX, OVY);
          M^.CmdX := OVX;
          M^.CmdY := OVY;
          Result := Result or MA_VELOCITY;
        end;
      end;
    TP_FLY:
      begin
        if Press then
        begin
          M^.CmdX := VX;
          M^.CmdY := VY;
          M^.NextFly := Tick;
          M^.Owed := 0;
          M^.LastHop := Tick;
          M^.PredTick := -100000;
        end;
        if not Down then
          Exit;
        if Tick < M^.NextFly then
          Exit;
        Sp := Clamp(FlyEvery, 1, 60);
        M^.NextFly := Tick + Round(Sp);
        HopLag(M^, Tick, Lag, LX, LY);
        TX := 0;
        TY := 0;
        DX := AimX - X + LX;
        DY := AimY - Y + LY;
        D := Sqrt(DX * DX + DY * DY);
        if D > FlyDead then
        begin
          L := FlyBase + (D - FlyDead) * FlyPerPixel;
          if L > FlyMax then
            L := FlyMax;
          TX := DX / D * L;
          TY := DY / D * L;
        end;
        M^.CmdX := M^.CmdX + (TX - M^.CmdX) * Clamp(FlySmooth, 0.05, 1);
        M^.CmdY := M^.CmdY + (TY - M^.CmdY) * Clamp(FlySmooth, 0.05, 1);
        LimitSpeed(M^.CmdX, M^.CmdY, FlyMax);
        OVX := M^.CmdX;
        OVY := M^.CmdY;
        LimitSpeed(OVX, OVY, Clamp(FlyVelMax, 1, 15.5));
        ClampAxes(OVX, OVY);
        HX := M^.CmdX - OVX;
        HY := M^.CmdY - OVY;
        L := Sqrt(HX * HX + HY * HY);
        if L > 0.05 then
          M^.Owed := M^.Owed + L * Sp
        else
          M^.Owed := 0;
        Comp := Gravity * (Sp + 1) / 2;
        OVY := OVY - Comp;
        Result := MA_VELOCITY;
        if (M^.Owed >= 2) and (L > 0.05) and (Tick - M^.LastHop >= FlyHopTicks) and (Tick - M^.LastHop >= Lag + 2) then
        begin
          D := M^.Owed;
          if D > FlyHopMax then
            D := FlyHopMax;
          IX := X;
          IY := Y;
          if Tick - M^.PredTick <= Lag + 4 then
          begin
            IX := M^.PredX + OVX * (Tick - M^.PredTick);
            IY := M^.PredY + (OVY + Comp) * (Tick - M^.PredTick);
          end;
          OX := IX + HX / L * D;
          OY := IY + HY / L * D;
          if ((Opts and MO_NO_WALLS) <> 0) and MapReady and
            (MapRay(IX, IY - 10, OX, OY - 10, MR_PLAYER, Team) or MapPointSolid(OX, OY - 10, MR_PLAYER, Team)) then
          begin
            M^.Owed := 0;
            M^.LastHop := Tick;
          end
          else
          begin
            AddHop(M^, Tick, OX - IX, OY - IY);
            M^.PredX := OX;
            M^.PredY := OY;
            M^.PredTick := Tick;
            M^.LastHop := Tick;
            M^.Owed := M^.Owed - D;
            if M^.Owed > FlyHopMax then
              M^.Owed := FlyHopMax;
            Result := MA_MOVE or MA_VELOCITY;
          end;
        end;
      end;
  end;
end;

end.
