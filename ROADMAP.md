# Basic-Extended - plan rozbudowy

Stan po wersji 3.5 i propozycje na kolejne wersje, od najbardziej opłacalnych. Każdy punkt ma
krótkie uzasadnienie i szacunek pracy (S - godziny, M - dzień, L - kilka dni).

## Co już jest (3.5)

- `/speed <gracz> <x> [all|ground|jump]`: przyspieszenie wszędzie, tylko na ziemi albo na ziemi i w
  wyskoku z ziemi (`SpeedJumpShare`), w powietrzu już nie.
- `/weaponmod` usunięte - biblioteka śledzi serwerowe `/loadwep` i czyta ten sam plik broni.
- `/flytomouse` domyślnie bez skoków: płynny lot do limitu prędkości gry (15.5 po przekątnej);
  skoki powyżej limitu tylko z `FlyHops = 1`.
- Anty-cheat: `/suspects`, `/acstats`, `/acreview` domyślnie dla wszystkich (`/` i `!`), tabela
  "ta gra | wszystkie gry" z kolorami, `/suspects` z wynikiem tej gry i wszystkich gier,
  `/acclear all all` (wszyscy, cała historia).
- Trajektoria: `/trajectory <gracz> [cursor] [me|self|selfme|public]` - kto widzi kropki.
- Radar: filtry `seenreal` / `seenallreal` i wykrywanie trybu realistic (`seen` liczy wtedy linię
  wzroku), zoom osobno dla każdego trybu, edytor dla labels i ring (rozmiar), `!radar marks` i
  `!radar edge` (`CircleEdgeScale`) dla płynniejszego koła, `CircleMovePixels = 0`, zarys ścian
  promieniami (lidar), niesiona flaga bez drugiego `F` na nosicielu, stały rozmiar liter ringu.
- `/sayteam`, odrzut Spas-12 i Minigun przy strzałach aimbota (`Recoil`), dźwięk rzutu noża.
- Więcej pracy w DLL: szablony wiadomości (`BE_Fill`), tekst HUD i pasek, liczby, kolory, linie
  logów, preferencje graczy jednym wywołaniem, widoczność dla numerów obrażeń, nazwy broni.
- `Example configs/`: 19 zestawów (od rundy 26: ctf, rscs, rs, rsa, tw, ttw, battlefield, insurgents, hardcore ...).

## Wcześniej (3.4)

- Aimbot: poprawiony `/aimbot acc` (dzielenie całkowite dawało 0% dla wszystkiego poniżej 100),
  tryb `radius` (tylko wrogowie w kole wokół kursora, bez przeskakiwania na dalekich graczy) z
  edytorem `/aimbot radius edit` rysującym koło, dodatkowe strzały po utracie celu (`ExtraShots`,
  losowo z zakresu), zasada LAW (`game` / `ground` / `anywhere`), collidery jako przeszkoda, rzucony
  nóż znika z ręki, pauza przy własnym strzale i ochrona licznika amunicji przed nieaktualnym odczytem.
- Trajektoria: rysowanie przed lecącym pociskiem Barretta, za którym idzie kamera, tryb
  `/trajectory <gracz> cursor` (sam kursor), collidery kończą tor.
- `/flytomouse` szybszy niż limit prędkości gry (brakująca część krótkimi skokami).
- Anty-cheat 2.0: czytelne `/suspects`, `/acstats`, nowe `/acreview`, tempo magazynka i przeładowania,
  prędkość, opcjonalne głosowanie za wyrzuceniem (bez automatycznego kicka), bez headshotów.
- Radar: grupy (pełni użytkownicy / wszyscy) z własnymi trybami, domyślnym trybem, filtrem i limitem
  odświeżania, `AdminsFull`, zasięg każdego trybu, kolory linii listy (drużyna/zdrowie/odległość),
  flagi poza bazą we wszystkich trybach, zarys mapy w kole (`!radar outline`).
- Nowe komendy: `/speed`, `/sayas`, `/sayteamas`, `/slay`; `[Permissions]` - kto może używać każdej
  komendy i czy przez `/`, `!` czy oba.

## 1. Wydajność

| Zadanie | Dlaczego | Praca |
| :--- | :--- | :--- |
| Skan pocisków supresji w DLL z pamięcią slotów | Dziś każdy aktywny pocisk to ~6 odczytów właściwości co 4 ticki; DLL może pamiętać właściciela i styl slotu, a skrypt czytać tylko X/Y. Ok. 40% mniej pracy w walce. | M |
| Odpytywanie zdrowia (HUD) jednym wywołaniem na gracza | Ten sam zysk co przy snapshocie: tablice w PascalScript kosztują tyle co wywołanie DLL. | S |
| Pomiar na serwerze Windows | `/be_bench` i `/be_status` na prawdziwym 2.8.2 - koszty odczytów bywają inne niż na Linuksie. | S |

## 2. Anty-cheat

| Zadanie | Jak | Praca |
| :--- | :--- | :--- |
| Aim-snap (aimbot u ludzi) | Dla graczy z wysokim wynikiem próbkować MouseAim co tick i szukać skoków kąta tuż przed trafieniem. Tylko dla podejrzanych, więc tanio. | M |
| Kierunek pocisku vs celownik | Porównać kierunek trafiającego pocisku z MouseAim w chwili strzału (statystycznie, bo serwer zna kursor z dokładnością ~30 px). | M |
| Strzały "przez ściany" | Z geometrią mapy: trafienie, którego tor przechodzi przez ścianę blokującą pociski. | S |
| Eksport historii | Historia z `players.bdb` do pliku (np. CSV) do przeglądania poza grą. | S |

## 3. Radar i HUD

- "Radar dźwiękowy": kierunek niedawnych strzałów wrogów w pobliżu (dane ze skanu pocisków). M

## 4. Narzędzia admina

| Komenda | Na czym | Praca |
| :--- | :--- | :--- |
| `/setspawn`, własne punkty odrodzenia | `OnBeforePlayerRespawn` zwraca `TVector` - pozycję odrodzenia (wiki podaje błędny typ). | M |

## 5. Tryby gry z gotowych klocków

Z `/give`, `/infammo`, `/dmgfix`, `/dmgtaken`, `/vest`, `/speed` i bonusów da się złożyć:
Gun Game (kolejna broń za zabójstwo), Juggernaut (jeden gracz z dużą odpornością), Instagib
(`/dmgfix all x10`), walka na noże, Zombie (drużyna z mnożnikiem obrażeń i bez broni palnej),
rundy turniejowe z gotowością drużyn. Każdy tryb to M.

## 6. Inżynieria

- GitHub Actions: build DLL (win32 i linux), testy jednostkowe, harness ABI PascalScript. M
- Podział `main.pas` na pliki (moduły skryptu) dla łatwiejszego rozwoju. M

## Zrobione poza tym planem

- Broń zabójstwa z aimbota: most do pamięci serwera (`be_bridge`) wpisuje prawdziwą broń do pocisku
  aimbota (tablicę pocisków znajduje po kodzie serwera, przed zapisem sprawdza slot, styl i obrażenia).
- Ograniczona amunicja i magazynki (`[Ammo]`, `[Looting]`, `be_ammo`): liczone z tego, co raportuje gra.
  Broń na ziemi śledzona po obiekcie mapy (podniesienie odróżnione od wyboru z menu, także bez broni
  drugorzędnej), zmiana drużyny i wyjście z gry zostawiają broń jak śmierć, zapas w pełnych magazynkach.
  Strzały z haka w `CreateBullet` serwera (też strzał razem z przeładowaniem), `!repack`,
  sortowanie magazynków, opcje jednego naboju i przerwanego przeładowania, `EmptyDrop = 0` bez
  przepuszczonego strzału, osobny tekst amunicji (`[AmmoHud]`, `!ammohud`, migające NO AMMO).
- Aimbot: cel szukany przed rozkręceniem Minigana/Barretta, dodatkowe strzały tylko po zabiciu (bez
  innych wrogów w zasięgu i bez ściany), `Key = flagthrow` i `FlagKey` przy niesionej fladze.
- Listy w `settings.ini` jako numerowane klucze (`Line-N`, `Message-N`, `Slot-N`, `Steam-N`, `Watch-N`),
  `settings.ini` obok `main.pas`; `/be_prof` mierzy czas każdej części ticku.
- Haki w `CreateBullet` i `CreateThing` serwera (`be_hook`, `[Debug] ServerHooks`): każdy pocisk
  (strzały ludzi z pakietów i ogień serwera/botów, granaty - broń 50, rzucone noże - 53) w chwili, gdy
  serwer go tworzy, z odróżnieniem pocisków skryptu; każda upuszczona broń z jej obiektem mapy.
  Skan tablicy pocisków co tick usunięty. Dla skryptu: `BE_HookWatch` + `BE_ShotNext` (zdarzenie
  strzału / rzutu), `BE_BulletInfo`, `BE_BulletKill`.
- Wyświetlany magazynek spada z każdym strzałem od razu (też z trzymanym R), 0 w trakcie
  przeładowania; `EmptyDrop = 0` także dla podniesionej pustej broni; `[Looting] DeadMagazines`
  (`weapon` / `body` / `auto`: magazynki przy ciele, `auto` = na survivalu); napisy Looting i
  Repacking wyśrodkowane, bez kropek, `TextScale` / `TextOffsetX` / `TextOffsetY`; strzał z magazynka
  uznanego za pusty (R i strzał trzymane razem) liczy się jako przeładowanie - magazynek idzie z
  ładownicy, każdy taki cykl kosztuje nabój.

