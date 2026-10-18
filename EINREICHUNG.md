# Veröffentlichung und SVN-Einreichung

Stand 18.10.2026. Version 0.2.8 ist ein Beta-Reviewpaket für die neue
GeoSphere-API. Es werden keine Änderungen an bestehenden FHEM-Kernmodulen
eingereicht. Das Paket enthält keinen Weather-Patch.

Mit vorhandenem SVN-Zugang zuerst den Provider im Wetterforum vorstellen,
Betreuung/Support und MAINTAINER-Eintrag vereinbaren und die API-Anbindung
reviewen lassen. Neue eigene Dateien entsprechend der Abstimmung über SVN
einreichen. Commit-Kommentare auf Englisch. Der reine fhem-mirror ist kein
Ziel für Pull Requests.

- [Entwicklerhinweise](https://forum.fhem.de/index.php?topic=18962.0)
- [Wetterforum](https://forum.fhem.de/index.php?board=86.0)
- [MAINTAINER](https://github.com/fhem/fhem-mirror/blob/main/fhem/MAINTAINER.txt)

Die letzte geprüfte Liste nennt neubert für 59_Weather.pm und CoolTux für
OpenWeatherMapAPI. Aktuelle Zuordnung vor einer Einreichung nochmals prüfen.
Ein eigener Git-Account kann zur Entwicklung dienen, ist aber kein notwendiger
Umweg bei vorhandenem SVN-Zugang.

## Einzureichender Umfang

- lib/FHEM/APIs/Weather/GeoSphereAPI.pm, Dokumentation, Beispiel und Tests.
- Nichtblockierende Stations-, Modell-, Warnungs- und Nowcast-Abfragen.
- Höhengewichtete Stationswahl, offizielle sy-Symbole und lokale Zeitreadings.
- Gemessener Taupunkt, Globalstrahlung und Sonnenscheindauer.
- Strahlungs-/Sonnenscheinprognose und ausdrücklich berechneter Prognosetaupunkt.
- Tagesmengen mit korrektem Mitternachtsbezug, DST und getrennten Abdeckungen.
- Gesonderte abgeleitete Tageszusammenfassung; bestehendes Tagesicon bleibt
  repräsentative Stunde.
- GPL-2.0-or-later, GeoSphere-Daten CC BY 4.0, sichtbare Attribution.
- Metadaten und einheitlicher Coding-Stil, keine privaten Koordinaten/Schlüssel.

## Noch zu klären und bekannte Grenzen

Maintainer: **50watt**. Support über das FHEM-Wetterforum.
FHEM-Kompatibilitätsadapter für Attribute und überzählige Readings reviewen.

Die offenen Datenfeeds enthalten keinen eingebundenen aktuellen Wetterzustand,
UV-Index oder gefühlte Temperatur. Strahlungswerte sind keine fertige
PV-Ertragsprognose. Tagesextrema sind Stichprobenextrema. Kein separater
offizieller Mehrtages-/Tagesprodukt-Endpoint ist integriert.

Stationsfehler unterbrechen weiterhin die nachfolgende Abfragekette. Vollständig
unabhängige Quell-Timer fehlen. Tests mit simulierten FHEM-Diensten ersetzen
keinen Langzeitbetrieb. KI-unterstützte Entwicklung transparent benennen;
dauerhafte Wartung übernimmt die ausdrücklich verantwortliche Person.

GitHub dient als öffentliche Testquelle. Es erfolgten keine externe Kontaktaufnahme oder SVN-Commits.
