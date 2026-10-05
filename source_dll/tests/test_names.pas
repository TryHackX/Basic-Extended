program test_names;

{ be_names: the maps of a folder, the names a part of a name means (rank, order, limits) }

{$mode objfpc}{$H+}

uses
  SysUtils, be_names;

var
  Failed, Passed: LongInt;

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

procedure Touch(const Path: string);
var
  F: TextFile;
begin
  AssignFile(F, Path);
  Rewrite(F);
  CloseFile(F);
end;

var
  L, Dir: AnsiString;
  n, i: LongInt;
begin
  Failed := 0;
  Passed := 0;
  L := 'ctf_Ash|ctf_Ascent|ctf_Laos|inf_Fortress|ctf_Ash2|rscs_Ash_Forest|htf_Arch|ctf_Kampf|ctf_Ash';
  n := NamesRank(L, 'ctf_ash');
  Check((n >= 1) and (NamesGet(0) = 'ctf_Ash') and (NamesRankOf(0) = 0), 'the exact name first (case ignored)');
  Check(n = 2, 'ctf_Ash once (the list has it twice) and ctf_Ash2 - ' + IntToStr(n));
  n := NamesRank(L, 'ash');
  Check((n = 3) and (NamesGet(0) = 'ctf_Ash') and (NamesRankOf(0) = 2), 'a word''s start: ctf_Ash first (shorter)');
  Check((NamesGet(1) = 'ctf_Ash2') and (NamesGet(2) = 'rscs_Ash_Forest'), 'then the longer names');
  n := NamesRank(L, 'ctf_a');
  Check((n = 3) and (NamesRankOf(0) = 1) and (NamesGet(0) = 'ctf_Ash'), 'the start: ctf_Ash, ctf_Ash2, ctf_Ascent');
  n := NamesRank(L, 'ort');
  Check((n = 1) and (NamesGet(0) = 'inf_Fortress') and (NamesRankOf(0) = 3), 'anywhere in it');
  n := NamesRank(L, 'ctf ash');
  Check((n >= 1) and (NamesGet(0) = 'ctf_Ash'), 'a space for the underscore');
  n := NamesRank(L, 'ctf_Laos.pms');
  Check((n = 1) and (NamesGet(0) = 'ctf_Laos'), 'the .pms ending left out');
  n := NamesRank(L, 'zzz');
  Check(n = 0, 'no match');
  n := NamesRank(L, '');
  Check(n = 0, 'an empty part matches nothing');
  Check(NamesGet(5) = '', 'beyond the matches: empty');
  { many names: at most NAMES_MAX, the best kept }
  L := '';
  for i := 1 to 100 do
  begin
    if L <> '' then
      L := L + '|';
    L := L + 'map_x' + IntToStr(i);
  end;
  L := L + '|x';
  n := NamesRank(L, 'x');
  Check((n = NAMES_MAX) and (NamesGet(0) = 'x'), 'at most ' + IntToStr(NAMES_MAX) + ', the exact one first');
  { a folder }
  Dir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'be_names_test' + PathDelim;
  ForceDirectories(Dir);
  Touch(Dir + 'ctf_Ash.pms');
  Touch(Dir + 'INF_Moon.PMS');
  Touch(Dir + 'readme.txt');
  Touch(Dir + 'ctf_Ash.pms.bak');
  L := NamesFolder(Dir, '.pms');
  Check(L = 'ctf_Ash|INF_Moon', 'the folder: the .pms maps, sorted, no extension - ' + L);
  DeleteFile(Dir + 'ctf_Ash.pms');
  DeleteFile(Dir + 'INF_Moon.PMS');
  DeleteFile(Dir + 'readme.txt');
  DeleteFile(Dir + 'ctf_Ash.pms.bak');
  RemoveDir(Dir);
  Check(NamesFolder(Dir, '.pms') = '', 'a folder that is not there: nothing');
  WriteLn(Passed, ' passed, ', Failed, ' failed');
  if Failed > 0 then
    Halt(1);
end.
