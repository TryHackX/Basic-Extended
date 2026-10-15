program test_dll;

{ The built library through its exports, as the script calls them: BE_Init takes over
  players.txt, values go in and out, a log line reaches its file, BE_Shutdown writes the store,
  and a second BE_Init reads it back.
  Usage: test_dll <path of basicext_dll.dll> <scratch folder> }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils, dynlibs;

type
  TInit = function(DataDir: PChar; ApiVersion: LongInt): LongInt; cdecl;
  TProc = procedure; cdecl;
  TStatus = function: PChar; cdecl;
  TCount = function(Key: PChar): LongInt; cdecl;
  TLoad = function(Key: PChar; V: PLongInt): LongInt; cdecl;
  TSave = procedure(Key: PChar; Count: LongInt; V: PLongInt); cdecl;
  TLog = procedure(FileName, Line: PChar); cdecl;
  TBridgeReady = function: LongInt; cdecl;
  TBridgeSetWeapon = function(B, Style, W: LongInt; HitM: Single): LongInt; cdecl;
  TBridgeInfo = function: PChar; cdecl;
  THookInit = function: LongInt; cdecl;
  TAmmoConfig = procedure(Enabled, MagMode, EmptyDrop, PickupFullSet, TrackGround, SawIdleTicks, SawAttackTicks,
    SawAttackDrain: LongInt; LootRadius: Single); cdecl;
  TAmmoSetReserve = procedure(W, Rounds: LongInt); cdecl;
  TAmmoRespawn = procedure(ID, Tick: LongInt); cdecl;
  TAmmoObserve = function(ID, Tick, W, A, SW, SA, Flags: LongInt; X, Y: Single; var Value: LongInt): LongInt; cdecl;
  TAmmoMagCount = function(ID, W: LongInt): LongInt; cdecl;
  TAmmoFormatHud = function(ID, W, Clip: LongInt): PChar; cdecl;

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

var
  H: TLibHandle;
  Init: TInit;
  Shutdown: TProc;
  Status: TStatus;
  Count: TCount;
  Load: TLoad;
  Save: TSave;
  Log: TLog;
  BridgeReady: TBridgeReady;
  BridgeSetWeapon: TBridgeSetWeapon;
  BridgeInfo: TBridgeInfo;
  HookInit: THookInit;
  AmmoConfig: TAmmoConfig;
  AmmoSetReserve: TAmmoSetReserve;
  AmmoRespawn: TAmmoRespawn;
  AmmoObserve: TAmmoObserve;
  AmmoMagCount: TAmmoMagCount;
  AmmoFormatHud: TAmmoFormatHud;
  k, V, Act, T, A, p, q, n: LongInt;
  Dir, LogFile, MainPas, S, Rest, Name, Missing, OldD, NewD: AnsiString;
  DataNote: TStatus;
  L, ML: TStringList;
  Vals: array[0..255] of LongInt;
