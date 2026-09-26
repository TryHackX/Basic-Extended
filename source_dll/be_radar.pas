unit be_radar;

{$mode objfpc}{$H+}

interface

uses
  be_world, be_texts, be_font;

const
  OVL_LIST = 0;
  OVL_LABELS = 1;
  OVL_CIRCLE = 2;
  OVL_ARROWS = 3;
  OVL_RING = 3;
  RC_TEAM = 0;
  RC_DISTANCE = 1;
  RC_HEALTH = 2;
  RO_FRIENDS = 1;
  TAG_NONE = 0;
  TAG_FLAG = 1;
  TAG_BOW = 2;
  RING_MAX = 32;
  ARROW_DOTS_MAX = 8;
  ARROWS_MAX = 8;

  RI_LIST_LINES = 1;
  RI_LIST_LAYER = 2;
  RI_LIST_COLOR = 3;
  RI_CIRCLE_DOTS = 4;
  RI_CIRCLE_LAYER = 5;
  RI_RING_COLOR = 6;
  RI_SELF_COLOR = 7;
  RI_ENEMY_COLOR = 8;
  RI_FRIEND_COLOR = 9;
  RI_SHOW_FAR = 10;
  RI_LABEL_LAYER = 12;
  RI_ARROWS_MAX = 13;
  RI_ARROW_DOTS = 14;
  RI_ARROW_LAYER = 15;
  RI_ARROW_NEAR = 16;
  RI_ARROW_MID = 17;
  RI_ARROW_FAR = 18;
  RI_REFRESH = 19;
  RI_MARK_DISPLAY = 20;
  RI_LIST_DISPLAY = 21;
  RI_METER_DECIMALS = 22;
  RI_COLOR_FULL = 23;
  RI_COLOR_HALF = 24;
  RI_COLOR_LOW = 25;
  RI_VIS_RAYS = 26;
  RI_VIS_ROUND = 27;
  RI_TEAMGAME = 28;
  RI_ARROW_STEPS = 29;
  RI_RING_COLOR_BY = 30;

  RF_RANGE = 1;
  RF_LIST_SCALE = 2;
  RF_CIRCLE_R = 3;
  RF_CIRCLE_SCALE = 4;
  RF_LABEL_SCALE = 5;
  RF_LABEL_OFFSET = 6;
  RF_SIZE_RANGE = 7;
  RF_ARROW_INNER = 8;
  RF_ARROW_OUTER = 9;
  RF_ARROW_HEAD = 10;
  RF_ARROW_WIDTH = 11;
  RF_ARROW_SCALE = 12;
  RF_ARROW_MOVE = 13;
  RF_ARROW_LEAD = 14;
  RF_LABEL_MOVE = 15;
  RF_TAG_SCALE = 16;
  RF_CIRCLE_MOVE = 17;
  RF_RING_NEAR_SCALE = 18;
  RF_RING_FAR_SCALE = 19;

  RT_RING = 1;
  RT_SELF = 2;
  RT_ENEMY = 3;
  RT_FRIEND = 4;
  RT_FAR = 5;
  RT_FLAG = 6;
  RT_BOW = 7;
  RT_ARROW = 8;
  RT_LIST_TITLE = 9;
  RT_LIST_LINE = 10;
  RT_EDIT = 11;
  RT_NOBODY = 12;

procedure RadarInt(Key, Value: LongInt);
procedure RadarFloat(Key: LongInt; Value: Single);
procedure RadarText(Key: LongInt; const Value: AnsiString);
procedure RadarUser(ID, On, Mode, Show, PX, PY: LongInt; Size, Zoom, MarkSize: Single; Editing: LongInt);
procedure RadarOpt(ID, Key, Value: LongInt);
function RadarPass(ID, Tick, Budget: LongInt): LongInt;
function RadarHide(ID, Budget: LongInt): LongInt;
function RadarPending(ID: LongInt): LongInt;
procedure RadarReset(ID: LongInt);
procedure RadarRedraw(ID: LongInt);
function RadarRange(ID: LongInt): Single;
function FloatText(V: Double; Decimals: LongInt): AnsiString;
function HealthColor(Pct: LongInt): LongInt;

implementation

uses
  SysUtils;

