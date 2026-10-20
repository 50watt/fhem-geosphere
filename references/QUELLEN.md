# Referenzquellen

Abgerufen am 17./18.10.2026. FHEM-Referenzdateien unverändert und unter ihrer bestehenden GPL-Lizenz.

- `59_Weather.pm`
  Quelle: https://raw.githubusercontent.com/fhem/Weather/dev/FHEM/59_Weather.pm
  SHA256: `dbf8df946117b6a76a121af0f3396c6181fb958197db4794ed997f6c37bac878`

- `CoreWeather.pm`
  Quelle (aktualisiert für 0.2.6): https://raw.githubusercontent.com/fhem/fhem-mirror/main/fhem/lib/FHEM/Core/Weather.pm
  SHA256: `77b27e2ffaf927917a00b2ff12f37e5c7ce56782b7bf2cc683fd279ef7fd75d0`

- `2022_Weather.pm`
  Quelle: https://raw.githubusercontent.com/fhem/Weather/3d4996777f7a1a410229789462ab26a91f26aa2a/FHEM/59_Weather.pm
  SHA256: `a584d9f0457255a97b015952f2a413ed3dfefd39bbf6808d74fbd2fd222ef8f3`

- `API.de.md`
  Quelle: https://raw.githubusercontent.com/fhem/Weather/dev/docs/API.de/README.md
  SHA256: `0445d80cd8b161bf6f2ea65809dc068662d4249d49ec8899bd5ae26ec7b3906f`


## Ergänzungen für 0.2.0

- Warn-API-Schema: https://openapi.hub.geosphere.at/warnapi/v1/openapi.json
- Stationsmetadaten: https://dataset.api.hub.geosphere.at/v1/station/current/tawes-v1-10min/metadata
- Öffentlicher Beispielstandort Wien/Hohe Warte: https://warnungen.zamg.at/wsapp/api/getWarningsForCoords?lat=48.2486&lon=16.3564&lang=de
- 0.2.1: internes Stations-Dropdown über FHEM setDevAttrList und .AttrList; Verhalten geprüft anhand https://raw.githubusercontent.com/fhem/fhem-mirror/master/fhem/fhem.pl und https://wiki.fhem.de/wiki/DevelopmentModuleAPI .
- Warnungs-Testbeispiel aus der offiziellen OpenAPI-Spezifikation. Datenlizenz GeoSphere Austria CC BY 4.0.
- Vollständige Dateiprüfsummen in SHA256SUMS.

## Official sy symbols (verified 2026-10-18 Europe/Vienna)

https://public.hub.geosphere.at/public/resources/misc/Hilfestellung_DE.pdf

Page 2 contains the sy 1–32 code table for NWP-v2. Retrieved directly over HTTPS
and extracted using pdftotext. The provider preserves these raw codes/names and
translates them to the closest pre-existing Weather icon code; the two code
spaces are not identical. Daily use is explicitly a representative-hour symbol.

## Precipitation semantics verified for 0.2.6

https://dataset.api.hub.geosphere.at/v1/timeseries/forecast/nwp-v2-1h-1km/metadata

The official metadata distinguishes tp (total liquid and solid precipitation),
rain (rainfall), and sf (snowfall), each for the last forecast interval and
expressed in kg m-2. Its frequency is 1H. The provider exposes interval boundaries
and converts water-equivalent area mass to mm. rain1h is sourced only from rain,
never from tp. NWP metadata snapshot: nwp-metadata-20261018.json.

Comparison sources retrieved 2026-10-18:
- https://github.com/fhem/fhem-mirror/blob/main/fhem/lib/FHEM/APIs/Weather/OpenWeatherMapAPI.pm
- https://github.com/fhem/fhem-mirror/blob/main/fhem/lib/FHEM/APIs/Weather/wundergroundAPI.pm
- https://github.com/fhem/fhem-mirror/blob/main/fhem/FHEM/Meta.pm
- https://forum.fhem.de/index.php?topic=18962.0

Release 0.2.9 contains no Weather patch or patch helper. References are not installed.

## Additional station and forecast parameters verified for 0.2.8

https://dataset.api.hub.geosphere.at/v1/station/current/tawes-v1-10min/metadata

Official station metadata: TP (measured dew point, °C), GLOW (global radiation,
W/m²), SO (sunshine duration, sec). The current Hohe Warte response confirmed
all three optional parameters. Snapshot: tawes-metadata-20261018.json.

Official NWP metadata lists ssrd (surface global radiation, W m-2) and sund
(sunshine duration in the last forecast interval, s). NWP frequency is 1H.
Hourly precipitation/sunshine accumulations end at their timestamp.

The forecast dew point is a documented calculation from temperature and RH,
not an extra GeoSphere parameter. Bolton/Magnus inversion over water uses
17.67 and 243.5 °C; RH=0 has no finite result and remains empty. Formula reference:
https://unidata.github.io/MetPy/latest/api/generated/metpy.calc.dewpoint.html

Daily amounts are local aggregations, not the separate official web daily
product. No undocumented website endpoint is scraped by this provider.
