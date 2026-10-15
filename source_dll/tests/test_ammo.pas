program test_ammo;

{ The ammunition module on its own: counts as the server shows them (with the server's own flickers),
  shots, reloads, a tactical reload, partial magazines, running dry, the Spas-12, single-round
  weapons, a phantom shot, the aimbot setting the magazine, a swap with the secondary, a dead
  soldier's pouch, a bot, the 255 glitch, the chainsaw and infinite ammo; the shots of the hook
  shown at once (also with the reload key held), the weapon objects the hook reports and the spare
  magazines left with the body. }

{$mode objfpc}{$H+}

uses
  SysUtils, be_world, be_ballistic, be_map, be_ammo;

var
  Fails: LongInt = 0;
  Checks: LongInt = 0;
  T: LongInt = 0;
  LastAct, LastVal, Sets, Drops: LongInt;

procedure Check(Ok: Boolean; const What: AnsiString);
begin
  Inc(Checks);
  if not Ok then
  begin
    Inc(Fails);
    WriteLn('FAIL: ', What);
  end;
end;

{ one tick of the server's count }
procedure Tick1(ID, W, A, SW, SA, Flags: LongInt);
var
  V, R: LongInt;
begin
  Inc(T);
  R := AmmoObserve(ID, T, W, A, SW, SA, Flags, 100, 200, V);
  if (R = AMA_SET) or (R = AMA_DROP) then
  begin
    LastAct := R;
    LastVal := V;
    if R = AMA_SET then
      Inc(Sets)
    else
      Inc(Drops);
  end;
end;

{ one tick of the server's count; the library's answer }
function TickR(ID, W, A, SW, SA, Flags: LongInt): LongInt;
var
  V: LongInt;
begin
  Inc(T);
  Result := AmmoObserve(ID, T, W, A, SW, SA, Flags, 100, 200, V);
  if (Result = AMA_SET) or (Result = AMA_DROP) then
  begin
    LastAct := Result;
    LastVal := V;
    if Result = AMA_SET then
      Inc(Sets)
    else
      Inc(Drops);
  end;
end;

procedure Hold(ID, W, A, Flags, Ticks: LongInt);
var
  k: LongInt;
begin
  for k := 1 to Ticks do
    Tick1(ID, W, A, -1, -1, Flags);
end;

{ Shots from A down to Stop, one every Iv ticks }
function Fire(ID, W, A, Stop, Iv, Flags: LongInt): LongInt;
begin
  while A > Stop do
  begin
    Dec(A);
    Hold(ID, W, A, Flags, Iv);
  end;
  Result := A;
end;

procedure ResetCounts;
begin
  LastAct := AMA_NONE;
  LastVal := -1;
  Sets := 0;
  Drops := 0;
end;

function Hud(ID, W, Clip: LongInt): AnsiString;
begin
  Result := AmmoFormatHud(ID, W, Clip);
end;

{ the script builds the ammunition line of the weapon the game shows (main.pas AmmoHudWant) }
function Draw(ID, W, A: LongInt): AnsiString;
begin
  Result := AmmoFormatHud(ID, W, AmmoShown(ID, T, W, A));
  AmmoDrawn(ID, W);
end;

const
  H = AMF_HUMAN;
  AK = 3;
  COLT = 0;
  M79 = 7;
  SPAS = 5;
  SAW = 12;

var
  A, Cap, G, R, S0, CA, k, n, D: LongInt;
  MX, MY, AX, AY, DX, DY: Single;
  Found: Boolean;
  Rays, Stamp: LongInt;
begin
  WeaponsDefault(False);
  Cap := Weapon[AK].Ammo;
  WriteLn('AK magazine ', Cap, ', Spas ', Weapon[SPAS].Ammo, ', M79 ', Weapon[M79].Ammo);
  AmmoConfig(1, 1, 1, 0, 1, 4, 2, 4, 45);
  AmmoSetReserve(AK, 2 * Cap);
  AmmoSetReserve(COLT, 48);
  AmmoSetReserve(M79, 2);
  AmmoSetReserve(SPAS, 3);
  AmmoSetReserve(SAW, 40);

  { 1. a fresh AK from the menu: two spare magazines; shots and a normal reload }
  ResetCounts;
  AmmoRespawn(1, T);
  Tick1(1, AK, Cap, COLT, 12, H);
  Check(Hud(1, AK, Cap) = ' | Ammo: ' + IntToStr(Cap) + ' [' + IntToStr(Cap) + ', ' + IntToStr(Cap) + ']',
    'fresh AK pouch: ' + Hud(1, AK, Cap));
  Hold(1, AK, Cap, H, 20);
  A := Fire(1, AK, Cap, 0, 10, H);
  Hold(1, AK, 0, H, 60);
  { the server's own reload shows a full magazine for a moment while the client still reloads }
  Hold(1, AK, Cap, H, 3);
  Hold(1, AK, 0, H, 60);
  Check(Sets + Drops = 0, 'no action while reloading');
  Hold(1, AK, Cap, H, 3);
  Check(AmmoShown(1, T, AK, Cap) = 0, 'the server showing a full magazine for a moment is not shown');
  Hold(1, AK, 0, H, 30);
  Check(AmmoMagCount(1, AK) = 2, 'no magazine used before the reload is done');
  Hold(1, AK, Cap, H, 20);
  Check(Sets + Drops = 0, 'a full spare magazine needs no correction');
  Check(AmmoMagCount(1, AK) = 1, 'one spare magazine left after the reload');

  { 2. a phantom shot of the server is corrected by the client's report: nothing counted }
  Hold(1, AK, Cap - 1, H, 3);
  Hold(1, AK, Cap, H, 20);
  Check(Sets + Drops = 0, 'a phantom shot is ignored');

  { 3. tactical reload: 10 shots, then the reload key empties the magazine; its rounds go back }
  A := Fire(1, AK, Cap, Cap - 10, 10, H);
  Hold(1, AK, A, H, 12);
  Hold(1, AK, 0, H or AMF_RELOAD, 2);
  Hold(1, AK, 0, H, 100);
  Hold(1, AK, Cap, H, 20);
  Check(Sets + Drops = 0, 'tactical reload loads the full spare magazine: nothing to set');
  Check((AmmoMagCount(1, AK) = 1) and (AmmoMagRounds(1, AK, 0) = Cap - 10),
    'the partial magazine is back in the pouch: ' + Hud(1, AK, Cap));

  { 4. the last magazine is partial: after the reload the script sets it, then the server's
    transient 0 and the client's echo change nothing }
  A := Fire(1, AK, Cap, 0, 10, H);
  Hold(1, AK, 0, H, 100);
  Hold(1, AK, Cap, H, 9);
  Check((LastAct = AMA_SET) and (LastVal = Cap - 10), 'partial magazine set to ' + IntToStr(Cap - 10) + ' (got ' +
    IntToStr(LastAct) + '/' + IntToStr(LastVal) + ')');
  Check(AmmoClip(1, T, Cap) = Cap - 10, 'while the set count travels the clip is the set one');
  ResetCounts;
  Hold(1, AK, 0, H, 4);
  Hold(1, AK, Cap - 10, H, 20);
  Check(Sets + Drops = 0, 'the transient after a set is ignored');

  { 5. the last rounds, nothing left: the weapon is taken away at the empty magazine }
  A := Fire(1, AK, Cap - 10, 0, 10, H);
  Hold(1, AK, 0, H, 20);
  Check(LastAct = AMA_DROP, 'an empty AK with no magazines is taken away');

  { 6. the M79 (one round) takes its reloads from the reserve and goes when it is empty }
  ResetCounts;
  AmmoRespawn(1, T);
  Tick1(1, M79, 1, COLT, 12, H);
  Hold(1, M79, 1, H, 20);
  Hold(1, M79, 0, H, 150);
  Hold(1, M79, 1, H, 20);
  Hold(1, M79, 0, H, 150);
  Hold(1, M79, 1, H, 20);
  Check(Sets + Drops = 0, 'two reloads of the M79 from a reserve of 2');
  Hold(1, M79, 0, H, 20);
  Check(LastAct = AMA_DROP, 'the M79 goes with the reserve used up');

  { 7. the Spas-12 loads shells from its reserve }
  ResetCounts;
  AmmoRespawn(1, T);
  Tick1(1, SPAS, Weapon[SPAS].Ammo, COLT, 12, H);
  A := Fire(1, SPAS, Weapon[SPAS].Ammo, Weapon[SPAS].Ammo - 2, 40, H);
  Hold(1, SPAS, A + 1, H, 24);
  Hold(1, SPAS, A + 2, H, 24);
  Check(Hud(1, SPAS, A + 2) = ' | Ammo: ' + IntToStr(A + 2) + '/1', 'two shells from 3: ' + Hud(1, SPAS, A + 2));
  A := Fire(1, SPAS, A + 2, 0, 40, H);
  Hold(1, SPAS, 0, H, 20);
  Check(Drops = 0, 'the Spas with one shell left stays');
  Hold(1, SPAS, 1, H, 24);
  Hold(1, SPAS, 2, H, 24);
  Check((LastAct = AMA_SET) and (LastVal = 1), 'the Spas loads only the shell it had (got ' + IntToStr(LastAct) + '/' +
    IntToStr(LastVal) + ')');
  ResetCounts;
  Hold(1, SPAS, 1, H, 24);
  Hold(1, SPAS, 0, H, 20);
  Check(LastAct = AMA_DROP, 'the Spas goes with no shells left');

  { 8. the aimbot sets the magazine itself: its sets and the server's transients change nothing }
  ResetCounts;
  AmmoRespawn(1, T);
  Tick1(1, AK, Cap, COLT, 12, H);
  Hold(1, AK, Cap, H, 20);
  A := Cap;
  while A > Cap - 5 do
  begin
    Dec(A);
    AmmoForced(1, T, AK, A);
    Hold(1, AK, 0, H, 3);
    Hold(1, AK, A, H, 7);
  end;
  Hold(1, AK, A, H, 20);
  Check(Sets + Drops = 0, 'aimbot shots change nothing');
  Check(AmmoMagCount(1, AK) = 2, 'aimbot shots do not use spare magazines');

  { 9. a swap with the secondary and back: nothing is dropped, both keep their counts }
  Tick1(1, COLT, 12, AK, A, H);
  Hold(1, COLT, 12, H, 20);
  Tick1(1, AK, A, COLT, 12, H);
  Hold(1, AK, A, H, 20);
  Check(Sets + Drops = 0, 'swaps change nothing');
  Check(AmmoMagCount(1, AK) = 2, 'the AK pouch is kept over the swaps');

  { 10. a dead soldier's AK pouch goes to the one who picks his AK up (the script says which
    record's map object vanished) }
  AmmoRespawn(2, T);
  Tick1(2, COLT, 12, 255, 0, H);
  Check(AmmoDeath(1, T, 110, 200) = AK, 'the dead soldier leaves his AK');
  G := AmmoGroundNext(AK, 0);
  Check((G >= 0) and (AmmoGroundAttach(1, AK, 17, 1, T) = 1), 'the AK lying there gets its map object');
  Check(AmmoGroundSlot(G) = 17, 'the record knows its object');
  T := T + 300;
  AmmoPickFrom(2, T + 1, G);
  Tick1(2, AK, 20, COLT, 12, H);
  Check(AmmoMagCount(2, AK) = 2, 'the pouch of the dead soldier comes with his AK: ' + Hud(2, AK, 20));
  Check(AmmoGroundSlot(G) = 0, 'the record is gone once picked up');

  { 11. a bot: the weapon reloads full (a bot takes no partial magazine), but the partial magazine is
    used up the same and the bot runs dry }
  ResetCounts;
  AmmoSetReserve(AK, Cap);
  AmmoRespawn(3, T);
  Tick1(3, AK, Cap, COLT, 12, 0);
  Hold(3, AK, Cap, 0, 20);
  A := Fire(3, AK, Cap, 20, 10, 0);
  Hold(3, AK, 20, 0, 12);
  Hold(3, AK, 0, AMF_RELOAD, 2);
  Hold(3, AK, 0, 0, 100);
  Hold(3, AK, Cap, 0, 20);
  A := Fire(3, AK, Cap, 0, 10, 0);
  Hold(3, AK, 0, 0, 100);
  Hold(3, AK, Cap, 0, 20);
  Check(Sets = 0, 'no partial magazine for a bot');
  A := Fire(3, AK, Cap, 0, 10, 0);
  Hold(3, AK, 0, 0, 20);
  Check(LastAct = AMA_DROP, 'a bot loses the AK when nothing is left');
  AmmoSetReserve(AK, 2 * Cap);

  { 12. the 255 of 2.8.2 for a tick is not a count }
  ResetCounts;
  AmmoRespawn(4, T);
  Tick1(4, AK, Cap, COLT, 12, H);
  Hold(4, AK, Cap, H, 20);
  Hold(4, AK, 255, H, 1);
  Hold(4, AK, Cap, H, 20);
  Check(Sets + Drops = 0, '255 is ignored');

  { 13. the chainsaw burns fuel while held, faster while sawing, and goes empty }
  ResetCounts;
  AmmoRespawn(5, T);
  Tick1(5, SAW, 200, COLT, 12, H);
  Hold(5, SAW, 200, H, 40);
  Check(Pos('Fuel: 30', Hud(5, SAW, 0)) > 0, 'fuel after 40 ticks held: ' + Hud(5, SAW, 0));
  Hold(5, SAW, 200, H or AMF_SHOOT, 20);
  Check(LastAct = AMA_DROP, 'the chainsaw goes without fuel');

  { 14. infinite ammo: nothing is counted }
  ResetCounts;
  AmmoRespawn(6, T);
  Tick1(6, AK, Cap, COLT, 12, H);
  A := Fire(6, AK, Cap, 0, 5, H or AMF_FREE);
  Hold(6, AK, 0, H or AMF_FREE, 100);
  Hold(6, AK, Cap, H or AMF_FREE, 20);
  A := Fire(6, AK, Cap, 0, 5, H or AMF_FREE);
  Hold(6, AK, 0, H or AMF_FREE, 100);
  Hold(6, AK, Cap, H or AMF_FREE, 20);
  A := Fire(6, AK, Cap, 0, 5, H or AMF_FREE);
  Hold(6, AK, 0, H or AMF_FREE, 100);
  Hold(6, AK, Cap, H or AMF_FREE, 20);
  Check(Sets + Drops = 0, 'infinite ammo: nothing happens');
  Check(AmmoMagCount(6, AK) = 2, 'infinite ammo: the spare magazines stay');

  { 15. pool mode: the AK takes its reloads from a reserve of rounds }
  ResetCounts;
  AmmoConfig(1, 0, 1, 0, 1, 4, 2, 4, 45);
  AmmoSetReserve(AK, Cap + 10);
  AmmoRespawn(7, T);
  Tick1(7, AK, Cap, COLT, 12, H);
  Hold(7, AK, Cap, H, 20);
  A := Fire(7, AK, Cap, 0, 10, H);
  Hold(7, AK, 0, H, 100);
  Hold(7, AK, Cap, H, 20);
  Check(Sets + Drops = 0, 'pool: a full reload from the reserve');
  Check(Hud(7, AK, Cap) = ' | Ammo: ' + IntToStr(Cap) + '/10', 'pool reserve after one reload: ' + Hud(7, AK, Cap));
  A := Fire(7, AK, Cap, 0, 10, H);
  Hold(7, AK, 0, H, 100);
  Hold(7, AK, Cap, H, 9);
  Check((LastAct = AMA_SET) and (LastVal = 10), 'pool: the last 10 rounds are set (got ' + IntToStr(LastAct) + '/' +
    IntToStr(LastVal) + ')');

  { 16. the client fires at once after a set magazine arrives (its report never shows the set
    count): the wait ends by time and the shot is counted normally }
  ResetCounts;
  AmmoConfig(1, 1, 1, 0, 1, 4, 2, 4, 45);
  AmmoSetReserve(AK, 2 * Cap);
  AmmoRespawn(8, T);
  Tick1(8, AK, Cap, COLT, 12, H);
  Hold(8, AK, Cap, H, 20);
  AmmoForced(8, T, AK, 30);
  Hold(8, AK, 0, H, 4);
  Hold(8, AK, 29, H, 40);
  Check(Sets + Drops = 0, 'a set count answered by a lower one changes nothing');
  Check(AmmoClip(8, T, 29) = 29, 'after the wait the clip follows the reports');

  { 17. /mag: a chosen magazine; the one in the weapon goes back into the pouch }
  ResetCounts;
  AmmoSetReserve(AK, 2 * Cap);
  AmmoRespawn(9, T);
  Tick1(9, AK, Cap, COLT, 12, H);
  Hold(9, AK, Cap, H, 20);
  A := Fire(9, AK, Cap, 15, 10, H);
  Hold(9, AK, 15, H, 12);
  Hold(9, AK, 0, H or AMF_RELOAD, 2);
  Hold(9, AK, 0, H, 100);
  Hold(9, AK, Cap, H, 20);
  A := Fire(9, AK, Cap, 20, 10, H);
  Hold(9, AK, 20, H, 12);
  Check((AmmoMagCount(9, AK) = 2) and (AmmoMagRounds(9, AK, 1) = 15), 'spare magazines of ' + IntToStr(Cap) +
    ' and 15 (' + Hud(9, AK, 20) + ')');
  Check(AmmoSelectMag(9, AK, 1) = 1, 'the 15-round magazine chosen');
  Check(AmmoReloadNow(9, T, 20) = 1, '/mag empties the magazine for a reload');
  Hold(9, AK, 0, H, 100);
  Hold(9, AK, Cap, H, 9);
  Check((LastAct = AMA_SET) and (LastVal = 15), 'the chosen 15-round magazine is loaded (got ' + IntToStr(LastAct) + '/' +
    IntToStr(LastVal) + ')');
  Check((AmmoMagCount(9, AK) = 2) and (AmmoMagRounds(9, AK, 1) = 20), 'the 20 rounds went back: ' + Hud(9, AK, 15));

  { 18. a reload with no spare magazine but rounds in the weapon: the same magazine comes back }
  ResetCounts;
  AmmoSetReserve(AK, 0);
  AmmoRespawn(10, T);
  Tick1(10, AK, Cap, COLT, 12, H);
  Hold(10, AK, Cap, H, 20);
  A := Fire(10, AK, Cap, 20, 10, H);
  Hold(10, AK, 20, H, 12);
  Hold(10, AK, 0, H or AMF_RELOAD, 2);
  Hold(10, AK, 0, H, 100);
  Check(Drops = 0, 'a reload with rounds in the weapon does not take it away');
  Hold(10, AK, Cap, H, 9);
  Check((LastAct = AMA_SET) and (LastVal = 20), 'the 20 rounds are loaded again (got ' + IntToStr(LastAct) + '/' +
    IntToStr(LastVal) + ')');

  { 19. an empty weapon picked up with nothing to load for it goes at once (before the game reloads
    it); with rounds for it, it stays }
  ResetCounts;
  AmmoSetReserve(AK, 0);
  AmmoRespawn(11, T);
  Tick1(11, COLT, 12, 255, 0, H);
  T := T + 700;
  Tick1(11, AK, 0, COLT, 12, H);
  Check(LastAct = AMA_DROP, 'an empty AK with no reserve is taken at the pickup');
  ResetCounts;
  AmmoSetReserve(AK, Cap);
  AmmoRespawn(12, T);
  Tick1(12, COLT, 12, 255, 0, H);
  T := T + 700;
  Tick1(12, AK, 0, COLT, 12, H);
  Hold(12, AK, 0, H, 20);
  Check(Drops = 0, 'an empty AK with a magazine for it stays');

  { 20. after the weapon is taken, the client's older reports still carrying it do not take it again }
  ResetCounts;
  AmmoSetReserve(AK, 0);
  AmmoRespawn(13, T);
  Tick1(13, AK, Cap, COLT, 12, H);
  Hold(13, AK, Cap, H, 20);
  A := Fire(13, AK, Cap, 0, 10, H);
  Hold(13, AK, 0, H, 9);
  Check(Drops = 1, 'the AK is taken once');
  Hold(13, AK, 0, H, 30);
  Hold(13, 255, 0, H, 30);
  Check(Drops = 1, 'late reports with the AK do not take it again');

  { 21. a gun thrown away alive keeps only its rounds: after a respawn (a new pouch) the soldier who
    picks it up again gets no spare magazines with it; the same kind from the menu is fresh }
  ResetCounts;
  AmmoSetReserve(AK, 2 * Cap);
  AmmoRespawn(14, T);
  Tick1(14, AK, Cap, COLT, 12, H);
  Hold(14, AK, Cap, H, 20);
  A := Fire(14, AK, Cap, Cap - 2, 10, H);
  Hold(14, AK, A, H, 12);
  Tick1(14, 255, 0, COLT, 12, H);
  Check(AmmoGroundAttach(14, AK, 23, 0, T) = 1, 'the thrown AK gets its map object');
  G := AmmoGroundNext(AK, 0);
  while (G >= 0) and (AmmoGroundSlot(G) <> 23) do
    G := AmmoGroundNext(AK, G + 1);
  Check(G >= 0, 'the thrown AK lies on the ground');
  AmmoRespawn(14, T);
  Tick1(14, 255, 0, COLT, 12, H);
  AmmoPickFrom(14, T + 1, G);
  Tick1(14, AK, Cap - 2, COLT, 12, H);
  Check(AmmoMagCount(14, AK) = 0, 'no spare magazines come with a gun thrown away alive: ' + Hud(14, AK, Cap - 2));
  AmmoRespawn(15, T);
  Tick1(15, 255, 0, COLT, 12, H);
  AmmoPickFrom(15, T + 1, -1);
  Tick1(15, AK, Cap, COLT, 12, H);
  Check(AmmoMagCount(15, AK) = 2, 'a weapon from the menu comes with its reserve: ' + Hud(15, AK, Cap));

  { 22. magazine mode fills full magazines only: the reserve rounded to whole magazines }
  AmmoSetReserve(AK, 4 * Cap + Cap div 4);
  AmmoRespawn(16, T);
  Tick1(16, AK, Cap, COLT, 12, H);
  Check((AmmoMagCount(16, AK) = 4) and (AmmoMagRounds(16, AK, 3) = Cap), '4.25 magazines of rounds give 4 full ones: ' +
    Hud(16, AK, Cap));
  AmmoSetReserve(AK, 4 * Cap + Cap div 2 + 1);
  AmmoRespawn(16, T);
  Tick1(16, AK, Cap, COLT, 12, H);
  Check((AmmoMagCount(16, AK) = 5) and (AmmoMagRounds(16, AK, 4) = Cap), '4.5 magazines of rounds give 5 full ones: ' +
    Hud(16, AK, Cap));
  AmmoSetReserve(AK, 2 * Cap);

  { 23. a record whose object stays missing (despawned, or taken by somebody not followed) is forgotten }
  AmmoRespawn(17, T);
  Tick1(17, AK, Cap, COLT, 12, H);
  Hold(17, AK, Cap, H, 20);
  Tick1(17, 255, 0, COLT, 12, H);
  Check(AmmoGroundAttach(17, AK, 31, 0, T) = 1, 'the thrown AK gets its map object');
  G := AmmoGroundNext(AK, 0);
  while (G >= 0) and (AmmoGroundSlot(G) <> 31) do
    G := AmmoGroundNext(AK, G + 1);
  Check(G >= 0, 'the record with object 31 is found');
  Check(AmmoGroundHasSlot(31) = 1, 'object 31 belongs to a record');
  AmmoGroundMissing(G, T);
  Check(AmmoGroundSlot(G) = 31, 'missing for a moment: kept');
  AmmoGroundMissing(G, T + 25);
  Check((AmmoGroundSlot(G) = 0) and (AmmoGroundHasSlot(31) = 0), 'missing for good: forgotten');

  { 24. a chainsaw thrown away keeps the fuel in its tank: picked up again in a new life it has that
    fuel, not none (it would go at once) and not a full tank }
  ResetCounts;
  AmmoRespawn(18, T);
  Tick1(18, SAW, 200, COLT, 12, H);
  Hold(18, SAW, 200, H, 40);
  Check(Pos('Fuel: 30', Hud(18, SAW, 0)) > 0, 'fuel after 40 ticks held: ' + Hud(18, SAW, 0));
  Tick1(18, 255, 0, COLT, 12, H);
  Check(AmmoGroundAttach(18, SAW, 41, 0, T) = 1, 'the thrown chainsaw gets its map object');
  G := AmmoGroundNext(SAW, 0);
  while (G >= 0) and (AmmoGroundSlot(G) <> 41) do
    G := AmmoGroundNext(SAW, G + 1);
  Check(G >= 0, 'the thrown chainsaw lies on the ground');
  AmmoRespawn(18, T);
  Tick1(18, 255, 0, COLT, 12, H);
  AmmoPickFrom(18, T + 1, G);
  Tick1(18, SAW, 200, COLT, 12, H);
  Check((Pos('Fuel: 30', Hud(18, SAW, 0)) > 0) and (Drops = 0), 'the picked chainsaw has the fuel of its tank: ' +
    Hud(18, SAW, 0));

  { 25. a shot and a reload in the same tick (the reload key held while firing): the count never shows
    the shot, the bullet does - the magazine taken out has one round less }
  ResetCounts;
  AmmoOptions(0, 0, 1, 60, 60);
  AmmoSetReserve(AK, 2 * Cap);
  AmmoRespawn(19, T);
  Tick1(19, AK, Cap, COLT, 12, H);
  Hold(19, AK, Cap, H, 20);
  AmmoShot(19, AK, T + 1);
  Hold(19, AK, 0, H or AMF_RELOAD, 2);
  Hold(19, AK, 0, H, 100);
  Hold(19, AK, Cap, H, 20);
  Check((AmmoMagCount(19, AK) = 2) and (AmmoMagRounds(19, AK, 1) = Cap - 1), 'the shot fired with the reload counts: ' +
    Hud(19, AK, Cap));

  { 26. a lower count that was never believed (an older report came after it) still counts for the
    magazine taken out: no rounds come back that were fired }
  ResetCounts;
  AmmoRespawn(20, T);
  Tick1(20, AK, Cap, COLT, 12, H);
  Hold(20, AK, Cap, H, 20);
  Hold(20, AK, Cap - 3, H, 3);
  Hold(20, AK, Cap, H, 2);
  Hold(20, AK, 0, H or AMF_RELOAD, 2);
  Hold(20, AK, 0, H, 100);
  Hold(20, AK, Cap, H, 20);
  Check((AmmoMagCount(20, AK) = 2) and (AmmoMagRounds(20, AK, 1) = Cap - 3), 'the magazine taken out has the lowest ' +
    'count: ' + Hud(20, AK, Cap));

  { 27. a reload with one round left: the round is lost (ReloadOneRound = 0), or the magazine with it
    goes back into the pouch (1) }
  ResetCounts;
  AmmoSetReserve(AK, Cap);
  AmmoRespawn(21, T);
  Tick1(21, AK, Cap, COLT, 12, H);
  Hold(21, AK, Cap, H, 20);
  A := Fire(21, AK, Cap, 1, 10, H);
  Hold(21, AK, 1, H, 12);
  Hold(21, AK, 0, H or AMF_RELOAD, 2);
  Hold(21, AK, 0, H, 100);
  Hold(21, AK, Cap, H, 20);
  Check(AmmoMagCount(21, AK) = 0, 'ReloadOneRound = 0: the round is gone: ' + Hud(21, AK, Cap));
  AmmoOptions(1, 0, 1, 60, 60);
  ResetCounts;
  AmmoRespawn(22, T);
  Tick1(22, AK, Cap, COLT, 12, H);
  Hold(22, AK, Cap, H, 20);
  A := Fire(22, AK, Cap, 1, 10, H);
  Hold(22, AK, 1, H, 12);
  Hold(22, AK, 0, H or AMF_RELOAD, 2);
  Hold(22, AK, 0, H, 100);
  Hold(22, AK, Cap, H, 20);
  Check((AmmoMagCount(22, AK) = 1) and (AmmoMagRounds(22, AK, 0) = 1), 'ReloadOneRound = 1: the magazine with one ' +
    'round comes back: ' + Hud(22, AK, Cap));
  AmmoOptions(0, 0, 1, 60, 60);

  { 28. a reload cut short by a swap to the secondary: the magazine taken out is lost
    (InterruptedReload = 0) or goes back into the pouch (1), also before its 0 was believed }
  AmmoSetReserve(AK, 2 * Cap);
  ResetCounts;
  AmmoRespawn(23, T);
  Tick1(23, AK, Cap, COLT, 12, H);
  Hold(23, AK, Cap, H, 20);
  A := Fire(23, AK, Cap, 20, 10, H);
  Hold(23, AK, 20, H, 12);
  Hold(23, AK, 0, H or AMF_RELOAD, 12);
  Tick1(23, COLT, 12, AK, 0, H);
  Check(AmmoMagCount(23, AK) = 2, 'InterruptedReload = 0: the magazine taken out is lost: ' + Hud(23, AK, 0));
  AmmoOptions(0, 1, 1, 60, 60);
  ResetCounts;
  AmmoRespawn(24, T);
  Tick1(24, AK, Cap, COLT, 12, H);
  Hold(24, AK, Cap, H, 20);
  A := Fire(24, AK, Cap, 20, 10, H);
  Hold(24, AK, 20, H, 12);
  Hold(24, AK, 0, H or AMF_RELOAD, 12);
  Tick1(24, COLT, 12, AK, 0, H);
  Check((AmmoMagCount(24, AK) = 3) and (AmmoMagRounds(24, AK, 2) = 20), 'InterruptedReload = 1: it goes back: ' +
    Hud(24, AK, 0));
  ResetCounts;
  AmmoRespawn(25, T);
  Tick1(25, AK, Cap, COLT, 12, H);
  Hold(25, AK, Cap, H, 20);
  A := Fire(25, AK, Cap, 20, 10, H);
  Hold(25, AK, 20, H, 12);
  Hold(25, AK, 0, H or AMF_RELOAD, 3);
  Tick1(25, 255, 0, COLT, 12, H);
  Check((AmmoMagCount(25, AK) = 3) and (AmmoMagRounds(25, AK, 2) = 20), 'thrown away right after the reload began ' +
    '(its 0 not believed yet): the magazine goes back: ' + Hud(25, AK, 0));
  AmmoOptions(0, 0, 1, 60, 60);

  { 29. SortMagazines = 1 keeps the pouch sorted, 0 keeps the order the magazines came in; /repack puts
    partial magazines together one every RepackStep ticks after RepackStart ticks without shooting }
  AmmoSetReserve(AK, 6 * Cap);
  AmmoOptions(0, 0, 0, 60, 60);
  ResetCounts;
  AmmoRespawn(26, T);
  Tick1(26, AK, Cap, COLT, 12, H);
  Hold(26, AK, Cap, H, 20);
  for G := 0 to 3 do
  begin
    if G = 0 then
      A := 5
    else if G = 1 then
      A := 20
    else if G = 2 then
      A := 10
    else
      A := 30;
    A := Fire(26, AK, Cap, A, 1, H);
    Hold(26, AK, A, H, 12);
    Hold(26, AK, 0, H or AMF_RELOAD, 2);
    Hold(26, AK, 0, H, 100);
    Hold(26, AK, Cap, H, 20);
  end;
  Check(Hud(26, AK, Cap) = ' | Ammo: ' + IntToStr(Cap) + ' [' + IntToStr(Cap) + ', ' + IntToStr(Cap) +
    ', 5, 20, 10, 30]', 'SortMagazines = 0: in the order they came: ' + Hud(26, AK, Cap));
  Check(AmmoRepack(26, T) = 1, '/repack begins');
  Hold(26, AK, Cap, H, 59);
  Check(AmmoRepacking(26) = 1, 'it waits RepackStart ticks');
  Hold(26, AK, Cap, H, 1);
  Check((AmmoRepacking(26) = 2) and (AmmoRepackEvent(26) = AMR_STARTED), 'then it runs');
  Hold(26, AK, Cap, H, 60);
  Check(AmmoRepackEvent(26) = AMR_STEP, 'one magazine after RepackStep ticks: ' + Hud(26, AK, Cap));
  Hold(26, AK, Cap, H, 60);
  Check(AmmoRepackEvent(26) = AMR_DONE, 'done: ' + Hud(26, AK, Cap));
  Check(Hud(26, AK, Cap) = ' | Ammo: ' + IntToStr(Cap) + ' [' + IntToStr(Cap) + ', ' + IntToStr(Cap) + ', ' +
    IntToStr(Cap) + ', ' + IntToStr(65 - Cap) + ']', 'the rounds put together and sorted: ' + Hud(26, AK, Cap));
  A := Fire(26, AK, Cap, Cap - 3, 1, H);
  Hold(26, AK, A, H, 12);
  Hold(26, AK, 0, H or AMF_RELOAD, 2);
  Hold(26, AK, 0, H, 100);
  Hold(26, AK, Cap, H, 20);
  Check(AmmoRepack(26, T) = 1, '/repack again');
  Hold(26, AK, Cap, H, 20);
  Tick1(26, AK, Cap, -1, -1, H or AMF_SHOOT);
  Check((AmmoRepacking(26) = 0) and (AmmoRepackEvent(26) = AMR_SHOT), 'a shot stops it');
  AmmoOptions(0, 0, 1, 60, 60);
  ResetCounts;
  AmmoRespawn(27, T);
  Tick1(27, AK, Cap, COLT, 12, H);
  Hold(27, AK, Cap, H, 20);
  for G := 0 to 1 do
  begin
    if G = 0 then
      A := 10
    else
      A := 30;
    A := Fire(27, AK, Cap, A, 1, H);
    Hold(27, AK, A, H, 12);
    Hold(27, AK, 0, H or AMF_RELOAD, 2);
    Hold(27, AK, 0, H, 100);
    Hold(27, AK, Cap, H, 20);
  end;
  Check(Pos(', 30, 10]', Hud(27, AK, Cap)) > 0, 'SortMagazines = 1: the fullest first: ' + Hud(27, AK, Cap));

  { 30. the health line: no spare magazine left is shown as a word; the chainsaw's fuel in ml and l }
  AmmoSetText(AMT_NO_SPARE, 'empty');
  AmmoSetReserve(AK, 0);
  ResetCounts;
  AmmoRespawn(28, T);
  Tick1(28, AK, Cap, COLT, 12, H);
  Check(Hud(28, AK, Cap) = ' | Ammo: ' + IntToStr(Cap) + ' [empty]', 'no spare magazine: ' + Hud(28, AK, Cap));
  Check(AmmoLevel(28, AK, Cap) = 100, 'a full load is 100%');
  Check(AmmoLevel(28, AK, Cap div 2) = 50, 'half of it 50%');
  Check(AmmoLevel(28, AK, 0) = 0, 'nothing left 0%');
  AmmoSetReserve(SAW, 1250);
  AmmoRespawn(29, T);
  Tick1(29, SAW, 200, COLT, 12, H);
  Check(Pos('Fuel: 1.25 l', Hud(29, SAW, 0)) > 0, 'fuel in litres: ' + Hud(29, SAW, 0));
  AmmoSetReserve(SAW, 850);
  AmmoRespawn(29, T);
  Tick1(29, SAW, 200, COLT, 12, H);
  Check(Pos('Fuel: 850 ml', Hud(29, SAW, 0)) > 0, 'fuel in millilitres: ' + Hud(29, SAW, 0));

  { 31. EmptyDrop = 0: a human's empty weapon stays at 0 - it is set again before the game's reload
    could fill it, and at once when a report shows rounds; a bot's goes (its reload is always full) }
  AmmoConfig(1, 1, 0, 0, 1, 4, 2, 4, 45);
  AmmoSetReserve(AK, 0);
  ResetCounts;
  AmmoRespawn(30, T);
  Tick1(30, AK, Cap, COLT, 12, H);
  Hold(30, AK, Cap, H, 20);
  A := Fire(30, AK, Cap, 0, 10, H);
  Hold(30, AK, 0, H, 9);
  Check((Sets = 1) and (Drops = 0) and (LastVal = 0), 'kept at 0, not taken');
  Hold(30, AK, 0, H, 200);
  Check(Sets >= 3, 'set to 0 again and again (' + IntToStr(Sets) + ')');
  A := Sets;
  Tick1(30, AK, Cap, -1, -1, H);
  Check((Sets = A + 1) and (LastVal = 0), 'a report with rounds is answered at once');
  ResetCounts;
  AmmoRespawn(31, T);
  Tick1(31, AK, Cap, COLT, 12, 0);
  Hold(31, AK, Cap, 0, 20);
  A := Fire(31, AK, Cap, 0, 10, 0);
  Hold(31, AK, 0, 0, 9);
  Check(Drops = 1, 'a bot loses the empty weapon also with EmptyDrop = 0');

  { 32. EmptyDrop = 0: an empty weapon thrown away and picked up again is kept at 0 at once, before
    the game can reload it }
  ResetCounts;
  AmmoRespawn(32, T);
  Tick1(32, AK, Cap, COLT, 12, H);
  Hold(32, AK, Cap, H, 20);
  A := Fire(32, AK, Cap, 0, 10, H);
  Hold(32, AK, 0, H, 9);
  Tick1(32, 255, 0, COLT, 12, H);
  Hold(32, 255, 0, H, 5);
  S0 := Sets;
  Tick1(32, AK, 0, COLT, 12, H);
  Check((Sets = S0 + 1) and (LastVal = 0) and (Drops = 0), 'EmptyDrop = 0: the empty weapon picked up is kept at 0 ' +
    'at once');
  Hold(32, AK, 0, H, 200);
  Check(Sets >= S0 + 3, 'and set again before a reload could end (' + IntToStr(Sets - S0) + ')');
  AmmoConfig(1, 1, 1, 0, 1, 4, 2, 4, 45);

  { 33. the hook's shots are shown at once; the reports catching up count nothing twice }
  AmmoSetReserve(AK, 2 * Cap);
  ResetCounts;
  AmmoRespawn(2, T);
  Tick1(2, AK, Cap, COLT, 12, H);
  Hold(2, AK, Cap, H, 20);
  AmmoShot(2, AK, T + 1);
  Tick1(2, AK, Cap, -1, -1, H);
  Check(AmmoShown(2, T, AK, Cap) = Cap - 1, 'a shot of the hook is shown at once');
  AmmoShot(2, AK, T + 1);
  Tick1(2, AK, Cap, -1, -1, H);
  Check(AmmoShown(2, T, AK, Cap) = Cap - 2, 'two shots');
  Hold(2, AK, Cap - 2, H, 20);
  Check(AmmoShown(2, T, AK, Cap - 2) = Cap - 2, 'the reports agree: no shot counted twice (' +
    IntToStr(AmmoShown(2, T, AK, Cap - 2)) + ')');
  { a shot no report shows (a bullet that came in before an older report): the client keeps reporting
    its count, and that is shown after a while }
  AmmoShot(2, AK, T + 1);
  Tick1(2, AK, Cap - 2, -1, -1, H);
  Check(AmmoShown(2, T, AK, Cap - 2) = Cap - 3, 'a shot not in the report yet is shown');
  Hold(2, AK, Cap - 2, H, 12);
  Check(AmmoShown(2, T, AK, Cap - 2) = Cap - 2, 'the client keeps reporting its count: that is shown');
  Check(Sets + Drops = 0, 'nothing set');

  { 34. the reload key held while firing (a shot, the reload at once): the shot and the reload are
    shown at once, the magazine taken out has the shot less }
  ResetCounts;
  AmmoRespawn(3, T);
  Tick1(3, AK, Cap, COLT, 12, H);
  Hold(3, AK, Cap, H, 20);
  AmmoShot(3, AK, T + 1);
  Tick1(3, AK, Cap, -1, -1, H or AMF_RELOAD);
  Check(AmmoShown(3, T, AK, Cap) = Cap - 1, 'the shot fired with the reload key held is shown');
  Hold(3, AK, 0, H or AMF_RELOAD, 3);
  Check(AmmoShown(3, T, AK, 0) = 0, 'the reload is shown at once');
  Hold(3, AK, 0, H or AMF_RELOAD, 100);
  Hold(3, AK, Cap, H or AMF_RELOAD, 20);
  Check((AmmoMagCount(3, AK) = 2) and (AmmoMagRounds(3, AK, 1) = Cap - 1), 'the magazine taken out has the shot ' +
    'less: ' + Hud(3, AK, Cap));
  Check(AmmoShown(3, T, AK, Cap) = Cap, 'the full magazine after the reload');

  { 35. a partial magazine set by the script: the client's shots from it (its report lower than the
    count set, with the hook's shots) and a reload started with the key held are taken during the wait }
  AmmoSetReserve(AK, Cap);
  ResetCounts;
  AmmoRespawn(4, T);
  Tick1(4, AK, Cap, COLT, 12, H);
  Hold(4, AK, Cap, H, 20);
  A := Fire(4, AK, Cap, Cap - 10, 10, H);
  Hold(4, AK, A, H, 12);
  Hold(4, AK, 0, H or AMF_RELOAD, 2);
  Hold(4, AK, 0, H, 100);
  Hold(4, AK, Cap, H, 20);
  A := Fire(4, AK, Cap, 0, 10, H);
  Hold(4, AK, 0, H, 100);
  Hold(4, AK, Cap, H, 9);
  Check((LastAct = AMA_SET) and (LastVal = Cap - 10), 'the partial magazine is set (' + IntToStr(LastVal) + ')');
  Hold(4, AK, Cap, H, 4);
  AmmoShot(4, AK, T + 1);
  Tick1(4, AK, Cap, -1, -1, H);
  Tick1(4, AK, Cap - 11, -1, -1, H);
  Check(AmmoShown(4, T, AK, Cap - 11) = Cap - 11, 'the client fired from the set magazine: shown (' +
    IntToStr(AmmoShown(4, T, AK, Cap - 11)) + ')');
  AmmoShot(4, AK, T + 1);
  Tick1(4, AK, Cap - 11, -1, -1, H);
  Check(AmmoShown(4, T, AK, Cap - 11) = Cap - 12, 'its next shot at once');
  Hold(4, AK, Cap - 12, H, 20);
  Check((AmmoShown(4, T, AK, Cap - 12) = Cap - 12) and (Sets = 1), 'the reports agree, nothing set again');
  AmmoSetReserve(AK, 2 * Cap);
  ResetCounts;
  AmmoRespawn(5, T);
  Tick1(5, AK, Cap, COLT, 12, H);
  Hold(5, AK, Cap, H, 20);
  A := Fire(5, AK, Cap, Cap - 10, 10, H);
  Hold(5, AK, A, H, 12);
  Hold(5, AK, 0, H or AMF_RELOAD, 2);
  Hold(5, AK, 0, H, 100);
  Hold(5, AK, Cap, H, 20);
  A := Fire(5, AK, Cap, Cap - 20, 10, H);
  Hold(5, AK, A, H, 12);
  Hold(5, AK, 0, H or AMF_RELOAD, 2);
  Hold(5, AK, 0, H, 100);
  Hold(5, AK, Cap, H, 20);
  A := Fire(5, AK, Cap, 0, 10, H);
  Hold(5, AK, 0, H, 100);
  Hold(5, AK, Cap, H, 9);
  Check((LastAct = AMA_SET) and (LastVal = Cap - 10), 'the fullest partial magazine is set');
  Hold(5, AK, Cap, H, 4);
  Hold(5, AK, 0, H or AMF_RELOAD, 12);
  Check(AmmoShown(5, T, AK, 0) = 0, 'the key held: the client reloads the set magazine at once (shown 0)');
  Hold(5, AK, 0, H or AMF_RELOAD, 100);
  Hold(5, AK, Cap, H or AMF_RELOAD, 9);
  Check((LastAct = AMA_SET) and (LastVal = Cap - 10), 'the magazine taken out came back and is loaded again');
  Check((AmmoMagCount(5, AK) = 1) and (AmmoMagRounds(5, AK, 0) = Cap - 20), 'the other one stays: ' +
    Hud(5, AK, Cap - 10));

  { 36. the hook reports the weapon object the game made: after the death (the script hears of the
    death first) and before a throw is seen }
  AmmoSetReserve(AK, 2 * Cap);
  ResetCounts;
  AmmoRespawn(6, T);
  Tick1(6, AK, Cap, COLT, 12, H);
  Hold(6, AK, Cap, H, 20);
  Check(AmmoDeath(6, T, 300, 200) = AK, 'dies with the AK');
  AmmoDropped(6, 7, 71, T + 1);
  Check(AmmoGroundHasSlot(71) = 1, 'the dead soldier''s AK has the object the hook reported');
  ResetCounts;
  AmmoRespawn(7, T);
  Tick1(7, AK, Cap, COLT, 12, H);
  Hold(7, AK, Cap, H, 20);
  AmmoDropped(7, 7, 72, T + 1);
  Tick1(7, 255, 0, COLT, 12, H);
  Check(AmmoGroundHasSlot(72) = 1, 'the thrown AK has the object the hook reported');
  AmmoDropped(7, 16, 73, T + 1);
  Check(AmmoGroundHasSlot(73) = 0, 'a kit is not a weapon');

  { 37. DeadMagazines = body: the weapon keeps its magazine, the spare magazines stay with the body
    (looted where it lies, gone with the next life); a team change still leaves them with the weapon }
  AmmoSetBodyMode(1);
  ResetCounts;
  AmmoRespawn(8, T);
  Tick1(8, AK, Cap, COLT, 12, H);
  Hold(8, AK, Cap, H, 20);
  A := Fire(8, AK, Cap, Cap - 5, 10, H);
  Hold(8, AK, A, H, 12);
  Check(AmmoDeath(8, T, 500, 200) = AK, 'body mode: dies with the AK');
  AmmoDropped(8, 7, 74, T + 1);
  Check(AmmoGroundHasSlot(74) = 1, 'body mode: the weapon has its object');
  AmmoRespawn(9, T);
  Tick1(9, AK, Cap, COLT, 12, H);
  Check(AmmoCanLoot(9, AK, 500, 200) = 1, 'the body can be looted');
  AmmoBodyMove(8, 520, 260);
  Check(AmmoCanLoot(9, AK, 500, 200) = 0, 'not where the body was (the weapon there has no spare magazine)');
  Check(AmmoCanLoot(9, AK, 520, 260) = 1, 'where the body lies now');
  R := AmmoLoot(9, AK, 520, 260, 0);
  Check(R = Cap, 'a spare magazine looted from the body (' + IntToStr(R) + ')');
  AmmoRespawn(10, T);
  Tick1(10, 255, 0, COLT, 12, H);
  G := AmmoGroundNext(AK, 0);
  while (G >= 0) and (AmmoGroundSlot(G) <> 74) do
    G := AmmoGroundNext(AK, G + 1);
  Check(G >= 0, 'the dead soldier''s weapon lies there');
  AmmoPickFrom(10, T + 1, G);
  Tick1(10, AK, Cap - 5, COLT, 12, H);
  Check(AmmoMagCount(10, AK) = 0, 'body mode: the weapon brings only its magazine: ' + Hud(10, AK, Cap - 5));
  AmmoRespawn(8, T);
  Check(AmmoCanLoot(9, AK, 520, 260) = 0, 'the body is gone with the next life');
  ResetCounts;
  AmmoRespawn(11, T);
  Tick1(11, AK, Cap, COLT, 12, H);
  Hold(11, AK, Cap, H, 20);
  Check(AmmoLeftBehind(11, T, 700, 200) = AK, 'a team change leaves the AK');
  Check(AmmoCanLoot(9, AK, 700, 200) = 1, 'with its spare magazines (a body mode is for the dead)');
  AmmoSetBodyMode(0);
  AmmoConfig(1, 1, 1, 0, 1, 4, 2, 4, 45);

  { 38. the reload key and the fire key held together (an MP5): every magazine loaded is fired at once
    and taken out again - the reports say 0 all the time, the hook's shots prove the reloads: a round
    less each time }
  AmmoSetReserve(AK, 2 * Cap);
  ResetCounts;
  AmmoRespawn(12, T);
  Tick1(12, AK, Cap, COLT, 12, H);
  Hold(12, AK, Cap, H, 20);
  for G := 1 to 4 do
  begin
    AmmoShot(12, AK, T + 1);
    Hold(12, AK, 0, H or AMF_RELOAD, 150);
  end;
  Check((AmmoMagCount(12, AK) = 2) and (AmmoMagRounds(12, AK, 0) = Cap - 1) and (AmmoMagRounds(12, AK, 1) = Cap - 1),
    'a round less each time: ' + Hud(12, AK, 0));
  Check((Sets = 1) and (LastVal = Cap - 2), 'the partial magazine of the fourth time is set (' + IntToStr(LastVal) + ')');
  Check(AmmoShown(12, T, AK, 0) = 0, 'shown 0 while it reloads');
  Hold(12, AK, Cap, H, 20);
  Check((LastVal = Cap - 1) and (AmmoMagCount(12, AK) = 2) and (AmmoMagRounds(12, AK, 1) = Cap - 2),
    'the keys let go: the fullest one is loaded (' + IntToStr(LastVal) + '): ' + Hud(12, AK, Cap - 1));

  { 39. EmptyDrop = 0: a round that slipped through the reload of a dry weapon (its shot) is answered
    at once }
  AmmoConfig(1, 1, 0, 0, 1, 4, 2, 4, 45);
  AmmoSetReserve(AK, 0);
  ResetCounts;
  AmmoRespawn(13, T);
  Tick1(13, AK, Cap, COLT, 12, H);
  Hold(13, AK, Cap, H, 20);
  A := Fire(13, AK, Cap, 0, 10, H);
  Hold(13, AK, 0, H, 40);
  S0 := Sets;
  AmmoShot(13, AK, T + 1);
  Tick1(13, AK, 0, -1, -1, H);
  Check((Sets = S0 + 1) and (LastVal = 0) and (Drops = 0), 'a shot of a dry weapon: set to 0 at once');
  AmmoConfig(1, 1, 1, 0, 1, 4, 2, 4, 45);

  { 40. !mag <n>: a shot the client fired before it got the script's 0 proves no reload }
  AmmoSetReserve(AK, 2 * Cap);
  ResetCounts;
  AmmoRespawn(14, T);
  Tick1(14, AK, Cap, COLT, 12, H);
  Hold(14, AK, Cap, H, 20);
  Check(AmmoReloadNow(14, T, Cap) = 1, '!mag: the magazine is taken out');
  AmmoShot(14, AK, T + 1);
  Tick1(14, AK, Cap, -1, -1, H);
  Hold(14, AK, 0, H, 30);
  Check((AmmoMagCount(14, AK) = 2) and (Sets = 0), 'the shot fired before the 0 arrived loads nothing: ' +
    Hud(14, AK, 0));

  { 41. ExtraMagazines: a fresh AK (2 spare magazines) with ExtraMagazines = 1 loots one more from a body,
    then its pouch is full; with 0 a full pouch takes nothing; a dead soldier's weapon picked up brings
    no more than the limit }
  AmmoLimit(1);
  AmmoSetReserve(AK, 2 * Cap);
  AmmoSetBodyMode(1);
  ResetCounts;
  AmmoRespawn(15, T);
  Tick1(15, AK, Cap, COLT, 12, H);
  Hold(15, AK, Cap, H, 20);
  Check(AmmoDeath(15, T, 900, 200) = AK, 'dies with the AK (his two spare magazines at the body)');
  AmmoRespawn(16, T);
  Tick1(16, AK, Cap, COLT, 12, H);
  Hold(16, AK, Cap, H, 20);
  Check(AmmoCanLoot(16, AK, 900, 200) = 1, 'a full pouch may take one more (ExtraMagazines = 1)');
  Check(AmmoLoot(16, AK, 900, 200, 0) = Cap, 'one more looted');
  Check(AmmoMagCount(16, AK) = 3, 'three spare magazines now: ' + Hud(16, AK, Cap));
  Check(AmmoCanLoot(16, AK, 900, 200) = 0, 'then the pouch is full (the body still has one)');
  Check(AmmoLoot(16, AK, 900, 200, 0) = -1, 'looting again: full');
  AmmoLimit(0);
  AmmoRespawn(17, T);
  Tick1(17, AK, Cap, COLT, 12, H);
  Hold(17, AK, Cap, H, 20);
  Check(AmmoCanLoot(17, AK, 900, 200) = 0, 'ExtraMagazines = 0: a full pouch takes nothing');
  AmmoSetBodyMode(0);
  { a soldier with five spare magazines dies; his AK picked up with ExtraMagazines = 0 brings two (a fresh
    AK's) }
  AmmoLimit(-1);
  AmmoSetReserve(AK, 5 * Cap);
  ResetCounts;
  AmmoRespawn(18, T);
  Tick1(18, AK, Cap, COLT, 12, H);
  Hold(18, AK, Cap, H, 20);
  Check(AmmoMagCount(18, AK) = 5, 'five spare magazines');
  Check(AmmoDeath(18, T, 1100, 200) = AK, 'dies with the AK');
  AmmoDropped(18, 7, 76, T + 1);
  AmmoSetReserve(AK, 2 * Cap);
  AmmoLimit(0);
  AmmoRespawn(19, T);
  Tick1(19, 255, 0, COLT, 12, H);
  G := AmmoGroundNext(AK, 0);
  while (G >= 0) and (AmmoGroundSlot(G) <> 76) do
    G := AmmoGroundNext(AK, G + 1);
  Check(G >= 0, 'his AK lies there');
  AmmoPickFrom(19, T + 1, G);
  Tick1(19, AK, Cap, COLT, 12, H);
  Check(AmmoMagCount(19, AK) = 2, 'picked up: two spare magazines, not five: ' + Hud(19, AK, Cap));
  AmmoLimit(-1);

  { 42. SurvivalCarry: an AK with two spare magazines, five shots fired: kept at the round's end (his death then
    leaves the AK on the ground: taken away when confirmed); the next life's fresh AK is loaded with his fullest
    magazine (a full one), the pouch keeps the other full one and the partial one }
  AmmoSetReserve(AK, 2 * Cap);
  AmmoSetBodyMode(0);
  ResetCounts;
  AmmoRespawn(20, T);
  Tick1(20, AK, Cap, COLT, 12, H);
  Hold(20, AK, Cap, H, 20);
  A := Fire(20, AK, Cap, Cap - 5, 10, H);
  Hold(20, AK, A, H, 12);
  Check(AmmoLeftOf(20, AK, T) = 3 * Cap - 5, 'left of the AK: the gun and two magazines (' +
    IntToStr(AmmoLeftOf(20, AK, T)) + ')');
  Check(AmmoLeftOf(20, M79, T) = -1, 'a weapon never used: -1');
  AmmoCarrySave(20, T);
  Check(AmmoCarryKept(20) = 1, 'kept');
  Check(AmmoDeath(20, T, 1300, 200) = AK, 'the round''s end kills him');
  AmmoDropped(20, 7, 77, T + 1);
  Check(AmmoGroundHasSlot(77) = 1, 'his AK lies there');
  AmmoCarryConfirm(20);
  Check(AmmoGroundHasSlot(77) = 0, 'confirmed: it came over with him, not on the ground');
  AmmoRespawn(20, T);
  ResetCounts;
  Tick1(20, AK, Cap, COLT, 12, H);
  Check((Sets = 0) and (AmmoMagCount(20, AK) = 2) and (AmmoMagRounds(20, AK, 0) = Cap) and
    (AmmoMagRounds(20, AK, 1) = Cap - 5), 'the next life: loaded with a full one of his, the pouch ' + Hud(20, AK, Cap));
  { no full magazine left: his gun is loaded with his partial one (set) }
  AmmoSetReserve(AK, 0);
  ResetCounts;
  AmmoRespawn(21, T);
  Tick1(21, AK, Cap, COLT, 12, H);
  Hold(21, AK, Cap, H, 20);
  A := Fire(21, AK, Cap, Cap - 10, 10, H);
  Hold(21, AK, A, H, 12);
  AmmoCarrySave(21, T);
  AmmoDeath(21, T, 1400, 200);
  AmmoCarryConfirm(21);
  AmmoRespawn(21, T);
  ResetCounts;
  Tick1(21, AK, Cap, COLT, 12, H);
  Check((LastAct = AMA_SET) and (LastVal = Cap - 10) and (AmmoMagCount(21, AK) = 0),
    'loaded with his own partial magazine: ' + IntToStr(LastVal));
  { a death in the round: nothing kept }
  AmmoCarrySave(21, T);
  AmmoCarryDrop(21);
  AmmoSetReserve(AK, 2 * Cap);
  AmmoRespawn(21, T);
  ResetCounts;
  Tick1(21, AK, Cap, COLT, 12, H);
  Check((Sets = 0) and (AmmoMagCount(21, AK) = 2), 'dropped: a fresh AK and pouch');
  { 43. AmmoPause: his weapons away while he is down - nothing counts; given back the same, nothing changed }
  Hold(21, AK, Cap, H, 20);
  A := Fire(21, AK, Cap, Cap - 3, 10, H);
  Hold(21, AK, A, H, 12);
  S0 := AmmoGroundNext(AK, 0);
  AmmoPause(21, 1, T);
  Hold(21, 255, 0, H, 30);
  AmmoPause(21, 0, T);
  Hold(21, AK, Cap - 3, H, 30);
  Check((AmmoShown(21, T, AK, Cap - 3) = Cap - 3) and (AmmoMagCount(21, AK) = 2),
    'after the pause: the same magazine, the same pouch');
  Check(AmmoGroundNext(AK, 0) = S0, 'no weapon record made for his weapons taken away');

  { 44. [Shop]: spare magazines bought within ExtraMagazines; a full pouch takes none; the fresh set only
    when the pouch holds less }
  AmmoLimit(1);
  AmmoSetReserve(AK, 2 * Cap);
  ResetCounts;
  AmmoRespawn(22, T);
  Tick1(22, AK, Cap, COLT, 12, H);
  Hold(22, AK, Cap, H, 20);
  Check(AmmoMagCount(22, AK) = 2, 'a fresh AK: two spare magazines');
  Check(AmmoTopUp(22, AK) = 0, 'a fresh set already: no top-up');
  Check(AmmoAddMags(22, AK, 3) = 1, 'three bought: one fits (ExtraMagazines = 1)');
  Check(AmmoMagCount(22, AK) = 3, 'three spare magazines now');
  Check(AmmoAddMags(22, AK, 1) = 0, 'a full pouch takes none');
  AmmoLimit(0);
  Check(AmmoAddMags(22, AK, 1) = 0, 'ExtraMagazines = 0: none over the fresh set');
  AmmoLimit(-1);
  Check(AmmoAddMags(22, AK, 2) = 2, 'no limit (-1): two more');
  AmmoLimit(1);
  Check(AmmoAddMags(22, M79, 3) = 1, 'a pool weapon not in the hands: its fresh rounds and one magazine''s worth more');
  AmmoLimit(-1);

  { 45. a class's extra magazines: two more with the weapon he takes up, and two more over ExtraMagazines }
  AmmoLimit(1);
  ResetCounts;
  AmmoPlayerExtra(23, 2);
  AmmoRespawn(23, T);
  Tick1(23, AK, Cap, COLT, 12, H);
  Hold(23, AK, Cap, H, 20);
  Check(AmmoMagCount(23, AK) = 4, 'a class with mags 2: a fresh AK with four spare magazines');
  Check(AmmoAddMags(23, AK, 3) = 1, 'bought: one more fits (fresh 2 + ExtraMagazines 1 + the class''s 2)');
  AmmoPlayerExtra(23, 0);
  AmmoLimit(-1);

  { 46. round 26: the game finished a reload, the reports not believed yet (CONFIRM), and Q at once: the reload
    is paid before the AK goes away (it came back full and unpaid) }
  ResetCounts;
  AmmoRespawn(24, T);
  Tick1(24, AK, Cap, COLT, 12, H);
  Hold(24, AK, Cap, H, 20);
  A := Fire(24, AK, Cap, 0, 10, H);
  Hold(24, AK, 0, H, 40);
  Check(AmmoMagCount(24, AK) = 2, 'two spare magazines before the reload');
  Hold(24, AK, Cap, H, 3);
  Tick1(24, COLT, 12, AK, Cap, H);
  Hold(24, COLT, 12, H, 20);
  Tick1(24, AK, Cap, COLT, 12, H);
  Hold(24, AK, Cap, H, 20);
  Check(AmmoMagCount(24, AK) = 1, 'the reload before the swap was paid: one spare magazine left (' +
    IntToStr(AmmoMagCount(24, AK)) + ')');

  { 47. round 26: Q right after the game's reload, before any report of it: the AK comes back with the rounds it
    went away with (0) - its reload then takes a magazine }
  ResetCounts;
  AmmoRespawn(25, T);
  Tick1(25, AK, Cap, COLT, 12, H);
  Hold(25, AK, Cap, H, 20);
  A := Fire(25, AK, Cap, 0, 10, H);
  Hold(25, AK, 0, H, 40);
  Tick1(25, COLT, 12, AK, Cap, H);
  Hold(25, COLT, 12, H, 20);
  ResetCounts;
  Tick1(25, AK, Cap, COLT, 12, H);
  Check((LastAct = AMA_SET) and (LastVal = 0), 'the AK back with what it went away with (' + IntToStr(LastAct) +
    ', ' + IntToStr(LastVal) + ')');
  Check(AmmoMagCount(25, AK) = 2, 'no magazine taken by the swaps');
  Hold(25, AK, 0, H, 40);
  Hold(25, AK, Cap, H, 20);
  Check(AmmoMagCount(25, AK) = 1, 'its reload takes one');

  { 48. round 26: a refill (a bounty's reward) keeps a fuller pouch: it only tops up }
  AmmoLimit(1);
  ResetCounts;
  AmmoPlayerExtra(26, 2);
  AmmoRespawn(26, T);
  Tick1(26, AK, Cap, COLT, 12, H);
  Hold(26, AK, Cap, H, 20);
  Check(AmmoMagCount(26, AK) = 4, 'a class with mags 2: four spare magazines');
  AmmoRefill(26, AK);
  Check(AmmoMagCount(26, AK) = 4, 'a refill keeps all four (' + IntToStr(AmmoMagCount(26, AK)) + ')');
  AmmoPlayerExtra(26, 0);
  AmmoLimit(-1);

  { 49. round 26: EmptyDrop = 0 - the chainsaw still goes when its tank is empty (it cannot be kept at 0) }
  AmmoConfig(1, 1, 0, 0, 1, 4, 2, 4, 45);
  AmmoSetReserve(SAW, 40);
  ResetCounts;
  AmmoRespawn(27, T);
  Tick1(27, SAW, 200, COLT, 12, H);
  Hold(27, SAW, 200, H or AMF_SHOOT, 60);
  Check(LastAct = AMA_DROP, 'EmptyDrop = 0: the empty chainsaw goes');
  AmmoConfig(1, 1, 1, 0, 1, 4, 2, 4, 45);

  { 50. round 26 (D15): a body with only loose rounds (its soldier died while the AK had no magazines - MagazineMode
    0) - a looter with full magazines and room gets a magazine of them, then nothing is left; D8: the record's age }
  AmmoConfig(1, 0, 1, 0, 1, 4, 2, 4, 45);
  AmmoSetBodyMode(1);
  AmmoSetReserve(AK, 10);
  ResetCounts;
  AmmoRespawn(28, T);
  Tick1(28, AK, Cap, COLT, 12, H);
  Hold(28, AK, Cap, H, 20);
  Check(AmmoDeath(28, T, 1300, 200) = AK, 'dies with the AK (10 loose rounds)');
  AmmoConfig(1, 1, 1, 0, 1, 4, 2, 4, 45);
  AmmoSetReserve(AK, 2 * Cap);
  G := AmmoGroundNext(AK, 0);
  while (G >= 0) and (AmmoGroundDist(G, 1300, 200) > 5) do
    G := AmmoGroundNext(AK, G + 1);
  Check(G >= 0, 'his rounds lie at the body');
  Check(AmmoGroundAge(G, T + 100) = 100, 'the record is 100 ticks old (' + IntToStr(AmmoGroundAge(G, T + 100)) + ')');
  ResetCounts;
  AmmoRespawn(29, T);
  Tick1(29, AK, Cap, COLT, 12, H);
  Hold(29, AK, Cap, H, 20);
  Check(AmmoCanLoot(29, AK, 1300, 200) = 1, 'the loose rounds can be looted');
  R := AmmoLoot(29, AK, 1300, 200, 0);
  Check(R = 10, 'a magazine of the 10 loose rounds (' + IntToStr(R) + ')');
  Check(AmmoMagCount(29, AK) = 3, 'three spare magazines now: ' + Hud(29, AK, Cap));
  Check(AmmoCanLoot(29, AK, 1300, 200) = 0, 'nothing left there');
  AmmoSetBodyMode(0);

  { 51. 4.2: the first Q after a respawn - the secondary comes into the hands with its full set at once (its pouch was
    made only a tick later, and the line drawn in the swap's own tick said "empty" until the first shot); also with
    the spare magazines of ExtraMagazines and a class }
  AmmoLimit(1);
  AmmoPlayerExtra(5, 1);
  ResetCounts;
  AmmoRespawn(5, T);
  Tick1(5, AK, Cap, COLT, 12, H);
  Hold(5, AK, Cap, H, 20);
  Check(AmmoMagCount(5, COLT) = 0, 'the secondary is not touched while it is away');
  Tick1(5, COLT, 12, AK, Cap, H);
  G := AmmoMagCount(5, COLT);
  Check(G >= 2, 'the secondary has its set in the swap tick (' + IntToStr(G) + ')');
  Check(Pos('empty', Hud(5, COLT, 12)) = 0, 'the line is not empty after the first Q: ' + Hud(5, COLT, 12));
  Hold(5, COLT, 12, H, 20);
  Check(AmmoMagCount(5, COLT) = G, 'the set stays as it was (' + IntToStr(AmmoMagCount(5, COLT)) + ')');
  Tick1(5, AK, Cap, COLT, 12, H);
  Hold(5, AK, Cap, H, 20);
  Tick1(5, COLT, 12, AK, Cap, H);
  Check(AmmoMagCount(5, COLT) = G, 'the second Q changes nothing (' + IntToStr(AmmoMagCount(5, COLT)) + ')');
  Check(Sets + Drops = 0, 'the swaps change nothing');
  AmmoPlayerExtra(5, 0);
  AmmoLimit(-1);

  { 52. 4.2: the ammunition line drawn before the library had the weapon (a respawn, a weapon given a tick later): no "empty" for
    a pouch that was never made, and one more mark when the library has the weapon - never again while nothing changes }
  AmmoLimit(-1);
  CA := Weapon[COLT].Ammo;
  ResetCounts;
  AmmoRespawn(8, T);
  Check(AmmoHandW(8) = 255, 'a new life follows no weapon');
  Check(AmmoDrawn(8, AK) = 0, 'the line drawn for the AK before the library has it');
  Check(Hud(8, AK, Cap) = ' | Ammo: ' + IntToStr(Cap), 'an unmade pouch is no empty one: ' + Hud(8, AK, Cap));
  Check(Pos('empty', Hud(8, COLT, CA)) = 0, 'nor the secondary: ' + Hud(8, COLT, CA));
  R := TickR(8, AK, Cap, COLT, CA, H);
  Check(R = AMA_HUD, 'the change of weapon marks the line');
  Check(AmmoHandW(8) = AK, 'the library follows the AK');
  Check(Draw(8, AK, Cap) = ' | Ammo: ' + IntToStr(Cap) + ' [' + IntToStr(Cap) + ', ' + IntToStr(Cap) + ']',
    'the line when the library has the weapon: ' + Hud(8, AK, Cap));
  Check(AmmoDrawn(8, AK) = 1, 'drawn for the weapon the library follows');
  G := 0;
  for A := 1 to 40 do
    if TickR(8, AK, Cap, -1, -1, H) = AMA_HUD then
    begin
      Inc(G);
      WriteLn('  mark at +', A);
    end;
  Check(G = 0, 'nothing changes: no more marks (' + IntToStr(G) + ')');
  { drawn before the library had the weapon, no change of weapon seen since (the script missed a mark): marked once }
  AmmoRespawn(9, T);
  AmmoDrawn(9, AK);
  Check(TickR(9, AK, Cap, COLT, CA, H) = AMA_HUD, 'the change marks it');
  AmmoShown(9, T, AK, Cap);
  G := 0;
  for A := 1 to 20 do
    if TickR(9, AK, Cap, -1, -1, H) = AMA_HUD then
      Inc(G);
  Check(G = 1, 'a line drawn before the weapon was followed is marked once more (' + IntToStr(G) + ')');
  Check(Draw(9, AK, Cap) <> '', 'the script draws it');
  G := 0;
  for A := 1 to 20 do
    if TickR(9, AK, Cap, -1, -1, H) = AMA_HUD then
      Inc(G);
  Check(G = 0, 'and then it is quiet (' + IntToStr(G) + ')');
  { the line shows the weapon he put away: marked once, until it is drawn for the weapon in his hands }
  AmmoDrawn(9, COLT);
  Check(TickR(9, AK, Cap, -1, -1, H) = AMA_HUD, 'a line drawn for another weapon is marked');
  Check(TickR(9, AK, Cap, -1, -1, H) = AMA_NONE, 'once');
  Check(AmmoDrawn(9, 255) = 1, 'no weapon: nothing of the library in the line');
  Check(TickR(9, AK, Cap, -1, -1, H) = AMA_HUD, 'drawn when he had no weapon: marked when he has one');
  { no line wanted for him (off, spectator): never marked }
  AmmoDrawn(9, -3);
  G := 0;
  for A := 1 to 20 do
    if TickR(9, AK, Cap, -1, -1, H) = AMA_HUD then
      Inc(G);
  Check(G = 0, 'a player without the line is never marked (' + IntToStr(G) + ')');
  { he is down: nothing is looked at; the line drawn without a weapon is marked when he is up with it }
  AmmoDrawn(9, 255);
  AmmoPause(9, 1, T);
  Check(TickR(9, 255, 0, -1, -1, H) = AMA_NONE, 'paused: nothing');
  AmmoPause(9, 0, T);
  Check(TickR(9, AK, Cap, -1, -1, H) = AMA_HUD, 'up again: the line is drawn again');

  { 53. 4.2: a survivor's round start as the game gives it - the game's own weapon first, his weapon a few ticks later, both
    not swaps - and two swaps with the secondary: his AK keeps its spare magazines all along and every line drawn is
    his weapon's own }
  AmmoPlayerExtra(10, 0);
  ResetCounts;
  AmmoRespawn(10, T);
  Tick1(10, AK, Cap, COLT, CA, H);
  Hold(10, AK, Cap, H, 20);
  Tick1(10, AK, Cap - 1, COLT, CA, H);
  Hold(10, AK, Cap - 1, H, 30);
  Tick1(10, COLT, CA, AK, Cap - 1, H);
  Hold(10, COLT, CA, H, 30);
  AmmoCarrySave(10, T);
  AmmoCarryConfirm(10);
  AmmoRespawn(10, T);
  Check(AmmoHandW(10) = 255, 'the new round: no weapon yet');
  R := TickR(10, SPAS, Weapon[SPAS].Ammo, 255, 0, H);
  Check(R = AMA_HUD, 'the game gives him a Spas first');
  Check(Draw(10, SPAS, Weapon[SPAS].Ammo) <> '', 'a line for it');
  Hold(10, SPAS, Weapon[SPAS].Ammo, H, 2);
  R := TickR(10, AK, Cap, COLT, CA, H);
  Check(R = AMA_HUD, 'his AK comes in');
  S0 := AmmoMagCount(10, AK);
  Check(S0 >= 2, 'the AK has its spare magazines (' + IntToStr(S0) + ')');
  Check(Draw(10, AK, Cap) = ' | Ammo: ' + IntToStr(Cap) + ' [' + IntToStr(Cap) + ', ' + IntToStr(Cap - 1) + ']',
    'the AK line: ' + Draw(10, AK, Cap));
  Hold(10, AK, Cap, H, 40);
  R := TickR(10, COLT, CA, AK, Cap, H);
  Check(R = AMA_HUD, 'the first Q (' + IntToStr(R) + ', value ' + IntToStr(LastVal) + ')');
  Check(Pos('empty', Draw(10, COLT, CA)) = 0, 'the secondary is not empty: ' + Draw(10, COLT, CA));
  Hold(10, COLT, CA, H, 40);
  R := TickR(10, AK, Cap, COLT, CA, H);
  Check(R = AMA_HUD, 'and back');
  Check(Draw(10, AK, Cap) = ' | Ammo: ' + IntToStr(Cap) + ' [' + IntToStr(Cap) + ', ' + IntToStr(Cap - 1) + ']',
    'the AK line after the swaps: ' + Draw(10, AK, Cap));
  Check(AmmoMagCount(10, AK) = S0, 'no magazine lost over the swaps');
  Hold(10, AK, Cap, H, 40);
  Check(Sets + Drops = 0, 'the swaps set nothing (' + IntToStr(Sets + Drops) + ')');

  { 54. 4.2 [Looting] Markers: the loot points he could take something from with the weapon in his hands, in range, nearest
    first, at most Max }
  AmmoSetBodyMode(0);
  AmmoLimit(-1);
  AmmoGroundClear;
  for k := 20 to 22 do
  begin
    AmmoRespawn(k, T);
    Tick1(k, AK, Cap, COLT, CA, H);
    Hold(k, AK, Cap, H, 20);
  end;
  AmmoRespawn(24, T);
  Tick1(24, AK, Cap, COLT, CA, H);
  Hold(24, AK, Cap, H, 20);
  Check(AmmoDeath(20, T, 1100, 200) = AK, 'three soldiers die with their AK: one at 100 px');
  Check(AmmoDeath(21, T, 1300, 200) = AK, 'one at 300 px');
  Check(AmmoDeath(22, T, 1000, 700) = AK, 'one at 500 px (down)');
  R := AmmoLootMarks(24, AK, 1000, 200, 1000, 185, 600, 4);
  Check(R = 3, 'three loot points within 600 px (' + IntToStr(R) + ')');
  AmmoLootMarkOp(0, G, MX, MY, D);
  Check((D = 100) and (Round(MX) = 1100) and (Round(MY) = 200) and (G >= 0), 'the nearest first: ' + IntToStr(D));
  AmmoLootMarkOp(2, G, MX, MY, D);
  Check(D = 500, 'the farthest last: ' + IntToStr(D));
  AmmoLootMarkOp(3, G, MX, MY, D);
  Check((G = -1) and (D = 0), 'past the count: nothing');
  Check(AmmoLootMarks(24, AK, 1000, 200, 1000, 185, 600, 2) = 2, 'at most Max');
  Check(AmmoLootMarks(24, AK, 1000, 200, 1000, 185, 350, 4) = 2, 'MaxDist 350: two');
  Check(AmmoLootMarks(24, AK, 1000, 200, 1000, 185, 50, 4) = 0, 'MaxDist 50: none');
  Check(AmmoLootMarks(24, COLT, 1000, 200, 1000, 185, 600, 4) = 0, 'the weapon of another kind in his hands: the AKs are no use to him');
  Check(AmmoLootMarks(24, SAW, 1000, 200, 1000, 185, 600, 4) = 0, 'the chainsaw loots nothing');
  Check(AmmoLootMarks(24, 255, 1000, 200, 1000, 185, 600, 4) = 0, 'no weapon: nothing');
  AmmoLootMarks(24, AK, 1000, 200, 1000, 185, 600, 4);
  AmmoLootMarkOp(0, G, MX, MY, D);
  Check(AmmoCanLoot(24, AK, MX, MY) = 1, 'what is marked can be looted');
  { the pouch full of whole magazines: nothing to take, no marker }
  AmmoAddMags(24, AK, 12);
  Check(AmmoLootMarks(24, AK, 1000, 200, 1000, 185, 600, 4) = 0, 'a full pouch: no markers');
  Check(AmmoCanLoot(24, AK, 1100, 200) = 0, 'and nothing to loot');
  AmmoRespawn(24, T);
  Tick1(24, AK, Cap, COLT, CA, H);
  { the record is taken: no marker }
  Check(AmmoLootMarks(24, AK, 1100, 200, 1100, 185, 20, 4) = 1, 'standing over the first one');
  AmmoLootMarkOp(0, G, MX, MY, D);
  S0 := G;
  while AmmoLoot(24, AK, 1100, 200, 0) > 0 do ;
  Check(AmmoLootMarks(24, AK, 1100, 200, 1100, 185, 20, 4) = 0, 'looted empty: the marker is gone');
  { the loot lies where the record is: a weapon's object slides, a body is moved }
  AmmoLootMarkOp(0, G, MX, MY, D);
  Check(AmmoLootMarks(24, AK, 1000, 200, 1000, 185, 600, 4) = 2, 'two left');
  AmmoLootMarkOp(1, G, MX, MY, D);
  AmmoGroundMove(G, 1500, 260);
  Check(AmmoLootMarks(24, AK, 1000, 200, 1000, 185, 600, 4) = 2, 'the weapon slid: still marked');
  AmmoLootMarkOp(1, G, MX, MY, D);
  Check((Round(MX) = 1500) and (Round(MY) = 260), 'at the new place');
  { a record that was too long on the ground is not offered }
  Check(AmmoLootMarks(24, AK, 5000, 200, 5000, 185, 100, 4) = 0, 'nothing near');
  { with a map: a wall between his eyes and the loot hides it }
  if MapLoad(ParamStr(1)) > 0 then
  begin
    AmmoGroundClear;
    Found := False;
    for k := 0 to 2 do
      for n := 0 to 15 do
        if not Found then
        begin
          if k = 0 then
          begin
            AX := 380;
            AY := -100;
          end
          else if k = 1 then
          begin
            AX := -285;
            AY := -290;
          end
          else
          begin
            AX := 0;
            AY := -200;
          end;
          DX := Cos(n * Pi / 8);
          DY := Sin(n * Pi / 8);
          if (not MapPointSolid(AX, AY, 0, 0)) and (not MapRay(AX, AY, AX + DX * 40, AY + DY * 40, 0, 0)) and
            (not MapPointSolid(AX + DX * 700, AY + DY * 700, 0, 0)) and MapRay(AX, AY, AX + DX * 700, AY + DY * 700, 0, 0) then
            Found := True;
        end;
    Check(Found, 'a wall between two open points on the map');
    if Found then
    begin
      { the point of the last try is the found one: A open, near open at 40 px, far behind a wall at 700 px }
      AmmoRespawn(25, T);
      Tick1(25, AK, Cap, COLT, CA, H);
      Hold(25, AK, Cap, H, 20);
      AmmoRespawn(26, T);
      Tick1(26, AK, Cap, COLT, CA, H);
      Hold(26, AK, Cap, H, 20);
      AmmoDeath(25, T, AX + DX * 40, AY + DY * 40 + 4);
      AmmoDeath(26, T, AX + DX * 700, AY + DY * 700 + 4);
      R := AmmoLootMarks(24, AK, AX, AY, AX, AY, 1000, 4);
      Check(R = 1, 'the loot behind the wall is not marked (' + IntToStr(R) + ')');
      AmmoLootMarkOp(0, G, MX, MY, D);
      Check(D < 60, 'the open one is');
      { what a call costs with the worst case of 16 loot points around (each needs its ray) }
      for k := 1 to 16 do
      begin
        AmmoRespawn(k, T);
        Tick1(k, AK, Cap, COLT, CA, H);
        Hold(k, AK, Cap, H, 4);
        AmmoDeath(k, T, AX + DX * 3 * (k + 2), AY + DY * 3 * (k + 2) + 4);
      end;
      Rays := 0;
      Stamp := GetTickCount64;
      for n := 1 to 5000 do
        Rays := Rays + AmmoLootMarks(24, AK, AX, AY, AX, AY, 1000, 6);
      Stamp := GetTickCount64 - Stamp;
      WriteLn('loot markers: ', Stamp * 1000 div 5000, ' microseconds a call (18 points, ', Rays div 5000, ' marked)');
      MapClear;
      R := AmmoLootMarks(24, AK, AX, AY, AX, AY, 1000, 4);
      Check(R = 4, 'without a map nothing is hidden (' + IntToStr(R) + ')');
    end;
  end
  else
    WriteLn('(no map: the line of sight is not tried)');

  { 4.2 KeepWeapons: a dead soldier's weapon with spare magazines is forgotten after the game's 90 s - unless the keeper
    holds its object: then the record lasts as long as the object, and follows the weapon when it is made again (an
    object of another slot) }
  AmmoGroundClear;
  AmmoGroundKeep(0);
  AmmoRespawn(30, T);
  Tick1(30, AK, Cap, COLT, 12, H);
  Hold(30, AK, Cap, H, 20);
  Check(AmmoDeath(30, T, 2000, 200) = AK, 'keep 1: a soldier dies with his AK');
  Check(AmmoGroundAttach(30, AK, 45, 1, T) = 1, 'keep 1: the AK has its object');
  AmmoRespawn(31, T);
  Tick1(31, AK, Cap, COLT, 12, H);
  Check(AmmoCanLoot(31, AK, 2000, 200) = 1, 'keep 1: lootable now');
  T := T + 6000;
  Tick1(31, AK, Cap, COLT, 12, H);
  Check(AmmoCanLoot(31, AK, 2000, 200) = 0, 'keep 1: without the keeper the record is forgotten after 90 s');
  AmmoGroundKeep(1);
  AmmoRespawn(32, T);
  Tick1(32, AK, Cap, COLT, 12, H);
  Hold(32, AK, Cap, H, 20);
  Check(AmmoDeath(32, T, 2100, 200) = AK, 'keep 2: another soldier dies with his AK');
  Check(AmmoGroundAttach(32, AK, 46, 1, T) = 1, 'keep 2: the AK has its object');
  Tick1(31, AK, Cap, COLT, 12, H);
  T := T + 6000;
  Tick1(31, AK, Cap, COLT, 12, H);
  Check(AmmoCanLoot(31, AK, 2100, 200) = 1, 'keep 2: with the keeper the record whose object is known stays');
  Check(AmmoGroundRebind(46, 47, 2150, 210) = 1, 'keep 2: the weapon is made again as object 47');
  Check((AmmoGroundHasSlot(47) = 1) and (AmmoGroundHasSlot(46) = 0), 'keep 2: the record follows it');
  Check(AmmoCanLoot(31, AK, 2150, 210) = 1, 'keep 2: and lies where it was made again');
  Check(AmmoGroundRebind(46, 48, 0, 0) = 0, 'keep 2: an object nobody knows is left alone');
  Check(AmmoGroundRebind(0, 48, 0, 0) = 0, 'keep 2: object 0 is nothing');
  AmmoGroundKeep(0);
  Tick1(31, AK, Cap, COLT, 12, H);
  Check(AmmoCanLoot(31, AK, 2150, 210) = 0, 'keep 3: the keeper off again: the old record goes with its age');

  { 55. 4.2: Q while an empty AK is kept at 0 (EmptyDrop = 0). His game swaps the weapons at once; the server hears of it
    only with the game's next full report (every 7 ticks, or later when it is late or lost) and until then still
    shows the AK in his hands. A set now would be Player.Primary.Ammo := 0 = a ForceWeapon of the server's arrangement
    (the AK in the hands, the USSOCOM away): it would undo his swap. So nothing is set while the change key was seen a
    moment ago; the empty AK went into the secondary place - nothing to set any more. }
  AmmoConfig(1, 1, 0, 0, 1, 4, 2, 4, 45);
  AmmoSetReserve(AK, 0);
  ResetCounts;
  AmmoRespawn(26, T);
  Tick1(26, AK, Cap, COLT, 12, H);
  Hold(26, AK, Cap, H, 20);
  A := Fire(26, AK, Cap, 0, 10, H);
  Hold(26, AK, 0, H, 40);
  Check((Sets >= 1) and (Drops = 0), 'the empty AK is kept at 0 (' + IntToStr(Sets) + ')');
  ResetCounts;
  Hold(26, AK, 0, H or AMF_CHANGE, 5);
  Hold(26, AK, 0, H, 6);
  { the server's own reload of the AK it still has shows rounds: before 4.2 answered at once }
  Hold(26, AK, Cap, H, 2);
  Hold(26, AK, 0, H, 12);
  Check(Sets + Drops = 0, 'no set while his swap may be on its way (' + IntToStr(Sets) + ' sets)');
  Tick1(26, COLT, 12, AK, 0, H);
  Hold(26, COLT, 12, H, 80);
  Check(Sets + Drops = 0, 'the swap came: the set that waited is not sent (' + IntToStr(Sets) + ')');
  { no swap came (the key did nothing): the set waits only so long }
  Tick1(26, AK, 0, COLT, 12, H);
  Hold(26, AK, 0, H, 40);
  ResetCounts;
  Hold(26, AK, 0, H or AMF_CHANGE, 3);
  Hold(26, AK, Cap, H, 2);
  Hold(26, AK, 0, H, 30);
  Check(Sets = 0, 'the set waits after the key (' + IntToStr(Sets) + ')');
  Hold(26, AK, 0, H, 30);
  Check((Sets >= 1) and (LastVal = 0), 'and comes after the wait when the server still shows the AK (' + IntToStr(Sets) +
    ')');
  { a bullet of the USSOCOM while the server still shows the AK: his game has swapped (the key itself may never
    reach the server - a short tap between two reports) }
  Hold(26, AK, 0, H, 40);
  ResetCounts;
  AmmoShot(26, COLT, T + 1);
  Tick1(26, AK, 0, -1, -1, H);
  Hold(26, AK, Cap, H, 2);
  Hold(26, AK, 0, H, 20);
  Check(Sets = 0, 'a bullet of the other weapon: no set (' + IntToStr(Sets) + ')');
  { a bot changes its weapons in the server itself: nothing waits }
  ResetCounts;
  AmmoRespawn(27, T);
  Tick1(27, AK, Cap, COLT, 12, 0);
  Hold(27, AK, Cap, 0, 20);
  A := Fire(27, AK, Cap, 0, 10, AMF_CHANGE);
  Hold(27, AK, 0, AMF_CHANGE, 9);
  Check(Drops = 1, 'a bot''s empty weapon still goes at once');
  AmmoConfig(1, 1, 1, 0, 1, 4, 2, 4, 45);
  AmmoSetReserve(AK, 2 * Cap);

  { 56. 4.2: the USSOCOM fired, Q, the AK's first bullet in the same tick as the report that brings the AK (a loaded
    server takes all the packets that came in one go): the report's count was sent before that shot - it comes off;
    the next report (with the shots) is taken at once }
  ResetCounts;
  AmmoRespawn(28, T);
  Tick1(28, COLT, 12, AK, Cap, H);
  Hold(28, COLT, 12, H, 20);
  A := Fire(28, COLT, 12, 9, 24, H);
  AmmoShot(28, AK, T + 1);
  Tick1(28, AK, Cap, COLT, 9, H);
  Check(AmmoShown(28, T, AK, Cap) = Cap - 1, 'the AK''s bullet of the change''s tick is shown (' +
    IntToStr(AmmoShown(28, T, AK, Cap)) + ')');
  Hold(28, AK, Cap, H, 4);
  AmmoShot(28, AK, T + 1);
  Tick1(28, AK, Cap, -1, -1, H);
  Check(AmmoShown(28, T, AK, Cap) = Cap - 2, 'the next one too (' + IntToStr(AmmoShown(28, T, AK, Cap)) + ')');
  Hold(28, AK, Cap - 2, H, 3);
  Check(AmmoShown(28, T, AK, Cap - 2) = Cap - 2, 'the report with both shots is taken at once (' +
    IntToStr(AmmoShown(28, T, AK, Cap - 2)) + ')');
  Hold(28, AK, Cap - 2, H, 30);
  Check((AmmoShown(28, T, AK, Cap - 2) = Cap - 2) and (Sets + Drops = 0), 'and stays (' +
    IntToStr(AmmoShown(28, T, AK, Cap - 2)) + ')');
  { the AK's bullet a tick before the report that brings it: that report was sent after the shot - nothing comes off }
  Tick1(28, COLT, 9, AK, Cap - 2, H);
  Hold(28, COLT, 9, H, 30);
  AmmoShot(28, AK, T + 1);
  Tick1(28, COLT, 9, -1, -1, H);
  Tick1(28, AK, Cap - 3, COLT, 9, H);
  Check(AmmoShown(28, T, AK, Cap - 3) = Cap - 3, 'a bullet before the report: in its count already (' +
    IntToStr(AmmoShown(28, T, AK, Cap - 3)) + ')');
  Hold(28, AK, Cap - 3, H, 30);
  Check((AmmoShown(28, T, AK, Cap - 3) = Cap - 3) and (Sets + Drops = 0), 'and stays (' +
    IntToStr(AmmoShown(28, T, AK, Cap - 3)) + ')');
  { the AK's bullet in the tick after the change: the server's copy of his report (the change's count) does not take it
    back }
  Tick1(28, COLT, 9, AK, Cap - 3, H);
  Hold(28, COLT, 9, H, 30);
  Tick1(28, AK, Cap - 3, COLT, 9, H);
  AmmoShot(28, AK, T + 1);
  Tick1(28, AK, Cap - 3, -1, -1, H);
  Hold(28, AK, Cap - 3, H, 3);
  Check(AmmoShown(28, T, AK, Cap - 3) = Cap - 4, 'a bullet the tick after the change is shown (' +
    IntToStr(AmmoShown(28, T, AK, Cap - 3)) + ')');
  Hold(28, AK, Cap - 4, H, 30);
  Check((AmmoShown(28, T, AK, Cap - 4) = Cap - 4) and (Sets + Drops = 0), 'and the reports agree (' +
    IntToStr(AmmoShown(28, T, AK, Cap - 4)) + ')');

  { 58. a set that waits (the change key held as the game's reload of the last, partial magazine is believed): it comes
    once he is settled, less the shots he fired meanwhile from the full magazine his game loaded }
  AmmoSetReserve(AK, Cap);
  ResetCounts;
  AmmoRespawn(25, T);
  Tick1(25, AK, Cap, COLT, 12, H);
  Hold(25, AK, Cap, H, 20);
  A := Fire(25, AK, Cap, Cap - 10, 10, H);
  Hold(25, AK, A, H, 12);
  Hold(25, AK, 0, H or AMF_RELOAD, 2);
  Hold(25, AK, 0, H, 100);
  Hold(25, AK, Cap, H, 20);
  A := Fire(25, AK, Cap, 0, 10, H);
  Hold(25, AK, 0, H, 100);
  Hold(25, AK, Cap, H or AMF_CHANGE, 9);
  Check(Sets = 0, 'the partial magazine waits while the change key is held');
  AmmoShot(25, AK, T + 1);
  Hold(25, AK, Cap, H, 5);
  AmmoShot(25, AK, T + 1);
  Hold(25, AK, Cap - 2, H, 50);
  Check((Sets = 1) and (LastVal = Cap - 12), 'and comes once he is settled, less his two shots (' + IntToStr(Sets) + ', ' +
    IntToStr(LastVal) + ')');
  AmmoSetReserve(AK, 2 * Cap);

  { 57. 4.2: two bullets of the AK made in one tick (the server took the packets of two of his ticks in one go) are two
    shots; the Spas-12's pellets and the second bullet of the Desert Eagles are one shot }
  ResetCounts;
  AmmoRespawn(29, T);
  Tick1(29, AK, Cap, COLT, 12, H);
  Hold(29, AK, Cap, H, 20);
  AmmoShot(29, AK, T + 1);
  AmmoShot(29, AK, T + 1);
  Tick1(29, AK, Cap, -1, -1, H);
  Check(AmmoShown(29, T, AK, Cap) = Cap - 2, 'two AK bullets in one tick are two shots (' +
    IntToStr(AmmoShown(29, T, AK, Cap)) + ')');
  Hold(29, AK, Cap - 2, H, 30);
  AmmoSetReserve(SPAS, 3);
  Tick1(29, SPAS, Weapon[SPAS].Ammo, AK, Cap - 2, H);
  Hold(29, SPAS, Weapon[SPAS].Ammo, H, 30);
  for k := 1 to 6 do
    AmmoShot(29, SPAS, T + 1);
  Tick1(29, SPAS, Weapon[SPAS].Ammo, -1, -1, H);
  Check(AmmoShown(29, T, SPAS, Weapon[SPAS].Ammo) = Weapon[SPAS].Ammo - 1, 'the Spas-12''s pellets are one shot (' +
    IntToStr(AmmoShown(29, T, SPAS, Weapon[SPAS].Ammo)) + ')');
  AmmoRespawn(29, T);
  Tick1(29, 1, Weapon[1].Ammo, COLT, 12, H);
  Hold(29, 1, Weapon[1].Ammo, H, 20);
  AmmoShot(29, 1, T + 1);
  AmmoShot(29, 1, T + 1);
  Tick1(29, 1, Weapon[1].Ammo, -1, -1, H);
  Check(AmmoShown(29, T, 1, Weapon[1].Ammo) = Weapon[1].Ammo - 1, 'the Desert Eagles'' two bullets are one shot (' +
    IntToStr(AmmoShown(29, T, 1, Weapon[1].Ammo)) + ')');

  WriteLn(Checks, ' checks, ', Fails, ' failed');
  WriteLn(AmmoStatus);
  if Fails > 0 then
    Halt(1);
end.
