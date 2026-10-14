program test_store;

{ The store and the writer of be_store on their own: put, get, remove, save, load, the .bak when
  the file is broken, taking over players.txt, and log lines appended by the worker.
  Usage: test_store <scratch folder> }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils, be_store;

var
  Failed: LongInt = 0;
  Dir: AnsiString;

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

function Vals(const A: array of LongInt): TBEValues;
var
  i: LongInt;
begin
  Result := nil;
  SetLength(Result, Length(A));
  for i := 0 to High(A) do
    Result[i] := A[i];
end;

{ the files a test left aside (players.bdb*.unread-*) }
function UnreadCount(const Folder: AnsiString; Remove: Boolean): LongInt;
var
  R: TSearchRec;
begin
  Result := 0;
  if FindFirst(Folder + 'players.bdb*unread*', faAnyFile, R) = 0 then
  begin
    repeat
      Inc(Result);
      if Remove then
        DeleteFile(Folder + R.Name);
    until FindNext(R) <> 0;
    FindClose(R);
  end;
end;

procedure TestStore;
var
  S, S2: TBEStore;
  P: AnsiString;
  L: TStringList;
  F: TFileStream;
  B: Byte;
  W: LongWord;
  KL: Word;
  V: LongInt;
  K: AnsiString;
begin
  P := Dir + 'players.bdb';
  UnreadCount(Dir, True);
  if FileExists(P) then
    DeleteFile(P);
  if FileExists(P + '.bak') then
    DeleteFile(P + '.bak');
  if FileExists(P + '.new') then
    DeleteFile(P + '.new');
  S := TBEStore.Create(P);
  Check(not S.Load, 'no file: nothing loaded');
  Check(S.Count('S123') = 0, 'unknown key has no values');
  S.Put('S123', Vals([1, 20, 384, 200, 2, 0, 1, 3, 0, -1, -1, 1000, 0, 0, 0]));
  S.Put('H42AB', Vals([2, -1, -1]));
  Check(S.Count('S123') = 15, 'fifteen values kept');
  Check(S.Get('S123', 2) = 384, 'value read back');
  Check(S.Get('S123', 9) = -1, 'negative value read back');
  Check(S.Get('S123', 99) = 0, 'index out of range gives 0');
  Check(S.Due(0), 'a change waits for the disk');
  Check(S.Save, 'saved');
  Check(not S.Due(0), 'nothing waits after the save');
  S.Put('H42AB', nil);
  Check(S.Count('H42AB') = 0, 'key removed');
  Check(S.Save, 'saved again (the first file becomes .bak)');
  Check(FileExists(P + '.bak'), 'the previous file is kept as .bak');
  S.Free;

  S2 := TBEStore.Create(P);
  Check(S2.Load, 'loaded');
  Check(S2.Size = 1, 'one key in the file');
  Check(S2.Get('S123', 11) = 1000, 'value survives the file');
  S2.Put('ac:H1', Vals([1, 2]));
  S2.Put('ac:H2', Vals([3]));
  S2.Put('acx', Vals([4]));
  Check(S2.DeletePrefix('ac:') = 2, 'two keys with the prefix removed');
  Check((S2.Count('ac:H1') = 0) and (S2.Count('acx') = 1) and (S2.Count('S123') = 15), 'the other keys stay');
  Check(S2.DeletePrefix('') = 0, 'an empty prefix removes nothing');
  S2.Free;

  { a broken file: the .bak is read instead }
  F := TFileStream.Create(P, fmCreate);
  B := 7;
  F.WriteBuffer(B, 1);
  F.Free;
  S2 := TBEStore.Create(P);
  Check(S2.Load, 'broken file: the .bak loaded');
  Check(S2.Count('H42AB') = 3, 'the .bak has the older content');
  S2.Free;

  { the same values again mark nothing }
  { a store in a folder that is not there yet (a fresh install: git keeps no empty data folder) }
  if FileExists(Dir + 'nodir' + PathDelim + 'p.bdb') then
    DeleteFile(Dir + 'nodir' + PathDelim + 'p.bdb');
  RemoveDir(Dir + 'nodir');
  S2 := TBEStore.Create(Dir + 'nodir' + PathDelim + 'p.bdb');
  S2.Put('S1', Vals([7]));
  Check(S2.Save and FileExists(Dir + 'nodir' + PathDelim + 'p.bdb'), 'the store makes its folder');
  S2.Free;

  S2 := TBEStore.Create(Dir + 'same.bdb');
  S2.Put('K1', Vals([1, 2, 3]));
  Check(S2.Save, 'saved');
  S2.Put('K1', Vals([1, 2, 3]));
  Check(not S2.Due(0), 'the same values: nothing waits for the disk');
  S2.Put('K1', Vals([1, 2, 4]));
  Check(S2.Due(0), 'a changed value waits for the disk');
  S2.Free;

  { neither the file nor the .bak can be read: both are moved aside, nothing is written over them }
  F := TFileStream.Create(P + '.bak', fmCreate);
  F.WriteBuffer(B, 1);
  F.Free;
  S2 := TBEStore.Create(P);
  Check(not S2.Load, 'both broken: nothing loaded');
  Check((not FileExists(P)) and (not FileExists(P + '.bak')), 'both moved aside');
  Check(UnreadCount(Dir, False) = 2, 'kept as .unread- files');
  S2.Put('S1', Vals([5]));
  Check(S2.Save, 'the new store saved');
  Check(UnreadCount(Dir, False) = 2, 'the unread files are still there');
  S2.Free;

  { round 26: a record with no values (a damaged file) is read without running past its end, and the records
    after it too }
  F := TFileStream.Create(P, fmCreate);
  F.WriteBuffer(BE_MAGIC, 4);
  W := NtoLE(LongWord(BE_FILE_VERSION));
  F.WriteBuffer(W, 4);
  W := NtoLE(LongWord(2));
  F.WriteBuffer(W, 4);
  KL := NtoLE(Word(2));
  F.WriteBuffer(KL, 2);
  K := 'K0';
  F.WriteBuffer(K[1], 2);
  B := 0;
  F.WriteBuffer(B, 1);
  F.WriteBuffer(KL, 2);
  K := 'K1';
  F.WriteBuffer(K[1], 2);
  B := 1;
  F.WriteBuffer(B, 1);
  V := NtoLE(LongInt(7));
  F.WriteBuffer(V, 4);
  F.Free;
  S2 := TBEStore.Create(P);
  Check(S2.Load, 'a record with 0 values: the file is read');
  Check(S2.Get('K1', 0) = 7, 'the record after it is read too');
  S2.Free;

  { round 26: the data a session saved into players.bdb.new (it could not move the unreadable files aside) comes
    back when the files are unreadable again }
  if FileExists(P + '.new') then
    DeleteFile(P + '.new');
  S2 := TBEStore.Create(P + '.new');
  S2.Put('S77', Vals([77]));
  Check(S2.Save, 'a players.bdb.new written');
  S2.Free;
  F := TFileStream.Create(P, fmCreate);
  B := 7;
  F.WriteBuffer(B, 1);
  F.Free;
  if FileExists(P + '.bak') then
    DeleteFile(P + '.bak');
  S2 := TBEStore.Create(P);
  Check(S2.Load, 'players.bdb unreadable, no .bak: players.bdb.new loaded');
  Check(S2.Get('S77', 0) = 77, 'the value of players.bdb.new');
  S2.Free;
  UnreadCount(Dir, True);
  DeleteFile(P + '.new');

  { taking over players.txt }
  L := TStringList.Create;
  L.Add('S555=1,10,20,250,3,2');
  L.Add('H7C=0,-1,-1,0,0,1,1,2');
  L.Add('broken line');
  L.SaveToFile(Dir + 'players.txt');
  L.Free;
  S2 := TBEStore.Create(Dir + 'other.bdb');
  Check(S2.ImportText(Dir + 'players.txt') = 2, 'two keys taken over from players.txt');
  Check(S2.Get('S555', 3) = 250, 'a value of players.txt');
  Check(S2.Count('H7C') = 8, 'all values of a line');
  S2.Free;
