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

Danach **Linux/SSH**, Standardinstallation unter /opt/fhem:

```bash
sudo -u fhem perl -c /opt/fhem/lib/FHEM/APIs/Weather/GeoSphereAPI.pm
```

Erwartet: syntax OK. Erst danach **FHEMWEB-Kommandozeile**, eigener Schritt:

```text
shutdown restart
```

Ein Weather-reload allein lädt einen bereits geladenen API-Provider nicht
zuverlässig neu. Nach dem Neustart muss apiVersion den Wert 0.2.8 zeigen.

## Testgerät

In der **FHEMWEB-Kommandozeile** eine eigene Definition anlegen. Dieses Beispiel
nutzt die in FHEM global eingestellten Koordinaten; diese müssen zum gewünschten
österreichischen Standort passen:

```text
define wetter_geosphere_test Weather API=GeoSphereAPI interval=300 lang=de
```

Erwartet: Stationsmesswerte und apiVersion=0.2.8. Ein bestehendes Wettergerät
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
