# FHEM-Anpassungen zu GeoSphereAPI 0.2.8

Dieses Release installiert ausschließlich GeoSphereAPI.pm. Es enthält keinen
Weather-Kernpatch und keinen Patch-Vorbereitungshelfer. Weather und HomeMode
werden über ihre vorhandenen Schnittstellen verwendet.

## Bestehende Installation

Vorhandene DEF, Stationsauswahl, Standort, Höhenangabe, Intervall und
forecastmaxage bleiben gültig. Die Zusatzparameter werden mit den bestehenden
Stations-/Modellabfragen angefordert. Keine zusätzlichen HTTP-Abfragen oder
Pflichtattribute und keine Datenbankmigration.

Nach Entpacken, getrennter Installer-Prüfung, Installation und kontrolliertem
Neustart apiVersion=0.2.8 kontrollieren. Jeder Schritt steht einzeln in README.md.

## Neue Readings

| Reading | Bedeutung |
| --- | --- |
| dewPoint | Gemessener Taupunkt TP in °C |
| globalRadiation | Stations-Globalstrahlung GLOW in W/m² |
| sunshineDuration_s | Gemessene Sonnenscheindauer SO der letzten zehn Minuten |
| hfcN_dewPoint | Aus Modelltemperatur/-feuchte berechneter, gekennzeichneter Taupunkt |
| hfcN_globalRadiation | ssrd-Strahlungsprognose in W/m² |
| hfcN_sunshineDuration_s | sund-Sonnenscheindauer einer Modellstunde |
| fcN_precipitation | Gesamtniederschlagssumme über verfügbare Modellintervalle des Tages |
| fcN_rainTotal_mm | Flüssige Regensumme derselben Intervalle |
| fcN_snowWaterEquivalent | Schneefallsumme als Wasseräquivalent |
| fcN_sunshineDuration_s | Sonnenscheindauer-Summe verfügbarer Modellintervalle |
| fcN_summaryCondition | Gesonderte, näherungsweise Tageszusammenfassung |

Tagesmengen sind Prognosewerte, keine aufsummierten Stationsmessungen.
precipitationCoverage, rainCoverage, snowCoverage und sunshineCoverage sind
jeweils complete, partial, unknown oder missing. Erst complete bezeichnet eine
vollständig vorhandene Tagessumme. unknown bedeutet, dass mindestens ein Wert
fehlt; die Summe bleibt dann leer. Zeitgrenzen und Samplezahlen immer beachten.
Die Zehn-Minuten-/Stunden-/Tagesspannen ergeben sich aus dem Readingpräfix und
den sunshinePeriodStart/End- bzw. precipitationPeriodStart/End-Readings.

## Logging und Events

Die bisherige Auswahl bleibt zweckmäßig. Nur falls abweichend, die gewünschte
Einzelzeile ausführen und das Ergebnis prüfen.

FHEMWEB-Kommandozeile:

~~~text
attr s.global.wetter.geosphere.weather DbLogInclude temperature,rain10min_mm,measurementTime,rainNextHour,nowcastReferenceTime
~~~

Erwartet: Es werden weiterhin nur diese fünf Readings für DbLog ausgewählt.

FHEMWEB-Kommandozeile – separater Schritt:

~~~text
attr s.global.wetter.geosphere.weather event-on-change-reading .*
~~~

Erwartet: Events nur bei Änderungen. Die neuen Zusatzfelder werden durch die
obige DbLogInclude-Liste nicht zusätzlich geloggt. Bereits migrierte historische
Daten und umgestellte Lüfter-/Tablet-/Plot-Verweise bleiben gültig.

## HomeMode und Automationen

homemode_geosphere.fhem enthält gezielte Beispielattribute. Keine Änderung am
HomeMode-Quellcode erforderlich. HomeWeatherDevice verweist auf das Weather-
Gerät. Andere externe Sensorübersteuerungen vor Ort prüfen.

fc1 bleibt heute, fc2 morgen. condition und icon bleiben die offiziellen
Symbole einer repräsentativen Stunde. summaryCondition ist bewusst zusätzlich
und als abgeleitet gekennzeichnet; bestehende HomeMode-Platzhalter werden nicht
ungeprüft umgedeutet. Tagesextrema betreffen weiterhin vorhandene Stundenwerte.

Vor Steuerbefehlen Quellstatus, numerische Werte, Datenalter und passende
Abdeckung prüfen. Ein UV-Index, eine gefühlte Temperatur, aktuelle SYNOP-
Wetterbeobachtungen und eine fertige PV-Ertragsprognose sind nicht integriert.
Der normale Standortwechsel erfolgt über die Gerätedefinition; die feste
newLocation-Providerliste des unveränderten Weather-Kerns bleibt bestehen.

## Veröffentlichung

Maintainer-Identität/Forumprofil vor SVN-Aufnahme ergänzen und die Provider-
Anbindung mit dem Weather-Maintainer abstimmen. Keine Veröffentlichung und kein
SVN-Commit wurden durch dieses Paket ausgeführt.