begin
  if ParamCount < 2 then
  begin
    WriteLn('usage: test_dll <basicext_dll.dll> <scratch folder>');
    Halt(2);
  end;
  Dir := IncludeTrailingPathDelimiter(ParamStr(2)) + 'dlldata' + PathDelim;
  ForceDirectories(Dir);
  { a fresh scratch folder of this test }
  DeleteFile(Dir + 'players.bdb');
  DeleteFile(Dir + 'players.bdb.bak');
  DeleteFile(Dir + 'players.bdb.tmp');
  DeleteFile(Dir + 'players.txt.imported');
  L := TStringList.Create;
  L.Add('S777=1,15,300,180,4,2');
  L.SaveToFile(Dir + 'players.txt');
  L.Free;

  H := LoadLibrary(ParamStr(1));
  Check(H <> NilHandle, 'library loaded');
  if H = NilHandle then
    Halt(1);
  Init := TInit(GetProcAddress(H, 'BE_Init'));
  Shutdown := TProc(GetProcAddress(H, 'BE_Shutdown'));
  Status := TStatus(GetProcAddress(H, 'BE_Status'));
  Count := TCount(GetProcAddress(H, 'BE_Pref_Count'));
  Load := TLoad(GetProcAddress(H, 'BE_Pref_Load'));
  Save := TSave(GetProcAddress(H, 'BE_Pref_Save'));
  Log := TLog(GetProcAddress(H, 'BE_Log'));
  BridgeReady := TBridgeReady(GetProcAddress(H, 'BE_BridgeReady'));
  BridgeSetWeapon := TBridgeSetWeapon(GetProcAddress(H, 'BE_BridgeSetWeapon'));
  BridgeInfo := TBridgeInfo(GetProcAddress(H, 'BE_BridgeInfo'));
  HookInit := THookInit(GetProcAddress(H, 'BE_HookInit'));
  AmmoConfig := TAmmoConfig(GetProcAddress(H, 'BE_AmmoConfig'));
  AmmoSetReserve := TAmmoSetReserve(GetProcAddress(H, 'BE_AmmoSetReserve'));
  AmmoRespawn := TAmmoRespawn(GetProcAddress(H, 'BE_AmmoRespawn'));
  AmmoObserve := TAmmoObserve(GetProcAddress(H, 'BE_AmmoObserve'));
  AmmoMagCount := TAmmoMagCount(GetProcAddress(H, 'BE_AmmoMagCount'));
  AmmoFormatHud := TAmmoFormatHud(GetProcAddress(H, 'BE_AmmoFormatHud'));

  Check(Assigned(Init) and Assigned(Shutdown) and Assigned(Status) and Assigned(Count) and Assigned(Load) and
    Assigned(Save) and Assigned(Log) and Assigned(BridgeReady) and Assigned(BridgeSetWeapon) and
    Assigned(BridgeInfo) and Assigned(HookInit) and Assigned(AmmoConfig) and Assigned(AmmoSetReserve) and
    Assigned(AmmoRespawn) and Assigned(AmmoObserve) and Assigned(AmmoMagCount) and Assigned(AmmoFormatHud),
    'every export found');

  { every library routine the script declares (main.pas next to source_dll) is exported: a missing
    one stops the script from loading }
  MainPas := ExpandFileName('..' + PathDelim + 'main.pas');
  if FileExists(MainPas) then
  begin
    ML := TStringList.Create;
    ML.LoadFromFile(MainPas);
    Missing := '';
    n := 0;
    for k := 0 to ML.Count - 1 do
    begin
      S := ML[k];
      p := Pos('''BE_', S);
      if p > 0 then
      begin
        Rest := Copy(S, p + 1, Length(S));
        q := Pos('@', Rest);
        if q > 1 then
        begin
          Name := Copy(Rest, 1, q - 1);
          Inc(n);
          if GetProcAddress(H, Name) = nil then
            Missing := Missing + ' ' + Name;
        end;
      end;
    end;
    ML.Free;
    Check((n > 0) and (Missing = ''), 'every routine main.pas declares (' + IntToStr(n) + ') is exported' + Missing);
  end
  else
    WriteLn('skip main.pas is not next to source_dll');

  Check(BridgeReady() = 0, 'bridge initially not ready');
  Check(StrPas(BridgeInfo()) = 'not calibrated, weapons set 0, refused 0; soldiers: not used yet; weapons and keys ' +
    'from the properties (not calibrated yet); ping compensation the server''s GetSpriteCollisionPoint was not found',
    'initial bridge info: ' + StrPas(BridgeInfo()));

  Check(Init(PChar(Dir), 99) = -29, 'another API version is refused');
  Check(Init(PChar(Dir), 29) = 29, 'started');
  Check(Count('S777') = 6, 'players.txt taken over');
  Check(FileExists(Dir + 'players.txt.imported'), 'players.txt moved aside');
  FillChar(Vals, SizeOf(Vals), 0);
  Check((Load('S777', @Vals[0]) = 6) and (Vals[2] = 300), 'a value of players.txt');
  Vals[0] := 1;
  Vals[1] := -1;
  Vals[2] := 42;
  Save('S888', 3, @Vals[0]);
  Check(Count('S888') = 3, 'three values written');
  FillChar(Vals, SizeOf(Vals), 0);
  Check((Load('S888', @Vals[0]) = 3) and (Vals[0] = 1) and (Vals[1] = -1) and (Vals[2] = 42), 'read back');
  { the ammunition: a fresh AK-74 (40 rounds) with a reserve of 80 in magazines; the magazine
    emptied, the reload done: one spare magazine left }
  AmmoConfig(1, 1, 1, 0, 1, 4, 2, 4, 45);
  AmmoSetReserve(3, 80);
  AmmoRespawn(1, 0);
  T := 1;
  Act := AmmoObserve(1, T, 3, 40, 0, 12, 1, 100, 100, V);
  Check(StrPas(AmmoFormatHud(1, 3, 40)) = ' | Ammo: 40 [40, 40]', 'a fresh AK-74 with two spare magazines: ' +
    StrPas(AmmoFormatHud(1, 3, 40)));
  A := 40;
  while A > 0 do
  begin
    Dec(A);
    for k := 1 to 10 do
    begin
      Inc(T);
      Act := AmmoObserve(1, T, 3, A, -1, -1, 1, 0, 0, V);
    end;
  end;
  for k := 1 to 100 do
  begin
    Inc(T);
    Act := AmmoObserve(1, T, 3, 0, -1, -1, 1, 0, 0, V);
  end;
  for k := 1 to 20 do
  begin
    Inc(T);
    Act := AmmoObserve(1, T, 3, 40, -1, -1, 1, 0, 0, V);
  end;
  Check(AmmoMagCount(1, 3) = 1, 'the reload took a spare magazine');

  LogFile := Dir + 'logs' + PathDelim + 'test.txt';
  DeleteFile(LogFile);
  Log(PChar(LogFile), 'first line');
  Log(PChar(LogFile), 'second line');
  WriteLn('     status: ', StrPas(Status()));
  Shutdown();

  Check(FileExists(Dir + 'players.bdb'), 'the store is on the disk after BE_Shutdown');
  L := TStringList.Create;
  if FileExists(LogFile) then
    L.LoadFromFile(LogFile);
  Check((L.Count = 2) and (L[1] = 'second line'), 'the log lines are in their file');
  L.Free;

  Check(Init(PChar(Dir), 29) = 29, 'started again');
  FillChar(Vals, SizeOf(Vals), 0);
  Check((Load('S888', @Vals[0]) = 3) and (Vals[2] = 42), 'the value came back from players.bdb');
  Check(Count('S777') = 6, 'and the taken-over one');
  Shutdown();

  { 4.2 (LEAD-01): the data folder of an earlier release is taken over once, entry by entry, never over what is there }
  DataNote := TStatus(GetProcAddress(H, 'BE_DataNote'));
  Check(Assigned(DataNote), 'BE_DataNote exported');
  OldD := Dir + 'olddata' + PathDelim;
  NewD := Dir + 'newdata' + PathDelim;
  DeleteFile(OldD + 'a.txt');
  DeleteFile(OldD + 'b.txt');
  DeleteFile(OldD + 'settings.ini');
  DeleteFile(OldD + 'imported' + PathDelim + 'x' + PathDelim + 'f.txt');
  RemoveDir(OldD + 'imported' + PathDelim + 'x');
  RemoveDir(OldD + 'imported');
  DeleteFile(NewD + 'a.txt');
  DeleteFile(NewD + 'b.txt');
  DeleteFile(NewD + 'imported' + PathDelim + 'x' + PathDelim + 'f.txt');
  RemoveDir(NewD + 'imported' + PathDelim + 'x');
  RemoveDir(NewD + 'imported');
  ForceDirectories(OldD + 'imported' + PathDelim + 'x');
  ForceDirectories(NewD);
  L := TStringList.Create;
  L.Add('old a');
  L.SaveToFile(OldD + 'a.txt');
  L.Clear;
  L.Add('old b');
  L.SaveToFile(OldD + 'b.txt');
  L.SaveToFile(OldD + 'settings.ini');
  L.SaveToFile(OldD + 'imported' + PathDelim + 'x' + PathDelim + 'f.txt');
  L.Clear;
  L.Add('new b');
  L.SaveToFile(NewD + 'b.txt');
  L.Free;
  Check(Init(PChar(NewD + '|' + OldD), 29) = 29, 'started with the data folder of an earlier release');
  Check(FileExists(NewD + 'a.txt') and (not FileExists(OldD + 'a.txt')), 'a file moved');
  Check(FileExists(NewD + 'imported' + PathDelim + 'x' + PathDelim + 'f.txt') and (not DirectoryExists(OldD + 'imported')),
    'a folder moved with its files');
  Check(FileExists(OldD + 'b.txt') and FileExists(NewD + 'b.txt'), 'a name that is in both places: both stay');
  L := TStringList.Create;
  L.LoadFromFile(NewD + 'b.txt');
  Check(L[0] = 'new b', 'and the new one is not touched');
  L.Free;
  Check(FileExists(OldD + 'settings.ini') and (not FileExists(NewD + 'settings.ini')), 'settings.ini stays where it was');
  Check(DirectoryExists(OldD), 'the old folder itself stays (the server makes it at every start)');
  Check((Pos('2 entries moved', StrPas(DataNote())) > 0) and (Pos('1 left', StrPas(DataNote())) > 0),
    'the note says so: ' + StrPas(DataNote()));
  Shutdown();
  Check(Init(PChar(NewD + '|' + OldD), 29) = 29, 'started again');
  Check(Pos('2 entries', StrPas(DataNote())) = 0, 'nothing more to take over: ' + StrPas(DataNote()));
  Shutdown();
  UnloadLibrary(H);
  if Failed > 0 then
  begin
    WriteLn(Failed, ' failed');
    Halt(1);
  end;
  WriteLn('test_dll: all passed');
end.
