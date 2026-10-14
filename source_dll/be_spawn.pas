unit be_spawn;

{$mode objfpc}{$H+}
{$Q-}{$IFNDEF BE_CHECKS}{$R-}{$ENDIF}

{ [Spawns] (4.1: the owner's Respawns-Control built in): the players' spawn point layouts of the maps, the
  server's spawn table read from its memory, the check of the points against the map's walls, and the taking
  over of the old script.

  Layouts: a map (its name; looked up in lower case) has a layout of player spawn points - the style (0 no
  team, 1-4 Alpha .. Delta), X, Y. They live in memory; data/spawns.bdb holds all of them and is written whole
  by the worker (SpSerialize; .tmp first, the old file becomes .bak):
    'BESP'  version (UInt32 = 1)  map count (UInt32)
    per map: name length (UInt8), name bytes, point count (UInt16), per point: style (UInt8), X (Int32), Y (Int32)
    CRC32 of everything before it (UInt32)
  all little-endian. A file whose length or CRC does not fit is not taken: the .bak is.

  The old script (Respawns-Control 1.0) kept a layout in a text file data/<map name>, four lines a point:
  true (false = switched off), the style, X, Y; a line that makes no point is skipped alone (its own rule).

  The server's spawn table (Map.SpawnPoints[1..255] of TMapSpawnpoint: Active: Boolean; X, Y, Team: LongInt):
  ScriptCore's Map.Spawns[i] (TScriptActiveSpawnPoint) keeps a pointer to its entry right after its class
  pointer (FSpawnPoint). Two of them, checked against their properties, give the table. It is only read here
  (counts, the nearest point, a free point for a player, the marks, the check against the walls); every change
  goes through ScriptCore.

  Everything runs on the game thread, but the /recompile after a takeover: a thread of its own talks to the
  server's admin port (the server runs an admin's command in its main loop, outside every script). }

interface

