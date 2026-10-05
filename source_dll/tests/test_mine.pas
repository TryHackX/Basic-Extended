program test_mine;

{ [Mines] (be_mine) without the server: soldiers stand where the test puts them (a simple skeleton,
  standing or low, on the ground or in the air), shots are fed as the hook would feed them, and the
  events and the marks are checked. No map is loaded: nothing stands in the way. }

{$mode objfpc}{$H+}

uses
  SysUtils, be_hook, be_mine, be_texts;

var
  PX, PY: array[1..32] of Single;
  Low, Unknown: array[1..32] of Boolean;
  Failed, Passed: LongInt;

{ the points of the test's soldier: feet at PX, PY; the right leg (5 hip, 4 knee, 1 foot, 17 toes) to the
  left of his middle, the left one (6, 3, 2, 18) to the right; standing or low (crouching, lying) }
function FakePoint(ID, K: LongInt; out X, Y: Single): Boolean;
var
  U: Single;
begin
  Result := not Unknown[ID];
  X := PX[ID];
  Y := PY[ID];
  if not Result then
    Exit;
  case K of
    1: begin X := PX[ID] - 2; U := 1; end;
    2: begin X := PX[ID] + 2; U := 1; end;
    17: begin X := PX[ID] - 4; U := 0; end;
    18: begin X := PX[ID] + 4; U := 0; end;
    4: begin X := PX[ID] - 2; if Low[ID] then U := 3 else U := 6; end;
    3: begin X := PX[ID] + 2; if Low[ID] then U := 3 else U := 6; end;
    5: begin X := PX[ID] - 1; if Low[ID] then U := 4 else U := 11; end;
    6: begin X := PX[ID] + 1; if Low[ID] then U := 4 else U := 11; end;
    7: if Low[ID] then U := 5 else U := 13;
    9: if Low[ID] then U := 8 else U := 18;
    12: if Low[ID] then U := 9 else U := 20;
  else
    U := 10;
  end;
  Y := PY[ID] - U;
end;

procedure Check(Ok: Boolean; const What: string);
begin
  if Ok then
  begin
    Inc(Passed);
    WriteLn('ok   ', What);
  end
  else
  begin
    Inc(Failed);
    WriteLn('FAIL ', What);
  end;
end;

procedure Put(ID, Team: LongInt; X, Y: Single; IsLow, Alive: Boolean);
begin
  PX[ID] := X;
  PY[ID] := Y;
  Low[ID] := IsLow;
  if Alive then
    MnPlayer(ID, Team, 1)
  else
    MnPlayer(ID, Team, 0);
end;

procedure Away(ID: LongInt);
begin
  PX[ID] := 5000;
  PY[ID] := 5000;
end;

procedure Shot(Owner: LongInt; X, Y, VX, VY: Single);
var
  E: TShotEvent;
begin
  E.Tick := 0;
  E.Slot := 1;
  E.Owner := Owner;
  E.W := 3;
  E.Style := 1;
  E.X := X;
  E.Y := Y;
  E.VX := VX;
  E.VY := VY;
  E.Script := False;
  MnQueueShot(E);
end;

var
  EvKind, EvId, EvP, EvQ: array[0..127] of LongInt;
  EvN: LongInt;

