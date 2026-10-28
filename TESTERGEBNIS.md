# Testnachweis GeoSphereAPI 0.2.12

28.10.2026, Perl 5.40.1, Python 3.13, Testzeitzone Europe/Vienna.
Das Paket enthält ausschließlich den neuen Provider und seine Begleitdateien.
Kein Weather-Patch und keine Tests gegen einen veränderten Weather-Kern.

## Erfolgreiche Prüfungen

780 Perl-Assertions:
- 80 allgemeine Provider-Tests, einschließlich abgefangener ungültiger
  Standort-, Options- und Timeout-Konfigurationen sowie der optionalen
  Nowcast-HTML-Darstellung, Balkenbegrenzung und HTML-Escaping.
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
- Je 99 Integrationsprüfungen mit unverändertem aktuellem Weather-Kern und
  unveränderter monolithischer Weather-Referenz von 2022. Darin enthalten:
  tatsächliche Veröffentlichung aller neuen Felder über den Weather-Rückruf
  sowie ungültiger Standort, ungültige Höhe und ungültige Stationswahl. Deren
  Fehler erscheinen als Readings, ohne aus `Weather Define` beziehungsweise
  der Aktualisierung zu entweichen.

Ein Python-Installer-Testfall prüft mehrere Bedingungen:
Syntaxprüfung vor Installation, Check-only ohne Änderungen, bytegenaue
Sicherung beim Upgrade, installierte API identisch zur Quelldatei,
unveränderter Weather-Kern und idempotente Wiederholung.

Zusätzlich: perl -c und podchecker erfolgreich, Code mit Perl::Tidy formatiert.
Der frühere optionale Kernpatch-Testlauf wird nicht mehr mitgezählt.

## Lokaler FHEM-Integrationstest 0.2.10

Am 22.10.2026 wurde der finale Provider zusätzlich in einem laufenden FHEM
mit unverändertem Weather v2.3.3 (FHEM fhem.pl 31759, Perl 5.40.1) getestet.
Die zuvor unter 0.2.9 reproduzierbare unvollständige Standortdefinition
`location=48.2213` beendete FHEM nicht mehr. `state`, `status` und `lastError`
enthielten stattdessen die Konfigurationsmeldung mit einem direkt verwendbaren
öffentlichen Beispielstandort. Die MainPID blieb unverändert.

Zusätzlich wurden `timeout:0` und ein nichtnumerisches
`geoSphereAltitude` abgefangen, ohne den FHEM-Prozess zu beenden. Nach der
Rückkehr zu einer gültigen Definition aktualisierte sich dasselbe Testdevice
ohne Neustart wieder erfolgreich: `status=ok`, leeres `lastError`,
`validity=up-to-date` und aktuelle Stationswerte von Wien/Hohe Warte.

## Lokale Prüfung 0.2.12

Die Provider-Syntaxprüfung und alle 80 allgemeinen Provider-Assertions liefen
erfolgreich. Darin enthalten sind die lokalisierte Nowcast-Überschrift, die
Begrenzung auf die angeforderte Balkenzahl, die Kennzeichnung des laufenden
Viertelstundenintervalls, sichtbare GeoSphere-Attribution und HTML-Escaping von
Fehlermeldungen. Zusätzlich bestanden jeweils 99 Vertragsprüfungen gegen den
unveränderten modularen Weather-Kern und die unveränderte monolithische
Weather-Referenz von 2022.

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

Erwartet: 780 erfolgreiche Perl-Assertions und ein erfolgreicher Python-
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
`wind_condition`; 0.2.10 fängt Konfigurationsfehler im Provider ab. 0.2.11
formatiert Stundenbeschriftungen kompakt; 0.2.12 ergänzt eine optionale
Nowcast-HTML-Darstellung. Keine Kernänderung ausgeführt.
