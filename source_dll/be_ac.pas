unit be_ac;

{$mode objfpc}{$H+}
{$Q-}{$R-}

interface

uses
  be_world;

const
  AF_FIRE = 1;
  AF_MOVE = 2;
  AF_AIR = 4;
  AK_STARTUP = 1;
  AK_RATE = 2;
  AK_JUMP = 3;
  AK_BINK = 4;
  AK_MOVE = 5;
  AC_ENABLED = 1;
  AC_SLACK = 2;
  AC_JUMP_SLACK = 3;
  AC_JUMP_LAG = 4;
  AC_RATE = 5;
  AC_BINK_TICKS = 6;
  AC_GRACE = 7;
  AC_TOTALS = 14;
  T_SESSIONS = 0;
  T_SU_N = 1;
  T_SU_BAD = 2;
  T_SU_MIN = 3;
  T_RATE = 4;
  T_JUMPS = 5;
  T_JUMP_MAX = 6;
  T_B_HITS = 7;
  T_BINK_HITS = 8;
  T_M_HITS = 9;
  T_MOVE_HITS = 10;
  T_HITS = 11;
  T_HEADS = 12;
  T_SU_SUM = 13;

type
  TAcTotals = array[0..AC_TOTALS - 1] of LongInt;

procedure AcSet(Key: LongInt; Value: Single);
function AcEnabled: Boolean;
procedure AcReset(ID: LongInt);
procedure AcResetAll;
procedure AcKeys(Tick, Count: LongInt; I: PLongArr);
procedure AcMoved(ID, Tick: LongInt);
procedure AcHurt(Victim, Tick, W: LongInt);
function AcHit(Tick, Shooter, W, Bullet: LongInt; Damage, BX, BY, BVX, BVY, SX, SY: Single): LongInt;
procedure AcWorld(Tick: LongInt);
function AcWatched(W: LongInt): Boolean;
function AcNext(out ID, Kind: LongInt; out Text: AnsiString): Boolean;
function AcScoreOf(const T: TAcTotals): LongInt;
function AcScore(ID: LongInt): LongInt;
procedure AcTotals(ID: LongInt; out T: TAcTotals);
function AcLineOf(const T: TAcTotals): AnsiString;
function AcSessionFlags(ID: LongInt): LongInt;

implementation

uses
  SysUtils, be_ballistic;

const
  MAX_STEP = 15.6;
  QUEUE_SIZE = 64;

type
  TAcRec = record
    Fire, LastAlive, Known: Boolean;
    Rise, KeyTick, HurtTick, HurtW, MovedTick, LastSnap, PrevShot, PrevShotW, LastBullet, LastFire: LongInt;
    LastX, LastY: Single;
    FlagAt: array[0..63] of Byte;
    FlagTick: array[0..63] of LongInt;
    T: TAcTotals;
  end;

  PAcRec = ^TAcRec;

  TIncident = record
    ID, Kind: LongInt;
    Text: AnsiString;
  end;

var
  Ac: array[1..BE_PLAYERS] of TAcRec;
  Incidents: array[0..QUEUE_SIZE - 1] of TIncident;
  QHead: LongInt = 0;
  QCount: LongInt = 0;
  Enabled: Boolean = False;
  Slack: Single = 7;
  JumpSlack: Single = 40;
  JumpLag: Single = 10;
  RateFrac: Single = 0.85;
  BinkTicks: Single = 35;
  Grace: Single = 90;

procedure AcSet(Key: LongInt; Value: Single);
begin
  case Key of
    AC_ENABLED: Enabled := Value <> 0;
    AC_SLACK: Slack := Value;
    AC_JUMP_SLACK: JumpSlack := Value;
    AC_JUMP_LAG: JumpLag := Value;
    AC_RATE: RateFrac := Value;
    AC_BINK_TICKS: BinkTicks := Value;
    AC_GRACE: Grace := Value;
  end;
end;

function AcEnabled: Boolean;
begin
  Result := Enabled;
end;

procedure AcReset(ID: LongInt);
begin
  if not ValidID(ID) then
    Exit;
  FillChar(Ac[ID], SizeOf(TAcRec), 0);
  Ac[ID].T[T_SESSIONS] := 1;
  Ac[ID].T[T_SU_MIN] := -1;
  Ac[ID].LastBullet := -1;
end;

procedure AcResetAll;
var
  i: LongInt;