const
  SP_SLOTS = 255;
  SP_MAX_POINTS = 255;
  { SpCheck's findings }
  SPC_WALL = 1;
  SPC_FLOOR = 2;
  SPC_CLOSE = 3;
  { SpRecompileState }
  SPR_IDLE = 0;
  SPR_RUNNING = 1;
  SPR_SENT = 2;
  SPR_NO_CONNECTION = -1;
  SPR_REFUSED = -2;
  SPR_RETIRE_FAILED = -3;

{ ---- layouts ---- }
{ the file (or its .bak): the maps read; -1 = no file (an empty store), -2 = neither file could be read }
function SpLoad(const Path: AnsiString): LongInt;
function SpLoadedFrom: AnsiString;
{ the whole store as the file's bytes }
function SpSerialize: AnsiString;
function SpMapCount: LongInt;
function SpMapName(Index: LongInt): AnsiString;
function SpMapPoints(Index: LongInt): LongInt;
{ the layout of a map is the selected one: its points (0 = none); SpPoint and SpSelStyles read it }
function SpSelect(const Map: AnsiString): LongInt;
function SpPoint(K: LongInt; out Style, X, Y: LongInt): Boolean;
{ bit S = the selected layout has points of style S }
function SpSelStyles: LongInt;
{ a new layout for a map: SpBegin, SpAdd for each point, SpCommit (no points = the map's layout goes) }
procedure SpBegin(const Map: AnsiString);
function SpAdd(Style, X, Y: LongInt): Boolean;
function SpCommit: LongInt;
function SpDelete(const Map: AnsiString): Boolean;
{ a layout file of the old script read into the pending points (SpBegin first): the points; Skipped = the
  lines that made no point }
function SpParseText(const Text: AnsiString; out Skipped: LongInt): LongInt;
{ every layout file of a folder (the old script's data/): Maps taken, Kept = maps that had a layout here already
  (they keep it), Points, Skipped lines, Bad = files not read; False = the folder could not be read }
function SpImportDir(const Dir: AnsiString; out Maps, Kept, Points, Skipped, Bad: LongInt): Boolean;
{ a layout as the old script's text (four lines a point) }
function SpLayoutText(Index: LongInt): AnsiString;

{ ---- the old script ---- }
{ the folder of Respawns-Control in ScriptsDir (its config.ini says Name = Respawn_Controls, or a folder called
  respawn*control* whose main.pas is that unit), not OwnDir; '' = none }
function SpFindOld(const ScriptsDir, OwnDir: AnsiString): AnsiString;
{ the old folder out of the scripts: moved to ImportedDir/<name>-<date> (Dest) or deleted; False = it stays }
function SpRetire(const Folder, ScriptsDir, ImportedDir: AnsiString; DeleteIt: Boolean; out Dest: AnsiString): Boolean;
{ where the last folder went (from either thread): its new place, or 'deleted ...'; '' = none yet }
function SpRetiredInfo: AnsiString;
{ /recompile through the server's admin port (a thread of its own; SpRecompileState tells how it went). Folder
  (when given) leaves the scripts (SpRetire) right after the port took the password and before /recompile is sent
  - not at all when the port cannot be reached, refuses or the folder cannot go (SPR_RETIRE_FAILED, no recompile).
  The connection stays open until SpRecompileDone (the first tick of the scripts started again) or 2 minutes: 2.8.2
  tells the scripts of an admin's end from that connection's own thread, and in the middle of a recompile that
  crashes the server. }
procedure SpRecompile(const Host: AnsiString; Port: LongInt; const Password, Folder, ScriptsDir,
  ImportedDir: AnsiString; DeleteIt: Boolean);
function SpRecompileState: LongInt;
procedure SpRecompileRefuse;
{ the scripts run again: True when a recompile of SpRecompile was waiting for it or a folder left the scripts
  since the last call }
function SpRecompileDone: Boolean;

{ ---- the server's spawn table ---- }
{ Map.Spawns[1] and [2] with their properties (Active 0/1, X, Y, Style): 1 = the table is known and fits }
function SpBind(Obj1: Pointer; A1, X1, Y1, S1: LongInt; Obj2: Pointer; A2, X2, Y2, S2: LongInt): Boolean;
function SpTableOk: Boolean;
procedure SpTableOff;
{ an entry as the server has it now }
function SpRead(ID: LongInt; out Active: Boolean; out X, Y, Style: LongInt): Boolean;
{ the active player points (styles 0-4) of a style, -1 = all of them }
function SpCount(Style: LongInt): LongInt;
{ the nearest active player point within MaxDist (0 = however far), 0 = none }
function SpNearest(X, Y, MaxDist: Single): LongInt;
{ the first active player point after After (round again after the last), 0 = none }
function SpNext(After: LongInt): LongInt;
{ the points for a round of moves: none taken yet; a random active point of a style - one nobody got in this
  round while there is one (it is taken then), 0 = none of the style }
procedure SpPickReset;
function SpPick(Style: LongInt): LongInt;
{ the N nearest active player points to X, Y within MaxDist (0 = however far; Must always among them when it is
  one): how many; SpNearGet }
function SpNear(X, Y: Single; N, Must: LongInt; MaxDist: Single): LongInt;
function SpNearGet(K: LongInt): LongInt;
{ every active player point against the map's walls (be_map): in a wall, no floor within FloorPx below, closer
  than MinGap to another point of its style. The findings (-1 = the table or the map not known); SpCheckGet }
function SpCheck(FloorPx, MinGap: Single): LongInt;
function SpCheckGet(K: LongInt; out ID, Kind, Other: LongInt; out Value: Single): Boolean;
function SpInfo: AnsiString;

implementation

uses
  {$IFDEF UNIX}BaseUnix,{$ENDIF}
  Classes, SysUtils, sockets, ssockets, be_bridge, be_map;

const
  MAGIC: array[0..3] of AnsiChar = ('B', 'E', 'S', 'P');
  FILE_VERSION = 1;
  MAX_FILE = 4 * 1024 * 1024;
  MAX_TEXT = 1024 * 1024;
  CHECK_MAX = 512;

type
  TSpPoint = record
    Style: Byte;
    X, Y: LongInt;
  end;

  TSpLayout = record
    Key, Name: AnsiString;
    Pts: array of TSpPoint;
  end;

var
  Layouts: array of TSpLayout;
  Sel: LongInt = -1;
  PendMap: AnsiString = '';
  Pend: array of TSpPoint;
  PendN: LongInt = 0;
  LoadedFrom: AnsiString = 'nothing yet';
  CrcTab: array[0..255] of LongWord;
  { the spawn table }
  TabBase: PtrUInt = 0;
  TabStep: LongInt = 0;
  OffX, OffY, OffT: LongInt;
  TabWhy: AnsiString = 'not bound';
  Taken: array[1..SP_SLOTS] of Boolean;
  NearIds: array[0..SP_SLOTS - 1] of LongInt;
  NearN: LongInt = 0;
  ChkId, ChkKind, ChkOther: array[0..CHECK_MAX - 1] of LongInt;
  ChkVal: array[0..CHECK_MAX - 1] of Single;
  ChkN: LongInt = 0;
  { the recompile: how it went, its thread runs (1), the scripts run again (1) }
  RcState: LongInt = SPR_IDLE;
  RcBusy: LongInt = 0;
  RcDone: LongInt = 0;
  { the last folder taken out of the scripts, and whether that is news for the next start of the script }
  RetiredAt: AnsiString = '';
  RetiredNew: LongInt = 0;

{ ---------------- layouts ---------------- }

procedure MakeCrcTab;
var
  i, j: LongInt;
  c: LongWord;
begin
  for i := 0 to 255 do
  begin
    c := LongWord(i);
    for j := 0 to 7 do
      if (c and 1) <> 0 then
        c := $EDB88320 xor (c shr 1)
      else
        c := c shr 1;
    CrcTab[i] := c;
  end;
end;

function Crc32(const S: AnsiString; Len: LongInt): LongWord;
var
  i: LongInt;
begin
  Result := $FFFFFFFF;
  for i := 1 to Len do
    Result := CrcTab[(Result xor Byte(S[i])) and $FF] xor (Result shr 8);
  Result := Result xor $FFFFFFFF;
end;

function FindKey(const Key: AnsiString): LongInt;
var
  i: LongInt;
begin
  for i := 0 to High(Layouts) do
    if Layouts[i].Key = Key then
      Exit(i);
  Result := -1;
end;

function KeyOf(const Map: AnsiString): AnsiString;
begin
  Result := LowerCase(Trim(Map));
end;

{ a map's layout set (no points: it goes); the list stays sorted by key }
procedure PutLayout(const Map: AnsiString; const P: array of TSpPoint; N: LongInt);
var
  i, k, At: LongInt;
  Key: AnsiString;
begin
  Key := KeyOf(Map);
  if Key = '' then
    Exit;
  i := FindKey(Key);
  if N <= 0 then
  begin
    if i < 0 then
      Exit;
    for k := i to High(Layouts) - 1 do
      Layouts[k] := Layouts[k + 1];
    SetLength(Layouts, Length(Layouts) - 1);
    Sel := -1;
    Exit;
  end;
  if i < 0 then
  begin
    At := 0;
    while (At < Length(Layouts)) and (Layouts[At].Key < Key) do
      Inc(At);
    SetLength(Layouts, Length(Layouts) + 1);
    for k := High(Layouts) downto At + 1 do
      Layouts[k] := Layouts[k - 1];
    i := At;
    Layouts[i].Key := Key;
    Sel := -1;
  end;
  Layouts[i].Name := Trim(Map);
  SetLength(Layouts[i].Pts, N);
  for k := 0 to N - 1 do
    Layouts[i].Pts[k] := P[k];
end;

function RdU32(const S: AnsiString; var P: LongInt; out V: LongWord): Boolean;
begin
  Result := P + 3 <= Length(S);
  if not Result then
    Exit;
  V := LongWord(Byte(S[P])) or (LongWord(Byte(S[P + 1])) shl 8) or (LongWord(Byte(S[P + 2])) shl 16) or
    (LongWord(Byte(S[P + 3])) shl 24);
  Inc(P, 4);
end;

function ParseFile(const S: AnsiString): Boolean;
var
  P, i, k, NameLen, Count: LongInt;
  V, Maps, Crc: LongWord;
  Name: AnsiString;
  Pts: array of TSpPoint;
begin
  Result := False;
  if (Length(S) < 16) or (Copy(S, 1, 4) <> MAGIC) then
    Exit;
  P := Length(S) - 3;
  if not RdU32(S, P, Crc) then
    Exit;
  if Crc <> Crc32(S, Length(S) - 4) then
    Exit;
  P := 5;
  if not RdU32(S, P, V) or (V <> FILE_VERSION) then
    Exit;
  if not RdU32(S, P, Maps) or (Maps > 100000) then
    Exit;
  SetLength(Layouts, 0);
  Sel := -1;
  for i := 1 to LongInt(Maps) do
  begin
    if P > Length(S) - 4 then
      Exit;
    NameLen := Byte(S[P]);
    Inc(P);
    if (NameLen = 0) or (P + NameLen + 1 > Length(S) - 4) then
      Exit;
    Name := Copy(S, P, NameLen);
    Inc(P, NameLen);
    Count := Byte(S[P]) or (Byte(S[P + 1]) shl 8);
    Inc(P, 2);
    if (Count > SP_MAX_POINTS) or (P + Count * 9 > Length(S) - 3) then
      Exit;
    SetLength(Pts, Count);
    for k := 0 to Count - 1 do
    begin
      Pts[k].Style := Byte(S[P]);
      Inc(P);
      RdU32(S, P, V);
      Pts[k].X := LongInt(V);
      RdU32(S, P, V);
      Pts[k].Y := LongInt(V);
      if Pts[k].Style > 4 then
        Exit;
    end;
    PutLayout(Name, Pts, Count);
  end;
  Result := P = Length(S) - 3;
end;

function ReadWhole(const Path: AnsiString; Max: LongInt; out S: AnsiString): Boolean;
var
  F: TFileStream;
  n: Int64;
begin
  Result := False;
  S := '';
  if not FileExists(Path) then
    Exit;
  try
    F := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
    try
      n := F.Size;
      if (n <= 0) or (n > Max) then
        Exit;
      SetLength(S, n);
      F.ReadBuffer(S[1], n);
      Result := True;
    finally
      F.Free;
    end;
  except
    Result := False;
  end;
end;

procedure PutAside(const Name, Stamp: AnsiString; var Kept: AnsiString);
var
  To_: AnsiString;
  k: LongInt;
begin
  if not FileExists(Name) then
    Exit;
  { a name of its own, also when a file was put aside in the same second }
  To_ := Name + Stamp;
  k := 1;
  while FileExists(To_) do
  begin
    Inc(k);
    To_ := Name + Stamp + '-' + IntToStr(k);
  end;
  if RenameFile(Name, To_) then
    Kept := Kept + ' ' + ExtractFileName(To_);
end;

function SpLoad(const Path: AnsiString): LongInt;
var
  S, Stamp, Kept: AnsiString;
  Seen: Boolean;
begin
  if CrcTab[1] = 0 then
    MakeCrcTab;
  SetLength(Layouts, 0);
  Sel := -1;
  Seen := FileExists(Path) or FileExists(Path + '.bak') or FileExists(Path + '.tmp');
  if ReadWhole(Path, MAX_FILE, S) and ParseFile(S) then
  begin
    LoadedFrom := ExtractFileName(Path);
    Exit(Length(Layouts));
  end;
  { a save cut off between its two renames: the old file is the .bak, the complete new one still the .tmp (its CRC
    tells that it is complete) }
  if ReadWhole(Path + '.tmp', MAX_FILE, S) and ParseFile(S) then
  begin
    LoadedFrom := ExtractFileName(Path) + '.tmp (the last save was cut off before the end)';
    Exit(Length(Layouts));
  end;
  if ReadWhole(Path + '.bak', MAX_FILE, S) and ParseFile(S) then
  begin
    LoadedFrom := ExtractFileName(Path) + '.bak (the file itself could not be read)';
    Exit(Length(Layouts));
  end;
  SetLength(Layouts, 0);
  if Seen then
  begin
    { the next save would delete the .bak and turn the unreadable file into a new .bak, then the next one that as
      well: they are put aside first, never deleted (as players.bdb does) }
    Stamp := '.unread-' + FormatDateTime('yyyymmdd-hhnnss', Now);
    Kept := '';
    PutAside(Path, Stamp, Kept);
    PutAside(Path + '.bak', Stamp, Kept);
    PutAside(Path + '.tmp', Stamp, Kept);
    LoadedFrom := 'neither ' + ExtractFileName(Path) + ' nor its .bak could be read';
    if Kept <> '' then
      LoadedFrom := LoadedFrom + ' (put aside as' + Kept + ')';
    Result := -2;
  end
  else
  begin
    LoadedFrom := 'no file yet';
    Result := -1;
  end;
end;

function SpLoadedFrom: AnsiString;
begin
  Result := LoadedFrom;
end;

procedure PutU32(var S: AnsiString; V: LongWord);
begin
  S := S + AnsiChar(V and $FF) + AnsiChar((V shr 8) and $FF) + AnsiChar((V shr 16) and $FF) +
    AnsiChar((V shr 24) and $FF);
end;

function SpSerialize: AnsiString;
var
  i, k: LongInt;
  Name: AnsiString;
begin
  if CrcTab[1] = 0 then
    MakeCrcTab;
  Result := MAGIC;
  PutU32(Result, FILE_VERSION);
  PutU32(Result, Length(Layouts));
  for i := 0 to High(Layouts) do
  begin
    Name := Copy(Layouts[i].Name, 1, 255);
    Result := Result + AnsiChar(Length(Name)) + Name;
    Result := Result + AnsiChar(Length(Layouts[i].Pts) and $FF) + AnsiChar(Length(Layouts[i].Pts) shr 8);
    for k := 0 to High(Layouts[i].Pts) do
    begin
      Result := Result + AnsiChar(Layouts[i].Pts[k].Style);
      PutU32(Result, LongWord(Layouts[i].Pts[k].X));
      PutU32(Result, LongWord(Layouts[i].Pts[k].Y));
    end;
  end;
  PutU32(Result, Crc32(Result, Length(Result)));
end;

function SpMapCount: LongInt;
begin
  Result := Length(Layouts);
end;

function SpMapName(Index: LongInt): AnsiString;
begin
  Result := '';
  if (Index >= 0) and (Index <= High(Layouts)) then
    Result := Layouts[Index].Name;
end;

function SpMapPoints(Index: LongInt): LongInt;
begin
  Result := 0;
  if (Index >= 0) and (Index <= High(Layouts)) then
    Result := Length(Layouts[Index].Pts);
end;

function SpSelect(const Map: AnsiString): LongInt;
begin
  Sel := FindKey(KeyOf(Map));
  if Sel >= 0 then
    Result := Length(Layouts[Sel].Pts)
  else
    Result := 0;
end;

function SpPoint(K: LongInt; out Style, X, Y: LongInt): Boolean;
begin
  Result := False;
  Style := 0;
  X := 0;
  Y := 0;
  if (Sel < 0) or (Sel > High(Layouts)) then
    Exit;
  if (K < 0) or (K > High(Layouts[Sel].Pts)) then
    Exit;
  Style := Layouts[Sel].Pts[K].Style;
  X := Layouts[Sel].Pts[K].X;
  Y := Layouts[Sel].Pts[K].Y;
  Result := True;
end;

function SpSelStyles: LongInt;
var
  k: LongInt;
begin
  Result := 0;
  if (Sel < 0) or (Sel > High(Layouts)) then
    Exit;
  for k := 0 to High(Layouts[Sel].Pts) do
    Result := Result or (1 shl Layouts[Sel].Pts[k].Style);
end;

procedure SpBegin(const Map: AnsiString);
begin
  PendMap := Map;
  PendN := 0;
  SetLength(Pend, SP_MAX_POINTS);
end;

function SpAdd(Style, X, Y: LongInt): Boolean;
begin
  Result := False;
  if (Style < 0) or (Style > 4) or (PendN >= SP_MAX_POINTS) then
    Exit;
  if Length(Pend) < SP_MAX_POINTS then
    SetLength(Pend, SP_MAX_POINTS);
  Pend[PendN].Style := Style;
  Pend[PendN].X := X;
  Pend[PendN].Y := Y;
  Inc(PendN);
  Result := True;
end;

function SpCommit: LongInt;
begin
  Result := PendN;
  PutLayout(PendMap, Pend, PendN);
  PendN := 0;
  PendMap := '';
end;

function SpDelete(const Map: AnsiString): Boolean;
begin
  Result := FindKey(KeyOf(Map)) >= 0;
  if Result then
    PutLayout(Map, Pend, 0);
end;

{ a whole number (StrToIntDef answers its default only for something else) }
function IsNumber(const T: AnsiString): Boolean;
begin
  Result := StrToIntDef(T, 1) = StrToIntDef(T, 2);
end;

function SpParseText(const Text: AnsiString; out Skipped: LongInt): LongInt;
var
  L: TStringList;
  i, Style: LongInt;
  Flag: AnsiString;
begin
  Result := 0;
  Skipped := 0;
  L := TStringList.Create;
  try
    L.Text := Text;
    i := 0;
    while i < L.Count do
    begin
      Flag := LowerCase(Trim(L[i]));
      Style := -1;
      if i + 3 < L.Count then
        if IsNumber(Trim(L[i + 2])) and IsNumber(Trim(L[i + 3])) then
          Style := StrToIntDef(Trim(L[i + 1]), -1);
      if (Style < 0) or (Style > 4) then
        Flag := '';
      if Flag = 'true' then
      begin
        if SpAdd(Style, StrToIntDef(Trim(L[i + 2]), 0), StrToIntDef(Trim(L[i + 3]), 0)) then
          Inc(Result);
        Inc(i, 4);
      end
      else if Flag = 'false' then
        Inc(i, 4)
      else
      begin
        Inc(Skipped);
        Inc(i);
      end;
    end;
  finally
    L.Free;
  end;
end;

function SpImportDir(const Dir: AnsiString; out Maps, Kept, Points, Skipped, Bad: LongInt): Boolean;
var
  SR: TSearchRec;
  D, Text: AnsiString;
  n, s: LongInt;
begin
  Result := False;
  Maps := 0;
  Kept := 0;
  Points := 0;
  Skipped := 0;
  Bad := 0;
  D := IncludeTrailingPathDelimiter(Dir);
  if not DirectoryExists(D) then
    Exit;
  Result := True;
  if FindFirst(D + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') or ((SR.Attr and faDirectory) <> 0) then
        Continue;
      if not ReadWhole(D + SR.Name, MAX_TEXT, Text) then
      begin
        Inc(Bad);
        Continue;
      end;
      if FindKey(KeyOf(SR.Name)) >= 0 then
      begin
        Inc(Kept);
        Continue;
      end;
      SpBegin(SR.Name);
      n := SpParseText(Text, s);
      Inc(Skipped, s);
      if n > 0 then
      begin
        SpCommit;
        Inc(Maps);
        Inc(Points, n);
      end
      else
      begin
        PendN := 0;
        Inc(Bad);
      end;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

function SpLayoutText(Index: LongInt): AnsiString;
var
  k: LongInt;
begin
  Result := '';
  if (Index < 0) or (Index > High(Layouts)) then
    Exit;
  for k := 0 to High(Layouts[Index].Pts) do
    Result := Result + 'true' + LineEnding + IntToStr(Layouts[Index].Pts[k].Style) + LineEnding +
      IntToStr(Layouts[Index].Pts[k].X) + LineEnding + IntToStr(Layouts[Index].Pts[k].Y) + LineEnding;
end;

{ ---------------- the old script ---------------- }

function ConfigName(const Folder: AnsiString): AnsiString;
var
  L: TStringList;
  i, p: LongInt;
  T, InSec: AnsiString;
begin
  Result := '';
  if not FileExists(Folder + 'config.ini') then
    Exit;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(Folder + 'config.ini');
    except
      Exit;
    end;
    InSec := '';
    for i := 0 to L.Count - 1 do
    begin
      T := Trim(L[i]);
      if (T <> '') and (T[1] = '[') then
      begin
        InSec := LowerCase(T);
        Continue;
      end;
      p := Pos('=', T);
      if (p > 0) and (InSec = '[config]') then
        if LowerCase(Trim(Copy(T, 1, p - 1))) = 'name' then
        begin
          Result := Trim(Copy(T, p + 1, Length(T)));
          Exit;
        end;
    end;
  finally
    L.Free;
  end;
end;

function MainIsRespawn(const Folder: AnsiString): Boolean;
var
  S: AnsiString;
begin
  Result := False;
  if ReadWhole(Folder + 'main.pas', MAX_TEXT, S) then
    Result := Pos('unit respawn_controls', LowerCase(S)) > 0;
end;

function SameFolder(const A, B: AnsiString): Boolean;
begin
  Result := LowerCase(ExpandFileName(ExcludeTrailingPathDelimiter(SetDirSeparators(A)))) =
    LowerCase(ExpandFileName(ExcludeTrailingPathDelimiter(SetDirSeparators(B))));
end;

function SpFindOld(const ScriptsDir, OwnDir: AnsiString): AnsiString;
var
  SR: TSearchRec;
  D, F, Low: AnsiString;
begin
  Result := '';
  D := IncludeTrailingPathDelimiter(ScriptsDir);
  if FindFirst(D + '*', faDirectory, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') or ((SR.Attr and faDirectory) = 0) then
        Continue;
      F := D + SR.Name + DirectorySeparator;
      if SameFolder(F, OwnDir) then
        Continue;
      Low := LowerCase(SR.Name);
      if LowerCase(ConfigName(F)) = 'respawn_controls' then
        Result := F
      else if (Pos('respawn', Low) > 0) and (Pos('control', Low) > 0) and MainIsRespawn(F) then
        Result := F;
      if Result <> '' then
        Exit;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

{ faSymLink exists on every platform, the compiler only warns that its value differs }
{$push}
{$warn 5044 off}

{ True when Path is itself a symbolic link (on Windows also a junction), not what it points to }
function IsLink(const Path: AnsiString): Boolean;
var
  SR: TSearchRec;
begin
  Result := False;
  if FindFirst(ExcludeTrailingPathDelimiter(Path), faAnyFile or faSymLink, SR) = 0 then
  begin
    Result := (SR.Attr and faSymLink) <> 0;
    FindClose(SR);
  end;
end;

{ removes the link itself, never what it points to (Unix: unlink; a folder junction on Windows: RemoveDir) }
function RemoveLink(const Path: AnsiString): Boolean;
begin
  Result := SysUtils.DeleteFile(Path);
  if not Result then
    Result := RemoveDir(Path);
end;

{ a link inside the tree is removed and not entered (faSymLink in the search makes Unix look at the link itself) }
function DeleteTree(const Dir: AnsiString): Boolean;
var
  SR: TSearchRec;
  D: AnsiString;
begin
  D := IncludeTrailingPathDelimiter(Dir);
  if FindFirst(D + '*', faAnyFile or faSymLink, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then
        Continue;
      if (SR.Attr and faSymLink) <> 0 then
        RemoveLink(D + SR.Name)
      else if (SR.Attr and faDirectory) <> 0 then
        DeleteTree(D + SR.Name)
      else
      begin
        { git keeps its objects read-only }
        {$IFDEF WINDOWS}FileSetAttr(D + SR.Name, 0);{$ENDIF}
        SysUtils.DeleteFile(D + SR.Name);
      end;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  Result := RemoveDir(ExcludeTrailingPathDelimiter(D));
end;

{$pop}

function SpRetire(const Folder, ScriptsDir, ImportedDir: AnsiString; DeleteIt: Boolean; out Dest: AnsiString): Boolean;
var
  Src, Name, Base: AnsiString;
  k: LongInt;
begin
  Result := False;
  Dest := '';
  Src := ExcludeTrailingPathDelimiter(Folder);
  Name := ExtractFileName(Src);
  { only a folder right in the scripts folder, and never that folder itself ('scripts/..' has the name '..' and the
    scripts folder as its parent) }
  if (Name = '') or (Name = '.') or (Name = '..') or not DirectoryExists(Src) then
    Exit;
  if not SameFolder(ExtractFilePath(Src), ScriptsDir) then
    Exit;
  try
    { a folder that is a link: only the link goes, never what it points to }
    if DeleteIt and IsLink(Src) then
    begin
      Result := RemoveLink(Src);
      if Result then
      begin
        RetiredAt := 'deleted ' + Src + ' (a link: what it pointed to is untouched)';
        RetiredNew := 1;
      end;
      Exit;
    end;
    if not ForceDirectories(ExcludeTrailingPathDelimiter(ImportedDir)) then
      Exit;
    Base := IncludeTrailingPathDelimiter(ImportedDir) + Name + '-' + FormatDateTime('yyyymmdd-hhnnss', Now);
    if DeleteIt then
      Base := Base + '-deleting';
    { a folder of the same name moved in the same second: the next free name }
    Dest := Base;
    k := 1;
    while DirectoryExists(Dest) or FileExists(Dest) do
    begin
      Inc(k);
      Dest := Base + '-' + IntToStr(k);
    end;
    if DeleteIt then
    begin
      { in two steps: the folder is renamed out of the scripts first (all at once: a file in use keeps it where it is
        and nothing is lost), only then its files go; deleting it in place could stop halfway }
      if not RenameFile(Src, Dest) then
      begin
        Dest := '';
        Exit;
      end;
      Result := True;
      RetiredAt := 'deleted ' + Src;
      RetiredNew := 1;
      if not DeleteTree(Dest) then
        RetiredAt := RetiredAt + ' (some files could not be removed, they stay in ' + Dest + ')';
      Dest := '';
      Exit;
    end;
    Result := RenameFile(Src, Dest);
    if Result then
    begin
      RetiredAt := Dest;
      RetiredNew := 1;
    end
    else
      Dest := '';
  except
    Result := False;
  end;
end;

{ ---------------- the recompile ---------------- }

{$IFDEF WINDOWS}
type
  TWsFdSet = record
    fd_count: LongWord;
    fd_array: array[0..63] of PtrUInt;
  end;
  TWsTimeVal = record
    tv_sec, tv_usec: LongInt;
  end;

function WsSelect(nfds: LongInt; readfds, writefds, exceptfds, timeout: Pointer): LongInt; stdcall;
  external 'ws2_32.dll' name 'select';
{$ENDIF}

function WaitReadable(H: PtrInt; Ms: LongInt): Boolean;
{$IFDEF WINDOWS}
var
  S: TWsFdSet;
  T: TWsTimeVal;
begin
  S.fd_count := 1;
  S.fd_array[0] := PtrUInt(H);
  T.tv_sec := Ms div 1000;
  T.tv_usec := (Ms mod 1000) * 1000;
  Result := WsSelect(0, @S, nil, nil, @T) > 0;
end;
{$ELSE}
var
  S: TFDSet;
  T: TTimeVal;
begin
  Result := False;
  if (H < 0) or (H >= FD_MAXFDSET) then
    Exit;
  fpFD_ZERO(S);
  fpFD_SET(H, S);
  T.tv_sec := Ms div 1000;
  T.tv_usec := (Ms mod 1000) * 1000;
  Result := fpSelect(H + 1, @S, nil, nil, @T) > 0;
end;
{$ENDIF}

type
  TRecompiler = class(TThread)
  private
    FHost, FPass, FFolder, FScripts, FImported: AnsiString;
    FPort: LongInt;
    FDelete: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const Host: AnsiString; Port: LongInt; const Pass, Folder, Scripts, Imported: AnsiString;
      DeleteIt: Boolean);
  end;

constructor TRecompiler.Create(const Host: AnsiString; Port: LongInt; const Pass, Folder, Scripts,
  Imported: AnsiString; DeleteIt: Boolean);
begin
  FHost := Host;
  FPort := Port;
  FPass := Pass;
  FFolder := Folder;
  FScripts := Scripts;
  FImported := Imported;
  FDelete := DeleteIt;
  FreeOnTerminate := True;
  inherited Create(False);
end;

{ what the server sends within Ms (one read, at most 1 KB); '' when nothing came }
function ReadSome(S: TInetSocket; Ms: LongInt): AnsiString;
var
  Buf: array[0..1023] of AnsiChar;
  n: LongInt;
begin
  Result := '';
  if not WaitReadable(S.Handle, Ms) then
    Exit;
  n := S.Read(Buf, SizeOf(Buf));
  if n > 0 then
    SetString(Result, PAnsiChar(@Buf[0]), n);
end;

procedure SendLine(S: TInetSocket; const Line: AnsiString);
var
  T: AnsiString;
begin
  T := Line + #13#10;
  S.Write(T[1], Length(T));
end;

procedure TRecompiler.Execute;
var
  S: TInetSocket;
  Got, Part: AnsiString;
  T0: QWord;
  Buf: array[0..1023] of AnsiChar;
  Gone: Boolean;
  Dest: AnsiString;
begin
  S := nil;
  try
    try
      S := TInetSocket.Create(FHost, FPort, 3000);
    except
      RcState := SPR_NO_CONNECTION;
      Exit;
    end;
    {$IFDEF LINUX}S.WriteFlags := MSG_NOSIGNAL;{$ENDIF}
    try
      SendLine(S, FPass);
      { the password is not kept a moment longer than needed }
      FPass := '';
      Got := '';
      T0 := GetTickCount64;
      while (GetTickCount64 - T0 < 3000) and (Pos('welcome', LowerCase(Got)) = 0) and
        (Pos('invalid', LowerCase(Got)) = 0) do
      begin
        Part := ReadSome(S, 300);
        Got := Got + Part;
      end;
      if Pos('welcome', LowerCase(Got)) = 0 then
        RcState := SPR_REFUSED
      { the old folder leaves the scripts now, just before the server looks for them again }
      else if (FFolder <> '') and not SpRetire(FFolder, FScripts, FImported, FDelete, Dest) then
        RcState := SPR_RETIRE_FAILED
      else
      begin
        { a start of the script between SpRecompile and here must not close the connection in the middle of the
          compilation: the sign is cleared just before the command goes }
        RcDone := 0;
        SendLine(S, '/recompile');
        RcState := SPR_SENT;
        { open until the scripts run again (their first tick after the recompile) and a second more, or 2 minutes;
          what the server sends meanwhile (its console lines) is read and dropped }
        Gone := False;
        T0 := GetTickCount64;
        while (RcDone = 0) and (GetTickCount64 - T0 < 120000) do
          if WaitReadable(S.Handle, 200) then
            if S.Read(Buf, SizeOf(Buf)) <= 0 then
            begin
              Gone := True;
              Break;
            end;
        if not Gone then
          Sleep(1000);
      end;
      { a gentle close: no more sending, read until the server closes its side (or 3 s) - a connection reset
        under the 2.8.2 admin server can make it log socket errors in a loop }
      fpShutdown(S.Handle, 1);
      T0 := GetTickCount64;
      while GetTickCount64 - T0 < 3000 do
      begin
        if not WaitReadable(S.Handle, 200) then
          Continue;
        if S.Read(Buf, SizeOf(Buf)) <= 0 then
          Break;
      end;
    except
      if RcState = SPR_RUNNING then
        RcState := SPR_NO_CONNECTION;
    end;
  finally
    FPass := '';
    S.Free;
    RcBusy := 0;
  end;
end;

procedure SpRecompile(const Host: AnsiString; Port: LongInt; const Password, Folder, ScriptsDir,
  ImportedDir: AnsiString; DeleteIt: Boolean);
begin
  if RcBusy <> 0 then
    Exit;
  RcBusy := 1;
  RcDone := 0;
  RcState := SPR_RUNNING;
  try
    TRecompiler.Create(Host, Port, Password, Folder, ScriptsDir, ImportedDir, DeleteIt);
  except
    RcBusy := 0;
    RcState := SPR_NO_CONNECTION;
  end;
end;

{ the library is not pinned: no thread is started and the script is told so (as for a port that cannot be reached) }
procedure SpRecompileRefuse;
begin
  RcState := SPR_NO_CONNECTION;
end;

function SpRecompileState: LongInt;
begin
  Result := RcState;
end;

function SpRecompileDone: Boolean;
begin
  Result := ((RcBusy <> 0) and (RcState = SPR_SENT) and (RcDone = 0)) or (RetiredNew <> 0);
  RcDone := 1;
  RetiredNew := 0;
end;

function SpRetiredInfo: AnsiString;
begin
  Result := RetiredAt;
end;

{ ---------------- the server's spawn table ---------------- }

function ClassIs(Obj: Pointer; const Want: AnsiString): Boolean;
var
  VMT, NameP: Pointer;
begin
  Result := False;
  if PtrUInt(Obj) <= $10000 then
    Exit;
  VMT := PPointer(Obj)^;
  if PtrUInt(VMT) <= $10000 then
    Exit;
  NameP := PPointer(PtrUInt(VMT) + 3 * SizeOf(Pointer))^;
  if PtrUInt(NameP) <= $10000 then
    Exit;
  Result := Pos(Want, PShortString(NameP)^) > 0;
end;

function EntryFits(P: PtrUInt; A, X, Y, S: LongInt): Boolean;
begin
  Result := (PByte(P)^ = Byte(A)) and (PLongInt(P + PtrUInt(OffX))^ = X) and (PLongInt(P + PtrUInt(OffY))^ = Y) and
    (PLongInt(P + PtrUInt(OffT))^ = S);
end;

function SpBind(Obj1: Pointer; A1, X1, Y1, S1: LongInt; Obj2: Pointer; A2, X2, Y2, S2: LongInt): Boolean;
var
  P1, P2: PtrUInt;
  Step: PtrInt;
begin
  Result := False;
  try
    if not (ClassIs(Obj1, 'SpawnPoint') and ClassIs(Obj2, 'SpawnPoint')) then
    begin
      SpTableOff;
      TabWhy := 'Map.Spawns gave no spawn point objects';
      Exit;
    end;
    P1 := PPtrUInt(PtrUInt(Obj1) + SizeOf(Pointer))^;
    P2 := PPtrUInt(PtrUInt(Obj2) + SizeOf(Pointer))^;
    Step := PtrInt(P2) - PtrInt(P1);
    { TMapSpawnpoint: Active (a Boolean), X, Y, Team - 16 bytes, or 13 packed }
    if Step = 16 then
    begin
      OffX := 4;
      OffY := 8;
      OffT := 12;
    end
    else if Step = 13 then
    begin
      OffX := 1;
      OffY := 5;
      OffT := 9;
    end
    else
    begin
      SpTableOff;
      TabWhy := 'the spawn points are ' + IntToStr(Step) + ' bytes apart';
      Exit;
    end;
    if not ExeData(P1 - PtrUInt(Step), Step * (SP_SLOTS + 1)) then
    begin
      SpTableOff;
      TabWhy := 'the table is not in the server''s data';
      Exit;
    end;
    if not (EntryFits(P1, A1, X1, Y1, S1) and EntryFits(P2, A2, X2, Y2, S2)) then
    begin
      SpTableOff;
      TabWhy := 'the table does not say what the properties say';
      Exit;
    end;
    TabStep := Step;
    TabBase := P1 - PtrUInt(Step);
    TabWhy := 'read from the server''s memory';
    Result := True;
  except
    SpTableOff;
    TabWhy := 'error while looking';
    Result := False;
  end;
end;

function SpTableOk: Boolean;
begin
  Result := TabBase <> 0;
end;

procedure SpTableOff;
begin
  TabBase := 0;
  TabStep := 0;
end;

function SpRead(ID: LongInt; out Active: Boolean; out X, Y, Style: LongInt): Boolean;
var
  P: PtrUInt;
begin
  Result := False;
  Active := False;
  X := 0;
  Y := 0;
  Style := 0;
  if (TabBase = 0) or (ID < 1) or (ID > SP_SLOTS) then
    Exit;
  P := TabBase + PtrUInt(ID * TabStep);
  Active := PByte(P)^ <> 0;
  X := PLongInt(P + PtrUInt(OffX))^;
  Y := PLongInt(P + PtrUInt(OffY))^;
  Style := PLongInt(P + PtrUInt(OffT))^;
  Result := True;
end;

{ an active spawn point of a player (styles 0-4: the others are flags and kits) }
function PlayerPoint(ID: LongInt; out X, Y, Style: LongInt): Boolean;
var
  A: Boolean;
begin
  Result := SpRead(ID, A, X, Y, Style) and A and (Style >= 0) and (Style <= 4);
end;

function SpCount(Style: LongInt): LongInt;
var
  i, X, Y, S: LongInt;
begin
  Result := 0;
  for i := 1 to SP_SLOTS do
    if PlayerPoint(i, X, Y, S) then
      if (Style < 0) or (S = Style) then
        Inc(Result);
end;

function SpNearest(X, Y, MaxDist: Single): LongInt;
var
  i, PX, PY, S: LongInt;
  D, Best: Single;
begin
  Result := 0;
  Best := 0;
  for i := 1 to SP_SLOTS do
    if PlayerPoint(i, PX, PY, S) then
    begin
      D := Sqrt(Sqr(PX - X) + Sqr(PY - Y));
      if (MaxDist <= 0) or (D < MaxDist) then
        if (Result = 0) or (D < Best) then
        begin
          Result := i;
          Best := D;
        end;
    end;
end;

function SpNext(After: LongInt): LongInt;
var
  k, ID, X, Y, S: LongInt;
begin
  Result := 0;
  { After is taken round the table once, whatever it is (a loop of After / SP_SLOTS turns would hold the game) }
  if After < 0 then
    After := 0;
  After := After mod SP_SLOTS;
  for k := 1 to SP_SLOTS do
  begin
    ID := After + k;
    if ID > SP_SLOTS then
      Dec(ID, SP_SLOTS);
    if PlayerPoint(ID, X, Y, S) then
      Exit(ID);
  end;
end;

procedure SpPickReset;
begin
  FillChar(Taken, SizeOf(Taken), 0);
end;

function SpPick(Style: LongInt): LongInt;
var
  i, Free, All, k, X, Y, S: LongInt;
begin
  Result := 0;
  Free := 0;
  All := 0;
  for i := 1 to SP_SLOTS do
    if PlayerPoint(i, X, Y, S) and (S = Style) then
    begin
      Inc(All);
      if not Taken[i] then
        Inc(Free);
    end;
  if All = 0 then
    Exit;
  if Free > 0 then
    k := Random(Free)
  else
    k := Random(All);
  for i := 1 to SP_SLOTS do
    if PlayerPoint(i, X, Y, S) and (S = Style) then
      if (Free = 0) or not Taken[i] then
      begin
        if k = 0 then
        begin
          Taken[i] := True;
          Exit(i);
        end;
        Dec(k);
      end;
end;

function SpNear(X, Y: Single; N, Must: LongInt; MaxDist: Single): LongInt;
var
  i, j, k, PX, PY, S, Cnt, Far: LongInt;
  D: array[1..SP_SLOTS] of Single;
  Ids: array[0..SP_SLOTS - 1] of LongInt;
  Have: Boolean;
  T: LongInt;
begin
  NearN := 0;
  Result := 0;
  if N <= 0 then
    Exit;
  if N > SP_SLOTS then
    N := SP_SLOTS;
  Cnt := 0;
  for i := 1 to SP_SLOTS do
    if PlayerPoint(i, PX, PY, S) then
    begin
      D[i] := Sqr(PX - X) + Sqr(PY - Y);
      { a point off the viewer's screen needs no mark }
      if (MaxDist > 0) and (D[i] > Sqr(MaxDist)) then
        Continue;
      Ids[Cnt] := i;
      Inc(Cnt);
    end;
  { the N nearest first (a partial selection: N is small) }
  for k := 0 to Cnt - 1 do
  begin
    if k >= N then
      Break;
    j := k;
    for i := k + 1 to Cnt - 1 do
      if D[Ids[i]] < D[Ids[j]] then
        j := i;
    T := Ids[k];
    Ids[k] := Ids[j];
    Ids[j] := T;
  end;
  if Cnt > N then
    Cnt := N;
  { the point being edited always among them }
  if (Must >= 1) and (Must <= SP_SLOTS) and PlayerPoint(Must, PX, PY, S) then
  begin
    Have := False;
    for k := 0 to Cnt - 1 do
      if Ids[k] = Must then
        Have := True;
    if not Have then
    begin
      if Cnt < N then
        Inc(Cnt);
      Far := Cnt - 1;
      Ids[Far] := Must;
    end;
  end;
  for k := 0 to Cnt - 1 do
    NearIds[k] := Ids[k];
  NearN := Cnt;
  Result := Cnt;
end;

function SpNearGet(K: LongInt): LongInt;
begin
  Result := 0;
  if (K >= 0) and (K < NearN) then
    Result := NearIds[K];
end;

procedure AddFinding(ID, Kind, Other: LongInt; Value: Single);
begin
  if ChkN >= CHECK_MAX then
    Exit;
  ChkId[ChkN] := ID;
  ChkKind[ChkN] := Kind;
  ChkOther[ChkN] := Other;
  ChkVal[ChkN] := Value;
  Inc(ChkN);
end;

function SpCheck(FloorPx, MinGap: Single): LongInt;
var
  i, j, X, Y, S, X2, Y2, S2: LongInt;
  D: Single;
begin
  ChkN := 0;
  Result := -1;
  if (TabBase = 0) or not MapReady then
    Exit;
  for i := 1 to SP_SLOTS do
    if PlayerPoint(i, X, Y, S) then
    begin
      { the point itself in a wall the soldier of its team collides with }
      if MapPointSolid(X, Y, MR_PLAYER, S) then
        AddFinding(i, SPC_WALL, 0, 0)
      { nothing under it within FloorPx: the soldier falls }
      else if not MapRay(X, Y, X, Y + FloorPx, MR_PLAYER, S) then
        AddFinding(i, SPC_FLOOR, 0, FloorPx);
      for j := i + 1 to SP_SLOTS do
        if PlayerPoint(j, X2, Y2, S2) and (S2 = S) then
        begin
          D := Sqrt(Sqr(X2 - X) + Sqr(Y2 - Y));
          if D < MinGap then
            AddFinding(i, SPC_CLOSE, j, D);
        end;
    end;
  Result := ChkN;
end;

function SpCheckGet(K: LongInt; out ID, Kind, Other: LongInt; out Value: Single): Boolean;
begin
  Result := (K >= 0) and (K < ChkN);
  ID := 0;
  Kind := 0;
  Other := 0;
  Value := 0;
  if not Result then
    Exit;
  ID := ChkId[K];
  Kind := ChkKind[K];
  Other := ChkOther[K];
  Value := ChkVal[K];
end;

function SpInfo: AnsiString;
var
  i, n: LongInt;
begin
  n := 0;
  for i := 0 to High(Layouts) do
    Inc(n, Length(Layouts[i].Pts));
  Result := 'spawn layouts ' + IntToStr(Length(Layouts)) + ' maps, ' + IntToStr(n) + ' points (' + LoadedFrom +
    '), spawn table ' + TabWhy;
end;

initialization
  MakeCrcTab;
end.
