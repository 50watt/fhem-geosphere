# GeoSphereAPI für FHEM Weather

Testversion 0.2.12 · Maintainer: **50watt**

GeoSphereAPI bringt österreichische Stationsmesswerte, Stundenprognosen und daraus
abgeleitete Tagesprognosen, einen 15-Minuten-Niederschlagsnowcast und standortbezogene
Wetterwarnungen in das FHEM-Weather-Modul. Ohne API-Schlüssel, mit automatischer
Stationswahl unter Berücksichtigung der Entfernung und Höhenlage sowie
nachvollziehbaren Angaben zu Datenalter und Gültigkeit.

## Änderungen in 0.2.12

- Ergänzt `GeoSphereNowcastAsHtml` als optionale FHEMWEB-Darstellung der
  vorhandenen 15-Minuten-Niederschlagswerte. Die Funktion begrenzt sich
  automatisch auf `nowcastPoints`, kennzeichnet das laufende Intervall und
  zeigt Status, Gültigkeit sowie Referenzzeit.
- Dokumentiert kopierbare Weblinks für Stunden-, Tages- und Nowcast-Anzeige.
- Keine Änderung am Weather-Kern und keine automatische Device-Anlage.

## Änderungen in 0.2.11

- Zeigt Stundenprognosen in `WeatherAsHtmlH`, `WeatherAsHtmlV` und
  `WeatherAsHtmlD` kompakt als lokalisierten Wochentag mit Uhrzeit an,
  beispielsweise `Mi, 14:00`, statt als vollständiges Datum mit Sekunden
  und Zeitzone.
- Behält vollständige Zeitangaben in Mess-, Nowcast-, Warnungs- und
  Diagnosereadings bei.
- Die Sprache der Wochentagskürzel folgt der Laufzeit-Locale von FHEM
  (insbesondere `LC_TIME`); für deutsche Kürzel muss auf dem FHEM-Host eine
  deutsche Locale aktiv sein.
- Keine Änderung am Weather-Kern erforderlich.

## Änderungen in 0.2.10

- Fängt ungültige Standort-, Höhen-, Stations-, API-Options- und
  Timeout-Konfigurationen innerhalb des Providers ab. Ein Konfigurationsfehler
  beendet FHEM dadurch nicht mehr.
- Schreibt die konkrete Ursache unmittelbar in `state`, `status` und
  `lastError`, beispielsweise
  `configuration error: location must be latitude,longitude; for example
  location=48.2486,16.3564`. Die Beispielkoordinaten gehören zum öffentlichen
  GeoSphere-Standort Wien/Hohe Warte.
- Prüft korrigierbare Einstellungen bei den folgenden Aktualisierungen erneut,
  sodass das Device nach einer Korrektur ohne Neustart wieder anlaufen kann.
- Keine Änderung am Weather-Kern erforderlich.

## Änderungen in 0.2.9

- Verhindert leere `wind_condition`-Ereignisse für aktuelle Messwerte und
  Stundenprognosen. Damit wird auch die seit Langem bekannte Warnung beim
  Zerlegen leerer Weather-Ereignisse durch DbLog vermieden.
- Überlässt die normale Winddarstellung weiterhin dem FHEM-Weather-Kern.
  Für Nordwind mit 0 Grad, Windstille und fehlende Einzelwerte erzeugt der
  Provider eine vollständige und sicher zerlegbare Ersatzdarstellung.
- Keine Änderung am Weather-Kern und keine neue Konfiguration erforderlich.

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
abwarten und anschließend `apiVersion` prüfen: erwartet wird `0.2.12`.
Bei einer Erstinstallation anschließend das Weather-Device definieren.

## Definition

Alle folgenden Befehle werden in der **FHEMWEB-Kommandozeile** jeweils einzeln
ausgeführt. Von den drei Definitionsvarianten nur die zum eigenen Anwendungsfall
passende verwenden.

### Variante 1: globale FHEM-Koordinaten

Mit folgendem Befehl zuerst die Detailausgabe des globalen Devices anzeigen:

```text
list global
```

Unter `Attributes` müssen `latitude` und `longitude` vorhanden sein. `altitude`
ist optional, verbessert aber die automatische Stationswahl. Falls der globale
FHEM-Standort tatsächlich Wien/Hohe Warte ist, könnten die Attribute anhand
dieses öffentlichen Beispielstandorts so gesetzt werden:

```text
attr global latitude 48.2486
```

```text
attr global longitude 16.3564
```

```text
attr global altitude 198
```

Die globalen Standortattribute werden möglicherweise auch von anderen
FHEM-Modulen verwendet. Daher nur auf den tatsächlichen Standort der eigenen
Installation setzen und nicht ungeprüft die Beispielwerte übernehmen.