- Stare skrypty FlashNades i ExtraRocket jako dodatki `[FlashNades]` i `[ExtraRocket]` (wyłączone, dopóki
  się ich nie włączy) - opis niżej.
- Flash usuwany z serwera tuż przed wybuchem (`Defuse`, most `BE_BulletKill`): koniec zapalnika albo tick
  przed dotknięciem żołnierza lub collidera mapy (rzucający liczy się od zapalnika < 130, jak w grze) -
  serwer nie ma wybuchu, więc nie ma obrażeń ani odrzutu, gry graczy i tak pokazują wybuch. Znacznik
  flasha w powietrzu to pierścień `O` wyśrodkowany na granacie (`MarkScale`, `BE_TextInk`), zwykłe granaty
  bez napisu. Krótkie komendy `!f` / `/f` (flash wł./wył.), `!n`; pomoc i tekst po wejściu (`{switch}`)
  mówią, jak zmieniać typ przy danych ustawieniach. `BlindBots = 2`: oślepiony bot zatacza się.
- Javelin (`[ExtraRocket]`): lot liczony w DLL (`be_rocket`) - ciąg przeciw oporowi, skręt ograniczony
  przyspieszeniem bocznym (wolna skręca ciasno, szybka szeroko), nawigacja proporcjonalna, omijanie ścian z
  wyhamowaniem, miękki start z zapłonem, atak z góry po łuku, lot ślizgowy po końcu paliwa, zapalnik
  zbliżeniowy. Namierzanie (`LockSeconds`, celownik z nawiasów), rakiety dodatkowe (nie biorą naboju LAW),
  licznik przy amunicji (`(1/2 Javelin)`, `Name`), `!rocket` jako instrukcja. Test lotu bez serwera na
  prawdziwych mapach: `source_dll/tests/test_rocket.pas` (w `test.bat`).
- Hak zgłasza też rzucone noże: `[Ammo] CombatKnife` (wcześniej martwe) to zapasowe noże, `/infammo` oddaje
  nóż od razu.
- Javelin, runda 10 (po teście na serwerze): cel szukany przy kursorze (`Target = radius`, `CursorRadius`,
  nawiasy szukacza), namierzanie trzymane bez kursora, na leżąco bez crouch, LAW musi być naładowany i
  przeładowuje się po starcie, a jego runda wraca (`Launcher = reload`, `BE_AmmoKeep`). Wybuch to kolumna
  prawdziwych rakiet LAW z wpisanym przez most punktem i czasem startu (`BE_BridgeSetOrigin`: pola
  `Initial` i `StartUpTime` rekordu pocisku), więc na liście zabójstw jest ikona LAW, a pod "You killed"
  prawdziwy dystans i czas lotu. Ostrzeżenie celu (`LockWarning`: celownik na nim, napis nad głową, pikanie
  `WarnSound` coraz szybsze, "INCOMING"), ton namierzania strzelca (`LockSound`), blokada po oślepieniu
  (`BlindLockSeconds`). Flash: mniejszy pierścień (0.1), co tick, u rzucającego wyprzedzony o jego ping;
  HUD granatów tuż nad tekstem amunicji gracza (`HudPlace = ammo`).
- Runda 11 (po teście właściciela): pierścień flasha jeszcze mniejszy (`MarkScale = 0.07`) i wyśrodkowany na
  obrazku granatu - gra rysuje go ok. 2 px nad pozycją granatu (`weapons-gfx/frag-grenade.png` 14 x 18 przy
  `DefaultScale = 4.5`, od X - 1, Y - 4), zmierzone na zrzucie z gry 2560 x 1440 (`MarkOffsetX`,
  `MarkOffsetY`); wyprzedzenie rzucającego tylko w locie (leżący granat nie ma już znacznika wciśniętego w
  ziemię), toczący się dostaje znacznik co piksel. Javelin: osobne włączniki tonów strzelca i celu
  (`ShooterBeep`, `TargetBeep`), węższe nawiasy szukacza (`SeekWidth = 200`, szukanie dalej w
  `CursorRadius`).
- Runda 12: most do rekordów żołnierzy serwera (`be_sprite`, `BE_API 9`). ScriptCore przekazuje obiekt
  gracza do biblioteki jako sam obiekt (`TScriptActivePlayer`), za wskaźnikiem klasy leży `FSpritePtr` =
  `@Sprite[ID]`, a w rekordzie szkielet (w 2.8.2 od +692): punkty, które serwer co tick ustawia z animacji i
  w które trafiają pociski. Oczy = środek głowy, 3 px od szyi (punkt 9) w stronę punktu 12: stojąc ok. 19 px
  nad pozycją gracza, w kucki 11, leżąc 6.5 (i 3 px w bok). Flash widzi się teraz z oczu (`BE_SpriteEyes`), a
  nie ze stałych 12 px nad stopami; dłuższe oślepienie dalej od wybuchu (`Falloff = 3`, `Radius = 300`),
  pierścień `MarkScale = 0.06`, `BlindLockSeconds = 0.25`. Most odczytu strzału: `BE_BulletOrigin` (Initial i
  StartUpTime, których miejsce w rekordzie most poznaje z pierwszego pocisku z haka `CreateBullet`) - dystans i
  czas lotu dokładnie jak pod "You killed"; `[KillInfo]` ma tokeny `{dist}` i `{air}`, `/be_status` linię
  mostu.
- Runda 13 (`BE_API 10`): widoczność trybu realistic ze szkieletów serwera za `[Radar] SkeletonSight = 1` -
  promienie radaru (`seen`/`seenreal`), mgła wojny cyferek obrażeń i znaczniki flasha dla wrogów idą jak w
  grze: z punktu 7 patrzącego (2 px wyżej) do punktu 7 drugiego, a granaty z szyi patrzącego (punkt 9); w
  kucki punkt 7 jest 3 px nad pozycją, leżąc 2 px, stojąc 11. `0` wraca do stałych wysokości. Biblioteka
  zna każdy slot, gdy ma dwa podpięte (krok tablicy `Sprite` w 2.8.2: 49688 bajtów); skrypt podpina żywych
  graczy co pół sekundy (`BE_SpriteBind`). Flash: `Radius = 260`, `MinTicks = 60` (daleko krócej i
  łagodniej), `JoinBigText` puste - na wejściu tylko linia na czacie.
- Runda 14 (`BE_API 11`): `[TeamKill]` ze starego skryptu tk (ScriptCore 2). Biblioteka (`be_tk`) patrzy na
  linię każdego strzału z haka `CreateBullet` względem szkieletów: kolega pierwszy na linii bez wroga blisko
  = strzał w niego, z wrogiem blisko lub za nim = ostrzał krzyżowy; z ostatnich strzałów bierze się, na ile
  trafienie w kolegę było celowe (wybuch przy wrogach 10 %, nóż 100 %), a kilka celowanych strzałów w tego
  samego kolegę w chwili to spray. Punkty za obrażenia drużyny i TK razy ta celowość (spawn, flaga, zemsta),
  topnieją z czasem, idą za graczem po Steam id; drabina: ostrzeżenie, blokada ognia w drużynę z odbiciem na
  strzelca, slay, kick, bany rosnące x2; spray blokuje ogień od razu, uporczywy spray mimo blokady prowadzi do
  kicka i bana. Menu ofiary jak w starym skrypcie (`!1`-`!4`, `!tk 1-4`), `!tk`, `/tk <gracz>`, `/tklist`,
  `/tkreset`, dziennik `teamkill.log`. Test bez serwera: `tests/test_tk.pas`. Prefiks w `main.pas`: `Ff`
  (`Tk` ma już `[TimeToKill]`). Tempo spadków w konfiguracji (pytanie właściciela): `DecayMinutes`,
  `DecayAfterSeconds`, `DecayOffline` i `BanForgetDays` - co 7 dni bez bana licznik banów o jeden w dół,
  więc kolejny ban znowu krótszy (resztę dni liczy do następnego; `/tkreset <gracz> bans` od razu).
- Runda 15 (`BE_API 12`): `[Mines]` ze starego skryptu Mines v0.0.0.1, z drugim rodzajem - claymore; oba
  włączane osobno (`Landmines`, `Claymores`). Biblioteka (`be_mine`) co tick sprawdza miny względem szkieletów
  (tylko żołnierzy blisko miny): mina wybucha pod wrogiem, którego noga lub ciało jest do `TriggerRadius` w bok
  i `TriggerHeight` nad nią (skok lub jetpack nad znaną miną bezpieczny, czołganie nie); claymore od drutu
  wzdłuż ziemi przed sobą (czerwone kreski widoczne dla wszystkich, w realistic tylko w zasięgu wzroku), od
  dotyku, albo od wroga w stożku (`Fuse = cone`). Wróg kucający lub leżący blisko miny ją znajduje (widzi ją on
  i jego drużyna), zostając nisko obok rozbraja ją w 3 s i zabiera; właściciel podnosi swoją; kula wroga
  odpala claymore (zabójstwa strzelca); mina obok wybucha łańcuchowo. Wybuch miny: pierwszy M79 prosto w
  ofiarę (działa na każdej podłodze), reszta w ziemię tam, gdzie ziemia zatrzymuje kule, plus odłamki w górę;
  claymore: 20 śrucin Spas w stożku ±20° tam, gdzie patrzył właściciel (100 px przed nim: 142 z 150 HP),
  8 słabszych dookoła i za nim, mały wybuch klastra. Zdobywanie: zabójstwa (`KillsPerMine` 3,
  `KillsPerClaymore` 5), przejęcie flagi, początek życia; limity noszonych, wkopanych i na mapie; klawisze:
  rzut flagi (skok + kucanie) = mina, na leżąco = claymore; `!mine`, `!claymore`, `!mines`, `/minelist`,
  `/mineclear`, `/givemines`; linia nad amunicją; znaczniki z puli warstw WorldText (133-148); boty też
  zdobywają i sadzą (z dala od własnego spawnu). Odkrycie z testów: w ctf_Ash część podłogi jest "tylko dla
  graczy" - kule i M79 przez nią przelatują, a M79 skryptu w ziemię nie wybucha (stąd pierwszy wybuch w
  ofiarę). Koszt: 10 walczących botów z minami, znaczniki wysyłane też botom - ok. 70 us na tick.
