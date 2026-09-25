program test_engine;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils, be_font, be_world, be_texts, be_radar, be_move, be_ballistic, be_gun, be_traj, be_fx;

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
end;

procedure TestRadarArrows;
var
  n, i, k, Dots: LongInt;
  X0, Y0, CX, CY: Single;
begin
  RadarReset(1);
  RadarInt(RI_ARROWS_MAX, 4);
  RadarInt(RI_ARROW_DOTS, 3);
  RadarFloat(RF_ARROW_LEAD, 1);
  WClear;
  WAdd(1, WF_ALIVE or WF_HUMAN, 1, 100, 0, 0, 0, 0, 500, 500, 0, 0);
  WAdd(2, WF_ALIVE, 2, 80, 0, 0, 0, 0, 700, 500, 0, 0);
  WAdd(3, WF_ALIVE, 2, 80, 0, 0, 0, 0, 500, 300, 0, 0);
  WLoad(2000);
  RadarUser(1, 1, OVL_ARROWS, SHOW_ALL, 0, 0, 1, 1, 1, 0);
  n := RadarPass(1, 2000, 100);
  Dots := 3 + 2;
  Check(n = 2 * Dots, 'two arrows of five dots: ' + IntToStr(n));
  for i := 0 to n - 1 do
    Check(Ops[i].Text = '.', 'arrow dots are periods');
  InkCenter('.', CX, CY);
  k := FindOp(KIND_WORLD, 210 + 2);
  if k < 0 then
    k := FindOp(KIND_WORLD, 210 + 8 + 2);
  Check(k >= 0, 'tip dot present');
  n := RadarPass(1, 2001, 100);
  Check(n = 0, 'still arrows are not resent');
  WClear;
  WAdd(1, WF_ALIVE or WF_HUMAN, 1, 100, 0, 0, 0, 0, 501, 500, 0, 0);
  WAdd(2, WF_ALIVE, 2, 80, 0, 0, 0, 0, 700, 500, 0, 0);
  WAdd(3, WF_ALIVE, 2, 80, 0, 0, 0, 0, 500, 300, 0, 0);
  WLoad(2002);
  n := RadarPass(1, 2002, 100);
  Check(n = 0, 'a move below ArrowMove sends nothing');
  WClear;
  WAdd(1, WF_ALIVE or WF_HUMAN, 1, 100, 0, 0, 0, 0, 510, 500, 0, 0);
  WAdd(2, WF_ALIVE, 2, 80, 0, 0, 0, 0, 700, 500, 0, 0);
  WAdd(3, WF_ALIVE, 2, 80, 0, 0, 0, 0, 500, 300, 0, 0);
  WLoad(2003);
  n := RadarPass(1, 2003, 4);
  Check(n = 0, 'an arrow goes whole or not at all: ' + IntToStr(n));
  Check(RadarPending(1) = 1, 'rest is pending');
  n := RadarPass(1, 2004, Dots + 2);
  Check(n = Dots, 'one whole arrow within the budget: ' + IntToStr(n));
  Check(RadarPending(1) = 1, 'the other arrow is pending');
  n := RadarPass(1, 2005, 100);
  Check(n = Dots, 'the other arrow next: ' + IntToStr(n));
  Check(RadarPending(1) = 0, 'nothing pending');
  WClear;
  WAdd(1, WF_ALIVE or WF_HUMAN, 1, 100, 0, 0, 0, 0, 510, 500, 0, 0);
  WAdd(2, WF_ALIVE, 2, 80, 0, 0, 0, 0, 706, 500, 0, 0);
  WAdd(3, WF_ALIVE, 2, 80, 0, 0, 0, 0, 499.7, 294, 0, 0);
  WLoad(2006);
  n := RadarPass(1, 2006, 100);
  Check(n = 0, 'a distance change within a colour band sends nothing: ' + IntToStr(n));
  WClear;
  WAdd(1, WF_ALIVE or WF_HUMAN, 1, 100, 0, 0, 0, 0, 530, 500, 0, 0);
  WAdd(2, WF_ALIVE, 2, 80, 0, 0, 0, 0, 706, 500, 0, 0);
  WAdd(3, WF_ALIVE, 2, 80, 0, 0, 0, 0, 510, 294, 0, 0);
  WLoad(2007);
  n := RadarPass(1, 2007, Dots);
  Check(n = Dots, 'one arrow a pass under a tight budget: ' + IntToStr(n));
  n := RadarPass(1, 2008, Dots);
  Check(n = Dots, 'the older arrow gets its turn: ' + IntToStr(n));
  Check(RadarPending(1) = 0, 'both arrows caught up');
  WClear;
  WAdd(1, WF_ALIVE or WF_HUMAN, 1, 100, 0, 100, 0, 0, 510, 500, 5, 0);
  WAdd(2, WF_ALIVE, 2, 80, 0, 0, 0, 0, 700, 500, 0, 0);
  WLoad(2010);
  n := RadarPass(1, 2010, 100);
  k := FindOp(KIND_WORLD, 210);
  if k < 0 then
    k := FindOp(KIND_WORLD, 210 + 8);
  Check(k >= 0, 'first shaft dot of the remaining arrow');
  if k >= 0 then
  begin
    X0 := Ops[k].X + CX * Ops[k].Scale * WORLD_EM;
    Check(Near(X0, 510 + 5 * 6 + 16, 0.6), 'arrow centre predicted with ping and velocity: ' + FloatToStr(X0));
  end;
  Check(FindOp(KIND_WORLD, 210 + 8) >= 0, 'dots of the gone arrow are hidden or moved');
  RadarUser(1, 1, OVL_LIST, SHOW_ALL, 10, 150, 1, 1, 1, 0);
  n := RadarPass(1, 2011, 100);
  k := 0;
  for i := 0 to n - 1 do
    if Ops[i].Text = ' ' then
      Inc(k);
  Check(k = Dots, 'mode change hides the arrows: ' + IntToStr(k));
  Y0 := 0;
  Check(Y0 = 0, 'noop');
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
  A, T: LongInt;
  OX, OY, OVX, OVY, Sp, LastSp, MaxSp, FlyX: Single;
