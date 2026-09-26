# Basic-Extended - plan rozbudowy

Stan po wersji 3.3 i propozycje na kolejne wersje, od najbardziej opłacalnych. Każdy punkt ma
krótkie uzasadnienie i szacunek pracy (S - godziny, M - dzień, L - kilka dni).

## Co już jest (3.3)

- Geometria mapy w bibliotece: raycasty radaru (`seen`), trajektorii, aimbota, mgły wojny i teleportu
  liczone natywnie (zgodność ze serwerem sprawdza `/be_status`).
- Trajektoria: przeliczana tylko przy zmianie wejścia, start z prawdziwej lufy, rysowana tylko w
  polu widzenia (także przy zoomie Barretta i śledzeniu pocisku).
- Teleport: `/teletomouse` przy trzymaniu skręca i zawraca (kompensacja opóźnienia kamery po skoku),
  `/flytomouse` szybszy (11 na oś, 15.5 po skosie) z mniejszą martwą strefą.
- Aimbot: prawdziwy magazynek i przeładowanie, `/aimbot acc`, model niecelności gry, pociski z lufy.
- Komendy adminów: `all`, drużyny, nazwy (także w cudzysłowie), `/give` z amunicją i `near`,
  `/bonus` od razu (GiveBonus), `/statgun`, `/removestatgun`, `/infammo`, `/dmgfix`, `/dmgtaken`,
  `/vest`.
- Radar: pierścień kropek zamiast strzałek, osobne ustawienia każdego trybu, opcja drużyny.
- Anty-cheat (statystyki): start-up Barretta, fire interval, teleporty, trafienia z binkiem i w ruchu,
  headshoty, `/suspects`, `/acstats`, log i historia per komputer.
- Tańszy snapshot graczy (jedno wywołanie DLL na gracza zamiast tablic).

## 1. Wydajność (najważniejsze dla serwera)

| Zadanie | Dlaczego | Praca |
| :--- | :--- | :--- |
| Skan pocisków supresji w DLL z pamięcią slotów | Dziś każdy aktywny pocisk to ~6 odczytów właściwości co 4 ticki; DLL może pamiętać właściciela i styl slotu, a skrypt czytać tylko X/Y. Ok. 40% mniej pracy w walce. | M |
| Odpytywanie zdrowia (HUD) jednym wywołaniem na gracza | Ten sam zysk co przy snapshocie: tablice w PascalScript kosztują tyle co wywołanie DLL. | S |
| Adaptacyjne odświeżanie radaru | Gdy nikt się nie rusza, nie ma po co liczyć; gdy dużo ruchu, najpierw najbliżsi. | M |
| Budżet tekstów na cały serwer | Dziś limity są na gracza; wspólny limit na tick wygładzi skoki (np. `/nuke` + radar + trajektoria naraz). | S |
| Pomiar na serwerze Windows | `/be_bench` i `/be_status` na prawdziwym 2.8.2 - koszty odczytów bywają inne niż na Linuksie. | S |

## 2. Anty-cheat 2.0

| Zadanie | Jak | Praca |
| :--- | :--- | :--- |
| Aim-snap (aimbot u ludzi) | Dla graczy z wysokim wynikiem próbkować MouseAim co tick i szukać skoków kąta tuż przed trafieniem. Tylko dla podejrzanych, więc tanio. | M |
| Kierunek pocisku vs celownik | Porównać kierunek trafiającego pocisku z MouseAim w chwili strzału (statystycznie, bo serwer zna kursor z dokładnością ~30 px). | M |
| Tempo broni automatycznych | Spadek amunicji z pakietów broni (co 5-7 ticków) vs FireInterval. | M |
| Speed hack | Średnia prędkość z kolejnych snapshotów powyżej fizyki gry przez dłuższy czas. | S |
| Strzały "przez ściany" | Z geometrią mapy: trafienie, którego tor przechodzi przez ścianę blokującą pociski. | S |
| Przegląd dla admina | `/acreview <gracz>` - ostatnie zdarzenia z logu; eksport historii do pliku (np. CSV) do przeglądania poza grą. | S |
| Akcje automatyczne (opcjonalne) | Kick/ban dopiero przy wysokim wyniku i minimalnej liczbie pomiarów; domyślnie wyłączone. | S |

## 3. Radar i HUD

- Znaczniki flag i celów na radarze (pozycje flag z `Map.RedFlag` / `BlueFlag`). S
- "Radar dźwiękowy": kierunek niedawnych strzałów wrogów w pobliżu (dane ze skanu pocisków). M
- Uproszczony zarys mapy w trybie `circle` (geometria jest już w DLL; trzeba ograniczyć liczbę
  tekstów, np. kilka linii kropek). L

## 4. Narzędzia admina (z ukrytego API ScriptCore 3)

| Komenda | Na czym | Praca |
| :--- | :--- | :--- |
| `/record <nazwa>`, `/stoprecord` | `Game.StartRecord` / `StopRecord` (demo `demos/<nazwa>.sdm`) - nie ma ich na wiki. | S |
| `/weaponmod <nazwa>` | `Game.LoadWeap` - wczytuje `configs/<nazwa>.ini` w locie (resetuje timery broni graczy). | S |
| `/setspawn`, własne punkty odrodzenia | `OnBeforePlayerRespawn` zwraca `TVector` - pozycję odrodzenia (wiki podaje błędny typ). | M |
| `/kill <gracz>` bez obrażeń | `Player.Kill()` - liczy się jako samobójstwo. | S |
| Wiadomości drużynowe od skryptu | `Player.Say(Text, MsgType)` - drugi parametr (0-3) nie jest na wiki. | S |

## 5. Tryby gry z gotowych klocków

Z `/give`, `/infammo`, `/dmgfix`, `/dmgtaken`, `/vest` i bonusów da się złożyć:
Gun Game (kolejna broń za zabójstwo), Juggernaut (jeden gracz z dużą odpornością), Instagib
(`/dmgfix all x10`), walka na noże, Zombie (drużyna z mnożnikiem obrażeń i bez broni palnej),
rundy turniejowe z gotowością drużyn. Każdy tryb to M.

## 6. Inżynieria

- GitHub Actions: build DLL (win32 i linux), testy jednostkowe, harness ABI PascalScript. M
- Podział `main.pas` na pliki (moduły skryptu) dla łatwiejszego rozwoju. M
- Wspólne dane z ZitroStats (np. wynik anty-cheatu przy statystykach gracza). M

## Czego nie da się zrobić ze skryptu

- Ustawić kursora ani wcisnąć klawiszy człowiekowi - settery `MouseAimX/Y` i `Key*` działają
  tylko na boty (serwer i tak nadpisuje je pakietami klienta).
- Usunąć pocisku ani ukryć strzału gracza - `Map.Bullets` jest tylko do odczytu.
- Zobaczyć pudeł - serwer daje skryptowi tylko trafienia (`OnDamage`).
- Wysyłać własnych pakietów z DLL - połączenia prowadzi serwer (szyfrowanie, numeracja, reliable);
  obce pakiety na tym samym porcie klient odrzuci albo rozsypią stan połączenia.

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
