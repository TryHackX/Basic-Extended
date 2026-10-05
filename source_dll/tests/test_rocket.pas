program test_rocket;

{ The guided rocket's flight (be_rocket) on a real map, without the server: shooters and targets on
  the floors of the map, a rocket each, its track written to a text file that tools can draw.

  test_rocket <map.pms> <out.txt> [count] [seed] [runner] [profile] [sx sy tx ty]
    count   scenarios (default 12)
    seed    random seed (default 1)
    runner  1 = the targets run left and right at 3 px a tick (default 0: they stand)
    profile 0 direct, 1 top, 2 auto (default)
    sx sy tx ty  one scenario at these places (feet), count times

  The out file: "P x1 y1 x2 y2 x3 y3 type" the polygons, "S n sx sy tx ty" a scenario, "R n x y phase"
  the rocket every tick, "T n x y" the target, "E n kind x y" an event (4 hit, 5 next to another,
  6 wall, 7 air, 2 motor start). The summary goes to the screen; the exit code is 1 when the map could
  not be read or a rocket did something impossible (NaN, a tick without an end). }

{$mode objfpc}{$H+}

uses
  SysUtils, Math, be_map, be_world, be_rocket;

const
  BODY_H = 10;

var
  OutF: Text;
  MinX, MinY, MaxX, MaxY: Single;
  Bad: LongInt = 0;

function Solid(X, Y: Single): Boolean;
begin
  Result := MapPointSolid(X, Y, MR_BULLET, 0);
end;

{ the floor under X, Y within 600 px: its height, or 1e9 }
function FloorUnder(X, Y: Single): Single;
var
  Lo, Hi, Mid: Single;
  i: LongInt;
begin
  Result := 1e9;
  if not MapRay(X, Y, X, Y + 600, MR_BULLET, 0) then
    Exit;
  Lo := 0;
  Hi := 600;
  for i := 1 to 12 do
  begin
    Mid := (Lo + Hi) / 2;
    if MapRay(X, Y, X, Y + Mid, MR_BULLET, 0) then
      Hi := Mid
    else
      Lo := Mid;
  end;
  Result := Y + Lo;
end;

{ a place to stand: feet on a floor, room for the body }
function StandPoint(out X, Y: Single): Boolean;
var
  n: LongInt;
  F: Single;
begin
  Result := False;
  for n := 1 to 400 do
  begin
    X := MinX + Random * (MaxX - MinX);
    Y := MinY + Random * (MaxY - MinY);
    if Solid(X, Y) then
      Continue;
    F := FloorUnder(X, Y);
    if F > 1e8 then
      Continue;
    Y := F - 1;
    if MapRay(X, Y - 2, X, Y - 40, MR_BULLET, 0) then
      Continue;
    { inside the map: walls all around }
    if not MapRay(X, Y - 20, X, Y - 4000, MR_BULLET, 0) then
      Continue;
    if not MapRay(X, Y - 20, X - 6000, Y - 20, MR_BULLET, 0) then
      Continue;
    if not MapRay(X, Y - 20, X + 6000, Y - 20, MR_BULLET, 0) then
      Continue;
    Result := True;
    Exit;
  end;
end;

procedure WritePolys;
var
  i, T: LongInt;
  X1, Y1, X2, Y2, X3, Y3: Single;
begin
  MinX := 1e9;
  MinY := 1e9;
  MaxX := -1e9;
  MaxY := -1e9;
  for i := 1 to MapPolys do
    if MapPolyGet(i, X1, Y1, X2, Y2, X3, Y3, T) then
    begin
      WriteLn(OutF, Format('P %.1f %.1f %.1f %.1f %.1f %.1f %d', [X1, Y1, X2, Y2, X3, Y3, T]));
      MinX := Min(MinX, Min(X1, Min(X2, X3)));
      MaxX := Max(MaxX, Max(X1, Max(X2, X3)));
      MinY := Min(MinY, Min(Y1, Min(Y2, Y3)));
      MaxY := Max(MaxY, Max(Y1, Max(Y2, Y3)));
    end;
end;

var
  Count, Seed, Runner, n, k, e, t, Kind, Owner, Target, Phase, Tries: LongInt;
  SX, SY, TX, TY, TVX, NY, X, Y, VX, VY, PX, PY, Dist: Single;
  Hits, Prox, Wall, Air, Lost, Timeout, SumT, Top, Near: LongInt;
  Done: Boolean;
