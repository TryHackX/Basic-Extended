unit be_rocket;

{ [ExtraRocket] guided rockets: the flight is worked out here, every tick; the script feeds in where
  the targets are and turns the events into bullets, sounds and damage (only ScriptCore can make
  those).

  A rocket is a point with a speed. Its motor pushes it along its heading (Thrust) against a drag that
  grows with the square of the speed, so it tops out at MaxSpeed; gravity pulls it down. It turns with
  the sideways push of its fins, at most Agility: the turn rate is Agility / speed, so a slow rocket
  turns tight and a fast one wide, and a turn costs speed (TurnDrag). Guidance is proportional
  navigation (Lead: the line of sight to the target is kept from turning, which flies it ahead of a
  running target) plus a share of pure pursuit (Pursuit). Walls: it looks ahead along its flight
  (LookTicks of flight), turns to the freer side and throttles back (Brake) to turn tighter - a rocket
  that comes too fast still cannot make the turn and hits the wall.

  Like a Javelin, the rocket leaves the tube slowly (EjectSpeed, falling a little) and its motor starts
  EjectTicks later; with the top attack profile it climbs over the target and dives on it (when there
  is room above). When the fuel ends it glides on for CoastTicks with half its fins' force and falls.
  It bursts at its target (within HitRadius of its path), next to another enemy on its way (ProxRadius),
  at a wall or at the end of the glide. The script reads what happened with RkNext. }

{$mode objfpc}{$H+}
{$Q-}{$IFNDEF BE_CHECKS}{$R-}{$ENDIF}

interface

