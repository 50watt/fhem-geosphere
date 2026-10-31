# GeoSphereAPI 0.2.14 für FHEM Weather

Beta-Provider für österreichische Stationsmesswerte, Stundenprognosen,
aggregierte Tagesprognosen, optionale Warnungen und 15-Minuten-Niederschlagsnowcast.
Code: GPL-2.0-or-later. Daten: GeoSphere Austria, CC BY 4.0.
Kein API-Schlüssel erforderlich. Maintainer: **50watt**.

## Funktionen

- Gemessener Taupunkt TP, Globalstrahlung GLOW und Sonnenscheindauer SO.
- Stundenprognosen für ssrd-Globalstrahlung und sund-Sonnenscheindauer.
- Aus Modelltemperatur/Feuchte berechneter Prognosetaupunkt mit expliziter Quelle.
- Tagesmengen aus verfügbaren vollständigen Stundenintervallen: Gesamtniederschlag,
  flüssiger Regen, Schneefall als Wasseräquivalent und Sonnenscheindauer.
- Für jede Tagesmenge wird getrennt angegeben, ob der ganze Tag erfasst ist
  und wie viele Stundenwerte vorliegen. Bei der Zeitumstellung werden Tage mit
  23 oder 25 Stunden berücksichtigt. Fehlende Werte sind keine Null.
- Separate summaryCondition für den verfügbaren Tageszeitraum. Die bestehenden
  offiziellen condition/icon bleiben auf die repräsentative Stunde bezogen.
- Anbindung über das vorhandene Weather-Modul.

Änderungen: [CHANGELOG.md](CHANGELOG.md). Tests: [TESTERGEBNIS.md](TESTERGEBNIS.md).

## Voraussetzungen und Dateien

FHEM Weather mit Namespace-API-Ladeschnittstelle unter
lib/FHEM/APIs/Weather/; Namespace- und ältere monolithische Weather-
Referenzkerne werden getestet. Perl ab 5.16 mit JSON::PP, POSIX, Time::Local,
Scalar::Util, Encode und Unicode::Normalize. FHEM stellt HttpUtils für
nichtblockierendes HTTP/TLS sowie FHEM::Meta bereit. Eigenständige
Syntax-/Parsertests brauchen keinen vollständigen FHEM-Server.
Python 3 wird nur für Installer und Testhilfen benötigt.

- lib/FHEM/APIs/Weather/GeoSphereAPI.pm: einzige regulär installierte Datei.
- beispiel.fhem: Beispiel ohne private Standortkoordinaten.
- homemode_geosphere.fhem: gezielte HomeMode-Attribute, kein Modulersatz.
- tests/: reproduzierbare Offline-Tests sowie optionaler echter Live-Abruf.
- references/: Prüfkopien und Quellen, keine Installationsdateien.

## Installation und Updates

