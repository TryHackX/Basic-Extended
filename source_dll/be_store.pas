unit be_store;

{ The store and the writer of Basic-Extended's library.

  TBEStore keeps the players' choices in memory: a key (the Steam id S<number>, or H and the
  computer id) with up to BE_MAX_VALUES whole numbers. Reads and writes are lookups in memory;
  the file (data/players.bdb) is written by the worker thread a moment after a change, never by
  the game thread. The file:
    'BEDB'  version (UInt32)  record count (UInt32)
    per record: key length (UInt16), key bytes, value count (UInt8), values (Int32 each)
  all little-endian. It is written to players.bdb.tmp first; the previous file becomes
  players.bdb.bak, so a crash in the middle leaves the old one.

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

type
  TBEValues = array of LongInt;

  TBERecord = class
    Values: TBEValues;
  end;

  TBEStore = class
  private
    FKeys: TStringList;
    FLock: TCriticalSection;
    FPath: AnsiString;
    FDirty: Boolean;
    FDirtySince: QWord;
    FSaves, FErrors: LongInt;
    FLastError: AnsiString;
    function Find(const Key: AnsiString): TBERecord;
    function LoadFile(const Path: AnsiString): Boolean;
  public
    constructor Create(const Path: AnsiString);
    destructor Destroy; override;
    { the file, or its .bak when the file is missing or broken; False when neither could be read
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
    property LastError: AnsiString read FLastError;
    property Path: AnsiString read FPath;
  end;

  TBEWriter = class
  private
    FLock: TCriticalSection;
    FLines: TStringList;
    FDropped, FWritten, FErrors: LongInt;
    FLastError: AnsiString;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const FileName, Line: AnsiString);
    { appends what waits; on the worker thread }
    procedure Flush;
    function Pending: LongInt;
    property Dropped: LongInt read FDropped;
    property Written: LongInt read FWritten;
    property Errors: LongInt read FErrors;
    property LastError: AnsiString read FLastError;
  end;

  TBEWorker = class(TThread)
  private
    FStore: TBEStore;
    FWriter: TBEWriter;
    FWake: TEvent;
  protected
    procedure Execute; override;
  public
    constructor Create(AStore: TBEStore; AWriter: TBEWriter);
    destructor Destroy; override;
    procedure Wake;
  end;

implementation

{ ---------------- TBEStore ---------------- }

constructor TBEStore.Create(const Path: AnsiString);
begin
  inherited Create;
  FPath := Path;
  FKeys := TStringList.Create;
  FKeys.Sorted := True;
  FKeys.Duplicates := dupIgnore;
  FKeys.CaseSensitive := True;
  FKeys.OwnsObjects := True;
  FLock := TCriticalSection.Create;
end;

destructor TBEStore.Destroy;
begin
  FKeys.Free;
  FLock.Free;
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
  F: TFileStream;
  Magic: array[0..3] of AnsiChar;
  Ver, N, i, j: LongWord;
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
    F := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
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
    for i := 1 to N do
    begin
      F.ReadBuffer(KL, 2);
      KL := LEtoN(KL);
      SetLength(Key, KL);
      if KL > 0 then
        F.ReadBuffer(Key[1], KL);
      F.ReadBuffer(VC, 1);
      if VC > BE_MAX_VALUES then
        raise Exception.Create('broken record');
      R := TBERecord.Create;
      SetLength(R.Values, VC);
      for j := 0 to VC - 1 do
      begin
        F.ReadBuffer(R.Values[j], 4);
        R.Values[j] := LEtoN(R.Values[j]);
      end;
      if (Key = '') or (FKeys.IndexOf(Key) >= 0) then
        R.Free
      else
        FKeys.AddObject(Key, R);
    end;
    Result := True;
  except
    on E: Exception do
    begin
      FKeys.Clear;
      Inc(FErrors);
      FLastError := 'reading ' + ExtractFileName(Path) + ': ' + E.Message;
    end;
  end;
  F.Free;
end;

function TBEStore.Load: Boolean;
begin
  FLock.Enter;
  try
    Result := LoadFile(FPath);
    if not Result then
      Result := LoadFile(FPath + '.bak');
    FDirty := False;
  finally
    FLock.Leave;
  end;