begin
  for i := 1 to BE_PLAYERS do
  begin
    Ac[i].LastAlive := False;
    Ac[i].LastSnap := 0;
  end;
end;

procedure Report(ID, Kind: LongInt; const Text: AnsiString);
var
  k: LongInt;
begin
  k := (QHead + QCount) mod QUEUE_SIZE;
  if QCount = QUEUE_SIZE then
    QHead := (QHead + 1) mod QUEUE_SIZE
  else
    Inc(QCount);
  Incidents[k].ID := ID;
  Incidents[k].Kind := Kind;
  Incidents[k].Text := Text;
end;

function AcNext(out ID, Kind: LongInt; out Text: AnsiString): Boolean;
begin
  Result := QCount > 0;
  ID := 0;
  Kind := 0;
  Text := '';
  if not Result then
    Exit;
  ID := Incidents[QHead].ID;
  Kind := Incidents[QHead].Kind;
  Text := Incidents[QHead].Text;
  Incidents[QHead].Text := '';
  QHead := (QHead + 1) mod QUEUE_SIZE;
  Dec(QCount);
end;

function AcWatched(W: LongInt): Boolean;
begin
  Result := False;
  if not ValidWeapon(W) then
    Exit;
  Result := ((Weapon[W].StartUp >= 8) and (Weapon[W].Interval > 5)) or (Weapon[W].Bink > 0) or
    (Weapon[W].MoveAcc >= 0.02);
end;

procedure AcKeys(Tick, Count: LongInt; I: PLongArr);
var
  k, ID, F: LongInt;
  Down: Boolean;
  R: ^TAcRec;
begin
  if Count > BE_PLAYERS then
    Count := BE_PLAYERS;
  for k := 0 to Count - 1 do
  begin
    ID := I^[k] shr 4;
    F := I^[k] and 15;
    if not ValidID(ID) then
      Continue;
    R := @Ac[ID];
    Down := (F and AF_FIRE) <> 0;
    if R^.KeyTick < Tick - 1 then
    begin
      R^.Known := not Down;
      R^.Rise := 0;
    end
    else if Down and not R^.Fire then
    begin
      R^.Rise := Tick;
      R^.Known := True;
    end;
    R^.Fire := Down;
    R^.KeyTick := Tick;
    R^.FlagAt[Tick and 63] := F;
    R^.FlagTick[Tick and 63] := Tick;
  end;
end;

procedure AcMoved(ID, Tick: LongInt);
begin
  if ValidID(ID) then
    Ac[ID].MovedTick := Tick;
end;

procedure AcHurt(Victim, Tick, W: LongInt);
begin
  if not ValidID(Victim) then
    Exit;
  Ac[Victim].HurtTick := Tick;
  Ac[Victim].HurtW := W;
end;

function Nm(ID: LongInt): AnsiString;
begin
  Result := WP[ID].Name;
  if Result = '' then
    Result := 'player ' + IntToStr(ID);
end;

function WName(W: LongInt): AnsiString;
begin
  if W = 8 then
    Result := 'Barrett'
  else
    Result := Weapon[W].Name;
end;

procedure Classify(R: PAcRec; W: LongInt; Damage, V: Single);
var
  Ratio, Base, Mid1, Mid2: Single;
  k: LongInt;
begin
  if not (Weapon[W].Style in [STYLE_PLAIN, STYLE_SHOTGUN, STYLE_ARROW]) then
    Exit;
  Base := V * Weapon[W].Damage;
  if (Base <= 0.0001) or (Damage <= 0) then
    Exit;
  Ratio := Damage / Base;
  for k := 0 to 2 do
  begin
    if (Ratio > Weapon[W].ModLegs * 0.93) and (Ratio < Weapon[W].ModHead * 1.07) then
      Break;
    Ratio := Ratio * 2;
  end;
  if (Ratio <= Weapon[W].ModLegs * 0.93) or (Ratio >= Weapon[W].ModHead * 1.07) then
    Exit;
  Mid1 := (Weapon[W].ModLegs + Weapon[W].ModChest) / 2;
  Mid2 := (Weapon[W].ModChest + Weapon[W].ModHead) / 2;
  if Mid2 - Mid1 < 0.01 then
    Exit;
  Inc(R^.T[T_HITS]);
  if Ratio > Mid2 then
    Inc(R^.T[T_HEADS]);
end;

