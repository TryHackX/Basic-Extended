unit be_store;

{ The store and the writer of Basic-Extended's library.

  TBEStore keeps the players' choices in memory: a key (the Steam id S<number>, or H and the
  computer id) with up to BE_MAX_VALUES whole numbers. Reads and writes are lookups in memory;
  the file (data/players.bdb) is written by the worker thread a moment after a change, never by
  the game thread. The file:
    'BEDB'  version (UInt32)  record count (UInt32)
    per record: key length (UInt16), key bytes, value count (UInt8), values (Int32 each)
  all little-endian. It is written to players.bdb.tmp first (and forced to the disk); the previous file
  becomes players.bdb.bak, so a crash in the middle leaves the old one, or the .bak and the complete .tmp
  (Load takes the .tmp then). A file with a record that has no key, or with bytes after the last record, is
  refused as broken (the unwritten end of a file after a power cut reads as zeros).

  TBEWriter takes lines for text files (the logger) and appends them on the worker thread, so a
  slow disk never holds the game up. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs;

const
  BE_MAX_VALUES = 32;
  BE_MAGIC: array[0..3] of AnsiChar = ('B', 'E', 'D', 'B');
  BE_FILE_VERSION = 1;
  { lines waiting for the disk at most; beyond that the oldest are dropped (and counted) }
  BE_MAX_LINES = 50000;

