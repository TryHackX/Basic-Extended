unit be_map;

{$mode objfpc}{$H+}
{$Q-}{$R-}

interface

const
  MR_PLAYER = 1;
  MR_FLAG = 2;
  MR_BULLET = 4;

var
  MapGeneration: LongInt = 0;

function MapLoad(const Path: AnsiString): LongInt;
procedure MapClear;
function MapReady: Boolean;
function MapPolys: LongInt;
function MapRay(AX, AY, BX, BY: Single; Flags, Team: LongInt): Boolean;
function MapPointSolid(X, Y: Single; Flags, Team: LongInt): Boolean;

implementation

uses
  Classes, SysUtils;

const
  MAX_POLYS = 5000;
  MAX_SECTOR = 25;
  COORD_LIMIT = 1000000;
  PT_ONLY_BULLETS = 1;
  PT_ONLY_PLAYER = 2;
  PT_DOESNT = 3;
  PT_RED_BULLETS = 10;
  PT_RED_PLAYER = 11;
  PT_BLUE_BULLETS = 12;
  PT_BLUE_PLAYER = 13;
  PT_YELLOW_BULLETS = 14;
  PT_YELLOW_PLAYER = 15;
  PT_GREEN_BULLETS = 16;
  PT_GREEN_PLAYER = 17;
  PT_ONLY_FLAGGERS = 21;
  PT_NOT_FLAGGERS = 22;
  PT_NON_FLAGGER_COLLIDES = 23;
  PT_BACKGROUND = 24;
  PT_BACKGROUND_TRANSITION = 25;

type
  TPoly = record
    X, Y: array[1..3] of Single;
    MinX, MinY, MaxX, MaxY: Single;
    T: Byte;
  end;

  TReader = record
    D: array of Byte;
    P: LongInt;
    Bad: Boolean;
  end;

var
  Polys: array of TPoly;
  PolyN: LongInt = 0;
  SecDiv: LongInt = 0;
  SecNum: LongInt = 0;
  SecSide: LongInt = 0;
  SecStart, SecLen: array of LongInt;
  SecPolys: array of Word;
  Stamp: array of LongWord;
  StampNow: LongWord = 0;
  Loaded: Boolean = False;

function FMin(A, B: Single): Single; inline;
begin
  if A < B then
    Result := A
  else
    Result := B;
end;

function FMax(A, B: Single): Single; inline;
begin
  if A > B then
    Result := A
  else
    Result := B;
end;

procedure Take(var R: TReader; Dest: Pointer; N: LongInt);
begin
  if R.Bad or (R.P + N > Length(R.D)) then
  begin
    R.Bad := True;
    FillChar(Dest^, N, 0);
    Exit;
  end;
  Move(R.D[R.P], Dest^, N);
  Inc(R.P, N);
end;

procedure Skip(var R: TReader; N: LongInt);
begin
  if R.Bad or (R.P + N > Length(R.D)) then
    R.Bad := True
  else
    Inc(R.P, N);
end;

function TakeInt(var R: TReader): LongInt;
begin
  Result := 0;
  Take(R, @Result, 4);
end;

function TakeWord(var R: TReader): Word;
begin
  Result := 0;
  Take(R, @Result, 2);
end;

function TakeByte(var R: TReader): Byte;
begin
  Result := 0;
  Take(R, @Result, 1);
end;

function TakeSingle(var R: TReader): Single;
begin
  Result := 0;
  Take(R, @Result, 4);
end;

function FindFile(const Path: AnsiString): AnsiString;
var
  Dir, Name: AnsiString;
  SR: TSearchRec;
begin
  Result := '';
  if Path = '' then
    Exit;
  if FileExists(Path) then
  begin
    Result := Path;
    Exit;
  end;
  Dir := ExtractFilePath(Path);
  Name := ExtractFileName(Path);
  if FindFirst(Dir + '*', faAnyFile, SR) = 0 then
  begin
    repeat
      if (SR.Attr and faDirectory) = 0 then
        if CompareText(SR.Name, Name) = 0 then
        begin
          Result := Dir + SR.Name;
          Break;
        end;
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
end;