type
  TRadarUser = record
    On, Editing, Pending: Boolean;
    Mode, Show, PX, PY: LongInt;
    Size, Zoom, MarkSize: Single;
    Friends: Boolean;
    Sent: TTextSet;
    RingBand: array[1..BE_PLAYERS] of LongInt;
  end;

var
  Users: array[1..BE_PLAYERS] of TRadarUser;
  OwnBig, OwnWorld: TOwnMask;
  ListLines: LongInt = 8;
  ListLayer: LongInt = 198;
  ListColor: LongInt = $E0E0E0;
  CircleDots: LongInt = 16;
  CircleLayer: LongInt = 110;
  RingColor: LongInt = $808080;
  SelfColor: LongInt = $FFFFFF;
  EnemyColor: LongInt = $FF4040;
  FriendColor: LongInt = $40FF40;
  ShowFar: Boolean = True;
  LabelLayer: LongInt = 150;
  ArrowsMax: LongInt = 6;
  ArrowDots: LongInt = 2;
  ArrowSteps: LongInt = 4;
  RingColorBy: LongInt = RC_TEAM;
  RingNearScale: Single = 0.16;
  RingFarScale: Single = 0.07;
  ArrowLayer: LongInt = 210;
  ArrowNear: LongInt = $FF2020;
  ArrowMid: LongInt = $FFFF20;
  ArrowFar: LongInt = $20FF20;
  RefreshTicks: LongInt = 300;
  MarkDisplay: LongInt = 900;
  ListDisplay: LongInt = 3600;
  MeterDecimals: LongInt = 2;
  ColorFull: LongInt = $00FF00;
  ColorHalf: LongInt = $FFFF00;
  ColorLow: LongInt = $FF0000;
  Range: Single = 700;
  ListScale: Single = 0.018;
  CircleR: Single = 50;
  CircleScale: Single = 0.03;
  LabelScale: Single = 0.02;
  LabelOffset: Single = 25;
  SizeRange: Single = 0.25;
  ArrowInner: Single = 16;
  ArrowOuter: Single = 32;
  ArrowHead: Single = 6;
  ArrowWidth: Single = 5;
  ArrowScale: Single = 0.085;
  ArrowMove: Single = 1.5;
  ArrowLead: Single = 1;
  LabelMove: Single = 2;
  TagScale: Single = 0.5;
  CircleMove: Single = 1;
  RingChar: AnsiString = '.';
  SelfChar: AnsiString = '+';
  EnemyChar: AnsiString = 'o';
  FriendChar: AnsiString = 'o';
  FarChar: AnsiString = '.';
  FlagChar: AnsiString = 'F';
  BowChar: AnsiString = 'R';
  ArrowChar: AnsiString = '.';
  ListTitle: AnsiString = 'Radar';
  ListLine: AnsiString = '{dir} {tag}{name} {pct}% {m}';
  EditMark: AnsiString = ' <edit>';
  NobodyText: AnsiString = '(nobody within {range})';
  HealthAt: array[0..100] of LongInt;
  HealthReady: Boolean = False;

function FloatText(V: Double; Decimals: LongInt): AnsiString;
var
  i: LongInt;
  Scale, All, Frac: Int64;
  Neg: Boolean;
  S: AnsiString;
begin
  if Decimals < 0 then
    Decimals := 0;
  if Decimals > 4 then
    Decimals := 4;
  Neg := V < 0;
  if Neg then
    V := -V;
  Scale := 1;
  for i := 1 to Decimals do
    Scale := Scale * 10;
  All := Round(V * Scale);
  Frac := All mod Scale;
  Result := IntToStr(All div Scale);
  if Decimals > 0 then
  begin
    S := IntToStr(Frac);
    while Length(S) < Decimals do
      S := '0' + S;
    Result := Result + '.' + S;
  end;
  if Neg and (All <> 0) then
    Result := '-' + Result;
end;

procedure BuildHealth;
var
  i: LongInt;
begin
  for i := 0 to 100 do
    if i >= 50 then
      HealthAt[i] := MixColor(ColorHalf, ColorFull, (i - 50) * 0.02)
    else
      HealthAt[i] := MixColor(ColorLow, ColorHalf, i * 0.02);
  HealthReady := True;
end;

