program test_engine;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils, be_font, be_world, be_texts, be_radar, be_move, be_ballistic, be_gun, be_traj, be_fx, be_sup, be_map, be_ac;

var
  Failed: LongInt = 0;
  Passed: LongInt = 0;

procedure Check(Ok: Boolean; const What: AnsiString);
begin
  if Ok then
    Inc(Passed)
  else
  begin
    WriteLn('FAIL ', What);
    Inc(Failed);
  end;
end;

function Near(A, B, Tol: Single): Boolean;
begin
  Result := Abs(A - B) <= Tol;
end;

var
  WI: array[0..4095] of LongInt;
  WF: array[0..4095] of Single;
  WN: LongInt;

procedure WClear;
begin
  WN := 0;
end;

procedure WAdd(ID, Flags, Team, Pct, Tag, Ping, AimX, AimY: LongInt; X, Y, VX, VY: Single);
begin
  WI[WN * WI_STRIDE] := ID;
  WI[WN * WI_STRIDE + 1] := Flags;
  WI[WN * WI_STRIDE + 2] := Team;
  WI[WN * WI_STRIDE + 3] := Pct;
  WI[WN * WI_STRIDE + 4] := Tag;
  WI[WN * WI_STRIDE + 5] := Ping;
  WI[WN * WI_STRIDE + 6] := AimX;
  WI[WN * WI_STRIDE + 7] := AimY;
  WF[WN * WF_STRIDE] := X;
  WF[WN * WF_STRIDE + 1] := Y;
  WF[WN * WF_STRIDE + 2] := VX;
  WF[WN * WF_STRIDE + 3] := VY;
  Inc(WN);
end;

procedure WLoad(Tick: LongInt);
begin
  WorldLoad(Tick, WN, @WI, @WF);
end;

function FindOp(Kind, Layer: LongInt): LongInt;
var
  i: LongInt;
begin
  Result := -1;
  for i := 0 to OpCount - 1 do
    if (Ops[i].Kind = Kind) and (Ops[i].Layer = Layer) then
    begin
      Result := i;
      Exit;
    end;
end;

procedure TestFont;
var
  CX, CY: Single;
begin
  Check(Near(TextAdvance('Admiral'), 5.241, 0.01), 'Admiral advance');
  InkCenter('.', CX, CY);
  Check(Near(CX, 0.192, 0.001) and Near(CY, 0.883, 0.001), 'period ink centre');
  InkCenter('+', CX, CY);
  Check(Near(CX, 0.375, 0.001) and Near(CY, 0.622, 0.001), 'plus ink centre');
  Check(Near(TextAdvance(''), 0, 0.0001), 'empty text');
end;

procedure TestRadarList;
var
  n, k: LongInt;
  T: AnsiString;
begin
  RadarReset(1);
  WClear;
  WAdd(1, WF_ALIVE or WF_HUMAN, 1, 100, 0, 50, 0, 0, 100, 100, 0, 0);
  WAdd(2, WF_ALIVE, 2, 80, TAG_FLAG, 0, 0, 0, 240, 100, 0, 0);
  WAdd(3, WF_ALIVE, 2, 55, 0, 0, 0, 0, 100, 900, 0, 0);
  WAdd(4, 0, 2, 0, 0, 0, 0, 0, 120, 100, 0, 0);
  WLoad(1000);
  WorldName(1, 'Me');
  WorldName(2, 'Kruger');
  WorldName(3, 'Far Guy');
  RadarText(RT_LIST_LINE, '{dir} {tag}{name} {pct}% {m} {dist}');
  RadarInt(RI_METER_DECIMALS, 2);
  RadarInt(RI_LIST_COLOR_BY, LC_NONE);
  RadarUser(1, 1, OVL_LIST, SHOW_ALL, 10, 150, 1, 1, 1, 0);
  n := RadarPass(1, 1000, 8);
  Check(n = 1, 'list: one text');
  k := FindOp(KIND_BIG, 198);
  Check(k >= 0, 'list layer');
  if k >= 0 then
  begin
    T := Ops[k].Text;
    Check(Pos('> F Kruger 80% 10.00m 140', T) > 0, 'list line with meters: ' + T);
    Check(Pos('Far Guy', T) = 0, 'out of range left out');
    Check(Near(Ops[k].X, 10, 0.01) and Near(Ops[k].Y, 150, 0.01), 'list position');
  end;
  n := RadarPass(1, 1001, 8);
  Check(n = 0, 'unchanged list is not sent again');
  n := RadarPass(1, 1000 + 300, 8);
  Check(n = 1, 'list refreshed after RefreshTicks');
  RadarUser(1, 0, OVL_LIST, SHOW_ALL, 10, 150, 1, 1, 1, 0);
  n := RadarPass(1, 1302, 8);
  Check((n = 1) and (Ops[0].Text = ' '), 'list hidden when off');
  RadarReset(1);
  RadarInt(RI_LIST_COLOR_BY, LC_TEAM);
  RadarInt(RI_TEAMGAME, 1);
  WClear;
  WAdd(1, WF_ALIVE or WF_HUMAN, 1, 100, 0, 50, 0, 0, 100, 100, 0, 0);
  WAdd(2, WF_ALIVE, 2, 80, TAG_FLAG, 0, 0, 0, 240, 100, 0, 0);
  WAdd(5, WF_ALIVE, 1, 70, 0, 0, 0, 0, 300, 100, 0, 0);
  WLoad(1400);
  WorldName(5, 'Mate');
  WorldFlag(0, 1, 2, 400, 100);
  WorldFlag(1, 2, 1, 50, 50);
  RadarOpt(1, RO_FRIENDS, 1);
  RadarUser(1, 1, OVL_LIST, SHOW_ALL, 10, 150, 1, 1, 1, 0);
  n := RadarPass(1, 1400, 20);
  Check(n = 4, 'coloured list: title, two players, the dropped flag: ' + IntToStr(n));
  k := FindOp(KIND_BIG, 180);
  Check((k >= 0) and (Ops[k].Color = $FF4040) and (Pos('Kruger', Ops[k].Text) > 0), 'enemy line red');
  k := FindOp(KIND_BIG, 181);
  Check((k >= 0) and (Ops[k].Color = $40FF40) and (Pos('Mate', Ops[k].Text) > 0), 'team mate line green');
  Check((k >= 0) and (Ops[k].Y > Ops[FindOp(KIND_BIG, 180)].Y), 'second line lower');
  k := FindOp(KIND_BIG, 182);
  Check((k >= 0) and (Pos('Red flag', Ops[k].Text) > 0), 'dropped flag listed, the one in base not');
  WorldFlag(0, 1, 0, 0, 0);
  WorldFlag(1, 2, 0, 0, 0);
  RadarInt(RI_TEAMGAME, 0);
  RadarInt(RI_LIST_COLOR_BY, LC_NONE);
  RadarReset(1);