- Runda 15b (po teście właściciela): napisy rozbrajania i podnoszenia jako WorldText nad miną (tylko dla
  niego, znikają same); "Taking ... 99%" wisiało, gdy mina znikała w trakcie (wybuch po dotknięciu, strzał) -
  biblioteka daje wtedy znać (`MNE_WORK_STOP`). Claymore widoczny dla wroga tylko w polu widzenia, nie przez
  ściany, w każdym trybie (`EnemySight = sight`, znaczniki co 10 ticków); drut 110 px (było 160), śrut 1,5 x
  Spas (wróg 77 px przed nim ginie od 6 śrucin), wybuch M79 przy claymorze (gdzie ziemia zatrzymuje kule)
  zamiast klastra i wachlarz nieszkodliwych płomieni w stożku. Podgląd stożka gęstszy: 6 kropek na krawędź
  + 3 na łuku, na własnych warstwach (185-199). Sadzenie: `FlagDistance` 130, `SpawnDistance` 110 i spawn
  albo flaga za ścianą się nie liczą (ctf_Ash: spawn Bravo stoi na dolnej podłodze przy x 483, więc tam
  blokada zostaje). `/givemines <gracz> [ile] [mines|claymores]`. `[FlashNades] BotFlashChance = 0.3`: boty
  rzucają też flashe.
- Runda 15c (przegląd): znaczniki co 10 ticków tylko wtedy, gdy na mapie leży mina widziana przez wrogów
  wzrokiem (domyślnie claymore), inaczej co 30; napisy nad miną mniejsze (`WorkScale` 0,04, jak etykiety
  flashy) i krótsze ("Defusing the claymore: 45%", "Claymore defused - it is yours"); `!mine` wpisane
  drugi raz przed `PlantSeconds` odpowiada, zamiast milczeć.
- Runda 15d (życzenie właściciela): po postawieniu nie BigText, tylko krótki napis nad miną dla właściciela
  ("Armed in 2s", potem "Armed"; warstwa WorldText 248), napisy pracy krótkie: "Picking 45%", "Defusing
  45%", "Defused - yours", "Picked up".
- Runda 15e (`BE_API 13`, zgłoszenie właściciela: napis podnoszenia zaraz po postawieniu i migający przy
  zwykłym chodzeniu obok miny): "nisko" (znajdowanie, rozbrajanie, podnoszenie) to teraz wciśnięte kucanie
  albo leżenie - skrypt czyta te dwa klawisze tylko graczom przy minach (`BE_MineNear`, `BE_MineLow`) - i
  niska postawa szkieletu (szyja < 12,5 px nad stopą). Zmierzone: stanie 16 px, bieg 12,6-15,7 (stary próg
  14 brał bieg za kucanie), kucanie 8,2, leżenie 3,9. Podnosi się tylko uzbrojoną minę.
- Runda 16 (`BE_API 14`, po teście właściciela): rozbrajanie 2 s (było 3), `MaxMines` 2, Javelin 1 na
  życie (`[ExtraRocket] Rockets`). Nowe `[Mines] Corpses` (`enemies` / `all` / `off`): ciało zabitego, które
  spadnie albo zsunie się na uzbrojoną minę, na claymore albo na jego drut, odpala je (biblioteka śledzi ciała
  od śmierci do następnego życia; ciało leżące tam już w chwili uzbrojenia miny jej nie odpala; stożek
  claymore'a reaguje tylko na żywych). Sprawdzone na serwerze testowym: rozbrojona mina znika w tym samym
  ticku i nie może już wybuchnąć (bot rozbroił, wstał i stanął w tym miejscu - nic); ciało bota zabitego nad
  miną odpaliło ją, z `Corpses = off` nie. Ofiara miny widzi teraz na środku ekranu, co ją zabiło
  (`VictimText`, wcześniej puste - stąd "nie wiem, co mnie zabiło"); u właściciela `Log = mines.log`.
  `[Ammo] ExtraMagazines` (1): w zapasie najwyżej tyle magazynków, ile ma świeża broń, plus tyle -
  lootowanie i podniesiona broń zabitego zatrzymują się na tym (wcześniej do 12 i dalej luzem). Napis
  Looting/Repacking idzie w dół razem z głową, gdy żołnierz kuca albo leży (`TextOffsetY` dla stojącego).
- Runda 17 (`BE_API 15`, życzenia właściciela z 30.09): nowe `[Bleeding]` - rany lekkie, ciężkie i tętnicze
  zależnie od obrażeń i miejsca trafienia (głowa, tułów, nogi - z koła trafienia serwera na szkielecie), krew,
  ubywanie zdrowia przy małej ilości krwi, szok (bez ruchu, czarny ekran; między szokami przerwa
  `ShockCheckSeconds` od końca szoku), wykrwawienie z zabójstwem dla tego, kto zadał najgorszą ranę (jego
  broń na liście zabójstw), bandaż w procentach zużywany zależnie od rany (1-4 s, nisko i bez ruchu, sam po
  `AutoDelay` albo `!bandage`), apteczka `!kit`, drobne rany ustają same po losowym czasie (`GrazeRandom`,
  `GrazeMinSeconds`-`GrazeSeconds`), `[Regeneration]` czeka przy krwawieniu i leczy tylko do udziału krwi;
  `[Downed]` - powalony zamiast martwy (bez headshota i "overkilla", `MaxDowns`), podnosi kolega nisko obok
  (i tamuje krwawienie), własna apteczka albo bot-kolega, ostatni z drużyny kończy od razu (`LastStand`),
  powalony bot sam używa apteczki po `BotBandageSeconds`, każdy koniec to zabójstwo tego, kto powalił
  (wolna kula z bliska + most wpisuje broń); `[Spotting]` - oznaczanie wrogów jak w Battlefieldzie: na
  radarze drużyny (`[Radar]` decyduje, kto ma radar - u właściciela radar jest prywatny, więc reszta graczy
  zobaczy oznaczonych dopiero z `[Radar] Public = 1` albo `[Spotting] World = 1`) i/lub znacznik nad głową,
  `/spot` (bind) albo reload z pełnym magazynkiem; `[Bounty]` - nagroda za głowę z nagrodami ze wszystkich
  modułów; `[Ammo] SurvivalCarry` / `SurvivalLock` - przeżyta runda survival zachowuje magazynki, bandaż,
  apteczki i wystrzelone Javeliny, broń bez amunicji zablokowana w menu broni (z trybem Advance i bez).
  Sprawdzone na serwerze testowym z botami: rana, wykrwawienie z zabójstwem dla strzelca, szok, bot sam się
  bandażuje, powalenie, podniesienie przez bota-kolegę, `MaxDowns`, koniec czasu jako zabójstwo, apteczka
  powalonego bota w survivalu, oznaczanie (dwa razy, za ścianą nie), nagroda (ogłoszenie i odebranie),
  przeniesienie magazynków na następną rundę (MP5 28/30 wraca do ładownicy, w broni pełny). Koszt przy 10
  walczących botach: krwawienie i powalenie ok. 24 us na tick, oznaczanie i nagrody 15 us, przeniesienie 3 us
  (cały tick skryptu ok. 460 us).
- Runda 18 (`BE_API 16`, życzenia właściciela z 01.10): `[SpawnProtection]` (ochrona po spawnie z napisem nad
  głową, koniec po strzale, bez zadawania obrażeń), `[PrivateMessages]` (`/pm`, `/msg`, `/r`, `/pmmute`,
  `/pmunmute` - blokady idą za graczem po Steam id, nie po slocie), `[Notes]` (`/note`, `/report`, `/comments`,
  czarna lista IP/HWID/Steam), `[AntiSpam]` (punkty za linie, ostrzeżenie, mute na czas rosnący dwukrotnie;
  mute serwera jest po IP - skrypt pamięta koniec w `mutes.txt` i zdejmuje go też po powrocie gracza, więc
  nikt nie zostaje wyciszony na stałe przez przypadek, a nowy gracz na tym samym slocie nie dostaje cudzego
  mute'a), `[AdminChat]` (`/col`, `/admcol`, `/colteam`, `/colp`, `/announce`), `[Pause]` (`!p`, `!up`,
  `/pause`, `/unpause` z odliczaniem; skrypt przejmuje te komendy od serwera), `[BanJournal]` (dziennik
  banów z czasem - serwer go nie ma; `/unbanlast <n|czas>`, `/banlist`), `[MapCommands]` (`/maplistadd`,
  `/maplistremove`, `/mapfind`, `/map` po części nazwy - biblioteka listuje folder map i dopasowuje jak
  głosowanie ZitroStats), `[Warn]`. `[SpecIdle]` liczy też spectatorów, którzy siedzieli tam, zanim serwer
  miał `MinPlayers`. Sprawdzone na serwerze testowym: ochrona zatrzymała trafienie (0 obrażeń), PM z
  odpowiedzią i blokadą, notatki i zgłoszenie, mute za flood i `/tunmute`, pauza z odliczaniem (zegar
  działa w czasie pauzy), ban 10 min w dzienniku i `/unbanlast 1h`, `/mapfind ash`, `/maplistadd laos`
  (powtórka odrzucona), `/maplistremove lao`, `/map cobr` -> ctf_Cobra.
- Runda 19 (`BE_API 17`, ostatni skrypt właściciela do włączenia - Shop 3.3, przepisany na ScriptCore 3,
  pieniądze w bazie biblioteki): `[Shop]` - ekonomia mapowa (portfel wraca po ponownym wejściu na tej samej
  mapie, więc reconnect nie daje nowych pieniędzy startowych) albo globalna (po Steam id w `players.bdb`,
  `GlobalComputerId` - po HWID); zarobki zależne od trybu: zabójstwo z mnożnikiem broni (`KillFactors`, bot
  `BotKillFactor`), headshot, asysta, obrażenia, przejęcie flagi, w survival przeżycie, wygrana i przegrana
  rundy z serią porażek, przychód, nagrody `[Bounty]`, kary za TK i samobójstwo; mnożniki zarobków i cen dla
  realistic, survival, advance i ekonomii globalnej. Sklep: `!shop`, `!buy` (też `/buy` pod klawisz), `!money`,
  `!pay`, `!sell`; broń wg listy broni serwera (łuki tylko w Rambo, miotacz tylko z `FlamerWeapon`), magazynki
  i amunicja w granicach `[Ammo]`, granaty, flashe, klastry, kamizelka, zdrowie, bandaż, apteczka, miny,
  claymore'y, Javeliny, berserker/predator (wyłączone), działko na `StatgunSeconds`, UAV (wrogowie na radarze
  drużyny), pociski AP do Barretta (wybuch klastrowy przy trafieniu w gracza albo w ścianę - biblioteka liczy
  tor pocisku przy strzale i zdejmuje go w ścianie), zrzut skrzynki pod celownik. `ShopOnly`: przy włączonym
  sklepie miny, claymore'y, Javeliny i flashe są tylko ze sklepu. `LoseOnDeath`, `BuyOnly` (menu broni = to,
  co gracz ma: kupione i to, co trzymał, przeżywając rundę albo - z `LoseOnDeath = 0` - ginąc; odblokowania
  trybu Advance nie trafiają do menu; boty serwera nie używają menu, więc dostają swoją najlepszą broń albo
  kupują). Pieniądze nad amunicją. `[Supply]`: skrzynki na spadochronie co `EveryMinutes` przy losowym spawnie
  i raz na rundę survival, otwierane w przysiadzie albo leżąc, losowa zawartość z wagami. Admin: `/givemoney`,
  `/takemoney`, `/setmoney`, `/wallet`, `/moneyreset`, `/shoplist`, `/supplydrop [here]`. Poprawka rundy 18:
  blokady PM wracają po ponownym wejściu (lista nie była tworzona). Sprawdzone na serwerze testowym: zakupy i
  odmowy, działko znika po czasie, pocisk AP wybucha w ścianie, skrzynka spada i bot ją otwiera, `/supplydrop`,
  BuyOnly z botami (cudza broń zabrana, własna wraca po śmierci, `LoseOnDeath` ją zabiera), pieniądze rundy
  survival (18 za zabójstwo + 30 za obrażenia + 100 za przeżycie + 300 za wygraną, 150 za przegraną), broń
  ocalałego w następnej rundzie, 10 botów przez minutę: 3,6% jednego rdzenia. Serwer 2.8.2 pada (Access
  violation), gdy admin TCP łączy się albo rozłącza w trakcie kompilacji skryptu po `/recompile` (Basic-Extended
  kompiluje się ok. 2 s) - opisane w README (Troubleshooting).
