library basicext_dll;

{ Basic-Extended native library: the players' store and the log writer.

  Every export uses cdecl, returns at once and never lets an exception reach the caller (the game
  thread of the Soldat server). Reads and writes of the store are lookups in memory; the disk is
  written by one worker thread: the store a moment after a change, the log lines as they come. So
  a slow disk never stops a tick.

  The library pins itself on the first BE_Init: a script reload finds the running worker again
  instead of unloading code under a running thread. BE_Shutdown (the script's finalization) writes
  what is pending and stops the thread; the next BE_Init starts again from the files.

    BE_Init         the script's data folder, BE_API_VERSION of main.pas: BE_API_VERSION when it
                    runs, -BE_API_VERSION when main.pas comes from another release, 0 when it could
                    not start. It reads data/players.bdb; without one, the older data/players.txt is
                    taken over once and moved aside (players.txt.imported).
    BE_Shutdown     writes what is pending, stops the thread
    BE_Status       one line about the store and the writer
    BE_Pref_Count   the number of values kept for a key (0 = none)
    BE_Pref_Get     one of them (0 when there is none)
    BE_Pref_Begin, BE_Pref_Add, BE_Pref_Commit
                    the values of a key are replaced (no values = the key goes)
    BE_Log          a line for a text file (a path relative to the server folder, or absolute) }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  SysUtils, be_store, be_font, be_world, be_texts, be_radar, be_move, be_ballistic, be_gun, be_traj, be_fx, be_sup, be_map, be_ac;

const
  BE_API_VERSION = 3;
  GET_MODULE_HANDLE_EX_FLAG_PIN = 1;
  GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS = 4;
{$IFNDEF WINDOWS}
  RTLD_NOW_FLAG = 2;
  RTLD_NODELETE_FLAG = $1000;
{$ENDIF}

var
  AcBuf: AnsiString = '';
  AcNextBuf: AnsiString = '';
  Store: TBEStore = nil;
  Writer: TBEWriter = nil;
  Worker: TBEWorker = nil;
  Pinned: Boolean = False;
  Imported: LongInt = 0;
  PutKey: AnsiString = '';
  PutValues: TBEValues;
  StatusBuf: AnsiString = '';

{$IFDEF WINDOWS}
function PinModuleHandle(Flags: DWORD; Addr: Pointer; var Module: HMODULE): BOOL; stdcall;
  external 'kernel32.dll' name 'GetModuleHandleExA';
{$ELSE}
type
  TDlInfo = record
    dli_fname: PAnsiChar;
    dli_fbase: Pointer;
    dli_sname: PAnsiChar;
    dli_saddr: Pointer;
  end;

function be_dladdr(Addr: Pointer; var Info: TDlInfo): LongInt; cdecl; external 'dl' name 'dladdr';
function be_dlopen(Name: PAnsiChar; Flags: LongInt): Pointer; cdecl; external 'dl' name 'dlopen';
{$ENDIF}

procedure PinModule;
{$IFDEF WINDOWS}
var
  H: HMODULE;
begin
  H := 0;
  if not Pinned then
    Pinned := PinModuleHandle(GET_MODULE_HANDLE_EX_FLAG_PIN or GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS, @PinModule, H);
end;
{$ELSE}
var
  Info: TDlInfo;
begin
  if Pinned then
    Exit;
  FillChar(Info, SizeOf(Info), 0);
  if (be_dladdr(@PinModule, Info) <> 0) and (Info.dli_fname <> nil) then
    Pinned := be_dlopen(Info.dli_fname, RTLD_NOW_FLAG or RTLD_NODELETE_FLAG) <> nil;
end;
{$ENDIF}

function Str(P: PChar; MaxLen: LongInt): AnsiString;
begin
  if P = nil then
    Result := ''
  else
    Result := Copy(StrPas(P), 1, MaxLen);
end;

procedure StopAll;
begin
  if Worker <> nil then
  begin
    Worker.Terminate;
    Worker.Wake;
    Worker.WaitFor;
    FreeAndNil(Worker);
  end;
  FreeAndNil(Writer);
  FreeAndNil(Store);
end;

procedure ResetEngines;
var
  i: LongInt;
begin
  for i := 1 to BE_PLAYERS do
  begin
    RadarReset(i);
    MoveReset(i);
    GunReset(i);
    TrajReset(i);
    VisReset(i);
    WP[i].Active := False;
    WP[i].Alive := False;
    WP[i].Name := '';
  end;
  WeaponsDefault(False);
end;

function BE_Init(DataDir: PChar; ApiVersion: LongInt): LongInt; cdecl;
var
  Dir, Txt: AnsiString;
begin
  Result := 0;
  try
    if ApiVersion <> BE_API_VERSION then
    begin
      Result := -BE_API_VERSION;
      Exit;
    end;
    PinModule;
    ResetEngines;
    { a second BE_Init without BE_Shutdown (the script was loaded again): start fresh }
    StopAll;
    Dir := IncludeTrailingPathDelimiter(Str(DataDir, 1024));
    Store := TBEStore.Create(Dir + 'players.bdb');
    Writer := TBEWriter.Create;
    Imported := 0;
    if not Store.Load then
    begin
      Txt := Dir + 'players.txt';
      if FileExists(Txt) then
      begin
        Imported := Store.ImportText(Txt);
        if Store.Save then
          RenameFile(Txt, Txt + '.imported');
      end;
    end;
    Worker := TBEWorker.Create(Store, Writer);
    Result := BE_API_VERSION;
  except
    try
      StopAll;
    except
    end;
    Result := 0;
  end;
end;

procedure BE_Shutdown; cdecl;
begin
  try
    StopAll;
  except
  end;
end;

function BE_Status: PChar; cdecl;
begin
  try
    if Store = nil then
      StatusBuf := 'not running'
    else
    begin
      StatusBuf := 'players ' + IntToStr(Store.Size) + ' (saved ' + IntToStr(Store.Saves) + ' times';
      if Imported > 0 then
        StatusBuf := StatusBuf + ', ' + IntToStr(Imported) + ' taken over from players.txt';
      StatusBuf := StatusBuf + '), log lines written ' + IntToStr(Writer.Written) + ', waiting ' +
        IntToStr(Writer.Pending);
      if Writer.Dropped > 0 then
        StatusBuf := StatusBuf + ', dropped ' + IntToStr(Writer.Dropped);
      if Store.Errors + Writer.Errors > 0 then
        StatusBuf := StatusBuf + ', errors ' + IntToStr(Store.Errors + Writer.Errors) + ' (last: ' +
          Store.LastError + Writer.LastError + ')';
    end;
    if MapReady then
      StatusBuf := StatusBuf + ', map polygons ' + IntToStr(MapPolys) + ', trajectories computed ' +
        IntToStr(TrajRecomputed)
    else
      StatusBuf := StatusBuf + ', map not loaded';
  except
    StatusBuf := 'status failed';
  end;
  Result := PChar(StatusBuf);
end;

function BE_Pref_Count(Key: PChar): LongInt; cdecl;
begin
  Result := 0;
  try
    if Store <> nil then
      Result := Store.Count(Str(Key, 200));
  except
    Result := 0;
  end;
end;

function BE_Pref_Get(Key: PChar; Index: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    if Store <> nil then
      Result := Store.Get(Str(Key, 200), Index);
  except
    Result := 0;
  end;
end;

procedure BE_Pref_Begin(Key: PChar); cdecl;
begin
  try
    PutKey := Str(Key, 200);
    SetLength(PutValues, 0);
  except
  end;
end;

procedure BE_Pref_Add(Value: LongInt); cdecl;
begin
  try
    if Length(PutValues) < BE_MAX_VALUES then
    begin
      SetLength(PutValues, Length(PutValues) + 1);
      PutValues[High(PutValues)] := Value;
    end;
  except
  end;
end;

procedure BE_Pref_Commit; cdecl;
begin
  try
    if Store <> nil then
      if PutKey <> '' then
      begin
        Store.Put(PutKey, PutValues);
        Worker.Wake;
      end;
    PutKey := '';
    SetLength(PutValues, 0);
  except
  end;
end;

procedure BE_Log(FileName, Line: PChar); cdecl;
begin
  try
    if Writer <> nil then
    begin
      Writer.Add(Str(FileName, 1024), Str(Line, 8192));
      Worker.Wake;
    end;
  except
  end;
end;

procedure BE_World(Tick, Count: LongInt; I: PLongArr; F: PSingleArr); cdecl;
begin
  try
    if (I <> nil) and (F <> nil) then
    begin
      WorldLoad(Tick, Count, I, F);
      if AcEnabled then
        AcWorld(Tick);
    end;
  except
  end;
end;

procedure BE_AcSet(Key: LongInt; Value: Single); cdecl;
begin
  try
    AcSet(Key, Value);
  except
  end;
end;

procedure BE_AcReset(ID: LongInt); cdecl;
begin
  try
    AcReset(ID);
  except
  end;
end;

procedure BE_AcKeys(Tick, Count: LongInt; I: PLongArr); cdecl;
begin
  try
    if I <> nil then
      AcKeys(Tick, Count, I);
  except
  end;
end;

procedure BE_AcMoved(ID, Tick: LongInt); cdecl;
begin
  try
    AcMoved(ID, Tick);
  except
  end;
end;

procedure BE_AcHurt(Victim, Tick, W: LongInt); cdecl;
begin
  try
    AcHurt(Victim, Tick, W);
  except
  end;
end;

function BE_AcHit(Tick, Shooter, W, Bullet: LongInt; Damage, BX, BY, BVX, BVY, SX, SY: Single): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := AcHit(Tick, Shooter, W, Bullet, Damage, BX, BY, BVX, BVY, SX, SY);
  except
    Result := 0;
  end;
end;

function BE_AcWatched(W: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    if AcWatched(W) then
      Result := 1;
  except
    Result := 0;
  end;
end;

function BE_AcNext(ID, Kind: PLongInt): PChar; cdecl;
var
  a, b: LongInt;
begin
  AcNextBuf := '';
  try
    if AcNext(a, b, AcNextBuf) then
    begin
      ID^ := a;
      Kind^ := b;
    end;
  except
    AcNextBuf := '';
  end;
  Result := PChar(AcNextBuf);
end;

function BE_AcScore(ID: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := AcScore(ID);
  except
    Result := 0;
  end;
end;

procedure AcStored(const K: AnsiString; out T: TAcTotals);
var
  i, n: LongInt;
begin
  for i := 0 to AC_TOTALS - 1 do
    T[i] := 0;
  T[T_SU_MIN] := -1;
  if (Store = nil) or (K = '') then
    Exit;
  n := Store.Count(K);
  if n > AC_TOTALS then
    n := AC_TOTALS;
  for i := 0 to n - 1 do
    T[i] := Store.Get(K, i);
end;

procedure AcMerge(var A: TAcTotals; const B: TAcTotals);
var
  i: LongInt;
begin
  for i := 0 to AC_TOTALS - 1 do
    case i of
      T_SU_MIN:
        if (B[i] >= 0) and ((A[i] < 0) or (B[i] < A[i])) then
          A[i] := B[i];
      T_JUMP_MAX:
        if B[i] > A[i] then
          A[i] := B[i];
    else
      A[i] := A[i] + B[i];
    end;
end;

function BE_AcLine(ID: LongInt; Key: PChar): PChar; cdecl;
var
  T, S: TAcTotals;
  K: AnsiString;
begin
  AcBuf := '';
  try
    AcTotals(ID, T);
    AcBuf := AcLineOf(T);
    K := Str(Key, 200);
    if K <> '' then
    begin
      AcStored(K, S);
      if S[T_SESSIONS] > 0 then
      begin
        AcMerge(S, T);
        AcBuf := 'now ' + AcBuf + ' | all ' + IntToStr(S[T_SESSIONS]) + ' games ' + AcLineOf(S);
      end;
    end;
  except
    AcBuf := '';
  end;
  Result := PChar(AcBuf);
end;

procedure BE_AcSave(ID: LongInt; Key: PChar); cdecl;
var
  T, S: TAcTotals;
  K: AnsiString;
  V: TBEValues;
  i: LongInt;
begin
  try
    K := Str(Key, 200);
    if (Store = nil) or (K = '') then
      Exit;
    AcTotals(ID, T);
    if T[T_SU_N] + T[T_RATE] + T[T_JUMPS] + T[T_B_HITS] + T[T_M_HITS] + T[T_HITS] = 0 then
      Exit;
    AcStored(K, S);
    AcMerge(S, T);
    SetLength(V, AC_TOTALS);
    for i := 0 to AC_TOTALS - 1 do
      V[i] := S[i];
    Store.Put(K, V);
    Worker.Wake;
  except
  end;
end;

procedure BE_AcForget(Key: PChar); cdecl;
var
  V: TBEValues;
begin
  try
    if Store = nil then
      Exit;
    SetLength(V, 0);
    Store.Put(Str(Key, 200), V);
    Worker.Wake;
  except
  end;
end;

procedure BE_Name(ID: LongInt; Name: PChar); cdecl;
begin
  try
    WorldName(ID, Str(Name, 64));
  except
  end;
end;

procedure BE_Vis(S, B, Seen: LongInt); cdecl;
begin
  try
    VisSet(S, B, Seen <> 0);
  except
  end;
end;

procedure BE_VisReset(ID: LongInt); cdecl;
begin
  try
    VisReset(ID);
  except
  end;
end;

function BE_VisNeeded: LongInt; cdecl;
begin
  Result := 0;
  try
    if VisNeeded then
      Result := 1;
  except
    Result := 0;
  end;
end;

function BE_MapLoad(Path: PChar): LongInt; cdecl;
begin
  Result := -3;
  try
    Result := MapLoad(Str(Path, 512));
  except
    MapClear;
    Result := -3;
  end;
end;

function BE_MapRay(X1, Y1, X2, Y2: Single; Flags, Team: LongInt): LongInt; cdecl;
begin
  Result := -1;
  try
    if MapReady then
      if MapRay(X1, Y1, X2, Y2, Flags, Team) then
        Result := 1
      else
        Result := 0;
  except
    Result := -1;
  end;
end;

function BE_VisRun(Tick: LongInt): LongInt; cdecl;
var
  a, c: LongInt;
  p, q, r, t: Single;
begin
  Result := -1;
  try
    if not MapReady then
      Exit;
    Result := 0;
    while VisNext(Tick, a, c, p, q, r, t) do
    begin
      VisSet(a, c, not MapRay(p, q, r, t, 0, 0));
      Inc(Result);
    end;
  except
    Result := -1;
  end;
end;

function BE_VisNext(Tick: LongInt; S, B: PLongInt; X1, Y1, X2, Y2: PSingle): LongInt; cdecl;
var
  a, c: LongInt;
  p, q, r, t: Single;
begin
  Result := 0;
  try
    if VisNext(Tick, a, c, p, q, r, t) then
    begin
      Result := 1;
      S^ := a;
      B^ := c;
      X1^ := p;
      Y1^ := q;
      X2^ := r;
      Y2^ := t;
    end;
  except
    Result := 0;
  end;
end;

procedure BE_RadarInt(Key, Value: LongInt); cdecl;
begin
  try
    RadarInt(Key, Value);
  except
  end;
end;

procedure BE_RadarFloat(Key: LongInt; Value: Single); cdecl;
begin
  try
    RadarFloat(Key, Value);
  except
  end;
end;

procedure BE_RadarText(Key: LongInt; Value: PChar); cdecl;
begin
  try
    RadarText(Key, Str(Value, 400));
  except
  end;
end;

procedure BE_RadarUser(ID, On, Mode, Show, PX, PY: LongInt; Size, Zoom, MarkSize: Single; Editing: LongInt); cdecl;
begin
  try
    RadarUser(ID, On, Mode, Show, PX, PY, Size, Zoom, MarkSize, Editing);
  except
  end;
end;

procedure BE_RadarOpt(ID, Key, Value: LongInt); cdecl;
begin
  try
    RadarOpt(ID, Key, Value);
  except
  end;
end;

function BE_RadarPass(ID, Tick, Budget: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := RadarPass(ID, Tick, Budget);
    if RadarPending(ID) <> 0 then
      Result := Result + 65536;
  except
    OpCount := 0;
    Result := 0;
  end;
end;

function BE_RadarHide(ID, Budget: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := RadarHide(ID, Budget);
  except
    OpCount := 0;
    Result := 0;
  end;
end;

function BE_RadarPending(ID: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := RadarPending(ID);
  except
    Result := 0;
  end;
end;

procedure BE_RadarReset(ID: LongInt); cdecl;
begin
  try
    RadarReset(ID);
  except
  end;
end;

procedure BE_RadarRedraw(ID: LongInt); cdecl;
begin
  try
    RadarRedraw(ID);
  except
  end;
end;

function BE_RadarRange(ID: LongInt): Single; cdecl;
begin
  Result := 0;
  try
    Result := RadarRange(ID);
  except
    Result := 0;
  end;
end;

function BE_Op(Index: LongInt; Kind, Layer, Delay, Color: PLongInt; Scale, X, Y: PSingle): PChar; cdecl;
begin
  Result := ' ';
  try
    if (Index >= 0) and (Index < OpCount) then
    begin
      Kind^ := Ops[Index].Kind;
      Layer^ := Ops[Index].Layer;
      Delay^ := Ops[Index].Delay;
      Color^ := Ops[Index].Color;
      Scale^ := Ops[Index].Scale;
      X^ := Ops[Index].X;
      Y^ := Ops[Index].Y;
      Result := PChar(Ops[Index].Text);
    end
    else
      Kind^ := 0;
  except
    Result := ' ';
  end;
end;

var
  ReplaceBuf: AnsiString = '';

function BE_Replace(Text, Find, Repl: PChar): PChar; cdecl;
begin
  try
    ReplaceBuf := StringReplace(Str(Text, 65536), Str(Find, 4096), Str(Repl, 65536), [rfReplaceAll]);
  except
    ReplaceBuf := Str(Text, 65536);
  end;
  Result := PChar(ReplaceBuf);
end;

procedure BE_SupConfig(Radius, RadiusBig: Single; ScanTicks, TeamBullets, FriendlyFire, TeamGame: LongInt); cdecl;
begin
  try
    SupConfig(Radius, RadiusBig, ScanTicks, TeamBullets <> 0, FriendlyFire <> 0, TeamGame <> 0);
  except
  end;
end;

procedure BE_SupPlayers(n: LongInt; I: PLongArr; F: PSingleArr); cdecl;
begin
  try
    SupPlayers(n, I, F);
  except
  end;
end;

function BE_SupBullet(Owner, Style: LongInt; X, Y, VX, VY: Single): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := SupBullet(Owner, Style, X, Y, VX, VY);
  except
    Result := 0;
  end;
end;

procedure BE_Team(ID, Team: LongInt); cdecl;
begin
  try
    TeamSet(ID, Team);
  except
  end;
end;

function BE_TextWidth(Text: PChar; Scale: Single): Single; cdecl;
begin
  Result := 0;
  try
    Result := TextAdvance(Str(Text, 400)) * Scale * WORLD_EM;
  except
    Result := 0;
  end;
end;

procedure BE_MoveSet(Key: LongInt; Value: Single); cdecl;
begin
  try
    MoveSet(Key, Value);
  except
  end;
end;

function BE_Move(ID, Tick, Mode, Variant, Key, Alive, Ping, Team, Opts: LongInt; X, Y, VX, VY: Single;
  AimX, AimY: LongInt; OX, OY, OVX, OVY: PSingle): LongInt; cdecl;
var
  a, b, c, d: Single;
begin
  Result := 0;
  try
    Result := MoveStep(ID, Tick, Mode, Variant, Key, Alive, Ping, Team, Opts, X, Y, VX, VY, AimX, AimY, a, b, c, d);
    OX^ := a;
    OY^ := b;
    OVX^ := c;
    OVY^ := d;
  except
    Result := 0;
  end;
end;

procedure BE_MoveBlocked(ID, Tick: LongInt); cdecl;
begin
  try
    MoveBlocked(ID, Tick);
  except
  end;
end;

procedure BE_MoveReset(ID: LongInt); cdecl;
begin
  try
    MoveReset(ID);
  except
  end;
end;

function BE_WeaponsLoad(Path: PChar; Realistic: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := WeaponsLoad(Str(Path, 1024), Realistic <> 0);
  except
    Result := 0;
  end;
end;

procedure BE_Gravity(G: Single); cdecl;
begin
  try
    if G > 0 then
      BulletGravity := G * 2.25;
  except
  end;
end;

function BE_Weapon(W: LongInt; Speed, Damage, Spread, Inherit: PSingle; Style, Interval, Ammo, Reload,
  StartUp: PLongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    if not ValidWeapon(W) then
      Exit;
    Speed^ := ShotSpeed(W);
    Damage^ := ShotDamage(W);
    Spread^ := Weapon[W].Spread;
    Inherit^ := Weapon[W].Inherit;
    Style^ := ShotStyle(W);
    Interval^ := Weapon[W].Interval;
    Ammo^ := Weapon[W].Ammo;
    Reload^ := Weapon[W].Reload;
    StartUp^ := Weapon[W].StartUp;
    Result := 1;
  except
    Result := 0;
  end;
end;

function BE_WeaponSound(W: LongInt): PChar; cdecl;
begin
  Result := '';
  try
    if ValidWeapon(W) then
      Result := PChar(Weapon[W].Sound);
  except
    Result := '';
  end;
end;

function BE_Path(W: LongInt; X, Y, VX, VY, AimX, AimY: Single; MaxTicks: LongInt; Spacing, MaxRange: Single): LongInt;
  cdecl;
begin
  Result := 0;
  try
    Result := BuildPath(W, X, Y, VX, VY, AimX, AimY, MaxTicks, Spacing, MaxRange);
  except
    PathCount := 0;
    Result := 0;
  end;
end;

function BE_PathClip(CX, CY, HW, HH: Single): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := PathClip(CX, CY, HW, HH);
  except
    Result := 0;
  end;
end;

function BE_Muzzle(X, Y, AimX, AimY: Single; Flags: LongInt; OX, OY: PSingle): LongInt; cdecl;
var
  a, b, c, d: Single;
begin
  Result := 0;
  try
    Muzzle(X, Y, AimX, AimY, Flags, a, b, c, d);
    OX^ := a;
    OY^ := b;
    Result := 1;
  except
    Result := 0;
  end;
end;

function BE_PathPoint(Index: LongInt; X, Y: PSingle): LongInt; cdecl;
begin
  Result := 0;
  try
    if (Index >= 0) and (Index < PathCount) then
    begin
      X^ := PathX[Index];
      Y^ := PathY[Index];
      Result := 1;
    end;
  except
    Result := 0;
  end;
end;

function BE_Solve(W: LongInt; SX, SY, SVX, SVY, TX, TY, TVX, TVY, TGrav: Single; DX, DY: PSingle;
  Ticks: PLongInt): LongInt; cdecl;
var
  a, b: Single;
  t: LongInt;
begin
  Result := 0;
  try
    if Solve(W, SX, SY, SVX, SVY, TX, TY, TVX, TVY, TGrav, a, b, t) then
      Result := 1;
    DX^ := a;
    DY^ := b;
    Ticks^ := t;
  except
    Result := 0;
  end;
end;

function BE_Shot(W: LongInt; SX, SY, SVX, SVY, DX, DY, Spread: Single; Seed, Flags: LongInt; Style: PLongInt;
  HitM: PSingle): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := BuildShot(W, SX, SY, SVX, SVY, DX, DY, Spread, Seed, Flags);
    Style^ := ShotStyle(W);
    HitM^ := ShotDamage(W);
  except
    ShotCount := 0;
    Result := 0;
  end;
end;

function BE_ShotGet(Index: LongInt; X, Y, VX, VY: PSingle): LongInt; cdecl;
begin
  Result := 0;
  try
    if (Index >= 0) and (Index < ShotCount) then
    begin
      X^ := ShotX[Index];
      Y^ := ShotY[Index];
      VX^ := ShotVX[Index];
      VY^ := ShotVY[Index];
      Result := 1;
    end;
  except
    Result := 0;
  end;
end;

function BE_GunTick(ID, Tick, W, Trigger, Infinite: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := GunTick(ID, Tick, W, Trigger, Infinite);
  except
    Result := 0;
  end;
end;

procedure BE_GunFired(ID, Tick: LongInt); cdecl;
begin
  try
    GunFired(ID, Tick);
  except
  end;
end;

procedure BE_GunReset(ID: LongInt); cdecl;
begin
  try
    GunReset(ID);
  except
  end;
end;

function BE_GunTargets(Shooter, Mode: LongInt; MaxDist, MaxAngle: Single): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := GunTargets(Shooter, Mode, MaxDist, MaxAngle);
  except
    Result := 0;
  end;
end;

function BE_GunTarget(Index: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := GunTarget(Index);
  except
    Result := 0;
  end;
end;

function BE_GunPick(Shooter, Mode: LongInt; MaxDist, MaxAngle, SX, SY, BodyH: Single; MaxCheck: LongInt): LongInt;
  cdecl;
var
  c, k, n, T: LongInt;
begin
  Result := -1;
  try
    if not MapReady then
      Exit;
    Result := 0;
    T := 0;
    if ValidID(Shooter) then
      T := WP[Shooter].Team;
    c := GunTargets(Shooter, Mode, MaxDist, MaxAngle);
    k := 0;
    while (k < c) and (k < MaxCheck) do
    begin
      n := GunTarget(k);
      if ValidID(n) then
        if not MapRay(SX, SY, WP[n].X, WP[n].Y - BodyH, MR_BULLET, T) then
        begin
          Result := n;
          Exit;
        end;
      Inc(k);
    end;
  except
    Result := -1;
  end;
end;

procedure BE_TrajInt(Key, Value: LongInt); cdecl;
begin
  try
    TrajInt(Key, Value);
  except
  end;
end;

procedure BE_TrajFloat(Key: LongInt; Value: Single); cdecl;
begin
  try
    TrajFloat(Key, Value);
  except
  end;
end;

procedure BE_TrajText(Key: LongInt; Value: PChar); cdecl;
begin
  try
    TrajText(Key, Str(Value, 8));
  except
  end;
end;

function BE_TrajPass(ID, Tick, Budget, Visible, Hit: LongInt; CX, CY: Single; Cursor: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := TrajPass(ID, Tick, Budget, Visible, Hit, CX, CY, Cursor);
  except
    OpCount := 0;
    Result := 0;
  end;
end;

function BE_TrajStep(ID, Tick, Budget, W, Flags, Team: LongInt; X, Y, VX, VY, AimX, AimY: Single;
  Cursor: LongInt): LongInt; cdecl;
begin
  Result := -1;
  try
    Result := TrajStep(ID, Tick, Budget, W, Flags, Team, X, Y, VX, VY, AimX, AimY, Cursor);
  except
    OpCount := 0;
    Result := 0;
  end;
end;

function BE_TrajHide(ID, Budget: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := TrajHide(ID, Budget);
  except
    OpCount := 0;
    Result := 0;
  end;
end;

procedure BE_TrajReset(ID: LongInt); cdecl;
begin
  try
    TrajReset(ID);
  except
  end;
end;

function BE_Fx(Kind, Seed: LongInt; Power: Single): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := FxBuild(Kind, Seed, Power);
  except
    FxCount := 0;
    Result := 0;
  end;
end;

function BE_FxGet(Index: LongInt; DX, DY, VX, VY, HitM: PSingle; Style, Delay: PLongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    if (Index >= 0) and (Index < FxCount) then
    begin
      DX^ := Fx[Index].DX;
      DY^ := Fx[Index].DY;
      VX^ := Fx[Index].VX;
      VY^ := Fx[Index].VY;
      HitM^ := Fx[Index].HitM;
      Style^ := Fx[Index].Style;
      Delay^ := Fx[Index].Delay;
      Result := 1;
    end;
  except
    Result := 0;
  end;
end;

exports
  BE_Init,
  BE_Shutdown,
  BE_Status,
  BE_Pref_Count,
  BE_Pref_Get,
  BE_Pref_Begin,
  BE_Pref_Add,
  BE_Pref_Commit,
  BE_Log,
  BE_World,
  BE_AcSet,
  BE_AcReset,
  BE_AcKeys,
  BE_AcMoved,
  BE_AcHurt,
  BE_AcHit,
  BE_AcWatched,
  BE_AcNext,
  BE_AcScore,
  BE_AcLine,
  BE_AcSave,
  BE_AcForget,
  BE_Name,
  BE_Vis,
  BE_VisReset,
  BE_VisNeeded,
  BE_VisNext,
  BE_VisRun,
  BE_MapLoad,
  BE_MapRay,
  BE_RadarInt,
  BE_RadarFloat,
  BE_RadarText,
  BE_RadarUser,
  BE_RadarOpt,
  BE_RadarPass,
  BE_RadarHide,
  BE_RadarPending,
  BE_RadarReset,
  BE_RadarRedraw,
  BE_RadarRange,
  BE_Op,
  BE_TextWidth,
  BE_Replace,
  BE_SupConfig,
  BE_SupPlayers,
  BE_SupBullet,
  BE_Team,
  BE_MoveSet,
  BE_Move,
  BE_MoveBlocked,
  BE_MoveReset,
  BE_WeaponsLoad,
  BE_Gravity,
  BE_Weapon,
  BE_WeaponSound,
  BE_Path,
  BE_PathPoint,
  BE_PathClip,
  BE_Muzzle,
  BE_Solve,
  BE_Shot,
  BE_ShotGet,
  BE_GunTick,
  BE_GunFired,
  BE_GunReset,
  BE_GunTargets,
  BE_GunTarget,
  BE_GunPick,
  BE_TrajInt,
  BE_TrajFloat,
  BE_TrajText,
  BE_TrajPass,
  BE_TrajStep,
  BE_TrajHide,
  BE_TrajReset,
  BE_Fx,
  BE_FxGet;

end.
