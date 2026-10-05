unit be_names;

{ Names found by a part of them: the maps of a folder, the maps of the server's list. A part matches a name
  (letter case ignored) exactly, at its start, at the start of one of its words (after _ - . or a space), or
  anywhere in it - in that order; equal ranks go to the shorter name, then by the alphabet. }

{$mode objfpc}{$H+}

interface

const
  NAMES_MAX = 64;

{ the files of Folder with the extension Ext ('.pms'), without it, sorted, joined by '|' }
function NamesFolder(const Folder, Ext: AnsiString): AnsiString;
{ the names of List ('a|b|c') that Part matches, best first (at most NAMES_MAX); their count }
function NamesRank(const List, Part: AnsiString): LongInt;
{ the rank of match Index of the last NamesRank: 0 exact, 1 start, 2 a word's start, 3 anywhere }
function NamesRankOf(Index: LongInt): LongInt;
function NamesGet(Index: LongInt): AnsiString;

implementation

uses
  SysUtils, Classes;

var
  Found: array[0..NAMES_MAX - 1] of AnsiString;
  FoundRank: array[0..NAMES_MAX - 1] of LongInt;
  FoundN: LongInt = 0;

function NamesFolder(const Folder, Ext: AnsiString): AnsiString;
var
  SR: TSearchRec;
  L: TStringList;
  i: LongInt;
  Dir, E, N: AnsiString;
begin
  Result := '';
  Dir := Folder;
  if Dir <> '' then
    if not (Dir[Length(Dir)] in ['/', '\']) then
      Dir := Dir + '/';
  E := LowerCase(Ext);
  L := TStringList.Create;
  try
    L.Sorted := False;
    if FindFirst(Dir + '*', faAnyFile, SR) = 0 then
    begin
      repeat
        if (SR.Attr and faDirectory) = 0 then
        begin
          N := SR.Name;
          if E <> '' then
          begin
            if LowerCase(ExtractFileExt(N)) <> E then
              Continue;
            N := Copy(N, 1, Length(N) - Length(ExtractFileExt(N)));
          end;
          if (N <> '') and (Pos('|', N) = 0) then
            L.Add(N);
        end;
      until FindNext(SR) <> 0;
      FindClose(SR);
    end;
    L.CaseSensitive := False;
    L.Sort;
    for i := 0 to L.Count - 1 do
    begin
      if i > 0 then
        Result := Result + '|';
      Result := Result + L[i];
    end;
  finally
    L.Free;
  end;
end;

{ the rank of Part in Name: 0 exact, 1 the start, 2 a word's start, 3 anywhere, -1 no match }
function RankOf(const Name, Part: AnsiString): LongInt;
var
  N, P: AnsiString;
  k: LongInt;
begin
  Result := -1;
  N := LowerCase(Name);
  P := LowerCase(Part);
  if P = '' then
    Exit;
  if N = P then
  begin
    Result := 0;
    Exit;
  end;
  if Copy(N, 1, Length(P)) = P then
  begin
    Result := 1;
    Exit;
  end;
  for k := 2 to Length(N) - Length(P) + 1 do
    if N[k - 1] in ['_', '-', '.', ' '] then
      if Copy(N, k, Length(P)) = P then
      begin
        Result := 2;
        Exit;
      end;
  if Pos(P, N) > 0 then
    Result := 3;
end;

{ a before b: the better rank, then the shorter name, then the alphabet }
function Better(const A: AnsiString; RA: LongInt; const B: AnsiString; RB: LongInt): Boolean;
begin
  if RA <> RB then
    Result := RA < RB
  else if Length(A) <> Length(B) then
    Result := Length(A) < Length(B)
  else
    Result := CompareText(A, B) < 0;
end;

function NamesRank(const List, Part: AnsiString): LongInt;
var
  S, N, P: AnsiString;
  p0, R, k, j: LongInt;
begin
  FoundN := 0;
  Result := 0;
  P := Trim(Part);
  if LowerCase(ExtractFileExt(P)) = '.pms' then
    P := Copy(P, 1, Length(P) - 4);
  if P = '' then
    Exit;
  S := List + '|';
  while S <> '' do
  begin
    p0 := Pos('|', S);
    N := Copy(S, 1, p0 - 1);
    Delete(S, 1, p0);
    if N = '' then
      Continue;
    R := RankOf(N, P);
    { "ctf ash" finds ctf_Ash too }
    if R < 0 then
      if Pos(' ', P) > 0 then
        R := RankOf(N, StringReplace(P, ' ', '_', [rfReplaceAll]));
    if R < 0 then
      Continue;
    { the same name once (a list may hold a map twice) }
    k := 0;
    while k < FoundN do
    begin
      if CompareText(Found[k], N) = 0 then
        Break;
      Inc(k);
    end;
    if k < FoundN then
      Continue;
    { in its place in the order }
    k := FoundN;
    while (k > 0) and Better(N, R, Found[k - 1], FoundRank[k - 1]) do
      Dec(k);
    if k >= NAMES_MAX then
      Continue;
    if FoundN < NAMES_MAX then
      Inc(FoundN);
    for j := FoundN - 1 downto k + 1 do
    begin
      Found[j] := Found[j - 1];
      FoundRank[j] := FoundRank[j - 1];
    end;
    Found[k] := N;
    FoundRank[k] := R;
  end;
  Result := FoundN;
end;

function NamesRankOf(Index: LongInt): LongInt;
begin
  Result := -1;
  if (Index >= 0) and (Index < FoundN) then
    Result := FoundRank[Index];
end;

function NamesGet(Index: LongInt): AnsiString;
begin
  Result := '';
  if (Index >= 0) and (Index < FoundN) then
    Result := Found[Index];
end;

end.