end;

{ 4.2 (BD1-03, BD1-04, BD1-05): the unwritten end of a file, a save cut off between its renames, keys in binary order,
  a file in another order, a whole file that waits is replaced }
procedure TestHardening;
var
  S, S2: TBEStore;
  P: AnsiString;
  F: TFileStream;
  W: TBEWriter;
  L: TStringList;
  i: LongInt;
  B: Byte;
  N, Chunk: Int64;
  Key: AnsiString;
  Z: array[0..4095] of Byte;
begin
  P := Dir + 'players.bdb';
  UnreadCount(Dir, True);
  for i := 0 to 3 do
    case i of
      0: if FileExists(P) then DeleteFile(P);
      1: if FileExists(P + '.bak') then DeleteFile(P + '.bak');
      2: if FileExists(P + '.tmp') then DeleteFile(P + '.tmp');
      3: if FileExists(P + '.new') then DeleteFile(P + '.new');
    end;
  { 200 keys saved, one more saved: the first file is the .bak }
  S := TBEStore.Create(P);
  for i := 1 to 200 do
    S.Put('S' + IntToStr(76561198000000000 + i), Vals([i, 2]));
  Check(S.Save, 'hardening: 200 keys saved');
  S.Put('Sextra', Vals([9]));
  Check(S.Save, 'hardening: saved again');
  S.Free;
  { the end of the file reads as zeros (the disk did not write it): the file is refused, the .bak is read }
  F := TFileStream.Create(P, fmOpenReadWrite);
  N := F.Size;
  F.Position := (N * 6) div 10;
  FillChar(Z, SizeOf(Z), 0);
  while F.Position < N do
  begin
    Chunk := N - F.Position;
    if Chunk > SizeOf(Z) then
      Chunk := SizeOf(Z);
    F.WriteBuffer(Z, Chunk);
  end;
  F.Free;
  S2 := TBEStore.Create(P);
  Check(S2.Load and (S2.Size = 200) and (S2.Count('Sextra') = 0), 'a zero tail: the file is refused, the .bak is read');
  Check(S2.Errors > 0, 'a zero tail: the error is counted');
  S2.Free;
  UnreadCount(Dir, True);
  { a byte after the last record }
  for i := 0 to 2 do
    case i of
      0: if FileExists(P) then DeleteFile(P);
      1: if FileExists(P + '.bak') then DeleteFile(P + '.bak');
      2: if FileExists(P + '.tmp') then DeleteFile(P + '.tmp');
    end;
  S := TBEStore.Create(P);
  S.Put('K1', Vals([1]));
  Check(S.Save, 'a file with a record saved');
  S.Put('K2', Vals([2]));
  Check(S.Save, 'and the next one');
  S.Free;
  F := TFileStream.Create(P, fmOpenReadWrite);
  F.Position := F.Size;
  B := 0;
  F.WriteBuffer(B, 1);
  F.Free;
  S2 := TBEStore.Create(P);
  Check(S2.Load and (S2.Errors > 0) and (S2.Count('K1') = 1) and (S2.Count('K2') = 0),
    'a byte after the last record: the file is refused, the .bak is read');
  S2.Free;
  UnreadCount(Dir, True);
  { a save cut off between its two renames: no file, the old one as .bak, the complete new one as .tmp }
  for i := 0 to 3 do
    case i of
      0: if FileExists(P) then DeleteFile(P);
      1: if FileExists(P + '.bak') then DeleteFile(P + '.bak');
      2: if FileExists(P + '.tmp') then DeleteFile(P + '.tmp');
      3: if FileExists(P + '.new') then DeleteFile(P + '.new');
    end;
  S := TBEStore.Create(P);
  S.Put('old', Vals([1]));
  S.Save;
  S.Put('new', Vals([2]));
  S.Save;
  S.Free;
  Check(RenameFile(P, P + '.tmp'), 'the new file waits as .tmp');
  S2 := TBEStore.Create(P);
  Check(S2.Load and (S2.Count('new') = 1) and (S2.Count('old') = 1), 'no file: the complete .tmp is read, not the older .bak');
  S2.Put('after', Vals([3]));
  Check(S2.Save and FileExists(P) and (not FileExists(P + '.tmp')), 'the next save puts the file in place');
  S2.Free;
  { keys are compared by their bytes: a soft hyphen makes a different key }
  S := TBEStore.Create(Dir + 'keys.bdb');
  S.Put('ac:a' + #173 + 'b', Vals([111]));
  S.Put('ac:ab', Vals([222]));
  Check((S.Size = 2) and (S.Get('ac:ab', 0) = 222) and (S.Get('ac:a' + #173 + 'b', 0) = 111), 'a soft hyphen is a different key');
  Check(S.Save, 'those keys saved');
  S.Free;
  S2 := TBEStore.Create(Dir + 'keys.bdb');
  Check(S2.Load and (S2.Size = 2) and (S2.Get('ac:ab', 0) = 222), 'and loaded');
  S2.Free;
  { a file whose records are not in the order of the store (an older release sorted by the locale) }
  F := TFileStream.Create(Dir + 'order.bdb', fmCreate);
  F.WriteBuffer(BE_MAGIC, 4);
  i := NtoLE(LongInt(BE_FILE_VERSION));
  F.WriteBuffer(i, 4);
  i := NtoLE(LongInt(300));
  F.WriteBuffer(i, 4);
  for i := 300 downto 1 do
  begin
    Key := 'K' + IntToStr(i);
    N := Length(Key);
    B := N;
    F.WriteBuffer(B, 1);
    B := 0;
    F.WriteBuffer(B, 1);
    F.WriteBuffer(Key[1], N);
    B := 1;
    F.WriteBuffer(B, 1);
    N := NtoLE(LongInt(i));
    F.WriteBuffer(N, 4);
  end;
  F.Free;
  S2 := TBEStore.Create(Dir + 'order.bdb');
  Check(S2.Load and (S2.Size = 300) and (S2.Get('K1', 0) = 1) and (S2.Get('K300', 0) = 300) and (S2.Get('K150', 0) = 150),
    'a file in another order loads and every key is found');
  S2.Free;
  { a whole file that still waits is replaced by the newer text and is never dropped for the limit }
  W := TBEWriter.Create;
  for i := 1 to BE_MAX_LINES do
    W.Add(Dir + 'lim.txt', 'x');
  W.AddWhole(Dir + 'whole.bin', 'one');
  W.AddWhole(Dir + 'whole.bin', 'two');
  W.AddWhole(Dir + 'other.bin', 'three');
  Check(W.Pending = BE_MAX_LINES + 2, 'whole files wait beyond the limit, one entry per file');
  Check(W.Dropped = 0, 'none dropped');
  W.Free;
  { 4.2 (BE3-07): a whole file put in place in one step }
  Check(WriteFileAtomic(Dir + 'atomic.txt', 'one' + LineEnding), 'a new file written atomically');
  Check(WriteFileAtomic(Dir + 'atomic.txt', 'two two' + LineEnding), 'an existing file replaced');
  L := TStringList.Create;
  L.LoadFromFile(Dir + 'atomic.txt');
  Check((L.Count = 1) and (L[0] = 'two two') and (not FileExists(Dir + 'atomic.txt.tmp')), 'the new text is the file, no .tmp left');
  L.Free;
  {$IFDEF WINDOWS}
  { Windows only: Unix lets a file that is open be replaced }
  F := TFileStream.Create(Dir + 'atomic.txt', fmOpenRead or fmShareDenyWrite);
  Check(not WriteFileAtomic(Dir + 'atomic.txt', 'three'), 'a file held open without sharing: not replaced');
  F.Free;
  Check(not FileExists(Dir + 'atomic.txt.tmp'), 'and no .tmp left behind');
  L := TStringList.Create;
  L.LoadFromFile(Dir + 'atomic.txt');
  Check(L[0] = 'two two', 'the old file is as it was');
  L.Free;
  {$ENDIF}
end;

procedure TestWriter;
var
  W: TBEWriter;
  S: TBEStore;
  K: TBEWorker;
  L: TStringList;
  P: AnsiString;
  i: LongInt;
begin
  P := Dir + 'logs' + PathDelim + 'day.txt';
  if FileExists(P) then
    DeleteFile(P);
  W := TBEWriter.Create;
  S := TBEStore.Create(Dir + 'w.bdb');
  K := TBEWorker.Create(S, W);
  for i := 1 to 100 do
    W.Add(P, 'line ' + IntToStr(i));
  W.Add(Dir + 'logs' + PathDelim + 'watched.txt', 'watched');
  K.Wake;
  Sleep(1500);
  K.Terminate;
  K.Wake;
  K.WaitFor;
  K.Free;
  Check(W.Pending = 0, 'nothing waits');
  Check(W.Written = 101, 'every line written');
  L := TStringList.Create;
  L.LoadFromFile(P);
  Check(L.Count = 100, 'the day file has its 100 lines (folder made)');
  Check(L[99] = 'line 100', 'in order');
  L.Free;
  W.Free;
  S.Free;
end;

{ round 26 (F12): a whole file written by the worker (tmp, then in place; the old one kept as .bak) }
procedure TestWhole;
var
  W: TBEWriter;
  S: TBEStore;
  K: TBEWorker;
  L: TStringList;
  P: AnsiString;
begin
  P := Dir + 'whole' + PathDelim + 'mutes.txt';
  if FileExists(P) then
    DeleteFile(P);
  if FileExists(P + '.bak') then
    DeleteFile(P + '.bak');
  W := TBEWriter.Create;
  S := TBEStore.Create(Dir + 'w2.bdb');
  K := TBEWorker.Create(S, W);
  W.AddWhole(P, 'a=1' + LineEnding + 'b=2' + LineEnding);
  W.Add(P + '.log', 'between');
  K.Wake;
  Sleep(1200);
  { the next text comes when the first one is on the disk: it becomes the file and the first the .bak (one that is
    still waiting would be replaced by the newer text) }
  W.AddWhole(P, 'c=3' + LineEnding);
  K.Wake;
  Sleep(1500);
  K.Terminate;
  K.Wake;
  K.WaitFor;
  K.Free;
  Check(W.Pending = 0, 'whole: nothing waits');
  Check(W.Errors = 0, 'whole: no error');
  L := TStringList.Create;
  L.LoadFromFile(P);
  Check((L.Count = 1) and (L[0] = 'c=3'), 'whole: the last text is the file');
  L.LoadFromFile(P + '.bak');
  Check((L.Count = 2) and (L[1] = 'b=2'), 'whole: the one before is the .bak');
  Check(not FileExists(P + '.tmp'), 'whole: no .tmp left');
  L.Free;
  W.Free;
  S.Free;
end;

{ BE2-05: a control character does not start a new line; a log over the limit is rotated, a data file is not }
procedure TestLogRules;
var
  W: TBEWriter;
  S: TBEStore;
  K: TBEWorker;
  L: TStringList;
  P, Q: AnsiString;
  i: LongInt;
begin
  P := Dir + 'rot' + PathDelim + 'x.log';
  Q := Dir + 'rot' + PathDelim + 'bans.log';
  for i := 0 to 1 do
  begin
    if FileExists(P + '.1') then
      DeleteFile(P + '.1');
    if FileExists(P) then
      DeleteFile(P);
    if FileExists(Q + '.1') then
      DeleteFile(Q + '.1');
    if FileExists(Q) then
      DeleteFile(Q);
  end;
  BeLogMaxBytes := 100000;
  W := TBEWriter.Create;
  S := TBEStore.Create(Dir + 'w3.bdb');
  K := TBEWorker.Create(S, W);
  for i := 1 to 30 do
  begin
    W.Add(P, 'line number ' + IntToStr(i));
    W.Add(Q, 'line number ' + IntToStr(i));
  end;
  K.Wake;
  Sleep(1200);
  { the 30 lines are on the disk now: the limit comes down below their size }
  BeLogMaxBytes := 100;
  W.Add(P, 'a' + #13 + #10 + '12:00:01  Admin joined' + #9 + 'tab' + #0 + 'z');
  W.Add(Q, 'after');
  K.Wake;
  Sleep(1200);
  K.Terminate;
  K.Wake;
  K.WaitFor;
  K.Free;
  Check(W.Errors = 0, 'rotation: no error');
  Check(FileExists(P + '.1'), 'rotation: a big log is moved to .1');
  Check(not FileExists(Q + '.1'), 'rotation: bans.log (read back by the script) is not rotated');
  L := TStringList.Create;
  L.LoadFromFile(P);
  Check(L.Count = 1, 'rotation: the new file has the one new line (CR LF in it did not make two)');
  Check(L[0] = 'a  12:00:01  Admin joined' + #9 + 'tab z', 'control characters become spaces, a tab stays');
  L.LoadFromFile(P + '.1');
  Check(L.Count = 30, 'rotation: the old file has its 30 lines');
  L.LoadFromFile(Q);
  Check(L.Count = 31, 'rotation: the data log keeps growing');
  L.Free;
  BeLogMaxBytes := 5 * 1024 * 1024;
  W.Free;
  S.Free;
end;

begin
  if ParamCount < 1 then
  begin
    WriteLn('usage: test_store <scratch folder>');
    Halt(2);
  end;
  Dir := IncludeTrailingPathDelimiter(ParamStr(1));
  ForceDirectories(Dir);
  TestStore;
  TestHardening;
  TestWriter;
  TestWhole;
  TestLogRules;
  if Failed > 0 then
  begin
    WriteLn(Failed, ' failed');
    Halt(1);
  end;
  WriteLn('test_store: all passed');
end.
