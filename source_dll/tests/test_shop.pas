program test_shop;

{ be_shop on a real map: an explosive round's first wall (the predicted point lies on a wall: open just before
  it, solid just after; the flight before it is free), the ground under a point.
  Usage: test_shop <map.pms> }

{$mode objfpc}{$H+}

uses
  SysUtils, be_map, be_ballistic, be_shop;

var
  Failed, Passed: LongInt;

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

var
  Ok: Boolean;
  k, n, Hits, Good, t: LongInt;
  X, Y, A, VX, VY, HX, HY, GY, DX, DY, L: Single;
begin
  Failed := 0;
  Passed := 0;
  WeaponsDefault(False);
  if MapLoad(ParamStr(1)) <= 0 then
  begin
    WriteLn('cannot read the map ', ParamStr(1));
    Halt(1);
  end;
  { Barrett rounds (55 px a tick) in 24 directions from open points of ctf_Ash }
  Hits := 0;
  Good := 0;
  for n := 0 to 2 do
  begin
    if n = 0 then
    begin
      X := 380;
      Y := -100;
    end
    else if n = 1 then
    begin
      X := -285;
      Y := -290;
    end
    else
    begin
      X := 0;
      Y := -200;
    end;
    if MapPointSolid(X, Y, MR_BULLET, 0) then
      Continue;
    for k := 0 to 23 do
    begin
      A := k * Pi / 12;
      VX := Cos(A) * 55;
      VY := Sin(A) * 55;
      t := ShopApPredict(1, X, Y, VX, VY, 60, 0, HX, HY);
      if t > 0 then
      begin
        Inc(Hits);
        DX := HX - X;
        DY := HY - Y;
        L := Sqrt(DX * DX + DY * DY);
        if L < 1 then
          L := 1;
        { just before the point: open; the point a little further along the last step: solid }
        if (not MapPointSolid(HX - VX / 55 * 2, HY - VY / 55 * 2, MR_BULLET, 0)) and
          MapRay(HX - VX / 55 * 3, HY - VY / 55 * 3, HX + VX / 55 * 3, HY + VY / 55 * 3, MR_BULLET, 0) then
          Inc(Good);
      end;
    end;
  end;
  Check(Hits >= 20, 'most directions meet a wall within a second (' + IntToStr(Hits) + ')');
  Check(Good >= Hits - 2, 'the predicted points lie on the walls (' + IntToStr(Good) + ' of ' + IntToStr(Hits) + ')');
  Check(ShopApPredict(1, 0, -200, 0, -55, 2, 0, HX, HY) = -1, 'upwards for 2 ticks from the open: no wall');
  { the ground: the floor at y -69 of ctf_Ash's lower part (x 300-400), under the platform at -120 }
  GY := 0;
  Ok := ShopGround(380, -100, 400, GY);
  WriteLn('the ground under (380, -100): ', GY:0:1);
  Check(Ok and (Abs(GY + 69) < 6), 'the ground under (380, -100) is the floor at -69');
  Check(not ShopGround(380, -100, 20, GY), 'nothing within 20 px');
  { round 26: a long search (a crate 600 px, the mortar 800 px) finds the same floor - 8 halvings missed it }
  Ok := ShopGround(380, -100, 800, GY);
  Check(Ok and (Abs(GY + 69) < 6), 'the floor at -69 with an 800 px search too (' + FloatToStrF(GY, ffFixed, 8, 1) + ')');
  n := 0;
  for k := 0 to 19 do
    if ShopGround(330 + k * 3, -100, 600 + k * 20, GY) then
      if Abs(GY + 69) < 6 then
        Inc(n);
  Check(n = 20, 'searches of 600-980 px all find the floor (' + IntToStr(n) + ' of 20)');
  { a point inside a wall: out of it first, then the floor under it (never in the wall, never under a low roof) }
  n := 0;
  for k := 0 to 40 do
  begin
    X := -800 + k * 40;
    Y := -40;
    if MapPointSolid(X, Y, MR_PLAYER, 0) then
      if ShopGround(X, Y, 400, GY) then
      begin
        Inc(n);
        if MapPointSolid(X, GY - 6, MR_PLAYER, 0) or MapRay(X, GY - 2, X, GY - 24, MR_PLAYER, 0) then
        begin
          WriteLn('  in a wall or under a low roof at ', X:0:0, ', ', GY:0:1);
          n := -1000;
        end;
      end;
  end;
  Check(n > 0, 'points inside the ground: a floor over them with room (' + IntToStr(n) + ')');
  WriteLn(Passed, ' passed, ', Failed, ' failed');
  if Failed > 0 then
    Halt(1);
end.