end;

function OpCenterX(k: LongInt): Single;
var
  CX, CY: Single;
begin
  InkCenter(Ops[k].Text, CX, CY);
  Result := Ops[k].X + CX * Ops[k].Scale * WORLD_EM;
end;

function OpCenterY(k: LongInt): Single;
var
  CX, CY: Single;
begin
  InkCenter(Ops[k].Text, CX, CY);
  Result := Ops[k].Y + CY * Ops[k].Scale * WORLD_EM;
end;

procedure TestPathClip;
var
  n, m: LongInt;
begin
  n := BuildPath(8, 0, 0, 0, 0, 1000, 0, 400, 16, 3000);
  Check(n > 100, 'long barrett path: ' + IntToStr(n));
  m := PathClip(0, 0, 440, 260);
  Check((m > 20) and (m < 40), 'path cut at the edge of the view: ' + IntToStr(m));
  Check(PathX[m - 1] > 440, 'the last point is just past the edge');
  Check(PathX[m - 2] <= 440, 'the one before is inside');
  n := BuildPath(8, 0, 0, 0, 0, 1000, 0, 400, 16, 3000);
  m := PathClip(5000, 5000, 440, 260);
  Check(m = 1, 'a path never in view keeps only its start');
end;

procedure TestSuppression;
var
  M: LongInt;
begin
  SupConfig(50, 130, 4, True, False, True);
  TeamSet(1, 1);
  TeamSet(2, 2);
  TeamSet(3, 1);
  WI[0] := 2;
  WI[1] := 2;
  WF[0] := 100;
  WF[1] := 100;
  WI[2] := 3;
  WI[3] := 1;
  WF[2] := 500;
  WF[3] := 100;
  SupPlayers(2, @WI, @WF);
  M := SupBullet(1, 1, 20, 90, 10, 0);
  Check(M = 2, 'a bullet passing an enemy suppresses him: ' + IntToStr(M));
  M := SupBullet(1, 1, 20, 300, 10, 0);
  Check(M = 0, 'a far bullet suppresses nobody');
  M := SupBullet(1, 1, 480, 100, 10, 0);
  Check(M = 0, 'no suppression by a team mate without friendly fire');
  SupConfig(50, 130, 4, True, True, True);
  M := SupBullet(1, 1, 480, 100, 10, 0);
  Check(M = 4, 'team bullets count with friendly fire: ' + IntToStr(M));
  M := SupBullet(2, 4, 20, 190, 10, 0);
  Check(M = 0, 'the owner is never suppressed by his own bullet');
  M := SupBullet(1, 4, 20, 190, 10, 0);
  Check(M = 2, 'explosives reach further: ' + IntToStr(M));
end;

procedure TestRadarRing;
var
  n, i, k, k2, k3: LongInt;
begin
  RadarReset(1);
  RadarInt(RI_TEAMGAME, 1);
  RadarInt(RI_ARROWS_MAX, 6);
  RadarInt(RI_ARROW_STEPS, 4);
  RadarInt(RI_RING_COLOR_BY, RC_TEAM);
  RadarFloat(RF_ARROW_OUTER, 30);
  RadarFloat(RF_ARROW_LEAD, 1);
  RadarFloat(RF_RING_NEAR_SCALE, 0.16);
  RadarFloat(RF_RING_FAR_SCALE, 0.07);
  WClear;
  WAdd(1, WF_ALIVE or WF_HUMAN, 1, 100, 0, 0, 0, 0, 500, 500, 0, 0);
  WAdd(2, WF_ALIVE, 2, 80, 0, 0, 0, 0, 600, 500, 0, 0);
  WAdd(3, WF_ALIVE, 2, 80, TAG_FLAG, 0, 0, 0, 500, 0, 0, 0);
  WAdd(4, WF_ALIVE, 1, 80, 0, 0, 0, 0, 400, 500, 0, 0);
  WLoad(2000);
  RadarUser(1, 1, OVL_RING, SHOW_ALL, 0, 0, 1, 1, 1, 0);
  n := RadarPass(1, 2000, 100);
  Check(n = 3, 'ring: one dot per player (two enemies, one team mate): ' + IntToStr(n));
  k2 := FindOp(KIND_WORLD, 210 + 1);
  k3 := FindOp(KIND_WORLD, 210 + 2);
  Check((k2 >= 0) and (k3 >= 0) and (FindOp(KIND_WORLD, 210 + 3) >= 0), 'ring layers by player slot');
  if (k2 >= 0) and (k3 >= 0) then
  begin
    Check(Ops[k2].Text = '.', 'enemy dot is a period');
    Check(Near(OpCenterX(k2), 530, 0.6) and Near(OpCenterY(k2), 500 - LOS_HEIGHT, 0.6),
      'dot on the ring towards the enemy: ' + FloatToStr(OpCenterX(k2)) + ' ' + FloatToStr(OpCenterY(k2)));
    Check(Ops[k2].Color = $FF4040, 'enemy colour');
    Check(Ops[k3].Text = 'F', 'flag carrier letter');
    Check(Near(OpCenterX(k3), 500, 0.6) and Near(OpCenterY(k3), 500 - LOS_HEIGHT - 30, 0.6), 'letter on the ring');
    Check(Ops[k2].Scale > 0.07, 'near enemy: bigger dot');
  end;
  k := FindOp(KIND_WORLD, 210 + 3);
  if k >= 0 then
    Check(Ops[k].Color = $40FF40, 'team mate colour');
  n := RadarPass(1, 2001, 100);
  Check(n = 0, 'still ring is not resent');
  RadarOpt(1, RO_FRIENDS, 0);
  n := RadarPass(1, 2002, 100);
  Check((n = 1) and (Ops[0].Layer = 210 + 3) and (Ops[0].Text = ' '), 'team mates hidden when friends are off');
  RadarOpt(1, RO_FRIENDS, 1);
  WClear;
  WAdd(1, WF_ALIVE or WF_HUMAN, 1, 100, 0, 0, 0, 0, 500, 500, 0, 0);
  WAdd(2, WF_ALIVE, 2, 80, 0, 0, 0, 0, 1150, 500, 0, 0);
  WAdd(3, WF_ALIVE, 2, 80, TAG_FLAG, 0, 0, 0, 500, 0, 0, 0);
  WAdd(4, WF_ALIVE, 1, 80, 0, 0, 0, 0, 400, 500, 0, 0);
  WLoad(2003);
  n := RadarPass(1, 2003, 100);
  k := FindOp(KIND_WORLD, 210 + 1);
  Check(k >= 0, 'far enemy redrawn');
  if k >= 0 then
    Check(Near(Ops[k].Scale, 0.07, 0.0011), 'far enemy: smallest dot ' + FloatToStr(Ops[k].Scale));
  WClear;
  WAdd(1, WF_ALIVE or WF_HUMAN, 1, 100, 0, 100, 0, 0, 510, 500, 5, 0);
  WAdd(2, WF_ALIVE, 2, 80, 0, 0, 0, 0, 1150, 500, 0, 0);
  WLoad(2010);
  n := RadarPass(1, 2010, 100);
  k := FindOp(KIND_WORLD, 210 + 1);
  Check(k >= 0, 'moving user: dot moves');
  if k >= 0 then
    Check(Near(OpCenterX(k), 510 + 5 * 6 + 30, 0.6), 'ring centre predicted with ping and speed: ' +
      FloatToStr(OpCenterX(k)));
  k := 0;
  for i := 0 to n - 1 do
    if Ops[i].Text = ' ' then
      Inc(k);
  Check(k = 2, 'dots of players who left are hidden: ' + IntToStr(k));
  RadarUser(1, 1, OVL_LIST, SHOW_ALL, 10, 150, 1, 1, 1, 0);
  n := RadarPass(1, 2011, 100);
  k := 0;
  for i := 0 to n - 1 do
    if Ops[i].Text = ' ' then
      Inc(k);
  Check(k = 1, 'mode change hides the ring: ' + IntToStr(k));
  RadarInt(RI_TEAMGAME, 0);