- Runda 20 (`BE_API 18`; audyt całości po rundzie 19 i zgłoszenie właściciela z 2026-10-01). Krwawienie:
  bez dużych napisów na środku ekranu (`WoundText` pusty), szybsze bandażowanie (0.7 / 1.6 / 2.5 s) i ostrzejszy
  upływ krwi (0.5 / 1.5 / 4 % na s, `Drain` 1.5), `ReferenceHealth = 65` (rana tak samo często w normalnym
  trybie jak w realistic), linia krwi pokazuje, co krwawi (miejsca, najgorsza rana, ile ich - `HudWound`),
  `{rate}`, zabójczy strzał nie otwiera rany, przerwany bandaż nie traci postępu, worek z krwią w sklepie
  (`BloodBag`). Biblioteka: zapomnienie gracza (wejście, nowa mapa) nie robiło z ludzi botów - bandaż sam po
  10 s, brak ran w pierwszym życiu na mapie; pomocnik powalonego przestaje przy jego śmierci; zdarzenia
  zabójczego trafienia znikają ze śmiercią; pauza gry zatrzymuje rany, krew, szok i czas powalenia
  (`BE_BodyShift`, `BE_MineShift`). Powalenie: reszta serii nie dobija od razu, dobicie zabija w ticku (broń
  wypada), wyjście do widzów kończy powalenie. Linie HUD przebudowane: jedna tabela stanu i jeden nadawca,
  układ liczony z tego, co jest pokazywane, tekst żyje trzy odświeżenia - nie zostaje stara ani podwójna
  linia (zmiana mapy gubiła linię krwi i pieniądze wchodziły na nią). Pociski AP: wybuch w ścianie w ticku,
  w którym pocisk ją osiąga (też gdy pocisku już nie ma; boty i ludzie), test botami: 9 wybuchów, 8 w
  ścianach. Sklep: lista `!shop` po kategoriach w kolorach, stała numeracja, `!shop all` w pomocy; ocaleni
  zachowują kupione flashe i Javeliny; boty kupują po starcie nowej mapy za pieniądze nowej mapy;
  `GainColor`/`BadColor` działają; portfele mapy przetrwają `/recompile`. Ochrona po odrodzeniu 2 s, działa
  na starcie mapy, znacznik w realistic tylko dla drużyny. Skrzynka survival w pierwszej rundzie mapy i
  jedna na rundę (wejścia graczy nie dokładają). Menu BuyOnly i blokady survival wysyłane znowu po zmianie
  drużyny (gra je kasowała). Naprawione: `/freeze` (błąd przy każdym użyciu), tablice słów komend mniejsze
  niż ich limity (skrypt mógł nie wystartować po dodaniu ok. 40 aliasów), `[Permissions] map` dzieliło
  ?map i /map (teraz `mappart`), `[Logger]` zapisywał hasła ZitroStats (`HideArgs`), publiczny radar mógł
  zobaczyć więcej niż `PublicShow` i sięgać 7x dalej (`PublicMaxZoom`), `!radar reset` kasował też HUD,
  `[Spree]` na zabójstwach serwera, `[TimeToKill]` w pauzie i powalający zamiast zabijać, `[Medic]` w DM i
  na powalonych, `/steamadmin add` brał pierwszego pasującego gracza, wyłączenie modułu przez
  `/reloadsettings` zostawiało wyciszenia i powalonych, `/reloadsettings` zabierał wszystkim magazynki,
  regeneracja `damage` uzupełniała krew, TK za zabójstwo miną. Wydajność: AntiSpam w jednym przejściu,
  zapis `mutes.txt` z ticku, `HudPoll` po 1-2 graczy na tick, radar - zmiana fazy użytkowników i limit
  tekstów na tick, AntiCheat i klawisze w turach, sortowane `CfgKeys` i lista banów, błędy liczone per
  miejsce (`/be_status`). Biblioteka: nieczytelny `players.bdb` i `.bak` odkładane na bok (nigdy nie
  nadpisywane), koniec skryptu czeka na dysk najwyżej 3 s, zapis bazy najwyżej co 15 s, nieskończona
  amunicja nie zabiera piły, testy z kontrolą zakresów (`BE_CHECKS`).
