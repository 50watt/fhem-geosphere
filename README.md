# GeoSphereAPI für FHEM Weather

Testversion 0.2.8 · Maintainer: **50watt**

GeoSphereAPI bringt österreichische Stationsmesswerte, Stundenprognosen und daraus
abgeleitete Tagesprognosen, einen 15-Minuten-Niederschlagsnowcast und standortbezogene
Wetterwarnungen in das FHEM-Weather-Modul. Ohne API-Schlüssel, mit automatischer
Stationswahl unter Berücksichtigung der Entfernung und Höhenlage sowie
nachvollziehbaren Angaben zu Datenalter und Gültigkeit.

## Über GeoSphere Austria

[GeoSphere Austria](https://www.geosphere.at/de/ueber-uns/portraet) ist der
österreichische nationale Dienst für Meteorologie, Klimatologie, Geologie und
Geophysik. Die Bundesanstalt ist eine
[Anstalt öffentlichen Rechts](https://geosphere.at/de/impressum).
Sie entstand 2023 aus dem Zusammenschluss der Zentralanstalt für Meteorologie
und Geodynamik (ZAMG) und der Geologischen Bundesanstalt (GBA).

Über den [GeoSphere Austria Data Hub](https://data.hub.geosphere.at/de/about)
werden offene Daten kostenfrei bereitgestellt. Diese FHEM-Anbindung nutzt
öffentlich zugängliche Schnittstellen ohne Benutzerkonto oder API-Schlüssel.
Die verwendeten Wetterdaten stehen unter CC BY 4.0; die jeweiligen
Quellen- und Lizenzangaben sind bei Weiterverwendung zu beachten.
GeoSphereAPI ist eine eigenständige FHEM-Anbindung von 50watt.

## Voraussetzungen

- FHEM mit dem standardmäßig mitgelieferten Weather-Modul.
- Internetzugang über HTTPS.
- Standortkoordinaten in Österreich, entweder in den globalen FHEM-Attributen
  `latitude`/`longitude` oder als `location=Breite,Länge` in der Definition.

## Installation und Updates

**FHEMWEB-Kommandozeile**, als eigenen Schritt ausführen:

```text
update all https://raw.githubusercontent.com/50watt/fhem-geosphere/main/controls_geosphere.txt
```

Erwartet: erfolgreicher Download von lib/FHEM/APIs/Weather/GeoSphereAPI.pm.
Bei Fehlern nicht mit dem Neustart fortfahren.

Erst nach erfolgreichem Update **FHEMWEB-Kommandozeile**, eigener Schritt:

```text
shutdown restart
```

Ein Weather-reload allein lädt einen bereits geladenen API-Provider nicht
zuverlässig neu. Direkt nach dem Neustart kann das Reading `apiVersion` noch die
alte Version anzeigen: FHEM stellt zunächst die gespeicherten Readings wieder her.
Erst bei einer Datenaktualisierung wird auch `apiVersion` neu geschrieben.
Bei einem bestehenden GeoSphere-Gerät daher die nächste Datenaktualisierung
abwarten und anschließend `apiVersion` prüfen: erwartet wird `0.2.8`.
Bei einer Erstinstallation anschließend das Weather-Device definieren.

## Definition

Weather-Device in der **FHEMWEB-Kommandozeile** definieren. Dieses Beispiel
nutzt die in FHEM global eingestellten Koordinaten; diese müssen zum gewünschten
österreichischen Standort passen:

```text
define wetter_geosphere Weather API=GeoSphereAPI interval=300 lang=de
```

Die API wählt automatisch eine geeignete GeoSphere-Wetterstation in der Nähe.
Dabei berücksichtigt sie die Entfernung, den Höhenunterschied zum Standort
und die Verfügbarkeit aktueller Messwerte. Die Standorthöhe kann über
`geoSphereAltitude` angegeben werden; am globalen Standort wird sonst das
globale Attribut `altitude` verwendet, sofern gesetzt. Ohne Höhenangabe erfolgt
die Bewertung nach Entfernung und verfügbaren Messwerten.

Alternativ lässt sich die Station in FHEMWEB über das Dropdown des Attributs
`geoSphereStation` manuell auswählen. Die Auswahlliste steht nach dem Laden
der Stationsmetadaten bereit.

Erwartet nach der ersten Datenaktualisierung: Stationsmesswerte und apiVersion=0.2.8.
Weitere Attribute, Prognosen, Warnungen, Gültigkeit
und bekannte Grenzen sind in [DOKUMENTATION.md](DOKUMENTATION.md) beschrieben.

## Rückmeldungen und Grenzen

Bitte im FHEM-Wetterforum unter Angabe von API-/FHEM-/Perl-Version, betroffenem
Reading und Fehlermeldung berichten. Private Koordinaten und vollständige
Konfigurationen sind nicht erforderlich.

Tagesprognosen werden aus verfügbaren Stundenwerten abgeleitet. `partial`
kennzeichnet einen unvollständigen Tag. Regenmengen sind keine
Niederschlagswahrscheinlichkeit. Gefühlte Temperatur und aktueller beobachteter
Wetterzustand werden nicht ergänzt. Vor Automationen den Status der jeweiligen
Datenquelle prüfen. Weitere Prüfgrenzen siehe [TESTERGEBNIS.md](TESTERGEBNIS.md).

Diese Testquelle ist keine Aufnahme in die reguläre FHEM-Distribution.
Code: GPL-2.0-or-later. Wetterdaten: GeoSphere Austria, CC BY 4.0.

KI-unterstützt entwickelt; Maintainer und Ansprechpartner: 50watt.