procedure MapClear;
begin
  Inc(MapGeneration);
  Loaded := False;
  PolyN := 0;
  SecDiv := 0;
  SecNum := 0;
  SecSide := 0;
  SetLength(Polys, 0);
  SetLength(SecStart, 0);
  SetLength(SecLen, 0);
  SetLength(SecPolys, 0);
  SetLength(Stamp, 0);
end;

function MapReady: Boolean;
begin
  Result := Loaded;
end;

function MapPolys: LongInt;
begin
  Result := PolyN;
end;

function MapLoad(const Path: AnsiString): LongInt;
var
  R: TReader;
  FS: TFileStream;
  Name: AnsiString;
  n, i, j, k, m, Cells, Total: LongInt;
begin
  MapClear;
  Result := -1;
  Name := FindFile(Path);
  if Name = '' then
    Exit;
  R.P := 0;
  R.Bad := False;
  try
    FS := TFileStream.Create(Name, fmOpenRead or fmShareDenyNone);
    try
      SetLength(R.D, FS.Size);
      if FS.Size > 0 then
        FS.ReadBuffer(R.D[0], FS.Size);
    finally
      FS.Free;
    end;
  except
    Exit;
  end;
  Result := -2;
  TakeInt(R);
  Skip(R, 1 + 38);
  Skip(R, 1 + 24);
  Skip(R, 20);
  n := TakeInt(R);
  if R.Bad or (n < 0) or (n > MAX_POLYS) then
    Exit;
  SetLength(Polys, n + 1);
  for i := 1 to n do
  begin
    for j := 1 to 3 do
    begin
      Polys[i].X[j] := TakeSingle(R);
      Polys[i].Y[j] := TakeSingle(R);
      Skip(R, 20);
    end;
    Skip(R, 36);
    Polys[i].T := TakeByte(R);
    Polys[i].MinX := FMin(Polys[i].X[1], FMin(Polys[i].X[2], Polys[i].X[3]));
    Polys[i].MaxX := FMax(Polys[i].X[1], FMax(Polys[i].X[2], Polys[i].X[3]));
    Polys[i].MinY := FMin(Polys[i].Y[1], FMin(Polys[i].Y[2], Polys[i].Y[3]));
    Polys[i].MaxY := FMax(Polys[i].Y[1], FMax(Polys[i].Y[2], Polys[i].Y[3]));
  end;
  SecDiv := TakeInt(R);
  SecNum := TakeInt(R);
  if R.Bad or (SecNum < 0) or (SecNum > MAX_SECTOR) or (SecDiv <= 0) then
    Exit;
  SecSide := 2 * SecNum + 1;
  Cells := SecSide * SecSide;
  SetLength(SecStart, Cells);
  SetLength(SecLen, Cells);
  SetLength(SecPolys, 1024);
  Total := 0;
  for k := 0 to Cells - 1 do
  begin
    m := TakeWord(R);
    if R.Bad or (m > MAX_POLYS) then
      Exit;
    SecStart[k] := Total;
    SecLen[k] := m;
    if Total + m > Length(SecPolys) then
      SetLength(SecPolys, (Total + m) * 2);
    for j := 0 to m - 1 do
      SecPolys[Total + j] := TakeWord(R);
    if R.Bad then
      Exit;
    Inc(Total, m);
  end;
  SetLength(SecPolys, Total);
  SetLength(Stamp, n + 1);
  for i := 0 to n do
    Stamp[i] := 0;
  StampNow := 0;
  PolyN := n;
  Loaded := True;
  Result := n;
end;

function Blocks(T: Byte; Flags, Team: LongInt): Boolean;
var
  NP, NB, Fl: Boolean;