end;

procedure TestRadarCircle;
var
  n, k: LongInt;
  CX, CY, Em: Single;
begin
  RadarReset(1);
  RadarInt(RI_CIRCLE_DOTS, 16);
  WClear;
  WAdd(1, WF_ALIVE or WF_HUMAN, 1, 100, 0, 0, 0, 0, 500, 500, 0, 0);
  WAdd(2, WF_ALIVE, 2, 80, 0, 0, 0, 0, 850, 500, 0, 0);
  WLoad(3000);
  RadarUser(1, 1, OVL_CIRCLE, SHOW_ALL, 10, 110, 1, 1, 1, 0);
  n := RadarPass(1, 3000, 100);
  Check(n = 16 + 1 + 1, 'circle: ring, self and one mark: ' + IntToStr(n));
  k := FindOp(KIND_BIG, 110 + RING_MAX);
  Check(k >= 0, 'self mark');
  if k >= 0 then
  begin
    InkCenter('+', CX, CY);
    Em := Ops[k].Scale * BIG_EM;
    Check(Near(Ops[k].X + CX * Em, 60, 0.6) and Near(Ops[k].Y + CY * Em, 160, 0.6), 'self mark centred');
  end;
  k := FindOp(KIND_BIG, 110 + RING_MAX + 2);
  Check(k >= 0, 'player mark');
  if k >= 0 then
  begin
    InkCenter('o', CX, CY);
    Em := Ops[k].Scale * BIG_EM;
    Check(Near(Ops[k].X + CX * Em, 60 + 25, 0.6) and Near(Ops[k].Y + CY * Em, 160, 0.6), 'mark at half the radius');
  end;
  RadarUser(1, 1, OVL_CIRCLE, SHOW_ALL, 12, 110, 1.2, 1, 1, 1);
  n := RadarPass(1, 3001, 100);
  k := FindOp(KIND_BIG, 110 + RING_MAX + 2);
  Check(k >= 0, 'editing hides the player marks');
  if k >= 0 then
    Check(Ops[k].Text = ' ', 'player mark hidden while editing');
  k := FindOp(KIND_BIG, 110);
  Check((k >= 0) and Near(Ops[k].Scale, QScale(0.03), 0.00001), 'marks keep their size while editing');
end;

procedure TestLabels;
var
  n, k: LongInt;
  W: Single;
begin
  RadarReset(1);
  WClear;
  WAdd(1, WF_ALIVE or WF_HUMAN, 1, 100, 0, 0, 0, 0, 500, 500, 0, 0);
  WAdd(2, WF_ALIVE, 2, 80, 0, 0, 0, 0, 600, 480, 0, 0);
  WLoad(4000);
  WorldName(2, 'Admiral');
  RadarUser(1, 1, OVL_LABELS, SHOW_ALL, 0, 0, 1, 1, 1, 0);
  n := RadarPass(1, 4000, 100);
  Check(n = 1, 'one label');
  k := FindOp(KIND_WORLD, 150 + 1);
  Check(k >= 0, 'label layer');
  if k >= 0 then
  begin
    W := TextAdvance('Admiral 80%') * 0.02 * WORLD_EM;
    Check(Near(Ops[k].X, 600 - W / 2, 0.01), 'label centred');
    Check(Near(Ops[k].Y, 480 - 25, 0.01), 'label 25 above the feet');
    Check(Ops[k].Color = HealthColor(80), 'label colour');
  end;
end;

procedure TestVision;
var
  S, B, Cnt: LongInt;
  X1, Y1, X2, Y2: Single;
begin
  RadarReset(1);
  RadarReset(2);
  RadarInt(RI_TEAMGAME, 1);
  WClear;
  WAdd(1, WF_ALIVE or WF_HUMAN, 1, 100, 0, 0, 900, 500, 500, 500, 0, 0);
  WAdd(2, WF_ALIVE, 2, 80, 0, 0, 0, 0, 700, 500, 0, 0);
  WAdd(3, WF_ALIVE, 2, 80, 0, 0, 0, 0, 300, 500, 0, 0);
  WAdd(4, WF_ALIVE, 1, 80, 0, 0, 0, 0, 350, 500, 0, 0);
  WLoad(5000);
  RadarUser(1, 1, OVL_LIST, SHOW_SEEN, 0, 0, 1, 1, 1, 0);
  Check(VisNeeded, 'vision needed');
  Cnt := 0;
  while VisNext(5000, S, B, X1, Y1, X2, Y2) do
  begin
    Inc(Cnt);
    VisSet(S, B, True);
  end;
  Check(Cnt >= 1, 'rays cast');
  Check(Shows(1, 2, SHOW_SEEN), 'enemy in front of the aim seen');
  Check(not Shows(1, 3, SHOW_SEEN) or VisMine[4, 3], 'enemy behind only through a team mate');
  Check(Shows(1, 4, SHOW_SEEN), 'team mate always shown');
  RadarInt(RI_TEAMGAME, 0);
end;

procedure TestMove;
var
  A, T, n: LongInt;
  OX, OY, OVX, OVY, Sp, LastSp, MaxSp, FlyX, PX, Art, HopD: Single;
  Back, Forward: Boolean;
