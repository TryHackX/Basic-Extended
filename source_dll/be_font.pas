unit be_font;

{$mode objfpc}{$H+}

interface

const
  FONT_ASCENT = 937;
  FONT_STRETCH = 1.5;
  WORLD_EM = 170.6667;
  BIG_EM = 179.2;

function TextAdvance(const S: AnsiString): Single;
procedure InkBox(const S: AnsiString; out L, T, R, B: Single);
procedure InkCenter(const S: AnsiString; out CX, CY: Single);

implementation

const
  PlayAdv: array[32..126] of SmallInt = (
    230, 280, 443, 580, 580, 855, 636, 256, 331, 331, 398, 500, 256, 358, 256, 421, 580, 580, 580,
    580, 580, 580, 580, 580, 580, 580, 256, 256, 500, 500, 500, 533, 737, 652, 613, 564, 679, 580,
    560, 666, 707, 265, 403, 609, 520, 861, 723, 679, 570, 676, 612, 569, 585, 676, 652, 968, 604,
    584, 580, 330, 421, 330, 321, 580, 239, 538, 579, 464, 571, 535, 380, 569, 573, 246, 247, 514,
    246, 890, 573, 568, 579, 579, 351, 483, 402, 573, 463, 792, 479, 460, 454, 330, 335, 330, 580);
  PlayX0: array[32..126] of SmallInt = (
    0, 80, 85, 60, 60, 46, 60, 85, 79, 26, 26, 60, 39, 40, 70, 10, 61, 122, 72, 77, 52, 87, 71, 62,
    59, 71, 70, 39, 60, 60, 60, 60, 60, 15, 84, 64, 84, 84, 84, 64, 84, 84, 20, 84, 84, 84, 84, 66,
    84, 64, 84, 60, 24, 84, 15, 8, 8, 8, 40, 84, 10, 20, 20, 71, 20, 50, 78, 60, 60, 60, 10, 60,
    78, 78, -43, 78, 78, 78, 78, 60, 78, 78, 78, 50, 10, 78, 6, 12, 10, 6, 40, 64, 140, 44, 68);
  PlayY0: array[32..126] of SmallInt = (
    0, 0, 429, 0, -140, -10, -10, 429, -127, -127, 320, 115, -112, 250, 0, -10, -10, 0, 0, -10, 0,
    -10, -10, 0, -10, -10, 0, -112, 62, 202, 62, 0, -90, 0, 0, -10, 0, 0, 0, -10, 0, 0, -10, 0, 0,
    0, 0, -10, 0, 0, 0, -10, 0, -10, 0, 0, 0, 0, 0, -190, -10, -190, 453, -141, 553, -10, -10, -10,
    -10, -10, 0, -220, 0, 0, -220, 0, 0, 0, 0, -10, -208, -208, 0, -10, -10, -10, 0, 0, 0, -208, 0,
    -190, -10, -190, 235);
  PlayX1: array[32..126] of SmallInt = (
    0, 200, 358, 520, 524, 809, 610, 171, 305, 252, 372, 440, 191, 318, 186, 411, 519, 406, 508,
    503, 528, 493, 509, 518, 520, 509, 186, 191, 440, 440, 440, 473, 677, 637, 553, 519, 615, 530,
    530, 602, 623, 181, 319, 619, 500, 777, 639, 613, 525, 682, 580, 514, 561, 591, 637, 960, 596,
    576, 540, 310, 411, 246, 301, 509, 219, 460, 519, 428, 501, 476, 382, 491, 495, 168, 169, 512,
    168, 812, 495, 506, 519, 519, 339, 437, 382, 495, 457, 780, 469, 454, 420, 286, 195, 266, 512);
  PlayY1: array[32..126] of SmallInt = (
    0, 649, 649, 639, 709, 660, 660, 649, 679, 679, 649, 515, 108, 322, 108, 660, 660, 649, 660,
    659, 649, 649, 660, 649, 660, 660, 484, 484, 560, 429, 560, 659, 579, 649, 649, 660, 649, 649,
    649, 659, 649, 649, 649, 649, 649, 649, 649, 659, 649, 659, 649, 659, 649, 649, 649, 649, 649,
    649, 649, 736, 659, 736, 680, -70, 680, 494, 700, 494, 700, 494, 710, 494, 700, 659, 659, 700,
    700, 494, 494, 494, 494, 494, 494, 494, 634, 484, 484, 484, 484, 484, 484, 736, 659, 736, 364);

function Code(C: AnsiChar): LongInt;
begin
  Result := Ord(C);
  if (Result < 32) or (Result > 126) then
    Result := 63;
end;

function TextAdvance(const S: AnsiString): Single;
var
  i: LongInt;
  W: LongInt;
begin
  W := 0;
  for i := 1 to Length(S) do
    Inc(W, PlayAdv[Code(S[i])]);
  Result := W * FONT_STRETCH / 1000;
end;

procedure InkBox(const S: AnsiString; out L, T, R, B: Single);
var
  i, c, Pen, Line: LongInt;
  Any: Boolean;
  gl, gr, gt, gb: Single;
begin
  L := 0;
  T := 0;
  R := 0;
  B := 0;
  Any := False;
  Pen := 0;
  Line := 0;
  for i := 1 to Length(S) do
  begin
    if S[i] = #10 then
    begin
      Pen := 0;
      Inc(Line);
      Continue;
    end;
    if S[i] = #13 then
      Continue;
    c := Code(S[i]);
    if PlayX1[c] > PlayX0[c] then
    begin
      gl := (Pen + PlayX0[c]) * FONT_STRETCH / 1000;
      gr := (Pen + PlayX1[c]) * FONT_STRETCH / 1000;
      gt := (Line * 1157 + FONT_ASCENT - PlayY1[c]) / 1000;
      gb := (Line * 1157 + FONT_ASCENT - PlayY0[c]) / 1000;
      if not Any then
      begin
        L := gl;
        R := gr;
        T := gt;
        B := gb;
        Any := True;
      end
      else
      begin
        if gl < L then
          L := gl;
        if gr > R then
          R := gr;
        if gt < T then
          T := gt;
        if gb > B then
          B := gb;
      end;
    end;
    Inc(Pen, PlayAdv[c]);
  end;
end;

procedure InkCenter(const S: AnsiString; out CX, CY: Single);
var
  L, T, R, B: Single;
begin
  InkBox(S, L, T, R, B);
  CX := (L + R) / 2;
  CY := (T + B) / 2;
end;

end.