begin
  if ParamCount < 2 then
  begin
    WriteLn('test_rocket <map.pms> <out.txt> [count] [seed] [runner]');
    Halt(2);
  end;
  if MapLoad(ParamStr(1)) <= 0 then
  begin
    WriteLn('the map could not be read: ', ParamStr(1));
    Halt(1);
  end;
  Count := StrToIntDef(ParamStr(3), 12);
  Seed := StrToIntDef(ParamStr(4), 1);
  Runner := StrToIntDef(ParamStr(5), 0);
  { profile: 0 direct, 1 top, 2 auto (default) }
  RkSet(RKC_PROFILE, StrToIntDef(ParamStr(6), 2));
  RandSeed := Seed;
  Assign(OutF, ParamStr(2));
  Rewrite(OutF);
  WritePolys;
  Hits := 0;
  Near := 0;
  Prox := 0;
  Wall := 0;
  Air := 0;
  Lost := 0;
  Timeout := 0;
  SumT := 0;
  Top := 0;
  { the world: the shooter 1, the target 2 (a team game, other teams) }
  RkSet(RKC_TEAM_GAME, 1);
  for n := 1 to Count do
  begin
    Tries := 0;
    { one scenario of the command line: sx sy tx ty (feet) }
    if ParamCount >= 10 then
    begin
      SX := StrToFloat(ParamStr(7));
      SY := StrToFloat(ParamStr(8));
      TX := StrToFloat(ParamStr(9));
      TY := StrToFloat(ParamStr(10));
      Tries := -1;
    end;
    if Tries = 0 then
    repeat
      Inc(Tries);
      if not StandPoint(SX, SY) then
        Continue;
      if not StandPoint(TX, TY) then
        Continue;
      Dist := Sqrt(Sqr(TX - SX) + Sqr(TY - SY));
      if (Dist < 250) or (Dist > 1000) then
        Continue;
      if MapRay(SX, SY - 11, TX, TY - BODY_H, MR_BULLET, 0) then
        Continue;
      Break;
    until Tries > 5000;
    if Tries > 5000 then
      Break;
    WriteLn(OutF, Format('S %d %.1f %.1f %.1f %.1f', [n, SX, SY, TX, TY]));
    RkReset;
    WTick := 0;
    WP[1].Active := True;
    WP[1].Alive := True;
    WP[1].Team := 1;
    WP[1].X := SX;
    WP[1].Y := SY;
    WP[2].Active := True;
    WP[2].Alive := True;
    WP[2].Team := 2;
    WP[2].X := TX;
    WP[2].Y := TY;
    TVX := 0;
    if Runner = 1 then
      TVX := 3;
    k := RkLaunch(1, 2, SX, SY - 11, TX, TY - BODY_H, TVX, 0);
    if k < 0 then
    begin
      WriteLn('no slot');
      Inc(Bad);
      Break;
    end;
    if Rk[k].Climb then
    begin
      Inc(Top);
      WriteLn(OutF, Format('C %d', [n]));
    end;
    Done := False;
    for t := 1 to 900 do
    begin
      if Runner = 1 then
      begin
        { runs along the floor, turning every 40 ticks and at walls and edges }
        if t mod 40 = 0 then
          TVX := -TVX;
        NY := FloorUnder(TX + TVX, TY - 30);
        if (NY > TY + 40) or MapRay(TX, TY - BODY_H, TX + TVX, NY - BODY_H, MR_BULLET, 0) then
        begin
          TVX := -TVX;
          NY := FloorUnder(TX + TVX, TY - 30);
        end;
        if (NY <= TY + 40) and not MapRay(TX, TY - BODY_H, TX + TVX, NY - BODY_H, MR_BULLET, 0) then
        begin
          TX := TX + TVX;
          TY := NY - 1;
        end;
      end;
      WTick := t;
      WP[2].X := TX;
      WP[2].Y := TY;
      RkAim(k, 1, TX, TY - BODY_H, TVX, 0);
      RkStep(t);
      if RkState(k, Owner, Target, Phase, X, Y, PX, PY) then
      begin
        if IsNan(X) or IsNan(Y) then
        begin
          WriteLn('NaN in scenario ', n);
          Inc(Bad);
          Done := True;
        end;
        WriteLn(OutF, Format('R %d %.1f %.1f %d', [n, X, Y, Phase]));
      end;
      WriteLn(OutF, Format('T %d %.1f %.1f', [n, TX, TY]));
      while RkNext(e, Kind, Owner, Target, X, Y, VX, VY) do
      begin
        if Kind in [RE_HIT, RE_PROX, RE_WALL, RE_AIR, RE_IGNITE, RE_LOST] then
          WriteLn(OutF, Format('E %d %d %.1f %.1f', [n, Kind, X, Y]));
        case Kind of
          RE_HIT:
            begin
              Inc(Hits);
              Inc(SumT, t);
              Done := True;
            end;
          RE_PROX:
            begin
              Inc(Prox);
              Done := True;
            end;
          RE_WALL:
            begin
              Inc(Wall);
              { within the blast of the burst (the M79 grenades reach 64 px) }
              if Sqrt(Sqr(X - TX) + Sqr(Y - TY + BODY_H)) <= 50 then
                Inc(Near);
              Done := True;
            end;
          RE_AIR:
            begin
              Inc(Air);
              Done := True;
            end;
          RE_LOST:
            begin
              Inc(Lost);
              Done := True;
            end;
        end;
      end;
      if Done then
        Break;
    end;
    if not Done then
    begin
      Inc(Timeout);
      Inc(Bad);
    end;
  end;
  Close(OutF);
  WriteLn(Format('%d rockets (%d top attack): %d hits, %d next to another, %d walls (%d within 50 px of him), %d in ' +
    'the air, %d lost, %d never ended; a hit after %.1f ticks', [Hits + Prox + Wall + Air + Lost + Timeout, Top, Hits,
    Prox, Wall, Near, Air, Lost, Timeout, SumT / Max(1, Hits)]));
  WriteLn(RkInfo);
  if Bad > 0 then
    Halt(1);
end.