begin
  MoveReset(5);
  A := MoveStep(5, 100, TP_MOMENTUM, VAR_INHERIT, 0, 1, 0, 1, 0, 100, 100, 0, 0, 300, 100, OX, OY, OVX, OVY);
  Check(A = 0, 'no action without a press');
  A := MoveStep(5, 101, TP_MOMENTUM, VAR_INHERIT, 1, 1, 0, 1, 0, 100, 100, 0, 0, 300, 100, OX, OY, OVX, OVY);
  Check((A and MA_MOVE) <> 0, 'tap moves');
  Check(Near(OX, 300, 0.01) and Near(OY, 100, 0.01), 'tap target is the cursor');
  Check(Near(OVX, 2 + 200 * 0.008, 0.01) and Near(OVY, 0, 0.01), 'tap speed');
  LastSp := 0;
  for T := 102 to 160 do
  begin
    A := MoveStep(5, T, TP_MOMENTUM, VAR_INHERIT, 1, 1, 0, 1, 0, 300, 100, 3.6, 0, 300 + (T - 100) div 5, 100, OX, OY,
      OVX, OVY);
    if (A and MA_VELOCITY) <> 0 then
      LastSp := Sqrt(OVX * OVX + OVY * OVY);
  end;
  Check(LastSp > 3.6, 'inherit variant accelerates: ' + FloatToStr(LastSp));
  MaxSp := 0;
  for T := 161 to 900 do
  begin
    A := MoveStep(5, T, TP_MOMENTUM, VAR_INHERIT, 1, 1, 0, 1, 0, 300, 100, 3.6, 0, 400 + T, 100, OX, OY, OVX, OVY);
    if (A and MA_VELOCITY) <> 0 then
    begin
      Sp := Sqrt(OVX * OVX + OVY * OVY);
      if Sp > MaxSp then
        MaxSp := Sp;
    end;
  end;
  Check((MaxSp > 8) and (MaxSp <= 9.2), 'vmax reached and respected: ' + FloatToStr(MaxSp));
  Back := False;
  for T := 901 to 960 do
  begin
    A := MoveStep(5, T, TP_MOMENTUM, VAR_INHERIT, 1, 1, 0, 1, 0, 300, 100, 9, 0, 300 - 250, 100, OX, OY, OVX, OVY);
    if (A and MA_VELOCITY) <> 0 then
      if OVX < 0 then
        Back := True;
  end;
  Check(Back, 'held: turns round when the cursor goes behind');
  MoveReset(8);
  MoveStep(8, 1000, TP_MOMENTUM, VAR_INHERIT, 0, 1, 100, 1, 0, 0, 0, 0, 0, 200, 0, OX, OY, OVX, OVY);
  MoveStep(8, 1001, TP_MOMENTUM, VAR_INHERIT, 1, 1, 100, 1, 0, 0, 0, 0, 0, 200, 0, OX, OY, OVX, OVY);
  PX := 200;
  HopD := 0;
  Forward := True;
  n := 0;
  for T := 1002 to 1100 do
  begin
    Art := 0;
    if (HopD > 0) and (n >= 0) then
      Art := HopD * Exp(n * Ln(0.86));
    A := MoveStep(8, T, TP_MOMENTUM, VAR_INHERIT, 1, 1, 100, 1, 0, PX, 0, 6, 0, Round(PX + 150 - Art), 0, OX, OY, OVX,
      OVY);
    Inc(n);
    if (A and MA_MOVE) <> 0 then
    begin
      HopD := OX - PX;
      PX := OX;
      n := -6;
    end;
    if (A and MA_VELOCITY) <> 0 then
      if OVX < 0 then
        Forward := False;
    PX := PX + 6;
  end;
  Check(Forward, 'held: the camera lag after a jump does not turn it round');
  Check(PX > 900, 'held: jumps keep going: ' + FloatToStr(PX));
  MoveReset(9);
  A := MoveStep(9, 50, TP_JUMP, VAR_FIXED, 0, 1, 0, 1, MO_NO_WALLS, 0, 0, 0, 0, 10, 10, OX, OY, OVX, OVY);
  A := MoveStep(9, 51, TP_JUMP, VAR_FIXED, 1, 1, 0, 1, MO_NO_WALLS, 0, 0, 0, 0, 10, 10, OX, OY, OVX, OVY);
  Check((A and MA_MOVE) <> 0, 'jump without a map');
  MoveReset(6);
  MoveStep(6, 200, TP_FLY, VAR_FIXED, 0, 1, 0, 1, 0, 100, 100, 0, 0, 105, 102, OX, OY, OVX, OVY);
  A := MoveStep(6, 201, TP_FLY, VAR_FIXED, 1, 1, 0, 1, 0, 100, 100, 0, 0, 105, 102, OX, OY, OVX, OVY);
  Check((A and MA_VELOCITY) <> 0, 'fly pushes');
  Check(Near(OVX, 0, 0.01) and (OVY < 0) and (OVY > -0.2), 'inside the dead zone it only hovers');
  MoveReset(7);
  MoveStep(7, 300, TP_FLY, VAR_FIXED, 0, 1, 0, 1, 0, 100, 100, 0, 0, 250, 100, OX, OY, OVX, OVY);
  FlyX := 0;
  for T := 301 to 340 do
  begin
    A := MoveStep(7, T, TP_FLY, VAR_FIXED, 1, 1, 0, 1, 0, 100, 100, 0, 0, 250, 100, OX, OY, OVX, OVY);
    if (A and MA_VELOCITY) <> 0 then
      FlyX := OVX;
  end;
  Check(Near(FlyX, 1.5 + (150 - 8) * 0.04, 0.3), 'fly speed grows with the distance: ' + FloatToStr(FlyX));
  for T := 341 to 380 do
  begin
    A := MoveStep(7, T, TP_FLY, VAR_FIXED, 1, 1, 0, 1, 0, 100, 100, 0, 0, 900, 900, OX, OY, OVX, OVY);
    if (A and MA_VELOCITY) <> 0 then
      FlyX := OVX;
  end;
  Check((FlyX > 7.5) and (FlyX <= 11), 'fly reaches FlyMax, each axis at most 11: ' + FloatToStr(FlyX));
  MoveSet(MF_FLY_MAX, 30);
  MoveReset(10);
  MoveStep(10, 500, TP_FLY, VAR_FIXED, 0, 1, 0, 1, 0, 0, 0, 0, 0, 2000, 0, OX, OY, OVX, OVY);
  n := 0;
  PX := 0;
  for T := 501 to 560 do
  begin
    A := MoveStep(10, T, TP_FLY, VAR_FIXED, 1, 1, 0, 1, 0, PX, 0, 11, 0, Round(PX) + 2000, 0, OX, OY, OVX, OVY);
    if (A and MA_MOVE) <> 0 then
    begin
      Inc(n);
      PX := OX;
    end;
    PX := PX + 11;
  end;
  Check((n >= 8) and (PX > 60 * 11 + 500), 'fly above 11 a tick with jumps: ' + IntToStr(n) + ' ' + FloatToStr(PX));
  MoveSet(MF_FLY_MAX, 11);
