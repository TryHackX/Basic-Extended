program test_sprite;

{ Round 26: the soldiers' weapons, keys and aim read from their records (be_sprite) and the ammunition of all of
  them in one call (be_ammo AmmoPass), on fake records laid out as the server's: the skeleton's points at +692,
  three gun records in a row (the weapon in the hands, the second one, the grenades) right after the control record
  (12 keys, then the aim). }

{$mode objfpc}{$H+}

uses
  SysUtils, be_sprite, be_ammo, be_ballistic;

const
  REC = 60000;
  CTL = 49084;
  GUN = 49104;
  STEP = 96;

type
  { the class name must hold ActivePlayer, the record's pointer is its first field (as TScriptActivePlayer) }
  TFakeActivePlayer = class
    FSprite: Pointer;
  end;

var
  Recs: array[1..4, 0..REC - 1] of Byte;
  Obj: array[1..4] of TFakeActivePlayer;
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

procedure PutSingle(ID, Off: LongInt; V: Single);
begin
  Move(V, Recs[ID, Off], 4);
end;

procedure PutSmall(ID, Off: LongInt; V: SmallInt);
begin
  Move(V, Recs[ID, Off], 2);
end;

var
  { the control record's layout of the fake soldiers: 2 = today's source (keys, then the aim), 1 = 2.8.2's (left,
    right, up, down, the aim, then fire ... flag throw) }
  Layout: LongInt = 2;

{ a soldier at X, Y: alive, his skeleton around him, his weapons, keys and aim }
procedure Soldier(ID: LongInt; X, Y: Single; W, A, SW, SA, Gren, AimX, AimY: LongInt);
var
  k: LongInt;
begin
  FillChar(Recs[ID], REC, 0);
  Recs[ID, 0] := 1;
  Recs[ID, 1] := 0;
  Recs[ID, 4] := ID;
  for k := 0 to 24 do
  begin
    PutSingle(ID, 692 + k * 8, X + (k mod 5) * 3 - 6);
    PutSingle(ID, 692 + k * 8 + 4, Y - (k div 5) * 4);
  end;
  Recs[ID, GUN] := 30;
  Recs[ID, GUN + 1] := A;
  Recs[ID, GUN + 2] := W;
  Recs[ID, GUN + STEP] := 12;
  Recs[ID, GUN + STEP + 1] := SA;
  Recs[ID, GUN + STEP + 2] := SW;
  Recs[ID, GUN + 2 * STEP + 1] := Gren;
  Recs[ID, GUN + 2 * STEP + 2] := 51;
  if Layout = 1 then
  begin
    PutSmall(ID, CTL + 4, AimX);
    PutSmall(ID, CTL + 6, AimY);
  end
  else
  begin
    PutSmall(ID, CTL + 12, AimX);
    PutSmall(ID, CTL + 14, AimY);
  end;
  Obj[ID].FSprite := @Recs[ID, 0];
end;

var
  i, n, k, W, A, ID, Act, V: LongInt;
  Alive, Fire, Reload, SawFull, SawOther: Boolean;
