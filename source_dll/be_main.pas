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
    BE_Pref_Load    the values of a key (at most 256)
    BE_Pref_Save    the values of a key are replaced (no values = the key goes)
    BE_Log          a line for a text file (a path relative to the server folder, or absolute) }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  SysUtils, SyncObjs, be_store, be_font, be_world, be_texts, be_radar, be_move, be_ballistic, be_gun, be_traj, be_fx, be_sup, be_map, be_ac, be_util, be_bridge, be_hook, be_ammo, be_prof, be_rocket, be_sprite, be_tk, be_mine, be_body, be_names, be_shop, be_hud;


const
  BE_API_VERSION = 23;
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
  StatusBuf: AnsiString = '';
  BridgeBuf: AnsiString = '';
  HookBuf: AnsiString = '';
  ProfBuf: AnsiString = '';
  ChatBuf: AnsiString = '';
  HudOpBuf: AnsiString = '';
  WoundBuf: AnsiString = '';
  MemInfoBuf: AnsiString = '';
  RkBuf: AnsiString = '';
  TkBuf: AnsiString = '';
  MnBuf: AnsiString = '';
  NamesBuf: AnsiString = '';
  BdBuf: AnsiString = '';

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
  HookShutdown;
  if Worker <> nil then
  begin
    Worker.Terminate;
    Worker.Wake;
    { the worker writes what waits; a stuck disk does not hold the game: after 3 s the thread is left with its
      objects (the library stays loaded, so their code stays too) }
    if Worker.Done.WaitFor(3000) = wrSignaled then
    begin
      Worker.WaitFor;
      FreeAndNil(Worker);
      FreeAndNil(Writer);
      FreeAndNil(Store);
    end
    else
    begin
      Worker := nil;
      Writer := nil;
      Store := nil;
    end;
    Exit;
  end;
  FreeAndNil(Writer);
  FreeAndNil(Store);
end;

procedure ResetEngines;
var
  i: LongInt;
begin
  BridgeReset;
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
  RkReset;
  MnClear;
  SpotClear;
  for i := 1 to BE_PLAYERS do
  begin
    MnForget(i);
    BdReset(i);
  end;
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
      StatusBuf := StatusBuf + ', map polygons ' + IntToStr(MapPolys) + ' and colliders ' + IntToStr(MapColliders) +
        ', trajectories computed ' + IntToStr(TrajRecomputed)
    else
      StatusBuf := StatusBuf + ', map not loaded';
    StatusBuf := StatusBuf + ', bridge: ' + BridgeInfo + ', ' + HookInfo + ', ' + AmmoStatus;
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
      LagWorld(Tick);
    end;
  except
  end;
end;

procedure BE_SnapBegin(Tick: LongInt); cdecl;
begin
  try
    WorldBegin(Tick);
  except
  end;
end;

procedure BE_SnapPos(ID, Alive: LongInt; X, Y: Single); cdecl;
begin
  try
    WorldPos(ID, Alive, X, Y);
  except
  end;
end;

procedure BE_SnapAim(ID, AimX, AimY: LongInt); cdecl;
begin
  try
    WorldAim(ID, AimX, AimY);
  except
  end;
end;

procedure BE_SnapVel(ID: LongInt; VX, VY: Single); cdecl;
begin
  try
    WorldVel(ID, VX, VY);
  except
  end;
end;

procedure BE_SnapExtra(ID, Pct, Tag, Ping: LongInt); cdecl;
begin
  try
    WorldExtra(ID, Pct, Tag, Ping);
  except
  end;
end;

procedure BE_SnapFlag(Index, Team, State: LongInt; X, Y: Single); cdecl;
begin
  try
    WorldFlag(Index, Team, State, X, Y);
  except
  end;
end;

procedure BE_SnapEnd(Tick: LongInt); cdecl;
begin
  try
    WorldEnd;
    if AcEnabled then
      AcWorld(Tick);
    LagWorld(Tick);
  except
  end;
end;

{ [LagGuard] }
procedure BE_LagSet(Key: LongInt; Value: Single); cdecl;
begin
  try
    LagSet(Key, Value);
  except
  end;
end;