end;

procedure TestBallistics;
var
  n, W, T, k: LongInt;
  DX, DY, BX, BY, BVX, BVY, Best, PX, PY, D2, R0X, R0Y: Single;
  Ok: Boolean;
begin
  WeaponsDefault(False);
  n := BuildPath(8, 0, 0, 0, 0, 1000, 0, 120, 20, 900);
  Check(n > 10, 'barrett path points');
  Check(PathY[n - 1] > 0, 'gravity bends the path down');
  Check(Near(PathX[1], 20, 0.5), 'points 20 px apart');
  for W := 0 to 16 do
  begin
    if (W = 11) or (W = 12) or (W = 14) then
      Continue;
    Ok := Solve(W, 0, 0, 0, 0, 400, -50, -2, 0, 0, DX, DY, T);
    Check(Ok, 'solve weapon ' + IntToStr(W));
    if Ok then
    begin
      BX := 0;
      BY := 0;
      BVX := DX * ShotSpeed(W);
      BVY := DY * ShotSpeed(W);
      Best := 1E9;
      PX := 400;
      PY := -50;
      for n := 1 to 400 do
      begin
        R0X := PX - BX;
        R0Y := PY - BY;
        BVY := BVY + BulletGravity;
        BX := BX + BVX;
        BY := BY + BVY;
        BVX := BVX * 0.99;
        BVY := BVY * 0.99;
        PX := PX - 2;
        for k := 0 to 20 do
        begin
          D2 := Sqr(R0X + (PX - BX - R0X) * k / 20) + Sqr(R0Y + (PY - BY - R0Y) * k / 20);
          if D2 < Best then
            Best := D2;
        end;
      end;
      Check(Best < 16, 'solution hits the moving target, weapon ' + IntToStr(W) + ' miss ' + FloatToStr(Sqrt(Best)));
    end;
  end;
  n := BuildShot(5, 0, 0, 0, 0, 1, 0, 1, 7, 0);
  Check(n = 6, 'shotgun six pellets');
  n := BuildShot(1, 0, 0, 0, 0, 1, 0, 1, 7, 0);
  Check(n = 2, 'deagles two bullets');
  n := BuildShot(3, 0, 0, 2, 0, 1, 0, 1, 7, 0);
  Check((n = 1) and Near(ShotVX[0], 24 + 1, 0.01), 'inherited velocity');
end;

procedure TestWeaponsIni(const Dir: AnsiString);
var
  L: TStringList;
  n: LongInt;
begin
  L := TStringList.Create;
  L.Add('[Info]');
  L.Add('Version=1.6.9');
  L.Add('[Desert Eagles]');
  L.Add('Damage=181');
  L.Add('FireInterval=24');
  L.Add('Speed=190');
  L.Add('BulletStyle=1');
  L.SaveToFile(Dir + 'old_weapons.ini');
  L.Clear;
  L.Add('[Info]');
  L.Add('Version=1.7.1');
  L.Add('[Barret M82A1]');
  L.Add('Damage=4.95');
  L.Add('Speed=55.5');
  L.Add('FireInterval=200');
  L.SaveToFile(Dir + 'new_weapons.ini');
  L.Free;
  n := WeaponsLoad(Dir + 'old_weapons.ini', False);
  Check(n = 1, 'old format read');
  Check(Near(Weapon[1].Speed, 19, 0.001) and Near(Weapon[1].Damage, 1.81, 0.001), 'old format scaled');
  n := WeaponsLoad(Dir + 'new_weapons.ini', True);
  Check(Near(Weapon[8].Speed, 55.5, 0.001) and (Weapon[8].Interval = 200), 'new format read');
  Check(Near(Weapon[0].Damage, 1.3, 0.001), 'realistic defaults for the rest');
  n := WeaponsLoad(Dir + 'missing.ini', False);
  Check((n = 0) and Near(Weapon[8].Speed, 55, 0.001), 'missing file: defaults');
end;

procedure TestGun;
var
  T, Shots, R: LongInt;
begin
  WeaponsDefault(False);
  GunReset(3);
  Shots := 0;
  for T := 0 to 59 do
  begin
    R := GunTick(3, T, 2, 1, 0);
    if R = 1 then
    begin
      GunFired(3, T);
      Inc(Shots);
    end;
  end;
  Check(Shots = 10, 'mp5 fires every 6 ticks: ' + IntToStr(Shots));
  GunReset(3);
  Shots := 0;
  for T := 0 to 400 do
  begin
    R := GunTick(3, T, 8, 1, 0);
    if R = 1 then
    begin
      GunFired(3, T);
      Inc(Shots);
    end;
  end;
  Check(Shots = 2, 'barrett start up and interval: ' + IntToStr(Shots));
  GunReset(3);
  Shots := 0;
  for T := 0 to 260 do
  begin
    R := GunTick(3, T, 6, 1, 0);
    if R = 1 then
    begin
      GunFired(3, T);
      Inc(Shots);
    end;
  end;
  Check(Shots = 6, 'ruger magazine and reload: ' + IntToStr(Shots));
end;

procedure TestTargets;
var
  n: LongInt;
begin
  RadarInt(RI_TEAMGAME, 1);
  WClear;
  WAdd(1, WF_ALIVE or WF_HUMAN, 1, 100, 0, 0, 900, 500, 500, 500, 0, 0);
  WAdd(2, WF_ALIVE, 2, 80, 0, 0, 0, 0, 700, 520, 0, 0);
  WAdd(3, WF_ALIVE, 2, 80, 0, 0, 0, 0, 300, 500, 0, 0);
  WAdd(4, WF_ALIVE, 1, 80, 0, 0, 0, 0, 650, 500, 0, 0);
  WAdd(5, WF_ALIVE, 2, 80, 0, 0, 0, 0, 560, 500, 0, 0);
  WLoad(6000);
  n := GunTargets(1, TM_CURSOR, 800, 45);
  Check(n = 2, 'enemies in front only: ' + IntToStr(n));
  Check(GunTarget(0) = 5, 'closest to the cursor line first');
  n := GunTargets(1, TM_NEAREST, 800, 180);
  Check((n = 3) and (GunTarget(0) = 5), 'nearest first');
  n := GunTargets(1, TM_RADIUS, 800, 250);
  Check((n = 1) and (GunTarget(0) = 2), 'only the enemy near the cursor: ' + IntToStr(n));
  n := GunTargets(1, TM_RADIUS, 800, 150);
  Check(n = 0, 'nobody within a small circle: ' + IntToStr(n));
  n := GunTargets(1, TM_RADIUS, 800, 700);
  Check((n = 3) and (GunTarget(0) = 2) and (GunTarget(1) = 5) and (GunTarget(2) = 3), 'nearest to the cursor first');
  RadarInt(RI_TEAMGAME, 0);
