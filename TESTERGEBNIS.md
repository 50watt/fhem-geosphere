# Testnachweis GeoSphereAPI 0.2.14

31.10.2026, Perl 5.38.2, Python 3.12.14, Testzeitzone Europe/Vienna.
Das Paket enthält ausschließlich den neuen Provider und seine Begleitdateien.
Kein Weather-Patch und keine Tests gegen einen veränderten Weather-Kern.

## Erfolgreiche Prüfungen

801 Perl-Assertions:

- 603 Prüfungen in elf Provider-Testsuiten. Darunter 27 Metadatenprüfungen
  für Versionsgleichheit, Maintainer, Lizenz, Repository-/Supportlinks,
  deutsche Beschreibung, Provider-Kennzeichnung und Laufzeitabhängigkeiten.
- Je 99 Vertragstests mit unverändertem aktuellem Weather-Referenzkern und
  unveränderter monolithischer Weather-Referenz von 2022. Geprüft werden
  die Veröffentlichung der Felder sowie abgefangene Konfigurationsfehler.
- Die Provider-Tests umfassen Stationswahl, Höhenlage, Prognosegültigkeit,
  lokale Zeit/DST, Nowcast, Symbole, Winddarstellung und Solar-/Tagesmengen.

Der Metadatenloader wird in `tests/metadata.t` simuliert. Die tatsächliche
Package-Anzeige im produktiven FHEM Installer ist noch vor Ort zu prüfen.

Ein Python-Installer-Testfall prüft mehrere Bedingungen:
Syntaxprüfung vor Installation, Check-only ohne Änderungen, bytegenaue
Sicherung beim Upgrade, installierte API identisch zur Quelldatei,
unveränderter Weather-Kern und idempotente Wiederholung.

Zusätzlich: perl -c und podchecker erfolgreich. Die Wetterverarbeitung wurde
bei diesem Metadatenupdate nicht geändert.
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

Die Provider-Syntaxprüfung und alle 81 allgemeinen Provider-Assertions liefen
erfolgreich. Darin enthalten sind die lokalisierte Nowcast-Überschrift, die
Begrenzung auf die angeforderte Balkenzahl, die Kennzeichnung des laufenden
Viertelstundenintervalls, sichtbare GeoSphere-Attribution und HTML-Escaping von
Fehlermeldungen sowie die UTF-8-Bytegrenze für FHEMWEB. Zusätzlich bestanden
jeweils 99 Vertragsprüfungen gegen den
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

Erwartet: 801 erfolgreiche Perl-Assertions und ein erfolgreicher Python-
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
Nowcast-HTML-Darstellung; 0.2.13 korrigiert deren UTF-8-Ausgabegrenze. 0.2.14 ergänzt ausschließlich
Metadaten und Versionsangaben. Keine
Kernänderung ausgeführt.
