program test_spawn;

{ be_spawn ([Spawns], 4.1): the layouts' store (the file, its CRC, the .bak), the old script's text files (its
  own rule for bad lines), a folder of them taken over twice, the text written back, finding and moving the old
  script's folder, the server's spawn table read through fake Map.Spawns objects (counts, the nearest, the
  next, the picks, the nearest marks), the check of the points against a real map's walls, and the /recompile
  through a stand-in for the server's admin port.
    test_spawn [<folder of old layout files> [<map.pms>]] }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes, sockets, be_spawn, be_map;

type
  { a stand-in for ScriptCore's TScriptActiveSpawnPoint: the pointer to the entry right after the class pointer }
  TFakeActiveSpawnPoint = class
    FSpawnPoint: Pointer;
  end;
  TFakeOther = class
    FSpawnPoint: Pointer;
  end;

  TEntry = record
    Active: Boolean;
    Pad: array[0..2] of Byte;
    X, Y, Team: LongInt;
  end;

  { a stand-in for the server's admin port: takes the password (welcome, or "Invalid password." and the end), keeps
    every line after it, and notes when the client's side ended }
  TFakeAdmin = class(TThread)
  private
    FListen: LongInt;
    FPass: AnsiString;
  protected
    procedure Execute; override;
  public
    Port: Word;
    Lines: AnsiString;
    Ended: Boolean;
    EndedAt: QWord;
    constructor Create(const Pass: AnsiString);
  end;

var
  Failed, Passed: LongInt;
  { the server's table: in this program's data, as the server's is in its own }
  Tab: array[0..255] of TEntry;

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

procedure SaveText(const Path, Text: AnsiString);
var
  F: TFileStream;
begin
  F := TFileStream.Create(Path, fmCreate);
  try
    if Text <> '' then
      F.WriteBuffer(Text[1], Length(Text));
  finally
    F.Free;
  end;
end;

function LoadText(const Path: AnsiString): AnsiString;
var
  F: TFileStream;
begin
  Result := '';
  F := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

constructor TFakeAdmin.Create(const Pass: AnsiString);
var
  A: TInetSockAddr;
  L: TSockLen;
begin
  FPass := Pass;
  FListen := fpSocket(AF_INET, SOCK_STREAM, 0);
  FillChar(A, SizeOf(A), 0);
  A.sin_family := AF_INET;
  A.sin_port := 0;
  A.sin_addr := StrToNetAddr('127.0.0.1');
  fpBind(FListen, @A, SizeOf(A));
  fpListen(FListen, 1);
  L := SizeOf(A);
  fpGetSockName(FListen, @A, @L);
  Port := NToHs(A.sin_port);
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TFakeAdmin.Execute;
var
  C, n, p: LongInt;
  Buf: array[0..1023] of AnsiChar;
  Acc, Line, T: AnsiString;
  Authed: Boolean;
begin
  C := fpAccept(FListen, nil, nil);
  CloseSocket(FListen);
  if C < 0 then
    Exit;
  Acc := '';
  Authed := False;
  while True do
  begin
    n := fpRecv(C, @Buf[0], SizeOf(Buf), 0);
    if n <= 0 then
    begin
      EndedAt := GetTickCount64;
      Ended := True;
      Break;
    end;
    SetString(T, PAnsiChar(@Buf[0]), n);
    Acc := Acc + T;
    p := Pos(#10, Acc);
    while p > 0 do
    begin
      Line := Trim(Copy(Acc, 1, p - 1));
      Delete(Acc, 1, p);
      if Authed then
        Lines := Lines + Line + '|'
      else if Line = FPass then
      begin
        Authed := True;
        T := 'Welcome, you are in command of the server now.'#13#10'Server Version: 2.8.2'#13#10;
        fpSend(C, @T[1], Length(T), 0);
      end
      else
      begin
        T := 'Invalid password.'#13#10;
        fpSend(C, @T[1], Length(T), 0);
        CloseSocket(C);
        Exit;
      end;
      p := Pos(#10, Acc);
    end;
  end;
  CloseSocket(C);
end;

{ SpRecompile once the last one's thread has ended: True = started }
function StartRecompile(Port: Word; const Pass, Folder, Scripts, Imported: AnsiString): Boolean;
var
  T0: QWord;
begin
  T0 := GetTickCount64;
  repeat
    SpRecompile('127.0.0.1', Port, Pass, Folder, Scripts, Imported, False);
    Result := SpRecompileState = SPR_RUNNING;
    if not Result then
      Sleep(50);
  until Result or (GetTickCount64 - T0 > 8000);
end;

function WaitState(Wanted: LongInt; Ms: LongInt): Boolean;
var
  T0: QWord;
begin
  T0 := GetTickCount64;
  while (SpRecompileState <> Wanted) and (GetTickCount64 - T0 < QWord(Ms)) do
    Sleep(20);
  Result := SpRecompileState = Wanted;
end;

procedure Put(ID: LongInt; Active: Boolean; X, Y, Team: LongInt);
begin
  Tab[ID].Active := Active;
  Tab[ID].X := X;
  Tab[ID].Y := Y;
  Tab[ID].Team := Team;
end;

procedure DeleteTree(const Dir: AnsiString);
var
  SR: TSearchRec;
  D: AnsiString;
begin
  D := IncludeTrailingPathDelimiter(Dir);
  if FindFirst(D + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then
        Continue;
      if (SR.Attr and faDirectory) <> 0 then
        DeleteTree(D + SR.Name)
      else
        DeleteFile(D + SR.Name);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  RemoveDir(ExcludeTrailingPathDelimiter(D));
end;

var
  Root, Path, S, S2, Old, Dest, Txt, MapFile: AnsiString;
  n, i, k, St, X, Y, Skipped, Maps, Kept, Points, Bad, ID, Kind, Other, Files, Walls, Floors, Close, PolyT: LongInt;
  Val: Single;
  O1, O2: TFakeActiveSpawnPoint;
  O3: TFakeOther;
  Act: Boolean;
  Seen: array[1..255] of Boolean;
  SR: TSearchRec;
  X1, Y1, X2, Y2, X3, Y3: Single;
  Fake: TFakeAdmin;
  T0: QWord;
  Ls: LongInt;
  A: TInetSockAddr;
  L: TSockLen;
begin
  Failed := 0;
  Passed := 0;
  Randomize;
  Root := ExpandFileName('build' + DirectorySeparator + 'test' + DirectorySeparator + 'spawn_tmp') + DirectorySeparator;
  DeleteTree(Root);
  ForceDirectories(Root);

  { ---- the old script's text: its own rule for a line that makes no point ---- }
  SpBegin('ctf_Test');
  n := SpParseText('true'#10'1'#10'100'#10'200'#10'false'#10'2'#10'1'#10'1'#10'junk'#10'true'#10'7'#10'5'#10'5'#10 +
    'TRUE'#13#10'2'#13#10'-40'#13#10'60'#13#10'true'#10'3'#10'x'#10'9'#10, Skipped);
  Check(n = 2, 'two points: a true one of style 1, the false one skipped whole, style 7 no point - ' + IntToStr(n));
  Check(Skipped = 9, 'the lines that made no point, one at a time - ' + IntToStr(Skipped));
  Check(SpCommit = 2, 'committed');
  Check(SpSelect('CTF_test') = 2, 'a map is looked up in any case');
  Check(SpPoint(0, St, X, Y) and (St = 1) and (X = 100) and (Y = 200), 'point 0');
  Check(SpPoint(1, St, X, Y) and (St = 2) and (X = -40) and (Y = 60), 'point 1 (CR LF lines, TRUE in capitals)');
  Check(not SpPoint(2, St, X, Y), 'no point 2');
  Check(SpSelStyles = 6, 'the styles 1 and 2');
  Check(SpSelect('ctf_Other') = 0, 'a map without a layout');

  { ---- the store: the file, its CRC, the .bak ---- }
  SpBegin('ctf_Ash');
  for k := 0 to 41 do
    SpAdd(k mod 5, 100 + k * 10, -50 - k);
  Check(SpCommit = 42, 'a layout of 42 points');
  Check(SpMapCount = 2, 'two maps, sorted: ' + SpMapName(0) + ' ' + SpMapName(1));
  Check((SpMapName(0) = 'ctf_Ash') and (SpMapName(1) = 'ctf_Test') and (SpMapPoints(0) = 42), 'names as given');
  S := SpSerialize;
  Path := Root + 'spawns.bdb';
  SaveText(Path, S);
  SpBegin('ctf_Ash');
  SpCommit;
  Check(SpMapCount = 1, 'a layout without points goes');
  Check(SpLoad(Path) = 2, 'the file read back');
  Check((SpSelect('ctf_ash') = 42) and SpPoint(41, St, X, Y) and (St = 1) and (X = 510) and (Y = -91),
    'every point as it was');
  S2 := S;
  S2[20] := AnsiChar(Byte(S2[20]) xor $FF);
  SaveText(Path, S2);
  SaveText(Path + '.bak', S);
  Check((SpLoad(Path) = 2) and (Pos('.bak', SpLoadedFrom) > 0), 'a damaged file: the .bak is taken - ' + SpLoadedFrom);
  SaveText(Path + '.bak', S2);
  Check((SpLoad(Path) = -2) and (SpMapCount = 0), 'both damaged: an empty store, said so - ' + SpLoadedFrom);
  DeleteFile(Path);
  DeleteFile(Path + '.bak');
  Check(SpLoad(Path) = -1, 'no file yet');
  SaveText(Path, Copy(S, 1, Length(S) - 1));
  Check(SpLoad(Path) = -2, 'a file cut short is not taken');
  SaveText(Path, S);
  Check(SpLoad(Path) = 2, 'the good file again');
  { 4.2 (BD1-04): a save cut off between its renames leaves no file and a complete .tmp }
  DeleteFile(Path);
  DeleteFile(Path + '.bak');
  SaveText(Path + '.tmp', S);
  Check((SpLoad(Path) = 2) and (Pos('.tmp', SpLoadedFrom) > 0), 'no file, a complete .tmp: it is taken - ' + SpLoadedFrom);
  DeleteFile(Path + '.tmp');
  { 4.2 (BE6-08): neither file readable: both are put aside (never deleted), so the next save cannot destroy them }
  S2 := S;
  S2[20] := AnsiChar(Byte(S2[20]) xor $FF);
  SaveText(Path, S2);
  SaveText(Path + '.bak', S2);
  Check(SpLoad(Path) = -2, 'both damaged again');
  Check((not FileExists(Path)) and (not FileExists(Path + '.bak')) and (Pos('put aside', SpLoadedFrom) > 0),
    'both put aside: ' + SpLoadedFrom);
  n := 0;
  if FindFirst(Root + 'spawns.bdb*unread*', faAnyFile, SR) = 0 then
  begin
    repeat
      Inc(n);
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
  Check(n >= 2, 'the unread files are kept: ' + IntToStr(n));
  SaveText(Path, S);
  Check(SpLoad(Path) = 2, 'the good file once more');

  { ---- the old script's folder of layouts, taken over twice ---- }
  Old := '';
  if ParamCount >= 1 then
    Old := IncludeTrailingPathDelimiter(ParamStr(1));
  if (Old <> '') and DirectoryExists(Old) then
  begin
    SpLoad(Root + 'none.bdb');
    { what every file holds, read one by one (nothing kept) }
    Files := 0;
    n := 0;
    if FindFirst(Old + '*', faAnyFile, SR) = 0 then
    try
      repeat
        if (SR.Attr and faDirectory) = 0 then
        begin
          Inc(Files);
          SpBegin('count');
          Inc(n, SpParseText(LoadText(Old + SR.Name), Skipped));
        end;
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
    SpBegin('');
    Check(SpImportDir(Old, Maps, Kept, Points, Skipped, Bad), 'the old folder read');
    Check((Maps = Files) and (Kept = 0) and (Bad = 0),
      Format('every file a layout: %d maps of %d files, %d points', [Maps, Files, Points]));
    Check(Points = n, Format('every point of them: %d of %d', [Points, n]));
    if FileExists(Old + 'ctf_cs_747_f') then
    begin
      Check(SpSelect('ctf_cs_747_f') = 14, 'the owner''s ctf_cs_747_f: 14 points');
      Check(SpPoint(0, St, X, Y) and (St = 0) and (X = 421) and (Y = 475), 'its first point (true 0 421 475)');
    end;
    Check(SpImportDir(Old, Maps, Kept, Points, Skipped, Bad) and (Maps = 0) and (Kept = Files),
      'taken over again: every map keeps the layout it has here');
    { the text written back reads as the same points (the first map's) }
    n := SpMapPoints(0);
    Txt := SpLayoutText(0);
    SpBegin('copy_of_the_first');
    Check((SpParseText(Txt, Skipped) = n) and (Skipped = 0) and (n > 0), 'the text of a layout reads back whole');
    SpCommit;
    Check(SpSelect('copy_of_the_first') = n, 'the copy');
    { the store of all of them through the file }
    S := SpSerialize;
    SaveText(Path, S);
    Check(SpLoad(Path) = Files + 1, 'all of them through the file: ' + IntToStr(Length(S)) + ' bytes');
  end
  else
    WriteLn('note: no folder of old layouts given, that part is left out');

  { ---- finding the old script and moving it out ---- }
  ForceDirectories(Root + 'scripts' + DirectorySeparator + 'Basic-Extended');
  ForceDirectories(Root + 'scripts' + DirectorySeparator + 'Other');
  ForceDirectories(Root + 'scripts' + DirectorySeparator + 'Respawns-Control' + DirectorySeparator + 'data' +
    DirectorySeparator + '.git');
  SaveText(Root + 'scripts' + DirectorySeparator + 'Other' + DirectorySeparator + 'config.ini',
    '[Config]'#13#10'Name = Other'#13#10);
  SaveText(Root + 'scripts' + DirectorySeparator + 'Respawns-Control' + DirectorySeparator + 'config.ini',
    '[Config]'#13#10'Name = Respawn_Controls'#13#10'MainFile = main.pas'#13#10);
  SaveText(Root + 'scripts' + DirectorySeparator + 'Respawns-Control' + DirectorySeparator + 'data' +
    DirectorySeparator + 'ctf_Moon', 'true'#10'1'#10'5'#10'6'#10);
  S := SpFindOld(Root + 'scripts', Root + 'scripts' + DirectorySeparator + 'Basic-Extended');
  Check(S = Root + 'scripts' + DirectorySeparator + 'Respawns-Control' + DirectorySeparator, 'found: ' + S);
  Check(SpFindOld(Root + 'scripts', Root + 'scripts' + DirectorySeparator + 'Respawns-Control') = '',
    'never the own folder');
  Check(not SpRetire(Root + 'scripts' + DirectorySeparator + 'Other', Root + 'elsewhere', Root + 'imported', False,
    Dest), 'a folder that is not in the scripts folder given is never moved');
  Check(SpRetire(S, Root + 'scripts', Root + 'imported', False, Dest) and DirectoryExists(Dest) and
    not DirectoryExists(S) and FileExists(Dest + DirectorySeparator + 'data' + DirectorySeparator + 'ctf_Moon'),
    'moved whole into imported: ' + Dest);
  { the same name again in the same second gets a name of its own }
  ForceDirectories(S);
  S2 := Dest;
  Check(SpRetire(S, Root + 'scripts', Root + 'imported', False, Dest) and DirectoryExists(Dest) and
    DirectoryExists(S2) and (Dest <> S2), 'a second folder of that name: ' + ExtractFileName(Dest));
  Check(SpFindOld(Root + 'scripts', Root + 'scripts' + DirectorySeparator + 'Basic-Extended') = '',
    'gone from the scripts');
  ForceDirectories(Root + 'scripts' + DirectorySeparator + 'respawn_controls_old');
  SaveText(Root + 'scripts' + DirectorySeparator + 'respawn_controls_old' + DirectorySeparator + 'main.pas',
    'unit Respawn_Controls;'#10'interface'#10);
  S := SpFindOld(Root + 'scripts', '');
  Check(Pos('respawn_controls_old', S) > 0, 'found by its folder name and its unit: ' + S);
  Check(SpRetire(S, Root + 'scripts', Root + 'imported', True, Dest) and not DirectoryExists(S), 'deleted');
  { 4.2 (BD1-07): never the scripts folder itself, whatever the name says }
  Check(not SpRetire(Root + 'scripts' + DirectorySeparator + '..', Root + 'scripts', Root + 'imported', True, Dest) and
    DirectoryExists(Root + 'scripts'), 'scripts/.. is never deleted');
  Check(not SpRetire(Root + 'scripts' + DirectorySeparator + '.', Root + 'scripts', Root + 'imported', False, Dest) and
    DirectoryExists(Root + 'scripts' + DirectorySeparator + 'Other'), 'scripts/. is never moved');
  { 4.2 (BD1-01): a delete takes the folder out of the scripts at once and removes the files afterwards }
  ForceDirectories(Root + 'scripts' + DirectorySeparator + 'delme' + DirectorySeparator + 'sub');
  SaveText(Root + 'scripts' + DirectorySeparator + 'delme' + DirectorySeparator + 'sub' + DirectorySeparator + 'b.txt', 'b');
  Check(SpRetire(Root + 'scripts' + DirectorySeparator + 'delme', Root + 'scripts', Root + 'imported', True, Dest) and
    (not DirectoryExists(Root + 'scripts' + DirectorySeparator + 'delme')) and (Pos('deleted', SpRetiredInfo) = 1),
    'delete: gone from the scripts - ' + SpRetiredInfo);
  Check(FindFirst(Root + 'imported' + DirectorySeparator + 'delme-*', faAnyFile, SR) <> 0, 'delete: nothing left in imported');
  FindClose(SR);
  {$IFDEF WINDOWS}
  { a junction inside the folder (and the folder itself as a junction) is removed, never what it points to }
  ForceDirectories(Root + 'outside' + DirectorySeparator + 'sub');
  SaveText(Root + 'outside' + DirectorySeparator + 'precious.txt', 'keep');
  SaveText(Root + 'outside' + DirectorySeparator + 'sub' + DirectorySeparator + 'deep.txt', 'keep');
  ForceDirectories(Root + 'scripts' + DirectorySeparator + 'linked');
  SaveText(Root + 'scripts' + DirectorySeparator + 'linked' + DirectorySeparator + 'config.ini', 'x');
  ExecuteProcess(GetEnvironmentVariable('COMSPEC'), '/c mklink /J "' + Root + 'scripts' + DirectorySeparator +
    'linked' + DirectorySeparator + 'shared" "' + Root + 'outside" > nul');
  ExecuteProcess(GetEnvironmentVariable('COMSPEC'), '/c mklink /J "' + Root + 'scripts' + DirectorySeparator +
    'jlink" "' + Root + 'outside" > nul');
  if DirectoryExists(Root + 'scripts' + DirectorySeparator + 'linked' + DirectorySeparator + 'shared') then
  begin
    Check(SpRetire(Root + 'scripts' + DirectorySeparator + 'linked', Root + 'scripts', Root + 'imported', True, Dest) and
      (not DirectoryExists(Root + 'scripts' + DirectorySeparator + 'linked')), 'a folder with a junction deleted');
    Check(FileExists(Root + 'outside' + DirectorySeparator + 'precious.txt') and
      FileExists(Root + 'outside' + DirectorySeparator + 'sub' + DirectorySeparator + 'deep.txt'),
      'what the junction pointed to is untouched');
  end
  else
    Check(False, 'mklink /J did not make the junction');
  if DirectoryExists(Root + 'scripts' + DirectorySeparator + 'jlink') then
  begin
    Check(SpRetire(Root + 'scripts' + DirectorySeparator + 'jlink', Root + 'scripts', Root + 'imported', True, Dest) and
      (not DirectoryExists(Root + 'scripts' + DirectorySeparator + 'jlink')), 'a folder that is a junction: only the link goes');
    Check(FileExists(Root + 'outside' + DirectorySeparator + 'precious.txt') and
      FileExists(Root + 'outside' + DirectorySeparator + 'sub' + DirectorySeparator + 'deep.txt'),
      'and what it pointed to is untouched');
  end
  else
    Check(False, 'mklink /J did not make the second junction');
  {$ENDIF}

  { ---- the server's spawn table through the script's objects ---- }
  FillChar(Tab, SizeOf(Tab), 0);
  Put(1, True, 100, 100, 1);
  Put(2, True, 200, 100, 1);
  Put(3, True, 900, 100, 2);
  Put(4, False, 150, 100, 1);
  Put(5, True, 160, 100, 7);
  Put(6, True, 300, 400, 0);
  O1 := TFakeActiveSpawnPoint.Create;
  O2 := TFakeActiveSpawnPoint.Create;
  O3 := TFakeOther.Create;
  O1.FSpawnPoint := @Tab[1];
  O2.FSpawnPoint := @Tab[2];
  O3.FSpawnPoint := @Tab[2];
  Check(not SpBind(O1, 1, 100, 100, 1, O3, 1, 200, 100, 1), 'an object of another class is refused');
  Check(not SpBind(O1, 1, 100, 101, 1, O2, 1, 200, 100, 1), 'properties that differ are refused');
  Check(SpBind(O1, 1, 100, 100, 1, O2, 1, 200, 100, 1) and SpTableOk, 'bound');
  Check(SpRead(3, Act, X, Y, St) and Act and (X = 900) and (St = 2), 'an entry read');
  Check((SpCount(-1) = 4) and (SpCount(1) = 2) and (SpCount(2) = 1) and (SpCount(0) = 1),
    'counts: the inactive point and the kit (style 7) are no player points');
  Check(SpNearest(140, 100, 50) = 1, 'the nearest within 50 px (the inactive and the kit left out)');
  Check(SpNearest(600, 100, 50) = 0, 'none within 50 px');
  Check(SpNearest(600, 100, 0) = 3, 'however far');
  Check((SpNext(0) = 1) and (SpNext(1) = 2) and (SpNext(3) = 6) and (SpNext(6) = 1), 'the next ones, round again');
  { 4.2 (BD1-07): any After takes no time }
  T0 := GetTickCount64;
  k := SpNext(2000000000);
  Check((GetTickCount64 - T0 < 100) and (k = SpNext(2000000000 mod 255)), 'a huge After is taken round at once');
  Check((SpNext(255) = SpNext(0)) and (SpNext(-5) = SpNext(0)), 'After of 255 and a negative one');
  SpPickReset;
  i := SpPick(1);
  k := SpPick(1);
  Check((i in [1, 2]) and (k in [1, 2]) and (i <> k), 'two picks of style 1: both points, each once');
  n := SpPick(1);
  Check(n in [1, 2], 'a third pick: one of them again');
  Check(SpPick(3) = 0, 'no point of style 3');
  FillChar(Seen, SizeOf(Seen), 0);
  for k := 1 to 200 do
  begin
    SpPickReset;
    Seen[SpPick(1)] := True;
  end;
  Check(Seen[1] and Seen[2], 'the picks are random');
  n := SpNear(105, 100, 2, 0, 0);
  Check((n = 2) and (SpNearGet(0) = 1) and (SpNearGet(1) = 2), 'the 2 nearest marks');
  n := SpNear(105, 100, 2, 3, 0);
  Check((n = 2) and (SpNearGet(0) = 1) and (SpNearGet(1) = 3), 'the point being edited always among them');
  n := SpNear(105, 100, 10, 0, 150);
  Check((n = 2) and (SpNearGet(0) = 1) and (SpNearGet(1) = 2), 'only the points within 150 px');
  n := SpNear(105, 100, 10, 3, 150);
  Check((n = 3) and (SpNearGet(2) = 3), 'the point being edited however far');
  n := SpNear(105, 100, 10, 0, 0);
  Check(n = 4, 'every player point with no distance given');
  Tab[2].Team := 3;
  Check(SpCount(1) = 1, 'read live: a change of the table is seen at once');
  SpTableOff;
  Check(not SpTableOk and (SpCount(-1) = 0), 'off');

  { ---- the check against the walls of a real map ---- }
  MapFile := '';
  if ParamCount >= 2 then
    MapFile := ParamStr(2);
  if (MapFile <> '') and FileExists(MapFile) and (MapLoad(MapFile) > 0) then
  begin
    FillChar(Tab, SizeOf(Tab), 0);
    Check(SpCheck(80, 8) = -1, 'not bound: no check');
    { a point inside a polygon soldiers collide with, one high above the map, two 3 px apart on the ground }
    Walls := 0;
    for i := 1 to MapPolys do
      if Walls = 0 then
        if MapPolyGet(i, X1, Y1, X2, Y2, X3, Y3, PolyT) then
          if (PolyT = 0) and MapPointSolid((X1 + X2 + X3) / 3, (Y1 + Y2 + Y3) / 3, MR_PLAYER, 0) then
          begin
            Put(1, True, Round((X1 + X2 + X3) / 3), Round((Y1 + Y2 + Y3) / 3), 0);
            Walls := 1;
          end;
    Put(2, True, 0, -100000, 1);
    { the ground: a point a little above a polygon's top found by a ray down }
    Floors := 0;
    for k := -40 to 40 do
      if Floors = 0 then
      begin
        X := k * 50;
        for i := -2000 to 2000 do
          if Floors = 0 then
            if MapRay(X, i * 5 - 5, X, i * 5, MR_PLAYER, 2) and not MapPointSolid(X, i * 5 - 20, MR_PLAYER, 2) and
               not MapRay(X, i * 5 - 25, X, i * 5 - 6, MR_PLAYER, 2) then
            begin
              Put(3, True, X, i * 5 - 10, 2);
              Put(4, True, X + 3, i * 5 - 10, 2);
              Floors := 1;
            end;
      end;
    O1.FSpawnPoint := @Tab[1];
    O2.FSpawnPoint := @Tab[2];
    Check(SpBind(O1, 1, Tab[1].X, Tab[1].Y, 0, O2, 1, 0, -100000, 1), 'bound again');
    n := SpCheck(80, 8);
    Walls := 0;
    Floors := 0;
    Close := 0;
    for k := 0 to n - 1 do
      if SpCheckGet(k, ID, Kind, Other, Val) then
        case Kind of
          SPC_WALL: if ID = 1 then Inc(Walls);
          SPC_FLOOR: if ID = 2 then Inc(Floors);
          SPC_CLOSE: if (ID = 3) and (Other = 4) then Inc(Close);
        end;
    Check(Walls = 1, 'the point in a wall is found');
    Check(Floors = 1, 'the point without a floor is found');
    Check(Close = 1, 'the two points 3 px apart are found');
    Check(n = 3, 'nothing else - ' + IntToStr(n));
  end
  else
    WriteLn('note: no map given, the check against the walls is left out');

  { ---- the takeover's /recompile through a stand-in for the admin port; the old folder leaves the scripts right
    before the command, and only then ---- }
  S := Root + 'scripts' + DirectorySeparator;
  ForceDirectories(S + 'Respawns-Old' + DirectorySeparator + 'data');
  SaveText(S + 'Respawns-Old' + DirectorySeparator + 'data' + DirectorySeparator + 'ctf_X', 'true'#10'1'#10'2'#10'3'#10);
  ForceDirectories(S + 'Respawns-Old2');
  SpRecompileDone;
  Fake := TFakeAdmin.Create('secret');
  Check(StartRecompile(Fake.Port, 'secret', S + 'Respawns-Old' + DirectorySeparator, S, Root + 'imported2' +
    DirectorySeparator), 'the recompile under way');
  Check(WaitState(SPR_SENT, 5000), 'the password taken, /recompile sent');
  Sleep(300);
  Check(Fake.Lines = '/recompile|', 'the admin port got the command alone: ' + Fake.Lines);
  Check(not DirectoryExists(S + 'Respawns-Old') and (Pos('Respawns-Old-', SpRetiredInfo) > 0) and
    FileExists(SpRetiredInfo + DirectorySeparator + 'data' + DirectorySeparator + 'ctf_X'),
    'the old folder went out whole before the command: ' + SpRetiredInfo);
  SpRecompile('127.0.0.1', Fake.Port, 'secret', '', '', '', False);
  Check(SpRecompileState = SPR_SENT, 'no second recompile while the first one waits');
  Sleep(1500);
  Check(not Fake.Ended, 'the connection stays open while the scripts have not run again');
  T0 := GetTickCount64;
  Check(SpRecompileDone, 'the scripts run again: the recompile was waiting for it');
  while (not Fake.Ended) and (GetTickCount64 - T0 < 8000) do
    Sleep(20);
  Check(Fake.Ended and (Fake.EndedAt - T0 >= 900),
    Format('then the connection ends, a second later (%d ms)', [Fake.EndedAt - T0]));
  Check(not SpRecompileDone, 'nothing waits any more');
  Fake.WaitFor;
  Fake.Free;
  Fake := TFakeAdmin.Create('other');
  Check(StartRecompile(Fake.Port, 'secret', S + 'Respawns-Old2' + DirectorySeparator, S, Root + 'imported2' +
    DirectorySeparator), 'a recompile again');
  Check(WaitState(SPR_REFUSED, 6000), 'a wrong password: refused');
  Check(DirectoryExists(S + 'Respawns-Old2'), 'refused: the folder stays');
  Fake.WaitFor;
  Fake.Free;
  Fake := TFakeAdmin.Create('secret');
  Check(StartRecompile(Fake.Port, 'secret', Root + 'Respawns-Elsewhere' + DirectorySeparator, S, Root + 'imported2' +
    DirectorySeparator), 'a recompile with a folder that cannot go');
  Check(WaitState(SPR_RETIRE_FAILED, 6000), 'the folder could not go: no recompile');
  Sleep(300);
  Check(Fake.Lines = '', 'nothing sent after the password');
  Fake.WaitFor;
  Fake.Free;
  Check(not SpRecompileDone, 'and no news of a folder');
  Check(SpRetire(S + 'Respawns-Old2', S, Root + 'imported2', False, Dest) and SpRecompileDone,
    'a folder taken out by the script is news for the next start: ' + SpRetiredInfo);
  { a port nobody listens on }
  Ls := fpSocket(AF_INET, SOCK_STREAM, 0);
  FillChar(A, SizeOf(A), 0);
  A.sin_family := AF_INET;
  A.sin_addr := StrToNetAddr('127.0.0.1');
  fpBind(Ls, @A, SizeOf(A));
  L := SizeOf(A);
  fpGetSockName(Ls, @A, @L);
  CloseSocket(Ls);
  ForceDirectories(S + 'Respawns-Old3');
  Check(StartRecompile(NToHs(A.sin_port), 'secret', S + 'Respawns-Old3' + DirectorySeparator, S, Root + 'imported2' +
    DirectorySeparator), 'and once more');
  Check(WaitState(SPR_NO_CONNECTION, 8000), 'no server on the port: no connection');
  Check(DirectoryExists(S + 'Respawns-Old3'), 'no connection: the folder stays');

  O1.Free;
  O2.Free;
  O3.Free;
  DeleteTree(Root);
  WriteLn(Passed, ' passed, ', Failed, ' failed');
  if Failed > 0 then
    Halt(1);
end.
