unit be_hook;

{ OnPlayerShoot and OnWeaponDrop: hooks on the server's CreateBullet and CreateThing (Soldat 2.8.2,
  found by their first bytes).

  Every bullet goes through CreateBullet: the server's own fire (bots, the fast weapons of humans),
  the bullets of humans that come in packets (ServerHandleBulletSnapshot), grenades, thrown knives,
  arrows, cluster fragments and the scripts' bullets (Map.CreateBullet -> ServerCreateBullet). The
  hook calls the original and looks at what it returned: only a bullet that was really made (an
  index 1..255) is reported - for a human's slow weapon the server's simulation calls CreateBullet
  too, and it returns -1 at once. A bullet made by ServerCreateBullet (the call comes from inside it)
  is a script's bullet, not a shot.

  CreateThing makes the weapons a soldier drops (thrown away, with his body, at a team change, when
  he leaves): the hook reports the object's index and its owner, so the dropped weapon is known
  exactly.

  The hooks run in the game thread inside the server's code: they hand the event to the library's own
  handlers (the ammunition) and copy the bullets of the weapons the script watches (HookWatch: grenades,
  thrown knives) into a ring the script reads every tick; nothing can throw out of them, and no float
  goes through the FPU there. The calling convention is Free Pascal's register convention of the server:
  EAX, EDX, ECX and the rest on the stack, popped by the callee. }

{$mode objfpc}{$H+}
{$asmmode intel}
{$Q-}{$IFNDEF BE_CHECKS}{$R-}{$ENDIF}

interface

const
  MAX_SHOT_QUEUE = 256;