function AcHit(Tick, Shooter, W, Bullet: LongInt; Damage, BX, BY, BVX, BVY, SX, SY: Single): LongInt;
var
  R: ^TAcRec;
  D, V: Single;
  n, Fire, Gap, Need, dt, Fl: LongInt;
begin
  Result := 0;
  if not Enabled or not ValidID(Shooter) or not ValidWeapon(W) then
    Exit;
  R := @Ac[Shooter];
  V := Sqrt(BVX * BVX + BVY * BVY);
  D := Sqrt(Sqr(BX - SX) + Sqr(BY - SY));
  n := 0;
  if V > 0.5 then
    n := Round(Ln(1 + 0.01 * D / V) / -Ln(0.99));
  if n > 420 then
    n := 420;
  if n < 0 then
    n := 0;
  Fire := Tick - n;
  Classify(R, W, Damage, V);
  if (Bullet = R^.LastBullet) and (Abs(Fire - R^.LastFire) <= 3) then
    Exit;
  R^.LastBullet := Bullet;
  R^.LastFire := Fire;
  Need := Weapon[W].StartUp;
  if (Need >= 8) and (Weapon[W].Interval > 5) then
    if R^.Known and (R^.Rise > 0) and (R^.KeyTick >= Fire - 1) and (Fire - R^.Rise >= -3) and
      (Fire - R^.Rise <= 120) then
    begin
      Gap := Fire - R^.Rise;
      if Gap < 0 then
        Gap := 0;
      Inc(R^.T[T_SU_N]);
      Inc(R^.T[T_SU_SUM], Gap);
      if (R^.T[T_SU_MIN] < 0) or (Gap < R^.T[T_SU_MIN]) then
        R^.T[T_SU_MIN] := Gap;
      if Gap < Need - Slack then
      begin
        Inc(R^.T[T_SU_BAD]);
        Report(Shooter, AK_STARTUP, Nm(Shooter) + ': ' + WName(W) + ' shot ' + IntToStr(Gap) +
          ' ticks after the fire key (start-up ' + IntToStr(Need) + ')');
        Result := AK_STARTUP;
      end;
    end;
  if (Weapon[W].Interval >= 20) and (R^.PrevShotW = W) and (Weapon[W].Style <> STYLE_SHOTGUN) then
  begin
    dt := Fire - R^.PrevShot;
    if (dt >= 3) and (dt < Round(Weapon[W].Interval * RateFrac) - 2) then
    begin
      Inc(R^.T[T_RATE]);
      Report(Shooter, AK_RATE, Nm(Shooter) + ': two ' + WName(W) + ' shots ' + IntToStr(dt) +
        ' ticks apart (fire interval ' + IntToStr(Weapon[W].Interval) + ')');
      Result := AK_RATE;
    end;
  end;
  if Abs(Fire - R^.PrevShot) > 1 then
  begin
    R^.PrevShot := Fire;
    R^.PrevShotW := W;
  end;
  if Weapon[W].Bink > 0 then
  begin
    Inc(R^.T[T_B_HITS]);
    if (R^.HurtW = W) and (R^.HurtTick > 0) and (Fire - R^.HurtTick >= 0) and (Fire - R^.HurtTick <= BinkTicks) then
    begin
      Inc(R^.T[T_BINK_HITS]);
      Report(Shooter, AK_BINK, Nm(Shooter) + ': ' + WName(W) + ' hit ' + IntToStr(Fire - R^.HurtTick) +
        ' ticks after being hit (bink ' + IntToStr(Weapon[W].Bink) + ')');
      if Result = 0 then
        Result := AK_BINK;
    end;
  end;
  if Weapon[W].MoveAcc >= 0.02 then
    if R^.FlagTick[Fire and 63] = Fire then
    begin
      Fl := R^.FlagAt[Fire and 63];
      Inc(R^.T[T_M_HITS]);
      if (Fl and (AF_MOVE or AF_AIR)) <> 0 then
      begin
        Inc(R^.T[T_MOVE_HITS]);
        if Result = 0 then
          Result := AK_MOVE;
      end;
    end;
end;

procedure AcWorld(Tick: LongInt);
var
  ID, dt: LongInt;
  D, Allowed: Single;
  R: ^TAcRec;