end;

function TBEStore.Save: Boolean;
var
  M: TMemoryStream;
  i, j: LongInt;
  W: LongWord;
  KL: Word;
  VC: Byte;
  V: LongInt;
  Key: AnsiString;
  R: TBERecord;
  Tmp, Bak: AnsiString;
begin
  Result := False;
  M := TMemoryStream.Create;
  try
    { the records are copied under the lock, the disk is written without it }
    FLock.Enter;
    try
      M.WriteBuffer(BE_MAGIC, 4);
      W := NtoLE(LongWord(BE_FILE_VERSION));
      M.WriteBuffer(W, 4);
      W := NtoLE(LongWord(FKeys.Count));
      M.WriteBuffer(W, 4);
      for i := 0 to FKeys.Count - 1 do
      begin
        Key := FKeys[i];
        R := TBERecord(FKeys.Objects[i]);
        KL := NtoLE(Word(Length(Key)));
        M.WriteBuffer(KL, 2);
        if Length(Key) > 0 then
          M.WriteBuffer(Key[1], Length(Key));
        VC := Length(R.Values);
        M.WriteBuffer(VC, 1);
        for j := 0 to VC - 1 do
        begin
          V := NtoLE(R.Values[j]);
          M.WriteBuffer(V, 4);
        end;
      end;
      FDirty := False;
    finally
      FLock.Leave;
    end;
    Tmp := FPath + '.tmp';
    Bak := FPath + '.bak';
    M.SaveToFile(Tmp);
    if FileExists(FPath) then
    begin
      if FileExists(Bak) then
        SysUtils.DeleteFile(Bak);
      if not RenameFile(FPath, Bak) then
        raise Exception.Create('cannot rename ' + ExtractFileName(FPath));
    end;
    if not RenameFile(Tmp, FPath) then
      raise Exception.Create('cannot rename ' + ExtractFileName(Tmp));
    Inc(FSaves);
    Result := True;
  except
    on E: Exception do
    begin
      Inc(FErrors);
      FLastError := 'writing ' + ExtractFileName(FPath) + ': ' + E.Message;
      { try again later }
      FLock.Enter;
      FDirty := True;
      FDirtySince := GetTickCount64;
      FLock.Leave;
    end;
  end;
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
      if R = nil then
      begin
        R := TBERecord.Create;
        FKeys.AddObject(Key, R);
      end;
      n := Length(V);
      if n > BE_MAX_VALUES then
        n := BE_MAX_VALUES;
      SetLength(R.Values, n);
      for i := 0 to n - 1 do
        R.Values[i] := V[i];
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
  FLines := TStringList.Create;
end;

destructor TBEWriter.Destroy;
begin
  FLines.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TBEWriter.Add(const FileName, Line: AnsiString);
begin
  if FileName = '' then
    Exit;
  FLock.Enter;
  try
    if FLines.Count >= BE_MAX_LINES then
    begin
      FLines.Delete(0);
      Inc(FDropped);
    end;
    FLines.Add(FileName + #1 + Line);
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
          AssignFile(T, Name);
          if FileExists(Name) then
            Append(T)
          else
            Rewrite(T);
          Open := True;
        except
          on E: Exception do
          begin
            Inc(FErrors);
            FLastError := Name + ': ' + E.Message;
            { the lines of this file are lost: skip them }
            j := i;
            while (j < Batch.Count) and (Copy(Batch[j], 1, p - 1) = Name) do
              Inc(j);
            i := j;
            Continue;
          end;
        end;
      end;
      WriteLn(T, Copy(Batch[i], p + 1, Length(Batch[i])));
      Inc(FWritten);
      Inc(i);
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
  inherited Create(False);
end;

destructor TBEWorker.Destroy;
begin
  FWake.Free;
  inherited Destroy;
end;

procedure TBEWorker.Wake;
begin
  FWake.SetEvent;
end;

procedure TBEWorker.Execute;
begin
  while not Terminated do
  begin
    FWake.WaitFor(500);
    try
      FWriter.Flush;
      if FStore.Due(2000) then
        FStore.Save;
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
end;

end.