end;

procedure TestCircle;
var
  n: LongInt;
begin
  TrajReset(3);
  n := AimCircle(3, 100, 64, 12, 120, $FF8000, 500, 400, 150, 0.08);
  Check(n = 12, 'circle drawn: ' + IntToStr(n));
  Check((Ops[0].Kind = KIND_WORLD) and (Ops[0].Layer = 120), 'circle on its layers');
  n := AimCircle(3, 103, 64, 12, 120, $FF8000, 500, 400, 150, 0.08);
  Check(n = 0, 'still circle sends nothing: ' + IntToStr(n));
  n := AimCircle(3, 106, 64, 12, 120, $FF8000, 540, 400, 150, 0.08);
  Check(n = 12, 'moved circle sent again: ' + IntToStr(n));
  n := AimCircleHide(3, 64);
  Check(n = 12, 'circle hidden: ' + IntToStr(n));
  n := AimCircleHide(3, 64);
  Check(n = 0, 'hidden once: ' + IntToStr(n));
end;

procedure TestTraj;
var
  n, i, Dots: LongInt;
begin
  TrajReset(2);
  TrajInt(TJ_DOTS, 10);
  BuildPath(3, 0, 0, 0, 0, 500, 0, 100, 10, 600);
  n := TrajPass(2, 100, 100, PathCount, -1, 500, 0, 1);
  Dots := 0;
  for i := 0 to OpCount - 1 do
    if Ops[i].Text = '.' then
      Inc(Dots);
  Check((Dots <= 10) and (Dots >= 8), 'trajectory limited to TrajDots: ' + IntToStr(Dots));
  Check(n = Dots + 1, 'dots and the cursor');
  n := TrajPass(2, 101, 100, PathCount, -1, 500, 0, 1);
  Check(n = 0, 'unchanged path not resent');
  n := TrajPass(2, 102, 100, 5, 4, 500, 0, 1);
  Check(n > 0, 'cut path resent');
  Check((FindOp(KIND_WORLD, 100 + 6) >= 0) and (Ops[FindOp(KIND_WORLD, 100 + 6)].Text = ' '), 'extra dots hidden');
end;

procedure PutInt(S: TStream; V: LongInt);
begin
  S.WriteBuffer(V, 4);
end;

procedure PutWord(S: TStream; V: Word);
begin
  S.WriteBuffer(V, 2);
end;

procedure PutByte(S: TStream; V: Byte);
begin
  S.WriteBuffer(V, 1);
end;

procedure PutSingle(S: TStream; V: Single);
begin
  S.WriteBuffer(V, 4);
end;

procedure PutZero(S: TStream; N: LongInt);
var
  i: LongInt;
begin
  for i := 1 to N do
    PutByte(S, 0);
end;

type
  TTestPoly = record
    X, Y: array[1..3] of Single;
    T: Byte;
  end;

procedure WriteMap(const Path: AnsiString; const P: array of TTestPoly; SecDiv, SecNum: LongInt; Cut: Boolean);
var
  F: TFileStream;
  i, j, k, v, n: LongInt;
  L: array[0..63] of Word;
  X0, X1, Y0, Y1, MinX, MaxX, MinY, MaxY: Single;
begin
  F := TFileStream.Create(Path, fmCreate);
  try
    PutInt(F, 11);
    PutZero(F, 1 + 38 + 1 + 24 + 20);
    PutInt(F, Length(P));
    for i := 0 to High(P) do
    begin
      for v := 1 to 3 do
      begin
        PutSingle(F, P[i].X[v]);
        PutSingle(F, P[i].Y[v]);
        PutZero(F, 20);
      end;
      PutZero(F, 36);
      PutByte(F, P[i].T);
    end;
    if Cut then
      Exit;
    PutInt(F, SecDiv);
    PutInt(F, SecNum);
    for i := -SecNum to SecNum do
      for j := -SecNum to SecNum do
      begin
        X0 := (i - 0.5) * SecDiv;
        X1 := (i + 0.5) * SecDiv;
        Y0 := (j - 0.5) * SecDiv;
        Y1 := (j + 0.5) * SecDiv;
        n := 0;
        for k := 0 to High(P) do
        begin
          MinX := P[k].X[1];
          MaxX := P[k].X[1];
          MinY := P[k].Y[1];
          MaxY := P[k].Y[1];
          for v := 2 to 3 do
          begin
            if P[k].X[v] < MinX then MinX := P[k].X[v];
            if P[k].X[v] > MaxX then MaxX := P[k].X[v];
            if P[k].Y[v] < MinY then MinY := P[k].Y[v];
            if P[k].Y[v] > MaxY then MaxY := P[k].Y[v];
          end;
          if (MaxX >= X0) and (MinX <= X1) and (MaxY >= Y0) and (MinY <= Y1) then
          begin
            L[n] := k + 1;
            Inc(n);
          end;
        end;
        PutWord(F, n);
        for k := 0 to n - 1 do
          PutWord(F, L[k]);
      end;
    PutInt(F, 0);
    PutInt(F, 0);
    PutInt(F, 1);
    PutByte(F, 1);
    PutZero(F, 3);
    PutSingle(F, 1000);
    PutSingle(F, 150);
    PutSingle(F, 17);
  finally
    F.Free;
  end;
end;

function Tri(X1, Y1, X2, Y2, X3, Y3: Single; T: Byte): TTestPoly;
begin
  Result.X[1] := X1;
  Result.Y[1] := Y1;
  Result.X[2] := X2;
  Result.Y[2] := Y2;
  Result.X[3] := X3;
  Result.Y[3] := Y3;
  Result.T := T;
end;

procedure TestMap(const Dir: AnsiString);
var
  P: array[0..4] of TTestPoly;
  n, i: LongInt;
  OX, OY, DX, DY, MaxX, HitX: Single;
  Found: Boolean;