Definition mit globalem Standort und automatischer Stationswahl:

```text
define wetter_geosphere Weather API=GeoSphereAPI interval=300 lang=de
```

### Variante 2: Standort direkt im Weather-Device

Diese Variante lässt die globalen Attribute unverändert. Das Beispiel verwendet
ebenfalls den öffentlichen Standort Wien/Hohe Warte:

```text
define wetter_geosphere Weather API=GeoSphereAPI location=48.2486,16.3564 interval=300 lang=de
```

Breitengrad und Längengrad werden mit Dezimalpunkt, ohne Leerzeichen und in
dieser Reihenfolge angegeben. Für einen entfernten Standort kann dessen Höhe
am Device ergänzt werden:

```text
attr wetter_geosphere geoSphereAltitude 198
```

### Variante 3: feste Station und Nowcast

Dieses vollständige Beispiel verwendet die Station Wien/Hohe Warte mit der
Stationsnummer `11035` und aktiviert den optionalen Niederschlagsnowcast:

```text
define wetter_geosphere Weather API=GeoSphereAPI,station:11035,nowcast:1 location=48.2486,16.3564 interval=300 lang=de
```

Stunden-/Tagesprognosen und standortbezogene Warnungen werden anschließend über
die vorhandenen Weather-Attribute aktiviert:

```text
attr wetter_geosphere forecast hourly,daily
```

```text
attr wetter_geosphere forecastLimit 24
```

```text
attr wetter_geosphere alerts 1
```

### Erster Abruf und Kontrolle

Bei einer Neuanlage im bereits laufenden FHEM nach der gewählten Definition und
den gewünschten Attributen als eigenen Befehl den ersten Abruf starten:

```text
set wetter_geosphere update
```

Der unveränderte Weather-Kern startet nach `defmod` selbst einen Abruf. Direkt
nach einem neuen `define` bleibt das Device dagegen bis zum ersten Abruf auf
`Initialized`. GeoSphereAPI startet im Konstruktor bewusst keinen eigenen
parallelen Timer.

## Grafische Darstellung in FHEMWEB

Die Standardfunktionen des Weather-Moduls können Stunden- und Tagesprognosen
als Weblink darstellen. `wetter_geosphere` ist dabei durch den eigenen
Device-Namen zu ersetzen.

Zehn Stunden horizontal:

```text
define wl_geosphere_stunden weblink htmlCode { WeatherAsHtmlH("wetter_geosphere","h",10) }
```

Drei verfügbare Prognosetage horizontal:

```text
define wl_geosphere_tage weblink htmlCode { WeatherAsHtmlH("wetter_geosphere","d",3) }
```

Die tatsächlich verfügbare Tageszahl steht im Reading
`forecastDaysAvailable`. Die direkte horizontale Funktion wird empfohlen,
da `WeatherAsHtmlD` in aktuellen Weather-Versionen die Anzahl intern zweimal
aufbereitet und dadurch eine zusätzliche leere Spalte anzeigen kann.

Bei aktiviertem GeoSphere-Nowcast stellt die providerspezifische Hilfsfunktion
bis zu zwölf 15-Minuten-Intervalle als Regenbalken dar:

```text
define wl_geosphere_regen weblink htmlCode { GeoSphereNowcastAsHtml("wetter_geosphere",12) }
```

`rain15m_01_mm` ist das aktuell laufende Viertelstundenintervall und wird als
`aktuell` markiert. Die folgenden Balken sind die zukünftigen Intervalle.
Die Funktion verwendet höchstens die in `nowcastPoints` gemeldete Anzahl.
Ohne gültigen Nowcast zeigt sie statt leerer Balken den Status und gegebenenfalls
`nowcastLastError`.

Die API wählt automatisch eine geeignete GeoSphere-Wetterstation in der Nähe.
Dabei berücksichtigt sie die Entfernung, den Höhenunterschied zum Standort
und die Verfügbarkeit aktueller Messwerte. Die Standorthöhe kann über
`geoSphereAltitude` angegeben werden; am globalen Standort wird sonst das
globale Attribut `altitude` verwendet, sofern gesetzt. Ohne Höhenangabe erfolgt
die Bewertung nach Entfernung und verfügbaren Messwerten.

Alternativ lässt sich die Station in FHEMWEB über das Dropdown des Attributs
`geoSphereStation` manuell auswählen. Die Auswahlliste steht nach dem Laden
der Stationsmetadaten bereit.

Erwartet nach der ersten Datenaktualisierung: `status=ok`, Stationsmesswerte,
`apiVersion=0.2.12` und eine nachvollziehbare Standortquelle. Bei Variante 1
steht `locationSource=global`, bei Variante 2 und 3 `locationSource=device`.
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
