program test_things;

{ [Looting] KeepWeapons on a table of this program: the signatures against the bytes of CreateThing and
  ServerThingMustSnapshot as they stand in the Windows and the Linux server, the layout read from them, the check of the
  table against what ScriptCore says, the weapons that are refreshed (a write of TimeOut and the resend), the ones that
  are not (taken, held, a time out of range, lying there before the keeper was armed, over the cap), the other way (made
  again shortly before the end) and the pause. The resend is a procedure of this program. }

{$mode objfpc}{$H+}

uses
  SysUtils, be_things;

{$I test_things_fixtures.inc}

const
  { a fake record: Active, Style, Num, Owner at 0..3, HoldingSprite at 12, TimeOut at 20, the skeleton at 40, its
    Pos[1] at 600 }
  REC = 1000;
  STYLE_AK = 7;
  STYLE_KIT = 16;

var
  Fails: LongInt = 0;
  Checks: LongInt = 0;
  Mem: PByte;
  Lay: TThLayout;
  Resent: LongInt = 0;
  ResentLast: LongInt = 0;

procedure Check(Ok: Boolean; const What: AnsiString);
begin
  Inc(Checks);
  if not Ok then
  begin
    Inc(Fails);
    WriteLn('FAIL: ', What);
  end;
end;

procedure FakeSnap(I: Byte); register;
begin
  Inc(Resent);
  ResentLast := I;
end;

function Rc(I: LongInt): PByte;
begin
  Result := PByte(PtrUInt(Mem) + PtrUInt(I * REC));
end;

procedure Put(I, Active, Style, Hold, TimeOut: LongInt; X, Y: Single);
begin
  Rc(I)[0] := Active;
  Rc(I)[1] := Style;
  Rc(I)[2] := I;
  Rc(I)[12] := Hold;
  PLongInt(PtrUInt(Rc(I)) + 20)^ := TimeOut;
  PSingle(PtrUInt(Rc(I)) + 600)^ := X;
  PSingle(PtrUInt(Rc(I)) + 604)^ := Y;
end;

function TimeOutOf(I: LongInt): LongInt;
begin
  Result := PLongInt(PtrUInt(Rc(I)) + 20)^;
end;

