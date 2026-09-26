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
- `Example configs/`: ctf, inf, htf, tm, dm, rscs (survival + realistic), clean.

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

## Zablokowane w tym środowisku (do decyzji autora)

- Broń zabójstwa z aimbota (Deagle zamiast prawdziwej broni, także w ZitroStats): `Map.CreateBullet`
  daje pociskowi pierwszą broń z danym stylem pocisku. Naprawa wymaga zapisu do pamięci serwera
  (numer broni pocisku) - to "most" do procesu serwera; narzędzie, w którym powstaje kod, blokuje
  tę zmianę (można ją dopuścić regułą uprawnień w ustawieniach Claude Code albo zrobić ręcznie).

## Czego nie da się zrobić ze skryptu

- Ustawić kursora ani wcisnąć klawiszy człowiekowi - settery `MouseAimX/Y` i `Key*` działają
  tylko na boty (serwer i tak nadpisuje je pakietami klienta).
- Usunąć pocisku ani ukryć strzału gracza - `Map.Bullets` jest tylko do odczytu.
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