begin
  NP := (Flags and MR_PLAYER) = 0;
  NB := (Flags and MR_BULLET) = 0;
  Fl := (Flags and MR_FLAG) <> 0;
  Result := True;
  case T of
    PT_RED_BULLETS: Result := (Team = 1) and not NB;
    PT_RED_PLAYER: Result := (Team = 1) and not NP;
    PT_BLUE_BULLETS: Result := (Team = 2) and not NB;
    PT_BLUE_PLAYER: Result := (Team = 2) and not NP;
    PT_YELLOW_BULLETS: Result := (Team = 3) and not NB;
    PT_YELLOW_PLAYER: Result := (Team = 3) and not NP;
    PT_GREEN_BULLETS: Result := (Team = 4) and not NB;
    PT_GREEN_PLAYER: Result := (Team = 4) and not NP;
    PT_ONLY_FLAGGERS: Result := Fl and not NP;
    PT_NOT_FLAGGERS: Result := not (Fl or NP);
    PT_NON_FLAGGER_COLLIDES: Result := Fl and not NP and not NB;
    PT_ONLY_BULLETS: Result := not NB;
    PT_ONLY_PLAYER: Result := not NP;
    PT_DOESNT, PT_BACKGROUND, PT_BACKGROUND_TRANSITION: Result := False;
  end;
end;

function PointIn(PX, PY: Single; w: LongInt): Boolean;
var
  APX, APY: Single;
  PAB, PAC: Boolean;
begin
  Result := False;
  with Polys[w] do
  begin
    APX := PX - X[1];
    APY := PY - Y[1];
    PAB := (X[2] - X[1]) * APY - (Y[2] - Y[1]) * APX > 0;
    PAC := (X[3] - X[1]) * APY - (Y[3] - Y[1]) * APX > 0;
    if PAC = PAB then
      Exit;
    if ((X[3] - X[2]) * (PY - Y[2]) - (Y[3] - Y[2]) * (PX - X[2]) > 0) <> PAB then
      Exit;
  end;
  Result := True;
end;

function LineIn(AX, AY, BX, BY: Single; w: LongInt): Boolean;
var
  i, j: LongInt;
  PX, PY, QX, QY, AK, AM, BK, BM, VX, VY: Single;
begin
  Result := False;
  for i := 1 to 3 do
  begin
    if i = 3 then
      j := 1
    else
      j := i + 1;
    PX := Polys[w].X[i];
    PY := Polys[w].Y[i];
    QX := Polys[w].X[j];
    QY := Polys[w].Y[j];
    if (BX <> AX) or (QX <> PX) then
    begin
      if BX = AX then
      begin
        BK := (QY - PY) / (QX - PX);
        BM := PY - BK * PX;
        VX := AX;
        VY := BK * VX + BM;
        if (VX > FMin(PX, QX)) and (VX < FMax(PX, QX)) and (VY > FMin(AY, BY)) and (VY < FMax(AY, BY)) then
        begin
          Result := True;
          Exit;
        end;
      end
      else if QX = PX then
      begin
        AK := (BY - AY) / (BX - AX);
        AM := AY - AK * AX;
        VX := PX;
        VY := AK * VX + AM;
        if (VY > FMin(PY, QY)) and (VY < FMax(PY, QY)) and (VX > FMin(AX, BX)) and (VX < FMax(AX, BX)) then
        begin
          Result := True;
          Exit;
        end;
      end
      else
      begin
        AK := (BY - AY) / (BX - AX);
        BK := (QY - PY) / (QX - PX);
        if AK <> BK then
        begin
          AM := AY - AK * AX;
          BM := PY - BK * PX;
          VX := (BM - AM) / (AK - BK);
          VY := AK * VX + AM;
          if (VX > FMin(PX, QX)) and (VX < FMax(PX, QX)) and (VX > FMin(AX, BX)) and (VX < FMax(AX, BX)) then
          begin
            Result := True;
            Exit;
          end;
        end;
      end;
    end;
  end;
end;

function SegTouchesBox(AX, AY, BX, BY: Single; w: LongInt): Boolean;
var
  T0, T1, DX, DY, P, Q, R: Single;
  k: LongInt;
