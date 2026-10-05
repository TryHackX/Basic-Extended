unit be_prof;

{ How long the script's parts of a tick take (/be_prof): the script calls ProfBegin and ProfEnd
  around each part while profiling is on; the time comes from the high resolution clock
  (QueryPerformanceCounter, gettimeofday on Linux). }

{$mode objfpc}{$H+}
{$Q-}{$IFNDEF BE_CHECKS}{$R-}{$ENDIF}

interface

const
  PROF_N = 64;

procedure ProfBegin(Stage: LongInt);
procedure ProfEnd(Stage: LongInt);
procedure ProfReset;
function ProfText(Stage: LongInt; Ticks: LongInt): AnsiString;

implementation

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  {$IFDEF UNIX}BaseUnix, Unix,{$ENDIF}
  SysUtils;

var
  Sum, Mx, T0: array[0..PROF_N - 1] of Int64;
  Cnt: array[0..PROF_N - 1] of LongInt;
  {$IFDEF WINDOWS}
  Freq: Int64 = 0;
  {$ENDIF}

function NowUs: Int64;
{$IFDEF WINDOWS}
var
  c: Int64;
begin
  if Freq = 0 then
    if not QueryPerformanceFrequency(Freq) then
      Freq := 1000;
  c := 0;
  QueryPerformanceCounter(c);
  Result := (c div Freq) * 1000000 + (c mod Freq) * 1000000 div Freq;
end;
{$ELSE}
var
  tv: TTimeVal;
begin
  fpgettimeofday(@tv, nil);
  Result := Int64(tv.tv_sec) * 1000000 + tv.tv_usec;
end;
{$ENDIF}

procedure ProfBegin(Stage: LongInt);
begin
  if (Stage >= 0) and (Stage < PROF_N) then
    T0[Stage] := NowUs;
end;

procedure ProfEnd(Stage: LongInt);
var
  d: Int64;
begin
  if (Stage < 0) or (Stage >= PROF_N) then
    Exit;
  if T0[Stage] <= 0 then
    Exit;
  d := NowUs - T0[Stage];
  T0[Stage] := 0;
  if d < 0 then
    d := 0;
  Sum[Stage] := Sum[Stage] + d;
  Inc(Cnt[Stage]);
  if d > Mx[Stage] then
    Mx[Stage] := d;
end;

procedure ProfReset;
var
  k: LongInt;
begin
  for k := 0 to PROF_N - 1 do
  begin
    Sum[k] := 0;
    Mx[k] := 0;
    T0[k] := 0;
    Cnt[k] := 0;
  end;
end;

{ "N runs, X us a run on average, Y us at most, Z us a tick" (Ticks: the ticks the profile covers) }
function ProfText(Stage: LongInt; Ticks: LongInt): AnsiString;
var
  T10: Int64;
begin
  Result := '';
  if (Stage < 0) or (Stage >= PROF_N) then
    Exit;
  if Cnt[Stage] = 0 then
    Exit;
  if Ticks < 1 then
    Ticks := 1;
  T10 := Sum[Stage] * 10 div Ticks;
  Result := IntToStr(Cnt[Stage]) + ' runs, ' + IntToStr(Sum[Stage] div Cnt[Stage]) + ' us a run, ' +
    IntToStr(Mx[Stage]) + ' us at most, ' + IntToStr(T10 div 10) + '.' + IntToStr(T10 mod 10) + ' us a tick';
end;

end.
