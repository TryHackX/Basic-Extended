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
  MF_HOP_TIMEOUT = 18;
  MF_ACCEL = 19;

procedure MoveSet(Key: LongInt; Value: Single);
function MoveStep(ID, Tick, Mode, Variant, Key, Alive: LongInt; X, Y, VX, VY: Single; AimX, AimY: LongInt;
  out OX, OY, OVX, OVY: Single): LongInt;
procedure MoveBlocked(ID, Tick: LongInt);
procedure MoveReset(ID: LongInt);

implementation

uses
  be_world;

type
  TMover = record
    Mode, Variant: LongInt;
    KeyWas, Continuous, HasOff, Fresh, Started: Boolean;
    Hold, LastHop, NextPush, NextFly, AimX, AimY: LongInt;
    OffX, OffY, DirX, DirY, Speed, CmdX, CmdY: Single;
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
  FlyBase: Single = 1;
  FlyPerPixel: Single = 0.03;
  FlyMax: Single = 9;
  FlyEvery: Single = 2;
  FlyDead: Single = 18;
  FlySmooth: Single = 0.5;
  Gravity: Single = 0.06;
  HopTimeout: Single = 20;
  Accel: Single = 4;

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
    MF_HOP_TIMEOUT: HopTimeout := Value;
    MF_ACCEL: Accel := Value;
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
  Movers[ID].Fresh := False;
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

function MoveStep(ID, Tick, Mode, Variant, Key, Alive: LongInt; X, Y, VX, VY: Single; AimX, AimY: LongInt;
  out OX, OY, OVX, OVY: Single): LongInt;
var
  M: ^TMover;
  Down, Press: Boolean;
  DX, DY, D, Sp, TX, TY, NX, NY, L, Comp: Single;
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
    M^.AimX := AimX;
    M^.AimY := AimY;
    M^.OffX := AimX - X;
    M^.OffY := AimY - Y;
    M^.HasOff := True;
  end;
  if (AimX <> M^.AimX) or (AimY <> M^.AimY) then
  begin
    M^.AimX := AimX;
    M^.AimY := AimY;
    M^.OffX := AimX - X;
    M^.OffY := AimY - Y;
    M^.HasOff := True;
    M^.Fresh := True;
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
  case Mode of
    TP_JUMP:
      if Press then
      begin
        OX := AimX;
        OY := AimY;
        Result := MA_MOVE or MA_VELOCITY or MA_TAP;
      end;
    TP_MOMENTUM:
      begin
        if Press then
        begin
          DX := AimX - X;
          DY := AimY - Y;
          D := Sqrt(DX * DX + DY * DY);
          Sp := Sqrt(VX * VX + VY * VY) * MomKeep + MomBase + D * MomPerPixel;
          if Sp > MomMax then
            Sp := MomMax;
          OX := AimX;
          OY := AimY;
          Result := MA_MOVE or MA_TAP;
          if D >= 1 then
          begin
            M^.DirX := DX / D;
            M^.DirY := DY / D;
            OVX := M^.DirX * Sp;
            OVY := M^.DirY * Sp;
            Result := Result or MA_VELOCITY;
          end
          else
          begin
            M^.DirX := 0;
            M^.DirY := 0;
          end;
          M^.Speed := Sp;
          M^.CmdX := OVX;
          M^.CmdY := OVY;
          M^.LastHop := Tick;
          M^.NextPush := Tick + Round(PushTicks);
          M^.Fresh := False;
          Exit;
        end;
        if not Down or (M^.Hold < HoldTicks) then
          Exit;
        M^.Continuous := True;
        if M^.Fresh and M^.HasOff then
        begin
          D := Sqrt(M^.OffX * M^.OffX + M^.OffY * M^.OffY);
          if D >= HopMin then
          begin
            NX := M^.OffX / D;
            NY := M^.OffY / D;
            if (M^.DirX = 0) and (M^.DirY = 0) then
            begin
              M^.DirX := NX;
              M^.DirY := NY;
            end
            else if NX * M^.DirX + NY * M^.DirY > -0.1 then
            begin
              TX := M^.DirX * 0.6 + NX * 0.4;
              TY := M^.DirY * 0.6 + NY * 0.4;
              L := Sqrt(TX * TX + TY * TY);
              if L > 0.0001 then
              begin
                M^.DirX := TX / L;
                M^.DirY := TY / L;
              end;
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
          D := Sqrt(M^.OffX * M^.OffX + M^.OffY * M^.OffY);
          M^.Speed := MomBase + D * MomPerPixel;
          if M^.Speed > MomMax then
            M^.Speed := MomMax;
        end;
        if (Tick - M^.LastHop >= HopTicks) and M^.HasOff and (M^.Fresh or (Tick - M^.LastHop >= HopTimeout)) then
        begin
          D := Sqrt(M^.OffX * M^.OffX + M^.OffY * M^.OffY);
          if (D >= HopMin) and (M^.OffX * M^.DirX + M^.OffY * M^.DirY > 0) then
          begin
            OX := X + M^.OffX;
            OY := Y + M^.OffY;
            if Variant = VAR_INHERIT then
            begin
              M^.Speed := M^.Speed + Gain;
              if M^.Speed > Vmax then
                M^.Speed := Vmax;
            end;
            OVX := M^.DirX * M^.Speed;
            OVY := M^.DirY * M^.Speed;
            M^.CmdX := OVX;
            M^.CmdY := OVY;
            M^.LastHop := Tick;
            M^.NextPush := Tick + Round(PushTicks);
            M^.Fresh := False;
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
          M^.CmdX := OVX;
          M^.CmdY := OVY;
          Result := MA_VELOCITY;
        end;
      end;
    TP_FLY:
      begin
        if Press then
        begin
          M^.CmdX := VX;
          M^.CmdY := VY;
          M^.NextFly := Tick;
        end;
        if not Down then
          Exit;
        if Tick < M^.NextFly then
          Exit;
        M^.NextFly := Tick + Round(Clamp(FlyEvery, 1, 60));
        TX := 0;
        TY := 0;
        if M^.HasOff then
        begin
          D := Sqrt(M^.OffX * M^.OffX + M^.OffY * M^.OffY);
          if D > FlyDead then
          begin
            Sp := FlyBase + (D - FlyDead) * FlyPerPixel;
            if Sp > FlyMax then
              Sp := FlyMax;
            TX := M^.OffX / D * Sp;
            TY := M^.OffY / D * Sp;
          end;
        end;
        M^.CmdX := M^.CmdX + (TX - M^.CmdX) * Clamp(FlySmooth, 0.05, 1);
        M^.CmdY := M^.CmdY + (TY - M^.CmdY) * Clamp(FlySmooth, 0.05, 1);
        LimitSpeed(M^.CmdX, M^.CmdY, FlyMax);
        Comp := Gravity * (Clamp(FlyEvery, 1, 60) + 1) / 2;
        OVX := M^.CmdX;
        OVY := M^.CmdY - Comp;
        Result := MA_VELOCITY;
      end;
  end;
end;

end.