const
  RK_SLOTS = 16;

  { the events }
  RE_TRAIL = 1;    { a flame of the trail: X, Y and its speed VX, VY }
  RE_IGNITE = 2;   { the motor starts: X, Y, VX, VY = the heading (length 1) }
  RE_MOTOR = 3;    { the motor's sound, at X, Y }
  RE_HIT = 4;      { the burst at the target (Target): X, Y where, VX, VY the rocket's speed }
  RE_PROX = 5;     { the burst next to another enemy (Target = him) }
  RE_WALL = 6;     { the burst at a wall }
  RE_AIR = 7;      { the burst at the end of the glide }
  RE_BURNOUT = 8;  { the fuel ended: X, Y }
  RE_LOST = 9;     { it left the map (no burst) }

  { RkSet: the settings }
  RKC_EJECT_SPEED = 1;
  RKC_EJECT_TICKS = 2;
  RKC_MAX_SPEED = 3;
  RKC_THRUST = 4;
  RKC_AGILITY = 5;
  RKC_TURN_DRAG = 6;
  RKC_GRAVITY = 7;
  RKC_LEAD = 8;
  RKC_PURSUIT = 9;
  RKC_LOOK_TICKS = 10;
  RKC_BRAKE = 11;
  RKC_AVOID = 12;
  RKC_FUEL_TICKS = 13;
  RKC_COAST_TICKS = 14;
  RKC_PROFILE = 15;
  RKC_TOP_HEIGHT = 16;
  RKC_TOP_MIN = 17;
  RKC_HIT_RADIUS = 18;
  RKC_PROX_RADIUS = 19;
  RKC_TRAIL_SPACING = 20;
  RKC_TRAIL_SHARE = 21;
  RKC_MOTOR_TICKS = 22;
  RKC_BODY = 23;
  RKC_WALLS = 24;
  RKC_TEAM_GAME = 25;
  RKC_TOP_SPEED = 27;

  RP_DIRECT = 0;
  RP_TOP = 1;
  RP_AUTO = 2;

  PH_EJECT = 0;
  PH_BOOST = 1;
  PH_COAST = 2;

type
  TRocket = record
    Used: Boolean;
    Owner, Target: LongInt;
    X, Y, VX, VY: Single;
    PX, PY: Single;
    Age, Fuel, Coast, Phase, NextMotor: LongInt;
    { the aim point (the target's chest) and his speed; Seen = he is there this tick }
    TX, TY, TVX, TVY: Single;
    Seen, Lost: Boolean;
    { top attack: still climbing to ApexY, and from which side it came }
    Climb: Boolean;
    ApexY, D0, H0, Y0, VCap: Single;
    Side: LongInt;
    { distance flown since the last flame of the trail }
    Trail: Single;
  end;

var
  Rk: array[0..RK_SLOTS - 1] of TRocket;

procedure RkSet(Key: LongInt; V: Single);
procedure RkReset;
{ a new rocket from X, Y at the target Target (his chest at TX, TY, running at TVX, TVY): its slot, or
  -1 when all are flying }
function RkLaunch(Owner, Target: LongInt; X, Y, TX, TY, TVX, TVY: Single): LongInt;
{ where the target of rocket k is this tick (Alive = 0: he is gone, the rocket flies on) }
procedure RkAim(k, Alive: LongInt; TX, TY, TVX, TVY: Single);
procedure RkStep(Tick: LongInt);
function RkNext(out k, Kind, Owner, Target: LongInt; out X, Y, VX, VY: Single): Boolean;
function RkFlying: LongInt;
function RkState(k: LongInt; out Owner, Target, Phase: LongInt; out X, Y, PX, PY: Single): Boolean;
procedure RkDrop(k: LongInt);
function RkInfo: AnsiString;

implementation

uses
  SysUtils, Math, be_map, be_world;

const
  MAX_EVENTS = 256;
  COAST_AGILITY = 0.5;
  MIN_BOOST_SPEED = 1.5;
  SPEED_LIMIT = 60;
  MAP_LIMIT = 40000;
  AVOID_ANGLE = 0.61;  { 35 degrees }

type
  TRkEvent = record
    k, Kind, Owner, Target: LongInt;
    X, Y, VX, VY: Single;
  end;

var
  EjectSpeed: Single = 4;
  EjectTicks: LongInt = 9;
  MaxSpeed: Single = 16;
  Thrust: Single = 0.9;
  Agility: Single = 1.1;
  TurnDrag: Single = 0.35;
  Gravity: Single = 0.06;
  Lead: Single = 3;
  Pursuit: Single = 0.12;
  LookTicks: Single = 12;
  Brake: Single = 0.6;
  Avoid: Boolean = True;
  FuelTicks: LongInt = 180;
  CoastTicks: LongInt = 60;
  Profile: LongInt = RP_AUTO;
  TopHeight: Single = 220;
  TopMin: Single = 300;
  TopSpeed: Single = 0.75;
  HitRadius: Single = 25;
  ProxRadius: Single = 18;
  TrailSpacing: Single = 22;
  TrailShare: Single = 0.25;
  MotorTicks: LongInt = 24;
  Body: Single = 10;
  Walls: Boolean = True;
  TeamGame: Boolean = True;
  { drag: Thrust = K * MaxSpeed^2 }
  DragK: Single = 0.9 / 256;

  Events: array[0..MAX_EVENTS - 1] of TRkEvent;
  EvHead: LongInt = 0;
  EvTail: LongInt = 0;
  StLaunched: LongInt = 0;
  StHits: LongInt = 0;
  StWalls: LongInt = 0;
  StAir: LongInt = 0;
  StAvoid: LongInt = 0;
  StTop: LongInt = 0;

procedure SetDrag;
begin
  if MaxSpeed < 1 then
    MaxSpeed := 1;
  DragK := Thrust / (MaxSpeed * MaxSpeed);
end;

procedure RkSet(Key: LongInt; V: Single);
begin
  case Key of
    RKC_EJECT_SPEED: EjectSpeed := V;
    RKC_EJECT_TICKS: EjectTicks := Round(V);
    RKC_MAX_SPEED: MaxSpeed := V;
    RKC_THRUST: Thrust := V;
    RKC_AGILITY: Agility := V;
    RKC_TURN_DRAG: TurnDrag := V;
    RKC_GRAVITY: Gravity := V;
    RKC_LEAD: Lead := V;
    RKC_PURSUIT: Pursuit := V;
    RKC_LOOK_TICKS: LookTicks := V;
    RKC_BRAKE: Brake := V;
    RKC_AVOID: Avoid := V <> 0;
    RKC_FUEL_TICKS: FuelTicks := Round(V);
    RKC_COAST_TICKS: CoastTicks := Round(V);
    RKC_PROFILE: Profile := Round(V);
    RKC_TOP_HEIGHT: TopHeight := V;
    RKC_TOP_MIN: TopMin := V;
    RKC_HIT_RADIUS: HitRadius := V;
    RKC_PROX_RADIUS: ProxRadius := V;
    RKC_TRAIL_SPACING: TrailSpacing := V;
    RKC_TRAIL_SHARE: TrailShare := V;
    RKC_MOTOR_TICKS: MotorTicks := Round(V);
    RKC_BODY: Body := V;
    RKC_WALLS: Walls := V <> 0;
    RKC_TEAM_GAME: TeamGame := V <> 0;
    RKC_TOP_SPEED: TopSpeed := V;
  end;
  SetDrag;
end;

procedure RkReset;
var
  k: LongInt;
begin
  for k := 0 to RK_SLOTS - 1 do
    Rk[k].Used := False;
  EvHead := 0;
  EvTail := 0;
end;

procedure Emit(k, Kind: LongInt; X, Y, VX, VY: Single);
var
  n: LongInt;
begin
  Events[EvHead].k := k;
  Events[EvHead].Kind := Kind;
  Events[EvHead].Owner := Rk[k].Owner;
  Events[EvHead].Target := Rk[k].Target;
  Events[EvHead].X := X;
  Events[EvHead].Y := Y;
  Events[EvHead].VX := VX;
  Events[EvHead].VY := VY;
  n := (EvHead + 1) mod MAX_EVENTS;
  { a full ring loses its oldest event (trail flames come first, so the bursts get through) }
  if n = EvTail then
    EvTail := (EvTail + 1) mod MAX_EVENTS;
  EvHead := n;
end;

function Blocked(AX, AY, BX, BY: Single): Boolean;
begin
  Result := False;
  if Walls then
    Result := MapRay(AX, AY, BX, BY, MR_BULLET or MR_COLLIDER, 0);
end;

{ how far along A -> B the first wall is (0..1; 1 = none): the ray is halved 7 times }
function WallAt(AX, AY, BX, BY: Single): Single;
var
  Lo, Hi, Mid: Single;
  i: LongInt;
begin
  Result := 1;
  if not Blocked(AX, AY, BX, BY) then
    Exit;
  Lo := 0;
  Hi := 1;
  for i := 1 to 7 do
  begin
    Mid := (Lo + Hi) / 2;
    if Blocked(AX, AY, AX + (BX - AX) * Mid, AY + (BY - AY) * Mid) then
      Hi := Mid
    else
      Lo := Mid;
  end;
  Result := Lo;
end;

{ the part of the step A -> B (0..Lim) nearest to C: its share (out F) and the squared distance }
function Closest(AX, AY, BX, BY, CX, CY, Lim: Single; out F: Single): Single;
var
  SX, SY, S2, DX, DY: Single;
begin
  SX := BX - AX;
  SY := BY - AY;
  S2 := SX * SX + SY * SY;
  F := 0;
  if S2 > 0.0001 then
    F := ((CX - AX) * SX + (CY - AY) * SY) / S2;
  if F < 0 then
    F := 0;
  if F > Lim then
    F := Lim;
  DX := AX + SX * F - CX;
  DY := AY + SY * F - CY;
  Result := DX * DX + DY * DY;
end;

function Sign1(V: Single): LongInt;
begin
  if V < 0 then
    Result := -1
  else
    Result := 1;
end;

{ the room above X, Y up to Want (less a margin of 40), or Want when nothing is there }
function RoomAbove(X, Y, Want: Single): Single;
begin
  if MapPointSolid(X, Y, MR_BULLET, 0) then
  begin
    Result := Want;
    Exit;
  end;
  Result := WallAt(X, Y, X, Y - Want - 40) * (Want + 40) - 40;
end;

{ the arc of a top attack from X, Y to TX, TY (H over the straight line in the middle, never over Apex)
  is free of walls: looked at in 10 pieces }
function ArcClear(X, Y, TX, TY, H, Apex: Single): Boolean;
var
  n, Side: LongInt;
  D0, F, PX, PY, QX, QY: Single;
begin
  Result := False;
  D0 := Abs(TX - X);
  if D0 < 1 then
    Exit;
  Side := Sign1(TX - X);
  PX := X;
  PY := Y;
  for n := 1 to 10 do
  begin
    F := D0 * (10 - n) / 10;
    QX := TX - Side * F;
    QY := TY + (Y - TY) * F / D0 - 4 * H * F * (D0 - F) / (D0 * D0);
    if QY < Apex then
      QY := Apex;
    if Blocked(PX, PY, QX, QY) then
      Exit;
    PX := QX;
    PY := QY;
  end;
  Result := True;
end;

{ top attack: is there room to climb over the target? The highest the rocket goes (Apex) is TopHeight
  over the higher of the two (at most half the way), less where a ceiling is lower (over the shooter, the
  middle, the target) }
function TopRoom(const R: TRocket; out Apex, H: Single): Boolean;
var
  DX, ADX, Base: Single;
begin
  Result := False;
  Apex := 0;
  H := 0;
  DX := R.TX - R.X;
  ADX := Abs(DX);
  if Profile = RP_DIRECT then
    Exit;
  if (Profile = RP_AUTO) and (ADX < TopMin) then
    Exit;
  if ADX < TopMin / 2 then
    Exit;
  { a target well above: straight at him }
  if R.TY < R.Y - 80 then
    Exit;
  Base := Min(R.Y, R.TY);
  H := Min(TopHeight, ADX * 0.5);
  H := Min(H, RoomAbove(R.X, R.Y, H));
  H := Min(H, RoomAbove(R.X + DX * 0.5, Base - 10, H) + 10);
  H := Min(H, RoomAbove(R.TX, R.TY, H) + (R.TY - Base));
  if H < 70 then
    Exit;
  Apex := Base - H;
  if Blocked(R.X, R.Y, R.X + DX * 0.25, Apex) then
    Exit;
  { the whole arc is free, and a lower one too (the rocket cuts inside its arc) }
  if not ArcClear(R.X, R.Y, R.TX, R.TY, H, Apex) then
    Exit;
  if not ArcClear(R.X, R.Y + 8, R.TX, R.TY, H * 0.75, Apex) then
    Exit;
  Result := True;
end;

function RkLaunch(Owner, Target: LongInt; X, Y, TX, TY, TVX, TVY: Single): LongInt;
var
  k: LongInt;
  DX, DY, D, UX, UY, Apex, H, A: Single;
begin
  Result := -1;
  for k := 0 to RK_SLOTS - 1 do
    if not Rk[k].Used then
    begin
      Result := k;
      Break;
    end;
  if Result < 0 then
    Exit;
  k := Result;
  FillChar(Rk[k], SizeOf(TRocket), 0);
  Rk[k].Used := True;
  Rk[k].Owner := Owner;
  Rk[k].Target := Target;
  Rk[k].X := X;
  Rk[k].Y := Y;
  Rk[k].PX := X;
  Rk[k].PY := Y;
  Rk[k].TX := TX;
  Rk[k].TY := TY;
  Rk[k].TVX := TVX;
  Rk[k].TVY := TVY;
  Rk[k].Seen := True;
  Rk[k].Phase := PH_EJECT;
  DX := TX - X;
  DY := TY - Y;
  D := Sqrt(DX * DX + DY * DY);
  if D < 0.001 then
  begin
    DX := 1;
    DY := 0;
    D := 1;
  end;
  UX := DX / D;
  UY := DY / D;
  Rk[k].Side := Sign1(DX);
  { out of the tube: up and towards the target for a top attack, else at it a little upwards }
  if TopRoom(Rk[k], Apex, H) then
  begin
    A := 0.87;
    if not Blocked(X, Y, X + Rk[k].Side * Cos(A) * 60, Y - Sin(A) * 60) then
    begin
      UX := Rk[k].Side * Cos(A);
      UY := -Sin(A);
      Rk[k].Climb := True;
      Rk[k].ApexY := Apex;
      { the arc: from here (Y0) to him over D0, H over the straight line in the middle; flown no faster
        than its tightest bend allows (radius D0^2 / 8H) }
      Rk[k].D0 := Abs(TX - X);
      Rk[k].H0 := Max(H, 1);
      Rk[k].Y0 := Y;
      Rk[k].VCap := Min(MaxSpeed * TopSpeed, Sqrt(Agility * Rk[k].D0 * Rk[k].D0 / (8 * Max(Rk[k].H0, 1))) * 1.15);
      Inc(StTop);
    end;
  end;
  if not Rk[k].Climb then
  begin
    { a little upwards }
    DX := UX;
    DY := UY - 0.14;
    D := Sqrt(DX * DX + DY * DY);
    DX := DX / D;
    DY := DY / D;
    if not Blocked(X, Y, X + DX * 40, Y + DY * 40) then
    begin
      UX := DX;
      UY := DY;
    end;
  end;
  Rk[k].VX := UX * EjectSpeed;
  Rk[k].VY := UY * EjectSpeed;
  Inc(StLaunched);
  if EjectTicks <= 0 then
  begin
    Rk[k].Phase := PH_BOOST;
    Rk[k].Fuel := FuelTicks;
    Emit(k, RE_IGNITE, X, Y, UX, UY);
  end;
end;

procedure RkAim(k, Alive: LongInt; TX, TY, TVX, TVY: Single);
begin
  if (k < 0) or (k >= RK_SLOTS) then
    Exit;
  if not Rk[k].Used then
    Exit;
  if Alive = 0 then
  begin
    Rk[k].Seen := False;
    Exit;
  end;
  Rk[k].Seen := True;
  Rk[k].TX := TX;
  Rk[k].TY := TY;
  Rk[k].TVX := TVX;
  Rk[k].TVY := TVY;
end;

procedure Retire(k: LongInt);
begin
  Rk[k].Used := False;
end;

procedure RkDrop(k: LongInt);
begin
  if (k >= 0) and (k < RK_SLOTS) then
    Rk[k].Used := False;
end;

{ the burst: an event and the rocket is gone }
procedure Burst(k, Kind, Who: LongInt; X, Y: Single);
begin
  Rk[k].Target := Who;
  Emit(k, Kind, X, Y, Rk[k].VX, Rk[k].VY);
  case Kind of
    RE_HIT, RE_PROX: Inc(StHits);
    RE_WALL: Inc(StWalls);
    RE_AIR: Inc(StAir);
  end;
  Retire(k);
end;

procedure StepOne(k, Tick: LongInt);
var
  Spd, UX, UY, NX, NY, ALat, AMax, Push, Along, AX, AY, RX, RY, D2, D, RVX, RVY, LamDot, Cr, Dt, Err: Single;
  L, DC, DL, DR, CA, SA, Urg, BX, BY, TW, F, Best, F2, Dist, DX, WX, WY, AimVX, AimVY: Single;
  i, Turn, Hit: LongInt;
begin
  with Rk[k] do
  begin
    Inc(Age);
    PX := X;
    PY := Y;
    Spd := Sqrt(VX * VX + VY * VY);
    if Spd < 0.01 then
    begin
      VX := 0.01 * Side;
      VY := 0;
      Spd := 0.01;
    end;
    UX := VX / Spd;
    UY := VY / Spd;
    NX := -UY;
    NY := UX;
    Push := 0;
    ALat := 0;
    AMax := Agility;

    { the motor starts }
    if Phase = PH_EJECT then
      if Age >= EjectTicks then
      begin
        Phase := PH_BOOST;
        Fuel := FuelTicks;
        NextMotor := Age + MotorTicks;
        Emit(k, RE_IGNITE, X, Y, UX, UY);
      end;
    if Phase = PH_BOOST then
    begin
      Push := Thrust;
      { the climb of a top attack is flown slower, so the rocket can turn down onto him }
      if Climb then
        if Spd > VCap then
          Push := DragK * Spd * Spd * 0.5;
    end
    else if Phase = PH_COAST then
      AMax := Agility * COAST_AGILITY;

    { guidance: at the target (or the top of the climb), leading him }
    if Phase <> PH_EJECT then
    begin
      AimVX := TVX;
      AimVY := TVY;
      WX := TX;
      WY := TY;
      if not Seen then
      begin
        { he is gone: on to where he was, then straight on }
        AimVX := 0;
        AimVY := 0;
        if not Lost then
          if (TX - X) * (TX - X) + (TY - Y) * (TY - Y) < 40 * 40 then
            Lost := True;
      end;
      if Climb then
      begin
        { the top attack follows its arc: the aim is a point of it a little ahead (Look), so the rocket
          climbs, flies over and comes down on him steeply in one smooth curve; the last stretch is flown
          straight at him, so it can still correct }
        DX := TX - X;
        D := Abs(DX);
        if D > D0 then
          D0 := D;
        L := Max(50, Spd * 6);
        if (Sign1(DX) <> Side) or (D < 40 + 2 * Spd) then
          Climb := False
        else
        begin
          F := Max(0, D - L);
          WX := TX - Side * F;
          WY := TY + (Y0 - TY) * F / D0 - 4 * H0 * F * (D0 - F) / (D0 * D0);
          if WY < ApexY then
            WY := ApexY;
          if Blocked(X, Y, WX, WY) then
            Climb := False;
        end;
        if not Climb then
        begin
          WX := TX;
          WY := TY;
        end;
      end;
      if not Lost then
      begin
        RX := WX - X;
        RY := WY - Y;
        D2 := RX * RX + RY * RY;
        if D2 > 1 then
        begin
          D := Sqrt(D2);
          RVX := AimVX - VX;
          RVY := AimVY - VY;
          LamDot := (RX * RVY - RY * RVX) / D2;
          Cr := UX * RY - UY * RX;
          Dt := UX * RX + UY * RY;
          Err := ArcTan2(Cr, Dt);
          ALat := Lead * Spd * LamDot + Pursuit * Spd * Err;
        end;
      end;
    end;

    { gravity is held off while the motor runs }
    if Phase = PH_BOOST then
      ALat := ALat - Gravity * NY;

    { walls ahead: turn to the freer side and throttle back }
    if Avoid and Walls and (Phase <> PH_EJECT) then
    begin
      L := Spd * LookTicks + 24;
      DC := WallAt(X, Y, X + UX * L, Y + UY * L) * L;
      if DC < L then
      begin
        Hit := 1;
        { the last stretch: he is in sight and near (the wall is at him or behind him) - no turning away }
        if Seen and not Lost then
          if not Climb then
          begin
            Dist := Sqrt((TX - X) * (TX - X) + (TY - Y) * (TY - Y));
            if (Dist < DC) or (Dist < 2 * L) then
              if not Blocked(X, Y, TX, TY) then
                Hit := 0;
          end;
        if Hit = 1 then
        begin
          Inc(StAvoid);
          CA := Cos(AVOID_ANGLE);
          SA := Sin(AVOID_ANGLE);
          BX := UX * CA + NX * SA;
          BY := UY * CA + NY * SA;
          DL := WallAt(X, Y, X + BX * L * 0.85, Y + BY * L * 0.85);
          BX := UX * CA - NX * SA;
          BY := UY * CA - NY * SA;
          DR := WallAt(X, Y, X + BX * L * 0.85, Y + BY * L * 0.85);
          if DL > DR + 0.02 then
            Turn := 1
          else if DR > DL + 0.02 then
            Turn := -1
          else if ALat <> 0 then
            Turn := Sign1(ALat)
          else if NY < 0 then
            Turn := 1
          else
            Turn := -1;
          Urg := 1 - DC / L;
          ALat := Turn * AMax * Min(1, 0.35 + 1.3 * Urg);
          Push := Push * (1 - Brake * Urg);
          { air brake }
          Push := Push - Brake * Urg * 0.05 * Spd;
        end;
      end;
    end;

    if ALat > AMax then
      ALat := AMax
    else if ALat < -AMax then
      ALat := -AMax;
    Along := Push - DragK * Spd * Spd - TurnDrag * Abs(ALat);
    if Phase = PH_EJECT then
      Along := -DragK * Spd * Spd;
    AX := UX * Along + NX * ALat;
    AY := UY * Along + NY * ALat + Gravity;
    VX := VX + AX;
    VY := VY + AY;
    Spd := Sqrt(VX * VX + VY * VY);
    if Phase = PH_BOOST then
      if Spd < MIN_BOOST_SPEED then
      begin
        if Spd < 0.01 then
        begin
          VX := UX;
          VY := UY;
          Spd := 1;
        end;
        VX := VX / Spd * MIN_BOOST_SPEED;
        VY := VY / Spd * MIN_BOOST_SPEED;
        Spd := MIN_BOOST_SPEED;
      end;
    if Spd > SPEED_LIMIT then
    begin
      VX := VX / Spd * SPEED_LIMIT;
      VY := VY / Spd * SPEED_LIMIT;
    end;
    BX := X + VX;
    BY := Y + VY;

    { what the step meets first: a wall, the target, another enemy }
    TW := WallAt(X, Y, BX, BY);
    if Seen and not Lost then
      if Closest(X, Y, BX, BY, TX, TY, TW, F) <= HitRadius * HitRadius then
      begin
        Burst(k, RE_HIT, Target, X + (BX - X) * F, Y + (BY - Y) * F);
        Exit;
      end;
    Best := 1000000;
    Hit := 0;
    if ProxRadius > 0 then
      if Abs(Tick - WTick) <= 3 then
        for i := 1 to BE_PLAYERS do
          if WP[i].Active and WP[i].Alive then
            if (i <> Owner) and (i <> Target) then
              if WP[i].Team <> TEAM_SPEC then
                if (not TeamGame) or (not ValidID(Owner)) or (WP[i].Team <> WP[Owner].Team) then
                begin
                  D2 := Closest(X, Y, BX, BY, WP[i].X, WP[i].Y - Body, TW, F2);
                  if D2 <= ProxRadius * ProxRadius then
                    if F2 < Best then
                    begin
                      Best := F2;
                      Hit := i;
                    end;
                end;
    if Hit > 0 then
    begin
      Burst(k, RE_PROX, Hit, X + (BX - X) * Best, Y + (BY - Y) * Best);
      Exit;
    end;
    if TW < 1 then
    begin
      D := Sqrt(VX * VX + VY * VY);
      F := TW;
      if D > 0.01 then
        F := TW - 3 / D;
      if F < 0 then
        F := 0;
      Burst(k, RE_WALL, 0, X + (BX - X) * F, Y + (BY - Y) * F);
      Exit;
    end;
    X := BX;
    Y := BY;
    if (Abs(X) > MAP_LIMIT) or (Abs(Y) > MAP_LIMIT) then
    begin
      Emit(k, RE_LOST, X, Y, 0, 0);
      Retire(k);
      Exit;
    end;

    { the trail: a flame every TrailSpacing of the way while the motor burns }
    if (Phase = PH_BOOST) and (TrailSpacing > 0) then
    begin
      Trail := Trail + Sqrt(VX * VX + VY * VY);
      i := 0;
      while (Trail >= TrailSpacing) and (i < 3) do
      begin
        Trail := Trail - TrailSpacing;
        D := Sqrt(VX * VX + VY * VY);
        F := 0;
        if D > 0.01 then
          F := Trail / D;
        Emit(k, RE_TRAIL, X - VX * F, Y - VY * F, VX * TrailShare, VY * TrailShare);
        Inc(i);
      end;
      if Trail > TrailSpacing then
        Trail := 0;
      if MotorTicks > 0 then
        if Age >= NextMotor then
        begin
          NextMotor := Age + MotorTicks;
          Emit(k, RE_MOTOR, X, Y, 0, 0);
        end;
      Dec(Fuel);
      if Fuel <= 0 then
      begin
        Phase := PH_COAST;
        Coast := CoastTicks;
        Emit(k, RE_BURNOUT, X, Y, VX, VY);
      end;
    end
    else if Phase = PH_COAST then
    begin
      Dec(Coast);
      if Coast <= 0 then
      begin
        Burst(k, RE_AIR, 0, X, Y);
        Exit;
      end;
    end;
  end;
end;

procedure RkStep(Tick: LongInt);
var
  k: LongInt;
begin
  for k := 0 to RK_SLOTS - 1 do
    if Rk[k].Used then
      StepOne(k, Tick);
end;

function RkNext(out k, Kind, Owner, Target: LongInt; out X, Y, VX, VY: Single): Boolean;
begin
  Result := EvHead <> EvTail;
  if not Result then
  begin
    k := -1;
    Kind := 0;
    Owner := 0;
    Target := 0;
    X := 0;
    Y := 0;
    VX := 0;
    VY := 0;
    Exit;
  end;
  k := Events[EvTail].k;
  Kind := Events[EvTail].Kind;
  Owner := Events[EvTail].Owner;
  Target := Events[EvTail].Target;
  X := Events[EvTail].X;
  Y := Events[EvTail].Y;
  VX := Events[EvTail].VX;
  VY := Events[EvTail].VY;
  EvTail := (EvTail + 1) mod MAX_EVENTS;
end;

function RkFlying: LongInt;
var
  k: LongInt;
begin
  Result := 0;
  for k := 0 to RK_SLOTS - 1 do
    if Rk[k].Used then
      Inc(Result);
end;

function RkState(k: LongInt; out Owner, Target, Phase: LongInt; out X, Y, PX, PY: Single): Boolean;
begin
  Result := False;
  Owner := 0;
  Target := 0;
  Phase := 0;
  X := 0;
  Y := 0;
  PX := 0;
  PY := 0;
  if (k < 0) or (k >= RK_SLOTS) then
    Exit;
  if not Rk[k].Used then
    Exit;
  Result := True;
  Owner := Rk[k].Owner;
  Target := Rk[k].Target;
  Phase := Rk[k].Phase;
  X := Rk[k].X;
  Y := Rk[k].Y;
  PX := Rk[k].PX;
  PY := Rk[k].PY;
end;

function RkInfo: AnsiString;
begin
  Result := 'rockets: ' + IntToStr(StLaunched) + ' launched (' + IntToStr(StTop) + ' top attack), ' + IntToStr(StHits) +
    ' hits, ' + IntToStr(StWalls) + ' walls, ' + IntToStr(StAir) + ' in the air, walls avoided ' + IntToStr(StAvoid) +
    ' ticks, ' + IntToStr(RkFlying) + ' flying';
end;

end.