- Runda 21 (`BE_API 19`; zgłoszenie właściciela z 2026-10-01: klasy, punkty, uzupełnianie amunicji z jego modu
  Battlefield). `[Classes]`: klasy z listy `List` (domyślnie Assault, Medic, Support, Engineer, Sniper, Recon; do
  10, w ustawieniach czekają jeszcze Grenadier i Marksman), każda z bronią menu (`Primary`, `Secondary`), wyposażeniem
  przy odrodzeniu (`Loadout`: granaty, flashe, miny, claymore'y, Javeliny, kamizelka, bandaż, apteczki, zapasowe
  magazynki - biblioteka `BE_AmmoPlayerExtra`), perkami co sekundę (leczenie w procentach zdrowia, naprawa
  kamizelek, magazynki dla kolegów, szybsze podnoszenie i bandażowanie - `BE_BodyPerk`, pancerz, dłuższe spoty,
  punkty za dystans) i dwiema umiejętnościami `!skill` / `!skill2` (rally, apteczka, skrzynka granatów, działko,
  moździerz, UAV, zrzut skrzynki, opatrzenie się, własna amunicja). `Assign = choice` (`!class`, od razu w ciągu
  `ChangeSeconds` po odrodzeniu, jeśli nic nie użył i nie strzelał), `life` (nowa klasa po każdej śmierci), `round`
  (co rundę survival; ocalały z SurvivalCarry zostaje przy swojej). Losowanie wyrównuje drużynę i daje każdemu
  spróbować każdej klasy (`Balance`, `Repeat`, `Max` w liczbie albo procentach drużyny). Każdy klucz klasy może mieć
  wersję `Realistic`, `Survival`, `RealisticSurvival` - domyślnie w RSCS słabsze leczenie, działko inżyniera 6 s co
  90 s, mniejszy moździerz. Menu broni jedną procedurą dla klas, `BuyOnly` i blokad survival; broń spoza klasy
  podmieniana 3 ticki po odrodzeniu; `ShopClassOnly` (sklep, boty i skrzynki tylko z bronią klasy); `[Medic]` ustępuje
  klasom, które leczą. `[Points]`: punkty bitewne z feedem (obrażenia, zabójstwa, headshoty, asysty, flagi,
  podniesienia, leczenie, amunicja, spot kille, nagrody, skrzynki ...), `!score`, `!scores`, tablica obu drużyn na
  koniec mapy, wynik zostaje po ponownym wejściu na tej samej mapie. `[Resupply]`: w przysiadzie przy swojej
  fladze albo spawnie - magazynki i bandaż (bez komendy, jak `/getammo` z modu). Dwie nowe linie HUD (klasa,
  punkty) w stosie nad amunicją. Sprawdzone botami na serwerze testowym: losowanie z wyrównaniem w CTF 3 na 3 i 4
  na 4, broń zgodna z klasą po `/setclass`, wszystkie umiejętności (działko stoi, skrzynka spada, apteczki na
  ziemi, moździerz), `life` (nowa klasa po śmierci), survival `round` (ocaleni zachowują klasę), wartości RSCS,
  `/reloadsettings` włącza i wyłącza moduły, `/recompile` zdejmuje działka i apteczki klas, tablica punktów przy
  zmianie mapy, 8 botów z umiejętnościami przez 3 minuty bez błędów: klasy 16 us, punkty 19 us, uzupełnianie
  17 us na tick (cały tick ok. 0,96 ms, 8% rdzenia).
- Runda 22 (`BE_API 20`; prośby właściciela po rundzie 21). `[HitFlash]` liczony od `ReferenceHealth = 65` (w normalu
  błysk był krótki, a gra rysuje tekst z małym czasem bladym: 10 ticków to 21% krycia), domyślnie 24-80 ticków; w jego
  ustawieniach włączony. `[Bleeding]`: najwyżej 3 lekkie, 2 ciężkie i 1 tętnicza rana naraz (`MaxGrazes`, `MaxHeavy`,
  `MaxArterial` - biblioteka nie otwiera kolejnej rany pełnego rodzaju), bandaż szybciej: start po 0,25 s bezruchu
  (`StillSpeed` 1.0), 0,5 / 1,2 / 2,0 s. Moździerz spada z nieba (z wolnej kolumny nad celem, do 450 px; pod dachem z
  dachu): każdy pocisk to 4 klastry rozchodzące się w locie, trafiają też gracza w powietrzu. Klasa nie ogranicza
  sklepu: `ShopClassOnly` domyślnie 0, broń kupiona w tym życiu nie jest zabierana (boty też kupują dowolną), z
  `BuyOnly` menu = posiadane + darmowe + bronie klasy, skrzynka daje dowolną broń. Klasy: C4 (`c4 RANGE COOLDOWN`,
  `Loadout c4 N`, `/c4` - wybuch M79 w ciele oznaczonego, zeskrobanie leżąc 3 s), sensor (`sensor SECONDS COOLDOWN
  RADIUS`), wykrywacz min (`detector RADIUS`, biblioteka `BE_MineDetect`); inżynier ma C4 i wykrywacz, zwiadowca sensor.
  `[SteamBan]`: `/bansteam`, `/unbansteam`, `/steambans`, plik `steambans.txt`, sprawdzanie przy każdym potwierdzeniu
  Steam, `BanAlsoSteam` dla `/banr` i `[TeamKill]`. `[BanJournal]`: nazwa gracza przy każdym banie (z banu skryptu, z
  gracza w grze o tym IP/HWID albo z wychodzących z ostatniej minuty), czas do końca w `/banlist`, `/unbanname`.
  `[Teams]`: `Balance` (słowa drużyn pilnują równowagi, `auto` = jak serwer) i `AutoBalance` (martwy gracz większej
  drużyny przechodzi do mniejszej; boty najpierw). `[LagGuard]` (wyłączony): ping, rozrzut i "warpy" (biblioteka
  `BE_LagSet` / `BE_LagWarps`), ostrzeżenie przed kickiem serwera (`Max_Ping` z `soldat.ini`, tylko odczyt), `/lag`,
  opcjonalnie do widzów (nigdy nie wyrzuca). Sprawdzone botami: C4 (oznaczenie i zabójstwo M79 z kredytem), sensor,
  moździerz z nieba, bany Steam (dodanie, lista, zdjęcie numerem, odmowa dla gracza bez Steam), dziennik z nazwą i
  czasem do końca, auto-wyrównanie, `[LagGuard]` z wersją testową (sztuczny ping: ostrzeżenia, przeniesienie do
  widzów, blokada `!j`), testy biblioteki (limity ran, wykrywacz, warpy), 8 botów z umiejętnościami i C4 przez 4
  minuty: 2,9% rdzenia, bez błędów.
- Runda 23 (`BE_API 20` bez zmian, nowe wzory w `be_fx`; ostatnia z sugestii po rundzie 21): `[Insurgents]` - jego
  skrypt Taliban z 2014 jako przełączany tryb z neutralnymi nazwami (każda nazwa i tekst to ustawienie). Jedna
  drużyna (`Team = alpha|bravo|both`) nosi kamizelki: kucanie + skok (`Keys`, jak `[Mines]`; `KeysOverMines`) albo
  `/detonate` odlicza `HoldSeconds` z piknięciem i `ArmText` nad nim, puszczenie przerywa; wybuch to M79 wewnątrz
  każdego widzianego wroga w `CoreRadius` (na pewno wybucha) i wzór z biblioteki (8 wzorów: `classic`, `hawk`,
  `inferno`, `shrapnel`, `ring`, `scatter`, `ied`, `plain`, albo `random`) ze stałego miejsca, najwyżej 48 pocisków
  na tick. Zamachowiec ginie jak od slaya (bez kary za samobójstwo, bez granatu `[Posthumous]`, bez powalenia),
  zabójstwa są jego. Kontra: nie w pierwszych 3 s życia, nie przy wrogim spawnie (`SpawnDistance`), nie z flagą,
  `TeamCooldownSeconds`; zabity w trakcie odliczania - `DeadManChance` (25%, nigdy po headshocie). Boty: 2 wrogów w
  110 px w zasięgu wzroku, 30% na sekundę (bliższy kolega blokuje tylko przy włączonym friendly fire). Linia HUD nad
  amunicją (9. w stosie), `!insurgents`, `/givevest`, `/takevest`, wiersz w `/be_status`, etap `insurgents` w
  `/be_prof`. Klasy: do 20 (z klasami powstańców z `[Insurgents] Classes`, grane tylko przez nich - reszta gra klasy
  z `List`), klucz `Vest`; nowe umiejętności `steal`, `barrage`, `gunship`, `cloak` i perki `crit`, `wounds`,
  `leech`; 8 klas powstańców (Hawk, Healer, Thief, Saboteur, Spotter, Leader, Raider, Mortarman - role z 2014) i 3
  gotowe klasy koalicji do dopisania do `List` (Mechanic z gunshipem, Spy z kamuflażem, Commando z leech).
  Sprawdzone botami: wybuch zabija wrogów obok z kredytem zamachowca (M79), dead man po `/kill`, odmowy (spawn,
  flaga, brak kamizelki), boty same detonują przy wrogach, `/givevest` drużynie i `/takevest`, kradzież broni,
  ostrzał z nieba po ostrzeżeniu, gunship zabija ze "Stationary gun", kamuflaż oddaje broń po 25 s, jego ustawienia
  bez ostrzeżeń (z `[Insurgents]` włączonym i bez `[Classes]`), 10 botów z umiejętnościami i kamizelkami przez 4
  minuty: 4-6% rdzenia, `insurgents` 53 us na tick, bez błędów.