function HealthColor(Pct: LongInt): LongInt;
begin
  if not HealthReady then
    BuildHealth;
  if Pct < 0 then
    Pct := 0;
  if Pct > 100 then
    Pct := 100;
  Result := HealthAt[Pct];
end;

procedure BuildOwned;
var
  i: LongInt;
begin
  for i := 0 to 255 do
  begin
    OwnBig[i] := False;
    OwnWorld[i] := False;
  end;
  if (ListLayer >= 0) and (ListLayer <= 255) then
    OwnBig[ListLayer] := True;
  for i := CircleLayer to CircleLayer + RING_MAX + BE_PLAYERS do
    if (i >= 0) and (i <= 255) then
      OwnBig[i] := True;
  for i := LabelLayer to LabelLayer + BE_PLAYERS - 1 do
    if (i >= 0) and (i <= 255) then
      OwnWorld[i] := True;
  for i := ArrowLayer to ArrowLayer + BE_PLAYERS - 1 do
    if (i >= 0) and (i <= 255) then
      OwnWorld[i] := True;
end;

procedure RadarInt(Key, Value: LongInt);
begin
  case Key of
    RI_LIST_LINES: ListLines := Value;
    RI_LIST_LAYER: ListLayer := Value;
    RI_LIST_COLOR: ListColor := Value;
    RI_CIRCLE_DOTS: if (Value >= 0) and (Value <= RING_MAX) then CircleDots := Value;
    RI_CIRCLE_LAYER: CircleLayer := Value;
    RI_RING_COLOR: RingColor := Value;
    RI_SELF_COLOR: SelfColor := Value;
    RI_ENEMY_COLOR: EnemyColor := Value;
    RI_FRIEND_COLOR: FriendColor := Value;
    RI_SHOW_FAR: ShowFar := Value <> 0;
    RI_LABEL_LAYER: LabelLayer := Value;
    RI_ARROWS_MAX: if (Value >= 1) and (Value <= BE_PLAYERS) then ArrowsMax := Value;
    RI_ARROW_DOTS: if (Value >= 1) and (Value <= ARROW_DOTS_MAX - 2) then ArrowDots := Value;
    RI_ARROW_LAYER: ArrowLayer := Value;
    RI_ARROW_NEAR: ArrowNear := Value;
    RI_ARROW_MID: ArrowMid := Value;
    RI_ARROW_FAR: ArrowFar := Value;
    RI_REFRESH: if Value > 0 then RefreshTicks := Value;
    RI_MARK_DISPLAY: if Value > 0 then MarkDisplay := Value;
    RI_LIST_DISPLAY: if Value > 0 then ListDisplay := Value;
    RI_METER_DECIMALS: MeterDecimals := Value;
    RI_COLOR_FULL: ColorFull := Value;
    RI_COLOR_HALF: ColorHalf := Value;
    RI_COLOR_LOW: ColorLow := Value;
    RI_VIS_RAYS: if Value > 0 then VisRaysPerTick := Value;
    RI_VIS_ROUND: if Value > 0 then VisRoundTicks := Value;
    RI_TEAMGAME: WTeamGame := Value <> 0;
    RI_ARROW_STEPS: if (Value >= 1) and (Value <= 16) then ArrowSteps := Value;
    RI_RING_COLOR_BY: if (Value >= RC_TEAM) and (Value <= RC_HEALTH) then RingColorBy := Value;
  end;
  HealthReady := False;
  BuildOwned;
end;

procedure RadarFloat(Key: LongInt; Value: Single);
begin
  case Key of
    RF_RANGE: Range := Value;
    RF_LIST_SCALE: ListScale := Value;
    RF_CIRCLE_R: CircleR := Value;
    RF_CIRCLE_SCALE: CircleScale := Value;
    RF_LABEL_SCALE: LabelScale := Value;
    RF_LABEL_OFFSET: LabelOffset := Value;
    RF_SIZE_RANGE: SizeRange := Value;
    RF_ARROW_INNER: ArrowInner := Value;
    RF_ARROW_OUTER: ArrowOuter := Value;
    RF_ARROW_HEAD: ArrowHead := Value;
    RF_ARROW_WIDTH: ArrowWidth := Value;
    RF_ARROW_SCALE: ArrowScale := Value;
    RF_ARROW_MOVE: ArrowMove := Value;
    RF_ARROW_LEAD: ArrowLead := Value;
    RF_LABEL_MOVE: LabelMove := Value;
    RF_TAG_SCALE: TagScale := Value;
    RF_CIRCLE_MOVE: CircleMove := Value;
    RF_RING_NEAR_SCALE: if Value > 0 then RingNearScale := Value;
    RF_RING_FAR_SCALE: if Value > 0 then RingFarScale := Value;
  end;