begin
  P[0] := Tri(100, 100, 200, 100, 200, 200, 0);
  P[1] := Tri(100, 100, 200, 200, 100, 200, 0);
  P[2] := Tri(300, 100, 400, 100, 400, 200, 3);
  P[3] := Tri(500, 100, 600, 100, 600, 200, 2);
  P[4] := Tri(700, 100, 800, 100, 800, 200, 1);
  WriteMap(Dir + 'be_test_map.pms', P, 50, 20, False);
  WriteMap(Dir + 'be_test_cut.pms', P, 50, 20, True);
  Check(MapLoad(Dir + 'no_such_map.pms') = -1, 'missing map');
  Check(not MapReady, 'no map after a failed load');
  Check(MapLoad(Dir + 'be_test_cut.pms') = -2, 'cut map refused');
  Check(MapLoad(Dir + 'BE_TEST_MAP.PMS') = 5, 'map found whatever the letter case');
  Check(MapReady, 'map ready');
  Check(MapRay(0, 150, 300, 150, MR_BULLET, 0), 'ray through the block');
  Check(not MapRay(0, 50, 300, 50, MR_BULLET, 0), 'ray above the block');
  Check(MapRay(150, 150, 160, 160, 0, 0), 'ray from inside');
  Check(MapRay(150, 0, 150, 300, 0, 0), 'vertical ray');
  Check(MapRay(50, 120, 250, 180, 0, 0), 'slanted ray');
  Check(not MapRay(250, 150, 450, 150, MR_BULLET, 0), 'no-collide polygon');
  Check(not MapRay(450, 150, 650, 150, MR_BULLET, 0), 'player-only polygon lets bullets through');
  Check(MapRay(450, 150, 650, 150, MR_PLAYER, 0), 'player-only polygon stops players');
  Check(MapRay(650, 150, 850, 150, MR_BULLET, 0), 'bullet-only polygon stops bullets');
  Check(not MapRay(650, 150, 850, 150, 0, 0), 'bullet-only polygon is not a wall for sight');
  Check(MapPointSolid(150, 150, 0, 0) and not MapPointSolid(250, 150, 0, 0), 'point in a wall');
  Check(MapColliders = 1, 'one collider');
  Check(MapRay(900, 150, 1100, 150, MR_BULLET or MR_COLLIDER, 0), 'collider stops the bullet');
  Check(not MapRay(900, 150, 1100, 150, MR_BULLET, 0), 'collider ignored without the flag');
  Check(not MapRay(900, 170, 1100, 170, MR_BULLET or MR_COLLIDER, 0), 'collider radius is a 1.7th');
  Check(MapEdgeCount >= 4, 'outline edges: ' + IntToStr(MapEdgeCount));
  Muzzle(0, 0, 1000, -11.4, 0, OX, OY, DX, DY);
  Check(Near(OX, 1.3, 0.05) and Near(OY, -13.4, 0.05) and Near(DX, 1, 0.001), 'standing muzzle');
  Muzzle(0, 0, -1000, -1.6, SF_PRONE, OX, OY, DX, DY);
  Check(Near(OX, -5.5, 0.05) and Near(OY, -3.6, 0.05) and Near(DX, -1, 0.001), 'prone muzzle facing left');
  Muzzle(0, 0, 0, -1000, SF_CROUCH, OX, OY, DX, DY);
  Check(Near(OX, -2.1, 0.1) and Near(OY, -10.9, 0.1), 'crouching muzzle aiming up');
  TrajRecomputed;
  TrajReset(3);
  TrajInt(TJ_DOTS, 12);
  n := TrajStep(3, 200, 100, 8, 0, 0, 0, 161.4, 0, 0, 1000, 150, 0);
  Found := False;
  HitX := 0;
  for i := 0 to OpCount - 1 do
    if Ops[i].Text = 'x' then
    begin
      Found := True;
      HitX := Ops[i].X;
    end;
  Check(n > 0, 'trajectory drawn');
  Check(Found and (HitX > 85) and (HitX < 105), 'hit mark at the wall: ' + FloatToStr(HitX));
  Check(TrajStep(3, 201, 100, 8, 0, 0, 0, 161.4, 0, 0, 1000, 150, 0) = 0, 'same input: nothing sent');
  Check(TrajRecomputed = 1, 'same input: path not computed again');
  TrajStep(3, 202, 100, 8, 0, 0, 0, 161.4, 0, 0, 1000, 140, 0);
  Check(TrajRecomputed = 1, 'aim moved: computed again');
  TrajReset(4);
  n := TrajStep(4, 300, 100, 8, 0, 0, 0, -1000, 0, 0, 600, -1000, 0);
  MaxX := 0;
  for i := 0 to OpCount - 1 do
    if (Ops[i].Text = '.') and (Ops[i].X > MaxX) then
      MaxX := Ops[i].X;
  Check((n > 0) and (MaxX > 700) and (MaxX < 900), 'path cut at the edge of the view: ' + FloatToStr(MaxX));
  TrajReset(6);
  n := TrajTrack(6, 400, 100, 1, 8, 0, -300, 148, 55, 0);
  Found := False;
  for i := 0 to OpCount - 1 do
    if Ops[i].Text = 'x' then
    begin
      Found := True;
      HitX := Ops[i].X;
    end;
  Check((n > 2) and Found and (HitX > 80) and (HitX < 105), 'tracked bullet path ends at the wall');
  n := TrajTrack(6, 405, 100, 0, 8, 0, -300 + 55 * 3, 148, 55 * 0.97, 0);
  Check((n >= 1) and (n <= 4), 'bullet moved on: only the dots behind it go: ' + IntToStr(n));
  MapClear;
  Check(TrajStep(4, 301, 100, 8, 0, 0, 0, -1000, 0, 0, 600, -1000, 0) = -1, 'no map: the script draws');
  Check(not MapRay(0, 150, 300, 150, MR_BULLET, 0), 'no map: no walls');
end;

procedure AcFeed(ID, Tick, Flags: LongInt);
var
  L: array[0..0] of LongInt;
begin
  L[0] := ID * 16 + Flags;
  AcKeys(Tick, 1, @L);
end;

function BulletAfter(n: LongInt; out BX, V: Single): Boolean;
var
  k: LongInt;
begin
  BX := 0;
  V := 55;
  for k := 1 to n do
  begin
    BX := BX + V;
    V := V * 0.99;
  end;
  Result := True;
end;

procedure TestAc;
var
  T, ID, Kind, n, k: LongInt;
  BX, V: Single;
  Txt: AnsiString;
  Tot, Ac7: TAcTotals;
