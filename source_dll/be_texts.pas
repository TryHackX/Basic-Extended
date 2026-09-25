unit be_texts;

{$mode objfpc}{$H+}

interface

const
  KIND_BIG = 1;
  KIND_WORLD = 2;
  MAX_OPS = 1024;
  MAX_GROUPS = 64;

type
  TSlot = record
    On: Boolean;
    Text: AnsiString;
    X, Y, Scale, Eps: Single;
    Color, Delay, Tick, Group: LongInt;
  end;
  TSlotArr = array[0..255] of TSlot;
  TTextSet = record
    Big, World: TSlotArr;
  end;
  TOwnMask = array[0..255] of Boolean;
  TOp = record
    Kind, Layer, Delay, Color: LongInt;
    Scale, X, Y: Single;
    Text: AnsiString;
  end;

var
  Ops: array[0..MAX_OPS - 1] of TOp;
  OpCount: LongInt = 0;
  Want: TTextSet;

procedure WantClear;
procedure WantText(Kind, Layer: LongInt; const Text: AnsiString; X, Y, Scale: Single; Color, Delay: LongInt;
  Eps: Single; Group: LongInt = 0);
procedure SetForget(var S: TTextSet);
procedure SetStale(var S: TTextSet);
function Diff(var Sent: TTextSet; const OwnBig, OwnWorld: TOwnMask; Tick, Refresh, Budget: LongInt;
  out More: Boolean): LongInt;
function HideAll(var Sent: TTextSet; const OwnBig, OwnWorld: TOwnMask; Budget: LongInt; out More: Boolean): LongInt;
function QScale(S: Single): Single;
function MixColor(A, B: LongInt; T: Single): LongInt;

implementation

var
  WantOrder: array[0..511] of LongInt;
  WantCount: LongInt = 0;

function QScale(S: Single): Single;
begin
  if S < 0.1 then
    Result := Round(S * 1000) * 0.001
  else
    Result := Round(S * 200) * 0.005;
  if Result < 0.005 then
    Result := 0.005;
end;

function MixColor(A, B: LongInt; T: Single): LongInt;
var
  ar, ag, ab, br, bg, bb: LongInt;
begin
  if T < 0 then
    T := 0;
  if T > 1 then
    T := 1;
  ar := (A shr 16) and 255;
  ag := (A shr 8) and 255;
  ab := A and 255;
  br := (B shr 16) and 255;
  bg := (B shr 8) and 255;
  bb := B and 255;
  Result := (Round(ar + (br - ar) * T) shl 16) or (Round(ag + (bg - ag) * T) shl 8) or Round(ab + (bb - ab) * T);
end;

procedure WantClear;
var
  i: LongInt;
begin
  for i := 0 to 255 do
  begin
    Want.Big[i].On := False;
    Want.World[i].On := False;
  end;
  WantCount := 0;
end;

procedure WantText(Kind, Layer: LongInt; const Text: AnsiString; X, Y, Scale: Single; Color, Delay: LongInt;
  Eps: Single; Group: LongInt);
var
  P: ^TSlot;
begin
  if (Group < 0) or (Group >= MAX_GROUPS) then
    Group := 0;
  if (Layer < 0) or (Layer > 255) then
    Exit;
  if Kind = KIND_BIG then
  begin
    P := @Want.Big[Layer];
    X := Round(X);
    Y := Round(Y);
  end
  else
    P := @Want.World[Layer];
  if not P^.On then
  begin
    if WantCount <= High(WantOrder) then
    begin
      WantOrder[WantCount] := Kind * 256 + Layer;
      Inc(WantCount);
    end;
  end;
  P^.On := True;
  P^.Text := Text;
  P^.X := X;
  P^.Y := Y;
  P^.Scale := Scale;
  P^.Color := Color;
  P^.Delay := Delay;
  P^.Eps := Eps;
  P^.Group := Group;
end;

procedure SetForget(var S: TTextSet);
var
  i: LongInt;
begin
  for i := 0 to 255 do
  begin
    S.Big[i].On := False;
    S.Big[i].Text := '';
    S.World[i].On := False;
    S.World[i].Text := '';
  end;
end;

procedure SetStale(var S: TTextSet);
var
  i: LongInt;
begin
  for i := 0 to 255 do
  begin
    S.Big[i].Tick := -2000000000;
    S.World[i].Tick := -2000000000;
  end;
end;

procedure EmitHide(Kind, Layer: LongInt);
begin
  if OpCount >= MAX_OPS then
    Exit;
  Ops[OpCount].Kind := Kind;
  Ops[OpCount].Layer := Layer;
  Ops[OpCount].Delay := 1;
  Ops[OpCount].Color := 0;
  Ops[OpCount].Scale := 0.01;
  Ops[OpCount].X := 0;
  Ops[OpCount].Y := 0;
  Ops[OpCount].Text := ' ';
  Inc(OpCount);
end;

procedure EmitSend(Kind, Layer: LongInt; const W: TSlot);
begin
  if OpCount >= MAX_OPS then
    Exit;
  Ops[OpCount].Kind := Kind;
  Ops[OpCount].Layer := Layer;
  Ops[OpCount].Delay := W.Delay;
  Ops[OpCount].Color := W.Color;
  Ops[OpCount].Scale := W.Scale;
  Ops[OpCount].X := W.X;
  Ops[OpCount].Y := W.Y;
  Ops[OpCount].Text := W.Text;
  Inc(OpCount);
