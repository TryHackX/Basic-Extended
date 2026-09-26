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
  TGet = function(Key: PChar; Index: LongInt): LongInt; cdecl;
  TBegin = procedure(Key: PChar); cdecl;
  TAdd = procedure(Value: LongInt); cdecl;
  TLog = procedure(FileName, Line: PChar); cdecl;

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
  Shutdown, Commit: TProc;
  Status: TStatus;
  Count: TCount;
  Get: TGet;
  PBegin: TBegin;
  Add: TAdd;
  Log: TLog;
  Dir, LogFile: AnsiString;
  L: TStringList;
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
  Get := TGet(GetProcAddress(H, 'BE_Pref_Get'));
  PBegin := TBegin(GetProcAddress(H, 'BE_Pref_Begin'));
  Add := TAdd(GetProcAddress(H, 'BE_Pref_Add'));
  Commit := TProc(GetProcAddress(H, 'BE_Pref_Commit'));
  Log := TLog(GetProcAddress(H, 'BE_Log'));
  Check(Assigned(Init) and Assigned(Shutdown) and Assigned(Status) and Assigned(Count) and Assigned(Get) and
    Assigned(PBegin) and Assigned(Add) and Assigned(Commit) and Assigned(Log), 'every export found');

  Check(Init(PChar(Dir), 99) = -5, 'another API version is refused');
  Check(Init(PChar(Dir), 5) = 5, 'started');
  Check(Count('S777') = 6, 'players.txt taken over');
  Check(FileExists(Dir + 'players.txt.imported'), 'players.txt moved aside');
  Check(Get('S777', 2) = 300, 'a value of players.txt');
  PBegin('S888');
  Add(1);
  Add(-1);
  Add(42);
  Commit();
  Check(Count('S888') = 3, 'three values written');
  Check(Get('S888', 2) = 42, 'read back');
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

  Check(Init(PChar(Dir), 5) = 5, 'started again');
  Check(Get('S888', 2) = 42, 'the value came back from players.bdb');
  Check(Count('S777') = 6, 'and the taken-over one');
  Shutdown();
  UnloadLibrary(H);
  if Failed > 0 then
  begin
    WriteLn(Failed, ' failed');
    Halt(1);
  end;
  WriteLn('test_dll: all passed');
end.
