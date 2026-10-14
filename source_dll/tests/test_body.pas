program test_body;

{ [Bleeding] and [Downed] (be_body) without the server: soldiers stand where the test puts them (a simple
  skeleton, standing or low), hits are fed as the script would feed them, and the events are checked -
  the hit places, the wounds, clotting, the blood, the drain, shock, bleeding out, bandaging, the kit, a
  downed soldier's time, a mate getting him up, the last stand, the bullets of a downed soldier. }

{$mode objfpc}{$H+}

uses
  SysUtils, be_hook, be_body;

var
  PX, PY: array[1..32] of Single;
  Low, Known: array[1..32] of Boolean;
  Failed, Passed: LongInt;

{ the points of the test's soldier: feet at PX, PY; the right side (1, 4, 5, 17) to the left of his middle,
  the left side (2, 3, 6, 18) to the right; standing or low }
function FakePoint(ID, K: LongInt; out X, Y: Single): Boolean;
var
  U: Single;
begin
  Result := Known[ID];
  X := PX[ID];
  Y := PY[ID];
  if not Result then
    Exit;
  case K of
    1: begin X := PX[ID] - 2; U := 1; end;
    2: begin X := PX[ID] + 2; U := 1; end;
    17: begin X := PX[ID] - 4; U := 0; end;
    18: begin X := PX[ID] + 4; U := 0; end;
    4: begin X := PX[ID] - 2; if Low[ID] then U := 3 else U := 6; end;
    3: begin X := PX[ID] + 2; if Low[ID] then U := 3 else U := 6; end;
    5: begin X := PX[ID] - 1; if Low[ID] then U := 4 else U := 11; end;
    6: begin X := PX[ID] + 1; if Low[ID] then U := 4 else U := 11; end;
    7: if Low[ID] then U := 5 else U := 13;
    9: if Low[ID] then U := 8 else U := 18;
    10: begin X := PX[ID] - 3; if Low[ID] then U := 7 else U := 16; end;
    11: begin X := PX[ID] + 3; if Low[ID] then U := 7 else U := 16; end;
    12: if Low[ID] then U := 9 else U := 21;
  else
    U := 10;
  end;
  Y := PY[ID] - U;
end;

{ 4.1: the server's ping compensation for bullet 7 at soldier 1 (he stood 5 px left and 22 px higher the
  shooter's ping ago); none for any other bullet }
function FakePing(V, B: LongInt; out DX, DY: Single): Boolean;
begin
  DX := 0;
  DY := 0;
  Result := (V = 1) and (B = 7);
  if Result then
  begin
    DX := -5;
    DY := -22;
  end;
end;

{ the stance as the server would have it: 2 crouching, 1 standing (0: not known - the keys then) }
function FakeStance(ID: LongInt): LongInt;
begin
  if not Known[ID] then
    Result := 0
  else if Low[ID] then
    Result := 2
  else
    Result := 1;
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

procedure Put(ID, Team: LongInt; X, Y: Single; IsLow: Boolean);
begin
  PX[ID] := X;
  PY[ID] := Y;
  Low[ID] := IsLow;
end;

var
  EvKind, EvId, EvP, EvQ: array[0..255] of LongInt;
  EvN: LongInt;
  T: LongInt = 1000;

procedure Run(Ticks: LongInt);
var
  n, k, a, b, c, d, j: LongInt;
begin
  EvN := 0;
  for j := 1 to Ticks do
  begin
    Inc(T);
    n := BdTick(T);
    for k := 1 to n do
      if BdNext(a, b, c, d) then
        if EvN <= High(EvKind) then
        begin
          EvKind[EvN] := a;
          EvId[EvN] := b;
          EvP[EvN] := c;
          EvQ[EvN] := d;
          Inc(EvN);
        end;
  end;
end;

function Has(Kind, ID, P: LongInt): Boolean;
var
  k: LongInt;
begin
  Result := False;
  for k := 0 to EvN - 1 do
    if EvKind[k] = Kind then
      if (ID < 0) or (EvId[k] = ID) then
        if (P < 0) or (EvP[k] = P) then
          Result := True;
end;

function QOf(Kind, ID: LongInt): LongInt;
var
  k: LongInt;
begin
  Result := -1;
  for k := 0 to EvN - 1 do
    if (EvKind[k] = Kind) and (EvId[k] = ID) then
      Result := EvQ[k];
end;

function PofEv(Kind, ID: LongInt): LongInt;
var
  k: LongInt;
begin
  Result := -1;
  for k := 0 to EvN - 1 do
    if (EvKind[k] = Kind) and (EvId[k] = ID) then
      Result := EvP[k];
end;

function Blood(ID: LongInt): Single;
var
  Worst, Wounds, Kits, Work, Pct, State: LongInt;
  Band: Single;
begin
  BdGet(ID, Result, Worst, Wounds, Band, Kits, Work, Pct, State);
end;

function Wounds(ID: LongInt): LongInt;
var
  Worst, Kits, Work, Pct, State: LongInt;
  Band, Bl: Single;
begin
  BdGet(ID, Bl, Worst, Result, Band, Kits, Work, Pct, State);
end;

function BandOf(ID: LongInt): Single;
var
  Worst, Wn, Kits, Work, Pct, State: LongInt;
  Bl: Single;
begin
  BdGet(ID, Bl, Worst, Wn, Result, Kits, Work, Pct, State);
end;

function KitsOf(ID: LongInt): LongInt;
var
  Worst, Wn, Work, Pct, State: LongInt;
  Band, Bl: Single;
begin
  BdGet(ID, Bl, Worst, Wn, Band, Result, Work, Pct, State);
end;

function WorkOf(ID: LongInt): LongInt;
var
  Worst, Wn, Kits, Pct, State: LongInt;
  Band, Bl: Single;
begin
  BdGet(ID, Bl, Worst, Wn, Band, Kits, Result, Pct, State);
end;

procedure Spawn(ID, Team: LongInt; X: Single);
begin
  Put(ID, Team, X, 0, False);
  BdPlayer(ID, Team, 1);
  BdHuman(ID, 1);
  BdSpawn(ID, T);
end;

procedure Shoot(Owner: LongInt);
var
  E: TShotEvent;
begin
  E.Tick := T;
  E.Slot := 5;
  E.Owner := Owner;
  E.W := 3;
  E.Style := 1;
  E.X := 0;
  E.Y := 0;
  E.VX := 1;
  E.VY := 0;
  BdShot(E);
end;

var
  i, n, k, W, P, Gap: LongInt;
  B0: Single;
begin
  Failed := 0;
  Passed := 0;
  RandSeed := 12345;
  BdPoint := @FakePoint;
  BdStance := @FakeStance;
  BdPing := nil;
  for i := 1 to 32 do
  begin
    Known[i] := True;
    PX[i] := 5000 + i * 100;
    PY[i] := 0;
  end;
  BdSet(BDC_ON, 1);
  BdSet(BDC_DOWN, 1);
  BdSet(BDC_CRIT, 100);
  BdSet(BDC_CRIT_DMG, 10);
  BdSet(BDC_RATE1, 3);
  BdSet(BDC_RATE2, 6);
  BdSet(BDC_RATE3, 12);
  BdSet(BDC_CLOT1, 120);
  BdSet(BDC_CLOT_RANDOM, 0);
  BdSet(BDC_CLOT2, 0);
  BdSet(BDC_CLOT3, 0);
  BdSet(BDC_WEAK, 75);
  BdSet(BDC_SHOCK, 55);
  BdSet(BDC_DEATH, 40);
  BdSet(BDC_DRAIN, 2);
  BdSet(BDC_SHOCK_EVERY, 60);
  BdSet(BDC_SHOCK_CHANCE, 100);
  BdSet(BDC_SHOCK_TICKS, 90);
  BdSet(BDC_REGEN, 6);
  BdSet(BDC_REGEN_DELAY, 60);
  BdSet(BDC_BANDAGE, 100);
  BdSet(BDC_BAND_T1, 60);
  BdSet(BDC_BAND_T2, 150);
  BdSet(BDC_BAND_T3, 240);
  BdSet(BDC_BAND_C1, 10);
  BdSet(BDC_BAND_C2, 25);
  BdSet(BDC_BAND_C3, 40);
  BdSet(BDC_BAND_LOW, 1);
  BdSet(BDC_BAND_AUTO, 1);
  BdSet(BDC_AUTO_DELAY, 30);
  BdSet(BDC_KITS, 1);
  BdSet(BDC_KIT_TICKS, 120);
  BdSet(BDC_KIT_BLOOD, 25);
  BdSet(BDC_DOWN_TICKS, 600);
  BdSet(BDC_REVIVE_R, 30);
  BdSet(BDC_REVIVE_TICKS, 180);
  BdSet(BDC_REVIVE_LOW, 1);
  BdSet(BDC_SELF_REVIVE, 1);
  BdSet(BDC_BOTS_REVIVE, 1);
  BdSet(BDC_DOWN_BLEED, 1);
  BdSet(BDC_STILL, 0.6);
  BdSet(BDC_BOTS, 1);
  BdSet(BDC_BOT_BANDAGE, 300);
  BdSet(BDC_LAST_STAND, 1);
  BdSet(BDC_TEAMS, 1);

  { 1. hit places: a bullet left on the edge of the circle it hit (the server's circles: 7 px, 2 px left) }
  Spawn(1, 1, 0);
  Check(BdHitPart(1, 0, 1, -2 - 7, -21, 10, 0) = WP_HEAD, 'a bullet on the head circle''s edge: the head');
  Check(BdHitPart(1, 0, 1, -1 - 2 - 7, -11, 10, 0) = WP_TORSO, 'on a hip circle''s edge: the torso');
  Check(BdHitPart(1, 0, 1, -2 - 2, -6 + 7, 0, 10) = WP_LEGS, 'on a knee circle''s edge from below: the legs');
  Check(BdHitPart(1, 0, 11, -7, -21, 10, 0) = WP_HEAD, 'a knife: no 2 px shift');
  Check(BdHitPart(1, 0, 1, -14, -26, 10, 0) = WP_HEAD, 'off the edges: the line enters the head first');
  Check(BdHitPart(1, 0, 1, -14, -21, 10, 0) = WP_TORSO, 'level with the head from the left: the shoulder first (the server''s rule)');
  Check(BdHitPart(1, 0, 7, -2 - 7 - 10, -21, 10, 0) = WP_HEAD, 'an arrow is left a step back');
  { 4.1: the server tests a human's circles where he stood the shooter's ping ago }
  BdPing := @FakePing;
  Check(BdHitPart(1, 8, 1, -2 - 7, -21, 10, 0) = WP_HEAD, 'a bullet without a shift on the head''s edge: the head');
  Check(BdHitPart(1, 7, 1, -2 - 7, -21, 10, 0) = WP_LEGS, 'the same place with the ping''s shift: the knee where he stood');
  BdPing := nil;

  { 2. a hit opens a wound (Crit 100 at 10% of the health); fire and fists do not; the blood runs out }
  n := BdHit(1, 2, 3, 1, 30, 150, WP_TORSO, T);
  Check(n > 0, 'a hit of a fifth of the health opens a wound');
  Check(Wounds(1) = 1, 'one wound');
  Check(BdHit(1, 2, 3, 5, 30, 150, WP_TORSO, T) = 0, 'fire opens none');
  Check(BdHit(1, 2, 3, 6, 30, 150, WP_TORSO, T) = 0, 'a fist opens none');
  Check(BdHit(1, 2, 3, 1, 0.5, 150, WP_TORSO, T) = 0, 'a scratch of 0.5 opens none (chance 3%)');
  B0 := Blood(1);
  Run(60);
  Check(Blood(1) < B0, 'the blood runs out');
  Check(Has(BDE_HUD, 1, -1), 'his line changes');

  { 3. a graze stops by itself after Clot1 ticks; then the blood comes back after RegenDelay }
  Spawn(3, 1, 200);
  BdSet(BDC_ART_SHARE, 0);
  BdSet(BDC_HEAVY_SHARE, 0);
  Check(BdHit(3, 2, 3, 1, 20, 150, WP_TORSO, T) = WK_GRAZE, 'no heavy or arterial share: a graze');
  Run(119);
  Check(Wounds(3) = 1, 'the graze still bleeds');
  Run(3);
  Check((Wounds(3) = 0) and Has(BDE_CLOSED, 3, WK_GRAZE), 'it stops by itself (clotted)');
  B0 := Blood(3);
  Run(60);
  Check(Blood(3) > B0, 'no wound for RegenDelay: the blood comes back');
  { GrazeRandom: each graze stops somewhere between Clot1Min and Clot1 }
  BdSet(BDC_CLOT_RANDOM, 1);
  BdSet(BDC_CLOT1_MIN, 30);
  for i := 20 to 27 do
  begin
    Spawn(i, 2, 6000 + i * 100);
    BdHit(i, 2, 3, 1, 20, 150, WP_TORSO, T);
  end;
  Run(29);
  n := 0;
  for i := 20 to 27 do
    n := n + Wounds(i);
  Check(n = 8, 'random clotting: none stops before Clot1Min');
  k := 0;
  for i := 1 to 92 do
  begin
    Run(1);
    W := 0;
    for P := 20 to 27 do
      W := W + Wounds(P);
    if (W > 0) and (W < 8) then
      Inc(k);
  end;
  n := 0;
  for i := 20 to 27 do
    n := n + Wounds(i);
  Check((n = 0) and (k > 0), 'random clotting: all stop by Clot1, not all at once');
  for i := 20 to 27 do
    BdPlayer(i, 2, 0);
  BdSet(BDC_CLOT_RANDOM, 0);

  { 4. a heavy wound, low and still: bandaged by itself after AutoDelay, in HeavySeconds, 25% of the bandage }
  BdSet(BDC_HEAVY_SHARE, 100);
  Spawn(4, 1, 400);
  Check(BdHit(4, 2, 3, 1, 60, 150, WP_TORSO, T) = WK_HEAVY, 'a heavy wound');
  Low[4] := True;
  Run(40);
  Check(Has(BDE_WORK, 4, BW_BANDAGE), 'low and still: he starts bandaging by himself');
  Run(160);
  Check(Has(BDE_BANDAGED, 4, WK_HEAVY) and (Wounds(4) = 0), 'bandaged after 2.5 s');
  Check(Abs(BandOf(4) - 75) < 0.01, 'the bandage used: 25%');
  { standing up stops it; a shot stops it }
  Low[4] := False;
  Check(BdHit(4, 2, 3, 1, 60, 150, WP_TORSO, T) = WK_HEAVY, 'another heavy wound');
  Run(10);
  Check(not Has(BDE_WORK, 4, -1), 'standing: no bandaging');
  Low[4] := True;
  Run(40);
  Check(Has(BDE_WORK, 4, BW_BANDAGE), 'low again: bandaging');
  Shoot(4);
  Run(1);
  Check(Has(BDE_WORK_STOP, 4, BW_BANDAGE), 'a shot stops it');
  { moving stops it }
  Run(60);
  Check(Has(BDE_WORK, 4, BW_BANDAGE), 'still again after the shot: bandaging again');
  PX[4] := PX[4] + 30;
  Run(2);
  Check(Has(BDE_WORK_STOP, 4, BW_BANDAGE), 'moving stops it');
  Low[4] := False;

  { 5. an arterial wound needs 40%: with 30% left he cannot; a kit closes all and gives blood back }
  BdSet(BDC_HEAVY_SHARE, 0);
  BdSet(BDC_ART_SHARE, 100);
  BdSet(BDC_RATE3, 1);
  Spawn(5, 1, 600);
  Check(BdHit(5, 2, 3, 1, 20, 150, WP_LEGS, T) = WK_ARTERY, 'an arterial wound (the leg)');
  Check(BdHit(5, 2, 3, 1, 20, 150, WP_LEGS, T) = WK_ARTERY, 'a second one');
  Check(BdWant(5, BW_BANDAGE) = 1, 'the bandage can take the first');
  Low[5] := True;
  Run(250);
  Check(Has(BDE_BANDAGED, 5, WK_ARTERY) and (Wounds(5) = 1), 'the first arterial wound bandaged in 4 s');
  Check(Abs(BandOf(5) - 60) < 0.01, '40% used');
  Run(250);
  Check(Abs(BandOf(5) - 20) < 0.01, 'the second one too: 20% left');
  Check(BdHit(5, 2, 3, 1, 20, 150, WP_LEGS, T) = WK_ARTERY, 'a third one');
  Check(BdWant(5, BW_BANDAGE) = -1, 'not enough bandage for an arterial wound (-1)');
  Check(BdWant(5, BW_KIT) = 1, 'the kit can');
  Run(125);
  Check(Has(BDE_KIT, 5, -1) and (Wounds(5) = 0) and (KitsOf(5) = 0), 'the kit closed it (no kit left)');
  Check(BdWant(5, BW_KIT) = -2, 'no kit (-2)');
  Low[5] := False;
  BdSet(BDC_RATE3, 12);

  { 6. low blood: drain below Weak, shock below Shock (chance 100%), bled out at Death: the culprit and his
    weapon }
  BdSet(BDC_ART_SHARE, 100);
  BdSet(BDC_DOWN, 0);
  BdSet(BDC_SHOCK_EVERY, 10);
  Spawn(6, 1, 800);
  Check(BdHit(6, 7, 4, 1, 30, 150, WP_LEGS, T) = WK_ARTERY, 'an arterial wound by 7 with weapon 4');
  n := 0;
  k := 0;
  i := 0;
  while (i < 900) and not Has(BDE_BLED, 6, -1) do
  begin
    Run(1);
    Inc(i);
    if Has(BDE_DRAIN, 6, -1) then
      Inc(n);
    if Has(BDE_SHOCK, 6, -1) then
      Inc(k);
  end;
  Check(n > 0, 'below WeakBlood his health drains');
  Check(k > 0, 'below ShockBlood a shock');
  Check(Has(BDE_BLED, 6, 7) and (QOf(BDE_BLED, 6) = 4), 'bled out at DeathBlood: the culprit 7, weapon 4');
  BdPlayer(6, 1, 0);
  Check(Wounds(6) = 0, 'his death ends his wounds');
  { a new shock waits ShockCheckSeconds after the last one ended: no chain of shocks }
  BdSet(BDC_RATE3, 3);
  Spawn(30, 1, 5200);
  Check(BdHit(30, 7, 4, 1, 30, 150, WP_LEGS, T) = WK_ARTERY, 'an arterial wound, slower');
  k := 0;
  n := -1;
  Gap := 100000;
  i := 0;
  while (i < 1500) and not Has(BDE_BLED, 30, -1) do
  begin
    Run(1);
    Inc(i);
    if Has(BDE_SHOCK, 30, -1) then
    begin
      if n >= 0 then
        if i - n < Gap then
          Gap := i - n;
      n := i;
      Inc(k);
    end;
  end;
  Check((k >= 2) and (Gap >= 100), 'shocks come apart: ShockSeconds and then ShockCheckSeconds between them');
  BdPlayer(30, 1, 0);
  BdSet(BDC_RATE3, 12);
  BdSet(BDC_SHOCK_EVERY, 60);

  { 7. down: his time runs out; a mate low next to him gets him up (his time waits meanwhile); a bot mate
    next to him counts; standing or away does not }
  BdSet(BDC_DOWN, 1);
  BdSet(BDC_CRIT, 0);
  Spawn(10, 1, 1500);
  Spawn(11, 1, 2000);
  BdDown(10, 20, 3, T);
  Check(BdMuted(10), 'a downed soldier''s bullets are taken out');
  Run(300);
  Check(BdDownLeft(10, T) > 250, 'down: about 5 s left of 10');
  Put(11, 1, 1515, 0, False);
  Run(30);
  Check(not Has(BDE_WORK, 11, -1), 'a mate standing next to him does not help');
  Low[11] := True;
  Run(2);
  Check(Has(BDE_WORK, 11, BW_REVIVE) and (BdWorkOn(11) = 10) and (BdHelper(10) = 11), 'low next to him: he helps');
  Run(100);
  Low[11] := False;
  Run(1);
  Check(Has(BDE_WORK_STOP, 11, BW_REVIVE), 'he stands up: it stops');
  Low[11] := True;
  Run(185);
  Check(Has(BDE_REVIVED, 10, 11) and not BdMuted(10), 'low again for ReviveSeconds: he is up');
  { his time runs out }
  Low[11] := False;
  PX[11] := 3000;
  BdDown(10, 20, 3, T);
  Run(605);
  Check(Has(BDE_DOWN_END, 10, DE_TIME), 'nobody helped: his time ran out');
  BdPlayer(10, 1, 0);
  { the last stand: his team has nobody up (no kit of his own) }
  BdSet(BDC_KITS, 0);
  Spawn(12, 2, 3000);
  Spawn(13, 2, 3500);
  BdDown(12, 20, 3, T);
  Run(5);
  Check(not Has(BDE_DOWN_END, 12, -1), 'a mate of his is up: he waits');
  BdPlayer(13, 2, 0);
  Run(1);
  Check(Has(BDE_DOWN_END, 12, DE_ALONE), 'nobody of his team up: he ends at once');
  BdPlayer(12, 2, 0);
  BdSet(BDC_KITS, 1);
  { a bot mate next to him (BotsRevive): no need to be low }
  Spawn(14, 3, 4000);
  Spawn(15, 3, 4012);
  BdHuman(15, 0);
  BdSet(BDC_CRIT, 100);
  Check(BdHit(14, 20, 3, 1, 60, 150, WP_LEGS, T) > 0, 'a wound before he goes down');
  BdSet(BDC_CRIT, 0);
  BdDown(14, 20, 3, T);
  Run(185);
  Check(Has(BDE_REVIVED, 14, 15), 'a bot mate next to him gets him up');
  Check(Wounds(14) = 0, 'the mate who got him up stopped his bleeding');
  { a downed bot with a kit of its own uses it after BotBandage ticks (it cannot crouch) }
  Spawn(18, 4, 4700);
  BdHuman(18, 0);
  BdDown(18, 20, 3, T);
  Run(299);
  Check(not Has(BDE_REVIVED, 18, 18), 'a downed bot with a kit waits BotBandage ticks');
  Run(2);
  Check(Has(BDE_REVIVED, 18, 18) and (KitsOf(18) = 0), 'then its own kit gets it up');
  { a kit of his own: low (crouch) for KitSeconds gets him up }
  Spawn(16, 4, 4500);
  BdDown(16, 20, 3, T);
  Low[16] := True;
  Run(125);
  Check(Has(BDE_KIT, 16, -1) and (QOf(BDE_KIT, 16) = 1) and Has(BDE_REVIVED, 16, 16), 'his own kit got him up');
  Low[16] := False;
  { he gives up }
  Spawn(17, 4, 4600);
  BdDown(17, 21, 5, T);
  BdGiveUp(17);
  Run(1);
  Check(Has(BDE_DOWN_END, 17, DE_GAVE_UP), 'he gave up');
  W := 0;
  P := BdCulprit(17, W);
  Check(P = 0, 'up again (gave up): no culprit kept');

  { 8. a bot bandages itself after BotBandage ticks }
  BdSet(BDC_CRIT, 100);
  BdSet(BDC_ART_SHARE, 0);
  BdSet(BDC_HEAVY_SHARE, 100);
  Spawn(20, 1, 6000);
  BdHuman(20, 0);
  Check(BdHit(20, 2, 3, 1, 60, 150, WP_TORSO, T) = WK_HEAVY, 'a bot''s heavy wound');
  Run(310);
  Check(Has(BDE_BANDAGED, 20, WK_HEAVY) and (Wounds(20) = 0), 'the bot bandaged itself after 5 s');
  { healed from outside: a medic or a polygon closes the grazes, a health kit everything }
  Spawn(21, 1, 6500);
  BdSet(BDC_HEAVY_SHARE, 0);
  Check(BdHit(21, 2, 3, 1, 20, 150, WP_TORSO, T) = WK_GRAZE, 'a graze');
  BdSet(BDC_HEAVY_SHARE, 100);
  Check(BdHit(21, 2, 3, 1, 60, 150, WP_TORSO, T) = WK_HEAVY, 'a heavy wound');
  BdHeal(21, BC_HEALED, 5);
  Check(Wounds(21) = 1, 'healed: the graze closed, the heavy wound not');
  BdHeal(21, BC_KIT, 20);
  Check(Wounds(21) = 0, 'a health kit: every wound closed');

  { 9. a blast opens shrapnel wounds (up to BlastMax); the keys when the stance is not known }
  BdSet(BDC_BLAST, 3);
  Spawn(22, 1, 7000);
  n := BdHit(22, 2, 7, 4, 100, 150, 0, T);
  Check((n > 0) and (Wounds(22) >= 2), 'an M79 blast: shrapnel wounds (' + IntToStr(Wounds(22)) + ')');
  BdStance := nil;
  Spawn(23, 1, 7500);
  BdSet(BDC_HEAVY_SHARE, 100);
  Check(BdHit(23, 2, 3, 1, 60, 150, WP_TORSO, T) = WK_HEAVY, 'a heavy wound (no stance known)');
  Low[23] := True;
  Run(1);
  Check((BdNear and (LongWord(1) shl 22)) <> 0, 'his keys are asked for');
  for i := 1 to 45 do
  begin
    BdLow(23, 1);
    Run(1);
  end;
  Check(WorkOf(23) = BW_BANDAGE, 'told low (keys): bandaging');
  for i := 1 to 45 do
  begin
    BdLow(23, 0);
    Run(1);
  end;
  Check(WorkOf(23) = BW_NONE, 'told not low: no bandaging');
  BdStance := @FakeStance;

  { 10. round 20: a forget (a join, a map start) keeps him alive and human; the places of his wounds and their rate;
    a transfusion; a class's revive speed; the helper of a soldier who died stops; the events of the killing hit go
    with the death }
  Spawn(24, 1, 8000);
  BdForget(24);
  BdSet(BDC_HEAVY_SHARE, 100);
  Check(BdHit(24, 2, 3, 1, 60, 150, WP_TORSO, T) > 0, 'after a forget he still bleeds');
  Check(BdHit(24, 2, 3, 1, 60, 150, WP_LEGS, T) > 0, 'a second wound, in the leg');
  n := BdPlaces(24, k, W);
  Check(((n and 15) = 0) and (((n shr 8) and 15) = 1) and (((n shr 16) and 15) = 1),
    'the places: torso 1, legs 1 (' + IntToStr(n) + ')');
  Check(k >= 1200, 'his rate is both wounds together (' + IntToStr(k) + ' hundredths a second)');
  Check(W >= 0, 'the seconds until he bleeds out (' + IntToStr(W) + ')');
  { round 26: the blood line's list made here (be_body BdWoundList) }
  Check((Pos('torso ', BdWoundList(24)) = 1) and (Pos(', leg ', BdWoundList(24)) > 0) and
    (Pos(' x', BdWoundList(24)) = 0), 'the list: ' + BdWoundList(24));
  BdHit(24, 2, 3, 1, 60, 150, WP_LEGS, T);
  Check(Pos(' x2', BdWoundList(24)) > 0, 'two in the leg: ' + BdWoundList(24));
  BdHudText(6, 'L');
  BdHudText(7, 'H');
  BdHudText(8, 'A');
  BdHudText(0, '[{place}:{kind}:{count}]');
  Check(Pos('[torso:', BdWoundList(24)) = 1, 'the texts set: ' + BdWoundList(24));
  BdHudText(0, '{place} {kind}{many}');
  BdHudText(6, 'light');
  BdHudText(7, 'heavy');
  BdHudText(8, 'arterial');
  Spawn(25, 1, 8500);
  BdHit(25, 2, 3, 1, 60, 150, WP_TORSO, T);
  Run(240);
  BdHeal(25, BC_KIT, 0);
  B0 := Blood(25);
  BdTransfuse(25, 15, 60);
  Run(61);
  Check((B0 < 85) and (Blood(25) >= B0 + 14.5), 'a transfusion: 15 blood back within a second (' + FloatToStr(B0) +
    ' -> ' + FloatToStr(Blood(25)) + ')');
  Spawn(26, 1, 9000);
  Spawn(27, 1, 9005);
  BdSet(BDC_REVIVE_TICKS, 240);
  BdPerk(27, 1, 4, 0);
  BdDown(26, 2, 3, T);
  Low[27] := True;
  Run(75);
  Check(Has(BDE_REVIVED, 26, 27), 'a medic (4 times faster) gets him up within 75 ticks');
  Low[27] := False;
  Spawn(29, 1, 10000);
  Spawn(30, 1, 10005);
  BdDown(29, 2, 3, T);
  Low[30] := True;
  Run(10);
  Check(WorkOf(30) = BW_REVIVE, 'a mate helps him up');
  BdPlayer(29, 1, 0);
  Run(1);
  Check(WorkOf(30) = BW_NONE, 'he died: the mate stops helping');
  Low[30] := False;
  Spawn(31, 1, 10500);
  BdHit(31, 2, 3, 1, 60, 150, WP_TORSO, T);
  BdPlayer(31, 1, 0);
  Run(1);
  Check(not Has(BDE_WOUND, 31, -1), 'the killing hit''s wound event went with the death');

  { 11. a pause: nothing ticks for 600 ticks, then everything moves on by them - the blood is where it was, the
    downed time is not used up }
  Spawn(1, 1, 11000);
  BdSet(BDC_HEAVY_SHARE, 100);
  BdHit(1, 2, 3, 1, 60, 150, WP_TORSO, T);
  Run(30);
  B0 := Blood(1);
  Spawn(2, 2, 11500);
  BdDown(2, 1, 3, T);
  k := BdDownLeft(2, T);
  Inc(T, 600);
  BdShift(600);
  Run(1);
  Check(Blood(1) >= B0 - 1, 'a pause: no blood lost while it lasted (' + FloatToStr(B0) + ' -> ' +
    FloatToStr(Blood(1)) + ')');
  Check(BdDownLeft(2, T) >= k - 2, 'a pause: the downed time waits (' + IntToStr(k) + ' -> ' +
    IntToStr(BdDownLeft(2, T)) + ')');

  { 12. at most MaxArterial arterial wounds open at once: the next arterial hit opens none; a graze still opens }
  BdSet(BDC_HEAVY_SHARE, 0);
  BdSet(BDC_ART_SHARE, 100);
  BdSet(BDC_MAX3, 1);
  Spawn(26, 1, 12000);
  Check(BdHit(26, 2, 3, 1, 20, 150, WP_LEGS, T) = WK_ARTERY, 'MaxArterial 1: an arterial wound');
  Check(BdHit(26, 2, 3, 1, 20, 150, WP_LEGS, T) = 0, 'MaxArterial 1: not a second one');
  Check(Wounds(26) = 1, 'one wound open');
  BdSet(BDC_ART_SHARE, 0);
  Check(BdHit(26, 2, 3, 1, 20, 150, WP_TORSO, T) = WK_GRAZE, 'a graze still opens');
  BdSet(BDC_MAX1, 1);
  Check(BdHit(26, 2, 3, 1, 20, 150, WP_TORSO, T) = 0, 'MaxGrazes 1: not a second graze');
  BdSet(BDC_MAX1, 0);
  BdSet(BDC_MAX3, 0);

  { 13. round 24: bleeding out with OutMode 1 - no death at DeathBlood, the health drains twice a second and more and
    more; a bandage stops it }
  BdSet(BDC_OUT_MODE, 1);
  BdSet(BDC_OUT_DRAIN, 5);
  BdSet(BDC_OUT_GROW, 1);
  BdSet(BDC_DOWN, 0);
  BdSet(BDC_SHOCK_CHANCE, 0);
  BdSet(BDC_ART_SHARE, 100);
  BdSet(BDC_CRIT, 100);
  BdSet(BDC_RATE3, 12);
  Spawn(7, 1, 13000);
  Check(BdHit(7, 9, 4, 1, 30, 150, WP_LEGS, T) = WK_ARTERY, 'an arterial wound');
  i := 0;
  while (i < 600) and not Has(BDE_FADING, 7, -1) do
  begin
    Run(1);
    Inc(i);
  end;
  Check(Has(BDE_FADING, 7, -1) and (Blood(7) <= 40.5), 'at DeathBlood: he bleeds out slowly (BDE_FADING)');
  n := 0;
  k := 0;
  W := 0;
  for i := 1 to 120 do
  begin
    Run(1);
    if Has(BDE_BLED, 7, -1) then
      Inc(W);
    if Has(BDE_DRAIN, 7, -1) then
      Inc(n);
  end;
  Check(W = 0, 'no instant death under DeathBlood');
  Check(n >= 3, 'the health drains twice a second (' + IntToStr(n) + ' in 2 s)');
  BdSet(BDC_ART_SHARE, 0);
  BdSet(BDC_HEAVY_SHARE, 0);
  { the drain grows: the amount of the last drain is more than of the first }
  Spawn(8, 1, 13500);
  BdSet(BDC_ART_SHARE, 100);
  Check(BdHit(8, 9, 4, 1, 30, 150, WP_LEGS, T) = WK_ARTERY, 'another arterial wound');
  BdSet(BDC_ART_SHARE, 0);
  k := -1;
  W := -1;
  for i := 1 to 900 do
  begin
    Run(1);
    if Has(BDE_DRAIN, 8, -1) then
    begin
      n := PofEv(BDE_DRAIN, 8);
      if Blood(8) <= 40 then
      begin
        if k < 0 then
          k := n;
        W := n;
      end;
    end;
  end;
  Check((k > 0) and (W > k), 'bleeding out: the drain grows (' + IntToStr(k) + ' -> ' + IntToStr(W) + ')');
  { bandaged: the fast drain stops }
  Low[8] := True;
  BdSet(BDC_BANDAGE, 100);
  BdSupplies(8, 100, 0, 0);
  Run(300);
  Check(Wounds(8) = 0, 'bandaged');
  Run(60);
  n := PofEv(BDE_DRAIN, 8);
  Check((n < 0) or (n <= 300), 'no wound open: only the slow drain (' + IntToStr(n) + ')');
  Low[8] := False;
  BdSet(BDC_OUT_MODE, 0);

  { 14. round 24: falling freely without a key held bandages (AirOn); without it, not }
  BdSet(BDC_AIR, 1);
  BdSet(BDC_HEAVY_SHARE, 100);
  Spawn(9, 1, 14000);
  Check(BdHit(9, 2, 3, 1, 60, 150, WP_TORSO, T) = WK_HEAVY, 'a heavy wound');
  for i := 1 to 60 do
  begin
    PY[9] := PY[9] + 4;
    Run(1);
  end;
  Check(WorkOf(9) = BW_NONE, 'falling, not told: no bandaging');
  for i := 1 to 200 do
  begin
    PY[9] := PY[9] + 4;
    BdAir(9, 1);
    Run(1);
    if Has(BDE_BANDAGED, 9, -1) then
      Break;
  end;
  Check(Wounds(9) = 0, 'falling freely (told): bandaged in the air');
  BdSet(BDC_AIR, 0);

  { 15. round 24: a medic bandages his mate (his own wound first); the mate is told }
  Spawn(10, 1, 15000);
  Spawn(11, 1, 15020);
  BdMedic(11, 40);
  BdSupplies(11, 200, 0, 0);
  Check(BdHit(10, 2, 3, 1, 60, 150, WP_TORSO, T) = WK_HEAVY, 'the mate''s heavy wound');
  Check(BdHit(11, 2, 3, 1, 60, 150, WP_TORSO, T) = WK_HEAVY, 'the medic''s heavy wound');
  Low[11] := True;
  Run(40);
  Check(Has(BDE_WORK, 11, BW_BANDAGE) and (BdWorkOn(11) = 0), 'the medic bandages himself first');
  Run(160);
  Check((Wounds(11) = 0) and (Wounds(10) = 1), 'his own wound bandaged, the mate''s still open');
  i := 0;
  while (i < 400) and not Has(BDE_TREATED, 11, 10) do
  begin
    Run(1);
    Inc(i);
    if Has(BDE_TREAT, 11, 10) then
      k := 1;
  end;
  Check(Has(BDE_TREATED, 11, 10) and (Wounds(10) = 0), 'then the mate''s wound (BDE_TREATED)');
  Check(Abs(BandOf(11) - 150) < 0.01, 'from the medic''s bandage: 200 - 25 - 25 = 150');
  { too far: nothing }
  Check(BdHit(10, 2, 3, 1, 60, 150, WP_TORSO, T) = WK_HEAVY, 'the mate wounded again');
  PX[10] := 15100;
  Run(200);
  Check(Wounds(10) = 1, 'the mate 80 px away: the medic does not reach him');
  BdMedic(11, 0);
  Low[11] := False;
  BdPlayer(10, 1, 0);
  BdPlayer(11, 1, 0);

  { 16. round 24: a vest covers the torso for the next hit: no wound there; the legs still bleed; it counts once }
  Spawn(12, 1, 16000);
  BdSet(BDC_ART_SHARE, 0);
  BdCover(12, COVER_TORSO);
  Check(BdHit(12, 2, 3, 1, 60, 150, WP_TORSO, T) = 0, 'a vest: no wound in the torso');
  BdCover(12, COVER_TORSO);
  Check(BdHit(12, 2, 3, 1, 60, 150, WP_LEGS, T) > 0, 'the legs bleed');
  Check(BdHit(12, 2, 3, 1, 60, 150, WP_TORSO, T) > 0, 'not told for this hit: the torso bleeds');
  { round 26: a blast's shrapnel still bleeds in the torso under a vest (the vest stops a bullet's hit there) }
  k := 0;
  for i := 1 to 30 do
    if k = 0 then
    begin
      BdPlayer(12, 1, 0);
      Spawn(12, 1, 16000);
      BdCover(12, COVER_TORSO);
      BdHit(12, 2, 7, 4, 100, 150, 0, T);
      if ((BdPlaces(12, n, W) shr 8) and 15) > 0 then
        k := i;
    end;
  Check(k > 0, 'a blast''s shrapnel opens a torso wound under the vest (try ' + IntToStr(k) + ')');
  BdPlayer(12, 1, 0);

  { 17. round 26: a medic killed while bandaging a mate gives him back - he bandages himself }
  Spawn(13, 1, 17000);
  Spawn(14, 1, 17020);
  BdMedic(14, 40);
  BdSupplies(14, 200, 0, 0);
  Check(BdHit(13, 2, 3, 1, 60, 150, WP_TORSO, T) = WK_HEAVY, 'the mate''s heavy wound');
  Low[14] := True;
  i := 0;
  while (i < 300) and not Has(BDE_TREAT, 14, 13) do
  begin
    Run(1);
    Inc(i);
  end;
  Check(BdWorkOn(14) = 13, 'the medic treats the mate');
  BdPlayer(14, 1, 0);
  Low[13] := True;
  Run(400);
  Check(Wounds(13) = 0, 'the medic died: the mate bandaged himself');
  Low[13] := False;
  Low[14] := False;
  BdPlayer(13, 1, 0);

  { 18. round 26: AutoBandage 0 - a medic with no wound of his own bandages a mate when he asks (!bandage) }
  BdSet(BDC_BAND_AUTO, 0);
  Spawn(15, 1, 18000);
  Spawn(16, 1, 18020);
  BdMedic(16, 40);
  BdSupplies(16, 200, 0, 0);
  Check(BdHit(15, 2, 3, 1, 60, 150, WP_TORSO, T) = WK_HEAVY, 'the mate''s heavy wound');
  Low[16] := True;
  Run(60);
  Check(WorkOf(16) = BW_NONE, 'without AutoBandage the medic waits');
  Check(BdWant(16, BW_BANDAGE) = 1, 'the medic asks to bandage: a mate near him');
  i := 0;
  while (i < 500) and not Has(BDE_TREATED, 16, 15) do
  begin
    Run(1);
    Inc(i);
  end;
  Check(Wounds(15) = 0, 'the medic bandaged the mate on his request');
  Run(30);
  Check(BdWant(16, BW_BANDAGE) = 0, 'nobody left: the request ends');
  BdSet(BDC_BAND_AUTO, 1);
  BdMedic(16, 0);
  Low[16] := False;
  BdPlayer(15, 1, 0);
  BdPlayer(16, 1, 0);

  { 19. round 26: a death by low blood after the wounds closed is the last shooter's }
  Spawn(17, 1, 19000);
  Check(BdHit(17, 5, 3, 1, 60, 150, WP_LEGS, T) > 0, 'a wound by player 5');
  Low[17] := True;
  Run(400);
  Check(Wounds(17) = 0, 'bandaged');
  Check(BdCulprit(17, W) = 5, 'no wound open: the culprit is still player 5');
  Low[17] := False;
  BdPlayer(17, 1, 0);

  WriteLn(BdInfo);
  WriteLn(Passed, ' passed, ', Failed, ' failed');
  if Failed > 0 then
    Halt(1);
end.