Installation und Updates erfolgen über die FHEM-Updatequelle. Die Befehle
stehen in [README.md](README.md#installation-und-updates).
Nach dem Neustart zeigt `apiVersion` zunächst noch das gespeicherte Reading;
erst nach einer Datenaktualisierung ist die geladene API-Version sichtbar.

## Definition

Weather-Device in der **FHEMWEB-Kommandozeile** definieren:

~~~text
define wetter_geosphere Weather API=GeoSphereAPI interval=300 lang=de
~~~

Das Beispiel verwendet die globalen Standortkoordinaten. Für einen anderen
Standort wird zusätzlich `location=Breite,Länge` in der Definition angegeben.
Bei einer Neuanlage im bereits laufenden FHEM danach als separaten
FHEMWEB-Befehl `set wetter_geosphere update` ausführen. Der unveränderte
Weather-Kern startet nach `defmod` selbst einen Abruf, nach einem neuen
`define` jedoch nicht unmittelbar. Bis zum ersten Abruf ist `Initialized`
daher erwartbar.

### Herkunft der Standortdaten

GeoSphereAPI wertet die Koordinaten in dieser Reihenfolge aus:

1. `location=Breite,Länge` in der Definition des Weather-Devices;
2. die globalen FHEM-Attribute `latitude` und `longitude`, wenn beide gesetzt
   sind;
3. den bereits vom Weather-Kern aufgelösten Standort als
   Kompatibilitätsrückfall.

Das Reading `locationSource` zeigt die tatsächlich verwendete Quelle:

| `locationSource` | Bedeutung |
| --- | --- |
| `device` | `location=...` stammt aus der Definition des Weather-Devices. |
| `global` | Die globalen Attribute `latitude` und `longitude` werden verwendet. |
| `Weather resolved location` | Kompatibilitätsrückfall auf den vom Weather-Kern übergebenen Standort. |
| `newLocation` | Temporärer Laufzeitstandort; der unveränderte Weather-Kern bietet diesen Befehl für GeoSphereAPI derzeit nicht an. |

Die tatsächlich verwendeten Werte stehen in `lat` und `long`. Die Höhenquelle
ist getrennt davon in `locationAltitudeSource` dokumentiert: `device` bedeutet
Attribut `geoSphereAltitude`, `global` bedeutet globales Attribut `altitude`
bei identischen globalen Koordinaten und `missing` bedeutet, dass keine
Standorthöhe verwendet wird. `locationAltitude` enthält den zugehörigen Wert.

Ungültige Standort-, Höhen-, Stations-, API-Options- oder Timeout-Angaben
werden innerhalb des Providers abgefangen. FHEM bleibt aktiv; die Ursache
erscheint in `state`, `status` und `lastError`. Nach einer korrigierten
Definition beziehungsweise einem korrigierten Attribut wird die dynamische
Konfiguration beim nächsten Update erneut geprüft. Bei einer ungültigen
Standortangabe enthält die Meldung mit `location=48.2486,16.3564` ein direkt
verwendbares Beispiel des öffentlichen GeoSphere-Standorts Wien/Hohe Warte.

### Parameter der Definition

- **`<name>`**: frei wählbarer, eindeutiger FHEM-Devicename; im Beispiel
  `wetter_geosphere`.
- **`Weather`**: FHEM-Modultyp.
- **`API=GeoSphereAPI`**: wählt GeoSphere als Datenquelle. Dieser Parameter
  muss für die GeoSphere-Anbindung angegeben werden.
- **`location=Breite,Länge`**: geografische Koordinaten mit Dezimalpunkt,
  Breitengrad zuerst. Ohne Angabe werden die globalen Attribute
  `latitude` und `longitude` verwendet.
- **`interval=Sekunden`**: Aktualisierungsintervall des Weather-Devices.
  Standard des Weather-Moduls: `3600`; im Beispiel `300` (fünf Minuten).
  Das Intervall bestimmt die Aktualisierungsprüfung, nicht den Messtakt
  der Station. Die API berücksichtigt zusätzlich ihre Cachezeiten.
- **`lang=de|en`**: Sprache der von der API erzeugten Wettertexte.
  Ohne Angabe gilt das globale Attribut `language`, ersatzweise `de`.
  GeoSphereAPI unterstützt `de` und `en`.

### Optionen innerhalb von API=GeoSphereAPI

Optionen werden mit Kommas an den API-Namen angehängt. Jede Option verwendet
einen Doppelpunkt zwischen Name und Wert, beispielsweise
`API=GeoSphereAPI,station:auto,forecastmaxage:32400`.

- **`station:auto|Stationsnummer`**: automatische Stationswahl oder feste
  Stationsnummer. Standard: `auto`. Das Attribut `geoSphereStation` hat Vorrang.
- **`cachemaxage:Sekunden`**: Cachezeit für die Wiederverwendung bereits
  abgerufener Stationswerte. Standard: `600` (zehn Minuten).
  Veraltete Messwerte werden dadurch nicht gültig.
- **`forecastcache:Sekunden`**: Cachezeit des abgerufenen Prognosedatensatzes.
  Standard: `1800` (30 Minuten). Die Auswahl der zukünftigen Stunden und
  Tageswerte wird bei der Verarbeitung auf die aktuelle Zeit bezogen.
- **`timeout:Sekunden`**: Zeitlimit je HTTP-Anfrage.
  Standard: `20`; erlaubt sind `1` bis `120`.
- **`observationmaxage:Sekunden`**: höchstes zulässiges Alter einer
  Stationsmessung, gerechnet ab ihrer Messzeit.
  Standard: `1800` (30 Minuten).
- **`forecastmaxage:Sekunden`**: höchstes zulässiges Alter des Prognosemodells,
  gerechnet ab seiner Referenzzeit. Standard: `32400` (neun Stunden).
  Dies ist nicht die Länge des Prognosezeitraums.
- **`nowcast:0|1`**: schaltet den Viertelstunden-Niederschlagsnowcast aus
  oder ein. Standard: `0`. Das Attribut `geoSphereNowcast` hat Vorrang.

### GeoSphere-Attribute

Die Attribute werden am Weather-Device gesetzt und in FHEMWEB angeboten.

- **`geoSphereStation`**: `auto`, eine Stationsnummer oder ein Eintrag aus
  dem Stations-Dropdown. Die Liste wird nach dem Laden der Stationsmetadaten
  mit Stationsnamen, Nummern und Entfernungen gefüllt. Ohne Attribut gilt
  die API-Option `station`, ersatzweise `auto`.
- **`geoSphereAltitude`**: Geländehöhe des Standorts in Metern über dem
  Meeresspiegel, keine Stockwerks- oder Montagehöhe. Erlaubt: `-500` bis
  `9000`. Ohne Attribut wird das globale `altitude` nur bei übereinstimmenden
  Standortkoordinaten verwendet. Fehlt auch diese Höhe, erfolgt die
  Stationsbewertung ohne Höhenvergleich.
- **`geoSphereNowcast`**: `0` deaktiviert, `1` aktiviert den
  Viertelstunden-Niederschlagsnowcast. Ohne Attribut gilt die API-Option
  `nowcast`, ersatzweise `0`.

### Weather-Attribute

- **`forecast`**: `hourly`, `daily` oder `hourly,daily`.
  Aktiviert Stundenprognosen (`hfcN_...`), Tagesprognosen (`fcN_...`) oder
  beide. Ohne Attribut werden keine NWP-Prognosen abgefragt;
  `forecastStatus=disabled` ist dann beabsichtigt.
- **`forecastLimit`**: maximale Anzahl veröffentlichter Prognoseeinträge
  je Reihe. Standard: `5`; `0` bedeutet unbegrenzt.
  `24` ermöglicht bis zu 24 Stundenprognosen, erzeugt aber mehr Readings.
  Das Attribut verlängert nicht den von GeoSphere gelieferten Prognosezeitraum.
- **`alerts`**: `0` deaktiviert, `1` aktiviert standortbezogene
  Wetterwarnungen. Standard: `0`.
- **`disable`**: `1` deaktiviert den Wetterabruf, `0` lässt ihn zu.
  Ohne Attribut ist der Abruf aktiviert.

`beispiel.fhem` und `homemode_geosphere.fhem` enthalten weitere Beispiele.
Jede Befehlszeile in der FHEMWEB-Kommandozeile einzeln ausführen.

## Aktualisierung der Daten

| Datenquelle | Neue Daten bei GeoSphere | Zeitliche Auflösung |
| --- | --- | --- |
| [TAWES-Stationsmesswerte](https://data.hub.geosphere.at/de/dataset/tawes-v1-10min) | Alle zehn Minuten | Zehn Minuten |
| [INCA-Nowcast](https://data.hub.geosphere.at/en/dataset/nowcast-v1-15min-1km) | Alle 15 Minuten | Viertelstundenwerte, bis drei Stunden voraus |
| [NWP-Prognose](https://data.hub.geosphere.at/de/dataset/nwp-v2-1h-1km) | Neuer Modelllauf alle drei Stunden | Stundenwerte, bis 60 Stunden voraus |
| Abgeleitete Tagesprognose | Auf Basis desselben NWP-Datensatzes | Lokale Kalendertage |
| [Wetterwarnungen](https://data.hub.geosphere.at/de/dataset/warnungen-v1) | Variabel | Abhängig von der Warnsituation |

Mess- und Modellzeiten sind keine garantierten Veröffentlichungszeiten.
Die Bereitstellung kann später erfolgen. Das FHEM-Intervall und die API-Caches
bestimmen zusätzlich, wann neue Daten eingelesen werden.

Für die Aktualität die Readings `measurementTime`, `forecastReferenceTime`
und `nowcastReferenceTime` sowie den jeweiligen Gültigkeitsstatus prüfen.
Ein kürzeres Abrufintervall erzeugt keine zusätzlichen Messwerte oder Modellläufe.

## GeoSphere-Abrufgrenzen

Stand: 18.10.2026. Für die **Dataset-API** unter
`dataset.api.hub.geosphere.at` nennt GeoSphere folgende Grenzen:

- **5 HTTP-Anfragen pro Sekunde.**
- **240 HTTP-Anfragen pro Stunde.**
- **Kein gesondertes Tageslimit in der verlinkten Dokumentation angegeben.**
  240 Anfragen pro Stunde entsprechen rechnerisch 5.760 Anfragen in 24 Stunden.
  Das ist kein eigenständiges Tageskontingent; die Sekunden- und Stundengrenze
  gelten weiterhin.

Bei Überschreitung antwortet der Server mit **HTTP 429 – Too Many Requests**.
Die Antwortheader enthalten die verbleibenden Anfragen und die Zeit bis zum
Zurücksetzen des Limits, unter anderem `x-ratelimit-remaining-hour` und
`ratelimit-reset`.

### Bedeutung für FHEM

`interval=300` bedeutet zwölf Aktualisierungszyklen pro Stunde bzw. 288 pro
24 Stunden. Ein Zyklus ist nicht gleich einer HTTP-Anfrage: Stationswerte,
Prognosen, Nowcast und Metadaten können separate Anfragen auslösen.
Caches vermeiden einen Teil dieser Abrufe. Bei der automatischen Stationswahl
kommen Prüfungen mehrerer Stationskandidaten hinzu. Stunden- und Tagesprognose
nutzen denselben NWP-Datensatz.

Die Grenze ist kein eigenes Kontingent pro FHEM-Device. Weitere Devices,
HTTPMOD-Abfragen und andere Anwendungen sind bei der Abrufplanung mit zu
berücksichtigen. Kurze Intervalle und häufige manuelle Aktualisierungen
erzeugen nicht automatisch neuere Wetterdaten.

Die genannten Grenzen beziehen sich auf die Dataset-API für Messwerte,
Prognosen und Nowcast. Für die separate Warn-API unter
`openapi.hub.geosphere.at/warnapi/v1/` wird damit keine identische Grenze
zugesichert.

Quelle: [GeoSphere Dataset API – Request Limit](https://dataset.api.hub.geosphere.at/v1/docs/user-guide/request-limit.html).
Maßgeblich sind die jeweils aktuellen Angaben des Anbieters.

## Standort, Höhe und Stationswahl

geoSphereAltitude ist die örtliche Geländehöhe in Metern über Meeresspiegel,
keine Gebäude-/Stockwerkshöhe. Erlaubt -500 bis 9000 m.
Ohne eigenes Attribut wird global altitude nur übernommen, wenn der
Gerätestandort mit den globalen Koordinaten übereinstimmt.
Ein entferntes Gerät erbt nicht versehentlich die Höhe der Wohnung.

Automatische Bewertung:
Entfernung in km + absoluter Höhenunterschied in m / 20.
Ein Höhenfehler von 100 m entspricht somit fünf zusätzlichen Bewertungspunkten.
Das ist eine dokumentierte Heuristik, kein meteorologischer Qualitätsbeweis.
Bei bekannter Zielhöhe erhalten Stationen ohne Höhenmetadaten 50 Zusatzpunkte;
ohne Zielhöhe zählt nur Entfernung. Die acht bestbewerteten Kandidaten werden
auf frische Pflichtmesswerte TL/RF/FF/PRED geprüft. Die beste brauchbare
Station wird gewählt und gespeichert. Danach kein stilles Stationshopping;
für Neuwahl Auswahl/Höhe/Standort ändern oder ausdrücklich neu definieren.

Das Dropdown enthält Namen, ID und Entfernung und wird aus offiziellen
Metadaten aufgebaut. Manuelle ID-/Dropdownauswahl bleibt möglich.
stationSelectionMethod, stationSelectionScore, stationAltitudeDifference_m,
stationDistanceKm und locationAltitudeSource machen die Wahl nachvollziehbar.

Metadaten-Cache 24 Stunden, Stationsmesswerte lokal bis cachemaxage.
Intervall 300 bedeutet Abrufprüfung alle fünf Minuten, nicht neue Messungen
alle fünf Minuten: TAWES liefert typischerweise Zehn-Minuten-Messungen.
measurementTime und validity prüfen, nicht nur den FHEM-Reading-Zeitstempel.

## Prognosen und Wetterzustand

hfc1 ist der erste zukünftige Stundenzeitpunkt. Lokale Kalendertage bestimmen
fc1=heute, fc2=morgen. Fehlen heute alle Modellstunden, ist fc1_coverage=missing,
samples=0, Temperatur leer und condition=Unbekannt. Die Indexposition bleibt
korrekt; es wird keine Temperatur erfunden. forecastDaysAvailable zählt die
Kalenderslots einschließlich dieses ausdrücklich leeren Slots.

coverage=partial kennzeichnet nur teilweise abgedeckte Tage.
low_c/high_c und tempLow/tempHigh sind Minima/Maxima verfügbarer Stundenwerte,
keine garantierten meteorologischen Tagesextrema. periodStart, periodEnd,
samples und minMaxScope zeigen den Ausschnitt. DST-Tage mit 23/25 Stunden
werden berücksichtigt.

GeoSphere sy-Symbole 1–32 werden auf deutsche/englische Texte und vorhandene
FHEM Weather-Icons abgebildet. geoSphereSymbol und geoSphereSymbolName bleiben
erhalten. Ein fehlendes/unbekanntes Symbol nutzt eine explizit als ungefähr
gekennzeichnete Ableitung aus Bewölkung/Niederschlag.
Tageszustand und Tagesicon beschreiben die repräsentative vorhandene Stunde,
nicht den ganzen Tag. representativeTime und conditionSource weisen darauf hin.
cloudCover ist dagegen der Mittelwert der vorhandenen Tagesstunden.
Eine separate astronomische Tag-/Nacht-Iconumschaltung ist nicht implementiert.

Aktuelle Stationsdaten enthalten keinen beobachteten Wetterzustand. Deshalb
code=48, condition=Wetterzustand nicht beobachtet und keine vorgetäuschte
aktuelle Sonne/Wolke aus dem Prognosemodell. Gefühlte Temperatur bleibt leer.
Stations-Taupunkt und Strahlungs-/Sonnenscheinprognosen sind seit 0.2.7 vorhanden.
UV-Index, Sichtweite, Sonnenzeiten und fertige PV-Ertragsprognosen sind nicht
integriert. Die zusätzliche Strahlungsprognose allein ergibt noch keinen PV-Ertrag.

## Niederschlag: nicht alle Regenfelder bedeuten dasselbe

| Reading | Herkunft und Zeitraum |
| --- | --- |
| rain10min_mm | Stationsmessung, vergangene zehn Minuten, mm |
| hfcN_precipitation | tp: gesamter flüssiger/fester Niederschlag der Modellstunde, mm Wasseräquivalent |
| hfcN_rain1h | rain: nur flüssiger Regen derselben prognostizierten Modellstunde, mm |
| hfcN_snowWaterEquivalent | sf: Schneefall als Wasseräquivalent, keine Schneehöhe |
| rain15m_NN_mm | Nowcast-Niederschlagsmenge eines Viertelstundenintervalls |
| rainNextHour_mm | Summe aus vier Nowcast-Viertelstunden, einschließlich bereits laufender Viertelstunde |

hfcN_precipitationPeriodStart und precipitationPeriodEnd bezeichnen das
Intervall bis zum jeweiligen Stundenzeitstempel. precipitationUnit=mm.
Diese Grenzen gelten auch für rain1h und snowWaterEquivalent.
Kein Alias tp→rain1h: Schnee darf nicht als flüssiger Regen ausgegeben werden.
Fehlt rain, bleibt rain1h leer. Tägliche rain1h-Werte bleiben leer. rainTotal_mm ist die separate flüssige
Regensumme. precipitation, snowWaterEquivalent und sunshineDuration_s werden
seit 0.2.7 über die verfügbaren Stundenintervalle des lokalen Tages summiert.

Vor einer Umstellung bestehender Automationen prüfen: Messung oder Prognose?
Gesamtniederschlag oder nur Regen? Welche Zeitspanne und Einheit?
Ein aktuelles rain1h einer anderen API ist kein Stundenprognosewert.
Ein hfcN_rain1h lässt sich nur dann gezielt ersetzen, wenn Zeitraum und Bedeutung
passen. Es gibt keinen aus einer einzelnen Zehn-Minuten-Messung hochgerechneten
aktuellen Stundenregen und keine erfundene Regenwahrscheinlichkeit.

## Optionaler 15-Minuten-Nowcast

GeoSphere INCA nowcast-v1-15min-1km wird für Gerätekoordinaten abgefragt.
Raster ca. 1 km, Viertelstundenwerte, typischerweise drei Stunden Horizont.
rain15m_NN_periodStart und rain15m_NN_time sind die tatsächlichen Zeitgrenzen.
rainNextHour=yes bei mindestens einem positiven Wert, no bei vier bestätigten
Nullwerten, unknown bei Fehler/fehlenden/unbrauchbaren Daten.
rainNextHourFrom/To zeigen das Fenster: nicht exakt die gleitenden nächsten
60 Minuten ab dem aktuellen Abrufzeitpunkt.
nextRainPeriodStart/End zeigen einen nassen Modellabschnitt, keinen exakten
Regenbeginn am Haus. rr ist Niederschlag, einschließlich festen Anteilen.

Nowcast-Modellalter maximal 2700 Sekunden, Rohdaten-Cache maximal 900 Sekunden.
Die Intervalle werden bei Wetterupdates neu auf die aktuelle Zeit bezogen;
nowcastFetchedAt zeigt den echten Abruf und wird durch Cachebenutzung nicht
fälschlich erneuert. Fehler bestätigen niemals Trockenheit. Auslaufende
rain15m-Indizes werden entfernt. Status nowcastStatus/nowcastValidity beachten.

## Grafische Darstellung in FHEMWEB

Für die allgemeinen Weather-Prognosen werden die vorhandenen Funktionen des
Weather-Kerns verwendet:

```text
define wl_geosphere_stunden weblink htmlCode { WeatherAsHtmlH("wetter_geosphere","h",10) }
```

```text
define wl_geosphere_tage weblink htmlCode { WeatherAsHtmlH("wetter_geosphere","d",3) }
```

Die Anzahl der verfügbaren Tageswerte steht in `forecastDaysAvailable`.
`WeatherAsHtmlH` wird direkt aufgerufen, damit der aktuelle Weather-Kern die
Anzahl nicht über `WeatherAsHtmlD` zweimal aufbereitet.

GeoSphereAPI stellt für die providerspezifischen 15-Minuten-Werte zusätzlich
eine optionale HTML-Hilfsfunktion bereit:

```text
define wl_geosphere_regen weblink htmlCode { GeoSphereNowcastAsHtml("wetter_geosphere",12) }
```

Die Funktion:

- erzeugt höchstens die angeforderte Anzahl von Balken und niemals mehr als
  `nowcastPoints`;
- markiert `rain15m_01_mm` als aktuell laufendes Viertelstundenintervall;
- verwendet `rain15m_NN_time` für die Zeitbeschriftung;
- skaliert die Balken relativ zur größten dargestellten Intervallmenge;
- zeigt `nowcastStatus`, `nowcastLastError`, `nowcastValidity` und
  `nowcastReferenceTime` in geeigneter Form;
- benötigt kein DbLog und legt selbst kein Device an.

Die Hilfsfunktion liefert ihr Ergebnis als UTF-8-Bytefolge an FHEMWEB. Das ist
wichtig, weil der ältere Weather-HTML-Code seine Gradzeichen ebenfalls als
UTF-8-Bytes erzeugt. Eine Unicode-markierte Teilansicht könnte beim
Zusammenfügen sonst zu einer zweiten Codierung und damit zu `Â°` führen.
Die Prozess-Locale (`LANG`/`LC_TIME`) beeinflusst die Sprache von
Wochentagen, ist aber nicht die Ursache dieses Zeichensatzfehlers.

## Warnungen und Fehlerzustände

alerts 1 aktiviert koordinatenbezogene GeoSphere-Warnungen. Nicht die Station,
sondern der Gerätestandort bestimmt das Warngebiet.
Nur eine erfolgreiche leere Antwort bestätigt null Warnungen. Fehler lassen
warningsCount/warnCount unknown; zuletzt bekannte Warntexte können erhalten
bleiben, sind bei Fehlerstatus aber keine bestätigte aktuelle Lage.
Warnstufe, Typ, Beginn/Ende, aktive/kommende Phase und Gebiet werden geprüft.
Abruf-Cache 300 s, maximale weiterverwendbare Warnungsdaten 900 s.

status/validity betreffen vor allem Stationsmesswerte;
forecastStatus/forecastValidity, nowcastStatus/nowcastValidity und
warningsStatus/warningsValidity die jeweiligen Datenquellen.
Forecastfehler blockieren frische Messwerte und nachfolgende Warnungen nicht.
Ein noch brauchbares gecachtes Modell kann bei fehlgeschlagener Modellauffrischung
weiterhin ok sein; forecastLastError nennt den fehlgeschlagenen Refresh.
Abgelaufene Modelle sind nie deswegen ok, weil die Station ebenfalls ausfällt.

Die Abfragekette bleibt sequentiell: Metadaten/Stationswahl → Station → NWP
(wenn ausgewählt) → Warnungen → Nowcast. Scheitert bereits die Station,
werden Warnungen/Nowcast in diesem Zyklus nicht separat neu abgefragt und
ihre Gültigkeit wird unbekannt. Vollständig unabhängige Quell-Timer sind
nicht Bestandteil dieses Releases. Bei dauerhaft ausbleibender FHEM-Ausführung
kann kein Provider allein eine laufende Automation absichern.

Vor Steuerbefehlen Quelle=ok, plausible Readingwerte und Mess-/Modellalter
prüfen. Für Tagesprognosen außerdem coverage und numerische Temperaturen.
Leere Werte sind keine Null, unknown ist nicht no.

## Zeitangaben und Standortänderung

Sichtbare Zeitreadings verwenden die lokale Zeitzone des FHEM-Prozesses:
TT.MM.JJJJ HH:MM:SS CET/CEST bei Europe/Vienna. Numerische Epoch-Werte bleiben
erhalten. location legt keine eigene Zeitzone fest.

Beispiele für Logging, Eventkontrolle und HomeMode stehen in
`beispiel.fhem` und `homemode_geosphere.fhem`.
Historische Datenbankwerte werden nicht umformatiert. Die reguläre
Standortänderung erfolgt über die Gerätedefinition. Der unveränderte Weather-
Kern lässt GeoSphere nicht über seine feste newLocation-Providerliste zu.
Dieses Release enthält keine Kernänderung und benötigt für den normalen
Betrieb keine solche Änderung.

## Taupunkt, Strahlung und Sonnenschein

dewPoint ist der gemessene Stationsparameter TP in °C. globalRadiation
verwendet GLOW, Einheit W/m². sunshineDuration_s verwendet SO, Sekunden der
vorherigen zehn Minuten; sunshinePeriodStart/End zeigen die Zeitgrenzen.
Fehlende oder unplausible optionale Werte bleiben leer.

hfcN_globalRadiation verwendet ssrd in W/m². hfcN_sunshineDuration_s verwendet
sund, Sekunden der Modellstunde bis zum Zeitstempel. Einheiten bleiben erhalten:
W/m² ist eine Strahlungsleistung pro Fläche und kein Energie- oder PV-Ertrag.
Ohne nachgewiesenen zeitlichen Mittelungsbezug wird daraus keine Tagesenergie
berechnet. Tägliche globalRadiation/dewPoint gehören zur representativeTime.

hfcN_dewPoint wird mangels direktem NWP-Taupunktparameter aus 2t/2r berechnet:
alpha = ln(RH/100) + 17.67*T/(243.5+T), Td = 243.5*alpha/(17.67-alpha).
Das ist eine Bolton/Magnus-Näherung über Wasser. dewPointSource bezeichnet
sie ausdrücklich als calculated; bei RH=0/fehlender Feuchte bleibt sie leer.
Sie ist kein von GeoSphere gelieferter Taupunktwert und keine gefühlte Temperatur.

## Tagesmengen und Tageszusammenfassung

Ein stündlicher Mengenwert gilt für die Stunde vor seinem Zeitstempel.
Für einen lokalen Kalendertag werden ausschließlich vollständige Modellintervalle
innerhalb 00:00 bis zum nächsten 00:00 aufsummiert. Die bei Tagesbeginn endende
Stunde gehört zum Vortag; die bei Tagesende endende Stunde gehört zum betrachteten
Tag. Das berücksichtigt auch Tage mit 23 oder 25 Stunden.

precipitationCoverage, rainCoverage, snowCoverage und sunshineCoverage:
complete = ganzer Kalendertag vorhanden; partial = alle vorhandenen Werte sind
gültig, aber der Tag ist nur teilweise abgedeckt; unknown = mindestens ein Wert
fehlt/ist ungültig, daher leere Summe; missing = keine geeigneten Intervalle.
precipitationSamples, rainSamples, snowSamples und sunshineSamples zählen die
gültigen Werte. precipitationExpectedSamples gibt die örtliche Tageslänge an.
precipitationPeriodStart/End und sunshinePeriodStart/End zeigen den wirklichen
Ausschnitt. Ein einzelner Ausfall bei sund macht nicht die Regensumme ungültig.

Alle Tagesmengen bleiben Modellprognosen, einschließlich eventuell bereits
vergangener verfügbarer Modellintervalle. Sie sind keine gemessene Tagesbilanz.
Auch bei vollständigen Temperatur-Stichproben kann die Mengenabdeckung abweichen,
weil die nächste Mitternachtsstunde noch fehlen kann.

summaryCondition ergänzt eine näherungsweise Bewölkungsklasse aus vorhandenen
Stundenstichproben sowie precipitationHours/snowfallHours. Als nasse Stunde zählt
eine Intervallmenge ab 0.1 mm Wasseräquivalent. Bei fehlenden Mengen bleiben
die Häufigkeiten unbekannt. Diese eigene Zusammenfassung ist kein offizielles
GeoSphere-Ganztagessymbol; bestehende condition/code/icon bleiben unverändert.

## Schnittstelle, Stil und Wartung

Öffentliche Methoden: new, setLocation, setForecast, setAlerts, setFetchTime,
getFetchTime, getWeather, setRetrieveData. Daten werden über die vorhandene
Weather-Rückruffunktion veröffentlicht. HTTP ist im Produktionsprovider
nichtblockierend. UTF-8 wird genau einmal an der FHEM-Grenze kodiert.

Die nötigen FHEM-Erweiterungen für providerbezogene Attribute und Entfernen
überzähliger Readings bleiben ausdrücklich gekapselte Kompatibilitätsadapter,
weil Weather dafür noch keine vollständigen Provider-Hooks anbietet.
Es gibt keine direkte Änderung fremder Geräte und keine direkten Schreibzugriffe
auf den userattr-Hash. Die Runtime-Attributliste des eigenen Geräts wird über
setDevAttrList ergänzt; bestehende Weather-Attribute bleiben erhalten.

FHEM::Meta liest die eingebetteten META.json-Daten im normalen FHEM-Betrieb.
JSON::PP bleibt absichtlich die Kernmodul-Abhängigkeit statt eines mehrfachen
JSON-Backend-Fallbacks. .perltidyrc dokumentiert die Codeformatierung.
Maintainer: **50watt**. Support über das FHEM-Wetterforum.

## Winddarstellung

Bei vorhandener Windrichtung und positiver Windgeschwindigkeit erzeugt weiterhin
der unveränderte Weather-Kern das Reading `wind_condition`. GeoSphereAPI
veröffentlicht dafür keinen vorläufigen Leerwert mehr. Für 0 Grad Nordwind,
Windstille oder fehlende Einzelwerte liefert der Provider selbst eine vollständige
Darstellung wie `Wind: N 0 km/h` oder `Wind: - - km/h`. Dadurch entstehen keine
leeren `wind_condition`-Ereignisse für die historische DbLog-Auswertung.

## Tests

Siehe TESTERGEBNIS.md für ausgeführte Tests und bekannte Prüfgrenzen.
0.2.8 wurde produktiv betrieben; 0.2.9 korrigierte die robuste
Veröffentlichung von `wind_condition`. 0.2.10 fängt Konfigurationsfehler an
der Providergrenze ab. Keine dieser Versionen ändert den Weather-Kern.
Offline-Vertragstests verwenden echte Weather-Quellen mit simulierten
FHEM-Diensten; sie ersetzen keinen vollständigen produktiven FHEM/HomeMode-Test.

## Quellen und Lizenzen

- [TAWES](https://data.hub.geosphere.at/de/dataset/tawes-v1-10min)
- [NWP v2](https://data.hub.geosphere.at/de/dataset/nwp-v2-1h-1km)
- [NWP-Metadaten](https://dataset.api.hub.geosphere.at/v1/timeseries/forecast/nwp-v2-1h-1km/metadata)
- [INCA-Nowcast](https://data.hub.geosphere.at/en/dataset/nowcast-v1-15min-1km)
- [Warn-API](https://openapi.hub.geosphere.at/warnapi/v1/)
- [FHEM Weather](https://github.com/fhem/fhem-mirror/blob/main/fhem/lib/FHEM/Core/Weather.pm)
- Daten: GeoSphere Austria, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/);
  Attribution bei Veröffentlichung sichtbar erhalten.
- Aufbereitung: Einheitenumrechnung, lokale Kalendertage, Stationsbewertung,
  symbolische Zustandsabbildung, Warnungsaufbereitung, Nowcast-Intervallsummen.
- Programmcode GPL-2.0-or-later, siehe LICENSE. Prüfkopien behalten ihre
  eigenen Copyright- und Lizenzhinweise.


## Format der Stundenprognose

Stundenprognosen liefern in `day_of_week` beziehungsweise
`hfcN_day_of_week` einen kompakten lokalisierten Text wie `Mi, 14:00`.
Damit bleiben die Standardfunktionen `WeatherAsHtmlH`, `WeatherAsHtmlV`
und `WeatherAsHtmlD` übersichtlich. Das Wochentagskürzel folgt der
FHEM-Laufzeit-Locale (`LC_TIME`). Vollständige Zeitstempel bleiben in den
dafür vorgesehenen Mess-, Nowcast-, Warnungs- und Diagnosereadings erhalten.