{ one tick: the script tells the crouch and prone keys (here the test's Low), then the events it brought }
procedure Run(Tick: LongInt);
var
  n, k, a, b, c, d: LongInt;
begin
  for k := 1 to 32 do
    if Low[k] then
      MnLow(k, 1)
    else
      MnLow(k, 0);
  n := MnTick(Tick);
  EvN := 0;
  for k := 1 to n do
    if MnNext(a, b, c, d) then
    begin
      EvKind[EvN] := a;
      EvId[EvN] := b;
      EvP[EvN] := c;
      EvQ[EvN] := d;
      Inc(EvN);
    end;
end;

function Has(Kind, Id, P: LongInt): Boolean;
var
  k: LongInt;
begin
  Result := False;
  for k := 0 to EvN - 1 do
    if EvKind[k] = Kind then
      if (Id < 0) or (EvId[k] = Id) then
        if (P < 0) or (EvP[k] = P) then
          Result := True;
end;

{ an event of Kind for Id and P with this Q }
function HasQ(Kind, Id, P, Q: LongInt): Boolean;
var
  k: LongInt;
begin
  Result := False;
  for k := 0 to EvN - 1 do
    if (EvKind[k] = Kind) and (EvId[k] = Id) and (EvP[k] = P) and (EvQ[k] = Q) then
      Result := True;
end;

function OpText(k: LongInt): string;
begin
  Result := Ops[k].Text;
end;

var
  i, M1, M2, M3, C1, n, More, T, Kind, Owner, Team: LongInt;
  X, Y, FX, FY, D: Single;

begin
  Failed := 0;
  Passed := 0;
  MnPoint := @FakePoint;
  MnBridge := False;
  MnSet(MNC_ON, 1);
  MnSet(MNC_ARM, 60);
  MnSet(MNC_LIFE, 0);
  MnSet(MNC_TRIG_R, 16);
  MnSet(MNC_TRIG_H, 8);
  MnSet(MNC_FUSE, FUSE_WIRE);
  MnSet(MNC_WIRE_LEN, 160);
  MnSet(MNC_WIRE_H, 5);
  MnSet(MNC_TOUCH, 14);
  MnSet(MNC_SPOT, 70);
  MnSet(MNC_DEFUSE_R, 40);
  MnSet(MNC_DEFUSE_T, 180);
  MnSet(MNC_PICK_T, 90);
  MnSet(MNC_SHOOT_CLAY, 1);
  MnSet(MNC_SHOOT_LAND, 0);
  MnSet(MNC_SEEN_LAND, 1);
  MnSet(MNC_SEEN_CLAY, 2);
  MnSet(MNC_LAYER, 133);
  MnSet(MNC_LAYERS, 16);
  MnSet(MNC_PREVIEW, 0);
  MnSet(MNC_SIGHT, SIGHT_EYES);
  for i := 1 to 32 do
  begin
    Unknown[i] := False;
    Away(i);
    MnHuman(i, 1);
  end;

  { 1. a landmine of 1 (team 1) at 0, 0: armed after 60 ticks; an enemy 2 far away, then on it }
  Put(1, 1, -300, 0, False, True);
  Put(2, 2, 200, 0, False, True);
  Put(3, 1, 300, 0, False, True);
  M1 := MnPlant(MN_LAND, 1, 1, 0, 0, 0, 0, 100);
  Check(M1 > 0, 'a landmine is planted');
  Check(MnCount(1, MN_LAND) = 1, 'the owner has one landmine');
  PX[2] := 5;
  Run(120);
  Check(not Has(MNE_TRIGGER, M1, -1), 'not armed yet: an enemy on it sets nothing off');
  Away(2);
  Run(160);
  Check(Has(MNE_ARMED, M1, 1), 'armed after ArmSeconds (the owner is told)');
  { an enemy jumping over it: his feet 25 px up }
  PX[2] := 0;
  PY[2] := -25;
  Run(161);
  Check(not Has(MNE_TRIGGER, M1, -1), 'an enemy jumping over it passes');
  { a team mate and the owner walk over it }
  Away(2);
  PX[3] := 3;
  PY[3] := 0;
  PX[1] := -4;
  Run(162);
  Check(not Has(MNE_TRIGGER, M1, -1), 'the owner and his team walk over it');
  Away(3);
  PX[1] := -300;
  { a dead enemy on it }
  Put(2, 2, 2, 0, False, False);
  Run(163);
  Check(not Has(MNE_TRIGGER, M1, -1), 'a dead enemy lying on it does not set it off');
  { an enemy walks onto it: his toe within 16 px }
  Put(2, 2, 19, 0, False, True);
  Run(164);
  Check(Has(MNE_TRIGGER, M1, 2), 'an enemy stepping on it sets it off');
  Run(165);
  Check(not Has(MNE_TRIGGER, M1, -1), 'it goes off once');
  MnRemove(M1);
  Check(MnCount(0, 0) = 0, 'removed after its blast');

  { 2. a claymore of 1 at 0, 0 looking right (and a little down): its wire 160 px ahead, knee high }
  Away(2);
  C1 := MnPlant(MN_CLAY, 1, 1, 0, 0, 300, -12 + 40, 200);
  Check(C1 > 0, 'a claymore is planted');
  MnGet(C1, Kind, Owner, Team, X, Y, FX, FY);
  Check((FX > 0.9) and (FY > 0.05), 'it looks right and a little down (where he looked)');
  Run(261);
  Check(Has(MNE_ARMED, C1, 1), 'the claymore is armed');
  { an enemy standing at 100 px in front: his legs cross the wire }
  Put(2, 2, 100, 0, False, True);
  Run(262);
  Check(Has(MNE_TRIGGER, C1, 2), 'an enemy walking into the wire sets it off');
  MnRemove(C1);
  C1 := MnPlant(MN_CLAY, 1, 1, 0, 0, 300, -12, 300);
  Away(2);
  Run(361);
  { over the wire: feet 20 px up at 100 px }
  PX[2] := 100;
  PY[2] := -20;
  Run(362);
  Check(not Has(MNE_TRIGGER, C1, -1), 'jumping over the wire passes');
  { beyond its end }
  PX[2] := 200;
  PY[2] := 0;
  Run(363);
  Check(not Has(MNE_TRIGGER, C1, -1), 'standing beyond the wire''s end is safe');
  { behind it, 40 px: nothing; then touching it from behind }
  PX[2] := -40;
  Run(364);
  Check(not Has(MNE_TRIGGER, C1, -1), 'behind the claymore (not touching) is safe');
  PX[2] := -9;
  Run(365);
  Check(Has(MNE_TRIGGER, C1, 2), 'touching it from behind sets it off');
  MnRemove(C1);

  { 3. the cone fuse: in front up to 180 px, not behind }
  MnSet(MNC_FUSE, FUSE_CONE);
  MnSet(MNC_CONE_ANGLE, 30);
  MnSet(MNC_CONE_RANGE, 180);
  Away(2);
  C1 := MnPlant(MN_CLAY, 1, 1, 0, 0, -300, -12, 400);
  MnGet(C1, Kind, Owner, Team, X, Y, FX, FY);
  Check(FX < -0.9, 'a claymore looking left');
  Run(461);
  Put(2, 2, 120, 0, False, True);
  Run(462);
  Check(not Has(MNE_TRIGGER, C1, -1), 'the cone looks left: an enemy on the right is safe');
  PX[2] := -150;
  PY[2] := -20;
  Run(463);
  Check(Has(MNE_TRIGGER, C1, 2), 'an enemy in its cone (even in the air) sets it off');
  MnRemove(C1);
  MnSet(MNC_FUSE, FUSE_WIRE);

  { 4. finding, taking apart, picking up }
  Away(2);
  M1 := MnPlant(MN_LAND, 1, 1, 0, 0, 0, 0, 500);
  Run(561);
  Put(2, 2, 50, 0, False, True);
  Run(562);
  Check(not Has(MNE_SPOTTED, M1, -1), 'standing near it he does not find it');
  n := MnDraw(2, 562, 64, PX[2], PY[2], More);
  Check(n = 0, 'an enemy does not see a landmine he did not find');
  Low[2] := True;
  PX[2] := 30;
  Run(563);
  Check(Has(MNE_SPOTTED, M1, 2), 'crouching near it he finds it');
  Check(Has(MNE_WORK, M1, 2), 'staying low next to it he starts taking it apart');
  n := MnDraw(2, 563, 64, PX[2], PY[2], More);
  Check((n = 1) and (OpText(0) = 'o'), 'now he sees its mark');
  Run(600);
  Check(not Has(MNE_DEFUSED, M1, -1), 'not done after 37 ticks');
  { he stands up: the work stops }
  Low[2] := False;
  Run(601);
  Check(Has(MNE_WORK_STOP, M1, 2), 'standing up stops it');
  Low[2] := True;
  Run(602);
  Check(Has(MNE_WORK, M1, 2), 'low again: he starts again');
  Run(781);
  Check(not Has(MNE_DEFUSED, M1, -1), 'not done before DefuseSeconds');
  Run(782);
  Check(Has(MNE_DEFUSED, M1, 2), 'done after DefuseSeconds');
  MnRemove(M1);
  { a team mate of 2 was near? SpotShare: the team of 2 sees a mine he found }
  Away(2);
  M1 := MnPlant(MN_LAND, 1, 1, 0, 0, 0, 0, 800);
  Put(4, 2, 500, 0, False, True);
  Put(2, 2, 40, 0, True, True);
  Run(861);
  Check(Has(MNE_SPOTTED, M1, 2), 'found again');
  Away(2);
  n := MnDraw(4, 861, 64, PX[4], PY[4], More);
  Check(n = 1, 'his team mate sees it too (SpotShare)');
  { the owner picks it up (a bot does not) }
  Away(4);
  Put(1, 1, -30, 0, True, True);
  MnHuman(1, 0);
  Run(862);
  Check(not Has(MNE_WORK, M1, 1), 'a bot next to his own mine does not pick it up');
  MnHuman(1, 1);
  Run(863);
  Check(Has(MNE_WORK, M1, 1), 'the owner low next to it starts picking it up');
  Run(953);
  Check(Has(MNE_PICKED, M1, 1), 'picked up after PickupSeconds');
  MnRemove(M1);
  { a mine not armed yet is not picked up (low next to it right after planting) }
  M2 := MnPlant(MN_LAND, 1, 1, 0, 0, 0, 0, 954);
  Put(1, 1, -30, 0, True, True);
  Run(955);
  Check(not Has(MNE_WORK, M2, 1), 'right after planting: no picking up');
  Run(1014);
  Check(Has(MNE_WORK, M2, 1), 'armed: now he picks it up');
  { he stands up: the picking up stops }
  Low[1] := False;
  Run(1015);
  Check(Has(MNE_WORK_STOP, M2, 1), 'crouch let go: the picking up stops');
  MnRemove(M2);
  Put(1, 1, -300, 0, False, True);

  { 5. shots: an enemy's bullet through a claymore sets it off; a team mate's or a miss does not }
  C1 := MnPlant(MN_CLAY, 1, 1, 0, 0, 300, -12, 1000);
  Run(1061);
  Shot(3, -200, -5, 20, 0);
  Run(1062);
  Check(not Has(MNE_SHOT, C1, -1), 'a team mate''s bullet does nothing');
  Shot(2, -200, -30, 20, 0);
  Run(1063);
  Check(not Has(MNE_SHOT, C1, -1), 'a bullet 25 px over it misses');
  Shot(2, -200, -5, 20, 0);
  Run(1064);
  Check(Has(MNE_SHOT, C1, 2), 'an enemy bullet through it sets it off');
  MnRemove(C1);
  M1 := MnPlant(MN_LAND, 1, 1, 0, 0, 0, 0, 1100);
  Run(1161);
  Shot(2, -200, -2, 20, 0);
  Run(1162);
  Check(not Has(MNE_SHOT, M1, -1), 'a buried landmine is not shot (ShootMines = 0)');
  MnRemove(M1);

  { 6. a chain: the second mine 50 px away goes off 9 ticks later, the third 200 px away not }
  M1 := MnPlant(MN_LAND, 1, 1, 0, 0, 0, 0, 1200);
  M2 := MnPlant(MN_LAND, 1, 1, 50, 0, 0, 0, 1200);
  M3 := MnPlant(MN_LAND, 1, 1, 250, 0, 0, 0, 1200);
  Check(MnNearest(40, 0, D) = M2, 'the nearest mine');
  Run(1261);
  MnChain(M1, 70, 1270);
  MnRemove(M1);
  Run(1269);
  Check(not Has(MNE_TRIGGER, M2, -1), 'the chain waits');
  Run(1270);
  Check(Has(MNE_TRIGGER, M2, 0) and not Has(MNE_TRIGGER, M3, -1), 'the mine within ChainRadius follows');
  MnRemove(M2);
  MnRemove(M3);

  { 7. the marks: the owner sees his landmine and his claymore with its wire; an enemy only the claymore }
  Away(2);
  M1 := MnPlant(MN_LAND, 1, 1, 0, 0, 0, 0, 1300);
  C1 := MnPlant(MN_CLAY, 1, 1, 100, 0, 400, -12, 1300);
  Put(2, 2, 400, 0, False, True);
  n := MnDraw(1, 1301, 64, -300, 0, More);
  Check(n = 3, 'the owner: his mine, his claymore and its wire (3 texts)');
  n := MnDraw(1, 1302, 64, -300, 0, More);
  Check(n = 0, 'nothing sent again while nothing changed');
  n := MnDraw(2, 1302, 64, 400, 0, More);
  Check(n = 2, 'an enemy: the claymore and its wire, not the landmine');
  T := 0;
  for i := 0 to n - 1 do
    if Pos('-', OpText(i)) > 0 then
      T := Length(OpText(i));
  Check(T > 20, 'the wire is a line of dashes');
  MnRemove(C1);
  n := MnDraw(2, 1303, 64, 400, 0, More);
  Check(n = 2, 'a gone claymore: its two texts are taken away');
  n := MnDraw(1, 1303 + 200, 64, -300, 0, More);
  Check(n >= 1, 'sent again after Refresh (texts are plain packets)');
  MnRemove(M1);
  n := MnHide(1, 64);
  Check(n = 1, 'hide: the one text left goes');

  { 7b. the preview: the owner of a new claymore sees its cone's edges and arc (6 + 6 + 3 dots) on their own
    layers for PreviewSeconds; a mine that goes while an enemy takes it apart stops his work }
  MnSet(MNC_PREVIEW, 150);
  MnSet(MNC_PREV_EDGE, 6);
  MnSet(MNC_PREV_ARC, 3);
  C1 := MnPlant(MN_CLAY, 1, 1, 0, 0, 400, -12, 1320);
  n := MnDraw(1, 1321, 64, -300, 0, More);
  Check(n = 2 + 15, 'the owner: the claymore, its wire and 15 dots of its cone');
  n := MnDraw(1, 1321 + 160, 64, -300, 0, More);
  Check(n = 17, 'the preview ends: its 15 dots go (the claymore and its wire are sent again)');
  MnSet(MNC_PREVIEW, 0);
  Run(1400);
  Put(2, 2, -30, 0, True, True);
  Run(1401);
  Check(Has(MNE_WORK, C1, 2), 'an enemy low behind the claymore starts taking it apart');
  MnRemove(C1);
  Run(1402);
  Check(Has(MNE_WORK_STOP, C1, 2), 'the claymore goes (a blast, a shot): his work stops');
  Away(2);

  { 8. a soldier the library does not know: the script tells where he is }
  M1 := MnPlant(MN_LAND, 1, 1, 0, 0, 0, 0, 1410);
  Put(5, 2, 900, 0, False, True);
  Unknown[5] := True;
  Run(1471);
  Check((MnWants and (LongWord(1) shl 4)) <> 0, 'the unknown soldier is asked for');
  MnPos(5, 6, 0, 0);
  Run(1472);
  Check(Has(MNE_TRIGGER, M1, 5), 'told where he stands, he sets it off');
  MnRemove(M1);

  { 9. the mines of a player who leaves; the most a map holds }
  M1 := MnPlant(MN_LAND, 1, 1, 0, 0, 0, 0, 1500);
  M2 := MnPlant(MN_CLAY, 1, 1, 60, 0, 300, 0, 1500);
  M3 := MnPlant(MN_LAND, 3, 1, 120, 0, 0, 0, 1500);
  Check(MnRemoveOwner(1) = 2, 'his two go when he leaves');
  Check(MnCount(0, 0) = 1, 'the others stay');
  MnClear;
  Check(MnCount(0, 0) = 0, 'a new map starts empty');
  n := 0;
  for i := 1 to 70 do
    if MnPlant(MN_LAND, 1, 1, i * 40, 0, 0, 0, 1600) > 0 then
      Inc(n);
  Check(n = 64, 'the library holds 64 at most');
  MnClear;

  { 10. bodies (Corpses = enemies): a dead enemy's body that comes onto an armed landmine sets it off (Q = 2),
    one lying there when it was armed does not, nor a team mate's; with Corpses = all anybody's; a body
    across a claymore's wire; with Corpses = off nothing }
  MnSet(MNC_CORPSES, CORPSE_ENEMY);
  Put(1, 1, -300, 0, False, True);
  Put(2, 2, 400, 0, False, True);
  Put(3, 1, 500, 0, False, True);
  M1 := MnPlant(MN_LAND, 1, 1, 0, 0, 0, 0, 1700);
  Run(1761);
  Put(2, 2, 400, 0, False, False);
  Run(1762);
  Check(not Has(MNE_TRIGGER, M1, -1), 'an enemy dies far from it: nothing');
  PX[2] := 5;
  Run(1763);
  Check(HasQ(MNE_TRIGGER, M1, 2, 2), 'his body slides onto it: it goes off (a body, Q = 2)');
  Run(1764);
  Check(not Has(MNE_TRIGGER, M1, -1), 'once');
  MnRemove(M1);
  { a mine armed under the body lying there waits; a team mate dying on it does not set it off }
  M1 := MnPlant(MN_LAND, 1, 1, 0, 0, 0, 0, 1800);
  Run(1801);
  Run(1860);
  Check(Has(MNE_ARMED, M1, 1) and not Has(MNE_TRIGGER, M1, -1), 'armed under a body lying there: it waits');
  Run(1861);
  Check(not Has(MNE_TRIGGER, M1, -1), 'the body lies still: nothing');
  Put(3, 1, 3, 0, False, True);
  Run(1862);
  Put(3, 1, 3, 0, False, False);
  Run(1863);
  Check(not Has(MNE_TRIGGER, M1, -1), 'a team mate''s body: not with Corpses = enemies');
  { the enemy's body goes (his next life), comes back dead and falls on it }
  Put(2, 2, 400, 0, False, True);
  Run(1864);
  Put(2, 2, 400, 0, False, False);
  Run(1865);
  PX[2] := -6;
  Run(1866);
  Check(HasQ(MNE_TRIGGER, M1, 2, 2), 'a new body of his falling on it sets it off');
  MnRemove(M1);
  { Corpses = all: the team mate's body too (the owner's team) }
  MnSet(MNC_CORPSES, CORPSE_ALL);
  Put(3, 1, 500, 0, False, True);
  Put(2, 2, 400, 0, False, True);
  M1 := MnPlant(MN_LAND, 1, 1, 0, 0, 0, 0, 1900);
  Run(1961);
  Put(3, 1, 500, 0, False, False);
  Run(1962);
  PX[3] := 4;
  Run(1963);
  Check(HasQ(MNE_TRIGGER, M1, 3, 2), 'Corpses = all: a team mate''s body sets it off too');
  MnRemove(M1);
  { a body across a claymore's wire }
  MnSet(MNC_CORPSES, CORPSE_ENEMY);
  Put(3, 1, 500, 0, False, True);
  C1 := MnPlant(MN_CLAY, 1, 1, 0, 0, 300, -12, 2000);
  Run(2061);
  Put(2, 2, 400, 0, False, False);
  Run(2062);
  PX[2] := 90;
  Run(2063);
  Check(HasQ(MNE_TRIGGER, C1, 2, 2), 'a body falling across a claymore''s wire sets it off');
  MnRemove(C1);
  { off: a body does nothing; he leaves: his body is forgotten }
  MnSet(MNC_CORPSES, CORPSE_OFF);
  Put(2, 2, 400, 0, False, True);
  M1 := MnPlant(MN_LAND, 1, 1, 0, 0, 0, 0, 2100);
  Run(2161);
  Put(2, 2, 400, 0, False, False);
  Run(2162);
  PX[2] := 2;
  Run(2163);
  Check(not Has(MNE_TRIGGER, M1, -1), 'Corpses = off: a body on it does nothing');
  MnSet(MNC_CORPSES, CORPSE_ENEMY);
  MnForget(2);
  Run(2164);
  PX[2] := 400;
  Run(2165);
  PX[2] := 2;
  Run(2166);
  Check(not Has(MNE_TRIGGER, M1, -1), 'a player who left has no body');
  MnRemove(M1);
  MnSet(MNC_CORPSES, CORPSE_OFF);
  Put(2, 2, 400, 0, False, True);

  { a mine detector: an enemy finds the mines within its reach without staying low; not again, not his own, not
    the far ones }
  M1 := MnPlant(MN_LAND, 1, 1, 380, 0, 0, 0, 2200);
  M2 := MnPlant(MN_LAND, 1, 1, 900, 0, 0, 0, 2200);
  Check(MnDetect(2, 400, 0, 160) = 1, 'the detector finds the near enemy mine');
  Check(MnDetect(2, 400, 0, 160) = 0, 'a mine found is not found again');
  Check(MnDetect(1, 380, 0, 160) = 0, 'its owner finds nothing');
  Check(MnDetect(2, 400, 0, 600) = 1, 'a longer reach finds the far one too');
  MnRemove(M1);
  MnRemove(M2);

  WriteLn(MnInfo);
  WriteLn(Passed, ' passed, ', Failed, ' failed');
  if Failed > 0 then
    Halt(1);
end.