begin
  WeaponsDefault(False);
  AcSet(AC_ENABLED, 1);
  AcReset(3);
  while AcNext(ID, Kind, Txt) do ;
  WorldName(3, 'Sniper');
  for T := 100 to 125 do
    if T < 101 then
      AcFeed(3, T, 0)
    else
      AcFeed(3, T, AF_FIRE);
  BulletAfter(5, BX, V);
  Check(AcHit(130, 3, 8, 7, 4.45 * V * 0.95, BX, 0, V, 0, 0, 0) = 0, 'barrett shot 24 ticks after the key is fine');
  AcTotals(3, Tot);
  Check((Tot[T_SU_N] = 1) and (Tot[T_SU_BAD] = 0) and (Tot[T_SU_MIN] = 24), 'start-up measured: ' +
    IntToStr(Tot[T_SU_MIN]));
  for T := 126 to 400 do
    if T < 390 then
      AcFeed(3, T, 0)
    else
      AcFeed(3, T, AF_FIRE);
  BulletAfter(2, BX, V);
  Check(AcHit(392, 3, 8, 9, 4.45 * V * 1.1, BX, 0, V, 0, 0, 0) = AK_STARTUP, 'barrett shot at once is reported');
  Check(AcNext(ID, Kind, Txt) and (ID = 3) and (Kind = AK_STARTUP) and (Pos('Sniper', Txt) = 1), 'incident: ' + Txt);
  Check(AcHit(393, 3, 8, 9, 4.45 * V * 1.1, BX + V, 0, V * 0.99, 0, 0, 0) = 0, 'the same bullet counts once');
  for T := 401 to 510 do
    if T < 490 then
      AcFeed(3, T, 0)
    else
      AcFeed(3, T, AF_FIRE or AF_MOVE);
  AcHurt(3, 485, 8);
  BulletAfter(1, BX, V);
  k := AcHit(510, 3, 8, 11, 4.45 * V * 0.95, BX, 0, V, 0, 0, 0);
  Check(k = AK_RATE, 'two barrett shots 120 ticks apart: ' + IntToStr(k));
  AcTotals(3, Tot);
  Check((Tot[T_BINK_HITS] = 1) and (Tot[T_B_HITS] = 3), 'hit under bink counted');
  Check((Tot[T_MOVE_HITS] = 1) and (Tot[T_M_HITS] = 3), 'hit while running counted');
  Check(AcScore(3) >= 40, 'score: ' + IntToStr(AcScore(3)));
  Check(Pos('start-up 1/3 too fast', AcBrief(Tot)) > 0, 'brief: ' + AcBrief(Tot));
  Check(Pos('1 of 3 shots too fast (fastest 0, average 14 ticks)', AcDetail(Tot)) > 0, 'detail: ' + AcDetail(Tot));
  Check(AcFindings(Tot) = 2, 'findings: ' + IntToStr(AcFindings(Tot)));
  Check(Pos('s ago: Sniper', AcReview(3, 600)) > 0, 'review: ' + AcReview(3, 600));
  AcReset(7);
  AcAmmo(7, 1000, 3, 40);
  AcAmmo(7, 1030, 3, 36);
  AcTotals(7, Ac7);
  Check(AcFindings(Ac7) = 0, 'ammo at the fire rate');
  AcAmmo(7, 1040, 3, 20);
  AcTotals(7, Tot);
  Check(Tot[T_AMMO] = 1, 'ammo used too fast');
  AcAmmo(7, 1050, 3, 0);
  AcAmmo(7, 1070, 3, 40);
  AcTotals(7, Tot);
  Check(Tot[T_RELOAD] = 1, 'reload too fast');
  AcAmmo(7, 1100, 3, 38);
  AcAmmo(7, 1110, 3, 0);
  AcAmmo(7, 1300, 3, 40);
  AcTotals(7, Tot);
  Check((Tot[T_RELOAD] = 1) and (Tot[T_AMMO] = 1), 'a manual reload and a normal one are fine');
  while AcNext(ID, Kind, Txt) do ;
  AcReset(4);
  WClear;
  WAdd(4, WF_ALIVE or WF_HUMAN, 1, 100, 0, 0, 0, 0, 100, 100, 0, 0);
  WorldLoad(600, WN, @WI, @WF);
  AcWorld(600);
  WClear;
  WAdd(4, WF_ALIVE or WF_HUMAN, 1, 100, 0, 0, 0, 0, 1500, 100, 0, 0);
  WorldLoad(603, WN, @WI, @WF);
  AcWorld(603);
  Check(AcNext(ID, Kind, Txt) and (Kind = AK_JUMP), 'teleport seen: ' + Txt);
  AcMoved(4, 605);
  WClear;
  WAdd(4, WF_ALIVE or WF_HUMAN, 1, 100, 0, 0, 0, 0, 3000, 100, 0, 0);
  WorldLoad(610, WN, @WI, @WF);
  AcWorld(610);
  Check(not AcNext(ID, Kind, Txt), 'a move by the script is not a teleport');
  WClear;
  WAdd(4, WF_ALIVE or WF_HUMAN, 1, 100, 0, 0, 0, 0, 3010, 100, 0, 0);
  WorldLoad(720, WN, @WI, @WF);
  AcWorld(720);
  Check(not AcNext(ID, Kind, Txt), 'walking is not a teleport');
  AcReset(5);
  for k := 0 to 8 do
  begin
    WClear;
    WAdd(5, WF_ALIVE or WF_HUMAN, 1, 100, 0, 0, 0, 0, 100 + k * 200, 100, 0, 0);
    WorldLoad(2000 + k * 10, WN, @WI, @WF);
    AcWorld(2000 + k * 10);
  end;
  AcTotals(5, Tot);
  Check(Tot[T_SPEED] = 1, 'sustained speed seen: ' + IntToStr(Tot[T_SPEED]));
  while AcNext(ID, Kind, Txt) do ;
  AcSet(AC_ENABLED, 0);
end;

procedure TestFx;
var
  k: LongInt;
begin
  for k := 0 to FX_LAST do
    Check(FxBuild(k, 1, 1) > 0, 'effect ' + IntToStr(k));
  FxBuild(FX_BIG, 3, 1);
  Check(FxCount > 20, 'big explosion is big');
end;

var
  Dir: AnsiString;
begin
  Dir := IncludeTrailingPathDelimiter(GetTempDir);
  if ParamCount > 0 then
    Dir := IncludeTrailingPathDelimiter(ParamStr(1));
  ForceDirectories(Dir);
  TestFont;
  TestRadarList;
  TestRadarRing;
  TestSuppression;
  TestPathClip;
  TestRadarCircle;
  TestLabels;
  TestVision;
  TestMove;
  TestBallistics;
  TestWeaponsIni(Dir);
  TestGun;
  TestTargets;
  TestTraj;
  TestCircle;
  TestMap(Dir);
  TestAc;
  TestFx;
  WriteLn(Passed, ' passed, ', Failed, ' failed');
  if Failed > 0 then
    Halt(1);
  WriteLn('test_engine: all passed');
end.