- Runda 24 (`BE_API 21`; uwagi właściciela po grze na rundzie 23). Krwawienie: przy `DeathBlood` nie ma już nagłej
  śmierci - `BleedOut = drain`: póki rana krwawi, życie spada coraz szybciej (`OutDrain` + `OutDrainGrow` za każdy
  punkt krwi poniżej, co pół sekundy, `OutText` na środku ekranu), bandaż albo apteczka ratują; najwyżej jedna
  rana każdego rodzaju, lekkie częściej (`ArterialShare` 12 -> 6, `HeavyShare` 45 -> 25), więcej bandaża (130,
  medyk i uzdrowiciel 250); bandażowanie w swobodnym spadaniu bez klawiszy ruchu (`AirBandage`, biblioteka
  `BE_BodyAir`); kamizelka chroni tułów przed raną (`VestTorso`, `BE_BodyCover`); medyk (perk `firstaid RADIUS`,
  `BE_BodyMedic`) bandażuje kolegów obok swoim bandażem, najpierw siebie; szok i powalenie w powietrzu - gracz spada
  (wcześniej wisiał). `[Ammo] CombatKnife` 0 (drugi nóż po rzucie był tym zapasem). Klasy: `Assign = map` (jedna
  klasa na mapę, zapamiętana po HWID i koncie - wyjście i powrót nie losuje nowej) i `limited` (wybór, ale klasa,
  której drużyna ma o `LimitedSpread` więcej niż najrzadszej, jest odrzucana), `ChoiceText` przy dołączeniu i
  pierwszych `ChoiceTimes` śmierciach mapy, `{choose}` w linii klasy; `!skill`/`!skill2` także jako `/cc1`, `/cc2`,
  `/smoke`, `/tabac` (Alt+1, Alt+2 gry; `[FlashNades]` oddaje te słowa, gdy klasy są włączone, a gdzie są
  bezczynne, słowa przełączają granat jak wcześniej); broń z menu w pierwszych 3 s życia sprawdzana ponownie
  (opóźnione menu gracza z lagiem); rally dla każdego kolegi, który się odrodzi w czasie trwania (bez promienia),
  przy ostatnim gruncie wzywającego, z komunikatem, czemu nie (flaga, powalenie); zwiadowca widzi wrogie miny z 400
  px. Skrzynka i moździerz nigdy w ścianie (biblioteka: punkt w ścianie najpierw wychodzi w górę, podłoga musi mieć
  miejsce nad sobą). Sprawdzone: testy biblioteki (wykrwawianie, bandaż w locie, medyk siebie i potem kolegę,
  kamizelka, ziemia w ścianie na ctf_Ash), na botach: `map` (ten sam bot po powrocie ma tę samą klasę, nowa mapa
  losuje), `limited` odmawia, aliasy, rally (zabity kolega wraca przy Assaulcie), medyk opatrzył kolegę, śmierć z
  wykrwawienia z kredytem strzelca, 10 botów przez 4 minuty: tick 1,16 ms, krwawienie 40 us, bez błędów.
- Runda 25 (pytanie właściciela: dwa aktywne rally naraz): rally drużyny biorą kolegów po kolei - ten, który
  najdawniej dostał kolegę, pierwszy (nowe rally od razu), więc każdy wzywający dostaje wsparcie; rally, które w tej
  chwili nie może przyjąć (powalony, flaga, w powietrzu bez znanego gruntu), jest pomijane na rzecz innego; wzywający
  słyszy, kto wrócił przy nim. Sprawdzone botami: dwa Assaulty z rally, dwóch kolegów ginących dwa razy - wracali na
  zmianę przy jednym i drugim (4 powroty).
- Przegląd martwych ustawień: `[Aimbot] MuzzleFlash` działa (płomyk u wylotu lufy), `[Ammo] CombatKnife`
  działa, `[Looting] CorpseLooting` usunięte (dublowało `Enabled`), `[Medic] CooldownSeconds` liczone od
  końca leczenia, `[Aimbot]` / `[Trajectory] Enabled = 0` po `/reloadsettings` wyłącza je graczom,
  `[HealthHud] SavePlayers = 0` nie wczytuje starych wyborów, `[Logger] Watch-N` z komentarzem `//` dla
  IP i nicków, ostrzeżenie dla złego `ExtraShotsMode`, poprawione opisy (players.bdb, bez [HitMarker]).
- Runda 26 (`BE_API 23`; zgłoszenie właściciela z 2026-10-05: flaga, pełny audyt całego kodu, wydajność w DLL,
  balans klas, gotowe zestawy configów). Audyt w 12 częściach (skrypt, biblioteka, spójność modułów) - wszystkie
  ustalenia i decyzje w `PLAN_Round26_Audit.md`. Flaga: `FlagGrab` płaci raz, dopóki flaga nie wróci do bazy przez
  przejęcie albo zwrot wroga (podniesienie, odrzucenie na miejsce i ponowne podniesienie nic nie daje), `FlagReturn`
  tylko za flagę, którą wziął wróg. Wynik i pieniądze: koniec rundy survival rozpoznany tylko po dokładnych ciosach
  serwera (4000, 1000 z kamizelką, 16000 berserker) i potwierdzony tick później (`/brutalkill` i admińskie `/kill`
  nie są już końcem rundy z pieniędzmi dla drużyny); `DamageLimit` (sklep i punkty: życie płaci najwyżej 150%
  zdrowia - leczenie i podnoszenie nie są farmą), `RepeatKillPercent` (to samo zabicie w minucie), mnożnik botów
  także dla headshota, asysty i obrażeń, broń zabójstwa z pocisku, nie z rąk; zemsta raz na minutę dla pary,
  podniesienie tylko powalonego przez wroga, `KitTaken` tylko gdy kolega potrzebował i raz na minutę, dystans tylko
  własnym pociskiem; tablica na końcu mapy z 4 drużynami. Klasy: menu broni zmienia się w chwili śmierci (ekran
  śmierci pokazuje broń następnej klasy), boty używają umiejętności (`[Classes] BotSkills`), Recon do wyboru
  `SkillSpots = marks|radar` (znaczniki nad wrogami albo radar drużyny tylko w czasie UAV/sensora), cooldowny należą
  do umiejętności i zostają po wyjściu i powrocie na tej samej mapie, zerują się co rundę survival; zmiana drużyny
  kończy działające umiejętności i daje klasę nowej drużyny (limit klasy po tamtej stronie); C4 uzbraja się po 2 s,
  nie z ziemi; moździerz i ostrzał wymagają nieba nad celem; cel tylko widziany (realistic: przed nim); umiejętności
  ataku kończą ochronę po respawnie; slot 32 (serwer nie robi tam pocisków) odmawia moździerza, ostrzału, gunshipa,
  C4 i kamizelki. Balans: Support z Minimi, AUG albo Spasem (Minigun 1.7.1 jest niegrywalny; w sklepie zostaje, skrzynki
  pomijają tylko broń, której sklep nie sprzedaje), dwie claymore, skrzynka co 50 s dla całej drużyny (każdy bierze raz, póki leży),
  resupply co 30 s (60 w survival) z granatami jego klasy; Assault 3 granaty, kit co 30 s (60 w survival); Engineer
  jedno C4 (`c4 200 20`), działko w survival 20 s co 120 s; Medic w survival `heal 3 100`; Mechanic, Spy, Commando,
  Hawk, Raider, Grenadier, Saboteur poprawione; Barrett 1200, `StatgunPlaced` 0. Antycheat (zgłoszenie
  właściciela): szybkość strzałów oceniana po serii 5 trafień (mediana odstępu, para trafień jednego strzału to
  jeden strzał), magazynek "w 17 ms" tylko gdy hak serwera widział tyle strzałów, nigdy dla strzelb. Amunicja:
  przeładowanie skończone przed odłożeniem broni jest płatne (Q po każdym przeładowaniu nie daje już magazynków),
  podniesienie nie myli się z bronią z menu ani z bronią, którą serwer zabrał po 20 s, piła z pustym bakiem odchodzi,
  uzupełnienia tylko dokładają, luźne naboje da się złupić. Pauza przesuwa wszystkie zegary skryptu; jeszcze dziesiątki
  drobniejszych poprawek (spotting oślepionego, flash nie oślepia chronionego po respawnie, `/kill` powalonego =
  poddanie się, zapalnik miny tylko tej samej miny, `ShopOnly` osobno dla min i claymore, słowa drużyn według trybu,
  `/ip` z niejednoznaczną nazwą pyta, bany sprawdzane po 50 na tick, dzienniki czytane od końca ...). Wydajność w
  DLL: HUD (miejsca dziewięciu linii, co gra gracza pokazuje, odświeżenia) w bibliotece (`be_hud`; 261 -> około 94
  us na tick przy 10 graczach widzących teksty), lista ran linii krwi i linie klasy, wyniku i pieniędzy jednym
  wywołaniem, `[AntiSpam]` waży linię czatu w bibliotece, `mutes.txt` zapisuje wątek biblioteki; żołnierze czytani
  z pamięci serwera (`[General] MemoryReads`: broń, naboje, klawisze i celownik znalezione przez dopasowanie
  wartości na dwóch żołnierzach, co sekundę porównanie jednego żołnierza ze wszystkimi 12 klawiszami, przy różnicy
  wyłączenie na stałe) - amunicja wszystkich żołnierzy jednym wywołaniem (178 -> 60 us na tick przy 10 botach).
  Rekord klawiszy 2.8.2 ma inny układ niż dzisiejsze źródło (Left, Right, Up, Down, potem celownik, potem Fire ...
  FlagThrow) - wykryty na żywym serwerze testowym, biblioteka zna oba. `Example configs/`: 19 zestawów
  generowanych z jednego pliku domyślnego (`default`, `ctf`, `inf`, `htf`, `tm`, `dm`, `rscs`, `rs`, `rsa`, `rsdm`,
  `shop`, `tw`, `ttw`, `battlefield`, `insurgents`, `hardcore`, `casual`, `clean`, `light`), każda zmiana oznaczona
  `; SET`, każdy zestaw ładuje się bez ostrzeżeń. `settings.ini`: nowe klucze z opisami, balans klas i poprawione
  opisy tylko tam, gdzie wartość była jeszcze domyślna. Niezgodne API biblioteki: skrypt się nie uruchamia (głośna
  linia w konsoli) zamiast działać w połowie; na Linuksie trzeba przebudować `basicext_dll.so`. Sprawdzone: testy
  biblioteki (nowe: zapis całego pliku, strzały w serii, HUD, lista ran, ważenie czatu, łupienie luźnych nabojów,
  rekordy żołnierzy w obu układach), na botach: kalibracja pamięci i 107 kontroli bez różnicy, 49 użyć umiejętności
  przez boty w 100 s (C4, rally, apteczki, działko, skrzynki), profil przed i po, wszystkie zestawy configów.
  Sprzątanie (prośba właściciela po wdrożeniu): skrypt i biblioteka bez nieużywanego kodu - zmienna `Tm`, zmienne
  tylko zapisywane, `LoadData`, 24 eksporty, których skrypt nie wołał, i funkcje, do których prowadziły tylko one,
  kalibracja mostu pociskami próbnymi (tablicę pocisków znajduje sygnatura kodu serwera; `test_bridge` sprawdza tę
  drogę), pierścień obiektów haka, którego nikt nie czytał, martwy klucz rakiety `TopLoft`, parametry, których nic
  nie czytało (cztery w eksportach, stąd `BE_API 23`). Zostają celowo: pełne tabele kodów, sygnatury zdarzeń gry
  i cztery małe funkcje używane tylko przez testy.
  Bez przeciwnika nie ma zarobku (zgłoszenie właściciela: gracz nabijał punkty sam na serwerze, gdy wszyscy siedzieli
  na specu albo gdy dwóch grało w jednej drużynie bez przeciwnika): `[General] Opponents = any|humans|off` - bez
  nikogo z innej drużyny w grze (w trybach bez drużyn: bez nikogo innego; spectatorzy się nie liczą) nie ma punktów
  `[Points]`, pieniędzy `[Shop]` (także `income` i pieniędzy rundy; skrzynka daje wtedy coś innego niż pieniądze),
  punktów dodatków (`[Medic]` i inne) ani min za przejęcie flagi; kary (samobójstwo, obrażenia drużyny) liczą się
  dalej. `any` liczy bota jako przeciwnika, `humans` tylko człowieka, `off` płaci jak dawniej. `NoOpponentText`
  mówi graczowi raz, czemu nic nie wpadło. Sprawdzone botami: dwa boty jednej drużyny brały i przejmowały flagę
  bez punktów i pieniędzy, po dojściu bota drugiej drużyny przejęcie dało 250 pkt i pieniądze.
