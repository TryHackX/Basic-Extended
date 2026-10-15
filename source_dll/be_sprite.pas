unit be_sprite;

{$mode objfpc}{$H+}
{$Q-}{$IFNDEF BE_CHECKS}{$R-}{$ENDIF}

{ The server's soldiers seen from the library. ScriptCore hands a player object to a library routine as
  the object itself (TScriptActivePlayer); right after its class pointer lies FSpritePtr = @Sprite[ID],
  the server's record of that soldier. In the record lies the skeleton: the points the server sets every
  tick from the animations (standing, crouching, lying, rolling) and hits the bullets against. Its
  place in the record is found once: 20 points in a row, all around the soldier.

  Point 9 is the neck; point 12 lies a tenth of a pixel from it towards the top of the head (the server
  turns it with the aim), and the head's picture (6 x 6 px) is drawn from the neck that way: its middle,
  3 px out, is where the eyes are. }

interface

{ the soldier in slot ID: Obj = the script's player object, X, Y = his position (Player.X, Player.Y -
  the particle the skeleton hangs on); 1 = known, 0 = not (yet) }
function SpriteBind(ID: LongInt; Obj: Pointer; X, Y: Single): LongInt;
{ a point of his skeleton (1 .. 25) / his eyes, as the server has them now }
function SpritePoint(ID, K: LongInt; out X, Y: Single): Boolean;
function SpriteEyes(ID: LongInt; out X, Y: Single): Boolean;
{ the record of slot ID is known (bound, or worked out from two bound ones) }
function SpriteKnown(ID: LongInt): Boolean;
{ how he stands as the server has it (the record's Position: 1 standing, 2 crouching, 4 lying); 0 = not
  known (the record not bound, or not laid out as 2.8.2's: its anchors are checked every time) }
function SpriteStance(ID: LongInt): LongInt;
function SpriteInfo: AnsiString;
{ 4.1: the server's ping compensation of a hit on soldier V by bullet B (2.8.2's GetSpriteCollisionPoint): a
  human's body parts are tested where he stood the bullet owner's ping ago (OldSpritePos[V, OwnerPingTick], at
  most 124 ticks back), a bot's - and a flame's first ticks - where he stands. DX, DY = that place less where he
  stands now (0, 0 when nothing is moved); False = not known (the server's code was not found) }
function SpritePingShift(V, B: LongInt; out DX, DY: Single): Boolean;
function SpritePingInfo: AnsiString;

{ ---- round 26: the weapons, the keys and the aim of every soldier read from his record ----
  The places are found by matching what the script reads through the properties on two soldiers at once (the
  weapon in the hands and the second one: number and rounds, three gun records in a row with the grenades in the
  third; the aim pair after 12 key bytes of 0 or 1), checked again every second against the properties; one
  mismatch switches the reading off for good: until the server restarts (the library stays loaded, so a /recompile
  does not reset it; SpriteMemReset is only for the tests). }

{ a calibration sample of a bound soldier (the properties of this tick): 1 = the places are known now }
function SpriteCalibrate(ID, W, A, SW, SA, Gren, AimX, AimY: LongInt): LongInt;
{ the places are known and the reading is on }
function SpriteMemReady: Boolean;
{ the check of a soldier against the properties of this tick (Keys: bit k = his key k in the record's order - left,
  right, up, down, fire, jetpack, grenade, change weapon, throw weapon, reload, prone, flag throw): 1 = the same,
  0 = a mismatch (the reading is switched off), -1 = not checked (not ready, not bound) }
function SpriteCheck(ID, Alive, W, A, SW, SA, Gren, AimX, AimY, Keys: LongInt): LongInt;
{ the soldier as his record has it now (False: not readable - the script reads the properties) }
function SpriteRead(ID: LongInt; out Alive: Boolean; out W, A: LongInt; out Fire, Reload: Boolean): Boolean;
{ 4.2: his change-weapon key or throw-weapon key is held (as his last report has it); False also when not readable }
function SpriteSwitchKeys(ID: LongInt): Boolean;
procedure SpriteMemOff(const Reason: AnsiString);
procedure SpriteMemReset;
function SpriteMemInfo: AnsiString;

implementation

uses
  SysUtils, be_bridge, be_hook;

const
  MAX_ID = 32;
  { the points that must lie around the soldier, and how far }
  RUN = 20;
  NEAR_PX = 60;
  { where the record may hold the skeleton (the record is some tens of kilobytes) }
  SCAN_MAX = 131072;
  EYES_OUT = 3;
  { the class of the script's player objects (TScriptActivePlayer in the server's source) }
  CLASS_WANT = 'ActivePlayer';

const
  { 4.1: 2.8.2's GetSpriteCollisionPoint, alike in the Windows and the Linux server: the flame case (SpriteParts.Pos
    when TimeOut > 30), the bot test (Sprite[i].Player.ControlMethod = BOT), the ping compensation (OldSpritePos[i,
    OwnerPingTick], [i, 124] beyond); the three tables' addresses are the wild bytes }
  COLW = $100;
  SIG_COLPOINT: array[0..76] of Word = (
    $53, $56, $57, $89, $CB, $80, $78, $01, $05, $75, COLW, $66, $81, $78, $0C, COLW, COLW, $7E, COLW, $89,
    $DF, $8D, $34, $D5, COLW, COLW, COLW, COLW, $B9, $08, $00, $00, $00, $F3, $A4, $EB, COLW, $69, $CA, $18,
    $C2, $00, $00, $80, $B9, COLW, COLW, COLW, COLW, $02, $74, COLW, $80, $78, $21, $7D, $73, COLW, $69, $CA,
    $F0, $03, $00, $00, $0F, $B6, $40, $21, $89, $DF, $8D, $B4, $C1, COLW, COLW, COLW, COLW);
  COL_POS_AT = 24;
  COL_CTL_AT = 45;
  COL_OLD_AT = 73;
  SPRITE_STEP_282 = $C218;
  OLDPOS_ROW = $3F0;
  OLDPOS_KEPT = 125;
  CONTROL_BOT = 2;
  STYLE_FLAME = 5;
  FLAME_FRESH = 30;

var
  PingTried: Boolean = False;
  PingPos: PtrUInt = 0;
  PingCtl: PtrUInt = 0;
  PingOld: PtrUInt = 0;
  PingWhy: AnsiString = 'not looked for yet';
  PingShifts: LongInt = 0;

var
  Addr: array[1..MAX_ID] of PtrUInt;
  { where FSpritePtr lies in the player object (-1 = not found yet), where the skeleton's points lie in
    the soldier's record (-1 = not found yet, -2 = given up) }
  FieldOff: PtrInt = -1;
  PosOff: PtrInt = -1;
  Tries: LongInt = 0;
  Bound: LongInt = 0;
  { the step of the server's table of soldiers (Sprite: array[1..] of TSprite), once two are bound }
  Stride: PtrInt = 0;
  Why: AnsiString = 'not used yet';

function Finite(Bits: LongWord): Boolean;
begin
  Result := (Bits and $7F800000) <> $7F800000;
end;

{ the 20 points from a lie around X, Y (within NEAR_PX) and are not all the same point }
function Around(a: PtrUInt; X, Y: Single): Boolean;
var
  k: LongInt;
  BX, BY: LongWord;
  PX, PY, Spread: Single;
begin
  Result := False;
  Spread := 0;
  for k := 0 to RUN - 1 do
  begin
    BX := PLongWord(a + PtrUInt(k * 8))^;
    BY := PLongWord(a + PtrUInt(k * 8 + 4))^;
    if not (Finite(BX) and Finite(BY)) then
      Exit;
    PX := PSingle(@BX)^;
    PY := PSingle(@BY)^;
    if (PX < X - NEAR_PX) or (PX > X + NEAR_PX) or (PY < Y - NEAR_PX) or (PY > Y + NEAR_PX) then
      Exit;
    Spread := Spread + Abs(PX - X) + Abs(PY - Y);
  end;
  Result := Spread > RUN;
end;

{ the skeleton in the record at a, for the soldier at X, Y: the first run of points around him (the
  points come before their copies of the last tick in the particle system) }
function FindSkeleton(a: PtrUInt; X, Y: Single): PtrInt;
var
  d: PtrInt;
begin
  Result := -1;
  d := 0;
  while d <= SCAN_MAX do
  begin
    if not ExeData(a + PtrUInt(d), RUN * 8) then
      Exit;
    if Around(a + PtrUInt(d), X, Y) then
    begin
      Result := d;
      Exit;
    end;
    Inc(d, 4);
  end;
end;

function ClassNameIs(Obj: Pointer; const Want: AnsiString): Boolean;
var
  VMT, NameP: Pointer;
  S: PShortString;
begin
  Result := False;
  VMT := PPointer(Obj)^;
  if PtrUInt(VMT) <= $10000 then
    Exit;
  NameP := PPointer(PtrUInt(VMT) + 3 * SizeOf(Pointer))^;
  if PtrUInt(NameP) <= $10000 then
    Exit;
  S := PShortString(NameP);
  Result := Pos(Want, S^) > 0;
end;

{ two soldiers bound: the step between them, and from it every other slot (the table is one array) }
procedure FillSlots;
var
  i, j, k: LongInt;
  St: PtrInt;
  a: PtrUInt;
begin
  if Stride <> 0 then
    Exit;
  i := 0;
  j := 0;
  for k := 1 to MAX_ID do
    if Addr[k] <> 0 then
    begin
      if i = 0 then
        i := k
      else if j = 0 then
        j := k;
    end;
  if (i = 0) or (j = 0) then
    Exit;
  if (PtrInt(Addr[j]) - PtrInt(Addr[i])) mod (j - i) <> 0 then
    Exit;
  St := (PtrInt(Addr[j]) - PtrInt(Addr[i])) div (j - i);
  if St < PosOff + 25 * 8 then
    Exit;
  Stride := St;
  for k := 1 to MAX_ID do
    if Addr[k] = 0 then
    begin
      a := PtrUInt(PtrInt(Addr[i]) + (k - i) * St);
      if ExeData(a + PtrUInt(PosOff), 25 * 8) then
        Addr[k] := a;
    end;
end;

procedure FindPing;
var
  A: PtrUInt;
begin
  PingTried := True;
  A := FindCodeW(SIG_COLPOINT);
  if A = 0 then
  begin
    PingWhy := 'the server''s GetSpriteCollisionPoint was not found';
    Exit;
  end;
  PingPos := PLongWord(A + COL_POS_AT)^;
  PingCtl := PLongWord(A + COL_CTL_AT)^;
  PingOld := PLongWord(A + COL_OLD_AT)^;
  if not (ExeData(PingPos + 8, 8 * MAX_ID) and ExeData(PingCtl + SPRITE_STEP_282 * MAX_ID, 1) and
    ExeData(PingOld + OLDPOS_ROW, OLDPOS_ROW * MAX_ID)) then
  begin
    PingPos := 0;
    PingCtl := 0;
    PingOld := 0;
    PingWhy := 'its tables are not in the server''s data';
    Exit;
  end;
  PingWhy := 'ready';
end;

function Finite32(B: LongWord): Boolean;
begin
  Result := (B and $7F800000) <> $7F800000;
end;

function SpritePingShift(V, B: LongInt; out DX, DY: Single): Boolean;
var
  Active, Owner, W, Style, TimeOut, Ping: LongInt;
  O, P: PtrUInt;
  OX, OY, PX, PY: LongWord;
begin
  Result := False;
  DX := 0;
  DY := 0;
  try
    if (V < 1) or (V > MAX_ID) then
      Exit;
    if not PingTried then
      FindPing;
    if PingOld = 0 then
      Exit;
    { a flame in its first ticks is tested where he stands }
    if BridgeBulletInfo(B, Active, Owner, W, Style, TimeOut) then
      if (Style = STYLE_FLAME) and (TimeOut > FLAME_FRESH) then
      begin
        Result := True;
        Exit;
      end;
    { a bot where he stands }
    if PByte(PingCtl + PtrUInt(V) * SPRITE_STEP_282)^ = CONTROL_BOT then
    begin
      Result := True;
      Exit;
    end;
    Ping := BridgeBulletPingTick(B);
    if Ping < 0 then
      Exit;
    if Ping >= OLDPOS_KEPT then
      Ping := OLDPOS_KEPT - 1;
    O := PingOld + PtrUInt(V) * OLDPOS_ROW + PtrUInt(Ping) * 8;
    P := PingPos + PtrUInt(V) * 8;
    OX := PLongWord(O)^;
    OY := PLongWord(O + 4)^;
    PX := PLongWord(P)^;
    PY := PLongWord(P + 4)^;
    if not (Finite32(OX) and Finite32(OY) and Finite32(PX) and Finite32(PY)) then
      Exit;
    DX := PSingle(@OX)^ - PSingle(@PX)^;
    DY := PSingle(@OY)^ - PSingle(@PY)^;
    if (DX <> 0) or (DY <> 0) then
      Inc(PingShifts);
    Result := True;
  except
    Result := False;
  end;
end;

function SpritePingInfo: AnsiString;
begin
  if not PingTried then
    FindPing;
  Result := 'ping compensation ' + PingWhy;
  if PingOld <> 0 then
    Result := Result + ' (hits moved ' + IntToStr(PingShifts) + ')';
end;

function SpriteKnown(ID: LongInt): Boolean;
begin
  Result := (ID >= 1) and (ID <= MAX_ID) and (PosOff >= 0);
  if Result then
    Result := Addr[ID] <> 0;
end;

function SpriteBind(ID: LongInt; Obj: Pointer; X, Y: Single): LongInt;
var
  f: PtrInt;
  a: PtrUInt;
  d: PtrInt;
begin
  Result := 0;
  try
    if (ID < 1) or (ID > MAX_ID) then
      Exit;
    if Addr[ID] <> 0 then
      if PosOff >= 0 then
      begin
        Result := 1;
        Exit;
      end;
    if PosOff = -2 then
      Exit;
    if PtrUInt(Obj) <= $10000 then
      Exit;
    if not ClassNameIs(Obj, CLASS_WANT) then
    begin
      Why := 'the player object is not a TScriptActivePlayer';
      Exit;
    end;
    a := 0;
    if FieldOff >= 0 then
    begin
      a := PPtrUInt(PtrUInt(Obj) + PtrUInt(FieldOff))^;
      if not ExeData(a, 64) then
        a := 0;
    end
    else
      { the first field that points into the server's own data (FSpritePtr in the source) }
      for f := 1 to 8 do
      begin
        a := PPtrUInt(PtrUInt(Obj) + PtrUInt(f * SizeOf(Pointer)))^;
        if ExeData(a, 64) then
        begin
          if PosOff < 0 then
          begin
            d := FindSkeleton(a, X, Y);
            if d < 0 then
            begin
              a := 0;
              Continue;
            end;
            PosOff := d;
          end;
          FieldOff := f * SizeOf(Pointer);
          Break;
        end;
        a := 0;
      end;
    if a = 0 then
    begin
      Inc(Tries);
      Why := 'no soldier record found in the player object';
      if Tries >= 64 then
        PosOff := -2;
      Exit;
    end;
    if PosOff < 0 then
    begin
      d := FindSkeleton(a, X, Y);
      if d < 0 then
      begin
        Inc(Tries);
        Why := 'the skeleton was not found around the soldier';
        if Tries >= 64 then
          PosOff := -2;
        Exit;
      end;
      PosOff := d;
    end;
    if Addr[ID] = 0 then
      Inc(Bound);
    Addr[ID] := a;
    Why := 'ready';
    FillSlots;
    Result := 1;
  except
    Result := 0;
  end;
end;

function SpritePoint(ID, K: LongInt; out X, Y: Single): Boolean;
var
  a: PtrUInt;
  BX, BY: LongWord;
begin
  Result := False;
  X := 0;
  Y := 0;
  try
    if (ID < 1) or (ID > MAX_ID) or (K < 1) or (K > 25) then
      Exit;
    if (Addr[ID] = 0) or (PosOff < 0) then
      Exit;
    a := Addr[ID] + PtrUInt(PosOff) + PtrUInt((K - 1) * 8);
    if not ExeData(a, 8) then
      Exit;
    BX := PLongWord(a)^;
    BY := PLongWord(a + 4)^;
    if not (Finite(BX) and Finite(BY)) then
      Exit;
    X := PSingle(@BX)^;
    Y := PSingle(@BY)^;
    Result := True;
  except
    Result := False;
  end;
end;

function SpriteEyes(ID: LongInt; out X, Y: Single): Boolean;
var
  NX, NY, HX, HY, L: Single;
begin
  Result := False;
  X := 0;
  Y := 0;
  if not SpritePoint(ID, 9, NX, NY) then
    Exit;
  if not SpritePoint(ID, 12, HX, HY) then
    Exit;
  HX := HX - NX;
  HY := HY - NY;
  L := Sqrt(HX * HX + HY * HY);
  if L < 0.001 then
  begin
    HX := 0;
    HY := -1;
  end
  else
  begin
    HX := HX / L;
    HY := HY / L;
  end;
  X := NX + HX * EYES_OUT;
  Y := NY + HY * EYES_OUT;
  Result := True;
end;

{ 2.8.2's TSprite (read from the server's binary): Active +0 (1 while the slot is used), Num +4 (the slot),
  Position +94, the skeleton's VDamping +20860 (0.9945 as CreateSprite stores it) - the skeleton itself at
  +132 (its points at +692) }
const
  REC_ACTIVE = 0;
  REC_NUM = 4;
  REC_POSITION = 94;
  REC_VDAMP = 20860;
  VDAMP_BITS = $3F7E978D;

function SpriteStance(ID: LongInt): LongInt;
var
  a: PtrUInt;
  P: Byte;
begin
  Result := 0;
  try
    if (ID < 1) or (ID > MAX_ID) then
      Exit;
    if (Addr[ID] = 0) or (PosOff <> 692) then
      Exit;
    a := Addr[ID];
    if not ExeData(a, REC_VDAMP + 4) then
      Exit;
    if PByte(a + REC_ACTIVE)^ <> 1 then
      Exit;
    if PByte(a + REC_NUM)^ <> ID then
      Exit;
    if PLongWord(a + REC_VDAMP)^ <> VDAMP_BITS then
      Exit;
    P := PByte(a + REC_POSITION)^;
    if (P = 1) or (P = 2) or (P = 4) then
      Result := P;
  except
    Result := 0;
  end;
end;

function SpriteInfo: AnsiString;
begin
  if PosOff >= 0 then
  begin
    Result := 'soldiers: ' + IntToStr(Bound) + ' bound, skeleton at +' + IntToStr(PosOff) + ' of the record (object +' +
      IntToStr(FieldOff) + ')';
    if Stride > 0 then
      Result := Result + ', table step ' + IntToStr(Stride) + ' (every slot known)';
  end
  else if PosOff = -2 then
    Result := 'soldiers: given up (' + Why + ')'
  else
    Result := 'soldiers: ' + Why;
end;

{ ---------------- round 26: the record's weapons, keys and aim ---------------- }

const
  { where the gun records may lie: after the skeleton's points (they come after the particle system and the two
    animations in 2.8.2), up to the end of what a record can be }
  GUN_FROM = 4096;
  GUN_TO = 120000;
  GUN_STEP_MIN = 64;
  GUN_STEP_MAX = 160;
  MAX_CAND = 8;

var
  GunOff: PtrInt = -1;
  GunStep: PtrInt = 0;
  CtlOff: PtrInt = -1;
  { the control record's layout: where the aim pair and each of the 12 keys lie in it (left, right, up, down, fire,
    jetpack, grenade, change weapon, throw weapon, reload, prone, flag throw) }
  CtlLayout: LongInt = 0;
  CtlAim: LongInt = 12;
  CtlKey: array[0..11] of LongInt = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11);
  MemOn: Boolean = False;
  MemDead: Boolean = False;
  MemWhy: AnsiString = 'not calibrated yet';
  MemChecks: LongInt = 0;
  { the candidates of the first soldier sampled (gun, step, control); confirmed by a second soldier }
  CandN: LongInt = 0;
  CandG, CandS, CandC: array[0..MAX_CAND - 1] of PtrInt;
  CandID: LongInt = 0;

function Rd8(a: PtrUInt): LongInt;
begin
  Result := PByte(a)^;
end;

function Rd16(a: PtrUInt): LongInt;
begin
  Result := PSmallInt(a)^;
end;

{ the two layouts of the control record (right before the first gun, which is 4-aligned: 20 bytes before it):
  1 = 2.8.2's (Left, Right, Up, Down, then MouseAimX, MouseAimY, MouseDist, then Fire, Jetpack, ThrowNade,
  ChangeWeapon, ThrowWeapon, Reload at +10 .. +15, a byte of its own at +16, Prone at +17, FlagThrow at +18 - the
  server's code reads the two keys there: 13 and 6 places, +16 only 2), 2 = the source's of today (the 12 keys,
  then the aim) }
procedure SetLayout(L: LongInt);
var
  k: LongInt;
begin
  CtlLayout := L;
  if L = 1 then
  begin
    CtlAim := 4;
    for k := 0 to 3 do
      CtlKey[k] := k;
    for k := 4 to 9 do
      CtlKey[k] := k + 6;
    CtlKey[10] := 17;
    CtlKey[11] := 18;
  end
  else
  begin
    CtlAim := 12;
    for k := 0 to 11 do
      CtlKey[k] := k;
  end;
end;

{ the control record before the gun at g: the layout whose aim pair is the soldier's and whose keys are all 0 or 1
  (0 = none) }
function FindCtl(a: PtrUInt; g: PtrInt; AimX, AimY: LongInt): LongInt;
var
  c: PtrInt;
  L, k: LongInt;
  Ok: Boolean;
begin
  Result := 0;
  c := g - 20;
  for L := 1 to 2 do
  begin
    SetLayout(L);
    if (Rd16(a + PtrUInt(c + CtlAim)) = AimX) and (Rd16(a + PtrUInt(c + CtlAim + 2)) = AimY) then
    begin
      Ok := True;
      for k := 0 to 11 do
        if Rd8(a + PtrUInt(c + CtlKey[k])) > 1 then
          Ok := False;
      if Ok then
      begin
        Result := L;
        Exit;
      end;
    end;
  end;
end;

function SpriteCalibrate(ID, W, A, SW, SA, Gren, AimX, AimY: LongInt): LongInt;
var
  Rec: PtrUInt;
  d, s, c, Top: PtrInt;
  k, n: LongInt;
  G, S2, C2: array[0..MAX_CAND - 1] of PtrInt;
begin
  Result := 0;
  try
    if MemOn then
    begin
      Result := 1;
      Exit;
    end;
    if MemDead then
      Exit;
    if (ID < 1) or (ID > MAX_ID) or (Addr[ID] = 0) or (PosOff < 0) then
      Exit;
    { Rec sample that tells little: no weapon, the same weapon twice }
    if (W < 0) or (W > 16) or (SW < 0) or (SW > 16) or (W = SW) then
      Exit;
    if (A < 0) or (A > 255) or (SA < 0) or (SA > 255) or (Gren < 0) or (Gren > 255) then
      Exit;
    Rec := Addr[ID];
    Top := GUN_TO;
    while (Top > GUN_FROM) and not ExeData(Rec, Top + 2 * GUN_STEP_MAX + 4) do
      Dec(Top, 4096);
    if Top <= GUN_FROM then
    begin
      MemWhy := 'the soldier''s record is not readable that far';
      Exit;
    end;
    n := 0;
    d := GUN_FROM;
    while d <= Top do
    begin
      if (Rd8(Rec + PtrUInt(d + 2)) = W) and (Rd8(Rec + PtrUInt(d + 1)) = A) then
      begin
        s := GUN_STEP_MIN;
        while s <= GUN_STEP_MAX do
        begin
          if (Rd8(Rec + PtrUInt(d + s + 2)) = SW) and (Rd8(Rec + PtrUInt(d + s + 1)) = SA) and
            (Rd8(Rec + PtrUInt(d + 2 * s + 1)) = Gren) then
          begin
            c := FindCtl(Rec, d, AimX, AimY);
            if (c > 0) and (n < MAX_CAND) then
            begin
              G[n] := d;
              S2[n] := s;
              C2[n] := c;
              Inc(n);
            end;
          end;
          Inc(s, 4);
        end;
      end;
      Inc(d, 4);
    end;
    if n = 0 then
    begin
      MemWhy := 'no weapon records found in a soldier''s record';
      Exit;
    end;
    { the first soldier gives the candidates, another one keeps those that fit him too }
    if (CandN = 0) or (CandID = ID) then
    begin
      CandN := n;
      CandID := ID;
      for k := 0 to n - 1 do
      begin
        CandG[k] := G[k];
        CandS[k] := S2[k];
        CandC[k] := C2[k];
      end;
      MemWhy := 'one soldier sampled';
      Exit;
    end;
    for k := 0 to CandN - 1 do
      for d := 0 to n - 1 do
        if (CandG[k] = G[d]) and (CandS[k] = S2[d]) and (CandC[k] = C2[d]) then
        begin
          GunOff := G[d];
          GunStep := S2[d];
          CtlOff := G[d] - 20;
          SetLayout(C2[d]);
          MemOn := True;
          MemWhy := 'ready';
          Result := 1;
          Exit;
        end;
    { nothing in common: this soldier's candidates start again }
    CandN := n;
    CandID := ID;
    for k := 0 to n - 1 do
    begin
      CandG[k] := G[k];
      CandS[k] := S2[k];
      CandC[k] := C2[k];
    end;
  except
    Result := 0;
  end;
end;

function SpriteMemReady: Boolean;
begin
  Result := MemOn;
end;

procedure SpriteMemOff(const Reason: AnsiString);
begin
  MemOn := False;
  MemDead := True;
  MemWhy := 'switched off: ' + Reason;
end;

function MemAddr(ID: LongInt; out Rec: PtrUInt): Boolean;
begin
  Result := False;
  Rec := 0;
  if not MemOn then
    Exit;
  if (ID < 1) or (ID > MAX_ID) then
    Exit;
  Rec := Addr[ID];
  if Rec = 0 then
    Exit;
  Result := ExeData(Rec, GunOff + 2 * GunStep + 4);
end;

function SpriteRead(ID: LongInt; out Alive: Boolean; out W, A: LongInt; out Fire, Reload: Boolean): Boolean;
var
  Rec: PtrUInt;
begin
  Result := False;
  Alive := False;
  W := -1;
  A := 0;
  Fire := False;
  Reload := False;
  try
    if not MemAddr(ID, Rec) then
      Exit;
    { TSprite: Active +0, DeadMeat +1 (Player.Alive = Active and not DeadMeat) }
    Alive := (PByte(Rec)^ <> 0) and (PByte(Rec + 1)^ = 0);
    W := Rd8(Rec + PtrUInt(GunOff + 2));
    A := Rd8(Rec + PtrUInt(GunOff + 1));
    { TControl: Left, Right, Up, Down, Fire (+4), Jetpack, ThrowNade, ChangeWeapon, ThrowWeapon, Reload (+9) }
    Fire := Rd8(Rec + PtrUInt(CtlOff + CtlKey[4])) <> 0;
    Reload := Rd8(Rec + PtrUInt(CtlOff + CtlKey[9])) <> 0;
    Result := True;
  except
    Result := False;
  end;
end;

function SpriteSwitchKeys(ID: LongInt): Boolean;
var
  Rec: PtrUInt;
begin
  Result := False;
  try
    if not MemAddr(ID, Rec) then
      Exit;
    Result := (Rd8(Rec + PtrUInt(CtlOff + CtlKey[7])) <> 0) or (Rd8(Rec + PtrUInt(CtlOff + CtlKey[8])) <> 0);
  except
    Result := False;
  end;
end;

function SpriteCheck(ID, Alive, W, A, SW, SA, Gren, AimX, AimY, Keys: LongInt): LongInt;
var
  Rec: PtrUInt;
  Al, k: LongInt;
  Bad: AnsiString;
begin
  Result := -1;
  try
    if not MemAddr(ID, Rec) then
      Exit;
    Al := 0;
    if (PByte(Rec)^ <> 0) and (PByte(Rec + 1)^ = 0) then
      Al := 1;
    Bad := '';
    if Al <> Alive then
      Bad := 'alive'
    else if Rd8(Rec + PtrUInt(GunOff + 2)) <> W then
      Bad := 'weapon'
    else if Rd8(Rec + PtrUInt(GunOff + 1)) <> A then
      Bad := 'rounds'
    else if Rd8(Rec + PtrUInt(GunOff + GunStep + 2)) <> SW then
      Bad := 'second weapon'
    else if Rd8(Rec + PtrUInt(GunOff + GunStep + 1)) <> SA then
      Bad := 'second rounds'
    else if Rd8(Rec + PtrUInt(GunOff + 2 * GunStep + 1)) <> Gren then
      Bad := 'grenades'
    else if (Rd16(Rec + PtrUInt(CtlOff + CtlAim)) <> AimX) or (Rd16(Rec + PtrUInt(CtlOff + CtlAim + 2)) <> AimY) then
      Bad := 'aim'
    else
      for k := 0 to 11 do
        if (Rd8(Rec + PtrUInt(CtlOff + CtlKey[k])) <> 0) <> (((Keys shr k) and 1) <> 0) then
          Bad := 'key ' + IntToStr(k);
    if Bad <> '' then
    begin
      SpriteMemOff('soldier ' + IntToStr(ID) + '''s ' + Bad + ' differs from the property');
      Result := 0;
      Exit;
    end;
    Inc(MemChecks);
    Result := 1;
  except
    Result := -1;
  end;
end;

procedure SpriteMemReset;
begin
  GunOff := -1;
  GunStep := 0;
  CtlOff := -1;
  MemOn := False;
  MemDead := False;
  MemWhy := 'not calibrated yet';
  MemChecks := 0;
  CandN := 0;
  CandID := 0;
end;

function SpriteMemInfo: AnsiString;
begin
  if MemOn then
    Result := 'weapons and keys read from memory (guns at +' + IntToStr(GunOff) + ' step ' + IntToStr(GunStep) +
      ', keys at +' + IntToStr(CtlOff) + ' laid out as ' + IntToStr(CtlLayout) + ', ' + IntToStr(MemChecks) +
      ' checks passed)'
  else
    Result := 'weapons and keys from the properties (' + MemWhy + ')';
end;

end.