function BE_LagWarps(ID: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := LagWarps(ID);
  except
    Result := 0;
  end;
end;

procedure BE_LagReset(ID: LongInt); cdecl;
begin
  try
    LagReset(ID);
  except
  end;
end;

procedure BE_Human(ID, Human: LongInt); cdecl;
begin
  try
    WorldMeta(ID, -100, Human);
    MnHuman(ID, Human);
    BdHuman(ID, Human);
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

function BE_AcHit(Tick, Shooter, W, Bullet: LongInt; BX, BY, BVX, BVY, SX, SY: Single): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := AcHit(Tick, Shooter, W, Bullet, BX, BY, BVX, BVY, SX, SY);
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

function BE_AcText(ID: LongInt; Key: PChar; Kind, Tick: LongInt): PChar; cdecl;
var
  T, S: TAcTotals;
  K: AnsiString;
begin
  AcBuf := '';
  try
    AcTotals(ID, T);
    case Kind of
      0: AcBuf := AcBrief(T);
      1, 2, 3, 5:
        begin
          K := Str(Key, 200);
          AcStored(K, S);
          if S[T_SESSIONS] < 0 then
            S[T_SESSIONS] := 0;
          AcMerge(S, T);
          case Kind of
            1: AcBuf := AcTable(T, S);
            2:
              if S[T_SESSIONS] = 1 then
                AcBuf := '1 game: ' + AcBrief(S)
              else
                AcBuf := IntToStr(S[T_SESSIONS]) + ' games: ' + AcBrief(S);
            3: AcBuf := AcDetail(S);
            5: AcBuf := IntToStr(AcScoreOf(S)) + '|' + IntToStr(S[T_SESSIONS]);
          end;
        end;
      4: AcBuf := AcReview(ID, Tick);
    end;
  except
    AcBuf := '';
  end;
  Result := PChar(AcBuf);
end;

function BE_AcFindings(ID: LongInt): LongInt; cdecl;
var
  T: TAcTotals;
begin
  Result := 0;
  try
    AcTotals(ID, T);
    Result := AcFindings(T);
  except
    Result := 0;
  end;
end;

procedure BE_AcAmmo(ID, Tick, W, Ammo: LongInt); cdecl;
begin
  try
    AcAmmo(ID, Tick, W, Ammo);
  except
  end;
end;

procedure BE_AcAmmoReset(ID: LongInt); cdecl;
begin
  try
    AcAmmoReset(ID);
  except
  end;
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
    if T[T_SU_N] + T[T_RATE] + T[T_JUMPS] + T[T_B_HITS] + T[T_M_HITS] + T[T_SPEED] + T[T_AMMO] + T[T_RELOAD] = 0 then
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

function BE_AcForgetAll(): LongInt; cdecl;
begin
  Result := 0;
  try
    if Store = nil then
      Exit;
    Result := Store.DeletePrefix('ac:');
    Worker.Wake;
  except
    Result := 0;
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

procedure BE_RadarReset(ID: LongInt); cdecl;
begin
  try
    RadarReset(ID);
  except
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
  FillBuf: AnsiString = '';
  FloatBuf: AnsiString = '';
  HudBuf: AnsiString = '';
  AmmoHudBuf: AnsiString = '';
  NameBuf: AnsiString = '';

function BE_Replace(Text, Find, Repl: PChar): PChar; cdecl;
begin
  try
    ReplaceBuf := StringReplace(Str(Text, 65536), Str(Find, 4096), Str(Repl, 65536), [rfReplaceAll]);
  except
    ReplaceBuf := Str(Text, 65536);
  end;
  Result := PChar(ReplaceBuf);
end;

function BE_Fill(Text, Pairs: PChar): PChar; cdecl;
begin
  try
    FillBuf := Fill(Str(Text, 65536), Str(Pairs, 65536));
  except
    FillBuf := Str(Text, 65536);
  end;
  Result := PChar(FillBuf);
end;

function BE_FloatStr(V: Single; Decimals: LongInt): PChar; cdecl;
begin
  try
    if Decimals < 0 then
      Decimals := 0;
    if Decimals > 6 then
      Decimals := 6;
    FloatBuf := FloatText(V, Decimals);
  except
    FloatBuf := '0';
  end;
  Result := PChar(FloatBuf);
end;

function BE_MixColor(A, B: LongInt; T: Single): LongInt; cdecl;
begin
  Result := A;
  try
    Result := MixColor(A, B, T);
  except
  end;
end;

procedure BE_HudStyle(Style: LongInt; Template: PChar); cdecl;
begin
  try
    HudStyle(Style, Str(Template, 1024));
  except
  end;
end;

procedure BE_HudBar(Full, Empty: PChar; Len: LongInt); cdecl;
begin
  try
    HudBar(Str(Full, 16), Str(Empty, 16), Len);
  except
  end;
end;

procedure BE_HudRegen(Mark: PChar); cdecl;
begin
  try
    HudRegen(Str(Mark, 64));
  except
  end;
end;

function BE_HudText(Style, Pct, Hp, MaxHp, Vest, Regen: LongInt): PChar; cdecl;
begin
  try
    HudBuf := HudText(Style, Pct, Hp, MaxHp, Vest, Regen);
  except
    HudBuf := '';
  end;
  Result := PChar(HudBuf);
end;

function BE_AmmoFormatHud(ID, Weapon, Clip: LongInt): PChar; cdecl;
begin
  try
    AmmoHudBuf := AmmoFormatHud(ID, Weapon, Clip);
  except
    AmmoHudBuf := '';
  end;
  Result := PChar(AmmoHudBuf);
end;

procedure BE_LogStamp(Folder, Text, Watched: PChar); cdecl;
var
  F, T, W: AnsiString;
begin
  try
    if Writer = nil then
      Exit;
    F := Str(Folder, 900);
    T := StampLine(Str(Text, 8000));
    Writer.Add(DayFile(F), T);
    W := Str(Watched, 100);
    if W <> '' then
      Writer.Add(F + 'watched/' + W + '.txt', FormatDateTime('yyyy-mm-dd ', Now) + T);
    Worker.Wake;
  except
  end;
end;

function BE_Pref_Load(Key: PChar; V: PLongArr): LongInt; cdecl;
var
  K: AnsiString;
  n, i: LongInt;
begin
  Result := 0;
  try
    if (Store = nil) or (V = nil) then
      Exit;
    K := Str(Key, 200);
    n := Store.Count(K);
    if n > 256 then
      n := 256;
    for i := 0 to n - 1 do
      V^[i] := Store.Get(K, i);
    Result := n;
  except
    Result := 0;
  end;
end;

procedure BE_Pref_Save(Key: PChar; Count: LongInt; V: PLongArr); cdecl;
var
  Vals: TBEValues;
  i: LongInt;
begin
  try
    if (Store = nil) or (V = nil) then
      Exit;
    if Count < 0 then
      Count := 0;
    if Count > BE_MAX_VALUES then
      Count := BE_MAX_VALUES;
    SetLength(Vals, Count);
    for i := 0 to Count - 1 do
      Vals[i] := V^[i];
    Store.Put(Str(Key, 200), Vals);
    Worker.Wake;
  except
  end;
end;

function BE_Sees(VX, VY, AimX, AimY, TX, TY: Single; Range: Single; Team: LongInt): LongInt; cdecl;
var
  DX, DY: Single;
begin
  Result := 1;
  try
    DX := TX - VX;
    DY := TY - VY;
    if DX * (AimX - VX) + DY * (AimY - VY) <= 0 then
    begin
      Result := 0;
      Exit;
    end;
    if DX * DX + DY * DY > Range * Range then
    begin
      Result := 0;
      Exit;
    end;
    if MapReady then
      if MapRay(VX, VY, TX, TY, 0, Team) then
        Result := 0;
  except
    Result := 1;
  end;
end;

function BE_WeaponName(Num: LongInt): PChar; cdecl;
begin
  try
    case Num of
      0: NameBuf := 'USSOCOM';
      1: NameBuf := 'Desert Eagles';
      2: NameBuf := 'HK MP5';
      3: NameBuf := 'Ak-74';
      4: NameBuf := 'Steyr AUG';
      5: NameBuf := 'Spas-12';
      6: NameBuf := 'Ruger 77';
      7: NameBuf := 'M79';
      8: NameBuf := 'Barrett M82A1';
      9: NameBuf := 'FN Minimi';
      10: NameBuf := 'XM214 Minigun';
      11: NameBuf := 'Combat Knife';
      12: NameBuf := 'Chainsaw';
      13: NameBuf := 'M72 LAW';
      14: NameBuf := 'Flamer';
      15: NameBuf := 'Rambo Bow';
      16: NameBuf := 'Flamed Arrows';
      30: NameBuf := 'Stationary gun';
      50: NameBuf := 'Grenade';
      51: NameBuf := 'Cluster grenade';
      52: NameBuf := 'Cluster';
      53: NameBuf := 'Thrown knife';
      255: NameBuf := 'Hands';
    else
      NameBuf := 'unknown';
    end;
  except
    NameBuf := 'unknown';
  end;
  Result := PChar(NameBuf);
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
    WorldMeta(ID, Team, -1);
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

procedure BE_ShotPush(var PX, PY: Single); cdecl;
begin
  PX := 0;
  PY := 0;
  try
    PX := ShotPushX;
    PY := ShotPushY;
  except
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

function BE_GunTargets(Shooter, Mode: LongInt; MaxDist, Limit: Single): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := GunTargets(Shooter, Mode, MaxDist, Limit);
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

function BE_GunPick(Shooter, Mode: LongInt; MaxDist, Limit, SX, SY, BodyH: Single; MaxCheck, RayFlags: LongInt): LongInt;
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
    c := GunTargets(Shooter, Mode, MaxDist, Limit);
    k := 0;
    while (k < c) and (k < MaxCheck) do
    begin
      n := GunTarget(k);
      if ValidID(n) then
        if not MapRay(SX, SY, WP[n].X, WP[n].Y - BodyH, RayFlags, T) then
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

function BE_GunCheckStartSound(ID: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := GunCheckStartSound(ID);
  except
    Result := 0;
  end;
end;

procedure BE_AmmoConfig(Enabled, MagMode, EmptyDrop, PickupFullSet, TrackGround, SawIdleTicks, SawAttackTicks,
  SawAttackDrain: LongInt; LootRadius: Single); cdecl;
begin
  try
    AmmoConfig(Enabled, MagMode, EmptyDrop, PickupFullSet, TrackGround, SawIdleTicks, SawAttackTicks, SawAttackDrain,
      LootRadius);
  except
  end;
end;

procedure BE_AmmoSetReserve(W, Rounds: LongInt); cdecl;
begin
  try
    AmmoSetReserve(W, Rounds);
  except
  end;
end;

{ [Ammo] ExtraMagazines (-1 = no limit but the pouch's) }
procedure BE_AmmoLimit(Extra: LongInt); cdecl;
begin
  try
    AmmoLimit(Extra);
  except
  end;
end;

procedure BE_AmmoRespawn(ID, Tick: LongInt); cdecl;
begin
  try
    AmmoRespawn(ID, Tick);
  except
  end;
end;

function BE_AmmoObserve(ID, Tick, W, A, SW, SA, Flags: LongInt; X, Y: Single; var Value: LongInt): LongInt; cdecl;
var
  V: LongInt;
begin
  Result := 0;
  try
    Result := AmmoObserve(ID, Tick, W, A, SW, SA, Flags, X, Y, V);
    Value := V;
  except
    Result := 0;
  end;
end;

procedure BE_AmmoForced(ID, Tick, W, Value: LongInt); cdecl;
begin
  try
    AmmoForced(ID, Tick, W, Value);
  except
  end;
end;

function BE_AmmoClip(ID, Tick, A: LongInt): LongInt; cdecl;
begin
  Result := A;
  try
    Result := AmmoClip(ID, Tick, A);
  except
    Result := A;
  end;
end;

function BE_AmmoShown(ID, Tick, W, A: LongInt): LongInt; cdecl;
begin
  Result := A;
  try
    Result := AmmoShown(ID, Tick, W, A);
  except
    Result := A;
  end;
end;

function BE_AmmoDeath(ID, Tick: LongInt; X, Y: Single): LongInt; cdecl;
begin
  Result := -1;
  try
    Result := AmmoDeath(ID, Tick, X, Y);
  except
    Result := -1;
  end;
end;

procedure BE_AmmoPickFrom(ID, Tick, Index: LongInt); cdecl;
begin
  try
    AmmoPickFrom(ID, Tick, Index);
  except
  end;
end;

function BE_AmmoGroundNext(W, From: LongInt): LongInt; cdecl;
begin
  Result := -1;
  try
    Result := AmmoGroundNext(W, From);
  except
    Result := -1;
  end;
end;

function BE_AmmoGroundSlot(Index: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := AmmoGroundSlot(Index);
  except
    Result := 0;
  end;
end;

function BE_AmmoGroundKind(Index: LongInt): LongInt; cdecl;
begin
  Result := -1;
  try
    Result := AmmoGroundKind(Index);
  except
    Result := -1;
  end;
end;

function BE_AmmoGroundAge(Index, Tick: LongInt): LongInt; cdecl;
begin
  Result := -1;
  try
    Result := AmmoGroundAge(Index, Tick);
  except
    Result := -1;
  end;
end;

{ ---------------- round 26: the HUD lines (be_hud) ---------------- }

procedure BE_HudCfgLine(L, Layer, Stacked, FX, FY: LongInt; FSc: Single); cdecl;
begin
  try
    HudCfgLine(L, Layer, Stacked, FX, FY, FSc);
  except
  end;
end;

procedure BE_HudCfgTimes(LifeTicks, DueTicks, AmmoOwn: LongInt); cdecl;
begin
  try
    HudCfgTimes(LifeTicks, DueTicks, AmmoOwn);
  except
  end;
end;

procedure BE_HudReset(ID, State: LongInt); cdecl;
begin
  try
    HudReset(ID, State);
  except
  end;
end;

procedure BE_HudWant(ID, L: LongInt; Text: PChar; Color: LongInt); cdecl;
begin
  try
    HudWant(ID, L, Str(Text, 4096), Color);
  except
  end;
end;

procedure BE_HudPlace(ID, L, X, Y: LongInt; Sc: Single); cdecl;
begin
  try
    HudPlace(ID, L, X, Y, Sc);
  except
  end;
end;

function BE_HudDraw(ID, Tick, Force: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := HudDraw(ID, Tick, Force);
  except
    Result := 0;
  end;
end;

function BE_HudHideAll(ID: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := HudHideAll(ID);
  except
    Result := 0;
  end;
end;

function BE_HudOp(k: LongInt; var Layer, Ticks, Color, X, Y: LongInt; var Sc: Single): PChar; cdecl;
var
  La, Ti, Co, XX, YY: LongInt;
  S: Single;
begin
  try
    HudOpBuf := HudOp(k, La, Ti, Co, XX, YY, S);
    Layer := La;
    Ticks := Ti;
    Color := Co;
    X := XX;
    Y := YY;
    Sc := S;
    Result := PChar(HudOpBuf);
  except
    Result := '';
  end;
end;

function BE_HudDue(ID, Tick: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    if HudDue(ID, Tick) then
      Result := 1;
  except
  end;
end;

procedure BE_HudClockReset(ID: LongInt); cdecl;
begin
  try
    HudClockReset(ID);
  except
  end;
end;

function BE_HudMoved(ID, L: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    if HudMoved(ID, L) then
      Result := 1;
  except
  end;
end;

function BE_HudState(ID, L: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := HudState(ID, L);
  except
  end;
end;

{ [AntiSpam] a chat line weighed (be_util ChatWeigh): the folded line; Caps and OneChar in % }
function BE_ChatWeigh(Text: PChar; var Caps, OneChar: LongInt): PChar; cdecl;
var
  C, O: LongInt;
begin
  try
    ChatBuf := ChatWeigh(Str(Text, 4096), C, O);
    Caps := C;
    OneChar := O;
    Result := PChar(ChatBuf);
  except
    Result := '';
  end;
end;

{ the whole file FileName becomes Text, written by the worker thread (FileName.tmp, then put in place) }
procedure BE_FileSave(FileName, Text: PChar); cdecl;
begin
  try
    if Writer <> nil then
    begin
      Writer.AddWhole(Str(FileName, 1024), Str(Text, 4194304));
      Worker.Wake;
    end;
  except
  end;
end;

function BE_AmmoGroundDist(Index: LongInt; X, Y: Single): LongInt; cdecl;
begin
  Result := 1000000;
  try
    Result := AmmoGroundDist(Index, X, Y);
  except
    Result := 1000000;
  end;
end;

function BE_AmmoGroundHasSlot(Slot: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := AmmoGroundHasSlot(Slot);
  except
    Result := 0;
  end;
end;

function BE_AmmoGroundAttach(ID, W, Slot, Corpse, Tick: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := AmmoGroundAttach(ID, W, Slot, Corpse, Tick);
  except
    Result := 0;
  end;
end;

procedure BE_AmmoGroundMove(Index: LongInt; X, Y: Single); cdecl;
begin
  try
    AmmoGroundMove(Index, X, Y);
  except
  end;
end;

procedure BE_AmmoGroundMissing(Index, Tick: LongInt); cdecl;
begin
  try
    AmmoGroundMissing(Index, Tick);
  except
  end;
end;

function BE_AmmoSelectMag(ID, W, Index: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := AmmoSelectMag(ID, W, Index);
  except
    Result := 0;
  end;
end;

function BE_AmmoReloadNow(ID, Tick, Clip: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := AmmoReloadNow(ID, Tick, Clip);
  except
    Result := 0;
  end;
end;

function BE_AmmoMagCount(ID, W: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := AmmoMagCount(ID, W);
  except
    Result := 0;
  end;
end;

function BE_AmmoMagRounds(ID, W, Index: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := AmmoMagRounds(ID, W, Index);
  except
    Result := 0;
  end;
end;

function BE_AmmoLoose(ID, W: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := AmmoLoose(ID, W);
  except
    Result := 0;
  end;
end;

function BE_AmmoUsesMags(W: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := AmmoUsesMags(W);
  except
    Result := 0;
  end;
end;

function BE_AmmoCanLoot(ID, W: LongInt; X, Y: Single): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := AmmoCanLoot(ID, W, X, Y);
  except
    Result := 0;
  end;
end;

function BE_AmmoLoot(ID, W: LongInt; X, Y: Single; Repack: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := AmmoLoot(ID, W, X, Y, Repack);
  except
    Result := 0;
  end;
end;

procedure BE_AmmoGroundClear; cdecl;
begin
  try
    AmmoGroundClear;
  except
  end;
end;

procedure BE_AmmoOptions(OneRound, KeepInterrupted, SortMags, RepackStartTicks, RepackStepTicks: LongInt); cdecl;
begin
  try
    AmmoOptions(OneRound, KeepInterrupted, SortMags, RepackStartTicks, RepackStepTicks);
  except
  end;
end;

procedure BE_AmmoText(Kind: LongInt; S: PChar); cdecl;
begin
  try
    AmmoSetText(Kind, StrPas(S));
  except
  end;
end;

{ the hooks' events for the ammunition, in the game thread as the server makes the bullet or the
  weapon object: a player's shot (a script's bullet is not one), a weapon he dropped }
procedure ShotToAmmo(const E: TShotEvent);
begin
  if E.Script then
    Exit;
  if (E.Owner >= 1) and (E.Owner <= 32) then
  begin
    AmmoShot(E.Owner, E.W, E.Tick);
    { the anticheat believes a magazine's drop only as far as real shots back it }
    AcShotSeen(E.Owner, E.W, E.Tick);
  end;
end;

{ every shot the hook sees: the ammunition, and [TeamKill]'s eyes (a copy for the script's next tick) }
procedure ShotHandler(const E: TShotEvent);
begin
  ShotToAmmo(E);
  { a soldier who is down or in shock fires nothing: his bullet (a shot, a grenade) is taken out as the
    server makes it - no damage, no push (his own game still draws it) }
  if not E.Script then
    if E.Style >= 0 then
      if BdMuted(E.Owner) then
        if BridgeBulletKill(E.Slot, E.Owner, E.Style) then
          Exit;
  BdShot(E);
  TkQueueShot(E);
  MnQueueShot(E);
end;

procedure ThingToAmmo(const E: TThingEvent);
begin
  if (E.Owner >= 1) and (E.Owner <= 32) then
    AmmoDropped(E.Owner, E.Style, E.Slot, E.Tick);
end;

procedure BE_AmmoSetBodyMode(Body: LongInt); cdecl;
begin
  try
    AmmoSetBodyMode(Body);
  except
  end;
end;

procedure BE_AmmoBodyMove(ID: LongInt; X, Y: Single); cdecl;
begin
  try
    AmmoBodyMove(ID, X, Y);
  except
  end;
end;

function BE_AmmoLeftBehind(ID, Tick: LongInt; X, Y: Single): LongInt; cdecl;
begin
  Result := -1;
  try
    Result := AmmoLeftBehind(ID, Tick, X, Y);
  except
    Result := -1;
  end;
end;

function BE_AmmoRepack(ID, Tick: LongInt): LongInt; cdecl;
begin
  Result := -2;
  try
    Result := AmmoRepack(ID, Tick);
  except
    Result := -2;
  end;
end;

function BE_AmmoRepacking(ID: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := AmmoRepacking(ID);
  except
    Result := 0;
  end;
end;

function BE_AmmoRepackEvent(ID: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := AmmoRepackEvent(ID);
  except
    Result := 0;
  end;
end;

function BE_AmmoLevel(ID, W, Clip: LongInt): LongInt; cdecl;
begin
  Result := 100;
  try
    Result := AmmoLevel(ID, W, Clip);
  except
    Result := 100;
  end;
end;

{ /be_prof: the script times its parts of a tick }
procedure BE_ProfBegin(Stage: LongInt); cdecl;
begin
  try
    ProfBegin(Stage);
  except
  end;
end;

procedure BE_ProfEnd(Stage: LongInt); cdecl;
begin
  try
    ProfEnd(Stage);
  except
  end;
end;

procedure BE_ProfReset; cdecl;
begin
  try
    ProfReset;
  except
  end;
end;

function BE_ProfText(Stage, Ticks: LongInt): PChar; cdecl;
begin
  try
    ProfBuf := ProfText(Stage, Ticks);
    Result := PChar(ProfBuf);
  except
    Result := '';
  end;
end;

{ the segment touches one of the map's colliders (the invisible circles bullets stop at; a frag grenade
  explodes on them): 1, else 0 }
function BE_MapColliderRay(X1, Y1, X2, Y2: Single): LongInt; cdecl;
begin
  Result := 0;
  try
    if MapColliderHit(X1, Y1, X2, Y2) then
      Result := 1;
  except
    Result := 0;
  end;
end;

{ where and when bullet B counts as fired (the kill's distance and air time): 1 = written, 0 = no bridge
  or the field not found, -1 = not the bullet just made }
function BE_BridgeSetOrigin(B, Style: LongInt; MadeX, MadeY, FromX, FromY: Single; Ago: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := BridgeSetOrigin(B, Style, MadeX, MadeY, FromX, FromY, Ago);
  except
    Result := 0;
  end;
end;

{ [Ammo]: rounds taken out of the weapon in the hands come back into the pool at its next reload }
procedure BE_AmmoKeep(ID, W, Rounds: LongInt); cdecl;
begin
  try
    AmmoKeep(ID, W, Rounds);
  except
  end;
end;

{ ---------------- the soldiers' skeletons (be_sprite), the shots of the kills (be_bridge) ---------------- }

{ the eyes of the soldier in slot ID as the server has them - his head moves with crouching, lying,
  rolling and the aim. Obj = the script's player object (ScriptCore passes the object itself), X, Y =
  his position (Player.X, Player.Y); 1 = EX, EY set }
function BE_SpriteEyes(ID: LongInt; Obj: Pointer; X, Y: Single; var EX, EY: Single): LongInt; cdecl;
var
  a, b: Single;
begin
  Result := 0;
  try
    { a point far from the soldier would be a wrong record: then he counts as unknown }
    if SpriteBind(ID, Obj, X, Y) = 1 then
      if SpriteEyes(ID, a, b) and (Abs(a - X) < 80) and (Abs(b - Y) < 80) then
      begin
        EX := a;
        EY := b;
        Result := 1;
      end;
  except
    Result := 0;
  end;
end;

{ a point of his skeleton, 1 .. 25 (9 the neck, 12 a tenth of a pixel from it towards the top of the
  head, 7 the chest, 5 and 6 the hips, 1 and 2 the feet ...) }
function BE_SpritePoint(ID: LongInt; Obj: Pointer; X, Y: Single; K: LongInt; var PX, PY: Single): LongInt; cdecl;
var
  a, b: Single;
begin
  Result := 0;
  try
    if SpriteBind(ID, Obj, X, Y) = 1 then
      if SpritePoint(ID, K, a, b) and (Abs(a - X) < 80) and (Abs(b - Y) < 80) then
      begin
        PX := a;
        PY := b;
        Result := 1;
      end;
  except
    Result := 0;
  end;
end;

{ the soldier in slot ID is looked up in the server's memory (Obj = the script's player object, X, Y = his
  position; 1 = known). Once two slots are known the library works out every other one, so the radar's
  realistic rays (WSkeleton) find every soldier's skeleton }
function BE_SpriteBind(ID: LongInt; Obj: Pointer; X, Y: Single): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := SpriteBind(ID, Obj, X, Y);
  except
    Result := 0;
  end;
end;

{ ---------------- [TeamKill]: the shots' lines (be_tk) ---------------- }

procedure BE_TkSet(Key: LongInt; Value: Single); cdecl;
begin
  try
    TkSet(Key, Value);
  except
  end;
end;

procedure BE_TkPlayer(ID, Team, Alive: LongInt); cdecl;
begin
  try
    TkPlayer(ID, Team, Alive);
    MnPlayer(ID, Team, Alive);
    BdPlayer(ID, Team, Alive);
  except
  end;
end;

{ the script's tick: the shots since the last one are looked at; the events waiting }
function BE_TkTick: LongInt; cdecl;
begin
  Result := 0;
  try
    Result := TkTick;
  except
    Result := 0;
  end;
end;

function BE_TkNext(var Kind, S, T, N, Reason: LongInt): LongInt; cdecl;
var
  a, b, c, d, e: LongInt;
begin
  Result := 0;
  try
    if TkNext(a, b, c, d, e) then
    begin
      Kind := a;
      S := b;
      T := c;
      N := d;
      Reason := e;
      Result := 1;
    end;
  except
    Result := 0;
  end;
end;

{ how meant a hit of S on his team mate V looks (0-100) and why }
function BE_TkHit(S, V, Style, Tick: LongInt; var Reason: LongInt): LongInt; cdecl;
var
  r: LongInt;
begin
  Result := 50;
  try
    r := 0;
    Result := TkHit(S, V, Style, Tick, r);
    Reason := r;
  except
    Result := 50;
  end;
end;

function BE_TkShots(S, T, Tick: LongInt; var AtT, Cross, AtEnemy, All: LongInt): LongInt; cdecl;
var
  a, b, c, d: LongInt;
begin
  Result := 0;
  try
    if TkShots(S, T, Tick, a, b, c, d) then
    begin
      AtT := a;
      Cross := b;
      AtEnemy := c;
      All := d;
      Result := 1;
    end;
  except
    Result := 0;
  end;
end;

procedure BE_TkForget(ID: LongInt); cdecl;
begin
  try
    TkForget(ID);
  except
  end;
end;

function BE_TkInfo: PChar; cdecl;
begin
  try
    TkBuf := TkInfo;
    Result := PChar(TkBuf);
  except
    Result := '';
  end;
end;

{ ---------------- [Mines]: the landmines and claymores (be_mine) ---------------- }

procedure BE_MineSet(Key: LongInt; Value: Single); cdecl;
begin
  try
    MnSet(Key, Value);
  except
  end;
end;

procedure BE_MineSetInt(Key, Value: LongInt); cdecl;
begin
  try
    MnSetInt(Key, Value);
  except
  end;
end;

procedure BE_MineText(Key: LongInt; Text: PChar); cdecl;
begin
  try
    MnText(Key, Str(Text, 200));
  except
  end;
end;

{ a soldier the library does not know: his feet and whether he crouches or lies }
procedure BE_MinePos(ID: LongInt; X, Y: Single; Low: LongInt); cdecl;
begin
  try
    MnPos(ID, X, Y, Low);
  except
  end;
end;

{ his crouch or prone key (the script reads it for the soldiers near a mine) }
procedure BE_MineLow(ID, Low: LongInt); cdecl;
begin
  try
    MnLow(ID, Low);
  except
  end;
end;

{ the soldiers near a mine (bit ID - 1): the script tells BE_MineLow about them }
function BE_MineNear: LongInt; cdecl;
begin
  Result := 0;
  try
    Result := LongInt(MnNear);
  except
    Result := 0;
  end;
end;

{ the slots (bit ID - 1) to tell about with BE_MinePos }
function BE_MineWants: LongInt; cdecl;
begin
  Result := 0;
  try
    Result := LongInt(MnWants);
  except
    Result := 0;
  end;
end;

function BE_MinePlant(Kind, Owner, Team: LongInt; X, Y, AimX, AimY: Single; Tick: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := MnPlant(Kind, Owner, Team, X, Y, AimX, AimY, Tick);
  except
    Result := 0;
  end;
end;

procedure BE_MineRemove(Id: LongInt); cdecl;
begin
  try
    MnRemove(Id);
  except
  end;
end;

function BE_MineRemoveOwner(Owner: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := MnRemoveOwner(Owner);
  except
    Result := 0;
  end;
end;

procedure BE_MineClear; cdecl;
begin
  try
    MnClear;
  except
  end;
end;

function BE_MineGet(Id: LongInt; var Kind, Owner, Team: LongInt; var X, Y, FX, FY: Single): LongInt; cdecl;
var
  a, b, c: LongInt;
  d, e, f, g: Single;
begin
  Result := 0;
  try
    if MnGet(Id, a, b, c, d, e, f, g) then
    begin
      Kind := a;
      Owner := b;
      Team := c;
      X := d;
      Y := e;
      FX := f;
      FY := g;
      Result := 1;
    end;
  except
    Result := 0;
  end;
end;

{ how far under mine Id bullets meet the ground (-1 = not within 12 px) }
function BE_MineGround(Id: LongInt): Single; cdecl;
begin
  Result := -1;
  try
    Result := MnGround(Id);
  except
    Result := -1;
  end;
end;

function BE_MineCount(Owner, Kind: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := MnCount(Owner, Kind);
  except
    Result := 0;
  end;
end;

{ a class's mine detector: V finds the enemy mines within R px of X, Y; how many now }
function BE_MineDetect(V: LongInt; X, Y, R: Single): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := MnDetect(V, X, Y, R);
  except
    Result := 0;
  end;
end;

function BE_MineNearest(X, Y: Single; var D: Single): LongInt; cdecl;
var
  e: Single;
begin
  Result := 0;
  try
    Result := MnNearest(X, Y, e);
    D := e;
  except
    Result := 0;
  end;
end;

procedure BE_MineChain(Id: LongInt; R: Single; AtTick: LongInt); cdecl;
begin
  try
    MnChain(Id, R, AtTick);
  except
  end;
end;

{ the script's tick: the mines looked after; the events waiting }
function BE_MineTick(Tick: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := MnTick(Tick);
  except
    Result := 0;
  end;
end;

function BE_MineNext(var Kind, Id, P, Q: LongInt): LongInt; cdecl;
var
  a, b, c, d: LongInt;
begin
  Result := 0;
  try
    if MnNext(a, b, c, d) then
    begin
      Kind := a;
      Id := b;
      P := c;
      Q := d;
      Result := 1;
    end;
  except
    Result := 0;
  end;
end;

{ the marks for a viewer standing at X, Y: the ops to send (BE_Op); More = 1: some are left }
function BE_MineDraw(Viewer, Tick, Budget: LongInt; X, Y: Single; var More: LongInt): LongInt; cdecl;
var
  m: LongInt;
begin
  Result := 0;
  try
    m := 0;
    Result := MnDraw(Viewer, Tick, Budget, X, Y, m);
    More := m;
  except
    Result := 0;
  end;
end;

function BE_MineHide(Viewer, Budget: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := MnHide(Viewer, Budget);
  except
    Result := 0;
  end;
end;

procedure BE_MineForget(Viewer: LongInt); cdecl;
begin
  try
    MnForget(Viewer);
  except
  end;
end;

function BE_MineVersion: LongInt; cdecl;
begin
  Result := 0;
  try
    Result := MnVersion;
  except
    Result := 0;
  end;
end;

function BE_MineInfo: PChar; cdecl;
begin
  try
    MnBuf := MnInfo;
    Result := PChar(MnBuf);
  except
    Result := '';
  end;
end;

{ ---------------- the map commands: the maps of a folder, names by a part (be_names) ---------------- }

function BE_NamesFolder(Folder, Ext: PChar): PChar; cdecl;
begin
  try
    NamesBuf := NamesFolder(AnsiString(Folder), AnsiString(Ext));
  except
    NamesBuf := '';
  end;
  Result := PChar(NamesBuf);
end;

function BE_NamesRank(List, Part: PChar): LongInt; cdecl;
begin
  try
    Result := NamesRank(AnsiString(List), AnsiString(Part));
  except
    Result := 0;
  end;
end;

function BE_NamesRankOf(Index: LongInt): LongInt; cdecl;
begin
  try
    Result := NamesRankOf(Index);
  except
    Result := -1;
  end;
end;

function BE_NamesGet(Index: LongInt): PChar; cdecl;
begin
  try
    NamesBuf := NamesGet(Index);
  except
    NamesBuf := '';
  end;
  Result := PChar(NamesBuf);
end;

{ ---------------- [Shop], [Supply] (be_shop, be_ammo) ---------------- }

function BE_ShopApPredict(Style: LongInt; X, Y, VX, VY: Single; MaxTicks, Team: LongInt; var HX, HY: Single): LongInt;
  cdecl;
begin
  Result := -1;
  try
    Result := ShopApPredict(Style, X, Y, VX, VY, MaxTicks, Team, HX, HY);
  except
    Result := -1;
  end;
end;

function BE_ShopGround(X, Y, Down: Single; var GY: Single): LongInt; cdecl;
begin
  Result := 0;
  try
    if ShopGround(X, Y, Down, GY) then
      Result := 1;
  except
    Result := 0;
  end;
end;

function BE_AmmoAddMags(ID, W, N: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := AmmoAddMags(ID, W, N);
  except
    Result := 0;
  end;
end;

{ a class's spare magazines over the fresh set (and over ExtraMagazines) }
procedure BE_AmmoPlayerExtra(ID, N: LongInt); cdecl;
begin
  try
    AmmoPlayerExtra(ID, N);
  except
  end;
end;

function BE_AmmoTopUp(ID, W: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := AmmoTopUp(ID, W);
  except
    Result := 0;
  end;
end;

{ ---------------- [Bleeding], [Downed]: the bodies (be_body) ---------------- }

procedure BE_BodySet(Key: LongInt; Value: Single); cdecl;
begin
  try
    BdSet(Key, Value);
  except
  end;
end;

{ a new life: full blood, no wounds, a full bandage, the kits }
procedure BE_BodySpawn(ID, Tick: LongInt); cdecl;
begin
  try
    BdSpawn(ID, Tick);
  except
  end;
end;

procedure BE_BodyForget(ID: LongInt); cdecl;
begin
  try
    BdForget(ID);
  except
  end;
end;

{ his bandage and kits: set (Add = 0) or given (Add = 1) }
procedure BE_BodySupplies(ID: LongInt; Band: Single; Kits, Add: LongInt); cdecl;
begin
  try
    BdSupplies(ID, Band, Kits, Add);
  except
  end;
end;

{ where a soldier the library does not know stands and whether he crouches or lies (BE_BodyWants) }
procedure BE_BodyPos(ID: LongInt; X, Y: Single; Low: LongInt); cdecl;
begin
  try
    BdPos(ID, X, Y, Low);
  except
  end;
end;

function BE_BodyWants: LongInt; cdecl;
begin
  Result := 0;
  try
    Result := LongInt(BdWants);
  except
    Result := 0;
  end;
end;

{ his crouch or prone key (the soldiers of BE_BodyNear, whose stance the library cannot read) }
procedure BE_BodyLow(ID, Low: LongInt); cdecl;
begin
  try
    BdLow(ID, Low);
  except
  end;
end;

function BE_BodyNear: LongInt; cdecl;
begin
  Result := 0;
  try
    Result := LongInt(BdNear);
  except
    Result := 0;
  end;
end;

{ which body part a bullet hit (12 the head, 10 the torso, 3 the legs, 0 not known) }
function BE_BodyHitPart(V, Style: LongInt; X, Y, VX, VY: Single): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := BdHitPart(V, Style, X, Y, VX, VY);
  except
    Result := 0;
  end;
end;

{ a hit: the kind of the wound it opened (0 none) }
function BE_BodyHit(V, By, W, Style: LongInt; Damage, MaxHP: Single; Part, Tick: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := BdHit(V, By, W, Style, Damage, MaxHP, Part, Tick);
  except
    Result := 0;
  end;
end;

{ he asks for work (1 bandage, 2 kit, 0 no more): 1 it can start, 0 nothing to do, -1 too little bandage,
  -2 no kit }
function BE_BodyWant(ID, What: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := BdWant(ID, What);
  except
    Result := 0;
  end;
end;

procedure BE_BodyHeal(ID, How: LongInt; Blood: Single); cdecl;
begin
  try
    BdHeal(ID, How, Blood);
  except
  end;
end;

procedure BE_BodyDown(ID, By, W, Tick: LongInt); cdecl;
begin
  try
    BdDown(ID, By, W, Tick);
  except
  end;
end;

procedure BE_BodyGiveUp(ID: LongInt); cdecl;
begin
  try
    BdGiveUp(ID);
  except
  end;
end;

{ the script's tick: the bodies looked after; the events waiting }
function BE_BodyTick(Tick: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := BdTick(Tick);
  except
    Result := 0;
  end;
end;

function BE_BodyNext(var Kind, ID, P, Q: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    if BdNext(Kind, ID, P, Q) then
      Result := 1;
  except
    Result := 0;
  end;
end;

{ his state for the texts (be_body BdGet) }
function BE_BodyGet(ID: LongInt; var Blood: Single; var Worst, Wounds: LongInt; var Band: Single; var Kits, Work,
  Pct, State: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    BdGet(ID, Blood, Worst, Wounds, Band, Kits, Work, Pct, State);
    Result := 1;
  except
    Result := 0;
  end;
end;

function BE_BodyWorkOn(ID: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := BdWorkOn(ID);
  except
    Result := 0;
  end;
end;

function BE_BodyHelper(ID: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := BdHelper(ID);
  except
    Result := 0;
  end;
end;

{ the one who opened his worst wound (or put him down) and his weapon: a bleeding out's kill }
function BE_BodyCulprit(ID: LongInt; var W: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := BdCulprit(ID, W);
  except
    Result := 0;
  end;
end;

function BE_BodyDownLeft(ID, Tick: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := BdDownLeft(ID, Tick);
  except
    Result := 0;
  end;
end;

{ his open wounds by place (bytes: head, torso, legs, none - bits 0-3 the count, 4-5 the worst kind, 6 shrapnel), the
  blood he loses a second (hundredths of a percent) and the seconds until he bleeds out (-1 = not bleeding) }
function BE_BodyPlaces(ID: LongInt; var Rate, Left: LongInt): LongInt; cdecl;
begin
  Result := 0;
  Rate := 0;
  Left := -1;
  try
    Result := BdPlaces(ID, Rate, Left);
  except
    Result := 0;
  end;
end;

{ ---------------- round 26: the soldiers' weapons and keys from their records ---------------- }

function BE_SpriteCalibrate(ID, W, A, SW, SA, Gren, AimX, AimY: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := SpriteCalibrate(ID, W, A, SW, SA, Gren, AimX, AimY);
  except
    Result := 0;
  end;
end;

function BE_SpriteCheck(ID, Alive, W, A, SW, SA, Gren, AimX, AimY, Keys: LongInt): LongInt; cdecl;
begin
  Result := -1;
  try
    Result := SpriteCheck(ID, Alive, W, A, SW, SA, Gren, AimX, AimY, Keys);
  except
    Result := -1;
  end;
end;

function BE_SpriteMemReady(): LongInt; cdecl;
begin
  Result := 0;
  try
    if SpriteMemReady then
      Result := 1;
  except
  end;
end;

function BE_SpriteMemInfo(): PChar; cdecl;
begin
  try
    MemInfoBuf := SpriteMemInfo;
    Result := PChar(MemInfoBuf);
  except
    Result := '';
  end;
end;

procedure BE_AmmoLastW(ID, W: LongInt); cdecl;
begin
  try
    AmmoLastW(ID, W);
  except
  end;
end;

function BE_AmmoPass(Tick, Mask, Human, Free, Repack: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := AmmoPass(Tick, LongWord(Mask), LongWord(Human), LongWord(Free), LongWord(Repack));
  except
    Result := 0;
  end;
end;

procedure BE_AmmoPassOp(k: LongInt; var ID, Act, Value: LongInt); cdecl;
var
  I0, A0, V0: LongInt;
begin
  try
    AmmoPassOp(k, I0, A0, V0);
    ID := I0;
    Act := A0;
    Value := V0;
  except
    ID := 0;
    Act := 0;
    Value := 0;
  end;
end;

{ round 26: a text of the blood line's wound list (be_body BdHudText) }
procedure BE_BodyHudText(Kind: LongInt; Text: PChar); cdecl;
begin
  try
    BdHudText(Kind, Str(Text, 1024));
  except
  end;
end;

{ round 26: his open wounds as the blood line's list ('' = none) }
function BE_BodyWoundList(ID: LongInt): PChar; cdecl;
begin
  try
    WoundBuf := BdWoundList(ID);
    Result := PChar(WoundBuf);
  except
    Result := '';
  end;
end;

{ a transfusion (a blood bag): Blood percent more within Ticks }
procedure BE_BodyTransfuse(ID: LongInt; Blood: Single; Ticks: LongInt); cdecl;
begin
  try
    BdTransfuse(ID, Blood, Ticks);
  except
  end;
end;

{ his class's perks: bandaging BandF times faster; getting the downed up ReviveF times faster, from ReviveR px }
procedure BE_BodyPerk(ID: LongInt; BandF, ReviveF, ReviveR: Single); cdecl;
begin
  try
    BdPerk(ID, BandF, ReviveF, ReviveR);
  except
  end;
end;

{ he falls freely without a key held this tick ([Bleeding] AirBandage: as low and still for bandaging) }
procedure BE_BodyAir(ID, Free: LongInt); cdecl;
begin
  try
    BdAir(ID, Free);
  except
  end;
end;

{ a medic: with no wound of his own to bandage he bandages the wounded mates within R px (0 = not a medic) }
procedure BE_BodyMedic(ID: LongInt; R: Single); cdecl;
begin
  try
    BdMedic(ID, R);
  except
  end;
end;

{ the parts his vest covers for the next hit (1 the head, 2 the torso, 4 the legs): no wound there }
procedure BE_BodyCover(ID, Mask: LongInt); cdecl;
begin
  try
    BdCover(ID, Mask);
  except
  end;
end;

{ the game was paused Delta ticks: the body's and the mines' clocks move on by them }
procedure BE_BodyShift(Delta: LongInt); cdecl;
begin
  try
    BdShift(Delta);
  except
  end;
end;

procedure BE_MineShift(Delta: LongInt); cdecl;
begin
  try
    MnShift(Delta);
  except
  end;
end;

function BE_BodyInfo: PChar; cdecl;
begin
  try
    BdBuf := BdInfo;
    Result := PChar(BdBuf);
  except
    Result := '';
  end;
end;

{ ---------------- [Spotting]: the radar ---------------- }

{ B on the radars of team T (0 = everybody without teams) until tick U }
procedure BE_SpotSet(B, T, U: LongInt); cdecl;
begin
  try
    SpotSet(B, T, U);
  except
  end;
end;

procedure BE_SpotClear; cdecl;
begin
  try
    SpotClear;
  except
  end;
end;

{ ---------------- [Ammo]: the survival carry-over, the pause ---------------- }

procedure BE_AmmoCarrySave(ID, Tick: LongInt); cdecl;
begin
  try
    AmmoCarrySave(ID, Tick);
  except
  end;
end;

procedure BE_AmmoCarryConfirm(ID: LongInt); cdecl;
begin
  try
    AmmoCarryConfirm(ID);
  except
  end;
end;

procedure BE_AmmoCarryDrop(ID: LongInt); cdecl;
begin
  try
    AmmoCarryDrop(ID);
  except
  end;
end;

{ the rounds he has for weapon W (-1 = not used this life) }
function BE_AmmoLeftOf(ID, W, Tick: LongInt): LongInt; cdecl;
begin
  Result := -1;
  try
    Result := AmmoLeftOf(ID, W, Tick);
  except
    Result := -1;
  end;
end;

{ a fresh set of spare magazines for weapon W (a reward, a supply) }
procedure BE_AmmoRefill(ID, W: LongInt); cdecl;
begin
  try
    AmmoRefill(ID, W);
  except
  end;
end;

procedure BE_AmmoPause(ID, On, Tick: LongInt); cdecl;
begin
  try
    AmmoPause(ID, On, Tick);
  except
  end;
end;

{ where and at which tick bullet B counts as fired (Initial, StartUpTime; learnt from the first bullets
  the server makes): the server's "You killed" distance is |bullet - (X, Y)| / 14, the air time
  (Game.TickCount - Tick) / 60; 1 = known }
function BE_BulletOrigin(B: LongInt; var X, Y: Single; var Tick: LongInt): LongInt; cdecl;
var
  OX, OY: Single;
  OT: LongInt;
begin
  Result := 0;
  try
    if BridgeBulletOrigin(B, OX, OY, OT) then
    begin
      X := OX;
      Y := OY;
      Tick := OT;
      Result := 1;
    end;
  except
    Result := 0;
  end;
end;

{ ---------------- [ExtraRocket] the rockets' flight (be_rocket) ---------------- }

procedure BE_RkSet(Key: LongInt; Value: Single); cdecl;
begin
  try
    RkSet(Key, Value);
  except
  end;
end;

procedure BE_RkReset; cdecl;
begin
  try
    RkReset;
  except
  end;
end;

function BE_RkLaunch(Owner, Target: LongInt; X, Y, TX, TY, TVX, TVY: Single): LongInt; cdecl;
begin
  Result := -1;
  try
    Result := RkLaunch(Owner, Target, X, Y, TX, TY, TVX, TVY);
  except
    Result := -1;
  end;
end;

procedure BE_RkAim(k, Alive: LongInt; TX, TY, TVX, TVY: Single); cdecl;
begin
  try
    RkAim(k, Alive, TX, TY, TVX, TVY);
  except
  end;
end;

procedure BE_RkStep(Tick: LongInt); cdecl;
begin
  try
    RkStep(Tick);
  except
  end;
end;

function BE_RkNext(var k, Kind, Owner, Target: LongInt; var X, Y, VX, VY: Single): LongInt; cdecl;
var
  a, b, c, d: LongInt;
  e, f, g, h: Single;
begin
  Result := 0;
  try
    if RkNext(a, b, c, d, e, f, g, h) then
    begin
      k := a;
      Kind := b;
      Owner := c;
      Target := d;
      X := e;
      Y := f;
      VX := g;
      VY := h;
      Result := 1;
    end;
  except
    Result := 0;
  end;
end;

function BE_RkState(k: LongInt; var Owner, Target, Phase: LongInt; var X, Y, PX, PY: Single): LongInt; cdecl;
var
  a, b, c: LongInt;
  e, f, g, h: Single;
begin
  Result := 0;
  try
    if RkState(k, a, b, c, e, f, g, h) then
    begin
      Owner := a;
      Target := b;
      Phase := c;
      X := e;
      Y := f;
      PX := g;
      PY := h;
      Result := 1;
    end;
  except
    Result := 0;
  end;
end;

procedure BE_RkDrop(k: LongInt); cdecl;
begin
  try
    RkDrop(k);
  except
  end;
end;

function BE_RkInfo: PChar; cdecl;
begin
  try
    RkBuf := RkInfo;
    Result := PChar(RkBuf);
  except
    Result := '';
  end;
end;

{ where the ink of Text is, from the corner of a text at Scale (Big = 1: a BigText, else a WorldText):
  a text put at X - DX, Y - DY has its ink centred on X, Y }
procedure BE_TextInk(Text: PChar; Scale: Single; Big: LongInt; var DX, DY: Single); cdecl;
var
  CX, CY, Em: Single;
begin
  try
    InkCenter(Str(Text, 400), CX, CY);
    if Big = 1 then
      Em := Scale * BIG_EM
    else
      Em := Scale * WORLD_EM;
    DX := CX * Em;
    DY := CY * Em;
  except
    DX := 0;
    DY := 0;
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

function BE_TrajTrack(ID, Tick, Budget, Start, Team: LongInt; BX, BY, BVX, BVY: Single): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := TrajTrack(ID, Tick, Budget, Start, Team, BX, BY, BVX, BVY);
  except
    OpCount := 0;
    Result := 0;
  end;
end;

function BE_AimCircle(ID, Tick, Budget, Count, First, Color: LongInt; CX, CY, R, Scale: Single): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := AimCircle(ID, Tick, Budget, Count, First, Color, CX, CY, R, Scale);
  except
    OpCount := 0;
    Result := 0;
  end;
end;

function BE_AimCircleHide(ID, Budget: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    Result := AimCircleHide(ID, Budget);
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

function BE_BridgeReady: LongInt; cdecl;
begin
  try
    if BridgeReady then
      Result := 1
    else
      Result := 0;
  except
    Result := 0;
  end;
end;

function BE_BridgeSetWeapon(B, Style, W: LongInt; HitM: Single): LongInt; cdecl;
begin
  try
    Result := BridgeSetWeapon(B, Style, W, HitM);
  except
    Result := 0;
  end;
end;

function BE_BridgeInfo: PChar; cdecl;
begin
  try
    BridgeBuf := BridgeInfo + '; ' + SpriteInfo + '; ' + SpriteMemInfo;
    Result := PChar(BridgeBuf);
  except
    Result := 'error';
  end;
end;

{ the hooks in the server's CreateBullet and CreateThing: 3 = both, 1 = CreateBullet only, 0 = none
  (see be_hook). The bullet table is looked up first (a bullet's style is read in the hook). }
function BE_HookInit: LongInt; cdecl;
begin
  Result := 0;
  try
    BridgeReady;
    OnShot := @ShotHandler;
    OnThing := @ThingToAmmo;
    Result := HookInit;
  except
    Result := 0;
  end;
end;

{ at the start of the script's tick }
procedure BE_HookTick(Tick: LongInt); cdecl;
begin
  try
    HookTick(Tick);
  except
  end;
end;

procedure BE_HookWatch(W, On: LongInt); cdecl;
begin
  try
    HookWatch(W, On <> 0);
  except
  end;
end;

function BE_HookInfo: PChar; cdecl;
begin
  try
    HookBuf := HookInfo;
    Result := PChar(HookBuf);
  except
    Result := 'error';
  end;
end;

{ the next bullet of a watched weapon made since the last call (1), or none (0): the script's tick it
  belongs to, its slot in the bullet table, owner, weapon number, style, where and how fast }
function BE_ShotNext(var Tick, Slot, Owner, W, Style: LongInt; var X, Y, VX, VY: Single): LongInt; cdecl;
var
  E: TShotEvent;
begin
  Result := 0;
  try
    if HookNextShot(E) = 1 then
    begin
      Tick := E.Tick;
      Slot := E.Slot;
      Owner := E.Owner;
      W := E.W;
      Style := E.Style;
      X := E.X;
      Y := E.Y;
      VX := E.VX;
      VY := E.VY;
      Result := 1;
    end;
  except
    Result := 0;
  end;
end;

{ a bullet in the server's table: 1 = known (Active 1 = flying, the ticks it has left), 0 = not }
function BE_BulletInfo(B: LongInt; var Active, Owner, W, Style, TimeOut: LongInt): LongInt; cdecl;
var
  a, o, ww, st, t: LongInt;
begin
  Result := 0;
  try
    if BridgeBulletInfo(B, a, o, ww, st, t) then
    begin
      Active := a;
      Owner := o;
      W := ww;
      Style := st;
      TimeOut := t;
      Result := 1;
    end;
  except
    Result := 0;
  end;
end;

{ takes a flying bullet out of the game (a grenade then never explodes), when it still has this owner
  and style: 1 = done }
function BE_BulletKill(B, Owner, Style: LongInt): LongInt; cdecl;
begin
  Result := 0;
  try
    if BridgeBulletKill(B, Owner, Style) then
      Result := 1;
  except
    Result := 0;
  end;
end;

exports
  BE_Init,
  BE_Shutdown,
  BE_Status,
  BE_Pref_Count,
  BE_Log,
  BE_World,
  BE_SnapBegin,
  BE_SnapPos,
  BE_SnapAim,
  BE_SnapVel,
  BE_SnapExtra,
  BE_SnapEnd,
  BE_SnapFlag,
  BE_Human,
  BE_AcSet,
  BE_AcReset,
  BE_AcKeys,
  BE_AcMoved,
  BE_AcHurt,
  BE_AcHit,
  BE_AcWatched,
  BE_AcNext,
  BE_AcScore,
  BE_AcText,
  BE_AcFindings,
  BE_AcAmmo,
  BE_AcAmmoReset,
  BE_AcSave,
  BE_AcForget,
  BE_AcForgetAll,
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
  BE_RadarReset,
  BE_Op,
  BE_TextWidth,
  BE_Replace,
  BE_Fill,
  BE_FloatStr,
  BE_MixColor,
  BE_HudStyle,
  BE_HudBar,
  BE_HudRegen,
  BE_HudText,
  BE_LogStamp,
  BE_Pref_Load,
  BE_Pref_Save,
  BE_Sees,
  BE_WeaponName,
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
  BE_ShotPush,
  BE_GunTick,
  BE_GunFired,
  BE_GunReset,
  BE_GunTargets,
  BE_GunTarget,
  BE_GunPick,
  BE_TrajInt,
  BE_TrajFloat,
  BE_TrajPass,
  BE_TrajStep,
  BE_TrajTrack,
  BE_AimCircle,
  BE_AimCircleHide,
  BE_TrajHide,
  BE_TrajReset,
  BE_Fx,
  BE_FxGet,
  BE_BridgeReady,
  BE_BridgeSetWeapon,
  BE_BridgeInfo,
  BE_HookInit,
  BE_GunCheckStartSound,
  BE_AmmoConfig,
  BE_AmmoSetReserve,
  BE_AmmoLimit,
  BE_AmmoRespawn,
  BE_AmmoObserve,
  BE_AmmoForced,
  BE_AmmoClip,
  BE_AmmoShown,
  BE_AmmoDeath,
  BE_AmmoPickFrom,
  BE_AmmoGroundNext,
  BE_AmmoGroundSlot,
  BE_AmmoGroundKind,
  BE_AmmoGroundDist,
  BE_AmmoGroundHasSlot,
  BE_AmmoGroundAttach,
  BE_AmmoGroundMove,
  BE_AmmoGroundMissing,
  BE_AmmoSelectMag,
  BE_AmmoReloadNow,
  BE_AmmoMagCount,
  BE_AmmoMagRounds,
  BE_AmmoLoose,
  BE_AmmoUsesMags,
  BE_AmmoCanLoot,
  BE_AmmoLoot,
  BE_AmmoGroundClear,
  BE_AmmoFormatHud,
  BE_AmmoOptions,
  BE_AmmoText,
  BE_AmmoSetBodyMode,
  BE_AmmoBodyMove,
  BE_AmmoLeftBehind,
  BE_HookTick,
  BE_HookWatch,
  BE_HookInfo,
  BE_ShotNext,
  BE_BulletInfo,
  BE_BulletKill,
  BE_AmmoRepack,
  BE_AmmoRepacking,
  BE_AmmoRepackEvent,
  BE_AmmoLevel,
  BE_ProfBegin,
  BE_ProfEnd,
  BE_ProfReset,
  BE_ProfText,
  BE_RkSet,
  BE_RkReset,
  BE_RkLaunch,
  BE_RkAim,
  BE_RkStep,
  BE_RkNext,
  BE_RkState,
  BE_RkDrop,
  BE_RkInfo,
  BE_TextInk,
  BE_MapColliderRay,
  BE_BridgeSetOrigin,
  BE_AmmoKeep,
  BE_SpriteEyes,
  BE_SpritePoint,
  BE_BulletOrigin,
  BE_SpriteBind,
  BE_TkSet,
  BE_TkPlayer,
  BE_TkTick,
  BE_TkNext,
  BE_TkHit,
  BE_TkShots,
  BE_TkForget,
  BE_TkInfo,
  BE_MineSet,
  BE_MineSetInt,
  BE_MineText,
  BE_MinePos,
  BE_MineLow,
  BE_MineNear,
  BE_MineWants,
  BE_MinePlant,
  BE_MineRemove,
  BE_MineRemoveOwner,
  BE_MineClear,
  BE_MineGet,
  BE_MineGround,
  BE_MineCount,
  BE_MineNearest,
  BE_MineChain,
  BE_MineTick,
  BE_MineNext,
  BE_MineDraw,
  BE_MineHide,
  BE_MineForget,
  BE_MineVersion,
  BE_MineInfo,
  BE_BodySet,
  BE_BodySpawn,
  BE_BodyForget,
  BE_BodyPos,
  BE_BodyWants,
  BE_BodyLow,
  BE_BodyNear,
  BE_BodyHitPart,
  BE_BodyHit,
  BE_BodyWant,
  BE_BodyHeal,
  BE_BodyDown,
  BE_BodyGiveUp,
  BE_BodyTick,
  BE_BodyNext,
  BE_BodyGet,
  BE_BodyWorkOn,
  BE_BodyHelper,
  BE_BodyCulprit,
  BE_BodyDownLeft,
  BE_BodyInfo,
  BE_BodyPlaces,
  BE_BodyTransfuse,
  BE_BodyPerk,
  BE_BodyAir,
  BE_BodyMedic,
  BE_BodyCover,
  BE_BodyShift,
  BE_MineShift,
  BE_SpotSet,
  BE_SpotClear,
  BE_AmmoCarrySave,
  BE_AmmoCarryConfirm,
  BE_AmmoCarryDrop,
  BE_AmmoLeftOf,
  BE_AmmoRefill,
  BE_BodySupplies,
  BE_AmmoPause,
  BE_NamesFolder,
  BE_NamesRank,
  BE_NamesRankOf,
  BE_NamesGet,
  BE_ShopApPredict,
  BE_ShopGround,
  BE_AmmoAddMags,
  BE_AmmoPlayerExtra,
  BE_LagSet,
  BE_LagWarps,
  BE_LagReset,
  BE_MineDetect,
  BE_AmmoTopUp,
  BE_AmmoGroundAge,
  BE_FileSave,
  BE_ChatWeigh,
  BE_HudCfgLine,
  BE_HudCfgTimes,
  BE_HudReset,
  BE_HudWant,
  BE_HudPlace,
  BE_HudDraw,
  BE_HudHideAll,
  BE_HudOp,
  BE_HudDue,
  BE_HudClockReset,
  BE_HudMoved,
  BE_HudState,
  BE_BodyHudText,
  BE_BodyWoundList,
  BE_SpriteCalibrate,
  BE_SpriteCheck,
  BE_SpriteMemReady,
  BE_SpriteMemInfo,
  BE_AmmoLastW,
  BE_AmmoPass,
  BE_AmmoPassOp;

end.