end;

procedure RadarText(Key: LongInt; const Value: AnsiString);
begin
  case Key of
    RT_RING: RingChar := Value;
    RT_SELF: SelfChar := Value;
    RT_ENEMY: EnemyChar := Value;
    RT_FRIEND: FriendChar := Value;
    RT_FAR: FarChar := Value;
    RT_FLAG: FlagChar := Value;
    RT_BOW: BowChar := Value;
    RT_ARROW: ArrowChar := Value;
    RT_LIST_TITLE: ListTitle := Value;
    RT_LIST_LINE: ListLine := Value;
    RT_EDIT: EditMark := Value;
    RT_NOBODY: NobodyText := Value;
  end;
end;

procedure RadarUser(ID, On, Mode, Show, PX, PY: LongInt; Size, Zoom, MarkSize: Single; Editing: LongInt);
begin
  if not ValidID(ID) then
    Exit;
  if Size <= 0 then
    Size := 1;
  if Zoom <= 0 then
    Zoom := 1;
  if MarkSize <= 0 then
    MarkSize := Size;
  Users[ID].On := On <> 0;
  Users[ID].Mode := Mode;
  Users[ID].Show := Show;
  Users[ID].PX := PX;
  Users[ID].PY := PY;
  Users[ID].Size := Size;
  Users[ID].Zoom := Zoom;
  Users[ID].MarkSize := MarkSize;
  Users[ID].Editing := Editing <> 0;
  if Users[ID].On then
    VisShow[ID] := Show
  else
    VisShow[ID] := SHOW_ALL;
end;

procedure RadarOpt(ID, Key, Value: LongInt);
begin
  if not ValidID(ID) then
    Exit;
  case Key of
    RO_FRIENDS: Users[ID].Friends := Value <> 0;
  end;
end;

function Wanted(A, b: LongInt): Boolean;
begin
  Result := (b <> A) and WP[b].Alive and Shows(A, b, Users[A].Show);
  if Result then
    if WTeamGame and (WP[b].Team = WP[A].Team) then
      Result := Users[A].Friends;
end;

function RadarRange(ID: LongInt): Single;
begin
  Result := 50;
  if not ValidID(ID) then
    Exit;
  Result := Range * (1 + (Users[ID].Size - 1) * SizeRange) * Users[ID].Zoom;
  if Result < 50 then
    Result := 50;
end;

function TagText(T: LongInt): AnsiString;
begin
  Result := '';
  if T = TAG_FLAG then
    Result := FlagChar
  else if T = TAG_BOW then
    Result := BowChar;
end;

function DirText(DX, DY: Single): AnsiString;
begin
  Result := '';
  if DX < -40 then
    Result := '<'
  else if DX > 40 then
    Result := '>';
  if DY < -40 then
    Result := Result + '^'
  else if DY > 40 then
    Result := Result + 'v';
  if Result = '' then
    Result := 'o';
end;

function Replace(const S, Find, Repl: AnsiString): AnsiString;
begin
  Result := StringReplace(S, Find, Repl, [rfReplaceAll]);
end;

procedure LayoutList(A: LongInt);
var
  b, k, Best: LongInt;
  ax, ay, DX, DY, R2, BestD: Single;
  Ref: Boolean;
  D2: array[1..BE_PLAYERS] of Single;
  Pick: array[1..BE_PLAYERS] of Boolean;
  T, L, Tg: AnsiString;
  U: ^TRadarUser;