- Wydanie 4.0.0 (2026-10-05, publikacja na GitHubie od nowa): rundy 6-26 jako wersja 4.0 (`VERSION` w `main.pas`,
  nagłówki `settings.ini` i zestawów); README gotowe do publikacji (instalacja z ZIP-a GitHuba - folder musi się
  nazywać `Basic-Extended`, `config.ini` zamiast `scripts.ini`, `basicext_dll.so` dołączony do wydania, aktualizacja z 3.5,
  `/ip` i `/hwid`, dziewięć linii HUD, dodatki walki i podstawy w opisie konfiguracji); magazyn graczy biblioteki
  sam zakłada folder `data` (git nie przechowuje pustych folderów, więc świeża instalacja go nie ma); post na
  forums.soldat.pl w `Message.txt` (SMF 2.0.11: sam ASCII, bez podwójnych spacji poza `[code]`).
  `build.sh` i `clean.sh` uruchomione przez `sh` same usuwają windowsowe końce linii (kopia z Windowsa dawała
  `cannot execute: required file not found`); w repo `.gitattributes` trzyma je z LF.

## FlashNades i ExtraRocket: co poprawiono względem starych skryptów

| Stary skrypt | Problem | W Basic-Extended |
| :--- | :--- | :--- |
| ExtraRocket | Pętla lotu z `Sleep` (40 -> 7 ms na krok, 45 kroków): serwer stał ok. pół sekundy przy każdej rakiecie; API ScriptCore 2 (`GetPlayerStat`, `AppOnIdle`), `Includes.txt` pusty. | Lot liczony co tick w DLL (`be_rocket`) jak pocisk kierowany: ciąg, opór, skręt zależny od prędkości, nawigacja proporcjonalna, omijanie ścian, atak z góry; skrypt dostaje zdarzenia (płomienie, dźwięki, wybuch). Żadnego czekania. |
| ExtraRocket | Strzał LAW-em i rakieta naraz (ForceWeaponEx z amunicją 255 nie zawsze zdążał przed rozruchem LAW). | Klawisze bez strzału (crouch + reload, na leżąco sam reload: przeładowanie nic nie robi naładowanemu LAW); rakieta startuje z naładowanego LAW, który się przeładowuje, a runda wraca (`Launcher = reload`; `round` zabiera ją z zapasu, `free` nie rusza LAW). |
| ExtraRocket | Rakieta leciała od razu po wciśnięciu, bez żadnego sygnału dla strzelca. | Namierzanie `LockSeconds` z celownikiem zaciskającym się na celu (zgubiony z oczu = koniec), dźwięki: namierzanie, wyrzut, zapłon, silnik. |
| ExtraRocket | Zabójstwo na liście jako "Stationary gun" albo M79 (styl pocisku wybuchu). | Wybuch to kolumna prawdziwych rakiet LAW; most wpisuje w nie LAW oraz punkt i czas startu (ikona LAW na liście, dystans i czas lotu pod "You killed", LAW w ZitroStats); `HitPercent` (domyślnie 0) odbiera najpierw część zdrowia. |
| ExtraRocket | Dwie wersje pliku (amunicja na życie / na mapę), stałe w kodzie, komunikaty co 10 ticków. | `Refill = life/map`, wszystko w `settings.ini`, komunikaty raz na wciśnięcie, `!rocket`. |
| FlashNades | Co tick skan 254 slotów pocisków i BigText (HUD) do każdego gracza co tick; `TStringList` z liczbami jako tekst dla każdego gracza. | Hak w `CreateBullet` zgłasza rzut od razu (bez haka: skan co 2 ticki do najwyższego zajętego slotu); HUD wysyłany tylko przy zmianie; tablice. |
| FlashNades | Napisy "Nade!/Flash!" na warstwach 41 + slot (do 295, poza zakresem), co tick do każdego widza. | Tylko flash ma znacznik: pierścień `O` wyśrodkowany na granacie; pula `LabelLayers` warstw, przesuwany co `LabelTicks` tylko gdy granat się rusza, zdejmowany `' '` po wybuchu, limit tekstów na tick. |
| FlashNades | Flash wybuchał na serwerze jak granat (odrzut, obrażenia poprawiane dopiero w `OnDamage`). | Flash usuwany z serwera tuż przed wybuchem (`Defuse`): bez odrzutu i obrażeń serwera, efekt robi skrypt. |
| FlashNades | Obrażenia poza 85 px zostawały pełne (błąd w `NadeDamage`), `SelfFlash` oślepiał rzucającego przy każdym oślepionym wrogu. | Obrażenia flasha tylko w `DamageRadius`, bez ściany; `Affects = all/enemies/enemiesself` liczone dla każdego gracza osobno. |
| FlashNades | "AntyNadeMove" zapisywał co tick prędkość każdego gracza jako tekst (`FloatToStr`). | Pozycja i prędkość czytane w ticku po wybuchu (odrzut gry przychodzi tick później - sprawdzone na serwerze testowym), `NoPushTicks`. |
| FlashNades | Warstwy BigText 36/37/38 kolidowały z Assists/SelfKill/TimeToKill; zajmował `/help`; `Game.MaxGrenades` zostawało 1 po wyłączeniu skryptu. | Własne warstwy (HUD 195, podpowiedź 194, ekran 250, napisy 80-87), tylko `/flashhelp`; `Max_Grenades` przywracane przy wyłączeniu i przy `/recompile`. |
| FlashNades | Granat wybuchający w tej samej klatce, w której bot go rzucił, nie był rozpoznawany. | `OnDamage` czyta zgłoszenia haka od razu, więc i taki flash ma swoje obrażenia. |
| tk | ScriptCore 2; 16 graczy; obrażenia drużyny liczone tylko w realistic (gałąź dla zwykłego trybu zagnieżdżona w realistic, nigdy nie działała), progi dokładne - skok przez przedział omijał karę; punkty znikały przy wyjściu i zmianie mapy; wyzwiska. | Punkty z celowości (linia każdego strzału względem szkieletów), spray blokowany od razu, drabina kar z banami x2, punkty topnieją i idą za Steam id, menu ofiary zostało (`!1`-`!4`), tryby gry i friendly fire sprawdzane same, dziennik. |
| Mines | Sprawdzanie raz na sekundę (`OnClockTick` przy domyślnym progu) - biegnący przebiegał minę bez wybuchu; co sprawdzenie 32 x 32 graczy z odczytami właściwości; mina nie działała, gdy właściciel był bliżej niż 80 px (także martwy lub po wyjściu - stara pozycja); jedna mina mogła wybuchnąć kilka razy naraz; w DM nigdy (drużyna 0 = 0) i bez zabójstw w DM; flagi czytane tylko na pierwszej mapie (`AfterMapChange` nieprzypięte); niewidoczna nawet dla właściciela; po zmianie drużyny mina zmieniała stronę; M79 skryptu w ziemię odbija się albo leci przez podłogę tylko dla graczy. | Co tick w DLL względem szkieletów (tylko żołnierze blisko miny), uzbrajanie, jedno odpalenie, DM i drużyny, bazy flag i spawny liczone na każdą mapę, znaczniki dla właściciela i drużyny (wrogowie po znalezieniu), rozbrajanie i przejęcie, podnoszenie, strzał w claymore, łańcuch, wybuch prosto w ofiarę, claymore kierunkowy z drutem, limity, wszystko w `settings.ini`. |

