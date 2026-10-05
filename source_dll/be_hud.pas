unit be_hud;

{ Round 26: the HUD lines of every player - where each one stands and what his game shows - kept here, so the
  script builds only the texts that changed and sends only what this unit says.

  Nine lines a player may have: 0 health, 1 ammunition, 2 flash grenades, 3 mines, 4 blood, 5 money, 6 class,
  7 score, 8 vest (main.pas HL_*). A line either has a fixed place (its module's HudX, HudY, HudScale) or stands over
  the ammunition (HudPlace = ammo): over the ammunition's own line with [Ammo] HudAppend = 2, else over the health
  line; one line up for each one shown, past the health line and the fixed lines it would meet, under it when the
  top of the screen is reached. His game keeps a text on its layer until it is replaced or its time runs out, so a
  shown line is sent again when its refresh is due (it lives LifeTicks, three refreshes). }

{$mode objfpc}{$H+}

interface

const
  HUD_LINES = 9;
  HUD_HIDDEN = 0;
  HUD_SHOWN = 1;
  HUD_UNKNOWN = 2;

{ line L: its layer, whether it stands over the ammunition (1) and its fixed place }
procedure HudCfgLine(L, Layer, Stacked, FX, FY: LongInt; FSc: Single);
{ how long a text lives on his screen, after how many ticks a shown line is sent again, whether the ammunition has
  its own line (the stack stands over it, else over the health line) }
procedure HudCfgTimes(LifeTicks, DueTicks, AmmoOwn: LongInt);
{ what his game shows is known (a join: nothing, HUD_HIDDEN) or not (the script starts: HUD_UNKNOWN); the wanted
  texts are cleared }
procedure HudReset(ID, State: LongInt);
{ the text line L should show now ('' = hidden) and its colour }
procedure HudWant(ID, L: LongInt; const Text: AnsiString; Color: LongInt);
{ the place of his health line (L 0) or ammunition line (L 1) - his own, or the editor's while he moves it }
procedure HudPlace(ID, L, X, Y: LongInt; Sc: Single);
{ the places of all his lines and what must be sent (Force: every shown line); the count of the ops }
function HudDraw(ID, Tick, Force: LongInt): LongInt;
{ every line his game may still show goes (the script stops): the count of the ops }
function HudHideAll(ID: LongInt): LongInt;
{ op k of the last HudDraw / HudHideAll: the text and where; Ticks = 0 is a hide (the script sends its own) }
function HudOp(k: LongInt; out Layer, Ticks, Color, X, Y: LongInt; out Sc: Single): AnsiString;
{ a shown line's refresh is due }
function HudDue(ID, Tick: LongInt): Boolean;
{ the tick counter started again: every shown line is due }
procedure HudClockReset(ID: LongInt);
{ /reloadsettings moved line L to another layer: True when his game may show it on the old one (it is unknown now) }
function HudMoved(ID, L: LongInt): Boolean;
function HudState(ID, L: LongInt): LongInt;
{ the scale a text is sent with (BigText's scale in steps the game shows apart) }
function HudQScale(S: Single): Single;

implementation

type
  TLine = record
    Want: AnsiString;
    WantC: LongInt;
    St: LongInt;
    Text: AnsiString;
    X, Y, C, Tick: LongInt;
    Sc: Single;
  end;

  TOp = record
    Layer, Ticks, Color, X, Y: LongInt;
    Sc: Single;
    Text: AnsiString;
  end;

var
  Lines: array[1..32, 0..HUD_LINES - 1] of TLine;
  { the places of his health and ammunition lines }
  PX, PY: array[1..32, 0..1] of LongInt;
  PSc: array[1..32, 0..1] of Single;
  CfgLayer: array[0..HUD_LINES - 1] of LongInt;
  CfgStacked: array[0..HUD_LINES - 1] of Boolean;
  CfgFX, CfgFY: array[0..HUD_LINES - 1] of LongInt;
  CfgFSc: array[0..HUD_LINES - 1] of Single;
  CfgLife: LongInt = 18000;
  CfgDue: LongInt = 300;
  CfgAmmoOwn: Boolean = False;
  Ops: array[0..HUD_LINES - 1] of TOp;
  OpN: LongInt = 0;
  { the places of the player being drawn }
  DX, DY: array[0..HUD_LINES - 1] of LongInt;
  DSc: array[0..HUD_LINES - 1] of Single;

function ValidID(ID: LongInt): Boolean;
begin
  Result := (ID >= 1) and (ID <= 32);
end;

function ValidLine(L: LongInt): Boolean;
begin
  Result := (L >= 0) and (L < HUD_LINES);
end;

function HudQScale(S: Single): Single;
begin
  if S < 0.1 then
    Result := Round(S * 1000) * 0.001
  else
    Result := Round(S * 200) * 0.005;
  if Result < 0.005 then
    Result := 0.005;
end;

procedure HudCfgLine(L, Layer, Stacked, FX, FY: LongInt; FSc: Single);
begin
  if not ValidLine(L) then
    Exit;
  CfgLayer[L] := Layer;
  CfgStacked[L] := (Stacked <> 0) and (L >= 2);
  CfgFX[L] := FX;
  CfgFY[L] := FY;
  CfgFSc[L] := FSc;
end;

procedure HudCfgTimes(LifeTicks, DueTicks, AmmoOwn: LongInt);
begin
  if LifeTicks < 1 then
    LifeTicks := 1;
  if DueTicks < 1 then
    DueTicks := 1;
  CfgLife := LifeTicks;
  CfgDue := DueTicks;
  CfgAmmoOwn := AmmoOwn <> 0;
end;

procedure HudReset(ID, State: LongInt);
var
  L: LongInt;
begin
  if not ValidID(ID) then
    Exit;
  for L := 0 to HUD_LINES - 1 do
  begin
    Lines[ID, L].St := State;
    Lines[ID, L].Text := '';
    Lines[ID, L].Want := '';
    Lines[ID, L].WantC := 0;
    Lines[ID, L].Tick := 0;
  end;
end;

procedure HudWant(ID, L: LongInt; const Text: AnsiString; Color: LongInt);
begin
  if ValidID(ID) and ValidLine(L) then
  begin
    Lines[ID, L].Want := Text;
    Lines[ID, L].WantC := Color;
  end;
end;

procedure HudPlace(ID, L, X, Y: LongInt; Sc: Single);
begin
  if ValidID(ID) and (L >= 0) and (L <= 1) then
  begin
    PX[ID, L] := X;
    PY[ID, L] := Y;
    PSc[ID, L] := Sc;
  end;
end;

{ a BigText line is 1.157 of the font's 179.2 units per scale }
function LineHigh(Sc: Single): LongInt;
begin
  Result := Round(Sc * 207.4);
end;

{ a line over the ammunition at Y (H high) would meet the health line (a line of its own with AmmoOwn) or a line at
  its fixed place shown now }
function Clash(ID, Y, H: LongInt): Boolean;
var
  L, FH: LongInt;
begin
  Result := False;
  if CfgAmmoOwn then
    if Lines[ID, 0].Want <> '' then
    begin
      FH := LineHigh(DSc[0]);
      if (Y < DY[0] + FH) and (Y + H > DY[0]) then
      begin
        Result := True;
        Exit;
      end;
    end;
  for L := 2 to HUD_LINES - 1 do
    if not CfgStacked[L] then
      if Lines[ID, L].Want <> '' then
      begin
        FH := LineHigh(DSc[L]);
        if (Y < DY[L] + FH) and (Y + H > DY[L]) then
        begin
          Result := True;
          Exit;
        end;
      end;
end;

procedure AddOp(Layer, Ticks, Color, X, Y: LongInt; Sc: Single; const Text: AnsiString);
begin
  if OpN >= HUD_LINES then
    Exit;
  Ops[OpN].Layer := Layer;
  Ops[OpN].Ticks := Ticks;
  Ops[OpN].Color := Color;
  Ops[OpN].X := X;
  Ops[OpN].Y := Y;
  Ops[OpN].Sc := Sc;
  Ops[OpN].Text := Text;
  Inc(OpN);
end;

function HudDraw(ID, Tick, Force: LongInt): LongInt;
var
  L, k, Below, AX, AY, AH, Y: LongInt;
  ASc: Single;
  P: ^TLine;
begin
  OpN := 0;
  Result := 0;
  if not ValidID(ID) then
    Exit;
  { the places: the health line, the ammunition line, the lines at fixed places }
  for L := 0 to 1 do
  begin
    DX[L] := PX[ID, L];
    DY[L] := PY[ID, L];
    DSc[L] := PSc[ID, L];
  end;
  for L := 2 to HUD_LINES - 1 do
    if not CfgStacked[L] then
    begin
      DX[L] := CfgFX[L];
      DY[L] := CfgFY[L];
      DSc[L] := CfgFSc[L];
    end;
  { the lines over the ammunition (or the health line): one line up for each one shown }
  if CfgAmmoOwn then
    k := 1
  else
    k := 0;
  AX := DX[k];
  AY := DY[k];
  ASc := DSc[k];
  AH := LineHigh(ASc);
  if AH < 1 then
    AH := 1;
  k := 0;
  Below := 0;
  for L := 2 to HUD_LINES - 1 do
    if CfgStacked[L] then
    begin
      DX[L] := AX;
      DY[L] := AY;
      DSc[L] := ASc;
      if Lines[ID, L].Want <> '' then
      begin
        repeat
          Inc(k);
          Y := AY - k * AH;
        until (Y < 0) or not Clash(ID, Y, AH);
        if Y < 0 then
        begin
          Inc(Below);
          Y := AY + Below * AH;
        end;
        DY[L] := Y;
      end;
    end;
  { what changed (or is due) is sent }
  for L := 0 to HUD_LINES - 1 do
  begin
    P := @Lines[ID, L];
    if P^.Want = '' then
    begin
      if P^.St <> HUD_HIDDEN then
      begin
        AddOp(CfgLayer[L], 0, 0, 0, 0, 0, ' ');
        P^.St := HUD_HIDDEN;
        P^.Text := '';
      end;
      Continue;
    end;
    if Force = 0 then
      if P^.St = HUD_SHOWN then
        if P^.Want = P^.Text then
          if (DX[L] = P^.X) and (DY[L] = P^.Y) and (P^.WantC = P^.C) and (DSc[L] = P^.Sc) then
            if Tick - P^.Tick < CfgDue then
              Continue;
    AddOp(CfgLayer[L], CfgLife, P^.WantC, DX[L], DY[L], HudQScale(DSc[L]), P^.Want);
    P^.St := HUD_SHOWN;
    P^.Text := P^.Want;
    P^.X := DX[L];
    P^.Y := DY[L];
    P^.C := P^.WantC;
    P^.Sc := DSc[L];
    P^.Tick := Tick;
  end;
  Result := OpN;
end;

function HudHideAll(ID: LongInt): LongInt;
var
  L: LongInt;
begin
  OpN := 0;
  Result := 0;
  if not ValidID(ID) then
    Exit;
  for L := 0 to HUD_LINES - 1 do
    if Lines[ID, L].St <> HUD_HIDDEN then
    begin
      AddOp(CfgLayer[L], 0, 0, 0, 0, 0, ' ');
      Lines[ID, L].St := HUD_HIDDEN;
    end;
  Result := OpN;
end;

function HudOp(k: LongInt; out Layer, Ticks, Color, X, Y: LongInt; out Sc: Single): AnsiString;
begin
  Layer := 0;
  Ticks := 0;
  Color := 0;
  X := 0;
  Y := 0;
  Sc := 0;
  Result := '';
  if (k < 0) or (k >= OpN) then
    Exit;
  Layer := Ops[k].Layer;
  Ticks := Ops[k].Ticks;
  Color := Ops[k].Color;
  X := Ops[k].X;
  Y := Ops[k].Y;
  Sc := Ops[k].Sc;
  Result := Ops[k].Text;
end;

function HudDue(ID, Tick: LongInt): Boolean;
var
  L: LongInt;
begin
  Result := False;
  if not ValidID(ID) then
    Exit;
  for L := 0 to HUD_LINES - 1 do
    if Lines[ID, L].St <> HUD_HIDDEN then
      if Tick - Lines[ID, L].Tick >= CfgDue then
      begin
        Result := True;
        Exit;
      end;
end;

procedure HudClockReset(ID: LongInt);
var
  L: LongInt;
begin
  if ValidID(ID) then
    for L := 0 to HUD_LINES - 1 do
      Lines[ID, L].Tick := 0;
end;

function HudMoved(ID, L: LongInt): Boolean;
begin
  Result := False;
  if ValidID(ID) and ValidLine(L) then
    if Lines[ID, L].St <> HUD_HIDDEN then
    begin
      Lines[ID, L].St := HUD_UNKNOWN;
      Result := True;
    end;
end;

function HudState(ID, L: LongInt): LongInt;
begin
  Result := HUD_HIDDEN;
  if ValidID(ID) and ValidLine(L) then
    Result := Lines[ID, L].St;
end;

end.