begin
  U := @Users[A];
  Ref := WP[A].Team <> TEAM_SPEC;
  ax := WP[A].X;
  ay := WP[A].Y;
  R2 := RadarRange(A);
  R2 := R2 * R2;
  for b := 1 to BE_PLAYERS do
  begin
    Pick[b] := False;
    D2[b] := -1;
    if Wanted(A, b) then
    begin
      D2[b] := 0;
      if Ref then
      begin
        DX := WP[b].X - ax;
        DY := WP[b].Y - ay;
        D2[b] := DX * DX + DY * DY;
        if D2[b] > R2 then
          D2[b] := -1;
      end;
    end;
  end;
  k := 0;
  while k < ListLines do
  begin
    Best := 0;
    BestD := 0;
    for b := 1 to BE_PLAYERS do
      if (D2[b] >= 0) and not Pick[b] then
        if (Best = 0) or (D2[b] < BestD) then
        begin
          Best := b;
          BestD := D2[b];
        end;
    if Best = 0 then
      Break;
    Pick[Best] := True;
    Inc(k);
  end;
  T := ListTitle;
  if U^.Editing then
    T := T + EditMark;
  for b := 1 to BE_PLAYERS do
    if Pick[b] then
    begin
      Tg := TagText(WP[b].Tag);
      if Tg <> '' then
        Tg := Tg + ' ';
      L := Replace(ListLine, '{name}', WP[b].Name);
      L := Replace(L, '{pct}', IntToStr(WP[b].Pct));
      L := Replace(L, '{tag}', Tg);
      if Ref then
      begin
        L := Replace(L, '{dist}', IntToStr(Round(Sqrt(D2[b]) / 10) * 10));
        L := Replace(L, '{m}', FloatText(Sqrt(D2[b]) / 14, MeterDecimals) + 'm');
        L := Replace(L, '{dir}', DirText(WP[b].X - ax, WP[b].Y - ay));
      end
      else
      begin
        L := Replace(L, '{dist}', '');
        L := Replace(L, '{m}', '');
        L := Replace(L, '{dir}', '');
      end;
      L := Trim(L);
      if T = '' then
        T := L
      else
        T := T + #13#10 + L;
    end;
  if k = 0 then
  begin
    L := Replace(Replace(NobodyText, '{range}', IntToStr(Round(Sqrt(R2)))), '{m}',
      FloatText(Sqrt(R2) / 14, 0) + 'm');
    if T = '' then
      T := L
    else
      T := T + #13#10 + L;
  end;
  WantText(KIND_BIG, ListLayer, T, U^.PX, U^.PY, QScale(ListScale * U^.Size), ListColor, ListDisplay, 0);
end;

procedure LayoutLabels(A: LongInt);
var
  b: LongInt;
  ax, ay, bx, by, R2, Em, X, Y: Single;
  T, Tg: AnsiString;
  U: ^TRadarUser;
begin
  U := @Users[A];
  ax := WP[A].X;
  ay := WP[A].Y;
  R2 := RadarRange(A);
  R2 := R2 * R2;
  Em := LabelScale * WORLD_EM;
  for b := 1 to BE_PLAYERS do
    if Wanted(A, b) then
    begin
      bx := WP[b].X - ax;
      by := WP[b].Y - ay;
      if bx * bx + by * by > R2 then
        Continue;
      T := WP[b].Name + ' ' + IntToStr(WP[b].Pct) + '%';
      Tg := TagText(WP[b].Tag);
      if Tg <> '' then
        T := T + ' [' + Tg + ']';
      X := WP[b].X - TextAdvance(T) * Em / 2;
      Y := WP[b].Y - LabelOffset;
      WantText(KIND_WORLD, LabelLayer + b - 1, T, X, Y, LabelScale, HealthColor(WP[b].Pct), MarkDisplay, LabelMove,
        16 + b);
    end;
end;

procedure BigMark(Layer: LongInt; const Ch: AnsiString; C: LongInt; Sc, X, Y, Eps: Single);
var
  Em, CX, CY: Single;
begin
  Em := Sc * BIG_EM;
  InkCenter(Ch, CX, CY);
  WantText(KIND_BIG, Layer, Ch, X - CX * Em, Y - CY * Em, Sc, C, MarkDisplay, Eps);
end;

procedure WorldMark(Layer: LongInt; const Ch: AnsiString; C: LongInt; Sc, X, Y, Eps: Single; Group: LongInt);
var
  Em, CX, CY: Single;
begin
  Em := Sc * WORLD_EM;
  InkCenter(Ch, CX, CY);
  WantText(KIND_WORLD, Layer, Ch, X - CX * Em, Y - CY * Em, Sc, C, MarkDisplay, Eps, Group);
end;