begin
  MoveReset(5);
  A := MoveStep(5, 100, TP_MOMENTUM, VAR_INHERIT, 0, 1, 100, 100, 0, 0, 300, 100, OX, OY, OVX, OVY);
  Check(A = 0, 'no action without a press');
  A := MoveStep(5, 101, TP_MOMENTUM, VAR_INHERIT, 1, 1, 100, 100, 0, 0, 300, 100, OX, OY, OVX, OVY);
  Check((A and MA_MOVE) <> 0, 'tap moves');
  Check(Near(OX, 300, 0.01) and Near(OY, 100, 0.01), 'tap target is the cursor');
  Check(Near(OVX, 2 + 200 * 0.008, 0.01) and Near(OVY, 0, 0.01), 'tap speed');
  LastSp := 0;
  for T := 102 to 160 do
  begin
    A := MoveStep(5, T, TP_MOMENTUM, VAR_INHERIT, 1, 1, 300, 100, 3.6, 0, 300 + (T - 100) div 5, 100, OX, OY,
      OVX, OVY);
    if (A and MA_VELOCITY) <> 0 then
      LastSp := Sqrt(OVX * OVX + OVY * OVY);
  end;
  Check(LastSp > 3.6, 'inherit variant accelerates: ' + FloatToStr(LastSp));
  MaxSp := 0;
  for T := 161 to 900 do
  begin
    A := MoveStep(5, T, TP_MOMENTUM, VAR_INHERIT, 1, 1, 300, 100, 3.6, 0, 400 + T, 100, OX, OY, OVX, OVY);
    if (A and MA_VELOCITY) <> 0 then
    begin
      Sp := Sqrt(OVX * OVX + OVY * OVY);
      if Sp > MaxSp then
        MaxSp := Sp;
    end;
  end;
  Check((MaxSp > 8) and (MaxSp <= 9.2), 'vmax reached and respected: ' + FloatToStr(MaxSp));
  MoveReset(6);
  MoveStep(6, 200, TP_FLY, VAR_FIXED, 0, 1, 100, 100, 0, 0, 105, 102, OX, OY, OVX, OVY);
  A := MoveStep(6, 201, TP_FLY, VAR_FIXED, 1, 1, 100, 100, 0, 0, 105, 102, OX, OY, OVX, OVY);
  Check((A and MA_VELOCITY) <> 0, 'fly pushes');
  Check(Near(OVX, 0, 0.01) and (OVY < 0) and (OVY > -0.2), 'inside the dead zone it only hovers');
  A := MoveStep(6, 203, TP_FLY, VAR_FIXED, 1, 1, 130, 100, 3, 0, 105, 102, OX, OY, OVX, OVY);
  Check(OVX >= -0.01, 'a stale cursor behind the moving player does not reverse the push');
  MoveReset(7);
  MoveStep(7, 300, TP_FLY, VAR_FIXED, 0, 1, 100, 100, 0, 0, 250, 100, OX, OY, OVX, OVY);
  FlyX := 0;
  for T := 301 to 340 do
  begin
    A := MoveStep(7, T, TP_FLY, VAR_FIXED, 1, 1, 100, 100, 0, 0, 250, 100, OX, OY, OVX, OVY);
    if (A and MA_VELOCITY) <> 0 then
      FlyX := OVX;
  end;
  Check(Near(FlyX, 1 + (150 - 18) * 0.03, 0.3), 'fly speed grows with the distance: ' + FloatToStr(FlyX));
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
  n := BuildShot(5, 0, 0, 0, 0, 1, 0, 1, 7);
  Check(n = 6, 'shotgun six pellets');
  n := BuildShot(1, 0, 0, 0, 0, 1, 0, 1, 7);
  Check(n = 2, 'deagles two bullets');
  n := BuildShot(3, 0, 0, 2, 0, 1, 0, 1, 7);
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
  RadarInt(RI_TEAMGAME, 0);
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
  TestRadarArrows;
  TestRadarCircle;
  TestLabels;
  TestVision;
  TestMove;
  TestBallistics;
  TestWeaponsIni(Dir);
  TestGun;
  TestTargets;
  TestTraj;
  TestFx;
  WriteLn(Passed, ' passed, ', Failed, ' failed');
  if Failed > 0 then
    Halt(1);
  WriteLn('test_engine: all passed');
end.
