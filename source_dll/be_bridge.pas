unit be_bridge;

{$mode objfpc}{$H+}
{$Q-}{$IFNDEF BE_CHECKS}{$R-}{$ENDIF}

interface

function BridgeReady: Boolean;
function BridgeSetWeapon(B, Style, W: LongInt; HitM: Single): LongInt;
function BridgeInfo: AnsiString;
procedure BridgeReset;
function AutoDetectBridge: Boolean;
{ a bullet's style (-1 = unknown); its Active flag, owner, weapon, style and the ticks it has left
  (TimeOut; a grenade explodes at 0); take a bullet out of the game before it explodes (only when it
  still has that owner and style) }
function BridgeBulletStyle(B: LongInt): LongInt;
function BridgeBulletInfo(B: LongInt; out Active, Owner, W, Style, TimeOut: LongInt): Boolean;
function BridgeBulletKill(B, Owner, Style: LongInt): Boolean;
{ where and when bullet B (made this tick at MadeX, MadeY) counts as fired: its Initial becomes FromX,
  FromY and its StartUpTime goes back by Ago ticks - the distance and the air time a kill by it shows
  (the server's death message) count from there }
function BridgeSetOrigin(B, Style: LongInt; MadeX, MadeY, FromX, FromY: Single; Ago: LongInt): LongInt;
{ inside the server program's own writable data (its global tables: the bullets, the soldiers) }
function ExeData(A: PtrUInt; Size: LongInt): Boolean;
{ CreateBullet has just made bullet B at the point PosPtr points to: the place of Initial in the record
  is learnt from it (a flame starts a step further on and is not used) }
procedure BridgeLearnOrigin(B: LongInt; PosPtr: Pointer);
{ where and at which tick bullet B counts as fired (its Initial and StartUpTime; False while their place
  is not known) - the server's death message counts the kill's distance and air time from these }
function BridgeBulletOrigin(B: LongInt; out X, Y: Single; out Tick: LongInt): Boolean;
implementation

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  {$IFDEF UNIX}BaseUnix,{$ENDIF}
  SysUtils;

const
  STRIDE_MIN = 24;
  STRIDE_MAX = 1024;
  { the fields of a bullet's record around its weapon byte (Base + B * Stride, where 2.8.2's code reads it) }
  OFF_W = 0;
  OFF_S = -4;
  OFF_N = -3;
  OFF_ACTIVE = -5;
  OFF_HITM = 11;

type
  TRegion = record
    A, B: PtrUInt;
  end;

var
  Regions: array of TRegion;
  Ready: Boolean = False;
  Base: PtrUInt = 0;
  Stride: PtrInt = 0;
  Info: AnsiString = 'not calibrated';
  Written: LongInt = 0;
  Refused: LongInt = 0;
  Killed: LongInt = 0;
  { the signature search runs once (a failed one would otherwise run again on every call) }
  Tried: Boolean = False;
  { Initial (the place a bullet was made at, a TVector2) from the weapon byte, with StartUpTime (the tick
    it was made) right after it: found once from a bullet just made (-999 = not looked for yet, -998 =
    not found); the origins written }
  OffInit: PtrInt = -999;
  Origins: LongInt = 0;
  { the bullets looked at for Initial's place (given up after 32 without a single match) }
  LearnTries: LongInt = 0;

const
  STYLE_FLAME = 5;


procedure AddRegion(A, B: PtrUInt);
var
  n: LongInt;
begin
  if B <= A + 16 then
    Exit;
  n := Length(Regions);
  SetLength(Regions, n + 1);
  Regions[n].A := A;
  Regions[n].B := B;
end;

{$IFDEF WINDOWS}
procedure FindRegions;
var
  M, Nt, Sec: PtrUInt;
  Count, OptSize, i: LongInt;
  VSize, VAddr, Flags: LongWord;
begin
  SetLength(Regions, 0);
  M := PtrUInt(GetModuleHandle(nil));
  if M = 0 then
    Exit;
  if PWord(M)^ <> $5A4D then
    Exit;
  Nt := M + PtrUInt(PLongInt(M + $3C)^);
  if PLongWord(Nt)^ <> $00004550 then
    Exit;
  Count := PWord(Nt + 6)^;
  OptSize := PWord(Nt + 20)^;
  Sec := Nt + 24 + PtrUInt(OptSize);
  for i := 0 to Count - 1 do
  begin
    VSize := PLongWord(Sec + 8)^;
    if VSize = 0 then
      VSize := PLongWord(Sec + 16)^;
    VAddr := PLongWord(Sec + 12)^;
    Flags := PLongWord(Sec + 36)^;
    if (Flags and $80000000) <> 0 then
      AddRegion(M + VAddr, M + VAddr + (VSize and not LongWord(3)));
    Inc(Sec, 40);
  end;
end;

function AutoDetectBridge: Boolean;
var
  M, Nt, Sec: PtrUInt;
  Count, OptSize, i: LongInt;
  VSize, VAddr: LongWord;
  p, pEnd: PByte;
  FoundAddr: PtrUInt;
  FoundStride: PtrInt;
begin
  Result := False;
  if Ready then
  begin
    Result := True;
    Exit;
  end;
  if Tried then
    Exit;
  Tried := True;
  FindRegions;
  M := PtrUInt(GetModuleHandle(nil));
  if M = 0 then
    Exit;
  if PWord(M)^ <> $5A4D then
    Exit;
  Nt := M + PtrUInt(PLongInt(M + $3C)^);
  if PLongWord(Nt)^ <> $00004550 then
    Exit;
  Count := PWord(Nt + 6)^;
  OptSize := PWord(Nt + 20)^;
  Sec := Nt + 24 + PtrUInt(OptSize);
  for i := 0 to Count - 1 do
  begin
    VSize := PLongWord(Sec + 8)^;
    if VSize = 0 then
      VSize := PLongWord(Sec + 16)^;
    VAddr := PLongWord(Sec + 12)^;
    if VSize < 14 then
    begin
      Inc(Sec, 40);
      Continue;
    end;
    p := PByte(M + VAddr);
    pEnd := PByte(M + VAddr + VSize - 14);
    while p <= pEnd do
    begin
      // Pattern of GetOwnerWeaponId:
      // 0F B6 40 08 6B C0 58 0F B6 80 [4 bytes: Base]
      if (p[0] = $0F) and (p[1] = $B6) and (p[2] = $40) and (p[3] = $08) and
         (p[4] = $6B) and (p[5] = $C0) and (p[7] = $0F) and (p[8] = $B6) and (p[9] = $80) then
      begin
        FoundStride := p[6]; // $58 = 88
        FoundAddr := PLongWord(@p[10])^;
        if (FoundStride >= STRIDE_MIN) and (FoundStride <= STRIDE_MAX) and (FoundAddr <> 0) then
        begin
          Base := FoundAddr;
          Stride := FoundStride;
          Ready := True;
          Info := 'ready (direct: base $' + HexStr(Base, 8) + ', record ' + IntToStr(Stride) + ' bytes)';
          Result := True;
          Exit;
        end;
      end;
      Inc(p);
    end;
    Inc(Sec, 40);
  end;
end;
{$ELSE}
function HexVal(const S: AnsiString): PtrUInt;
var
  i: LongInt;
  C: AnsiChar;
begin
  Result := 0;
  for i := 1 to Length(S) do
  begin
    C := S[i];
    Result := Result shl 4;
    case C of
      '0'..'9': Result := Result or PtrUInt(Ord(C) - Ord('0'));
      'a'..'f': Result := Result or PtrUInt(Ord(C) - Ord('a') + 10);
      'A'..'F': Result := Result or PtrUInt(Ord(C) - Ord('A') + 10);
    end;
  end;
end;

procedure FindRegions;
var
  F: TextFile;
  L, Exe, Path, Perm: AnsiString;
  p, q: LongInt;
  A, B, LastEnd: PtrUInt;
  Mine: Boolean;
begin
  SetLength(Regions, 0);
  Exe := fpReadLink('/proc/self/exe');
  if Exe = '' then
    Exit;
  AssignFile(F, '/proc/self/maps');
  {$I-}
  Reset(F);
  {$I+}
  if IOResult <> 0 then
    Exit;
  LastEnd := 0;
  try
    while not Eof(F) do
    begin
      ReadLn(F, L);
      p := Pos('-', L);
      q := Pos(' ', L);
      if (p = 0) or (q = 0) or (q < p) then
        Continue;
      A := HexVal(Copy(L, 1, p - 1));
      B := HexVal(Copy(L, p + 1, q - p - 1));
      Perm := Copy(L, q + 1, 4);
      Path := '';
      p := Pos('/', L);
      if p > 0 then
        Path := Trim(Copy(L, p, Length(L)));
      Mine := Path = Exe;
      if (Perm[1] = 'r') and (Perm[2] = 'w') then
      begin
        if Mine then
          AddRegion(A, B)
        else if (Path = '') and (LastEnd <> 0) and (A = LastEnd) then
          AddRegion(A, B);
      end;
      if Mine then
        LastEnd := B
      else
        LastEnd := 0;
    end;
  finally
    CloseFile(F);
  end;
end;

function AutoDetectBridge: Boolean;
var
  F: TextFile;
  L, Exe, Path, Perm: AnsiString;
  p, q: LongInt;
  A, B: PtrUInt;
  ptr, ptrEnd: PByte;
  FoundAddr: PtrUInt;
  FoundStride: PtrInt;
begin
  Result := False;
  if Ready then
  begin
    Result := True;
    Exit;
  end;
  if Tried then
    Exit;
  Tried := True;
  FindRegions;
  Exe := fpReadLink('/proc/self/exe');
  if Exe = '' then
    Exit;
  AssignFile(F, '/proc/self/maps');
  {$I-}
  Reset(F);
  {$I+}
  if IOResult <> 0 then
    Exit;
  try
    while not Eof(F) do
    begin
      ReadLn(F, L);
      p := Pos('-', L);
      q := Pos(' ', L);
      if (p = 0) or (q = 0) or (q < p) then
        Continue;
      A := HexVal(Copy(L, 1, p - 1));
      B := HexVal(Copy(L, p + 1, q - p - 1));
      Perm := Copy(L, q + 1, 4);
      Path := '';
      p := Pos('/', L);
      if p > 0 then
        Path := Trim(Copy(L, p, Length(L)));
      if (Path = Exe) and (Perm[1] = 'r') and (Perm[3] = 'x') then
      begin
        ptr := PByte(A);
        ptrEnd := PByte(B - 14);
        while ptr <= ptrEnd do
        begin
          if (ptr[0] = $0F) and (ptr[1] = $B6) and (ptr[2] = $40) and (ptr[3] = $08) and
             (ptr[4] = $6B) and (ptr[5] = $C0) and (ptr[7] = $0F) and (ptr[8] = $B6) and (ptr[9] = $80) then
          begin
            FoundStride := ptr[6];
            FoundAddr := PLongWord(@ptr[10])^;
            if (FoundStride >= STRIDE_MIN) and (FoundStride <= STRIDE_MAX) and (FoundAddr <> 0) then
            begin
              Base := FoundAddr;
              Stride := FoundStride;
              Ready := True;
              Info := 'ready (direct: base $' + HexStr(Base, 8) + ', record ' + IntToStr(Stride) + ' bytes)';
              Result := True;
              Exit;
            end;
          end;
          Inc(ptr);
        end;
      end;
    end;
  finally
    CloseFile(F);
  end;
end;
{$ENDIF}

function InRegion(a: PtrUInt; Size: LongInt): Boolean;
var
  r: LongInt;
begin
  Result := False;
  for r := 0 to High(Regions) do
    if (a >= Regions[r].A) and (a + PtrUInt(Size) <= Regions[r].B) then
    begin
      Result := True;
      Exit;
    end;
end;

function BridgeReady: Boolean;
begin
  if not Ready then
    AutoDetectBridge;
  Result := Ready;
end;

function BridgeSetWeapon(B, Style, W: LongInt; HitM: Single): LongInt;
var
  a: PtrUInt;
  H: Single;
begin
  Result := 0;
  if not Ready then
    if not AutoDetectBridge then
      Exit;
  if (B < 1) or (B > 254) or (W < 0) or (W > 255) then
    Exit;
  try
    a := PtrUInt(PtrInt(Base) + B * Stride);
    if not InRegion(a, 1) then
      Exit;

    // Safety check 1: Active flag
    if PByte(PtrInt(a) + OFF_ACTIVE)^ <> 1 then
    begin
      Inc(Refused);
      Result := -1;
      Exit;
    end;

    // Safety check 2: Bullet ID / Num
    if (PSmallInt(PtrInt(a) + OFF_N)^ <> SmallInt(B)) and (PByte(PtrInt(a) + OFF_N)^ <> Byte(B)) then
    begin
      Inc(Refused);
      Result := -1;
      Exit;
    end;

    // Safety check 3: Style
    if (Style >= 0) and (PByte(PtrInt(a) + OFF_S)^ <> Byte(Style)) then
    begin
      Inc(Refused);
      Result := -1;
      Exit;
    end;

    // Safety check 4: HitMultiply
    if HitM > 0.0 then
    begin
      H := PSingle(PtrInt(a) + OFF_HITM)^;
      if Abs(H - HitM) > 0.01 then
      begin
        Inc(Refused);
        Result := -1;
        Exit;
      end;
    end;

    // All safety checks passed! Write the weapon byte:
    PByte(PtrInt(a) + OFF_W)^ := Byte(W);
    Inc(Written);
    Result := 1;
  except
    Result := 0;
  end;
end;

{ the weapon byte of bullet B, when the table is known and B lies in it }
function SlotAddr(B: LongInt): PtrUInt;
begin
  Result := 0;
  if not Ready then
    if not AutoDetectBridge then
      Exit;
  if (B < 1) or (B > 254) then
    Exit;
  Result := PtrUInt(PtrInt(Base) + B * Stride);
  if not InRegion(PtrUInt(PtrInt(Result) + OFF_ACTIVE), 24) then
    Result := 0;
end;

function BridgeBulletStyle(B: LongInt): LongInt;
var
  a: PtrUInt;
begin
  Result := -1;
  try
    a := SlotAddr(B);
    if a <> 0 then
      Result := PByte(PtrInt(a) + OFF_S)^;
  except
    Result := -1;
  end;
end;

{ Active, Style, Num, Owner, OwnerWeapon, TimeOutReal, TimeOut from the record's start; relative to the
  weapon byte: -5, -4, -3, -1, 0, +3, +7 }
function BridgeBulletInfo(B: LongInt; out Active, Owner, W, Style, TimeOut: LongInt): Boolean;
var
  a: PtrUInt;
begin
  Result := False;
  Active := 0;
  Owner := 0;
  W := 0;
  Style := 0;
  TimeOut := 0;
  try
    a := SlotAddr(B);
    if a = 0 then
      Exit;
    Active := PByte(PtrInt(a) + OFF_ACTIVE)^;
    Owner := PByte(PtrInt(a) + OFF_W - 1)^;
    W := PByte(PtrInt(a) + OFF_W)^;
    Style := PByte(PtrInt(a) + OFF_S)^;
    TimeOut := PSmallInt(PtrInt(a) + OFF_W + 7)^;
    Result := Active <= 1;
  except
    Result := False;
  end;
end;

{ the game skips a bullet whose Active flag is off: it never explodes (its particle only drifts until
  the slot is used again, and CreateBullet then sets it anew) }
function BridgeBulletKill(B, Owner, Style: LongInt): Boolean;
var
  a: PtrUInt;
begin
  Result := False;
  try
    a := SlotAddr(B);
    if a = 0 then
      Exit;
    if PByte(PtrInt(a) + OFF_ACTIVE)^ <> 1 then
      Exit;
    if PByte(PtrInt(a) + OFF_W - 1)^ <> Byte(Owner) then
      Exit;
    if PByte(PtrInt(a) + OFF_S)^ <> Byte(Style) then
      Exit;
    PByte(PtrInt(a) + OFF_ACTIVE)^ := 0;
    Inc(Killed);
    Result := True;
  except
    Result := False;
  end;
end;
{ The TBullet record of the server: Initial (8 bytes) and StartUpTime follow the fields the signature
  gives (Active -5 ... HitMultiply +11 from the weapon byte); in the source they lie at +43 and +51. The
  place is not taken on trust: the record is searched once for the pair of floats the bullet was just
  made at, and it has to be there exactly once. }
function BridgeSetOrigin(B, Style: LongInt; MadeX, MadeY, FromX, FromY: Single; Ago: LongInt): LongInt;
var
  a: PtrUInt;
  d: PtrInt;
  Found: LongInt;
  BX, BY: LongWord;
begin
  Result := 0;
  try
    a := SlotAddr(B);
    if a = 0 then
      Exit;
    if (PByte(PtrInt(a) + OFF_ACTIVE)^ <> 1) or (PByte(PtrInt(a) + OFF_S)^ <> Byte(Style)) then
    begin
      Result := -1;
      Exit;
    end;
    BX := PLongWord(@MadeX)^;
    BY := PLongWord(@MadeY)^;
    if OffInit = -999 then
    begin
      OffInit := -998;
      Found := 0;
      d := OFF_ACTIVE;
      while d <= OFF_ACTIVE + Stride - 12 do
      begin
        if (PLongWord(PtrInt(a) + d)^ = BX) and (PLongWord(PtrInt(a) + d + 4)^ = BY) then
        begin
          Inc(Found);
          if Found = 1 then
            OffInit := d;
        end;
        Inc(d);
      end;
      if Found <> 1 then
        OffInit := -998;
    end;
    if OffInit < -900 then
      Exit;
    if not InRegion(PtrUInt(PtrInt(a) + OffInit), 12) then
      Exit;
    { still the bullet just made: its Initial is where it was made }
    if (PLongWord(PtrInt(a) + OffInit)^ <> BX) or (PLongWord(PtrInt(a) + OffInit + 4)^ <> BY) then
    begin
      Result := -1;
      Exit;
    end;
    PSingle(PtrInt(a) + OffInit)^ := FromX;
    PSingle(PtrInt(a) + OffInit + 4)^ := FromY;
    if Ago > 0 then
      PLongInt(PtrInt(a) + OffInit + 8)^ := PLongInt(PtrInt(a) + OffInit + 8)^ - Ago;
    Inc(Origins);
    Result := 1;
  except
    Result := 0;
  end;
end;

function ExeData(A: PtrUInt; Size: LongInt): Boolean;
begin
  if Length(Regions) = 0 then
    FindRegions;
  Result := InRegion(A, Size);
end;

procedure BridgeLearnOrigin(B: LongInt; PosPtr: Pointer);
var
  a: PtrUInt;
  d, At: PtrInt;
  Found: LongInt;
  BX, BY: LongWord;
begin
  try
    if OffInit <> -999 then
      Exit;
    if PtrUInt(PosPtr) <= $10000 then
      Exit;
    a := SlotAddr(B);
    if a = 0 then
      Exit;
    if PByte(PtrInt(a) + OFF_S)^ = STYLE_FLAME then
      Exit;
    BX := PLongWord(PosPtr)^;
    BY := PLongWord(PtrUInt(PosPtr) + 4)^;
    Found := 0;
    At := 0;
    d := OFF_ACTIVE;
    while d <= OFF_ACTIVE + Stride - 12 do
    begin
      if (PLongWord(PtrInt(a) + d)^ = BX) and (PLongWord(PtrInt(a) + d + 4)^ = BY) then
      begin
        Inc(Found);
        if Found = 1 then
          At := d;
      end;
      Inc(d);
    end;
    if Found = 1 then
      OffInit := At
    else
    begin
      Inc(LearnTries);
      if LearnTries >= 32 then
        OffInit := -998;
    end;
  except
  end;
end;

function BridgeBulletOrigin(B: LongInt; out X, Y: Single; out Tick: LongInt): Boolean;
var
  a: PtrUInt;
  BX, BY: LongWord;
begin
  Result := False;
  X := 0;
  Y := 0;
  Tick := 0;
  try
    if OffInit < -900 then
      Exit;
    a := SlotAddr(B);
    if a = 0 then
      Exit;
    if not InRegion(PtrUInt(PtrInt(a) + OffInit), 12) then
      Exit;
    BX := PLongWord(PtrInt(a) + OffInit)^;
    BY := PLongWord(PtrInt(a) + OffInit + 4)^;
    { a float of the map, not a pattern of an unused slot }
    if ((BX and $7F800000) = $7F800000) or ((BY and $7F800000) = $7F800000) then
      Exit;
    X := PSingle(@BX)^;
    Y := PSingle(@BY)^;
    Tick := PLongInt(PtrInt(a) + OffInit + 8)^;
    Result := True;
  except
    Result := False;
  end;
end;

function BridgeInfo: AnsiString;
begin
  Result := Info + ', weapons set ' + IntToStr(Written) + ', refused ' + IntToStr(Refused);
  if Killed > 0 then
    Result := Result + ', grenades taken out ' + IntToStr(Killed);
  if OffInit > -900 then
    Result := Result + ', shot origins set ' + IntToStr(Origins) + ' (at ' + IntToStr(OffInit) + ')'
  else if OffInit = -998 then
    Result := Result + ', shot origin field not found';
end;

procedure BridgeReset;
begin
  Ready := False;
  Base := 0;
  Stride := 0;
  Info := 'not calibrated';
  Written := 0;
  Refused := 0;
  Killed := 0;
  OffInit := -999;
  Origins := 0;
  LearnTries := 0;
  Tried := False;
  SetLength(Regions, 0);
end;

end.
