unit be_things;

{$mode objfpc}{$H+}
{$Q-}{$IFNDEF BE_CHECKS}{$R-}{$ENDIF}

{ [Looting] KeepWeapons: the weapons lying on the ground do not vanish before the round ends.

  What the server does (Soldat 2.8.2, shared/mechanics/Things.pas): a weapon thrown away or left by a dead
  soldier gets TimeOut := GUNRESISTTIME (1200 ticks, 20 s); TThing.Update counts it down and Kills the
  object at 0. The same number is the pickup delay (a soldier may take the weapon only when TimeOut <
  GUNRESISTTIME - 30). The clients run TThing.Update too, with a TimeOut of their own: a weapon that
  lies still is not sent again (ServerThingSnapshot skips static things), so the client's copy blinks
  in its last 5 s and disappears 20 s after the drop whatever the server does. ServerThingMustSnapshot(I)
  sends the object with the server's TimeOut and the client takes it over - that is the one message that
  keeps the client's copy alive.

  Two ways to keep a weapon:

  bridge     the server's Thing table is found in its code (the sequence of stores in CreateThing that
             sets Active, Style, Num, HoldingSprite, Owner and TimeOut of the object - the same code on
             the Windows and the Linux server), checked against what ScriptCore says about every object
             (Active, Style, X, Y), and ServerThingMustSnapshot is found by its first instructions. A
             weapon whose TimeOut falls to RefreshBelow gets TimeOut := RefreshTo (below the pickup
             delay's 1170) and the server sends it to the clients again. Nothing is written before the
             table agrees with ScriptCore at every object and the resend is found; a disagreement later
             refuses the bridge for good.
  recreate   shortly before the end the script kills the object and makes the same weapon at the same
             place (Map.AddObject); ThingsDue / ThingsRenewed tell the script which and keep the order.
             The new weapon has full ammunition (AddObject's) and no owner.

  The library tracks the free weapons from the script's looks (ThingsSeen: Map.Objects[I] every half
  second) and the hook's reports (ThingsMade: the tick of the drop). Only weapons dropped while the
  keeper is armed are kept: ThingsPass(Tick, 0) (the round has ended, or the mode is off) releases every
  weapon on the ground for good - they run out their own TimeOut. At most KeepMax weapons are kept: the
  oldest above it are not refreshed and expire normally, so a new drop still finds one of the 90
  slots. }

interface