var
  { a log file (*.log but bans.log, which the script reads back; a watched player's file) over this size is moved to
    name.1 (an older .1 is deleted) before the next line is appended: two files of at most this size are kept }
  BeLogMaxBytes: Int64 = 5 * 1024 * 1024;

{ 4.2 (BE3-07): the whole file Name becomes Text at once, never half written or missing: the text goes to Name.tmp,
  to the disk, and that is put in the place of the file in one step (MoveFileEx with MOVEFILE_REPLACE_EXISTING on
  Windows, rename on Unix). False = the old file is as it was (a program that has the file open without sharing is
  the usual reason). It runs on the caller's thread. }
function WriteFileAtomic(const Name, Text: AnsiString): Boolean;

type
  TBEValues = array of LongInt;

  TBERecord = class
    Values: TBEValues;
  end;

  TBEStore = class
  private
    FKeys: TStringList;
    FLock: TCriticalSection;
    { one disk write at a time (the worker of an earlier session may still be writing the same objects) }
    FSaveLock: TCriticalSection;
    FPath: AnsiString;
    FDirty: Boolean;
    FDirtySince: QWord;
    FSaves, FErrors: LongInt;
    FLastError: AnsiString;
    { the file and its .bak could not be read and not be moved aside: saved as players.bdb.new }
    FWriteNew: Boolean;
    function Find(const Key: AnsiString): TBERecord;
    function LoadFile(const Path: AnsiString): Boolean;
    function GetLastError: AnsiString;
    procedure SetError(const Msg: AnsiString);
  public
    constructor Create(const Path: AnsiString);
    destructor Destroy; override;
    { the file, or its .tmp / .bak when the file is missing or broken; False when none could be read
      (an empty store then) }
    function Load: Boolean;
    { writes the file now (on the worker thread, or at the end) }
    function Save: Boolean;
    { lines "key=v0,v1,..." of the older players.txt; the number of keys taken over }
    function ImportText(const TxtPath: AnsiString): LongInt;
    function Count(const Key: AnsiString): LongInt;
    function Get(const Key: AnsiString; Index: LongInt): LongInt;
    { no values = the key is removed }
    procedure Put(const Key: AnsiString; const V: TBEValues);
    function DeletePrefix(const Prefix: AnsiString): LongInt;
    function Size: LongInt;
    { True when a change waits longer than DelayMs for the disk }
    function Due(DelayMs: QWord): Boolean;
    property Saves: LongInt read FSaves;
    property Errors: LongInt read FErrors;
    { read under the lock: the worker thread writes it }
    property LastError: AnsiString read GetLastError;
    property Path: AnsiString read FPath;
  end;

  TBEWriter = class
  private
    FLock: TCriticalSection;
    { one Flush at a time, so two threads on one writer cannot open the same file twice }
    FFlushLock: TCriticalSection;
    FLines: TStringList;
    FDropped, FWritten, FErrors: LongInt;
    FLastError: AnsiString;
    function GetLastError: AnsiString;
    procedure FlushBatch;
  public
    constructor Create;
    destructor Destroy; override;
    { a line for a file; with BE_MAX_LINES waiting the new one is dropped (and counted) }
    procedure Add(const FileName, Line: AnsiString);
    { the whole file FileName becomes Text (FileName.tmp is written, then put in its place); in order with the
      lines. One that still waits for the same file is replaced by the newer text, and it never counts against
      BE_MAX_LINES (a stuck disk must not make a layout save vanish) }
    procedure AddWhole(const FileName, Text: AnsiString);
    { appends what waits; on the worker thread }
    procedure Flush;
    function Pending: LongInt;
    property Dropped: LongInt read FDropped;
    property Written: LongInt read FWritten;
    property Errors: LongInt read FErrors;
    property LastError: AnsiString read GetLastError;
  end;

  TBEWorker = class(TThread)
  private
    FStore: TBEStore;
    FWriter: TBEWriter;
    FWake, FDone: TEvent;
    FLastSave: QWord;
  protected
    procedure Execute; override;
  public
    constructor Create(AStore: TBEStore; AWriter: TBEWriter);
    destructor Destroy; override;
    procedure Wake;
    { set when the thread has written what waited and ends (BE_Shutdown waits for it a limited time) }
    property Done: TEvent read FDone;
  end;

implementation

{$IFDEF WINDOWS}
function BeMoveFileEx(Src, Dst: PWideChar; Flags: LongWord): LongInt; stdcall; external 'kernel32.dll' name 'MoveFileExW';
{$ENDIF}

function WriteFileAtomic(const Name, Text: AnsiString): Boolean;
var
  Tmp: AnsiString;
  S: TFileStream;
begin
  Result := False;
  if Name = '' then
    Exit;
  Tmp := Name + '.tmp';
  try
    if ExtractFilePath(Name) <> '' then
      ForceDirectories(ExtractFilePath(Name));
    S := TFileStream.Create(Tmp, fmCreate);
    try
      if Length(Text) > 0 then
        S.WriteBuffer(Text[1], Length(Text));
      FileFlush(S.Handle);
    finally
      S.Free;
    end;
    {$IFDEF WINDOWS}
    { 1 = MOVEFILE_REPLACE_EXISTING, 8 = MOVEFILE_WRITE_THROUGH }
    Result := BeMoveFileEx(PWideChar(UnicodeString(Tmp)), PWideChar(UnicodeString(Name)), 1 or 8) <> 0;
    {$ELSE}
    Result := RenameFile(Tmp, Name);
    {$ENDIF}
  except
    Result := False;
  end;
  if not Result then
    try
      SysUtils.DeleteFile(Tmp);
    except
    end;
end;

{ ---------------- TBEStore ---------------- }

constructor TBEStore.Create(const Path: AnsiString);
begin
  inherited Create;
  FPath := Path;
  FKeys := TStringList.Create;
  { binary order: the locale's comparison is ~20 times slower, and it ignores some characters (a soft hyphen), so
    two different keys could be one }
  FKeys.UseLocale := False;
  FKeys.Sorted := True;
  FKeys.Duplicates := dupIgnore;
  FKeys.CaseSensitive := True;
  FKeys.OwnsObjects := True;
  FLock := TCriticalSection.Create;
  FSaveLock := TCriticalSection.Create;
end;

destructor TBEStore.Destroy;
begin
  FKeys.Free;
  FLock.Free;
  FSaveLock.Free;
  inherited Destroy;
end;

function TBEStore.Find(const Key: AnsiString): TBERecord;
var
  i: LongInt;
begin
  Result := nil;
  if FKeys.Find(Key, i) then
    Result := TBERecord(FKeys.Objects[i]);
end;

function TBEStore.LoadFile(const Path: AnsiString): Boolean;
var
  F: TMemoryStream;
  Magic: array[0..3] of AnsiChar;
  Ver, N, i: LongWord;
  j, d: LongInt;
  KL: Word;
  VC: Byte;
  Key: AnsiString;
  R: TBERecord;
begin
  Result := False;
  if not FileExists(Path) then
    Exit;
  F := nil;
  try
    F := TMemoryStream.Create;
    F.LoadFromFile(Path);
    F.ReadBuffer(Magic, 4);
    if (Magic[0] <> 'B') or (Magic[1] <> 'E') or (Magic[2] <> 'D') or (Magic[3] <> 'B') then
      raise Exception.Create('not a players.bdb file');
    F.ReadBuffer(Ver, 4);
    Ver := LEtoN(Ver);
    if Ver <> BE_FILE_VERSION then
      raise Exception.Create('unknown version ' + IntToStr(Ver));
    F.ReadBuffer(N, 4);
    N := LEtoN(N);
    FKeys.Clear;
    { the records are added unsorted and sorted once: a file written in another order loads as fast as one in this
      order }
    FKeys.Sorted := False;
    for i := 1 to N do
    begin
      F.ReadBuffer(KL, 2);
      KL := LEtoN(KL);
      { Put never writes a record without a key: zeros here are the unwritten end of a file that the disk did not
        finish (a record with no values is still read, as before) }
      if KL = 0 then
        raise Exception.Create('broken record');
      SetLength(Key, KL);
      F.ReadBuffer(Key[1], KL);
      F.ReadBuffer(VC, 1);
      if VC > BE_MAX_VALUES then
        raise Exception.Create('broken record');
      R := TBERecord.Create;
      FKeys.AddObject(Key, R);
      SetLength(R.Values, VC);
      for j := 0 to VC - 1 do
      begin
        F.ReadBuffer(R.Values[j], 4);
        R.Values[j] := LEtoN(R.Values[j]);
      end;
    end;
    if F.Position <> F.Size then
      raise Exception.Create('bytes after the last record');
    FKeys.Sorted := True;
    { a key twice (never written): one of them stays }
    for d := FKeys.Count - 1 downto 1 do
      if FKeys[d] = FKeys[d - 1] then
        FKeys.Delete(d);
    Result := True;
  except
    on E: Exception do
    begin
      FKeys.Clear;
      FKeys.Sorted := True;
      Inc(FErrors);
      FLastError := 'reading ' + ExtractFileName(Path) + ': ' + E.Message;
    end;
  end;
  F.Free;
end;

function TBEStore.GetLastError: AnsiString;
begin
  FLock.Enter;
  try
    Result := FLastError;
  finally
    FLock.Leave;
  end;
end;

procedure TBEStore.SetError(const Msg: AnsiString);
begin
  FLock.Enter;
  try
    Inc(FErrors);
    FLastError := Msg;
  finally
    FLock.Leave;
  end;
end;

function TBEStore.Load: Boolean;
var
  Stamp: AnsiString;
  Kept: Boolean;
begin
  FLock.Enter;
  try
    Result := LoadFile(FPath);
    { a save cut off between its two renames: the old file is the .bak and the complete new one still the .tmp }
    if not Result then
      Result := LoadFile(FPath + '.tmp');
    if not Result then
      Result := LoadFile(FPath + '.bak');
    { neither could be read: both are moved aside before anything is written (never deleted); when that fails
      the store is saved as players.bdb.new }
    if not Result then
    begin
      Kept := True;
      Stamp := '.unread-' + FormatDateTime('yyyymmdd-hhnnss', Now);
      if FileExists(FPath) then
        if not RenameFile(FPath, FPath + Stamp) then
          Kept := False;
      if FileExists(FPath + '.bak') then
        if not RenameFile(FPath + '.bak', FPath + '.bak' + Stamp) then
          Kept := False;
      FWriteNew := not Kept;
      { a session that could not move them aside saved into players.bdb.new: its data comes back }
      if LoadFile(FPath + '.new') then
        Result := True;
    end;
    FDirty := False;
  finally
    FLock.Leave;
  end;
end;

{ the bytes of M in a new file, forced to the disk before this returns: a power cut right after the renames that
  follow then cannot leave a file whose end the disk never wrote (it would read as zeros) }
procedure SaveFlushed(const Path: AnsiString; M: TMemoryStream);
var
  S: TFileStream;
begin
  S := TFileStream.Create(Path, fmCreate);
  try
    if M.Size > 0 then
      S.WriteBuffer(M.Memory^, M.Size);
    FileFlush(S.Handle);
  finally
    S.Free;
  end;
end;

function TBEStore.Save: Boolean;
type
  TSnap = record
    Key: AnsiString;
    Vals: TBEValues;
  end;
var
  M: TMemoryStream;
  Snap: array of TSnap;
  i, j: LongInt;
  W: LongWord;
  KL: Word;
  VC: Byte;
  V: LongInt;
  Tmp, Bak: AnsiString;
begin
  Result := False;
  M := TMemoryStream.Create;
  FSaveLock.Enter;
  try
    { under the lock only the pairs (key, values) are taken: both are reference counted, and Put replaces the values
      of a key by a new array, so the snapshot stays as it was; the bytes are made and written without the lock (a
      tick that wants a key never waits for the serializing) }
    FLock.Enter;
    try
      SetLength(Snap, FKeys.Count);
      for i := 0 to FKeys.Count - 1 do
      begin
        Snap[i].Key := FKeys[i];
        Snap[i].Vals := TBERecord(FKeys.Objects[i]).Values;
      end;
      FDirty := False;
    finally
      FLock.Leave;
    end;
    M.WriteBuffer(BE_MAGIC, 4);
    W := NtoLE(LongWord(BE_FILE_VERSION));
    M.WriteBuffer(W, 4);
    W := NtoLE(LongWord(Length(Snap)));
    M.WriteBuffer(W, 4);
    for i := 0 to High(Snap) do
    begin
      KL := NtoLE(Word(Length(Snap[i].Key)));
      M.WriteBuffer(KL, 2);
      if Length(Snap[i].Key) > 0 then
        M.WriteBuffer(Snap[i].Key[1], Length(Snap[i].Key));
      VC := Length(Snap[i].Vals);
      M.WriteBuffer(VC, 1);
      for j := 0 to VC - 1 do
      begin
        V := NtoLE(Snap[i].Vals[j]);
        M.WriteBuffer(V, 4);
      end;
    end;
    Tmp := FPath + '.tmp';
    Bak := FPath + '.bak';
    { a fresh install has no data folder yet }
    ForceDirectories(ExtractFilePath(FPath));
    if FWriteNew then
      SaveFlushed(FPath + '.new', M)
    else
    begin
      SaveFlushed(Tmp, M);
      if FileExists(FPath) then
      begin
        if FileExists(Bak) then
          SysUtils.DeleteFile(Bak);
        if not RenameFile(FPath, Bak) then
          raise Exception.Create('cannot rename ' + ExtractFileName(FPath));
      end;
      if not RenameFile(Tmp, FPath) then
        raise Exception.Create('cannot rename ' + ExtractFileName(Tmp));
    end;
    Inc(FSaves);
    Result := True;
  except
    on E: Exception do
    begin
      SetError('writing ' + ExtractFileName(FPath) + ': ' + E.Message);
      { try again later }
      FLock.Enter;
      FDirty := True;
      FDirtySince := GetTickCount64;
      FLock.Leave;
    end;
  end;
  FSaveLock.Leave;
  M.Free;
end;

function TBEStore.ImportText(const TxtPath: AnsiString): LongInt;
var
  L: TStringList;
  i, p, n: LongInt;
  S, Key, Part: AnsiString;
  V: TBEValues;
begin
  Result := 0;
  if not FileExists(TxtPath) then
    Exit;
  L := TStringList.Create;
  try
    L.LoadFromFile(TxtPath);
    for i := 0 to L.Count - 1 do
    begin
      S := Trim(L[i]);
      p := Pos('=', S);
      if p < 2 then
        Continue;
      Key := Copy(S, 1, p - 1);
      Delete(S, 1, p);
      SetLength(V, 0);
      n := 0;
      while (S <> '') and (n < BE_MAX_VALUES) do
      begin
        p := Pos(',', S);
        if p = 0 then
        begin
          Part := S;
          S := '';
        end
        else
        begin
          Part := Copy(S, 1, p - 1);
          Delete(S, 1, p);
        end;
        SetLength(V, n + 1);
        V[n] := StrToIntDef(Trim(Part), 0);
        Inc(n);
      end;
      if n > 0 then
      begin
        Put(Key, V);
        Inc(Result);
      end;
    end;
  finally
    L.Free;
  end;
end;

function TBEStore.Count(const Key: AnsiString): LongInt;
var
  R: TBERecord;
begin
  FLock.Enter;
  try
    R := Find(Key);
    if R = nil then
      Result := 0
    else
      Result := Length(R.Values);
  finally
    FLock.Leave;
  end;
end;

function TBEStore.Get(const Key: AnsiString; Index: LongInt): LongInt;
var
  R: TBERecord;
begin
  Result := 0;
  FLock.Enter;
  try
    R := Find(Key);
    if R <> nil then
      if (Index >= 0) and (Index < Length(R.Values)) then
        Result := R.Values[Index];
  finally
    FLock.Leave;
  end;
end;

procedure TBEStore.Put(const Key: AnsiString; const V: TBEValues);
var
  i, n: LongInt;
  R: TBERecord;
  NewV: TBEValues;
begin
  if (Key = '') or (Length(Key) > 200) then
    Exit;
  FLock.Enter;
  try
    if Length(V) = 0 then
    begin
      if FKeys.Find(Key, i) then
        FKeys.Delete(i)
      else
        Exit;
    end
    else
    begin
      R := Find(Key);
      n := Length(V);
      if n > BE_MAX_VALUES then
        n := BE_MAX_VALUES;
      { the same values: nothing to write }
      if R <> nil then
        if Length(R.Values) = n then
        begin
          i := 0;
          while (i < n) and (R.Values[i] = V[i]) do
            Inc(i);
          if i = n then
            Exit;
        end;
      if R = nil then
      begin
        R := TBERecord.Create;
        FKeys.AddObject(Key, R);
      end;
      { a new array, never a change of the old one: Save holds a reference to the old array while it writes }
      NewV := nil;
      SetLength(NewV, n);
      for i := 0 to n - 1 do
        NewV[i] := V[i];
      R.Values := NewV;
    end;
    if not FDirty then
      FDirtySince := GetTickCount64;
    FDirty := True;
  finally
    FLock.Leave;
  end;
end;

function TBEStore.DeletePrefix(const Prefix: AnsiString): LongInt;
var
  i: LongInt;
begin
  Result := 0;
  if Prefix = '' then
    Exit;
  FLock.Enter;
  try
    for i := FKeys.Count - 1 downto 0 do
      if Copy(FKeys[i], 1, Length(Prefix)) = Prefix then
      begin
        FKeys.Delete(i);
        Inc(Result);
      end;
    if Result > 0 then
    begin
      if not FDirty then
        FDirtySince := GetTickCount64;
      FDirty := True;
    end;
  finally
    FLock.Leave;
  end;
end;

function TBEStore.Size: LongInt;
begin
  FLock.Enter;
  Result := FKeys.Count;
  FLock.Leave;
end;

function TBEStore.Due(DelayMs: QWord): Boolean;
begin
  FLock.Enter;
  Result := FDirty and (GetTickCount64 - FDirtySince >= DelayMs);
  FLock.Leave;
end;

{ ---------------- TBEWriter ---------------- }

constructor TBEWriter.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FFlushLock := TCriticalSection.Create;
  FLines := TStringList.Create;
end;

destructor TBEWriter.Destroy;
begin
  FLines.Free;
  FFlushLock.Free;
  FLock.Free;
  inherited Destroy;
end;

{ a line of a text file is one line: a control character (a CR or LF in a name, a computer id of a changed client)
  would start a line that looks like another entry; a tab stays }
function CleanLogLine(const S: AnsiString): AnsiString;
var
  i: LongInt;
begin
  Result := S;
  for i := 1 to Length(Result) do
    if (Result[i] < #32) and (Result[i] <> #9) then
      Result[i] := ' ';
end;

{ does a file of the writer rotate by size: a log, not a file the script reads back }
function RotatesBySize(const Name: AnsiString): Boolean;
var
  F: AnsiString;
begin
  F := LowerCase(ExtractFileName(Name));
  Result := (ExtractFileExt(F) = '.log') and (F <> 'bans.log');
  if not Result then
    Result := (Pos('/watched/', StringReplace(LowerCase(Name), '\', '/', [rfReplaceAll])) > 0);
end;

{ the file is over the limit: it becomes name.1 (the old .1 goes) and the next line starts a new file }
procedure RotateLog(const Name: AnsiString);
var
  SR: TSearchRec;
  Big: Boolean;
begin
  Big := False;
  if FindFirst(Name, faAnyFile, SR) = 0 then
  begin
    Big := SR.Size > BeLogMaxBytes;
    FindClose(SR);
  end;
  if not Big then
    Exit;
  if FileExists(Name + '.1') then
    SysUtils.DeleteFile(Name + '.1');
  RenameFile(Name, Name + '.1');
end;

procedure TBEWriter.Add(const FileName, Line: AnsiString);
begin
  if FileName = '' then
    Exit;
  FLock.Enter;
  try
    if FLines.Count >= BE_MAX_LINES then
    begin
      Inc(FDropped);
      Exit;
    end;
    FLines.Add(FileName + #1 + CleanLogLine(Line));
  finally
    FLock.Leave;
  end;
end;

procedure TBEWriter.AddWhole(const FileName, Text: AnsiString);
var
  Head: AnsiString;
  i: LongInt;
begin
  if FileName = '' then
    Exit;
  Head := #2 + FileName + #1;
  FLock.Enter;
  try
    { a whole file that still waits is replaced by this newer one (its place in the order stays) }
    for i := FLines.Count - 1 downto 0 do
      if (Length(FLines[i]) >= Length(Head)) and (CompareByte(FLines[i][1], Head[1], Length(Head)) = 0) then
      begin
        FLines[i] := Head + Text;
        Exit;
      end;
    FLines.Add(Head + Text);
  finally
    FLock.Leave;
  end;
end;

{ a whole file: FileName.tmp written, the old file to FileName.bak, the new one in its place }
function WriteWhole(const Name, Text: AnsiString): Boolean;
var
  S: TFileStream;
  Tmp, Bak: AnsiString;
begin
  Result := False;
  Tmp := Name + '.tmp';
  Bak := Name + '.bak';
  if ExtractFilePath(Name) <> '' then
    ForceDirectories(ExtractFilePath(Name));
  { the bytes as they are (4.1: data/spawns.bdb is binary) }
  S := TFileStream.Create(Tmp, fmCreate);
  try
    if Length(Text) > 0 then
      S.WriteBuffer(Text[1], Length(Text));
    { to the disk before the renames below (see SaveFlushed) }
    FileFlush(S.Handle);
  finally
    S.Free;
  end;
  if FileExists(Name) then
  begin
    if FileExists(Bak) then
      SysUtils.DeleteFile(Bak);
    if not RenameFile(Name, Bak) then
      Exit;
  end;
  Result := RenameFile(Tmp, Name);
end;

function TBEWriter.GetLastError: AnsiString;
begin
  FLock.Enter;
  try
    Result := FLastError;
  finally
    FLock.Leave;
  end;
end;

function TBEWriter.Pending: LongInt;
begin
  FLock.Enter;
  Result := FLines.Count;
  FLock.Leave;
end;

procedure TBEWriter.Flush;
begin
  FFlushLock.Enter;
  try
    FlushBatch;
  finally
    FFlushLock.Leave;
  end;
end;

procedure TBEWriter.FlushBatch;
var
  Batch: TStringList;
  i, j, p: LongInt;
  Name, Cur: AnsiString;
  T: TextFile;
  Open: Boolean;
begin
  FLock.Enter;
  if FLines.Count = 0 then
  begin
    FLock.Leave;
    Exit;
  end;
  Batch := FLines;
  FLines := TStringList.Create;
  FLock.Leave;
  { the lines of one file one after the other: each file is opened once }
  Open := False;
  Cur := '';
  try
    i := 0;
    while i < Batch.Count do
    begin
      p := Pos(#1, Batch[i]);
      { a whole file (AddWhole) }
      if (Length(Batch[i]) > 0) and (Batch[i][1] = #2) then
      begin
        if Open then
          CloseFile(T);
        Open := False;
        Cur := '';
        Name := Copy(Batch[i], 2, p - 2);
        try
          if WriteWhole(Name, Copy(Batch[i], p + 1, Length(Batch[i]))) then
            Inc(FWritten)
          else
          begin
            FLock.Enter;
            Inc(FErrors);
            FLastError := Name + ': cannot put the new file in place';
            FLock.Leave;
          end;
        except
          on E: Exception do
          begin
            FLock.Enter;
            Inc(FErrors);
            FLastError := Name + ': ' + E.Message;
            FLock.Leave;
          end;
        end;
        Inc(i);
        Continue;
      end;
      Name := Copy(Batch[i], 1, p - 1);
      if (not Open) or (Name <> Cur) then
      begin
        if Open then
          CloseFile(T);
        Open := False;
        Cur := Name;
        try
          if ExtractFilePath(Name) <> '' then
            ForceDirectories(ExtractFilePath(Name));
          if FileExists(Name) then
            if RotatesBySize(Name) then
              RotateLog(Name);
          AssignFile(T, Name);
          if FileExists(Name) then
            Append(T)
          else
            Rewrite(T);
          Open := True;
        except
          on E: Exception do
          begin
            FLock.Enter;
            Inc(FErrors);
            FLastError := Name + ': ' + E.Message;
            FLock.Leave;
            { the lines of this file are lost: skip them }
            j := i;
            while (j < Batch.Count) and (Copy(Batch[j], 1, p - 1) = Name) do
              Inc(j);
            i := j;
            Continue;
          end;
        end;
      end;
      try
        WriteLn(T, Copy(Batch[i], p + 1, Length(Batch[i])));
        Inc(FWritten);
        Inc(i);
      except
        on E: Exception do
        begin
          FLock.Enter;
          Inc(FErrors);
          FLastError := Name + ': ' + E.Message;
          FLock.Leave;
          try
            CloseFile(T);
          except
          end;
          Open := False;
          Cur := '';
          j := i;
          while (j < Batch.Count) and (Copy(Batch[j], 1, p - 1) = Name) do
          begin
            Inc(FDropped);
            Inc(j);
          end;
          i := j;
        end;
      end;
    end;
  finally
    if Open then
      CloseFile(T);
    Batch.Free;
  end;
end;

{ ---------------- TBEWorker ---------------- }

constructor TBEWorker.Create(AStore: TBEStore; AWriter: TBEWriter);
begin
  FStore := AStore;
  FWriter := AWriter;
  FWake := TEvent.Create(nil, False, False, '');
  FDone := TEvent.Create(nil, True, False, '');
  inherited Create(False);
end;

destructor TBEWorker.Destroy;
begin
  FWake.Free;
  FDone.Free;
  inherited Destroy;
end;

procedure TBEWorker.Wake;
begin
  FWake.SetEvent;
end;

procedure TBEWorker.Execute;
begin
  try
    while not Terminated do
    begin
      FWake.WaitFor(500);
      try
        FWriter.Flush;
        { a change 2 s old is saved, at most every 15 s (the whole file is written each time) }
        if FStore.Due(2000) then
          if GetTickCount64 - FLastSave >= 15000 then
          begin
            FStore.Save;
            FLastSave := GetTickCount64;
          end;
      except
        { never let an exception end the thread }
      end;
    end;
    { the end: what waits goes to the disk }
    try
      FWriter.Flush;
      if FStore.Due(0) then
        FStore.Save;
    except
    end;
  finally
    FDone.SetEvent;
  end;
end;

end.