type
  TShotEvent = record
    { the script's tick the bullet belongs to (seen in the samples of that tick) }
    Tick: LongInt;
    Slot, Owner, W, Style: LongInt;
    X, Y, VX, VY: Single;
    { made by a script (ServerCreateBullet), not fired }
    Script: Boolean;
  end;

  TThingEvent = record
    Tick, Slot, Owner, Style: LongInt;
    X, Y: Single;
  end;

  TShotProc = procedure(const E: TShotEvent);
  TThingProc = procedure(const E: TThingEvent);

var
  { the library's own handlers (the ammunition) }
  OnShot: TShotProc = nil;
  OnThing: TThingProc = nil;

{ 3 = both hooks in place, 1 = only CreateBullet, 0 = the server's code was not found }
function HookInit: LongInt;
procedure HookShutdown;
{ the script's tick begins: the bullets from now on are seen in the samples of the next one }
procedure HookTick(Tick: LongInt);
{ the script wants the bullets of weapon number W (0..255; -1 = all) in its ring, or not }
procedure HookWatch(W: LongInt; On: Boolean);
function HookNextShot(out E: TShotEvent): LongInt;
function HookInfo: AnsiString;

implementation

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  {$IFDEF UNIX}BaseUnix,{$ENDIF}
  SysUtils, be_bridge;

const
  { ServerCreateBullet(sPos, sVelocity: TVector2; sNum: Byte; sOwner: Integer; N: Byte; HitM: Single;
    Net: Boolean): Integer - push ebp; mov ebp,esp; sub esp,2Ch; ... mov eax,[ebp+14h] (sOwner) }
  SIG_SCB: array[0..23] of Byte = (
    $55, $89, $E5, $83, $EC, $2C, $53, $56, $57, $89, $45, $FC, $89, $55, $F8, $88,
    $CB, $8B, $45, $14, $89, $45, $E0, $8A);
  { CreateBullet(sPos, sVelocity: TVector2; sNum: Byte; sOwner: Integer; N: Byte; HitM: Single; Net,
    MustCreate: Boolean; Seed: LongInt): Integer - sub esp,8Ch; ... mov eax,[ebp+1Ch] (sOwner) }
  SIG_CB: array[0..23] of Byte = (
    $55, $89, $E5, $81, $EC, $8C, $00, $00, $00, $53, $56, $57, $89, $45, $FC, $89,
    $55, $F8, $88, $4D, $90, $8B, $45, $1C);
  { CreateThing(sPos: TVector2; owner, sStyle, N: Byte): Integer - sub esp,4Ch; mov [ebp-4],eax;
    mov [ebp-3Ch],dl; mov [ebp-38h],cl; mov bl,[ebp+8] (N) ... rep movsb (the position) }
  SIG_CT: array[0..33] of Byte = (
    $55, $89, $E5, $83, $EC, $4C, $53, $56, $57, $89, $45, $FC, $88, $55, $C4, $88,
    $4D, $C8, $8A, $5D, $08, $8B, $75, $FC, $8D, $7D, $D4, $B9, $08, $00, $00, $00,
    $F3, $A4);
  { the whole instructions replaced by the jump: push ebp; mov ebp,esp; sub esp,imm32 / imm8 }
  CB_PATCH = 9;
  CT_PATCH = 6;
  TRAMP_SIZE = 32;

var
  Installed: LongInt = 0;
  AddrCB, AddrSCB, AddrSCBEnd, AddrCT: PtrUInt;
  SavedCB: array[0..CB_PATCH - 1] of Byte;
  SavedCT: array[0..CT_PATCH - 1] of Byte;
  TrampCB: Pointer = nil;
  TrampCT: Pointer = nil;
  { where the trampolines lead (an earlier start's are used again: the same prologue) }
  TrampCBFor: PtrUInt = 0;
  TrampCTFor: PtrUInt = 0;
  TickNow: LongInt = 0;
  Shots: array[0..MAX_SHOT_QUEUE - 1] of TShotEvent;
  ShotHead: LongInt = 0;
  ShotTail: LongInt = 0;
  CntShots: LongInt = 0;
  CntScript: LongInt = 0;
  CntThings: LongInt = 0;
  Why: AnsiString = 'not installed';
  Watch: array[0..255] of Boolean;
  WatchAll: Boolean = False;

{ ---------------- what the hooks report ---------------- }

procedure ShotMade(Res: LongInt; PosPtr, VelPtr: Pointer; Num, Owner: LongInt; CallerRet: PtrUInt); cdecl;
var
  E: TShotEvent;
  n: LongInt;
begin
  try
    if (Res < 1) or (Res > 254) then
      Exit;
    E.Tick := TickNow + 1;
    E.Slot := Res;
    E.Owner := Owner;
    E.W := Num and $FF;
    E.Style := BridgeBulletStyle(Res);
    { the first bullets teach the bridge where Initial lies (for the kills' distance and air time) }
    if E.Style <> 5 then
      BridgeLearnOrigin(Res, PosPtr);
    { the floats are copied as they are (a load into the FPU could trap inside the server's code) }
    PLongWord(@E.X)^ := 0;
    PLongWord(@E.Y)^ := 0;
    PLongWord(@E.VX)^ := 0;
    PLongWord(@E.VY)^ := 0;
    if PtrUInt(PosPtr) > $10000 then
    begin
      PLongWord(@E.X)^ := PLongWord(PosPtr)^;
      PLongWord(@E.Y)^ := PLongWord(PtrUInt(PosPtr) + 4)^;
    end;
    if PtrUInt(VelPtr) > $10000 then
    begin
      PLongWord(@E.VX)^ := PLongWord(VelPtr)^;
      PLongWord(@E.VY)^ := PLongWord(PtrUInt(VelPtr) + 4)^;
    end;
    E.Script := (AddrSCB <> 0) and (CallerRet >= AddrSCB) and (CallerRet < AddrSCBEnd);
    if E.Script then
      Inc(CntScript)
    else
      Inc(CntShots);
    if not E.Script then
      if WatchAll or Watch[E.W] then
      begin
        Shots[ShotHead] := E;
        n := (ShotHead + 1) and (MAX_SHOT_QUEUE - 1);
        if n = ShotTail then
          ShotTail := (ShotTail + 1) and (MAX_SHOT_QUEUE - 1);
        ShotHead := n;
      end;
    if Assigned(OnShot) then
      OnShot(E);
  except
  end;
end;

procedure ThingMade(Res: LongInt; PosPtr: Pointer; Owner, Style: LongInt); cdecl;
var
  E: TThingEvent;
begin
  try
    if (Res < 1) or (Res > 255) then
      Exit;
    E.Tick := TickNow + 1;
    E.Slot := Res;
    E.Owner := Owner and $FF;
    E.Style := Style and $FF;
    PLongWord(@E.X)^ := 0;
    PLongWord(@E.Y)^ := 0;
    if PtrUInt(PosPtr) > $10000 then
    begin
      PLongWord(@E.X)^ := PLongWord(PosPtr)^;
      PLongWord(@E.Y)^ := PLongWord(PtrUInt(PosPtr) + 4)^;
    end;
    Inc(CntThings);
    if Assigned(OnThing) then
      OnThing(E);
  except
  end;
end;

{ ---------------- the hooks ---------------- }

{ entered by the jump at CreateBullet: EAX = @sPos, EDX = @sVelocity, CL = sNum, the stack: the
  return address and Seed, MustCreate, Net, HitM, N, sOwner (sOwner the deepest). The original gets
  the same registers and a copy of the six, pops them (ret 24); then the result is reported and the
  caller's six are popped. }
procedure HookCB; assembler; nostackframe;
asm
  push ebp
  mov ebp, esp
  push eax
  push edx
  push ecx
  push dword ptr [ebp + 28]
  push dword ptr [ebp + 24]
  push dword ptr [ebp + 20]
  push dword ptr [ebp + 16]
  push dword ptr [ebp + 12]
  push dword ptr [ebp + 8]
  mov eax, [ebp - 4]
  mov edx, [ebp - 8]
  mov ecx, [ebp - 12]
  call dword ptr [TrampCB]
  push eax
  push dword ptr [ebp + 4]
  push dword ptr [ebp + 28]
  push dword ptr [ebp - 12]
  push dword ptr [ebp - 8]
  push dword ptr [ebp - 4]
  push eax
  call ShotMade
  add esp, 24
  pop eax
  mov esp, ebp
  pop ebp
  ret 24
end;

{ entered by the jump at CreateThing: EAX = @sPos, DL = owner, CL = sStyle, the stack: the return
  address and N (ret 4) }
procedure HookCT; assembler; nostackframe;
asm
  push ebp
  mov ebp, esp
  push eax
  push edx
  push ecx
  push dword ptr [ebp + 8]
  mov eax, [ebp - 4]
  mov edx, [ebp - 8]
  mov ecx, [ebp - 12]
  call dword ptr [TrampCT]
  push eax
  push dword ptr [ebp - 12]
  push dword ptr [ebp - 8]
  push dword ptr [ebp - 4]
  push eax
  call ThingMade
  add esp, 16
  pop eax
  mov esp, ebp
  pop ebp
  ret 4
end;

{ ---------------- finding the code ---------------- }

{$IFDEF UNIX}
function HexOf(const S: AnsiString): PtrUInt;
var
  i: LongInt;
  c: AnsiChar;
begin
  Result := 0;
  for i := 1 to Length(S) do
  begin
    c := S[i];
    if c in ['0'..'9'] then
      Result := Result * 16 + PtrUInt(Ord(c) - Ord('0'))
    else if c in ['a'..'f'] then
      Result := Result * 16 + PtrUInt(Ord(c) - Ord('a') + 10)
    else if c in ['A'..'F'] then
      Result := Result * 16 + PtrUInt(Ord(c) - Ord('A') + 10)
    else
      Break;
  end;
end;
{$ENDIF}

function Matches(p: PByte; const Sig: array of Byte): Boolean;
var
  j: LongInt;
begin
  Result := False;
  for j := 0 to High(Sig) do
    if p[j] <> Sig[j] then
      Exit;
  Result := True;
end;

{ the address of the only place in the server's code that begins with Sig (0 = none, or more than one) }
function FindCode(const Sig: array of Byte): PtrUInt;
var
  Found: LongInt;
  {$IFDEF WINDOWS}
  M, Nt, Sec: PtrUInt;
  Count, OptSize, i: LongInt;
  VSize, VAddr, Flags: LongWord;
  p, pEnd: PByte;
  {$ELSE}
  F: TextFile;
  L, Exe, Path, Perm: AnsiString;
  pPos, qPos: LongInt;
  A, B: PtrUInt;
  p, pEnd: PByte;
  {$ENDIF}
begin
  Result := 0;
  Found := 0;
  {$IFDEF WINDOWS}
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
    VAddr := PLongWord(Sec + 12)^;
    Flags := PLongWord(Sec + 36)^;
    { code sections only }
    if ((Flags and $20000000) <> 0) and (VSize > LongWord(Length(Sig))) then
    begin
      p := PByte(M + VAddr);
      pEnd := PByte(M + VAddr + VSize - LongWord(Length(Sig)));
      while p <= pEnd do
      begin
        if p^ = Sig[0] then
          if Matches(p, Sig) then
          begin
            Inc(Found);
            Result := PtrUInt(p);
          end;
        Inc(p);
      end;
    end;
    Inc(Sec, 40);
  end;
  {$ELSE}
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
      pPos := Pos('-', L);
      qPos := Pos(' ', L);
      if (pPos = 0) or (qPos = 0) or (qPos < pPos) then
        Continue;
      A := HexOf(Copy(L, 1, pPos - 1));
      B := HexOf(Copy(L, pPos + 1, qPos - pPos - 1));
      Perm := Copy(L, qPos + 1, 4);
      Path := '';
      pPos := Pos('/', L);
      if pPos > 0 then
        Path := Trim(Copy(L, pPos, Length(L)));
      if (Path = Exe) and (Length(Perm) >= 3) and (Perm[1] = 'r') and (Perm[3] = 'x') then
        if B > A + PtrUInt(Length(Sig)) then
        begin
          p := PByte(A);
          pEnd := PByte(B - PtrUInt(Length(Sig)));
          while p <= pEnd do
          begin
            if p^ = Sig[0] then
              if Matches(p, Sig) then
              begin
                Inc(Found);
                Result := PtrUInt(p);
              end;
            Inc(p);
          end;
        end;
    end;
  finally
    CloseFile(F);
  end;
  {$ENDIF}
  if Found <> 1 then
    Result := 0;
end;

{ the end of a function: the first "leave; ret Pops" within Span bytes (0 = not there) }
function FindRet(Start: PtrUInt; Pops: LongInt; Span: LongInt): PtrUInt;
var
  p: PByte;
  k: LongInt;
begin
  Result := 0;
  p := PByte(Start);
  for k := 0 to Span - 4 do
    if (p[k] = $C9) and (p[k + 1] = $C2) and (p[k + 2] = Byte(Pops)) and (p[k + 3] = 0) then
    begin
      Result := Start + PtrUInt(k) + 4;
      Exit;
    end;
end;

function NewTrampoline(Target: PtrUInt; Size: LongInt): Pointer;
var
  t: PByte;
begin
  {$IFDEF WINDOWS}
  Result := VirtualAlloc(nil, TRAMP_SIZE, MEM_COMMIT or MEM_RESERVE, PAGE_EXECUTE_READWRITE);
  {$ELSE}
  Result := fpmmap(nil, 4096, PROT_READ or PROT_WRITE or PROT_EXEC, MAP_PRIVATE or MAP_ANONYMOUS, -1, 0);
  if Result = MAP_FAILED then
    Result := nil;
  {$ENDIF}
  if Result = nil then
    Exit;
  t := PByte(Result);
  Move(Pointer(Target)^, t^, Size);
  t[Size] := $E9;
  PLongInt(@t[Size + 1])^ := LongInt(Target + PtrUInt(Size)) - LongInt(PtrUInt(Result) + PtrUInt(Size) + 5);
  {$IFDEF UNIX}
  { written: read and run only from now on }
  fpmprotect(Result, 4096, PROT_READ or PROT_EXEC);
  {$ENDIF}
end;

procedure FreeTrampoline(var T: Pointer);
begin
  if T = nil then
    Exit;
  {$IFDEF WINDOWS}
  VirtualFree(T, 0, MEM_RELEASE);
  {$ELSE}
  fpmunmap(T, 4096);
  {$ENDIF}
  T := nil;
end;

{ Size bytes at Target become a jump to Handler (the rest NOPs) }
function Patch(Target: PtrUInt; Handler: Pointer; Size: LongInt): Boolean;
var
  p: PByte;
  k: LongInt;
  {$IFDEF WINDOWS}
  Old: LongWord;
  {$ENDIF}
begin
  Result := False;
  {$IFDEF WINDOWS}
  if not VirtualProtect(Pointer(Target), Size, PAGE_EXECUTE_READWRITE, @Old) then
    Exit;
  {$ELSE}
  if fpmprotect(Pointer(Target and not PtrUInt($FFF)), $2000, PROT_READ or PROT_WRITE or PROT_EXEC) <> 0 then
    Exit;
  {$ENDIF}
  p := PByte(Target);
  p[0] := $E9;
  PLongInt(@p[1])^ := LongInt(PtrUInt(Handler)) - LongInt(Target + 5);
  for k := 5 to Size - 1 do
    p[k] := $90;
  {$IFDEF WINDOWS}
  VirtualProtect(Pointer(Target), Size, Old, @Old);
  FlushInstructionCache(GetCurrentProcess, Pointer(Target), Size);
  {$ELSE}
  { the server's code pages read and run only again }
  fpmprotect(Pointer(Target and not PtrUInt($FFF)), $2000, PROT_READ or PROT_EXEC);
  {$ENDIF}
  Result := True;
end;

procedure Unpatch(Target: PtrUInt; const Saved: array of Byte);
var
  {$IFDEF WINDOWS}
  Old: LongWord;
  {$ENDIF}
  k: LongInt;
begin
  {$IFDEF WINDOWS}
  if not VirtualProtect(Pointer(Target), Length(Saved), PAGE_EXECUTE_READWRITE, @Old) then
    Exit;
  {$ELSE}
  if fpmprotect(Pointer(Target and not PtrUInt($FFF)), $2000, PROT_READ or PROT_WRITE or PROT_EXEC) <> 0 then
    Exit;
  {$ENDIF}
  for k := 0 to High(Saved) do
    PByte(Target + PtrUInt(k))^ := Saved[k];
  {$IFDEF WINDOWS}
  VirtualProtect(Pointer(Target), Length(Saved), Old, @Old);
  FlushInstructionCache(GetCurrentProcess, Pointer(Target), Length(Saved));
  {$ELSE}
  fpmprotect(Pointer(Target and not PtrUInt($FFF)), $2000, PROT_READ or PROT_EXEC);
  {$ENDIF}
end;

{ ---------------- the interface ---------------- }

function HookInit: LongInt;
var
  k: LongInt;
begin
  Result := Installed;
  if Installed <> 0 then
    Exit;
  try
    AddrCB := FindCode(SIG_CB);
    if AddrCB = 0 then
    begin
      Why := 'CreateBullet not found';
      Exit;
    end;
    { CreateBullet must end with leave; ret 24 (six stack parameters) }
    if FindRet(AddrCB, 24, $1000) = 0 then
    begin
      Why := 'CreateBullet does not end as expected';
      Exit;
    end;
    AddrSCB := FindCode(SIG_SCB);
    AddrSCBEnd := 0;
    if AddrSCB <> 0 then
      AddrSCBEnd := FindRet(AddrSCB, 16, $600);
    if AddrSCBEnd = 0 then
      AddrSCB := 0;
    for k := 0 to CB_PATCH - 1 do
      SavedCB[k] := PByte(AddrCB + PtrUInt(k))^;
    if (TrampCB = nil) or (TrampCBFor <> AddrCB) or (not CompareMem(TrampCB, @SavedCB[0], CB_PATCH)) then
    begin
      TrampCB := NewTrampoline(AddrCB, CB_PATCH);
      TrampCBFor := AddrCB;
    end;
    if TrampCB = nil then
    begin
      Why := 'no memory for the trampoline';
      Exit;
    end;
    if not Patch(AddrCB, @HookCB, CB_PATCH) then
    begin
      FreeTrampoline(TrampCB);
      Why := 'CreateBullet could not be patched';
      Exit;
    end;
    Installed := 1;
    Why := 'CreateBullet hooked';
    AddrCT := FindCode(SIG_CT);
    if AddrCT <> 0 then
      if FindRet(AddrCT, 4, $2000) <> 0 then
      begin
        for k := 0 to CT_PATCH - 1 do
          SavedCT[k] := PByte(AddrCT + PtrUInt(k))^;
        if (TrampCT = nil) or (TrampCTFor <> AddrCT) or (not CompareMem(TrampCT, @SavedCT[0], CT_PATCH)) then
        begin
          TrampCT := NewTrampoline(AddrCT, CT_PATCH);
          TrampCTFor := AddrCT;
        end;
        if TrampCT <> nil then
          if Patch(AddrCT, @HookCT, CT_PATCH) then
          begin
            Installed := 3;
            Why := 'CreateBullet and CreateThing hooked';
          end
          else
            FreeTrampoline(TrampCT);
      end;
  except
    Why := 'error while hooking';
  end;
  Result := Installed;
end;

procedure HookShutdown;
begin
  try
    if (Installed and 2) <> 0 then
      Unpatch(AddrCT, SavedCT);
    if (Installed and 1) <> 0 then
      Unpatch(AddrCB, SavedCB);
  except
  end;
  { the trampolines stay: a call that is on its way through one must not fall into freed memory }
  Installed := 0;
  Why := 'not installed';
  HookWatch(-1, False);
  ShotHead := 0;
  ShotTail := 0;
end;

procedure HookTick(Tick: LongInt);
begin
  TickNow := Tick;
end;

procedure HookWatch(W: LongInt; On: Boolean);
var
  k: LongInt;
begin
  if W < 0 then
  begin
    WatchAll := On;
    if not On then
      for k := 0 to 255 do
        Watch[k] := False;
  end
  else if W <= 255 then
    Watch[W] := On;
end;

function HookNextShot(out E: TShotEvent): LongInt;
begin
  Result := 0;
  FillChar(E, SizeOf(E), 0);
  if ShotHead = ShotTail then
    Exit;
  E := Shots[ShotTail];
  ShotTail := (ShotTail + 1) and (MAX_SHOT_QUEUE - 1);
  Result := 1;
end;

function HookInfo: AnsiString;
begin
  Result := 'hooks: ' + Why;
  if Installed <> 0 then
    Result := Result + ' (shots ' + IntToStr(CntShots) + ', script bullets ' + IntToStr(CntScript) +
      ', objects made ' + IntToStr(CntThings) + ')';
end;

end.
