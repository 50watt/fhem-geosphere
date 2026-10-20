# Testnachweis GeoSphereAPI 0.2.9

20.10.2026, Perl 5.40.1, Python 3.13, Testzeitzone Europe/Vienna.
Das Paket enthält ausschließlich den neuen Provider und seine Begleitdateien.
Kein Weather-Patch und keine Tests gegen einen veränderten Weather-Kern.

## Erfolgreiche Prüfungen

741 Perl-Assertions:
- 59 allgemeine Provider-Tests.
- 58 Stations-/Warnungstests.
- 27 Höhen-/Auswahltests.
- 39 Tests getrennter Prognosegültigkeit.
- 34 Tests lokaler Zeit einschließlich DST.
- 51 Nowcast-Tests.
- 153 offizielle Symboltests.
- 50 Review-Regressionen aus 0.2.6.
- 9 Metadatenprüfungen einschließlich Maintainer 50watt.
- 7 Winddarstellungsprüfungen für Nordwind bei 0/360 Grad, Windstille,
  deutsche Himmelsrichtungen und fehlende Richtungs-/Geschwindigkeitswerte.
- 74 neue Solar-/Taupunkt-/Tagesmengentests: optionale Felder, gültige Nullwerte,
  unplausible/missing Werte, Kennzeichnung berechneter Taupunkte, Einheiten,
  lokale Zeitgrenzen, getrennte Regen-/Schneemengen, richtige Mitternachts-
  attribution, 23/25-Stunden-Tage, Teilabdeckung, fehlende Daten und eine
  separate Tageszusammenfassung.
- Je 90 Integrationsprüfungen mit unverändertem aktuellem Weather-Kern und
  unveränderter monolithischer Weather-Referenz von 2022. Darin enthalten:
  tatsächliche Veröffentlichung aller neuen Felder über den Weather-Rückruf.

Ein Python-Installer-Testfall prüft mehrere Bedingungen:
Syntaxprüfung vor Installation, Check-only ohne Änderungen, bytegenaue
Sicherung beim Upgrade, installierte API identisch zur Quelldatei,
unveränderter Weather-Kern und idempotente Wiederholung.

Zusätzlich: perl -c und podchecker erfolgreich, Code mit Perl::Tidy formatiert.
Der frühere optionale Kernpatch-Testlauf wird nicht mehr mitgezählt.

## Live-Test der funktional unveränderten Version 0.2.7 am öffentlichen Beispielstandort

Wien/Hohe Warte, 48.2486/16.3564, Zielhöhe 198 m, automatische Stationswahl
11035 mit Distanz/Höhendifferenz 0. Sechs echte HTTPS-Abfragen über die reine
Testtransportbrücke; der Produktionsprovider bleibt nichtblockierend.

Ergebnisse:
- Beobachtung 18.10.2026 10:50:00 CEST, Temperatur 15,7 °C.
- Gemessener Taupunkt 10,3 °C, Globalstrahlung 279 W/m².
- Sonnenscheindauer der letzten zehn Minuten 0 s, Grenzen 10:40–10:50 CEST.
- Prognosemodell 18.10.2026 05:00:00 CEST, 55 Zukunftsstunden.
- Erster Stundenwert: Globalstrahlung 380,1 W/m², Sonnenscheindauer 3366,5 s,
  berechneter Taupunkt 9,0 °C.
- Heutige verfügbare Prognoseintervalle: Niederschlag 0 mm, flüssiger Regen
  0 mm, Sonnenscheindauer 25958,7 s. Abdeckung jeweils ausdrücklich partial.
- Separate Zusammenfassung: leicht bewölkt, null Niederschlags-/Schneefallstunden
  im verfügbaren Zeitraum; Mengen-Häufigkeitsschwelle 0,1 mm pro Stunde.
- Stations-, Prognose-, Warnungs- und Nowcaststatus jeweils ok.
- Warngebiet Wien-Döbling, null Warnungen. Nowcast elf Viertelstundenwerte;
  rainNextHour=no mit tatsächlichem Fenster 10:45–11:45 CEST.

Das sind punktuelle echte API-Ergebnisse. Positive Regen-/Schneefälle und
vollständige/fehlende Tageswerte werden mit reproduzierbaren Fixtures geprüft.
Ein trockener Live-Test bestätigt nicht jede Warnart im produktiven FHEM.

## Wiederholung

Linux/SSH – im entpackten Paketverzeichnis als eigener Arbeitsschritt:

~~~bash
TZ=Europe/Vienna python3 tests/run_all.py
~~~

Erwartet: 741 erfolgreiche Perl-Assertions und ein erfolgreicher Python-
Installer-Testfall. Es wird kein produktiver FHEM-Server verändert.

Linux/SSH – separater optionaler Live-Test:

~~~bash
python3 tests/live_smoke.py --altitude 198 --nowcast
~~~

Erwartet bei verfügbaren Quellen frische Stationswerte und separate gültige
Quellstatus. Die echten Wetterwerte ändern sich.

## Prüfgrenzen

Die Vertragstests laden unveränderte Weather-Quellen, simulieren aber FHEM-
Laufzeitdienste. Produktiver Neustart, grafische Anzeige, HomeMode-Texte,
private Automationen und Langzeitbetrieb sind vor Ort zu prüfen. 0.2.8 wurde
vom Nutzer produktiv betrieben; 0.2.9 korrigiert die Veröffentlichung von
`wind_condition`. Keine Kernänderung ausgeführt.