{ the script's look at all 90 slots, as the table has them now }
procedure Look;
var
  I: LongInt;
begin
  for I := 1 to TH_N do
    ThingsSeen(I, Rc(I)[0], Rc(I)[1], PSingle(PtrUInt(Rc(I)) + 600)^, PSingle(PtrUInt(Rc(I)) + 604)^);
end;

procedure Fresh(Method, MaxKept: LongInt);
begin
  FillChar(Mem^, (TH_N + 1) * REC, 0);
  ThingsTestUse(Lay, @FakeSnap);
  ThingsConfig(Method, MaxKept);
  Resent := 0;
  ResentLast := 0;
end;

var
  Buf: array[0..2047] of Byte;
  L, L2: TThLayout;
  k, n, m, Hits: LongInt;
  Bad: array[0..116] of Byte;

begin
  { 1. the signatures: both servers' bytes match, and only at their place }
  Check(ThingsSigMatches(@InitWIN[0], TH_INIT_SIG), 'the Windows CreateThing matches the signature');
  Check(ThingsSigMatches(@InitLIN[0], TH_INIT_SIG), 'the Linux CreateThing matches the signature');
  Check(ThingsSigMatches(@SnapWIN[0], TH_SNAP_SIG), 'the Windows resend matches its signature');
  Check(ThingsSigMatches(@SnapLIN[0], TH_SNAP_SIG), 'the Linux resend matches its signature');
  Check(Length(TH_SNAP_SIG) = TH_SNAP_LEN * 3 - 1, 'the resend signature is TH_SNAP_LEN bytes');
  Check(Length(TH_INIT_SIG) = TH_INIT_LEN * 3 - 1, 'the CreateThing signature is TH_INIT_LEN bytes');
  Check(not ThingsSigMatches(@SnapWIN[0], TH_INIT_SIG), 'the resend is not CreateThing');
  FillChar(Buf, SizeOf(Buf), $90);
  Move(InitLIN[0], Buf[700], SizeOf(InitLIN));
  Hits := 0;
  for k := 0 to 2047 - TH_INIT_LEN do
    if ThingsSigMatches(@Buf[k], TH_INIT_SIG) then
    begin
      Inc(Hits);
      n := k;
    end;
  Check((Hits = 1) and (n = 700), 'in a buffer the signature is found once, at its place');

  { 2. the layout read from the bytes }
  Check(ThingsParseInit(@InitWIN[0], L), 'the Windows layout is read');
  Check((L.Base = $89C51C) and (L.Size = 30004) and (L.OffStyle = 1) and (L.OffHold = 12) and (L.OffOwner = 3) and
    (L.OffTime = 20) and (L.OffSkel = 40) and (L.OffPos = 600), 'Windows: base, record 30004, TimeOut at 20, Pos[1] at 600');
  Check(ThingsParseInit(@InitLIN[0], L2), 'the Linux layout is read');
  Check((L2.Base = $84D733C) and (L2.Size = 30004) and (L2.OffTime = 20) and (L2.OffHold = 12) and (L2.OffPos = 600),
    'Linux: the same record at another base');
  Check(ThingsParseSnap(@SnapWIN[0], L), 'the Windows resend agrees with the table (record size, Style of record 0)');
  Check(ThingsParseSnap(@SnapLIN[0], L2), 'the Linux resend agrees with the table');
  Check(not ThingsParseSnap(@SnapLIN[0], L), 'the Linux resend does not agree with the Windows table');
  Move(InitWIN[0], Bad, SizeOf(Bad));
  Bad[36] := $35;
  Check(not ThingsParseInit(@Bad[0], L2), 'a different record size in one store: refused');
  Move(InitWIN[0], Bad, SizeOf(Bad));
  Bad[29] := $20;
  Check(not ThingsParseInit(@Bad[0], L2), 'Style not right after Active: refused');
  Move(InitWIN[0], Bad, SizeOf(Bad));
  Bad[91] := $FF;
  Bad[92] := $FF;
  Check(not ThingsParseInit(@Bad[0], L2), 'TimeOut far from the start: refused');
  Check(ThingsWeaponStyle(4) and ThingsWeaponStyle(14) and ThingsWeaponStyle(24) and ThingsWeaponStyle(26), 'the guns, knife, chainsaw, LAW run out');
  Check(not (ThingsWeaponStyle(1) or ThingsWeaponStyle(15) or ThingsWeaponStyle(16) or ThingsWeaponStyle(27) or ThingsWeaponStyle(0)),
    'flags, the bow, kits and stationary guns are not weapons');

  { a table of this program laid out like the server's }
  GetMem(Mem, (TH_N + 1) * REC);
  FillChar(Lay, SizeOf(Lay), 0);
  Lay.Found := True;
  Lay.Base := PtrUInt(Mem);
  Lay.Size := REC;
  Lay.OffStyle := 1;
  Lay.OffHold := 12;
  Lay.OffOwner := 3;
  Lay.OffTime := 20;
  Lay.OffSkel := 40;
  Lay.OffPos := 600;

  { 3. the check against ScriptCore }
  Fresh(0, 50);
  Check(ThingsState = 1, 'a table, nothing to check it against yet: waiting');
  Look;
  Check(ThingsState = 1, 'all slots inactive and agreeing: still waiting for an object');
  Check(ThingsMethodNow = 0, 'auto: nothing is kept before the table is checked');
  ThingsPass(100, 1);
  Put(3, 1, STYLE_AK, 0, 1200, 100.5, 200.25);
  Check(ThingsSeen(3, 1, STYLE_AK, 100.5, 200.25) = 1, 'an object ScriptCore agrees on');
  Check(ThingsState = 2, 'ready after one object agreed (Active, Style, X, Y)');
  Check(ThingsMethodNow = 1, 'auto: the bridge');
  Check(ThingsSeen(4, 1, STYLE_AK, 5, 5) = 0, 'slot 4 is inactive in the table, ScriptCore says active: refused');
  Check(ThingsState = 3, 'refused');
  Check(ThingsMethodNow = 2, 'auto: the table is refused - made again instead');
  Check(ThingsKeep = 0, 'a refused table is never written');
  ThingsConfig(1, 50);
  Check(ThingsMethodNow = 0, 'bridge only: refused - nothing');
  ThingsConfig(2, 50);
  Check(ThingsMethodNow = 2, 'recreate only');

  Fresh(0, 50);
  Put(3, 1, STYLE_AK, 0, 1200, 100.5, 200.25);
  Check(ThingsSeen(3, 1, STYLE_KIT, 100.5, 200.25) = 0, 'the style differs: refused');
  Fresh(0, 50);
  Put(3, 1, STYLE_AK, 0, 1200, 100.5, 200.25);
  Check(ThingsSeen(3, 1, STYLE_AK, 100.5, 201) = 0, 'the position differs: refused');
  Fresh(0, 50);
  Put(3, 1, STYLE_AK, 0, 1200, 100.5, 200.25);
  Check(ThingsSeen(3, 0, 0, 0, 0) = 0, 'ScriptCore says inactive, the table active: refused');
  Fresh(0, 50);
  Rc(7)[0] := 5;
  Check(ThingsSeen(7, 0, 0, 0, 0) = 0, 'an Active byte that is no boolean: refused');
  Fresh(0, 50);
  ThingsTestUse(Lay, nil);
  Put(3, 1, STYLE_AK, 0, 1200, 1, 2);
  Look;
  Check(ThingsState = 4, 'no resend found: not usable');
  Check(ThingsMethodNow = 2, 'auto: made again instead');

  { 4. the bridge: what is refreshed }
  Fresh(0, 50);
  ThingsPass(100, 1);
  Put(5, 1, STYLE_AK, 0, 1200, 10, 20);
  Look;
  Check(ThingsState = 2, 'ready');
  ThingsMade(6, STYLE_AK + 1, 101);
  Put(6, 1, STYLE_AK + 1, 0, 1200, 30, 40);
  ThingsPass(130, 1);
  Look;
  Check(ThingsKept = 1, 'the weapon lying before the pass is not kept (not dropped while armed), the other one is');
  Check(ThingsKeep = 0, 'TimeOut 1200: nothing to do');
  { 400 ticks after the drop its time out is 800 }
  ThingsPass(501, 1);
  PLongInt(PtrUInt(Rc(6)) + 20)^ := 800;
  Check(ThingsKeep = 1, 'TimeOut 800: refreshed');
  Check(TimeOutOf(6) = TH_REFRESH_TO, 'TimeOut written ' + IntToStr(TimeOutOf(6)));
  Check(TH_REFRESH_TO < 1200 - 30, 'below the game''s pickup delay: a soldier can take it at once');
  Check((Resent = 1) and (ResentLast = 6), 'and sent to the clients again');
  PLongInt(PtrUInt(Rc(5)) + 20)^ := 500;
  Check(ThingsKeep = 0, 'the weapon that lay there before the keeper was armed is left to run out');
  Check(TimeOutOf(5) = 500, 'its TimeOut untouched');
  { taken: another object in the slot }
  PLongInt(PtrUInt(Rc(6)) + 20)^ := 500;
  Rc(6)[1] := STYLE_KIT;
  Look;
  Check(ThingsKeep = 0, 'a kit in the slot now: nothing written');
  Check(TimeOutOf(6) = 500, 'kit TimeOut untouched');
  Rc(6)[0] := 0;
  Look;
  Check(ThingsKept = 0, 'taken: not tracked any more');
  { held, odd times }
  ThingsMade(8, STYLE_AK, 140);
  Put(8, 1, STYLE_AK, 3, 500, 1, 1);
  ThingsMade(9, STYLE_AK, 140);
  Put(9, 1, STYLE_AK, 0, 5000, 1, 1);
  ThingsMade(10, STYLE_AK, 140);
  Put(10, 1, STYLE_AK, 0, 0, 1, 1);
  ThingsPass(150, 1);
  Look;
  Check(ThingsKept = 3, 'three new weapons tracked');
  Check(ThingsKeep = 0, 'held by a soldier, a time out above 1200, a time out of 0: nothing written');
  Check((TimeOutOf(8) = 500) and (TimeOutOf(9) = 5000) and (TimeOutOf(10) = 0), 'their times untouched');
  Rc(8)[12] := 0;
  ThingsPass(840, 1);
  Check(ThingsKeep = 1, 'not held any more: refreshed (700 ticks after the drop, 500 left)');

  { 5. at most MaxKept; the oldest above it run out }
  Fresh(0, 2);
  ThingsPass(200, 1);
  Put(1, 1, 0 + 12, 0, 600, 1, 1);
  Look;
  Check(ThingsState = 2, 'ready (an object agrees)');
  Rc(1)[0] := 0;
  for k := 0 to 3 do
  begin
    ThingsMade(11 + k, STYLE_AK, 210 + k * 10);
    Put(11 + k, 1, STYLE_AK, 0, 600, 5 + k, 5);
  end;
  ThingsPass(810, 1);
  Look;
  Check(ThingsKept = 4, 'four weapons tracked');
  Check(ThingsKeep = 2, 'only two of them are refreshed (the newest)');
  Check((TimeOutOf(11) = 600) and (TimeOutOf(12) = 600) and (TimeOutOf(13) = TH_REFRESH_TO) and (TimeOutOf(14) = TH_REFRESH_TO),
    'the oldest two are left to run out');
  Check((ThingsKept = 2) and (ThingsCapped = 2), 'two kept, two over the cap');
  Rc(14)[0] := 0;
  Look;
  PLongInt(PtrUInt(Rc(11)) + 20)^ := 550;
  Check(ThingsKeep = 1, 'one taken: the oldest of three is still over the cap, the next one (600) is refreshed');
  Check(TimeOutOf(11) = 550, 'and the oldest is left alone');
  Rc(13)[0] := 0;
  Look;
  PLongInt(PtrUInt(Rc(12)) + 20)^ := 560;
  Check(ThingsKeep = 2, 'another taken: two left, both inside the cap (' + IntToStr(ThingsKept) + ' kept)');

  { 6. the keeper is let go: nothing on the ground is kept }
  Fresh(0, 50);
  ThingsPass(300, 1);
  Put(2, 1, 14, 0, 1200, 1, 1);
  Look;
  ThingsMade(20, STYLE_AK, 310);
  Put(20, 1, STYLE_AK, 0, 700, 7, 7);
  ThingsPass(330, 1);
  Look;
  Check(ThingsKept = 1, 'a weapon kept');
  ThingsPass(400, 0);
  Check(ThingsKept = 0, 'let go (the round ended)');
  Check(ThingsKeep = 0, 'and nothing is refreshed');
  PLongInt(PtrUInt(Rc(20)) + 20)^ := 400;
  Look;
  Check(ThingsKeep = 0, 'not even when it is seen again');
  ThingsMade(21, STYLE_AK, 450);
  Put(21, 1, STYLE_AK, 0, 700, 8, 8);
  ThingsPass(460, 1);
  ThingsMade(22, STYLE_AK, 461);
  Put(22, 1, STYLE_AK, 0, 700, 9, 9);
  Look;
  Check(ThingsKept = 1, 'the next round: a weapon from before it is let go, one dropped in it is kept');
  ThingsPass(961, 1);
  Check(ThingsKeep = 1, 'and refreshed');
  Check(TimeOutOf(22) = TH_REFRESH_TO, 'the one dropped in the new round');
  Check(TimeOutOf(20) = 400, 'the old one left alone');
  ThingsMap;
  Check(ThingsKept = 0, 'a new map: nothing tracked');

  { 6b. the first write into a weapon whose drop the hook told checks that the field counts down like a TimeOut }
  Fresh(0, 50);
  ThingsPass(100, 1);
  Put(1, 1, 14, 0, 1200, 1, 1);
  Look;
  ThingsMade(2, STYLE_AK, 110);
  Put(2, 1, STYLE_AK, 0, 1200, 2, 2);
  ThingsPass(140, 1);
  Look;
  ThingsPass(510, 1);
  PLongInt(PtrUInt(Rc(2)) + 20)^ := 100;
  Check(ThingsKeep = 0, 'a time out of 100 400 ticks after the drop (800 expected): not the field - refused');
  Check((ThingsState = 3) and (TimeOutOf(2) = 100), 'refused, and nothing written');
  Check(Pos('time out', ThingsInfo) > 0, 'the report says why');
  Fresh(0, 50);
  ThingsPass(100, 1);
  Put(1, 1, 14, 0, 1200, 1, 1);
  Look;
  { no hook: the tick of the drop is not known, the time out is believed }
  Put(2, 1, STYLE_AK, 0, 300, 2, 2);
  ThingsPass(140, 1);
  Look;
  Check(ThingsKeep = 1, 'without the drop''s tick the time out is taken as it is');

  { 7. made again (no bridge) }
  Fresh(2, 50);
  ThingsPass(1000, 1);
  ThingsMade(30, STYLE_AK, 1001);
  Put(30, 1, STYLE_AK, 0, 1200, 50, 60);
  ThingsPass(1030, 1);
  Look;
  Check(ThingsDue(1) = 0, 'a weapon 30 ticks old is not due');
  ThingsPass(1500, 1);
  ThingsMade(31, STYLE_AK, 1501);
  Put(31, 1, STYLE_AK, 0, 1200, 70, 80);
  ThingsPass(1530, 1);
  Look;
  ThingsPass(1001 + TH_RENEW_AGE - 1, 1);
  Check(ThingsDue(1) = 0, 'not one tick before');
  ThingsPass(1001 + TH_RENEW_AGE, 1);
  Check(ThingsDue(1) = 30, 'the first weapon is due after TH_RENEW_AGE');
  Check(ThingsDue(31) = 0, 'the other (made 500 ticks later) is not');
  { the script kills it and makes the same weapon again; the game gives the new object the lowest free slot, here the same }
  ThingsMade(30, STYLE_AK, 1001 + TH_RENEW_AGE);
  ThingsRenewed(30, 30);
  Check(ThingsKept = 2, 'made again in the same slot: still two weapons kept');
  Check(ThingsDue(1) = 0, 'and its age begins again');
  ThingsPass(1501 + TH_RENEW_AGE, 1);
  Check(ThingsDue(1) = 31, 'the second weapon is due now');
  { another slot }
  ThingsMade(25, STYLE_AK, 1502 + TH_RENEW_AGE);
  ThingsRenewed(31, 25);
  Check((ThingsKept = 2) and (ThingsDue(1) = 0), 'made again in another slot: the entry moved');
  Rc(30)[0] := 0;
  Rc(31)[0] := 0;
  Put(25, 1, STYLE_AK, 0, 1200, 70, 80);
  Look;
  Check(ThingsKept = 1, 'the old slots are empty, the new one tracked');
  ThingsPass(1501 + 2 * TH_RENEW_AGE, 1);
  Check(ThingsDue(1) = 25, 'due again later');
  Check(ThingsKeep = 0, 'the bridge writes nothing in this method');
  { the pause: the game stood still for 600 ticks }
  ThingsShift(600);
  Check(ThingsDue(1) = 0, 'after a pause of 600 ticks it is not due yet');
  { the cap in this method too }
  Fresh(2, 1);
  ThingsPass(2000, 1);
  for k := 0 to 2 do
  begin
    ThingsMade(40 + k, STYLE_AK, 2001 + k);
    Put(40 + k, 1, STYLE_AK, 0, 1200, 1 + k, 1);
  end;
  ThingsPass(2030, 1);
  Look;
  ThingsPass(2003 + TH_RENEW_AGE + 5, 1);
  Check(ThingsDue(1) = 42, 'MaxKept 1: only the newest is made again');
  Check(ThingsDue(43) = 0, 'and nothing after it');

  { 8. the report }
  Check(Pos('method in use', ThingsInfo) > 0, 'the report says the method');
  WriteLn(ThingsInfo);

  FreeMem(Mem);
  WriteLn(Checks, ' checks, ', Fails, ' failed');
  if Fails > 0 then
    Halt(1);
end.