function ArrowColor(Band: LongInt): LongInt;
var
  T: Single;
begin
  if ArrowSteps <= 1 then
    T := 0
  else
    T := Band / (ArrowSteps - 1);
  if T < 0.5 then
    Result := MixColor(ArrowNear, ArrowMid, T * 2)
  else
    Result := MixColor(ArrowMid, ArrowFar, (T - 0.5) * 2);
end;

function BandOf(T: Single; Prev: LongInt): LongInt;
const
  HYST = 0.04;
begin
  if T < 0 then
    T := 0;
  if T > 1 then
    T := 1;
  if (Prev >= 0) and (Prev < ArrowSteps) then
    if (T >= Prev / ArrowSteps - HYST) and (T <= (Prev + 1) / ArrowSteps + HYST) then
    begin
      Result := Prev;
      Exit;
    end;
  Result := Trunc(T * ArrowSteps);
  if Result >= ArrowSteps then
    Result := ArrowSteps - 1;
end;

procedure LayoutCircle(A: LongInt);
var
  b, k: LongInt;
  R, Sc, CX, CY, ax, ay, DX, DY, D, Ang, Rng: Single;
  Ch: AnsiString;
  C: LongInt;
  Friend: Boolean;
  U: ^TRadarUser;
begin
  U := @Users[A];
  R := CircleR * U^.Size;
  Sc := QScale(CircleScale * U^.MarkSize / Sqrt(U^.Zoom));
  CX := U^.PX + R;
  CY := U^.PY + R;
  Rng := RadarRange(A);
  for k := 0 to CircleDots - 1 do
  begin
    Ang := 2 * Pi * k / CircleDots;
    BigMark(CircleLayer + k, RingChar, RingColor, Sc, CX + R * Cos(Ang), CY + R * Sin(Ang), 0);
  end;
  BigMark(CircleLayer + RING_MAX, SelfChar, SelfColor, Sc, CX, CY, 0);
  if U^.Editing then
    Exit;
  ax := WP[A].X;
  ay := WP[A].Y;
  for b := 1 to BE_PLAYERS do
    if Wanted(A, b) then
    begin
      DX := WP[b].X - ax;
      DY := WP[b].Y - ay;
      D := Sqrt(DX * DX + DY * DY);
      Friend := WTeamGame and (WP[b].Team = WP[A].Team);
      if Friend then
      begin
        Ch := FriendChar;
        C := FriendColor;
      end
      else
      begin
        Ch := EnemyChar;
        C := EnemyColor;
      end;
      if WP[b].Tag <> TAG_NONE then
        Ch := TagText(WP[b].Tag);
      if D <= Rng then
        BigMark(CircleLayer + RING_MAX + b, Ch, C, Sc, CX + DX / Rng * R, CY + DY / Rng * R, CircleMove)
      else if ShowFar and (D > 0.001) then
      begin
        if WP[b].Tag = TAG_NONE then
          Ch := FarChar;
        BigMark(CircleLayer + RING_MAX + b, Ch, C, Sc, CX + DX / D * R, CY + DY / D * R, CircleMove);
      end;
    end;
end;

procedure LayoutRing(A: LongInt);
var
  b, k, Best, Cnt, Band: LongInt;
  cx, cy, DX, DY, D, Ux, Uy, Rng, BestD, Lead, Sc, T: Single;
  C: LongInt;
  D2: array[1..BE_PLAYERS] of Single;
  Picked: array[1..BE_PLAYERS] of Boolean;
  Ch: AnsiString;
  U: ^TRadarUser;