Koszt (serwer testowy, 10 botów rzucających granaty): cały tick skryptu ok. 370 us zamiast 320 us; granaty ok.
30 us na tick, rakiety 8 us na tick (klawisze sprawdzane co 3 ticki, broń z odczytu systemu amunicji). Po
przeniesieniu lotu do DLL (6 walczących botów, wszystko włączone): cały tick ok. 395 us, granaty i noże
15 us, rakiety 17 us na tick; rakieta w locie to jedno wywołanie DLL na tick plus płomienie śladu.

## Do dopracowania

- FlashNades / ExtraRocket: wygląd białego ekranu (`Method`, `Char`, skale i przesunięcia) przepisany ze
  starego skryptu - do sprawdzenia w grze na 1.7.1 w różnych rozdzielczościach; opóźnienie "NoPush" u
  graczy z dużym pingiem (ich gra odpycha ich od razu); ewentualnie osobne ustawienia dla botów-celów.
  Do obejrzenia w grze: pierścień flasha po rundzie 11 (`MarkScale`, `MarkOffsetX/Y`), celownik
  namierzania (`LockScale`), gęstość śladu rakiety (`TrailSpacing`) i dźwięki silnika.
- ZitroStats a Javelin: start opróżnia LAW, gdy strzelec trzyma reload, a ZitroStats (`main.pas`: klawisz
  reload w ticku, w którym magazynek pustoszeje) bierze to za przeładowanie jednej rundy - liczy
  przeładowanie LAW, a zabójstwo zostaje bez dystansu. Decyzja właściciela (29.09): zostaje tak, ZitroStats
  dostanie kiedyś osobny update (mógłby wtedy wziąć dystans i czas lotu z `BE_BulletOrigin`).
- Biblioteka ma teraz `BE_API 15` (rakiety, `BE_TextInk`, `BE_MapColliderRay`, `BE_BridgeSetOrigin`,
  `BE_AmmoKeep`, `BE_AmmoLimit`, `BE_SpriteEyes`, `BE_SpritePoint`, `BE_BulletOrigin`, `BE_SpriteBind`, `BE_Tk*`,
  `BE_Mine*`, `BE_Body*`, `BE_SpriteStance`, `BE_SpotSet`, `BE_SpotClear`, `BE_AmmoCarry*`, `BE_AmmoLeftOf`,
  `BE_AmmoRefill`, `BE_AmmoPause`; od rundy 18 `BE_API 16`: `BE_Names*`; od rundy 19 `BE_API 17`:
  `BE_ShopApPredict`, `BE_ShopGround`, `BE_AmmoAddMags`, `BE_AmmoTopUp`; od rundy 20 `BE_API 18`:
  `BE_BodyPlaces`, `BE_BodyTransfuse`, `BE_BodyPerk`, `BE_BodyShift`, `BE_MineShift`; od rundy 21 `BE_API 19`:
  `BE_AmmoPlayerExtra`; od rundy 22 `BE_API 20`: `BE_LagSet`, `BE_LagWarps`, `BE_LagReset`, `BE_MineDetect`; w rundzie
  23 nowe wzory wybuchów w `be_fx` bez nowych eksportów; od rundy 24 `BE_API 21`: `BE_BodyAir`, `BE_BodyMedic`,
  `BE_BodyCover`; od rundy 26 `BE_API 23`: `BE_Hud*`, `BE_SpriteCalibrate`, `BE_SpriteCheck`, `BE_AmmoPass`,
  `BE_ChatWeigh` i inne, bez eksportów, których skrypt nie wołał, m.in. `BE_SpriteStance`, `BE_AmmoCarryKept`,
  `BE_Pref_Get`): wersja linuksowa (`.so`) wymaga przebudowania (`build.sh`).
- Krwawienie i klasy po rundzie 24: do obejrzenia z ludźmi - `OutText` i tempo wykrwawiania (`OutDrain`,
  `OutDrainGrow`), bandaż w locie (boty nie naciskają klawiszy), medyk przy rannym koledze (boty rzadko kucają),
  `ChoiceText` i `{choose}`, sprawdzenie broni graczy z dużym pingiem.
- `[Insurgents]`: do obejrzenia w grze z ludźmi - klawisze kamizelki (kucanie + skok trzymane `HoldSeconds`; boty
  klawiszy nie naciskają), napis `!!!` i piknięcia, linia `Vest:` nad amunicją, `JoinText`; siła wzorów (`Power`,
  `CoreRadius`) i chęć botów (`BotRadius`, `BotChance`) do strojenia po kilku wieczorach. Kamuflaż to bonus
  predatora gry (25 s) - wcześniejsze zakończenie wymagałoby zapisu w pamięci serwera.
- `[LagGuard]`: do ustawienia na prawdziwych graczach (boty nie mają pingu ani warpów) - `WarpPixels`, `WarnPing` i
  progi widzów po kilku wieczorach z `/lag`.
- Klasy: do obejrzenia w grze z ludźmi - menu broni klasy (boty menu nie używają), linie klasy i punktów nad
  amunicją, napis ostrzeżenia moździerza (`MORTAR`, `MortarLayer`) i tablica na koniec mapy (`BoardLayer`);
  balans klas (wartości domyślne to punkt wyjścia: `heal`, `Max`, czasy umiejętności) do strojenia po kilku
  wieczorach gry.
- Krwawienie i powalenie: do obejrzenia w grze czarny ekran szoku (`ShockScale`, `ShockOffsetX/Y` - przepisane z
  białego ekranu flasha), linia krwi nad amunicją, napisy bandażowania i podnoszenia, znacznik powalonego
  (`Mark`); boty AI dobijają powalonych wrogów (tak gra je prowadzi), a do powalonego kolegi same nie
  podchodzą - podnoszą go tylko, gdy akurat są obok.
- Miny: do obejrzenia w grze wygląd znaczników (`MineMark`, `ClaymoreRight/Left`, `WireMark`, skale, kolory)
  i klawisze sadzenia (skok + kucanie: szybkie stuknięcie nie powinno podskakiwać - sprawdzone tylko w
  źródłach gry, boty nie naciskają klawiszy).
- Haki na Linuksie: kod jest (szukanie po `/proc/self/maps`, `mprotect`), ale nie był budowany ani
  sprawdzony na serwerze linuksowym (`build.sh`).
- Odczyt stanu graczy wprost z pamięci serwera: rekord żołnierza jest już znaleziony (runda 12, szkielet).
  Amunicja i aimbot czytają dziś po kilka właściwości ScriptCore na gracza na tick (ok. 20 us na gracza);
  pola tego rekordu w DLL zdjęłyby to ze skryptu. Szkielet zastąpił już stałe wysokości w widoczności
  trybu realistic (runda 13); zostaje cel Javelina (dziś stałe 10-11 px nad stopami).

## Czego nie da się zrobić ze skryptu

- Ustawić kursora ani wcisnąć klawiszy człowiekowi - settery `MouseAimX/Y` i `Key*` działają
  tylko na boty (serwer i tak nadpisuje je pakietami klienta).
- Ukryć strzału ani granatu przed graczami - `Map.Bullets` jest tylko do odczytu, a most (`BE_BulletKill`)
  usuwa pocisk tylko z serwera: gry graczy i tak go pokazują i wybuchają u siebie (bez obrażeń serwera).
- Zobaczyć pudeł - serwer daje skryptowi tylko trafienia (`OnDamage`).
- Wysyłać własnych pakietów z DLL - połączenia prowadzi serwer (szyfrowanie, numeracja, reliable);
  obce pakiety na tym samym porcie klient odrzuci albo rozsypią stan połączenia.
- `Game.StartRecord`, `Player.Kill` i `Player.Say(Text, MsgType)` - nie ma ich w 2.8.2 (albo działają
  inaczej niż w nowszych wersjach): `/slay` zabija obrażeniami, `/sayas` pisze liniami konsoli w
  formacie i kolorach czatu gry.

## Dlaczego WorldText / BigText potrafią lagować

Z kodu Soldata (1.8, ta sama logika co 1.7.1):

- Każdy `WorldText` / `BigText` to osobna wiadomość *reliable* do jednego gracza (25 bajtów + tekst,
  z potwierdzeniem i ponowieniem), bez scalania i bez limitu po stronie serwera. Dużo tekstów naraz to
  dużo małych pakietów i ponowień; przy słabszym łączu kolejka rośnie i teksty przychodzą z opóźnieniem.
- Klient co klatkę przegląda wszystkie 256 warstw BigText i 256 WorldText. Dla każdego widocznego
  tekstu wybiera font po rozmiarze (liniowe szukanie tabeli, `FT_Request_Size`), liczy układ liter
  (kerning) i rysuje każdą literę dwa razy (tekst i cień).
- Każdy **nowy rozmiar** (skala * rozdzielczość) tworzy nową tabelę glifów, której klient nigdy nie
  zwalnia; brakujące litery renderuje FreeType i wgrywa do atlasu tekstur, a gdy atlas się zapełni,
  dokłada nową stronę (np. 2 MiB przy 1080p). Animowanie skali = ciągłe renderowanie i rosnąca
  pamięć. Dlatego skrypt trzyma stałe skale (także w edytorze) i wysyła tylko zmienione teksty.
- Tekst ze zbyt dużą skalą (WorldText 1.0 to ~288 pt przy 1080p) jest rozciągany z mniejszego;
  litery większe niż strona atlasu w ogóle się nie rysują.

Własne pakiety z DLL nie rozwiązują problemu: koszt jest po stronie klienta (rysowanie i fonty) i w
kanale reliable, a DLL nie może bezpiecznie wejść w połączenia serwera.
