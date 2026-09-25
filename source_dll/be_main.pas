library basicext_dll;

{ Basic-Extended native library: the players' store and the log writer.

  Every export uses cdecl, returns at once and never lets an exception reach the caller (the game
  thread of the Soldat server). Reads and writes of the store are lookups in memory; the disk is
  written by one worker thread: the store a moment after a change, the log lines as they come. So
  a slow disk never stops a tick.

  The library pins itself on the first BE_Init: a script reload finds the running worker again
  instead of unloading code under a running thread. BE_Shutdown (the script's finalization) writes
  what is pending and stops the thread; the next BE_Init starts again from the files.

    BE_Init         the script's data folder, BE_API_VERSION of main.pas: BE_API_VERSION when it
                    runs, -BE_API_VERSION when main.pas comes from another release, 0 when it could
                    not start. It reads data/players.bdb; without one, the older data/players.txt is
                    taken over once and moved aside (players.txt.imported).
    BE_Shutdown     writes what is pending, stops the thread
    BE_Status       one line about the store and the writer
    BE_Pref_Count   the number of values kept for a key (0 = none)
    BE_Pref_Get     one of them (0 when there is none)
    BE_Pref_Begin, BE_Pref_Add, BE_Pref_Commit
                    the values of a key are replaced (no values = the key goes)
    BE_Log          a line for a text file (a path relative to the server folder, or absolute) }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  SysUtils, be_store;

const
  BE_API_VERSION = 1;
  GET_MODULE_HANDLE_EX_FLAG_PIN = 1;
  GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS = 4;
{$IFNDEF WINDOWS}
  RTLD_NOW_FLAG = 2;
  RTLD_NODELETE_FLAG = $1000;
{$ENDIF}

var
  Store: TBEStore = nil;
  Writer: TBEWriter = nil;
  Worker: TBEWorker = nil;
  Pinned: Boolean = False;
  Imported: LongInt = 0;
  PutKey: AnsiString = '';
  PutValues: TBEValues;
  StatusBuf: AnsiString = '';

{$IFDEF WINDOWS}
function PinModuleHandle(Flags: DWORD; Addr: Pointer; var Module: HMODULE): BOOL; stdcall;
  external 'kernel32.dll' name 'GetModuleHandleExA';
{$ELSE}
type
  TDlInfo = record
    dli_fname: PAnsiChar;
    dli_fbase: Pointer;
    dli_sname: PAnsiChar;
    dli_saddr: Pointer;
  end;

function be_dladdr(Addr: Pointer; var Info: TDlInfo): LongInt; cdecl; external 'dl' name 'dladdr';
function be_dlopen(Name: PAnsiChar; Flags: LongInt): Pointer; cdecl; external 'dl' name 'dlopen';
{$ENDIF}

procedure PinModule;
{$IFDEF WINDOWS}
var
  H: HMODULE;
begin
  H := 0;
  if not Pinned then
    Pinned := PinModuleHandle(GET_MODULE_HANDLE_EX_FLAG_PIN or GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS, @PinModule, H);
end;
{$ELSE}
var
  Info: TDlInfo;
begin
  if Pinned then
    Exit;
  FillChar(Info, SizeOf(Info), 0);
  if (be_dladdr(@PinModule, Info) <> 0) and (Info.dli_fname <> nil) then
    Pinned := be_dlopen(Info.dli_fname, RTLD_NOW_FLAG or RTLD_NODELETE_FLAG) <> nil;
end;
{$ENDIF}

function Str(P: PChar; MaxLen: LongInt): AnsiString;
begin
  if P = nil then
    Result := ''
  else
    Result := Copy(StrPas(P), 1, MaxLen);
end;

procedure StopAll;
begin
  if Worker <> nil then
  begin
    Worker.Terminate;
    Worker.Wake;
    Worker.WaitFor;
    FreeAndNil(Worker);
  end;
  FreeAndNil(Writer);
  FreeAndNil(Store);
end;

function BE_Init(DataDir: PChar; ApiVersion: LongInt): LongInt; cdecl;
var
  Dir, Txt: AnsiString;
begin
  Result := 0;
  try
    if ApiVersion <> BE_API_VERSION then
    begin
      Result := -BE_API_VERSION;
      Exit;
    end;
    PinModule;
    { a second BE_Init without BE_Shutdown (the script was loaded again): start fresh }
    StopAll;
    Dir := IncludeTrailingPathDelimiter(Str(DataDir, 1024));
    Store := TBEStore.Create(Dir + 'players.bdb');
    Writer := TBEWriter.Create;
    Imported := 0;
    if not Store.Load then
    begin
      Txt := Dir + 'players.txt';
      if FileExists(Txt) then
      begin
        Imported := Store.ImportText(Txt);
        if Store.Save then
          RenameFile(Txt, Txt + '.imported');
      end;
    end;
    Worker := TBEWorker.Create(Store, Writer);
    Result := BE_API_VERSION;
  except
    try
      StopAll;
    except
    end;
    Result := 0;
  end;
end;

procedure BE_Shutdown; cdecl;
begin
  try
    StopAll;
  except
  end;
end;

function BE_Status: PChar; cdecl;
begin
  try
    if Store = nil then
      StatusBuf := 'not running'
    else
    begin
      StatusBuf := 'players ' + IntToStr(Store.Size) + ' (saved ' + IntToStr(Store.Saves) + ' times';
      if Imported > 0 then
        StatusBuf := StatusBuf + ', ' + IntToStr(Imported) + ' taken over from players.txt';
      StatusBuf := StatusBuf + '), log lines written ' + IntToStr(Writer.Written) + ', waiting ' +
        IntToStr(Writer.Pending);
      if Writer.Dropped > 0 then
        StatusBuf := StatusBuf + ', dropped ' + IntToStr(Writer.Dropped);
      if Store.Errors + Writer.Errors > 0 then
        StatusBuf := StatusBuf + ', errors ' + IntToStr(Store.Errors + Writer.Errors) + ' (last: ' +
          Store.LastError + Writer.LastError + ')';
    end;
  except
    StatusBuf := 'status failed';
  end;
  Result := PChar(StatusBuf);
end;

function BE_Pref_Count(Key: PChar): LongInt; cdecl;
begin
  Result := 0;
  try
    if Store <> nil then
      Result := Store.Count(Str(Key, 200));
  except
    Result := 0;
  end;
end;

function BE_Pref_Get(Key: PChar; Index: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    if Store <> nil then
      Result := Store.Get(Str(Key, 200), Index);
  except
    Result := 0;
  end;
end;

procedure BE_Pref_Begin(Key: PChar); cdecl;
begin
  try
    PutKey := Str(Key, 200);
    SetLength(PutValues, 0);
  except
  end;
end;

procedure BE_Pref_Add(Value: LongInt); cdecl;
begin
  try
    if Length(PutValues) < BE_MAX_VALUES then
    begin
      SetLength(PutValues, Length(PutValues) + 1);
      PutValues[High(PutValues)] := Value;
    end;
  except
  end;
end;

procedure BE_Pref_Commit; cdecl;
begin
  try
    if Store <> nil then
      if PutKey <> '' then
      begin
        Store.Put(PutKey, PutValues);
        Worker.Wake;
      end;
    PutKey := '';
    SetLength(PutValues, 0);
  except
  end;
end;

procedure BE_Log(FileName, Line: PChar); cdecl;
begin
  try
    if Writer <> nil then
    begin
      Writer.Add(Str(FileName, 1024), Str(Line, 8192));
      Worker.Wake;
    end;
  except
  end;
end;

exports
  BE_Init,
  BE_Shutdown,
  BE_Status,
  BE_Pref_Count,
  BE_Pref_Get,
  BE_Pref_Begin,
  BE_Pref_Add,
  BE_Pref_Commit,
  BE_Log;

end.