begin
  U := @Users[A];
  Lead := WP[A].Ping * 0.06 * ArrowLead;
  if Lead < 0 then
    Lead := 0;
  if Lead > 20 then
    Lead := 20;
  if not WP[A].Alive then
    Lead := 0;
  cx := WP[A].X + WP[A].VX * Lead;
  cy := WP[A].Y + WP[A].VY * Lead - LOS_HEIGHT;
  Rng := RadarRange(A);
  for b := 1 to BE_PLAYERS do
  begin
    D2[b] := -1;
    Picked[b] := False;
    if Wanted(A, b) then
    begin
      DX := WP[b].X - WP[A].X;
      DY := WP[b].Y - WP[A].Y;
      D2[b] := DX * DX + DY * DY;
      if D2[b] > Rng * Rng then
        D2[b] := -1;
    end;
    if D2[b] < 0 then
      U^.RingBand[b] := -1;
  end;
  Cnt := 0;
  while Cnt < ArrowsMax do
  begin
    Best := 0;
    BestD := 0;
    for b := 1 to BE_PLAYERS do
      if (D2[b] >= 0) and not Picked[b] then
        if (Best = 0) or (D2[b] < BestD) then
        begin
          Best := b;
          BestD := D2[b];
        end;
    if Best = 0 then
      Break;
    Picked[Best] := True;
    Inc(Cnt);
  end;
  for b := 1 to BE_PLAYERS do
  begin
    if not Picked[b] then
    begin
      U^.RingBand[b] := -1;
      Continue;
    end;
    DX := WP[b].X - WP[A].X;
    DY := WP[b].Y - WP[A].Y;
    D := Sqrt(DX * DX + DY * DY);
    if D < 1 then
    begin
      Ux := 1;
      Uy := 0;
    end
    else
    begin
      Ux := DX / D;
      Uy := DY / D;
    end;
    Band := BandOf(D / Rng, U^.RingBand[b]);
    U^.RingBand[b] := Band;
    if ArrowSteps > 1 then
      T := Band / (ArrowSteps - 1)
    else
      T := 0;
    Sc := QScale(RingNearScale + (RingFarScale - RingNearScale) * T);
    case RingColorBy of
      RC_DISTANCE: C := ArrowColor(Band);
      RC_HEALTH: C := HealthColor(WP[b].Pct);
    else
      if WTeamGame and (WP[b].Team = WP[A].Team) then
        C := FriendColor
      else
        C := EnemyColor;
    end;
    Ch := ArrowChar;
    if WP[b].Tag <> TAG_NONE then
    begin
      Ch := TagText(WP[b].Tag);
      Sc := QScale(Sc * TagScale);
    end;
    k := ArrowLayer + b - 1;
    WorldMark(k, Ch, C, Sc, cx + Ux * ArrowOuter, cy + Uy * ArrowOuter, ArrowMove, 0);
  end;
end;

function RadarPass(ID, Tick, Budget: LongInt): LongInt;
var
  More: Boolean;
begin
  Result := 0;
  if not ValidID(ID) then
    Exit;
  WantClear;
  if Users[ID].On and WP[ID].Active then
    case Users[ID].Mode of
      OVL_LIST: LayoutList(ID);
      OVL_LABELS: LayoutLabels(ID);
      OVL_CIRCLE: LayoutCircle(ID);
      OVL_RING: LayoutRing(ID);
    end;
  Result := Diff(Users[ID].Sent, OwnBig, OwnWorld, Tick, RefreshTicks, Budget, More);
  Users[ID].Pending := More;
end;

function RadarHide(ID, Budget: LongInt): LongInt;
var
  More: Boolean;
  n: LongInt;
begin
  Result := 0;
  if not ValidID(ID) then
    Exit;
  Result := HideAll(Users[ID].Sent, OwnBig, OwnWorld, Budget, More);
  Users[ID].Pending := More;
  for n := 1 to BE_PLAYERS do
    Users[ID].RingBand[n] := -1;
end;

function RadarPending(ID: LongInt): LongInt;
begin
  Result := 0;
  if ValidID(ID) then
    if Users[ID].Pending then
      Result := 1;
end;

procedure RadarReset(ID: LongInt);
var
  n: LongInt;
begin
  if not ValidID(ID) then
    Exit;
  SetForget(Users[ID].Sent);
  Users[ID].Pending := False;
  Users[ID].On := False;
  VisShow[ID] := SHOW_ALL;
  Users[ID].Friends := True;
  for n := 1 to BE_PLAYERS do
    Users[ID].RingBand[n] := -1;
end;

procedure RadarRedraw(ID: LongInt);
begin
  if ValidID(ID) then
    SetStale(Users[ID].Sent);
end;

procedure InitUsers;
var
  i, n: LongInt;
begin
  for i := 1 to BE_PLAYERS do
  begin
    Users[i].Friends := True;
    for n := 1 to BE_PLAYERS do
      Users[i].RingBand[n] := -1;
  end;
end;

initialization
  BuildOwned;
  InitUsers;
end.
