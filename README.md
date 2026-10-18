# GeoSphereAPI für FHEM Weather

Testversion 0.2.8 · Maintainer: **50watt**

GeoSphere Austria: österreichische Stationsmesswerte, Stunden- und abgeleitete
Tagesprognosen, Viertelstunden-Niederschlagsnowcast und Wetterwarnungen.
Kein API-Schlüssel erforderlich. Keine Änderung am Weather-Modul nötig.

## Installation und Updates

Voraussetzung: eine funktionierende FHEM-Weather-Installation und Internetzugang
über HTTPS. Vor einem Upgrade eine Sicherung der bisherigen GeoSphereAPI.pm
anlegen. Die Updatequelle installiert ausschließlich die API-Datei.

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

Erwartet nach der ersten Datenaktualisierung: Stationsmesswerte und apiVersion=0.2.8. Ein bestehendes Weather-Device
kann parallel weiterlaufen. Weitere Attribute, Prognosen, Warnungen, Gültigkeit
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