begin
  if not Enabled then
    Exit;
  for ID := 1 to BE_PLAYERS do
  begin
    R := @Ac[ID];
    if not (WP[ID].Active and WP[ID].Alive) then
    begin
      R^.LastAlive := False;
      Continue;
    end;
    if R^.LastAlive and WP[ID].Human and (Tick > R^.LastSnap) and (Tick - R^.LastSnap <= 120) and
      (Tick - R^.MovedTick > Grace) then
    begin
      dt := Tick - R^.LastSnap;
      D := Sqrt(Sqr(WP[ID].X - R^.LastX) + Sqr(WP[ID].Y - R^.LastY));
      Allowed := MAX_STEP * (dt + JumpLag) + JumpSlack;
      if D > Allowed then
      begin
        Inc(R^.T[T_JUMPS]);
        if Round(D) > R^.T[T_JUMP_MAX] then
          R^.T[T_JUMP_MAX] := Round(D);
        Report(ID, AK_JUMP, Nm(ID) + ': moved ' + IntToStr(Round(D)) + ' px in ' + IntToStr(dt) +
          ' ticks (at most ' + IntToStr(Round(Allowed)) + ')');
      end;
    end;
    R^.LastAlive := True;
    R^.LastX := WP[ID].X;
    R^.LastY := WP[ID].Y;
    R^.LastSnap := Tick;
  end;
end;

function Ratio(A, B: LongInt): Single;
begin
  Result := 0;
  if B > 0 then
    Result := A / B;
end;

function AcScoreOf(const T: TAcTotals): LongInt;
var
  S: Single;
begin
  S := 0;
  if T[T_SU_N] > 0 then
    S := S + 100 * T[T_SU_BAD] / (T[T_SU_N] + 1);
  S := S + 20 * T[T_RATE] + 15 * T[T_JUMPS];
  if T[T_B_HITS] >= 5 then
    S := S + 60 * Ratio(T[T_BINK_HITS], T[T_B_HITS]);
  if T[T_M_HITS] >= 5 then
    S := S + 40 * Ratio(T[T_MOVE_HITS], T[T_M_HITS]);
  if T[T_HITS] >= 20 then
    if Ratio(T[T_HEADS], T[T_HITS]) > 0.5 then
      S := S + 100 * (Ratio(T[T_HEADS], T[T_HITS]) - 0.5);
  if S > 100 then
    S := 100;
  Result := Round(S);
end;

function AcScore(ID: LongInt): LongInt;
begin
  Result := 0;
  if ValidID(ID) then
    Result := AcScoreOf(Ac[ID].T);
end;

procedure AcTotals(ID: LongInt; out T: TAcTotals);
var
  k: LongInt;
begin
  for k := 0 to AC_TOTALS - 1 do
    T[k] := 0;
  if ValidID(ID) then
    T := Ac[ID].T;
end;

function AcSessionFlags(ID: LongInt): LongInt;
begin
  Result := 0;
  if not ValidID(ID) then
    Exit;
  if Ac[ID].T[T_SU_BAD] > 0 then
    Result := Result or 1;
  if Ac[ID].T[T_RATE] > 0 then
    Result := Result or 2;
  if Ac[ID].T[T_JUMPS] > 0 then
    Result := Result or 4;
end;

function AcLineOf(const T: TAcTotals): AnsiString;
begin
  Result := IntToStr(AcScoreOf(T)) + '%: start-up ';
  if T[T_SU_N] > 0 then
    Result := Result + IntToStr(T[T_SU_BAD]) + '/' + IntToStr(T[T_SU_N]) + ' short (min ' + IntToStr(T[T_SU_MIN]) +
      ', avg ' + IntToStr(Round(T[T_SU_SUM] / T[T_SU_N])) + ' ticks)'
  else
    Result := Result + '-';
  Result := Result + ', fast shots ' + IntToStr(T[T_RATE]) + ', jumps ' + IntToStr(T[T_JUMPS]);
  if T[T_JUMPS] > 0 then
    Result := Result + ' (max ' + IntToStr(T[T_JUMP_MAX]) + ' px)';
  Result := Result + ', hits under bink ' + IntToStr(T[T_BINK_HITS]) + '/' + IntToStr(T[T_B_HITS]) +
    ', hits while moving ' + IntToStr(T[T_MOVE_HITS]) + '/' + IntToStr(T[T_M_HITS]) + ', head ' +
    IntToStr(T[T_HEADS]) + '/' + IntToStr(T[T_HITS]);
end;

end.