end;

function Moved(Kind: LongInt; const W, S: TSlot): Boolean;
begin
  if Kind = KIND_BIG then
    Result := (Abs(Round(W.X) - Round(S.X)) > W.Eps) or (Abs(Round(W.Y) - Round(S.Y)) > W.Eps)
  else
    Result := (Abs(W.X - S.X) > W.Eps) or (Abs(W.Y - S.Y) > W.Eps);
end;

function NeedSend(Kind: LongInt; const W, S: TSlot; Tick, Refresh: LongInt): Boolean;
begin
  Result := (not S.On) or (W.Text <> S.Text) or (W.Color <> S.Color) or (Abs(W.Scale - S.Scale) > 0.00001) or
    (W.Delay <> S.Delay) or Moved(Kind, W, S) or (Tick - S.Tick >= Refresh);
end;

function Diff(var Sent: TTextSet; const OwnBig, OwnWorld: TOwnMask; Tick, Refresh, Budget: LongInt;
  out More: Boolean): LongInt;
var
  i, j, g, Best, Code, Kind, Layer: LongInt;
  W, S: ^TSlot;
  Need: array[0..511] of Boolean;
  GCount, GAge: array[0..MAX_GROUPS - 1] of LongInt;
  GDone: array[0..MAX_GROUPS - 1] of Boolean;
begin
  OpCount := 0;
  More := False;
  if Budget > MAX_OPS then
    Budget := MAX_OPS;
  for i := 0 to 255 do
  begin
    if OwnBig[i] and Sent.Big[i].On and not Want.Big[i].On then
    begin
      if OpCount < Budget then
      begin
        EmitHide(KIND_BIG, i);
        Sent.Big[i].On := False;
        Sent.Big[i].Text := '';
      end
      else
        More := True;
    end;
    if OwnWorld[i] and Sent.World[i].On and not Want.World[i].On then
    begin
      if OpCount < Budget then
      begin
        EmitHide(KIND_WORLD, i);
        Sent.World[i].On := False;
        Sent.World[i].Text := '';
      end
      else
        More := True;
    end;
  end;
  for g := 0 to MAX_GROUPS - 1 do
  begin
    GCount[g] := 0;
    GAge[g] := High(LongInt);
    GDone[g] := False;
  end;
  for i := 0 to WantCount - 1 do
  begin
    Need[i] := False;
    Code := WantOrder[i];
    Kind := Code div 256;
    Layer := Code mod 256;
    if Kind = KIND_BIG then
    begin
      W := @Want.Big[Layer];
      S := @Sent.Big[Layer];
    end
    else
    begin
      W := @Want.World[Layer];
      S := @Sent.World[Layer];
    end;
    if not W^.On then
      Continue;
    Need[i] := NeedSend(Kind, W^, S^, Tick, Refresh);
    if not Need[i] then
      Continue;
    g := W^.Group;
    if g = 0 then
    begin
      if OpCount >= Budget then
      begin
        More := True;
        Continue;
      end;
      EmitSend(Kind, Layer, W^);
      S^ := W^;
      S^.Tick := Tick;
      Need[i] := False;
    end
    else
    begin
      Inc(GCount[g]);
      if S^.On then
      begin
        if S^.Tick < GAge[g] then
          GAge[g] := S^.Tick;
      end
      else
        GAge[g] := Low(LongInt);
    end;
  end;
  repeat
    Best := 0;
    for g := 1 to MAX_GROUPS - 1 do
      if (GCount[g] > 0) and not GDone[g] then
        if (Best = 0) or (GAge[g] < GAge[Best]) then
          Best := g;
    if Best = 0 then
      Break;
    GDone[Best] := True;
    if OpCount + GCount[Best] > Budget then
    begin
      More := True;
      Continue;
    end;
    for j := 0 to WantCount - 1 do
      if Need[j] then
      begin
        Code := WantOrder[j];
        Kind := Code div 256;
        Layer := Code mod 256;
        if Kind = KIND_BIG then
        begin
          W := @Want.Big[Layer];
          S := @Sent.Big[Layer];
        end
        else
        begin
          W := @Want.World[Layer];
          S := @Sent.World[Layer];
        end;
        if W^.Group <> Best then
          Continue;
        EmitSend(Kind, Layer, W^);
        S^ := W^;
        S^.Tick := Tick;
        Need[j] := False;
      end;
  until False;
  Result := OpCount;
end;

function HideAll(var Sent: TTextSet; const OwnBig, OwnWorld: TOwnMask; Budget: LongInt; out More: Boolean): LongInt;
var
  i: LongInt;
begin
  OpCount := 0;
  More := False;
  if Budget > MAX_OPS then
    Budget := MAX_OPS;
  for i := 0 to 255 do
  begin
    if OwnBig[i] and Sent.Big[i].On then
    begin
      if OpCount < Budget then
      begin
        EmitHide(KIND_BIG, i);
        Sent.Big[i].On := False;
        Sent.Big[i].Text := '';
      end
      else
        More := True;
    end;
    if OwnWorld[i] and Sent.World[i].On then
    begin
      if OpCount < Budget then
      begin
        EmitHide(KIND_WORLD, i);
        Sent.World[i].On := False;
        Sent.World[i].Text := '';
      end
      else
        More := True;
    end;
  end;
  Result := OpCount;
end;

end.
