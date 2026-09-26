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

procedure TestStore;
var
  S, S2: TBEStore;
  P: AnsiString;
  L: TStringList;
  F: TFileStream;
  B: Byte;
begin
  P := Dir + 'players.bdb';
  if FileExists(P) then
    DeleteFile(P);
  if FileExists(P + '.bak') then
    DeleteFile(P + '.bak');
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

begin
  if ParamCount < 1 then
  begin
    WriteLn('usage: test_store <scratch folder>');
    Halt(2);
  end;
  Dir := IncludeTrailingPathDelimiter(ParamStr(1));
  ForceDirectories(Dir);
  TestStore;
  TestWriter;
  if Failed > 0 then
  begin
    WriteLn(Failed, ' failed');
    Halt(1);
  end;
  WriteLn('test_store: all passed');
end.
