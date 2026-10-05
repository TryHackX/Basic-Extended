program test_bridge;

{ The bullet memory bridge on a table of this program, the way it finds the server's: the signature of
  2.8.2's GetOwnerWeaponId (the bullet table read with 88 bytes a record) lies in a constant here and leads
  AutoDetectBridge to MockMem, laid out as the server's TBullet around its weapon byte; then the safety
  checks before a write. Windows: the bridge searches every section of the program for the signature. }

{$mode objfpc}{$H+}

uses
  SysUtils, be_bridge;

const
  REC = 88;

var
  { the records of bullets 0..64; the weapon byte of bullet B at MockMem[B * REC + 5] }
  MockMem: array[0..65 * REC + 15] of Byte;

const
  { movzx eax, byte [eax+8]; imul eax, eax, 88; movzx eax, byte [eax + the weapon byte of bullet 0] }
  Sig: packed record
    Code: array[0..9] of Byte;
    Base: Pointer;
  end = (Code: ($0F, $B6, $40, $08, $6B, $C0, REC, $0F, $B6, $80); Base: @MockMem[5]);

var
  Failed: LongInt = 0;

procedure Check(Ok: Boolean; const What: AnsiString);
begin
  if Ok then
    WriteLn('ok   ', What)
  else
  begin
    WriteLn('FAIL ', What);
    Inc(Failed);
  end;
end;

{ a bullet as 2.8.2 lays it out: Active, Style, Num (2 bytes), Owner, the weapon, TimeOut at +7 and HitMultiply
  at +11 from the weapon byte }
procedure Put(B, Active, Style, Owner, W, TimeOut: LongInt; HitM: Single);
var
  a: LongInt;
begin
  a := B * REC + 5;
  MockMem[a - 5] := Active;
  MockMem[a - 4] := Style;
  PSmallInt(@MockMem[a - 3])^ := B;
  MockMem[a - 1] := Owner;
  MockMem[a] := W;
  PSmallInt(@MockMem[a + 7])^ := TimeOut;
  PSingle(@MockMem[a + 11])^ := HitM;
end;

function Weapon(B: LongInt): LongInt;
begin
  Result := MockMem[B * REC + 5];
end;

var
  Res, Active, Owner, W, Style, TimeOut: LongInt;
  Found: Boolean;
begin
  FillChar(MockMem, SizeOf(MockMem), 0);
  Check(Sig.Base = @MockMem[5], 'the signature points at the table');
  Put(2, 1, 1, 1, 11, 100, 11.25);
  Put(5, 1, 2, 1, 22, 200, 22.50);
  Put(9, 1, 3, 2, 33, 300, 33.75);

  Found := BridgeReady;
  Check(Found, 'the table found by the signature: ' + BridgeInfo);
  Check(Pos('record 88 bytes', BridgeInfo) > 0, 'a record of 88 bytes');

  Res := BridgeSetWeapon(5, 2, 8, 22.50);
  Check(Res = 1, 'the weapon of bullet 5 set to 8');
  Check(Weapon(5) = 8, 'bullet 5''s weapon byte is 8');
  Check((Weapon(2) = 11) and (Weapon(9) = 33), 'the other bullets untouched');

  { the safety checks: nothing is written into a record that is not the bullet the script means }
  Res := BridgeSetWeapon(5, 2, 10, 999.0);
  Check(Res = -1, 'another HitMultiply is refused');
  Check(Weapon(5) = 8, 'bullet 5 unchanged after the refusal');
  Res := BridgeSetWeapon(5, 99, 10, 22.50);
  Check(Res = -1, 'another style is refused');
  PSmallInt(@MockMem[9 * REC + 2])^ := 7;
  Res := BridgeSetWeapon(9, 3, 10, 33.75);
  Check(Res = -1, 'a record with another number is refused');
  PSmallInt(@MockMem[9 * REC + 2])^ := 9;
  MockMem[2 * REC] := 0;
  Res := BridgeSetWeapon(2, 1, 10, 11.25);
  Check(Res = -1, 'a bullet no longer flying is refused');
  Check(Weapon(2) = 11, 'bullet 2 unchanged');
  MockMem[2 * REC] := 1;
  Res := BridgeSetWeapon(0, 1, 1, 11.25);
  Check(Res = 0, 'bullet 0 is no bullet');
  Res := BridgeSetWeapon(256, 1, 1, 11.25);
  Check(Res = 0, 'bullet 256 is no bullet');

  { reading and taking out a bullet }
  Check(BridgeBulletStyle(9) = 3, 'the style of bullet 9');
  Check(BridgeBulletInfo(9, Active, Owner, W, Style, TimeOut) and (Active = 1) and (Owner = 2) and (W = 33) and
    (Style = 3) and (TimeOut = 300), 'bullet 9 read: its owner, weapon, style and time out');
  Check(not BridgeBulletKill(9, 1, 3), 'another owner''s bullet is not taken out');
  Check(BridgeBulletKill(9, 2, 3), 'bullet 9 taken out');
  Check(MockMem[9 * REC] = 0, 'its Active flag is off');
  Check(Pos('weapons set 1, refused 4', BridgeInfo) > 0, 'counted: ' + BridgeInfo);

  if Failed > 0 then
  begin
    WriteLn(Failed, ' tests FAILED');
    Halt(1);
  end;
  WriteLn('test_bridge: all passed');
end.
