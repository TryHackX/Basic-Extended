unit be_util;

{$mode objfpc}{$H+}

interface

const
  HUD_STYLES = 5;

function Fill(const Template, Pairs: AnsiString): AnsiString;
procedure HudStyle(Style: LongInt; const Template: AnsiString);
procedure HudBar(const Full, Empty: AnsiString; Len: LongInt);
procedure HudRegen(const Mark: AnsiString);
function HudText(Style, Pct, Hp, MaxHp, Vest, Regen: LongInt): AnsiString;
function StampLine(const Text: AnsiString): AnsiString;
function DayFile(const Folder: AnsiString): AnsiString;

implementation

uses
  SysUtils;

var
  Styles: array[1..HUD_STYLES] of AnsiString;
  Bars: array[0..40] of AnsiString;
  BarLen: LongInt = 10;
  RegenMark: AnsiString = '+';

function Fill(const Template, Pairs: AnsiString): AnsiString;
var
  p, q: LongInt;
  Rest, K, V: AnsiString;
begin
  Result := Template;
  if Pos('{', Result) = 0 then
    Exit;
  Rest := Pairs;
  while Rest <> '' do
  begin
    p := Pos(#1, Rest);
    if p = 0 then
      Break;
    K := Copy(Rest, 1, p - 1);
    Delete(Rest, 1, p);
    q := Pos(#1, Rest);
    if q = 0 then
    begin
      V := Rest;
      Rest := '';
    end
    else
    begin
      V := Copy(Rest, 1, q - 1);
      Delete(Rest, 1, q);
    end;
    if (K <> '') and (Pos(K, Result) > 0) then
      Result := StringReplace(Result, K, V, [rfReplaceAll]);
  end;
end;

procedure HudStyle(Style: LongInt; const Template: AnsiString);
begin
  if (Style >= 1) and (Style <= HUD_STYLES) then
    Styles[Style] := Template;
end;

procedure HudBar(const Full, Empty: AnsiString; Len: LongInt);
var
  i, k: LongInt;
begin
  if Len < 1 then
    Len := 1;
  if Len > 40 then
    Len := 40;
  BarLen := Len;
  for i := 0 to Len do
  begin
    Bars[i] := '';
    for k := 1 to Len do
      if k <= i then
        Bars[i] := Bars[i] + Full
      else
        Bars[i] := Bars[i] + Empty;
  end;
end;

procedure HudRegen(const Mark: AnsiString);
begin
  RegenMark := Mark;
end;

function HudText(Style, Pct, Hp, MaxHp, Vest, Regen: LongInt): AnsiString;
var
  b: LongInt;
begin
  if (Style < 1) or (Style > HUD_STYLES) then
    Style := 1;
  Result := Styles[Style];
  if Pos('{', Result) = 0 then
    Exit;
  if Pct < 0 then
    Pct := 0;
  if Pct > 100 then
    Pct := 100;
  Result := StringReplace(Result, '{pct}', IntToStr(Pct), [rfReplaceAll]);
  Result := StringReplace(Result, '{hp}', IntToStr(Hp), [rfReplaceAll]);
  Result := StringReplace(Result, '{max}', IntToStr(MaxHp), [rfReplaceAll]);
  Result := StringReplace(Result, '{vest}', IntToStr(Vest), [rfReplaceAll]);
  if Pos('{bar}', Result) > 0 then
  begin
    b := Round(Pct * BarLen * 0.01);
    if b < 0 then
      b := 0;
    if b > BarLen then
      b := BarLen;
    Result := StringReplace(Result, '{bar}', Bars[b], [rfReplaceAll]);
  end;
  if Regen <> 0 then
    Result := StringReplace(Result, '{regen}', RegenMark, [rfReplaceAll])
  else
    Result := StringReplace(Result, '{regen}', '', [rfReplaceAll]);
end;

function StampLine(const Text: AnsiString): AnsiString;
begin
  Result := FormatDateTime('hh:nn:ss', Now) + '  ' + Text;
end;

function DayFile(const Folder: AnsiString): AnsiString;
begin
  Result := Folder + FormatDateTime('yyyy-mm-dd', Now) + '.txt';
end;

var
  i: LongInt;

initialization
  for i := 1 to HUD_STYLES do
    Styles[i] := '{pct}%';
  HudBar('|', '.', 10);
end.
