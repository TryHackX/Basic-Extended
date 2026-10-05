program test_tk;

{ [TeamKill]'s eyes (be_tk) without the server: soldiers stand where the test puts them, shots are fed
  as the hook would feed them, and the classes, the intents and the spray events are checked. }

{$mode objfpc}{$H+}

uses
  SysUtils, be_hook, be_tk;

var
  PX, PY: array[1..32] of Single;
  Failed, Passed: LongInt;

function FakePoint(ID, K: LongInt; out X, Y: Single): Boolean;
begin
  X := PX[ID];
  Y := PY[ID] - 10;
  Result := True;
end;

procedure Check(Ok: Boolean; const What: string);
begin
  if Ok then
  begin
    Inc(Passed);
    WriteLn('ok   ', What);
  end
  else
  begin
    Inc(Failed);
    WriteLn('FAIL ', What);
  end;
end;

procedure Put(ID, Team: LongInt; X, Y: Single; Alive: Boolean);
begin
  PX[ID] := X;
  PY[ID] := Y;
  if Alive then
    TkPlayer(ID, Team, 1)
  else
    TkPlayer(ID, Team, 0);
end;

procedure Shot(Owner, Tick, Style: LongInt; X, Y, VX, VY: Single);
var
  E: TShotEvent;
begin
  E.Tick := Tick;
  E.Slot := 1;
  E.Owner := Owner;
  E.W := 3;
  E.Style := Style;
  E.X := X;
  E.Y := Y;
  E.VX := VX;
  E.VY := VY;
  E.Script := False;
  TkQueueShot(E);
end;

var
  i, n, Kind, S, T, N2, Reason, Intent, AtT, Cross, AtEnemy, All: LongInt;

begin
  Failed := 0;
  Passed := 0;
  TkPoint := @FakePoint;
  TkSet(TKC_ON, 1);
  TkSet(TKC_SPRAY_SHOTS, 5);
  TkSet(TKC_SPRAY_TICKS, 90);

  { 1. a spray: six shots of 1 at his mate 2, the enemy 3 far from the line }
  Put(1, 1, 0, 0, True);
  Put(2, 1, 200, 0, True);
  Put(3, 2, 200, 300, True);
  for i := 0 to 5 do
    Shot(1, 100 + i, 1, 0, -10, 10, 0);
  n := TkTick;
  Check(n = 1, 'one event after six aimed shots at the mate');
  Check(TkNext(Kind, S, T, N2, Reason), 'the event is there');
  Check((Kind = TK_EV_SPRAY) and (S = 1) and (T = 2) and (N2 >= 5), 'a spray of 1 at 2 (' + IntToStr(N2) + ' shots)');
  Intent := TkHit(1, 2, 1, 106, Reason);
  Check((Reason = TR_SPRAY) and (Intent = 100), 'his hit on 2 is a spray, 100%');
  Check(TkShots(1, 2, 106, AtT, Cross, AtEnemy, All) and (AtT = 6) and (All = 6), 'six of six shots at him');

  { 2. crossfire: the enemy 6 stands on the line behind the mate 5 }
  Put(4, 1, 0, 100, True);
  Put(5, 1, 200, 100, True);
  Put(6, 2, 400, 100, True);
  for i := 0 to 5 do
    Shot(4, 200 + i, 1, 0, 90, 10, 0);
  n := TkTick;
  Check(n = 0, 'no spray through a mate at an enemy behind him');
  Intent := TkHit(4, 5, 1, 206, Reason);
  Check((Reason = TR_CROSSFIRE) and (Intent = 20), 'the hit on the mate is crossfire, 20%');

  { 3. the enemy 8 stands before the mate 9: the shots are at the enemy }
  Put(7, 1, 0, 200, True);
  Put(8, 2, 100, 200, True);
  Put(9, 1, 300, 200, True);
  for i := 0 to 5 do
    Shot(7, 300 + i, 1, 0, 190, 10, 0);
  n := TkTick;
  Check(n = 0, 'no spray when the enemy is first on the line');
  Intent := TkHit(7, 9, 1, 306, Reason);
  Check((Reason = TR_STRAY) and (Intent = 20), 'a hit on the mate behind is a stray one, 20%');

  { 4. blasts: no enemy near the mate, then an enemy next to him }
  Intent := TkHit(1, 2, 4, 400, Reason);
  Check((Reason = TR_SPLASH_ALONE) and (Intent = 60), 'an M79 blast with no enemy near the mate: 60%');
  Put(3, 2, 260, 0, True);
  Intent := TkHit(1, 2, 2, 400, Reason);
  Check((Reason = TR_SPLASH_ENEMY) and (Intent = 10), 'a grenade blast with an enemy near the mate: 10%');

  { 5. a knife or fists }
  Intent := TkHit(1, 2, 11, 400, Reason);
  Check((Reason = TR_MELEE) and (Intent = 100), 'a knife on the mate: 100%');

  { 6. a dead mate on the line is nobody }
  Put(11, 1, 0, 500, True);
  Put(12, 1, 200, 500, False);
  for i := 0 to 5 do
    Shot(11, 500 + i, 1, 0, 490, 10, 0);
  n := TkTick;
  Check(n = 0, 'shots at a dead mate are no spray');
  Check(TkShots(11, 12, 506, AtT, Cross, AtEnemy, All) and (AtT = 0) and (All = 6), 'none of them at him');

  { 7. one aimed shot among three at enemies: mostly at the enemy }
  Put(13, 1, 0, 600, True);
  Put(14, 1, 200, 600, True);
  Put(15, 2, 150, 700, True);
  for i := 0 to 2 do
    Shot(13, 600 + i, 1, 0, 590, 150, 100);
  Shot(13, 603, 1, 0, 590, 10, 0);
  TkTick;
  Intent := TkHit(13, 14, 1, 604, Reason);
  Check((Intent = 25) and (Reason = TR_CROSSFIRE), 'one shot at the mate, three at an enemy: 25%, crossfire');

  { 8. one aimed shot and nothing else: meant }
  Put(16, 1, 0, 800, True);
  Put(17, 1, 200, 800, True);
  Shot(16, 800, 1, 0, 790, 10, 0);
  TkTick;
  Intent := TkHit(16, 17, 1, 801, Reason);
  Check((Intent = 90) and (Reason = TR_AIMED), 'a single aimed shot at the mate: 90%, aimed');

  { 9. switched off: shots are not taken }
  TkSet(TKC_ON, 0);
  Put(18, 1, 0, 900, True);
  Put(19, 1, 200, 900, True);
  for i := 0 to 5 do
    Shot(18, 900 + i, 1, 0, 890, 10, 0);
  n := TkTick;
  Check(n = 0, 'off: no events');
  Check(TkShots(18, 19, 906, AtT, Cross, AtEnemy, All) and (All = 0), 'off: no shots kept');

  WriteLn(IntToStr(Passed) + ' passed, ' + IntToStr(Failed) + ' failed');
  if Failed > 0 then
    Halt(1);
  WriteLn('test_tk: all passed');
end.
