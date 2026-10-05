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
function HudTextEx(Style, Pct, Hp, MaxHp, Vest, Regen, Ammo, Mag, Wep, AppendAmmo: LongInt): AnsiString;
function StampLine(const Text: AnsiString): AnsiString;
function DayFile(const Folder: AnsiString): AnsiString;
{ [AntiSpam] a chat line weighed in one pass: the line folded for the repeat test (small letters and digits, a
  character repeated once, at most 60 of the first 200), the share of capitals among its letters (0 with fewer than
  8 letters) and the share of its commonest character but the space (0 for a line under 8) }
function ChatWeigh(const Text: AnsiString; out Caps, OneChar: LongInt): AnsiString;

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
  p, q, i, n, k: LongInt;
  Rest: AnsiString;
  Keys, Vals: array of AnsiString;
  Hit: Boolean;
begin
  Result := Template;
  if Pos('{', Result) = 0 then
    Exit;
  { the pairs }
  n := 0;
  Rest := Pairs;
  while Rest <> '' do
  begin
    p := Pos(#1, Rest);
    if p = 0 then
      Break;
    SetLength(Keys, n + 1);
    SetLength(Vals, n + 1);
    Keys[n] := Copy(Rest, 1, p - 1);
    Delete(Rest, 1, p);
    q := Pos(#1, Rest);
    if q = 0 then
    begin
      Vals[n] := Rest;
      Rest := '';
    end
    else
    begin
      Vals[n] := Copy(Rest, 1, q - 1);
      Delete(Rest, 1, q);
    end;
    if Keys[n] <> '' then
      Inc(n);
  end;
  { one walk over the template: a key at a place is replaced by its value; the value is not looked at again }
  Result := '';
  i := 1;
  while i <= Length(Template) do
  begin
    Hit := False;
    if Template[i] = '{' then
      for k := 0 to n - 1 do
        if not Hit then
          if Copy(Template, i, Length(Keys[k])) = Keys[k] then
          begin
            Result := Result + Vals[k];
            Inc(i, Length(Keys[k]));
            Hit := True;
          end;
    if not Hit then
    begin
      Result := Result + Template[i];
      Inc(i);
    end;
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

function HudTextEx(Style, Pct, Hp, MaxHp, Vest, Regen, Ammo, Mag, Wep, AppendAmmo: LongInt): AnsiString;
var
  b: LongInt;
  HasAmmoTag: Boolean;
begin
  if (Style < 1) or (Style > HUD_STYLES) then
    Style := 1;
  Result := Styles[Style];
  if Pct < 0 then
    Pct := 0;
  if Pct > 100 then
    Pct := 100;
  if Pos('{', Result) > 0 then
  begin
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

  HasAmmoTag := Pos('{ammo}', Result) > 0;
  if HasAmmoTag then
    Result := StringReplace(Result, '{ammo}', IntToStr(Ammo), [rfReplaceAll])
  else if (AppendAmmo <> 0) and (Wep >= 0) and (Wep <= 16) and (Wep <> 255) then
  begin
    if Wep = 12 then
      Result := Result + ' | Fuel: ' + IntToStr(Mag)
    else if Mag >= 0 then
      Result := Result + ' | Ammo: ' + IntToStr(Mag) + ' [' + IntToStr(Ammo) + 'm]'
    else
      Result := Result + ' | Ammo: ' + IntToStr(Ammo);
  end;

  if Pos('{mag}', Result) > 0 then
    Result := StringReplace(Result, '{mag}', IntToStr(Mag), [rfReplaceAll]);
end;

function HudText(Style, Pct, Hp, MaxHp, Vest, Regen: LongInt): AnsiString;
begin
  Result := HudTextEx(Style, Pct, Hp, MaxHp, Vest, Regen, 0, 0, 255, 0);
end;

function StampLine(const Text: AnsiString): AnsiString;
begin
  Result := FormatDateTime('hh:nn:ss', Now) + '  ' + Text;
end;

function ChatWeigh(const Text: AnsiString; out Caps, OneChar: LongInt): AnsiString;
var
  i, n, c, Last, Up, Al, Best: LongInt;
  Cnt: array[0..255] of LongInt;
  Full: Boolean;
begin
  Result := '';
  Caps := 0;
  OneChar := 0;
  n := Length(Text);
  if n > 200 then
    n := 200;
  FillChar(Cnt, SizeOf(Cnt), 0);
  Last := -1;
  Up := 0;
  Al := 0;
  Best := 0;
  Full := False;
  for i := 1 to n do
  begin
    c := Ord(Text[i]) and 255;
    if (c >= 65) and (c <= 90) then
    begin
      Inc(Up);
      Inc(Al);
    end
    else if (c >= 97) and (c <= 122) then
      Inc(Al);
    if c <> 32 then
    begin
      Inc(Cnt[c]);
      if Cnt[c] > Best then
        Best := Cnt[c];
    end;
    if not Full then
    begin
      if (c >= 65) and (c <= 90) then
        c := c + 32;
      if ((c >= 97) and (c <= 122)) or ((c >= 48) and (c <= 57)) then
        if c <> Last then
        begin
          Result := Result + Chr(c);
          Last := c;
          if Length(Result) >= 60 then
            Full := True;
        end;
    end;
  end;
  if Al >= 8 then
    Caps := Up * 100 div Al;
  if Length(Text) >= 8 then
    OneChar := Best * 100 div n;
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