begin
  for i := 1 to 4 do
    Obj[i] := TFakeActivePlayer.Create;
  Soldier(1, 500, 300, 3, 30, 0, 12, 2, 700, -250);
  Soldier(2, 900, 200, 5, 7, 1, 7, 1, -1200, 480);
  Soldier(3, 100, 100, 2, 20, 0, 12, 0, 50, 60);
  Check(SpriteBind(1, Obj[1], 500, 300) = 1, 'soldier 1 bound');
  Check(SpriteBind(2, Obj[2], 900, 200) = 1, 'soldier 2 bound');
  Check(SpriteKnown(3), 'soldier 3 worked out from the table''s step: ' + SpriteInfo);

  Check(SpriteCalibrate(1, 3, 30, 0, 12, 2, 700, -250) = 0, 'one soldier is not enough');
  Check(not SpriteMemReady, 'not ready after one sample');
  Check(SpriteCalibrate(2, 5, 7, 1, 7, 1, -1200, 480) = 1, 'a second soldier confirms the places: ' + SpriteMemInfo);
  Check(SpriteMemReady, 'ready');
  Check(Pos('guns at +49104 step 96, keys at +49084 laid out as 2', SpriteMemInfo) > 0, 'the places found: ' +
    SpriteMemInfo);

  Recs[3, CTL + 4] := 1;
  Recs[3, CTL + 9] := 1;
  Check(SpriteRead(3, Alive, W, A, Fire, Reload) and Alive and (W = 2) and (A = 20) and Fire and Reload,
    'soldier 3 read: weapon, rounds, the fire and reload keys');
  Recs[3, 1] := 1;
  Check(SpriteRead(3, Alive, W, A, Fire, Reload) and not Alive, 'a dead soldier (DeadMeat)');
  Recs[3, 1] := 0;

  Check(SpriteCheck(1, 1, 3, 30, 0, 12, 2, 700, -250, 0) = 1, 'the check of soldier 1 against his properties');
  Recs[1, CTL + 9] := 1;
  Check(SpriteCheck(1, 1, 3, 30, 0, 12, 2, 700, -250, 512) = 1, 'his reload key (bit 9) as the property says');
  Recs[1, CTL + 9] := 0;
  Recs[1, GUN + 1] := 29;
  Check(SpriteCheck(1, 1, 3, 30, 0, 12, 2, 700, -250, 0) = 0, 'a mismatch switches it off');
  Check(not SpriteMemReady, 'off for good');
  Check(SpriteCalibrate(1, 3, 29, 0, 12, 2, 700, -250) = 0, 'no calibration after it was switched off');
  Recs[1, GUN + 1] := 30;

  { a calibration that fails: the second soldier has his weapons somewhere else }
  SpriteMemReset;
  Soldier(4, 300, 300, 4, 25, 1, 7, 3, 10, 20);
  Recs[4, GUN + 2] := 0;
  Recs[4, GUN + 2 + 400] := 4;
  Recs[4, GUN + 1 + 400] := 25;
  Check(SpriteCalibrate(1, 3, 30, 0, 12, 2, 700, -250) = 0, 'reset: one sample');
  Check(SpriteCalibrate(4, 4, 25, 1, 7, 3, 10, 20) = 0, 'a soldier without the pattern confirms nothing');
  Check(not SpriteMemReady, 'not ready');
  Check(SpriteCalibrate(2, 5, 7, 1, 7, 1, -1200, 480) = 1, 'another soldier with it does');

  { 2.8.2's control record: the aim after the first four keys, the fire key 10 bytes in, the reload key 15 }
  SpriteMemReset;
  Layout := 1;
  Soldier(1, 500, 300, 3, 30, 0, 12, 2, 700, -250);
  Soldier(2, 900, 200, 5, 7, 1, 7, 1, -1200, 480);
  Soldier(3, 100, 100, 2, 20, 0, 12, 0, 50, 60);
  Check(SpriteCalibrate(1, 3, 30, 0, 12, 2, 700, -250) = 0, '2.8.2: one sample');
  Check(SpriteCalibrate(2, 5, 7, 1, 7, 1, -1200, 480) = 1, '2.8.2: confirmed: ' + SpriteMemInfo);
  Check(Pos('laid out as 1', SpriteMemInfo) > 0, '2.8.2 layout found: ' + SpriteMemInfo);
  Recs[3, CTL + 10] := 1;
  Check(SpriteRead(3, Alive, W, A, Fire, Reload) and Fire and not Reload, '2.8.2: the fire key at +10');
  Recs[3, CTL + 10] := 0;
  Recs[3, CTL + 15] := 1;
  Check(SpriteRead(3, Alive, W, A, Fire, Reload) and Reload and not Fire, '2.8.2: the reload key at +15');
  Check(SpriteCheck(3, 1, 2, 20, 0, 12, 0, 50, 60, 512) = 1, '2.8.2: the check with his reload key');
  Recs[3, CTL + 15] := 0;
  Recs[1, CTL + 2] := 1;
  Check(SpriteCheck(1, 1, 3, 30, 0, 12, 2, 700, -250, 4) = 1, '2.8.2: the up key');
  Recs[1, CTL + 2] := 0;
  { 4.1: prone at +17 and flag throw at +18 - the byte at +16 is no key }
  Recs[1, CTL + 17] := 1;
  Check(SpriteCheck(1, 1, 3, 30, 0, 12, 2, 700, -250, 1024) = 1, '2.8.2: the prone key at +17');
  Recs[1, CTL + 17] := 0;
  Recs[1, CTL + 18] := 1;
  Check(SpriteCheck(1, 1, 3, 30, 0, 12, 2, 700, -250, 2048) = 1, '2.8.2: the flag throw key at +18');
  Recs[1, CTL + 18] := 0;
  Recs[1, CTL + 16] := 7;
  Check(SpriteCheck(1, 1, 3, 30, 0, 12, 2, 700, -250, 0) = 1, '2.8.2: the byte at +16 is no key');
  Recs[1, CTL + 16] := 0;

  { the ammunition of all of them in one call }
  WeaponsDefault(False);
  AmmoConfig(1, 1, 1, 0, 1, 4, 2, 4, 45);
  AmmoRespawn(1, 100);
  AmmoRespawn(2, 100);
  AmmoRespawn(3, 100);
  { the script has seen soldier 1's AK and soldier 3's MP5, not soldier 2's change yet }
  V := 0;
  AmmoObserve(1, 100, 3, 30, 0, 12, AMF_HUMAN, 500, 300, V);
  AmmoLastW(1, 3);
  AmmoObserve(3, 100, 2, 20, 0, 12, AMF_HUMAN, 100, 100, V);
  AmmoLastW(3, 2);
  AmmoLastW(2, 1);
  n := AmmoPass(101, 7, 7, 0, 0);
  SawFull := False;
  SawOther := False;
  for k := 0 to n - 1 do
  begin
    AmmoPassOp(k, ID, Act, V);
    if (ID = 2) and (Act = AMA_FULL) then
      SawFull := True
    else if Act = AMA_FULL then
      SawOther := True;
  end;
  Check(SawFull, 'soldier 2 changed his weapon: the script looks at him itself');
  Check(not SawOther, 'the others are followed in the library');
  Recs[3, 1] := 1;
  n := AmmoPass(102, 4, 4, 0, 0);
  Check(n = 0, 'a dead soldier: nothing to do (' + IntToStr(n) + ')');
  Recs[3, 1] := 0;
  SpriteMemOff('test');
  n := AmmoPass(103, 1, 1, 0, 0);
  AmmoPassOp(0, ID, Act, V);
  Check((n = 1) and (ID = 1) and (Act = AMA_FULL), 'the reading off: every soldier is the script''s');

  for i := 1 to 4 do
    Obj[i].Free;
  WriteLn('test_sprite: ', Passed, ' passed, ', Failed, ' failed');
  if Failed > 0 then
    Halt(1);
end.