begin
  Result := False;
  T0 := 0;
  T1 := 1;
  DX := BX - AX;
  DY := BY - AY;
  for k := 0 to 3 do
  begin
    case k of
      0:
        begin
          P := -DX;
          Q := AX - (Polys[w].MinX - 0.5);
        end;
      1:
        begin
          P := DX;
          Q := (Polys[w].MaxX + 0.5) - AX;
        end;
      2:
        begin
          P := -DY;
          Q := AY - (Polys[w].MinY - 0.5);
        end;
    else
      begin
        P := DY;
        Q := (Polys[w].MaxY + 0.5) - AY;
      end;
    end;
    if P = 0 then
    begin
      if Q < 0 then
        Exit;
    end
    else
    begin
      R := Q / P;
      if P < 0 then
      begin
        if R > T1 then
          Exit;
        if R > T0 then
          T0 := R;
      end
      else
      begin
        if R < T0 then
          Exit;
        if R < T1 then
          T1 := R;
      end;
    end;
  end;
  Result := True;
end;

function Sane(V: Single): Boolean; inline;
begin
  Result := (V = V) and (V > -COORD_LIMIT) and (V < COORD_LIMIT);
end;

function SectorOf(V: Single): LongInt; inline;
begin
  Result := Round(V / SecDiv);
end;

procedure NextStamp;
var
  i: LongInt;
begin
  Inc(StampNow);
  if StampNow = 0 then
  begin
    for i := 0 to High(Stamp) do
      Stamp[i] := 0;
    StampNow := 1;
  end;
end;

function MapRay(AX, AY, BX, BY: Single; Flags, Team: LongInt): Boolean;
var
  i, j, X0, Y0, X1, Y1, c, p, w: LongInt;
begin
  Result := False;
  if not Loaded then
    Exit;
  if not (Sane(AX) and Sane(AY) and Sane(BX) and Sane(BY)) then
    Exit;
  X0 := SectorOf(FMin(AX, BX));
  Y0 := SectorOf(FMin(AY, BY));
  X1 := SectorOf(FMax(AX, BX));
  Y1 := SectorOf(FMax(AY, BY));
  if (X0 > SecNum) or (X1 < -SecNum) or (Y0 > SecNum) or (Y1 < -SecNum) then
    Exit;
  if X0 < -SecNum then
    X0 := -SecNum;
  if Y0 < -SecNum then
    Y0 := -SecNum;
  if X1 > SecNum then
    X1 := SecNum;
  if Y1 > SecNum then
    Y1 := SecNum;
  NextStamp;
  for i := X0 to X1 do
    for j := Y0 to Y1 do
    begin
      c := (i + SecNum) * SecSide + (j + SecNum);
      for p := SecStart[c] to SecStart[c] + SecLen[c] - 1 do
      begin
        w := SecPolys[p];
        if (w < 1) or (w > PolyN) then
          Continue;
        if Stamp[w] = StampNow then
          Continue;
        Stamp[w] := StampNow;
        if not Blocks(Polys[w].T, Flags, Team) then
          Continue;
        if not SegTouchesBox(AX, AY, BX, BY, w) then
          Continue;
        if PointIn(AX, AY, w) or LineIn(AX, AY, BX, BY, w) then
        begin
          Result := True;
          Exit;
        end;
      end;
    end;
end;

function MapPointSolid(X, Y: Single; Flags, Team: LongInt): Boolean;
var
  c, p, w, i, j: LongInt;
begin
  Result := False;
  if not Loaded then
    Exit;
  if not (Sane(X) and Sane(Y)) then
    Exit;
  i := SectorOf(X);
  j := SectorOf(Y);
  if (i < -SecNum) or (i > SecNum) or (j < -SecNum) or (j > SecNum) then
    Exit;
  c := (i + SecNum) * SecSide + (j + SecNum);
  for p := SecStart[c] to SecStart[c] + SecLen[c] - 1 do
  begin
    w := SecPolys[p];
    if (w < 1) or (w > PolyN) then
      Continue;
    if not Blocks(Polys[w].T, Flags, Team) then
      Continue;
    if (X < Polys[w].MinX) or (X > Polys[w].MaxX) or (Y < Polys[w].MinY) or (Y > Polys[w].MaxY) then
      Continue;
    if PointIn(X, Y, w) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

end.