type
  TSnapProc = procedure(I: Byte); register;

  { what the code of the server says about the Thing table: record I lies at Base + I * Size (Base is
    where record 0 would stand, the way FPC addresses a 1-based array); Offset... from a record's start }
  TThLayout = record
    Found: Boolean;
    Base: PtrUInt;
    Size: LongInt;
    OffStyle, OffHold, OffOwner, OffTime, OffSkel, OffPos: LongInt;
  end;

const
  TH_N = 90;
  { 2.8.2's CreateThing, from the first store (Active := True) to the call of Skeleton.Destroy; the 4-byte
    fields are wildcards, ThingsParseInit reads them }
  TH_INIT_SIG = '69 45 ?? ?? ?? ?? ?? C6 80 ?? ?? ?? ?? 01 69 45 ?? ?? ?? ?? ?? 8A 55 ?? 88 55 ?? 88 90 ?? ?? ?? ?? ' +
    '69 45 ?? ?? ?? ?? ?? 8A 55 ?? 88 90 ?? ?? ?? ?? 69 45 ?? ?? ?? ?? ?? C6 80 ?? ?? ?? ?? 00 ' +
    '69 45 ?? ?? ?? ?? ?? 8A 55 ?? 88 55 ?? 88 90 ?? ?? ?? ?? 69 45 ?? ?? ?? ?? ?? C7 80 ?? ?? ?? ?? 00 00 00 00 ' +
    '69 45 ?? ?? ?? ?? ?? 8D 80 ?? ?? ?? ?? E8 ?? ?? ?? ??';
  TH_INIT_LEN = 117;
  { ServerThingMustSnapshot(I: Byte): push ebp; mov ebp,esp; sub esp,imm; push ebx; movzx edx,al; imul edx,edx,Size;
    cmp byte [edx+Style of record 0],23 (the parachute: not sent); je ...; mov byte [ebp-x],33 (the message's id) }
  TH_SNAP_SIG = '55 89 E5 81 EC ?? ?? ?? ?? 53 0F B6 D0 69 D2 ?? ?? ?? ?? 80 BA ?? ?? ?? ?? 17 0F 84 ?? ?? ?? ?? C6 45 ?? 21';
  TH_SNAP_LEN = 36;
  { TThing.Skeleton.Pos[1] lies after the skeleton's Active[1..560] }
  TH_POS_AFTER_SKEL = 560;
  TH_GUNTIME = 1200;
  { a weapon whose TimeOut is at most this is refreshed ... }
  TH_REFRESH_BELOW = 800;
  { ... to this (below GUNRESISTTIME - 30: a soldier can take it at once) }
  TH_REFRESH_TO = 1160;
  { the time out of a weapon the hook saw dropped may differ this much from 1200 less its age in ticks }
  TH_TIME_SLACK = 150;
  { recreate: a weapon this old (ticks since it was made or last renewed) is made again }
  TH_RENEW_AGE = 1080;

{ pure: do the bytes at P match the pattern Pat ('69 45 ?? ...': hex bytes, ?? = any) }
function ThingsSigMatches(P: PByte; const Pat: AnsiString): Boolean;
{ pure: the layout from the bytes at a match of TH_INIT_SIG; the resend function's check against it }
function ThingsParseInit(P: PByte; out L: TThLayout): Boolean;
function ThingsParseSnap(P: PByte; const L: TThLayout): Boolean;
{ weapons that run out: the guns (4..14), the knife, chainsaw and LAW (24..26); not the bow (it respawns) }
function ThingsWeaponStyle(S: LongInt): Boolean;

{ Method: 0 auto (bridge when it works, else recreate), 1 bridge only, 2 recreate only; MaxKept }
procedure ThingsConfig(Method, MaxKept: LongInt);
{ the half second's pass begins (Tick, Armed = the keeper is on now); Armed = 0 releases every weapon }
procedure ThingsPass(Tick, Armed: LongInt);
{ Map.Objects[I] as the script sees it; 1 = fine, 0 = the table disagrees (the bridge is refused) }
function ThingsSeen(I, Active, Style: LongInt; X, Y: Single): LongInt;
{ bridge: refresh the weapons that need it; the number written }
function ThingsKeep: LongInt;
{ recreate: the next slot >= From whose weapon is to be made again (0 = none) / done: New is the new one }
function ThingsDue(From: LongInt): LongInt;
procedure ThingsRenewed(Old, New: LongInt);
{ the game stood still for N ticks (a pause): the clocks go on with it }
procedure ThingsShift(N: LongInt);
{ a new map: nothing is tracked }
procedure ThingsMap;
{ the hook saw the game make object Slot (a weapon dropped) at Tick }
procedure ThingsMade(Slot, Style, Tick: LongInt);
{ 1 bridge, 2 recreate, 0 none (yet / off) }
function ThingsMethodNow: LongInt;
{ 0 not looked for, 1 waiting for an object to check, 2 ready, 3 refused, 4 not found }
function ThingsState: LongInt;
function ThingsInfo: AnsiString;
procedure ThingsReset;
{ tests: use this layout and resend function without the server's code or regions }
procedure ThingsTestUse(const L: TThLayout; Snap: TSnapProc);
{ tests: weapons kept / capped now }
function ThingsKept: LongInt;
function ThingsCapped: LongInt;

implementation

uses
  SysUtils, be_bridge, be_hook;

type
  TWordArr = array of Word;

  TTrack = record
    { Known: the hook told the tick of the drop; Written: the time out was written at least once }
    Used, Released, Capped, Known, Written: Boolean;
    Style, Born, Anchor: LongInt;
    X, Y: Single;
  end;

var
  Lay: TThLayout;
  SnapProc: TSnapProc = nil;
  SnapNote: AnsiString = '';
  Tried: Boolean = False;
  Verified: Boolean = False;
  Refused: Boolean = False;
  Why: AnsiString = '';
  Proofs: LongInt = 0;
  Unchecked: Boolean = False;
  CfgMethod: LongInt = 0;
  CfgMax: LongInt = 50;
  PassTick: LongInt = 0;
  IsArmed: Boolean = False;
  ArmedSince: LongInt = 0;
  Track: array[1..TH_N] of TTrack;
  MadeTick, MadeStyle: array[1..TH_N] of LongInt;
  StRefresh: LongInt = 0;
  StRenew: LongInt = 0;
  StSkipped: LongInt = 0;
  StReleased: LongInt = 0;
  { the weapon ThingsDue named last (its entry: the hook's report of the new object may clear the slot's before
    ThingsRenewed) }
  DueSlot: LongInt = 0;
  DueTrack: TTrack;

function ThingsWeaponStyle(S: LongInt): Boolean;
begin
  Result := ((S >= 4) and (S <= 14)) or ((S >= 24) and (S <= 26));
end;

function U32(P: PByte; O: LongInt): LongWord;
begin
  Result := PLongWord(PtrUInt(P) + PtrUInt(O))^;
end;

function SigWords(const S: AnsiString): TWordArr;
var
  i, n: LongInt;
  Tok: AnsiString;
begin
  Result := nil;
  i := 1;
  while i < Length(S) do
  begin
    if S[i] = ' ' then
    begin
      Inc(i);
      Continue;
    end;
    Tok := Copy(S, i, 2);
    n := Length(Result);
    SetLength(Result, n + 1);
    if Tok = '??' then
      Result[n] := $100
    else
      Result[n] := Word(StrToInt('$' + Tok));
    Inc(i, 2);
  end;
end;

function ThingsSigMatches(P: PByte; const Pat: AnsiString): Boolean;
var
  W: TWordArr;
  k: LongInt;
begin
  W := SigWords(Pat);
  Result := Length(W) > 0;
  for k := 0 to High(W) do
    if W[k] < $100 then
      if P[k] <> W[k] then
      begin
        Result := False;
        Exit;
      end;
end;

function ThingsParseInit(P: PByte; out L: TThLayout): Boolean;
var
  S, A, B, C, H, O, T, K: LongWord;
  k2: LongInt;
const
  Imul: array[0..6] of LongInt = (3, 17, 36, 52, 66, 85, 102);
begin
  FillChar(L, SizeOf(L), 0);
  Result := False;
  S := U32(P, 3);
  { the seven stores use the same imul by the record's size }
  for k2 := 1 to 6 do
    if U32(P, Imul[k2]) <> S then
      Exit;
  A := U32(P, 9);
  B := U32(P, 29);
  C := U32(P, 45);
  H := U32(P, 58);
  O := U32(P, 78);
  T := U32(P, 91);
  K := U32(P, 108);
  if (S < 1000) or (S > 200000) then
    Exit;
  if (B <> A + 1) or (C <> A + 2) or (O <> A + 3) then
    Exit;
  if (H < A + 4) or (H > A + 60) or (T < A + 8) or (T > A + 60) or (K < T + 4) or (K > A + 400) then
    Exit;
  if (A < $10000) or (A > $FFFFFFFF - 200 * S) then
    Exit;
  L.Found := True;
  L.Base := A;
  L.Size := S;
  L.OffStyle := 1;
  L.OffHold := H - A;
  L.OffOwner := 3;
  L.OffTime := T - A;
  L.OffSkel := K - A;
  L.OffPos := L.OffSkel + TH_POS_AFTER_SKEL;
  Result := L.OffPos + 8 < L.Size;
  if not Result then
    L.Found := False;
end;

function ThingsParseSnap(P: PByte; const L: TThLayout): Boolean;
begin
  Result := False;
  if not L.Found then
    Exit;
  Result := (U32(P, 15) = LongWord(L.Size)) and (U32(P, 21) = LongWord(L.Base + PtrUInt(L.OffStyle)));
end;

procedure Find;
var
  A: PtrUInt;
  L: TThLayout;
begin
  if Tried then
    Exit;
  Tried := True;
  Lay.Found := False;
  SnapProc := nil;
  A := FindCodeW(SigWords(TH_INIT_SIG));
  if A = 0 then
  begin
    Why := 'the sequence of stores in CreateThing was not found (another server build?)';
    Exit;
  end;
  if not ThingsParseInit(PByte(A), L) then
  begin
    Why := 'CreateThing is laid out differently than expected';
    Exit;
  end;
  Lay := L;
  A := FindCodeW(SigWords(TH_SNAP_SIG));
  if A = 0 then
    SnapNote := 'the server''s resend (ServerThingMustSnapshot) was not found'
  else if not ThingsParseSnap(PByte(A), Lay) then
    SnapNote := 'the server''s resend does not match the table'
  else
  begin
    SnapProc := TSnapProc(Pointer(A));
    SnapNote := '';
  end;
end;

{ record I: the address when its first 64 bytes and its position lie in the server's data }
function RecAddr(I: LongInt): PtrUInt;
begin
  Result := 0;
  if not Lay.Found then
    Exit;
  if (I < 1) or (I > TH_N) then
    Exit;
  Result := PtrUInt(PtrInt(Lay.Base) + I * Lay.Size);
  if not Unchecked then
    if not (ExeData(Result, 64) and ExeData(Result + PtrUInt(Lay.OffPos), 8)) then
      Result := 0;
end;

function BridgeUsable: Boolean;
begin
  Result := Lay.Found and (SnapProc <> nil) and Verified and (not Refused);
end;

function BridgeFailed: Boolean;
begin
  Result := Tried and ((not Lay.Found) or (SnapProc = nil) or Refused);
end;

function ThingsMethodNow: LongInt;
begin
  Result := 0;
  case CfgMethod of
    2: Result := 2;
    1: if BridgeUsable then
         Result := 1;
  else
    if BridgeUsable then
      Result := 1
    else if BridgeFailed then
      Result := 2;
  end;
end;

function ThingsState: LongInt;
begin
  if not Tried then
    Result := 0
  else if not Lay.Found then
    Result := 4
  else if Refused then
    Result := 3
  else if BridgeUsable then
    Result := 2
  else if SnapProc = nil then
    Result := 4
  else
    Result := 1;
end;

procedure Refuse(const What: AnsiString);
begin
  if not Refused then
  begin
    Refused := True;
    Why := What;
  end;
end;

{ the script's view of object I against the memory }
procedure CheckRecord(I, Active, Style: LongInt; X, Y: Single);
var
  a: PtrUInt;
  MX, MY: Single;
begin
  a := RecAddr(I);
  if a = 0 then
  begin
    Refuse('record ' + IntToStr(I) + ' is outside the server''s data');
    Exit;
  end;
  if PByte(a)^ > 1 then
  begin
    Refuse('record ' + IntToStr(I) + ': Active is ' + IntToStr(PByte(a)^));
    Exit;
  end;
  if (PByte(a)^ = 1) <> (Active <> 0) then
  begin
    Refuse('record ' + IntToStr(I) + ': Active is ' + IntToStr(PByte(a)^) + ', ScriptCore says ' + IntToStr(Active));
    Exit;
  end;
  if Active = 0 then
    Exit;
  if PByte(a + PtrUInt(Lay.OffStyle))^ <> Style then
  begin
    Refuse('record ' + IntToStr(I) + ': Style is ' + IntToStr(PByte(a + PtrUInt(Lay.OffStyle))^) +
      ', ScriptCore says ' + IntToStr(Style));
    Exit;
  end;
  MX := PSingle(a + PtrUInt(Lay.OffPos))^;
  MY := PSingle(a + PtrUInt(Lay.OffPos) + 4)^;
  if (Abs(MX - X) > 0.01) or (Abs(MY - Y) > 0.01) then
  begin
    Refuse('record ' + IntToStr(I) + ': position differs from ScriptCore''s');
    Exit;
  end;
  Inc(Proofs);
  if not Verified then
    Verified := True;
end;

{ ---------------- tracking ---------------- }

procedure ThingsMade(Slot, Style, Tick: LongInt);
begin
  if (Slot < 1) or (Slot > TH_N) then
    Exit;
  MadeTick[Slot] := Tick;
  MadeStyle[Slot] := Style;
  { a new object in the slot: what was tracked there is gone }
  Track[Slot].Used := False;
end;

procedure TrackSeen(I, Active, Style: LongInt; X, Y: Single);
var
  Born: LongInt;
  Known: Boolean;
begin
  if (Active = 0) or (not ThingsWeaponStyle(Style)) then
  begin
    Track[I].Used := False;
    MadeTick[I] := 0;
    Exit;
  end;
  if Track[I].Used and (Track[I].Style = Style) then
  begin
    Track[I].X := X;
    Track[I].Y := Y;
    Exit;
  end;
  Born := PassTick;
  Known := False;
  if (MadeTick[I] > 0) and (MadeStyle[I] = Style) and (PassTick - MadeTick[I] >= -2) and (PassTick - MadeTick[I] <= 120) then
  begin
    Born := MadeTick[I];
    Known := True;
  end;
  MadeTick[I] := 0;
  Track[I].Used := True;
  Track[I].Style := Style;
  Track[I].Born := Born;
  Track[I].Anchor := Born;
  Track[I].Capped := False;
  Track[I].Known := Known;
  Track[I].Written := False;
  Track[I].X := X;
  Track[I].Y := Y;
  { only a weapon dropped while the keeper is on is kept: one that lay there before (a drop before the
    keeper was armed, or one this pass is the first to see) runs out its own time }
  Track[I].Released := (not IsArmed) or (Born < ArmedSince) or ((not Known) and (Born <= ArmedSince));
  if Track[I].Released then
    Inc(StReleased);
end;

function ThingsSeen(I, Active, Style: LongInt; X, Y: Single): LongInt;
begin
  Result := 0;
  if (I < 1) or (I > TH_N) then
    Exit;
  try
    Find;
    if Lay.Found and (not Refused) then
      CheckRecord(I, Active, Style, X, Y);
    TrackSeen(I, Active, Style, X, Y);
    if not Refused then
      Result := 1;
  except
    Result := 0;
  end;
end;

procedure ThingsPass(Tick, Armed: LongInt);
var
  i: LongInt;
begin
  PassTick := Tick;
  if Armed <> 0 then
  begin
    if not IsArmed then
    begin
      IsArmed := True;
      ArmedSince := Tick;
    end;
  end
  else
  begin
    if IsArmed then
      for i := 1 to TH_N do
        if Track[i].Used and (not Track[i].Released) then
        begin
          Track[i].Released := True;
          Inc(StReleased);
        end;
    IsArmed := False;
  end;
end;

{ the oldest weapons above KeepMax are not kept }
procedure Rank;
var
  i, n, Over, Oldest: LongInt;
begin
  n := 0;
  for i := 1 to TH_N do
  begin
    Track[i].Capped := False;
    if Track[i].Used and (not Track[i].Released) then
      Inc(n);
  end;
  Over := n - CfgMax;
  while Over > 0 do
  begin
    Oldest := 0;
    for i := 1 to TH_N do
      if Track[i].Used and (not Track[i].Released) and (not Track[i].Capped) then
        if (Oldest = 0) or (Track[i].Born < Track[Oldest].Born) then
          Oldest := i;
    if Oldest = 0 then
      Break;
    Track[Oldest].Capped := True;
    Dec(Over);
  end;
end;

function RefreshOne(I: LongInt): Boolean;
var
  a: PtrUInt;
  T: LongInt;
begin
  Result := False;
  a := RecAddr(I);
  if a = 0 then
  begin
    Inc(StSkipped);
    Exit;
  end;
  { not the weapon we track any more (taken, killed, another object in the slot): nothing is written }
  if (PByte(a)^ <> 1) or (PByte(a + PtrUInt(Lay.OffStyle))^ <> Track[I].Style) then
  begin
    Track[I].Used := False;
    Exit;
  end;
  if PByte(a + PtrUInt(Lay.OffHold))^ <> 0 then
  begin
    Inc(StSkipped);
    Exit;
  end;
  T := PLongInt(a + PtrUInt(Lay.OffTime))^;
  if (T < 1) or (T > TH_GUNTIME) then
  begin
    Inc(StSkipped);
    Exit;
  end;
  if T > TH_REFRESH_BELOW then
    Exit;
  { the first write into a weapon whose drop the hook told: the field has to count down the way a TimeOut does
    (1200 at the drop, one a tick) - the one test of the field's place that only a live weapon can make }
  if (not Track[I].Written) and Track[I].Known then
    if Abs(T - (TH_GUNTIME - (PassTick - Track[I].Born))) > TH_TIME_SLACK then
    begin
      Refuse('the time out of object ' + IntToStr(I) + ' reads ' + IntToStr(T) + ' where about ' +
        IntToStr(TH_GUNTIME - (PassTick - Track[I].Born)) + ' is expected');
      Exit;
    end;
  PLongInt(a + PtrUInt(Lay.OffTime))^ := TH_REFRESH_TO;
  Track[I].Written := True;
  try
    SnapProc(Byte(I));
  except
  end;
  Inc(StRefresh);
  Result := True;
end;

function ThingsKeep: LongInt;
var
  i: LongInt;
begin
  Result := 0;
  try
    if not IsArmed then
      Exit;
    Rank;
    if ThingsMethodNow <> 1 then
      Exit;
    for i := 1 to TH_N do
      if Track[i].Used and (not Track[i].Released) and (not Track[i].Capped) then
      begin
        { a refusal on the way (the time out's place) stops the writing }
        if not BridgeUsable then
          Break;
        if RefreshOne(i) then
          Inc(Result);
      end;
  except
    Result := 0;
  end;
end;

function ThingsDue(From: LongInt): LongInt;
var
  i: LongInt;
begin
  Result := 0;
  if not IsArmed then
    Exit;
  if ThingsMethodNow <> 2 then
    Exit;
  if From < 1 then
    From := 1;
  Rank;
  for i := From to TH_N do
    if Track[i].Used and (not Track[i].Released) and (not Track[i].Capped) then
      if PassTick - Track[i].Anchor >= TH_RENEW_AGE then
      begin
        Result := i;
        DueSlot := i;
        DueTrack := Track[i];
        Exit;
      end;
end;

procedure ThingsRenewed(Old, New: LongInt);
var
  Keep: TTrack;
begin
  if (Old < 1) or (Old > TH_N) or (New < 1) or (New > TH_N) then
    Exit;
  if DueSlot = Old then
    Keep := DueTrack
  else
    Keep := Track[Old];
  DueSlot := 0;
  Track[Old].Used := False;
  MadeTick[New] := 0;
  if not Keep.Used then
    Exit;
  Track[New] := Keep;
  Track[New].Used := True;
  Track[New].Anchor := PassTick;
  Track[New].Capped := False;
  Inc(StRenew);
end;

procedure ThingsShift(N: LongInt);
var
  i: LongInt;
begin
  if N <= 0 then
    Exit;
  for i := 1 to TH_N do
  begin
    Track[i].Born := Track[i].Born + N;
    Track[i].Anchor := Track[i].Anchor + N;
    if MadeTick[i] > 0 then
      MadeTick[i] := MadeTick[i] + N;
  end;
  ArmedSince := ArmedSince + N;
end;

procedure ThingsMap;
var
  i: LongInt;
begin
  for i := 1 to TH_N do
  begin
    Track[i].Used := False;
    MadeTick[i] := 0;
  end;
  { the keeper arms again with the new map's first pass }
  IsArmed := False;
end;

procedure ThingsConfig(Method, MaxKept: LongInt);
begin
  if (Method < 0) or (Method > 2) then
    Method := 0;
  if MaxKept < 1 then
    MaxKept := 1;
  if MaxKept > 80 then
    MaxKept := 80;
  CfgMethod := Method;
  CfgMax := MaxKept;
end;

function ThingsKept: LongInt;
var
  i: LongInt;
begin
  Result := 0;
  for i := 1 to TH_N do
    if Track[i].Used and (not Track[i].Released) and (not Track[i].Capped) then
      Inc(Result);
end;

function ThingsCapped: LongInt;
var
  i: LongInt;
begin
  Result := 0;
  for i := 1 to TH_N do
    if Track[i].Used and (not Track[i].Released) and Track[i].Capped then
      Inc(Result);
end;

function ThingsInfo: AnsiString;
var
  M: AnsiString;
begin
  case ThingsState of
    0: Result := 'not looked for yet';
    1: Result := 'waiting for an object to check the table against';
    2: Result := 'ready (record ' + IntToStr(Lay.Size) + ' bytes at $' + HexStr(Lay.Base, 8) + ', checked on ' +
         IntToStr(Proofs) + ' looks, resend found)';
    3: Result := 'refused (' + Why + ')';
  else
    begin
      if Why <> '' then
        Result := 'not found (' + Why + ')'
      else
        Result := 'not found (' + SnapNote + ')';
    end;
  end;
  case ThingsMethodNow of
    1: M := 'bridge';
    2: M := 'recreate';
  else
    M := 'none';
  end;
  Result := Result + '; method in use: ' + M + '; kept now ' + IntToStr(ThingsKept) + ', over the cap ' +
    IntToStr(ThingsCapped) + ', refreshed ' + IntToStr(StRefresh) + ', made again ' + IntToStr(StRenew) +
    ', let go ' + IntToStr(StReleased);
  if StSkipped > 0 then
    Result := Result + ', skipped ' + IntToStr(StSkipped);
end;

procedure ThingsReset;
var
  i: LongInt;
begin
  Lay.Found := False;
  Lay.Base := 0;
  Lay.Size := 0;
  SnapProc := nil;
  SnapNote := '';
  Tried := False;
  Verified := False;
  Refused := False;
  Why := '';
  Proofs := 0;
  IsArmed := False;
  ArmedSince := 0;
  PassTick := 0;
  DueSlot := 0;
  StRefresh := 0;
  StRenew := 0;
  StSkipped := 0;
  StReleased := 0;
  for i := 1 to TH_N do
  begin
    Track[i].Used := False;
    MadeTick[i] := 0;
  end;
end;

procedure ThingsTestUse(const L: TThLayout; Snap: TSnapProc);
begin
  ThingsReset;
  Lay := L;
  SnapProc := Snap;
  Tried := True;
  Unchecked := True;
end;

initialization
  ThingsReset;
end.
